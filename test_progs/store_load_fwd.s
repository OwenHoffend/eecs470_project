#Hammer the LSQ with weird combinations of byte-level stores and loads

.section .text
.align 4

#sh, offset of 2 and 0
li sp, 1024
li x5, 0x5
li x1, 0x0000dead
li x2, 0x0000beef

loop1:
    sh x1, 2(sp)
    sh x2, 0(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lw x3, 0(sp)

    sh x1, 2(sp)
    sh x2, 0(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lh x3, 0(sp)

    sh x1, 2(sp)
    sh x2, 0(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lb x3, 0(sp)

    addi x5, x5, -1
    addi sp, sp, -8
    bne x5, x0, loop1

#sh, offset of 1 and 3
li sp, 1024
li x5, 0x5
li x1, 0x0000dead
li x2, 0x0000beef

loop2:
    sh x1, 1(sp)
    sh x2, 3(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lw x3, 0(sp)

    sh x1, 1(sp)
    sh x2, 3(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lh x3, 0(sp)

    sh x1, 1(sp)
    sh x2, 3(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lb x3, 0(sp)

    addi x5, x5, -1
    addi sp, sp, -8
    bne x5, x0, loop2

#sb offset of 2 and 0
li sp, 1024
li x5, 0x5
li x1, 0x0000dead
li x2, 0x0000beef

loop3:
    sb x1, 2(sp)
    sb x2, 0(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lw x3, 0(sp)

    sb x1, 2(sp)
    sb x2, 0(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lh x3, 0(sp)

    sb x1, 2(sp)
    sb x2, 0(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lb x3, 0(sp)

    addi x5, x5, -1
    addi sp, sp, -8
    bne x5, x0, loop3

##sb offset of 1 and 3
li sp, 1024
li x5, 0x5
li x1, 0x0000dead
li x2, 0x0000beef

loop4:
    sb x1, 1(sp)
    sb x2, 3(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lw x3, 0(sp)

    sb x1, 1(sp)
    sb x2, 3(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lh x3, 0(sp)

    sb x1, 1(sp)
    sb x2, 3(sp)
    mul x6, x1, x1
    mul x6, x6, x6
    lb x3, 0(sp)

    addi x5, x5, -1
    addi sp, sp, -8
    bne x5, x0, loop4
wfi