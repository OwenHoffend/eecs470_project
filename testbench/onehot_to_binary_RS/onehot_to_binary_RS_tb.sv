`ifndef _OH_TO_BIN_RS_TB__
`define _OH_TO_BIN_RS_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"

//Extremely basic testbench just so I can see that it works visually - TODO: improve this
module onehot_to_binary_RS_tb;
    parameter N = `RS_SIZE;
    logic clock;
    logic [N-1:0] in_data;
    logic [$clog2(N)-1:0] out_data;

    onehot_to_binary_RS #(.N(N)) oh_dut (
        .oh(in_data),
        .bin(out_data)
    );

    always begin //Just to keep simulation time
        #5 clock = ~clock;
    end

    int correct;
    task check;
        if(correct !== out_data) begin
            $display("FAILED: output: %h, correct: %h", out_data, correct);
            $finish;
        end
    endtask

    initial begin
        $monitor("Time:%4.0f in_data:%32h out_data:%h", $time, in_data, out_data);
        clock = 0;
        @(negedge clock);

        correct = 8'h1f;
        in_data = 32'h8000_0000;
        while(in_data > 0) begin
            @(negedge clock);
            check();
            @(negedge clock);
            correct--;
            in_data >>= 1;
        end

        correct = 0;
        in_data = 0;
        @(negedge clock);
        check();
        $display("PASSED");
        $finish;
    end
endmodule

`endif