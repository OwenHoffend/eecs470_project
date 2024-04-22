`ifndef _BARREL_TB__
`define _BARREL_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"

//Extremely basic testbench just so I can see that it works visually - TODO: improve this
module barrel_shift_tb;

    parameter N = 32;
    parameter DIR = 1;
    logic clock;
    logic [N-1:0] in_data;
    logic [$clog2(N)-1:0] nshifts;
    logic [N-1:0] out_data;

    barrel_shift #(.N(N), .DIR(DIR)) barrel_shift_dut (
        .in_data(in_data),
        .nshifts(nshifts),
        .out_data(out_data)
    );

    always begin //Just to keep simulation time
        #5 clock = ~clock;
    end

    initial begin
        $monitor("Time:%4.0f in_data:%32h nshifts:%d out_data:%32h", $time, in_data, nshifts, out_data);
        clock = 0;
        @(negedge clock);
        in_data = 32'hDEADBEEF;
        nshifts = 32'h10; //16 left shifts
        //It should say "BEEFDEAD"
        @(negedge clock);

        in_data = 32'h11111111;
        nshifts = 32'hFF; //It should say 88888888
        @(negedge clock);

        in_data = 32'hFEEDDADA;
        nshifts = 32'h0; //It should still say FEEDDADA
        @(negedge clock);
        $finish;
    end
endmodule

`endif