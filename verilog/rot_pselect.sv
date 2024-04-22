`ifndef __ROT_PSELECT_DIR0__
`define __ROT_PSELECT_DIR0__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/pselect_dir0.sv"

//Recursively defined rotating priority select module
module rot_pselect #(parameter N = 8)(
    input clock,
    input reset,
    input [N-1:0] req,
    input en,
    input ROTATION_TYPE rotator,        // NONE, WALKING, JUMPING, RANDOM

    output logic [N-1:0] gnt
);
    logic [$clog2(N)-1:0] sel, next_sel;
    logic                 jump_toggle;

    pselect_dir0 #(.N(N)) pselect0 (
        .req(req),
        .en(en),
        .sel(sel),
        .gnt(gnt)
        //NC for req_up
    );

    always_comb begin
        next_sel = 0;
        if (rotator == NONE)
            next_sel = 0;
        else if (rotator == WALKING)
            next_sel = sel + 1'b1;
        else if (rotator == JUMPING)
            next_sel = jump_toggle ? sel + ($clog2(N)-1)'(N/2 + 1) : sel + ($clog2(N)-1)'(N/2);
        else if (rotator == RANDOM)
            next_sel = 0; // does nothing at the moment, requires a pseudo RNG, someone can implement this if they want to
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            sel <= `SD 0;
            jump_toggle <= `SD 0;
        end else if(en)begin
            sel <= `SD next_sel; 
            jump_toggle <= `SD ~jump_toggle;
        end
    end
endmodule

`endif