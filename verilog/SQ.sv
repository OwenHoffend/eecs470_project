// This is a generic definition for a FIFO.  To use, just update IO and save a copy of this file
`ifndef _SQ__
`define _SQ__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/onehot_to_binary.sv"
// `include "./verilog/pselect.sv"
`include "./verilog/binary_pselect_dir0.sv"
`include "./verilog/binary_pselect_dir1.sv"
// `include "./verilog/barrel_shift.sv"
`include "./verilog/barrel_shift_dir0.sv"
`include "./verilog/barrel_shift_dir1.sv"

module SQ (
    input                       clock,               // clock
    input                       reset,               // Synchronous reset/clear the FIFO
    
    input CDB_PACKET            cdb_in, 
    
    //Store dispatch
    input                       valid_store,         // Dispatch stage only Store instruction tail_ptr to execute and incr the tail_ptr
    
    //Data from execute stage (load functional unit)
    input SQ_PACKET             ex_to_sq_in,	         // Address     

    //Retire stage
    input			            rob2sq_retire_en,	 // Input from ROB saying the ROB head is a store

    //Write enable from Dcache
    input	                    dcache_store_stall,	 // Memory request missed in dcache

    output SQ_IDX 		        sq_onc,		         // Oldest non-complete store updated to RS 
    output SQ_IDX 		        tail_ptr_out,        // To Execute stage for each SQ instruction
    output SQ_IDX               head_ptr_out,        // Used by RS to determine valid dispatch
    output SQ_PACKET            sq_to_cache,         // Output to Dcache during Store inst retire from ROB
    output logic 		        sq2load_frwd_valid,  // Valid signal for determining store to load forwarding 
    output logic [`XLEN-1:0]    sq2load_frwd_value,  // Value to be forwarded from store to load 
    output logic                sq2load_partial_frwd,
    output logic [3:0]          sq2load_frwd_mask,
    output logic                full,                 // Are we at capacity?
    output logic 		        available,
    output logic                all_complete
`ifdef DEBUG_MODE
    , input  INST               dispatch_instr,      //Instruction at which this is SQ entry was dispatched
    output SQ_DEBUG_PACKET      sq_debug
`endif
);
    //SQ Signals and Structure
    SQ_ENTRY [`SQ_SIZE-1:0]		    SQ_FIFO, SQ_FIFO_next;
    logic    [$clog2(`SQ_SIZE)-1:0]	head_ptr, tail_ptr, head_ptr_next, tail_ptr_next, diff_head_lp, load_ptr_check;
    logic 				available_next;
    logic               retire_cond, store_cond;

    logic squash; //helper variable

    //Store to Load forwarding signals
    logic [3:0] [`SQ_SIZE-1:0] fwd_addr_hits; //Bit vector storing all of the comparison hits for a load instruction
    logic [3:0] [`SQ_SIZE-1:0] fwd_addr_hits_shifted; 
    logic [3:0] [$clog2(`SQ_SIZE)-1:0] fwd_hit, fwd_idx;
    logic [3:0] fwd_valids;
    logic found_forward; //Does the forward contain enough data? Or should we wait for memory?

    // Oldest non-complete store calculation signals
    logic [`SQ_SIZE-1:0] n_completes; //Wire bus to unpack non-completes from the SQ_FIFO entries
    logic [`SQ_SIZE-1:0] n_completes_shifted; 

    //ONC algorithm: 
    //1: Extract the inverted complete bit from every entry.
    //2: Barrel shift by the head_ptr to align the n_complete bits as if the head pointer was at 0. (see barrel_shift.sv)
    //3: Compute a pselect with a standard priority select
    //4: Convert one-hot notation to binary notation using a binary search (see onehot_to_binary.sv)
    //5: Send the onc output to the RS
    //All of this logic is O(log(N)) depth instead of O(N) depth, so we should see a performance improvement over for loops.
    //An added benefit of doing this is that the barrel shifting means we don't have to subtract head_ptr from sq_onc in the RS anymore
    //So that saves us another 32-bit adder

    barrel_shift_dir0 onc_bs (
        .in_data(n_completes),
        .nshifts(head_ptr),
        .out_data(n_completes_shifted)
    );

    binary_pselect_dir0 onc_psel (
        .req(n_completes_shifted),
        .en(1'b1),
        .sel({$clog2(`SQ_SIZE){1'b0}}),
        .gnt(sq_onc) //This onc value is already shifted w/ respect to the head_ptr, so no need to do it again in the RS
    );

    //Store to load forward algorithm

    genvar i;
    generate
        for(i = 0; i < 4; i++) begin
            barrel_shift_dir1 sl_fwd_bs (
                .in_data(fwd_addr_hits[i]),
                .nshifts({$clog2(`SQ_SIZE){1'b1}} - ex_to_sq_in.idx),
                .out_data(fwd_addr_hits_shifted[i])
            );
            binary_pselect_dir1 sl_fwd_psel (
                .req(fwd_addr_hits_shifted[i]),
                .en(ex_to_sq_in.ld_valid),
                .sel({$clog2(`SQ_SIZE){1'b0}}),
                .gnt(fwd_hit[i])
            );
        end
    endgenerate

     function [3:0] fwd_mask(
        input MEM_SIZE size,
        input [1:0] addr_offset
    );
        case(size)
            BYTE: begin
               case(addr_offset)
                    2'b00: fwd_mask = 4'b0001;
                    2'b01: fwd_mask = 4'b0010;
                    2'b10: fwd_mask = 4'b0100;
                    2'b11: fwd_mask = 4'b1000;
               endcase 
            end
            HALF:   fwd_mask = addr_offset[1] ? 4'b1100 : 4'b0011; 
            WORD:   fwd_mask = 4'b1111;
            DOUBLE: fwd_mask = 4'b0000; //Bad
        endcase
    endfunction

    function [`XLEN-1:0] fwd_data(
        input [`XLEN-1:0] data,
        input MEM_SIZE size,
        input [1:0] addr_offset
    );
        case(size)
            BYTE: begin
                case(addr_offset)
                    2'b00: fwd_data = data;
                    2'b01: fwd_data = data << 8;
                    2'b10: fwd_data = data << 16;
                    2'b11: fwd_data = data << 24;
                endcase
            end
            HALF:   fwd_data = addr_offset[1] ? data << 16 : data; 
            WORD:   fwd_data = data; 
            DOUBLE: fwd_data = 32'hdeadbeef; //Bad
        endcase
    endfunction

    always_comb begin
        squash = cdb_in.valid & cdb_in.squash_enable;
        store_cond  = rob2sq_retire_en & SQ_FIFO[head_ptr].complete & available;
        retire_cond = store_cond & ~dcache_store_stall;   

        // SQ state indicators
        case(available)
            1'b0: available_next = valid_store;
            1'b1: available_next = ~((head_ptr + 1'b1 == tail_ptr) & 
                                    (retire_cond & ~valid_store));
        endcase
        
        full = (head_ptr == tail_ptr) & available;
        SQ_FIFO_next = SQ_FIFO;
        tail_ptr_next  = tail_ptr;
        head_ptr_next  = head_ptr;

        //Handle squashes
        if(squash) begin
            if(cdb_in.sq_idx == head_ptr) 
                available_next = 0;
            tail_ptr_next = cdb_in.sq_idx;
            for(int i = 0; i < `SQ_SIZE; i++) begin
                if(((i <= tail_ptr) | (tail_ptr == 0 & i == {$clog2(`SQ_SIZE){1'b0}})) &
                   ((i > cdb_in.sq_idx) | (cdb_in.sq_idx == {$clog2(`SQ_SIZE){1'b0}} & i == 0)) &
                    (i != head_ptr))  
                    SQ_FIFO_next[i].complete = 0;
            end
            /*
            for(int i = 0; i < `SQ_SIZE; i++) begin
                if(((i <= tail_ptr) | (tail_ptr == 0 & i == {$clog2(`SQ_SIZE){1'b0}})) &
                   ((i > cdb_in.sq_idx) | (cdb_in.sq_idx == {$clog2(`SQ_SIZE){1'b0}} & i == 0)) &
                    (i != head_ptr))  
                    SQ_FIFO_next[i].complete = 0;
            end
            */
            /*
           for(logic [$clog2(`SQ_SIZE)] i = tail_ptr; i != cdb_in.sq_idx; i = i - 1'b1) begin
                SQ_FIFO_next[i].complete = 0;
            end
            */
            SQ_FIFO_next[cdb_in.sq_idx].complete = 0;
        end else if(valid_store & (~full | retire_cond)) begin 
	    //Dispatch
            tail_ptr_next = tail_ptr + 1'b1;
            SQ_FIFO_next[tail_ptr] = 0;
            `ifdef DEBUG_MODE
                SQ_FIFO_next[tail_ptr].inst = dispatch_instr;
            `endif
        end

        // Complete stage
        // Update address and value coming from execute 
        if(ex_to_sq_in.st_valid & available) begin //Analogous to ROB completion
            SQ_FIFO_next[ex_to_sq_in.idx].sq_address  = ex_to_sq_in.address;
            SQ_FIFO_next[ex_to_sq_in.idx].mem_size    = ex_to_sq_in.mem_size;
            SQ_FIFO_next[ex_to_sq_in.idx].sq_value    = ex_to_sq_in.value;
            SQ_FIFO_next[ex_to_sq_in.idx].fwd_value   = fwd_data(ex_to_sq_in.value, ex_to_sq_in.mem_size.size, ex_to_sq_in.address[1:0]);
            SQ_FIFO_next[ex_to_sq_in.idx].fwd_mask    = fwd_mask(ex_to_sq_in.mem_size.size, ex_to_sq_in.address[1:0]);
            SQ_FIFO_next[ex_to_sq_in.idx].complete    = 1'b1;
        end
        
        //Enabling a store to dcache
        sq_to_cache    = 0;
        if (store_cond) begin
            sq_to_cache.address  = SQ_FIFO[head_ptr].sq_address;
            sq_to_cache.value    = SQ_FIFO[head_ptr].sq_value;
            sq_to_cache.mem_size = SQ_FIFO[head_ptr].mem_size;
            sq_to_cache.st_valid = 1'b1; 
	    end

        // Retire stage
        if(retire_cond) begin
            head_ptr_next = head_ptr + 1'b1;
            SQ_FIFO_next[head_ptr].complete = 1'b0;
        end

        // Special case
        if((head_ptr_next == tail_ptr_next) & squash)
            available_next = 0;

        // Oldest non-complete Store calculation
        //Bus completes to n_completes
        for(int i = 0; i < `SQ_SIZE; i++)
            n_completes[i] = ~SQ_FIFO[i].complete;

        all_complete  = ~|n_completes;

        // Store to load forwarding
        //Forward address hit comparison

        fwd_addr_hits = 0;
        /*
        for(int i = 0; i < `SQ_SIZE; i++) begin
            for(int j = 0; j < 4; j++) begin
                if((SQ_FIFO[i].complete & available) &
                    ((i >= ex_to_sq_in.idx) | (ex_to_sq_in.idx == {$clog2(`SQ_SIZE){1'b1}} & i == 0)) &  
                    ((i <= head_ptr) | (head_ptr == 0 & i == {$clog2(`SQ_SIZE){1'b1}})))
                    fwd_addr_hits[j][i] = (SQ_FIFO[i].sq_address == ex_to_sq_in.address) & SQ_FIFO[i].fwd_mask[j];
            end
        end
        */

        diff_head_lp = (head_ptr > ex_to_sq_in.idx) ? `SQ_SIZE - head_ptr + ex_to_sq_in.idx : ex_to_sq_in.idx - head_ptr;
        for (int i = 0; i < diff_head_lp; i++) begin
            load_ptr_check = (i > ex_to_sq_in.idx) ? `SQ_SIZE -i + ex_to_sq_in.idx : ex_to_sq_in.idx - i;
            for(int j = 0; j < 4; j ++) begin
                if(SQ_FIFO[load_ptr_check].complete & available)
                    fwd_addr_hits[j][load_ptr_check] = (SQ_FIFO[load_ptr_check].sq_address == ex_to_sq_in.address) & SQ_FIFO[load_ptr_check].fwd_mask[j];
            end
        end

        /*
        for(logic [$clog2(`SQ_SIZE)-1:0] i = ex_to_sq_in.idx; i != head_ptr; i = i - 1'b1) begin //i needs to be closer, or equal distance, to the head than the load pointer
            for(int j = 0; j < 4; j ++) begin
                if(SQ_FIFO[i].complete & available)
                    fwd_addr_hits[j][i] = (SQ_FIFO[i].sq_address == ex_to_sq_in.address) & SQ_FIFO[i].fwd_mask[j];
            end
        end
        */
        for(int j = 0; j < 4; j++) begin
            if(SQ_FIFO[head_ptr].complete & available)
                fwd_addr_hits[j][head_ptr] = (SQ_FIFO[head_ptr].sq_address == ex_to_sq_in.address) & SQ_FIFO[head_ptr].fwd_mask[j];
        end

        //Gather pselect hit results
        fwd_valids = 4'h0;
        for(int i = 0; i < 4; i++) begin
            fwd_idx[i] = fwd_hit[i] + ex_to_sq_in.idx - {$clog2(`SQ_SIZE){1'b1}};
            fwd_valids[i] = fwd_addr_hits_shifted[i] != 0;
            // $display("fwd_hit: %b, i", fwd_hit[i], i);
        end
        found_forward = fwd_valids != 4'h0;
        // $display("ld valid: %b, ld_address: %h, complete fwd: %b, fwd_valids: %b", ex_to_sq_in.ld_valid, ex_to_sq_in.address, found_forward, fwd_valids);

        //Perfom the forwarding
        sq2load_frwd_valid = 0;
        sq2load_frwd_value = 0;
        sq2load_frwd_mask  = 0;
        if(ex_to_sq_in.ld_valid & found_forward) begin
            sq2load_frwd_valid = 1'b1;
            for(int i = 0; i < 4; i++) begin
                // $display("i: %d, valid: %b, idx: %h, value: %h", i, fwd_valids[i], fwd_idx[i], SQ_FIFO[fwd_idx[i]].sq_value);
                if(fwd_valids[i]) begin
                    sq2load_frwd_value |= SQ_FIFO[fwd_idx[i]].fwd_value;
                    sq2load_frwd_mask  |= SQ_FIFO[fwd_idx[i]].fwd_mask;
                end
            end
            //Part-select syntax: [0 * 8 +: 8] is equivalent to [7:0] 
        end
        sq2load_partial_frwd = ex_to_sq_in.ld_valid & found_forward & (sq2load_frwd_mask != 4'hf);

        //Read from dcache if the forward is less data than we are requesting
        sq_to_cache.ld_valid = ex_to_sq_in.ld_valid & (~sq2load_frwd_valid | sq2load_partial_frwd);
        // $display("FORWARD: %b", sq2load_frwd_valid);

        //Outputs
        head_ptr_out   = head_ptr;
        tail_ptr_out   = tail_ptr;

        `ifdef DEBUG_MODE
            sq_debug.available    = available;
            sq_debug.full         = full;
            sq_debug.dcache_stall = dcache_store_stall;
            sq_debug.valid_store  = valid_store;
            sq_debug.ex_to_sq     = ex_to_sq_in;
            sq_debug.head_ptr_out = head_ptr_out;
            sq_debug.tail_ptr_out = tail_ptr_out;
            sq_debug.sq_onc       = sq_onc;
            sq_debug.SQ_FIFO      = SQ_FIFO;
            sq_debug.rob2sq_retire_en   = rob2sq_retire_en;
            sq_debug.sq2load_frwd_valid = sq2load_frwd_valid;
            sq_debug.sq2load_frwd_value = sq2load_frwd_value;
            sq_debug.ld_fwd_hit         = fwd_hit[3];
        `endif
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < `SQ_SIZE; i++) begin
                SQ_FIFO[i] <= 0;
            end
            head_ptr  <= `SD 0;
            tail_ptr  <= `SD 0;
            available <= `SD 0;
        end else begin
            SQ_FIFO   <= `SD SQ_FIFO_next;
            head_ptr  <= `SD head_ptr_next;
            tail_ptr  <= `SD tail_ptr_next;
            available <= `SD available_next;
        end
    end
endmodule

`endif
