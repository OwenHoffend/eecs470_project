`ifndef _ROB__
`define _ROB__
`timescale 1ns/100ps
`include "./headers/include.svh"

module ROB (
    input                  clock,               // DEFINITELY NEEDED: CLOCK
    input                  reset,               // DEFINITELY NEEDED: Synchronous reset/clear the ROB
    input                  dcache_store_stall,  // Stall the ROB if the memory is currently processing a store
    
    //Dispatch stage
    input ROB_PACKET       rob_packet_in,
        
    //Complete stage
    input  CDB_PACKET      cdb_in,              // DEFINITELY NEEDED: Input from CDB for complete and branch recovery (e.g. T/NT)

`ifdef DEBUG_MODE
    output ROB_ENTRY [`ROB_SIZE-1:0] rob_debug,
`endif

    output ROB_IDX         head_ptr_out,        // Debug Output    
    output ROB_ENTRY       head_packet,         // DEFINITELY NEEDED: Head tag and dest info so Retire stage can free phyiscal registers
    output ROB_IDX         tail_ptr_out,        // DEFINITELY NEEDED: Tail pointer out for branch checkpointing
    output ROB_ENTRY       tail_packet,         // NOT SURE: Tail tag and dest info for branch checkpointing
    output logic           rob2sq_retire_en,
    output logic           rob_retire_cond,
    output logic           full,                // DEFINITELY NEEDED: Are we at capacity?
    output logic           available            // DEFINITELY NEEDED: Is there something in the ROB?
);

    //ROB Signals
    ROB_ENTRY [`ROB_SIZE-1:0] ROB_current, ROB_next;
    ROB_IDX head_ptr, tail_ptr, head_ptr_next, tail_ptr_next;
    logic available_next;
    logic retire_cond;

    always_comb begin

    `ifdef DEBUG_MODE
        rob_debug = ROB_current;
    `endif

        //Complete logic factoring in stores
        //Can't retire stores until other pending stores are done 
        retire_cond = ROB_current[head_ptr].complete & available & 
                        ~(dcache_store_stall & ROB_current[head_ptr].is_store);
        rob2sq_retire_en = ROB_current[head_ptr].complete & available & ROB_current[head_ptr].is_store;

        // ROB state indicators
        case(available)
            1'b0: available_next = rob_packet_in.valid;
            1'b1: available_next = ~((head_ptr + 1'b1 == tail_ptr) & 
                                    (retire_cond & ~rob_packet_in.valid));
        endcase

        full = (head_ptr == tail_ptr) & available;
        ROB_next  = ROB_current;
        tail_ptr_next  = tail_ptr;
        if (cdb_in.valid & cdb_in.squash_enable) begin                        // Clear ROB on checkpoint 
            if(cdb_in.rob_idx == head_ptr)
                available_next = 0;
            tail_ptr_next = cdb_in.rob_idx + 1'b1;             // if we squash, just make the new tail_ptr the squash_idx
        end else if(rob_packet_in.valid & (~full | retire_cond)) begin 
            tail_ptr_next  = tail_ptr + 1'b1; // Current tail pointer is written, increment to next free slot
            // Tail_ptr starts at 0, this is where we want our first instruction to be
            ROB_next[tail_ptr].dispatch_NPC   = rob_packet_in.dispatch_NPC;
            ROB_next[tail_ptr].T_used         = rob_packet_in.T_used;
            ROB_next[tail_ptr].d_tag          = rob_packet_in.T;
            ROB_next[tail_ptr].d_tag_old      = rob_packet_in.Told;
            ROB_next[tail_ptr].d_tag_old_arch = rob_packet_in.dest_reg;
            ROB_next[tail_ptr].is_store       = rob_packet_in.is_store;
            ROB_next[tail_ptr].halt           = rob_packet_in.halt;
            ROB_next[tail_ptr].complete       = rob_packet_in.halt;
`ifdef DEBUG_MODE
            ROB_next[tail_ptr].inst           = rob_packet_in.inst; 
            ROB_next[tail_ptr].branch_mask    = rob_packet_in.branch_mask;
            ROB_next[tail_ptr].branch_tag     = rob_packet_in.branch_tag;
`endif
        end

        //Complete
        if(cdb_in.valid & available) begin
            ROB_next[cdb_in.rob_idx].complete = 1;
            `ifdef DEBUG_MODE
                for(int i = 0; i < `ROB_SIZE; i++)
                    ROB_next[i].branch_tag &= ~cdb_in.branch_mask;
            `endif
        end

        //Retire 
        head_ptr_next = retire_cond ? head_ptr + 1'b1 : head_ptr;  // if our head is complete, retire
        
        //Output
        head_packet  = ROB_current[head_ptr];
        tail_packet  = ROB_current[tail_ptr-1'b1];
        head_ptr_out = head_ptr;
        tail_ptr_out = tail_ptr;

        // Send retire condition to dispatch
        rob_retire_cond = retire_cond;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < `ROB_SIZE; i++) begin
                ROB_current[i] <= `SD 0;
            end
            head_ptr  <= `SD 0;
            tail_ptr  <= `SD 0;
            available <= `SD 0;
        end else begin
            ROB_current <= `SD ROB_next;
            head_ptr    <= `SD head_ptr_next;
            tail_ptr    <= `SD tail_ptr_next;
            available   <= `SD available_next;
        end
    end
endmodule

`endif
