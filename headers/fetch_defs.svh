`ifndef __FETCH_DEFS_VH__
`define __FETCH_DEFS_VH__

`include "./headers/include.svh"

`ifndef INST_BUFF_SIZE
`define INST_BUFF_SIZE 64

`endif

`ifndef GHB_SIZE
`define GHB_SIZE 4
`endif

`ifndef SATURATION_BITS
`define	SATURATION_BITS 2
`endif

//////////////////////////////////////////////
// BTB defines
//////////////////////////////////////////////
// direct-mapped BTB
`define BTB_UNUSED_BITS 20
`define NUM_BTB_ENTRIES 32

`define BTB_IDX_BITS $clog2(`NUM_BTB_ENTRIES)
`define BTB_TAG_BITS 32-2-`BTB_UNUSED_BITS-`BTB_IDX_BITS
typedef logic [`BTB_IDX_BITS-1:0] 				BTB_IDX;     // Index to a set in the cache
typedef logic [`BTB_TAG_BITS-1:0] 				BTB_TAG;     // Tag into BTB
typedef logic [`BTB_IDX_BITS+`BTB_TAG_BITS-1:0] BTB_DATA;    // BTB data

//////////////////////////////////////////////
//
// IF Packets:
// Data that is exchanged from IF to ID stage
//
//////////////////////////////////////////////
`ifdef GSHARE
typedef struct packed {
	// Branch Prediction data
	logic [`XLEN-1:0] fetch_NPC_target;
	logic BTB_taken;	
	logic [`GHB_SIZE-1:0] ghbr;
	logic is_branch;
} BP_PACKET;
`endif
typedef struct packed {
	logic valid; // If low, the data in this struct is garbage
    INST  inst;  // fetched instruction out
	logic [`XLEN-1:0] NPC; // PC + 4
	logic [`XLEN-1:0] PC;  // PC
`ifdef GSHARE	
	// Branch Prediction data
	BP_PACKET BP;
`endif
 
} FETCH_PACKET;

`endif
