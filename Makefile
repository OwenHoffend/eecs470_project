# make		  <- runs simv (after compiling simv if needed)
# make all	  <- runs simv (after compiling simv if needed)
# make simv	 <- compile simv if needed (but do not run)
# make syn	  <- runs syn_simv (after synthesizing if needed then 
#								 compiling synsimv if needed)
# make clean	<- remove files created during compilations (but not synthesis)
# make nuke	 <- remove all files created during compilation and synthesis
#
# To compile additional files, add them to the TESTBENCH or SIMFILES as needed
# Every .vg file will need its own rule and one or more synthesis scripts
# The information contained here (in the rules for those vg files) will be 
# similar to the information in those scripts but that seems hard to avoid.
#
#

SOURCE = test_progs/sampler.s

CRT = crt.s
LINKERS = linker.lds
ASLINKERS = aslinker.lds

DEBUG_FLAG = -g
CFLAGS =  -mno-relax -march=rv32im -mabi=ilp32 -nostartfiles -std=gnu11 -mstrict-align -mno-div 
OFLAGS = -O0
ASFLAGS = -mno-relax -march=rv32im -mabi=ilp32 -nostartfiles -Wno-main -mstrict-align
OBJFLAGS = -SD -M no-aliases 
OBJDFLAGS = -SD -M numeric,no-aliases

##########################################################################
# IF YOU AREN'T USING A CAEN MACHINE, CHANGE THIS TO FALSE OR OVERRIDE IT
CAEN = 1
##########################################################################
ifeq (1, $(CAEN))
	GCC = riscv gcc
	OBJDUMP = riscv objdump
	AS = riscv as
	ELF2HEX = riscv elf2hex
else
	GCC = riscv64-unknown-elf-gcc
	OBJDUMP = riscv64-unknown-elf-objdump
	AS = riscv64-unknown-elf-as
	ELF2HEX = elf2hex
endif


VCS = vcs -V -sverilog +vc -Mupdate -line -full64 +vcs+vcdpluson -debug_pp
LIB = /afs/umich.edu/class/eecs470/lib/verilog/lec25dscc25.v
VCS_COV = vcs -V -sverilog +vc -Mupdate -line -full64 +vcs+vcdpluson -debug_pp -cm line+tgl
VCS_MOD_LOAD = module load vcs

