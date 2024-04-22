.section .text
.align 4
li a1, 123154
li sp, 2048

# W --> W (should forward)
sw a1, 0(sp)
lw a2, 0(sp)

# W --> H (should forward)
sw a1, 4(sp)
lh a2, 4(sp)

# W --> B (should forward)
sw a1, 8(sp)
lb a2, 8(sp)

# H --> W (should NOT forward)
sh a1, 12(sp)
lw a2, 12(sp)

# H --> H (should forward)
sh a1, 16(sp)
lh a2, 16(sp)

# H --> B (should forward)
sh a1, 20(sp)
lb a2, 20(sp)

# B --> W (should NOT forward)
sb a1, 24(sp)
lw a2, 24(sp)

# B --> H (should NOT forward)
sb a1, 28(sp)
lh a2, 28(sp)

# B --> B (should forward)
sb a1, 32(sp)
lb a2, 32(sp)

# B --> W, with prior store
li a3, 111111
li a5, 0xbad
sw a3, 36(sp)
sb a1, 36(sp)
lw a2, 36(sp)

# B --> W, with prior store, force partial forward
li a3, 0xdeadbeef #Background
li a1, 0xf00df00d #Foreground
li sp, 2048
sw a3, 40(sp)
addi sp, sp, 0x80
sw a5, 40(sp)
li sp, 2048 
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
sb a1, 40(sp)
lw a2, 40(sp) #Should be 0xdeadbe0d
add a4, a2, a2 #Should be .... something
sw a4, 40(sp)
wfi