// =============================================================================
// File: data_array.v
// Module: data_array
// Description: 4-Way 32-Byte Cache Line Data Array with Byte-Enable Masking
//              (32 Sets x 4 Ways x 8 Words of 32 bits = 4KB).
// =============================================================================

`timescale 1ns / 1ps

module data_array #(
    parameter NUM_SETS = 32,
    parameter SET_INDEX_WIDTH = 5
)(
    input  wire                       clk,

    // Read Port
    input  wire                       ren,
    input  wire [SET_INDEX_WIDTH-1:0] rindex,
    input  wire [1:0]                 rway,
    input  wire [2:0]                 rword_offset,
    output wire [31:0]                rword_data,
    output wire [255:0]               rline_data,

    // Word Write Port (Core Store Hit)
    input  wire                       word_wen,
    input  wire [SET_INDEX_WIDTH-1:0] word_windex,
    input  wire [1:0]                 word_wway,
    input  wire [2:0]                 word_woffset,
    input  wire [3:0]                 word_wstrb,
    input  wire [31:0]                word_wdata,

    // Full Line Refill Port (Memory Line Fill)
    input  wire                       line_wen,
    input  wire [SET_INDEX_WIDTH-1:0] line_windex,
    input  wire [1:0]                 line_wway,
    input  wire [255:0]               line_wdata
);

    // 32 sets x 4 ways x 8 words x 32 bits
    reg [31:0] mem [NUM_SETS-1:0][3:0][7:0];

    integer s, w, wd;

    // Full Line Readout
    assign rline_data = {
        mem[rindex][rway][7],
        mem[rindex][rway][6],
        mem[rindex][rway][5],
        mem[rindex][rway][4],
        mem[rindex][rway][3],
        mem[rindex][rway][2],
        mem[rindex][rway][1],
        mem[rindex][rway][0]
    };

    // Single Word Readout for CPU Load Hit
    assign rword_data = mem[rindex][rway][rword_offset];

    // Synchronous Writes
    always @(posedge clk) begin
        // Full Line Refill from AXI Line Fill
        if (line_wen) begin
            mem[line_windex][line_wway][0] <= line_wdata[31:0];
            mem[line_windex][line_wway][1] <= line_wdata[63:32];
            mem[line_windex][line_wway][2] <= line_wdata[95:64];
            mem[line_windex][line_wway][3] <= line_wdata[127:96];
            mem[line_windex][line_wway][4] <= line_wdata[159:128];
            mem[line_windex][line_wway][5] <= line_wdata[191:160];
            mem[line_windex][line_wway][6] <= line_wdata[223:192];
            mem[line_windex][line_wway][7] <= line_wdata[255:224];
        end
        // Byte-masked Word Write on Store Hit
        else if (word_wen) begin
            if (word_wstrb[0]) mem[word_windex][word_wway][word_woffset][7:0]   <= word_wdata[7:0];
            if (word_wstrb[1]) mem[word_windex][word_wway][word_woffset][15:8]  <= word_wdata[15:8];
            if (word_wstrb[2]) mem[word_windex][word_wway][word_woffset][23:16] <= word_wdata[23:16];
            if (word_wstrb[3]) mem[word_windex][word_wway][word_woffset][31:24] <= word_wdata[31:24];
        end
    end

endmodule
