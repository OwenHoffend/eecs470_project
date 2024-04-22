`ifndef _BTAG_TRACKER__
`define _BTAG_TRACKER__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/pselect_dir0.sv"
`include "./verilog/onehot_to_therm.sv"
module btag_tracker(
    input clock,
    input reset,
    input branch_dispatch,
    input CDB_PACKET cdb_in,

    output BRANCH_MASK branch_tag_out,
    output BRANCH_MASK branch_mask,
    output logic bs_stall //Branch stack stall
`ifdef DEBUG_MODE
   ,output BRANCH_MASK branch_tag_next
`endif
);
    BRANCH_MASK branch_tag, branch_tag_temp;
`ifndef DEBUG_MODE
    BRANCH_MASK branch_tag_next; 
`endif
    BRANCH_MASK branch_mask_psel;
    BRANCH_MASK squash_mask_therm;

    pselect_dir0 #(
        .N(`BS_SIZE)
    ) pselect0 (
        .req(branch_tag_temp),
        .en(1'b1),
        .sel({$clog2(`BS_SIZE){1'b0}}),
        .gnt(branch_mask_psel)
    );

    onehot_to_therm #(
        .N(`BS_SIZE), 
        .DIR(0)
    ) onehot_to_therm0 (
        .oh(cdb_in.branch_mask),
        .therm(squash_mask_therm)
    );

    always_comb begin
        //Handle branches that are completing
        branch_tag_temp = branch_tag;
        if(cdb_in.valid) begin 
            //Clear out the bit corresponding to the branch mask from the CDB
            //If the mask is zero, this does nothing.
            if(cdb_in.squash_enable) begin
                branch_tag_temp &= ~squash_mask_therm;
            end else
                branch_tag_temp &= ~cdb_in.branch_mask; 
        end
        branch_tag_out = branch_tag_temp;

        //Find the current branch mask from the branch tag
        branch_mask = branch_mask_psel;
        if(~| branch_mask)
            branch_mask = `MAX_BRANCH_MASK;
        else
            branch_mask >>= 1;

        //Handle new branches
        bs_stall = 0;
        branch_tag_next = branch_tag_temp;
        if(~| branch_mask) //Stall if no more branches can be added to the be BS
            bs_stall = 1;
            
        if(branch_dispatch)
            branch_tag_next |= branch_mask;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            branch_tag  <= `SD 0;
        end else begin
            branch_tag  <= `SD branch_tag_next; 
        end
    end
endmodule
`endif