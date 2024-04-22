/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  sys_defs.vh                                         //
//                                                                     //
//  Description :  This file has the macro-defines for macros used in  //
//                 the pipeline design.                                //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __SYS_DEFS_VH__
`define __SYS_DEFS_VH__
/* Synthesis testing definition, used in DUT module instantiation */

`ifdef  SYNTH_TEST
`define DUT(mod) mod``_svsim
`else
`define DUT(mod) mod
`endif

//`ifndef DEBUG_MODE
//`define DEBUG_MODE
//`endif

// `define EARLY_TAG_BROADCAST
`define USE_IF_ID_REG
//`define USE_ID_IS_REG
`define USE_IS_EX_REG //PSA: Please keep this enabled -- we need it for the cdb_stall signal to work properly
//`define USE_EX_C_REG // will break early tag atm

// these are things that early tag broadcast relies on, so I'm forcing them to be enabled when early tag is
`ifdef EARLY_TAG_BROADCAST
	`ifndef USE_IS_EX_REG
	`define USE_IS_EX_REG
	`endif
	`ifdef ALLOW_MULTIPLE_CDB_ENQUEUE
	`undef ALLOW_MULTIPLE_CDB_ENQUEUE
	`endif
`else
	`ifndef ALLOW_MULTIPLE_CDB_ENQUEUE
	`define ALLOW_MULTIPLE_CDB_ENQUEUE
	`endif
`endif

//Color defines :D
`define C_BLACK  "%c[1;30m"
`define C_RED    "%c[1;31m"
`define C_GREEN  "%c[1;32m"
`define C_YELLOW "%c[1;33m"
`define C_BLUE   "%c[1;34m"
`define C_PINK   "%c[1;35m"
`define C_CYAN   "%c[1;36m"
`define C_WHITE  "%c[1;37m"
`define C_CLEAR  "%c[0m"

//////////////////////////////////////////////
// BTB defines
//////////////////////////////////////////////
`define GSHARE

//////////////////////////////////////////////
//
// Memory/testbench attribute definitions
//
//////////////////////////////////////////////
// We're supposed to have CACHE_MODE defined apparently
`define CACHE_MODE //removes the byte-level interface from the memory mode, DO NOT MODIFY!
`define NUM_MEM_TAGS           15

