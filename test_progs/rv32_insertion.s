/*
   GROUP 17
	TEST PROGRAM: insertion sort

	long a[] = { 3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3 };

  int i,j,temp;
  for(i=1;i<16;++i) {
    temp = a[i];
    j = i;
    while(1) {
      if(a[j-1] > temp)
        a[j] = a[j-1];
      else
        break; 
      --j;
      if(j == 0) 
        break;      
    }
    a[j] = temp;
  }  
  
  modified from sort.s
*/

 j	start
 nop 
  .dword 3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3 # Load initial data
  .align 4                                              # ?
start:	
	li	x6, 1                                           # x6 -> i
	li	x10, 16                                         # x10 -> ptr
iloop:
	lw	x4,  0(x10)                                     # x4 -> temp, x4 = a[i]
	mv	x7,	x6 #j = i                                   # x7 -> j, j = i
	mv	x20,	x10 #index j                            # x20 -> ptr of j loop
	addi	x19,	x20,	-8 #index j-1               # x19 -> j-1
jloop:
	lw	x15,  0(x19)                                    # x15 -> a[j-1]
	lw	x16,  0(x20)                                    # x16 -> a[j]

	sltu	x12,	x15,	x4 #                        # check if a[j-1] > temp
	bne	x12,	x0,	ifinish #                           # branch
  
	sw	x15,  0(x20)                                    # a[j] = a[j-1]
  
	addi	x19,	x19,	-8 #index to a[j-1]         # j-1ptr--
	addi	x20,	x20,	-8 #index to a[j]           # jptr--
  
	addi	x7,	x7,	-1 #j--                             # j--
	beq	x7,	x0,	ifinish #                               # if(j==0) break
  j jloop                                               # loop
  
ifinish:
	sw	x4,  0(x20)                                     # a[j] = temp
	addi	x10,	x10,	8 #                         # iptr++
	addi	x6,	x6,	1 #increment and check i loop       # i++
  
	sltu	x11,	x6,	16 #                            # check if i<16
	bne	x11,	x0,	iloop #                             # repeat loop

	wfi

  
