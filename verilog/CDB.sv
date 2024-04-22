`ifndef _CDB__
`define _CDB__
`timescale 1ns/100ps
`include "./headers/include.svh"

// goal of CDB - avoid having to stall the pipeline. Should be achievable with CDB_SIZE = ROB_SIZE

// TODO - remove full signal if it does not toggle

module CDB (
    input                       clock,               // CLOCK
    input                       reset,               // Synchronous reset/clear the Buffer
    
    // receive pre-constructed CDB packets
    input  EX_PACKET            alu_packet,          // ALU packet, may or may not be valid. Branch is ALU type
    input  EX_PACKET            load_packet,         // LD  packet, may or may not be valid.
    input  EX_PACKET            mul_packet,          // MUL result, may or may not be valid.

    output CDB_PACKET           cdb,                 // what gets broadcasted
    output logic                available,
    output logic                full
`ifndef ALLOW_MULTIPLE_CDB_ENQUEUE
    , output logic              cdb_stall            // conflict on the cdb bus
`endif
);

    EX_PACKET   [`CDB_SIZE-1:0]     buff_current, buff_next;

    CDB_IDX     head_ptr_next, tail_ptr_next;
    logic [1:0] num_input_valid;
    logic       alu_valid, load_valid, mul_valid, all_invalid_next;
    logic       available_next;    // available means atleast 1 valid entry in buffer

    logic [`CDB_SIZE-1:0] buff_valids;
    CDB_IDX              head_ptr;
    CDB_IDX              tail_ptr;

    /** broadcast spec

        head broadcasts its data and tag (recall data will be written to RF)
        head + 1 will broadcast tag only. This lets a dependent instruction
            issue early while grabbing garbage data from RF. In next cycle,
            head broadcasts data to mux input. Mux select picks this data
            over garbage data from RF
    
        when buffer is empty, add entries onto CDB. Empty head gets broadcasted,
            and next_tag is `ZERO_REG
            
        when buffer has 1 entry only, add entries onto CDB, broadcast current
            head. Head's next_tag is `ZERO_REG

    */

    /** squashing spec

        if head.squash_enable, then run a for-loop from head+1 to CDB_SIZE-1, checking
        ***head.new_mask*** with the branch mask of every other valid instruction. 
        If there is a hit, then set the valid bit to zero.

        squashing is implemented in EX-CDB pipeline register, so assume all CDB packets
        that come in are pre-squashed.

        naive implementation: do not update head to next resulting valid entry, just
        set update head to head + 1.

        possible optimizations:
        1. update head to next valid entry
        2. update head_next_tag to be next valid entry after next valid entry
        3. update tail to last valid entry + 1
        4. early head/tag broadcast when empty/1 entry only
            - these would be better handled with forwarding from EX
        
    */
    
    /** execution flow

        - head squashes if branch
        - write entries into CDB_next
        - head and tail update

    */

    always_comb begin

        buff_next = buff_current;

        // convenience valid signals
        alu_valid  = alu_packet.valid;
        load_valid = load_packet.valid;
        mul_valid  = mul_packet.valid;
        
        num_input_valid  = alu_valid + load_valid + mul_valid;
 
        full = (head_ptr == tail_ptr) & available;
        
        `ifndef ALLOW_MULTIPLE_CDB_ENQUEUE
            cdb_stall = 0;
        `endif

        /*** CDB insertion at Tail ***/

        // because `CDB_SIZE = `ROB_SIZE, there is always room in the CDB
        // also, every cycle, the head broadcasts, so we can always put atleast 1 entry on buffer
        if (!full) begin
        // use a priority select in this order: LOAD, ALU, MUL
            buff_next[tail_ptr] = load_valid ? load_packet : 
                                  alu_valid  ? alu_packet  :
                                  mul_valid  ? mul_packet  : buff_current[tail_ptr];
    
            // tail + 1 is load if both alu and load valid
            // tail + 1 is mul  if only 1 of {alu, load} is valid
