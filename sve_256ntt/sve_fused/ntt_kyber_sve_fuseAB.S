.arch armv8-a+sve
    .text
// ntt_kyber_sve_fuseAB: identical to ntt_kyber_sve except Phase C, which replaces
// ld4h/st4h with ld1h + UZP1/UZP2 (.s) + full-width CT + ZIP1/ZIP2 (.s) + st1h.
// Montgomery multiply count is unchanged: still 2 CT/iter, all 16 lanes = real z*b.
// Keep the original ntt_kyber_sve as the baseline; benchmark both.
#define Q 3329
.macro CT za, zb
    movprfx z6, \zb
    smulh   z6.h, p3/m, z6.h, z28.h
    mul     \zb\().h, p3/m, \zb\().h, z29.h
    smulh   \zb\().h, p3/m, \zb\().h, z30.h
    sub     z6.h, z6.h, \zb\().h
    sub     \zb\().h, \za\().h, z6.h
    add     \za\().h, \za\().h, z6.h
.endm
.macro CT2_TW za0,zb0,m0,l0, za1,zb1,m1,l1
    movprfx z6,  \zb0
    smulh   z6.h,  p3/m, z6.h,  \m0\().h
    movprfx z26, \zb1
    smulh   z26.h, p3/m, z26.h, \m1\().h
    mul     \zb0\().h, p3/m, \zb0\().h, \l0\().h
    mul     \zb1\().h, p3/m, \zb1\().h, \l1\().h
    smulh   \zb0\().h, p3/m, \zb0\().h, z30.h
    smulh   \zb1\().h, p3/m, \zb1\().h, z30.h
    sub     z6.h,  z6.h,  \zb0\().h
    sub     z26.h, z26.h, \zb1\().h
    sub     \zb0\().h, \za0\().h, z6.h
    sub     \zb1\().h, \za1\().h, z26.h
    add     \za0\().h, \za0\().h, z6.h
    add     \za1\().h, \za1\().h, z26.h
.endm
.macro TRANSPOSE4 B0,B1,B2,B3, O0,O1,O2,O3, T0,T1,T2,T3
    uzp1 \T0\().d, \B0\().d, \B1\().d
    uzp1 \T1\().d, \B2\().d, \B3\().d
    uzp2 \T2\().d, \B0\().d, \B1\().d
    uzp2 \T3\().d, \B2\().d, \B3\().d
    uzp1 \O0\().d, \T0\().d, \T1\().d
    uzp2 \O2\().d, \T0\().d, \T1\().d
    uzp1 \O1\().d, \T2\().d, \T3\().d
    uzp2 \O3\().d, \T2\().d, \T3\().d
.endm
.macro NEXT_ZETA
    ld1rh   {z28.h}, p3/z, [x16] ; ld1rh {z29.h}, p3/z, [x17]
    add     x16, x16, #2 ; add x17, x17, #2
