`ifndef _OH_TO_THERM_TB__
`define _OH_TO_THERM_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"

module onehot_to_therm_tb;
    parameter N = 32;
    logic clock;
    logic [N-1:0] in_data;
    logic [N-1:0] out_data, out_data_rev;
    logic [N-1:0] correct, correct_rev;

    onehot_to_therm #(.N(N), .DIR(0)) therm_fwd (
        .oh(in_data),
        .therm(out_data)
    );

    onehot_to_therm #(.N(N), .DIR(1)) therm_rev (
        .oh(in_data),
        .therm(out_data_rev)
    );

    always begin //Just to keep simulation time
        #5 clock = ~clock;
    end

    logic hit;
    always_comb begin 
        hit = 0;
        correct = 0;
        correct_rev = 0;
        for(int i = N-1; i >= 0; i--) begin
            if(in_data[i])
                hit = 1;
            if(hit)
                correct[i] = 1;
        end

        hit = 0;
        for(int i = 0; i < N; i++) begin
            if(in_data[i])
                hit = 1;
            if(hit)
                correct_rev[i] = 1; 
        end
    end

    task check;
        if(correct !== out_data | correct_rev !== out_data_rev) begin
            $display("FAILED: output: %h, correct: %h, output_rev: %h, correct_rev: %h", 
                out_data, correct, out_data_rev, correct_rev);
            $finish;
        end
    endtask

    initial begin
        $monitor("Time:%4.0f in_data:%h out_data:%h out_data_rev: %h", 
            $time, in_data, out_data, out_data_rev);
        clock = 0;
        @(negedge clock);

        in_data = 32'h8000_0000;
        while(in_data > 0) begin //This is a 100% exhaustive test
            @(negedge clock);
            check();
            @(negedge clock);
            in_data >>= 1;
        end

        in_data = 0;
        @(negedge clock);
        check();
        $display("PASSED");
        $finish;
    end
endmodule

`endif