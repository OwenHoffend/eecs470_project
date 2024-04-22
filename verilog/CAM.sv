`ifndef _CAM__
`define _CAM__
`timescale 1ns/100ps
`include "./headers/include.svh"

module CAM #(
    parameter ARRAY_SIZE=`ARCH_REGFILE_SIZE, 
    parameter DATA_SIZE=$clog2(`PHYS_REGFILE_SIZE)
)(
    input enable,

    input [ARRAY_SIZE-1:0][DATA_SIZE-1:0] array,
    input [ARRAY_SIZE-1:0]                array_valid,
    input                 [DATA_SIZE-1:0] read_data,

    output logic [$clog2(ARRAY_SIZE)-1:0] read_idx,
    output logic hit
);

    always_comb begin
        hit = 0;
        read_idx = 0;
        if(enable) begin
            for(int i = 0; i < ARRAY_SIZE; i++) begin
                if((array[i] == read_data) & array_valid[i]) begin
                    hit = 1;
                    read_idx = i;
                    break;
                end
            end
        end
    end
endmodule

`endif