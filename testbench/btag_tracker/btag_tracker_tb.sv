`ifndef _BTAG_TRACKER_TB__
`define _BTAG_TRACKER_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/pselect.sv"
`define FINISH_ON_ERROR

module btag_tracker_tb;
    logic clock;
    logic reset;
    logic branch_dispatch;
    CDB_PACKET cdb_in;

    BRANCH_MASK branch_tag;
    BRANCH_MASK branch_mask;
    logic bs_stall;

    integer event_code;

    BRANCH_MASK btag_mirror, btag_mirror_next, btag_mirror_out; 
    BRANCH_MASK bmask_mirror;
    logic bs_stall_mirror;

    btag_tracker btag_tracker_dut (
        .clock(clock),
        .reset(reset),
        .branch_dispatch(branch_dispatch),
        .cdb_in(cdb_in),

        .branch_tag_out(branch_tag),
        .branch_mask(branch_mask),
        .bs_stall(bs_stall)
    );

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %b", $time, signal, correct_result);
        $display("---branch_tag: %b branch_mask: %b bs_stall: %b---", branch_tag, branch_mask, bs_stall);
        $display("---branch_tag_mirror: %b branch_mask_mirror: %b bs_stall_mirror: %b---", 
            btag_mirror, bmask_mirror, bs_stall_mirror);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    task fill_btag_tracker();
        $display("------Filling up the btag tracker, including one extra------");
        branch_dispatch = 1;
        repeat(`BS_SIZE + 1) @(negedge clock);
        branch_dispatch = 0;
        @(negedge clock);
        $display("------DONE: Filling up the btag tacker------");
    endtask

    task reset_task();
        $display("Resetting...");
        reset = 1;
        cdb_in = 0;
        @(negedge clock);
        reset = 0;
        @(negedge clock);
    endtask

    always begin
        #5 clock = ~clock;
    end

    //Un-synthesizable implementation of the design
    always_comb begin
        //Branches that are completing
        btag_mirror_next  = btag_mirror;
        for(int i = 0; i < `BS_SIZE; i++) begin
            if(cdb_in.valid & cdb_in.branch_mask[i])
                btag_mirror_next[i] = 0;
        end
        btag_mirror_out = btag_mirror_next;

        //New branch mask
        bmask_mirror = 0;
        for(int i = 0; i < `BS_SIZE; i++) begin
            if(btag_mirror_next[i]) begin //Found a 1, set the mask to the last zero before the 1
                if(i != 0)
                    bmask_mirror[i-1] = 1;
                break;
            end else if(i == `BS_SIZE - 1)
                bmask_mirror[i] = 1;
        end

        //New branches
        if(branch_dispatch) begin
            btag_mirror_next |= bmask_mirror;
        end

        //Stalling
        bs_stall_mirror = branch_dispatch & (bmask_mirror == 0);
    end

    always_ff @(posedge clock) begin
        if(reset)
            btag_mirror  <= `SD 0;
        else begin
            if(btag_mirror_out != branch_tag) 
                fail("btag", btag_mirror_out);
            if(bmask_mirror != branch_mask)
                fail("bmask", bmask_mirror);
            if(bs_stall_mirror != bs_stall)
                fail("bs_stall", bs_stall_mirror); 
            btag_mirror  <= `SD btag_mirror_next;
        end
    end
    
    initial begin
        $monitor("Time:%4.0f branch_dispatch: %b branch_tag: %b branch_mask: %b bs_stall: %b cdb_valid: %b cdb_mask: %b bmask_mirror: %b btag_mirror: %b", 
            $time, branch_dispatch, branch_tag, branch_mask, bs_stall, cdb_in.valid, cdb_in.branch_mask, bmask_mirror, btag_mirror);

        clock = 0;
        reset_task();

        fill_btag_tracker();

        $display("------Completing entries in reverse order------");
        cdb_in.valid   = 1;
        for(int i = 0; i < `BS_SIZE; i++) begin
            cdb_in.branch_mask = 1 << i;
            @(negedge clock);
        end
        cdb_in = 0;
        $display("------DONE: Completing entries in reverse order------");

        fill_btag_tracker();

        $display("------Completing entries in alternating order-----");
        cdb_in.valid   = 1;
        for(int i = 0; i < `BS_SIZE; i++) begin
            if(i % 2)
                cdb_in.branch_mask = 1 << i;
            @(negedge clock);
        end
        for(int i = 0; i < `BS_SIZE; i++) begin
            if((i+1) % 2)
                cdb_in.branch_mask = 1 << i;
            @(negedge clock);
        end
        cdb_in.valid   = 0;
        $display("------DONE: Completing entries in alternating order-----");

        reset_task();

        $display("------Random event testing------");
        for(int i = 0; i < 1000; i++) begin
            event_code = $random;
            if(event_code & 3'b001) begin //CDB complete, at a random location
                cdb_in.valid = 1;
                cdb_in.branch_mask = 1 << ($random % `BS_SIZE);
                //Blast the other cdb packet fields with random data to achieve good toggle coverage
                cdb_in.head_data     = $random;
                cdb_in.cdb_tag       = $random;
                cdb_in.cdb_arch_tag  = $random;
                cdb_in.T_used        = $random;
                cdb_in.rob_idx       = $random;
                cdb_in.next_cdb_tag  = $random;
                cdb_in.squash_enable = $random; 
                cdb_in.full          = $random;
                @(negedge clock);
                cdb_in.valid = 0;
                @(negedge clock); 
            end else if(event_code & 3'b010) begin //Dispatch branch
                branch_dispatch = 1;
                @(negedge clock);
                branch_dispatch = 0;
                @(negedge clock);
            end else begin
                cdb_in.valid = 1;
                cdb_in.branch_mask = 1 << ($random % `BS_SIZE);
                branch_dispatch = 1;
                //Blast the other cdb packet fields with random data to achieve good toggle coverage
                cdb_in.head_data     = $random;
                cdb_in.cdb_tag       = $random;
                cdb_in.cdb_arch_tag  = $random;
                cdb_in.T_used        = $random;
                cdb_in.rob_idx       = $random;
                cdb_in.next_cdb_tag  = $random;
                cdb_in.squash_enable = $random; 
                cdb_in.full          = $random;
                @(negedge clock);
                cdb_in.valid    = 0;
                branch_dispatch = 0;
                @(negedge clock); 
            end
        end
        $display("------DONE: Random event testing------");

        `ifdef FINISH_ON_ERROR
            $display("PASSED!");
        `endif
        $finish;
    end
endmodule
`endif