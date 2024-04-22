`ifndef __PS2_DIR1__
`define __PS2_DIR1__
`timescale 1ns/100ps
`include "./headers/include.svh"

module ps2_dir1 (
    input [1:0] req,
    input en,
    input sel, 
    output logic [1:0] gnt,
    output logic req_up
);
    always_comb begin
        req_up = req[0] | req[1];
        if(en) begin
            if(~sel) begin
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

`endif