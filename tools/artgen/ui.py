"""UI art for the round loop (design doc section 11f): diegetic, improvised, rusty.

- stencil_font(): 5x7 stencil font for headings (spray-painted look, bars broken by bridges).
- icons():        16x16 icons: weapon kinds, card categories and tech branches.
- card_tag():     a draft card as a manila shipping tag (crumpled, stained, punched hole + string).
- tape():         masking-tape label, 3-slice (caps + tiling middle), near-white so it can be tinted.
- hazard():       8x8 hazard-stripe tile (READY button).
- steel_plate():  riveted steel plate 9-patch (CRT housing, buttons).
- vignette():     banded, dithered darkness with a clear pool in the middle (workshop camp light).
"""

import numpy as np

from palette import BONE, BRASS, FIRE, HAZARD, LEATHER, OUTLINE, RUST, SAND, STEEL, TYRE
from pixel import (Canvas, bayer, circle, line, outline, paint, pixels, poly, rect, rgb, shift,
                   value_noise)

STENCIL_CHARS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:!-'./+%"
STENCIL_CELL = 6
STENCIL_H = 7

_S = {
    "A": ".#.#.|#...#|#...#|##.##|#...#|#...#|#...#",
    "B": "##.#.|#...#|#...#|##.#.|#...#|#...#|##.#.",
    "C": ".#.##|#....|#....|#....|#....|#....|.#.##",
    "D": "##.#.|#...#|#...#|#...#|#...#|#...#|##.#.",
    "E": "##.##|#....|#....|##.#.|#....|#....|##.##",
    "F": "##.##|#....|#....|##.#.|#....|#....|#....",
    "G": ".#.##|#....|#....|#..##|#...#|#...#|.#.#.",
    "H": "#...#|#...#|#...#|##.##|#...#|#...#|#...#",
    "I": "###|.#.|.#.|...|.#.|.#.|###",
    "J": "...##|....#|....#|....#|#...#|#...#|.#.#.",
    "K": "#...#|#..#.|#.#..|#.#..|#.#..|#..#.|#...#",
    "L": "#....|#....|#....|#....|#....|#....|##.##",
    "M": "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#",
    "N": "#...#|##..#|#.#.#|#.#.#|#..##|#...#|#...#",
    "O": ".#.#.|#...#|#...#|#...#|#...#|#...#|.#.#.",
    "P": "##.#.|#...#|#...#|##.#.|#....|#....|#....",
    "Q": ".#.#.|#...#|#...#|#...#|#.#.#|#..#.|.#.##",
    "R": "##.#.|#...#|#...#|##.#.|#..#.|#...#|#...#",
    "S": ".#.##|#....|#....|.#.#.|....#|....#|##.#.",
    "T": "##.##|..#..|..#..|..#..|..#..|..#..|..#..",
    "U": "#...#|#...#|#...#|#...#|#...#|#...#|.#.#.",
    "V": "#...#|#...#|#...#|#...#|.#.#.|.#.#.|..#..",
    "W": "#...#|#...#|#...#|#.#.#|#.#.#|##.##|#...#",
    "X": "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#",
    "Y": "#...#|#...#|.#.#.|..#..|..#..|..#..|..#..",
    "Z": "##.##|....#|...#.|..#..|.#...|#....|##.##",
    "0": ".###.|#...#|#..##|#.#.#|##..#|#...#|.###.",
    "1": ".#.|##.|.#.|.#.|.#.|.#.|###",
    "2": ".#.#.|#...#|....#|...#.|..#..|.#...|##.##",
    "3": "##.#.|....#|....#|.#.#.|....#|....#|##.#.",
    "4": "#...#|#...#|#...#|##.##|....#|....#|....#",
    "5": "##.##|#....|#....|##.#.|....#|....#|##.#.",
    "6": ".#.#.|#....|#....|##.#.|#...#|#...#|.#.#.",
    "7": "##.##|....#|...#.|..#..|..#..|..#..|..#..",
    "8": ".#.#.|#...#|#...#|.#.#.|#...#|#...#|.#.#.",
    "9": ".#.#.|#...#|#...#|.#.##|....#|....#|.#.#.",
    ":": ".|.|#|.|.|#|.",
    "!": "#|#|#|#|#|.|#",
    "-": "...|...|...|###|...|...|...",
    "'": "#|#|.|.|.|.|.",
    ".": ".|.|.|.|.|.|#",
    "/": "...#|...#|..#.|..#.|.#..|.#..|#...",
    "+": "...|...|.#.|###|.#.|...|...",
    "%": "#...#|#..#.|...#.|..#..|.#...|.#..#|#...#",
    " ": "...|...|...|...|...|...|...",
}


