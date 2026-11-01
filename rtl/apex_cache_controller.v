// =============================================================================
// File: apex_cache_controller.v
// Module: apex_cache_controller
// Description: Synthesizable ASIC/FPGA Controller for Apex-L1Cache (Excluding Data SRAM).
//              Integrates Tag Array, Tree-PLRU, 4-Entry MSHR, Writeback Buffer,
//              and AMBA AXI4 Master Burst Controller.
// =============================================================================

`timescale 1ns / 1ps

module apex_cache_controller #(
    parameter TAG_WIDTH       = 22,
    parameter SET_INDEX_WIDTH = 5,
    parameter NUM_SETS        = 32,
    parameter NUM_MSHR        = 4
)(
    input  wire         clk,
    input  wire         rst_n,

    // Core Request Interface
    input  wire         core_req_valid,
    output wire         core_req_ready,
    input  wire [31:0]  core_req_addr,
    input  wire         core_req_is_write,
    input  wire [31:0]  core_req_wdata,
    input  wire [3:0]   core_req_wstrb,
    input  wire [3:0]   core_req_id,

    output reg          core_resp_valid,
    output reg  [31:0]  core_resp_data,
    output reg  [3:0]   core_resp_id,

    // Interface to External Data SRAM Macro (Read & Write Ports)
    output wire         sram_ren,
    output wire [4:0]   sram_rindex,
    output wire [1:0]   sram_rway,
    output wire [2:0]   sram_roffset,
    input  wire [31:0]  sram_rword_data,
    input  wire [255:0] sram_rline_data,

    output reg          sram_word_wen,
    output reg  [4:0]   sram_word_windex,
    output reg  [1:0]   sram_word_wway,
    output reg  [2:0]   sram_word_woffset,
    output reg  [3:0]   sram_word_wstrb,
    output reg  [31:0]  sram_word_wdata,

    output reg          sram_line_wen,
    output reg  [4:0]   sram_line_windex,
    output reg  [1:0]   sram_line_wway,
    output reg  [255:0] sram_line_wdata,

    // AMBA AXI4 Master Memory Interface
    output wire [3:0]   m_axi_arid,
    output wire [31:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,

    input  wire [3:0]   m_axi_rid,
    input  wire [31:0]  m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    output wire [3:0]   m_axi_awid,
    output wire [31:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,

    output wire [31:0]  m_axi_wdata,
    output wire [3:0]   m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    input  wire [3:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready,

    // Performance Counters
    output reg  [31:0]  perf_hits,
    output reg  [31:0]  perf_misses,
    output reg  [31:0]  perf_hit_under_miss
);

    wire [TAG_WIDTH-1:0]       req_tag    = core_req_addr[31:10];
    wire [SET_INDEX_WIDTH-1:0] req_index  = core_req_addr[9:5];
    wire [2:0]                 req_offset = core_req_addr[4:2];

    wire                       tag_hit;
    wire [1:0]                 tag_hit_way;
    wire                       tag_hit_dirty;
    wire [TAG_WIDTH-1:0]       victim_tag;
    wire                       victim_dirty;
    wire                       victim_valid;
    wire [1:0]                 plru_victim_way;

    wire                       mshr_secondary_hit;
    wire [1:0]                 mshr_secondary_entry;
    wire                       mshr_full;
    wire [1:0]                 mshr_alloc_idx;
    wire                       mshr_axi_req_valid;
    wire [1:0]                 mshr_axi_req_entry;
    wire [31:0]                mshr_axi_req_addr;
    wire                       mshr_commit_valid;
    wire [SET_INDEX_WIDTH-1:0] mshr_commit_index;
    wire [1:0]                 mshr_commit_way;
    wire [TAG_WIDTH-1:0]       mshr_commit_tag;
    wire [255:0]               mshr_commit_data;
    wire [31:0]                mshr_core_data;
    wire [3:0]                 mshr_core_id;
    wire                       mshr_core_resp_valid;

    wire                       wb_buffer_busy;
    wire                       wb_axi_valid;
    wire [31:0]                wb_axi_addr;
    wire [255:0]               wb_axi_data;
    wire                       wb_axi_done;

    wire                       axi_fill_valid;
    wire [1:0]                 axi_fill_id;
    wire [255:0]               axi_fill_data;
    wire                       axi_read_ready;

    assign core_req_ready = !mshr_full && !mshr_commit_valid && !wb_buffer_busy;
    wire active_miss_in_flight = mshr_axi_req_valid || (perf_misses > perf_hits);

    assign sram_ren     = core_req_valid;
    assign sram_rindex  = req_index;
    assign sram_rway    = tag_hit ? tag_hit_way : plru_victim_way;
    assign sram_roffset = req_offset;

    // Tag Array
    reg         tag_wen;
    reg [4:0]   tag_windex;
    reg [1:0]   tag_wway;
    reg [21:0]  tag_wtag;
    reg         tag_wvalid;
    reg         tag_wdirty;

    tag_array #(
        .NUM_SETS(NUM_SETS),
        .TAG_WIDTH(TAG_WIDTH),
        .SET_INDEX_WIDTH(SET_INDEX_WIDTH)
    ) u_tags (
        .clk(clk),
        .rst_n(rst_n),
        .ren(core_req_valid),
        .rindex(req_index),
        .rtag(req_tag),
        .hit(tag_hit),
        .hit_way(tag_hit_way),
        .hit_dirty(tag_hit_dirty),
        .victim_tag(victim_tag),
        .victim_dirty(victim_dirty),
        .victim_valid(victim_valid),
        .wen(tag_wen),
        .windex(tag_windex),
        .wway(tag_wway),
        .wtag(tag_wtag),
        .wvalid(tag_wvalid),
        .wdirty(tag_wdirty),
        .victim_way_sel(plru_victim_way)
    );

    // Tree-PLRU
    reg       plru_update_en;
    reg [4:0] plru_update_set;
    reg [1:0] plru_access_way;

    plru_replacement #(
        .NUM_SETS(NUM_SETS),
        .SET_INDEX_WIDTH(SET_INDEX_WIDTH)
    ) u_plru (
        .clk(clk),
        .rst_n(rst_n),
        .query_set(req_index),
        .victim_way(plru_victim_way),
        .update_en(plru_update_en),
        .update_set(plru_update_set),
        .access_way(plru_access_way)
    );

    // MSHR
    reg mshr_alloc_en;
    reg mshr_merge_en;

    mshr_table #(
        .NUM_ENTRIES(NUM_MSHR),
        .TAG_WIDTH(TAG_WIDTH),
        .SET_INDEX_WIDTH(SET_INDEX_WIDTH)
    ) u_mshr (
        .clk(clk),
        .rst_n(rst_n),
        .check_en(core_req_valid && !tag_hit),
        .check_tag(req_tag),
        .check_index(req_index),
        .check_offset(req_offset),
        .secondary_hit(mshr_secondary_hit),
        .secondary_entry(mshr_secondary_entry),
        .alloc_en(mshr_alloc_en),
        .alloc_tag(req_tag),
        .alloc_index(req_index),
        .alloc_way(plru_victim_way),
        .alloc_offset(req_offset),
        .alloc_is_write(core_req_is_write),
        .alloc_wdata(core_req_wdata),
        .alloc_wstrb(core_req_wstrb),
        .alloc_id(core_req_id),
        .mshr_full(mshr_full),
        .alloc_idx(mshr_alloc_idx),
        .merge_en(mshr_merge_en),
        .merge_idx(mshr_secondary_entry),
        .merge_offset(req_offset),
        .axi_req_valid(mshr_axi_req_valid),
        .axi_req_entry(mshr_axi_req_entry),
        .axi_req_addr(mshr_axi_req_addr),
        .axi_req_grant(axi_read_ready),
        .fill_valid(axi_fill_valid),
        .fill_entry(axi_fill_id),
        .fill_line_data(axi_fill_data),
        .commit_valid(mshr_commit_valid),
        .commit_index(mshr_commit_index),
        .commit_way(mshr_commit_way),
        .commit_tag(mshr_commit_tag),
        .commit_data(mshr_commit_data),
        .resp_core_data(mshr_core_data),
        .resp_core_id(mshr_core_id),
        .resp_core_valid(mshr_core_resp_valid),
        .commit_ack(1'b1)
    );

    // Writeback Buffer
    reg wb_alloc_en;
    writeback_buffer u_wb_buf (
        .clk(clk),
        .rst_n(rst_n),
        .alloc_en(wb_alloc_en),
        .alloc_line_addr({victim_tag, req_index, 5'b00000}),
        .alloc_line_data(sram_rline_data),
        .buffer_busy(wb_buffer_busy),
        .axi_wb_valid(wb_axi_valid),
        .axi_wb_addr(wb_axi_addr),
        .axi_wb_data(wb_axi_data),
        .axi_wb_done(wb_axi_done)
    );

    // AXI4 Master
    axi4_master_interface u_axi_master (
        .clk(clk),
        .rst_n(rst_n),
        .read_req_valid(mshr_axi_req_valid),
        .read_req_id(mshr_axi_req_entry),
        .read_req_addr(mshr_axi_req_addr),
        .read_req_ready(axi_read_ready),
        .fill_valid(axi_fill_valid),
        .fill_id(axi_fill_id),
        .fill_data(axi_fill_data),
        .wb_req_valid(wb_axi_valid),
        .wb_req_addr(wb_axi_addr),
        .wb_req_data(wb_axi_data),
        .wb_done(wb_axi_done),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    // Control FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_resp_valid     <= 1'b0;
            core_resp_data      <= 32'd0;
            core_resp_id        <= 4'd0;
            perf_hits           <= 32'd0;
            perf_misses         <= 32'd0;
            perf_hit_under_miss <= 32'd0;
            tag_wen             <= 1'b0;
            sram_word_wen       <= 1'b0;
            sram_line_wen       <= 1'b0;
            plru_update_en      <= 1'b0;
            mshr_alloc_en       <= 1'b0;
            mshr_merge_en       <= 1'b0;
            wb_alloc_en         <= 1'b0;
        end else begin
            core_resp_valid <= 1'b0;
            tag_wen         <= 1'b0;
            sram_word_wen   <= 1'b0;
            sram_line_wen   <= 1'b0;
            plru_update_en  <= 1'b0;
            mshr_alloc_en   <= 1'b0;
            mshr_merge_en   <= 1'b0;
            wb_alloc_en     <= 1'b0;

            if (mshr_commit_valid) begin
                tag_wen          <= 1'b1;
                tag_windex       <= mshr_commit_index;
                tag_wway         <= mshr_commit_way;
                tag_wtag         <= mshr_commit_tag;
                tag_wvalid       <= 1'b1;
                tag_wdirty       <= 1'b0;

                sram_line_wen    <= 1'b1;
                sram_line_windex <= mshr_commit_index;
                sram_line_wway   <= mshr_commit_way;
                sram_line_wdata  <= mshr_commit_data;

                plru_update_en   <= 1'b1;
                plru_update_set  <= mshr_commit_index;
                plru_access_way  <= mshr_commit_way;

                if (mshr_core_resp_valid) begin
                    core_resp_valid <= 1'b1;
                    core_resp_data  <= mshr_core_data;
                    core_resp_id    <= mshr_core_id;
                end
            end else if (core_req_valid && core_req_ready) begin
                if (tag_hit) begin
                    perf_hits <= perf_hits + 32'd1;
                    if (active_miss_in_flight) begin
                        perf_hit_under_miss <= perf_hit_under_miss + 32'd1;
                    end

                    plru_update_en  <= 1'b1;
                    plru_update_set <= req_index;
                    plru_access_way <= tag_hit_way;

                    if (!core_req_is_write) begin
                        core_resp_valid <= 1'b1;
                        core_resp_data  <= sram_rword_data;
                        core_resp_id    <= core_req_id;
                    end else begin
                        sram_word_wen     <= 1'b1;
                        sram_word_windex  <= req_index;
                        sram_word_wway    <= tag_hit_way;
                        sram_word_woffset <= req_offset;
                        sram_word_wstrb   <= core_req_wstrb;
                        sram_word_wdata   <= core_req_wdata;

                        tag_wen           <= 1'b1;
                        tag_windex        <= req_index;
                        tag_wway          <= tag_hit_way;
                        tag_wtag          <= req_tag;
                        tag_wvalid        <= 1'b1;
                        tag_wdirty        <= 1'b1;
                    end
                end else begin
                    perf_misses <= perf_misses + 32'd1;

                    if (mshr_secondary_hit) begin
                        mshr_merge_en <= 1'b1;
                    end else if (!mshr_full) begin
                        if (victim_valid && victim_dirty && !wb_buffer_busy) begin
                            wb_alloc_en <= 1'b1;
                        end
                        mshr_alloc_en <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
