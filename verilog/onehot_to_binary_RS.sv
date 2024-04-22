`ifndef _OH_TO_BIN_RS__
`define _OH_TO_BIN_RS__
`include "./headers/include.svh"

`timescale 1ns/100ps

module onehot_to_binary_RS #(parameter N = `RS_SIZE)(
    input  [N-1:0] oh,
    output wor [$clog2(N)-1:0] bin
);
    genvar i,j;
    generate
        for(i=0;i<$clog2(N);i=i+1)
        begin : foo
            for(j=1;j<N;j=j+1)
            begin : bar
                if (j[i])
                    assign bin[i] = oh[j];
            end
        end
    endgenerate
endmodule

//GRAVEYARD FULL OF SAD OWEN TEARS: 
//THIS MODULE IS COOL AF BUT NOT AS EFFICIENT AS THE ONE ABOVE
//Convert one-hot to binary via binary search
/*
f module onehot_to_binary #(parameter N = 32) (
f     input  [N-1:0] oh,
f     output logic [$clog2(N)-1:0] bin
f );
f 
f     logic [N:0] loop, temp;
f     always_comb begin
f         bin = 0;
f         loop[N-1:0] = oh;
f         for(int i = $clog2(N)-1; i >= 0; i--) begin
f             temp = loop >> (2 ** i);
f             if(temp == 0) //Too far
f                 bin[i] = 1'b0;
f             else begin 
f                 loop = temp;
f                 bin[i] = 1'b1;
f             end
f         end
f     end
f endmodule
f */
`endif