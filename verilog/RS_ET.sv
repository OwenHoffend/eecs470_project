`ifndef _RS_ET_
`define _RS_ET_
`timescale 1ns/100ps

`include "./headers/include.svh"
`include "./verilog/rot_pselect_RS.sv"
`include "./verilog/onehot_to_binary_RS.sv"

module RS_ET(
    input clock,
    input reset,

    input DISPATCH_PACKET dispatch_in,
    input CDB_PACKET      cdb_in,

    // early_tag inputs from etbuffer
    input PHYS_REG_TAG    early_tag,
    input                 early_tag_valid, alu_busy,


    //Pointer from the store queue indicating the oldest store
    //that is not complete yet. This is used to determine when 
    //loads should be issued. 
    input SQ_IDX          sq_onc,  //Store queue oldest non-complete
    input SQ_IDX          sq_head, //Head pointer of the store queue
    input                 sq_available,
    input                 sq_full,
    input                 sq_all_complete,

    input cdb_stall, 
    input mem_busy,  //Load is stuck in EX
    //input lq_full, 
    //input sq_full,

    output RS_PACKET     am_rs_out,
    output RS_PACKET     ls_rs_out,

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
    logic [`RS_SIZE-1:0] valid_reduce, alu_can_issue, mult_can_issue, st_can_issue, ld_can_issue,
                                       alu_gnt,       mult_gnt,       st_gnt,       ld_gnt;
    //RS_IDX rs_freed_idx, rs_new_idx;
    RS_IDX rs_input_idx, am_rs_issue_idx, ld_rs_issue_idx, st_rs_issue_idx, ls_rs_issue_idx, alu_gnt_idx, mult_gnt_idx;
    PHYS_REG_TAG early_tag_cam;
    logic last_was_mult, last_was_mult_next;//, cdb_stall_2;

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

    rot_pselect_RS #(.N(`RS_SIZE)) alu_psel (
        .clock(clock),
        .reset(reset),
        .req(alu_can_issue),
        .en(~alu_busy),
        .rotator(JUMPING),
        .gnt(alu_gnt)
    );

    onehot_to_binary_RS #(.N(`RS_SIZE)) alu_penc (
        .oh(alu_gnt),
        .bin(alu_gnt_idx)
    );

    rot_pselect_RS #(.N(`RS_SIZE)) mult_psel (
        .clock(clock),
        .reset(reset),
        .req(mult_can_issue),
        .en(1'b1),
        .rotator(JUMPING),
        .gnt(mult_gnt)
    );

    onehot_to_binary_RS #(.N(`RS_SIZE)) mult_penc (
        .oh(mult_gnt),
        .bin(mult_gnt_idx)
    );

    rot_pselect_RS #(.N(`RS_SIZE)) ld_psel (
        .clock(clock),
        .reset(reset),
        .req(ld_can_issue),
        .en(~mem_busy),
        .rotator(JUMPING),
        .gnt(ld_gnt)
    );

    onehot_to_binary_RS #(.N(`RS_SIZE)) ld_penc (
        .oh(ld_gnt),
        .bin(ld_rs_issue_idx)
    );

    rot_pselect_RS #(.N(`RS_SIZE)) st_psel (
        .clock(clock),
        .reset(reset),
        .req(st_can_issue),
        .en(~mem_busy),
        .rotator(JUMPING),
        .gnt(st_gnt)
    );

    onehot_to_binary_RS #(.N(`RS_SIZE)) st_penc (
        .oh(st_gnt),
        .bin(st_rs_issue_idx)
    );

    function RS_CAM (
        input PHYS_REG_TAG tag,
        input PHYS_REG_TAG tag_et
    );
        for (int i = 0; i < `RS_SIZE; i++) begin // TODO: check when cdb dest tag is not used, ie the zero register/
            if(RS[i].d.valid) begin
                //Check T1
                if ((RS[i].d.T1 == tag) & RS[i].d.T1_used & cdb_in.valid) begin // if early and regular tag are the same, we should update to be regular, not early
                    RS_next[i].d.T1r = 1'b1;
                    RS_next[i].T1_early = 0;
                end else if (~cdb_stall & (RS[i].d.T1 == tag_et) & RS[i].d.T1_used) begin
                    RS_next[i].d.T1r = 1'b1;
                    RS_next[i].T1_early = (tag_et != 0);
                end else begin
                    RS_next[i].d.T1r = RS[i].d.T1r;
                    RS_next[i].T1_early = 1'b0;  // FIXME: after the first round of checks, I think this is setting everything to its previous value
                end
                //Check T2
                if ((RS[i].d.T2 == tag) & RS[i].d.T2_used & cdb_in.valid) begin
                    RS_next[i].d.T2r = 1'b1;
                    RS_next[i].T2_early = 0;
                end else if (~cdb_stall & (RS[i].d.T2 == tag_et) & RS[i].d.T2_used) begin
                    RS_next[i].d.T2r = 1'b1;
                    RS_next[i].T2_early = (tag_et != 0);
                end else begin
                    RS_next[i].d.T2r = RS[i].d.T2r;
                    RS_next[i].T2_early = 1'b0;
                end
            end else begin
                RS_next[i].d.T1r = RS[i].d.T1r;
                RS_next[i].d.T2r = RS[i].d.T2r;
                RS_next[i].T1_early = 1'b0;
                RS_next[i].T2_early = 1'b0;
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
    always_comb begin // --------------------------------------------------------------------------------------------------------------------------- ALWAYS_COMB BEGIN
        last_was_mult_next = 0;
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

        rs_input_idx = 0;

        // default values for issued outputs
        am_rs_issue_idx = 0;
        am_rs_out.valid = 1;

        ls_rs_issue_idx = 0;
        ls_rs_out.valid = 1;

        alu_can_issue = 0; // initialize the request bits for the issued packets
        mult_can_issue = 0;
        st_can_issue = 0;
        ld_can_issue = 0;

        //Allocate dispatch and issue locations
        for (int i = `RS_SIZE; i > 0; i--) begin         // using i-1 so that the i=0 condition kills the loop
            if (~RS[i-1].d.valid) begin                  // Dispatch Index
                rs_input_idx = i-1;
            end else if(
                (RS[i-1].d.T1r | ~RS[i-1].d.T1_used) &          //T1 issue condition
                (RS[i-1].d.T2r | ~RS[i-1].d.T2_used)) begin     //T2 issue condition
                
                //Subtracting sq_head from both sides of this equation ensures the comparison is made as if 
                //head pointer were stationed at 0, allowing the comparison to work despite circular buffer wraparound
                //NOTE: I moved the sq_head subtraction for the sq_onc value into the onc computation itself, because
                //that made the computation more efficient
                //if(RS[i-1].d.rd_mem) begin //TODO: BAD, remove this
                //    $display("idx: %h, sq_onc: %h, RS[i-1].d.sq_idx: %h, sq_head: %h", i-1, sq_onc, RS[i-1].d.sq_idx, sq_head);
                //end

                if (RS[i-1].d.rd_mem) begin //Load issue condition
                    if((sq_onc == 0 & (~sq_available | (sq_full & sq_all_complete))) | (RS[i-1].d.sq_idx - sq_head <= sq_onc))
                        ld_can_issue[i-1] = 1;
                end else if (RS[i-1].d.wr_mem) begin
                    st_can_issue[i-1] = 1;
                end else if (RS[i-1].d.mult) begin
                    mult_can_issue[i-1] = 1;
                end else begin
                    alu_can_issue[i-1] = 1;
                end
            end

            //Completing branches
            if (cdb_in.valid) begin
                if(cdb_in.squash_enable & ((cdb_in.branch_mask & RS[i-1].branch_tag) != 0)) begin // kill squashes for the next cycle
                    RS_next[i-1].d.valid = 1'b0;
                end else begin //Clear out mask bit for non-squashes
                    RS_next[i-1].branch_tag &= ~cdb_in.branch_mask;
                end
            end 
        end
        
        // assign the index for am_rs_issue_idx and validity of rs_outputs
        if ((mult_can_issue[mult_gnt_idx]) | (alu_can_issue[alu_gnt_idx] & ~alu_busy)) begin
            if (last_was_mult & (alu_can_issue[alu_gnt_idx] & ~alu_busy)) begin // if the last instruction was a mult and an alu is ready
                am_rs_issue_idx = alu_gnt_idx;
                last_was_mult_next = 0;
            end else if (mult_can_issue[mult_gnt_idx]) begin
                am_rs_issue_idx = mult_gnt_idx;
                last_was_mult_next = 1;
            end else begin
                am_rs_issue_idx = alu_gnt_idx;
                am_rs_out.valid = ~alu_busy;
                last_was_mult_next = 0;
            end
        end else begin
            am_rs_issue_idx = 0;
            am_rs_out.valid = 0;
            last_was_mult_next = 0;
        end
        if (cdb_stall)// | cdb_stall_2) // if we have to stall due to a load completion, invalidate the am_rs output
            am_rs_out.valid = 0;

        // assign load/store packet output idx
        if (ld_can_issue[ld_rs_issue_idx] & ~mem_busy) begin
            ls_rs_issue_idx = ld_rs_issue_idx;
            ls_rs_out.valid = 1;
        end else if (st_can_issue[st_rs_issue_idx] & ~mem_busy) begin
            ls_rs_issue_idx = st_rs_issue_idx;
            ls_rs_out.valid = 1;
        end else begin
            ls_rs_issue_idx = 0;
            ls_rs_out.valid = 0;
        end
        if (cdb_stall)// | cdb_stall_2) // if we have to stall due to a load completion, invalidate the am_rs output
            ls_rs_out.valid = 0;
        
        // check all rs_out versions for squashes
        if (cdb_in.valid & cdb_in.squash_enable) begin
            if ((RS[am_rs_issue_idx].branch_tag & cdb_in.branch_mask) != 0) begin
                am_rs_out.valid = 0;
            end
            if ((RS[ls_rs_issue_idx].branch_tag & cdb_in.branch_mask) != 0) begin
                ls_rs_out.valid = 0;
            end
        end

        //Update tags from CDB result ---- has to happen before dispatch next state
        //RS_CAM(cdb_in.cdb_tag, cdb_in.next_cdb_tag);
        
        `ifdef EARLY_TAG_BROADCAST
        early_tag_cam = early_tag_valid ? early_tag : 0;
        `else
        early_tag_cam = 0;
        `endif
        //$display("et_valid:%b tag:%h", early_tag_valid, early_tag_cam);
        RS_CAM(cdb_in.cdb_tag, early_tag_cam);  // sets next state values

        //Perform dispatch
        if (full) begin // handles case where we want to dispatch and issue on a full RS
            rs_input_idx = ls_rs_out.valid ? ls_rs_issue_idx : am_rs_issue_idx;
        end
        if((dispatch_in.valid & ~dispatch_in.illegal & ~dispatch_in.halt) & ~(cdb_in.squash_enable & cdb_in.valid) & (~full | (ls_rs_out.valid | am_rs_out.valid))) begin
            RS_next[rs_input_idx].d           = dispatch_in;
            RS_next[rs_input_idx].branch_tag  = dispatch_in.branch_tag; // update branch tag based on global branch tag register
            RS_next[rs_input_idx].d.T1r         = ~dispatch_in.T1_used ? 1 : (dispatch_in.T1 == cdb_in.cdb_tag) // if the tag isn't used, it's ready to go
                                                    & dispatch_in.T1_used 
                                                    & cdb_in.valid & cdb_in.T_used ? 1 : dispatch_in.T1r; // if the incoming tag clears the incoming instruction, set it to ready
            RS_next[rs_input_idx].d.T2r         = ~dispatch_in.T2_used ? 1 : (dispatch_in.T2 == cdb_in.cdb_tag) 
                                                    & dispatch_in.T2_used & cdb_in.valid 
                                                    & cdb_in.T_used ? 1 : dispatch_in.T2r; // if the tag is the zero register, the data is ready by default
        end

        //Perform issue
        am_rs_out.rs = RS[am_rs_issue_idx];
        if (am_rs_out.valid & ~((am_rs_issue_idx == rs_input_idx) & dispatch_in.valid & ~(cdb_in.squash_enable & cdb_in.valid))) // don't clear the entry if we're full, dispatching, and issuing
            RS_next[am_rs_issue_idx].d.valid = 0;

        ls_rs_out.rs = RS[ls_rs_issue_idx];
        if (ls_rs_out.valid & ~((ls_rs_issue_idx == rs_input_idx) & dispatch_in.valid & ~(cdb_in.squash_enable & cdb_in.valid))) 
            RS_next[ls_rs_issue_idx].d.valid = 0;

        if(cdb_in.valid) begin
            am_rs_out.rs.branch_tag &= ~cdb_in.branch_mask;
            ls_rs_out.rs.branch_tag &= ~cdb_in.branch_mask;
            RS_next[rs_input_idx].d.branch_tag &= ~cdb_in.branch_mask;
        end

        /*// set early tags
        //          .. early tags have to be sent the same cycle 
        //          .. that they are set because of the wakeup cycle delay

        am_rs_out.rs.T1_early = RS[am_rs_issue_idx].T1_early;
        am_rs_out.rs.T2_early = RS[am_rs_issue_idx].T2_early;

        ld_rs_out.rs.T1_early = RS[ld_rs_issue_idx].T1_early;
        ld_rs_out.rs.T2_early = RS[ld_rs_issue_idx].T2_early;

        st_rs_out.rs.T1_early = RS[st_rs_issue_idx].T1_early;
        st_rs_out.rs.T2_early = RS[st_rs_issue_idx].T2_early; */

        `ifdef DEBUG_MODE
            //debug output - is the current output valid?
            rs_debug.num_entries_actual = 0;
            for(int i = 0; i < `RS_SIZE; i++) begin
                rs_debug.can_issue[i] = RS[i].d.valid & RS[i].d.T1r & RS[i].d.T2r;
                if(RS[i].d.valid)
                    rs_debug.num_entries_actual++;
            end
            rs_debug.valid_issue_out = am_rs_out.valid;
            rs_debug.rs_input_idx_out = rs_input_idx;
            rs_debug.rs_issue_idx_out = am_rs_issue_idx;
            rs_debug.rs_entries = RS;
            rs_debug.next_rs_entries = RS_next;
            rs_debug.ls_rs_issue_idx_out = ls_rs_issue_idx;
            rs_debug.valid_ls_issue_out = ls_rs_out.valid;
        `endif
    end // ---------------------------------------------------------------------------------------------------------------------------------------- ALWAYS_COMB END

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            //cdb_stall_2 = 0;
            for (int i = 0; i < `ROB_SIZE; i++) begin
                RS[i] <= `SD 0;
            end
            last_was_mult <= `SD 0;
        end else if (~cdb_stall) begin
            RS <= `SD RS_next;
            last_was_mult <= `SD last_was_mult_next;
        end else begin//if (~cdb_stall_2) begin
            //cdb_stall_2 = 1;
            for (int i = 0; i < `RS_SIZE; i++) begin
                RS[i].d.T1r <= RS_next[i].d.T1r;
                RS[i].d.T2r <= RS_next[i].d.T2r;
                RS[i].d.valid <= RS_next[i].d.valid; // allow squashes while cdb is stalled
                RS[i].d.branch_tag <= RS_next[i].d.branch_tag;
                // TODO: factor in early tag getting reset -- maybe if next.t1r != RS.t1r -> early = 0
                // TODO: stop execute from stalling
            end
        end //else begin
        //    cdb_stall_2 = 0;
        //    for (int i = 0; i < `RS_SIZE; i++) begin
        //        RS[i].d.T1r = RS_next[i].d.T1r;
        //        RS[i].d.T2r = RS_next[i].d.T2r;
        //    end
        //end
    end
endmodule

`endif
