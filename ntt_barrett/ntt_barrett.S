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
.macro CT za, zb          // Barrett: z28=zhat, z29=zt, z30=Q, tmps z26/z27, pred p0
    sqrdmulh z26.h, \zb\().h, z28.h        // qest = round(zb*zhat / 2^15)
    mul      z27.h, \zb\().h, z29.h        // lo   = zb*zt (low16)
    mls      z27.h, p0/m, z26.h, z30.h      // t    = lo - qest*Q   (reduced product)
    sub      \zb\().h, \za\().h, z27.h      // zb = za - t
    add      \za\().h, \za\().h, z27.h      // za = za + t
.endm

// --- per-lane Montgomery butterfly: m=zeta vec, l=zeta' vec, z30=Q, tmp z27 ---
.macro CT_TW za, zb, m, l   // Barrett: m=zhat vec, l=zt vec, z30=Q, tmps z26/z27, pred p0
    sqrdmulh z26.h, \zb\().h, \m\().h
    mul      z27.h, \zb\().h, \l\().h
    mls      z27.h, p0/m, z26.h, z30.h
    sub      \zb\().h, \za\().h, z27.h
    add      \za\().h, \za\().h, z27.h
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
    // Opt#1: whole-register LDR (imm range -256..255) => single base x1, no addvl x2.
    // On LE AArch64 with an all-true predicate this is bit-identical to the old ld1h.
    ldr z0 ,[x1]            
    ldr z1 ,[x1,#1,mul vl]
    ldr z2 ,[x1,#2,mul vl]  
    ldr z3 ,[x1,#3,mul vl]
    ldr z4 ,[x1,#4,mul vl]  
    ldr z5 ,[x1,#5,mul vl]
    ldr z6 ,[x1,#6,mul vl]  
    ldr z7 ,[x1,#7,mul vl]
    ldr z8 ,[x1,#8,mul vl]  
    ldr z9 ,[x1,#9,mul vl]
    ldr z10,[x1,#10,mul vl] 
    ldr z11,[x1,#11,mul vl]
    ldr z12,[x1,#12,mul vl] 
    ldr z13,[x1,#13,mul vl]
    ldr z14,[x1,#14,mul vl] 
    ldr z15,[x1,#15,mul vl]

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

    str z0 ,[x1]            
    str z1 ,[x1,#1,mul vl]
    str z2 ,[x1,#2,mul vl]  
    str z3 ,[x1,#3,mul vl]
    str z4 ,[x1,#4,mul vl]  
    str z5 ,[x1,#5,mul vl]
    str z6 ,[x1,#6,mul vl]  
    str z7 ,[x1,#7,mul vl]
    str z8 ,[x1,#8,mul vl]  
    str z9 ,[x1,#9,mul vl]
    str z10,[x1,#10,mul vl] 
    str z11,[x1,#11,mul vl]
    str z12,[x1,#12,mul vl] 
    str z13,[x1,#13,mul vl]
    str z14,[x1,#14,mul vl] 
    str z15,[x1,#15,mul vl]
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
    adrp    x11, ntt_z128_m 
    add x11,x11,:lo12:ntt_z128_m
    adrp    x12, ntt_z128_q 
    add x12,x12,:lo12:ntt_z128_q
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
