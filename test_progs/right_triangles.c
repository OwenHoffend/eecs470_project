/////////////////////////////////////////////////
// right_triangles.c
// Consider the set of triangles OPQ with verticies O(0,0), P(x1,y1), Q(x2,y2),
// where 0 ≤ x1, y1, x2, y2 ≤ 50. How many of these triangles are right triangles?
// - Jack Erhardt, 12/2020
/////////////////////////////////////////////////

#include <stdio.h>
#include <stdlib.h>

#define MAXCOORD 3
#define MAX(a,b,c) (((a>b)&(a>c))?a:(b>c)?b:c)

#ifndef DEBUG
extern void exit();
#endif

int main() {
    int count = 0;
    int xP, yP, xQ, yQ;
    int xPyQ, xQyP;
    for(xP = 0; xP <= MAXCOORD; xP++) {
		for(yP = 0; yP <= MAXCOORD; yP++) {
			for(xQ = 0; xQ <= MAXCOORD; xQ++) {
				for(yQ = 0; (yQ*xP < yP*xQ) & (yQ < MAXCOORD+1); yQ++) {
					int l1 = (xP-xQ)*(xP-xQ)+(yP-yQ)*(yP-yQ);
					int l2 = (   xP)*(   xP)+(   yP)*(   yP);
					int l3 = (   xQ)*(   xQ)+(   yQ)*(   yQ);
					count+=((l1+l2+l3-2*MAX(l1,l2,l3)==0)&(l1!=0)&(l2!=0)&(l3!=0))?1:0;
				}
			}
		}
	}

    return 0;
}