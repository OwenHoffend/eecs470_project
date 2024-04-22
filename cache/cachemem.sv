`ifndef _D_CACHEMEM__
`define _D_CACHEMEM__

`include "./headers/include.svh"
`include "./cache/replacement_policy.sv"

`timescale 1ns/100ps

module cachemem(
    input clock, 
    input reset, 

    // Processor port in - processor read or write
    input MEM_ADDR           proc_addr_m,
    input                    proc_read_en,
    input                    proc_write_en,
    input [`XLEN-1:0]        proc_write_data,
    input SIGNED_MEM_SIZE    proc_size,

    // Memory write port - memory write
    input MEM_ADDR           mem_write_addr_m,
    input                    mem_write_en,
    input  [63:0]            mem_write_data,
  
    // Processor port out  
    output logic [63:0]      proc_data,  // Needs to be 64 bits for Icache to return results to fetch
    output logic             proc_valid, // Read OR Write hit

    // Eviction port out
    output logic             evict,       // Is data evicted on this clock cycle?
    output logic [63:0]      evict_data,  // What needs to be written to memory
    output logic [`XLEN-1:0] evict_addr,  // Where does it need to be written

    // Cache output port
    output CACHE             cache_debug

`ifdef DEBUG_MODE
    ,
    output CACHE_ADDR        cache_proc_addr_debug,
    output logic             cache_proc_read_debug,
    output logic             cache_proc_write_debug,
    output SIGNED_MEM_SIZE   cache_proc_size_debug,
    output logic             cache_proc_valid_debug // hit
`endif // endif DEBUG_MODE
);
    CACHE cache, cache_next;
    CACHE_ADDR proc_addr_c;
    CACHE_ADDR mem_write_addr_c;
    EXAMPLE_CACHE_BLOCK proc_data_unsigned;

    // Must buffer eviction signals by one clock cycle so they are seen by memory on the negative edge following a cache eviction
    logic             evict_buffer;
    logic [63:0]      evict_data_buffer;
    logic [`XLEN-1:0] evict_addr_buffer;

    // CAMs for finding tags in sets; replacement policy logic
`ifdef SASSOC_CACHE_MODE
    CACHE_WAY_IDX [`NUM_SETS-1:0] proc_way_arr;      // From CAMs
    logic         [`NUM_SETS-1:0] proc_valids_arr;   // From CAMs
    CACHE_WAY_IDX [`NUM_SETS-1:0] mem_write_way_arr; // From replacement policies

    // Random number generators for NMRU / RAND
