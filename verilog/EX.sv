`ifndef __EX_STAGE_V__
`define __EX_STAGE_V__
`include "./headers/include.svh"
`timescale 1ns/100ps

module mult_stage (
	input clock, reset, start,
	input [63:0] product_in, mplier_in, mcand_in,
	output logic done,
	output logic [63:0] product_out, mplier_out, mcand_out
);

	logic [63:0] prod_in_reg, partial_prod_reg;
	logic [63:0] partial_product, next_mplier, next_mcand;

	assign product_out = prod_in_reg + partial_prod_reg;

	assign partial_product = mplier_in[(`MULT_BLOCK_SIZE)-1:0] * mcand_in;

	assign next_mplier = mplier_in >> `MULT_BLOCK_SIZE;
	assign next_mcand = mcand_in << `MULT_BLOCK_SIZE;

    //synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if(reset) begin
            prod_in_reg      <= `SD 0;
            partial_prod_reg <= `SD 0;
            mplier_out       <= `SD 0;
            mcand_out        <= `SD 0;
			done             <= `SD 1'b0;
		end else begin
            prod_in_reg      <= `SD product_in;
            partial_prod_reg <= `SD partial_product;
            mplier_out       <= `SD next_mplier;
            mcand_out        <= `SD next_mcand;
			done             <= `SD start;
		end
	end
endmodule

module mult (
	input clock, reset,
	input [63:0] mcand, mplier,
	input start,
	
	output [63:0] product,
	output done
);

	logic [63:0] mcand_out, mplier_out;
	logic [((`NUM_MULT_STAGES-1)*64)-1:0] internal_products, internal_mcands, internal_mpliers;
	logic [`NUM_MULT_STAGES-2:0] internal_dones;

	mult_stage mstage [`NUM_MULT_STAGES-1:0] (
		.clock(clock),
		.reset(reset),
		.product_in({internal_products,64'h0}),
		.mplier_in({internal_mpliers,mplier}),
		.mcand_in({internal_mcands,mcand}),
		.start({internal_dones,start}),
		.product_out({product,internal_products}),
		.mplier_out({mplier_out,internal_mpliers}),
		.mcand_out({mcand_out,internal_mcands}),
		.done({done,internal_dones})
	);
endmodule

//
// The ALU
//
// given the command code CMD and proper operands A and B, compute the
// result of the instruction
//
// This module is purely combinational
//
module alu (
    input clock,
    input reset,
	input [`XLEN-1:0] opa,
	input [`XLEN-1:0] opb,
	input ALU_FUNC    func,

    output logic is_mult,
	output logic [`XLEN-1:0] result,
    output logic [`XLEN-1:0] mult_result
);
	wire signed [`XLEN-1:0] signed_opa, signed_opb;
	wire signed [2*`XLEN-1:0] signed_mul, mixed_mul;
	wire        [2*`XLEN-1:0] unsigned_mul;

    MULT_HL [`NUM_MULT_STAGES-1:0] mult_HL; //Select between upper and lower bits of mult result
    MULT_HL mult_HL_new;

    //Multiplier IO signals
    logic [2*`XLEN-1:0] mcand, mplier;
    logic start;
    logic [2*`XLEN-1:0] product;
	logic mult_done;
    
	assign signed_opa = opa; //Casts to signed using SV type system
	assign signed_opb = opb;
     
    mult mult (
		.clock(clock),
		.reset(reset),
	    .mcand(mcand),
		.mplier(mplier),
		.start(start),
	    .product(product),
        .done(mult_done)
	);

//////////////////////////////////////////////////////////////////////////////
	// if valid_mul_out & done (muliply complete and not squashed), mult_done = 1

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            mult_HL <= `SD '{`NUM_MULT_STAGES{MULT_NONE}};
        end else begin
            mult_HL <= `SD {mult_HL[`NUM_MULT_STAGES-2:0], mult_HL_new};
        end
    end
	
    always_comb begin
        mult_result = 0;
        if(mult_done) begin
            case(mult_HL[`NUM_MULT_STAGES-1]) //Last index of the mult high-low shift register
                MULT_NONE: mult_result = 0; 
                MULT_LOW:  mult_result = product[`XLEN-1:0];           //Select lower bits
                MULT_HIGH: mult_result = product[2*`XLEN-1:`XLEN];    //Select upper bits
            endcase 
        end
    end

//////////////////////////////////////////////////////////////////////////////

	always_comb begin
        start  = 0;
        mcand  = 0;
        mplier = 0;
        result = 0;
        mult_HL_new = MULT_NONE;
		case (func)
			ALU_ADD:      result = opa + opb;
			ALU_SUB:      result = opa - opb;
			ALU_AND:      result = opa & opb;
			ALU_SLT:      result = signed_opa < signed_opb;
			ALU_SLTU:     result = opa < opb;
			ALU_OR:       result = opa | opb;
			ALU_XOR:      result = opa ^ opb;
			ALU_SRL:      result = opa >> opb[4:0];
			ALU_SLL:      result = opa << opb[4:0];
			ALU_SRA:      result = signed_opa >>> opb[4:0]; // arithmetic from logical shift
			
			// multiplier opcodes
			ALU_MUL:	begin
                start = 1;
                mcand = signed_opa;
                mplier = signed_opb;
                mult_HL_new = MULT_LOW;
                //result = signed_mul[`XLEN-1:0];  signed_opa * signed_opb
            end   
			ALU_MULH:     begin //result = signed_mul[2*`XLEN-1:`XLEN]; signed_opa * signed_opb
                start = 1;
                mcand = signed_opa;
                mplier = signed_opb;   
                mult_HL_new = MULT_HIGH;           
            end
			ALU_MULHSU:   begin //result = mixed_mul[2*`XLEN-1:`XLEN];  signed_opa * opb;
                start = 1;
                mcand = signed_opa;
                mplier = opb;
                mult_HL_new = MULT_HIGH;
            end
			ALU_MULHU:    begin //result = unsigned_mul[2*`XLEN-1:`XLEN]; opa * opb;
                start = 1;
                mcand = opa;
                mplier = opb;
                mult_HL_new = MULT_HIGH;
            end
			default: result = `XLEN'hfacebeec;  // here to prevent latches
		endcase
        is_mult = start; //Used to determine if the ALU instruction is valid right away or valid in NUM_MULT_STAGES cycles.
	end

endmodule // alu

//
// BrCond module
//
// Given the instruction code, compute the proper condition for the
// instruction; for branches this condition will indicate whether the
// target is taken.
//
// This module is purely combinational
//
module brcond(// Inputs
	input [`XLEN-1:0] rs1,    // Value to check against condition
	input [`XLEN-1:0] rs2,
	input  [2:0] func,  // Specifies which condition to check

	output logic cond    // 0/1 condition result (False/True)
);

	logic signed [`XLEN-1:0] signed_rs1, signed_rs2;
	assign signed_rs1 = rs1;
	assign signed_rs2 = rs2;
	always_comb begin
		cond = 0;
		case (func)
			3'b000: cond = signed_rs1 == signed_rs2;  // BEQ
			3'b001: cond = signed_rs1 != signed_rs2;  // BNE
			3'b100: cond = signed_rs1 < signed_rs2;   // BLT
			3'b101: cond = signed_rs1 >= signed_rs2;  // BGE
			3'b110: cond = rs1 < rs2;                 // BLTU
			3'b111: cond = rs1 >= rs2;                // BGEU
		endcase
	end
	
