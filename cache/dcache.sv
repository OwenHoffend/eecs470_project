`ifndef _DCACHE__
`define _DCACHE__
`timescale 1ns/100ps
`include "./headers/include.svh"

module dcache (
    input               clock,
    input               reset,

    // Data Memory sends response and tag to DCache controller
    input              [3:0] Dmem2Dctrl_response,
    input              [3:0] Dmem2Dctrl_tag,
    
    // was DCache request rejected because of ICache priority? (ex. if ROB is empty or near-empty)
    input                    reject_D_req,

    // LSQ sends cache requests to DCache controller
    input        BUS_COMMAND proc2Dctrl_command,
    input        [`XLEN-1:0] proc2Dctrl_addr,
    
    // DCache memory sends responses to DCache controller
    input        [`XLEN-1:0] Dcache2Dctrl_data,   // read value from cache
    input                    Dcache_proc_hit,     // indicates proc hit or miss

    // On cache miss, DCache controller sends request to Instruction Memory
    output       BUS_COMMAND Dctrl2Dmem_command,
    output logic [`XLEN-1:0] Dctrl2Dmem_addr,      // Only bottom 16 bits are ever used

    // DCache controller returns results to LSQ
    output logic [`XLEN-1:0] Dctrl2proc_data,  // value is memory[proc2Ictrl_addr]
    output logic             Dctrl2proc_valid, // when this is high
    
    // Upper 16 bits of current cache request, used to read into DCache
    output MEM_ADDR          current_addr,

    // stall signals
    output logic             mem_busy,
    output logic             cache_busy,

    // write from memory
    output logic             mem_write_enable,
    output MEM_ADDR          mem_write_addr,
    
    output logic             proc_write_enable,  // store
    output logic             proc_read_enable    // load
);
    MEM_ADDR    last_addr;
    logic [3:0] current_mem_tag;
    logic       miss_outstanding;
    logic [3:0] mem_response;
    //STORE_MAP_ENTRY [15:0] store_map, store_map_next; 
    logic       load_stall;
    logic       store_stall;
    wire        Dcache_read_hit;
    wire        Dcache_write_hit;
    wire        Dcache_hit;
    BUS_COMMAND last_proc2Dctrl_command;

    // Get the current address and check if it changed (cannot change if we aren't requesting a Dmem operation)
    assign current_addr = (proc2Dctrl_command != BUS_NONE) ? proc2Dctrl_addr[15:0] : 0;
    wire changed_addr = (current_addr[15:3] != last_addr[15:3]) & (proc2Dctrl_command != BUS_NONE);

    assign changed_command = proc2Dctrl_command != last_proc2Dctrl_command;

    // request data if address hasn't changed and miss outstanding, and if DMem is requesting an operation
    wire send_request = (miss_outstanding & ~(changed_addr | changed_command)) & (proc2Dctrl_command != BUS_NONE);

    // verify mem_write_enable is correct signal here
    wire update_mem_tag = (changed_addr | changed_command) | miss_outstanding | mem_write_enable;

    // if the request was rejected because of D-cache priority, treat response as 0
    assign mem_response = reject_D_req ? 0 : 
                          ((proc2Dctrl_command != BUS_NONE) & ~Dcache_hit) ? Dmem2Dctrl_response :
                          0;
                          
    // if the address changed, and it was a MISS then we have unanswered miss
    // if same address, check for outstanding miss *and* denied mem request
    wire unanswered_miss = (changed_addr | changed_command) ? !Dcache_hit : miss_outstanding && (mem_response == 0);

    // Perform a load to DMem when a load instruction is executed
    assign proc_read_enable = (proc2Dctrl_command == BUS_LOAD);
    assign Dctrl2proc_data  = Dcache2Dctrl_data;
    assign Dctrl2proc_valid = Dcache_read_hit;
    assign Dcache_read_hit  = Dcache_proc_hit & proc_read_enable;
    // assign load_stall       = reject_D_req | (proc_read_enable & ~Dcache_read_hit);

    // Perform a store from processor to DCache when a store instruction is executed
    assign proc_write_enable = (proc2Dctrl_command == BUS_STORE);
    assign Dcache_write_hit  = Dcache_proc_hit & proc_write_enable;
    // assign store_stall       = reject_D_req | (proc_write_enable & ~Dcache_write_hit);
    
    // assign mem_busy = load_stall | store_stall;
    assign mem_busy   = reject_D_req | (proc_read_enable & ~Dcache_read_hit) | (proc_write_enable & ~Dcache_write_hit);
    assign cache_busy = reject_D_req | (proc_read_enable & ~Dcache_read_hit) |  proc_write_enable; // stall loads in place in EX if there is a load miss or an active store

    assign mem_write_enable = (current_mem_tag == Dmem2Dctrl_tag) &
                              (current_mem_tag != 0) &
                              ~Dcache_hit &
                              ~changed_addr;
    
    assign mem_write_addr   = current_addr;

    // Check if a processor read / write resulted in a hit
    assign Dcache_hit       = Dcache_read_hit | Dcache_write_hit;

    // when send_request = 1, load value from memory
    assign Dctrl2Dmem_addr    = {proc2Dctrl_addr[`XLEN-1:3], 3'b0};
    assign Dctrl2Dmem_command = send_request ? BUS_LOAD : BUS_NONE;

    /*
    // non-blocking stuff
    
    always_comb begin

        store_map_next = store_map;

        // write cache block from memory if the tag entry is valid
        mem_write_enable = store_map[Dmem2Dctrl_tag].valid;
        mem_write_addr = store_map[Dmem2Dctrl_tag].addr;
        
        // reset valid to 0 since the tag has been used
        store_map_next[Dmem2Dctrl_tag].valid = 0;
        
        // wait for a response and add it to the map table
        if (send_request & (mem_response != 0)) begin
            store_map_next[mem_response].valid = 1;
            store_map_next[mem_response].addr = current_addr;
        end
    end
    */

    // synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            last_addr <= `SD -1;
            current_mem_tag  <= `SD 0;
            miss_outstanding <= `SD 0;
        end else begin
            last_addr        <= `SD current_addr;
            miss_outstanding <= `SD unanswered_miss;
            last_proc2Dctrl_command <= `SD proc2Dctrl_command;
            if(update_mem_tag)
                current_mem_tag <= `SD mem_response;
        end
    end

endmodule

`endif

    /*  How cache miss is handled: TLDR - we need to implement a stall in the fetch module
        
        On Cycle N:
        1. new address changes tag and/or index
        2. changed_addr = 1
        3. send_request = 0
        4. Ictrl2Imem_command = BUS_NONE
        5. tag and index, in parallel, are sent to cachemem
        6. cachemem reports a MISS, so Ictrl_valid_out = 0
        7. unanswered_miss = 1

        On Cycle N+1:
        1. miss_outstanding = 1 after `SD
        2. If index and tag both don't change, changed_addr = 0
        3. send_request = 1

        A cache miss incurs a 1 cycle delay between registering a miss and
        sending request to fetch from memory. This can happen if the address
        does not change between cycles N and N+1. For Icache scenario, this
        means Fetch stage must stall on a Icache miss.

        If the address does change between cycles N and N+1, then repeat
        steps from cycle N section (treat cycle N+1 as you would cycle N)

    */

