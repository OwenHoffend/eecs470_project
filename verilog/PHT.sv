/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  PHT.v                                               //
//                                                                     //
//  Description :  This module holds the saturating PHT counters       //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __PHT_V__
`define __PHT_V__
`timescale 1ns/100ps
`include "./headers/include.svh"

module PHT(
    input  [`GHB_SIZE-1:0] rd_idx, wb_idx,     // read/writeback index
    input  wb_taken, wb_en, clock, reset,      // was the branch taken or not taken?

    output logic  taken     // read data

`ifdef DEBUG_MODE
    ,
	output logic  [2**(`GHB_SIZE)-1:0] [`SATURATION_BITS-1:0] debug_PHT, debug_next_PHT,
    output logic  [2**(`GHB_SIZE)-1:0] debug_PHT_dirty_idxs
`endif

);
  
    logic  [2**(`GHB_SIZE)-1:0] [`SATURATION_BITS-1:0] saturation, next_saturation;   // 2^(GHB_SIZE), (SATURATION_BITS) counters
    logic  [`SATURATION_BITS-1:0] weakly_taken, weakly_not_taken, strongest_taken;

`ifdef DEBUG_MODE
	assign debug_PHT = saturation;
	assign debug_next_PHT = next_saturation;
`endif

    assign weakly_taken = 2**(`SATURATION_BITS-1);
    assign weakly_not_taken = 2**(`SATURATION_BITS-1)-1;
    assign strongest_taken = 2**(`SATURATION_BITS)-1;

    always_comb begin
        next_saturation = saturation;

        if (wb_en) begin
            if (~wb_taken) begin                  // if not taken
                if (saturation[wb_idx] == 0) begin  // don't roll over
                    next_saturation[wb_idx] = 0;
                end else begin
                    next_saturation[wb_idx] = saturation[wb_idx] - 1'b1; // decrement the state
                end
            end else begin                        // if taken
                if (saturation[wb_idx] == strongest_taken) begin // don't roll over
                    next_saturation[wb_idx] = strongest_taken;
                end else begin
                    next_saturation[wb_idx] = saturation[wb_idx] + 1'b1; // increment the state
                end
            end
        end
        taken = (next_saturation[rd_idx] >= weakly_taken); // forwards writes, taken means we're at num_states/2
    end

    //synopsys sync_set_reset "reset" 
    always_ff @(posedge clock) begin
        if (reset) begin
            for (int i = 0; i < 2**(`GHB_SIZE); i++) begin
                saturation[i] <= `SD weakly_not_taken;
            end
        end
        else if (wb_en) begin
            saturation[wb_idx] <= `SD next_saturation[wb_idx];
`ifdef DEBUG_MODE
            debug_PHT_dirty_idxs[wb_idx] <= `SD 1'b1;
`endif
        end
    end

endmodule // PHT

`endif //__PHT_V__