`ifdef NMRU_REPLACEMENT
    logic [3:0] LFSR_rand;

    generate
        if(`NUM_WAYS > 2)  begin
            LFSR #(
                .NUM_BITS($clog2(`NUM_WAYS)) // Random betwixt 1 and `NUM_WAYS - 1
            ) SASSOC_LFSR (
                .clock(clock),
                .reset(reset),
                .enable(1'b1),
                .LFSR(LFSR_rand)
            );
        end
    endgenerate
`endif // endif NMRU_REPLACEMENT
`ifdef RAND_REPLACEMENT
`ifdef LESS_PSEUDORAND_LFSR
    logic [4:0] LFSR_rand;
    LFSR #(
        .NUM_BITS(5)
    ) SASSOC_LFSR (
        .clock(clock),
        .reset(reset),
        
        // Input
        .enable(1'b1),
        
        // Output
        .LFSR(LFSR_rand)
    );
`endif // endif LESS_PSEUDORAD_LFSR
`ifndef LESS_PSEUDORAND_LFSR
    logic [$clog2(`NUM_WAYS):0] LFSR_rand;
    LFSR #(
        .NUM_BITS($clog2(`NUM_WAYS)+1)
    ) SASSOC_LFSR (
        .clock(clock),
        .reset(reset),
        
        // Input
        .enable(1'b1),
        
        // Output
        .LFSR(LFSR_rand)
    );
`endif // endif LESS_PSUEDORAND_LFSR
    assign mem_write_addr_c.way = LFSR_rand[$clog2(`NUM_WAYS)-1:0];
`endif // endif RAND_REPLACEMENT

    genvar i;
    generate
        for(i = 0; i < `NUM_SETS; i++) begin
            // CAMs for finding data tag and calculating cache misses
            CAM #(
                .ARRAY_SIZE(`NUM_WAYS),
                .DATA_SIZE(13-$clog2(`NUM_SETS))
            ) SASSOC_tag_CAM (
                // Inputs
                .enable      ((proc_read_en | proc_write_en) & (proc_addr_m.idx == i)),
                .array       (cache[i].set_tags   ), // tags for a given set
                .array_valid (cache[i].set_valids ), // valids for a given set
                .read_data   (proc_addr_m.tag     ), // Find proc addr tag in set

                // Outputs
                .read_idx    (proc_way_arr[i]     ), // Save way information
                .hit         (proc_valids_arr[i]  )  // Save hit information
            );

`ifdef LRU_REPLACEMENT
            // LRU for evicting cache lines
            LRU #(
                .ARRAY_SIZE(`NUM_WAYS)
            ) SASSOC_LRU (
                .clock(clock),
                .reset(reset),

                // Inputs
                .proc_valid      (proc_valid & (proc_addr_m.idx == i)       ),
                .proc_way        (proc_way_arr[i]                           ),
                .mem_write_valid (mem_write_en & (mem_write_addr_m.idx == i)),

                // Outputs
                .mem_write_way   (mem_write_way_arr[i]                      )
`ifdef DEBUG_MODE
                ,
                .cache_uses_debug (cache_debug[i].set_uses)
`endif // endif DEBUG_MODE
            );
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
            // NMRU for evicting cache lines
            NMRU #(
                .ARRAY_SIZE(`NUM_WAYS)
            ) SASSOC_NMRU (
                .clock(clock),
                .reset(reset),

                // Inputs
                .proc_valid  (proc_valid & (proc_addr_m.idx == i)       ),
                .proc_way    (proc_way_arr[i]                           ),
                .LFSR_in     (LFSR_rand                                 ),
                .write_valid (mem_write_en & (mem_write_addr_m.idx == i)),

                // Outputs
                .NMRU_idx    (mem_write_way_arr[i]                      )    
`ifdef DEBUG_MODE
                ,
                .MRU_idx     (cache_debug[i].MRU_idx)
`endif // endif DEBUG_MODE
            );
`endif // endif NMRU_REPLACEMENT
        end
    endgenerate
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
    // CAM for finding data tag and calculating cache misses
    CAM #(
        .ARRAY_SIZE(16),
        .DATA_SIZE(13)
    ) FASSOC_tag_CAM (
        // Inputs
        .enable      (proc_read_en | proc_write_en),
        .array       (cache.set_tags  ),
        .array_valid (cache.set_valids),
        .read_data   (proc_addr_m.tag ),

        // Outputs
        .read_idx    (proc_addr_c.way ),
        .hit         (proc_valid      )
    );
`ifdef LRU_REPLACEMENT
    // LRU for evicting cache lines
    LRU #(
        .ARRAY_SIZE(16)
    ) FASSOC_LRU (
        .clock       (clock),
        .reset       (reset),

        // Inputs
        .proc_valid      (proc_valid          ),
        .proc_way        (proc_addr_c.way     ),
        .mem_write_valid (mem_write_en        ),

        // Outputs
        .mem_write_way   (mem_write_addr_c.way)
`ifdef DEBUG_MODE
        ,
        .cache_uses_debug (cache_debug.set_uses)
`endif // endif DEBUG_MODE
    );
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
    logic [3:0] LFSR_rand;

    LFSR #(
        .NUM_BITS(4) // Random betwixt 1 and 15
    ) FASSOC_LFSR (
        .clock(clock),
        .reset(reset),

        // Input
        .enable(1'b1),

        // Output
        .LFSR(LFSR_rand)
    );

    NMRU #(
        .ARRAY_SIZE(16)
    ) FASSOC_NMRU (
        .clock(clock),
        .reset(reset),

        // Inputs
        .proc_valid  (proc_valid          ),
        .proc_way    (proc_addr_c.way     ),
        .LFSR_in     (LFSR_rand           ),
        .write_valid (mem_write_en        ),

        // Outputs
        .NMRU_idx    (mem_write_addr_c.way)

`ifdef DEBUG_MODE
        ,
        .MRU_idx     (cache_debug.MRU_idx)
`endif // endif DEBUG_MODE
    );

`endif // endif NMRU_REPLACEMENT
`ifdef RAND_REPLACEMENT
    logic [4:0] LFSR_rand;
    LFSR #(
        .NUM_BITS(5)
    ) FASSOC_LFSR (
        .clock(clock),
        .reset(reset),
        
        // Input
        .enable(1'b1),
        
        // Output
        .LFSR(LFSR_rand)
    );

    assign mem_write_addr_c.way = LFSR_rand[$clog2(`NUM_WAYS)-1:0];
`endif // endif RAND_REPLACEMENT
`endif // endif FASSOC_CACHE_MODE

    always_comb begin
        cache_next = cache;

        // Compute proc / mem_write addresses
`ifdef DMAP_CACHE_MODE
        proc_addr_c.idx      = proc_addr_m.idx;
        mem_write_addr_c.idx = mem_write_addr_m.idx;
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
        // Get ways and valid bits from appropriate CAMs / LRUs
        proc_addr_c.idx      = proc_addr_m.idx;
        proc_addr_c.way      = proc_way_arr[proc_addr_m.idx];
        mem_write_addr_c.idx = mem_write_addr_m.idx;
`ifdef LRU_REPLACEMENT
        mem_write_addr_c.way = mem_write_way_arr[mem_write_addr_m.idx];
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
        mem_write_addr_c.way = mem_write_way_arr[mem_write_addr_m.idx];
`endif // endif NMRU_REPLACEMENT
`endif // endif SASSOC_CACHE_MODE

        // Processor read port
`ifdef DMAP_CACHE_MODE
        proc_data_unsigned = cache[proc_addr_c].set_data;
        proc_valid = cache[proc_addr_c].set_valids & 
                     (cache[proc_addr_c].set_tags == proc_addr_m.tag) & 
                     (proc_read_en | proc_write_en);
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
        proc_data_unsigned = cache[proc_addr_c.idx].set_data[proc_addr_c.way];
        proc_valid = proc_valids_arr[proc_addr_m.idx];
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
        proc_data_unsigned = cache.set_data[proc_addr_c];
`endif // endif FASSOC_CACHE_MODE
        // Get requested byte / half / word / double of data, sign extend
        if(~proc_size.sign) begin // 0 -> signed
            case(proc_size.size)
                BYTE:   proc_data = { {56{proc_data_unsigned[ 7]}}, proc_data_unsigned.byte_level[proc_addr_m.bo     ]};
                HALF:   proc_data = { {48{proc_data_unsigned[15]}}, proc_data_unsigned.half_level[proc_addr_m.bo[2:1]]};
                WORD:   proc_data = { {32{proc_data_unsigned[31]}}, proc_data_unsigned.word_level[proc_addr_m.bo[2  ]]};
                DOUBLE: proc_data = {                               proc_data_unsigned                                };
            endcase
        end else begin // 1 -> unsigned
            case(proc_size.size)
                BYTE:   proc_data = { 56'h0, proc_data_unsigned.byte_level[proc_addr_m.bo     ]};
                HALF:   proc_data = { 48'h0, proc_data_unsigned.half_level[proc_addr_m.bo[2:1]]};
                WORD:   proc_data = { 32'h0, proc_data_unsigned.word_level[proc_addr_m.bo[2  ]]};
                DOUBLE: proc_data = {        proc_data_unsigned                                };
            endcase
        end

        // Processor Write port
        if(proc_write_en & proc_valid) begin
`ifdef DMAP_CACHE_MODE
            case(proc_size.size)
                BYTE:    cache_next[proc_addr_c].set_data.byte_level[proc_addr_m.bo     ] = proc_write_data[ 7:0];
                HALF:    cache_next[proc_addr_c].set_data.half_level[proc_addr_m.bo[2:1]] = proc_write_data[15:0];
                WORD:    cache_next[proc_addr_c].set_data.word_level[proc_addr_m.bo[2  ]] = proc_write_data[31:0];
                default: cache_next[proc_addr_c].set_data.word_level[proc_addr_m.bo[2  ]] = proc_write_data[31:0];
            endcase
            cache_next[proc_addr_c].set_dirty = 1'b1;
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
            case(proc_size.size)
                BYTE:    cache_next[proc_addr_c.idx].set_data[proc_addr_c.way].byte_level[proc_addr_m.bo     ] = proc_write_data[ 7:0];
                HALF:    cache_next[proc_addr_c.idx].set_data[proc_addr_c.way].half_level[proc_addr_m.bo[2:1]] = proc_write_data[15:0];
                WORD:    cache_next[proc_addr_c.idx].set_data[proc_addr_c.way].word_level[proc_addr_m.bo[2  ]] = proc_write_data[31:0];
                default: cache_next[proc_addr_c.idx].set_data[proc_addr_c.way].word_level[proc_addr_m.bo[2  ]] = proc_write_data[31:0];
            endcase
            cache_next[proc_addr_c.idx].set_dirty[proc_addr_c.way] = 1'b1;
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
            case(proc_size.size)
                BYTE:    cache_next.set_data[proc_addr_c].byte_level[proc_addr_m.bo     ] = proc_write_data[ 7:0];
                HALF:    cache_next.set_data[proc_addr_c].half_level[proc_addr_m.bo[2:1]] = proc_write_data[15:0];
                WORD:    cache_next.set_data[proc_addr_c].word_level[proc_addr_m.bo[2  ]] = proc_write_data[31:0];
                default: cache_next.set_data[proc_addr_c].word_level[proc_addr_m.bo[2  ]] = proc_write_data[31:0];
            endcase
            cache_next.set_dirty[proc_addr_c] = 1'b1;
`endif // endif FASSOC_CACHE_MODE
        end

        // Memory Write port
        if(mem_write_en) begin
`ifdef DMAP_CACHE_MODE
            cache_next[mem_write_addr_c].set_valids = 1'b1;
            cache_next[mem_write_addr_c].set_tags   = mem_write_addr_m.tag;
            cache_next[mem_write_addr_c].set_data   = mem_write_data;
            cache_next[mem_write_addr_c].set_dirty  = 1'b0;
`endif // DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
            cache_next[mem_write_addr_c.idx].set_valids[mem_write_addr_c.way] = 1'b1;
            cache_next[mem_write_addr_c.idx].set_tags[  mem_write_addr_c.way] = mem_write_addr_m.tag;
            cache_next[mem_write_addr_c.idx].set_data[  mem_write_addr_c.way] = mem_write_data;
            cache_next[mem_write_addr_c.idx].set_dirty[ mem_write_addr_c.way] = 1'b0;
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
            cache_next.set_valids[mem_write_addr_c] = 1'b1;
            cache_next.set_tags[  mem_write_addr_c] = mem_write_addr_m.tag;
            cache_next.set_data[  mem_write_addr_c] = mem_write_data;
            cache_next.set_dirty[ mem_write_addr_c] = 1'b0;
`endif // endif FASSOC_CACHE_MODE
        end

        // Detect evictions
`ifdef DMAP_CACHE_MODE
        evict_buffer      =         cache[mem_write_addr_c].set_dirty & mem_write_en;
        evict_data_buffer =         cache[mem_write_addr_c].set_data;
        evict_addr_buffer = {16'h0, cache[mem_write_addr_c].set_tags, mem_write_addr_c.idx, 3'b0};
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
        evict_buffer      =         cache[mem_write_addr_c.idx].set_dirty[mem_write_addr_c.way] & mem_write_en;
        evict_data_buffer =         cache[mem_write_addr_c.idx].set_data[ mem_write_addr_c.way];
        evict_addr_buffer = {16'h0, cache[mem_write_addr_c.idx].set_tags[ mem_write_addr_c.way], mem_write_addr_c.idx, 3'b0};
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
        evict_buffer      =         cache.set_dirty[mem_write_addr_c] & mem_write_en;
        evict_data_buffer =         cache.set_data[ mem_write_addr_c];
        evict_addr_buffer = {16'h0, cache.set_tags[ mem_write_addr_c], 3'b0};
`endif // endif FASSOC_CACHE_MODE

        // Cache data output
`ifdef DMAP_CACHE_MODE
        cache_debug = cache;
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
        for(int i = 0; i < `NUM_SETS; i++) begin
            cache_debug[i].set_valids = cache[i].set_valids;
            cache_debug[i].set_tags   = cache[i].set_tags;
            cache_debug[i].set_data   = cache[i].set_data;
            cache_debug[i].set_dirty  = cache[i].set_dirty;
        end
        
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
        cache_debug.set_valids = cache.set_valids;
        cache_debug.set_tags   = cache.set_tags;
        cache_debug.set_data   = cache.set_data;
        cache_debug.set_dirty  = cache.set_dirty;
`endif // endif FASSOC_CACHE_MODE

        // Debug outputs
`ifdef DEBUG_MODE
        cache_proc_addr_debug  = proc_addr_c;
        cache_proc_read_debug  = proc_read_en;
        cache_proc_write_debug = proc_write_en;
        cache_proc_size_debug  = proc_size;
        cache_proc_valid_debug = proc_valid;
`endif // endif DEBUG_MODE
    end

    // Latch logic
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            cache <= `SD 0;
            evict <= `SD 0;
            evict_data <= `SD 0;
            evict_addr <= `SD 0;
        end else begin
            cache <= `SD cache_next;
            evict <= `SD evict_buffer;
            evict_data <= `SD evict_data_buffer;
            evict_addr <= `SD evict_addr_buffer;
        end
    end

endmodule

`endif