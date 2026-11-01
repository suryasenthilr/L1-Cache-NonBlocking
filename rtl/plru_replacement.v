// =============================================================================
// File: plru_replacement.v
// Module: plru_replacement
// Description: 4-Way Tree Pseudo-LRU (Tree-PLRU) Replacement Logic.
//              Maintains a 3-bit binary decision tree per set.
// =============================================================================

`timescale 1ns / 1ps

module plru_replacement #(
    parameter NUM_SETS = 32,
    parameter SET_INDEX_WIDTH = 5
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // Query Port (Which way to evict for a set)
    input  wire [SET_INDEX_WIDTH-1:0] query_set,
    output wire [1:0]                 victim_way,

    // Update Port (Mark way as recently accessed on Hit or Line Fill)
    input  wire                       update_en,
    input  wire [SET_INDEX_WIDTH-1:0] update_set,
    input  wire [1:0]                 access_way
);

    // Tree-PLRU bits per set:
    // b[0]: points to left (0) or right (1) pair
    // b[1]: points to way 0 (0) or way 1 (1) in left pair
    // b[2]: points to way 2 (0) or way 3 (1) in right pair
    reg [2:0] plru_tree [NUM_SETS-1:0];

    integer s;

    // Victim computation based on current tree state
    // To evict the LEAST recently used, we traverse towards where the arrows point
    wire [2:0] cur_tree = plru_tree[query_set];
    assign victim_way = (cur_tree[0] == 1'b0) ?
                            ((cur_tree[1] == 1'b0) ? 2'd0 : 2'd1) :
                            ((cur_tree[2] == 1'b0) ? 2'd2 : 2'd3);

    // Update tree: point arrows AWAY from the accessed way
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                plru_tree[s] <= 3'b000;
            end
        end else if (update_en) begin
            case (access_way)
                2'd0: begin
                    plru_tree[update_set][0] <= 1'b1; // point to right
                    plru_tree[update_set][1] <= 1'b1; // point to way 1
                end
                2'd1: begin
                    plru_tree[update_set][0] <= 1'b1; // point to right
                    plru_tree[update_set][1] <= 1'b0; // point to way 0
                end
                2'd2: begin
                    plru_tree[update_set][0] <= 1'b0; // point to left
                    plru_tree[update_set][2] <= 1'b1; // point to way 3
                end
                2'd3: begin
                    plru_tree[update_set][0] <= 1'b0; // point to left
                    plru_tree[update_set][2] <= 1'b0; // point to way 2
                end
            endcase
        end
    end

endmodule
