// =============================================================================
// File: tag_array.v
// Module: tag_array
// Description: 4-Way Set-Associative Tag Array with Integrated Valid and Dirty Bits
//              for 4KB L1 Data Cache (32 Sets x 4 Ways).
// =============================================================================

`timescale 1ns / 1ps

module tag_array #(
    parameter NUM_SETS = 32,
    parameter TAG_WIDTH = 22,
    parameter SET_INDEX_WIDTH = 5
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // Read Port (Pipelined or Single-Cycle)
    input  wire                       ren,
    input  wire [SET_INDEX_WIDTH-1:0] rindex,
    input  wire [TAG_WIDTH-1:0]       rtag,

    output wire                       hit,
    output wire [1:0]                 hit_way,
    output wire                       hit_dirty,
    output wire [TAG_WIDTH-1:0]       victim_tag,
    output wire                       victim_dirty,
    output wire                       victim_valid,

    // Write / Update Port
    input  wire                       wen,
    input  wire [SET_INDEX_WIDTH-1:0] windex,
    input  wire [1:0]                 wway,
    input  wire [TAG_WIDTH-1:0]       wtag,
    input  wire                       wvalid,
    input  wire                       wdirty,

    // Victim Inspection Way (from PLRU)
    input  wire [1:0]                 victim_way_sel
);

    // Tag and status storage: 32 sets x 4 ways
    reg [TAG_WIDTH-1:0] tags   [NUM_SETS-1:0][3:0];
    reg                 valids [NUM_SETS-1:0][3:0];
    reg                 dirties[NUM_SETS-1:0][3:0];

    integer i, j;

    // Reset and Write Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    tags[i][j]    <= {TAG_WIDTH{1'b0}};
                    valids[i][j]  <= 1'b0;
                    dirties[i][j] <= 1'b0;
                end
            end
        end else if (wen) begin
            tags[windex][wway]    <= wtag;
            valids[windex][wway]  <= wvalid;
            dirties[windex][wway] <= wdirty;
        end
    end

    // Combinational Match Logic for Read Index
    wire way0_match = valids[rindex][0] && (tags[rindex][0] == rtag);
    wire way1_match = valids[rindex][1] && (tags[rindex][1] == rtag);
    wire way2_match = valids[rindex][2] && (tags[rindex][2] == rtag);
    wire way3_match = valids[rindex][3] && (tags[rindex][3] == rtag);

    assign hit = ren && (way0_match || way1_match || way2_match || way3_match);

    assign hit_way = way0_match ? 2'd0 :
                     way1_match ? 2'd1 :
                     way2_match ? 2'd2 :
                     way3_match ? 2'd3 : 2'd0;

    assign hit_dirty = dirties[rindex][hit_way];

    // Victim Status readouts
    assign victim_tag   = tags[rindex][victim_way_sel];
    assign victim_dirty = dirties[rindex][victim_way_sel];
    assign victim_valid = valids[rindex][victim_way_sel];

endmodule
