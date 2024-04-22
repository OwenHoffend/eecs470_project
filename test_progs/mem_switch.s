    li sp, 0 # Memory pointer
    li x1, 0 # Loop counter
loop:
    li a0, 0 # Branch taken condition
    li a1, 1 
    li a2, 0xa1a1 # data
    bne a1, a2, skip # Works best with GSHARE disabled 
                     # (needs misprediction to demonstrate failure mode)
    sw a2, 80(sp) # Store to DMemory space, should squash
skip:
    lw a2, 0(sp) # read from (non-zero) IMemory space
    addi x1, x1, 1
    addi sp, sp, 8
    slti x3, x1, 4
    bne x3, x0, loop
    wfi