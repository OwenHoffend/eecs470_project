`ifndef _CACHE__
`define _CACHE__
`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./cache/cachemem.sv"
`include "./cache/icache.sv"
`include "./cache/dcache.sv"

module cache (
    input clock,
    input reset,

    /* Memory inputs */
    input  [3:0]             mem2cache_response,
    input [63:0]             mem2cache_data,
    input  [3:0]             mem2cache_tag,

    /* I-cache inputs */
    input [`XLEN-1:0]        proc2Icache_addr, // BUS_LOAD, UNSIGNED DOUBLE
    
    /* D-Cache inputs */ 
    input [`XLEN-1:0]        proc2Dcache_addr,
    input BUS_COMMAND        proc2Dcache_command, // BUS_NONE, BUS_LOAD, BUS_STORE
    input [`XLEN-1:0]        proc2Dcache_data, 
    input SIGNED_MEM_SIZE    proc2Dcache_size, // WORD, HALF, BYTE

    /* Memory outputs */
    output logic [`XLEN-1:0] cache2mem_addr,
    output BUS_COMMAND       cache2mem_command, // BUS_NONE, BUS_LOAD, BUS_STORE
    output logic      [63:0] cache2mem_data,

    /* I-cache outputs */
    output logic      [63:0] Icache2proc_data,
    output logic             Icache2proc_valid, // Cache hit/miss

    /* D-cache outputs */
    output logic [`XLEN-1:0] Dcache2proc_data,
    output logic             Dcache2proc_valid, // Cache hit/miss

    /* Stall signals to LQ / SQ */
    output logic             mem_busy,
    output logic             cache_busy,

    /* DCache contents, needed by pipeline_tb to evict dirty cache lines at WFI */
    output CACHE             Dcache

