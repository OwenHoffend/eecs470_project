`ifndef _BRAT__
`define _BRAT__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/CAM.sv"

module BRAT( 
    input                             clock,
    input                             reset,

    input                             checkpoint_write,         // Are we taking a snapshot on this cycle?
    input  BRANCH_MASK                checkpoint_branch_mask,   // Index to checkpoint to
    input  BRANCH_STACK_ENTRY         checkpoint_entry_in,      // Data to write
    input  CDB_PACKET                 cdb_in,                   // CDB in for updating on instruction complete
    input  ROB_ENTRY                  ROB_head_entry,           // ROB entry in for updating the freelist
    input                             rob_retire_cond,
    input                             ROB_available,
    
    output BRANCH_STACK_ENTRY         checkpoint_entry_out      // Read value from CDB in tag
);

    // Control signals for BRAT frames
    BRANCH_MASK checkpoint_write_mask;
    BRANCH_MASK complete_write_mask;
    logic 		retire_write;

    // FIFO logic
    FREELIST_IDX [`BS_SIZE-1:0] freelist_head_ptr, freelist_head_ptr_next;

    // RAT logic
    ARCH_REG_TAG [`BS_SIZE-1:0]                          cam_idx;
    logic        [`BS_SIZE-1:0]                          cam_hit;
    PHYS_REG_TAG [`BS_SIZE-1:0] [`ARCH_REGFILE_SIZE-1:0] rat_value, rat_value_next;
    logic        [`BS_SIZE-1:0] [`ARCH_REGFILE_SIZE-1:0] rat_ready, rat_ready_next;

    // Generate CAMs for BRAT RATs
    genvar i;
    generate
        for(i = 0; i < `BS_SIZE; i++) begin
            CAM #(
                .ARRAY_SIZE(`ARCH_REGFILE_SIZE),
                .DATA_SIZE($clog2(`PHYS_REGFILE_SIZE))
            ) ready_bit_cam (
                // Inputs
                .enable(cdb_in.valid),
                .array(rat_value[i]),
                .array_valid({`ARCH_REGFILE_SIZE{1'b1}}),
                .read_data(cdb_in.cdb_tag),

                // Outputs
                .read_idx(cam_idx[i]),
                .hit(cam_hit[i])
            );
        end
    endgenerate

    // Control signals, combinational logic for FIFOs and RATs in frames, output wrapping
    always_comb begin
        // Write only if checkpoint_write is high and we're one-hot selecting the appropriate BRAT frame
        checkpoint_write_mask = {`BS_SIZE{checkpoint_write}} & {`BS_SIZE{~(cdb_in.valid & cdb_in.squash_enable)}} & checkpoint_branch_mask;

        // Write complete data to RATs in BRAT frames based on this mask
        complete_write_mask = ~cdb_in.branch_tag; // This allows JALR instructions to forward the complete of their register write to the BRAT if we mispredict BRAT target

	    // On retire add entry to Freelists in BRAT frames based on this mask
	    retire_write = ROB_available & rob_retire_cond & (ROB_head_entry.d_tag_old_arch != `ZERO_REG);

        // Track FIFOs and RATs in frames
        for(int i = 0; i < `BS_SIZE; i++) begin
            // FIFO logic
            freelist_head_ptr_next[i] = (checkpoint_write_mask == (1 << i)) ? 
                                        checkpoint_entry_in.freelist_head_ptr : 
                                        freelist_head_ptr[i];

            // RAT logic
            rat_value_next[i] = rat_value[i];
            rat_ready_next[i] = rat_ready[i];

            if(complete_write_mask[i] & cam_hit[i]) begin
                rat_ready_next[i][cam_idx[i]] = 1;
            end
            if(checkpoint_write_mask[i]) begin
                rat_value_next[i] = checkpoint_entry_in.rat_value;
                rat_ready_next[i] = checkpoint_entry_in.rat_ready;
            end
        end

        // Output logic
        checkpoint_entry_out = 0;
        if(cdb_in.valid & cdb_in.squash_enable) begin
            for(int i = 0; i < `BS_SIZE; i++) begin
                if(cdb_in.branch_mask == (1 << i)) begin
                    checkpoint_entry_out.freelist_head_ptr = freelist_head_ptr_next[i];
                    checkpoint_entry_out.rat_value         = rat_value_next[i];
                    checkpoint_entry_out.rat_ready         = rat_ready_next[i];
                end
            end
        end
    end

    // Track Registers
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for(int i = 0; i < `BS_SIZE; i++) begin
                freelist_head_ptr[i] <= `SD 0;
                for (int j = 0; j < `ARCH_REGFILE_SIZE; j++) begin
                    rat_value[i][j] <= `SD $unsigned(j);
                    rat_ready[i][j] <= `SD 1'b1;
                end
            end
        end else begin
            for(int i = 0; i < `BS_SIZE; i++) begin
                freelist_head_ptr[i] <= `SD freelist_head_ptr_next[i];
                rat_value[i]         <= `SD rat_value_next[i];
                rat_ready[i]         <= `SD rat_ready_next[i];
            end
        end
    end

endmodule

`endif
