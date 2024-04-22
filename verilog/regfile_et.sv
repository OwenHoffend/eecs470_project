/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  regfile.v                                           //
//                                                                     //
//  Description :  This module creates the Regfile used by the ID and  // 
//                 WB Stages of the Pipeline.                          //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __REGFILE_ET_V__
`define __REGFILE_ET_V__
`timescale 1ns/100ps
`include "./headers/include.svh"
module regfile_et(
        input  [$clog2(`PHYS_REGFILE_SIZE)-1:0] rda1_idx, rdb1_idx, wr_idx,    // read/write index
                                                rda2_idx, rdb2_idx,
        input  [`XLEN-1:0] wr_data,            // write data
        input [$clog2(`PHYS_REGFILE_SIZE)-1:0] retire_idx,
        input         wr_en, wr_clk,

        output logic [`XLEN-1:0] rda1_out, rdb1_out,    // read data
                                 rda2_out, rdb2_out,

        output logic [`XLEN-1:0] retire_data
    `ifdef DEBUG_MODE
        ,output REG_DEBUG_PACKET reg_debug
    `endif
);
  
  logic    [`PHYS_REGFILE_SIZE-1:0] [`XLEN-1:0] registers;   // 32, 64-bit Registers

  wire   [`XLEN-1:0] rda1_reg = registers[rda1_idx];
  wire   [`XLEN-1:0] rdb1_reg = registers[rdb1_idx];
  wire   [`XLEN-1:0] rda2_reg = registers[rda2_idx];
  wire   [`XLEN-1:0] rdb2_reg = registers[rdb2_idx];

//  `ifdef DEBUG_MODE
  wire   [`XLEN-1:0] retire_reg = registers[retire_idx];
//  `endif
    // `ifndef DEBUG_MODE
        // REG_DEBUG_PACKET reg_debug;
    // `endif
  // -------------------------------------------------------------
  //
  // Read port A1
  //
  always_comb begin
    if (rda1_idx == `ZERO_REG)
      rda1_out = 0;
    else if (wr_en && (wr_idx == rda1_idx))
      rda1_out = wr_data;  // internal forwarding
    else
      rda1_out = rda1_reg;
  end

  //
  // Read port B1
  //
  always_comb begin
    if (rdb1_idx == `ZERO_REG)
      rdb1_out = 0;
    else if (wr_en && (wr_idx == rdb1_idx))
      rdb1_out = wr_data;  // internal forwarding
    else
      rdb1_out = rdb1_reg;
  end

  // -------------------------------------------------------------
  //
  // Read port A2
  //
  always_comb begin
    if (rda2_idx == `ZERO_REG)
      rda2_out = 0;
    else if (wr_en && (wr_idx == rda2_idx))
      rda2_out = wr_data;  // internal forwarding
    else
      rda2_out = rda2_reg;
  end

  //
  // Read port B2
  //
  always_comb begin
    if (rdb2_idx == `ZERO_REG)
      rdb2_out = 0;
    else if (wr_en && (wr_idx == rdb2_idx))
      rdb2_out = wr_data;  // internal forwarding
    else
      rdb2_out = rdb2_reg;
  end

  // -------------------------------------------------------------
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

  `ifdef DEBUG_MODE
    reg_debug.register_data = registers;
    reg_debug.rsa_idx = rda1_idx;
    reg_debug.rsb_idx = rdb1_idx;
    reg_debug.rda_data = rda1_reg;
    reg_debug.rdb_data = rdb1_reg; 
    reg_debug.write_idx = wr_idx;
    reg_debug.write_data = wr_data;
  `endif
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
