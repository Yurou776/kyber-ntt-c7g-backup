#!/usr/bin/env python3
# Barrett variant tables: store (zhat, zt) instead of (zeta_mont, zeta_mont*qinv).
#   zt   = centered small representative of zeta_true = zeta_mont * R^-1 mod q  (for MUL)
#   zhat = round(zt * 2^15 / q), int16                                          (for SQRDMULH)
# Layout is byte-identical to gen.py so the same kernel structure consumes it.
Q = 3329
Rinv = pow(65536, -1, Q)

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

def s16(x):
    x &= 0xffff
    return x - 0x10000 if x >= 0x8000 else x
def center(x):
    x %= Q
    return x - Q if x > Q//2 else x
def zt(idx):   return center(zetas[idx] * Rinv)
def zhat(idx): return s16(round(zt(idx) * (1<<15) / Q))

# broadcast stream (len=64,32,16,8), half0 then half1  -> m=zhat, q=zt
bc_m, bc_q = [], []
for h in range(2):
    idxs = [2+h] + [4+2*h,5+2*h] + [8+4*h+g for g in range(4)] + [16+8*h+g for g in range(8)]
    for idx in idxs:
        bc_m.append(zhat(idx)); bc_q.append(zt(idx))
assert len(bc_m) == 30

# len=4 per-lane vectors: [za]*4 + [zb]*4
tw4_m, tw4_q = [], []
for h in range(2):
    for p in range(8):
        a = 32+16*h+2*p; b = a+1
        tw4_m += [zhat(a)]*4 + [zhat(b)]*4
        tw4_q += [zt(a)]*4   + [zt(b)]*4

# len=2 per-lane vectors: [a0,a0,a1,a1, b0,b0,b1,b1]
tw2_m, tw2_q = [], []
for h in range(2):
    for p in range(8):
        base = 64+32*h+4*p
        ids = [base,base,base+1,base+1, base+2,base+2,base+3,base+3]
        tw2_m += [zhat(i) for i in ids]
        tw2_q += [zt(i)   for i in ids]

def emit(name, arr):
    out=[f"{name}:"]
    for i in range(0,len(arr),8):
        out.append("    .hword " + ", ".join(str(x) for x in arr[i:i+8]))
    return "\n".join(out)

with open("ntt_tables.S","w") as f:
    f.write(".arch armv8-a+sve2\n    .section .rodata\n    .align 4\n")
    f.write("    .global ntt_z128_m\nntt_z128_m:\n    .hword %d\n" % zhat(1))
    f.write("    .global ntt_z128_q\nntt_z128_q:\n    .hword %d\n" % zt(1))
    for name, arr in [("ntt_bc_m",bc_m),("ntt_bc_q",bc_q),
                      ("ntt_tw4_m",tw4_m),("ntt_tw4_q",tw4_q),
                      ("ntt_tw2_m",tw2_m),("ntt_tw2_q",tw2_q)]:
        f.write("    .global %s\n" % name + emit(name,arr) + "\n")
    f.write("    .section .note.GNU-stack,\"\",%progbits\n")
print("wrote ntt_tables.S (barrett)")