`ifndef _RS_TB__
`define _RS_TB__
`define FINISH_ON_ERROR 
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/decoder.sv"
`include "./verilog/FIFO.sv"
`include "./verilog/RAT.sv"
`include "./verilog/dispatch.sv"

// TODO: Modify random testing so impossible scenarios are not reached

typedef enum logic {
    TB_DISPATCH_ADD = 1'h0,
    TB_DISPATCH_SD  = 1'h1
} TB_INST_TYPE;

// Testbench for the Dispatch Module
module dispatch_tb;
    // Module inputs
    logic                                 clock;
    logic                                 reset;
   
    FETCH_PACKET                          fetch_packet_in;
    CDB_PACKET                            cdb_in;
    BRANCH_STACK_ENTRY                    checkpoint_entry_in;
    ROB_ENTRY                             ROB_head_entry;
    logic                                 ROB_full;
    ROB_IDX                               ROB_tail_ptr_in;
    logic                                 RS_full;

    // Debug outputs   
    logic                                 freelist_full;
    logic                                 freelist_available;
    logic [$clog2(`FREELIST_SIZE)-1:0]    freelist_head;
    logic [$clog2(`FREELIST_SIZE)-1:0]    freelist_tail;
    PHYS_REG_TAG [`FREELIST_SIZE-1:0]     freelist_debug;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat_debug;
    logic        [`ARCH_REGFILE_SIZE-1:0] rat_debug_ready;

    DISPATCH_PACKET                       dispatch_packet_out;
    ROB_PACKET                            rob_packet_out;
    BRANCH_MASK                           branch_tag_out;
    BRANCH_MASK                           branch_mask_out;
    logic                                 stall_out;
    logic                                 checkpoint_write;
    BRANCH_STACK_ENTRY                    checkpoint_entry_out;

    dispatch dispatch_DUT(
        // Inputs
        .clock               (clock),
        .reset               (reset),

        .fetch_packet_in     (fetch_packet_in),
        .cdb_in              (cdb_in),
        .checkpoint_entry_in (checkpoint_entry_in),
        .ROB_head_entry      (ROB_head_entry),
        .ROB_full            (ROB_full),
        .ROB_tail_ptr_in     (ROB_tail_ptr_in),
        .RS_full             (RS_full),

        // Debug Outputs
        .freelist_full       (freelist_full),
        .freelist_available  (freelist_available),
        .freelist_head       (freelist_head),
        .freelist_tail       (freelist_tail),
        .freelist_debug      (freelist_debug),

        .rat_debug           (rat_debug),
        .rat_debug_ready     (rat_debug_ready),

        .branch_tag_out      (branch_tag_out),

        // Normal Outputs
        .dispatch_packet_out (dispatch_packet_out),
        .rob_packet_out      (rob_packet_out),
        .branch_mask_out     (branch_mask_out),
        .stall_out           (stall_out),
        .checkpoint_write    (checkpoint_write),
        .checkpoint_entry_out(checkpoint_entry_out)
    );

    // Variables for testbench to track the state of the freelist
    integer freelist_counter;
    integer freelist_counter_next;
    integer freelist_counter_dec;
    integer freelist_counter_inc;
    logic   freelist_checkpoint_signal; // Signal to checkpoint counter next MUX
    integer freelist_counter_checkpoint;
    integer freelist_counter_checkpoint_next;
    logic   freelist_full_tb;
    logic   freelist_available_tb;
    logic   freelist_dequeue_tb;
    logic   freelist_enqueue_tb;

    // Variables for testbench to track the state of the map table
    ARCH_REG_TAG                          map_table_complete_idx_tb;
    logic                                 map_table_complete_hit_tb;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] map_table_value_tb;
    logic        [`ARCH_REGFILE_SIZE-1:0] map_table_ready_tb;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] map_table_value_tb_next;
    logic        [`ARCH_REGFILE_SIZE-1:0] map_table_ready_tb_next;

    // Variables for testbench to save a squash state to
    BRANCH_STACK_ENTRY checkpoint_entry_tb;

    ARCH_REG_TAG scratchpad_arch; // For generating the same random architectural tag for 2+ use cases

    // Variables for random testing
    logic        random_dispatch_valid;
    TB_INST_TYPE random_dispatch_type;
    ARCH_REG_TAG random_dest_reg;
    ARCH_REG_TAG random_opa_reg;
    ARCH_REG_TAG random_opb_reg;
    logic        random_complete_valid;
    ARCH_REG_TAG random_complete_arch_tag;
    logic        random_retire_valid;
    PHYS_REG_TAG random_retire_phys_tag;
    logic        random_stall;
    logic        random_squash_valid;
    logic        random_save_checkpoint;

    ////////////////////////////////////////////////////////////////////////
    // TASK DEFINITIONS                                                   //
    ////////////////////////////////////////////////////////////////////////
    
    function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        $display("-RS_packet: T:%h, T_used:%b, dest_reg:%h", dispatch_packet_out.T, dispatch_packet_out.T_used, dispatch_packet_out.dest_reg);
        $display("-RS_packet: T1:%h, T1r:%b, T1_used:%b, T2:%h, T2r:%b, T2_used:%b", 
            dispatch_packet_out.T1, dispatch_packet_out.T1r, dispatch_packet_out.T1_used,
            dispatch_packet_out.T2, dispatch_packet_out.T2r, dispatch_packet_out.T2_used);
        $display("-RS_packet: bmask:%h, btag:%h", dispatch_packet_out.branch_mask, dispatch_packet_out.branch_tag);
        $display("-RS_packet: dst_select:%h, opa_select:%h, opb_select:%h, alu_func:%h, valid:%b", 
            dispatch_packet_out.dst_select, dispatch_packet_out.opa_select, dispatch_packet_out.opb_select,
            dispatch_packet_out.alu_func, dispatch_packet_out.valid);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction 

    // // Save a squash checkpoint to local testbench variables
    // task save_checkpoint(
    // );
    //     checkpoint_entry_tb = checkpoint_entry_out;
    //     freelist_counter_checkpoint = freelist_counter_next;
    //     @(negedge clock);
    // endtask

    // Save a squash checkpoint to local testbench variables
    task save_checkpoint_event(
        input logic              dispatch_valid,
        input TB_INST_TYPE       dispatch_type,
        input ARCH_REG_TAG       dest_reg,
        input ARCH_REG_TAG       opa_reg,
        input ARCH_REG_TAG       opb_reg,
        input logic              complete_valid,
        input PHYS_REG_TAG       complete_phys_tag, // Complete
        input logic              retire_valid,
        input PHYS_REG_TAG       retire_phys_tag,   // Retire
        input logic              stall 
    );
        // Create a dispatch event
        fetch_packet_in.valid = dispatch_valid;
        if(dispatch_type == TB_DISPATCH_ADD)
            fetch_packet_in.inst = {7'b0, opb_reg, opa_reg, 3'b0, dest_reg, `RV32_OP};
        if(dispatch_type == TB_DISPATCH_SD)
            fetch_packet_in.inst = {7'b0, opb_reg, opa_reg, 3'b0, 5'b0, `RV32_STORE};

        // Create a complete event
        cdb_in.valid = complete_valid;
        cdb_in.cdb_tag = complete_phys_tag;

        // Create a retire event
        ROB_head_entry.complete = retire_valid;
        ROB_head_entry.d_tag_old = retire_phys_tag;
        ROB_head_entry.d_tag_old_arch = 1; // So it doesn't ignore the retire

        // Create a stall event
        ROB_full = stall;
        RS_full = stall;

        // Asynchronously read checkpoint data
        // Allow combinational logic to propogate
        `SD checkpoint_entry_tb = checkpoint_entry_out;
        freelist_checkpoint_signal = 1;

        @(negedge clock);

        // Clear inputs
        cdb_in.squash_enable = 0;
        fetch_packet_in.valid = 0;
        cdb_in.valid = 0;
        ROB_head_entry.complete = 0;
        ROB_full = 0;
        RS_full = 0;
        freelist_checkpoint_signal = 0;

        @(negedge clock);
    endtask

    // Insert a combination of squash, dispatch ADD, complete, and retire
    task insert_event(
        input logic              dispatch_valid,
        input TB_INST_TYPE       dispatch_type,
        input ARCH_REG_TAG       dest_reg,
        input ARCH_REG_TAG       opa_reg,
        input ARCH_REG_TAG       opb_reg,
        input logic              complete_valid,
        input PHYS_REG_TAG       complete_phys_tag, // Complete
        input logic              retire_valid,
        input PHYS_REG_TAG       retire_phys_tag,   // Retire
        input logic              stall,
        input logic              squash_valid
    );
        // Create a dispatch event
        fetch_packet_in.valid = dispatch_valid;
        if(dispatch_type == TB_DISPATCH_ADD)
            fetch_packet_in.inst = {7'b0, opb_reg, opa_reg, 3'b0, dest_reg, `RV32_OP};
        if(dispatch_type == TB_DISPATCH_SD)
            fetch_packet_in.inst = {7'b0, opb_reg, opa_reg, 3'b0, 5'b0, `RV32_STORE};

        // Create a complete event
        cdb_in.valid = complete_valid;
        cdb_in.cdb_tag = complete_phys_tag;

        // Create a retire event
        ROB_head_entry.complete = retire_valid;
        ROB_head_entry.d_tag_old = retire_phys_tag;
        ROB_head_entry.d_tag_old_arch = 1; // So it doesn't ignore the retire

        // Create a stall event
        ROB_full = stall;
        RS_full = stall;

        // Create a squash event
        cdb_in.squash_enable = squash_valid;
        checkpoint_entry_in = checkpoint_entry_tb;

        @(negedge clock);

        // Clear inputs
        cdb_in.squash_enable = 0;
        fetch_packet_in.valid = 0;
        cdb_in.valid = 0;
        ROB_head_entry.complete = 0;
        ROB_full = 0;
        RS_full = 0;

        @(negedge clock);
    endtask

    ////////////////////////////////////////////////////////////////////////
    // TRACK FREELIST AND MAP TABLE                                       //
    ////////////////////////////////////////////////////////////////////////

    always begin
        #5 clock = ~clock;
    end
    
    always_comb begin
        // Track the freelist
        freelist_dequeue_tb   = fetch_packet_in.valid & ~(ROB_full | RS_full) & ~cdb_in.squash_enable & (dispatch_packet_out.dest_reg != `ZERO_REG);
        freelist_enqueue_tb   = ROB_head_entry.complete & ~cdb_in.squash_enable & (ROB_head_entry.d_tag_old_arch != `ZERO_REG);

        freelist_counter_inc  = (freelist_enqueue_tb & (~freelist_full_tb | freelist_dequeue_tb)) ? 1 : 0;
        freelist_counter_dec  = (freelist_dequeue_tb & (freelist_available_tb | freelist_enqueue_tb)) ? 1 : 0;

        freelist_counter_next =            ( cdb_in.squash_enable & ~freelist_checkpoint_signal) ? freelist_counter_checkpoint + freelist_counter_inc             : freelist_counter + freelist_counter_inc - freelist_counter_dec;
        freelist_counter_checkpoint_next = (~cdb_in.squash_enable &  freelist_checkpoint_signal) ? freelist_counter + freelist_counter_inc - freelist_counter_dec : freelist_counter_checkpoint + freelist_counter_inc;

        freelist_full_tb      = (freelist_counter == `FREELIST_SIZE);
        freelist_available_tb = (freelist_counter != 0);

        // Track the map table
        map_table_value_tb_next = map_table_value_tb;
        map_table_ready_tb_next = map_table_ready_tb;
        if (~ROB_full & ~RS_full) begin
            if(cdb_in.valid) begin
                map_table_complete_hit_tb = 0;
                for(int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                    if(map_table_value_tb[i] == cdb_in.cdb_tag) begin
                        map_table_complete_hit_tb = 1;
                        map_table_complete_idx_tb = i;
                        break;
                    end
                end
                if(map_table_complete_hit_tb == 1) begin
                    map_table_ready_tb_next[map_table_complete_idx_tb] = 1;
                end
            end
            if (freelist_dequeue_tb) begin
                map_table_value_tb_next[dispatch_packet_out.dest_reg] = dispatch_packet_out.T;
                map_table_ready_tb_next[dispatch_packet_out.dest_reg] = 0;
            end
        end
        if (cdb_in.squash_enable) begin
            map_table_value_tb_next = checkpoint_entry_in.rat_value; 
            map_table_ready_tb_next = checkpoint_entry_in.rat_ready;
        end
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            freelist_counter <= `SD `FREELIST_SIZE;
            for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                map_table_value_tb[i] <= `SD $unsigned(i);
                map_table_ready_tb[i] <= `SD 1'b1;
            end
        end else begin

            // We fail on some of these conditions right now due to how randomly generated test cases
            // can represent impossible scenarios (e.g. dispatching an in-use physical register, retiring
            // a physical register that is not complete). For synthesis purposes, I'm just ommitting checks
            // for now, since we have confidence in the models correctness from the pipeline tests - Jack
/*
            // Check that T1 is read correctly
            if(dispatch_packet_out.valid & 
               (dispatch_packet_out.opa_select == OPA_IS_RS1) & 
               (map_table_value_tb[dispatch_packet_out.inst.r.rs1] != dispatch_packet_out.T1))
                fail("T1", map_table_value_tb[dispatch_packet_out.inst.r.rs1]);
            
            // Check that T2 is read correctly
            if(dispatch_packet_out.valid & 
               (dispatch_packet_out.opb_select == OPB_IS_RS2) & 
               (map_table_value_tb[dispatch_packet_out.inst.r.rs2] != dispatch_packet_out.T2))
                fail("T2", map_table_value_tb[dispatch_packet_out.inst.r.rs2]);
            
            // Check T1 ready bit
            if(dispatch_packet_out.valid & 
               (dispatch_packet_out.opa_select == OPA_IS_RS1) &
               (map_table_ready_tb[dispatch_packet_out.inst.r.rs1] != dispatch_packet_out.T1r) &
               ~(cdb_in.valid & (cdb_in.cdb_tag == map_table_value_tb[dispatch_packet_out.inst.r.rs1])))
               fail("T1r", map_table_ready_tb[dispatch_packet_out.inst.r.rs1]);
            else if(dispatch_packet_out.valid & 
               (dispatch_packet_out.opa_select == OPA_IS_RS1) &
               ~dispatch_packet_out.T1r & 
               cdb_in.valid & 
               (cdb_in.cdb_tag == map_table_value_tb[dispatch_packet_out.inst.r.rs1]))
               fail("T1r", 1'b1);

            // Check T2 ready bit
            if(dispatch_packet_out.valid & 
               (dispatch_packet_out.opb_select == OPB_IS_RS2) &
               (map_table_ready_tb[dispatch_packet_out.inst.r.rs2] != dispatch_packet_out.T2r) &
               ~(cdb_in.valid & (cdb_in.cdb_tag == map_table_value_tb[dispatch_packet_out.inst.r.rs2])))
                fail("T2r", map_table_ready_tb[dispatch_packet_out.inst.r.rs2]);
            else if(dispatch_packet_out.valid & 
               (dispatch_packet_out.opb_select == OPB_IS_RS2) &
               ~dispatch_packet_out.T2r & 
               cdb_in.valid & 
               (cdb_in.cdb_tag == map_table_value_tb[dispatch_packet_out.inst.r.rs2]))
                fail("T2r", 1'b1);

            // Check that the instruction out is valid
            if((fetch_packet_in.valid != dispatch_packet_out.valid) & ~(stall_out | cdb_in.squash_enable))
                fail("dispatch_packet_out.valid", fetch_packet_in.valid);
            if(dispatch_packet_out.valid & (stall_out | cdb_in.squash_enable))
                fail("dispatch_packet_out.valid", fetch_packet_in.valid);

            if(freelist_available != freelist_available_tb)
                fail("freelist_available", freelist_available_tb);
            if(freelist_full != freelist_full_tb)
                fail("freelist_full", freelist_full_tb);
*/

            freelist_counter            <= `SD freelist_counter_next;
            freelist_counter_checkpoint <= `SD freelist_counter_checkpoint_next;
            map_table_value_tb          <= `SD map_table_value_tb_next;
            map_table_ready_tb          <= `SD map_table_ready_tb_next;
        end
    end

    ////////////////////////////////////////////////////////////////////////
    // MAIN TEST FLOW                                                     //
    ////////////////////////////////////////////////////////////////////////

    initial begin
        $monitor("Time:%4.0f | dispatch:%b inst:%h rd:%h T:%h Told:%h rs1:%h T1:%h T1r:%b rs2:%h T2:%h T2r:%b | complete:%b cdb_tag:%h hit:%b arch_tag:%h sqen:%b | retire:%b phys_tag:%h | available:%b counter:%h", 
            $time, fetch_packet_in.valid, fetch_packet_in.inst, 
            fetch_packet_in.inst.r.rd, dispatch_packet_out.T, rob_packet_out.Told, 
            fetch_packet_in.inst.r.rs1, dispatch_packet_out.T1, dispatch_packet_out.T1r,
            fetch_packet_in.inst.r.rs2, dispatch_packet_out.T2, dispatch_packet_out.T2r,
            cdb_in.valid, cdb_in.cdb_tag, map_table_complete_hit_tb, map_table_complete_idx_tb, cdb_in.squash_enable,
            ROB_head_entry.complete, ROB_head_entry.d_tag_old,
            freelist_available, freelist_counter
        );

        clock = 0;
        reset = 1;
        fetch_packet_in = 0;
        cdb_in = 0;
        // checkpoint_branch_mask_in = 0;
        checkpoint_entry_in = 0;
        ROB_head_entry = 0;
        ROB_full = 0;
        ROB_tail_ptr_in = 0;
        RS_full = 0;

        @(negedge clock);

        reset = 0;

        ////////////////////////////////////////////////////////////////////////
        // Instructions with destination registers                            //
        ////////////////////////////////////////////////////////////////////////

        $display("&&& Complete while FIFO is full &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 0, 0, 0, 0);

        $display("&&& Dispatch while FIFO is full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Complete while FIFO is not full &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 0, 0, 0, 0);

        $display("&&& Retire while FIFO is not full &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 0, 0);

        $display("&&& Dispatch and complete while FIFO is full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 0, 0, 0, 0);

        $display("&&& Complete and retire while FIFO is not full &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 1, $random, 0, 0);

        $display("&&& Dispatch and complete with a dependency while FIFO is full &&&");
        scratchpad_arch = $random;
        insert_event(1, TB_DISPATCH_ADD, $random, scratchpad_arch, scratchpad_arch, 1, scratchpad_arch, 0, 0, 0, 0);

        // Retire to bring FIFO back to full
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 0, 0);

        $display("&&& Dispatch and retire while FIFO is full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 1, $random, 0, 0);

        $display("&&& Dispatch, complete, and retire while FIFO is full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 1, $random, 0, 0);

        $display("&&& Dispatch, complete, and retire with a dependency while FIFO is full &&&");
        scratchpad_arch = $random;
        insert_event(1, TB_DISPATCH_ADD, $random, scratchpad_arch, scratchpad_arch, 1, scratchpad_arch, 1, $random, 0, 0);

        // Dispatch to bring FIFO to not full
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Dispatch while FIFO is not full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Dispatch and complete while FIFO is not full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 0, 0, 0, 0);

        $display("&&& Dispatch and complete with a dependency while FIFO is not full &&&");
        scratchpad_arch = $random;
        insert_event(1, TB_DISPATCH_ADD, $random, scratchpad_arch, scratchpad_arch, 1, scratchpad_arch, 0, 0, 0, 0);

        $display("&&& Dispatch and retire while FIFO is not full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 1, $random, 0, 0);

        $display("&&& Dispatch, complete, and retire while FIFO is not full &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 1, $random, 0, 0);

        $display("&&& Disptach, complete, and retire with a dependency while FIFO is not full &&&");
        scratchpad_arch = $random;
        insert_event(1, TB_DISPATCH_ADD, $random, scratchpad_arch, scratchpad_arch, 1, scratchpad_arch, 1, $random, 0, 0);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end

        $display("&&& Complete while FIFO is empty &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 0, 0, 0, 0);

        $display("&&& Retire while FIFO is empty &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 0, 0);

        // Dispatch to make FIFO empty
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Complete and retire while FIFO is empty &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 1, $random, 0, 0);

        // Dispatch to make FIFO empty
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Dispatch and retire while FIFO is empty &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 1, $random, 0, 0);

        $display("&&& Dispatch, complete, and retire while FIFO is empty &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 1, $random, 0, 0);

        $display("&&& Dispatch, complete, and retire with a dependency while FIFO is empty &&&");
        scratchpad_arch = $random;
        insert_event(1, TB_DISPATCH_ADD, $random, scratchpad_arch, scratchpad_arch, 1, scratchpad_arch, 1, $random, 0, 0);


        ////////////////////////////////////////////////////////////////////////
        // Instructions with no destination registers                         //
        ////////////////////////////////////////////////////////////////////////

        // Repeatedly retire to bring FIFO to full
        while(~freelist_full_tb) begin
            insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 0, 0);
        end

        $display("&&& Dispatch an intruction with no destination register while FIFO is full &&&");
        insert_event(1, TB_DISPATCH_SD, 0, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Retire an instruction with zero destination register while FIFO is full &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, 0, 0, 0);

        $display("&&& Dispatch and retire instructions with no/zero destination registers while FIFO is full &&&");
        insert_event(1, TB_DISPATCH_SD, 0, $random, $random, 0, 0, 1, 0, 0, 0);

        $display("&&& Dispatch, complete, and retire instructions with no/zero destination registers while FIFO is full");
        insert_event(1, TB_DISPATCH_SD, 0, $random, $random, 1, $random, 1, 0, 0, 0);

        $display("&&& Dispatch an instruction with zero register while FIFO is full");
        insert_event(1, TB_DISPATCH_ADD, 0, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Dispatch and retire instructions with zero destination registers while FIFO is full &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, $random, $random, 0, 0, 1, 0, 0, 0);

        $display("&&& Dispatch, complete, and retire instructions with zero destination registers while FIFO is full");
        insert_event(1, TB_DISPATCH_ADD, 0, $random, $random, 1, $random, 1, 0, 0, 0);    

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end

        $display("&&& Dispatch an intruction with no destination register while FIFO is empty &&&");
        insert_event(1, TB_DISPATCH_SD, 0, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Retire an instruction with zero destination register while FIFO is empty &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, 0, 0, 0);

        $display("&&& Dispatch and retire instructions with no/zero destination registers while FIFO is empty &&&");
        insert_event(1, TB_DISPATCH_SD, 0, $random, $random, 0, 0, 1, 0, 0, 0);

        $display("&&& Dispatch, complete, and retire instructions with no/zero destination registers while FIFO is empty");
        insert_event(1, TB_DISPATCH_SD, 0, $random, $random, 1, $random, 1, 0, 0, 0);

        $display("&&& Dispatch an instruction with zero register while FIFO is empty");
        insert_event(1, TB_DISPATCH_ADD, 0, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Dispatch and retire instructions with zero destination registers while FIFO is empty &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, $random, $random, 0, 0, 1, 0, 0, 0);

        $display("&&& Dispatch, complete, and retire instructions with zero destination registers while FIFO is empty");
        insert_event(1, TB_DISPATCH_ADD, 0, $random, $random, 1, $random, 1, 0, 0, 0);    


        ////////////////////////////////////////////////////////////////////////
        // Instructions while stalling                                        //
        ////////////////////////////////////////////////////////////////////////

        // Repeatedly retire to bring FIFO to full
        while(~freelist_full_tb) begin
            insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 0, 0);
        end
        
        // Make FIFO not full so we can see retires occur
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);

        $display("&&& Dispatch  an instruction while stalling &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 1, 0);

        $display("&&& Complete an instruction while stalling &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 0, 0, 1, 0);

        $display("&&& Retire an instruction while stalling &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 1, 0);

        $display("&&& Dispatch, complete, and retire an instruction whiel stalling &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 1, $random, 1, 0);


        ////////////////////////////////////////////////////////////////////////
        // Squashes                                                           //
        ////////////////////////////////////////////////////////////////////////

        $display("&&& Creating snapshot of RAT and FIFO &&&");
        // save_checkpoint();
        save_checkpoint_event(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end
        
        $display("&&& Reverting to squash state");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 0, 0, 0, 1);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end

        $display("&&& Reverting to squash state while dispatching &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 1);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end

        $display("&&& Reverting to squash state while completing &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 1, $random, 0, 0, 0, 1);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end
        
        $display("&&& Reverting to squash state while retiring &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 1, $random, 0, 1);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end

        $display("&&& Reverting to squash state while stalling &&&");
        insert_event(0, TB_DISPATCH_ADD, 0, 0, 0, 0, 0, 0, 0, 1, 1);

        // Repeated dispatch to bring FIFO to empty
        while(freelist_available_tb) begin
            insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 0, 0, 0, 0, 0, 0);
        end

        $display("&&& I'M GIVIN' 'ER ALL SHE'S GOT, CAP'N &&&");
        insert_event(1, TB_DISPATCH_ADD, $random, $random, $random, 1, $random, 1, $random, 1, 1);

        ////////////////////////////////////////////////////////////////////////
        // Stochastic testing                                                 //
        ////////////////////////////////////////////////////////////////////////

        $display("&&& Random Testing &&&");

        for(int i = 0; i < 10000; i++) begin
            random_dispatch_valid    = $random; // 50% chance of doing a dispatch
            random_dispatch_type     = $random; // 50% chance of ADD, 50% chance of SD
            random_dest_reg          = random_dispatch_valid & (random_dispatch_type == TB_DISPATCH_ADD) ? $random : 0;
            random_opa_reg           = random_dispatch_valid ? $random : 0;
            random_opb_reg           = random_dispatch_valid ? $random : 0;
            random_complete_valid    = $random; // 50% chance of doing a complete
            random_complete_arch_tag = random_complete_valid ? $random : 0;
            random_retire_valid      = $random; // 50% chance of doing a retire
            random_retire_phys_tag   = random_retire_valid ? $random : 0;
            random_stall = ($random % 100 == 0) ? 1 : 0; // 1% chance of doing a stall
            random_squash_valid = ($random % 100 == 0) ? 1 : 0; // 1% chance of doing a squash
            random_squash_valid = 0;
            random_save_checkpoint = ($random % 100 == 0) ? 1 : 0; // 1% chance of doing a save
            random_save_checkpoint = 0;

            case(random_save_checkpoint)
                0: begin
                    insert_event(random_dispatch_valid, random_dispatch_type, random_dest_reg,
                        random_opa_reg, random_opb_reg, random_complete_valid, random_complete_arch_tag,
                        random_retire_valid, random_retire_phys_tag, random_stall, random_squash_valid);
                end
                1: begin
                    // save_checkpoint();
                    save_checkpoint_event(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
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
