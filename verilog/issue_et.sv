`ifndef __ISSUE_ET_SV__
`define __ISSUE_ET_SV__

`timescale 1ns/100ps

`include "./headers/include.svh"
`include "./verilog/RS_ET.sv"
`include "./verilog/regfile_et.sv"

module issue_et(
    input clock,
    input reset,

    input DISPATCH_PACKET  dispatch_in,
    input CDB_PACKET cdb_in,

    input BRANCH_MASK branch_tag_in,
    input PHYS_REG_TAG early_mult_tag,

    input SQ_IDX      sq_onc,  //Store queue oldest non-complete
    input SQ_IDX      sq_head, //Head pointer of the store queue
    input             sq_available,
    input             sq_full,
    input             sq_all_complete,
    input cdb_stall, mem_busy,

    output IS_PACKET am_issue_out, ls_issue_out,
    output rs_full, rs_available, 
    
    //Retire reg read (architectural read)
    input [$clog2(`PHYS_REGFILE_SIZE)-1:0] retire_idx,
    output logic [`XLEN-1:0] retire_data

    
`ifdef DEBUG_MODE
    , 
    output RS_DEBUG_PACKET rs_debug,
    output REG_DEBUG_PACKET reg_debug
`endif
);

RS_PACKET am_rs_packet_out, ls_rs_packet_out;
logic regf_wr_en, alu_busy, mult_can_issue, early_tag_valid;
PHYS_REG_TAG early_tag, early_alu_tag;
logic [`XLEN-1:0] reg_write_data;
`ifdef DEBUG_MODE
logic tag_conflict;
`endif

regfile_et regf_et_0 (
    // alu/mult reg read
    .rda1_idx(am_rs_packet_out.rs.d.T1),
    .rda1_out(am_issue_out.rs1_value), 

    .rdb1_idx(am_rs_packet_out.rs.d.T2),
    .rdb1_out(am_issue_out.rs2_value),

    // load     reg read
    .rda2_idx(ls_rs_packet_out.rs.d.T1),
    .rda2_out(ls_issue_out.rs1_value), 

    .rdb2_idx(ls_rs_packet_out.rs.d.T2),
    .rdb2_out(ls_issue_out.rs2_value),

    // cdb_in writeback
    .wr_clk(clock),
    .wr_en(regf_wr_en),
    .wr_idx(cdb_in.cdb_tag),
    .wr_data(reg_write_data),

    //Retire reg read
    .retire_idx(retire_idx),
    .retire_data(retire_data)
    `ifdef DEBUG_MODE
        , .reg_debug(reg_debug)
    `endif
);

RS_ET rs_et0 (
    .clock(clock),
    .reset(reset),

    .dispatch_in(dispatch_in),
    .cdb_in(cdb_in),

    .sq_onc(sq_onc),
    .sq_head(sq_head),
    .sq_full(sq_full),
    .sq_available(sq_available),
    .sq_all_complete(sq_all_complete),

    .cdb_stall(cdb_stall),
    .mem_busy(mem_busy),

    .early_tag(early_tag),
    .early_tag_valid(early_tag_valid),
    .alu_busy(alu_busy),

    .am_rs_out(am_rs_packet_out),
    .ls_rs_out(ls_rs_packet_out),

    .full(rs_full),
    .available(rs_available)  
`ifdef DEBUG_MODE
    , .rs_debug(rs_debug)
`endif
);

always_comb begin
    
    regf_wr_en = cdb_in.valid & cdb_in.T_used & 
                (cdb_in.cdb_tag != 0); // don't write to the zero register

    am_issue_out.valid = am_rs_packet_out.valid;
    am_issue_out.rs    = am_rs_packet_out.rs;

    ls_issue_out.valid = ls_rs_packet_out.valid;
    ls_issue_out.rs    = ls_rs_packet_out.rs;

    reg_write_data = (cdb_in.uncond_branch) ? cdb_in.NPC : cdb_in.head_data;

    early_alu_tag = (am_rs_packet_out.valid & ~am_rs_packet_out.rs.d.mult) ? am_rs_packet_out.rs.d.T : 0; // assign alu tag to 0 if the issue isn't an alu
    `ifdef DEBUG_MODE
    tag_conflict = 0;
    `ifdef EARLY_TAG_BROADCAST
    if (early_alu_tag != 0 && early_mult_tag != 0) begin
       //$display("ERROR: conflicting early tags");
       tag_conflict = 1;
    end
    `endif
    `endif
    alu_busy = (early_mult_tag != 0);

    //$display("mult_tag:%h alu_tag:%h", early_mult_tag, early_alu_tag);
    
    early_tag = early_alu_tag | early_mult_tag;
    early_tag_valid = (early_tag != 0);
end

`ifdef DEBUG_MODE
//synopsys sync_set_reset "reset"
always_ff @(posedge clock) begin
    if (tag_conflict) begin
        $display("ERROR: tag conflict occurred");
        $finish;
    end
end
`endif 

endmodule

`endif
