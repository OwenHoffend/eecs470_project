`ifndef __PSELECT_RS__
`define __PSELECT_RS__
`timescale 1ns/100ps
`include "./headers/include.svh"
//`include "./verilog/onehot_to_binary_RS.sv"

module ps2_RS #(parameter DIR = 0) (
    input [1:0] req,
    input en,
    input sel, 
    output logic [1:0] gnt,
    output logic req_up
);
    always_comb begin
        req_up = req[0] | req[1];
        if(en) begin
            if(sel ^ DIR) begin //xor to make DIR invert the gnt priority assignments
                gnt[1] = req[1];
                gnt[0] = req[0] & !req[1];
            end else begin
                gnt[0] = req[0];
                gnt[1] = req[1]  & !req[0];
            end
        end else begin
            gnt = 2'b00;
        end
    end
endmodule

module pselect_RS #(parameter N = `RS_SIZE, DIR = 0)(
    input [N-1:0] req,
    input en,
    input [$clog2(N)-1:0] sel, //Hierarchical select bits, for rotation
    output logic [N-1:0] gnt,
    output logic req_up
);

    logic [1:0] internal_reqs;
    logic [1:0] internal_ens;

    generate
    if(N == 2) begin : base
        ps2_RS #(.DIR(DIR)) sel_ps2(
            .req(req),
            .en(en),
            .sel(sel),
            .gnt(gnt),
            .req_up(req_up)
        );
    end else begin : rec
        pselect_RS #(.N(N/2), .DIR(DIR)) top(
            .req(req[(N-1):(N/2)]),
            .en(internal_ens[1]),
            .sel(sel[$clog2(N)-2:0]), //All but the last bit of the select bus
            .gnt(gnt[(N-1):(N/2)]),
            .req_up(internal_reqs[1])
        );
        pselect_RS #(.N(N/2), .DIR(DIR)) bot(
            .req(req[(N/2)-1:0]),
            .en(internal_ens[0]),
            .sel(sel[$clog2(N)-2:0]), //All but the last bit of the select bus
            .gnt(gnt[(N/2)-1:0]),
            .req_up(internal_reqs[0])
        );
        ps2_RS #(.DIR(DIR)) mid(
            .req(internal_reqs),
            .en(en),
            .sel(sel[$clog2(N)-1]), //Last bit of the select bus
            .gnt(internal_ens),
            .req_up(req_up)
        );
    end
    endgenerate
endmodule

// //Priority selector that outputs binary and not one-hot
// module binary_pselect #(parameter N = `RS_SIZE, DIR = 0)( 
//     input [N-1:0] req,
//     input en,
//     input [$clog2(N)-1:0] sel,
//     output logic [$clog2(N)-1:0] gnt
// );
//     logic [N-1:0] gnt_onehot;

//     pselect_RS #(.N(N), .DIR(DIR)) psel0 (
//         .req(req),
//         .en(en),
//         .sel(sel),
//         .gnt(gnt_onehot)
//     );

//     onehot_to_binary #(.N(N)) oh0 (
//         .oh(gnt_onehot),
//         .bin(gnt)    
//     );

// endmodule

//Recursively defined rotating priority select module
module rot_pselect_RS #(parameter N = `RS_SIZE)(
    input clock,
    input reset,
    input [N-1:0] req,
    input en,
    input ROTATION_TYPE rotator,        // NONE, WALKING, JUMPING, RANDOM

    output logic [N-1:0] gnt
);
    logic [$clog2(N)-1:0] sel, next_sel;
    logic                 jump_toggle;

    pselect_RS #(.N(N)) pselect_RS0 (
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