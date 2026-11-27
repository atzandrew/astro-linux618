#!/usr/bin/env python3
"""Exponential (Farina) sine sweep for speaker measurement.

sweep.py gen OUT.wav [--ch both|L|R] [--dbfs -12]   write 48 kHz S16 stereo sweep
sweep.py ir  REC.wav OUT.npz [--mic-ch 0]           deconvolve a recording -> IR + response
sweep.py plot A.npz [B.npz ...] OUT.txt              1/6-octave table (and PNG if matplotlib)

Sweep: 50 Hz - 20 kHz, 6 s, 1 s silence before, 2 s after. numpy only.
"""
import sys, wave, struct, argparse
import numpy as np

FS = 48000
F1, F2, T = 50.0, 20000.0, 6.0
PRE, POST = 1.0, 2.0

def sweep():
    t = np.arange(int(T * FS)) / FS
    R = np.log(F2 / F1)
    x = np.sin(2 * np.pi * F1 * T / R * (np.exp(t * R / T) - 1))
    fade = int(0.05 * FS)
    w = np.ones_like(x); w[:fade] = np.linspace(0, 1, fade); w[-fade:] = np.linspace(1, 0, fade)
    return x * w, t, R

def inverse(x, t, R):
    # time-reversed sweep with -6 dB/oct envelope (Farina)
    return x[::-1] * np.exp(-t * R / T)

def gen(a):
    x, t, R = sweep()
    x *= 10 ** (a.dbfs / 20)
    sig = np.concatenate([np.zeros(int(PRE * FS)), x, np.zeros(int(POST * FS))])
    l = sig if a.ch in ("both", "L") else np.zeros_like(sig)
    r = sig if a.ch in ("both", "R") else np.zeros_like(sig)
    pcm = np.round(np.stack([l, r], 1) * 32767).astype("<i2")
    with wave.open(a.out, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(FS); w.writeframes(pcm.tobytes())

def read(fn):
    with wave.open(fn) as w:
        assert w.getframerate() == FS and w.getsampwidth() == 2, "need 48 kHz S16"
        d = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, w.getnchannels())
    return d.astype(float) / 32768

def ir(a):
    rec = read(a.rec)[:, a.mic_ch]
    peak = np.max(np.abs(rec))
    x, t, R = sweep()
    inv = inverse(x, t, R)
    n = 1 << int(np.ceil(np.log2(len(rec) + len(inv))))
    h = np.fft.irfft(np.fft.rfft(rec, n) * np.fft.rfft(inv, n), n)
    i0 = int(np.argmax(np.abs(h)))
    # full (ungated) IR as a WAV next to the .npz, for REW (Import impulse response)
    full = h[max(0, i0 - int(0.01 * FS)):i0 + int(0.5 * FS)]
    full = np.round(full / np.max(np.abs(full)) * 32000).astype("<i2")
    with wave.open(a.out.rsplit(".", 1)[0] + "-ir.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(FS); w.writeframes(full.tobytes())
    # gate: 1 ms before the peak, 5 ms after (keeps room reflections out
    # at ~30 cm; limits resolution below ~200 Hz, which the HPF removes anyway)
    pre, post = int(0.001 * FS), int(0.005 * FS)
    seg = h[i0 - pre:i0 + post].copy()
    win = np.ones(len(seg)); k = int(0.0005 * FS)
    win[:k] = np.hanning(2 * k)[:k]; win[-int(0.002 * FS):] = np.hanning(int(0.004 * FS))[int(0.002 * FS):]
    seg *= win
    nf = 1 << 15
    H = np.fft.rfft(seg, nf); f = np.fft.rfftfreq(nf, 1 / FS)
    mag = 20 * np.log10(np.abs(H) + 1e-12)
    np.savez(a.out, f=f, mag=mag, peak=peak, snr_floor=20*np.log10(np.std(h[:i0 - int(0.05*FS)]) + 1e-12) - 20*np.log10(np.abs(h[i0])))
    print(f"{a.rec}: rec peak {20*np.log10(peak+1e-12):.1f} dBFS, IR peak at {i0/FS:.3f} s")

def smooth(f, mag, frac=6):
    centers = 1000 * 2 ** (np.arange(-30, 25) / frac)
    centers = centers[(centers >= 100) & (centers <= 16000)]
    out = []
    p = 10 ** (mag / 10)
    for c in centers:
        lo, hi = c * 2 ** (-0.5 / frac), c * 2 ** (0.5 / frac)
        m = (f >= lo) & (f < hi)
        out.append(10 * np.log10(np.mean(p[m])))
    return centers, np.array(out)

def plot(a):
    rows = []
    for fn in a.inputs:
        d = np.load(fn)
        c, s = smooth(d["f"], d["mag"])
        ref = np.mean(s[(c >= 1000) & (c <= 3000)])
        rows.append((fn, c, s - ref))
    with open(a.out, "w") as o:
        o.write("Hz\t" + "\t".join(r[0] for r in rows) + "\n")
        for i, c in enumerate(rows[0][1]):
            o.write(f"{c:.0f}\t" + "\t".join(f"{r[2][i]:+.1f}" for r in rows) + "\n")
    print(open(a.out).read())

p = argparse.ArgumentParser()
sp = p.add_subparsers(dest="cmd", required=True)
g = sp.add_parser("gen"); g.add_argument("out"); g.add_argument("--ch", default="both"); g.add_argument("--dbfs", type=float, default=-12)
i = sp.add_parser("ir"); i.add_argument("rec"); i.add_argument("out"); i.add_argument("--mic-ch", type=int, default=0)
q = sp.add_parser("plot"); q.add_argument("inputs", nargs="+"); q.add_argument("out")
a = p.parse_args()
{"gen": gen, "ir": ir, "plot": plot}[a.cmd](a)
