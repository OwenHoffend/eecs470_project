`ifndef _ICACHE__
`define _ICACHE__
`timescale 1ns/100ps
`include "./headers/include.svh"

module icache (
    input               clock,
    input               reset,

    // Instruction Memory sends request data to ICache controller
    input         [3:0]      Imem2Ictrl_response,
    input         [3:0]      Imem2Ictrl_tag,

    // was ICache request rejected because of DCache priority?
    input                    reject_I_req,

    // Fetch sends cache requests to ICache controller
    input        [`XLEN-1:0] proc2Ictrl_addr,

    // ICache memory sends resopnses to ICache controller
    input        [63:0]      Icache2Ictrl_data,
    input                    Icache2Ictrl_valid,

    // On cache miss, ICache controller sends read request to Instruction Memory
    output BUS_COMMAND       Ictrl2Imem_command,
    output logic [`XLEN-1:0] Ictrl2Imem_addr, // Only bottom 16 bits are ever used

    // ICache controller returns results to fetch module
    output logic [63:0]      Ictrl2proc_data,  // value is memory[proc2Ictrl_addr]
    output logic             Ictrl2proc_valid, // when this is high

    // Index and Tag of current cache request, used to read into ICache
    output MEM_ADDR          current_addr,
    // Index and Tag of pending cache miss, used to write into ICache
    output logic             Ictrl2Icache_mem_write_en
);
    MEM_ADDR    last_addr;
    logic [3:0] current_mem_tag;
    logic miss_outstanding;
    logic [3:0] mem_response;

    // Get the current address and check if it changed
    assign current_addr = proc2Ictrl_addr[15:0];
    wire changed_addr = (current_addr[15:3] != last_addr[15:3]);

    // if hit in cache, valid = 1
    assign Ictrl2proc_valid = Icache2Ictrl_valid; 
    assign Ictrl2proc_data  = Icache2Ictrl_data;

    // send request: requests data from memory
    wire send_request = miss_outstanding && !changed_addr;

    // if address changes, need to update which tag we expect (Imem2Ictrl_response)
    wire update_mem_tag = changed_addr || miss_outstanding || Ictrl2Icache_mem_write_en;

    // if the request was rejected because of D-cache priority, treat response as 0
    assign mem_response = reject_I_req ? 0 : Imem2Ictrl_response;
    
    // if the address changed, and it was a MISS then we have unanswered miss
    // if same address, check for outstanding miss *and* denied mem request
    wire unanswered_miss = changed_addr ? !Ictrl2proc_valid : miss_outstanding && (mem_response == 0);

    assign Ictrl2Imem_addr = {proc2Ictrl_addr[`XLEN-1:3],3'b0};
    assign Ictrl2Imem_command = send_request ?  BUS_LOAD : BUS_NONE;

    // Imem2Ictrl_response is clocked into a register. when the received tag
    // matches the expected response, then write_enable = 1 
    assign Ictrl2Icache_mem_write_en = 
        (current_mem_tag == Imem2Ictrl_tag) &&
        (current_mem_tag != 0) &
        ~Ictrl2proc_valid & 
        ~changed_addr; 
        // Very specific case where a squash occurs the cycle before a memory read returns, the program counter will update but the
        // Icache will still write the fetched data, at the wrong program counter
    
    // synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            last_addr <= `SD -1;
            current_mem_tag  <= `SD 0;              
            miss_outstanding <= `SD 0;
        end else begin
            last_addr        <= `SD current_addr;
            miss_outstanding <= `SD unanswered_miss;
            if(update_mem_tag)
                current_mem_tag <= `SD mem_response;
        end
    end

endmodule

`endif
