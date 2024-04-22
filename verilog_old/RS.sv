`ifndef _RS__
`define _RS__
`timescale 1ns/100ps

`include "./headers/include.svh"

module RS(
    input clock,
    input reset,
    input load_busy,

    input DISPATCH_PACKET dispatch_in,
    input CDB_PACKET      cdb_in,

    //Pointer from the store queue indicating the oldest store
    //that is not complete yet. This is used to determine when 
    //loads should be issued. 
    input SQ_IDX          sq_onc,  //Store queue oldest non-complete
    input SQ_IDX          sq_head, //Head pointer of the store queue

    output RS_PACKET     rs_out,

    `ifdef DEBUG_MODE
        output RS_DEBUG_PACKET rs_debug,
    `endif

    output logic         full,
    output logic         available  
);
 
/*
    parameter RS_IDX [`RS_SIZE-1:0] INIT;
    generate;
        for(int i = 0; i < `RS_SIZE; i++) begin
            INIT[i] = i;
        end
    endgenerate
*/

    RS_ENTRY [`RS_SIZE-1:0] RS, RS_next;
    logic [`RS_SIZE-1:0] valid_reduce;
    //RS_IDX rs_freed_idx, rs_new_idx;
    RS_IDX rs_input_idx, rs_issue_idx;
    //logic  rs_free_enable;

