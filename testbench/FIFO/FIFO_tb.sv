`ifndef FIFO_SIZE
`define FIFO_SIZE 32
`endif

`ifndef DATA_TYPE
`define DATA_TYPE PHYS_REG_TAG
`endif

`ifndef _FIFO_TB__
`define _FIFO_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/FIFO.sv"

`define FINISH_ON_ERROR

module FIFO_tb;
    logic                                 clock;                // CLOCK
    logic                                 reset;                // Synchronous reset/clear the FIFO
    
    logic                                 checkpoint_enable;        // enables squashes/resetting tail_ptr to an index
    logic [$clog2(`FIFO_SIZE)-1:0]        checkpoint_head_ptr_in;   // use if you want to overwrite the entire FIFO to a checkpoint. Used when squash_mode = 1'b1

    logic                                 enqueue; // Valid dispatch
    `DATA_TYPE                            data_in; // T for tag from free list/dispatch, Told for free list
    logic                                 dequeue; // Dest reg for indexing the arch map table
    
    logic [$clog2(`FIFO_SIZE)-1:0]        head_ptr_out;
    logic [$clog2(`FIFO_SIZE)-1:0]        tail_ptr_out;
    logic                                 available;
     `DATA_TYPE [`FIFO_SIZE-1:0]          FIFO_debug_out; // For DVE

    `DATA_TYPE                            head_packet;
    logic                                 full;
    logic [$clog2(`FIFO_SIZE)-1:0]        checkpoint_head_ptr_out;

    FIFO #(
        .DATA_TYPE(`DATA_TYPE), 
        .FIFO_DEPTH(`FIFO_SIZE), 
        .INIT_AVAILABLE(1)
    ) test_fifo (
        // Inputs
        .clock(clock),
        .reset(reset),
        .checkpoint_enable(checkpoint_enable),
        .checkpoint_head_ptr_in(checkpoint_head_ptr_in),
        .enqueue(enqueue),
        .data_in(data_in),
        .dequeue(dequeue),
        
        // Debug Outputs
        .head_ptr_out(head_ptr_out),
        .tail_ptr_out(tail_ptr_out),
        .available(available),
        .FIFO_debug_out(FIFO_debug_out),

        // Normal Outputs
        .head_packet(head_packet),
        .full(full),
        .checkpoint_head_ptr_out(checkpoint_head_ptr_out)
    );

    // Variables for testbench to track the state of the freelist
    integer entry_counter;
    integer entry_counter_next;
    integer entry_counter_dec;
    integer entry_counter_inc;
    logic   entry_checkpoint_signal; // Signal to checkpoint counter next MUX
    integer entry_counter_checkpoint;
    integer entry_counter_checkpoint_next;
    logic [$clog2(`FIFO_SIZE)-1:0] current_size;

    // Checkpoint data registers to be used by TB. Written to by task save_checkpoint()
    logic [$clog2(`FIFO_SIZE)-1:0]        checkpoint_head_ptr;

    // Random test signals
    logic      random_enqueue_valid;
    `DATA_TYPE random_data_added;
    logic      random_dequeue_valid;
    logic      random_squash_valid;
    logic      random_checkpoint_write;

    ////////////////////////////////////////////////////////////////////////
    // TASK DEFINITIONS                                                   //
    ////////////////////////////////////////////////////////////////////////

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

    task save_checkpoint_event(
        input logic enqueue_valid,
        input `DATA_TYPE data_added,
        input logic dequeue_valid
    );
        // Create enqueue event
        enqueue = enqueue_valid;
        data_in = data_added;

        // Create dequeue event
        dequeue = dequeue_valid;

        // Asynchronously read checkpoint data
        // Allow combinational logic to propogate
        `SD checkpoint_head_ptr = checkpoint_head_ptr_out;
        entry_checkpoint_signal = 1;

        @(negedge clock);

        // Clear inputs
        enqueue = 0;
        dequeue = 0;
        entry_checkpoint_signal = 0;

        @(negedge clock);
    endtask

    task insert_event(
        input logic enqueue_valid,
        input `DATA_TYPE data_added,
        input logic dequeue_valid,
        input logic squash_valid
    );
        // Create enqueue event
        enqueue = enqueue_valid;
        data_in = data_added;

        // Create dequeue event
        dequeue = dequeue_valid;

        // Create squash event
	    checkpoint_enable = squash_valid;
	    checkpoint_head_ptr_in = checkpoint_head_ptr;

        @(negedge clock);

        enqueue = 0;
        dequeue = 0;
        checkpoint_enable = 0;

        @(negedge clock);
    endtask

    task fill_FIFO(
    );
        while(~full) begin
            insert_event(1, $random, 0, 0); // Enqueue
        end
    endtask

    task empty_FIFO(
    );
        while(available) begin
            insert_event(0, 0, 1, 0); // Dequeue
        end
    endtask

    ////////////////////////////////////////////////////////////////////////
    // ENTRY COUNTER LOGIC                                                //
    ////////////////////////////////////////////////////////////////////////

    always begin
        #5 clock = ~clock;
    end
    
    always_comb begin
        current_size                  = tail_ptr_out - head_ptr_out;
        entry_counter_inc             = (enqueue & (    !full | dequeue)) ? 1 : 0;
        entry_counter_dec             = (dequeue & (available | enqueue)) ? 1 : 0;
        entry_counter_next            = ( checkpoint_enable & ~entry_checkpoint_signal) ? entry_counter_checkpoint + entry_counter_inc          : entry_counter + entry_counter_inc - entry_counter_dec;
        entry_counter_checkpoint_next = (~checkpoint_enable &  entry_checkpoint_signal) ? entry_counter + entry_counter_inc - entry_counter_dec : entry_counter_checkpoint + entry_counter_inc;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            entry_counter <= `SD `FIFO_SIZE;
        end else begin
            if(entry_counter !== `FIFO_SIZE && full)
                fail("full", 0);
            if(entry_counter === `FIFO_SIZE && ~full)
                fail("full", 1);
            if(entry_counter == 0 && available)
                fail("available", 0); 
            if(entry_counter != 0 && ~available)
                fail("available", 1);
            if(((current_size !== entry_counter) && ~full) || 
              (tail_ptr_out - head_ptr_out !== 0 &&  full))
                fail("size", entry_counter);

            entry_counter            <= `SD entry_counter_next;
            entry_counter_checkpoint <= `SD entry_counter_checkpoint_next;
        end
    end

    ////////////////////////////////////////////////////////////////////////
    // MAIN TEST FLOW                                                     //
    ////////////////////////////////////////////////////////////////////////

    initial begin
        $monitor("Time:%4.0f head_ptr:%h tail_ptr:%h avail:%b full:%b enqueue:%b dequeue:%b EC:%h save_chk:%b sq_en:%h sq_head_ptr:%h sq_EC:%h", 
            $time, head_ptr_out, tail_ptr_out, available, full, enqueue, dequeue, entry_counter, entry_checkpoint_signal, checkpoint_enable, checkpoint_head_ptr, entry_counter_checkpoint);
        clock = 0;
        reset = 1;
        data_in = 0;
        checkpoint_enable = 0;
	    checkpoint_head_ptr_in = 0;
        dequeue = 0;
        enqueue = 0;

        @(negedge clock);
        
        reset = 0;

        /////////////////////////////////////////////////////////////////////////
        // Fill the FIFO, then empty it                                        //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& EMPTYING AND FILLING FIFO &&& ");

        $display("Filling the FIFO");
        fill_FIFO();
        $display("Filling the FIFO: DONE");

        $display("Trying to add entry while full");
        insert_event(1, $random, 0, 0); // should do nothing
        $display("Trying to add entry while full: DONE");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Simultaneous dequeue and enqueue to full FIFO                       //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SIMULTANEOUS ENQUEUE AND DEQUEUE (FIFO FULL) &&& ");

        $display("Filling the FIFO");
        fill_FIFO();
        $display("Filling the FIFO: DONE");
        
        $display("Dequeue and enqueue to the FIFO simultaneously (when FULL)");
        for (int i = 0; i < `FIFO_SIZE; i++) begin
            insert_event(1, $random, 1, 0);
        end
        $display("Dequeue and enqueue to the FIFO simultaneously (when FULL): DONE");
        
        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");


        ////////////////////////////////////////////////////////////////////////////////
        // Simultaneous dequeue and enqueue to non-full and non-empty FIFO            //
        ////////////////////////////////////////////////////////////////////////////////
        $display(" &&& SIMULTANEOUS ENQUEUE AND DEQUEUE (FIFO 1 ENTRY) &&& ");

        $display("Adding 1 entry to the FIFO");
        insert_event(1, $random, 0, 0);
        
        $display("Dequeue and enqueue to the FIFO simultaneously (when 1 ENTRY)");
        for (int i = 0; i < `FIFO_SIZE; i++) begin
            insert_event(1, $random, 1, 0);
        end
        $display("Dequeue and enqueue to the FIFO simultaneously (when 1 ENTRY): DONE");


        ////////////////////////////////////////////////////////////////////////////////
        // Simultaneous dequeue and enqueue to empty FIFO                             //
        ////////////////////////////////////////////////////////////////////////////////
        $display(" &&& SIMULTANEOUS ENQUEUE AND DEQUEUE (FIFO EMPTY) &&& ");
        
        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Dequeue and enqueue to the FIFO simultaneously (when EMPTY)");
        for (int i = 0; i < `FIFO_SIZE; i++) begin
            insert_event(1, $random, 1, 0);
        end
        $display("Dequeue and enqueue to the FIFO simultaneously (when EMPTY): YEET");


        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint                                                //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& CREATE AND SQUASH TO CHECKPOINT &&& ");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `FIFO_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 0);
        $display("Creating checkpoint: DONE");

        $display("Filling FIFO to full");
        fill_FIFO();
        $display("Filling FIFO to full: DONE");

        $display("Squashing to checkpoint");
        insert_event(0, 0, 0, 1);
        $display("Squashing to checkpoint: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Create checkpoint while enqueueing, then squash to it               //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& CREATE CHECKPOINT WHILE ENQUEUEING AND SQUASH TO IT &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `FIFO_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(1, $random, 0);
        $display("Creating checkpoint: DONE");

        $display("Filling FIFO to full");
        fill_FIFO();
        $display("Filling FIFO to full: DONE");

        $display("Squashing to checkpoint");
        insert_event(0, 0, 0, 1);
        $display("Squashing to checkpoint: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Create checkpoint while dequeueing, then squash to it               //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& CREATE CHECKPOINT WHILE DEQUEUEING AND SQUASH TO IT &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `FIFO_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 1);
        $display("Creating checkpoint: DONE");

        $display("Filling FIFO to full");
        fill_FIFO();
        $display("Filling FIFO to full: DONE");

        $display("Squashing to checkpoint");
        insert_event(0, 0, 0, 1);
        $display("Squashing to checkpoint: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and enqueue simultaneously                     //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND ENQUEUE &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `FIFO_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 0);
        $display("Creating checkpoint: DONE");

        $display("Inserting entry");
        insert_event(1, $random, 0, 0);
        $display("Inserting entry: DONE");

        $display("Squashing to checkpoint and enqueueing simultaneously");
        insert_event(1, $random, 0, 1);
        $display("Squashing to checkpoint and enqueueing simultaneously: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and dequeue simultaneously                     //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND DEQUEUE &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `FIFO_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 0);
        $display("Creating checkpoint: DONE");

        $display("Inserting entry");
        insert_event(1, $random, 0, 0);
        $display("Inserting entry: DONE");

        $display("Squashing to checkpoint and dequeueing simultaneously");
        insert_event(0, 0, 1, 1);
        $display("Squashing to checkpoint and dequeueing simultaneously: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and enqueue and dequeue simultaneously         //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND ENQUEUE AND DEQUEUE &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `FIFO_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 0);
        $display("Creating checkpoint: DONE");

        $display("Inserting entry");
        insert_event(1, $random, 0, 0);
        $display("Inserting entry: DONE");

        $display("Squashing to checkpoint and enqueueing and dequeueing simultaneously");
        insert_event(1, $random, 1, 1);
        $display("Squashing to checkpoint and enqueueing and dequeueing simultaneously: DONE");
        

        /////////////////////////////////////////////////////////////////////////
        //                              RANDOM TESTING                         //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& RANDOM TESTING &&& ");

        for (int i = 0; i < 10000; i++) begin
            random_enqueue_valid = (entry_counter_checkpoint == `FIFO_SIZE) ? 0 : $random; // There would be no data to enqueue in this situation IRL
            random_data_added = $random;
            random_dequeue_valid = $random;
            random_squash_valid = ($random % 10 == 0); // 10% chance of squash
            random_checkpoint_write = (random_squash_valid) ? 0 : ($random % 5 == 0); // 18% chance of checkpoint write

            if(random_checkpoint_write) begin
                save_checkpoint_event(random_enqueue_valid, random_data_added, random_dequeue_valid);                
            end else begin
                insert_event(random_enqueue_valid, random_data_added, random_dequeue_valid, random_squash_valid);
            end
        end

        `ifdef FINISH_ON_ERROR
        $display("PASSED!");
        `endif
        $finish;
    end
endmodule
`endif
