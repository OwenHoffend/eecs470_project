LEAF_MODS=(
    # "PHT" # DONE
    # "GBP" # DONE
    # "BTB" # DONE
    # "fetch" # DONE
    
    # "CAM" # Not individually synthesized
    # "FIFO" # DONE
    # "RAT" # DONE
    # "btag_tracker" # DONE
    # "decoder" # DONE
    # "dispatch" # DONE
    # "BRAT" # DONE
    # "ROB" # DONE

    # "SQ" # Not working right now
    
    "regfile_et"
    "rot_pselect_RS"
    "onehot_to_binary_RS"
    "RS_ET"
    "issue_et"

    "EX"

    "CDB"

    # "cachemem" # DONE
    # "icache" # DONE
    # "dcache" # DONE
    # "cache" # DONE

    # "pipeline" # Not working right now
)

TEST_DIR=verilog
CACHE_TEST_DIR=cache

for file in ${LEAF_MODS[@]}; do
    ./synthopt.sh -m $file
done