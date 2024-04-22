#!/bin/bash

OPT_FILE=clk_search/deprecated_clock_periods.log
rm -f $OPT_FILE
BSO_LOGS=clk_search/*.log
for file in ${BSO_LOGS[@]}; do
    grep "BSO Found" $file >> $OPT_FILE
done