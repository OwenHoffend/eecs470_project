`ifndef _DISPATCH__
`define _DISPATCH__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/FIFO.sv"
`include "./verilog/RAT.sv"
`include "./verilog/decoder.sv"
`include "./verilog/btag_tracker.sv"

module dispatch(
    input                     clock,
    input                     reset,

    input  FETCH_PACKET       fetch_packet_in, // dispatch a new instruction
    input  CDB_PACKET         cdb_in, // complete (updating the RAT) and squashing
    input  BRANCH_STACK_ENTRY checkpoint_entry_in, // checkpointing
    input  ROB_ENTRY          ROB_head_entry, // retire
    input                     rob_retire_cond, // retire but better
    input                     ROB_full, // structural hazard
    input                     ROB_available,
    input  ROB_IDX            ROB_tail_ptr_in, // data carry-through
    input  SQ_IDX             sq_tail_ptr_in,
    input                     RS_full, // structural hazard
    input                     sq_full,

`ifdef DEBUG_MODE
    // freelist
    output logic                                freelist_full,
    output logic                                freelist_available,
    output logic [$clog2(`FREELIST_SIZE)-1:0]   freelist_head,
    output logic [$clog2(`FREELIST_SIZE)-1:0]   freelist_tail,
    output PHYS_REG_TAG  [`FREELIST_SIZE-1:0]   freelist_debug,
    
    // RAT
    output PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat_debug,
    output              [`ARCH_REGFILE_SIZE-1:0] rat_debug_ready,

    // BTAG TRACKER
    output BRANCH_MASK                           branch_tag_out,  //Global branch tag - given to all new instructions
    output BRANCH_MASK                           branch_tag_next,
    output logic                                 bs_stall, //Normally, this is included in dispatch_stall, but we may want to see it on its own
`endif

    output DISPATCH_PACKET    dispatch_packet_out,
    output ROB_PACKET         rob_packet_out,
    output BRANCH_MASK        branch_mask_out, //Global branch mask - updated whenever a new branch is seen
    output logic              stall_out, // to fetch / fetch buffer
    output logic              checkpoint_write, // to BRAT
    output BRANCH_STACK_ENTRY checkpoint_entry_out // to BRAT

);
    logic freelist_enqueue_enable;
    logic freelist_dequeue_enable;
    logic stall;
    logic decode_valid;
`ifndef DEBUG_MODE //Local logic signal for non-debug mode. Otherwise, it's defined as an output logic port.
    BRANCH_MASK branch_tag_out;
    logic       bs_stall; //Branch stack full