/*
    FIFO #(
        .BIT_WIDTH($clog2(`RS_SIZE)),
        .FIFO_DEPTH(`RS_SIZE),
        .INIT(INIT)
    ) RS_freelist (
        //Inputs
        .clock(clock),
        .reset(reset),
        .enqueue(rs_free_enable),              
        .data_in(rs_freed_idx),     
        .dequeue(dispatch_in.valid),
        //Outputs
        .head_packet(rs_new_idx),           
        .full(full),                 
        .available(available)             
    );
*/

    function RS_CAM (
        input PHYS_REG_TAG tag,
        input PHYS_REG_TAG early_tag
    );
        for (int i = 0; i < `RS_SIZE; i++) begin // TODO: check when cdb dest tag is not used, ie the zero register/
            if(RS[i].d.valid & cdb_in.valid) begin
                //Check T1
                if ((RS[i].d.T1 == tag) & RS[i].d.T1_used) begin // if early and regular tag are the same, we should update to be regular, not early
                    RS_next[i].d.T1r = 1'b1;
                    //RS_next[i].T1_early = 0;
                end else if ((RS[i].d.T1 == early_tag) & RS[i].d.T1_used) begin // if early and regular tag are the same, we should update to be regular, not early
                    RS_next[i].d.T1r = 1'b1;
                    //RS_next[i].T1_early = 1;
                end else begin
                    RS_next[i].d.T1r = RS[i].d.T1r;
                    //RS_next[i].T1_early = 1'b0;  // FIXME: after the first round of checks, I think this is setting everything to its previous value
                end
                //Check T2
                if ((RS[i].d.T2 == tag) & RS[i].d.T2_used) begin
                    RS_next[i].d.T2r = 1'b1;
                    //RS_next[i].T2_early = 0;
                end else if ((RS[i].d.T2 == early_tag) & RS[i].d.T2_used) begin
                    RS_next[i].d.T2r = 1'b1;
                    //RS_next[i].T2_early = 1;
                end else begin
                    RS_next[i].d.T2r = RS[i].d.T2r;
                    //RS_next[i].T2_early = 1'b0;
                end
            end else begin
                RS_next[i].d.T1r = RS[i].d.T1r;
                RS_next[i].d.T2r = RS[i].d.T2r;
                //RS_next[i].T1_early = 1'b0;
                //RS_next[i].T2_early = 1'b0;
            end
        end
    endfunction

/* 
    In the future, we'd like to maintain a "free list" of RS entries.
    Checkpointing these for branches can be done by copying the free
    list to a seperate FIFO based on the branch mask. RS entries that
    are issued after this point are added to the FIFO that represents the 
    current and below/earlier/less dependent branch masks. When a checkpoint 
    is restored, copy that entire FIFO back into the primary free list. 
    This prevents you from having to concatenate two partially-full FIFO.  
*/
    always_comb begin
        
        for (int i = 0; i < `RS_SIZE; i++) begin
            valid_reduce[i] = RS[i].d.valid;
            `ifdef DEBUG_MODE
                rs_debug.rs_input_idx_out[i] = RS[i].branch_tag;
            `endif
        end
        
        RS_next = RS; 
        available = 1'b0;
        for (int i = 0; i < `RS_SIZE; i++) begin
            available |= RS[i].d.valid;
        end

        full = 1'b1;
        for (int i = 0; i < `RS_SIZE; i++) begin
            full &= RS[i].d.valid;
        end
        //TODO: add stalls for lq_full and sq_full

        //TODO: Fix this dumb version - this has no rotation, and can be prone to starvation
        //Allocate dispatch and issue locations
        rs_input_idx = 0;
        rs_issue_idx = 0;
        rs_out.valid = 0;
        for (int i = `RS_SIZE; i > 0; i--) begin         // using i-1 so that the i=0 condition kills the loop
            if (~RS[i-1].d.valid) begin                  // Dispatch Index
                rs_input_idx = i-1;
            end else if(
                (RS[i-1].d.T1r | ~RS[i-1].d.T1_used) &  //T1 issue condition
                (RS[i-1].d.T2r | ~RS[i-1].d.T2_used) &  //T2 issue condition
                //Subtracting sq_head from both sides of this equation ensures the comparison is made as if 
                //head pointer were stationed at 0, allowing the comparison to work despite circular buffer wraparound
                //NOTE: I moved the sq_head subtraction for the sq_onc value into the onc computation itself, because
                //that made the computation more efficient
                ((sq_onc == 0 | (RS[i-1].d.sq_idx - sq_head <= sq_onc)) | ~RS[i-1].d.rd_mem) //Load issue condition
            ) begin // Issue Index
                rs_issue_idx = i-1;
                rs_out.valid = 1;
            end

            if ((cdb_in.valid & cdb_in.squash_enable) &&
               ((cdb_in.branch_mask & RS[i-1].branch_tag) != 0)) begin // mask 0010 tag 1110
                RS_next[i-1].d.valid = 1'b0;
                if (i-1 == rs_issue_idx) begin // in a branch, make sure we don't output a squashed instruction
                    rs_out.valid = 0;
                end
            end
        end
        
        //Update tags from CDB result ---- has to happen before dispatch next state
        //RS_CAM(cdb_in.cdb_tag, cdb_in.next_cdb_tag);
        RS_CAM(cdb_in.cdb_tag, 0);

        //Perform dispatch
        if (full) begin // handles case where we want to dispatch and issue on a full RS
            rs_input_idx = rs_issue_idx;
        end
        if((dispatch_in.valid & ~dispatch_in.illegal & ~dispatch_in.halt) & ~(cdb_in.squash_enable & cdb_in.valid)) begin
            RS_next[rs_input_idx].d           = dispatch_in;
            RS_next[rs_input_idx].branch_tag  = dispatch_in.branch_tag; // update branch tag based on global branch tag register
            RS_next[rs_input_idx].d.T1r         = ~dispatch_in.T1_used ? 1 : (dispatch_in.T1 == cdb_in.cdb_tag) // if the tag isn't used, it's ready to go
                                                    & dispatch_in.T1_used 
                                                    & cdb_in.valid & cdb_in.T_used ? 1 : dispatch_in.T1r; // if the incoming tag clears the incoming instruction, set it to ready
            RS_next[rs_input_idx].d.T2r         = ~dispatch_in.T2_used ? 1 : (dispatch_in.T2 == cdb_in.cdb_tag) 
                                                    & dispatch_in.T2_used & cdb_in.valid 
                                                    & cdb_in.T_used ? 1 : dispatch_in.T2r; // if the tag is the zero register, the data is ready by default
                                                                   // TODO: if an instruction coming in has its tag cleared, how do we clear its tags?
        end

        //Perform issue
        rs_out.rs = RS[rs_issue_idx];
        if (rs_out.valid & ~((rs_issue_idx == rs_input_idx) & dispatch_in.valid & ~(cdb_in.squash_enable & cdb_in.valid))) // if our indeces are the same and the output is valid, we must be full, so we don't want to clear the valid bit
            RS_next[rs_issue_idx].d.valid = 0;

        // TODO: remove for early broadcast
        for (int i = 0; i < `RS_SIZE; i++) begin
            RS_next[i].T1_early = 0;
            RS_next[i].T2_early = 0;
        end
        rs_out.rs.T1_early = 0;
        rs_out.rs.T2_early = 0;

        `ifdef DEBUG_MODE
            //debug output - is the current output valid?
            rs_debug.num_entries_actual = 0;
            for(int i = 0; i < `RS_SIZE; i++) begin
                rs_debug.can_issue[i] = RS[i].d.valid & RS[i].d.T1r & RS[i].d.T2r;
                if(RS[i].d.valid)
                    rs_debug.num_entries_actual++;
            end
            rs_debug.valid_issue_out = RS[rs_issue_idx].d.valid & (RS[rs_issue_idx].d.T1r & RS[rs_issue_idx].d.T2r) & 
                            ~(((RS[rs_issue_idx].branch_tag & cdb_in.branch_mask) != 0) & cdb_in.squash_enable & cdb_in.valid);
            rs_debug.rs_input_idx_out = rs_input_idx;
            rs_debug.rs_issue_idx_out = rs_issue_idx;
            rs_debug.rs_entries = RS;
            rs_debug.next_rs_entries = RS_next;
        `endif
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < `ROB_SIZE; i++) begin
                RS[i] <= `SD 0;
            end
        end else begin
            RS <= `SD RS_next;
        end
    end
endmodule

`endif
