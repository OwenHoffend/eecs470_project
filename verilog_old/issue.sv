`ifndef __ISSUE_SV__
`define __ISSUE_SV__

`timescale 1ns/100ps

`include "./headers/include.svh"
`include "./verilog/RS.sv"
`include "./verilog/regfile.sv"

module issue(
    input clock,
    input reset,

    input DISPATCH_PACKET  dispatch_in,
    input CDB_PACKET cdb_in,

    input BRANCH_MASK branch_tag_in,

    input SQ_IDX      sq_onc,  //Store queue oldest non-complete
    input SQ_IDX      sq_head, //Head pointer of the store queue
    input load_busy,

    output IS_PACKET issue_out,
    output rs_full, rs_available, 
    
    //Retire reg read (architectural read)
    input [$clog2(`PHYS_REGFILE_SIZE)-1:0] retire_idx,
    output logic [`XLEN-1:0] retire_data, 
    output RS_DEBUG_PACKET rs_debug
    
    `ifdef DEBUG_MODE
        , output REG_DEBUG_PACKET reg_debug
    `endif
);

RS_PACKET rs_packet_out;
logic regf_wr_en;
logic [`XLEN-1:0] reg_write_data;

//Copied from p3 code -- need to change
regfile regf_0 (
    .rda_idx(issue_out.rs.d.T1),
    .rda_out(issue_out.rs1_value), 

    .rdb_idx(issue_out.rs.d.T2),
    .rdb_out(issue_out.rs2_value),

    .wr_clk(clock),
    .wr_en(regf_wr_en),
    .wr_idx(cdb_in.cdb_tag),
    .wr_data(reg_write_data),  // <------------------ NEEDS NEW CDB INPUT

    //Retire reg read
    .retire_idx(retire_idx),
    .retire_data(retire_data),
    `ifdef DEBUG_MODE
        .reg_debug(reg_debug)
    `endif
);

RS rs0 (
    .clock(clock),
    .reset(reset),
    .load_busy(load_busy),

    .dispatch_in(dispatch_in),
    .cdb_in(cdb_in),

    .sq_onc(sq_onc),
    .sq_head(sq_head),

    .rs_out(rs_packet_out),
    .full(rs_full),
    .available(rs_available)  
`ifdef DEBUG_MODE
    , .rs_debug(rs_debug)
`endif
);

always_comb begin
    regf_wr_en = cdb_in.valid & cdb_in.T_used & 
                (cdb_in.cdb_tag != 0); // don't write to the zero register
    issue_out.valid = rs_packet_out.valid;
    issue_out.rs = rs_packet_out.rs;
    reg_write_data = (cdb_in.uncond_branch) ? cdb_in.NPC : cdb_in.head_data; // <------------------ NEEDS NEW CDB INPUT
end
endmodule

`endif
