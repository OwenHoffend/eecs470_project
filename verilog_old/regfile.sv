/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  regfile.v                                           //
//                                                                     //
//  Description :  This module creates the Regfile used by the ID and  // 
//                 WB Stages of the Pipeline.                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __REGFILE_V__
`define __REGFILE_V__
`timescale 1ns/100ps
`include "./headers/include.svh"
module regfile(
        input  [$clog2(`PHYS_REGFILE_SIZE)-1:0] rda_idx, rdb_idx, wr_idx,    // read/write index
        input  [`XLEN-1:0] wr_data,            // write data
        input [$clog2(`PHYS_REGFILE_SIZE)-1:0] retire_idx,
        input         wr_en, wr_clk,

        output logic [`XLEN-1:0] rda_out, rdb_out,    // read data
        output logic [`XLEN-1:0] retire_data
    `ifdef DEBUG_MODE
        , output REG_DEBUG_PACKET reg_debug
    `endif
);
  
  logic    [`PHYS_REGFILE_SIZE-1:0] [`XLEN-1:0] registers;   // 32, 64-bit Registers

  wire   [`XLEN-1:0] rda_reg = registers[rda_idx];
  wire   [`XLEN-1:0] rdb_reg = registers[rdb_idx];
  `ifdef DEBUG_MODE
  wire   [`XLEN-1:0] retire_reg = registers[retire_idx];
  `endif

  //
  // Read port A
  //
  always_comb begin
    if (rda_idx == `ZERO_REG)
      rda_out = 0;
    else if (wr_en && (wr_idx == rda_idx))
      rda_out = wr_data;  // internal forwarding
    else
      rda_out = rda_reg;
  end

  //
  // Read port B
  //
  always_comb begin
    if (rdb_idx == `ZERO_REG)
      rdb_out = 0;
    else if (wr_en && (wr_idx == rdb_idx))
      rdb_out = wr_data;  // internal forwarding
    else
      rdb_out = rdb_reg;
  end

  //
  // Read retire port
  //
  always_comb begin
    if (retire_idx == `ZERO_REG)
      retire_data = 0;
    else if (wr_en && (wr_idx == retire_idx))
      retire_data = wr_data;  // internal forwarding
    else
      retire_data = retire_reg;


    reg_debug.register_data = registers;
    reg_debug.rsa_idx = rda_idx;
    reg_debug.rsb_idx = rdb_idx;
    reg_debug.rda_data = rda_reg;
    reg_debug.rdb_data = rdb_reg; 
    reg_debug.write_idx = wr_idx;
    reg_debug.write_data = wr_data;
  end

  //
  // Write port
  //
  //synopsys sync_set_reset "reset"
  always_ff @(posedge wr_clk) begin
    if (wr_en) begin
      registers[wr_idx] <= `SD wr_data;
    end
  end

endmodule // regfile
`endif //__REGFILE_V__
