.arch armv8-a+sve2
    .text
// ============================================================================
// ntt_kyber_sve2_v128 : Kyber forward NTT, VL=128 (C8g / Neoverse V2), SVE2.
//
//   * Montgomery butterfly uses SVE2 *unpredicated* mul/smulh
//     (no movprfx, no governing predicate).
//   * Register budget at VL=128 (8 int16/vector) cannot hold all 256 coeffs
//     (32 vectors), so structure is:
//       Phase A0 : len=128 streamed (single zeta)
//       Per half : load 16 vectors (128 coeffs), do len=64,32,16,8 (broadcast),
//                  then len=4 (uzp.d) and len=2 (uzp.s) in-register, store.
//
//   x0 = int16_t r[256]
// ============================================================================
#define Q 3329

// --- broadcast Montgomery butterfly: z28=zeta, z29=zeta*qinv, z30=Q, tmp z27 ---
.macro CT za, zb
    smulh   z27.h, \zb\().h, z28.h        // t_hi = hi(zb*zeta)
    mul     \zb\().h, \zb\().h, z29.h      // m    = zb*zeta' (low16)
    smulh   \zb\().h, \zb\().h, z30.h      // hi(m*Q)
    sub     z27.h, z27.h, \zb\().h        // t = t_hi - hi(m*Q)
    sub     \zb\().h, \za\().h, z27.h      // zb = za - t
    add     \za\().h, \za\().h, z27.h      // za = za + t
.endm

// --- per-lane Montgomery butterfly: m=zeta vec, l=zeta' vec, z30=Q, tmp z27 ---
.macro CT_TW za, zb, m, l
    smulh   z27.h, \zb\().h, \m\().h
    mul     \zb\().h, \zb\().h, \l\().h
    smulh   \zb\().h, \zb\().h, z30.h
    sub     z27.h, z27.h, \zb\().h
    sub     \zb\().h, \za\().h, z27.h
    add     \za\().h, \za\().h, z27.h
.endm

// load next broadcast (zeta,zeta') from streams x11/x12 into z28/z29
.macro LDBC
    ld1rh   {z28.h}, p0/z, [x11]
    ld1rh   {z29.h}, p0/z, [x12]
    add     x11, x11, #2
    add     x12, x12, #2
.endm

.macro LDTW4
    ld1h    z28.h, p0/z, [x13]
    ld1h    z29.h, p0/z, [x14]
    addvl   x13, x13, #1
    addvl   x14, x14, #1
.endm

.macro LDTW2
    ld1h    z28.h, p0/z, [x15]
    ld1h    z29.h, p0/z, [x16]
    addvl   x15, x15, #1
    addvl   x16, x16, #1
.endm

