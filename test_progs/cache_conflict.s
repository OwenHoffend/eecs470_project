/*
    cache_conflict.s:   Create a scenario where a load exists in execute
                        on the same cycle that a store misses in retirement,
                        where the load cannot forward it's data to the store
                        (e.g. the store and load operate on different addresses).
                        This should cause the load to not properly send it's
                        command and address to cache, since cache will be
                        servicing the store instruction on this cycle.
*/

.section .text
.align 4
li a1, 0xA1A1
li a2, 0x2B2B
li sp, 2048
sw a1, 0(sp) # Create non-zero data for loads to read
sw a2, 8(sp) # Store miss without evicting cache line
lw a3, 0(sp) # Generate a few non-forwarding load requests
lw a4, 0(sp) # One of these should attempt to send a cache
             # command on the same cycle as sw a2, 8(sp) is
             # getting it's cache hit due to bugs in the
             # EX / IS load stall signal
wfi