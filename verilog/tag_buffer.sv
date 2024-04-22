`ifndef _TAG_BUFFER_
`define _TAG_BUFFER_
`timescale 1ns/100ps
`include "./headers/include.svh"

module tag_buffer #(
    parameter BUFFER_SIZE = `RS_SIZE,
    parameter STANDARD_LATENCY = 1,
    parameter MULTIPLY_LATENCY = `NUM_MULT_STAGES
)(
    input CDB_PACKET    cdb_in,
    input PHYS_REG_TAG  issued_tag,
    input BRANCH_MASK   issued_branch_tag,
    input               issued_mult, issue_valid,
    input               stall, reset, clock,

    output logic        alu_can_issue, mult_can_issue,
    output PHYS_REG_TAG early_tag,
    output logic        early_tag_valid
    `ifdef DEBUG_MODE
        , output TAG_BUFFER_ENTRY [BUFFER_SIZE-1:0] buff
    `endif
);
    logic [$clog2(BUFFER_SIZE)-1:0] std_lat, mult_lat;
    logic [$clog2(BUFFER_SIZE)-1:0] head_ptr, next_head_ptr, insert_idx, alu_insert_idx, mult_insert_idx;
    logic                           squash, is_ex_reg, ex_c_reg;

    `ifndef DEBUG_MODE
        TAG_BUFFER_ENTRY [BUFFER_SIZE-1:0] buff;
    `endif
    TAG_BUFFER_ENTRY [BUFFER_SIZE-1:0] next_buff;

    assign std_lat  = STANDARD_LATENCY;
    assign mult_lat = MULTIPLY_LATENCY;
    assign squash   = cdb_in.squash_enable & cdb_in.valid;

    always_comb begin
        next_buff = buff;

        `ifdef USE_IS_EX_REG
            is_ex_reg = 1'b1;
        `else
            is_ex_reg = 1'b0;
        `endif
        `ifdef USE_EX_C_REG
            ex_c_reg = 1'b1;
        `else
            ex_c_reg = 1'b0;
        `endif

        for (int i = 0; i < BUFFER_SIZE; i++) begin // handle squashing
            if (squash) begin
                if (buff[i].branch_tag & cdb_in.branch_tag) begin
                    next_buff[i] = 0;
                end 
            end
        end

        
        early_tag =          buff[head_ptr + std_lat].tag;
        early_tag_valid =    buff[head_ptr + std_lat].valid & ~stall;
        mult_can_issue = 1;

        mult_insert_idx = head_ptr + mult_lat + is_ex_reg + ex_c_reg;
        alu_insert_idx = head_ptr + std_lat + is_ex_reg + ex_c_reg;

        insert_idx = head_ptr;
        alu_can_issue = ~buff[alu_insert_idx].valid; // if the thing blocking the ALU is squashed, we can still issue an alu

        if (issue_valid) begin
            if (issued_mult)
                insert_idx = mult_insert_idx;
            else
                insert_idx = alu_insert_idx;

            if (alu_can_issue | issued_mult) begin  // don't let a busy alu slot be overwritten
                next_buff[insert_idx].valid        = 1;
                next_buff[insert_idx].tag          = issued_tag;
                next_buff[insert_idx].branch_tag   = issued_branch_tag;
            end
        end
        //`endif

        next_head_ptr = head_ptr + 1'b1;
        
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if (reset) begin
            buff <= `SD 0;
            head_ptr <= `SD 0;
        end else if (~stall) begin
            for (int i = 0; i < BUFFER_SIZE; i++) begin
                if (i == head_ptr) 
                    buff[i] <= `SD 0;
                else
                    buff[i] <= `SD next_buff[i];
            end
            
            head_ptr <= `SD next_head_ptr;
        end
    end



endmodule

`endif