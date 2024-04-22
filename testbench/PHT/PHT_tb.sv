`ifndef _PHT_TB__
`define _PHT_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"

`define FINISH_ON_ERROR

module PHT_tb;
    logic  clock, reset;
    logic  [`GHB_SIZE-1:0] rd_idx, wb_idx;    // read/writeback index
    logic  wb_taken, wb_en;     // was the branch taken or not taken?

    logic  taken;    // read data

    PHT PHT_dut(
        .rd_idx(rd_idx),
        .wb_idx(wb_idx),
        .wb_taken(wb_taken),
        .wb_en(wb_en),
        .clock(clock),
        .reset(reset),
        .taken(taken)
    ); 

    task fail(
        input string signal,
        input integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endtask

    task ex_branch(input int br_taken, input int index);
        wb_idx = index;
        wb_en = 1;
        wb_taken = br_taken;
        @(negedge clock);
        wb_en = 0;
    endtask;

    always begin
        #5 clock = ~clock;
    end

    initial begin
        clock = 0;
        reset = 1;
        wb_en = 0;
        rd_idx = 1;
        $display("beginning tests");
        @(negedge clock);
        reset = 0;
        @(negedge clock);
        rd_idx = 0;
        for (int k = 0; k < 2**(`GHB_SIZE); k++) begin
            for (int i = 0; i < 100; i++) begin
                wb_en = 0;
                wb_taken = 1;
                wb_idx = k;
                rd_idx = k;
                @(negedge clock);
                if (taken)
                    fail("wb wasn't enabled", 0);
            end
        end
        for (int k = 0; k < 2**(`GHB_SIZE); k++) begin
            wb_en = 1;
            wb_taken = 1;
            wb_idx = k;
            rd_idx = k;
            @(negedge clock);
            if(~taken)
                fail("didn't flip to taken fast enough", 1);
        end
        for (int k = 0; k < 2**(`GHB_SIZE); k++) begin
            for (int i = 0; i < 100; i++) begin
                wb_en = 0;
                wb_taken = 0;
                wb_idx = k;
                rd_idx = k;
                @(negedge clock);
                if (~taken)
                    fail("wb wasn't enabled", 0);
            end
        end
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;
        @(negedge clock);
        if (taken)
            fail("hi",0);
        @(negedge clock);
        for (int k = 0; k < 2**(`GHB_SIZE); k++) begin
            rd_idx = k;
            for (int i = 0; i < 10000; i++) begin
                ex_branch(0,rd_idx);
                if(taken)
                    fail("hi",0);
            end
            for (int i = 0; i < 10000; i++) begin
                ex_branch(1,rd_idx);
                if(taken)
                    break;
                if(i == 9999)
                    fail("never goes back to taken", k);
            end
            for (int i = 0; i < 10000; i++) begin
                ex_branch(1,rd_idx);
                if(~taken)
                    fail("hi",0);
            end
            //$display("k:%h rd_idx:%h", k, rd_idx);
            if (rd_idx == 0 && k != 0)
                break;
        end
        `ifdef FINISH_ON_ERROR
        $display("PASSED");
        `endif
        $finish;
    end
endmodule

`endif