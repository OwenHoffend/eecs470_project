`ifndef __BINARY_PSELECT_DIR1__
`define __BINARY_PSELECT_DIR1__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/pselect_dir1.sv"
`include "./verilog/onehot_to_binary.sv"

//Priority selector that outputs binary and not one-hot
module binary_pselect_dir1 #(parameter N = `SQ_SIZE)( 
    input [N-1:0] req,
    input en,
    input [$clog2(N)-1:0] sel,
    output logic [$clog2(N)-1:0] gnt
);
    logic [N-1:0] gnt_onehot;

    pselect_dir1 #(.N(N)) psel0 (
        .req(req),
        .en(en),
        .sel(sel),
        .gnt(gnt_onehot)
    );

    onehot_to_binary #(.N(N)) oh0 (
        .oh(gnt_onehot),
        .bin(gnt)    
    );

endmodule

`endif