// =============================================================================
// File: writeback_buffer.v
// Module: writeback_buffer
// Description: Non-Blocking Dirty Victim Eviction Buffer.
//              Holds dirty cache lines awaiting background writeback to main memory.
// =============================================================================

`timescale 1ns / 1ps

module writeback_buffer (
    input  wire         clk,
    input  wire         rst_n,

    // Allocate Victim Line Port (From Cache Core on Dirty Miss)
    input  wire         alloc_en,
    input  wire [31:0]  alloc_line_addr,
    input  wire [255:0] alloc_line_data,
    output wire         buffer_busy,

    // AXI Write Burst Interface
    output reg          axi_wb_valid,
    output reg  [31:0]  axi_wb_addr,
    output reg  [255:0] axi_wb_data,
    input  wire         axi_wb_done
);

    reg         busy;
    reg [31:0]  addr_reg;
    reg [255:0] data_reg;

    assign buffer_busy = busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy         <= 1'b0;
            addr_reg     <= 32'd0;
            data_reg     <= 256'd0;
            axi_wb_valid <= 1'b0;
            axi_wb_addr  <= 32'd0;
            axi_wb_data  <= 256'd0;
        end else begin
            if (alloc_en && !busy) begin
                busy         <= 1'b1;
                addr_reg     <= alloc_line_addr;
                data_reg     <= alloc_line_data;
                axi_wb_valid <= 1'b1;
                axi_wb_addr  <= alloc_line_addr;
                axi_wb_data  <= alloc_line_data;
            end else if (busy && axi_wb_done) begin
                busy         <= 1'b0;
                axi_wb_valid <= 1'b0;
            end
        end
    end

endmodule
