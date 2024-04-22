.section .text
.align 4


beq x0, x0, first
beq x0, x0, back
j end
beq x0, x0, first

loop:
add x2, x5, x2
mul x6, x5, x6
beq x2, x0, end
blt x6, x0, cond1
addi x10, x10, 16
sw x2, 0(x10)
sh x2, 1(x10)
sb x2, 3(x10)
sw x2, 4(x10)
beq x6, x0, loop
lb x9, 3(x10)
lb x9, 2(x10)
lh x9, 1(x10)
sh x9, 4(x10)
beq x2, x0, end

cond1:
beq x0, x5, end
beq x0, x6, end
beq x0, x2, end
beq x0, x0, loop
j end

back:
j loop
end:
wfi #baboosh
first:
li x2, 0x4 # try increasing this to add more stress
li x5, -1
li x6, 0xdead0bad
li x10, 0x100
beq x0, x0, loop
wfi