// Process one 128-coeff half resident in z0..z15 (v_j = coeffs[base+8j..+7]).
// Data base pointer in x1. Uses/advances table pointers x11..x16.
.macro HALF
    addvl x2, x1, #8                 // upper-8 base (ld1h imm offset is -8..7)
    ld1h z0.h ,p0/z,[x1]             
    ld1h z1.h ,p0/z,[x1,#1,mul vl]
    ld1h z2.h ,p0/z,[x1,#2,mul vl]   
    ld1h z3.h ,p0/z,[x1,#3,mul vl]
    ld1h z4.h ,p0/z,[x1,#4,mul vl]   
    ld1h z5.h ,p0/z,[x1,#5,mul vl]
    ld1h z6.h ,p0/z,[x1,#6,mul vl]   
    ld1h z7.h ,p0/z,[x1,#7,mul vl]
    ld1h z8.h ,p0/z,[x2]             
    ld1h z9.h ,p0/z,[x2,#1,mul vl]
    ld1h z10.h,p0/z,[x2,#2,mul vl]   
    ld1h z11.h,p0/z,[x2,#3,mul vl]
    ld1h z12.h,p0/z,[x2,#4,mul vl]   
    ld1h z13.h,p0/z,[x2,#5,mul vl]
    ld1h z14.h,p0/z,[x2,#6,mul vl]   
    ld1h z15.h,p0/z,[x2,#7,mul vl]

    // len=64 : v_j <-> v_{j+8}, one zeta
    LDBC
    CT z0,z8 
    CT z1,z9 
    CT z2,z10 
    CT z3,z11
    CT z4,z12
    CT z5,z13
    CT z6,z14 
    CT z7,z15
    // len=32 : two groups (v0..7, v8..15), partner +4
    LDBC
    CT z0,z4 
    CT z1,z5 
    CT z2,z6 
    CT z3,z7
    LDBC
    CT z8,z12
    CT z9,z13
    CT z10,z14
    CT z11,z15
    // len=16 : four groups, partner +2
    LDBC
    CT z0,z2 
    CT z1,z3
    LDBC
    CT z4,z6 
    CT z5,z7
    LDBC
    CT z8,z10
    CT z9,z11
    LDBC
    CT z12,z14
    CT z13,z15
    // len=8 : eight groups, partner +1
    LDBC 
    CT z0,z1
    LDBC 
    CT z2,z3
    LDBC 
    CT z4,z5
    LDBC 
    CT z6,z7
    LDBC 
    CT z8,z9
    LDBC 
    CT z10,z11
    LDBC 
    CT z12,z13
    LDBC 
    CT z14,z15

    // len=4 : within-vector, uzp.d pairs (v0,v1)..(v14,v15)
    HALF_LEN4 z0 ,z1
    HALF_LEN4 z2 ,z3
    HALF_LEN4 z4 ,z5
    HALF_LEN4 z6 ,z7
    HALF_LEN4 z8 ,z9
    HALF_LEN4 z10,z11
    HALF_LEN4 z12,z13
    HALF_LEN4 z14,z15

    // len=2 : within-vector, uzp.s pairs (v0,v1)..(v14,v15)
    HALF_LEN2 z0 ,z1
    HALF_LEN2 z2 ,z3
    HALF_LEN2 z4 ,z5
    HALF_LEN2 z6 ,z7
    HALF_LEN2 z8 ,z9
    HALF_LEN2 z10,z11
    HALF_LEN2 z12,z13
    HALF_LEN2 z14,z15

    st1h z0.h ,p0,[x1]             
    st1h z1.h ,p0,[x1,#1,mul vl]
    st1h z2.h ,p0,[x1,#2,mul vl]   
    st1h z3.h ,p0,[x1,#3,mul vl]
    st1h z4.h ,p0,[x1,#4,mul vl]   
    st1h z5.h ,p0,[x1,#5,mul vl]
    st1h z6.h ,p0,[x1,#6,mul vl]   
    st1h z7.h ,p0,[x1,#7,mul vl]
    st1h z8.h ,p0,[x2]             
    st1h z9.h ,p0,[x2,#1,mul vl]
    st1h z10.h,p0,[x2,#2,mul vl]   
    st1h z11.h,p0,[x2,#3,mul vl]
    st1h z12.h,p0,[x2,#4,mul vl]   
    st1h z13.h,p0,[x2,#5,mul vl]
    st1h z14.h,p0,[x2,#6,mul vl]   
    st1h z15.h,p0,[x2,#7,mul vl]
.endm

// len=4 butterfly on a vector pair: separate lo/hi 4-lane halves via uzp.d
.macro HALF_LEN4 va, vb
    LDTW4
    uzp1 z16.d, \va\().d, \vb\().d      // lo = [a0..3, b0..3]
    uzp2 z17.d, \va\().d, \vb\().d      // hi = [a4..7, b4..7]
    CT_TW z16, z17, z28, z29
    zip1 \va\().d, z16.d, z17.d
    zip2 \vb\().d, z16.d, z17.d
.endm

// len=2 butterfly on a vector pair: separate adjacent coeff-pairs via uzp.s
.macro HALF_LEN2 va, vb
    LDTW2
    uzp1 z16.s, \va\().s, \vb\().s
    uzp2 z17.s, \va\().s, \vb\().s
    CT_TW z16, z17, z28, z29
    zip1 \va\().s, z16.s, z17.s
    zip2 \vb\().s, z16.s, z17.s
.endm

    .global ntt_kyber_sve2_v128
    .type ntt_kyber_sve2_v128, %function
    .align 4
ntt_kyber_sve2_v128:
    ptrue   p0.h
    mov     w9, #Q
    dup     z30.h, w9

    // ---- Phase A0 : len=128, single zeta, stream 16 vector-pairs ----
    adrp    x11, ntt_z128_m ; add x11,x11,:lo12:ntt_z128_m
    adrp    x12, ntt_z128_q ; add x12,x12,:lo12:ntt_z128_q
    ld1rh   {z28.h}, p0/z, [x11]
    ld1rh   {z29.h}, p0/z, [x12]
    mov     x1, x0
    addvl   x2, x0, #16
    mov     x9, #16
.La0:
    ld1h    z0.h, p0/z, [x1]
    ld1h    z1.h, p0/z, [x2]
    CT      z0, z1
    st1h    z0.h, p0, [x1]
    st1h    z1.h, p0, [x2]
    addvl   x1, x1, #1
    addvl   x2, x2, #1
    subs    x9, x9, #1
    b.ne    .La0

    // ---- table pointers for the per-half streams ----
    adrp    x11, ntt_bc_m  
    add x11,x11,:lo12:ntt_bc_m
    adrp    x12, ntt_bc_q  
    add x12,x12,:lo12:ntt_bc_q
    adrp    x13, ntt_tw4_m 
    add x13,x13,:lo12:ntt_tw4_m
    adrp    x14, ntt_tw4_q 
    add x14,x14,:lo12:ntt_tw4_q
    adrp    x15, ntt_tw2_m 
    add x15,x15,:lo12:ntt_tw2_m
    adrp    x16, ntt_tw2_q 
    add x16,x16,:lo12:ntt_tw2_q

    // ---- half 0 ----
    mov     x1, x0
    HALF
    // ---- half 1 ----
    addvl   x1, x0, #16
    HALF

    ret
    .size ntt_kyber_sve2_v128, .-ntt_kyber_sve2_v128
    .section .note.GNU-stack,"",%progbits