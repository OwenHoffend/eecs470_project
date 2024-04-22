.section .text
.align 4
    nop
    li sp, 2048
    jal x1, test
    wfi
test:
    li a0, 100
    ret