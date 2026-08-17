#include <stdio.h>
#include <stdint.h>
#include <limits.h>

#define Q 3329
#define QINV -3327

/* Official Kyber Montgomery reduction */
static int16_t official_montgomery_reduce(int32_t a)
{
    int16_t t;

    t = (int16_t)a * QINV;
    t = (a - (int32_t)t * Q) >> 16;

    return t;
}

/*
 * Your SVE decomposition:
 *
 *   z28 = zeta
 *   z29 = zeta * QINV mod 2^16
 *   z30 = Q
 *
 *   H = signed_high16(x * zeta)
 *   T = low16(x * (zeta*QINV))
 *   K = signed_high16(T * Q)
 *
 *   result = H - K
 */
static int16_t your_montgomery(int16_t x, int16_t zeta)
{
    int32_t a = (int32_t)x * zeta;

    int16_t zeta_q =
        (int16_t)((int32_t)zeta * QINV);

    int16_t H = (int16_t)(a >> 16);

    int16_t T =
        (int16_t)((int32_t)x * zeta_q);

    int16_t K =
        (int16_t)(((int32_t)T * Q) >> 16);

    return (int16_t)(H - K);
}

static void check(int16_t x, int16_t zeta)
{
    int16_t ref = official_montgomery_reduce((int32_t)x * zeta);
    int16_t sve = your_montgomery(x, zeta);

    printf("x=%6d zeta=%6d  official=%6d  yours=%6d",
           x, zeta, ref, sve);

    if (ref == sve)
        printf("  PASS\n");
    else
        printf("  *** MISMATCH ***\n");
}

int main(void)
{
    printf("Kyber Montgomery reduction comparison\n");
    printf("Q=%d QINV=%d\n\n", Q, QINV);

    /*
     * Official first zetas:
     * -1044, -758, -359, -1517, ...
     */
    int16_t zetas[] = {
        -1044, -758, -359, -1517,
         1493, 1422, 287, 202,
        -171, 622, 1577, 182,
         962, -1202, -1474, 1468
    };

    int nz = sizeof(zetas) / sizeof(zetas[0]);

    /*
     * Basic values
     */
    int16_t xs[] = {
        0,
        1,
        -1,
        2,
        -2,
        100,
        -100,
        3328,
        -3328,
        1000,
        -1000,
        1664,
        -1664
    };

    int nx = sizeof(xs) / sizeof(xs[0]);

    printf("=== Basic tests ===\n");

    for (int i = 0; i < nz; i++) {
        for (int j = 0; j < nx; j++) {
            check(xs[j], zetas[i]);
        }
    }

    /*
     * Boundary / stress values
     */
    printf("\n=== Boundary tests ===\n");

    int16_t special[] = {
        INT16_MIN,
        INT16_MIN + 1,
        -32767,
        -30000,
        -20000,
        -10000,
        10000,
        20000,
        30000,
        32767
    };

    int ns = sizeof(special) / sizeof(special[0]);

    for (int i = 0; i < nz; i++) {
        for (int j = 0; j < ns; j++) {
            check(special[j], zetas[i]);
        }
    }

    /*
     * Exhaustive x range for every zeta would be:
     *
     *   65536 * 128
     *
     * which is still completely reasonable.
     */
    printf("\n=== Exhaustive test ===\n");

    int fails = 0;

    for (int zi = 0; zi < nz; zi++) {
        for (int x = INT16_MIN; x <= INT16_MAX; x++) {

            int16_t ref =
                official_montgomery_reduce(
                    (int32_t)(int16_t)x * zetas[zi]);

            int16_t sve =
                your_montgomery(
                    (int16_t)x, zetas[zi]);

            if (ref != sve) {

                if (fails < 20) {
                    printf(
                        "FAIL: x=%d zeta=%d "
                        "official=%d yours=%d\n",
                        (int16_t)x,
                        zetas[zi],
                        ref,
                        sve);
                }

                fails++;
            }
        }
    }

    printf("\nTotal failures = %d\n", fails);

    return fails ? 1 : 0;
}
