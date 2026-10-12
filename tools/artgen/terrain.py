"""Procedural ground for the six biomes (design doc section 7d). Returns HxWx3 float arrays."""

import numpy as np

from palette import CANYON, GLOW, OBSIDIAN, RUST, SALT, SAND, SPORE, STEEL
from pixel import bayer, dither_ramp, fbm, ramp_arr, rgb, value_noise

LIGHT = np.array([-0.55, -0.6, 0.58])  # from the top-left, fairly high sun


def _lambert(height, k):
    gy, gx = np.gradient(height * k)
    nx, ny, nz = -gx, -gy, np.ones_like(gx)
    norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / norm


def dune_sea(w, h, seed=0, ox=0, oy=0):
    ys, xs = np.mgrid[0:h, 0:w].astype(float)
    xs += ox
    ys += oy
    warp = fbm(h, w, (96, 48, 24), seed)
    p = ((xs * 0.8 + ys * 0.55) / 150.0 + warp * 1.3) % 1.0
    crest = 0.8
    dune = np.where(p < crest, p / crest, (1 - p) / (1 - crest))  # long windward, steep lee
    dune = dune * dune * (3 - 2 * dune)
    ripples = 0.018 * np.sin((xs * 0.35 + ys * 0.9) / 1.4 + warp * 14)
    height = dune * 0.9 + warp * 0.8 + ripples
    v = _lambert(height, 9.0)
    v = (v - 0.25) * 1.25 + (fbm(h, w, (16, 8), seed + 9) - 0.5) * 0.25
    out = dither_ramp(np.clip(v, 0.02, 0.98), SAND)
    rng = np.random.default_rng(seed)
    peb = rng.random((h, w)) < 0.004  # pebbles
    out[peb] = rgb(SAND[0])
    return out


def salt_flats(w, h, seed=0):
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0, 1, (int(w * h / 260), 2)) * [w, h]
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.full((h, w), 1e9)
    d2 = np.full((h, w), 1e9)
    cell = np.zeros((h, w), int)
    for i, (px, py) in enumerate(pts):
        dd = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
        closer = dd < d
        d2 = np.where(closer, d, np.minimum(d2, dd))
        cell = np.where(closer, i, cell)
        d = np.where(closer, dd, d)
    tone = rng.uniform(0.55, 0.9, len(pts))[cell] - np.minimum(d, 12) * 0.012
    v = tone + (fbm(h, w, (32, 8), seed) - 0.5) * 0.3
    out = dither_ramp(np.clip(v, 0, 1), SALT)
    crack = (d2 - d) < 1.3
    out[crack] = rgb(SALT[1])
    out[crack & ((d2 - d) < 0.5)] = rgb(SALT[0])
    return out


def canyon(w, h, seed=0):
    ys, xs = np.mgrid[0:h, 0:w]
    n = fbm(h, w, (48, 24, 12), seed)
    plateau = n > 0.5
    strata = 0.5 + 0.18 * np.sin(ys * 0.45 + n * 9) + (fbm(h, w, (8, 4), seed + 3) - 0.5) * 0.3
    v = np.where(plateau, 0.55 + strata * 0.45, 0.2 + strata * 0.3)
    # cliff faces cast shadows down-right
    shade = np.zeros((h, w), bool)
    for k in range(1, 7):
        sh = np.zeros_like(plateau)
        sh[k:, k:] = plateau[:-k, :-k]
        shade |= sh & ~plateau
    v = np.where(shade, v * 0.35, v)
    edge = plateau & ~np.roll(np.roll(plateau, -1, 0), -1, 1)
    v = np.where(edge, 0.98, v)
    return dither_ramp(np.clip(v, 0, 1), CANYON)


def glass_crater(w, h, seed=0):
    """Old impact site: sand fused into dark glass that mirrors the sky in a soft diagonal band."""
    ys, xs = np.mgrid[0:h, 0:w]
    cx, cy = w * 0.55, h * 0.6
    r = np.sqrt(((xs - cx) / (w * 0.7)) ** 2 + ((ys - cy) / (h * 0.7)) ** 2)
    n = fbm(h, w, (24, 12, 6), seed)
    glass = r < 0.85 + (n - 0.5) * 0.3
    band = np.exp(-(((xs - ys * 1.3) - w * 0.15) / (w * 0.18)) ** 2)  # sky reflection
    v = 0.12 + n * 0.25 + band * 0.35 - r * 0.1
    out = dither_ramp(np.clip(v, 0, 1), OBSIDIAN)
    cracks = (np.abs(value_noise(h, w, 9, seed + 2) - 0.5) < 0.012) & glass
    out[cracks] = rgb(OBSIDIAN[3])
    rng = np.random.default_rng(seed)
    sparkle = (rng.random((h, w)) < 0.004 + band * 0.01) & glass
    out[sparkle] = rgb(OBSIDIAN[5])
    rim = dune_sea(w, h, seed + 1)
    out[~glass] = rim[~glass]
    ring = glass & ~(np.roll(glass, 2, 0) & np.roll(glass, -2, 0) & np.roll(glass, 2, 1) & np.roll(glass, -2, 1))
    out[ring] = rgb(SAND[1])
    return out


def wreck_field(w, h, seed=0):
    out = dune_sea(w, h, seed)
    rng = np.random.default_rng(seed)
    st = ramp_arr(STEEL)
    for _ in range(int(w * h / 180)):
        x, y = rng.integers(1, w - 3), rng.integers(1, h - 3)
        sw, sh = rng.integers(1, 4), rng.integers(1, 3)
        out[y:y + sh, x:x + sw] = st[rng.integers(2, 5)]
        out[y + sh, x:x + sw] = st[0]
    rust = ramp_arr(RUST)
    for _ in range(int(w * h / 1500)):  # bent beams and larger plates
        x, y = rng.integers(2, w - 12), rng.integers(2, h - 6)
        lw = rng.integers(6, 11)
        out[y:y + 2, x:x + lw] = rust[rng.integers(2, 5)]
        out[y + 2, x:x + lw] = rust[0]
        out[y, x] = st[5]
    return out


def spore_basin(w, h, seed=0):
    """Bruised ground with mycelium patches and clusters of spore pods (some tips glow)."""
    base = dune_sea(w, h, seed) * 0.72 + ramp_arr(SPORE)[2] * 0.28
    n = fbm(h, w, (24, 12), seed + 4)
    patch = n > 0.56
    tint = patch & (bayer(h, w) < np.clip((n - 0.56) * 6, 0, 1))
    base[tint] = base[tint] * 0.6 + ramp_arr(SPORE)[1] * 0.4
    rng = np.random.default_rng(seed)
    sp = ramp_arr(SPORE)
    ys, xs = np.nonzero(patch)
    for i in rng.choice(len(ys), size=min(len(ys), int(w * h / 90)), replace=False):
        y, x = ys[i], xs[i]
        if not (1 <= x < w - 2 and 1 <= y < h - 2):
            continue
        base[y:y + 2, x:x + 2] = sp[3]
        base[y + 1, x + 1] = sp[1]
        base[y, x] = rgb(GLOW[3]) if rng.random() < 0.25 else sp[4]
    return base


BIOMES = {
    "DUNE SEA": dune_sea,
    "SALT FLATS": salt_flats,
    "CANYON": canyon,
    "GLASS CRATER": glass_crater,
    "WRECK FIELD": wreck_field,
    "SPORE BASIN": spore_basin,
}