`ifdef DEBUG_MODE
    ,
    output CACHE           Icache_debug,
    output CACHE_ADDR      Icache_proc_addr_debug,
    output logic           Icache_proc_valid_debug,
    
    output CACHE_ADDR      Dcache_proc_addr_debug,
    output logic           Dcache_proc_read_debug,
    output logic           Dcache_proc_write_debug,
    output SIGNED_MEM_SIZE Dcache_proc_write_size_debug,
    output logic           Dcache_proc_valid_debug
`endif
);
    // I-cache internal signals
    logic [63:0]      Icache2Ictrl_data; // to processor (64 bits default)
    logic             Icache2Ictrl_valid;
    MEM_ADDR          Ictrl2Icache_addr;
    logic             Ictrl2Icache_mem_write_en;
    BUS_COMMAND       Ictrl2Imem_command;
    logic [`XLEN-1:0] Ictrl2Imem_addr;
    
    // D-cache internal signals
    logic [`XLEN-1:0] Dcache2Dctrl_data_upper; // unused
    logic [`XLEN-1:0] Dcache2Dctrl_data;  // to processor (32 bits maximum)
    logic             Dcache2Dctrl_proc_valid;
    BUS_COMMAND       Dctrl2Dmem_command;
    logic [`XLEN-1:0] Dctrl2Dmem_addr;
    logic             Dctrl2Dcache_mem_write_en;
    logic             Dctrl2Dcache_write_en;
    logic             Dctrl2Dcache_read_en;
    MEM_ADDR          Dctrl2Dcache_addr;
    MEM_ADDR          Dctrl2Dcache_mem_write_addr;
    // MEM_ADDR          Dmem2Dcache_addr;

    // Eviction signals
    logic             Dcache_evict;
    logic [63:0]      Dcache_evict_data;  // to memory
    logic [`XLEN-1:0] Dcache_evict_addr;

    // Rejection signals (AKA my senior prom)
    logic             reject_I_req;
    logic             reject_D_req;      

    /////////////////////////////////////////////////
    //          ARBITER (WORT WORT WORT)           //
    /////////////////////////////////////////////////

    always_comb begin
        // Evictions > Dcache > Icache    
        if(Dcache_evict) begin
            cache2mem_addr    = Dcache_evict_addr;
            cache2mem_command = BUS_STORE;
            cache2mem_data    = Dcache_evict_data;
        end else if (Dctrl2Dmem_command != BUS_NONE) begin
            cache2mem_addr    = Dctrl2Dmem_addr;
            cache2mem_command = Dctrl2Dmem_command;
            cache2mem_data    = 0;
        end else begin
            cache2mem_addr    = Ictrl2Imem_addr;
            cache2mem_command = Ictrl2Imem_command;
            cache2mem_data    = 0;
        end

        reject_I_req = (Ictrl2Imem_command != BUS_NONE) & (Dcache_evict | (Dctrl2Dmem_command != BUS_NONE));
        reject_D_req = (Dctrl2Dmem_command != BUS_NONE) & (Dcache_evict);
    end
    
    /////////////////////////////////////////////////
    //                    ICACHE                   //
    /////////////////////////////////////////////////

    // Instruction cache controller
    icache icache_ctrl(
        .clock(clock),
        .reset(reset),

        /* Inputs */
        // Memory returns instructions requested by cache
        // Dcache tells Icache ctrl to stall it's request so Dcache requests can occur
        .Imem2Ictrl_response      (mem2cache_response),
        .Imem2Ictrl_tag           (mem2cache_tag     ),
        .reject_I_req             (reject_I_req      ),

        // Fetch tells Icache ctrl which address to retrieve
        .proc2Ictrl_addr          (proc2Icache_addr),

        // Icache Memory tells ctrl if read was a hit / read data
        .Icache2Ictrl_data        (Icache2Ictrl_data ),
        .Icache2Ictrl_valid       (Icache2Ictrl_valid),
        
        /* Outputs */
        // Icache ctrl tells memory what data to retrieve
        .Ictrl2Imem_command       (Ictrl2Imem_command),
        .Ictrl2Imem_addr          (Ictrl2Imem_addr   ),

        // Icache ctrl returns results to fetch
        .Ictrl2proc_data          (Icache2proc_data ),
        .Ictrl2proc_valid         (Icache2proc_valid),

        // Icache ctrl tells Icache mem what data to read or write
        .current_addr             (Ictrl2Icache_addr        ),
        .Ictrl2Icache_mem_write_en(Ictrl2Icache_mem_write_en)
    );

    // Instruction cache memory
    cachemem icachemem(
        .clock(clock),
        .reset(reset),

        // Processor port in - ICacheCtrl tells ICacheMem what data to read
        .proc_addr_m      (Ictrl2Icache_addr),
        .proc_read_en     (1'b1             ),
        .proc_write_en    (1'b0             ),
        .proc_write_data  (32'b0            ),
        .proc_size        ({1'b1, DOUBLE}   ), // UNSIGNED DOUBLE

        // Memory write port - IMem tells ICacheMem what data to load into cache
        .mem_write_addr_m (Ictrl2Icache_addr        ),
        .mem_write_en     (Ictrl2Icache_mem_write_en),
        .mem_write_data   (mem2cache_data           ),

        // Processor port out - ICacheMem tells ICacheCtrl what data it read
        .proc_data        (Icache2Ictrl_data ), 
        .proc_valid       (Icache2Ictrl_valid)

        // Debug outputs
`ifdef DEBUG_MODE
        ,
        .cache_debug            (Icache_debug           ),
        .cache_proc_addr_debug  (Icache_proc_addr_debug ),
        .cache_proc_valid_debug (Icache_proc_valid_debug)
`endif
    );

    /////////////////////////////////////////////////
    //               DCACHE                        //
    /////////////////////////////////////////////////

    // Data cache controller
    dcache dcache_ctrl(
        .clock(clock),
        .reset(reset),

        /* Inputs */
        // From Mem
        .Dmem2Dctrl_response (mem2cache_response),
        .Dmem2Dctrl_tag      (mem2cache_tag     ),
        .reject_D_req        (reject_D_req      ),

        // From LSQ
        .proc2Dctrl_addr     (proc2Dcache_addr   ),
        .proc2Dctrl_command  (proc2Dcache_command),

        // From Dcache - hit status
        .Dcache2Dctrl_data   (Dcache2Dctrl_data),
        .Dcache_proc_hit     (Dcache2Dctrl_proc_valid),

        /* Outputs */
        // To Memory
        .Dctrl2Dmem_command  (Dctrl2Dmem_command),
        .Dctrl2Dmem_addr     (Dctrl2Dmem_addr   ),
        
        // To LSQ
        .Dctrl2proc_data     (Dcache2proc_data ),
        .Dctrl2proc_valid    (Dcache2proc_valid),
        .mem_busy            (mem_busy         ),
        .cache_busy          (cache_busy       ),
        
        // To Dcache
        .mem_write_enable    (Dctrl2Dcache_mem_write_en),
        .mem_write_addr      (Dctrl2Dcache_mem_write_addr),

        .proc_write_enable   (Dctrl2Dcache_write_en    ),
        .proc_read_enable    (Dctrl2Dcache_read_en     ),
        .current_addr        (Dctrl2Dcache_addr        )
    );

    // Data cache memory
    cachemem dcachemem(
        .clock(clock),
        .reset(reset),

        // Processor port in - DCacheCtrl tells DCacheMem what data to read / write
        .proc_addr_m      (Dctrl2Dcache_addr    ),
        .proc_read_en     (Dctrl2Dcache_read_en ),
        .proc_write_en    (Dctrl2Dcache_write_en),
        .proc_write_data  (proc2Dcache_data     ),
        .proc_size        (proc2Dcache_size     ),

        // Memory write port - DMem tells DCacheMem what data to load into cache
        .mem_write_addr_m (Dctrl2Dcache_mem_write_addr),
        .mem_write_en     (Dctrl2Dcache_mem_write_en  ),
        .mem_write_data   (mem2cache_data             ),

        // Processor port out - DCacheMem tells DCacheCtrl what data it read
        .proc_data        ({Dcache2Dctrl_data_upper, Dcache2Dctrl_data}), 
        .proc_valid       (Dcache2Dctrl_proc_valid),

        // Eviction port out - DCacheMem tells DMem what data it needs to store
        .evict            (Dcache_evict     ),
        .evict_data       (Dcache_evict_data), 
        .evict_addr       (Dcache_evict_addr),

        // Cache contents port
        .cache_debug      (Dcache)

        // Debug outputs
`ifdef DEBUG_MODE
        ,
        .cache_proc_addr_debug  (Dcache_proc_addr_debug      ),
        .cache_proc_read_debug  (Dcache_proc_read_debug      ),
        .cache_proc_write_debug (Dcache_proc_write_debug     ),
        .cache_proc_size_debug  (Dcache_proc_write_size_debug),
        .cache_proc_valid_debug (Dcache_proc_valid_debug     )
`endif
    );

endmodule

`endif