`define MEM_SIZE_IN_BYTES      (64*1024)
`define MEM_64BIT_LINES        (`MEM_SIZE_IN_BYTES/8)

//you can change the clock period to whatever, 10 is just fine
`define VERILOG_CLOCK_PERIOD   10.0
`define SYNTH_CLOCK_PERIOD     26.5 // Clock period for synth and memory latency

`define MEM_LATENCY_IN_CYCLES (100.0/`SYNTH_CLOCK_PERIOD+0.49999) //0
// the 0.49999 is to force ceiling(100/period).  The default behavior for
// float to integer conversion is rounding to nearest

//////////////////////////////////////////////
// Cache defines
//////////////////////////////////////////////

// Associativies:
// Only one of these should be defined
`define DMAP_CACHE_MODE // Direct mapped
// `define FASSOC_CACHE_MODE // Fully associative
// `define SASSOC_CACHE_MODE // Set associative

// Replacement Policies:
// Only one of these should be defined (None need to be defined for DMAP_CACHE_MODE)
// `define LRU_REPLACEMENT
// `define NMRU_REPLACEMENT
// `define RAND_REPLACEMENT

// this allows for better "random" distribution but with more bits (5)
// `define LESS_PSEUDORAND_LFSR // should be defined only if RAND_REPLACEMENT is defined

typedef union packed {
    logic [7:0][7:0]  byte_level;
    logic [3:0][15:0] half_level;
    logic [1:0][31:0] word_level;
} EXAMPLE_CACHE_BLOCK;

typedef logic [2:0] CACHE_BO; // Block offset

`ifdef DMAP_CACHE_MODE
    `define NUM_SETS 16
    `define NUM_WAYS 1
    typedef logic [8:0] CACHE_TAG;     // Tag into cache
    typedef logic [3:0] CACHE_SET_IDX; // Index to a set in the cache

    typedef struct packed {
        CACHE_TAG     tag;
        CACHE_SET_IDX idx;
        CACHE_BO      bo;
    } MEM_ADDR;

    typedef struct packed {
        CACHE_SET_IDX idx;
    } CACHE_ADDR;

    typedef struct packed {
        logic        set_valids;
        CACHE_TAG    set_tags;
        EXAMPLE_CACHE_BLOCK  set_data;
        logic        set_dirty;
    } CACHE_SET;
    typedef CACHE_SET [15:0] CACHE;
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
    `define NUM_SETS 4 // CHANGE THIS TO CHANGE SET ASSOCIATIVITY
    `define NUM_WAYS (16 / `NUM_SETS)
    typedef logic [12-$clog2(`NUM_SETS):0] CACHE_TAG;     // Tag into cache
    typedef logic [$clog2(`NUM_SETS)-1:0]  CACHE_SET_IDX; // Index to a set in the cache
    typedef logic [$clog2(`NUM_WAYS)-1:0]  CACHE_WAY_IDX; // Index to a way in a set

    typedef struct packed {
        CACHE_TAG     tag;
        CACHE_SET_IDX idx;
        CACHE_BO      bo;
    } MEM_ADDR;

    typedef struct packed {
        CACHE_SET_IDX idx;
        CACHE_WAY_IDX way;
    } CACHE_ADDR;

    typedef struct packed {
        logic         [`NUM_WAYS-1:0] set_valids;
        CACHE_TAG     [`NUM_WAYS-1:0] set_tags;
        EXAMPLE_CACHE_BLOCK   [`NUM_WAYS-1:0] set_data;
        logic         [`NUM_WAYS-1:0] set_dirty;
`ifdef DEBUG_MODE
`ifdef LRU_REPLACEMENT
        CACHE_WAY_IDX [`NUM_WAYS-1:0] set_uses;
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
        CACHE_WAY_IDX        MRU_idx;
`endif // endif NMRU_REPLACEMENT
`endif // endif DEBUG_MODE
    } CACHE_SET;
    typedef CACHE_SET [`NUM_SETS-1:0] CACHE;
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
    `define NUM_SETS 1
    `define NUM_WAYS 16
    typedef logic [12:0] CACHE_TAG;     // Tag into cache
    typedef logic [3:0]  CACHE_WAY_IDX; // Index to a way in a set

    typedef struct packed {
        CACHE_TAG tag;
        CACHE_BO  bo;
    } MEM_ADDR; // memory address

    typedef struct packed {
        CACHE_WAY_IDX way;
    } CACHE_ADDR; // cache address

    typedef struct packed {
        logic         [15:0] set_valids;
        CACHE_TAG     [15:0] set_tags;
        EXAMPLE_CACHE_BLOCK   [15:0] set_data;
        logic         [15:0] set_dirty;
`ifdef DEBUG_MODE
`ifdef LRU_REPLACEMENT
        CACHE_WAY_IDX [15:0] set_uses;
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
        CACHE_WAY_IDX        MRU_idx;
`endif // endif NMRU_REPLACEMENT
`endif // endif DEBUG_MODE
    } CACHE_SET;
    typedef CACHE_SET CACHE;
`endif // endif FASSOC_CACHE_MODE

typedef struct packed {
    logic       valid;
    MEM_ADDR     addr;
} STORE_MAP_ENTRY;

//////////////////////////////////////////////
// Begin our defined code here
//////////////////////////////////////////////

`define ARCH_REGFILE_SIZE 32
`define ROB_SIZE 32
`define FREELIST_SIZE (`ROB_SIZE)
`define PHYS_REGFILE_SIZE (`ARCH_REGFILE_SIZE + `ROB_SIZE)
`define BS_SIZE 8 //Branch stack size (lol)
`define RS_SIZE 32
`define CDB_SIZE `ROB_SIZE
`define SQ_SIZE 8 //Store queue size
`define XLEN 32
`define DATALEN `XLEN
`define MAX_BRANCH_MASK (1 << `BS_SIZE-1)

typedef logic [$clog2(`ROB_SIZE)-1:0]          ROB_IDX;		    // Pointer within the ROB
typedef logic [$clog2(`FREELIST_SIZE)-1:0]	   FREELIST_IDX;	// Pointer within the Free List
typedef logic [$clog2(`PHYS_REGFILE_SIZE)-1:0] PHYS_REG_TAG;	// Pointer to a physical register
typedef logic [$clog2(`ARCH_REGFILE_SIZE)-1:0] ARCH_REG_TAG;	// Pointer to an architectural register, used by the ROB
typedef logic [$clog2(`RS_SIZE)-1:0]           RS_IDX;
typedef logic [$clog2(`CDB_SIZE)-1:0]		   CDB_IDX;
typedef logic [$clog2(`SQ_SIZE)-1:0]           SQ_IDX;
typedef logic [`BS_SIZE-1:0]                   BRANCH_MASK;

typedef struct {
	PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat;
	logic        [`ARCH_REGFILE_SIZE-1:0] ready;
} MAP_TABLE;