endmodule // brcond

module EX (
	input clock,                       // system clock
	input reset,                       // system reset

    input   IS_EX_PACKET is_ex_packet,
    input   CDB_PACKET   cdb_in,        //Used for squashing

    //SQ store-to-load forwarding inputs
    input                  sq2load_frwd_valid,
    input                  sq2load_partial_frwd,
    input   [3:0]          sq2load_frwd_mask,
    input   [`XLEN-1:0]    sq2load_frwd_value,

    //Dcache input signals
    input               mem_busy,
    input   [`XLEN-1:0] Dcache2proc_data,

    output  SQ_PACKET  ex_to_sq_out,       // For load/store functional unit
    output  EX_PACKET  alu_packet_out,     // ALU packet, may or may not be valid. Branch is ALU type
    output  EX_PACKET  load_packet_out,    // LD  packet, may or may not be valid.
    output  EX_PACKET  mul_packet_out,     // MUL result, may or may not be valid.

    output  PHYS_REG_TAG early_mult_tag    // early tag broadcast for multiplier, outputs 0 if invalid/squashed
);
    //Internal data
    IS_PACKET issued_am;
    IS_PACKET issued_ls;
    DISPATCH_PACKET inst_info_am;
    DISPATCH_PACKET inst_info_ls;

	logic [`XLEN-1:0] opa_mux_out, opb_mux_out;
    logic [`XLEN-1:0] brcond_in_1, brcond_in_2;
    logic [`XLEN-1:0] ls_in; 
    logic [`XLEN-1:0] alu_result, mult_result;

    //Control signals
	logic brcond_result, squash;
    logic is_mult;

    //Internal packets
    EX_PACKET mult_pipe_new; //Used to build the output packet. Reduces code bulk
    EX_PACKET [`NUM_MULT_STAGES-1:0] mult_pipe, mult_pipe_next; 

	//
	// ALU opA mux
	//
	always_comb begin
		opa_mux_out = `XLEN'hdeadfbac;
		case (inst_info_am.opa_select)
			OPA_IS_RS1:  opa_mux_out =  issued_am.rs.T1_early ?  
                                        ((cdb_in.uncond_branch & cdb_in.valid) ? cdb_in.NPC : cdb_in.head_data) : // account for JALRs
                                        issued_am.rs1_value;
			OPA_IS_NPC:  opa_mux_out = inst_info_am.NPC;
			OPA_IS_PC:   opa_mux_out = inst_info_am.PC;
			OPA_IS_ZERO: opa_mux_out = 0;
		endcase
	end

	 //
	 // ALU opB mux
	 //
	always_comb begin
		// Default value, Set only because the case isnt full.  If you see this
		// value on the output of the mux you have an invalid opb_select
		opb_mux_out = `XLEN'hfacefeed;
		case (inst_info_am.opb_select)
			OPB_IS_RS2:   opb_mux_out = issued_am.rs.T2_early ? 
                                        ((cdb_in.uncond_branch & cdb_in.valid) ? cdb_in.NPC : cdb_in.head_data) : // account for JALRs
                                        issued_am.rs2_value;
			OPB_IS_I_IMM: opb_mux_out = `RV32_signext_Iimm(inst_info_am.inst);
			OPB_IS_S_IMM: opb_mux_out = `RV32_signext_Simm(inst_info_am.inst);
			OPB_IS_B_IMM: opb_mux_out = `RV32_signext_Bimm(inst_info_am.inst);
			OPB_IS_U_IMM: opb_mux_out = `RV32_signext_Uimm(inst_info_am.inst);
			OPB_IS_J_IMM: opb_mux_out = `RV32_signext_Jimm(inst_info_am.inst);
		endcase
	end

    function EX_PACKET ex_default(
        IS_PACKET issued_instr
    );
        DISPATCH_PACKET inst_info;

        inst_info = issued_instr.rs.d;
        //Set a default packet (reduces code bulk)
        ex_default = 0;
        ex_default.data           = 0;
        ex_default.tag            = inst_info.T;        //Phys tag of output reg
        ex_default.arch_tag       = inst_info.dest_reg; //Arch tag of output reg
        ex_default.T_used         = inst_info.T_used;
        ex_default.rob_idx        = inst_info.rob_idx;
        ex_default.sq_idx         = inst_info.sq_idx;
        ex_default.is_store       = 0;
        ex_default.NPC            = inst_info.NPC;
        ex_default.squash_enable  = 0;
        ex_default.uncond_branch  = 0;
        ex_default.branch_mask    = 0;
        ex_default.branch_tag     = issued_instr.rs.branch_tag;
        ex_default.valid          = 0;
//	ex_default.ex_bp.misprediction  = 1; 
//      ex_default.ex_bp.taken		= 0;
//      ex_default.ex_bp.PC 		= inst_info.PC;
//      ex_default.ex_bp.target_PC	= inst_info.NPC;
//      ex_default.ex_bp.branch 	= 0;
    endfunction

    function logic [`XLEN-1:0] ls_size_adjust(
        input [`XLEN-1:0] in_data,
        input [`XLEN-1:0] addr,
        input SIGNED_MEM_SIZE sz
    );
        if(~sz.sign) begin // 0 -> signed
            case(sz.size)
                BYTE: begin
                    case(addr[1:0])
                        2'b00: ls_size_adjust = {{24{in_data[ 7]}}, in_data[ 7: 0]};
                        2'b01: ls_size_adjust = {{24{in_data[15]}}, in_data[15: 8]};
                        2'b10: ls_size_adjust = {{24{in_data[23]}}, in_data[23:16]};
                        2'b11: ls_size_adjust = {{24{in_data[31]}}, in_data[31:24]};
                    endcase
                end
                HALF: begin
                    case(addr[1])
                        1'b0: ls_size_adjust = {{16{in_data[15]}}, in_data[15: 0]};
                        1'b1: ls_size_adjust = {{16{in_data[31]}}, in_data[31:16]};
                    endcase
                end
                WORD:   ls_size_adjust = in_data; //Just leave it as-is
                DOUBLE: ls_size_adjust = 32'hdeadbeef; //Invalid case
            endcase
        end else begin // 1 -> unsigned
            case(sz.size)
                BYTE: begin
                    case(addr[1:0])
                        2'b00: ls_size_adjust = {24'h0, in_data[ 7: 0]};
                        2'b01: ls_size_adjust = {24'h0, in_data[15: 8]};
                        2'b10: ls_size_adjust = {24'h0, in_data[23:16]};
                        2'b11: ls_size_adjust = {24'h0, in_data[31:24]};
                    endcase
                end
                HALF: begin
                    case(addr[1])
                        1'b0: ls_size_adjust = {16'h0, in_data[15: 0]};
                        1'b1: ls_size_adjust = {16'h0, in_data[31:16]};
                    endcase
                end
                WORD:   ls_size_adjust = in_data; //Just leave it as-is
                DOUBLE: ls_size_adjust = 32'hdeadbeef; //Invalid case
            endcase
        end
    endfunction

    always_comb begin
        //Helper variables
        issued_am    = is_ex_packet.am;
        issued_ls    = is_ex_packet.ls;
        inst_info_am = issued_am.rs.d;
        inst_info_ls = issued_ls.rs.d;
        squash       = cdb_in.valid && cdb_in.squash_enable;

        //Mult
        //Input to mult pipeline
        mult_pipe_new       = ex_default(issued_am);
        mult_pipe_new.valid = issued_am.valid & is_mult;
        mult_pipe_next = {mult_pipe[`NUM_MULT_STAGES-2:0], mult_pipe_new}; //This shift happens regardless of if the new instr is a valid mult

        //Output packet at the end of the multiplication pipeline
        mul_packet_out      = mult_pipe[`NUM_MULT_STAGES-1]; 
        mul_packet_out.data = mult_result;

        `ifdef USE_IS_EX_REG
        early_mult_tag = (squash & ((cdb_in.branch_mask & mult_pipe[`NUM_MULT_STAGES-2].branch_tag) != 0) | ~mult_pipe[`NUM_MULT_STAGES-2].valid) ?
                         0 : mult_pipe[`NUM_MULT_STAGES-2].tag;
        `else
        early_mult_tag = (squash & ((cdb_in.branch_mask & mult_pipe[`NUM_MULT_STAGES-1].branch_tag) != 0) | ~mult_pipe[`NUM_MULT_STAGES-1].valid) ?
                         0 : mult_pipe[`NUM_MULT_STAGES-1].tag;
        `endif

        //ALU
        //Note that this assigns to the output (T, dest_reg, etc) even if the instr is not an ALU one.
        //The valid bit reflects whether or not this is actually an ALU instruction
        alu_packet_out                = ex_default(issued_am);
        alu_packet_out.data           = alu_result;
`ifndef GSHARE 
        alu_packet_out.squash_enable  = inst_info_am.uncond_branch | (inst_info_am.cond_branch & brcond_result);
`endif
        alu_packet_out.uncond_branch  = inst_info_am.uncond_branch; 
        alu_packet_out.branch_mask    = inst_info_am.branch_mask; //New branch mask comes from the BRAT, determined globally
        alu_packet_out.valid          = issued_am.valid & ~is_mult;

`ifdef GSHARE
       
        // Branch Prediction
        
        alu_packet_out.ex_bp.cond_taken	    = inst_info_am.cond_branch & brcond_result;
        alu_packet_out.ex_bp.PC 		    = inst_info_am.PC;
        // alu_packet_out.ex_bp.target_PC	= (inst_info_am.uncond_branch & alu_packet_out.valid) ? inst_info_am.NPC : alu_packet_out.data;  // Not correct
        alu_packet_out.ex_bp.target_PC	    =  alu_packet_out.data;
        alu_packet_out.ex_bp.ghbr 		    = inst_info_am.BP.ghbr;
        alu_packet_out.ex_bp.cond_branch 	= inst_info_am.cond_branch;
        alu_packet_out.ex_bp.branch 	 	= inst_info_am.uncond_branch | inst_info_am.cond_branch;
        alu_packet_out.ex_bp.valid          = alu_packet_out.valid;		 // Stall signal to be rechecked

        if (inst_info_am.uncond_branch) begin
		    alu_packet_out.actual_taken = 1;
            if (inst_info_am.BP.BTB_taken) begin
                alu_packet_out.ex_bp.BTB_update = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
            end else begin
                alu_packet_out.ex_bp.BTB_update = 1;
            end
            alu_packet_out.squash_enable = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
        end else if (inst_info_am.cond_branch) begin
	        alu_packet_out.actual_taken = (brcond_result) ? 1'b1 : 1'b0;		
            alu_packet_out.squash_enable = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
            if (brcond_result) begin
            	alu_packet_out.squash_enable = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
		        if (inst_info_am.BP.BTB_taken) begin
                	alu_packet_out.ex_bp.BTB_update = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
                end else begin
                    alu_packet_out.ex_bp.BTB_update = 1;
                end
	        end else begin
            	alu_packet_out.squash_enable = (inst_info_am.NPC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
            	alu_packet_out.ex_bp.BTB_update = 0 ;
            end
	    end else begin
            alu_packet_out.squash_enable = 0;
            alu_packet_out.ex_bp.BTB_update = 0;
        end	
//            if (inst_info_am.BP.BTB_taken)
//                if (brcond_result) begin
//                    alu_packet_out.ex_bp.BTB_update = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
//                    alu_packet_out.squash_enable = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
//                end
//                else begin
//                    alu_packet_out.squash_enable = (alu_packet_out.NPC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
//                    alu_packet_out.ex_bp.BTB_update = 0;
//                end
//            else begin
//                if (brcond_result) begin
//                    alu_packet_out.squash_enable = (alu_packet_out.ex_bp.target_PC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;
//                    alu_packet_out.ex_bp.BTB_update = 1;
//                end
//                else begin
//                    alu_packet_out.squash_enable = (alu_packet_out.NPC != inst_info_am.BP.fetch_NPC_target) ? 1'b1 : 1'b0;		
//                    alu_packet_out.ex_bp.BTB_update = 0;
//		end
//            end
//      end
//        else begin
//            alu_packet_out.squash_enable = 0;
//            alu_packet_out.ex_bp.BTB_update = 0;
//        end				
		
`endif

        //Load/Store unit
        ls_in = issued_ls.rs.T1_early ? 
                        ((cdb_in.uncond_branch & cdb_in.valid) ? cdb_in.NPC : cdb_in.head_data) : // account for JALRs
                        issued_ls.rs1_value;
        if(inst_info_ls.rd_mem) begin
            ex_to_sq_out.address = ls_in + `RV32_signext_Iimm(inst_info_ls.inst); //Loads add rs1 and Iimm for address
        end else if(inst_info_ls.wr_mem) begin
            ex_to_sq_out.address = ls_in + `RV32_signext_Simm(inst_info_ls.inst); //Stores add rs1 and Simm for address
        end else begin
            ex_to_sq_out.address = 0;
        end
            
        ex_to_sq_out.value    = issued_ls.rs.T2_early ? 
                                            ((cdb_in.uncond_branch & cdb_in.valid) ? cdb_in.NPC : cdb_in.head_data) : // account for JALRs
                                            issued_ls.rs2_value; //For stores - store value read from rs2
        ex_to_sq_out.idx      = inst_info_ls.sq_idx;
        ex_to_sq_out.st_valid = issued_ls.valid & inst_info_ls.wr_mem;
        ex_to_sq_out.ld_valid = issued_ls.valid & inst_info_ls.rd_mem;
        ex_to_sq_out.mem_size = inst_info_ls.inst.r.funct3;

        load_packet_out = ex_default(issued_ls);
        if(inst_info_ls.wr_mem)
            load_packet_out.is_store = 1'b1;
            
        if(issued_ls.valid & inst_info_ls.rd_mem) begin

            //Obtain data from store-->load forwarding
            if(sq2load_frwd_valid) begin //Get load data from SQ forward
                load_packet_out.data = ls_size_adjust( //Trim loaded data
                    sq2load_frwd_value,
                    ex_to_sq_out.address,
                    ex_to_sq_out.mem_size
                );
            end 

            if(~mem_busy) begin //Obtain data from Dcache
                if(~sq2load_frwd_valid) begin
                    if(~ex_to_sq_out.mem_size.sign) begin
                        case(ex_to_sq_out.mem_size.size)
                            BYTE:   load_packet_out.data = {{24{Dcache2proc_data[ 7]}}, Dcache2proc_data[ 7: 0]};
                            HALF:   load_packet_out.data = {{16{Dcache2proc_data[15]}}, Dcache2proc_data[15: 0]};
                            WORD:   load_packet_out.data = Dcache2proc_data;
                            DOUBLE: load_packet_out.data = 32'hdeadbeef; //BAD
                        endcase
                    end else
                        load_packet_out.data = Dcache2proc_data;              
                end else begin
                    load_packet_out.data = load_packet_out.data | (Dcache2proc_data &
                        ~{{8{sq2load_frwd_mask[3]}}, {8{sq2load_frwd_mask[2]}}, {8{sq2load_frwd_mask[1]}}, {8{sq2load_frwd_mask[0]}}});
                end
            end
        end

        //This load packet valid signal will signal to the CDB to stall EX
        load_packet_out.valid = issued_ls.valid & (inst_info_ls.wr_mem |
            (inst_info_ls.rd_mem & ((sq2load_frwd_valid & ~sq2load_partial_frwd) | ~mem_busy))); 

        //Handle squashing
        if(squash) begin
            //Single-cycle instructions - immediately invalidate output
            if(cdb_in.branch_mask & issued_am.rs.branch_tag)
                alu_packet_out.valid  = 0; //Invalidate instruction on branch mask 

            if(cdb_in.branch_mask & issued_ls.rs.branch_tag) begin
                load_packet_out.valid = 0;
                ex_to_sq_out.st_valid = 0;
                ex_to_sq_out.ld_valid = 0;
            end

            //CAM on the entries within the multiplier
            for(int i = 0; i < `NUM_MULT_STAGES; i++) begin
                if(cdb_in.branch_mask & mult_pipe_next[i].branch_tag)
                    mult_pipe_next[i].valid = 0;
            end
            //Special case for mul_packet_out
            if(cdb_in.branch_mask & mul_packet_out.branch_tag)
                mul_packet_out.valid = 0;
        end

        //Handle branch completion
        if(cdb_in.valid) begin
            alu_packet_out.branch_tag  &= ~cdb_in.branch_mask;
            load_packet_out.branch_tag &= ~cdb_in.branch_mask;
            mul_packet_out.branch_tag  &= ~cdb_in.branch_mask;
            for(int i = 0; i < `NUM_MULT_STAGES; i++) begin
                mult_pipe_next[i].branch_tag &= ~cdb_in.branch_mask;
            end
        end
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            mult_pipe <= `SD 0;
        end else begin
            mult_pipe <= `SD mult_pipe_next;
        end
    end

	//
	// instantiate the ALU
	//
	alu alu_0 (// Inputs
        .clock(clock),
        .reset(reset),
		.opa(opa_mux_out),
		.opb(opb_mux_out),
		.func(inst_info_am.alu_func),
		// Output
        .is_mult(is_mult),
		.result(alu_result),
        .mult_result(mult_result)
	);

    always_comb begin
        brcond_in_1 = issued_am.rs.T1_early ? 
                        ((cdb_in.uncond_branch & cdb_in.valid) ? cdb_in.NPC : cdb_in.head_data) : // account for JALRs
                        issued_am.rs1_value;
        brcond_in_2 = issued_am.rs.T2_early ? 
                        ((cdb_in.uncond_branch & cdb_in.valid) ? cdb_in.NPC : cdb_in.head_data) : // account for JALRs
                        issued_am.rs2_value;
    end

	 //
	 // instantiate the branch condition tester
	 //
	brcond brcond (// Inputs
		.rs1(brcond_in_1), 
		.rs2(brcond_in_2),
		.func(inst_info_am.inst.b.funct3), // inst bits to determine check

		// Output
		.cond(brcond_result)
	);
endmodule // module ex_stage
`endif // __EX_STAGE_V__