# SIMULATION CONFIG
export HEADERS = headers/include.svh #$(wildcard headers/*.svh)
export PIPEFILES = $(wildcard verilog/*.sv)
export CACHEFILES = $(wildcard cache/*.sv)
export TOP	= pipeline

SYNTH_DIR = synth
TCL_DIR = tcl
PIPELINE = $(SYNTH_DIR)/$(TOP).vg 

# GROUND TRUTH CONFIG
HEADERS_TRUTH   = $(wildcard ./p3_shit/*.svh)
PIPEFILES_TRUTH = $(wildcard ./p3_shit/*.sv)
TESTBENCH_TRUTH = ./p3_shit/pipeline_tb.sv ./p3_shit/pipe_print.c

# export TOP_TB = $(TOP)_tb
TESTBENCH = headers/include.svh
TESTBENCH += testbench/pipeline/pipeline_tb.sv 
TESTBENCH += testbench/mem.sv 
TESTBENCH += testbench/pipe_print.c
SIMFILES = verilog/barrel_shift_dir0.sv 
SIMFILES += verilog/CDB.sv 
# SIMFILES += verilog/issue.sv 
SIMFILES += verilog/ps2_dir1.sv 
SIMFILES += verilog/rot_pselect.sv 
SIMFILES += verilog/barrel_shift_dir1.sv 
SIMFILES += verilog/decoder.sv 
SIMFILES += verilog/LFSR.sv 
SIMFILES += verilog/pselect_dir0.sv 
SIMFILES += verilog/RS_ET.sv 
SIMFILES += verilog/binary_pselect_dir0.sv 
SIMFILES += verilog/dispatch.sv 
SIMFILES += verilog/onehot_to_binary_RS.sv 
SIMFILES += verilog/pselect_dir1.sv 
# SIMFILES += verilog/RS.sv 
SIMFILES += verilog/binary_pselect_dir1.sv 
SIMFILES += verilog/EX.sv 
SIMFILES += verilog/onehot_to_binary.sv 
SIMFILES += verilog/RAT.sv 
SIMFILES += verilog/SQ.sv 
SIMFILES += verilog/BRAT.sv
SIMFILES += verilog/fetch.sv 
SIMFILES += verilog/onehot_to_therm.sv 
SIMFILES += verilog/regfile_et.sv 
SIMFILES += verilog/tag_buffer.sv 
SIMFILES += verilog/btag_tracker.sv 
SIMFILES += verilog/FIFO.sv 
SIMFILES += verilog/PHT.sv 
# SIMFILES += verilog/regfile.sv 
SIMFILES += verilog/BTB.sv 
SIMFILES += verilog/GBP.sv 
SIMFILES += verilog/pipeline.sv 
SIMFILES += verilog/ROB.sv 
SIMFILES += verilog/CAM.sv 
SIMFILES += verilog/issue_et.sv 
SIMFILES += verilog/ps2_dir0.sv 
SIMFILES += verilog/rot_pselect_RS.sv 
SIMFILES += cache/cachemem.sv 
SIMFILES += cache/cache.sv 
SIMFILES += cache/dcache.sv 
SIMFILES += cache/icache.sv 
SIMFILES += cache/replacement_policy.sv 
SYNFILES = $(SYNTH_DIR)/$(TOP).vg

# TB_FULL = ./testbench/testbench.sv
# SIM_FULL = $(wildcard verilog/*.sv)
# SYNTHESIS CONFIG
# export CACHE_NAME = cache
# SYN_SINGLE = $(SYNTH_DIR)/$(TOP).vg
# SYNFILES   = $(PIPELINE) $(SYNTH_DIR)/$(PIPELINE_NAME)_svsim.sv
# CACHE	  = $(SYNTH_DIR)/$(CACHE_NAME).vg

# Passed through to .tcl scripts:	
export CLOCK_NET_NAME = clock
export RESET_NET_NAME = reset
# export CLOCK_PERIOD = 20 # Comment this line out if using synthopt script

# This makes it so that the default make target is 'sim', which is helpful exclusively to Jack
all: simv
	@:

# useage: make syn TOP=<module you'd like to synthesize> CLOCK_PERIOD=<clock period you'd like to synthesize>

################################################################################
## PIPELINE
################################################################################

synth/pipeline.vg:	$(SIMFILES) $(TCL_DIR)/pipeline.tcl
# synth/pipeline.vg:	$(SIMFILES) $(SYNTH_DIR)/BRAT.vg $(SYNTH_DIR)/CDB.vg $(SYNTH_DIR)/dispatch.vg $(SYNTH_DIR)/EX.vg $(SYNTH_DIR)/fetch.vg $(SYNTH_DIR)/issue_et.vg $(SYNTH_DIR)/ROB.vg $(SYNTH_DIR)/SQ.vg $(SYNTH_DIR)/cache.vg $(TCL_DIR)/pipeline.tcl
	dc_shell-t -f $(TCL_DIR)/pipeline.tcl | tee $(SYNTH_DIR)/pipeline_synth.out
	mv ./pipeline* $(SYNTH_DIR)

################################################################################
## BRANCH PREDICTOR
################################################################################

synth/PHT.vg:	$(SIMFILES) $(TCL_DIR)/PHT.tcl
	dc_shell-t -f $(TCL_DIR)/PHT.tcl | tee $(SYNTH_DIR)/PHT_synth.out
	mv ./PHT* $(SYNTH_DIR)

synth/GBP.vg:	$(SIMFILES) $(SYNTH_DIR)/PHT.vg $(TCL_DIR)/GBP.tcl
	dc_shell-t -f $(TCL_DIR)/GBP.tcl | tee $(SYNTH_DIR)/GBP_synth.out
	mv ./GBP* $(SYNTH_DIR)

synth/BTB.vg:	$(SIMFILES) $(TCL_DIR)/BTB.tcl
	dc_shell-t -f $(TCL_DIR)/BTB.tcl | tee $(SYNTH_DIR)/BTB_synth.out
	mv ./BTB* $(SYNTH_DIR)

################################################################################
## FETCH
################################################################################

synth/fetch.vg:	$(SIMFILES) $(SYNTH_DIR)/BTB.vg $(SYNTH_DIR)/GBP.vg $(TCL_DIR)/fetch.tcl
	dc_shell-t -f $(TCL_DIR)/fetch.tcl | tee $(SYNTH_DIR)/fetch_synth.out
	mv ./fetch* $(SYNTH_DIR)

################################################################################
## DISPATCH
################################################################################

synth/CAM.vg:	$(PIPEFILES) $(TCL_DIR)/CAM.tcl
	dc_shell-t -f $(TCL_DIR)/CAM.tcl | tee $(SYNTH_DIR)/CAM_synth.out
	mv ./CAM* $(SYNTH_DIR)

synth/FIFO.vg:	$(PIPEFILES) $(TCL_DIR)/FIFO.tcl
	dc_shell-t -f $(TCL_DIR)/FIFO.tcl | tee $(SYNTH_DIR)/FIFO_synth.out
	mv ./FIFO* $(SYNTH_DIR)

synth/RAT.vg:	$(PIPEFILES) $(TCL_DIR)/RAT.tcl
	dc_shell-t -f $(TCL_DIR)/RAT.tcl | tee $(SYNTH_DIR)/RAT_synth.out
	mv ./RAT* $(SYNTH_DIR)

synth/btag_tracker.vg:	$(PIPEFILES) $(TCL_DIR)/btag_tracker.tcl
	dc_shell-t -f $(TCL_DIR)/btag_tracker.tcl | tee $(SYNTH_DIR)/btag_tracker_synth.out
	mv ./btag_tracker* $(SYNTH_DIR)

synth/decoder.vg:	$(PIPEFILES) $(TCL_DIR)/decoder.tcl
	dc_shell-t -f $(TCL_DIR)/decoder.tcl | tee $(SYNTH_DIR)/decoder_synth.out
	mv ./decoder* $(SYNTH_DIR)

synth/dispatch.vg:	$(PIPEFILES) $(SYNTH_DIR)/FIFO.vg $(SYNTH_DIR)/RAT.vg $(SYNTH_DIR)/decoder.vg $(SYNTH_DIR)/btag_tracker.vg $(TCL_DIR)/dispatch.tcl
	dc_shell-t -f $(TCL_DIR)/dispatch.tcl | tee $(SYNTH_DIR)/dispatch_synth.out
	mv ./dispatch* $(SYNTH_DIR)

synth/BRAT.vg:	$(PIPEFILES) $(TCL_DIR)/BRAT.tcl
	dc_shell-t -f $(TCL_DIR)/BRAT.tcl | tee $(SYNTH_DIR)/BRAT_synth.out
	mv ./BRAT* $(SYNTH_DIR)

synth/ROB.vg:	$(PIPEFILES) $(TCL_DIR)/ROB.tcl
	dc_shell-t -f $(TCL_DIR)/ROB.tcl | tee $(SYNTH_DIR)/ROB_synth.out
	mv ./ROB* $(SYNTH_DIR)

################################################################################
## SQ
################################################################################

synth/SQ.vg:	$(PIPEFILES) $(TCL_DIR)/SQ.tcl
	dc_shell-t -f $(TCL_DIR)/SQ.tcl | tee $(SYNTH_DIR)/SQ_synth.out
	mv ./SQ* $(SYNTH_DIR)

################################################################################
## ISSUE
################################################################################

synth/regfile_et.vg:	$(SIMFILES) $(TCL_DIR)/regfile_et.tcl
	dc_shell-t -f $(TCL_DIR)/regfile_et.tcl | tee $(SYNTH_DIR)/regfile_et_synth.out
	mv ./regfile_et* $(SYNTH_DIR)

synth/rot_pselect_RS.vg:	$(SIMFILES) $(TCL_DIR)/rot_pselect_RS.tcl
	dc_shell-t -f $(TCL_DIR)/rot_pselect_RS.tcl | tee $(SYNTH_DIR)/rot_pselect_RS_synth.out
	mv ./rot_pselect_RS* $(SYNTH_DIR)

synth/onehot_to_binary_RS.vg:	$(SIMFILES) $(TCL_DIR)/onehot_to_binary_RS.tcl
	dc_shell-t -f $(TCL_DIR)/onehot_to_binary_RS.tcl | tee $(SYNTH_DIR)/onehot_to_binary_RS_synth.out
	mv ./onehot_to_binary_RS* $(SYNTH_DIR)

synth/RS_ET.vg:	$(SIMFILES) $(SYNTH_DIR)/onehot_to_binary_RS.vg $(SYNTH_DIR)/rot_pselect_RS.vg $(TCL_DIR)/RS_ET.tcl
	dc_shell-t -f $(TCL_DIR)/RS_ET.tcl | tee $(SYNTH_DIR)/RS_ET_synth.out
	mv ./RS_ET* $(SYNTH_DIR)

synth/issue_et.vg:	$(SIMFILES) $(SYNTH_DIR)/RS_ET.vg $(SYNTH_DIR)/regfile_et.vg $(TCL_DIR)/issue_et.tcl
	dc_shell-t -f $(TCL_DIR)/issue_et.tcl | tee $(SYNTH_DIR)/issue_et_synth.out
	mv ./issue_et* $(SYNTH_DIR)

################################################################################
## EXECUTE
################################################################################

synth/EX.vg:	$(SIMFILES) $(TCL_DIR)/EX.tcl
	dc_shell-t -f $(TCL_DIR)/EX.tcl | tee $(SYNTH_DIR)/EX_synth.out
	mv ./EX* $(SYNTH_DIR)

################################################################################
## COMPLETE
################################################################################

synth/CDB.vg:	$(SIMFILES) $(TCL_DIR)/CDB.tcl
	dc_shell-t -f $(TCL_DIR)/CDB.tcl | tee $(SYNTH_DIR)/CDB_synth.out
	mv ./CDB* $(SYNTH_DIR)

################################################################################
## CACHE
################################################################################

synth/cachemem.vg:	$(CACHEFILES) $(TCL_DIR)/cachemem.tcl
	dc_shell-t -f $(TCL_DIR)/cachemem.tcl | tee $(SYNTH_DIR)/cachemem_synth.out
	mv ./cachemem* $(SYNTH_DIR)

synth/icache.vg:	$(CACHEFILES) $(TCL_DIR)/icache.tcl
	dc_shell-t -f $(TCL_DIR)/icache.tcl | tee $(SYNTH_DIR)/icache_synth.out
	mv ./icache* $(SYNTH_DIR)

synth/dcache.vg:	$(CACHEFILES) $(TCL_DIR)/dcache.tcl
	dc_shell-t -f $(TCL_DIR)/dcache.tcl | tee $(SYNTH_DIR)/dcache_synth.out
	mv ./dcache* $(SYNTH_DIR)

# synth/cache.vg:	$(CACHEFILES) $(SYNTH_DIR)/cachemem.vg $(SYNTH_DIR)/icache.vg $(SYNTH_DIR)/dcache.vg $(TCL_DIR)/cache.tcl
synth/cache.vg:	$(CACHEFILES) $(TCL_DIR)/cache.tcl
	dc_shell-t -f $(TCL_DIR)/cache.tcl | tee $(SYNTH_DIR)/cache_synth.out
	mv ./cache.* $(SYNTH_DIR)

# ///////////////////////////////////////////////////////// #
#                         PROGRAMS                          #
# ///////////////////////////////////////////////////////// #

compile: $(CRT) $(LINKERS)
	$(GCC) $(CFLAGS) $(OFLAGS) $(CRT) $(SOURCE) -T $(LINKERS) -o program.elf
	$(GCC) $(CFLAGS) $(DEBUG_FLAG) $(CRT) $(SOURCE) -T $(LINKERS) -o program.debug.elf
assemble: $(ASLINKERS)
	$(GCC) $(ASFLAGS) $(SOURCE) -T $(ASLINKERS) -o program.elf 
	cp program.elf program.debug.elf
disassemble: program.debug.elf
	$(OBJDUMP) $(OBJFLAGS) program.debug.elf > program.dump
	$(OBJDUMP) $(OBJDFLAGS) program.debug.elf > program.debug.dump
	rm program.debug.elf
hex: program.elf
	$(ELF2HEX) 8 8192 program.elf > program.mem
program: compile disassemble hex
	@:
debug_program:
	gcc -lm -g -std=gnu11 -DDEBUG $(SOURCE) -o debug_bin
assembly: assemble disassemble hex
	@:

# ///////////////////////////////////////////////////////// #
#                         SIMULATION                        #
# ///////////////////////////////////////////////////////// #

simv:	$(SIMFILES)	$(TESTBENCH)
	$(VCS) $(TESTBENCH) $(SIMFILES) -o simv

remove:
	rm -f ./simv
	rm -f ./simv.daidir/.vcs.timestamp

sim:	remove simv
	./simv | tee program.out

simv_dve:	$(SIMFILES)	$(TESTBENCH)
	$(VCS) +memcbk $(TESTBENCH) $(SIMFILES) -o simv_dve -R -gui

remove_dve:
	rm -f ./simv_dve.daidir/.vcs.timestamp
	rm -f simv_dve

dve:	remove_dve simv_dve
	./simv_dve -gui

sim_dve: remove_dve simv_dve
	./simv_dve | tee program.out

# generates line and toggle coverage reports without makefile
cvg: 	$(HEADERS) $(TESTBENCH) ./verilog/$(TOP).sv ./testbench/$(TOP)/$(TOP_TB).sv
	$(VCS_COV) $^ -o simv
	./simv -cm line+tgl
	bash -c "module load vcs; urg -dir simv.vdb -format text"

.PHONY: sim

# Ground truth:
sim_truth: simv_truth
	./simv_truth | tee program.out

simv_truth: $(HEADERS_TRUTH) $(PIPEFILES_TRUTH) $(TESTBENCH_TRUTH)
	$(VCS) $^ -o simv_truth

.PHONY: gt

# ///////////////////////////////////////////////////////// #
#                         SYNTHESIS                         #
# ///////////////////////////////////////////////////////// #

syn_simv:	$(SYNFILES) $(TESTBENCH)
	$(VCS) $(TESTBENCH) $(SYNFILES) $(LIB) -o syn_simv

syn:	$(SYNFILES)
	@:
	# $(VCS) $(SYNFILES) $(LIB) -o syn | tee syn_program.out

syn_simv_dve:	$(SYNFILES) $(TESTBENCH)
	$(VCS) +memcbk $(TESTBENCH) $(SYNFILES) $(LIB) -o syn_simv_dve -R -gui

syn_dve: syn_simv_dve
	./syn_simv_dve -gui

.PHONY: syn

# ///////////////////////////////////////////////////////// #
#                         CLEANUP                           #
# ///////////////////////////////////////////////////////// #

clean:
	rm -rf *simv *simv.daidir csrc vcs.key program.out *.key
	rm -rf vis_simv vis_simv.daidir
	rm -rf dve* inter.vpd DVEfiles
	rm -rf syn_simv syn_simv.daidir syn_program.out
	rm -rf synsimv synsimv.daidir csrc vcdplus.vpd vcs.key synprog.out pipeline.out writeback.out vc_hdrs.h
	rm -f *.elf *.dump *.mem debug_bin

clean_syn:
	rm -rf $(SYNTH_DIR)/*_synth.out
	rm -rf $(SYNTH_DIR)/*-verilog.pvl
	rm -rf $(SYNTH_DIR)/*-verilog.syn
	rm -rf $(SYNTH_DIR)/*.chk
	rm -rf $(SYNTH_DIR)/*.mr
	# rm -rf $(SYNTH_DIR)/*.rep

nuke_syn:
	rm -rf $(SYNTH_DIR)/*

nuke:	clean
	# rm -rf synth/*.vg synth/*.rep synth/*.ddc synth/*.chk synth/*.log synth/*.syn
	# rm -rf synth/*.out command.log synth/*.db synth/*.svf synth/*.mr synth/*.pvl
	rm -f -r simv*
	rm -f -r *simv
	rm -rf ./*.pvl
	rm -rf ./*.syn
	rm -rf ./*.mr
