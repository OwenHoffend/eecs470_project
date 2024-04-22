`include "./headers/include.svh"
//////////////////////////////////////////////
//
// 	Pipeline Register Packets
//
//////////////////////////////////////////////

typedef struct packed {
	FETCH_PACKET fetch;
} IF_ID_PACKET;

typedef struct packed {
	DISPATCH_PACKET disp;
	ROB_PACKET rob;
	//BRANCH_MASK 	br_tag;
} ID_IS_PACKET;

typedef struct packed {
	IS_PACKET 	am, ls;
} IS_EX_PACKET;

typedef struct packed {
	EX_PACKET mul_packet;
	EX_PACKET load_packet;
	EX_PACKET alu_packet;
} EX_C_PACKET;
