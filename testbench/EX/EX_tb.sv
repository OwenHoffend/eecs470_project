`ifndef _EX_TB__
`define _EX_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./p3_shit/id_stage.sv"
`include "./p3_shit/regfile.sv"
//`define FINISH_ON_ERROR 
//Testbench for the Execute Stage

module EX_tb;

    logic       clock;              // system clock
	logic       reset;              // system reset
    IS_PACKET   issued_instr;
    CDB_PACKET  cdb_in;             //Used for squashing

    EX_PACKET   alu_packet_out;     // ALU packet, may or may not be valid. Branch is ALU type
    EX_PACKET   load_packet_out;    // LD  packet, may or may not be valid.
    EX_PACKET   mul_packet_out;     // MUL result, may or may not be valid.

    EX EX_dut(
        .clock(clock),          
        .reset(reset),          
        // .issued_instr(issued_instr),
        .cdb_in(cdb_in),         
        .alu_packet_out(alu_packet_out), 
        .load_packet_out(load_packet_out),
        .mul_packet_out(mul_packet_out) 
    );

    INST            current_inst;
    FETCH_PACKET    if_id_packet;
    ID_EX_PACKET    id_packet_out;
    DISPATCH_PACKET disp_packet;

    logic [`XLEN-1:0] rs1_value, rs2_value;
    logic [`XLEN-1:0] correct_alu, correct_mult;
    logic [`NUM_MULT_STAGES-1:0] [`XLEN-1:0] correct_muls;

    BRANCH_MASK     branch_tag;
    logic enable_issue;

    function logic [`XLEN-1:0] mul (
        input [`XLEN-1:0] rs1,
        input [`XLEN-1:0] rs2
    );
        logic signed [`XLEN-1:0] signed_rs1;
        logic signed [`XLEN-1:0] signed_rs2;
        logic [2*`XLEN-1:0] mul_temp;
        signed_rs1 = rs1;
        signed_rs2 = rs2;
        mul_temp = signed_rs1 * signed_rs2;
        return mul_temp[`XLEN-1:0];
    endfunction

    function logic [`XLEN-1:0] mulh (
        input [`XLEN-1:0] rs1,
        input [`XLEN-1:0] rs2
    );
        logic signed [`XLEN-1:0] signed_rs1;
        logic signed [`XLEN-1:0] signed_rs2;
        logic [2*`XLEN-1:0] mul_temp;
        signed_rs1 = rs1;
        signed_rs2 = rs2;
        mul_temp = signed_rs1 * signed_rs2;
        return mul_temp[2*`XLEN-1:`XLEN];
    endfunction

    function logic [`XLEN-1:0] mulhsu (
        input [`XLEN-1:0] rs1,
        input [`XLEN-1:0] rs2
    );
        logic signed [`XLEN-1:0] signed_rs1;
        logic signed [2*`XLEN-1:0] mul_temp_s;
        logic [2*`XLEN-1:0] mul_temp;
        signed_rs1 = rs1;
        mul_temp_s = signed_rs1 * rs2;
        mul_temp = mul_temp_s;
        return mul_temp[2*`XLEN-1:`XLEN];
    endfunction

    function logic [`XLEN-1:0] mulhu (
        input [`XLEN-1:0] rs1,
        input [`XLEN-1:0] rs2
    );
        logic [2*`XLEN-1:0] mul_temp;
        mul_temp = rs1 * rs2; 
        return mul_temp[2*`XLEN-1:`XLEN];
    endfunction

    //Use the p3 decoder module to decode instructions for the testbench
    decoder decoder_0 (
		.if_packet(if_id_packet),	 
		// Outputs
		// .dst_select(id_packet_out.opa_select)
        .opa_select(id_packet_out.opa_select),
		.opb_select(id_packet_out.opb_select),
		.alu_func(id_packet_out.alu_func),
		.rd_mem(id_packet_out.rd_mem),
		.wr_mem(id_packet_out.wr_mem),
		.cond_branch(id_packet_out.cond_branch),
		.uncond_branch(id_packet_out.uncond_branch),
		.csr_op(id_packet_out.csr_op),
		.halt(id_packet_out.halt),
		.illegal(id_packet_out.illegal),
		.valid_inst(id_packet_out.valid)
	);

    always begin
        #5 clock = ~clock;
    end

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("alu_actual = %h mult_actual = %h", alu_packet_out.data, mul_packet_out.data);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    //Decodes the instruction contained in current_inst
    //And sets the proper fields in the dispatch packet
    always_comb begin
        if_id_packet              = 0;
        disp_packet               = 0;
        if_id_packet.inst   = current_inst;
        if_id_packet.valid  = 1;
        disp_packet.inst          = current_inst;
        disp_packet.opa_select    = id_packet_out.opa_select;    
        disp_packet.opb_select    = id_packet_out.opb_select;  
        disp_packet.alu_func      = id_packet_out.alu_func;      
        disp_packet.rd_mem        = id_packet_out.rd_mem;        
        disp_packet.wr_mem        = id_packet_out.wr_mem;        
        disp_packet.cond_branch   = id_packet_out.cond_branch;   
        disp_packet.uncond_branch = id_packet_out.uncond_branch; 
        disp_packet.csr_op        = id_packet_out.csr_op;        
        disp_packet.halt          = id_packet_out.halt;          
        disp_packet.illegal       = id_packet_out.illegal;       
        disp_packet.valid         = id_packet_out.valid;
        
        issued_instr               = 0;
        issued_instr.rs1_value     = rs1_value; 
        issued_instr.rs2_value     = rs2_value; 
        issued_instr.rs.d          = disp_packet;
        issued_instr.rs.branch_tag = branch_tag;
        issued_instr.valid         = enable_issue;
    end

    //Sets the issued_instr variable to the current disp_packet
    //And sets it as a valid instruction
    task issue_inst();
        enable_issue = 1;
        @(negedge clock);
        enable_issue = 0;
    endtask

    always_ff @(posedge clock) begin
        if(reset) begin
            //Reset check variables
            correct_muls <= `SD 0;
        end else begin
            //Run checks

            correct_muls <= `SD {correct_muls[`NUM_MULT_STAGES-2:0], correct_mult};
            if(alu_packet_out.valid && alu_packet_out.data !== correct_alu)
                fail("alu_data", correct_alu);
            if(mul_packet_out.valid && mul_packet_out.data !== correct_muls[`NUM_MULT_STAGES-1])
                fail("mult_data", correct_muls[`NUM_MULT_STAGES-1]);
        end
    end

    initial begin
        $monitor("Time:%4.0f reset:%b alu_out:%h mul_out:%h load_out:%h shift_reg_head:%h", 
                 $time, reset, alu_packet_out.data, mul_packet_out.data, load_packet_out.data, correct_muls[`NUM_MULT_STAGES-1]); //Add more stuff here
        clock = 0;
        reset = 1;
        rs1_value    = 0;
        rs2_value    = 0;
        branch_tag   = 0;
        correct_alu  = 0;
        correct_mult = 0;
        cdb_in = 0;
        @(negedge clock);
        reset = 0;
        @(negedge clock);

        //////////////////////////////////////////////////////
        //          Basic instruction execution             //
        //////////////////////////////////////////////////////
        $display("--Instruction: addi x10, x0, 1000--");

        // addi a0, zero, 1000 (x10, x0, 1000)
        current_inst.i.imm        = 1000;
        current_inst.i.rs1        = 0;
        current_inst.i.funct3     = 3'b000;
        current_inst.i.rd         = 10;
        current_inst.i.opcode     = 7'b0010011;
        
        rs1_value = 0;
        rs2_value = 0;
        branch_tag = 8'b10000000;
        correct_alu = 1000;
        issue_inst();

        $display("--Conditional Taken Instruction: beq x11, x12, 32--");
        // beq x11, x12, (1 << 5) 0 0 000001 0000
        current_inst.b.of          = 1'b0;
        current_inst.b.s           = 6'b000001; // offset in multiples of 2, so desire 32, then use 16 
        current_inst.b.rs2         = 12;
        current_inst.b.rs1         = 11;
        current_inst.b.funct3      = 3'b000;
        current_inst.b.et          = 4'b0000;
        current_inst.b.f           = 1'b0;
        current_inst.b.opcode      = 7'b1100011;

        // Conditional Taken
        rs1_value = 13;
        rs2_value = 13;
        branch_tag = 8'b00000000;
        correct_alu = 32'h0000_0020;
        issue_inst();

        // Conditional Not Taken
        $display("--Conditional Not Taken Instruction: beq x11, x12, 32--");
        rs1_value = 13;
        rs2_value = 14;
        correct_alu = 32'h0000_0020;
        issue_inst();

        $display("--Unconditional Jump Instruction: jal x0, 1024--");
        // jal x0, offset (jump without linking -- see Page 140 [158 overall in PDF] of riscv-spec.pdf)
        // offset = 1 << 10 (0 00000000 0 1000000000)
        current_inst.j.of          = 1'b0;
        current_inst.j.et          = 10'b1000000000;
        current_inst.j.s           = 1'b0;
        current_inst.j.f           = 8'b00000000;
        current_inst.j.rd          = 0;
        current_inst.j.opcode      = 7'b1101111; 

        // unused
        rs1_value = 0;
        rs2_value = 0;
        correct_alu = 1024;
        branch_tag = 8'b00000000;
        issue_inst();

        correct_alu = 0;
        $display("--MUL Instruction: mul x1, x1, x1--");
        // mul x1, x1, x1
        current_inst.r.funct7     = 1;
        current_inst.r.rs2        = 1;
        current_inst.r.rs1        = 1;
        current_inst.r.funct3     = 0;
        current_inst.r.rd         = 1;
        current_inst.r.opcode     = 7'b0110011;

        rs1_value = 470;
        rs2_value = 570;
        branch_tag = 8'b10000000;
        correct_mult = mul(rs1_value, rs2_value);
        $display("MUL 1: correct_mult: %h", correct_mult);        
        issue_inst();

        $display("--MULH Instruction: mul x2, x2, x2--");
        // mulh  x2, x2, x2
        current_inst.r.funct7    = 1;
        current_inst.r.rs2       = 2;
        current_inst.r.rs1       = 2;
        current_inst.r.funct3    = 1;
        current_inst.r.rd        = 2;
        current_inst.r.opcode    = 7'b0110011;

        rs1_value = -(1 << 20);
        rs2_value = -(1 << 20);
        branch_tag = 8'b11000000;
        correct_mult = mulh(rs1_value, rs2_value);
        $display("MUL 2: correct_mult: %h", correct_mult);
        issue_inst();

        $display("--MULHSU Instruction: mul x3, x3, x3--");
        // mulhsu  x3, x3, x3
        current_inst.r.funct7   = 1;
        current_inst.r.rs2      = 3;
        current_inst.r.rs1      = 3;
        current_inst.r.funct3   = 2;
        current_inst.r.rd       = 3;
        current_inst.r.opcode   = 7'b0110011;

        rs1_value = 0-(1 << 15);
        rs2_value = 696969;
        branch_tag = 8'b11100000;
        correct_mult = mulhsu(rs1_value, rs2_value);
        $display("MUL 3: correct_mult: %h", correct_mult);
        issue_inst();

        $display("--MULHU Instruction: mul x4, x4, x4--");
        // mulhu  x4, x4, x4
        current_inst.r.funct7   = 1;
        current_inst.r.rs2      = 4;
        current_inst.r.rs1      = 4;
        current_inst.r.funct3   = 3;
        current_inst.r.rd       = 4;
        current_inst.r.opcode   = 7'b0110011;

        rs1_value = (1 << 32) - 1;
        rs2_value = (1 << 20);
        branch_tag = 8'b11110000;
        correct_mult = mulhu(rs1_value, rs2_value);
        $display("MUL 4: correct_mult: %h", correct_mult);
        issue_inst();
        
        $display("done issuing muls");
        correct_mult = 0; 
        wait(correct_muls == 0);

        @(negedge clock);

        // squashing test CDB init     
        cdb_in.valid = 0;
        cdb_in.full = 0;
        cdb_in.head_data = 1024;
        cdb_in.cdb_tag = 5;
        cdb_in.cdb_arch_tag = 5;
        cdb_in.T_used = 0;
        cdb_in.rob_idx = 1;
        cdb_in.next_cdb_tag = 6;
        cdb_in.squash_enable = 1;
        cdb_in.branch_mask = 8'b10000000;

        rs1_value = (1 << 32) - 1;
        rs2_value = (1 << 20);
        branch_tag = 8'b11110000;
        correct_mult = mulhu(rs1_value, rs2_value);

        // squashing to internal mul pipe registers
        for(int i = 0; i < `NUM_MULT_STAGES - 1; i++) begin
            issue_inst();
            
            $display("\nsquashing to stage %1d", i+1);
            // wait before sending squash
            repeat(i) @(negedge clock);
            cdb_in.valid = 1;

            // wait remainder cycles to check output
            repeat(`NUM_MULT_STAGES - 1 - i) @(negedge clock);
            assert(~mul_packet_out.valid);
            cdb_in.valid = 0;
        end

        // squashing last stage
        // can put this in the above loop, but need to have 
        // 1 clock tick delay before assert statement to account
        // for signal propagation delay

        $display("\nsquashing to stage %1d", `NUM_MULT_STAGES);
        issue_inst();
        repeat(`NUM_MULT_STAGES) @(negedge clock);
        cdb_in.valid = 1;
        assert(~mul_packet_out.valid);
        cdb_in.valid = 0;

        $display("");

        correct_mult = 0;
        $display("--Squashing ALU instruction--");

        // addi a0, zero, 1000 (x10, x0, 1000)
        current_inst.i.imm        = 1000;
        current_inst.i.rs1        = 0;
        current_inst.i.funct3     = 3'b000;
        current_inst.i.rd         = 10;
        current_inst.i.opcode     = 7'b0010011;
        
        rs1_value = 0;
        rs2_value = 0;
        branch_tag = 8'b10000000;
        correct_alu = 1000;
        issue_inst();

        // enable squash
        cdb_in.valid = 1;
        assert(~mul_packet_out.valid);
        cdb_in.valid = 0;


        `ifdef FINISH_ON_ERROR
            $display("PASSED!");
        `endif
        $finish;
    end
endmodule
`endif