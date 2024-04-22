`define NUM_WAYS 4

// `define NMRU_REPLACEMENT
`define RAND_REPLACEMENT
// `define LESS_PSEUDORAND_LFSR
`include "./verilog/LFSR.sv"
module LFSR_tb();

    logic clock, reset, enable;
    typedef logic [$clog2(`NUM_WAYS)-1:0] CACHE_WAY_IDX;
    
`ifdef NMRU_REPLACEMENT

    logic [$clog2(`NUM_WAYS)-1:0] LFSR_out;

    generate
    if (`NUM_WAYS > 2) begin : rng
        LFSR #(
            .NUM_BITS($clog2(`NUM_WAYS))
        ) LFSR_dut (
            .clock(clock),
            .reset(reset),
            .enable(enable),
            .LFSR(LFSR_out)
        );
    end
    endgenerate

`endif

`ifdef RAND_REPLACEMENT

`ifdef LESS_PSEUDORAND_LFSR

    logic [4:0] LFSR_out;

    LFSR #(
        .NUM_BITS(5)
    ) LFSR_dut (
        .clock(clock),
        .reset(reset),
        .enable(enable),
        .LFSR(LFSR_out)
    );

`else

    logic [$clog2(`NUM_WAYS):0] LFSR_out;

    LFSR #(
        .NUM_BITS($clog2(`NUM_WAYS)+1)
    ) LFSR_dut (
        .clock(clock),
        .reset(reset),
        .enable(enable),
        .LFSR(LFSR_out)
    );

`endif
`endif


`ifdef NMRU_REPLACEMENT
    
    CACHE_WAY_IDX                 MRU_idx, NMRU_idx, proc_way;

    always_comb begin
        if (`NUM_WAYS == 2)
            NMRU_idx = 1'b1 - MRU_idx;
        else
            NMRU_idx = MRU_idx + LFSR_out;
    end

    always_ff @(posedge clock) begin
        if(reset) begin
            MRU_idx <= #1 0;
        end else begin
            if (enable)
                MRU_idx <= #1 proc_way;
        end
    end
    always begin
        #10
        proc_way = proc_way + 1;       
    end
`endif

`ifdef RAND_REPLACEMENT
    CACHE_WAY_IDX     rand_idx;
    assign rand_idx = LFSR_out[$clog2(`NUM_WAYS)-1:0];
`endif

    always begin
        #5;
        clock = ~clock;
    end

    initial begin
        clock = 1'b0;
        reset = 1'b1;
        enable = 1'b0;

`ifdef NMRU_REPLACEMENT
        proc_way = -2;
        $monitor("Time:%4.0f  reset:%b  enable:%b  LFSR_state:%d  LFSR_state:%b  proc_way:%d  MRU_idx:%d  NMRU_idx:%d", 
            $time, reset, enable, LFSR_out, LFSR_out, proc_way, MRU_idx, NMRU_idx);
`endif

`ifdef RAND_REPLACEMENT
        $monitor("Time:%4.0f  reset:%b  enable:%b  LFSR_state:%d  LFSR_state:%b  rand_idx:%d", 
            $time, reset, enable, LFSR_out, LFSR_out, rand_idx);
`endif

        repeat(2) begin
            @(negedge clock);
        end
        reset = 1'b0;
        enable = 1'b1;
        repeat(32) begin
            @(negedge clock);
        end
        $finish;
    end
endmodule



// `ifdef USE_RAND
//     logic use_zero;
//     LFSR_rand LFSR_dut (
//         .clock(clock),
//         .reset(reset),
//         .enable(enable),
//         .use_zero(use_zero),
//         .LFSR(LFSR_out)
//     );
// `else
//     LFSR_NMRU LFSR_dut (
//         .clock(clock),
//         .reset(reset),
//         .enable(enable),
//         .LFSR(LFSR_out)
//     );
// `endif

