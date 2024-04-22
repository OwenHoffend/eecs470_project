`ifndef _LFSR__
`define _LFSR__
`timescale 1ns/100ps
`include "./headers/include.svh"

// Need to fix possible index-out-of-bound synthesis issue

module LFSR #(
    parameter NUM_BITS = 4
)(
    input clock,
    input reset,
    input enable,

    output logic [NUM_BITS-1:0] LFSR

);

    logic [NUM_BITS-1:0] LFSR_next;
    
    always_comb begin
        LFSR_next = LFSR;
        if (enable) begin
            LFSR_next = LFSR << 1;
            
            case (NUM_BITS)
                5: begin
                    // 5 bit LFSR
                    LFSR_next[0] = LFSR[1]^LFSR[NUM_BITS-1];
                end
                default: begin
                    // 2, 3, 4 bit LFSR
                    LFSR_next[0] = LFSR[0]^LFSR[NUM_BITS-1];
                end
            endcase

        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if (reset)
            LFSR <= #1 1;
        else
            LFSR <= #1 LFSR_next;
    end
endmodule
`endif