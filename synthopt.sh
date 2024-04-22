#!/bin/bash

function opt_mod(){
    echo >> $OPT_SYN_LOG
    echo "*************** COMMENCE NEW RUN **********">> $OPT_SYN_LOG
    echo >> $OPT_SYN_LOG
    make synth/$MOD_NAME.vg CLOCK_PERIOD=$CLK | tee -a $OPT_SYN_LOG
}

# need to detect either of the following
# slack (VIOLATED: increase significant digits)  0.00
# slack (VIOLATED)
function check_slack(){
    SLACK_CHECK=$(grep "slack (VIOLATED" ./synth/$MOD_NAME.rep)
    if [ "$SLACK_CHECK" != "" ] ; then

        if [ $LEVEL -eq $MAX_LEVEL ] ; then
            if [ $(echo "$OPT_CLOCK<1000" | bc) -eq 0 ] ; then
                echo "BSO Failed to Find a Sufficient Clock Period for $MOD_NAME. Start with a higher initial value" >> $BSO_FILE
            else
                echo "BSO Found $OPT_CLOCK for $MOD_NAME" >> $BSO_FILE
            fi
            break
        fi

        echo Optimization Level: $LEVEL >> $BSO_FILE
        echo Current Clock Period is $CLK >> $BSO_FILE
        CLK=$(echo "$CLK" + $INC | bc)
        echo New Clock Period is $CLK >> $BSO_FILE
                
        echo >> $BSO_FILE
    
    else

        OPT_CLOCK=$CLK
        if [ $LEVEL -eq $MAX_LEVEL ] ; then
            if [ $(echo "$OPT_CLOCK<1000" | bc) -eq 0 ] ; then
                echo "BSO Failed to Find a Sufficient Clock Period for $MOD_NAME. Start with a higher initial value" >> $BSO_FILE
            else
                echo "BSO Found $OPT_CLOCK for $MOD_NAME" >> $BSO_FILE
            fi
            break
        fi

        echo Optimization Level: $LEVEL >> $BSO_FILE
        echo Current Clock Period is $CLK >> $BSO_FILE
        CLK=$(echo "$CLK" - $INC | bc)
        echo New Clock Period is $CLK >> $BSO_FILE

        echo >> $BSO_FILE
    fi

    # change increment and level
    LEVEL=$((LEVEL+1))
    INC=$(echo ${INCREMENTS[$LEVEL]})

}


# Change the increments as needed
INCREMENTS=(4 2 1 0.5 0.25)

#Parse command line options
if [ $# -eq 0 ]; then #Just exit if no action is specified
    echo "No options specified. Use -m to specify the module name to optimize, -c for initial clock period [OPTIONAL], -l for (N+1) iterations (input N here)"
    exit
fi
# -gt means greater than
while [[ $# -gt 0 ]]; do
    arg="$1"
    case $arg in
        -m) #Name of module to optimize
        MOD_NAME="$2"
        shift
        shift
        ;;
        -c) #Best clock period of lower module
        CLK_IN="$2"
        shift
        shift
        ;;
        -l) #max_level
        MAX_LEVEL="$2"
        shift
        shift
        ;;
        *) #Bad argument
        echo "Invalid option: $arg. Use -m to specify the module name to optimize"
        exit
        ;;
    esac
done

# ifdef CLK, export it
# ifndef CLK, set it to 0.5

if [[ -z "${CLK_IN}" ]] ; then
  export CLK=8.0
else
  export CLK="${CLK_IN}"
fi

if [[ -z "${MAX_LEVEL}" ]] ; then
  MAX_LEVEL=4
fi

mkdir -p clk_search
mkdir -p clk_search/synth
rm -f clk_search/backup/*

BSO_DIR=clk_search
SYNTH_LOG_DIR=clk_search/synth

BSO_FILE=$BSO_DIR/$(echo $MOD_NAME).log

rm -f $SYNTH_LOG_DIR/$(echo $MOD_NAME)_synth*
OPT_SYN_LOG=$SYNTH_LOG_DIR/$(echo $MOD_NAME)_synth.log

echo Initial Clock Period: $CLK > $BSO_FILE
echo >> $BSO_FILE

LEVEL=0
INC=${INCREMENTS[$LEVEL]}
OPT_CLOCK=1000

echo "Optimizing module $MOD_NAME.sv" >> $BSO_FILE
echo >> $BSO_FILE
while true; do
    rm -f ./synth/$MOD_NAME.vg #Remove the existing copy of the module
    opt_mod #Optimize the specified module
    check_slack
done

if [ $(echo "$OPT_CLOCK<1000" | bc) -eq 0 ] ; then
    echo "BSO Failed to Find a Sufficient Clock Period for $MOD_NAME. Start with a higher initial value"
else
    echo "BSO Found $OPT_CLOCK for $MOD_NAME"
    rm -f ./synth/$MOD_NAME.vg #Remove the existing copy of the module
    CLK=$OPT_CLOCK
    opt_mod
fi

./get_BSO_clk.sh
