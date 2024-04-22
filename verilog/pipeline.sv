/////////////////////////////////////////////////////////////////////////
//                                                                     //
//   Modulename :  pipeline.v                                          //
//                                                                     //
//  Description :  Top-level module of the verisimple pipeline;        //
//                 This instantiates and connects the 5 stages of the  //
//                 Verisimple pipeline togeather.                      //
//                                                                     //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __PIPELINE_V__
`define __PIPELINE_V__

`timescale 1ns/100ps
`include "./headers/include.svh"
`include "./verilog/CDB.sv"
`include "./verilog/dispatch.sv"
`include "./verilog/EX.sv"
`include "./verilog/fetch.sv"
`include "./verilog/issue_et.sv"
`include "./verilog/ROB.sv"
`include "./verilog/SQ.sv"
`include "./verilog/BRAT.sv"
`include "./testbench/mem.sv"
`include "./cache/cache.sv"

module pipeline (
	input         clock,                        // System clock
	input         reset,                        // System reset
	input [3:0]              mem2proc_response, // Tag from memory about current request
	input [63:0]             mem2proc_data,     // Data coming back from memory
	input [3:0]              mem2proc_tag,      // Tag from memory about current reply

    // Data to MEM
	output BUS_COMMAND       proc2mem_command,  // command sent to memory
	output logic [`XLEN-1:0] proc2mem_addr,     // Address sent to memory
	output logic [63:0]      proc2mem_data,     // Data sent to memory
