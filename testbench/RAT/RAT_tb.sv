`ifndef _RAT_TB__
`define _RAT_TB__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/RAT.sv"

`define FINISH_ON_ERROR

module RAT_tb;
    logic                                 clock;                  // CLOCK
    logic                                 reset;
    logic                                 stall;

    // logic                                 checkpoint_write;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_value_in;   // Squash value from BRAT
    logic        [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_ready_in;   // Squash ready bits from BRAT                                    
    ARCH_REG_TAG                          dst_idx;                // Architectural register for destination. T_old sent to ROB, tag overwritten by next value from freelist 
    PHYS_REG_TAG                          write_value;            // New tag to overwrite at destination, comes from freelist
    logic                                 write_valid;            // Do the write or not?
    ARCH_REG_TAG                          opa_idx;                // Architectural register for operand A. Goes to RS
    logic                                 opa_valid;              // Valid bit for operand A
    ARCH_REG_TAG                          opb_idx;                // Architectural register for operand B. Goes to RS
    logic                                 opb_valid;              // Valid bit for operand B
    CDB_PACKET                            cdb_in;              // CDB for setting ready bits
    // logic                                 cdb_valid;
    // PHYS_REG_TAG                          cdb_tag;
    PHYS_REG_TAG                          T_old_value;            // T_old sent to the ROB
    PHYS_REG_TAG                          opa_value;
    logic                                 opa_ready;
    PHYS_REG_TAG                          opb_value;
    logic                                 opb_ready;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_value_out;              // Map table    
    logic        [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_ready_out;              // Map table ready bits
   
    RAT  RAT_test (
        // Inputs
        .clock(clock),
        .reset(reset),
        .stall(stall),
        .checkpoint_write(cdb_in.squash_enable),
        .checkpoint_rat_value_in(checkpoint_rat_value_in),
        .checkpoint_rat_ready_in(checkpoint_rat_ready_in),
        .dst_idx(dst_idx),
        .write_value(write_value),
        .write_valid(write_valid),
        .opa_idx(opa_idx),
        .opa_valid(opa_valid),
        .opb_idx(opb_idx),
        .opb_valid(opb_valid),
        // .cdb_in(cdb_in),
        .cdb_valid(cdb_in.valid),
        .cdb_tag(cdb_in.cdb_tag),

        // Outputs
        .T_old_value(T_old_value),
        .opa_value(opa_value),
        .opa_ready(opa_ready),
        .opb_value(opb_value),
        .opb_ready(opb_ready),
        .checkpoint_rat_value_out(checkpoint_rat_value_out),
        .checkpoint_rat_ready_out(checkpoint_rat_ready_out)
    );

    // Checkpoint data registers to be used by TB. Written to by task save_checkpoint()
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] brat_map_value;
    logic        [`ARCH_REGFILE_SIZE-1:0] brat_map_ready;
    
    // Testbench Map table
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] map_table_value;
    logic        [`ARCH_REGFILE_SIZE-1:0] map_table_ready;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] map_table_value_next;
    logic        [`ARCH_REGFILE_SIZE-1:0] map_table_ready_next;

    // Random test signals
    ARCH_REG_TAG                          temp_idx;
    PHYS_REG_TAG                          temp_value;
    ARCH_REG_TAG                          temp_cdb;
    
    int found =0;
    int found_next =0;
    int j = 0;
    int k = 0;
  
    ////////////////////////////////////////////////////////////////////////
    // TASK DEFINITIONS                                                   //
    ////////////////////////////////////////////////////////////////////////

    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("---RAT_table: %h. Map_table: %h", checkpoint_rat_value_out, map_table_value);
        $display("---RAT_table ready: %b. Map_table ready: %b", checkpoint_rat_ready_out, map_table_ready);
        $display("---opb_value: %h. opb_idx value: %h map value: %h", opb_value, opb_idx, map_table_value[opb_idx]);
        $display("---opb_ready: %h. opb_idx value: %h", opb_ready, opb_idx);
        $display("---cdb_in.valid: %h. opb_valid: %h. check_point_enable: %h cdb_in.cdb_tag: %h", cdb_in.valid, opb_valid, cdb_in.squash_enable,cdb_in.cdb_tag);
        $display("---j: %h. k: %h", j, k);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

    task read_opa_opb(
    );
        $display("Reading all using operand a idx");
        
        for (int i = `ARCH_REGFILE_SIZE-1; i >= 0; i--) begin 
            opa_idx = i;
            opa_valid =1;
            opb_valid = 0;

            @(negedge clock);
        end

        $display("Reading all using operand b idx");

        for (int i = `ARCH_REGFILE_SIZE-1; i >= 0; i--) begin 
            opb_idx = i;
            opb_valid =1;
            opa_valid = 0;
            @(negedge clock);
        end
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task add_from_freelist_to_all_map_table_addr(
    );
        for (int i = `ARCH_REGFILE_SIZE-1; i >= 0; i--) begin 
            write_valid = 1;
            write_value = i + `ARCH_REGFILE_SIZE;
            dst_idx = i;
            opa_idx = i;
            opa_valid = 1;
            @(negedge clock);
            write_valid = 0;
            @(negedge clock);
        end
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task cdb_set_valid_to_all_map_table_addr(
    );
        for (int i = `ARCH_REGFILE_SIZE-1; i >= 0; i--) begin 
            cdb_in.cdb_tag = i;    
            cdb_in.valid = 1;
            opb_idx = i;
            opb_valid = 1;    
            @(negedge clock);
            cdb_in.valid = 0;
            @(negedge clock);
        end
        opb_valid = 0;
    endtask

    task add_from_freelist_read_opa(
        input ARCH_REG_TAG add_idx,
        input PHYS_REG_TAG data_added
    );
        write_valid = 1;
        write_value = data_added;
        dst_idx = add_idx;
        opa_idx = add_idx;
        opa_valid = 1;

        @(negedge clock);

        write_valid = 0;

        @(negedge clock);
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task add_from_freelist_read_opb(
        input ARCH_REG_TAG add_idx,
        input PHYS_REG_TAG data_added
    );
        write_valid = 1;
        write_value = data_added;
        dst_idx = add_idx;
        opb_idx = add_idx;
        opb_valid = 1;

        @(negedge clock);

        write_valid = 0;

        @(negedge clock);
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task cdb_set_valid_read_opa(
        input ARCH_REG_TAG cdb_tag
    );
        cdb_in.cdb_tag = cdb_tag;    
        cdb_in.valid = 1;
        opa_idx = cdb_tag;
        opa_valid = 1;    

        @(negedge clock);

        cdb_in.valid = 0;

        @(negedge clock);
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task cdb_set_valid_read_opb(
        input ARCH_REG_TAG cdb_tag
    );
        cdb_in.cdb_tag = cdb_tag;    
        cdb_in.valid = 1;
        opb_idx = cdb_tag;
        opb_valid = 1;    

        @(negedge clock);

        cdb_in.valid = 0;

        @(negedge clock);
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task add_from_freelist_cdb_set_valid_read_opa_read_opb(
        input ARCH_REG_TAG add_idx,
        input PHYS_REG_TAG data_added,
        input ARCH_REG_TAG cdb_tag       
    );
        write_valid = 1;
        write_value = data_added;
        dst_idx = add_idx;
        cdb_in.cdb_tag = cdb_tag;    
        cdb_in.valid = 1;
        opb_idx = add_idx;
        opb_valid = 1;
        opa_idx = cdb_tag;
        opa_valid = 1;

        @(negedge clock);

        write_valid = 0;
        cdb_in.valid = 0;

        @(negedge clock);
        opa_valid = 0;
        opb_valid = 0;
    endtask

    task save_checkpoint(
    );
        brat_map_value      = checkpoint_rat_value_out; // Save snapshot of RAT to BRAT in the TB
        brat_map_ready      = checkpoint_rat_ready_out;
        //entry_counter_brat = entry_counter;

        @(negedge clock);
    endtask

    task squash_to_checkpoint(
        input PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] BRAT_map_value,
        input [`ARCH_REGFILE_SIZE-1:0] BRAT_map_ready
    );
        cdb_in.squash_enable = 1;
        checkpoint_rat_value_in = BRAT_map_value;
        checkpoint_rat_ready_in = BRAT_map_ready;

        @(negedge clock);

        cdb_in.squash_enable = 0;

        @(negedge clock);
    endtask

    task squash_to_checkpoint_add_from_freelist(
        input PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] BRAT_map_value,
        input [`ARCH_REGFILE_SIZE-1:0] BRAT_map_ready,
        input ARCH_REG_TAG add_idx,
        input PHYS_REG_TAG data_added
    );
        cdb_in.squash_enable = 1;
        checkpoint_rat_value_in = BRAT_map_value;
        checkpoint_rat_ready_in = BRAT_map_ready;
        write_valid = 1;
        write_value = data_added;
        dst_idx = add_idx;
        @(negedge clock);

        cdb_in.squash_enable = 0;
        write_valid = 0;

        @(negedge clock);
    endtask    

    task squash_to_checkpoint_cdb_set_valid(
        input PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] BRAT_map_value,
        input [`ARCH_REGFILE_SIZE-1:0] BRAT_map_ready,
        input ARCH_REG_TAG cdb_tag
    );
        cdb_in.squash_enable = 1;
        checkpoint_rat_value_in = BRAT_map_value;
        checkpoint_rat_ready_in = BRAT_map_ready;
        cdb_in.cdb_tag = cdb_tag;    
        cdb_in.valid = 1;

        @(negedge clock);

        cdb_in.squash_enable = 0;
        cdb_in.valid = 0;

        @(negedge clock);
    endtask   

    task squash_to_checkpoint_add_from_freelist_cdb_set_valid(
        input PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] BRAT_map_value,
        input [`ARCH_REGFILE_SIZE-1:0] BRAT_map_ready,
        input ARCH_REG_TAG add_idx,
        input PHYS_REG_TAG data_added,
        input ARCH_REG_TAG cdb_tag
    );
        cdb_in.squash_enable = 1;
        checkpoint_rat_value_in = BRAT_map_value;
        checkpoint_rat_ready_in = BRAT_map_ready;
        write_valid = 1;
        write_value = data_added;
        dst_idx = add_idx;
        cdb_in.cdb_tag = cdb_tag;    
        cdb_in.valid = 1;

        @(negedge clock);

        cdb_in.squash_enable = 0;
        write_valid = 0;
        cdb_in.valid = 0;

        @(negedge clock);
    endtask  

    ////////////////////////////////////////////////////////////////////////
    // MAP TABLE TRACKING LOGIC                                           //
    ////////////////////////////////////////////////////////////////////////

    always begin
        #5 clock = ~clock;
    end
    
    always_comb begin
        map_table_value_next = map_table_value;
        map_table_ready_next = map_table_ready;
        if (~stall) begin
            if (cdb_in.valid) begin
        found_next =0;
        for (int i =0 ; i < `ARCH_REGFILE_SIZE; i++) begin
            if (map_table_value_next[i] == cdb_in.cdb_tag && !found_next) begin
                                map_table_ready_next[i] = 1;
                found_next =1;
            end
                 end
            end
                if (write_valid) begin
                map_table_value_next[dst_idx] = write_value;
                map_table_ready_next[dst_idx] = 0;
            end
        end
        if (cdb_in.squash_enable) begin
            map_table_value_next = checkpoint_rat_value_in; 
            map_table_ready_next = checkpoint_rat_ready_in;
        end

    end

    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                map_table_value[i] <= `SD $unsigned(i);
                map_table_ready[i] <= `SD 1'b1;
            end
        end else begin
            map_table_value <= `SD map_table_value_next;
            map_table_ready <= `SD map_table_ready_next;
            if ( (map_table_value[dst_idx] != T_old_value))
                fail("T_old_value", map_table_value[dst_idx]);
            if ( (map_table_value[opa_idx] != opa_value) && opa_valid)
                fail("opa_value", map_table_value[opa_idx]);
            if ( (map_table_ready[opa_idx] !== opa_ready) && opa_valid && !(cdb_in.valid && (map_table_value[opa_idx] == cdb_in.cdb_tag)))
                fail("opa_ready", map_table_ready[opa_idx]);
            else if (!opa_ready && opa_valid && (cdb_in.valid && (map_table_value[opa_idx] == cdb_in.cdb_tag)))
                fail("opa_ready", 1);
            if ( (map_table_value[opb_idx] != opb_value) && opb_valid)
                fail("opb_value", map_table_value[opb_idx]);
            if ( (map_table_ready[opb_idx] !== opb_ready) && opb_valid && !(cdb_in.valid && (map_table_value[opb_idx] == cdb_in.cdb_tag)))
                fail("opb_ready", map_table_ready[opb_idx]);
            else if (!opb_ready && opb_valid && (cdb_in.valid && (map_table_value[opb_idx] == cdb_in.cdb_tag))) 
                fail("opb_ready", 1);

            found =0;

            for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                if (map_table_value[i] != checkpoint_rat_value_out[i]) 
                    fail("checkpoint_rat_value_out", map_table_value[i]);
                if (map_table_ready[i] != checkpoint_rat_ready_out[i] && !(cdb_in.valid && (map_table_value[i] == cdb_in.cdb_tag))) begin
                    // $display("---cdb_in.valid: %h. map_table_ready[i]: %b. checkpoint_rat_ready_out[i]: %b map_table_value[i]: %b cdb_in.cdb_tag: %b check_point_enable: %h i : %d", cdb_in.valid, map_table_ready[i], checkpoint_rat_ready_out[i], map_table_value[i], cdb_in.cdb_tag, cdb_in.squash_enable, i);
                    fail("checkpoint_rat_ready_out", map_table_ready[i]);
                end
                else if (!found & (!checkpoint_rat_ready_out[i] && (cdb_in.valid && (map_table_value[i] == cdb_in.cdb_tag)))) begin
                    // $display("---cdb_in.valid: %h. map_table_ready: %b. checkpoint_rat_ready_out: %b map_table_value[i]: %h cdb_in.cdb_tag: %h check_point_enable: %h i: %d", cdb_in.valid, map_table_ready, checkpoint_rat_ready_out, map_table_value[i], cdb_in.cdb_tag, cdb_in.squash_enable, i);
                    fail("checkpoint_rat_ready_out", 1);
                end
                if (map_table_value[i] == cdb_in.cdb_tag && !found)
                    // $display("---map_table_value[i]: %h cdb_in.cdb_tag: %h i: %d", map_table_value[i], cdb_in.cdb_tag, i);
                    found = 1;
            end
        end
    end

    ////////////////////////////////////////////////////////////////////////
    // MAIN TEST FLOW                             //
    ////////////////////////////////////////////////////////////////////////

    initial begin
        $monitor("Time:%4.0f write_value:%h write_valid:%b opa_idx:%hhh opa_valid:%b opb_idx:%h opb_valid:%b checkpoint_en:%h opa_value:%h opa_ready:%b opb_value:%h opb_ready:%b", 
                $time, write_value, write_valid, opa_idx, opa_valid, opb_idx, opb_valid, cdb_in.squash_enable, opa_value, opa_ready, opb_value, opb_ready);
        clock = 0;
        reset = 1;
        stall = 0;
        opa_idx = 0;
        opa_valid = 0;
        opb_idx = 0;
        opb_valid = 0;
        checkpoint_rat_ready_in = 0;
        cdb_in.valid = 0;
        cdb_in.squash_enable = 0;
    
        @(negedge clock);
        
        reset = 0;
        
        for(int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
            checkpoint_rat_value_in[i] = i;
        end

        /////////////////////////////////////////////////////////////////////////
        // Read from Map Table                               //
        /////////////////////////////////////////////////////////////////////////
        $display("Reading all values");
        read_opa_opb();

        /////////////////////////////////////////////////////////////////////////
        // Add reg tag from freelist on arch destnation from ROB           //
        /////////////////////////////////////////////////////////////////////////
        $display("Updating tag from freelist to map table for all idx");
        add_from_freelist_to_all_map_table_addr();
        $display("Updating tag from freelist to map table for all idx: DONE");
        opa_valid = 0;
        opb_valid = 0;

        /////////////////////////////////////////////////////////////////////////
        // Set CDB bit on all tags in the map table                   //
        /////////////////////////////////////////////////////////////////////////
        $display("Set CDB bit valid and set the tag ready to all locations in map table");
        cdb_set_valid_to_all_map_table_addr();
        $display("Set CDB bit valid and set the tag ready to all locations in map table: DONE");
        opa_valid = 0;
        opb_valid = 0;


        /////////////////////////////////////////////////////////////////////////
        // Add reg tag from freelist on arch destnation from ROB           //
        /////////////////////////////////////////////////////////////////////////
        $display("Updating tag from freelist to map table");
        add_from_freelist_read_opa(15,45);
        add_from_freelist_read_opa(8,37);
        add_from_freelist_read_opa(11,51);
        $display("Updating tag from freelist to map table: DONE");
        opa_valid = 0;
        opb_valid = 0;

        /////////////////////////////////////////////////////////////////////////
        // Set ready bit on tag when CDB broadcasts the tag            //
        /////////////////////////////////////////////////////////////////////////
        $display("Set CDB bit valid and set the tag ready in map table");
        cdb_set_valid_read_opb(8);
        $display("Set CDB bit valid and set the tag ready in map table: DONE");
        opa_valid = 0;
        opb_valid = 0;

        ////////////////////////////////////////////////////////////////////////////////
        // Simultaneous Add reg tag and CDB valid set                      //
        ////////////////////////////////////////////////////////////////////////////////

        $display("Simultaneous Add reg tag and CDB valid set");
        add_from_freelist_cdb_set_valid_read_opa_read_opb(12,38,15);
        $display("Simultaneous Add reg tag and CDB valid set: DONE");
        opa_valid = 0;
        opb_valid = 0;

        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint                        //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& CREATE AND SQUASH TO CHECKPOINT &&& ");

        $display("Creating checkpoint");
        save_checkpoint();
        $display("Creating checkpoint: DONE");

        $display("Updating map table");
        for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
        add_from_freelist_read_opa(i,i);
        end
        $display("Updating map table: DONE");

        $display("Squashing to checkpoint");
        squash_to_checkpoint(brat_map_value, brat_map_ready);
        $display("Squashing to checkpoint: DONE");
        opa_valid = 0;
        opb_valid = 0;
        $display("Reading all values");
        read_opa_opb();

        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and add reg tag simultaneously         //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND ADD REG TAG &&& ");

        $display("Updating map table");
        for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
        add_from_freelist_read_opa(i,i);
        end
        $display("Updating map table: DONE");
        opa_valid = 0;
        opb_valid = 0;

        $display("Squashing to checkpoint and adding reg tag simultaneously");
        squash_to_checkpoint_add_from_freelist(brat_map_value, brat_map_ready,19,23);
        $display("Squashing to checkpoint and adding reg tag simultaneously: DONE");

        $display("Reading all values");
        read_opa_opb();

        /////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and CDB valid set simultaneously           //
        /////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND CDB VALID SET &&& ");

        $display("Updating map table");
        for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
        add_from_freelist_read_opa(i,i);
        end
        $display("Updating map table: DONE");
        opa_valid = 0;
        opb_valid = 0;

        $display("Squashing to checkpoint and setting ready bit simultaneously");
        squash_to_checkpoint_cdb_set_valid(brat_map_value, brat_map_ready,11);
        $display("Squashing to checkpoint and setting ready bit simultaneously: DONE");

        $display("Reading all values");
        read_opa_opb();

        ///////////////////////////////////////////////////////////////////////////
        // Squash to checkpoint and add reg tag and CDB valid set simultaneously //
        ///////////////////////////////////////////////////////////////////////////
        $display(" &&& SQUASH TO CHECKPOINT AND ADD REG TAG AND CDB VALID SET &&& ");

        for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
        add_from_freelist_read_opa(i,i);
        end
        $display("Updating map table: DONE");
        opa_valid = 0;
        opb_valid = 0;


        $display("Squashing to checkpoint and adding reg tag and setting ready bit simultaneously");
        squash_to_checkpoint_add_from_freelist_cdb_set_valid(brat_map_value, brat_map_ready,19,23,11);
        $display("Squashing to checkpoint and adding reg tag and setting ready bit simultaneously: DONE");

        $display("Reading all values");
        read_opa_opb();

        /////////////////////////////////////////////////////////////////////////
        // RANDOM TESTING                                                      //
        /////////////////////////////////////////////////////////////////////////
        
        $display(" &&& RANDOM TESTING &&& ");
          for (int i = 0; i < 10000; i++) begin
            temp_idx = $random % `ARCH_REGFILE_SIZE;
            temp_value = $random % `PHYS_REGFILE_SIZE;    
            temp_cdb = $random % `ARCH_REGFILE_SIZE;    
            j = $random % 8;
            k = $random % 4;
            case(j)
            0:  read_opa_opb(); 
            1:  add_from_freelist_read_opa(temp_idx, temp_value);
            2:  add_from_freelist_read_opb(temp_idx, temp_value);
            3:  cdb_set_valid_read_opa(temp_cdb);
            4:  cdb_set_valid_read_opb(temp_cdb);
            5:  add_from_freelist_cdb_set_valid_read_opa_read_opb(temp_idx, temp_value, temp_cdb);
            6:  save_checkpoint();
            7:  begin
                case(k)
                    0: squash_to_checkpoint(brat_map_value, brat_map_ready);
                    1: squash_to_checkpoint_add_from_freelist(brat_map_value, brat_map_ready, temp_idx, temp_value);
                    2: squash_to_checkpoint_cdb_set_valid(brat_map_value, brat_map_ready, temp_cdb);
                    3: squash_to_checkpoint_add_from_freelist_cdb_set_valid(brat_map_value, brat_map_ready, temp_idx, temp_value, temp_cdb);
                endcase
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