typedef struct {
	PHYS_REG_TAG [`FREELIST_SIZE-1:0] freelist;	
	FREELIST_IDX                      head_ptr;	
	FREELIST_IDX                      tail_ptr;
	logic 		                      available;		
} FREELIST_QUEUE;

//////////////////////////////////////////////
// Exception codes
// This mostly follows the RISC-V Privileged spec
// except a few add-ons for our infrastructure
// The majority of them won't be used, but it's
// good to know what they are
//////////////////////////////////////////////

typedef enum logic [3:0] {
	INST_ADDR_MISALIGN  = 4'h0,
	INST_ACCESS_FAULT   = 4'h1,
	ILLEGAL_INST        = 4'h2,
	BREAKPOINT          = 4'h3,
	LOAD_ADDR_MISALIGN  = 4'h4,
	LOAD_ACCESS_FAULT   = 4'h5,
	STORE_ADDR_MISALIGN = 4'h6,
	STORE_ACCESS_FAULT  = 4'h7,
	ECALL_U_MODE        = 4'h8,
	ECALL_S_MODE        = 4'h9,
	NO_ERROR            = 4'ha, //a reserved code that we modified for our purpose
	ECALL_M_MODE        = 4'hb,
	INST_PAGE_FAULT     = 4'hc,
	LOAD_PAGE_FAULT     = 4'hd,
	HALTED_ON_WFI       = 4'he, //another reserved code that we used
	STORE_PAGE_FAULT    = 4'hf
} EXCEPTION_CODE;

//////////////////////////////////////////////
//
// Assorted things it is not wise to change
//
//////////////////////////////////////////////

//
// actually, you might have to change this if you change VERILOG_CLOCK_PERIOD
// JK you don't ^^^
//
`define SD #1


// the RISCV register file zero register, any read of this register always
// returns a zero value, and any write to this register is thrown away
//
`define ZERO_REG 5'd0

//
// Memory bus commands control signals
//
typedef enum logic [1:0] {
	BUS_NONE     = 2'h0,
	BUS_LOAD     = 2'h1,
	BUS_STORE    = 2'h2
} BUS_COMMAND;

typedef enum logic [1:0] {
	BYTE = 2'h0,
	HALF = 2'h1,
	WORD = 2'h2,
	DOUBLE = 2'h3
} MEM_SIZE;

typedef struct packed {
    logic    sign; // 0 -> signed, 1 -> unsigned
    MEM_SIZE size;
} SIGNED_MEM_SIZE;

// `endif
//
// useful boolean single-bit definitions
//
`define FALSE  1'h0
`define TRUE  1'h1

// RISCV ISA SPEC

typedef union packed {
	logic [31:0] inst;
	struct packed {
		logic [6:0] funct7;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} r; //register to register instructions
	struct packed {
		logic [11:0] imm;
		logic [4:0]  rs1; //base
		logic [2:0]  funct3;
		logic [4:0]  rd;  //dest
		logic [6:0]  opcode;
	} i; //immediate or load instructions
	struct packed {
		logic [6:0] off; //offset[11:5] for calculating address
		logic [4:0] rs2; //source
		logic [4:0] rs1; //base
		logic [2:0] funct3;
		logic [4:0] set; //offset[4:0] for calculating address
		logic [6:0] opcode;
	} s; //store instructions
	struct packed {
		logic       of; //offset[12]
		logic [5:0] s;   //offset[10:5]
		logic [4:0] rs2;//source 2
		logic [4:0] rs1;//source 1
		logic [2:0] funct3;
		logic [3:0] et; //offset[4:1]
		logic       f;  //offset[11]
		logic [6:0] opcode;
	} b; //branch instructions
	struct packed {
		logic [19:0] imm;
		logic [4:0]  rd;
		logic [6:0]  opcode;
	} u; //upper immediate instructions
	struct packed {
		logic       of; //offset[20]
		logic [9:0] et; //offset[10:1]
		logic       s;  //offset[11]
		logic [7:0] f;	//offset[19:12]
		logic [4:0] rd; //dest
		logic [6:0] opcode;
	} j;  //jump instructions
`ifdef ATOMIC_EXT
	struct packed {
		logic [4:0] funct5;
		logic       aq;
		logic       rl;
		logic [4:0] rs2;
		logic [4:0] rs1;
		logic [2:0] funct3;
		logic [4:0] rd;
		logic [6:0] opcode;
	} a; //atomic instructions
`endif
`ifdef SYSTEM_EXT
	struct packed {
		logic [11:0] csr;
		logic [4:0]  rs1;
		logic [2:0]  funct3;
		logic [4:0]  rd;
		logic [6:0]  opcode;
	} sys; //system call instructions
`endif

} INST; //instruction typedef, this should cover all types of instructions

//
// Basic NOP instruction.  Allows pipline registers to clearly be reset with
// an instruction that does nothing instead of Zero which is really an ADDI x0, x0, 0
//
`define NOP 32'h00000013

//////////////////////////////////////////////
//
// Complete Packets:
// Data that is exchanged from EX to C stage
//
//////////////////////////////////////////////

typedef struct packed {
    logic [`XLEN-1:0] head_data; //Head of CDB FIFO data

    //Tags
    PHYS_REG_TAG cdb_tag;      //Head of CDB FIFO tag
    ARCH_REG_TAG cdb_arch_tag; //Head of CDB FIFO arch tag
	logic T_used;
    ROB_IDX      rob_idx;      //Squash index in the ROB
    PHYS_REG_TAG next_cdb_tag; //Early tag broadcast tag
    
    //SQ signals
    SQ_IDX       sq_idx;       //SQ index for stores and squashing
    logic        is_store;

    //Branching
	logic	     squash_enable;
`ifdef GSHARE
	logic 		actual_taken;
`endif
	logic		 uncond_branch;
	BRANCH_MASK	 branch_tag;
    BRANCH_MASK  branch_mask;
	logic [`XLEN-1:0] NPC;

    //Status bits
    logic        full;
	logic        valid;

} CDB_PACKET;

typedef enum logic [1:0] {
	NONE,
	JUMPING,
	WALKING,
	RANDOM
} ROTATION_TYPE;

`endif // __SYS_DEFS_VH__
