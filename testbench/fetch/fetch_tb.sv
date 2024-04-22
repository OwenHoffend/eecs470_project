`ifndef __FETCH_TB_
`define __FETCH_TB_

`include "./headers/include.svh"

module fetch_tb;

logic clock, reset;
CDB_PACKET cdb_in;
logic fetch_stall;
logic [63:0] Imem2proc_data;

logic [`XLEN-1:0] proc2Imem_addr;
FETCH_PACKET if_packet_out;

// logic [`XLEN-1:0] BTB_target;
// logic		      BTB_taken;

fetch fetch_dut(
    .clock(clock),
    .reset(reset),
    .cdb_in(cdb_in),
    .dispatch_stall(fetch_stall),
    .Icache2proc_data(Imem2proc_data),
    .proc2Icache_addr(proc2Imem_addr),
    .Icache2proc_valid(1),
    .if_packet_out(if_packet_out)
    // .BTB_target(BTB_target),
    // .BTB_taken(BTB_taken)
);

function fail(
        string signal,
        integer correct_result
    );
        $display("TESTCASE FAILED @ time %4.0f: %s caused failure. Should be: %h", $time, signal, correct_result);
        //$display("---available: %b. full: %b", available, full);
        //$display("Current size: %h, Entry counter: %h", num_entries_actual, entry_counter);
        `ifdef FINISH_ON_ERROR
            $finish;
        `endif
    endfunction

always begin
    #5 clock = ~clock;
end

always_ff @(posedge clock) begin
    //if (fetch_stall ^ if_packet_out.valid) begin
        //fail("if_packet_out.valid", fetch_stall);
    //end
    //if ()
end

always_ff @(negedge clock) begin
    if (reset)
        Imem2proc_data <= 64'h0010001000100010;
    else
        Imem2proc_data <= Imem2proc_data + if_packet_out.PC;
end

initial begin
    $dumpvars;
    $monitor("time:%4.0f if_v:%b if_pc:%h inst:%h", 
             $time, if_packet_out.valid, if_packet_out.PC, if_packet_out.inst);
    reset = 0;
    clock = 0;
    cdb_in = 0;
    fetch_stall = 0;
    // BTB_target = 0;
    // BTB_taken = 0;
    @(negedge clock);
    reset = 1;
    @(negedge clock);
    reset = 0;
    for (int i = 0; i < 20; i++) begin
        @(negedge clock);
    end
    
    $display("PASSED!");
    $finish;
end

endmodule
`endif