`ifndef _DECODER__
`define _DECODER__

`timescale 1ns/100ps
`include "./headers/include.svh"

// TODO: Handle writing to zero register by setting dst_select to DEST_NONE
module decoder(
	//input [31:0] inst,
	//input valid_inst_in,  // ignore inst when low, outputs will
	                        // reflect noop (except valid_inst)
	//see sys_defs.svh for definition
	input  FETCH_PACKET   if_packet,
	
    output DEST_REG_SEL   dst_select,
	output ALU_OPA_SELECT opa_select,
	output ALU_OPB_SELECT opb_select,
    output ARCH_REG_TAG   dst_idx,
    output ARCH_REG_TAG   opa_idx,
    output ARCH_REG_TAG   opb_idx,
	output ALU_FUNC       alu_func,
	output logic          rd_mem, wr_mem, cond_branch, uncond_branch,
	output logic          csr_op,     // used for CSR operations, we only used this as 
	                         //a cheap way to get the return code out
	output logic          halt,       // non-zero on a halt
    output logic          mult,       //Is this a mult instruction
	output logic          illegal,    // non-zero on an illegal instruction
	output logic          valid_inst,  // for counting valid instructions executed
	                         // and for making the fetch stage die on halts/
	                         // keeping track of when to allow the next
	                         // instruction out of fetch
	                         // 0 for HALT and illegal instructions (die on halt)

	output logic		 T1_used, T2_used, T_used
);
	INST inst;
	logic valid_inst_in;
    
	
	assign inst          = if_packet.inst;
	assign valid_inst_in = if_packet.valid;
	assign valid_inst    = valid_inst_in & ~illegal;
	
	always_comb begin
		// default control values:
		// - valid instructions must override these defaults as necessary.
		//	 opa_select, opb_select, and alu_func should be set explicitly.
		// - invalid instructions should clear valid_inst.
		// - These defaults are equivalent to a noop
		// * see sys_defs.vh for the constants used here
		opa_select = OPA_IS_RS1;
		opb_select = OPB_IS_RS2;
		alu_func = ALU_ADD;
		dst_select = DEST_NONE;
		csr_op = `FALSE;
		rd_mem = `FALSE;
		wr_mem = `FALSE;
		cond_branch = `FALSE;
		uncond_branch = `FALSE;
		halt = `FALSE;
		illegal = `FALSE;
		T_used  = `TRUE;
		T1_used = `TRUE;
		T2_used = `TRUE;
		mult	= `FALSE;
		if(valid_inst_in) begin
			casez (inst) 
				`RV32_LUI: begin
					dst_select   = DEST_RD;
					opa_select = OPA_IS_ZERO;
					opb_select = OPB_IS_U_IMM;
					T1_used = `FALSE;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_AUIPC: begin
					dst_select   = DEST_RD;
					opa_select = OPA_IS_PC;
					opb_select = OPB_IS_U_IMM;
					T1_used = `FALSE;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_JAL: begin
					dst_select    = DEST_RD;
					opa_select    = OPA_IS_PC;
					opb_select    = OPB_IS_J_IMM;
					uncond_branch = `TRUE;
					T1_used = `FALSE;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_JALR: begin
					dst_select      = DEST_RD;
					opa_select    = OPA_IS_RS1;
					opb_select    = OPB_IS_I_IMM;
					uncond_branch = `TRUE;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE,
				`RV32_BLTU, `RV32_BGEU: begin
					opa_select  = OPA_IS_PC;
					opb_select  = OPB_IS_B_IMM;
					cond_branch = `TRUE;
					T_used = `FALSE;
					// T used checked
				end
				`RV32_LB, `RV32_LH, `RV32_LW,
				`RV32_LBU, `RV32_LHU: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					rd_mem     = `TRUE;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_SB, `RV32_SH, `RV32_SW: begin
					opb_select = OPB_IS_S_IMM;
					wr_mem     = `TRUE;
					T_used = `FALSE;
					// T used checked
				end
				`RV32_ADDI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_SLTI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_SLT;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_SLTIU: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_SLTU;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_ANDI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_AND;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_ORI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_OR;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_XORI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_XOR;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_SLLI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_SLL;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_SRLI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_SRL;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_SRAI: begin
					dst_select   = DEST_RD;
					opb_select = OPB_IS_I_IMM;
					alu_func   = ALU_SRA;
					T2_used = `FALSE;
					// T used checked
				end
				`RV32_ADD: begin
					dst_select   = DEST_RD;
					// T used checked
				end
				`RV32_SUB: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_SUB;
					// T used checked
				end
				`RV32_SLT: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_SLT;
					// T used checked
				end
				`RV32_SLTU: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_SLTU;
					// T used checked
				end
				`RV32_AND: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_AND;
					// T used checked
				end
				`RV32_OR: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_OR;
					// T used checked
				end
				`RV32_XOR: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_XOR;
					// T used checked
				end
				`RV32_SLL: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_SLL;
					// T used checked
				end
				`RV32_SRL: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_SRL;
					// T used checked
				end
				`RV32_SRA: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_SRA;
					// T used checked
				end
				`RV32_MUL: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_MUL;
					mult = `TRUE;
					// T used checked
				end
				`RV32_MULH: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_MULH;
					mult = `TRUE;
					// T used checked
				end
				`RV32_MULHSU: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_MULHSU;
					mult = `TRUE;
					// T used checked
				end
				`RV32_MULHU: begin
					dst_select   = DEST_RD;
					alu_func   = ALU_MULHU;
					mult = `TRUE;
					// T used checked
				end
				`RV32_CSRRW, `RV32_CSRRS, `RV32_CSRRC: begin
					csr_op = `TRUE;
					T2_used = `FALSE;
					// T used checked
				end
				`WFI: begin
					halt = `TRUE;
					T_used = `FALSE;
					T1_used = `FALSE;
					T2_used = `FALSE;
					// T used checked
				end
				default: begin 
					illegal = `TRUE;
				end

		endcase // casez (inst)
		end // if(valid_inst_in)

        dst_idx = (dst_select == DEST_RD   ) ? if_packet.inst.r.rd  : `ZERO_REG;
        // opa_idx = (opa_select == OPA_IS_RS1) ? if_packet.inst.r.rs1 : `ZERO_REG;
        // opb_idx = (opb_select == OPB_IS_RS2) ? if_packet.inst.r.rs2 : `ZERO_REG;
        opa_idx = (T1_used) ? if_packet.inst.r.rs1 : `ZERO_REG;
        opb_idx = (T2_used) ? if_packet.inst.r.rs2 : `ZERO_REG;
	end // always
endmodule // decoder

`endif