`endif
    ARCH_REG_TAG opa_idx, opb_idx;
    logic decoded_branch, branch_dispatch;
    PHYS_REG_TAG FIFO_head_packet;

    decoder decoder_0 (
        // Inputs 
        .if_packet(fetch_packet_in),

        // Outputs
        .dst_select(dispatch_packet_out.dst_select),
        .opa_select(dispatch_packet_out.opa_select),
        .opb_select(dispatch_packet_out.opb_select),
        .dst_idx(dispatch_packet_out.dest_reg),
        .opa_idx(opa_idx),
        .opb_idx(opb_idx),
        .alu_func(dispatch_packet_out.alu_func),
        .rd_mem(dispatch_packet_out.rd_mem), 
        .wr_mem(dispatch_packet_out.wr_mem),
        .cond_branch(dispatch_packet_out.cond_branch), 
        .uncond_branch(dispatch_packet_out.uncond_branch),
        .csr_op(dispatch_packet_out.csr_op),
        .mult(dispatch_packet_out.mult),
        .halt(dispatch_packet_out.halt),
        .illegal(dispatch_packet_out.illegal),
        .valid_inst(decode_valid),
        .T_used(dispatch_packet_out.T_used),
        .T1_used(dispatch_packet_out.T1_used),
        .T2_used(dispatch_packet_out.T2_used)
    );

    FIFO #(
        .DATA_TYPE(PHYS_REG_TAG), 
        .FIFO_DEPTH(`FREELIST_SIZE), 
        .INIT_AVAILABLE(1)
    ) freelist_0 (
        // Inputs
        .clock(clock),
        .reset(reset),
        .checkpoint_enable(cdb_in.valid & cdb_in.squash_enable),
        .checkpoint_head_ptr_in(checkpoint_entry_in.freelist_head_ptr),    
        .enqueue(freelist_enqueue_enable),
        .data_in(ROB_head_entry.d_tag_old),
        .dequeue(freelist_dequeue_enable),

    `ifdef DEBUG_MODE
        .full(freelist_full),
        .available(freelist_available),
        .head_ptr_out(freelist_head),
        .tail_ptr_out(freelist_tail),
        .FIFO_debug_out(freelist_debug),
    `endif
        // Outputs
        .head_packet(FIFO_head_packet),
        .checkpoint_head_ptr_out(checkpoint_entry_out.freelist_head_ptr)
    );

    RAT map_table_0 (
        // Inputs
        .clock(clock),
        .reset(reset),
        .stall(stall),

        .checkpoint_write(cdb_in.valid & cdb_in.squash_enable),
        .checkpoint_rat_value_in(checkpoint_entry_in.rat_value),
        .checkpoint_rat_ready_in(checkpoint_entry_in.rat_ready),

        .dst_idx(dispatch_packet_out.dest_reg),
        .write_value(dispatch_packet_out.T),
        .write_valid(freelist_dequeue_enable),        
        .opa_idx(opa_idx),
        .opa_valid(dispatch_packet_out.T1_used),
        .opb_idx(opb_idx),
        .opb_valid(dispatch_packet_out.T2_used),
        .cdb_valid(cdb_in.valid),
        .cdb_tag(cdb_in.cdb_tag),
        
        // Outputs
    
    `ifdef DEBUG_MODE
        .rat_debug_value(rat_debug),
        .rat_debug_ready(rat_debug_ready),
    `endif

        .T_old_value(rob_packet_out.Told),
        .opa_value(dispatch_packet_out.T1),
        .opa_ready(dispatch_packet_out.T1r),
        .opb_value(dispatch_packet_out.T2),
        .opb_ready(dispatch_packet_out.T2r),
        
        .checkpoint_rat_value_out(checkpoint_entry_out.rat_value),
        .checkpoint_rat_ready_out(checkpoint_entry_out.rat_ready)
    );

    btag_tracker bmask0 (
        //Inputs
        .clock(clock),
        .reset(reset),
        .branch_dispatch(branch_dispatch),
        .cdb_in(cdb_in),

        //Outputs
        .branch_tag_out(branch_tag_out),
        .branch_mask(branch_mask_out),

        .bs_stall(bs_stall)
    `ifdef DEBUG_MODE
      , .branch_tag_next(branch_tag_next)
    `endif
    );

    always_comb begin

        // Compute stall on structural hazard (ROB, RS, or BRAT)
        decoded_branch = decode_valid & (dispatch_packet_out.cond_branch | dispatch_packet_out.uncond_branch);
        stall = (ROB_full & ~rob_retire_cond) | RS_full  | (bs_stall & decoded_branch) | sq_full; 
        stall_out = stall;

        // Invalidate packets to RS if stalling
        dispatch_packet_out.valid = decode_valid & ~stall & ~(cdb_in.valid & cdb_in.squash_enable);

        //Whether or not we are dispatching a branch instruction
        // Second condition isn't strictly necessary but breaks a timing loop in synthesis
        branch_dispatch = dispatch_packet_out.valid & decoded_branch & ~((branch_mask_out == cdb_in.branch_mask) & cdb_in.squash_enable & cdb_in.valid);

        // Whether to write state to the BS
        checkpoint_write = branch_dispatch;

        //The btag_tracker's combinational logic acts as if it is located here
        dispatch_packet_out.branch_mask = 0;
        dispatch_packet_out.branch_tag  = branch_tag_out;
        if(branch_dispatch)
            dispatch_packet_out.branch_mask = branch_mask_out;

        freelist_enqueue_enable =  ROB_available & rob_retire_cond & (ROB_head_entry.d_tag_old_arch != `ZERO_REG); // Don't free the zero register architectural tag
        // Can enqueue data while squashing, as this operation occurs on retire, which is always valid regardless of pending squashes
        freelist_dequeue_enable = dispatch_packet_out.valid & ~(cdb_in.valid & cdb_in.squash_enable) & (dispatch_packet_out.dest_reg != `ZERO_REG); // Don't assign a new physical register to the zero register
        // These also apply to instructions without destination registers

        // Populate dispatch packet out
        dispatch_packet_out.NPC     = fetch_packet_in.NPC;
        dispatch_packet_out.PC      = fetch_packet_in.PC;
        dispatch_packet_out.rob_idx = ROB_tail_ptr_in;
        dispatch_packet_out.sq_idx  = sq_tail_ptr_in; 
        dispatch_packet_out.inst    = fetch_packet_in.inst;
        dispatch_packet_out.T       = freelist_dequeue_enable ? FIFO_head_packet : 0;
`ifdef GSHARE
        dispatch_packet_out.BP      = fetch_packet_in.BP;
`endif
        // Populate ROB packet out
        rob_packet_out.dispatch_NPC = fetch_packet_in.NPC;
        rob_packet_out.T_used       = dispatch_packet_out.T_used;
        rob_packet_out.T            = dispatch_packet_out.T;
        rob_packet_out.dest_reg     = dispatch_packet_out.dest_reg;
        rob_packet_out.valid        = dispatch_packet_out.valid;
        rob_packet_out.is_store     = dispatch_packet_out.wr_mem;
        rob_packet_out.halt         = dispatch_packet_out.halt;
`ifdef DEBUG_MODE
        rob_packet_out.inst         = dispatch_packet_out.inst;
        rob_packet_out.branch_mask  = dispatch_packet_out.branch_mask;
        rob_packet_out.branch_tag   = branch_tag_out;   
`endif
    end
endmodule
`endif
