#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "params.h"

void pqcrystals_kyber768_ref_ntt(int16_t r[256]);
void ntt_kyber_sve_bunroll_a4(int16_t a[256]);

static uint64_t rng = 0x123456789abcdef0ULL;

static uint16_t rnd(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return (uint16_t)rng;
}

static int run_case(const char *name, int16_t in[256])
{
    int16_t ref[256];
    int16_t sve[256];

    memcpy(ref, in, sizeof(ref));
    memcpy(sve, in, sizeof(sve));

    /* Official Kyber reference */
    pqcrystals_kyber768_ref_ntt(ref);

    /* Your SVE implementation */
    ntt_kyber_sve_bunroll_a4(sve);

    for (int i = 0; i < 256; i++) {
        /*
         * Compare modulo q because SVE may leave
         * a different representative of the same residue.
         */
        int r = ref[i] % KYBER_Q;
        int s = sve[i] % KYBER_Q;

        if (r < 0) r += KYBER_Q;
        if (s < 0) s += KYBER_Q;

        if (r != s) {
            printf("[FAIL] %s\n", name);
            printf("  idx = %d\n", i);
            printf("  official = %d\n", r);
            printf("  sve raw  = %d\n", sve[i]);
            printf("  sve mod  = %d\n", s);
            return 1;
        }
    }

    printf("[PASS] %s\n", name);
    return 0;
}

int main(void)
{
    int fails = 0;
    int16_t in[256];

    memset(in, 0, sizeof(in));
    fails += run_case("zeros", in);

    memset(in, 0, sizeof(in));
    in[0] = 1;
    fails += run_case("impulse", in);

    for (int i = 0; i < 256; i++)
        in[i] = 1;
    fails += run_case("all_ones", in);

    for (int i = 0; i < 256; i++)
        in[i] = KYBER_Q - 1;
    fails += run_case("all_q_minus_1", in);

    for (int i = 0; i < 256; i++)
        in[i] = i % KYBER_Q;
    fails += run_case("sequence", in);

    for (int i = 0; i < 256; i++)
        in[i] = (i & 1) ? KYBER_Q - 1 : 0;
    fails += run_case("alternating", in);

    for (int t = 0; t < 1000; t++) {
        for (int i = 0; i < 256; i++)
            in[i] = rnd() % KYBER_Q;

        char name[32];
        snprintf(name, sizeof(name), "random_%d", t);

        if (run_case(name, in)) {
            fails++;
            break;
        }
    }

    printf("\nRESULT: %s\n",
           fails ? "FAIL" : "ALL PASS");

    return fails ? 1 : 0;
}
