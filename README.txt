-------R10k-inspired Out-of-Order Pipeline-------
--Baker, Daftardar, Erhardt, Hoffend, Mahindroo--

// ------------------------------------------------------------------------------------------------------

INFO for FINAL SUBMISSION:
    Features : 
        Early Retirement of Mispredicted Branches   - FUNCTIONAL
        Wakeup/Select Reservation Station           - FUNCTIONAL
        N-Way Set Associative Cache                 - FUNCTIONAL
        Parametrized Replacement Policy             - FUNCTIONAL
        Store-to-Load Forwarding                    - FUNCTIONAL
        Gshare Branch Predictor                     - IMPLEMENTED
            enabling Gshare causes trouble for the , so we've disabled this for final submission.
        Synthesis Optimization Script               - FUNCTIONAL
        Regression Testing Script                   - FUNCTIONAL
        Independent ALU/MULT and L/S Issue          - FUNCTIONAL
        Early Tag Broadcast                         - IMPLEMENTED
            lsq integration is causing problems and we ran out of debug time, so this feature is disabled in submission.  the feature is working in many other programs.
            adding a second CDB for only loads and stores would greatly mitigate this problem, and it's very possible that having a wakeup/select reservation station
            would mitigate the penalty incurred by using a second CDB since the second CDB would only route to the RS and ROB, both of which have low cdb interface delays.

    Regression Results:
        Passing all synthesized regression without Gshare enabled
        Failing graph.c with Gshare enabled


Debug Outputs (testbench/pipeline/pipeline_tb.sv)
    - Defining DEBUG_MODE in sys_defs.svh enables debug infrastructure
    - Search PRINT STATEMENTS in pipeline_tb and uncomment the relevant files
    - Color coding is enabled by defining TECHNICOLOR in pipeline_tb
    - Single cycle outputs can be output using the debug_counter > XXXXXXXX version of debug outputs


Synthesis Binary Search Optimization (synthopt.sh)
    Flags:
        -m modname :
            runs default synthesis optimization on file ./verilog/modname.sv
            modname must be the same as the module name in the file modname.sv
        -c (CLK_PERIOD) :
            overrides default clock period for first synth run
            default clock period starts at 8
        -l (MAX_LEVEL) :
            overrides default number of iterations the script attempts
            if "l" is N, N+1 search iterations are run. N+1 must not exceed the
            number of elements in the INCREMENTS list (currently 5) in synthopt.sh
            default MAX_LEVEL = 4

Examples:
    Optimize Modname for 6 iterations with a starting clock of 10.0 ns :
         ./synthopt.sh -m modname -c 10 -l 6


Regression Testing Script (runall.sh)
    Flags:
        -f test_progs/filename.(s^c) :
            runs a single assembly program (in simulation by default, see -s flag below)
        -d :
            runs diff check of writeback.out and program.out vs ground truth for single file run
        -r :
            runs every file that is in the regression list and not in the exclusion list
        -c :
            runs every c file that is not in the exclusion list
        -a :
            runs every assembly file that is not in the exclusion list
        -s :
            runs tests in synthesis instead of simulation

Examples:
    Regression Command: ./runall.sh -r
    Single File Syn with Diff Check:    ./runall.sh -f test_progs/alexnet.c -d -s

Custom Testcase:
    ./test_progs/right_triangles.c

    Consider the set of triangles OPQ with verticies O(0,0), P(x1,y1), Q(x2,y2),
    where 0 ≤ x1, y1, x2, y2 ≤ 50. How many of these triangles are right triangles?

    This test program computes this answer for 0 ≤ x1, y1, x2, y2 ≤ 3. It accomplishes
    this with four nexted for-loops; the three outermost for loops iterate from 0 
    to 3 without any additional control logic, and the innermost for loop performs 
    additional control logic that causes the loop to terminate at different times 
    depending on the state of the 3 outer loops. This program was written by Jack 
    Erhardt as a solution to problem 91 of Project Euler.

// ------------------------------------------------------------------------------------------------------

GENERAL INFO

Makefile Usage:

# to make an individual file for unsynthesized simulation on a particular testbench, run:
make sim TOP=module_name

# to make an individual file for synthesized simulation on a particular unsynthesized testbench, run:
make syn_single TOP=module_name

# to make the full pipeline and run unsynthesized simulation on all testbenches, run:
make

# to make the full pipeline and run synthesized simulation on all unsynthesized testbenches, run:
make syn

# generates line and toggle coverage reports with makefile
make cvg TOP_TB=testbench/RS/RS_tb.sv TOP_SYN=verilog/RS.sv

# generates line and toggle coverage reports without makefile
vcs -V -sverilog +vc -Mupdate -line -full64 +vcs+vcdpluson -debug_pp -cm line+tgl headers/include.svh verilog/ROB.sv testbench/ROB/ROB_tb.sv -o simv
module load vcs
./simv -cm line+tgl
urg -dir simv.vdb -format text

# has instructions for coloring output
http://www.asicguru.com/articles/verification/pass-fail-messages-in-testbench-with-color/156/

# runs a single test program and compares to ground truth (add -d to see diff report)
./runall.sh -f (test_prog filepath)

# for running ALL assembly or c tests
./runall.sh -a or -c

# for SYNTH
./runall.sh -s [-f or -a or -c]

LET'S GO GAMERS!!!!