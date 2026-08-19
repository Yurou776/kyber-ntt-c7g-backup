#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <sys/prctl.h>

#include "ntt_defs.h"

#ifndef PR_SVE_SET_VL
#define PR_SVE_SET_VL 50
#endif

#define RANDOM_Q_TRIALS      200000
#define RANDOM_SIGNED_TRIALS 200000

void ntt_ref(int16_t r[256]);
void ntt_kyber_sve2_v128(int16_t r[256]);
int16_t creduce(int32_t x);

/* --------------------------------------------------------------------------
 * Deterministic xorshift RNG
 * -------------------------------------------------------------------------- */

static uint64_t rng = 0xdeadbeefcafef00dULL;

static uint16_t rnd16(void)
{
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return (uint16_t)rng;
}

/* --------------------------------------------------------------------------
 * Compare one test vector
 * -------------------------------------------------------------------------- */

static int test_vector(
    const char *name,
    int trial,
    const int16_t in[256],
    int *peak_maxabs)
{
    int16_t ref[256];
    int16_t sve[256];

    memcpy(ref, in, sizeof(ref));
    memcpy(sve, in, sizeof(sve));

    /* Reference NTT */
    ntt_ref(ref);

    /* Barrett SVE2 NTT */
    ntt_kyber_sve2_v128(sve);

    for (int i = 0; i < 256; i++) {

        int v = sve[i];

        int abs_v = v;
        if (abs_v < 0)
            abs_v = -abs_v;

        if (abs_v > *peak_maxabs)
            *peak_maxabs = abs_v;

        /*
         * Compare modulo q.
         *
         * The reference NTT and assembly may use different
         * representatives, so reduce both before comparison.
         */
        int ref_red = creduce(ref[i]);
        int sve_red = creduce(sve[i]);

        if (ref_red != sve_red) {
            printf(
                "FAIL [%s] trial=%d index=%d "
                "ref=%d red=%d  sve=%d red=%d\n",
                name,
                trial,
                i,
                ref[i],
                ref_red,
                sve[i],
                sve_red
            );

            return 1;
        }
    }

    return 0;
}

/* --------------------------------------------------------------------------
 * Fixed pattern tests
 * -------------------------------------------------------------------------- */

static int run_fixed_tests(int *peak_maxabs)
{
    int16_t a[256];

    printf("\n=== Fixed / boundary tests ===\n");

    /* all zero */
    memset(a, 0, sizeof(a));

    if (test_vector("all-zero", 0, a, peak_maxabs))
        return 1;

    printf("PASS all-zero\n");

    /* all one */
    for (int i = 0; i < 256; i++)
        a[i] = 1;

    if (test_vector("all-one", 0, a, peak_maxabs))
        return 1;

    printf("PASS all-one\n");

    /* all q-1 */
    for (int i = 0; i < 256; i++)
        a[i] = KYBER_Q - 1;

    if (test_vector("all-q-1", 0, a, peak_maxabs))
        return 1;

    printf("PASS all-q-1\n");

    /* alternating 0 / q-1 */
    for (int i = 0; i < 256; i++)
        a[i] = (i & 1) ? (KYBER_Q - 1) : 0;

    if (test_vector("alternating-0-q-1", 0, a, peak_maxabs))
        return 1;

    printf("PASS alternating-0-q-1\n");

    /* alternating 1 / q-1 */
    for (int i = 0; i < 256; i++)
        a[i] = (i & 1) ? (KYBER_Q - 1) : 1;

    if (test_vector("alternating-1-q-1", 0, a, peak_maxabs))
        return 1;

    printf("PASS alternating-1-q-1\n");


    /*
     * Repeating important boundary values.
     *
     * These exercise positive / negative representatives
     * around q and around int16 boundaries.
     */
    static const int16_t boundary[] = {
    0,
    1,
    2,
    -1,
    -2,
    KYBER_Q - 2,
    KYBER_Q - 1,
    1664,
    1665
};

    int nboundary =
        (int)(sizeof(boundary) / sizeof(boundary[0]));

    for (int i = 0; i < 256; i++)
        a[i] = boundary[i % nboundary];

    if (test_vector("boundary-mix", 0, a, peak_maxabs))
        return 1;

    printf("PASS boundary-mix\n");

    return 0;
}

/* --------------------------------------------------------------------------
 * Random [0, q-1]
 * -------------------------------------------------------------------------- */

static int run_random_q(int *peak_maxabs)
{
    int16_t a[256];

    printf(
        "\n=== Random [0, q-1] : %d trials ===\n",
        RANDOM_Q_TRIALS
    );

    for (int t = 0; t < RANDOM_Q_TRIALS; t++) {

        for (int i = 0; i < 256; i++)
            a[i] = (int16_t)(rnd16() % KYBER_Q);

        if (test_vector("random-q", t, a, peak_maxabs))
            return 1;

        if ((t + 1) % 50000 == 0)
            printf("  %d / %d passed\n",
                   t + 1,
                   RANDOM_Q_TRIALS);
    }

    printf("PASS random [0,q-1]\n");

    return 0;
}

/* --------------------------------------------------------------------------
 * Random full signed int16 range
 * -------------------------------------------------------------------------- */

static int run_random_signed(int *peak_maxabs)
{
    int16_t a[256];

    printf(
        "\n=== Random signed range [-16000,16000] : %d trials ===\n",
        RANDOM_SIGNED_TRIALS
    );

    for (int t = 0; t < RANDOM_SIGNED_TRIALS; t++) {

        for (int i = 0; i < 256; i++) {
            int v = (int)(rnd16() % 32001) - 16000;
            a[i] = (int16_t)v;
        }

        if (test_vector("random-signed", t, a, peak_maxabs))
            return 1;

        if ((t + 1) % 50000 == 0)
            printf("  %d / %d passed\n",
                   t + 1,
                   RANDOM_SIGNED_TRIALS);
    }

    printf("PASS random signed range [-16000,16000]\n");

    return 0;
}

/* --------------------------------------------------------------------------
 * Main
 * -------------------------------------------------------------------------- */

int main(void)
{
    /*
     * Force SVE VL = 128 bits = 16 bytes.
     */
    if (prctl(PR_SVE_SET_VL, 16) < 0) {
        perror("prctl(PR_SVE_SET_VL)");
        return 2;
    }

    unsigned long vl;

    __asm__ volatile(
        "rdvl %0, #1"
        : "=r"(vl)
    );

    printf(
        "SVE VL = %lu bytes (%lu bits)\n",
        vl,
        vl * 8
    );

    if (vl != 16) {
        printf("ERROR: expected VL=128\n");
        return 2;
    }

    int peak_maxabs = 0;

    /* 1. Fixed / boundary */
    if (run_fixed_tests(&peak_maxabs))
        return 1;

    /* 2. Normal Kyber input range */
    if (run_random_q(&peak_maxabs))
        return 1;

    /* 3. Full signed int16 stress */
    if (run_random_signed(&peak_maxabs))
        return 1;

    printf("\n========================================\n");
    printf("ALL CORRECTNESS TESTS PASSED\n");
    printf("peak_maxabs = %d\n", peak_maxabs);
    printf("int16 margin = %d\n", 32767 - peak_maxabs);
    printf("========================================\n");

    return 0;
}
