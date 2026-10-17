"""Tiny pixel-art toolkit: canvases, aliased masks, ramp shading, outlines, dithering, light."""

import math

import numpy as np
from PIL import Image, ImageDraw

BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0


def rgb(c):
    if isinstance(c, str):
        c = c.lstrip("#")
        return np.array([int(c[i:i + 2], 16) for i in (0, 2, 4)], np.float32)
    return np.asarray(c, np.float32)


def ramp_arr(ramp):
    return np.stack([rgb(c) for c in ramp])


def bayer(h, w, ox=0, oy=0):
    ys = (np.arange(h) + oy) % 4
    xs = (np.arange(w) + ox) % 4
    return BAYER4[ys[:, None], xs[None, :]]


def shift(m, dx, dy):
    """out[y, x] = m[y + dy, x + dx]; False/0 outside."""
    h, w = m.shape
    out = np.zeros_like(m)
    out[max(0, -dy):min(h, h - dy), max(0, -dx):min(w, w - dx)] = \
        m[max(0, dy):min(h, h + dy), max(0, dx):min(w, w + dx)]
    return out


# ---------------------------------------------------------------- masks

def _mask(w, h, fn):
    im = Image.new("L", (w, h), 0)
    fn(ImageDraw.Draw(im))
    return np.array(im) > 0


def poly(w, h, pts):
    return _mask(w, h, lambda d: d.polygon([tuple(map(float, p)) for p in pts], fill=255))


def rect(w, h, x0, y0, x1, y1):
    return _mask(w, h, lambda d: d.rectangle([x0, y0, x1, y1], fill=255))


def ellipse(w, h, x0, y0, x1, y1):
    return _mask(w, h, lambda d: d.ellipse([x0, y0, x1, y1], fill=255))


def circle(w, h, cx, cy, r):
    return ellipse(w, h, cx - r, cy - r, cx + r, cy + r)


def line(w, h, pts, width=1):
    return _mask(w, h, lambda d: d.line([tuple(map(float, p)) for p in pts], fill=255, width=width))


def blob(w, h, cx, cy, rx, ry, rough=0.15, seed=0, cell=4):
    """Irregular ellipse with a noisy edge."""
    n = value_noise(h, w, cell, seed) - 0.5
    ys, xs = np.mgrid[0:h, 0:w]
    d = ((xs - cx) / rx) ** 2 + ((ys - cy) / ry) ** 2
    return d < 1 + rough * 2 * n


def pixels(w, h, pts):
    m = np.zeros((h, w), bool)
    for x, y in pts:
        if 0 <= x < w and 0 <= y < h:
            m[int(y), int(x)] = True
    return m


# ---------------------------------------------------------------- noise

