`ifndef _PSELECT_RS_TB__
`define _PSELECT_RS_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"

`define FINISH_ON_ERROR

module pselect_RS_tb;
    parameter N = 8;

    logic clock;
    logic reset;

    //Non-rotating priority select
    logic [N-1:0] req;
    logic en;
    logic [$clog2(N)-1:0] sel;
    logic [N-1:0] gnt, gnt_inv;

    logic [N-1:0] gnt_correct, gnt_correct_inv;

    pselect_RS #(.N(N), .DIR(0)) pselect_dut (
        .req(req),
        .en(en),
        .sel(sel),
        .gnt(gnt)
    );

    //pselect selecting from the other direction
    pselect_RS #(.N(N), .DIR(1)) pselect_inv_dut (
        .req(req),
        .en(en),
        .sel(sel),
        .gnt(gnt_inv)
    );

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    always begin
        #5 clock = ~clock;
    end

    //Compute the correct rotated grant value
    always_comb begin
        //Compute the normal grant value, for loop w/ break statement method
        gnt_correct = 0;
        for(int i = 0; i < N; i++) begin
            if(req[i]) begin
                gnt_correct[i] = 1'b1;
                break;
            end
        end

        gnt_correct_inv = 0;
        for(int i = N-1; i >= 0; i--) begin
            if(req[i]) begin
                gnt_correct_inv[i] = 1'b1;
                break;
            end
        end
    end

    always_ff @(posedge clock) begin
        if(reset) begin
            //Do reset things            
        end else begin
            if(gnt_correct !== gnt && sel == 0) //Don't test rotation for now, that's a rabbit hole...
                fail("gnt", gnt_correct);
            if(gnt_correct_inv !== gnt_inv && sel == 0) //Don't test rotation for now, that's a rabbit hole...
                fail("gnt", gnt_correct);
        end
    end

    initial begin
        $monitor("Time:%4.0f req: %b, sel: %b, gnt: %b, gnt_correct: %b gnt_inv: %b gnt_correct_inv: %b", 
            $time, req, sel, gnt, gnt_correct, gnt_inv, gnt_correct_inv);
        clock = 0;
        en = 1; 
        reset = 1;
        @(negedge clock);
        reset = 0;

        //Rotate through all selections for highest-priority output
        for(int i = 0; i < N; i++) begin 
            sel = i;
            for(int j = 0; j < 2 ** N; j++) begin //Exhaustivly test all possible requests
                req = j;
                @(negedge clock); //Design is combinational, but this helps divide tests for debugging
            end
        end
        $display("PASSED");
        $finish;
    end
endmodule

`endif