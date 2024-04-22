/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  if_stage.v                                          //
//                                                                     //
//  Description :  instruction fetch (IF) stage of the pipeline;       //
//                 fetch instruction, compute next PC location, and    //
//                 send them down the pipeline.                        //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __FETCH_
`define __FETCH_

`include "headers/include.svh"
// `include "verilog/FIFO.sv"
`include "verilog/BTB.sv"
`include "verilog/GBP.sv"

`ifndef INST_BUFF_SIZE
`define INST_BUFF_SIZE 64
`endif

`timescale 1ns/100ps

module fetch(
    input                    clock,             // system clock
    input                    reset,             // system reset
    input  CDB_PACKET        cdb_in,            // branch taken and target comes from this input
    input                    dispatch_stall,    // if this is true, we should kill updating the PC unless there is a taken branch
    input  [63:0]            Icache2proc_data,  // Data coming back from instruction-memory
    input                    Icache2proc_valid, // did we hit or miss in Icache?
`ifdef GSHARE
    input  EX_BP_PACKET      ex_bp,		// EX_BP packet containing all data from EX required for Brnach Prediction

    // output logic
`ifdef DEBUG_MODE
	output logic    [`GHB_SIZE-1:0] debug_ghbr, debug_n_ghbr,
	output logic    [2**(`GHB_SIZE)-1:0] [`SATURATION_BITS-1:0] debug_PHT, debug_next_PHT,
    output logic    [2**(`GHB_SIZE)-1:0]    debug_PHT_dirty_idxs,
    output BTB_DATA [`NUM_BTB_ENTRIES-1:0]  debug_BTB_data,
    output BTB_TAG  [`NUM_BTB_ENTRIES-1:0]  debug_BTB_tags,
    output logic    [`NUM_BTB_ENTRIES-1:0]  debug_BTB_dirty_idxs,
`endif

`endif 
    output logic [`XLEN-1:0] proc2Icache_addr,  // Address sent to Instruction memory    
    output FETCH_PACKET      if_packet_out      // Output data packet from IF going to ID, see sys_defs for signal information 
);
    
    // Defines instruction buffer so that fetch can continue even while dispatch is stalled TODO: add controls and I/O
    //FIFO #(.DATA_TYPE(FETCH_PACKET), .FIFO_DEPTH(`INST_BUFF_SIZE), .INIT_AVAILABLE(0)) inst_buff ();
    
    
    logic [`XLEN-1:0] PC_reg;        // PC we are currently fetching
    logic [`XLEN-1:0] PC_plus_4;
    logic [`XLEN-1:0] next_PC;
    logic             PC_enable;
    logic             squash;

	//Branch Prediction

`ifdef GSHARE
    logic [`XLEN-1:0] BTB_target;
    logic             GBP_taken, BTB_taken, F_is_branch, F_is_cond_branch, F_is_uncond_branch;

    BTB_TAG           PC_tag;
    BTB_IDX           PC_idx;
    BTB_DATA          BTB_data;
    logic             BTB_hit;
    BTB_DATA          target_PC_data; // index of mispredicted PC
    BTB_IDX           mispredict_PC_idx; // index of mispredicted PC 
    BTB_TAG           mispredict_PC_tag; // tag of mispredicted PC
    logic [`GHB_SIZE-1:0] ghbr;  
 
    GBP gbp (
        // inputs
        .clock(clock),
    	.reset(reset),
    	.F_PC(PC_reg),
    	.F_branch(F_is_cond_branch),        
	    .X_PC(ex_bp.PC),
    	.X_branch(ex_bp.cond_branch & ex_bp.valid),
	    .X_taken(ex_bp.cond_taken), 
 	    .X_ghbr(ex_bp.ghbr),

        // outputs
    	.F_ghbr(ghbr),
	    .F_predict_taken(GBP_taken)
`ifdef DEBUG_MODE
		,
		.debug_ghbr(debug_ghbr),
		.debug_n_ghbr(debug_n_ghbr),
        .debug_PHT(debug_PHT),
        .debug_next_PHT(debug_next_PHT),
        .debug_PHT_dirty_idxs(debug_PHT_dirty_idxs)
`endif

    );

    BTB btb (
        // inputs
        .clock(clock),
        .reset(reset),
        .wr_en(ex_bp.BTB_update & ex_bp.valid),
        .wr_idx(mispredict_PC_idx),
        .wr_tag(mispredict_PC_tag),
        .wr_data(target_PC_data), 
        .rd_idx(PC_idx),
        .rd_tag(PC_tag),
        
        // outputs
        .rd_data(BTB_data),
        .rd_valid(BTB_hit)
`ifdef DEBUG_MODE
        ,
        .debug_data(debug_BTB_data),
        .debug_tags(debug_BTB_tags),
        .debug_BTB_dirty_idxs(debug_BTB_dirty_idxs)
`endif

	); 

    assign target_PC_data = ex_bp.target_PC[`BTB_IDX_BITS+`BTB_TAG_BITS+1:2]; 
    assign PC_idx = PC_reg[`BTB_IDX_BITS+1:2];
    assign PC_tag = PC_reg[`BTB_TAG_BITS+`BTB_IDX_BITS+1:`BTB_IDX_BITS+2];
    
    assign BTB_target = {PC_reg[`XLEN-1:`XLEN-`BTB_UNUSED_BITS], BTB_data, PC_reg[1:0]};
    assign mispredict_PC_idx = ex_bp.PC[`BTB_IDX_BITS+1:2];
    assign mispredict_PC_tag = ex_bp.PC[`BTB_TAG_BITS+`BTB_IDX_BITS+1:`BTB_IDX_BITS+2];
 `endif

    always_comb begin

        squash = cdb_in.valid & cdb_in.squash_enable;
        proc2Icache_addr = {PC_reg[`XLEN-1:3], 3'b0};

        // this mux is because the Icache gives us 64 bits not 32 bits
        if_packet_out.inst = PC_reg[2] ? Icache2proc_data[63:32] : Icache2proc_data[31:0];

        // default next PC value
        PC_plus_4 = PC_reg + 4;

	//Branch Prediction
`ifdef GSHARE
	    F_is_uncond_branch = (if_packet_out.inst.b.opcode == 7'b1101111 || if_packet_out.inst.b.opcode == 7'b1100111) ? 1'b1 : 1'b0;
        F_is_cond_branch = (if_packet_out.inst.b.opcode == 7'b1100011) ? 1'b1 : 1'b0;
        F_is_branch = F_is_cond_branch | F_is_uncond_branch ? 1'b1 : 1'b0;

        /////////////////////////////////////////////
        // make sure this condition is correct
		BTB_taken = (F_is_uncond_branch | GBP_taken) ? BTB_hit : 0;
        /////////////////////////////////////////////

        if_packet_out.BP.fetch_NPC_target = (BTB_taken ? BTB_target : PC_plus_4);
        if_packet_out.BP.BTB_taken = BTB_taken;
        if_packet_out.BP.ghbr = ghbr;
        if_packet_out.BP.is_branch = F_is_branch;

        // next PC is target_pc if there is a taken branch or
        // the next sequential PC (PC+4) if no branch
        // (halting is handled with the enable PC_enable;
        next_PC = (squash) ? ((cdb_in.actual_taken) ? cdb_in.head_data : cdb_in.NPC) : // if we squash, take the cdb value
                    (BTB_taken ? BTB_target : PC_plus_4); // if we don't squash, take the BTB target if BTB is taken
`else
        next_PC = squash ? cdb_in.head_data : PC_plus_4;
`endif

		// if squashing and cache miss, squash takes precedence
        PC_enable = (Icache2proc_valid & ~dispatch_stall) | squash;

        // Pass PC+4 down pipeline w/instruction
        if_packet_out.NPC   = PC_plus_4;
        if_packet_out.PC    = PC_reg;

        // If squashing or if stalling due to dispatch or if cache miss, send a NOP
        if_packet_out.valid = ~squash & ~dispatch_stall & Icache2proc_valid; 
    end
    
    // This register holds the PC value
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            PC_reg <= `SD 0;       // initial PC value is 0
        end else if(PC_enable) begin
            PC_reg <= `SD next_PC; // transition to next PC
        end
    end  // always
endmodule  // module if_stage

`endif
