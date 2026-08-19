#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#ifndef PR_SVE_SET_VL
#define PR_SVE_SET_VL 50
#endif

#define KYBER_Q 3329
#define QINV (-3327)  /* q^-1 mod 2^16 */

static const int16_t zetas[128] = {
  -1044,  -758,  -359, -1517,  1493,  1422,   287,   202,
   -171,   622,  1577,   182,   962, -1202, -1474,  1468,
    573, -1325,   264,   383,  -829,  1458, -1602,  -130,
   -681,  1017,   732,   608, -1542,   411,  -205, -1571,
   1223,   652,  -552,  1015, -1293,  1491,  -282, -1544,
    516,    -8,  -320,  -666, -1618, -1162,   126,  1469,
   -853,   -90,  -271,   830,   107, -1421,  -247,  -951,
   -398,   961, -1508,  -725,   448, -1065,   677, -1275,
  -1103,   430,   555,   843, -1251,   871,  1550,   105,
    422,   587,   177,  -235,  -291,  -460,  1574,  1653,
   -246,   778,  1159,  -147,  -777,  1483,  -602,  1119,
  -1590,   644,  -872,   349,   418,   329,  -156,   -75,
    817,  1097,   603,   610,  1322, -1285,  -1465,   384,
  -1215,  -136,  1218, -1335,  -874,   220, -1187, -1659,
  -1185, -1530, -1278,   794, -1510,  -854,  -870,   478,
   -108,  -308,   996,   991,   958, -1460,  1522,  1628
};

static int16_t montgomery_reduce(int32_t a){
    int16_t t = (int16_t)(a * QINV);
    t = (a - (int32_t)t * KYBER_Q) >> 16;
    return t;
}
static int16_t fqmul(int16_t a, int16_t b){ return montgomery_reduce((int32_t)a*b); }

/* standard Kyber forward NTT (reference) */
static void ntt_ref(int16_t r[256]){
    unsigned len, start, j, k = 1;
    int16_t t, zeta;
    for(len = 128; len >= 2; len >>= 1){
        for(start = 0; start < 256; start = j + len){
            zeta = zetas[k++];
            for(j = start; j < start + len; j++){
                t = fqmul(zeta, r[j+len]);
                r[j+len] = r[j] - t;
                r[j]     = r[j] + t;
            }
        }
    }
}

extern void ntt_kyber_sve2_v128(int16_t *r);

static int posmod(int x){ int m = x % KYBER_Q; if(m<0) m+=KYBER_Q; return m; }

int main(void){
    if(prctl(PR_SVE_SET_VL, 16) < 0){ perror("prctl"); return 2; }
    unsigned long vl; __asm__ volatile("rdvl %0,#1":"=r"(vl));
    printf("running with SVE VL = %lu bytes (%lu bits)\n", vl, vl*8);
    if(vl != 16){ printf("ERROR: could not force VL=128\n"); return 2; }

    srand(1234);
    int trials = 2000, fails = 0;
    for(int t=0;t<trials;t++){
        int16_t a[256], b[256];
        for(int i=0;i<256;i++){ int v = (rand()%KYBER_Q); a[i]=b[i]=(int16_t)v; }
        ntt_ref(a);
        ntt_kyber_sve2_v128(b);
        for(int i=0;i<256;i++){
            if(posmod(a[i]) != posmod(b[i])){
                if(fails<8) printf("  trial %d idx %d: ref=%d(%d) asm=%d(%d)\n",
                    t,i,a[i],posmod(a[i]),b[i],posmod(b[i]));
                fails++;
            }
        }
        if(fails) break;
    }
    if(fails){ printf("FAIL: %d mismatches\n", fails); return 1; }
    printf("PASS: %d trials, all 256 coeffs match mod q\n", trials);
    return 0;
}