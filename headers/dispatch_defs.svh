`ifndef __DISPATCH_DEFS_VH__
`define __DISPATCH_DEFS_VH__

//////////////////////////////////////////////
//
// Datapath control signals
//
//////////////////////////////////////////////

// Destination register select
typedef enum logic [1:0] {
	DEST_RD = 2'h0,
	DEST_NONE  = 2'h1
} DEST_REG_SEL;

//////////////////////////////////////////////
//
// ID Packets:
// Data that is exchanged from ID to EX stage
//
//////////////////////////////////////////////

typedef struct packed {
	logic [`XLEN-1:0] NPC;     // PC + 4
    logic [`XLEN-1:0] PC;      // PC

`ifdef GSHARE   
    // Branch Prediction data
    BP_PACKET BP;
`endif
 
    ROB_IDX rob_idx;           //Entry in the ROB that will be retired once this instr completes
    SQ_IDX  sq_idx;            //Youngest entry in the SQ that this instr corresponds to
    /*
    For loads, sq_idx holds the SQ tail pointer allocated at dispatch. 
    For stores, sq_idx holds the SQ writeback index, where EX will put the data and addr
    For branches, sq_idx holds the SQ squash index
    Loads/stores are mutually exclusive, so we use the same data slot for both.
    Dispatch packet d contains rd_mem, which will be used to determine if
    the sq_idx should be considered when determining if this entry can be issued.
    */

    //Output
    PHYS_REG_TAG T;            //T for tag from free list used in retire
    logic T_used;
    ARCH_REG_TAG dest_reg;     // destination (writeback) register index      

    //T1 - First input
    PHYS_REG_TAG T1;
	logic T1r; 				   	// does Tag 1 have zero dependencies? if this is true, T1 is good to issue
                                // TODO: This is functionally equivalent to opa_select
    logic T1_used;

    BRANCH_MASK branch_mask;   //For branch instructions only
	BRANCH_MASK branch_tag;
    
    //T2 - Second input
    PHYS_REG_TAG T2;
    logic T2_used;
    logic T2r; 				   	// does Tag 2 have zero dependencies? if this is true, T1 is good to issue
                                // TODO: This is functionally equivalent to opb_select
    
    //Decoded instruction information (Carried over from p3)
    INST inst;                 //The instruction itself
    DEST_REG_SEL   dst_select;
	ALU_OPA_SELECT opa_select; // ALU opa mux select (ALU_OPA_xxx *)
	ALU_OPB_SELECT opb_select; // ALU opb mux select (ALU_OPB_xxx *)
	ALU_FUNC     alu_func;     // ALU function select (ALU_xxx *)
	// logic		 mult;		   // is inst a multiply?
	logic        rd_mem;       // does inst read memory?
	logic        wr_mem;       // does inst write memory?
	logic        cond_branch;  // is inst a conditional branch?
    logic        uncond_branch;// is inst an unconditional branch?
    logic        mult;         // is this a multiply?
	logic        halt;         // is this a halt?
	logic        illegal;      // is this instruction illegal?
	logic        csr_op;       // is this a CSR operation? (we only used this as a cheap way to get return code)
	logic        valid;        // is inst a valid instruction to be counted for CPI calculations?
} DISPATCH_PACKET;

//Old p3 ID_EX packet def for legacy support. Please don't remove this, a testbench uses it
typedef struct packed {
	logic [`XLEN-1:0] NPC;   // PC + 4
	logic [`XLEN-1:0] PC;    // PC

	logic [`XLEN-1:0] rs1_value;    // reg A value                                  
	logic [`XLEN-1:0] rs2_value;    // reg B value                                  
	                                                                                
	ALU_OPA_SELECT opa_select; // ALU opa mux select (ALU_OPA_xxx *)
	ALU_OPB_SELECT opb_select; // ALU opb mux select (ALU_OPB_xxx *)
    INST inst;                 // instruction
	
	logic [4:0] dest_reg_idx;  // destination (writeback) register index      
	ALU_FUNC    alu_func;      // ALU function select (ALU_xxx *)
	logic       rd_mem;        // does inst read memory?
	logic       wr_mem;        // does inst write memory?
	logic       cond_branch;   // is inst a conditional branch?
	logic       uncond_branch; // is inst an unconditional branch?
	logic       halt;          // is this a halt?
	logic       illegal;       // is this instruction illegal?
	logic       csr_op;        // is this a CSR operation? (we only used this as a cheap way to get return code)
	logic       valid;         // is inst a valid instruction to be counted for CPI calculations?
} ID_EX_PACKET;

typedef struct packed {
    logic [`XLEN-1:0] dispatch_NPC; 
    logic T_used; 
    PHYS_REG_TAG T;              //T for tag from free list used in retire
    PHYS_REG_TAG Told;           //Told for free list
    ARCH_REG_TAG dest_reg;       //Dest reg for indexing the arch map table
`ifdef DEBUG_MODE
    INST inst;
    BRANCH_MASK  branch_mask;
    BRANCH_MASK  branch_tag;
`endif
    logic        is_store;       // Is this entry a store instruction?
	logic 		 halt;		     //Is the incoming dispatch a halt instruction?
    logic        valid;          //Valid dispatch
} ROB_PACKET;

typedef struct packed {
    logic [`XLEN-1:0] dispatch_NPC; 
    logic T_used; 
	PHYS_REG_TAG d_tag;             // Physical register this instruction is writing to
	PHYS_REG_TAG d_tag_old;         // Former physical register of the architectural register this instruction is writing to
	ARCH_REG_TAG d_tag_old_arch;    // Architectural register this instruction is writing to
`ifdef DEBUG_MODE
    INST inst;
    BRANCH_MASK  branch_mask;
    BRANCH_MASK  branch_tag;
`endif
    logic is_store;                 // Is this entry a store instruction?
	logic halt;					    // Is this entry a halt instruction?
	logic complete;
} ROB_ENTRY;

typedef struct packed {
    FREELIST_IDX                          freelist_head_ptr;
    PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat_value;
    logic        [`ARCH_REGFILE_SIZE-1:0] rat_ready;
} BRANCH_STACK_ENTRY;
`endif