def stencil_font():
    cv = Canvas(STENCIL_CELL * len(STENCIL_CHARS), STENCIL_H)
    for i, ch in enumerate(STENCIL_CHARS):
        for ry, row in enumerate(_S[ch].split("|")):
            for rx, c in enumerate(row):
                if c == "#":
                    cv.rgb[ry, i * STENCIL_CELL + rx] = 255
                    cv.a[ry, i * STENCIL_CELL + rx] = 1
    return cv


# ---------------------------------------------------------------- icons (16x16)

ICON_NAMES = ["mg", "shotgun", "cannon", "flamer", "armor", "mobility", "behavior",
              "ballistics", "engineering", "propulsion", "electronics", "salvage", "scrap", "fuel"]
N = 16


def _ic():
    return Canvas(N, N)


def _icon_mg():
    cv = _ic()
    paint(cv, rect(N, N, 7, 5, 15, 6), STEEL, base=2)      # barrel
    paint(cv, rect(N, N, 7, 8, 14, 9), STEEL, base=2)      # second barrel
    paint(cv, rect(N, N, 2, 4, 8, 10), STEEL, base=3)      # receiver
    paint(cv, rect(N, N, 3, 11, 5, 14), LEATHER, base=2)   # grip
    for x in (9, 11, 13):                                  # ammo belt
        cv.put(pixels(N, N, [(x - 6, 12), (x - 6, 13)]), BRASS[3])
    cv.put(pixels(N, N, [(3, 5), (4, 5)]), STEEL[5])
    outline(cv, OUTLINE)
    return cv


def _icon_shotgun():
    cv = _ic()
    paint(cv, rect(N, N, 6, 4, 15, 5), STEEL, base=3)
    paint(cv, rect(N, N, 6, 7, 15, 8), STEEL, base=2)
    paint(cv, poly(N, N, [(0, 9), (6, 4), (8, 4), (8, 9), (4, 13), (1, 13)]), LEATHER, base=2)
    cv.put(pixels(N, N, [(15, 4), (15, 7)]), OUTLINE)
    outline(cv, OUTLINE)
    return cv


def _icon_cannon():
    cv = _ic()
    paint(cv, rect(N, N, 6, 5, 13, 9), STEEL, base=2)
    paint(cv, rect(N, N, 12, 4, 15, 10), STEEL, base=3)   # muzzle ring
    paint(cv, circle(N, N, 5, 7, 4.5), STEEL, base=2, depth=2)
    cv.put(pixels(N, N, [(14, 6), (14, 7), (14, 8)]), OUTLINE)
    cv.put(pixels(N, N, [(3, 5), (4, 4)]), STEEL[5])
    outline(cv, OUTLINE)
    return cv


def _icon_flamer():
    cv = _ic()
    paint(cv, rect(N, N, 1, 5, 6, 13), RUST, base=3, depth=2)       # fuel tank
    cv.put(rect(N, N, 1, 8, 6, 8), HAZARD)
    paint(cv, rect(N, N, 6, 7, 11, 9), STEEL, base=2)               # nozzle
    flame = poly(N, N, [(11, 8), (15, 3), (14, 8), (15, 13)])
    cv.put(flame, FIRE[3], emissive=True)
    cv.put(poly(N, N, [(11, 8), (14, 6), (13, 8), (14, 10)]), FIRE[5], emissive=True)
    outline(cv, OUTLINE)
    return cv


