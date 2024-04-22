`ifndef _ROB_TB__
`define _ROB_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/ROB.sv"

`define FINISH_ON_ERROR

module ROB_tb;
    logic            clock;            // CLOCK
    logic            reset;            // Synchronous reset/clear the ROB
    logic            stall;            // Stall the ROB 
    
    //Dispatch stage
    logic            dispatch_valid;     // Valid dispatch
    PHYS_REG_TAG     T_in, Told_in;      // T for tag from free list/dispatch, Told for free list
    ARCH_REG_TAG     dest_reg;           // Dest reg for indexing the arch map table
    ROB_PACKET       rob_packet_in;
        
    //Complete stage
    CDB_PACKET       cdb_in;             // Input from CDB for complete and branch recovery (e.g. T/NT)
    
    ROB_IDX          head_ptr_out;       // Debug Head pointer output from ROB
    ROB_ENTRY        head_packet;        // Head tag and dest info so Retire stage can free phyiscal registers
    ROB_IDX          tail_ptr_out;       // Tail pointer out for branch checkpointing
    ROB_ENTRY        tail_packet;        // Tail tag and dest info for branch checkpointing
    logic            full;               // Are we at capacity?
    logic            available;          // Is there something in the ROB?

    ROB rob_tb (
        .clock(clock),
        .reset(reset),
        //.stall(stall),
        .rob_packet_in(rob_packet_in),
        .cdb_in(cdb_in),
        .head_ptr_out(head_ptr_out),
        .head_packet(head_packet),
        .tail_ptr_out(tail_ptr_out),
        .tail_packet(tail_packet),
        .full(full),
        .available(available)
    );

    integer entry_counter;
    integer entry_counter_next = 0;
    integer entry_counter_dec = 0;
    integer entry_counter_inc = 0;
    ROB_IDX current_size  = 0;
    ROB_IDX temp_idx      = 0;
    int     j             = 0;
    assign rob_packet_in = { T_in, Told_in, dest_reg, dispatch_valid};

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("---Head ptr: %h. Tail ptr: %h", head_ptr_out, tail_ptr_out);
        $display("---available: %b. full: %b", available, full);
        $display("Current size: %h, Entry counter: %h", current_size, entry_counter);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction


    task add_entry(
        input PHYS_REG_TAG _T_in,
        input PHYS_REG_TAG _Told_in,
        input ARCH_REG_TAG _dest_reg 
    );
        T_in     = _T_in;
        Told_in  = _Told_in;
        dest_reg = _dest_reg;

        dispatch_valid = 1;
        @(negedge clock);

        dispatch_valid = 0;

        @(negedge clock);
    endtask

    task complete_entry(
        input ROB_IDX complete_idx
    );
        cdb_in.valid = 1;
        cdb_in.rob_idx = complete_idx;      
        @(negedge clock);

        cdb_in.valid = 0;
        
        @(negedge clock);
    endtask

    task complete_and_add(
        input ROB_IDX complete_idx,
        input PHYS_REG_TAG _T_in,
        input PHYS_REG_TAG _Told_in,
        input ARCH_REG_TAG _dest_reg 
    );
        T_in     = _T_in;
        Told_in  = _Told_in;
        dest_reg = _dest_reg;

        cdb_in.valid = 1;
        cdb_in.rob_idx = complete_idx; 
        @(negedge clock);
        cdb_in.valid = 0;
        dispatch_valid = 1;
        @(negedge clock);

        dispatch_valid = 0;
        
        @(negedge clock);
    endtask

    task squash_to_entry(
        input ROB_IDX rob_idx
    );
        cdb_in.valid = 1;
        cdb_in.rob_idx = rob_idx;
        cdb_in.squash_enable = 1;
        @(negedge clock);

        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;

        @(negedge clock);
    endtask

    always begin
        #5 clock = ~clock;
    end
    
    always_comb begin
        current_size = (tail_ptr_out < head_ptr_out)  ? 
            (`ROB_SIZE + tail_ptr_out - head_ptr_out) : 
            (tail_ptr_out - head_ptr_out);

        entry_counter_inc  = (dispatch_valid && (!full || head_packet.complete)) ? 1 : 0;
        entry_counter_dec  = (head_packet.complete && available) ? 1 : 0;
        entry_counter_next = (cdb_in.squash_enable) ? (cdb_in.rob_idx + 1 - head_ptr_out - entry_counter_dec) :
                             entry_counter + entry_counter_inc - entry_counter_dec;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            entry_counter <= `SD 0;
        end
        else
            if(entry_counter !== `ROB_SIZE && full)
                fail("full", 0);
            if(entry_counter === `ROB_SIZE && ~full)
                fail("full", 1);
            if(entry_counter == 0 && available)
                fail("available", 0); 
            if(entry_counter != 0 && ~available)
                fail("available", 1);
            if(((current_size !== entry_counter) && ~full) || 
              (tail_ptr_out - head_ptr_out !== 0 &&  full))
                fail("size", entry_counter);

            entry_counter <= `SD entry_counter_next;
    end

    initial begin
        $monitor("Time:%4.0f dispatch valid:%b head:%h tail:%h ECI:%h ECD:%h EC:%h av:%h sqi:%h sqe:%h", 
            $time, dispatch_valid, head_ptr_out, tail_ptr_out, entry_counter_inc, entry_counter_dec, 
            entry_counter, rob_tb.available_next, cdb_in.rob_idx, cdb_in.squash_enable);
        clock    = 0;
        @(negedge clock);
        reset    = 1;
        stall    = 0;
        T_in     = 0;
        Told_in  = 0;
        dest_reg = 0;
        cdb_in   = 0;
        dispatch_valid = 0;
        @(negedge clock);
        reset = 0;

        /////////////////////////////////////////////////////////////////////////
        // Fill the ROB, then empty it                                         //
        /////////////////////////////////////////////////////////////////////////
        
        $display("Filling the ROB");
        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly fill the ROB
            add_entry(i, i, i);
            $display("Tag at tail packet: %h", tail_packet.d_tag);
        end
        $display("Filling the ROB: DONE");

        $display("Trying to add entry while full");
        add_entry(69, 69, 69);      // should do nothing
        $display("Trying to add entry while full: DONE");

        $display("Emptying the ROB");
        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly empty the ROB - top down
            complete_entry(head_ptr_out);
        end
        $display("Emptying the ROB: DONE");

        /////////////////////////////////////////////////////////////////////////
        // fill the ROB and complete every other from back to front, then wait //
        /////////////////////////////////////////////////////////////////////////

        complete_entry(head_ptr_out);   // should do nothing

        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly fill the ROB
            add_entry(i, i, i);
        end

        add_entry(69, 69, 69);      // should do nothing
        $display("Starting OoO empty");
        for (int i = `ROB_SIZE-1; i >= 0; i--) begin // exactly empty the ROB
            if (i%2 == 0) 
                complete_entry(i);
        end
        for (int i = `ROB_SIZE-1; i >= 0; i--) begin // exactly empty the ROB
            if (i%2 == 1) 
                complete_entry(i);
        end

        wait(available == 0);

        $display("Starting OoO empty: DONE");

        /////////////////////////////////////////////////////////////////////////
        // fill the ROB and then retire and insert simultaneously              //
        /////////////////////////////////////////////////////////////////////////

        complete_entry(head_ptr_out);   // should do nothing

        $display("Filling the ROB");
        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly fill the ROB
            add_entry(i, i, i);
        end
        $display("Filling the ROB: DONE");

        add_entry(69, 69, 69);      // should do nothing
        
        $display("Retiring and adding to the ROB simultaneously");
        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly empty the ROB
                complete_and_add(head_ptr_out, i, i, i);
        end
        $display("Retiring and adding to the ROB simultaneously: DONE");
        
        $display("Emptying the ROB");
        while(available) begin
            complete_entry(head_ptr_out);
        end
        $display("Emptying the ROB: DONE");

        ///////////////////////////////////////////////////////////////////////////
        // Dispatch & Retire simultaneously on non-full ROB (walk the ROB on em) //
        ///////////////////////////////////////////////////////////////////////////

        $display("Seeding the ROB");
        add_entry(69, 69, 69);
        
        $display("Retiring and adding to the ROB simultaneously");
        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly empty the ROB
                complete_and_add(head_ptr_out, i, i, i);
        end
        $display("Retiring and adding to the ROB simultaneously: DONE");
        
        $display("Emptying the ROB");
        while(available) begin
            complete_entry(head_ptr_out);
        end
        $display("Emptying the ROB: DONE");


        $display("Starting OoO empty: DONE");

        /////////////////////////////////////////////////////////////////////////
        // Fill the ROB, then squash to a specific index                       //
        /////////////////////////////////////////////////////////////////////////

        $display("Running Squash Test");
        for (int i = 0; i < `ROB_SIZE; i++) begin // exactly fill the ROB
            add_entry(i, i, i);
        end

        $display("ROB exactly filled");

        squash_to_entry(12);    // Squash to tail_idx = 13
        
        $display("Squashed");

        while(available) begin // exactly empty the ROB - top down
            complete_entry(head_ptr_out);
        end

        $display("Squash Test: DONE");

        /////////////////////////////////////////////////////////////////////////
        // Dispatch and Squash at the same time. Should only squash.           //
        /////////////////////////////////////////////////////////////////////////

        $display("Running Dispatch + Squash");

        for (int i = 0; i < `ROB_SIZE / 2; i++) begin 
            add_entry(i, i, i);
        end
        $display("ROB half filled");

        // Request a dispatch
        T_in     = 0;
        Told_in  = 0;
        dest_reg = 0;
        dispatch_valid = 1;
        // Request a squash on the CDB
        cdb_in.valid = 1;
        cdb_in.rob_idx = 13;
        cdb_in.squash_enable = 1;
        
        // Result should be a squash
        // entry_counter = (13 + 1 - head_ptr_out) = 1;
        @(negedge clock);
        
        $display("Squash done on index 13");
        
        dispatch_valid = 0;
        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;
        @(negedge clock);

        /////////////////////////////////////////////////////////////////////////
        // Squash and Retire at the same time. Should do both.                 //
        /////////////////////////////////////////////////////////////////////////

        while(available) begin
            complete_entry(head_ptr_out);
        end
        
        $display("Running Squash + Retire");

        // fill out the entire ROB
        for (int i = 0; i < `ROB_SIZE; i++) begin 
            add_entry(i, i, i);
        end
        $display("ROB filled, head = tail = 14");
        
        $display("Completing head");
        // complete an instruction
        cdb_in.valid = 1;
        cdb_in.rob_idx = head_ptr_out;
      
        @(negedge clock);
        
        /* 
         * in next clock cycle:
         * not dispatching instruction
         * head of ROB retires
         * squashing from index 20
         * num_entries = 6 (7 remain - 1 retired)
         */

        $display("Squashing");
        // no dispatch
        dispatch_valid = 0;

        // Squash index 20, only inds 15-20 remain
        cdb_in.valid = 1;
        cdb_in.rob_idx = 20;
        cdb_in.squash_enable = 1;
        
        @(negedge clock);
        
        $display("Squash done on index 20");
        
        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;
        @(negedge clock);

        /////////////////////////////////////////////////////////////////////////
        // Dispatch, Squash, and Retire. Should do only retire and squash.     //
        /////////////////////////////////////////////////////////////////////////

        while(available) begin
            complete_entry(head_ptr_out);
        end
        
        $display("Running Dispatch + Squash + Retire");

        // fill out the entire ROB
        for (int i = 0; i < `ROB_SIZE; i++) begin 
            add_entry(i, i, i);
        end
        $display("ROB filled, head = tail = 21");
        
        $display("Completing head");
        // complete an instruction
        cdb_in.valid = 1;
        cdb_in.rob_idx = head_ptr_out;
      
        @(negedge clock);
        
        /* 
         * in next clock cycle:
         * dispatching an instruction
         * head of ROB retires
         * squashing from index 28
         * num_entries = 7 (8 remain - 1 retired + 0 dispatched)
         */
        
        $display("Attempt a Dispatch");
        // dispatch
        T_in     = 13;
        Told_in  = 13;
        dest_reg = 13;
        dispatch_valid = 1;

        $display("Squashing");
        // Squash index 28, only inds 22-28 remain
        cdb_in.valid = 1;
        cdb_in.rob_idx = 28;
        cdb_in.squash_enable = 1;
        
        @(negedge clock);
        
        $display("Squash done on index 28");
        
        dispatch_valid = 0;
        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;
        @(negedge clock);

        // Leave this section commented, the testbench should work
        // even with residual data from prior runs
        // uncommenting should still pass

        // while(available) begin
        //     complete_entry(head_ptr_out);
        // end

        /////////////////////////////////////////////////////////////////////////
        // DESTINED_TO_FAIL Case --> squashing the tail pointer with 1 entry   //
        /////////////////////////////////////////////////////////////////////////

        // while(available) begin
        //     complete_entry(head_ptr_out);
        // end
        
        // $display("Running Squash + Retire");

        // // fill out the entire ROB
        // add_entry(13, 13, 13);
        // $display("just 1 entry");
        
        // $display("Completing head");
        // // complete an instruction
        // cdb_in.valid = 1;
        // cdb_in.rob_idx = head_ptr_out;
      
        // @(negedge clock);     

        // $display("Squashing");

        // // Squash index head
        // cdb_in.valid = 1;
        // cdb_in.rob_idx = tail_ptr_out;
        // cdb_in.squash_enable = 1;
        
        // @(negedge clock);
        
        // $display("Squash done at head");
        
        // cdb_in.valid = 0;
        // cdb_in.squash_enable = 0;
        // @(negedge clock);


        /////////////////////////////////////////////////////////////////////////
        //                              RANDOM TESTING                         //
        /////////////////////////////////////////////////////////////////////////
        $display("Random testing");
        for (int i = 0; i < 10000; i++) begin
            temp_idx = $random;
            j = $random;
            if (j % 3 == 0) begin // add element
                add_entry(i, j, j);
            end
            else if (j % 3 == 1) begin // complete random element (if within range)
                if (temp_idx - head_ptr_out <= entry_counter && available)
                    complete_entry(temp_idx);
            end
            else begin // squash to random element (if within range)
                if (temp_idx - head_ptr_out < entry_counter && available) begin
                    cdb_in.valid = 1;
                    cdb_in.squash_enable = 1;
                    cdb_in.rob_idx = temp_idx;
                    @(negedge clock);
                    cdb_in.valid = 0;
                    cdb_in.squash_enable = 0;
                    @(negedge clock);
                end
            end

        end
        $display("Random testing: DONE");

        `ifdef FINISH_ON_ERROR
            $display("PASSED!");
        `endif
        $finish;
    end
endmodule
`endif