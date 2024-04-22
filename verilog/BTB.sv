`ifndef _BTB__
`define _BTB__

`include "./headers/include.svh"

`timescale 1ns/100ps

module BTB(
    input           clock,
    input           reset, 

    input           wr_en,
    input  BTB_IDX  wr_idx,
    input  BTB_TAG  wr_tag,
    input  BTB_DATA wr_data, 

    input  BTB_IDX  rd_idx,
    input  BTB_TAG  rd_tag,

    output BTB_DATA rd_data,
    output          rd_valid

`ifdef DEBUG_MODE
	,
    output BTB_DATA [`NUM_BTB_ENTRIES-1:0]  debug_data,
    output BTB_TAG  [`NUM_BTB_ENTRIES-1:0]  debug_tags,
    output logic    [`NUM_BTB_ENTRIES-1:0]  debug_BTB_dirty_idxs
`endif
);

    BTB_DATA [`NUM_BTB_ENTRIES-1:0]  data;
    BTB_TAG  [`NUM_BTB_ENTRIES-1:0]  tags;

`ifdef DEBUG_MODE
    assign debug_data = data;
    assign debug_tags = tags;
`endif

    assign rd_data = data[rd_idx];
    assign rd_valid = (tags[rd_idx] == rd_tag);

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if (reset) begin
            data <= `SD 0;
            tags <= `SD -1;
        end
        if (wr_en) begin
            data[wr_idx] <= `SD wr_data;
            tags[wr_idx] <= `SD wr_tag;
`ifdef DEBUG_MODE
            debug_BTB_dirty_idxs[wr_idx] <= `SD 1'b1;
`endif

        end
    end

endmodule

`endif