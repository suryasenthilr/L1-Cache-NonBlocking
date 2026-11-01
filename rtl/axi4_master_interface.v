// =============================================================================
// File: axi4_master_interface.v
// Module: axi4_master_interface
// Description: AMBA AXI4 Master Burst Controller for 256-bit Line Fills (Read)
//              and Writeback Evictions (Write).
// =============================================================================

`timescale 1ns / 1ps

module axi4_master_interface (
    input  wire         clk,
    input  wire         rst_n,

    // Line Fill Request (from MSHR)
    input  wire         read_req_valid,
    input  wire [1:0]   read_req_id,
    input  wire [31:0]  read_req_addr,
    output wire         read_req_ready,

    // Line Fill Response (to MSHR)
    output reg          fill_valid,
    output reg  [1:0]   fill_id,
    output reg  [255:0] fill_data,

    // Writeback Request (from Writeback Buffer)
    input  wire         wb_req_valid,
    input  wire [31:0]  wb_req_addr,
    input  wire [255:0] wb_req_data,
    output reg          wb_done,

    // AMBA AXI4 Read Channels
    output reg  [3:0]   m_axi_arid,
    output reg  [31:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,   // 8 beats = 8x4 = 32 bytes
    output reg  [2:0]   m_axi_arsize,  // 4 bytes per beat (32-bit data bus)
    output reg  [1:0]   m_axi_arburst, // INCR (01)
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,

    input  wire [3:0]   m_axi_rid,
    input  wire [31:0]  m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,

    // AMBA AXI4 Write Channels
    output reg  [3:0]   m_axi_awid,
    output reg  [31:0]  m_axi_awaddr,
    output reg  [7:0]   m_axi_awlen,   // 8 beats
    output reg  [2:0]   m_axi_awsize,
    output reg  [1:0]   m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,

    output reg  [31:0]  m_axi_wdata,
    output reg  [3:0]   m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,

    input  wire [3:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg          m_axi_bready
);

    // States for Read (Fill) Pipeline
    localparam R_IDLE  = 2'd0;
    localparam R_ADDR  = 2'd1;
    localparam R_DATA  = 2'd2;

    reg [1:0] r_state;
    reg [2:0] r_beat_cnt;
    reg [255:0] r_shift_reg;

    assign read_req_ready = (r_state == R_IDLE);
    assign m_axi_rready   = (r_state == R_DATA);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state       <= R_IDLE;
            m_axi_arvalid <= 1'b0;
            m_axi_arid    <= 4'd0;
            m_axi_araddr  <= 32'd0;
            m_axi_arlen   <= 8'd7;   // 8 beats
            m_axi_arsize  <= 3'b010; // 4 bytes
            m_axi_arburst <= 2'b01;  // INCR
            r_beat_cnt    <= 3'd0;
            r_shift_reg   <= 256'd0;
            fill_valid    <= 1'b0;
            fill_id       <= 2'd0;
            fill_data     <= 256'd0;
        end else begin
            fill_valid <= 1'b0;

            case (r_state)
                R_IDLE: begin
                    if (read_req_valid) begin
                        m_axi_arvalid <= 1'b1;
                        m_axi_arid    <= {2'b00, read_req_id};
                        m_axi_araddr  <= {read_req_addr[31:5], 5'b00000}; // 32-byte aligned
                        m_axi_arlen   <= 8'd7;
                        m_axi_arsize  <= 3'b010;
                        m_axi_arburst <= 2'b01;
                        r_state       <= R_ADDR;
                    end
                end

                R_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        r_beat_cnt    <= 3'd0;
                        r_state       <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (m_axi_rvalid) begin
                        case (r_beat_cnt)
                            3'd0: r_shift_reg[31:0]    <= m_axi_rdata;
                            3'd1: r_shift_reg[63:32]   <= m_axi_rdata;
                            3'd2: r_shift_reg[95:64]   <= m_axi_rdata;
                            3'd3: r_shift_reg[127:96]  <= m_axi_rdata;
                            3'd4: r_shift_reg[159:128] <= m_axi_rdata;
                            3'd5: r_shift_reg[191:160] <= m_axi_rdata;
                            3'd6: r_shift_reg[223:192] <= m_axi_rdata;
                            3'd7: r_shift_reg[255:224] <= m_axi_rdata;
                        endcase
                        r_beat_cnt <= r_beat_cnt + 3'd1;

                        if (m_axi_rlast || (r_beat_cnt == 3'd7)) begin
                            fill_valid <= 1'b1;
                            fill_id    <= m_axi_rid[1:0];
                            fill_data  <= {m_axi_rdata, r_shift_reg[223:0]};
                            r_state    <= R_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    // States for Write (Eviction) Pipeline
    localparam W_IDLE  = 2'd0;
    localparam W_ADDR  = 2'd1;
    localparam W_DATA  = 2'd2;
    localparam W_RESP  = 2'd3;

    reg [1:0]   w_state;
    reg [2:0]   w_beat_cnt;
    reg [255:0] w_latched_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state        <= W_IDLE;
            m_axi_awvalid  <= 1'b0;
            m_axi_awid     <= 4'd0;
            m_axi_awaddr   <= 32'd0;
            m_axi_awlen    <= 8'd7;
            m_axi_awsize   <= 3'b010;
            m_axi_awburst  <= 2'b01;
            m_axi_wvalid   <= 1'b0;
            m_axi_wdata    <= 32'd0;
            m_axi_wstrb    <= 4'b1111;
            m_axi_wlast    <= 1'b0;
            m_axi_bready   <= 1'b0;
            wb_done        <= 1'b0;
            w_beat_cnt     <= 3'd0;
            w_latched_data <= 256'd0;
        end else begin
            wb_done <= 1'b0;

            case (w_state)
                W_IDLE: begin
                    if (wb_req_valid) begin
                        m_axi_awvalid  <= 1'b1;
                        m_axi_awaddr   <= {wb_req_addr[31:5], 5'b00000};
                        m_axi_awlen    <= 8'd7;
                        m_axi_awsize   <= 3'b010;
                        m_axi_awburst  <= 2'b01;
                        w_latched_data <= wb_req_data;
                        w_state        <= W_ADDR;
                    end
                end

                W_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        m_axi_wdata   <= w_latched_data[31:0];
                        m_axi_wstrb   <= 4'b1111;
                        m_axi_wlast   <= 1'b0;
                        w_beat_cnt    <= 3'd0;
                        w_state       <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (m_axi_wready) begin
                        w_beat_cnt <= w_beat_cnt + 3'd1;
                        case (w_beat_cnt + 3'd1)
                            3'd1: m_axi_wdata <= w_latched_data[63:32];
                            3'd2: m_axi_wdata <= w_latched_data[95:64];
                            3'd3: m_axi_wdata <= w_latched_data[127:96];
                            3'd4: m_axi_wdata <= w_latched_data[159:128];
                            3'd5: m_axi_wdata <= w_latched_data[191:160];
                            3'd6: m_axi_wdata <= w_latched_data[223:192];
                            3'd7: begin
                                m_axi_wdata <= w_latched_data[255:224];
                                m_axi_wlast <= 1'b1;
                            end
                        endcase

                        if (w_beat_cnt == 3'd7) begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            w_state      <= W_RESP;
                        end
                    end
                end

                W_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        wb_done      <= 1'b1;
                        w_state      <= W_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
