#!/usr/bin/env python3
"""Average single-speaker measurements and evaluate a biquad EQ (RBJ cookbook).
fit.py OUT.txt A.npz B.npz ...   (prints average and average+EQ, 1/3 octave)"""
import sys, numpy as np
sys.argv[0:0] = []
from importlib.machinery import SourceFileLoader
FS = 48000
def smooth(f, mag, frac=3):
    c = 1000 * 2 ** (np.arange(-12, 13) / frac); c = c[(c >= 250) & (c <= 12500)]
    p = 10 ** (mag / 10); out = []
    for x in c:
        m = (f >= x * 2 ** (-0.5 / frac)) & (f < x * 2 ** (0.5 / frac)); out.append(10 * np.log10(np.mean(p[m])))
    return c, np.array(out)
def biquad(kind, f0, q, g, f):
    A = 10 ** (g / 40); w0 = 2 * np.pi * f0 / FS; al = np.sin(w0) / (2 * q); cw = np.cos(w0)
    if kind == "peak":
        b = [1 + al * A, -2 * cw, 1 - al * A]; a = [1 + al / A, -2 * cw, 1 - al / A]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == "hs":
        sA = 2 * np.sqrt(A) * al
        b = [A * ((A + 1) + (A - 1) * cw + sA), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sA)]
        a = [(A + 1) - (A - 1) * cw + sA, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sA]
    z = np.exp(-1j * 2 * np.pi * f / FS)
    return 20 * np.log10(np.abs((b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z)))
EQ = [("hp", 300, 0.7071, 0), ("peak", 650, 1.0, 3.0), ("peak", 4800, 1.4, -7.0)]
PRE = -3.0
out, files = sys.argv[1], sys.argv[2:]
curves = []
for fn in files:
    d = np.load(fn); c, s = smooth(d["f"], d["mag"]); curves.append(s - np.mean(s[(c >= 1000) & (c <= 3000)]))
avg = 10 * np.log10(np.mean(10 ** (np.array(curves) / 10), 0)); spread = np.std(curves, 0)
eq = sum(biquad(k, f0, q, g, c) for k, f0, q, g in EQ) + PRE
with open(out, "w") as o:
    o.write("Hz\tavg\tspread\tEQ\tavg+EQ\n")
    for i, x in enumerate(c):
        o.write(f"{x:.0f}\t{avg[i]:+.1f}\t{spread[i]:.1f}\t{eq[i]:+.1f}\t{avg[i]+eq[i]:+.1f}\n")
print(open(out).read()); print("EQ:", EQ, "pre", PRE)