def _icon_armor():
    cv = _ic()
    shield = poly(N, N, [(2, 2), (13, 2), (13, 9), (8, 14), (7, 14), (2, 9)])
    paint(cv, shield, STEEL, base=3, depth=2, noise=0.2, seed=4)
    cv.put(pixels(N, N, [(4, 4), (11, 4), (4, 9), (11, 9)]), STEEL[1])
    cv.put(line(N, N, [(5, 7), (10, 7)]), RUST[3])
    outline(cv, OUTLINE)
    return cv


def _icon_mobility():
    cv = _ic()
    paint(cv, circle(N, N, 7.5, 7.5, 7), TYRE, base=2, depth=2)
    for x, y in ((7, 1), (12, 3), (14, 7), (12, 12), (7, 14), (3, 12), (1, 7), (3, 3)):
        cv.put(pixels(N, N, [(x, y)]), TYRE[3])                    # tread blocks
    paint(cv, circle(N, N, 7.5, 7.5, 3.2), STEEL, base=3)
    cv.put(pixels(N, N, [(7, 7), (8, 8)]), STEEL[1])
    outline(cv, OUTLINE)
    return cv


def _icon_behavior():
    cv = _ic()  # steering wheel: the player's hand on the AI (section 6)
    ring = circle(N, N, 7.5, 7.5, 7) & ~circle(N, N, 7.5, 7.5, 4.6)
    paint(cv, ring, LEATHER, base=2)
    spokes = line(N, N, [(2, 9), (13, 9)]) | line(N, N, [(7, 9), (7, 14)]) | line(N, N, [(8, 9), (8, 14)])
    paint(cv, spokes & ~ring, STEEL, base=3, light=False)
    paint(cv, circle(N, N, 7.5, 8.5, 1.6), BRASS, base=3)
    outline(cv, OUTLINE)
    return cv


def _icon_ballistics():
    cv = _ic()  # one cartridge
    paint(cv, rect(N, N, 5, 6, 10, 14), BRASS, base=2)
    paint(cv, poly(N, N, [(5, 6), (10, 6), (9, 3), (7.5, 1), (6, 3)]), STEEL, base=3)
    cv.put(rect(N, N, 5, 12, 10, 12), BRASS[1])
    outline(cv, OUTLINE)
    return cv


def _icon_engineering():
    cv = _ic()  # wrench
    paint(cv, line(N, N, [(4, 12), (10, 6)], width=3), STEEL, base=3)
    head = circle(N, N, 11, 4.5, 3.6) & ~poly(N, N, [(10, 4), (13, 0), (16, 3), (12, 6)])
    paint(cv, head, STEEL, base=3)
    paint(cv, circle(N, N, 3.5, 12.5, 2.2), STEEL, base=2)
    outline(cv, OUTLINE)
    return cv


def _icon_propulsion():
    cv = _ic()  # exhaust stack with a warm blast
    paint(cv, rect(N, N, 2, 6, 9, 10), STEEL, base=2, depth=2)
    paint(cv, rect(N, N, 9, 5, 11, 11), STEEL, base=3)
    cv.put(poly(N, N, [(11, 6), (15, 4), (14, 8), (15, 12), (11, 10)]), FIRE[3], emissive=True)
    cv.put(poly(N, N, [(11, 7), (13, 7), (13, 9), (11, 9)]), FIRE[5], emissive=True)
    cv.put(pixels(N, N, [(4, 8), (6, 8)]), STEEL[1])
    outline(cv, OUTLINE)
    return cv


def _icon_electronics():
    cv = _ic()  # field radio with a whip antenna
    paint(cv, rect(N, N, 1, 6, 13, 14), STEEL, base=3, depth=2)
    for y in (8, 10, 12):                                   # speaker grille
        cv.put(line(N, N, [(3, y), (7, y)]), STEEL[1])
    paint(cv, circle(N, N, 10.5, 10.5, 1.8), BRASS, base=3)  # tuning dial
    cv.put(line(N, N, [(11, 6), (14, 0)]), STEEL[4])
    cv.put(pixels(N, N, [(14, 0), (15, 0)]), FIRE[4], emissive=True)
    outline(cv, OUTLINE)
    return cv


