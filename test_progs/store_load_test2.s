.section .text
.align 4
data = 0x1000
    li    x4, data                    # Pointer i-2
    li    x5, 0x1008                  # Pointer i-1
    li    x6, 0x1010                  # Pointer i
    li    x10, 2                      # Initial value
    li    x2, 3                       # Initial value
    sw    x2, 0(x4)                   # Store initial value
    sw    x2, 0(x5)                   # Store initial value
    lw    x2, 0(x4)                   # x2 = output[i-2]
    lw    x3, 0(x5)                   # x3 = output[i-1]
    wfi