def value_noise(h, w, cell, seed):
    rng = np.random.default_rng(seed)
    g = rng.random((h // cell + 3, w // cell + 3))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    fy = ys - y0
    fx = xs - x0
    fy = fy * fy * (3 - 2 * fy)
    fx = fx * fx * (3 - 2 * fx)
    a = g[y0[:, None], x0[None, :]]
    b = g[y0[:, None], x0[None, :] + 1]
    c = g[y0[:, None] + 1, x0[None, :]]
    d = g[y0[:, None] + 1, x0[None, :] + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(h, w, cells=(64, 32, 16, 8, 4), seed=0):
    total = np.zeros((h, w))
    norm = 0.0
    amp = 1.0
    for i, c in enumerate(cells):
        total += amp * value_noise(h, w, c, seed + i * 101)
        norm += amp
        amp *= 0.5
    return total / norm


def dither_ramp(v, ramp, ox=0, oy=0):
    """Map v (0..1) onto a colour ramp with ordered dithering between steps."""
    ra = ramp_arr(ramp)
    n = len(ramp)
    t = np.clip(v, 0, 1) * (n - 1)
    idx = np.floor(t + bayer(*v.shape, ox, oy)).astype(int)
    return ra[np.clip(idx, 0, n - 1)]


# ---------------------------------------------------------------- canvas

class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)
        self.a = np.zeros((h, w), np.float32)
        self.emit = np.zeros((h, w), bool)

    def put(self, mask, color, alpha=1.0, emissive=False):
        """Composite colour (single colour or HxWx3 array) over mask."""
        if not mask.any():
            return
        col = rgb(color) if not (isinstance(color, np.ndarray) and color.ndim == 3) else color
        src = np.broadcast_to(col, self.rgb.shape)[mask]
        da = self.a[mask]
        sa = alpha
        out_a = sa + da * (1 - sa)
        self.rgb[mask] = (src * sa + self.rgb[mask] * (da * (1 - sa))[:, None]) / out_a[:, None]
        self.a[mask] = out_a
        if emissive:
            self.emit[mask] = True
        elif alpha >= 1:
            self.emit[mask] = False

    def solid(self):
        return self.a > 0.5

    def rot90(self, k):
        c = Canvas(self.w, self.h) if k % 2 == 0 else Canvas(self.h, self.w)
        c.rgb = np.ascontiguousarray(np.rot90(self.rgb, k))
        c.a = np.ascontiguousarray(np.rot90(self.a, k))
        c.emit = np.ascontiguousarray(np.rot90(self.emit, k))
        return c

    def flip_x(self):
        c = Canvas(self.w, self.h)
        c.rgb, c.a, c.emit = self.rgb[:, ::-1].copy(), self.a[:, ::-1].copy(), self.emit[:, ::-1].copy()
        return c

    def to_image(self, scale=1):
        arr = np.dstack([np.clip(self.rgb, 0, 255), np.clip(self.a * 255, 0, 255)]).astype(np.uint8)
        im = Image.fromarray(arr, "RGBA")
        if scale != 1:
            im = im.resize((self.w * scale, self.h * scale), Image.NEAREST)
        return im


def paint(cv, m, ramp, base=None, light=True, noise=0.0, seed=0, emissive=False, alpha=1.0, depth=1):
    """Fill a mask with a ramp, lit from the top-left (sun direction) plus optional grit noise."""
    if not m.any():
        return
    ra = ramp_arr(ramp)
    n = len(ramp)
    base = n // 2 if base is None else base
    idx = np.full(m.shape, base, np.int32)
    if light:
        hl = m & (~shift(m, 0, -1) | ~shift(m, -1, 0))
        sh = m & (~shift(m, 0, 1) | ~shift(m, 1, 0))
        idx += hl.astype(np.int32)
        idx -= sh.astype(np.int32)
        for d in range(2, depth + 1):
            idx -= (m & ~shift(m, 0, d) & ~sh).astype(np.int32)
    if noise:
        # clustered grit: mostly low-frequency blotches (grime, rust, dents) plus a little speckle
        r = 0.7 * value_noise(*m.shape, 2, seed) + 0.3 * np.random.default_rng(seed).random(m.shape)
        rank = np.zeros(m.shape)
        rank[m] = r[m].argsort().argsort() / max(1, m.sum() - 1)
        idx[m & (rank < noise / 2)] -= 1
        idx[m & (rank > 1 - noise / 2)] += 1
    idx = np.clip(idx, 0, n - 1)
    cv.put(m, ra[idx], alpha=alpha, emissive=emissive)


def outline(cv, color, skip_emissive=False):
    """1px ring around the solid pixels; with skip_emissive, glowing pixels get no ring of their own."""
    m = cv.solid()
    src = m & ~cv.emit if skip_emissive else m
    ring = (shift(src, 1, 0) | shift(src, -1, 0) | shift(src, 0, 1) | shift(src, 0, -1)) & ~m
    cv.put(ring, color)


def paste(dst, src, x, y):
    """Alpha-composite src onto dst with its top-left at (x, y)."""
    x, y = int(round(x)), int(round(y))
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(dst.w, x + src.w), min(dst.h, y + src.h)
    if x0 >= x1 or y0 >= y1:
        return
    sx0, sy0 = x0 - x, y0 - y
    s_rgb = src.rgb[sy0:sy0 + y1 - y0, sx0:sx0 + x1 - x0]
    s_a = src.a[sy0:sy0 + y1 - y0, sx0:sx0 + x1 - x0]
    s_e = src.emit[sy0:sy0 + y1 - y0, sx0:sx0 + x1 - x0]
    d_rgb = dst.rgb[y0:y1, x0:x1]
    d_a = dst.a[y0:y1, x0:x1]
    out_a = s_a + d_a * (1 - s_a)
    safe = np.where(out_a > 0, out_a, 1)
    dst.rgb[y0:y1, x0:x1] = (s_rgb * s_a[..., None] + d_rgb * (d_a * (1 - s_a))[..., None]) / safe[..., None]
    dst.a[y0:y1, x0:x1] = out_a
    solid = s_a > 0.5
    dst.emit[y0:y1, x0:x1] = np.where(solid, s_e, dst.emit[y0:y1, x0:x1])


def cast_shadow(dst, src, x, y, dx, dy, strength=0.5, color=None):
    """Darken dst where src's silhouette lands, offset by (dx, dy)."""
    from palette import SHADOW
    col = rgb(color or SHADOW)
    tmp = np.zeros((dst.h, dst.w), bool)
    x, y = int(round(x + dx)), int(round(y + dy))
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(dst.w, x + src.w), min(dst.h, y + src.h)
    if x0 >= x1 or y0 >= y1:
        return
    tmp[y0:y1, x0:x1] = src.solid()[y0 - y:y1 - y, x0 - x:x1 - x]
    dst.rgb[tmp] = dst.rgb[tmp] * (1 - strength) + col * strength


def halo(dst, cx, cy, r, color, strength=0.5, steps=3):
    """Additive, dithered, banded glow - keeps a pixel-art look instead of a smooth blur."""
    x0, x1 = max(0, int(cx - r)), min(dst.w, int(cx + r) + 1)
    y0, y1 = max(0, int(cy - r)), min(dst.h, int(cy + r) + 1)
    if x0 >= x1 or y0 >= y1:
        return
    ys, xs = np.mgrid[y0:y1, x0:x1]
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / r
    f = np.clip(1 - d, 0, 1) ** 1.6
    lvl = np.floor(f * steps + bayer(y1 - y0, x1 - x0, x0, y0) * 0.999) / steps
    dst.rgb[y0:y1, x0:x1] += rgb(color) * (lvl * strength)[..., None]


def angle_to(x0, y0, x1, y1):
    """Angle in radians, 0 = up (north), clockwise."""
    return math.atan2(x1 - x0, -(y1 - y0))


def polar(cx, cy, ang, dist):
    return cx + math.sin(ang) * dist, cy - math.cos(ang) * dist


# ---------------------------------------------------------------- 3x5 pixel font

_GLYPHS = {
    "A": ".#.|#.#|###|#.#|#.#", "B": "##.|#.#|##.|#.#|##.", "C": ".##|#..|#..|#..|.##",
    "D": "##.|#.#|#.#|#.#|##.", "E": "###|#..|##.|#..|###", "F": "###|#..|##.|#..|#..",
    "G": ".##|#..|#.#|#.#|.##", "H": "#.#|#.#|###|#.#|#.#", "I": "###|.#.|.#.|.#.|###",
    "J": "..#|..#|..#|#.#|.#.", "K": "#.#|#.#|##.|#.#|#.#", "L": "#..|#..|#..|#..|###",
    "M": "#.#|###|###|#.#|#.#", "N": "##.|#.#|#.#|#.#|#.#", "O": ".#.|#.#|#.#|#.#|.#.",
    "P": "##.|#.#|##.|#..|#..", "Q": ".#.|#.#|#.#|##.|.##", "R": "##.|#.#|##.|#.#|#.#",
    "S": ".##|#..|.#.|..#|##.", "T": "###|.#.|.#.|.#.|.#.", "U": "#.#|#.#|#.#|#.#|###",
    "V": "#.#|#.#|#.#|#.#|.#.", "W": "#.#|#.#|###|###|#.#", "X": "#.#|#.#|.#.|#.#|#.#",
    "Y": "#.#|#.#|.#.|.#.|.#.", "Z": "###|..#|.#.|#..|###",
    "0": "###|#.#|#.#|#.#|###", "1": ".#.|##.|.#.|.#.|###", "2": "##.|..#|.#.|#..|###",
    "3": "##.|..#|.#.|..#|##.", "4": "#.#|#.#|###|..#|..#", "5": "###|#..|##.|..#|##.",
    "6": ".##|#..|###|#.#|###", "7": "###|..#|.#.|.#.|.#.", "8": "###|#.#|###|#.#|###",
    "9": "###|#.#|###|..#|##.",
    ":": ".|#|.|#|.", ".": ".|.|.|.|#", "+": "...|.#.|###|.#.|...", "-": "...|...|###|...|...",
    "/": "..#|..#|.#.|#..|#..", "(": ".#|#.|#.|#.|.#", ")": "#.|.#|.#|.#|#.",
    "!": "#|#|#|.|#", "'": "#|#|.|.|.", ",": ".|.|.|#|#", " ": "..|..|..|..|..",
    "%": "#.#|..#|.#.|#..|#.#", ">": "#..|.#.|..#|.#.|#..", "<": "..#|.#.|#..|.#.|..#",
    "?": "##.|..#|.#.|...|.#.", "*": "...|#.#|.#.|#.#|...", "=": "...|###|...|###|...",
    "#": "#.#|###|#.#|###|#.#",
}


def text_width(s):
    return sum(len(_GLYPHS.get(ch.upper(), "...|").split("|")[0]) + 1 for ch in s) - 1


def text(cv, s, x, y, color, shadow=None):
    if shadow:
        text(cv, s, x + 1, y + 1, shadow)
    cx = x
    col = rgb(color)
    for ch in s.upper():
        rows = _GLYPHS.get(ch, "...|...|...|...|...").split("|")
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                px, py = cx + rx, y + ry
                if c == "#" and 0 <= px < cv.w and 0 <= py < cv.h:
                    cv.rgb[py, px] = col
                    cv.a[py, px] = 1
        cx += len(rows[0]) + 1
    return cx
