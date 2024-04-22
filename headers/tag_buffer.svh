`ifndef _TAG_BUFFER_H_
`define _TAG_BUFFER_H_

typedef struct packed {
    logic valid;                // is there actually something at this entry?
    PHYS_REG_TAG T;             // issued tag
    logic T_used;               // branches and stuff still go on the CDB
    BRANCH_MASK branch_mask;    // enables squashes

} TAG_BUFFER_ENTRY;

`endif