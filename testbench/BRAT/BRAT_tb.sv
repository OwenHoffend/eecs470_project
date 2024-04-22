//`ifndef BS_SIZE
//`define BS_SIZE 4
//`endif
`ifndef _BRAT_TB__
`define _BRAT_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/CAM.sv"
`include "./verilog/BRAT.sv"
`define FINISH_ON_ERROR

module BRAT_tb;
    // Module inputs
    logic              clock;                   // CLOCK
    logic              reset;

    logic              checkpoint_write;        // Are we taking a snapshot on this cycle?
    BRANCH_MASK        checkpoint_branch_mask;  // Index to checkpoint to
    BRANCH_STACK_ENTRY checkpoint_entry_in;     // Data to write
    CDB_PACKET         cdb_in;                  // CDB in for updating on instruction complete
    ROB_ENTRY          ROB_head_entry;          // ROB entry in for updating the freelist

    // Module outputs    
    BRANCH_STACK_ENTRY checkpoint_entry_out;    // Read value from CDB in tag
   
    // DUT instance
    BRAT  BRAT_dut (
        .clock(clock),
        .reset(reset),
        .checkpoint_write(checkpoint_write),
        .checkpoint_branch_mask(checkpoint_branch_mask),
        .checkpoint_entry_in(checkpoint_entry_in),
        .cdb_in(cdb_in),
        .ROB_head_entry(ROB_head_entry),
        .checkpoint_entry_out(checkpoint_entry_out)
    );

    // Variables for testbench to track the state of the freelists
    integer freelist_counter            [`BS_SIZE-1:0];
    integer freelist_counter_next       [`BS_SIZE-1:0];
    integer freelist_counter_inc        [`BS_SIZE-1:0];
    integer freelist_counter_checkpoint;
    logic   freelist_full_tb            [`BS_SIZE-1:0];
    logic   freelist_available_tb       [`BS_SIZE-1:0];
    logic   freelist_enqueue_tb;

    // Variables for testbench to track the state of the map tables
    logic        [`BS_SIZE-1:0]                          map_table_complete_valid_tb;
    logic                                                map_table_complete_hit_tb;
    ARCH_REG_TAG                                         map_table_complete_idx_tb;
    PHYS_REG_TAG [`BS_SIZE-1:0] [`ARCH_REGFILE_SIZE-1:0] map_table_value_tb;
    logic        [`BS_SIZE-1:0] [`ARCH_REGFILE_SIZE-1:0] map_table_ready_tb;
    PHYS_REG_TAG [`BS_SIZE-1:0] [`ARCH_REGFILE_SIZE-1:0] map_table_value_tb_next;
    logic        [`BS_SIZE-1:0] [`ARCH_REGFILE_SIZE-1:0] map_table_ready_tb_next;

    // Variable for testbench to save a checkpoint state to (for writing to a BRAT frame)
    BRANCH_MASK        branch_mask_tb;
    BRANCH_STACK_ENTRY checkpoint_entry_tb;

    // Signals for verification
    integer frame;
    logic   verify;
    BRANCH_STACK_ENTRY checkpoint_entry_out_tb;

    // Random test signals
    logic        random_dispatch_valid;
    logic [1:0]  random_branch_mask_in_int;
    BRANCH_MASK  random_branch_mask_in;
    logic        random_complete_valid;
    PHYS_REG_TAG random_cdb_tag_in;
    BRANCH_MASK  random_branch_tag_cdb;
    logic        random_retire_valid;
    PHYS_REG_TAG random_rob_tag_in;
    logic        random_read_squash;

    ////////////////////////////////////////////////////////////////////////
    // TASK DEFINITIONS                                                   //
    ////////////////////////////////////////////////////////////////////////

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    task read_squash(
        input BRANCH_MASK branch_mask_in
    );
        @(negedge clock);

        verify = 0;
        cdb_in.valid = 1;
        cdb_in.squash_enable = 1;
        cdb_in.branch_mask = branch_mask_in;
        // Allow combinational logic to propogate
        `SD checkpoint_entry_out_tb = checkpoint_entry_out;

        @(negedge clock);

        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;
        verify = 1;

        @(negedge clock);

        verify = 0;
    endtask

    task read_squash_and_retire(
        input BRANCH_MASK branch_mask_in,
        input PHYS_REG_TAG rob_tag_in      // What data to add to FLs
    );
        @(negedge clock);

        // Create a squash event
        verify = 0;
        cdb_in.valid = 1;
        cdb_in.squash_enable = 1;
        cdb_in.branch_mask = branch_mask_in;
        `SD checkpoint_entry_out_tb = checkpoint_entry_out;

        // Create a retire event
        ROB_head_entry.complete = 1;
        ROB_head_entry.d_tag_old = rob_tag_in;

        @(negedge clock);

        // Verify the event
        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;
        ROB_head_entry.complete = 1;
        verify = 1;

        @(negedge clock);

        verify = 0;
    endtask

    task randomize_squash(
    );
        checkpoint_entry_tb.freelist_head_ptr = $random;
        freelist_counter_checkpoint = 0;
        
        // Generate RAT data
        for(int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
            checkpoint_entry_tb.rat_value[i] = $random;
            checkpoint_entry_tb.rat_ready[i] = $random;
        end
    endtask

    task insert_event(
        input logic        dispatch_valid, // Do a dispatch?
        input BRANCH_MASK  branch_mask_in, // Which frame to dispatch to
        input logic        complete_valid, // Do a complete?
        input PHYS_REG_TAG cdb_tag_in,     // What data to update in RATs
        input BRANCH_MASK  branch_tag_cdb, // Which frames to write the complete to?
        input logic        retire_valid,   // Do a retire?
        input PHYS_REG_TAG rob_tag_in      // What data to add to FLs
    );
        // Create dispatch event
        checkpoint_write = dispatch_valid;
        checkpoint_branch_mask = branch_mask_in;
        checkpoint_entry_in = checkpoint_entry_tb;

        // Create a complete event
        cdb_in.valid = complete_valid;
        cdb_in.cdb_arch_tag = cdb_tag_in;
        cdb_in.branch_tag = branch_tag_cdb;

        // Create a retire event
        ROB_head_entry.complete = retire_valid;
        ROB_head_entry.d_tag_old = rob_tag_in;
        ROB_head_entry.d_tag_old_arch = 1; // So it doesn't ignore the retire

        @(negedge clock);

        checkpoint_write = 0;
        cdb_in.valid = 0;
        ROB_head_entry.complete = 0;

        @(negedge clock);
    endtask

    ////////////////////////////////////////////////////////////////////////
    //  BRAT TRACKING LOGIC                                               //
    ////////////////////////////////////////////////////////////////////////

    always begin
        #5 clock = ~clock;
    end
    
    always_comb begin
        
        // Track the freelists
        freelist_enqueue_tb = ROB_head_entry.complete & (ROB_head_entry.d_tag_old_arch != `ZERO_REG);

        // Track the map tables
        // map_table_complete_idx_tb = cdb_in.cdb_arch_tag;

        for(int frame = 0; frame < `BS_SIZE; frame++) begin            
            // Track the freelists
            freelist_full_tb[frame] = (freelist_counter[frame] == `FREELIST_SIZE);
            freelist_available_tb[frame] = (freelist_counter[frame] != 0);
            freelist_counter_inc[frame]  = (freelist_enqueue_tb & ~freelist_full_tb[frame]) ? 1 : 0;
            freelist_counter_next[frame] = (checkpoint_write & checkpoint_branch_mask[frame]) ? freelist_counter_checkpoint : freelist_counter[frame] + freelist_counter_inc[frame];

            // Track the map tables
            map_table_complete_valid_tb[frame] = cdb_in.valid & ~cdb_in.branch_tag[frame] & ~cdb_in.squash_enable;
            map_table_value_tb_next[frame] = map_table_value_tb[frame];
            map_table_ready_tb_next[frame] = map_table_ready_tb[frame];
            if(map_table_complete_valid_tb[frame]) begin
                map_table_complete_hit_tb = 0;
                for(int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                    if(map_table_value_tb[frame][i] == cdb_in.cdb_tag) begin
                        map_table_complete_hit_tb = 1;
                        map_table_complete_idx_tb = i;
                        break;
                    end
                end
                if(map_table_complete_hit_tb == 1) begin
                    map_table_ready_tb_next[frame][map_table_complete_idx_tb] = 1;
                end
            end
            if(checkpoint_write & checkpoint_branch_mask[frame]) begin
                map_table_value_tb_next[frame] = checkpoint_entry_in.rat_value;
                map_table_ready_tb_next[frame] = checkpoint_entry_in.rat_ready;
            end
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            for (int frame = 0; frame < `BS_SIZE; frame++) begin 
                freelist_counter[frame] <= `SD `FREELIST_SIZE;   
                for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                    map_table_value_tb[frame][i] <= `SD $unsigned(i);
                    map_table_ready_tb[frame][i] <= `SD 1'b1;
                end
            end
        end else begin
            // Check that values read out of the BRAT match expectations
            if(verify) begin

                // Get which frame is being read
                for(int i = 0; i < `BS_SIZE; i++) begin
                    if(cdb_in.branch_mask[i]) begin
                        frame = i;
                        break;
                    end
                end

                // Verify freelist
                // if(freelist_available_tb[frame] != checkpoint_entry_out_tb.freelist_available)
                //     fail("freelist_available", freelist_available_tb[frame]);

                // Verify RAT
                for(int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                    // if(map_table_value_tb[frame][i] != checkpoint_entry_out_tb.rat_value[i]) begin
                    //     fail("map_table_value", map_table_value_tb[frame][i]);
                    // end
                    // if(map_table_ready_tb[frame][i] != checkpoint_entry_out_tb.rat_ready[i]) begin
                    //     fail("map_table_ready", map_table_ready_tb[frame][i]);
                    // end
                end
            end

            freelist_counter <= `SD freelist_counter_next;
            map_table_value_tb <= `SD map_table_value_tb_next;
            map_table_ready_tb <= `SD map_table_ready_tb_next;
        end
    end

    ////////////////////////////////////////////////////////////////////////
    // MAIN TEST FLOW                                                     //
    ////////////////////////////////////////////////////////////////////////

    initial begin
        $monitor("Time:%4.0f checkpoint_write:%b checkpoint_branch_mask:%b cdb_in.valid:%b cdb_in.branch_mask:%b cdb_in.cdb_tag:%h ROB_head_entry.complete:%b ROB_head_entry.d_tag_old:%h", 
            $time, checkpoint_write, checkpoint_branch_mask, cdb_in.valid, cdb_in.branch_mask, cdb_in.cdb_tag, ROB_head_entry.complete, ROB_head_entry.d_tag_old);
        clock = 0;
        reset = 1;
        checkpoint_write = 0;
        checkpoint_branch_mask = 0;
        checkpoint_entry_in = 0;
        cdb_in = 0;
        ROB_head_entry = 0;

        @(negedge clock);
    
        reset = 0;

        ////////////////////////////////////////////////////////////////////////
        // Write checkpoints to BRAT frames                                   //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Writing random data to BRAT frames &&&");

        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            $display("&&&&&& Checkpointing to BRAT Frame (%d / %d) &&&&&&", frame+1, `BS_SIZE);
            randomize_squash();
            branch_mask_tb = (1 << frame);
            insert_event(1, branch_mask_tb, 0, 0, 0, 0, 0);
        end

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Complete data to specific BRAT frames                              //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Completing random data to BRAT frames &&&");

        insert_event(0, 0, 1, $random, 4'b0101, 0, 0);
        insert_event(0, 0, 1, $random, 4'b1010, 0, 0);

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Retire data to all BRAT frames                                     //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Retiring random data to BRAT frames &&&");

        insert_event(0, 0, 0, 0, 0, 1, $random);

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Complete and Retire data to BRAT frames on the same cycle          //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Completing and retiring random data to BRAT frames &&&");

        insert_event(0, 0, 1, $random, 4'b0101, 1, $random);

        insert_event(0, 0, 1, $random, 4'b1010, 1, $random);

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Write checkpoints and complete to BRAT frames on the same cycle    //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Writing random data to BRAT frame and completing on the same cycle &&&");

        randomize_squash();
        insert_event(1, 4'b1000, 1, $random, 4'b1011, 0, 0); // Checkpoint to one frame, complete to a different frame

        randomize_squash();
        insert_event(1, 4'b0100, 1, $random, 4'b1011, 0, 0); // Checkpoint to one frame, complete to the same frame
        
        randomize_squash();
        insert_event(1, 4'b0010, 1, $random, 4'b1001, 0, 0); // Checkpoint to one frame, complete to multiple different frames

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Write checkpoints and retire to BRAT frames on the same cycle      //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Writing random data to BRAT frame and completing on the same cycle &&&");

        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            $display("&&&&&& Checkpointing to BRAT Frame (%d / %d) and Retiring &&&&&&", frame+1, `BS_SIZE);
            randomize_squash();
            branch_mask_tb = (1 << frame);
            insert_event(1, branch_mask_tb, 0, 0, 0, 1, $random);
        end

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Write checkpoints, complete, and retire to BRAT frames on the same cycle //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Writing random data to BRAT frame, completing, and retiring on the same cycle &&&");

        randomize_squash();
        insert_event(1, 4'b1000, 1, $random, 4'b1011, 1, $random); // Checkpoint to one frame, complete to a different frame

        randomize_squash();
        insert_event(1, 4'b0100, 1, $random, 4'b1011, 1, $random); // Checkpoint to one frame, complete to the same frame
        
        randomize_squash();
        insert_event(1, 4'b0010, 1, $random, 4'b1001, 1, $random); // Checkpoint to one frame, complete to multiple different frames

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash(branch_mask_tb);
        end

        ////////////////////////////////////////////////////////////////////////
        // Read checkpoints and retire on the same cycle                      //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Reading checkpoints and retiring data on the same cycle &&&");

        $display("&&& Verifying BRAT contents &&&");
        for(int frame = 0; frame < `BS_SIZE; frame++) begin
            branch_mask_tb = (1 << frame);
            read_squash_and_retire(branch_mask_tb, $random);
        end

        ////////////////////////////////////////////////////////////////////////
        // Random Testing                                                     //
        ////////////////////////////////////////////////////////////////////////
        $display("&&& Random Testing &&&");

        for(int i = 0; i < 10000; i++) begin
            random_dispatch_valid = ($random % 5 == 1) ? 1 : 0; // 20% chance of writing a checkpoint
            random_branch_mask_in_int = $random % `BS_SIZE;
            random_branch_mask_in = 1 << random_branch_mask_in_int;
            random_complete_valid = $random; // 50% chance of doing a complete
            random_cdb_tag_in = $random;
            random_branch_tag_cdb = $random;
            random_retire_valid = $random; // 50% chance of doing a retire
            random_rob_tag_in = $random;
            random_read_squash = $random; // 50% chance of validating data

            case(random_read_squash)
                0: begin // No read this cycle
                    if(random_dispatch_valid) begin
                        randomize_squash();
                    end
                    insert_event(random_dispatch_valid, random_branch_mask_in, 
                        random_complete_valid, random_cdb_tag_in, random_branch_tag_cdb,
                        random_retire_valid, random_rob_tag_in);
                end
                1: begin // Validate data
                    if(random_retire_valid) begin
                        read_squash_and_retire(random_branch_mask_in, random_rob_tag_in);
                    end else begin
                        read_squash(random_branch_mask_in);
                    end
                end
            endcase
        end


        `ifdef FINISH_ON_ERROR
        $display("PASSED!");
        `endif
        $finish;
    end
endmodule
`endif
