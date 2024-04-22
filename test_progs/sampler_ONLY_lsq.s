.section .text
.align 4
## Memory tests ##
	li sp, 2048
	li t0, 0x2
	li t1, 255
    sb t1, 0(sp) 
	lb t2, 0(sp)
	bge t2, t1, FAIL
	lbu t2, 0(sp)
	bne t1,t2, FAIL	
	ori t1, t1, -1 
	lui t1, 0xf	
	sh t1, 0(sp)
	lh t2, 0(sp)
	bge t2, t1, FAIL
	lhu t2, 0(sp)
	bne t2, t2, FAIL	
	ori t1, t1, -1 
	lui t1, 0x7ffff
	sw t1, 0(sp)
	lw t2, 0(sp)
	bne t1, t2, FAIL
    wfi
FAIL: 
	wfi