/*
 * Copyright (c) 2024-2025 The mlkem-native project authors
 * SPDX-License-Identifier: Apache-2.0
 */

#include <inttypes.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/prctl.h>

#include "hal.h"

#ifndef PR_SVE_SET_VL
#define PR_SVE_SET_VL 50
#endif

#define NWARMUP 50
#define NITERATIONS 300
#define NTESTS 500

void ntt_kyber_sve2_v128(int16_t a[256]);

static int cmp_uint64_t(const void *a, const void *b)
{
    uint64_t ua = *((const uint64_t *)a);
    uint64_t ub = *((const uint64_t *)b);

    if (ua < ub)
        return -1;
    if (ua > ub)
        return 1;
    return 0;
}

static void print_median(const char *txt, uint64_t cyc[NTESTS])
{
    printf("%10s cycles = %" PRIu64 "\n",
           txt,
           cyc[NTESTS >> 1] / NITERATIONS);
}

static int percentiles[] = {
    1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 99
};

static void print_percentile_legend(void)
{
    unsigned i;

    printf("%21s", "percentile");

    for (i = 0;
         i < sizeof(percentiles) / sizeof(percentiles[0]);
         i++)
    {
        printf("%7d", percentiles[i]);
    }

    printf("\n");
}

static void print_percentiles(const char *txt, uint64_t cyc[NTESTS])
{
    unsigned i;

    printf("%10s percentiles:", txt);

    for (i = 0;
         i < sizeof(percentiles) / sizeof(percentiles[0]);
         i++)
    {
        printf(
            "%7" PRIu64,
            cyc[NTESTS * percentiles[i] / 100] / NITERATIONS
        );
    }

    printf("\n");
}

static int bench(void)
{
    int16_t a[256] = {0};

    int i, j;

    uint64_t t0, t1;
    uint64_t cycles_ntt[NTESTS];

    for (i = 0; i < NTESTS; i++)
    {
        /*
         * Warm-up
         */
        for (j = 0; j < NWARMUP; j++)
        {
            ntt_kyber_sve2_v128(a);
        }

        /*
         * Timed iterations
         */
        t0 = get_cyclecounter();

        for (j = 0; j < NITERATIONS; j++)
        {
            ntt_kyber_sve2_v128(a);
        }

        t1 = get_cyclecounter();

        cycles_ntt[i] = t1 - t0;
    }

    /*
     * Sort measurements
     */
    qsort(
        cycles_ntt,
        NTESTS,
        sizeof(uint64_t),
        cmp_uint64_t
    );

    /*
     * Median
     */
    print_median("ntt", cycles_ntt);

    printf("\n");

    /*
     * Percentiles
     */
    print_percentile_legend();

    print_percentiles("ntt", cycles_ntt);

    return 0;
}

int main(void)
{
    /*
     * Force SVE VL = 128 bits (16 bytes)
     */
    if (prctl(PR_SVE_SET_VL, 16) < 0)
    {
        perror("prctl(PR_SVE_SET_VL)");
        return 1;
    }

    /*
     * Verify actual VL
     */
    unsigned long vl;
    __asm__ volatile("rdvl %0, #1" : "=r"(vl));

    printf(
        "SVE VL = %lu bytes (%lu bits)\n",
        vl,
        vl * 8
    );

    if (vl != 16)
    {
        fprintf(stderr, "ERROR: expected VL=128 bits\n");
        return 1;
    }

    enable_cyclecounter();

    bench();

    disable_cyclecounter();

    return 0;
}