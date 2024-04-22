// This is a generic definition for a FIFO.  To use, just update IO and save a copy of this file
`ifndef _FIFO__
`define _FIFO__
`timescale 1ns/100ps
`include "./headers/include.svh"


module FIFO #(
    parameter type DATA_TYPE = PHYS_REG_TAG,
    parameter FIFO_DEPTH = `FREELIST_SIZE,
    parameter INIT_AVAILABLE = 1
)(
    input                                 clock,                   // clock
    input                                 reset,                   // Synchronous reset/clear the FIFO
    
    input                                 checkpoint_enable,       // enables squashes/resetting tail_ptr to an index
    input [$clog2(FIFO_DEPTH)-1:0]        checkpoint_head_ptr_in,  // use if you want to restore FIFO to a checkpoint
    
    input                                 enqueue,                 // Valid input
    input DATA_TYPE                       data_in,     
    input                                 dequeue,

`ifdef DEBUG_MODE
    output logic [$clog2(FIFO_DEPTH)-1:0] head_ptr_out,
    output logic [$clog2(FIFO_DEPTH)-1:0] tail_ptr_out,
    output logic                          available,
    output DATA_TYPE     [FIFO_DEPTH-1:0] FIFO_debug_out,
`endif

    output DATA_TYPE                      head_packet,  
    output logic                          full,                    // Are we at capacity?
    output logic [$clog2(FIFO_DEPTH)-1:0] checkpoint_head_ptr_out
);
    //FIFO Signals and Structure
    DATA_TYPE [FIFO_DEPTH-1:0] FIFO, FIFO_next;
    logic [$clog2(FIFO_DEPTH)-1:0] head_ptr, tail_ptr, head_ptr_next, tail_ptr_next;
    // logic available, available_next;
    logic available_next;
`ifndef DEBUG_MODE
    logic                          available;
`endif
    always_comb begin   
        // FIFO state indicators
        case(available)
            1'b0: available_next = enqueue & ~dequeue;
            1'b1: available_next = ~((head_ptr + 1'b1 == tail_ptr) & 
                                    (dequeue & ~enqueue));
        endcase
        full = (head_ptr == tail_ptr) & available;

        FIFO_next = FIFO;
        head_ptr_next = checkpoint_enable ? checkpoint_head_ptr_in : 
                        (dequeue & (available | enqueue)) ? head_ptr + 1'b1 : 
                        head_ptr;
        tail_ptr_next  = tail_ptr;

        // Enqueue some data
        if(enqueue & (~full | dequeue)) begin
            tail_ptr_next = tail_ptr + 1'b1;
            FIFO_next[tail_ptr] = data_in;
        end

    `ifdef DEBUG_MODE
        head_ptr_out = head_ptr;
        tail_ptr_out = tail_ptr;
        FIFO_debug_out = FIFO;
    `endif

        //Outputs
        head_packet  = (~available & enqueue) ? data_in : FIFO[head_ptr]; // Forward input to output when queue is empty
        checkpoint_head_ptr_out = head_ptr_next; // Checkpoint will forward dequeued data from the same cycle
                                                 // This is so a JALR linked register is not squashed if the jump target is mispredicted
                                                 // This does not happen in the BRAT, as data is not dequeued from the BRAT FIFOs
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            for (int i = 0; i < FIFO_DEPTH; i++) begin
                FIFO[i] <= `SD $unsigned(i) + `ARCH_REGFILE_SIZE;
            end
            head_ptr  <= `SD 0;
            tail_ptr  <= `SD 0;
            available <= `SD INIT_AVAILABLE;
        end else begin
            FIFO        <= `SD FIFO_next;
            head_ptr    <= `SD head_ptr_next;
            tail_ptr    <= `SD tail_ptr_next;
            available   <= `SD available_next;
        end
    end
endmodule

`endif
