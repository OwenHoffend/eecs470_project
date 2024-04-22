`ifndef _RS_ET_TB__
`define _RS_ET_TB__
`define FINISH_ON_ERROR 
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/pselect.sv"
`include "./verilog/onehot_to_binary.sv"
`include "./verilog/RS_ET.sv"


// Testbench for the Reservation Station
module RS_ET_tb;

    logic clock;
    logic reset;

    DISPATCH_PACKET dispatch_in;
    CDB_PACKET   cdb_in;

    // logic lq_full;
    // logic sq_full;

    RS_PACKET    am_rs_out;
    RS_PACKET    ls_rs_out;

    logic        full;
    logic        available;

    RS_DEBUG_PACKET rs_debug;

    `ifdef DEBUG_MODE
        logic [$clog2(`RS_SIZE):0] num_entries_actual;
        logic [`RS_SIZE-1:0] can_issue;
        logic valid_issue_out;
        RS_IDX rs_issue_idx_out;
        RS_IDX rs_input_idx_out;
        //BRANCH_MASK [`RS_SIZE-1:0] branch_tag_matrix;
    `endif

    RS_ET RS_ET_dut (
        .clock(clock),
        .reset(reset),

        .dispatch_in(dispatch_in),
        .cdb_in(cdb_in),

        // .lq_full(lq_full), 
        // .sq_full(sq_full),

        .ls_rs_out(ls_rs_out),
        .am_rs_out(am_rs_out),

        `ifdef DEBUG_MODE
            .rs_debug(rs_debug),
        `endif

        .full(full),
        .available(available)  
    );
/*
    always_comb begin
        num_entries_actual = rs_debug.num_entries_actual;
        can_issue          = rs_debug.can_issue;
        valid_issue_out    = rs_debug.valid_issue_out;
        rs_issue_idx_out   = rs_debug.rs_issue_idx_out;
        rs_input_idx_out   = rs_debug.rs_input_idx_out;
        //branch_tag_matrix  = rs_debug.branch_tag_matrix;
    end

    always begin
        #5 clock = ~clock;
    end

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("---available: %b. full: %b", available, full);
        $display("Current size: %h, Entry counter: %h", num_entries_actual, entry_counter);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    task T_used(
        input T_used, T1_used, T2_used
    );
        dispatch_in.T1_used = T1_used;
        dispatch_in.T2_used = T2_used;
        dispatch_in.T_used  = T_used;
    endtask

    task Tr(
        input T1r, T2r
    );
        dispatch_in.T1r = T1r;
        dispatch_in.T2r = T2r;
    endtask

    task set_tags(
            input PHYS_REG_TAG T, T1, T2
    );
        dispatch_in.T  = T;
        dispatch_in.T1 = T1;
        dispatch_in.T2 = T2;
    endtask

    task reset_rs();
        @(negedge clock);
        dispatch_in = 0;
        cdb_in = 0;
        reset = 1;
        @(negedge clock);
        reset = 0;
    endtask

    task dispatch(  // pass in dispatch parameters, this will dispatch a single instruction
        input DISPATCH_PACKET disp
    );
    dispatch_in.valid = 0;
    @(negedge clock);
    dispatch_in.valid = 1;
    @(negedge clock);
    dispatch_in.valid = 0;
    endtask
    
    task complete(
        input CDB_PACKET cdb_in
    );

    endtask

    // declare vars
    int entry_counter, entry_counter_next, num_entries_squashed;
    logic num_entries_inc, num_entries_dec;
    logic any_can_issue;

    always_comb begin
        any_can_issue = 1'b0;
        for(int i = 0; i < `RS_SIZE; i++) begin
            any_can_issue |= can_issue[i];
        end
        num_entries_squashed = 0;
        //for (int i = 0; i < `RS_SIZE; i++) begin
        //    if (cdb_in.valid & cdb_in.squash_enable)
        //        num_entries_squashed++;
        //end
        //Set variables related to combinational checks here
        num_entries_inc = (~full & dispatch_in.valid) | (full & dispatch_in.valid & any_can_issue);
        num_entries_dec = any_can_issue;
        entry_counter_next = cdb_in.squash_enable ? entry_counter - num_entries_squashed : entry_counter + num_entries_inc - num_entries_dec;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            entry_counter <= `SD 0;
        end else begin
            //Combinational checks performed here
            //Full/available tests (similar to ROB_tb)
            if(entry_counter != `RS_SIZE && full)
                fail("full", 0);
            if(entry_counter == `RS_SIZE && ~full)
                fail("full", 1);
            if(entry_counter == 0 && available)
                fail("available", 0); 
            if(entry_counter != 0 && ~available)
                fail("available", 1);

            //Entry counter test
            if(num_entries_actual !== entry_counter)
                fail("size", entry_counter);

            //Tests that anything can issue
            if(any_can_issue & ~valid_issue_out)
                fail("valid_issue_out", 1);
            if(valid_issue_out & ~any_can_issue)
                fail("valid_issue_out", 0);
                
            entry_counter <= `SD entry_counter_next;
        end
    end


    initial begin
        $dumpvars;
        $monitor("Time:%4.0f reset:%b valid_dispatch:%b am_valid_issue:%b ls_valid_issue:%b full:%b available:%b d_idx:%h i_idx:%h entry_counter:%h ", 
                 $time,      reset,   dispatch_in.valid, am_rs_out.valid, ls_rs_out.valid, full, available, rs_input_idx_out, rs_issue_idx_out, entry_counter); //Add more stuff here
        //$monitor("CDB -- valid:%b tag:%h mask:%b", cdb_in.valid, cdb_in.cdb_tag, cdb_in.branch_mask);
        //`ifdef DEBUG_MODE
        //    $monitor("issue valid:%b issue index:%h dispatch index:%h", valid_issue_out, rs_issue_idx_out, rs_input_idx_out);
        //`endif
        dispatch_in.branch_tag = 0;
        cdb_in = 0;
        clock = 0;
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
        //$finish;
        $display("Filling reservation station with incomplete tags: DONE");

        $display("Trying to dispatch while full");
        @(negedge clock); // should not do anything
        dispatch_in.T = 3;
        dispatch_in.T1 = 6;
        dispatch_in.T2 = 9; // damn she fine
        @(negedge clock); // 
        dispatch_in.valid = 0;
        $display("Trying to dispatch while full: DONE");

        $display("Clearing tags and emptying the RS");
        
        // clear tags from 0 - RS_SIZE - 1
        for (int i = 0; i < `PHYS_REGFILE_SIZE; i++) begin
            @(negedge clock);
            cdb_in.cdb_tag = i;
            cdb_in.valid = 1;
            cdb_in.T_used = 1;
            //$display("CDB tag:%h issue index:%h issue valid:%b", cdb_in.cdb_tag, rs_issue_idx_out, valid_issue_out);
        end
        
        $display("Clearing tags and emptying the RS: DONE");

        //////////////////////////////////////////////////////
        //    refilling RS and checking full-forwarding     //
        //////////////////////////////////////////////////////

        $display("Filling reservation station with incomplete tags");
        
        // fill up the reservation station with incomplete tags FIXME: THIS IS NOT WORKING
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            dispatch_in.valid = 1;
            dispatch_in.T = i;
            dispatch_in.T1 = i;
            dispatch_in.T2 = i;
            dispatch_in.T1r = 0;
            dispatch_in.T2r = 0;
            dispatch_in.branch_tag = 0;
        end
        
        $display("Filling reservation station with incomplete tags: DONE");

        $display("Dispatching and issuing simultaneously while full"); // full should stay true the whole time but indeces should update
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            cdb_in.valid = 1;
            cdb_in.cdb_tag = i;
            
            dispatch_in.valid = 1;
            dispatch_in.T = i;
            dispatch_in.T1 = i;
            dispatch_in.T2 = i;
            dispatch_in.T1r = 0;
            dispatch_in.T2r = 0;
            dispatch_in.branch_tag = 0;
        end
        dispatch_in.valid = 0;
        $display("Dispatching and issuing simultaneously while full: DONE");

        /*
        $display("Clearing the RS");
        
        // fill up the reservation station with incomplete tags
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            dispatch_in.valid = 1;
            dispatch_in.T = i;
            dispatch_in.T1 = i;
            dispatch_in.T2 = i;
            dispatch_in.T1r = 0;
            dispatch_in.T2r = 0;
            dispatch_in.branch_tag = 0;
        end
        
        $display("Clearing the RS: DONE");

        // TODO: test when an instruction dispatches not ready and gets cleared by the CDB on the way in
*//*

        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;

        
        
        $display("Dispatching incomplete instruction with tags cleared in current CDB");
        @(negedge clock);
        dispatch_in = $random;
        cdb_in = $random;
        T_used(1, 1, 1);
        Tr(1, 0);
        set_tags(3, 2, 1);
        dispatch_in.branch_tag = 0;
        dispatch_in.valid = 1;
        cdb_in.branch_mask = 0;
        cdb_in.T_used = 1;
        cdb_in.cdb_tag = 1;
        cdb_in.valid = 1;
        @(negedge clock);
        cdb_in.valid = 0;
        dispatch_in.valid = 0;
        // should now issue one instruction
        @(negedge clock);
        T_used(1, 1, 1);
        Tr(0, 1);
        set_tags(3, 2, 1);
        dispatch_in.valid = 1;
        cdb_in.T_used = 1;
        cdb_in.cdb_tag = 2;
        cdb_in.valid = 1;
        @(negedge clock);
        cdb_in = 0;
        dispatch_in = 0;
        // should now issue one instruction
        $display("Dispatching incomplete instruction with tags cleared in current CDB");

        @(negedge clock);

        @(negedge clock);
        reset = 1;
        @(negedge clock);
        reset = 0;

        $display("Dispatching incomplete instructions with the same branch tag");
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            dispatch_in.valid = 1;
            T_used(1,1,1);
            dispatch_in.T = i;
            dispatch_in.T1 = i;
            dispatch_in.T2 = i;
            if (i % `PHYS_REGFILE_SIZE == 0) begin
                dispatch_in.T1 = 1;
                dispatch_in.T2 = 1;
            end
            dispatch_in.T1r = 0;
            dispatch_in.T2r = 0;
            dispatch_in.branch_tag = 4'b1111;
        end
        $display("Squashing instructions with the same branch tag");
        // also tests that the incoming dispatch is squashed and not input into the RS
        @(negedge clock);
        cdb_in.valid = 1;
        cdb_in.branch_mask = 4'b0100;
        cdb_in.squash_enable = 1;
        @(negedge clock);
        cdb_in = 0;
        dispatch_in = 0;

        $display("Squashing instructions with the same branch tag: DONE");



        $display("Dispatching incomplete instructions with the same branch tag");
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            dispatch_in.valid = 1;
            T_used(1,1,1);
            dispatch_in.T = i;
            dispatch_in.T1 = i;
            dispatch_in.T2 = i;
            if (i % `PHYS_REGFILE_SIZE == 0) begin
                dispatch_in.T1 = 1;
                dispatch_in.T2 = 1;
            end
            dispatch_in.T1r = 0;
            dispatch_in.T2r = 0;
            dispatch_in.branch_tag = 4'b0010;
        end
        $display("Squashing instructions with the wrong branch tag");
        // also tests that the incoming dispatch is squashed and not input into the RS
        @(negedge clock);
        cdb_in.valid = 1;
        cdb_in.branch_mask = 4'b0100;
        cdb_in.squash_enable = 1;
        @(negedge clock);
        cdb_in = 0;
        dispatch_in = 0;

        $display("Squashing instructions with the wrong branch tag: DONE"); // should do nothing

        reset_rs();

        $display("Dispatching incomplete instructions with the same branch tag");
        for (int i = 0; i < `RS_SIZE; i++) begin
            @(negedge clock);
            dispatch_in.valid = 1;
            T_used(1,1,1);
            set_tags(i,i,3);
            if (i % `PHYS_REGFILE_SIZE == 0) begin
                dispatch_in.T1 = 1;
                dispatch_in.T2 = 3;
                dispatch_in.T = 1;
            end
            Tr(1,0);
            if (i%2)
                dispatch_in.branch_tag = 4'b0010;
            else
                dispatch_in.branch_tag = 4'b0100;
        end
        $display("Completing everything at the same time");
        @(negedge clock);
        cdb_in.valid = 1;
        cdb_in.T_used = 1;
        cdb_in.cdb_tag = 3;
        @(negedge clock);
        cdb_in = 0;
        $display("Squashing instructions with half right half wrong");
        // also tests that the incoming dispatch is squashed and not input into the RS
        @(negedge clock);
        cdb_in.valid = 1;
        cdb_in.branch_mask = 4'b0100;
        cdb_in.squash_enable = 1;
        @(negedge clock);
        cdb_in = 0;
        dispatch_in = 0;

        $display("Squashing instructions with half right half wrong: DONE"); // should do nothing


        // Dispatch something that's ready and squash it when it tries to issue

        // Random testing - dum dum style
        reset_rs();
        $display("Begin completely dum-dum random testing");
        for (int i = 0; i < 1000; i++) begin
            @(negedge clock);
            cdb_in = $random;
            dispatch_in = $random;
        end

        `ifdef FINISH_ON_ERROR
            $display("PASSED!");
        `endif
        $finish;
    end
    */
endmodule
`endif