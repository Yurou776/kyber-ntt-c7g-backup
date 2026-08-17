#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define Q 3329
#define N 256

void ntt_kyber_sve_fuseAB(int16_t a[256]);

/*
 * 把 SVE output 轉成 [0, Q-1]
 */
static int reduce_mod_q(int x)
{
    x %= Q;
    if (x < 0)
        x += Q;
    return x;
}

static void print_array(const int16_t a[256])
{
    for (int i = 0; i < N; i++) {
        printf("%d", reduce_mod_q(a[i]));

        if (i != N - 1)
            printf(" ");
    }
    printf("\n");
}

static void run_test(const char *name, const int16_t input[256])
{
    int16_t a[256];

    memcpy(a, input, sizeof(a));

    printf("\n");
    printf("======================================================================\n");
    printf("TEST: %s\n", name);
    printf("======================================================================\n");

    printf("\nInput:\n");
    print_array(a);

    ntt_kyber_sve_fuseAB(a);

    printf("\nOutput:\n");
    print_array(a);
}

int main(void)
{
    int16_t in[256];

    /*
     * ------------------------------------------------------------
     * 1. impulse
     * [1, 0, 0, ..., 0]
     * ------------------------------------------------------------
     */
    memset(in, 0, sizeof(in));
    in[0] = 1;
    run_test("impulse", in);


    /*
     * ------------------------------------------------------------
     * 2. all ones
     * [1, 1, 1, ..., 1]
     * ------------------------------------------------------------
     */
    for (int i = 0; i < N; i++)
        in[i] = 1;

    run_test("all_ones", in);


    /*
     * ------------------------------------------------------------
     * 3. all q-1
     * [3328, 3328, ..., 3328]
     * ------------------------------------------------------------
     */
    for (int i = 0; i < N; i++)
        in[i] = Q - 1;

    run_test("all_q_minus_1", in);


    /*
     * ------------------------------------------------------------
     * 4. sequence
     * [1, 2, 3, ..., 256]
     * ------------------------------------------------------------
     */
    for (int i = 0; i < N; i++)
        in[i] = i + 1;

    run_test("sequence", in);


    /*
     * ------------------------------------------------------------
     * 5. alternating
     * [1, 3328, 1, 3328, ...]
     * ------------------------------------------------------------
     */
    for (int i = 0; i < N; i++)
        in[i] = (i & 1) ? (Q - 1) : 1;

    run_test("alternating", in);


    /*
     * ------------------------------------------------------------
     * 6. sparse
     * [1,2,3,0,...,11,...,65,...,129,...,201,...,256]
     * ------------------------------------------------------------
     */
    memset(in, 0, sizeof(in));

    in[0]   = 1;
    in[1]   = 2;
    in[2]   = 3;
    in[10]  = 11;
    in[64]  = 65;
    in[128] = 129;
    in[200] = 201;
    in[255] = 256;

    run_test("sparse", in);


    return 0;
}