`ifndef CACHE_MODE
	output MEM_SIZE          proc2mem_size,     // data size sent to memory
`endif
    output CACHE             Dcache,
    output logic             mem_busy,

	output logic [3:0]       pipeline_completed_insts,
	 // FIXME: Should be updated to fit in line with our pipeline features
	output EXCEPTION_CODE    pipeline_error_status,
	output PHYS_REG_TAG      cdb_commit_wr_idx,
	output logic [`XLEN-1:0] cdb_commit_wr_data,
	output logic             cdb_commit_wr_en,
	//output logic [`XLEN-1:0] pipeline_commit_NPC,

	// testing hooks (these must be exported so we can test
	// the synthesized version) data is tested by looking at
	// the final values in memory
	output FETCH_PACKET if_packet_out,
	output IF_ID_PACKET if_id_packet,
	output ID_IS_PACKET id_is_packet,
	output IS_EX_PACKET is_ex_packet,
	output EX_C_PACKET  ex_c_packet,
	output CDB_PACKET	cdb_in,
	output ROB_ENTRY	ROB_head_packet_out,

    // retire logic
    output logic arch_wb_en,
    output logic arch_wb_used,
    output logic [$clog2(`PHYS_REGFILE_SIZE)-1:0] retire_idx,
    output logic [`XLEN-1:0] retire_data,
    output logic [`XLEN-1:0] retire_NPC

`ifdef DEBUG_MODE
	, 
    // Fetch
    output logic [63:0]      Icache2proc_data,
    output logic             Icache2proc_valid,
    output logic [`XLEN-1:0] proc2Icache_addr,

    // branch prediction
	output logic   [`GHB_SIZE-1:0] debug_ghbr, debug_n_ghbr,
	output logic   [2**(`GHB_SIZE)-1:0] [`SATURATION_BITS-1:0] debug_PHT, debug_next_PHT,
    output logic   [2**(`GHB_SIZE)-1:0]    debug_PHT_dirty_idxs,
    output BTB_DATA [`NUM_BTB_ENTRIES-1:0]  debug_BTB_data,
    output BTB_TAG  [`NUM_BTB_ENTRIES-1:0]  debug_BTB_tags,
    output logic    [`NUM_BTB_ENTRIES-1:0]  debug_BTB_dirty_idxs,

	// ROB
	output ROB_ENTRY [`ROB_SIZE-1:0] rob_debug,
	output ROB_IDX rob_head,
	output ROB_IDX rob_tail,
	output logic ROB_full, ROB_available, rob_retire_cond,

	// RS
	output RS_DEBUG_PACKET rs_debug,
	output logic RS_full, RS_available,
	
	// RegFile
	output REG_DEBUG_PACKET reg_debug,

	// freelist
	output logic                          freelist_full,
	output logic                          freelist_available,
	output logic [$clog2(`FREELIST_SIZE)-1:0] freelist_head,
	output logic [$clog2(`FREELIST_SIZE)-1:0] freelist_tail,
	output PHYS_REG_TAG  [`FREELIST_SIZE-1:0] freelist_debug,
	
	// RAT
	output PHYS_REG_TAG [`ARCH_REGFILE_SIZE-1:0] rat_debug,
	output logic        [`ARCH_REGFILE_SIZE-1:0] rat_debug_ready,

    // BTAG TRACKER
    output BRANCH_MASK branch_mask_out,
    output BRANCH_MASK branch_tag_out,
    output BRANCH_MASK branch_tag_next,
    output logic       bs_stall,

    // SQ
    output SQ_DEBUG_PACKET sq_debug,

    // Cache
    output CACHE           Icache_debug,
    output CACHE_ADDR      Icache_proc_addr_debug,
    output logic           Icache_proc_valid_debug,
    output CACHE_ADDR      Dcache_proc_addr_debug,
    output logic           Dcache_proc_read_debug,
    output logic           Dcache_proc_write_debug,
    output SIGNED_MEM_SIZE Dcache_proc_write_size_debug,
    output logic           Dcache_proc_valid_debug
`endif
);
	// Defining ROB ports
	ROB_PACKET rob_packet_in;
	// ROB_ENTRY  ROB_head_packet_out; // Made into a pipeline output
	ROB_ENTRY  ROB_tail_packet_out;
	ROB_IDX    ROB_tail_ptr_out;
`ifndef DEBUG_MODE
	logic      ROB_full, ROB_available, rob_retire_cond;
`endif

    // Defining SQ ports
    //Inputs
    SQ_PACKET         ex_to_sq;
    logic             rob2sq_retire_en;
    // logic             dcache_store_stall;

    //Outputs
    SQ_IDX            sq_onc;
    SQ_IDX            sq_tail_ptr_out; 
    SQ_IDX            sq_head_ptr_out;
    SQ_PACKET         sq_to_cache;
    logic             sq2load_frwd_valid;
    logic             sq2load_partial_frwd;
    logic [3:0]       sq2load_frwd_mask;
    logic [`XLEN-1:0] sq2load_frwd_value;
    logic             sq_full;
    logic             sq_available;
    logic             sq_all_complete;

	// Defining Mem ports
`ifndef DEBUG_MODE
    // Fetch
	logic [63:0]      Icache2proc_data;
    logic             Icache2proc_valid;
	logic [`XLEN-1:0] proc2Icache_addr;
`endif

	// D-Cache
    logic [`XLEN-1:0] Dcache2proc_data;
    logic             Dcache2proc_valid;
    logic [`XLEN-1:0] proc2Dcache_addr;
	BUS_COMMAND       proc2Dcache_command;
	logic [`XLEN-1:0] proc2Dcache_data;
    SIGNED_MEM_SIZE   proc2Dcache_size;
    //Stall loads if the cache misses or a store is happening
    logic             cache_busy;

	// Defining Dispatch ports
	DISPATCH_PACKET    dispatch_packet_out;
    BRANCH_STACK_ENTRY dispatch_checkpoint_entry_out;
    logic              dispatch_stall;
    logic              checkpoint_write;
`ifndef DEBUG_MODE
    BRANCH_MASK        branch_mask_out;
`endif

	// Defining IS ports
	IS_PACKET am_issue_packet_out, ls_issue_packet_out;

`ifndef DEBUG_MODE
    logic RS_full, RS_available;
`endif

	// Defining EX ports
	EX_PACKET mul_packet_out, alu_packet_out, load_packet_out;
	PHYS_REG_TAG early_mult_tag;

	// Defining CDB ports
	// CDB_PACKET cdb_in; // Made into a pipeline output
	logic CDB_available;
    logic cdb_stall; 

    // Defining BRAT ports
    BRANCH_STACK_ENTRY brat_checkpoint_entry_out;

	// DEBUG I/O
`ifdef DEBUG_MODE
	// defined in output port map
	assign rob_tail = ROB_tail_ptr_out;
`endif
	
	// Pipeline register enables
	//logic   if_id_enable, id_ex_enable, ex_mem_enable, mem_wb_enable;
	
    //////////////////////////////////////////////////
    //                                              //
    //         PIPELINE OUTPUT ASSIGNMENTS          //
    //                                              //
    //////////////////////////////////////////////////
    
	assign pipeline_completed_insts = {3'b0, (ROB_available & rob_retire_cond)};
	
	assign pipeline_error_status =  (ROB_head_packet_out.halt & ROB_available) ? HALTED_ON_WFI : NO_ERROR;
									/*mem_wb_illegal             ? ILLEGAL_INST :
	                                mem_wb_halt                ? HALTED_ON_WFI :
	                                (mem2proc_response==4'h0)  ? LOAD_ACCESS_FAULT :
	                                NO_ERROR;*/
	
	assign cdb_commit_wr_idx = cdb_in.cdb_tag;
	assign cdb_commit_wr_data = cdb_in.head_data;
	assign cdb_commit_wr_en = cdb_in.valid & cdb_in.T_used;

    //////////////////////////////////////////////////
    //                                              //
    //       CACHE RULES EVERYTHING AROUND ME       //
    //          (IT'S PRETTY CACHE MONEY)           //
    //                                              //
    //////////////////////////////////////////////////
 
    // DCache inputs received from LQ / SQ
    always_comb begin
        proc2Dcache_addr    = sq_to_cache.st_valid ? sq_to_cache.address : 
                              (ex_to_sq.ld_valid & sq_to_cache.ld_valid) ? ex_to_sq.address    : 0;
        proc2Dcache_command = sq_to_cache.st_valid ? BUS_STORE : 
                              (ex_to_sq.ld_valid & sq_to_cache.ld_valid) ? BUS_LOAD  : BUS_NONE;
        proc2Dcache_size    = sq_to_cache.st_valid ? sq_to_cache.mem_size : 
                              (ex_to_sq.ld_valid & sq_to_cache.ld_valid) ? ex_to_sq.mem_size    : {1'b1, BYTE}; // UNSIGNED BYTE
        proc2Dcache_data    = sq_to_cache.value;
    end

    cache pipeline_cache(
        .clock              (clock),
        .reset              (reset),

        // INPUT: Memory responds to requests from pipeline
        .mem2cache_response (mem2proc_response),
        .mem2cache_data     (mem2proc_data    ),
        .mem2cache_tag      (mem2proc_tag     ),

        // INPUT: Pipeline requests instructions from I-Cache
        .proc2Icache_addr   (proc2Icache_addr ),

		// INPUT: Pipeline loads/stores data to D-Cache
		.proc2Dcache_addr   (proc2Dcache_addr ),
		.proc2Dcache_command(proc2Dcache_command),
		.proc2Dcache_data   (proc2Dcache_data   ),
        .proc2Dcache_size   (proc2Dcache_size ),

        // OUTPUTS: Cache sends command to memory
        .cache2mem_command  (proc2mem_command ),
        .cache2mem_addr     (proc2mem_addr    ),
		.cache2mem_data     (proc2mem_data    ),

        // OUTPUTS: Cache sends instructions to fetch
        .Icache2proc_data    (Icache2proc_data ),
        .Icache2proc_valid   (Icache2proc_valid),

		// OUTPUTS: Cache sends memory data and status signals to pipeline
		.Dcache2proc_data   (Dcache2proc_data ),
		.Dcache2proc_valid  (Dcache2proc_valid),
		.mem_busy           (mem_busy         ),
        .cache_busy         (cache_busy       ),

        // OUTPUTS: DCache contents for evicting dirty cache lines on WFI
        .Dcache             (Dcache)

        // Debug OUTPUTS
`ifdef DEBUG_MODE
        ,
        .Icache_debug                 (Icache_debug                ),
        .Icache_proc_addr_debug       (Icache_proc_addr_debug      ),
        .Icache_proc_valid_debug      (Icache_proc_valid_debug     ),
        .Dcache_proc_addr_debug       (Dcache_proc_addr_debug      ),
        .Dcache_proc_read_debug       (Dcache_proc_read_debug      ),
        .Dcache_proc_write_debug      (Dcache_proc_write_debug     ),
        .Dcache_proc_write_size_debug (Dcache_proc_write_size_debug),
        .Dcache_proc_valid_debug      (Dcache_proc_valid_debug     )
`endif
    );

    //////////////////////////////////////////////////
    //                                              //
    //              BOYS OF THE ROB                 //
    //                                              //
    //////////////////////////////////////////////////

    ROB ROB0 (
    	// Input
    	.clock			    (clock),
    	.reset			    (reset),    
    	.dcache_store_stall (mem_busy),
    	.rob_packet_in	    (id_is_packet.rob),
    	.cdb_in			    (cdb_in),

    	// Output
	    .tail_ptr_out	    (ROB_tail_ptr_out), 
	    .head_packet	    (ROB_head_packet_out),  
	    .tail_packet	    (ROB_tail_packet_out),  
        .rob2sq_retire_en   (rob2sq_retire_en),
        .rob_retire_cond    (rob_retire_cond),
	    .full			    (ROB_full),         
	    .available          (ROB_available)
`ifdef DEBUG_MODE
        ,
	    .rob_debug          (rob_debug),
	    .head_ptr_out	    (rob_head)
`endif
    );

    //////////////////////////////////////////////////
    //                                              //
    //              GENTS OF THE SQ                 //
    //                                              //
    //////////////////////////////////////////////////

    SQ SQ0 (
        // Input
    	.clock			    (clock),
    	.reset			    (reset),
        .cdb_in             (cdb_in),
        .valid_store        (id_is_packet.disp.valid & 
                             id_is_packet.disp.wr_mem),
        .ex_to_sq_in        (ex_to_sq),
        .rob2sq_retire_en   (rob2sq_retire_en),
        .dcache_store_stall (mem_busy),

        // Output
        .sq_onc             (sq_onc),
        .tail_ptr_out       (sq_tail_ptr_out),
        .head_ptr_out       (sq_head_ptr_out),
        .sq_to_cache        (sq_to_cache),
        .sq2load_frwd_valid (sq2load_frwd_valid),
        .sq2load_partial_frwd(sq2load_partial_frwd),
        .sq2load_frwd_value (sq2load_frwd_value),
        .sq2load_frwd_mask  (sq2load_frwd_mask),
        .full               (sq_full),            //not connected yet
        .available          (sq_available),        //not connected yet
        .all_complete       (sq_all_complete)
`ifdef DEBUG_MODE
        ,
        .dispatch_instr     (id_is_packet.disp.inst),
        .sq_debug            (sq_debug)
`endif
    );

    //////////////////////////////////////////////////
    //                                              //
    //             OMG THAT'S SO FETCH              //
    //                                              //
    //////////////////////////////////////////////////

    fetch fetch0 (
    	// Input
    	.clock			   (clock),
    	.reset			   (reset),
    	.cdb_in			   (cdb_in),
    	.dispatch_stall	   (dispatch_stall),   
    	.Icache2proc_data  (Icache2proc_data),
    	.Icache2proc_valid (Icache2proc_valid), 

`ifdef GSHARE
    	.ex_bp		      (alu_packet_out.ex_bp),

`ifdef DEBUG_MODE
        .debug_ghbr(debug_ghbr),
        .debug_n_ghbr(debug_n_ghbr),
        .debug_PHT(debug_PHT),
        .debug_next_PHT(debug_next_PHT),
        .debug_PHT_dirty_idxs(debug_PHT_dirty_idxs),
        .debug_BTB_data(debug_BTB_data),
        .debug_BTB_tags(debug_BTB_tags),
        .debug_BTB_dirty_idxs(debug_BTB_dirty_idxs),
`endif

`endif 

    	// Output	
    	.proc2Icache_addr  (proc2Icache_addr),
    	.if_packet_out     (if_packet_out)
    );

    //////////////////////////////////////////////////
    //                                              //
    //            IF/ID Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

`ifdef USE_IF_ID_REG
    //synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if (reset | (cdb_in.valid & cdb_in.squash_enable)) begin	// clock if_packet_out
			if_id_packet <= `SD 0;
		end else if (~dispatch_stall) begin 		// noop insertion is handled by dispatch
            if_id_packet.fetch <= `SD if_packet_out;
		end
	end
`else
	assign if_id_packet.fetch = if_packet_out;
`endif
   
    //////////////////////////////////////////////////
    //                                              //
    //              Dispatch Stage                  //
    //                                              //
    //////////////////////////////////////////////////

    dispatch dispatch0 (
    	// Input
    	.clock								(clock),
    	.reset								(reset),
    	.fetch_packet_in					(if_id_packet.fetch),
    	.cdb_in								(cdb_in),
    	.checkpoint_entry_in	            (brat_checkpoint_entry_out),
    	.ROB_head_entry						(ROB_head_packet_out),
        .rob_retire_cond                    (rob_retire_cond),
    	.ROB_full							(ROB_full),
        .ROB_available                      (ROB_available),
    	.ROB_tail_ptr_in					(ROB_tail_ptr_out),
        .sq_tail_ptr_in                     (sq_tail_ptr_out),
    	.RS_full							(RS_full),
        .sq_full                            (sq_full),

    	// Output
    	.dispatch_packet_out				(dispatch_packet_out),
    	.rob_packet_out						(rob_packet_in), // drives ROB's input packet
        .branch_mask_out                    (branch_mask_out),
        .checkpoint_write                   (checkpoint_write),
        .checkpoint_entry_out               (dispatch_checkpoint_entry_out),
        .stall_out                          (dispatch_stall)

`ifdef DEBUG_MODE
	    ,
	    // freelist
	    .freelist_full						(freelist_full),
	    .freelist_available					(freelist_available),
	    .freelist_head						(freelist_head),
	    .freelist_tail						(freelist_tail),
	    .freelist_debug						(freelist_debug),
    
	    // RAT
	    .rat_debug							(rat_debug),
	    .rat_debug_ready					(rat_debug_ready),

        // BTAG TRACKER
        .branch_tag_out                     (branch_tag_out),
        .branch_tag_next                    (branch_tag_next),
        .bs_stall                           (bs_stall)
`endif
    );

    //////////////////////////////////////////////////
    //                                              //
    //          ID/IS Pipeline Register             //
    //                                              //
    //////////////////////////////////////////////////

`ifdef USE_ID_IS_REG
    ID_IS_PACKET id_is_packet;
    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
    	if(reset) begin
    		id_is_packet <= `SD 0;
        end else begin
    		id_is_packet.disp <= `SD dispatch_packet_out;
			id_is_packet.rob  <= `SD rob_packet_in;
    	end
    end
`else
	assign id_is_packet.disp = dispatch_packet_out;
	assign id_is_packet.rob  = rob_packet_in;
`endif

    //////////////////////////////////////////////////
    //                                              //
    //              Branch Stack                    //
    //                                              //
    //////////////////////////////////////////////////

    BRAT BRAT0(
        .clock(clock),
        .reset(reset),
        .checkpoint_write(checkpoint_write),
        .checkpoint_branch_mask(branch_mask_out),
        .checkpoint_entry_in(dispatch_checkpoint_entry_out),
        .cdb_in(cdb_in),
        .ROB_head_entry(ROB_head_packet_out),
        .rob_retire_cond(rob_retire_cond),
        .ROB_available(ROB_available),
        .checkpoint_entry_out(brat_checkpoint_entry_out)
    );

    //////////////////////////////////////////////////
    //                                              //
    //               Issue Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    logic issue_ls_stall;
    assign issue_ls_stall = cache_busy | (cdb_in.valid & cdb_in.is_store);
    // Just stop us from getting into the state where our processor doesn't work

	issue_et issue_et0 (
    	// Input
    	.clock			(clock),
    	.reset			(reset),
    	.dispatch_in    (id_is_packet.disp),
    	.cdb_in			(cdb_in),
    	.branch_tag_in	(id_is_packet.disp.branch_tag),

		.early_mult_tag (early_mult_tag),

        //SQ inputs
        .sq_onc         (sq_onc),
        .sq_head        (sq_head_ptr_out),
        .sq_available   (sq_available),
        .sq_full        (sq_full),
        .sq_all_complete(sq_all_complete),
`ifndef ALLOW_MULTIPLE_CDB_ENQUEUE
		.cdb_stall      (cdb_stall),
`else
        .cdb_stall      (1'b0),
`endif
        .mem_busy       (issue_ls_stall),

    	// Output
    	.am_issue_out   (am_issue_packet_out),
		.ls_issue_out   (ls_issue_packet_out),

    	.rs_full		(RS_full),
    	.rs_available	(RS_available),

        .retire_idx(ROB_head_packet_out.d_tag),
        .retire_data(retire_data)

`ifdef DEBUG_MODE
        , 
        .rs_debug(rs_debug),
        .reg_debug(reg_debug)
`endif
    );

    //////////////////////////////////////////////////
    //                                              //
    //          IS/EX Pipeline Register             //
    //                                              //
    //////////////////////////////////////////////////

`ifdef USE_IS_EX_REG
    IS_PACKET am_next, ls_next;

    always_comb begin
        am_next = am_issue_packet_out;
        ls_next = ls_issue_packet_out;
    end

    //synopsys sync_set_reset "reset"
    always_ff @(posedge clock) begin
        if(reset) begin
            is_ex_packet <= `SD 0;
        end else begin
            is_ex_packet.am <= `SD am_next; // must also account for stalls and early tag data
            if(~cache_busy | (sq2load_frwd_valid & ~sq2load_partial_frwd) | is_ex_packet.ls.rs.d.wr_mem) begin
                is_ex_packet.ls <= `SD ls_next;
            end else if((cdb_in.valid & cdb_in.squash_enable) &&
                ((cdb_in.branch_mask & is_ex_packet.ls.rs.branch_tag) != 0)) begin
                is_ex_packet.ls <= `SD 0;
            end else if(cdb_in.valid & ~cdb_in.squash_enable) begin
                is_ex_packet.ls.rs.branch_tag <= `SD is_ex_packet.ls.rs.branch_tag & ~cdb_in.branch_mask;
            end
        end
    end
`else
    assign is_ex_packet.am = am_issue_packet_out; // if you use these three lines Brad will body slam you
    assign is_ex_packet.ls = ls_issue_packet_out;
`endif
   
    //////////////////////////////////////////////////
    //                                              //
    //             Execute Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    EX EX0 (
    	// Input
    	.clock			(clock),
    	.reset			(reset),
		.is_ex_packet       (is_ex_packet),
    	.cdb_in			    (cdb_in),
        .sq2load_frwd_valid (sq2load_frwd_valid),
        .sq2load_frwd_value (sq2load_frwd_value),
        .sq2load_frwd_mask  (sq2load_frwd_mask),
        .sq2load_partial_frwd(sq2load_partial_frwd),
        .mem_busy           (cache_busy),
        .Dcache2proc_data   (Dcache2proc_data),

    	// Output
        .ex_to_sq_out   (ex_to_sq),
    	.alu_packet_out	(alu_packet_out),
    	.load_packet_out(load_packet_out),
    	.mul_packet_out	(mul_packet_out),

		.early_mult_tag (early_mult_tag)
    );

    //////////////////////////////////////////////////
    //                                              //
    //             EX/C Pipeline Register           //
    //                                              //
    //////////////////////////////////////////////////

`ifdef USE_EX_C_REG // adds one cycle for early tag broadcast - it's untested but theoretically it works

    //synopsys sync_set_reset "reset"
	always_ff @(posedge clock) begin
		if(reset) begin
			ex_c_packet <= `SD 0;
		end else begin
			ex_c_packet.mul_packet <= `SD mul_packet_out;
			ex_c_packet.alu_packet <= `SD alu_packet_out;
			ex_c_packet.load_packet <= `SD load_packet_out;
		end
	end
`else
	always_comb begin 
		ex_c_packet.mul_packet = mul_packet_out;
		ex_c_packet.alu_packet = alu_packet_out;
		ex_c_packet.load_packet = load_packet_out;
	end
`endif

    //////////////////////////////////////////////////
    //                                              //
    //             Complete Stage                   //
    //                                              //
    //////////////////////////////////////////////////

    CDB CDB0 (
    	// Input
    	.clock		(clock),
    	.reset		(reset),
    	.alu_packet	(ex_c_packet.alu_packet),
    	.load_packet(ex_c_packet.load_packet),
    	.mul_packet	(ex_c_packet.mul_packet),

    	// Output
    	.cdb		(cdb_in),    // Drives cdb packet for the rest of the system
    	.available	(CDB_available)
`ifndef ALLOW_MULTIPLE_CDB_ENQUEUE
        , .cdb_stall  (cdb_stall)
`endif
    );

    //////////////////////////////////////////////////
    //                                              //
    //              Retire Stage                    //
    //                                              //
    //////////////////////////////////////////////////

    always_comb begin
        // Retire
        arch_wb_used = ROB_available & ROB_head_packet_out.T_used;
        retire_idx   = rob_retire_cond ? ROB_head_packet_out.d_tag_old_arch : 0;
        arch_wb_en   = rob_retire_cond & (~mem_busy | ~ROB_head_packet_out.is_store);
        retire_NPC   = ROB_head_packet_out.dispatch_NPC;
    end

endmodule  // module VeriHardx69 ( ͡° ͜ʖ ͡°)

`endif  // __PIPELINE_V__
