#include "ntt_defs.h"

/* canonical reduce to [0,q) */
int16_t creduce(int32_t x){
    x %= KYBER_Q;
    if(x<0) x += KYBER_Q;
    return (int16_t)x;
}

/*
 * Reference forward Kyber NTT (incomplete, 7 layers, CT butterflies),
 * exact modular arithmetic in wide int (no overflow, no lazy tricks).
 * Uses the SAME twiddle values/ordering as the SVE (zeta_c[k]).
 * Output left in [0,q) so it can be compared bit-exactly after the SVE
 * result is also canonicalised.
 */
void ntt_ref(int16_t r[256]){
    int32_t a[256];
    for(int i=0;i<256;i++){ a[i]=((int32_t)r[i])%KYBER_Q; if(a[i]<0)a[i]+=KYBER_Q; }

    int k=1;
    for(int len=128; len>=2; len>>=1){
        for(int start=0; start<256; start += 2*len){
            int32_t zc = zeta_c[k++];
            for(int j=start;j<start+len;j++){
                int32_t t = ( (a[j+len]*zc) % KYBER_Q + KYBER_Q ) % KYBER_Q;
                int32_t u = a[j];
                a[j]     = (u + t) % KYBER_Q;
                a[j+len] = ((u - t) % KYBER_Q + KYBER_Q) % KYBER_Q;
            }
        }
    }
    for(int i=0;i<256;i++) r[i]=(int16_t)a[i];   /* already in [0,q) */
}