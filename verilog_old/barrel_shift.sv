`ifndef __BARREL_SHIFT__
`define __BARREL_SHIFT__
`timescale 1ns/100ps
`include "./headers/include.svh"

//Combinational bidirectional circular barrel shifter
//Shift a bus by a variable value with log(N) logic levels
module barrel_shift_dir0 #(parameter N = 32, CIRC = 1)(
    input [N-1:0] in_data,
    input [$clog2(N)-1:0] nshifts,
    output logic [N-1:0] out_data
);
    logic [(2*N)-1:0] loop;
    always_comb begin
        loop = 0;
        //Right shift
        loop[(2*N)-1:N] = in_data;
        for(int i = 0; i < $clog2(N); i++) begin
            if(nshifts[i]) begin //Bit selects if the shift at this level should be done
                //Directional shift by a power of 2
                loop >>= (2 ** i);
            end
        end
        if(CIRC) //Circular case: Wrap the overflow bits
            out_data = loop[N-1:0] | loop[(2*N)-1:N];
        else //Non circular case: Ignore the overflow bits
            out_data = loop[(2*N)-1:N];
    end
endmodule

module barrel_shift_dir1 #(parameter N = 32, CIRC = 1)(
    input [N-1:0] in_data,
    input [$clog2(N)-1:0] nshifts,
    output logic [N-1:0] out_data
);
    logic [(2*N)-1:0] loop;
    always_comb begin
        loop = 0;
        //Left shift
        loop[N-1:0] = in_data;
        for(int i = 0; i < $clog2(N); i++) begin
            if(nshifts[i]) begin //Bit selects if the shift at this level should be done
                //Directional shift by a power of 2
                loop <<= (2 ** i);
            end
        end
        if(CIRC) //Circular case: Wrap the overflow bits
            out_data = loop[N-1:0] | loop[(2*N)-1:N];
        else //Non circular case: Ignore the overflow bits
            out_data = loop[N-1:0];
    end
endmodule

`endif