.endm
.macro LOAD_A
    addvl x1, x0, #8
    ld1h z0.h,p0/z,[x0];            ld1h z1.h,p0/z,[x0,#1,mul vl];  ld1h z2.h,p0/z,[x0,#2,mul vl]
    ld1h z3.h,p0/z,[x0,#3,mul vl];  ld1h z4.h,p0/z,[x0,#4,mul vl];  ld1h z7.h,p0/z,[x0,#5,mul vl]
    ld1h z16.h,p0/z,[x0,#6,mul vl]; ld1h z17.h,p0/z,[x0,#7,mul vl]
    ld1h z18.h,p0/z,[x1];           ld1h z19.h,p0/z,[x1,#1,mul vl]; ld1h z20.h,p0/z,[x1,#2,mul vl]
    ld1h z21.h,p0/z,[x1,#3,mul vl]; ld1h z22.h,p0/z,[x1,#4,mul vl]; ld1h z23.h,p0/z,[x1,#5,mul vl]
    ld1h z24.h,p0/z,[x1,#6,mul vl]; ld1h z25.h,p0/z,[x1,#7,mul vl]
.endm
.macro STORE_A
    st1h z0.h,p0,[x0];             st1h z1.h,p0,[x0,#1,mul vl];  st1h z2.h,p0,[x0,#2,mul vl]
    st1h z3.h,p0,[x0,#3,mul vl];   st1h z4.h,p0,[x0,#4,mul vl];  st1h z7.h,p0,[x0,#5,mul vl]
    st1h z16.h,p0,[x0,#6,mul vl];  st1h z17.h,p0,[x0,#7,mul vl]
    st1h z18.h,p0,[x1];            st1h z19.h,p0,[x1,#1,mul vl]; st1h z20.h,p0,[x1,#2,mul vl]
    st1h z21.h,p0,[x1,#3,mul vl];  st1h z22.h,p0,[x1,#4,mul vl]; st1h z23.h,p0,[x1,#5,mul vl]
    st1h z24.h,p0,[x1,#6,mul vl];  st1h z25.h,p0,[x1,#7,mul vl]
.endm
    .global ntt_kyber_sve_fuseAB
    .type ntt_kyber_sve_fuseAB, %function
    .align 4
ntt_kyber_sve_fuseAB:
    ptrue   p3.h
    mov     w9, #Q
    dup     z30.h, w9
    adrp x2, kyb_zeta_m ; add x2,x2,:lo12:kyb_zeta_m ; add x2,x2,#2
    adrp x3, kyb_zeta_q ; add x3,x3,:lo12:kyb_zeta_q ; add x3,x3,#2
    ptrue p0.h
    mov x16,x2 ; mov x17,x3
    LOAD_A
    NEXT_ZETA
    CT z0,z18 ; CT z1,z19 ; CT z2,z20 ; CT z3,z21
    CT z4,z22 ; CT z7,z23 ; CT z16,z24 ; CT z17,z25
    NEXT_ZETA
    CT z0,z4 ; CT z1,z7 ; CT z2,z16 ; CT z3,z17
    NEXT_ZETA
    CT z18,z22 ; CT z19,z23 ; CT z20,z24 ; CT z21,z25
    NEXT_ZETA
    CT z0,z2 ; CT z1,z3
    NEXT_ZETA
    CT z4,z16 ; CT z7,z17
    NEXT_ZETA
    CT z18,z20 ; CT z19,z21
    NEXT_ZETA
    CT z22,z24 ; CT z23,z25
    NEXT_ZETA
    CT z0,z1
    NEXT_ZETA
    CT z2,z3
    NEXT_ZETA
    CT z4,z7
    NEXT_ZETA
    CT z16,z17
    NEXT_ZETA
    CT z18,z19
    NEXT_ZETA
    CT z20,z21
    NEXT_ZETA
    CT z22,z23
    NEXT_ZETA
    CT z24,z25
// ==== FUSED A->B: in-register transpose replaces STORE_A + ld4d ====
    adrp x2, tw_ln8a_m ; add x2,x2,:lo12:tw_ln8a_m
    adrp x3, tw_ln8a_q ; add x3,x3,:lo12:tw_ln8a_q
    adrp x4, tw_ln8b_m ; add x4,x4,:lo12:tw_ln8b_m
    adrp x5, tw_ln8b_q ; add x5,x5,:lo12:tw_ln8b_q
    adrp x6, tw_ln4a_m ; add x6,x6,:lo12:tw_ln4a_m
    adrp x7, tw_ln4a_q ; add x7,x7,:lo12:tw_ln4a_q
    adrp x9, tw_ln4b_m ; add x9,x9,:lo12:tw_ln4b_m
    adrp x10,tw_ln4b_q ; add x10,x10,:lo12:tw_ln4b_q
    mov x1, x0
    ptrue p0.d
    // group 0: blocks z0-z3 (in-place)
    TRANSPOSE4 z0,z1,z2,z3, z0,z1,z2,z3, z5,z6,z26,z27
    ld1h z8.h,p3/z,[x2];  ld1h z9.h,p3/z,[x3]
    ld1h z10.h,p3/z,[x4]; ld1h z11.h,p3/z,[x5]
    ld1h z12.h,p3/z,[x6]; ld1h z13.h,p3/z,[x7]
    ld1h z14.h,p3/z,[x9]; ld1h z15.h,p3/z,[x10]
    CT2_TW z0,z2,z8,z9, z1,z3,z10,z11
    CT2_TW z0,z1,z12,z13, z2,z3,z14,z15
    st4d {z0.d-z3.d}, p0, [x1]
    // group 1: blocks z4,z7,z16,z17 -> z0-z3
    TRANSPOSE4 z4,z7,z16,z17, z0,z1,z2,z3, z5,z6,z26,z27
    ld1h z8.h,p3/z,[x2,#1,mul vl];  ld1h z9.h,p3/z,[x3,#1,mul vl]
    ld1h z10.h,p3/z,[x4,#1,mul vl]; ld1h z11.h,p3/z,[x5,#1,mul vl]
    ld1h z12.h,p3/z,[x6,#1,mul vl]; ld1h z13.h,p3/z,[x7,#1,mul vl]
    ld1h z14.h,p3/z,[x9,#1,mul vl]; ld1h z15.h,p3/z,[x10,#1,mul vl]
    CT2_TW z0,z2,z8,z9, z1,z3,z10,z11
    CT2_TW z0,z1,z12,z13, z2,z3,z14,z15
    st4d {z0.d-z3.d}, p0, [x1, #4, mul vl]
    // group 2: blocks z18-z21 (in-place)
    TRANSPOSE4 z18,z19,z20,z21, z18,z19,z20,z21, z5,z6,z26,z27
    ld1h z8.h,p3/z,[x2,#2,mul vl];  ld1h z9.h,p3/z,[x3,#2,mul vl]
    ld1h z10.h,p3/z,[x4,#2,mul vl]; ld1h z11.h,p3/z,[x5,#2,mul vl]
    ld1h z12.h,p3/z,[x6,#2,mul vl]; ld1h z13.h,p3/z,[x7,#2,mul vl]
    ld1h z14.h,p3/z,[x9,#2,mul vl]; ld1h z15.h,p3/z,[x10,#2,mul vl]
    CT2_TW z18,z20,z8,z9, z19,z21,z10,z11
    CT2_TW z18,z19,z12,z13, z20,z21,z14,z15
    st4d {z18.d-z21.d}, p0, [x1, #8, mul vl]
    // group 3: blocks z22-z25 (in-place)
    TRANSPOSE4 z22,z23,z24,z25, z22,z23,z24,z25, z5,z6,z26,z27
    ld1h z8.h,p3/z,[x2,#3,mul vl];  ld1h z9.h,p3/z,[x3,#3,mul vl]
    ld1h z10.h,p3/z,[x4,#3,mul vl]; ld1h z11.h,p3/z,[x5,#3,mul vl]
    ld1h z12.h,p3/z,[x6,#3,mul vl]; ld1h z13.h,p3/z,[x7,#3,mul vl]
    ld1h z14.h,p3/z,[x9,#3,mul vl]; ld1h z15.h,p3/z,[x10,#3,mul vl]
    CT2_TW z22,z24,z8,z9, z23,z25,z10,z11
    CT2_TW z22,z23,z12,z13, z24,z25,z14,z15
    st4d {z22.d-z25.d}, p0, [x1, #12, mul vl]
// Phase C (UZP variant): ld1h + UZP1/UZP2(.s) + full CT + ZIP1/ZIP2(.s) + st1h
    adrp x2, tw_ln2_uzp_m ; add x2,x2,:lo12:tw_ln2_uzp_m
    adrp x3, tw_ln2_uzp_q ; add x3,x3,:lo12:tw_ln2_uzp_q
    mov x1,x0 ; mov x11,#0 ; mov x12,#(256/4)
.LCu:
    whilelt p0.h, x11, x12
    b.none .LCud
    ld1h z0.h,p0/z,[x1]
    ld1h z1.h,p0/z,[x1,#1,mul vl]
    ld1h z2.h,p0/z,[x1,#2,mul vl]
    ld1h z3.h,p0/z,[x1,#3,mul vl]
    uzp1 z4.s,  z0.s, z1.s        // lo0 : coeffs %4 in {0,1}, blocks 0..7
    uzp2 z5.s,  z0.s, z1.s        // hi0 : {2,3}
    uzp1 z16.s, z2.s, z3.s        // lo1 : blocks 8..15
    uzp2 z17.s, z2.s, z3.s        // hi1
    ld1h z28.h,p3/z,[x2];           ld1h z29.h,p3/z,[x3];           CT z4,z5
    ld1h z28.h,p3/z,[x2,#1,mul vl]; ld1h z29.h,p3/z,[x3,#1,mul vl]; CT z16,z17
    zip1 z0.s, z4.s,  z5.s        // re-interleave back to contiguous
    zip2 z1.s, z4.s,  z5.s
    zip1 z2.s, z16.s, z17.s
    zip2 z3.s, z16.s, z17.s
    st1h z0.h,p0,[x1]
    st1h z1.h,p0,[x1,#1,mul vl]
    st1h z2.h,p0,[x1,#2,mul vl]
    st1h z3.h,p0,[x1,#3,mul vl]
    addvl x1,x1,#4
    addvl x2,x2,#2; addvl x3,x3,#2
    inch x11
    b .LCu
.LCud:
    ret
    .size ntt_kyber_sve_fuseAB, .-ntt_kyber_sve_fuseAB
    .section .note.GNU-stack,"",%progbits