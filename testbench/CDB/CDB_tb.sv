`ifndef _CDB_TB__
`define _CDB_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"

 `define FINISH_ON_ERROR

    /** Test cases to write: 
        - [DONE] adding 0-3 entries and checking timing of output
          -- no squashing

        - [DONE] adding inst at head & nothing afterward for several cycles
          -- available should become 0

        - [DONE] adding inst at head then inst in following cycle
          -- available should not become 0

        - [DONE] adding squash inst at head & 2 dependent insts in same cycle
          -- in next cycle, head broadcasts and dependent insts are squashed
          -- available_next = 0
        
        - [DONE] adding squash inst at head & 2 dependent insts in next cycle
          -- this will *not* be tested because it cannot happen
          -- head broadcasts to EX, which will squash the incoming
             dependent instruction

        - [DONE] adding squash inst not at head & 2 dependent insts in same cycle
          -- if head enters in cycle N, becomes head in cycle N+1
          -- dependent inst enters in cycle N, squashed in cycle N+1
        
        - [DONE] adding squash inst not at head & dependent insts in next cycle
          -- if head enters in cycle N, becomes head in cycle N+1
          -- dependent inst enters in cycle N+1, squashed in cycle N+1
                
        - [DONE] adding squash inst not at head & 1 dependent and 1 independent
          inst in same cycle
          -- leads to fragmented buffer (depending upon which instruction squashed)
          -- more instructions at once

        - [DONE] adding squash inst not at head & 1 dependent and 1 independent
          inst in next cycle
          -- leads to fragmented buffer (depending upon which instruction squashed)
          -- fewer instructions at once

    */

module CDB_tb;
    logic            clock;            // CLOCK
    logic            reset;            // Synchronous reset/clear the ROB
    
    EX_PACKET        alu_packet;
    EX_PACKET        load_packet;
    EX_PACKET        mul_packet;
    
    CDB_PACKET       cdb;               // Input from CDB for complete and branch recovery (e.g. T/NT)
    CDB_IDX          head_ptr_out;      // Debug Head pointer output from CDB buffer    
    CDB_IDX          tail_ptr_out;      // Debug Tail pointer output from CDB buffer
    logic            available;         // Is there something in the CDB?
    logic            full;
    logic [`CDB_SIZE-1:0] buff_valids;
    logic            dont_check_counter;

    CDB buff_dut (
        .clock(clock),
        .reset(reset),
        .buff_valids(buff_valids),
        .cdb(cdb),
        .alu_packet(alu_packet),
        .load_packet(load_packet),
        .mul_packet(mul_packet),
        .head_ptr(head_ptr_out),
        .tail_ptr(tail_ptr_out),
        .available(available),
        .full(full)
    );

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("---available: %b. full: %b", available, full);
        $display("---available: %b", available);
        if (dont_check_counter)
            $display("allocated size: %h", allocated_size);
        else
            $display("allocated size: %h, Entry counter: %h", allocated_size, entry_counter);

        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    function check_packets(
        string signal,
        EX_PACKET in_packet,
        PHYS_REG_TAG next_cdb_tag,
        CDB_PACKET cdb_out,
        logic expected_valid
    );
        logic exit;
        
        if (~(cdb_out.valid == expected_valid)) begin
            $display("%s TESTCASE FAILED @ time %4.0f: valid caused failure. expected: %h  actual: %h",
                signal, $time, expected_valid, cdb_out.valid);
            exit = 1;
        end
        // status bits
        if (cdb_out.full) begin
            $display("%s TESTCASE FAILED @ time %4.0f: full caused failure. expected: %h  actual: %h",
                signal, $time, 0, cdb_out.full);
            exit = 1;
        end
       
        // if expecting invalid entry, don't need to check the data contents
        if (expected_valid) begin
     
            // data
            if (~(cdb_out.head_data == in_packet.data)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: head_data caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.data, cdb_out.head_data);
                exit = 1;
            end
            // tags
            if (~(cdb_out.cdb_tag == in_packet.tag)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: tag caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.tag, cdb_out.cdb_tag);
                exit = 1;
            end

            if (~(cdb_out.cdb_arch_tag == in_packet.arch_tag)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: arch_tag caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.arch_tag, cdb_out.cdb_arch_tag);
                exit = 1;
            end

            if (~(cdb_out.T_used == in_packet.T_used)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: T_used caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.T_used, cdb_out.T_used);
                exit = 1;
            end

            if (~(cdb_out.rob_idx == in_packet.rob_idx)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: rob_idx caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.rob_idx, cdb_out.rob_idx);
                exit = 1;
            end
            
            if (~(cdb_out.next_cdb_tag == next_cdb_tag)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: next_cdb_tag caused failure. expected: %h  actual: %h",
                    signal, $time, next_cdb_tag, cdb_out.next_cdb_tag);
                exit = 1;
            end

            // branching info
            if (~(cdb_out.squash_enable == in_packet.squash_enable)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: squash caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.squash_enable, cdb_out.squash_enable);
                exit = 1;
            end

            if (~(cdb_out.branch_mask == in_packet.branch_mask)) begin
                $display("%s TESTCASE FAILED @ time %4.0f: branch mask caused failure. expected: %h  actual: %h",
                    signal, $time, in_packet.branch_mask, cdb_out.branch_mask);
                exit = 1;
            end
        end

        `ifdef FINISH_ON_ERROR
            if (exit) begin
                $display("");
                $finish;
            end
        `endif

    endfunction

    int entry_counter, entry_counter_next;
    int entry_counter_inc, entry_counter_dec;
    int num_input_valid;
    int allocated_size;

    always_comb begin
        allocated_size = (tail_ptr_out < head_ptr_out)  ? 
            (`CDB_SIZE + tail_ptr_out - head_ptr_out) : 
            (tail_ptr_out - head_ptr_out);

        num_input_valid = alu_packet.valid + load_packet.valid + mul_packet.valid;
        entry_counter_inc  = full ? 0 : num_input_valid;
        entry_counter_inc  = num_input_valid;
        entry_counter_dec  = (cdb.valid && available) ? 1 : 0;
        entry_counter_next = (~available) ? entry_counter_inc : entry_counter + entry_counter_inc - entry_counter_dec;
    end

    always begin
        #5 clock = ~clock;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            entry_counter <= `SD 0;
        end
        else begin
            entry_counter <= `SD entry_counter_next;

            // Full cases - delete these if zero toggle on full signal
            if(entry_counter != `CDB_SIZE && full)
                fail("full", 0);
            if(entry_counter == `CDB_SIZE && ~full)
                fail("full", 1);
            
            
            // Available test cases - don't run with squash-enabled
            if (~dont_check_counter) begin
                if(entry_counter == 0 && available)
                    fail("available", 0); 
                if(entry_counter != 0 && ~available)
                    fail("available", 1);

                //Entry counter test
                if(allocated_size !== entry_counter)
                    fail("allocated size", entry_counter);
            end

        end
    end

    logic [2:0] valid_bits;
    assign alu_packet.valid = valid_bits[2];
    assign load_packet.valid = valid_bits[1];
    assign mul_packet.valid = valid_bits[0];

    task set_valid_and_wait(
        input [2:0] bits
    );
        @(negedge clock);
        valid_bits = bits;
        @(posedge clock);
        #2;
    endtask
    
    task squash_size_check(
        input int expected_alloc_size,
        input logic expected_available
    );
        if (expected_alloc_size != allocated_size)
            fail("allocated size", expected_alloc_size);
        if (expected_available != available)
            fail("available", 0);
    endtask
    
    initial begin
        $dumpvars;
        // $monitor("Time:%4.0f clk:%b alu:%b  ld:%b  mul:%b  cdb:%b  buff_valids:%b  head:%h  tail:%h  av:%h  ECI:%h  ECD:%h  EC:%h  sqe:%h", 
        //     signal, $time, clock, alu_packet.valid, load_packet.valid, mul_packet.valid, cdb.valid, buff_valids,
        //     head_ptr_out, tail_ptr_out, available, entry_counter_inc, entry_counter_dec, entry_counter, cdb.squash_enable);

        $monitor("Time:%4.0f  alu:%b  ld:%b  mul:%b  cdb:%b  head:%2d  tail:%2d  av:%h  ECI:%1d  ECD:%1d  EC:%1d  sqe:%h", 
            $time, alu_packet.valid, load_packet.valid, mul_packet.valid, cdb.valid,
            head_ptr_out, tail_ptr_out, available, entry_counter_inc, entry_counter_dec, entry_counter, cdb.squash_enable);

        dont_check_counter = 0;
        clock    = 0;
        @(negedge clock);
        reset    = 1;
        @(negedge clock);
        reset = 0;

        // constants for first few test cases
        alu_packet.data = 32'h0;
        alu_packet.tag = 13;
        alu_packet.arch_tag = 13;
        alu_packet.T_used = 1;
        alu_packet.rob_idx = 13;
        alu_packet.squash_enable = 0;
        alu_packet.branch_mask = 8'b10000000;
        alu_packet.branch_tag = 0;

        load_packet.data = 32'h1;
        load_packet.tag = 14;
        load_packet.arch_tag = 14;
        load_packet.T_used = 1;
        load_packet.rob_idx = 14;
        load_packet.squash_enable = 0;
        load_packet.branch_mask = 0;
        load_packet.branch_tag = 8'b10000000;

        mul_packet.data = 32'h2;
        mul_packet.tag = 15;
        mul_packet.arch_tag = 15;
        mul_packet.T_used = 1;
        mul_packet.rob_idx = 15;
        mul_packet.squash_enable = 0;
        mul_packet.branch_mask = 0;
        mul_packet.branch_tag = 8'b10000000;

        // initialize to all zeros
        valid_bits = 3'b000;

        /* adding 0-3 entries */

        // test 0: nothing should be on CDB
        set_valid_and_wait(3'b000);
        check_packets("test 0", alu_packet, 0, cdb, 0);

        // test 1: ALU onlu
        set_valid_and_wait(3'b100);
        check_packets("test 1", alu_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000); 
        check_packets("test 1", alu_packet, 0, cdb, 0);  // check that cdb is now invalid

        // test 2: LD only
        set_valid_and_wait(3'b010);
        check_packets("test 2", load_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 2", load_packet, 0, cdb, 0);

        // test 3: MUL only
        set_valid_and_wait(3'b001);
        check_packets("mul only", mul_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("mul only", mul_packet, 0, cdb, 0);

        // test 4: ALU and LD
        set_valid_and_wait(3'b110);
        check_packets("test 4", alu_packet, load_packet.tag, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 4", load_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);         // invoke with 000 to exploit the task's delay
        check_packets("test 4", load_packet, 0, cdb, 0);

        // test 5: ALU and MUL
        set_valid_and_wait(3'b101);
        check_packets("test 5", alu_packet, mul_packet.tag, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 5", mul_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 5", mul_packet, 0, cdb, 0);

        // test 6: LD and MUL
        set_valid_and_wait(3'b011);
        check_packets("test 6", load_packet, mul_packet.tag, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 6", mul_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 6", mul_packet, 0, cdb, 0);

        // test 6: ALU and LD and MUL
        set_valid_and_wait(3'b111);
        check_packets("test 7", alu_packet, load_packet.tag, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 7", load_packet, mul_packet.tag, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 7", mul_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);
        check_packets("test 7", mul_packet, 0, cdb, 0);

        /* MISCELLANEOUS TEST */
        set_valid_and_wait(3'b100);
        check_packets("test 8", alu_packet, 0, cdb, 1);
        set_valid_and_wait(3'b001);
        check_packets("test 8", mul_packet, 0, cdb, 1);
        set_valid_and_wait(3'b000);
        
        /* SQUASH TESTS */
        dont_check_counter = 1;
        alu_packet.squash_enable = 1;
        
        // add all 3 at same time, LD and MUL are dependent
        set_valid_and_wait(3'b111);        
        squash_size_check(3, 1);  // expected_alloc_size = 3, expected_available = 1
        check_packets("test 9", alu_packet, 0, cdb, 1);
        
        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);
        check_packets("test 9", load_packet, 0, cdb, 0);
        
        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);
        check_packets("test 9", mul_packet, 0, cdb, 0);
        
        
        // add 3, none squashing, then add squashing + dependent LD and MUL in next cycle
        alu_packet.squash_enable = 0;

        set_valid_and_wait(3'b111);
        squash_size_check(3, 1);
        check_packets("test 10", alu_packet, load_packet.tag, cdb, 1);
        
        alu_packet.squash_enable = 1;
        
        set_valid_and_wait(3'b111);
        squash_size_check(5, 1);
        check_packets("test 10", load_packet, mul_packet.tag, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(4, 1);
        check_packets("test 10", mul_packet, alu_packet.tag, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(3, 1);
        check_packets("test 10", alu_packet, 0, cdb, 1);
        
        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);
        check_packets("test 10", alu_packet, 0, cdb, 0);

        // add 3, none squashing, then add squashing in next cycle, then 2 dependent (LD and MUL) in following cycle
        alu_packet.squash_enable = 0;

        set_valid_and_wait(3'b111);
        squash_size_check(3, 1);
        check_packets("test 11", alu_packet, load_packet.tag, cdb, 1);
        
        alu_packet.squash_enable = 1;
        
        set_valid_and_wait(3'b100);
        squash_size_check(3, 1);
        check_packets("test 11", load_packet, mul_packet.tag, cdb, 1);

        set_valid_and_wait(3'b011);
        squash_size_check(4, 1);
        check_packets("test 11", mul_packet, alu_packet.tag, cdb, 1);
        
        set_valid_and_wait(3'b000);
        squash_size_check(3, 1);
        check_packets("test 11", alu_packet, 0, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);
        check_packets("test 11", alu_packet, 0, cdb, 0);

        // add 3, none squashing, then add squashing + 1 dependent LD + 1 independent MUL in same cycle
        alu_packet.squash_enable = 0;

        set_valid_and_wait(3'b111);
        squash_size_check(3, 1);
        check_packets("test 12a", alu_packet, load_packet.tag, cdb, 1);
        
        alu_packet.squash_enable = 1;
        mul_packet.branch_tag = 0;  // mul won't be squashed

        set_valid_and_wait(3'b111);
        squash_size_check(5, 1);
        check_packets("test 12a", load_packet, mul_packet.tag, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(4, 1);
        check_packets("test 12a", mul_packet, alu_packet.tag, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(3, 1);
        check_packets("test 12a", alu_packet, 0, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(2, 1);
        check_packets("test 12a", load_packet, mul_packet.tag, cdb, 0); // load squashed, but still broadcast next tag

        set_valid_and_wait(3'b000);
        squash_size_check(1, 1);
        check_packets("test 12a", mul_packet, 0, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);
        check_packets("test 12a", mul_packet, 0, cdb, 0);

        // add 3, none squashing, then add squashing + 1 independent LD + 1 dependent MUL in same cycle
        alu_packet.squash_enable = 0;

        set_valid_and_wait(3'b111);
        squash_size_check(3, 1);
        check_packets("test 12b", alu_packet, load_packet.tag, cdb, 1);
        
        alu_packet.squash_enable = 1;
        mul_packet.branch_tag = 8'b10000000;
        load_packet.branch_tag = 0;  // load won't be squashed

        // $display("test1");
        set_valid_and_wait(3'b111);
        // $display("exp_ntag %h", mul_packet.tag);
        // $display("cdb_ntag %h", cdb.next_cdb_tag);
        squash_size_check(5, 1);
        check_packets("test 12b", load_packet, mul_packet.tag, cdb, 1);

        // $display("test2");
        set_valid_and_wait(3'b000);
        // $display("exp_ntag %h", alu_packet.tag);
        // $display("cdb_ntag %h", cdb.next_cdb_tag);
        
        squash_size_check(4, 1);
        check_packets("test 12b", mul_packet, alu_packet.tag, cdb, 1);

        // $display("test3");
        set_valid_and_wait(3'b000);
        squash_size_check(3, 1);
        check_packets("test 12b", alu_packet, load_packet.tag, cdb, 1);
        
        // $display("test4");
        set_valid_and_wait(3'b000);
        squash_size_check(2, 1);
        check_packets("test 12b", load_packet, 0, cdb, 1);

        // since MUL is last and got squashed, head == tail
        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);   // straight to empty since last instruction invalid
        check_packets("test 12b", mul_packet, 0, cdb, 0);
 
        // add 3, none squashing, then add squashing in next cycle, then 1 dependent LD + 1 independent MUL in following cycle
        alu_packet.squash_enable = 0;

        set_valid_and_wait(3'b111);
        squash_size_check(3, 1);
        check_packets("test 13a", alu_packet, load_packet.tag, cdb, 1);
        
        alu_packet.squash_enable = 1;
        load_packet.branch_tag = 8'b10000000;
        mul_packet.branch_tag = 0;  // mul won't be squashed

        set_valid_and_wait(3'b100);
        squash_size_check(3, 1);
        check_packets("test 13a", load_packet, mul_packet.tag, cdb, 1);

        set_valid_and_wait(3'b011);
        squash_size_check(4, 1);
        check_packets("test 13a", mul_packet, alu_packet.tag, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(3, 1);
        check_packets("test 13a", alu_packet, 0, cdb, 1);
        
        // Fragmentation
        set_valid_and_wait(3'b000);
        squash_size_check(2, 1);
        check_packets("test 13a", load_packet, mul_packet.tag, cdb, 0); // load squashed but still broadcast mul tag

        set_valid_and_wait(3'b000);
        squash_size_check(1, 1);
        check_packets("test 13a", mul_packet, 0, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);
        check_packets("test 13a", mul_packet, 0, cdb, 0);


        // add 3, none squashing, then add squashing in next cycle, then 1 independent LD + 1 dependent MUL in following cycle
        alu_packet.squash_enable = 0;

        set_valid_and_wait(3'b111);
        squash_size_check(3, 1);
        check_packets("test 13b", alu_packet, load_packet.tag, cdb, 1);
        
        alu_packet.squash_enable = 1;
        mul_packet.branch_tag = 8'b10000000;
        load_packet.branch_tag = 0;  // load won't be squashed

        set_valid_and_wait(3'b100);
        squash_size_check(3, 1);
        check_packets("test 13b", load_packet, mul_packet.tag, cdb, 1);

        set_valid_and_wait(3'b011);
        squash_size_check(4, 1);
        check_packets("test 13b", mul_packet, alu_packet.tag, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(3, 1);
        check_packets("test 13b", alu_packet, load_packet.tag, cdb, 1);
        
        set_valid_and_wait(3'b000);
        squash_size_check(2, 1);
        check_packets("test 13b", load_packet, 0, cdb, 1);

        set_valid_and_wait(3'b000);
        squash_size_check(0, 0);   // straight to empty since last instruction invalid
        check_packets("test 13b", mul_packet, 0, cdb, 0);

        /* Other (likely redundant) test cases

        - fill up buffer halfway, squash half the entries, adding in entries in next cycle
          -- available_next = 1
        - fill up buffer halfway, squash half the entries, adding no entries in next cycle
          -- available_next = 1
        - fill up buffer halfway, squash all entries, adding in entries in next cycle
          -- available_next = 1
        - fill up buffer halfway, squash all entries, adding no entries in next cycle
          -- available_next = 0
        
        */

        $finish;
    end
endmodule
`endif