`ifndef _RAT__
`define _RAT__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/CAM.sv"

module RAT (
    input                                        clock,
    input                                        reset,
    input                                        stall,

    input                                        checkpoint_write,         // Squash enable bit
    input  PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_value_in,  // Squash value from BRAT
    input  logic        [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_ready_in,  // Squash ready bits from BRAT

    input  ARCH_REG_TAG                          dst_idx,                  // Architectural register for destination. T_old sent to ROB, tag overwritten by next value from freelist
    input  PHYS_REG_TAG                          write_value,              // New tag to overwrite at destination, comes from freelist
    input                                        write_valid,              // Do the write or not?
    input  ARCH_REG_TAG                          opa_idx,                  // Architectural register for operand A. Goes to RS
    input                                        opa_valid,                // Valid bit for operand A
    input  ARCH_REG_TAG                          opb_idx,                  // Architectural register for operand B. Goes to RS
    input                                        opb_valid,                // Valid bit for operand B
    // input  CDB_PACKET                            cdb_in,                // Don't pass in CDB; this makes the BRAT easier to code
    input  logic                                 cdb_valid,
    input  PHYS_REG_TAG                          cdb_tag,
    
`ifdef DEBUG_MODE
    output PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat_debug_value,
    output logic        [`ARCH_REGFILE_SIZE-1:0] rat_debug_ready,
`endif

    output PHYS_REG_TAG                          T_old_value,              // T_old sent to the ROB
    output PHYS_REG_TAG                          opa_value,          
    output logic                                 opa_ready,
    output PHYS_REG_TAG                          opb_value,
    output logic                                 opb_ready,

    output PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_value_out, // Map table, going to checkpoint module for snapshots   
    output logic        [`ARCH_REGFILE_SIZE-1:0] checkpoint_rat_ready_out  // Map table ready bits, going to checkpoint module for snapshots
);
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat_value, rat_value_next;
    logic        [`ARCH_REGFILE_SIZE-1:0] rat_ready, rat_ready_next;

    ARCH_REG_TAG complete_idx;
    logic        complete_hit;

    CAM #(
        .ARRAY_SIZE(`ARCH_REGFILE_SIZE),
        .DATA_SIZE($clog2(`PHYS_REGFILE_SIZE))
    ) ready_bit_cam (
        // Inputs
        .enable(cdb_valid),
        .array(rat_value),
        .array_valid({`ARCH_REGFILE_SIZE{1'b1}}),
        .read_data(cdb_tag),

        // Outputs
        .read_idx(complete_idx),
        .hit(complete_hit)
    );

    always_comb begin
        rat_value_next =  rat_value;
        rat_ready_next =  rat_ready;

    `ifdef DEBUG_MODE
        rat_debug_value = rat_value;
        rat_debug_ready = rat_ready;
    `endif

        if(cdb_valid & complete_hit) begin
            rat_ready_next[complete_idx] = 1;
        end
        if(~stall & write_valid) begin
            rat_value_next[dst_idx] = write_value;
            rat_ready_next[dst_idx] = 1'b0;
        end
        if (checkpoint_write) begin // If i move this before the previous two if statements, do I even have to forward completes from BRAT to RAT?
            rat_value_next = checkpoint_rat_value_in;
            rat_ready_next = checkpoint_rat_ready_in;
        end

        opa_value = opa_valid ? rat_value[opa_idx] : 0;
        opa_ready = opa_valid ? ((cdb_valid & (rat_value[opa_idx] == cdb_tag)) ? 1 : rat_ready[opa_idx]) : 0;
        opb_value = opb_valid ? rat_value[opb_idx] : 0;
        opb_ready = opb_valid ? ((cdb_valid & (rat_value[opb_idx] == cdb_tag)) ? 1 : rat_ready[opb_idx]) : 0;
        T_old_value = rat_value[dst_idx];

        // Forward data directly to checkpointing service. This is for JALR
        checkpoint_rat_value_out = rat_value_next;
        checkpoint_rat_ready_out = rat_ready_next;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
                rat_value[i] <= `SD $unsigned(i);
                rat_ready[i] <= `SD 1'b1;
            end
        end else begin
            rat_value <= `SD rat_value_next;
            rat_ready <= `SD rat_ready_next;
        end
    end
endmodule

`endif