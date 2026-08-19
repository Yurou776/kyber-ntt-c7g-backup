#!/usr/bin/env python3
# Generate VL=128 twiddle tables for the Kyber forward NTT (SVE2 version).
# Emits ntt_tables.S. Layout is derived to match the assembly's consumption order.

Q = 3329
QINV = -3327  # q^{-1} mod 2^16, signed (== 62209 unsigned)

zetas = [
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
]
assert len(zetas) == 128

def to_i16(x):
    x &= 0xffff
    return x - 0x10000 if x >= 0x8000 else x

def zq(z):  # zeta * qinv mod 2^16, signed
    return to_i16(z * QINV)

# ---- broadcast stream (len=64,32,16,8), order: half0 then half1 ----
# per half order: len64(1), len32(2), len16(4), len8(8) = 15 entries
bc_m, bc_q = [], []
for h in range(2):
    # len=64
    for idx in [2+h]:
        bc_m.append(zetas[idx]); bc_q.append(zq(zetas[idx]))
    # len=32 : groupA=4+2h, groupB=5+2h
    for idx in [4+2*h, 5+2*h]:
        bc_m.append(zetas[idx]); bc_q.append(zq(zetas[idx]))
    # len=16 : 8+4h .. +3
    for g in range(4):
        idx = 8+4*h+g
        bc_m.append(zetas[idx]); bc_q.append(zq(zetas[idx]))
    # len=8 : 16+8h .. +7
    for g in range(8):
        idx = 16+8*h+g
        bc_m.append(zetas[idx]); bc_q.append(zq(zetas[idx]))
assert len(bc_m) == 30

# ---- len=4 per-lane vectors : pairs (v0,v1)..(v14,v15), 8 pairs/half ----
# vector m = [za]*4 + [zb]*4 ; za=zetas[32+16h+2p], zb=zetas[32+16h+2p+1]
tw4_m, tw4_q = [], []
for h in range(2):
    for p in range(8):
        za = zetas[32+16*h+2*p]; zb = zetas[32+16*h+2*p+1]
        tw4_m += [za]*4 + [zb]*4
        tw4_q += [zq(za)]*4 + [zq(zb)]*4
assert len(tw4_m) == 16*8

# ---- len=2 per-lane vectors : pairs (v0,v1)..(v14,v15) ----
# lo lane layout after uzp1.s = [a_g0,a_g0,a_g1,a_g1, b_g0,b_g0,b_g1,b_g1]
# a_g0=zetas[64+32h+4p], a_g1=+1, b_g0=+2, b_g1=+3
tw2_m, tw2_q = [], []
for h in range(2):
    for p in range(8):
        base = 64+32*h+4*p
        a0,a1,b0,b1 = zetas[base],zetas[base+1],zetas[base+2],zetas[base+3]
        vec = [a0,a0,a1,a1, b0,b0,b1,b1]
        tw2_m += vec
        tw2_q += [zq(x) for x in vec]
assert len(tw2_m) == 16*8

def emit(name, arr):
    lines = [f"{name}:"]
    for i in range(0, len(arr), 8):
        chunk = ", ".join(str(x) for x in arr[i:i+8])
        lines.append(f"    .hword {chunk}")
    return "\n".join(lines)

with open("ntt_tables.S","w") as f:
    f.write(".arch armv8-a+sve2\n")
    f.write("    .section .rodata\n    .align 4\n")
    f.write("    .global ntt_z128_m\nntt_z128_m:\n    .hword %d\n" % zetas[1])
    f.write("    .global ntt_z128_q\nntt_z128_q:\n    .hword %d\n" % zq(zetas[1]))
    for name, arr in [("ntt_bc_m",bc_m),("ntt_bc_q",bc_q),
                      ("ntt_tw4_m",tw4_m),("ntt_tw4_q",tw4_q),
                      ("ntt_tw2_m",tw2_m),("ntt_tw2_q",tw2_q)]:
        f.write("    .global %s\n" % name)
        f.write(emit(name, arr) + "\n")
    f.write("    .section .note.GNU-stack,\"\",%progbits\n")

print("wrote ntt_tables.S")
print("bc entries:", len(bc_m), "tw4 hwords:", len(tw4_m), "tw2 hwords:", len(tw2_m))