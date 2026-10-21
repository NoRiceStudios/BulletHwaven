"""Small DSP kit for the procedural audio (numpy + scipy.signal). Everything is seeded, so a run
always writes the same files."""

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

SR = 44100


def secs(dur, sr=SR):
    return np.arange(int(round(dur * sr))) / sr


def silence(dur, sr=SR):
    return np.zeros(int(round(dur * sr)))


def noise(n, rng):
    return rng.uniform(-1.0, 1.0, n)


def pink(n, rng):
    """Roughly 1/f noise (Voss-style filter on white noise)."""
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return lfilter(b, a, noise(n, rng)) * 3.5


def env(n, attack, decay, sr=SR, curve=4.0):
    """Linear attack then exponential decay (to about -70 dB at `decay` s)."""
    t = np.arange(n) / sr
    a = np.clip(t / max(attack, 1e-5), 0.0, 1.0)
    d = np.exp(-np.maximum(t - attack, 0.0) / max(decay, 1e-5) * curve)
    return a * d


def adsr(n, a, d, s, r, sr=SR):
    t = np.arange(n) / sr
    hold = n / sr - r
    out = np.where(t < a, t / max(a, 1e-5), np.where(t < a + d, 1.0 - (1.0 - s) * (t - a) / max(d, 1e-5), s))
    rel = np.clip((t - hold) / max(r, 1e-5), 0.0, 1.0)
    return out * (1.0 - rel)


def filt(x, kind, cutoff, sr=SR, order=2):
    nyq = sr / 2.0
    if kind == "band":
        lo, hi = cutoff
        sos = butter(order, [max(lo, 10.0) / nyq, min(hi, nyq * 0.95) / nyq], btype="band", output="sos")
    else:
        sos = butter(order, min(max(cutoff, 10.0), nyq * 0.95) / nyq, btype=kind, output="sos")
    return sosfilt(sos, x)


def sweep_filt(x, kind, start, end, sr=SR, block=128, shape=1.0):
    """Second-order filter whose cutoff glides exponentially from `start` to `end` Hz."""
    out = np.zeros_like(x)
    zi = np.zeros(2)
    nb = max(1, (len(x) + block - 1) // block)
    nyq = sr / 2.0
    for i in range(nb):
        f = (i / max(nb - 1, 1)) ** shape
        c = start * (end / start) ** f
        b, a = butter(2, min(max(c, 10.0), nyq * 0.95) / nyq, btype=kind)
        seg = x[i * block:(i + 1) * block]
        y, zi = lfilter(b, a, seg, zi=zi)
        out[i * block:i * block + len(seg)] = y
    return out


def osc(freq, n, sr=SR, shape="sine", phase=0.0):
    """Oscillator with a constant or per-sample frequency (array)."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = phase + np.cumsum(f) / sr
    frac = ph % 1.0
    if shape == "sine":
        return np.sin(2 * np.pi * ph)
    if shape == "saw":
        return 2.0 * frac - 1.0
    if shape == "square":
        return np.where(frac < 0.5, 1.0, -1.0)
    if shape == "tri":
        return 4.0 * np.abs(frac - 0.5) - 1.0
    raise ValueError(shape)


def glide(f0, f1, n, curve=1.0):
    k = np.linspace(0.0, 1.0, n) ** curve
    return f0 * (f1 / f0) ** k


def drive(x, amount):
    return np.tanh(x * amount) / np.tanh(amount)


def crush(x, bits):
    q = 2 ** (bits - 1)
    return np.round(x * q) / q


def _recur(x, d, fn):
    """Run y[n] = fn(x[n], y[n - d], y[n - d - 1]) in chunks of d samples (each chunk only needs the
    previous output), so long feedback delays stay vectorised."""
    y = np.zeros(len(x) + d + 1)
    for s in range(0, len(x), d):
        e = min(len(x), s + d)
        k = e - s
        prev = y[s + 1:s + 1 + k]  # y[n - d] (y is offset by d + 1)
        prev2 = y[s:s + k]  # y[n - d - 1]
        y[s + d + 1:e + d + 1] = fn(x[s:e], prev, prev2, s, e)
    return y[d + 1:]


def pluck(freq, dur, rng, sr=SR, bright=0.6, damp=0.996):
    """Karplus-Strong string: a noise burst through a damped averaging delay line."""
    n = int(dur * sr)
    p = max(2, int(round(sr / freq)))
    burst = noise(p, rng)
    burst = filt(burst, "low", 1200 + 7000 * bright, sr, 1) if p > 12 else burst
    x = np.zeros(n)
    x[:min(p, n)] = burst[:n]
    g = damp * 0.5
    return _recur(x, p, lambda xs, a, b, s, e: xs + g * (a + b))


def comb(x, d, g):
    return _recur(x, d, lambda xs, a, b, s, e: xs + g * a)


def allpass(x, d, g):
    xd = np.concatenate([np.zeros(d), x])[: len(x)]  # x[n - d]
    return _recur(x, d, lambda xs, a, b, s, e: -g * xs + xd[s:e] + g * a)


def reverb(x, sr=SR, size=1.0, mix=0.25, damp=3500.0):
    """Schroeder reverb: four combs into two allpasses."""
    wet = np.zeros_like(x)
    for ms, g in ((29.7, 0.80), (37.1, 0.78), (41.1, 0.76), (43.7, 0.74)):
        wet += comb(x, int(ms * size * sr / 1000), g)
    for ms, g in ((5.0, 0.7), (1.7, 0.7)):
        wet = allpass(wet, int(ms * sr / 1000), g)
    wet = filt(wet, "low", damp, sr, 1) * 0.25
    return x * (1.0 - mix) + wet * mix


def place(buf, sig, at, gain=1.0):
    """Mix `sig` into `buf` starting at sample `at` (clipped to the buffer)."""
    if at >= len(buf):
        return
    end = min(len(buf), at + len(sig))
    buf[at:end] += sig[:end - at] * gain


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x if m < 1e-9 else x * (peak / m)


def fade(x, fin=0.002, fout=0.01, sr=SR):
    x = x.copy()
    a = min(len(x), int(fin * sr))
    b = min(len(x), int(fout * sr))
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    return x


def midi(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)
