#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "ntt_defs.h"

void ntt_ref(int16_t r[256]);
void ntt_kyber_sve_fuseAB(int16_t a[256]);
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
    int peak = 0;
    int fails = 0;

    for (long t = 0; t < 200000; t++) {

        int16_t in[256];
        int16_t ref[256];
        int16_t sve[256];

        for (int i = 0; i < 256; i++)
            in[i] = (int16_t)(rnd() % KYBER_Q);

        memcpy(ref, in, sizeof(ref));
        memcpy(sve, in, sizeof(sve));

        ntt_ref(ref);
        ntt_kyber_sve_fuseAB(sve);

        for (int i = 0; i < 256; i++) {

            int v = sve[i];
            if (v < 0)
                v = -v;

            if (v > peak)
                peak = v;

            if (creduce(sve[i]) != ref[i]) {
                fails++;

                if (fails <= 5) {
                    printf(
                        "FAIL t=%ld i=%d ref=%d raw=%d reduced=%d\n",
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
        "\n200000 trials: peak_maxabs=%d margin=%d fails=%d\n",
        peak,
        32767 - peak,
        fails
    );

    return fails ? 1 : 0;
}