def _icon_salvage():
    cv = _ic()  # horseshoe magnet
    shoe = (circle(N, N, 7.5, 9, 6) & ~circle(N, N, 7.5, 9, 2.8)) & rect(N, N, 0, 0, 15, 10)
    shoe |= rect(N, N, 2, 9, 4, 13) | rect(N, N, 11, 9, 13, 13)
    shoe &= ~rect(N, N, 5, 9, 10, 15)
    paint(cv, shoe, RUST, base=3)
    paint(cv, rect(N, N, 2, 12, 4, 14) | rect(N, N, 11, 12, 13, 14), STEEL, base=4, light=False)
    outline(cv, OUTLINE)
    return cv


def _icon_scrap():
    cv = _ic()  # a nut and a bent plate
    paint(cv, poly(N, N, [(1, 9), (8, 6), (12, 9), (5, 13)]), RUST, base=3, noise=0.3, seed=2)
    nut = poly(N, N, [(8, 2), (12, 2), (14, 5), (12, 8), (8, 8), (6, 5)]) & ~circle(N, N, 10, 5, 1.2)
    paint(cv, nut, STEEL, base=3)
    outline(cv, OUTLINE)
    return cv


def _icon_fuel():
    cv = _ic()  # jerrycan
    paint(cv, poly(N, N, [(3, 4), (10, 4), (13, 7), (13, 14), (3, 14)]), RUST, base=3, depth=2)
    cv.put(line(N, N, [(5, 7), (11, 13)]) | line(N, N, [(11, 7), (5, 13)]), RUST[1])
    paint(cv, rect(N, N, 4, 1, 7, 3), STEEL, base=2)
    outline(cv, OUTLINE)
    return cv


def icons():
    fns = {"mg": _icon_mg, "shotgun": _icon_shotgun, "cannon": _icon_cannon, "flamer": _icon_flamer,
           "armor": _icon_armor, "mobility": _icon_mobility, "behavior": _icon_behavior,
           "ballistics": _icon_ballistics, "engineering": _icon_engineering,
           "propulsion": _icon_propulsion, "electronics": _icon_electronics, "salvage": _icon_salvage,
           "scrap": _icon_scrap, "fuel": _icon_fuel}
    cv = Canvas(N * len(ICON_NAMES), N)
    for i, name in enumerate(ICON_NAMES):
        ic = fns[name]()
        cv.rgb[:, i * N:(i + 1) * N] = ic.rgb
        cv.a[:, i * N:(i + 1) * N] = ic.a
    return cv


# ---------------------------------------------------------------- card tag

CARD_W, CARD_H = 100, 122


