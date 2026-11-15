#!/usr/bin/env python3
"""Print a small worked example of both tasks (used in the README)."""
from golden import forward, backward
show = lambda name, m, w=4: print(f"{name:7s}" + " | ".join(" ".join(f"{v:{w}d}" for v in m[4*i:4*i+4]) for i in range(4)))
A  = [1, 2, 3, 4,  5, 6, 7, 8,  9, 10, 11, 12,  13, 14, 15, 16]
B  = [10, 20, 30, 40,  50, 60, 70, 80,  90, 100, 110, 120,  130, 140, 150, 160]
I  = [1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1]
F1 = I
H1 = [2 * v for v in I]
F2 = [0, 1, 0, 0,  1, 0, 0, 0,  0, 0, 0, 1,  0, 0, 1, 0]
H2 = [1] * 16
for name, fn in (("FORWARD (task 0)", forward), ("BACKWARD (task 1)", backward)):
    t = {}
    oa, ob = fn(A, B, F1, H1, F2, H2, t)
    print("=====", name, "=====")
    for k, v in t.items():
        show(k, v, 5)
    show("OUT_A", oa, 5); show("OUT_B", ob, 5)
