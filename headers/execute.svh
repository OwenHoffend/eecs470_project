`ifndef __EXECUTE_VH__
`define __EXECUTE_VH__

`define NUM_MULT_STAGES 4
`define MULT_BLOCK_SIZE (64 / `NUM_MULT_STAGES)

//Select between upper and lower bits of mult result
typedef enum logic [1:0] {
    MULT_NONE  = 2'h0,
    MULT_LOW   = 2'h1,
    MULT_HIGH  = 2'h2
} MULT_HL;

//
// ALU function code input
// probably want to leave these alone
//
typedef enum logic [4:0] {
	ALU_ADD     = 5'h00,
	ALU_SUB     = 5'h01,
	ALU_SLT     = 5'h02,
	ALU_SLTU    = 5'h03,
	ALU_AND     = 5'h04,
	ALU_OR      = 5'h05,
	ALU_XOR     = 5'h06,
	ALU_SLL     = 5'h07,
	ALU_SRL     = 5'h08,
	ALU_SRA     = 5'h09,
	ALU_MUL     = 5'h0a,
	ALU_MULH    = 5'h0b,
	ALU_MULHSU  = 5'h0c,
	ALU_MULHU   = 5'h0d,
	ALU_DIV     = 5'h0e,
	ALU_DIVU    = 5'h0f,
	ALU_REM     = 5'h10,
	ALU_REMU    = 5'h11
} ALU_FUNC;

//////////////////////////////////////////////
//
// Datapath control signals
//
//////////////////////////////////////////////

//
// ALU opA input mux selects
//
typedef enum logic [1:0] {
	OPA_IS_RS1  = 2'h0,
	OPA_IS_NPC  = 2'h1,
	OPA_IS_PC   = 2'h2,
	OPA_IS_ZERO = 2'h3
} ALU_OPA_SELECT;

//
// ALU opB input mux selects
//
typedef enum logic [3:0] {
	OPB_IS_RS2    = 4'h0,
	OPB_IS_I_IMM  = 4'h1,
	OPB_IS_S_IMM  = 4'h2,
	OPB_IS_B_IMM  = 4'h3,
	OPB_IS_U_IMM  = 4'h4,
	OPB_IS_J_IMM  = 4'h5
} ALU_OPB_SELECT;

 `ifdef GSHARE
typedef struct packed {
    logic [`XLEN-1:0] PC;
    logic [`XLEN-1:0] target_PC;
    logic [`GHB_SIZE-1:0] ghbr;
    logic             BTB_update;
    logic             branch;
    logic             cond_branch;
    logic             cond_taken;
    logic             valid;
} EX_BP_PACKET;
`endif

typedef struct packed {
	logic [`XLEN-1:0] data;		    // determined in EX
	
	//Tags
	PHYS_REG_TAG tag;				// determined in dispatch
    ARCH_REG_TAG arch_tag;          // determined in dispatch
	logic T_used;
    ROB_IDX      rob_idx;			// determined in dispatch
    SQ_IDX       sq_idx;            // determined in dispatch
    logic        is_store;

	//Branching
    logic [`XLEN-1:0] NPC;             // PC + 4, used as writeback for jal and jalr
    logic 		      squash_enable;   // determined in EX
    logic             uncond_branch;   // Supports jal and jalr
    BRANCH_MASK       branch_mask;     // the mask being broadcasted
	BRANCH_MASK       branch_tag;	   // tag indicated dependencies on prior branches
`ifdef GSHARE
	// EX to BP data
    EX_BP_PACKET ex_bp;	
`endif
	//Status bits
	logic        valid;				// is this entry valid?
`ifdef GSHARE
	logic actual_taken;
`endif
} EX_PACKET;

typedef struct packed {
    logic [`XLEN-1:0] address;
    logic [`XLEN-1:0] value;
    SQ_IDX            idx;
    SIGNED_MEM_SIZE   mem_size;
    logic             st_valid;
    logic             ld_valid;
    `ifdef DEBUG_MODE
        INST inst; // instruction
    `endif
} SQ_PACKET;

typedef struct packed {
    logic [`XLEN-1:0] sq_address;
    logic [`XLEN-1:0] sq_value;
    logic [`XLEN-1:0] fwd_value;
    logic [3:0] fwd_mask;

    SIGNED_MEM_SIZE   mem_size;
    SQ_IDX            sq_idx;
    logic             complete;
    `ifdef DEBUG_MODE
        INST inst; // instruction
    `endif
} SQ_ENTRY;

`ifdef DEBUG_MODE
typedef struct packed {
    logic available;
    logic full;
    logic valid_store;
    logic dcache_stall;
    SQ_PACKET ex_to_sq;
    SQ_IDX head_ptr_out;
    SQ_IDX tail_ptr_out;
    SQ_IDX sq_onc;
    SQ_ENTRY [`SQ_SIZE-1:0] SQ_FIFO;
    logic rob2sq_retire_en;
    logic sq2load_frwd_valid;
    logic [`XLEN-1:0] sq2load_frwd_value;
    logic [$clog2(`SQ_SIZE)-1:0] ld_fwd_hit;
} SQ_DEBUG_PACKET;
`endif

`endif