def card_tag(seed=3):
    W, H = CARD_W, CARD_H
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    # shipping-tag outline: chamfered top corners, slightly torn bottom edge
    body = poly(W, H, [(14, 1), (W - 15, 1), (W - 2, 12), (W - 2, H - 2), (1, H - 2), (1, 12)])
    ys, xs = np.mgrid[0:H, 0:W]
    tear = (H - 2 - (rng.integers(0, 3, W) * (rng.random(W) < 0.35)))[None, :]
    body &= ys <= tear
    # crumpled paper: banded value noise mapped onto the paper ramp
    n = 0.6 * value_noise(H, W, 10, seed) + 0.4 * value_noise(H, W, 4, seed + 1)
    paper = np.array([rgb(BONE[2]), rgb(BONE[3]), rgb(BONE[4])])
    lvl = np.clip(np.floor(n * 2.4 + bayer(H, W) * 0.9), 0, 2).astype(int)
    lvl = np.where(n > 0.25, np.maximum(lvl, 1), lvl)
    lvl = np.where(n > 0.4, lvl, np.minimum(lvl, 1))
    cv.put(body, paper[lvl])
    # fold creases (light ridge + dark valley)
    for (x0, y0, x1, y1) in ((4, 40, W - 6, 52), (12, H - 30, W - 3, H - 40)):
        crease = line(W, H, [(x0, y0), (x1, y1)]) & body
        cv.put(crease, BONE[2])
        cv.put(shift(crease, 0, -1) & body & ~crease, BONE[4])
    # stains: oil and rust rings
    for _ in range(3):
        cx, cy, r = rng.uniform(10, W - 10), rng.uniform(30, H - 10), rng.uniform(4, 9)
        ring = circle(W, H, cx, cy, r) & ~circle(W, H, cx + 0.5, cy + 0.5, r - 1.3) & body
        ring &= rng.random((H, W)) < 0.7
        cv.put(ring, SAND[2], alpha=0.55)
    # edge shading (light top-left, darker bottom-right) and dirty rim
    rim_dark = body & (~shift(body, 0, 1) | ~shift(body, 1, 0))
    rim_light = body & (~shift(body, 0, -1) | ~shift(body, -1, 0))
    cv.put(rim_light, BONE[4])
    cv.put(rim_dark, BONE[1])
    # reinforced punch hole and a loop of wire
    cx, cy = W // 2, 7
    cv.put(circle(W, H, cx - 0.5, cy - 0.5, 4.2) & body, BRASS[2])
    cv.put(circle(W, H, cx - 0.5, cy - 0.5, 4.2) & ~circle(W, H, cx - 0.5, cy - 1.5, 3.6) & body, BRASS[1])
    hole = circle(W, H, cx - 0.5, cy - 0.5, 2.2)
    cv.a[hole] = 0
    outline(cv, OUTLINE)
    cv.a[hole] = 0
    wire = line(W, H, [(cx - 1, cy - 1), (cx - 4, 0)]) | line(W, H, [(cx, cy - 1), (cx + 3, 0)])
    cv.put(wire, STEEL[4])
    return cv


# ---------------------------------------------------------------- tape, hazard, plates, vignette

def tape(w=24, h=9, seed=5):
    cv = Canvas(w, h)
    rng = np.random.default_rng(seed)
    m = rect(w, h, 0, 0, w - 1, h - 1)
    for x in (0, 1, w - 2, w - 1):  # torn ends
        for y in range(h):
            if rng.random() < (0.55 if x in (0, w - 1) else 0.2):
                m[y, x] = False
    n = value_noise(h, w, 3, seed)
    ramp = np.array([rgb("#c8c0b0"), rgb("#ddd6c8"), rgb("#efeadf")])
    cv.put(m, ramp[np.clip((n * 3).astype(int), 0, 2)], alpha=0.95)
    cv.put(m & ~shift(m, 0, 1), rgb("#b0a898"))
    return cv


def hazard(size=8):
    cv = Canvas(size, size)
    ys, xs = np.mgrid[0:size, 0:size]
    stripe = ((xs + ys) % size) < size // 2
    cv.put(stripe, HAZARD)
    cv.put(~stripe, OUTLINE)
    return cv


def steel_plate(size=24):
    cv = Canvas(size, size)
    m = rect(size, size, 0, 0, size - 1, size - 1)
    paint(cv, m, STEEL, base=2, noise=0.3, seed=8)
    cv.put(m & ~rect(size, size, 1, 1, size - 2, size - 2), OUTLINE)
    for (x, y) in ((2, 2), (size - 3, 2), (2, size - 3), (size - 3, size - 3)):
        cv.put(pixels(size, size, [(x, y)]), STEEL[4])
        cv.put(pixels(size, size, [(x + 1, y + 1)]), STEEL[0])
    return cv


def vignette(w=1280, h=720, clear=78.0, steps=(0.0, 0.28, 0.5, 0.66, 0.76)):
    """Darkness with a clear pool in the centre: banded levels, Bayer-dithered between bands."""
    ys, xs = np.mgrid[0:h, 0:w] + 0.5
    d = np.sqrt(((xs - w / 2) / 1.25) ** 2 + (ys - h / 2) ** 2)
    t = np.clip((d - clear) / 150.0, 0, 1) * (len(steps) - 1)
    i = np.floor(t + bayer(h, w) * 0.999).astype(int)
    a = np.array(steps)[np.clip(i, 0, len(steps) - 1)]
    cv = Canvas(w, h)
    cv.rgb[:] = rgb("#140e12")
    cv.a = a.astype(np.float32)
    return cv