`ifdef ALLOW_MULTIPLE_CDB_ENQUEUE
            buff_next[tail_ptr + 1'b1] = (alu_valid & load_valid) ? alu_packet :
                                    (mul_valid & (alu_valid | load_valid)) ? mul_packet : buff_current[tail_ptr+2'b01]; 
        
            // tail + 2 is mul if other 2 valid
            buff_next[tail_ptr + 2'b10] = (alu_valid & load_valid & mul_valid)   ? mul_packet : buff_current[tail_ptr+2'b10];
`else
            cdb_stall = (alu_valid | mul_valid) & load_valid; 
            if(cdb_stall)
                buff_next[tail_ptr + 1'b1] = alu_valid  ? alu_packet : (mul_valid  ? mul_packet : buff_current[tail_ptr + 1]);
`endif
        end
        
        /*** end CDB insertion at Tail ***/

        /*** tail_ptr_next assigned at end of comb block ***/

        // data
        cdb.head_data = buff_current[head_ptr].data;

        // tags
        cdb.cdb_tag = buff_current[head_ptr].tag;
        cdb.cdb_arch_tag = buff_current[head_ptr].arch_tag;
        cdb.T_used = buff_current[head_ptr].T_used;
        cdb.rob_idx = buff_current[head_ptr].rob_idx;
        cdb.sq_idx  = buff_current[head_ptr].sq_idx;
        cdb.is_store = buff_current[head_ptr].is_store;
        cdb.next_cdb_tag = buff_current[head_ptr + 1'b1].tag;
        cdb.branch_tag = buff_current[head_ptr].branch_tag;

        // status bits
        cdb.full = full;
        cdb.valid = buff_current[head_ptr].valid;

        // branching info
        cdb.squash_enable = buff_current[head_ptr].squash_enable & cdb.valid;
`ifdef GSHARE
	cdb.actual_taken = buff_current[head_ptr].actual_taken & cdb.valid;
`endif
        cdb.branch_mask = buff_current[head_ptr].branch_mask;
        cdb.NPC         = buff_current[head_ptr].NPC;
        cdb.uncond_branch = buff_current[head_ptr].uncond_branch;
        
        // $display("buff_current[head_ptr].valid:%b", buff_current[1].valid);
        // $display("cdb_valid:%b", cdb.valid);

        // bit-wise AND between new_mask and branch_mask of ALL CDB entries
        // only invalidate entries if there is a hit and the entry was already valid
        // invalid entries should stay invalid
        if (cdb.valid) begin
            for (int i = 0; i < `CDB_SIZE; i++) begin
                if (buff_current[i].valid) begin
                    if(cdb.squash_enable)
                        buff_next[i].valid = ~|(cdb.branch_mask & buff_current[i].branch_tag);
                    else
                        buff_next[i].branch_tag &= ~cdb.branch_mask;
                end
            end
        end

        // invalidate the head entry for next cycle
        // except if head == tail and entries being added
        if (~(head_ptr == tail_ptr & num_input_valid != 0)) begin
            buff_next[head_ptr].valid = 0;
            buff_next[head_ptr].squash_enable = 0;
        end
        // $display("buff_next[head_ptr].valid : %b", buff_next[head_ptr].valid);    

        head_ptr_next = head_ptr + available; // if available, h+1, else h

        // if head+1 is invalid, its tag should not be broadcasted
        if (~buff_next[head_ptr + 1'b1].valid)
            cdb.next_cdb_tag = 0;

        // if none of the next-cycle buffer entries are valid, 
        for (int i = 0; i < `CDB_SIZE; i++) begin
            buff_valids[i] = buff_next[i].valid;
        end
        all_invalid_next = ~|buff_valids;

        /*  if empty & new valid entry, available_next = 1
            if nonempty, head is valid, no new entries
            and head is the only entry, available_next = 0
        */
        case(available)
            1'b0: available_next = num_input_valid > 0;    // a new entry comes in
            1'b1: available_next = ~all_invalid_next;   // CDB popped, no new entries, and (head + 1 = tail or all entries squashed)

            // ~((cdb.valid & (num_input_valid == 0)) & ((head_ptr + 1'b1 == tail_ptr) | (cdb.squash_enable & all_invalid_next)))
        endcase

        // if next cycle buffer is all empty, tail == head, otherwise increment
        tail_ptr_next = (available_next) ? tail_ptr + num_input_valid : head_ptr_next;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < `CDB_SIZE; i++) begin
                buff_current[i] <= `SD 0;
            end
            head_ptr  <= `SD 0;
            tail_ptr  <= `SD 0;
            available <= `SD 0;
        end else begin
            buff_current <= `SD buff_next;
            head_ptr     <= `SD head_ptr_next;
            tail_ptr     <= `SD tail_ptr_next;
            available    <= `SD available_next;
        end
    end

endmodule

`endif
