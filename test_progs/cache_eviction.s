.section .text
.align 4 
li a1, 41377 # 0xA1A1
li a3, 11051 # 0x2B2B
li sp, 2048
sw a1, 0(sp) # Load in 0xA1A1 to mem addr 2048
li sp, 1920
sw a3, 0(sp) # Load in 0x2B2B to mem addr 1920
             # Force eviction of addr 2048 from cache
wfi