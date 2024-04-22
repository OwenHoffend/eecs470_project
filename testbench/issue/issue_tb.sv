`define FINISH_ON_ERROR
`timescale 1ns/100ps

`include "./headers/include.svh"
`include "./verilog/RS.sv"
`include "./verilog/regfile.sv"

// Testbench for the Issue Stage
module issue_tb;
    logic clock, reset;

    DISPATCH_PACKET dispatch_in;
    CDB_PACKET cdb_in;

    BRANCH_MASK branch_tag_in;

    logic lq_full, sq_full;

    IS_PACKET issue_out;
    logic rs_full, rs_available;

    issue issue_dut (
        .clock(clock),
        .reset(reset),
        .dispatch_in(dispatch_in),
        .cdb_in(cdb_in),
        .branch_tag_in(branch_tag_in),
        .lq_full(lq_full),
        .sq_full(sq_full),
        .issue_out(issue_out),
        .rs_full(rs_full),
        .rs_available(rs_available)
    );

    always begin
        #5 clock = ~clock;
    end

    function fail(
        string signal,
        integer correct_result
    );
        //$display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        //$display("---available: %b. full: %b", available, full);
        //$display("Current size: %h, Entry counter: %h", num_entries_actual, entry_counter);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    ///////////////////////////////////////////////////
    //          define tasks
    ///////////////////////////////////////////////////

    task dispatch_single(
        input DISPATCH_PACKET disp
    );

    endtask

    ///////////////////////////////////////////////////
    //          define variables
    ///////////////////////////////////////////////////

    always_comb begin
        
    end

    always_ff @(posedge clock) begin
        
    end

    initial begin
        $dumpvars;
        $monitor("Time:%4.0f reset:%b v_disp:%b v_iss:%b v_cdb:%b available:%b full:%b", 
                $time, reset, dispatch_in.valid, issue_out.valid, cdb_in.valid, rs_available, rs_full);
        /*reset = 0;
        clock = 0;
        cdb_in = 0;
        branch_tag_in = 0;
        lq_full = 0;
        sq_full = 0;
        dispatch_in = 0;
        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;
        @(negedge clock);
   
        dispatch_in.T1r = 1;
        dispatch_in.T2r = 1;
        dispatch_in.T1_used = 1;
        dispatch_in.T2_used = 1;
        dispatch_in.T1 = 4;
        dispatch_in.T2 = 2;
        dispatch_in.T = 1;
        dispatch_in.T_used = 1;
        dispatch_in.valid = 1;
        @(negedge clock);
        dispatch_in.valid = 0;
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);*/

        branch_tag_in = 0;
        cdb_in = 0;
        clock = 0;
        @(negedge clock);
        reset = 1;
        @(negedge clock); // initialize variables
        reset = 0;
        dispatch_in = 0; 
        dispatch_in.T1_used = 1;
        dispatch_in.T2_used = 1;
        @(negedge clock);

        //////////////////////////////////////////////////////
        //          basic filling and emptying              //
        //////////////////////////////////////////////////////

        $display("Filling reservation station with incomplete tags");
        
        // fill up the reservation station with incomplete tags
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            dispatch_in.valid = 1;
            dispatch_in.T = i;
            dispatch_in.T1 = i;
            dispatch_in.T2 = i;
            if (i == 0) begin
                dispatch_in.T1r = 1;
                dispatch_in.T2r = 1;
            end else begin
                dispatch_in.T1r = 0;
                dispatch_in.T2r = 0;
            end
            dispatch_in.branch_tag = 0;
        end

        $finish;
        
    end

endmodule
