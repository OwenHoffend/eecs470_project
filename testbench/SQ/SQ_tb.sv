
`ifndef _SQ_TB__
`define _SQ_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/SQ.sv"
`include "./verilog/onehot_to_binary.sv"
`include "./verilog/pselect.sv"
`include "./verilog/barrel_shift.sv"

`define DEBUG_MODE
`define FINISH_ON_ERROR

module SQ_tb;
    logic               clock;       	     // clock
    logic               reset;       	     // Synchronous reset/clear the FIFO
    
    CDB_PACKET		    cdb_in;              // Use if you want to restore FIFO to a squash
    
    //Store dispatch
    logic               valid_store;          // Dispatch stage only Store instruction tail_ptr to execute and incr the tail_ptr
    
    //Data from execute
    SQ_PACKET           ex_to_sq;	     // Address     

    //Write enable from Dcache
    logic	            dcache_store_stall;  // enable signal 
    logic		        rob2sq_retire_en;    // Sent from ROB when SQ is dequeued to Dcache


    SQ_IDX 		        sq_onc;		         // Oldest non-complete store updated to RS 
    SQ_IDX 		        tail_ptr_out;        // To Execute stage for each SQ instruction
    SQ_IDX              head_ptr_out;        // Used by RS to determine valid dispatch
    SQ_PACKET           sq_to_cache;         // Output to Dcache during Store inst retire from ROB
    logic 		        sq2load_frwd_valid;  // Valid signal for determining store to load forwarding 
    logic [`XLEN-1:0]   sq2load_frwd_value;  // Value to be forwarded from store to load 
    logic               full;                // Are we at capacity?
    logic               available;

    SQ_DEBUG_PACKET     sq_debug;

    SQ  test_sq (
        // Inputs
        .clock(clock),
        .reset(reset),
        .cdb_in(cdb_in),
        .valid_store(valid_store),
        .ex_to_sq_in(ex_to_sq),
        .dcache_store_stall(dcache_store_stall),
        .rob2sq_retire_en(rob2sq_retire_en),

        .sq_onc(sq_onc),         
        .tail_ptr_out(tail_ptr_out),
        .head_ptr_out(head_ptr_out),
        .sq_to_cache(sq_to_cache),
        .sq2load_frwd_valid(sq2load_frwd_valid),
        .sq2load_frwd_value(sq2load_frwd_value),
        .full(full),
	    .available(available),
        .sq_debug(sq_debug)
    );

    integer clock_count;

    // Variables for testbench to track the state of the freelist
    integer entry_counter;
    integer entry_counter_next;
    integer entry_counter_dec;
    integer entry_counter_inc;
    logic   entry_checkpoint_signal; // Signal to checkpoint counter next MUX
    integer entry_counter_checkpoint;
    integer entry_counter_checkpoint_next;

    logic [$clog2(`SQ_SIZE)-1:0] current_size;

    logic [`SQ_SIZE -1:0] complete_tracker, complete_tracker_next;
    logic   onc_found;
    SQ_IDX  tb_onc, onc_check; 
    integer head_tail_diff;
    
    // Checkpoint data registers to be used by TB. Written to by task save_checkpoint()
    logic [$clog2(`SQ_SIZE)-1:0]    checkpoint_head_ptr;

    //Signals for testing store to load forwarding
    logic [`SQ_SIZE-1:0][`XLEN-1:0] st_addr_tracker, st_addr_tracker_next;
    logic [`SQ_SIZE-1:0][`XLEN-1:0] st_value_tracker, st_value_tracker_next;

    //Since the module only outputs load forwads during the cycle which the load instr is valid, 
    //we need to save it. This is equivalent to the load buffer that EX will have for load outputs.
    logic [`XLEN-1:0] store_fwd_correct;
    logic [`XLEN-1:0] saved_fwd_value, saved_fwd_value_next; 
    logic             saved_fwd_valid, saved_fwd_valid_next; 

/*    // Random test signals
    logic      random_dispatch_valid;
    `DATA_TYPE random_data_added;
    logic      random_dequeue_valid;
    logic      random_squash_valid;
    logic      random_checkpoint_write;
*/
    SQ_IDX	temp_idx;
    ////////////////////////////////////////////////////////////////////////
    // TASK DEFINITIONS                                                   //
    ////////////////////////////////////////////////////////////////////////

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("---Forwarded load value: %h", saved_fwd_value);
        $display("---Forwarding addresss: %h", ex_to_sq.address);
        $display("---Head ptr: %h. Tail ptr: %h", head_ptr_out, tail_ptr_out);
        $display("---available: %b. full: %b", available, full);
        $display("Current size: %h, Entry counter: %h", current_size, entry_counter);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    task print_SQ;
        SQ_IDX complete_idx = sq_debug.ex_to_sq.idx;
        string prefix;
        string suffix;
        string color;
        $display("cycle %1d | %1h: store_dispatch: %b st_complete: %b ld_complete: %b",
            clock_count, clock_count, sq_debug.valid_store, sq_debug.ex_to_sq.st_valid, sq_debug.ex_to_sq.ld_valid);
        for(int i = 0; i < `SQ_SIZE; i++) begin //SQ_FIFO contents
            color = `C_WHITE;
            prefix = "    ";
            suffix = "";
            if(i == sq_debug.head_ptr_out) begin
                if(i == sq_debug.tail_ptr_out)
                    prefix = "HT->";
                else
                    prefix = "H-->";
            end else if(i == sq_debug.tail_ptr_out)
                prefix = "T-->";

            if(i < sq_debug.head_ptr_out & i >= sq_debug.tail_ptr_out |
            ((sq_debug.tail_ptr_out > sq_debug.head_ptr_out) & (i >= sq_debug.tail_ptr_out | i < sq_debug.head_ptr_out)) | 
            (sq_debug.head_ptr_out == sq_debug.tail_ptr_out & ~sq_debug.available))
                color = `C_BLACK;

            if(sq_debug.SQ_FIFO[i].complete) begin
                if(sq_debug.sq2load_frwd_valid & 
                sq_debug.ld_fwd_hit + sq_debug.ex_to_sq.idx - (`SQ_SIZE - 1'b1) == i) begin
                    suffix = {suffix, $sformatf("FWD --> To load @ SQ idx: %h", sq_debug.ex_to_sq.idx)};
                    color  = `C_YELLOW;
                end else
                    color  = `C_GREEN;
            end else begin
                if(i == sq_debug.sq_onc + sq_debug.head_ptr_out & sq_debug.available) begin //ONC index (actual ONC)
                    suffix = {"<--- ONC ", suffix};
                    color  = `C_BLUE;
                end else if(sq_debug.valid_store & i == sq_debug.tail_ptr_out) begin //Normal index
                    suffix = {"<--- ST DISPATCH ", suffix};
                    color  = `C_WHITE;
                end
            end

            if(sq_debug.rob2sq_retire_en & sq_debug.SQ_FIFO[i].complete & i == sq_debug.head_ptr_out) begin
                suffix = {"<--- RETIRE ", suffix};
                color  = `C_PINK;
            end

            $write(color, 27);
            $display("%s SQ Entry %2h st addr: %h st value: %h complete: %b %s", 
                prefix, i, sq_debug.SQ_FIFO[i].sq_address, sq_debug.SQ_FIFO[i].sq_value, sq_debug.SQ_FIFO[i].complete, suffix);
            $write(`C_CLEAR, 27);
        end
        $display();
    endtask

/*
    task save_checkpoint_event(
        input logic dispatch_valid,
        input `DATA_TYPE data_added,
        input logic dequeue_valid
    );
        // Create valid_store event
        valid_store = dispatch_valid;

        // Create dequeue event
        dequeue = dequeue_valid;

        // Asynchronously read checkpoint data
        // Allow combinational logic to propogate
        `SD checkpoint_head_ptr = checkpoint_head_ptr_out;
        entry_checkpoint_signal = 1;

        @(negedge clock);

        // Clear inputs
        valid_store = 0;
        dequeue = 0;
        entry_checkpoint_signal = 0;

        @(negedge clock);
    endtask
*/
    task reset_SQ;
        $display("Resetting the SQ");
        reset = 1;
        @(negedge clock);
        reset = 0;
        @(negedge clock);
        $display("Resetting the SQ - DONE");
    endtask

	// This task can perform dispatch, store complete, squash_enable and retire 
    task st_and_add_event_to_sq(
        input logic dispatch_valid,
	    input logic store_complete,
	    input SQ_IDX sq_idx,
        input logic [`XLEN-1:0] data_address,
        input logic [`XLEN-1:0] data_value,	
        input logic dequeue_valid,
        input logic dcache_wr_valid,
        input logic squash_valid,
	    input SQ_IDX squash_tail_ptr
    );
        // Create valid_store event
        valid_store = dispatch_valid;

	    // Add the store address and value
	    ex_to_sq.st_valid = store_complete;
	    ex_to_sq.idx      = sq_idx; 
        ex_to_sq.address  = data_address;
        ex_to_sq.value    = data_value;

        // Create dequeue event
        rob2sq_retire_en = dequeue_valid;
	    dcache_store_stall = dcache_wr_valid;

        // Create squash event
	    cdb_in.squash_enable = squash_valid;
	    cdb_in.sq_idx = squash_tail_ptr;

        @(negedge clock);
	    valid_store          = 0;
	    ex_to_sq.st_valid = 0;
	    rob2sq_retire_en     = 0;
	    dcache_store_stall   = 0;
	    cdb_in.squash_enable = 0;

        @(negedge clock);
    endtask

	// This task can perform dispatch, store to load forward, squash_enable and retire
    task ld_and_add_event_to_sq(
        input logic dispatch_valid,
	    input logic load_complete,
	    input SQ_IDX sq_idx,
        input logic [`XLEN-1:0] data_address,
        input logic dequeue_valid,
        input logic dcache_wr_valid,
        input logic squash_valid,
	    input SQ_IDX squash_tail_ptr
    );
        // Create valid_store event
        valid_store = dispatch_valid;

	    // Add the store address and value
	    ex_to_sq.ld_valid = load_complete;
	    ex_to_sq.idx      = sq_idx;  
        ex_to_sq.address  = data_address;

        // Create dequeue event
        rob2sq_retire_en   = dequeue_valid;
	    dcache_store_stall = dcache_wr_valid;

        // Create squash event
	    cdb_in.squash_enable = squash_valid;
	    cdb_in.sq_idx = squash_tail_ptr;

        @(negedge clock);
	    valid_store          = 0;
	    ex_to_sq.ld_valid = 0;
	    rob2sq_retire_en     = 0;
	    dcache_store_stall   = 0;
	    cdb_in.squash_enable = 0;

        @(negedge clock);
    endtask

    task fill_SQ;
	    integer j = 0;
        $display("Filling the SQ");
        while(~full) begin
            j = j + 1;
            st_and_add_event_to_sq(1, 0, 0, 0, 0, 0, 0, 0, 0); // Enqueue
            if (j >= 3) begin
                temp_idx = tail_ptr_out - 3;
                st_and_add_event_to_sq(0, 1, temp_idx, $random % 256, $random, 0, 0, 0, 0);
            end 
        end
        st_and_add_event_to_sq(0, 1, tail_ptr_out - 2, $random % 256, $random, 0, 0, 0, 0);
        st_and_add_event_to_sq(0, 1, tail_ptr_out - 1, $random % 256, $random, 0, 0, 0, 0);	
        $display("Filling the SQ - DONE");
    endtask

    task retire;
        ld_and_add_event_to_sq(0, 0, 0, 0, 1, 0, 0, 0);
    endtask
    
    task empty_SQ;
        $display("Emptying the SQ");
        while(available)
            retire();
        $display("Emptying the SQ - DONE");
    endtask

    task ld_dispatch_and_complete(
        input [`XLEN-1:0] addr
    );
        ld_and_add_event_to_sq(0, 0, 0, 0, 0, 0, 0, 0); // Enqueue
        ld_and_add_event_to_sq(0, 1, tail_ptr_out - 1, addr, 0, 0, 0, 0); //Complete
    endtask

    task st_dispatch_and_complete(
        input [`XLEN-1:0] addr,
        input [`XLEN-1:0] value
    );
        st_and_add_event_to_sq(1, 0, 0, 0, 0, 0, 0, 0, 0); // Enqueue
        st_and_add_event_to_sq(0, 1, tail_ptr_out - 1, addr, value, 0, 0, 0, 0); //Complete
    endtask

    //Looping pattern of num_adds enqueues and num_retires dequeues
    //This should cause head/tail pointer looping and help test edge cases
    task add_remove_pattern(
        input integer num_adds,
        input integer num_retires
    );
        assert(num_adds != num_retires) else $finish; //Otherwise we infinite loop - these are bad parameters for the task
        $display("Running add-remove pattern: %1d:%1d", num_adds, num_retires);
        reset_SQ();

        //Loop until either we are full (if num_adds > num_retires)
        //Or we are empty (if num_adds < num_retires)
        while(1) begin
            repeat(num_adds) st_dispatch_and_complete($random, $random);
            if(full) 
                break;
            repeat(num_retires) retire();
            if(~available) 
                break;
        end
    endtask

    //Sweep a set of patterns designed to move the head pointer and tail pointer around
    //For example, pattern 2, 1 will add 2 entries and then remove 1, continously until the SQ is full
    task add_remove_pattern_parameter_sweep;
        for(int i = 1; i < `SQ_SIZE; i++) begin
            for(int j = 1; j < `SQ_SIZE; j++) begin
                if(i != j)
                    add_remove_pattern(i, j);
            end
        end
    endtask

    ////////////////////////////////////////////////////////////////////////
    // ENTRY COUNTER LOGIC                                                //
    ////////////////////////////////////////////////////////////////////////

    always begin
        #5 clock = ~clock;
    end
    
    always_comb begin
        current_size                  		  = tail_ptr_out - head_ptr_out;
	    complete_tracker_next 	      		  = complete_tracker;
        st_addr_tracker_next                  = st_addr_tracker;
        st_value_tracker_next                 = st_value_tracker;
        saved_fwd_value_next                  = saved_fwd_value;
        entry_counter_inc             		  = (valid_store & (!full | rob2sq_retire_en & !dcache_store_stall)) ? 1 : 0;
        entry_counter_dec             		  = (rob2sq_retire_en & !dcache_store_stall & available & complete_tracker[head_ptr_out]) ? 1 : 0;
        entry_counter_next            		  = ( cdb_in.squash_enable & ~entry_checkpoint_signal) ? entry_counter_checkpoint + entry_counter_inc          : entry_counter + entry_counter_inc - entry_counter_dec;
        entry_counter_checkpoint_next 		  = (~cdb_in.squash_enable &  entry_checkpoint_signal) ? entry_counter + entry_counter_inc - entry_counter_dec : entry_counter_checkpoint + entry_counter_inc;
        if (ex_to_sq.st_valid & available) begin
            complete_tracker_next[ex_to_sq.idx] = 1;
            st_addr_tracker_next[ex_to_sq.idx]  = ex_to_sq.address;
            st_value_tracker_next[ex_to_sq.idx] = ex_to_sq.value;  
        end
        if (rob2sq_retire_en & !dcache_store_stall & available & complete_tracker[head_ptr_out])
            complete_tracker_next[head_ptr_out] = 0;

        //Store to load forwarding
        saved_fwd_valid_next = sq2load_frwd_valid; //Done so that the test case for this receives the valid signal and data on the same cycle 
        if(sq2load_frwd_valid)
            saved_fwd_value_next = sq2load_frwd_value;

        //Store to load forwarding correct result
        store_fwd_correct = 0;
        if(saved_fwd_valid) begin
            for (logic [$clog2(`SQ_SIZE)-1:0] i = ex_to_sq.idx; i - 1'b1 != ex_to_sq.idx; i = i - 1'b1) begin
                if(complete_tracker[i] & (st_addr_tracker[i] == ex_to_sq.address)) begin
                    store_fwd_correct = st_value_tracker[i];
                    break;
                end
            end
        end

        //ONC Correct result
        tb_onc    = 0;
        onc_found = 0;
        head_tail_diff = !full ? ((head_ptr_out > tail_ptr_out) ? `SQ_SIZE - head_ptr_out + tail_ptr_out : tail_ptr_out - head_ptr_out) : `SQ_SIZE;
        for (int i = 0; i <= head_tail_diff; i ++) begin
            onc_check = head_ptr_out + i;
            //	$display("onc_check: %d, tb_onc: %d", onc_check, tb_onc);
            if (!complete_tracker[onc_check] && !onc_found) begin
                onc_found = 1'b1;
                tb_onc = onc_check - head_ptr_out;
            //	$display("onc_check_if: %d, tb_onc_if: %d", onc_check, tb_onc);
            end
            else if (complete_tracker[onc_check] && !onc_found) begin
                tb_onc = 0;
            end
        end
    end

    always_ff @(posedge clock) begin
        print_SQ();
        if (reset) begin
            clock_count      <= `SD 0;
            entry_counter    <= `SD 0;
	        complete_tracker <= `SD 0;
            saved_fwd_value  <= `SD 0;
            saved_fwd_valid  <= `SD 0;
            st_addr_tracker  <= `SD 0; 
            st_value_tracker <= `SD 0;
        end else begin
	        //$display("head_ptr_out:%b sq_onc: %d, tb_onc: %d", head_ptr_out, sq_onc, tb_onc);
            if(entry_counter !== `SQ_SIZE && full)
                fail("full", 0);
            if(entry_counter === `SQ_SIZE && ~full)
                fail("full", 1);
            if(entry_counter == 0 && available)
                fail("available", 0); 
            if(entry_counter != 0 && ~available)
                fail("available", 1);
            if(((current_size !== entry_counter) && ~full) || 
              (tail_ptr_out - head_ptr_out !== 0 &&  full))
                fail("size", entry_counter);
	        if(sq_onc !== tb_onc)
		        fail("sq_onc", tb_onc);

            if(saved_fwd_valid) begin
                if(saved_fwd_value !== store_fwd_correct)
                    fail("sq2load_frwd_value", store_fwd_correct);
                else
                    $display("Received forwarded value: %h from address %h", saved_fwd_value, ex_to_sq.address);
            end
            //$display("ex_to_sq.st_valid: %b, ex_to_sq.idx: %h, available: %b, complete_tracker_bit: %b ", 
            //    ex_to_sq.st_valid, ex_to_sq.idx, available, complete_tracker[ex_to_sq.idx]);
            clock_count              <= `SD (clock_count + 1);
            entry_counter            <= `SD entry_counter_next;
            entry_counter_checkpoint <= `SD entry_counter_checkpoint_next;
	        complete_tracker	     <= `SD complete_tracker_next;
            saved_fwd_value          <= `SD saved_fwd_value_next;
            saved_fwd_valid          <= `SD saved_fwd_valid_next; 
            st_addr_tracker          <= `SD st_addr_tracker_next; 
            st_value_tracker         <= `SD st_value_tracker_next;
        end
    end

    ////////////////////////////////////////////////////////////////////////
    // MAIN TEST FLOW                                                     //
    ////////////////////////////////////////////////////////////////////////

    initial begin
        $monitor("Time:%4.0f head_ptr:%h tail_ptr:%h avail:%b full:%b valid_store:%b ex_to_sq.st_valid:%b rob2sq_retire_en:%b ",
            $time, head_ptr_out, tail_ptr_out, available, full, valid_store, ex_to_sq.st_valid, rob2sq_retire_en, 
            "dcache_store_stall:%b EC:%h save_chk:%b sq_en:%h sq_head_ptr:%h sq_EC:%h complete_tracker:%b sq_onc:%d tb_onc: %d ",
            dcache_store_stall, entry_counter, entry_checkpoint_signal, cdb_in.squash_enable, cdb_in.sq_idx, entry_counter_checkpoint, complete_tracker, sq_onc, tb_onc);
        clock                = 0;
        reset                = 1;
        ex_to_sq          = 0;
        cdb_in.squash_enable = 0;
	    cdb_in.sq_idx        = 0;
        rob2sq_retire_en     = 0;
	    dcache_store_stall   = 0;
        valid_store          = 0;

        @(negedge clock);
        
        reset = 0;
        /////////////////////////////////////////////////////////////////////////
        // Fill the SQ, then empty it                                        //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& EMPTYING AND FILLING SQ &&& ");

        fill_SQ();

        $display("Trying to add entry while full");
        st_and_add_event_to_sq(1, 0, 0, 0, 0, 0, 0, 0, 0); // should do nothing
        $display("Trying to add entry while full: DONE");

        empty_SQ();

        ////////////////////////////////////////////////////////////////////////
        // Dispatch and store complete the SQ simultaneously                  //
        ////////////////////////////////////////////////////////////////////////

	    $display("Dispatch 3 inst to the SQ");		
        st_and_add_event_to_sq(1, 0, 0, 0, 0, 0, 0, 0, 0);	
        st_and_add_event_to_sq(1, 0, 0, 0, 0, 0, 0, 0, 0);
        st_and_add_event_to_sq(1, 0, 0, 0, 0, 0, 0, 0, 0);

        $display("Dispatch and store complete ");
	    temp_idx = tail_ptr_out -3;
	    st_and_add_event_to_sq(1, 1, temp_idx, 134, 23, 0, 0, 0, 0);
        $display("Dispatch and store complete : Done ");
					
        ////////////////////////////////////////////////////////////////////////
        // Dispatch, store complete and retire the SQ simultaneously          //
        ////////////////////////////////////////////////////////////////////////
        $display("Dispatch, store complete and retire simultaneously ");
	    temp_idx = tail_ptr_out -3;
	    st_and_add_event_to_sq(1, 1, temp_idx, 91, 52, 1, 0, 0, 0);
        $display("Dispatch, store complete and retire simultaneously  : Done ");

        $display("Dispatch, store complete and retire when dcache stall simultaneously ");
	    temp_idx = tail_ptr_out -3;
	    st_and_add_event_to_sq(1, 1, temp_idx, 213, 11, 1, 1, 0, 0);
        $display("Dispatch, store complete and retire when dcache stall simultaneously  : Done ");

        ////////////////////////////////////////////////////////////////////////
        // Store complete and retire the SQ simultaneously                    //
        ////////////////////////////////////////////////////////////////////////
        $display("Store complete and retire simultaneously ");
	    temp_idx = tail_ptr_out -3;
	    st_and_add_event_to_sq(0, 1, temp_idx, 17, 152, 1, 0, 0, 0);
        $display("Store complete and retire simultaneously  : Done ");

        $display("Store complete and retire simultaneously when dcache stall simultaneously");
	    temp_idx = tail_ptr_out -1;
	    st_and_add_event_to_sq(0, 1, temp_idx, 27, 19, 1, 1, 0, 0);
        $display("Store complete and retire simultaneously when dcache stall simultaneously : Done ");

        ////////////////////////////////////////////////////////////////////////
        // Dispatch and retire the SQ simultaneously                          //
        ////////////////////////////////////////////////////////////////////////
        $display("Dispatch and retire simultaneously ");
	    st_and_add_event_to_sq(1, 0, 0, 0, 0, 1, 0, 0, 0);
        $display("Dispatch and retire simultaneously  : Done ");

        $display("Dispatch and retire simultaneously when dcache stall simultaneously");
	    st_and_add_event_to_sq(1, 0, 0, 0, 0, 1, 1, 0, 0);
        $display("Dispatch and retire simultaneously when dcache stall simultaneously : Done ");
	
        ////////////////////////////////////////////////////////////////////////
        // Store to Load forward 				                              //
        ////////////////////////////////////////////////////////////////////////
        $display("Store to Load forward ");
	    temp_idx = tail_ptr_out -2;	
	    ld_and_add_event_to_sq(0, 1, temp_idx, 27, 0, 0, 0, 0);				// Output should be 19
        $display("Store to Load forward  : Done ");

        $display("Dispatch and store complete ");
	    temp_idx = tail_ptr_out -1;
	    st_and_add_event_to_sq(1, 1, temp_idx, 27, 143, 0, 0, 0, 0);
        $display("Dispatch and store complete : Done 27, 143");
					
        ////////////////////////////////////////////////////////////////////////
        // Store to Load forward and retire the SQ simultaneously             //
        ////////////////////////////////////////////////////////////////////////
        $display("Store to Load forward and retire the SQ simultaneously");
	    temp_idx = tail_ptr_out -2;	
	    ld_and_add_event_to_sq(0, 1, temp_idx, 27, 1, 0, 0, 0);				// Output should be 143
        $display("Store to Load forward and retire the SQ simultaneously : Done ");

        ////////////////////////////////////////////////////////////////////////
        // Store complete and retire the SQ simultaneously speacial case      //
        ////////////////////////////////////////////////////////////////////////
	    temp_idx = head_ptr_out; 
        $display(" Store complete and retire simultaneously when head_ptr not complete");
	    st_and_add_event_to_sq(0, 1, temp_idx, 27, 58, 1, 0, 0, 0);			
        $display("Dispatch and retire simultaneously when dcache stall simultaneously : Done ");

        ////////////////////////////////////////////////////////////////////////
        // Store to Load forward and dispatch the SQ simultaneously           //
        ////////////////////////////////////////////////////////////////////////
        $display("Store to Load forward and dispatch the SQ simultaneously");
	    temp_idx = head_ptr_out + 2;	
	    ld_and_add_event_to_sq(1, 1, temp_idx, 27, 0, 0, 0, 0);				// Output should be 19
        $display("Store to Load forward and dispatch the SQ simultaneously : Done ");

        ////////////////////////////////////////////////////////////////////////
        // Store to Load forward, dispatch and retire the SQ simultaneously   //
        ////////////////////////////////////////////////////////////////////////
        $display("Store to Load forward, dispatch and retire the SQ simultaneously");
	    temp_idx = head_ptr_out + 3;	
	    ld_and_add_event_to_sq(1, 1, temp_idx, 27, 1, 0, 0, 0);				// Output should be 143
        $display("Store to Load forward, dispatch and retire the SQ simultaneously : Done ");


        //add_remove_pattern_parameter_sweep();

/*        ////////////////////////////////////////////////////////////////////////
        // Simultaneous dequeue and valid_store to full FIFO                    //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SIMULTANEOUS ENQUEUE AND DEQUEUE (FIFO FULL) &&& ");

        $display("Filling the FIFO");
        fill_FIFO();
        $display("Filling the FIFO: DONE");
        
        $display("Dequeue and valid_store to the FIFO simultaneously (when FULL)");
        for (int i = 0; i < `SQ_SIZE; i++) begin
            insert_event(1, $random, 1, 0);
        end
        $display("Dequeue and valid_store to the FIFO simultaneously (when FULL): DONE");
        
        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");


        ////////////////////////////////////////////////////////////////////////////////
        // Simultaneous dequeue and valid_store to non-full and non-empty FIFO            //
        ////////////////////////////////////////////////////////////////////////////////
        $display(" &&& SIMULTANEOUS ENQUEUE AND DEQUEUE (FIFO 1 ENTRY) &&& ");

        $display("Adding 1 entry to the FIFO");
        insert_event(1, $random, 0, 0);
        
        $display("Dequeue and valid_store to the FIFO simultaneously (when 1 ENTRY)");
        for (int i = 0; i < `SQ_SIZE; i++) begin
            insert_event(1, $random, 1, 0);
        end
        $display("Dequeue and valid_store to the FIFO simultaneously (when 1 ENTRY): DONE");


        ////////////////////////////////////////////////////////////////////////////////
        // Simultaneous dequeue and valid_store to empty FIFO                             //
        ////////////////////////////////////////////////////////////////////////////////
        $display(" &&& SIMULTANEOUS ENQUEUE AND DEQUEUE (FIFO EMPTY) &&& ");
        
        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Dequeue and valid_store to the FIFO simultaneously (when EMPTY)");
        for (int i = 0; i < `SQ_SIZE; i++) begin
            insert_event(1, $random, 1, 0);
        end
        $display("Dequeue and valid_store to the FIFO simultaneously (when EMPTY): YEET");


        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint                                                //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& CREATE AND SQUASH TO CHECKPOINT &&& ");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `SQ_SIZE / 2; i++) begin
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
        // Create checkpoint while valid_storeing, then squash to it               //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& CREATE CHECKPOINT WHILE ENQUEUEING AND SQUASH TO IT &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `SQ_SIZE / 2; i++) begin
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
        for (int i = 0; i < `SQ_SIZE / 2; i++) begin
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
        // Squash to checkpoint and valid_store simultaneously                     //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND ENQUEUE &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `SQ_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 0);
        $display("Creating checkpoint: DONE");

        $display("Inserting entry");
        insert_event(1, $random, 0, 0);
        $display("Inserting entry: DONE");

        $display("Squashing to checkpoint and valid_storeing simultaneously");
        insert_event(1, $random, 0, 1);
        $display("Squashing to checkpoint and valid_storeing simultaneously: DONE");


        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and dequeue simultaneously                     //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND DEQUEUE &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `SQ_SIZE / 2; i++) begin
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
        // Squash to checkpoint and valid_store and dequeue simultaneously         //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND ENQUEUE AND DEQUEUE &&& ");

        $display("Emptying the FIFO");
        empty_FIFO();
        $display("Emptying the FIFO: DONE");

        $display("Filling FIFO to half full");
        for (int i = 0; i < `SQ_SIZE / 2; i++) begin
            insert_event(1, $random, 0, 0);
        end
        $display("Filling FIFO to half full: DONE");

        $display("Creating checkpoint");
        save_checkpoint_event(0, 0, 0);
        $display("Creating checkpoint: DONE");

        $display("Inserting entry");
        insert_event(1, $random, 0, 0);
        $display("Inserting entry: DONE");

        $display("Squashing to checkpoint and valid_storeing and dequeueing simultaneously");
        insert_event(1, $random, 1, 1);
        $display("Squashing to checkpoint and valid_storeing and dequeueing simultaneously: DONE");
        

        /////////////////////////////////////////////////////////////////////////
        //                              RANDOM TESTING                         //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& RANDOM TESTING &&& ");

        for (int i = 0; i < 10000; i++) begin
            random_dispatch_valid = (entry_counter_checkpoint == `SQ_SIZE) ? 0 : $random; // There would be no data to valid_store in this situation IRL
            random_data_added = $random;
            random_dequeue_valid = $random;
            random_squash_valid = ($random % 10 == 0); // 10% chance of squash
            random_checkpoint_write = (random_squash_valid) ? 0 : ($random % 5 == 0); // 18% chance of checkpoint write

            if(random_checkpoint_write) begin
                save_checkpoint_event(random_dispatch_valid, random_data_added, random_dequeue_valid);                
            end else begin
                insert_event(random_dispatch_valid, random_data_added, random_dequeue_valid, random_squash_valid);
            end
        end
*/
        `ifdef FINISH_ON_ERROR
            $display("PASSED!");
        `endif
        $finish;
    end
endmodule
`endif
