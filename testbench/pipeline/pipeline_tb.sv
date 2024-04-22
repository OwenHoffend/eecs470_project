/////////////////////////////////////////////////////////////////////////
//                                                                     //
//                                                                     //
//   Modulename :  testbench.v                                         //
//                                                                     //
//  Description :  Testbench module for the verisimple pipeline;       //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef _PIPELINE_TB_
`define _PIPELINE_TB_
`define TECHNICOLOR // color printouts

`timescale 1ns/100ps

`include "./headers/include.svh"
`include "./testbench/mem.sv"
/*
`include "./verilog/CDB.sv"
`include "./verilog/RAT.sv"
`include "./verilog/dispatch.sv"
`include "./verilog/EX.sv"
`include "./verilog/fetch.sv"
`include "./verilog/issue_et.sv"
`include "./verilog/ROB.sv"
`include "./verilog/BRAT.sv"


// `include "./verilog/barrel_shift.sv"
// `include "./verilog/barrel_shift_dir0.sv"
// `include "./verilog/barrel_shift_dir1.sv"
// `include "./verilog/pipeline.sv"
`include "./verilog/onehot_to_binary.sv"
`include "./verilog/LFSR.sv"
// `include "./verilog/pselect.sv"
// `include "./verilog/barrel_shift_dir0.sv"
// `include "./verilog/barrel_shift_dir1.sv"
// `include "./verilog/binary_pselect_dir0.sv"
// `include "./verilog/binary_pselect_dir1.sv"
// `include "./verilog/ps2_dir0.sv"
// `include "./verilog/ps2_dir1.sv"
// `include "./verilog/pselect_dir0.sv"
// `include "./verilog/pselect_dir1.sv"
// `include "./verilog/rot_pselect.sv"
`include "./cache/cachemem.sv"
`include "./cache/cache.sv"
`include "./cache/dcache.sv"
`include "./cache/icache.sv"
`include "./cache/replacement_policy.sv"
*/

import "DPI-C" function void print_header(string str);
import "DPI-C" function void print_cycles();
import "DPI-C" function void print_stage(string div, int inst, int npc, int valid_inst);
import "DPI-C" function void print_reg(int wb_reg_wr_data_out_hi, int wb_reg_wr_data_out_lo,
                                       int wb_reg_wr_idx_out, int wb_reg_wr_en_out);
import "DPI-C" function void print_membus(int proc2mem_command, int mem2proc_response,
                                          int proc2mem_addr_hi, int proc2mem_addr_lo,
						 			     int proc2mem_data_hi, int proc2mem_data_lo);
import "DPI-C" function void print_close();


module pipeline_tb;

	// variables used in the testbench
	logic        clock;
	logic        reset;
	logic [31:0] clock_count;
	logic [31:0] instr_count;
	int          wb_fileno;
	
	logic [1:0]  proc2mem_command;
	logic [`XLEN-1:0] proc2mem_addr;
	logic [63:0] proc2mem_data;

	logic  [3:0] mem2proc_response;
	logic [63:0] mem2proc_data;
	logic  [3:0] mem2proc_tag;
`ifndef CACHE_MODE
	MEM_SIZE     proc2mem_size;
`endif
    CACHE        Dcache;
    logic        mem_busy;
	logic  [3:0] pipeline_completed_insts;
