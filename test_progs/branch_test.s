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
beq x6, x6, loop

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
li x2, 0x69
li x5, -1
li x6, 0xdead0bad
beq x0, x0, loop
wfi

