// =============================================================================
// File: mshr_table.v
// Module: mshr_table
// Description: 4-Entry Non-Blocking Miss Status Holding Register (MSHR) Table.
//              Enables Hit-Under-Miss and Miss-Under-Miss with Secondary Merging.
// =============================================================================

`timescale 1ns / 1ps

module mshr_table #(
    parameter NUM_ENTRIES     = 4,
    parameter TAG_WIDTH       = 22,
    parameter SET_INDEX_WIDTH = 5
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // Core Request Inquiry (Lookup for Secondary Miss)
    input  wire                       check_en,
    input  wire [TAG_WIDTH-1:0]       check_tag,
    input  wire [SET_INDEX_WIDTH-1:0] check_index,
    input  wire [2:0]                 check_offset,
    output wire                       secondary_hit,
    output wire [$clog2(NUM_ENTRIES)-1:0] secondary_entry,

    // Allocation Port (New Primary Miss)
    input  wire                       alloc_en,
    input  wire [TAG_WIDTH-1:0]       alloc_tag,
    input  wire [SET_INDEX_WIDTH-1:0] alloc_index,
    input  wire [1:0]                 alloc_way,
    input  wire [2:0]                 alloc_offset,
    input  wire                       alloc_is_write,
    input  wire [31:0]                alloc_wdata,
    input  wire [3:0]                 alloc_wstrb,
    input  wire [3:0]                 alloc_id,
    output wire                       mshr_full,
    output wire [$clog2(NUM_ENTRIES)-1:0] alloc_idx,

    // Secondary Miss Merge Port
    input  wire                       merge_en,
    input  wire [$clog2(NUM_ENTRIES)-1:0] merge_idx,
    input  wire [2:0]                 merge_offset,

    // AXI Issue Interface (Find oldest entry waiting for memory burst)
    output reg                        axi_req_valid,
    output reg  [$clog2(NUM_ENTRIES)-1:0] axi_req_entry,
    output reg  [31:0]                axi_req_addr,
    input  wire                       axi_req_grant,

    // AXI Line Fill Return Port
    input  wire                       fill_valid,
    input  wire [$clog2(NUM_ENTRIES)-1:0] fill_entry,
    input  wire [255:0]               fill_line_data,

    // Cache Array Commit & Core Response Port
    output reg                        commit_valid,
    output reg  [SET_INDEX_WIDTH-1:0] commit_index,
    output reg  [1:0]                 commit_way,
    output reg  [TAG_WIDTH-1:0]       commit_tag,
    output reg  [255:0]               commit_data,
    output reg  [31:0]                resp_core_data,
    output reg  [3:0]                 resp_core_id,
    output reg                        resp_core_valid,
    input  wire                       commit_ack
);

    localparam S_IDLE     = 2'b00;
    localparam S_WAIT_MEM = 2'b01;
    localparam S_COMMIT   = 2'b10;

    reg [1:0]                 state       [NUM_ENTRIES-1:0];
    reg [TAG_WIDTH-1:0]       tags        [NUM_ENTRIES-1:0];
    reg [SET_INDEX_WIDTH-1:0] indices     [NUM_ENTRIES-1:0];
    reg [1:0]                 ways        [NUM_ENTRIES-1:0];
    reg [2:0]                 offsets     [NUM_ENTRIES-1:0];
    reg                       is_writes   [NUM_ENTRIES-1:0];
    reg [31:0]                wdatas      [NUM_ENTRIES-1:0];
    reg [3:0]                 wstrbs      [NUM_ENTRIES-1:0];
    reg [3:0]                 req_ids     [NUM_ENTRIES-1:0];
    reg [7:0]                 sec_masks   [NUM_ENTRIES-1:0]; // tracks secondary words
    reg [255:0]               line_buffers[NUM_ENTRIES-1:0];

    integer i;

    // Check for Secondary Miss (Match on Tag + Index)
    wire [NUM_ENTRIES-1:0] match_vec;
    generate
        genvar g;
        for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : gen_match
            assign match_vec[g] = (state[g] != S_IDLE) && 
                                  (tags[g] == check_tag) && 
                                  (indices[g] == check_index);
        end
    endgenerate

    assign secondary_hit = check_en && (|match_vec);
    assign secondary_entry = match_vec[0] ? 2'd0 :
                             match_vec[1] ? 2'd1 :
                             match_vec[2] ? 2'd2 : 2'd3;

    // Find Free Entry for Allocation
    wire [NUM_ENTRIES-1:0] free_vec;
    for (g = 0; g < NUM_ENTRIES; g = g + 1) begin : gen_free
        assign free_vec[g] = (state[g] == S_IDLE);
    end

    assign mshr_full = !(|free_vec);
    assign alloc_idx = free_vec[0] ? 2'd0 :
                       free_vec[1] ? 2'd1 :
                       free_vec[2] ? 2'd2 : 2'd3;

    // AXI Issue Arbitration (Priority to lowest index waiting for memory)
    always @(*) begin
        axi_req_valid = 1'b0;
        axi_req_entry = 2'd0;
        axi_req_addr  = 32'd0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!axi_req_valid && (state[i] == S_WAIT_MEM)) begin
                axi_req_valid = 1'b1;
                axi_req_entry = i[1:0];
                axi_req_addr  = {tags[i], indices[i], 5'b00000};
            end
        end
    end

    // Commit Arbitration (Find entry in S_COMMIT)
    reg [$clog2(NUM_ENTRIES)-1:0] active_commit_idx;
    reg commit_found;
    always @(*) begin
        commit_found      = 1'b0;
        active_commit_idx = 2'd0;
        for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
            if (!commit_found && (state[i] == S_COMMIT)) begin
                commit_found      = 1'b1;
                active_commit_idx = i[1:0];
            end
        end
    end

    // Line Extraction for Core Response
    wire [31:0] extracted_core_word;
    wire [2:0]  sel_offset = offsets[active_commit_idx];
    wire [255:0] active_line = line_buffers[active_commit_idx];

    assign extracted_core_word = (sel_offset == 3'd0) ? active_line[31:0]    :
                                 (sel_offset == 3'd1) ? active_line[63:32]   :
                                 (sel_offset == 3'd2) ? active_line[95:64]   :
                                 (sel_offset == 3'd3) ? active_line[127:96]  :
                                 (sel_offset == 3'd4) ? active_line[159:128] :
                                 (sel_offset == 3'd5) ? active_line[191:160] :
                                 (sel_offset == 3'd6) ? active_line[223:192] : active_line[255:224];

    // State Transitions and Buffer Updates
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_ENTRIES; i = i + 1) begin
                state[i]        <= S_IDLE;
                tags[i]         <= {TAG_WIDTH{1'b0}};
                indices[i]      <= {SET_INDEX_WIDTH{1'b0}};
                ways[i]         <= 2'd0;
                offsets[i]      <= 3'd0;
                is_writes[i]    <= 1'b0;
                wdatas[i]       <= 32'd0;
                wstrbs[i]       <= 4'd0;
                req_ids[i]      <= 4'd0;
                sec_masks[i]    <= 8'd0;
                line_buffers[i] <= 256'd0;
            end
            commit_valid     <= 1'b0;
            commit_index     <= {SET_INDEX_WIDTH{1'b0}};
            commit_way       <= 2'd0;
            commit_tag       <= {TAG_WIDTH{1'b0}};
            commit_data      <= 256'd0;
            resp_core_data   <= 32'd0;
            resp_core_id     <= 4'd0;
            resp_core_valid  <= 1'b0;
        end else begin
            // 1. Primary Allocation
            if (alloc_en && !mshr_full) begin
                state[alloc_idx]        <= S_WAIT_MEM;
                tags[alloc_idx]         <= alloc_tag;
                indices[alloc_idx]      <= alloc_index;
                ways[alloc_idx]         <= alloc_way;
                offsets[alloc_idx]      <= alloc_offset;
                is_writes[alloc_idx]    <= alloc_is_write;
                wdatas[alloc_idx]       <= alloc_wdata;
                wstrbs[alloc_idx]       <= alloc_wstrb;
                req_ids[alloc_idx]      <= alloc_id;
                sec_masks[alloc_idx]    <= (8'b1 << alloc_offset);
            end

            // 2. Secondary Merge
            if (merge_en) begin
                sec_masks[merge_idx] <= sec_masks[merge_idx] | (8'b1 << merge_offset);
            end

            // 3. AXI Fill Reception
            if (fill_valid && (state[fill_entry] == S_WAIT_MEM)) begin
                line_buffers[fill_entry] <= fill_line_data;
                state[fill_entry]        <= S_COMMIT;
            end

            // 4. Commit to SRAM & Core Response
            if (commit_found) begin
                commit_valid             <= 1'b1;
                commit_index             <= indices[active_commit_idx];
                commit_way               <= ways[active_commit_idx];
                commit_tag               <= tags[active_commit_idx];
                commit_data              <= line_buffers[active_commit_idx];
                resp_core_data           <= extracted_core_word;
                resp_core_id             <= req_ids[active_commit_idx];
                resp_core_valid          <= !is_writes[active_commit_idx]; // respond to loads
                state[active_commit_idx] <= S_IDLE;
            end else begin
                commit_valid             <= 1'b0;
                resp_core_valid          <= 1'b0;
            end
        end
    end

endmodule
