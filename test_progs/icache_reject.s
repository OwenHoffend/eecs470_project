.section .text
.align 4 
li sp, 2048
li a1, 41377 # 0xA1A1
sw a1, 0(sp)   # 2048
sw a1, 8(sp)   # 2056
sw a1, 16(sp)  # 2064
sw a1, 24(sp)  # 2072
sw a1, 32(sp)  # 2080
sw a1, 40(sp)  # 2088
sw a1, 48(sp)  # 2096
sw a1, 56(sp)  # 2104
sw a1, 64(sp)  # 2112
sw a1, 72(sp)  # 2120
sw a1, 80(sp)  # 2128
sw a1, 88(sp)  # 2136
sw a1, 96(sp)  # 2144
sw a1, 104(sp) # 2152
sw a1, 112(sp) # 2160
sw a1, 120(sp) # 2168
wfi