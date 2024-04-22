`ifndef __PSELECT_DIR1__
`define __PSELECT_DIR1__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/ps2_dir1.sv"

module pselect_dir1 #(parameter N = 8)(
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
        ps2_dir1 sel_ps2(
            .req(req),
            .en(en),
            .sel(sel),
            .gnt(gnt),
            .req_up(req_up)
        );
    end else begin : rec
        pselect_dir1 #(.N(N/2)) top(
            .req(req[(N-1):(N/2)]),
            .en(internal_ens[1]),
            .sel(sel[$clog2(N)-2:0]), //All but the last bit of the select bus
            .gnt(gnt[(N-1):(N/2)]),
            .req_up(internal_reqs[1])
        );
        pselect_dir1 #(.N(N/2)) bot(
            .req(req[(N/2)-1:0]),
            .en(internal_ens[0]),
            .sel(sel[$clog2(N)-2:0]), //All but the last bit of the select bus
            .gnt(gnt[(N/2)-1:0]),
            .req_up(internal_reqs[0])
        );
        ps2_dir1 mid(
            .req(internal_reqs),
            .en(en),
            .sel(sel[$clog2(N)-1]), //Last bit of the select bus
            .gnt(internal_ens),
            .req_up(req_up)
        );
    end
    endgenerate
endmodule

`endif