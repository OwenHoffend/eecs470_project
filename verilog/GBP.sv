`ifndef _GSHARE_BRANCH_PREDICTOR_
`define _GSHARE_BRANCH_PREDICTOR_
`include "./headers/include.svh"
`include "verilog/PHT.sv"

`timescale 1ns/100ps

module GBP(
	input 	              clock,			// Clock
	input 	              reset,		   	// Reset
	input [`XLEN-1:0]     F_PC, 		   	// Instruction Address from fetch
	input                 F_branch,			// Branch signal from Execute Stage
	input [`XLEN-1:0]     X_PC, 			// Instruction Address from Execute Stage
	input                 X_branch, 		// Branch signal from Execute Stage
	input                 X_taken, 			// Actual Prediction from Execute Stage
 	input [`GHB_SIZE-1:0] X_ghbr,			// From the EX stage GHB

	// From the BSTACK based on the bmask of the EX stage inst
	output logic [`GHB_SIZE-1:0] F_ghbr,
	output logic F_predict_taken			// Branch Prediction Taken/Not-taken?

`ifdef DEBUG_MODE
	,
	output logic [`GHB_SIZE-1:0] debug_ghbr, debug_n_ghbr,
	output logic [2**(`GHB_SIZE)-1:0] [`SATURATION_BITS-1:0] debug_PHT, debug_next_PHT,
    output logic [2**(`GHB_SIZE)-1:0] debug_PHT_dirty_idxs
`endif

);

	// Global Branch History Register (ghbr)
	logic [`GHB_SIZE-1:0] ghbr, n_ghbr;
	
	logic [`GHB_SIZE-1:0] rd_addr;
	logic [`GHB_SIZE-1:0] wb_addr, wb_addr_next;
	logic taken;
	
`ifdef DEBUG_MODE
	assign debug_ghbr = ghbr;
	assign debug_n_ghbr = n_ghbr;
`endif
	
	PHT pht (
		.clock (clock),
		.reset (reset),
		.rd_idx (rd_addr),
		.wb_idx (wb_addr),
		.wb_taken (X_taken),
		.wb_en (X_branch),
		.taken (taken)
`ifdef DEBUG_MODE
		,
		.debug_PHT(debug_PHT),
		.debug_next_PHT(debug_next_PHT),
		.debug_PHT_dirty_idxs(debug_PHT_dirty_idxs)
`endif

	);
	
	always_comb begin 
		n_ghbr = (X_branch) ? {ghbr[`GHB_SIZE-2:0], X_taken} : ghbr;
		F_ghbr = n_ghbr;
			
		wb_addr = (X_branch) ? X_PC[`GHB_SIZE + 1:2] ^ X_ghbr : 0;
		rd_addr = 0;
		F_predict_taken = 0;
		if (F_branch) begin
			rd_addr = F_PC[`GHB_SIZE + 1:2] ^ n_ghbr;
			F_predict_taken = taken;
		end
	end

    //synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if (reset) begin
			ghbr <= `SD 0;
			// wb_addr <= `SD 0;
		end
		else begin
			ghbr <= `SD n_ghbr;
			// wb_addr <= wb_addr_next;
		end
	end

endmodule

`endif
