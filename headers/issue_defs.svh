`ifndef __ISSUE_DEFS_VH__
`define __ISSUE_DEFS_VH__
//////////////////////////////////////////////
//
// Issue Packets:
// Data used by the issue stage
//
//////////////////////////////////////////////

typedef struct packed {
    DISPATCH_PACKET d;
	BRANCH_MASK branch_tag;
	logic T1_early;
    logic T2_early;
} RS_ENTRY;

typedef struct packed {
	RS_ENTRY rs;
	logic valid;
} RS_PACKET;

typedef struct packed {
	RS_ENTRY rs;
	logic valid;
	logic [`DATALEN-1:0] rs1_value, rs2_value;
} IS_PACKET;

typedef struct packed {
	logic valid;
	PHYS_REG_TAG tag;
	BRANCH_MASK branch_tag;
} TAG_BUFFER_ENTRY;

typedef struct packed {
	logic [$clog2(`RS_SIZE):0] num_entries_actual;
	logic [`RS_SIZE-1:0] can_issue;
	logic valid_issue_out;
	logic valid_ls_issue_out;
	RS_IDX ls_rs_issue_idx_out;
	RS_IDX rs_issue_idx_out;
	RS_IDX rs_input_idx_out;
	RS_ENTRY [`RS_SIZE-1:0] rs_entries, next_rs_entries;
} RS_DEBUG_PACKET;

typedef struct packed {
	logic [`PHYS_REGFILE_SIZE-1:0] [`XLEN-1:0] register_data;
    PHYS_REG_TAG rsa_idx, rsb_idx, write_idx;
    logic [`XLEN-1:0] write_data;
    logic [`XLEN-1:0] rda_data, rdb_data;
} REG_DEBUG_PACKET;

`endif