/*	
    EXCEPTION_CODE   pipeline_error_status;
	logic  [4:0] pipeline_commit_wr_idx;
	logic [`XLEN-1:0] pipeline_commit_wr_data;
	logic        pipeline_commit_wr_en;
	logic [`XLEN-1:0]  pipeline_commit_NPC;
*/	
	EXCEPTION_CODE     pipeline_error_status;
	PHYS_REG_TAG       cdb_commit_wr_idx;
	logic [`XLEN-1:0]  cdb_commit_wr_data;
	logic              cdb_commit_wr_en;

    //Retire 
    logic             arch_wb_en;
    logic             arch_wb_used;
    ARCH_REG_TAG      retire_idx;  //Equivalent of pipeline_commit_wr_idx from p3
    logic [`XLEN-1:0] retire_data; //Equivalent of pipeline_commit_wr_data from p3
    logic [`XLEN-1:0] retire_NPC;

`ifdef DEBUG_MODE
	// controls when to print during simulation
	logic ok_to_print;
	
    // Fetch
    logic [63:0]      Icache2proc_data;
    logic             Icache2proc_valid;
	logic [`XLEN-1:0] proc2Icache_addr;

	// Branch Prediction
	logic [`GHB_SIZE-1:0] debug_ghbr, debug_n_ghbr;
	logic [2**(`GHB_SIZE)-1:0] [`SATURATION_BITS-1:0] debug_PHT, debug_next_PHT;
	logic [2**(`GHB_SIZE)-1:0]    debug_PHT_dirty_idxs;

	BTB_DATA [`NUM_BTB_ENTRIES-1:0]  debug_BTB_data;
	BTB_TAG  [`NUM_BTB_ENTRIES-1:0]  debug_BTB_tags;
	logic    [`NUM_BTB_ENTRIES-1:0]  debug_BTB_dirty_idxs;

	// ROB
	ROB_ENTRY [`ROB_SIZE-1:0] rob_debug;
	ROB_IDX rob_head;
	ROB_IDX rob_tail;
    logic ROB_full, ROB_available, ROB_retire_cond;

	// RS
	RS_DEBUG_PACKET rs_debug;
	logic RS_full, RS_available;

	// RegFile
	REG_DEBUG_PACKET  reg_debug;

	// freelist
	logic                          			freelist_full;
	logic                         			freelist_available;
	logic    [$clog2(`FREELIST_SIZE)-1:0] 	freelist_head;
	logic    [$clog2(`FREELIST_SIZE)-1:0] 	freelist_tail;
	PHYS_REG_TAG     [`FREELIST_SIZE-1:0] 	freelist_debug;

	// RAT
	PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] 	rat_debug;
	logic        [`ARCH_REGFILE_SIZE-1:0] 	rat_debug_ready;

    // BTAG TRACKER 
    BRANCH_MASK branch_mask_out;
    BRANCH_MASK branch_tag_out;
    BRANCH_MASK branch_tag_next;
    logic       bs_stall;

    // SQ
    SQ_DEBUG_PACKET sq_debug;

    // CACHE
    CACHE           Icache_debug;
    CACHE_ADDR      Icache_proc_addr_debug;
    logic           Icache_proc_valid_debug;
    CACHE_ADDR      Dcache_proc_addr_debug;
    logic           Dcache_proc_read_debug;
    logic           Dcache_proc_write_debug;
    SIGNED_MEM_SIZE Dcache_proc_write_size_debug;
    logic           Dcache_proc_valid_debug;
`endif

    // Output
	FETCH_PACKET if_packet_out;
	IF_ID_PACKET if_id_packet;
	ID_IS_PACKET id_is_packet;
	IS_EX_PACKET is_ex_packet;
	EX_C_PACKET  ex_c_packet;
	CDB_PACKET   cdb_in;
	ROB_ENTRY    ROB_head_packet_out;
	
    //counter used for when pipeline infinite loops, forces termination
    logic [63:0] debug_counter;

	// Instantiate the Pipeline
	pipeline core(
		// Inputs
		.clock             		(clock),
		.reset             		(reset),
		.mem2proc_response 		(mem2proc_response),
		.mem2proc_data     		(mem2proc_data),
		.mem2proc_tag      		(mem2proc_tag),
		
		// Outputs
		.proc2mem_command  		(proc2mem_command),
		.proc2mem_addr     		(proc2mem_addr),
		.proc2mem_data     		(proc2mem_data),
`ifndef CACHE_MODE
		.proc2mem_size     		(proc2mem_size),
`endif
        .Dcache                 (Dcache),
        .mem_busy               (mem_busy),

        //Retire
        .arch_wb_en             (arch_wb_en),
        .arch_wb_used           (arch_wb_used),
        .retire_idx             (retire_idx),
        .retire_data            (retire_data),
        .retire_NPC             (retire_NPC),

`ifdef DEBUG_MODE
        // Fetch
        .Icache2proc_data       (Icache2proc_data),
        .Icache2proc_valid      (Icache2proc_valid),
	    .proc2Icache_addr       (proc2Icache_addr),

		// Branch Prediction
        .debug_ghbr             (debug_ghbr),
        .debug_n_ghbr           (debug_n_ghbr),
        .debug_PHT              (debug_PHT),
        .debug_next_PHT         (debug_next_PHT),
		.debug_PHT_dirty_idxs   (debug_PHT_dirty_idxs),
        .debug_BTB_data         (debug_BTB_data),
        .debug_BTB_tags         (debug_BTB_tags),
		.debug_BTB_dirty_idxs   (debug_BTB_dirty_idxs),

		// ROB
		.rob_debug		     	(rob_debug),
		.rob_head			 	(rob_head),
		.rob_tail			 	(rob_tail),
		.ROB_full				(ROB_full),
		.ROB_available			(ROB_available),
        .rob_retire_cond        (ROB_retire_cond),
		
		// RS
		.rs_debug			 	(rs_debug),
		.RS_full				(RS_full),
		.RS_available			(RS_available),
		
		// RegFile
		.reg_debug			 	(reg_debug),

		// freelist
		.freelist_full  	 	(freelist_full),
		.freelist_available		(freelist_available),
		.freelist_head   		(freelist_head),
		.freelist_tail   		(freelist_tail),
		.freelist_debug	 		(freelist_debug),

		// RAT
		.rat_debug				(rat_debug),
		.rat_debug_ready		(rat_debug_ready),

        // BTAG TRACKER
        .branch_mask_out        (branch_mask_out),
        .branch_tag_out         (branch_tag_out),
        .branch_tag_next        (branch_tag_next),
        .bs_stall               (bs_stall),

        // SQ
        .sq_debug               (sq_debug),

        // CACHE
        .Icache_debug                 (Icache_debug                ),
        .Icache_proc_addr_debug       (Icache_proc_addr_debug      ),
        .Icache_proc_valid_debug      (Icache_proc_valid_debug     ),
        .Dcache_proc_addr_debug       (Dcache_proc_addr_debug      ),
        .Dcache_proc_read_debug       (Dcache_proc_read_debug      ),
        .Dcache_proc_write_debug      (Dcache_proc_write_debug     ),
        .Dcache_proc_write_size_debug (Dcache_proc_write_size_debug),
        .Dcache_proc_valid_debug      (Dcache_proc_valid_debug     ),
`endif // endif DEBUG_MODE

		.pipeline_completed_insts(pipeline_completed_insts),

		.pipeline_error_status(pipeline_error_status),
		.cdb_commit_wr_idx(cdb_commit_wr_idx),
		.cdb_commit_wr_data(cdb_commit_wr_data),
		.cdb_commit_wr_en(cdb_commit_wr_en),
		
/*
        .pipeline_commit_wr_data(pipeline_commit_wr_data),
		.pipeline_commit_wr_idx(pipeline_commit_wr_idx),
		.pipeline_commit_wr_en(pipeline_commit_wr_en),
		.pipeline_commit_NPC(pipeline_commit_NPC),
*/

		.if_packet_out(if_packet_out),		
		.if_id_packet(if_id_packet),
		.id_is_packet(id_is_packet),
		.is_ex_packet(is_ex_packet),
		.ex_c_packet(ex_c_packet),
		.cdb_in(cdb_in),
		.ROB_head_packet_out(ROB_head_packet_out)
	);
	`ifdef DEBUG_MODE
		string str_temp;
	`endif
	
	// Instantiate the Data Memory
	mem memory (
		// Inputs
		.clk               (clock),
		.proc2mem_command  (proc2mem_command),
		.proc2mem_addr     (proc2mem_addr),
		.proc2mem_data     (proc2mem_data),
`ifndef CACHE_MODE
		.proc2mem_size     (proc2mem_size),
`endif

		// Outputs
		.mem2proc_response (mem2proc_response),
		.mem2proc_data     (mem2proc_data),
		.mem2proc_tag      (mem2proc_tag)
	);
	
	// Generate System Clock
	always begin
		#(`VERILOG_CLOCK_PERIOD/2.0);
		clock = ~clock;
	end
	
	// Task to display # of elapsed clock edges
	task show_clk_count;
		real cpi;
		
		begin
			cpi = (clock_count + 1.0) / instr_count;
			$display("@@  %0d cycles / %0d instrs = %f CPI\n@@",
			          clock_count+1, instr_count, cpi);
			$display("@@  %4.2f ns total time to execute\n@@\n",
			          clock_count*`VERILOG_CLOCK_PERIOD);
		end
	endtask  // task show_clk_count 
	
	// Show contents of a range of Unified Memory, in both hex and decimal
	task show_mem_with_decimal;
		input [31:0] start_addr;
		input [31:0] end_addr;
		int showing_data;
        MEM_ADDR cache_addr;
        logic    cache_evict_hit;
		begin
            // wait(~mem_busy);
			$display("@@@");
			showing_data=0;
			for(int k=start_addr;k<=end_addr; k=k+1) begin
                // Check if data exists in D$ (writeback cache)
                cache_addr = k*8;
`ifdef DMAP_CACHE_MODE
                cache_evict_hit = (Dcache[cache_addr.idx].set_valids) &
                                  (Dcache[cache_addr.idx].set_tags == cache_addr.tag) &
                                  (Dcache[cache_addr.idx].set_dirty); // UwU ur such a dirty boy :)
                
                if(cache_evict_hit) begin
                    if((Dcache[cache_addr.idx].set_data != 0)) begin
                        $display("@@@ mem[%5d] = %x : %0d", k*8, Dcache[cache_addr.idx].set_data,
                                                                 Dcache[cache_addr.idx].set_data);
                        showing_data = 1;
                    end else if(showing_data!=0) begin
				    	$display("@@@");
				    	showing_data=0;
				    end
                end
`endif
`ifdef SASSOC_CACHE_MODE
                for(int way=0; way < `NUM_WAYS; way++) begin
                    cache_evict_hit = (Dcache[cache_addr.idx].set_valids[way]) & 
                                      (Dcache[cache_addr.idx].set_tags[way] == cache_addr.tag) &
                                      (Dcache[cache_addr.idx].set_dirty[way]);
                    if(cache_evict_hit) begin
                        if(Dcache[cache_addr.idx].set_data[way] != 0) begin
                            $display("@@@ mem[%5d] = %x : %0d", k*8, Dcache[cache_addr.idx].set_data[way],
                                                                     Dcache[cache_addr.idx].set_data[way]);
                            showing_data = 1;
                        end else if(showing_data!=0) begin
				    	    $display("@@@");
				    	    showing_data=0;
				        end
                        break;
                    end 
                end
`endif
`ifdef FASSOC_CACHE_MODE
                for(int way=0; way < `NUM_WAYS; way++) begin
                    cache_evict_hit = (Dcache.set_valids[way]) & 
                                      (Dcache.set_tags[way] == cache_addr.tag) &
                                      (Dcache.set_dirty[way]);
                    if(cache_evict_hit) begin
                        if(Dcache.set_data[way] != 0) begin
                            $display("@@@ mem[%5d] = %x : %0d", k*8, Dcache.set_data[way],
                                                                     Dcache.set_data[way]);
                            showing_data = 1;
                        end else if(showing_data!=0) begin
				        	$display("@@@");
				        	showing_data=0;
				        end
                        break;
                    end
                end
`endif
                if(~cache_evict_hit) begin
				    if (memory.unified_memory[k] != 0) begin
				    	$display("@@@ mem[%5d] = %x : %0d", k*8, memory.unified_memory[k], 
				                                                memory.unified_memory[k]);
				    	showing_data=1;
                    end else if(showing_data!=0) begin
				    	$display("@@@");
				    	showing_data=0;
				    end
                end
            end
			$display("@@@");
		end
	endtask  // task show_mem_with_decimal

`ifdef DEBUG_MODE
	
	task print_BTB;
		for (int i = 0; i < `NUM_BTB_ENTRIES; i++) begin
			if (debug_BTB_dirty_idxs[i]) begin
				$display("BTB entry %1d:  Tag: %h  Data:  %h", i, debug_BTB_data[i], debug_BTB_tags[i]);
			end
		end
	endtask

	task print_PHT_and_GHR;
		$display("Global Branch History Register: %b", debug_ghbr);
		$display("Next Global Branch History Register: %b", debug_n_ghbr);
		for (int i = 0; i < 1<<`GHB_SIZE; i++) begin
			if (debug_PHT_dirty_idxs[i]) begin
				$display("PHT entry %1d:  Counter Value: %b", i, debug_PHT[i]);
			end
		end
		for (int i = 0; i < 1<<`GHB_SIZE; i++) begin
			if (debug_PHT_dirty_idxs[i]) begin
				$display("next PHT entry %1d:  Counter Value: %b", i, debug_next_PHT[i]);
			end
		end
	endtask

    task print_basic;
		$display("cycle %1d | %1h  >  time:%4.0f:", clock_count, clock_count, $time);
		$display("mem2proc_response:  %h", mem2proc_response);
		$display("fetch_instr:	%h fetch_valid:%b", if_packet_out.inst, if_packet_out.valid);
		$display(" disp_instr:	%h  disp_valid:%b", id_is_packet.disp.inst, id_is_packet.disp.valid);
		$display("am_iss_instr: 	%h am_iss_valid:%b", is_ex_packet.am.rs.d.inst, is_ex_packet.am.valid);
		$display("                            ex_valid:%b", ex_c_packet.mul_packet.valid | ex_c_packet.alu_packet.valid | ex_c_packet.load_packet.valid);
		$display("                           cdb_valid:%b\n", cdb_in.valid);	
		$display();
	endtask // task basic_print

    task print_fetch;
        $display("cycle %1d | %1h: FETCH: Icache2proc_data: %h  Icache2proc_valid: %b  proc2Icache_addr: %h",
            clock_count, clock_count, Icache2proc_data, Icache2proc_valid, proc2Icache_addr);
        $display();
    endtask // task print_fetch

	task print_ROB;
        logic [`XLEN-1:0] rob_pc;
        string suffix = "";
		$display("cycle %1d | %1h: ROB:  ROB_head: %h  ROB_tail: %h ROB_full: %b  ROB_available: %b  ROB_retire_cond: %b", 
            clock_count, clock_count, rob_head, rob_tail, ROB_full, ROB_available, ROB_retire_cond);
		for (int i = 0; i < `ROB_SIZE; i++) begin
            rob_pc = rob_debug[i].dispatch_NPC == 0 ? 0 : rob_debug[i].dispatch_NPC-4'h4;
			if ((i >= rob_head && i < rob_tail) || ROB_full || 
				((rob_head > rob_tail) & (i < rob_tail || i >= rob_head))) begin
				if (i == rob_head)
                    suffix = "<------ HEAD ";
                else
                    suffix = "";
                $display("ROB entry: %2h PC: %h inst:%h phys_tag: %h phys_tag_old: %h arch_tag: %h halt? %b bmask:%b btag:%b complete: %b %s",
                i, rob_pc, rob_debug[i].inst, rob_debug[i].d_tag, rob_debug[i].d_tag_old, rob_debug[i].d_tag_old_arch,
                rob_debug[i].halt, rob_debug[i].branch_mask, rob_debug[i].branch_tag, rob_debug[i].complete, suffix);
			end
		end
		$display();
	endtask // task print_ROB

    task print_CDB;
        $display("cycle %1d | %1h: CDB", clock_count, clock_count);
        //Does not include all fields from the CDB packet (yet)
`ifdef TECHNICOLOR
		if (cdb_in.valid)
			$write(`C_GREEN,27); // green text
		else
			$write(`C_BLACK,27); // black text
`endif // endif TECHNICOLOR
        $display("CDB: head_data: %h cdb_tag: %h T_used: %b rob_idx: %h br_tag: %h br_mask: %h, full: %b valid: %b",
            cdb_in.head_data, cdb_in.cdb_tag, cdb_in.T_used, cdb_in.rob_idx, 
            cdb_in.branch_tag, cdb_in.branch_mask, cdb_in.full, cdb_in.valid); 
`ifdef TECHNICOLOR
		$write(`C_CLEAR,27);
`endif // endif TECHNICOLOR
        $display();
    endtask

	/*
		Displays all entries in the Reservation Station.  
		The issuing entry is green, the dispatch index is white, 
		other valid entries are green, and invalid entries are black.
	*/

    task print_RS_line(
        integer i,
        string color,
        string prefix,
        string suffix
    );
`ifdef TECHNICOLOR
        $write(color, 27);
`endif // endif TECHNICOLOR
		
		if (rs_debug.rs_entries[i].d.rd_mem)
			str_temp = "LOAD ";
		else if (rs_debug.rs_entries[i].d.wr_mem) begin
			str_temp = "STORE";
		end else if (rs_debug.rs_entries[i].d.mult) begin
			str_temp = "MULT ";
		end else
			str_temp = "ALU  ";
        $display("%s RS entry %2h: inst:%h T:%h T1:%h T1r:%h T2:%h T2r:%h can_issue:%b br_tag:%b br_mask:%b %s %s",
                prefix, i, rs_debug.rs_entries[i].d.inst, rs_debug.rs_entries[i].d.T, rs_debug.rs_entries[i].d.T1, rs_debug.rs_entries[i].d.T1r,
                rs_debug.rs_entries[i].d.T2, rs_debug.rs_entries[i].d.T2r, rs_debug.can_issue[i], rs_debug.rs_entries[i].d.branch_tag, 
                rs_debug.rs_entries[i].d.branch_mask, str_temp, suffix);
`ifdef TECHNICOLOR
		$write(`C_CLEAR,27);
`endif // endif TECHNICOLOR
    endtask

	task print_RS;
`ifdef TECHNICOLOR
		if (RS_full)
			$write(`C_BLUE,27); // blue text
`endif // endif TECHNICOLOR
		$display("cycle %1d | %1h: RS: disp_idx:%h, valid:%b issue_idx:%h, valid:%b, full:%b, available:%b", 
			clock_count,  clock_count, rs_debug.rs_input_idx_out, id_is_packet.disp.valid, rs_debug.rs_issue_idx_out, rs_debug.valid_issue_out, RS_full, RS_available);
`ifdef TECHNICOLOR
		$write(`C_CLEAR,27);
`endif // endif TECHNICOLOR
		for (int i = 0; i < `RS_SIZE; i++) begin
			if (rs_debug.rs_entries[i].d.valid && (rs_debug.rs_entries[i].branch_tag & cdb_in.branch_mask) != 0 && 
            cdb_in.squash_enable && cdb_in.valid) begin
                print_RS_line(i, `C_RED, ">", "<----- SQUASH"); // red text for squashing
			end else if (i == rs_debug.rs_issue_idx_out && rs_debug.valid_issue_out) begin // am issue
				if (rs_debug.rs_entries[i].d.valid) begin
					if (rs_debug.can_issue[i])
                        print_RS_line(i, `C_BLUE, ">", "-----> ALU/MULT ISSUE"); // blue text
					else
                        print_RS_line(i, `C_GREEN, ">", ""); // green text
				end else begin
					`ifdef VERBOSE_MODE
                        print_RS_line(i, `C_BLACK, " ", ""); // black text
					`endif
				end
			end else if (i == rs_debug.ls_rs_issue_idx_out && rs_debug.valid_ls_issue_out) begin
		        if (rs_debug.rs_entries[i].d.valid) begin
					if (rs_debug.can_issue[i])
                        print_RS_line(i, `C_BLUE, ">", "-----> LOAD/STORE ISSUE"); // blue text
					else
                        print_RS_line(i, `C_GREEN, ">", ""); // green text
				end else begin
					`ifdef VERBOSE_MODE
                        print_RS_line(i, `C_BLACK, " ", ""); // black text
					`endif
				end
			end else if (i == rs_debug.rs_input_idx_out) begin
				if (id_is_packet.disp.valid & ~rs_debug.rs_entries[i].d.valid) begin
`ifdef TECHNICOLOR
					$write(`C_WHITE, 27);
`endif // endif TECHNICOLOR
        			$display("  RS entry %2h: inst:XXXXXXXX T:XX T1:XX T1r:X T2:XX T2r:X can_issue:X br_tag:XXXX <----- DISPATCH", i);
`ifdef TECHNICOLOR
					$write(`C_CLEAR,27);
`endif // endif TECHNICOLOR
                    //print_RS_line(i, `C_WHITE, ">", "<----- DISPATCH"); // white text -- commented out because it prints bad data
				end else begin
					`ifdef VERBOSE_MODE
                        print_RS_line(i, `C_BLACK, " ", ""); // black text
					`endif
				end
			end else begin // if dispatch idx
				if (rs_debug.rs_entries[i].d.valid) begin
                    print_RS_line(i, `C_GREEN, ">", ""); // green text
				end else begin
					`ifdef VERBOSE_MODE
                        print_RS_line(i, `C_BLACK, " ", ""); // black text
					`endif
				end
			end // not dispatch or issue
		end
		$display();
	endtask

    task print_btag_tracker;
        $display("cycle %1d | %1h: BTAG_TRACKER: bmask:%b  btag:%b  btag_next:%b  bs_stall:%b",
            clock_count, clock_count, branch_mask_out, branch_tag_out, branch_tag_next, bs_stall);
    endtask

	task print_squash;
		if (cdb_in.squash_enable & cdb_in.valid) begin
`ifdef TECHNICOLOR
			$write("%c[5;31m",27); // RED BLINK
`endif
			$display("------------------------------------------------- SQUASHING MASK %b -------------------------------------------------", cdb_in.branch_mask);
`ifdef TECHNICOLOR
			$write(`C_CLEAR,27);
`endif
			$display();
		end
	endtask

	task print_regf;
		if (cdb_in.valid & cdb_in.T_used & (cdb_in.cdb_tag != 0))
			$display("cycle %1d | %1h: regfile:  wr_data:%h -----> reg%h  rda_idx:%h  rda_data:%h  rdb_idx:%h  rdb_data:%h\n", 
				clock_count, clock_count, reg_debug.write_data, reg_debug.write_idx, 
				reg_debug.rsa_idx, reg_debug.rda_data, reg_debug.rsb_idx, reg_debug.rdb_data);
		else
			$display("cycle %1d:    rda_idx:%h  rda_data:%h  rdb_idx:%h  rdb_data:%h\n", 
				clock_count, reg_debug.rsa_idx, reg_debug.rda_data, reg_debug.rsb_idx, reg_debug.rdb_data);
		for (int i = 0; i < `PHYS_REGFILE_SIZE; i++) begin
`ifdef TECHNICOLOR
			if (i == reg_debug.rsa_idx || i == reg_debug.rsb_idx) begin
				$write(`C_GREEN,27); // green text
			end else if (i == reg_debug.write_idx) begin
				$write(`C_BLUE,27); // blue text
			end else if (^reg_debug.register_data[i] === 1'bx) begin
				$write(`C_BLACK,27); // black text
			end else begin
				$write(`C_WHITE,27); // white text
			end
`endif
			if (i == 0) begin
				if (i == reg_debug.rsa_idx || i == reg_debug.rsb_idx) begin
					$display("  reg%2h: %8h -----> READ", i, 0);
				end else begin
`ifdef TECHNICOLOR
					$write(`C_BLACK,27); // black text
`endif
					$display("  reg%2h: %8h", i, 0);
				end
			end else begin
				if (i == reg_debug.rsa_idx || i == reg_debug.rsb_idx) begin
					$display("  reg%2h: %h -----> READ", i, reg_debug.register_data[i]);
				end else if (i == reg_debug.write_idx) begin
					$display("  reg%2h: %h <----- WRITE", i, reg_debug.register_data[i]);
				end else begin
					$display("  reg%2h: %h", i, reg_debug.register_data[i]);
				end
			end
`ifdef TECHNICOLOR
			$write(`C_CLEAR,27); // clear color for next entry
`endif
		end
		$display();
	endtask;

	task print_FL;
		$display("cycle %1d | %1h:  freelist_head: %h  freelist_tail: %h", clock_count, clock_count, freelist_head, freelist_tail);
		for (int i = 0; i < `FREELIST_SIZE; i++) begin
			if ((i >= freelist_head && i < freelist_tail) || (freelist_head == freelist_tail) || 
				((freelist_head > freelist_tail) & (i < freelist_tail || i >= freelist_head))) begin
				if (i == freelist_head) begin
				    $display("FreeList entry %2d:  phys_tag: %h <------ HEAD", i, freelist_debug[i]);
				end else begin
					$display("FreeList entry %2d:  phys_tag: %h", i, freelist_debug[i]);
				end
			end
		end
		$display();
	endtask;

	task print_RAT;
		$display("cycle %1d | %1h RAT Contents", clock_count, clock_count);
		for (int i = 0; i < `ARCH_REGFILE_SIZE; i++) begin
            $display("RAT entry %2d:  phys_tag: %h  ready: %b", i, rat_debug[i], rat_debug_ready[i]);
    	end
		$display();
	endtask;

    task print_Icache;
        string line_status;
        integer set, way;
        $display("cycle %1d | %1h ICache Contents", clock_count, clock_count);
        for(int i = 0; i < 16; i++) begin
            if((i == Icache_proc_addr_debug) && Icache_proc_valid_debug) begin // hit
                line_status = " <------ READ (HIT)";         
            end else if((i == Icache_proc_addr_debug) && ~Icache_proc_valid_debug) begin // or miss
                line_status = " <------ READ (MISS)";
            end else begin // i guess they never miss, huh
                line_status = "";         
            end
`ifdef DMAP_CACHE_MODE
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h%s", 
                i, i, 0, Icache_debug[i].set_valids, Icache_debug[i].set_tags, 
                {Icache_debug[i].set_tags, i[$clog2(`NUM_SETS)-1:0], 3'h0}, // PC
                Icache_debug[i].set_data[63:32], Icache_debug[i].set_data[31:00],
                line_status);
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
            set = i[3:$clog2(`NUM_WAYS)];
            way = i[$clog2(`NUM_WAYS)-1:0];
`ifdef LRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h use:%h%s", 
                i, set, way, Icache_debug[set].set_valids[way], Icache_debug[set].set_tags[way], 
                {Icache_debug[set].set_tags[way], set[$clog2(`NUM_SETS)-1:0], 3'h0}, // PC
                Icache_debug[set].set_data[way][63:32], Icache_debug[set].set_data[way][31:00],
                Icache_debug[set].set_uses[way], line_status);
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h%s%s", 
                i, set, way, Icache_debug[set].set_valids[way], Icache_debug[set].set_tags[way], 
                {Icache_debug[set].set_tags[way], set[$clog2(`NUM_SETS)-1:0], 3'h0}, // PC
                Icache_debug[set].set_data[way][63:32], Icache_debug[set].set_data[way][31:00],
                (Icache_debug[set].MRU_idx == way) ? " <------ MRU" : "",
                line_status);
`endif // endif NMRU_REPLACEMENT
`ifdef RAND_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h%s", 
                i, set, way, Icache_debug[set].set_valids[way], Icache_debug[set].set_tags[way], 
                {Icache_debug[set].set_tags[way], set[$clog2(`NUM_SETS)-1:0], 3'h0}, // PC
                Icache_debug[set].set_data[way][63:32], Icache_debug[set].set_data[way][31:00],
                line_status);
`endif // endif RAND_REPLACEMENT
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
`ifdef LRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h use:%h%s", 
                i, 0, i, Icache_debug.set_valids[i], Icache_debug.set_tags[i], 
                {Icache_debug.set_tags[i], 3'h0}, // PC
                Icache_debug.set_data[i][63:32], Icache_debug.set_data[i][31:00],
                Icache_debug.set_uses[i], line_status);
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h%s%s", 
                i, 0, i, Icache_debug.set_valids[i], Icache_debug.set_tags[i], 
                {Icache_debug.set_tags[i], 3'h0}, // PC
                Icache_debug.set_data[i][63:32], Icache_debug.set_data[i][31:00],
                (Icache_debug.MRU_idx == i) ? " <------ MRU" : "",
                line_status);
`endif // endif NMRU_REPLACEMENT
`ifdef RAND_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b tag:%h (PC:%h) data:%h_%h%s", 
                i, 0, i, Icache_debug.set_valids[i], Icache_debug.set_tags[i], 
                {Icache_debug.set_tags[i], 3'h0}, // PC
                Icache_debug.set_data[i][63:32], Icache_debug.set_data[i][31:00],
                line_status);
`endif // endif RAND_REPLACEMENT
`endif // endif FASSOC_CACHE_MODE
        end
        $display();
    endtask

    task print_SQ;
        SQ_IDX complete_idx = sq_debug.ex_to_sq.idx;
        string prefix;
        string suffix;
        string color;
        $display("cycle %1d | %1h: store_dispatch: %b st_complete: %b ld_complete: %b sq_full: %b sq_available: %b dcache_store_stall: %b",
            clock_count, clock_count, sq_debug.valid_store, sq_debug.ex_to_sq.st_valid, 
            sq_debug.ex_to_sq.ld_valid, sq_debug.full, sq_debug.available, sq_debug.dcache_stall);
        for(int i = 0; i < `SQ_SIZE; i++) begin //SQ_FIFO contents
            color = `C_WHITE;
            prefix = "    ";
            suffix = "";
            if(i == sq_debug.head_ptr_out) begin
                if(i == sq_debug.tail_ptr_out)
                    prefix = "HT->";
                else
                    prefix = "H-->";
            end else if(i == sq_debug.tail_ptr_out)
                prefix = "T-->";

            if(i < sq_debug.head_ptr_out & i >= sq_debug.tail_ptr_out |
            ((sq_debug.tail_ptr_out > sq_debug.head_ptr_out) & (i >= sq_debug.tail_ptr_out | i < sq_debug.head_ptr_out)) | 
            (sq_debug.head_ptr_out == sq_debug.tail_ptr_out & ~sq_debug.available))
                color = `C_BLACK;

            if(sq_debug.SQ_FIFO[i].complete) begin
                if(sq_debug.sq2load_frwd_valid & 
                sq_debug.ld_fwd_hit + sq_debug.ex_to_sq.idx - (`SQ_SIZE - 1'b1) == i) begin
                    suffix = {suffix, $sformatf("FWD --> To load @ SQ idx: %h", sq_debug.ex_to_sq.idx)};
                    color  = `C_YELLOW;
                end else
                    color  = `C_GREEN;
            end else begin
                if(i == sq_debug.sq_onc + sq_debug.head_ptr_out & sq_debug.available) begin //ONC index (actual ONC)
                    suffix = {"<--- ONC ", suffix};
                    color  = `C_BLUE;
                end else if(sq_debug.valid_store & i == sq_debug.tail_ptr_out) begin //Normal index
                    suffix = {"<--- ST DISPATCH ", suffix};
                    color  = `C_WHITE;
                end
            end

            if(sq_debug.rob2sq_retire_en & sq_debug.SQ_FIFO[i].complete & i == sq_debug.head_ptr_out) begin
                suffix = {"<--- RETIRE ", suffix};
                color  = `C_PINK;
            end

            if(cdb_in.valid & cdb_in.squash_enable & (i == cdb_in.sq_idx)) begin
                suffix = {"<--- SQUASH ", suffix};
                color  = `C_RED;
            end
`ifdef TECHNICOLOR
            $write(color, 27);
`endif
            $display("%s SQ Entry %2h instr: %h st addr: %h st value: %h fwd_value: %h fwd_mask:%b complete: %b %s", 
                prefix, i, sq_debug.SQ_FIFO[i].inst, sq_debug.SQ_FIFO[i].sq_address, sq_debug.SQ_FIFO[i].sq_value, 
                sq_debug.SQ_FIFO[i].fwd_value, sq_debug.SQ_FIFO[i].fwd_mask, sq_debug.SQ_FIFO[i].complete, suffix);
`ifdef TECHNICOLOR
            $write(`C_CLEAR, 27);
`endif
        end
        $display();
    endtask

    task print_Dcache;
        string line_status;
        string write_size, write_size_size, write_size_sign;
        integer set, way;
        $display("cycle %1d | %1h DCache Contents", clock_count, clock_count);
        if(Dcache_proc_write_debug) begin // Get cache operation size / sign
            case(Dcache_proc_write_size_debug.size)
                BYTE:   write_size_size = "BYTE";
                HALF:   write_size_size = "HALF";
                WORD:   write_size_size = "WORD";
                DOUBLE: write_size_size = "DOUBLE";
            endcase
            write_size_sign = Dcache_proc_write_size_debug.sign ? "SIGNED" : "UNSIGNED";
            write_size = {write_size_sign, " ", write_size_size};
        end
        for(int i = 0; i < 16; i++) begin
            if((i == Dcache_proc_addr_debug) & Dcache_proc_read_debug & Dcache_proc_valid_debug) begin
                line_status = " <------ READ (HIT)";
            end else if((i == Dcache_proc_addr_debug) & Dcache_proc_read_debug & ~Dcache_proc_valid_debug) begin
                line_status = " <------ READ (MISS)";
            end else if((i == Dcache_proc_addr_debug) & Dcache_proc_write_debug & Dcache_proc_valid_debug) begin
                line_status = {" <------ WRITE (", write_size, ") (HIT)"};
            end else if((i == Dcache_proc_addr_debug) & Dcache_proc_write_debug & ~Dcache_proc_valid_debug) begin
                line_status = {" <------ WRITE (", write_size, ") (MISS)"};
            end else begin
                line_status = "";
            end
`ifdef DMAP_CACHE_MODE
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h%s", 
                i, i, 0, Dcache[i].set_valids, Dcache[i].set_dirty, 
                Dcache[i].set_tags, 
                Dcache[i].set_valids ? {Dcache[i].set_tags, i[$clog2(`NUM_SETS)-1:0], 3'h0} : 0, // ADDR
                Dcache[i].set_data, line_status);
`endif // endif DMAP_CACHE_MODE
`ifdef SASSOC_CACHE_MODE
            set = i[3:$clog2(`NUM_WAYS)];
            way = i[$clog2(`NUM_WAYS)-1:0];
`ifdef LRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h use:%h%s", 
                i, set, way, Dcache[set].set_valids[way], Dcache[set].set_dirty[way], 
                Dcache[set].set_tags[way], 
                Dcache[set].set_valids[way] ? {Dcache[set].set_tags[way], set[$clog2(`NUM_SETS)-1:0], 3'h0} : 0, // ADDR
                Dcache[set].set_data[way], Dcache[set].set_uses[way],
                line_status);
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h%s%s", 
                i, set, way, Dcache[set].set_valids[way], Dcache[set].set_dirty[way], 
                Dcache[set].set_tags[way], 
                Dcache[set].set_valids[way] ? {Dcache[set].set_tags[way], set[$clog2(`NUM_SETS)-1:0], 3'h0} : 0, // ADDR
                Dcache[set].set_data[way], (Dcache[set].MRU_idx == way) ? " <------ MRU" : "",
                line_status);
`endif // endif NMRU_REPLACEMENT
`ifdef RAND_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h%s", 
                i, set, way, Dcache[set].set_valids[way], Dcache[set].set_dirty[way], 
                Dcache[set].set_tags[way], 
                Dcache[set].set_valids[way] ? {Dcache[set].set_tags[way], set[$clog2(`NUM_SETS)-1:0], 3'h0} : 0, // ADDR
                Dcache[set].set_data[way], line_status);
`endif // endif RAND_REPLACEMENT
`endif // endif SASSOC_CACHE_MODE
`ifdef FASSOC_CACHE_MODE
`ifdef LRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h use:%h%s", 
                i, 0, i, Dcache.set_valids[i], Dcache.set_dirty[i], 
                Dcache.set_tags[i], 
                Dcache.set_valids[i] ? {Dcache.set_tags[i], 3'h0} : 0, // ADDR
                Dcache.set_data[i], Dcache.set_uses[i],
                line_status);
`endif // endif LRU_REPLACEMENT
`ifdef NMRU_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h%s%s", 
                i, 0, i, Dcache.set_valids[i], Dcache.set_dirty[i], 
                Dcache.set_tags[i], 
                Dcache.set_valids[i] ? {Dcache.set_tags[i], 3'h0} : 0, // ADDR
                Dcache.set_data[i], (Dcache.MRU_idx == i) ? " <------ MRU" : "",
                line_status);
`endif // endif NMRU_REPLACEMENT
`ifdef RAND_REPLACEMENT
            $display("Cache Line %1h [Set %1h Way %1h]: valid:%b dirty:%b tag:%h (ADDR:%h) data:%h%s", 
                i, 0, i, Dcache.set_valids[i], Dcache.set_dirty[i], 
                Dcache.set_tags[i], 
                Dcache.set_valids[i] ? {Dcache.set_tags[i], 3'h0} : 0, // ADDR
                Dcache.set_data[i], line_status);
`endif // endif RAND_REPLACEMENT
`endif // endif FASSOC_CACHE_MODE
        end
        $display();
    endtask

	task print_cycle();
`ifdef TECHNICOLOR
		$write(`C_BLUE,27); // green text
`endif
		$display("=============================================== CYCLE %4d | 0x%h ===============================================", clock_count, clock_count);
`ifdef TECHNICOLOR
		$write(`C_CLEAR,27); // clear color for next entry
`endif
		$display();
	endtask

`endif // endif DEBUG_MODE
	initial begin
		//$dumpvars;
	
		clock = 1'b0;
		reset = 1'b0;

		// Pulse the reset signal
		$display("@@\n@@\n@@  %t  Asserting System reset......", $realtime);
		reset = 1'b1;
		@(posedge clock);
		@(posedge clock);
		
		$readmemh("program.mem", memory.unified_memory);
		
		@(posedge clock);
		@(posedge clock);
		`SD;
		// This reset is at an odd time to avoid the pos & neg clock edges
		
		reset = 1'b0;
		$display("@@  %t  Deasserting System reset......\n@@\n@@", $realtime);
		
		// start printing ROB, stage outputs, etc.
		`ifdef DEBUG_MODE
			ok_to_print = 1;
		`endif


		wb_fileno = $fopen("writeback.out");
		
		//Open header AFTER throwing the reset otherwise the reset state is displayed
		print_header("                                                                            D-MEM Bus &\n");
		print_header("Cycle:      IF      |     ID      |     IS      |     EX     |     C     |     R      Reg Result");
	end

	// ----------------------------------------------------------------------------------------------------------------------------------- PRINT STATEMENTS
	// FIX excess print issue
	// Branch_tag needs to be sent to ROB via input_packet after dispatch
	`ifdef DEBUG_MODE
		always_ff @(negedge clock) begin
			if (ok_to_print) begin
 				// print_cycle();
				// print_BTB();
				// print_PHT_and_GHR();
				// $display();
				// print_squash();
				// print_basic();
				// print_regf();
				// if(cdb_in.valid)
    				// print_CDB();
                // print_fetch();
			    // print_ROB();
				// print_RS();
                // print_btag_tracker();
                // print_FL();
				// print_RAT();
                // print_Icache(); 
                // print_SQ();
                // print_Dcache();
			end
		end
	`endif
	// ----------------------------------------------------------------------------------------------------------------------------------- PRINT STATEMENTS END

	// Count the number of posedges and number of instructions completed
	// till simulation ends
	always @(posedge clock) begin
		if(reset) begin
			clock_count <= `SD 0;
			instr_count <= `SD 0;
		end else begin
			clock_count <= `SD (clock_count + 1);
			instr_count <= `SD (instr_count + pipeline_completed_insts);
		end
	end

	always @(negedge clock) begin
        if(reset) begin
			$display("@@\n@@  %t : System STILL at reset, can't show anything\n@@",
			         $realtime);
            debug_counter <= 0;
        end else begin
			`SD;
			`SD;
			
			// print the piepline stuff via c code to the pipeline.out
			print_cycles();
			print_stage(" ", if_packet_out.inst, if_packet_out.NPC[31:0], {31'b0,if_packet_out.valid});
			print_stage("|", if_id_packet.fetch.inst, if_id_packet.fetch.NPC[31:0], {31'b0,if_id_packet.fetch.valid});
			print_stage("|", id_is_packet.disp.inst, id_is_packet.disp.NPC[31:0], {31'b0,id_is_packet.disp.valid});
			print_stage("|", is_ex_packet.am.rs.d.inst, is_ex_packet.am.rs.d.NPC[31:0], {31'b0,is_ex_packet.am.valid});
			//print_stage("|", ex_c_packet.mul_packet.inst, ex_c_packet.mul_packet.NPC[31:0], {31'b0,ex_c_packet.mul_packet.valid});
			//print_stage("|", ex_c_packet.load_packet.inst, ex_c_packet.load_packet.NPC[31:0], {31'b0,ex_c_packet.load_packet.valid});
			//print_stage("|", ex_c_packet.alu_packet.inst, ex_c_packet.alu_packet.NPC[31:0], {31'b0,ex_c_packet.alu_packet.valid});			 
			//print_reg(32'b0, pipeline_commit_wr_data[31:0],
			//	{27'b0,pipeline_commit_wr_idx}, {31'b0,pipeline_commit_wr_en});
			 print_reg(32'b0, cdb_commit_wr_data[31:0],
				{27'b0, cdb_commit_wr_idx}, {31'b0, cdb_commit_wr_en});
			 print_membus({30'b0,proc2mem_command}, {28'b0,mem2proc_response},
				32'b0, proc2mem_addr[31:0],
				proc2mem_data[63:32], proc2mem_data[31:0]);
			
			// print the writeback information to writeback.out
			if(pipeline_completed_insts>0 & arch_wb_en) begin
                if(arch_wb_used & retire_idx != 0) begin
                    $fdisplay(wb_fileno, "PC=%x, REG[%d]=%x",
                        retire_NPC-4,
                        retire_idx,
                        retire_data);
                end else
                    $fdisplay(wb_fileno, "PC=%x, ---", retire_NPC-4);
			end
			
			// deal with any halting conditions
            //Original value for maximum debug counter was 30000000
			if(pipeline_error_status != NO_ERROR || debug_counter > 30000000) begin  // --------------------------------------------------------------- KILL SWITCH / TIMEOUT
                if(pipeline_error_status == NO_ERROR) begin
                    $display("HEY TRAVELER, you just timed out, that might be a big no-no");
                end
				`ifdef DEBUG_MODE
					// $display();
					// print_squash();
					// print_basic();
					// print_regf();
					// print_CDB();
                    // print_fetch();
					// print_ROB();
					// print_RS();
					// print_RAT();
                    // print_Icache();
                    // print_SQ();
                    // print_Dcache();
				`endif
				$display("@@@ Unified Memory contents hex on left, decimal on right: ");
				show_mem_with_decimal(0,`MEM_64BIT_LINES - 1); 
				// 8Bytes per line, 16kB total
				
				$display("@@  %t : System halted\n@@", $realtime);
				
				// don't want to print ROB, stage outputs, etc. since we've halted
				`ifdef DEBUG_MODE
					ok_to_print	= 0;
				`endif

				case(pipeline_error_status)
					// LOAD_ACCESS_FAULT:  
					// 	$display("@@@ System halted on memory error");
					HALTED_ON_WFI:          
						$display("@@@ System halted on WFI instruction");
					// ILLEGAL_INST:
					// 	$display("@@@ System halted on illegal instruction");
					default: 
						$display("@@@ System halted on unknown error code %x", 
							pipeline_error_status);
				endcase
				$display("@@@\n@@");
				show_clk_count;
				print_close(); // close the pipe_print output file
				$fclose(wb_fileno);		
				$finish;
			end
			
            debug_counter <= debug_counter + 1;
		end  // if(reset)   
	end 

endmodule  // module testbench

`endif
