#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <sys/prctl.h>

#include "ntt_defs.h"

#ifndef PR_SVE_SET_VL
#define PR_SVE_SET_VL 50
#endif

void ntt_ref(int16_t r[256]);
void ntt_kyber_sve2_v128(int16_t a[256]);
int16_t creduce(int32_t x);

static uint64_t rng = 0xdeadbeefcafef00dULL;

static uint16_t rnd(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return (uint16_t)rng;
}

int main(void)
{
    /* Force SVE VL = 128 bits */
    if (prctl(PR_SVE_SET_VL, 16) < 0) {
        perror("prctl(PR_SVE_SET_VL)");
        return 2;
    }

    unsigned long vl;
    __asm__ volatile("rdvl %0, #1" : "=r"(vl));

    printf("SVE VL = %lu bytes (%lu bits)\n", vl, vl * 8);

    if (vl != 16) {
        printf("ERROR: expected VL=128\n");
        return 2;
    }

    int peak = 0;
    int fails = 0;

    for (long t = 0; t < 200000; t++) {
        int16_t in[256];
        int16_t ref[256];
        int16_t sve[256];

        /* Random input: [0, q-1] */
        for (int i = 0; i < 256; i++)
            in[i] = (int16_t)(rnd() % KYBER_Q);

        memcpy(ref, in, sizeof(ref));
        memcpy(sve, in, sizeof(sve));

        /* Reference NTT */
        ntt_ref(ref);

        /* SVE2 VL=128 NTT */
        ntt_kyber_sve2_v128(sve);

        /* Compare modulo q + track raw range */
        for (int i = 0; i < 256; i++) {
            int v = sve[i];

            int abs_v = v;
            if (abs_v < 0)
                abs_v = -abs_v;

            if (abs_v > peak)
                peak = abs_v;

            if (creduce(sve[i]) != ref[i]) {
                fails++;

                if (fails <= 3) {
                    printf(
                        "FAIL t=%ld i=%d ref=%d raw=%d red=%d\n",
                        t,
                        i,
                        ref[i],
                        sve[i],
                        creduce(sve[i])
                    );
                }
            }
        }
    }

    printf(
        "200000 trials: peak_maxabs=%d  margin=%d  fails=%d\n",
        peak,
        32767 - peak,
        fails
    );

    return fails ? 1 : 0;
}