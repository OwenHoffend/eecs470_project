

int main () {
    const int MAGIC_NUMBER = 10;
    int big_data[MAGIC_NUMBER];
    int j, k, l, baddie = 0;
    for (int i = 0; i < MAGIC_NUMBER; i++) {
        if (i & 1 == 0) { // if even, try to slam the RS with dependent and independent multiplies, and then sneak a really important branch in the middle that will get starved
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            if (i & 0x1100 == 0) // a pretty independent test condition for a branch break
                break;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
            j = i * i;
            baddie = i * i;
            k = j * i;
            baddie = i * i;
            l = k * i;
            baddie = i * i;
    } else { // give early tag a big air bonus
        j = i;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        j++;
        if (j & 1 == 0)
            j++;
        else
            j--;
    }
    big_data[i] = j; // lots of stores, not a lot of loads
}}