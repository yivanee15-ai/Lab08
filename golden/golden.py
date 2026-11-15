#!/usr/bin/env python3
"""Lab08 Coupling Network - golden model and pattern generator.

Usage: golden.py [num_patterns] [seed] [outdir]
Writes input.txt / output.txt consumed by 00_TESTBED/PATTERN.v
  input.txt : PATNUM, then per pattern 97 numbers (task, A[16], B[16], F1[16], H1[16], F2[16], H2[16])
  output.txt: per pattern 32 numbers (OUT_A[16], OUT_B[16])
All matrices are 4x4 in raster-scan order.  All arithmetic is unsigned.
"""
import random, sys


def matmul(F, M):
    """4x4 matrix product F x M (lists of 16, raster order), exact integers."""
    return [sum(F[4 * i + k] * M[4 * k + j] for k in range(4)) for i in range(4) for j in range(4)]


def xy(F, H, M):
    X = [v % 15 + 1 for v in matmul(F, M)]      # 4-bit, 1..15
    Y = [v % 256 for v in matmul(H, M)]         # 8-bit
    return X, Y


def forward(A, B, F1, H1, F2, H2, trace=None):
    X1, Y1 = xy(F1, H1, A)
    BX1 = [x * b for x, b in zip(X1, B)]                 # 12-bit
    MidA, MidB = A, [p ^ y for p, y in zip(BX1, Y1)]     # 12-bit
    X2, Y2 = xy(F2, H2, MidB)
    MidAX2 = [x * a for x, a in zip(X2, MidA)]
    OutA = [p ^ y for p, y in zip(MidAX2, Y2)]
    if trace is not None:
        trace.update(X1=X1, Y1=Y1, BX1=BX1, MidB=MidB, X2=X2, Y2=Y2, MidAX2=MidAX2)
    return OutA, MidB


def backward(A, B, F1, H1, F2, H2, trace=None):
    X2, Y2 = xy(F2, H2, B)
    MidAX2 = [a ^ y for a, y in zip(A, Y2)]              # 8-bit
    MidA = [p // x for p, x in zip(MidAX2, X2)]
    X1, Y1 = xy(F1, H1, MidA)
    BX1 = [b ^ y for b, y in zip(B, Y1)]
    OutB = [p // x for p, x in zip(BX1, X1)]
    if trace is not None:
        trace.update(X2=X2, Y2=Y2, MidAX2=MidAX2, MidA=MidA, X1=X1, Y1=Y1, BX1=BX1)
    return MidA, OutB


def run(task, A, B, F1, H1, F2, H2, trace=None):
    return (backward if task else forward)(A, B, F1, H1, F2, H2, trace)


def gen_pattern(rng, kind):
    r8 = lambda: [rng.randrange(256) for _ in range(16)]
    r4 = lambda: [rng.randrange(16) for _ in range(16)]
    c = lambda v: [v] * 16
    task = rng.randrange(2)
    if kind == 0:   mats = [c(0)] * 6                                   # all zero
    elif kind == 1: mats = [c(255), c(255), c(15), c(15), c(15), c(15)]  # all max
    elif kind == 2: mats = [r8(), r8(), c(0), r4(), c(0), r4()]          # F = 0 -> X = 1
    elif kind == 3: mats = [r8(), r8(), r4(), c(0), r4(), c(0)]          # H = 0 -> Y = 0
    elif kind == 4: mats = [c(255), c(0), r4(), r4(), r4(), r4()]
    elif kind == 5: mats = [c(0), c(255), r4(), r4(), r4(), r4()]
    else:           mats = [r8(), r8(), r4(), r4(), r4(), r4()]
    return [task] + [v for m in mats for v in m]


def split(p):
    return p[0], [p[1 + 16 * m: 17 + 16 * m] for m in range(6)]


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 2026
    outdir = sys.argv[3] if len(sys.argv) > 3 else "."
    rng = random.Random(seed)
    pats = []
    for idx in range(n):
        kind = idx // 2 if idx < 12 else 99          # 2 patterns of each corner kind first
        p = gen_pattern(rng, kind)
        if idx < 12:
            p[0] = idx & 1                           # both tasks for every corner
        pats.append(p)
    with open(f"{outdir}/input.txt", "w") as fi, open(f"{outdir}/output.txt", "w") as fo:
        fi.write(f"{n}\n")
        for p in pats:
            task, m = split(p)
            oa, ob = run(task, *m)
            assert all(0 <= v < 4096 for v in oa + ob)
            fi.write(" ".join(map(str, p)) + "\n")
            fo.write(" ".join(map(str, oa + ob)) + "\n")
    print(f"wrote {n} patterns (seed {seed}) to {outdir}")


if __name__ == "__main__":
    main()
