`ifndef _REPLACEMENTPOLICY__
`define _REPLACEMENTPOLICY__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/CAM.sv"
`include "./verilog/LFSR.sv"

`ifndef DMAP_CACHE_MODE

`ifdef LRU_REPLACEMENT
module LRU #(
    parameter ARRAY_SIZE=`NUM_WAYS
)(
    input clock,
    input reset,

    // Processor interaction
    input                proc_valid,
    input CACHE_WAY_IDX  proc_way,

    // Memory write request
    input                mem_write_valid,

    // Read address out
    output CACHE_WAY_IDX mem_write_way

`ifdef DEBUG_MODE
    ,
    output CACHE_WAY_IDX [ARRAY_SIZE-1:0] cache_uses_debug 
`endif
);
    // Use counters in LRU
    CACHE_WAY_IDX [ARRAY_SIZE-1:0] uses, uses_next;
    logic                          prev_use;

    // Compute way for a replacement
    CAM #(
        .ARRAY_SIZE  (ARRAY_SIZE),
        .DATA_SIZE   ($clog2(ARRAY_SIZE))
    ) LRU_CAM (
        // Inputs
        .enable      (mem_write_valid),
        .array       (uses),
        .array_valid ({ARRAY_SIZE{1'b1}}),
        .read_data   ({$clog2(ARRAY_SIZE){1'b1}}),

        // Outputs
        .read_idx    (mem_write_way)
    );

    always_comb begin
        // Update use counters on a processor interaction
        uses_next = uses;
        if(proc_valid) begin
            for(int i = 0; i < ARRAY_SIZE; i++) begin
                if(uses[i] < uses[proc_way])
                    uses_next[i] = uses[i] + 1'b1;
            end
            uses_next[proc_way] = 0;
        end

        // Debug Output
`ifdef DEBUG_MODE
        cache_uses_debug = uses;
`endif
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for(int i = 0; i < ARRAY_SIZE; i++) begin
                uses[i] <= `SD ARRAY_SIZE - i - 1;
            end
        end else begin
            uses <= `SD uses_next;
        end
    end
endmodule
`endif // LRU_REPLACEMENT

`ifdef NMRU_REPLACEMENT
module NMRU #(
    parameter ARRAY_SIZE=`NUM_WAYS
)(
    input clock,
    input reset,

    // Read port in
    input                proc_valid,
    input CACHE_WAY_IDX  proc_way,

    input logic [$clog2(ARRAY_SIZE)-1:0] LFSR_in,

    // Write request
    input                write_valid,

    // Read address out
    output CACHE_WAY_IDX NMRU_idx

`ifdef DEBUG_MODE
    ,
    output CACHE_WAY_IDX MRU_idx
`endif // endif DEBUG_MODE
);

`ifndef DEBUG_MODE
    CACHE_WAY_IDX MRU_idx;
`endif // endif ifndef DEBUG_MODE

    always_comb begin
        if (ARRAY_SIZE == 2)
            NMRU_idx = 1'b1 - MRU_idx;
        else
            NMRU_idx = MRU_idx + LFSR_in;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            MRU_idx <= `SD 0;
        end else begin
            if (proc_valid)
                MRU_idx <= `SD proc_way;
        end
    end
endmodule
`endif // NMRU_REPLACEMENT

`endif // ifndef DMAP_CACHE_MODE

`endif // REPLACEMENTPOLICY