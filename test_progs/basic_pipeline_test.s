.section .text
.align 4
addi x1, zero, 1000
addi x2, x1, 1000
addi x2, x2, 1000
addi x3, x2, 1000
mul	x1,	x2,	x3 #96	60
nop
wfi