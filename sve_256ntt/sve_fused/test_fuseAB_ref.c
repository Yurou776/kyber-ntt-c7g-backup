#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "ntt_defs.h"

void ntt_ref(int16_t r[256]);
void ntt_kyber_sve_fuseAB(int16_t a[256]);

int16_t creduce(int32_t x);

static void print_first_diff(
    const char *name,
    int16_t ref[256],
    int16_t sve[256])
{
    for (int i = 0; i < 256; i++) {
        int r = creduce(ref[i]);
        int s = creduce(sve[i]);

        if (r != s) {
            printf("\n[%s] FIRST MISMATCH\n", name);
            printf("index = %d\n", i);
            printf("ref   = %d\n", r);
            printf("sve   = %d\n", s);
            printf("raw   = %d\n", sve[i]);

            return;
        }
    }

    printf("[%s] PASS\n", name);
}

static void run_case(const char *name, int16_t in[256])
{
    int16_t ref[256];
    int16_t sve[256];

    memcpy(ref, in, sizeof(ref));
    memcpy(sve, in, sizeof(sve));

    ntt_ref(ref);
    ntt_kyber_sve_fuseAB(sve);

    print_first_diff(name, ref, sve);
}

int main(void)
{
    int16_t in[256];

    /* impulse */
    memset(in, 0, sizeof(in));
    in[0] = 1;
    run_case("impulse", in);

    /* all ones */
    for (int i = 0; i < 256; i++)
        in[i] = 1;
    run_case("all_ones", in);

    /* all q-1 */
    for (int i = 0; i < 256; i++)
        in[i] = KYBER_Q - 1;
    run_case("all_q_minus_1", in);

    /* sequence */
    for (int i = 0; i < 256; i++)
        in[i] = i + 1;
    run_case("sequence", in);

    /* alternating */
    for (int i = 0; i < 256; i++)
        in[i] = (i & 1) ? KYBER_Q - 1 : 1;
    run_case("alternating", in);

    /* sparse */
    memset(in, 0, sizeof(in));
    in[0]   = 1;
    in[1]   = 2;
    in[2]   = 3;
    in[10]  = 11;
    in[64]  = 65;
    in[128] = 129;
    in[200] = 201;
    in[255] = 256;
    run_case("sparse", in);

    return 0;
}