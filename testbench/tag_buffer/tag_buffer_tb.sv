`ifndef _TAG_BUFFER_TB_
`define _TAG_BUFFER_TB_
`timescale 1ns/100ps
`include "./headers/include.svh"

`ifndef DEBUG_MODE
`define DEBUG_MODE
`endif
`ifndef USE_IS_EX_REG
`define USE_IS_EX_REG
`endif
module tag_buffer_tb;
    PHYS_REG_TAG issued_tag, early_tag;
    BRANCH_MASK  issued_branch_tag;
    CDB_PACKET   cdb_in;
    logic clock, issued_mult, issue_valid, stall, reset,
            alu_can_issue, mult_can_issue, early_tag_valid;
    TAG_BUFFER_ENTRY [`RS_SIZE-1:0] buff;

    logic [15:0]        instr_valid;
    logic [15:0] [15:0] instr_countdown;
    PHYS_REG_TAG [15:0] instr_tag;
    BRANCH_MASK  [15:0] instr_branch_tag;
    int                 instr_num;

    tag_buffer tag_buffer_dut(
        .clock(clock),
        .issued_tag(issued_tag),
        .issued_mult(issued_mult),
        .issued_branch_tag(issued_branch_tag),
        .cdb_in(cdb_in),
        .issue_valid(issue_valid),
        .stall(stall),
        .reset(reset),
        .alu_can_issue(alu_can_issue),
        .mult_can_issue(mult_can_issue),
        .early_tag(early_tag),
        .early_tag_valid(early_tag_valid),
        .buff(buff)
    );

    always begin
        #5 clock = ~clock;
    end

    task fail(string message);
        $display("time:%4.0f FAILED: %s", $time, message);
        $finish();
    endtask

    task issue_alu(input PHYS_REG_TAG tag_in = 1, input BRANCH_MASK br_t = 0);
        // issue to test struct as well
        for (int i = 0; i < 16; i++) begin
            if (~instr_valid[i]) begin
                instr_num = i;
                break;
            end
        end
        // issue to main struct
        issued_tag = tag_in;
        issue_valid = alu_can_issue;
        issued_mult = 0;
        issued_branch_tag = br_t;
        
        @(negedge clock);
        issue_valid = 0;
    endtask

    task issue_multi(input PHYS_REG_TAG tag_in = 1, input BRANCH_MASK br_t = 0);
        // issue to test struct as well
        for (int i = 0; i < 16; i++) begin
            if (~instr_valid[i]) begin
                instr_num = i;
                break;
            end
        end
        // issue to main struct
        issued_tag = tag_in;
        issue_valid = mult_can_issue;
        issued_mult = 1;
        issued_branch_tag = br_t;
        
        @(negedge clock);
        issue_valid = 0;
    endtask

    task squash(input BRANCH_MASK br_m = 1);
        cdb_in.valid = 1;
        cdb_in.squash_enable = 1;
        cdb_in.branch_mask = br_m;
        @(negedge clock);
        cdb_in.valid = 0;
    endtask

    always_ff @(negedge clock) begin
        
        if (~mult_can_issue)
            fail("mult_can_issue");
        for (int i = 0; i < 16; i++) begin
            if (instr_valid[i] & (instr_countdown[i] == 1)) begin
                if (instr_tag[i] != early_tag) begin
                    fail("early_tag");
                end
                if (~stall & ~early_tag_valid) begin
                    fail("early_tag_valid");
                end
                if (alu_can_issue) begin
                    fail("alu_can_issue");
                end
                i = 16; // breaks the loop the dumb way because it's late and I'm stupid
            end
        end
    end

    always_ff @(negedge clock) begin
        if (early_tag_valid)
            $display("biggity biggity early tag broadcaaaaaaast");
    end

    always_ff @(posedge clock) begin

        if (reset) begin
            instr_valid         <= 0;
            instr_countdown     <= 0;
            instr_tag           <= 0;
            instr_branch_tag    <= 0;
        end else if (~stall) begin
            for (int i = 0; i < 16; i++) begin
                if ((i == instr_num) && issue_valid[i]) begin
                    instr_valid[i]      <= 1;
                    instr_tag[i]        <= issued_tag;
                    instr_branch_tag[i] <= issued_branch_tag;
                    if (issued_mult)
                        instr_countdown[i] <= `NUM_MULT_STAGES-1;
                    else
                        instr_countdown[i] <= 1;
                end else if ((instr_branch_tag[i] & cdb_in.branch_mask) & (cdb_in.valid & cdb_in.squash_enable)) begin
                    instr_valid[i]      <= 0;
                    instr_branch_tag[i] <= 0;
                    instr_countdown[i]  <= 0;
                    instr_tag[i]        <= 0;
                end else if (instr_countdown[i] == 0) begin
                    instr_valid[i]         <= 0;
                    instr_tag[i]           <= 0;
                    instr_branch_tag[i]    <= 0;
                end else if (instr_valid[i]) begin
                    instr_countdown[i]     <= instr_countdown[i] - 1;
                end
            end
        end
    end


    
    initial begin
        $dumpvars;
        $monitor("time:%4.0f early_tag:%h valid:%b", $time, early_tag, early_tag_valid);
        clock = 0;
        
        @(negedge clock);
        reset = 0;
        stall = 0;
        reset = 1;
        cdb_in = 0;
        issue_valid = 0;
        issued_mult = 0;
        @(negedge clock);
        reset = 0;

        issue_multi(1,1);
        issue_alu(2,2);
        /*
        for (int i = 0; i < 50; i++) begin
            int j = $random;
            if (j % 3 == 0) begin
                issue_multi($random, $random);
            end else if (j % 3 == 1) begin
                issue_alu($random, $random);
            end else begin
                squash($random);
            end
        end */    
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        @(negedge clock);
        $finish;
    end


endmodule

`endif