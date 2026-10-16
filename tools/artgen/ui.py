"""UI art for the round loop (design doc section 11f): diegetic, improvised, rusty.

- stencil_font(): 5x7 stencil font for headings (spray-painted look, bars broken by bridges).
- icons():        16x16 icons: weapon kinds, card categories and tech branches.
- card_tag():     a draft card as a manila shipping tag (crumpled, stained, punched hole + string).
- card_legendary(): an evolution card: the tag cut from gunmetal in a riveted brass frame.
- tape():         masking-tape label, 3-slice (caps + tiling middle), near-white so it can be tinted.
- hazard():       8x8 hazard-stripe tile (READY button).
- steel_plate():  riveted steel plate 9-patch (CRT housing, buttons).
- vignette():     banded, dithered darkness with a clear pool in the middle (workshop camp light).
- logo():         the title: "BULLET" + "HWAVEN" spray-stencilled on a welded scrap sign.
- splat():        paint splat (near-white, tinted at runtime): the colour picker's swatches.
"""

import numpy as np

from palette import BONE, BRASS, FIRE, HAZARD, LEATHER, OUTLINE, RUST, SAND, STEEL, TYRE
from pixel import (Canvas, bayer, blob, circle, line, outline, paint, pixels, poly, rect, rgb, shift,
                   value_noise)
from sprites import rivets, weather, weld

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


def card_legendary(seed=11):
    """An evolution card (legendary): the tag's shape cut from dark gunmetal, a riveted brass frame with
    corner brackets, a brass-ringed punch hole on a short chain. Text on it is drawn light (bone / brass)."""
    W, H = CARD_W, CARD_H
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    pts = [(14, 1), (W - 15, 1), (W - 2, 12), (W - 2, H - 2), (1, H - 2), (1, 12)]
    body = poly(W, H, pts)
    ys, xs = np.mgrid[0:H, 0:W]
    n = 0.6 * value_noise(H, W, 9, seed) + 0.4 * value_noise(H, W, 3, seed + 1)
    metal = np.array([rgb("#1f1a1c"), rgb("#2a2324"), rgb("#352c2b")])
    lvl = np.clip(np.floor(n * 2.6 + bayer(H, W) * 0.8), 0, 2).astype(int)
    cv.put(body, metal[lvl])
    # brushed streaks and a few scratches
    for _ in range(14):
        y = rng.integers(14, H - 6)
        x0 = rng.integers(4, W - 30)
        cv.put(line(W, H, [(x0, y), (x0 + rng.integers(6, 26), y + rng.integers(-1, 2))]) & body, "#3d3332", alpha=0.6)
    # the brass frame: 3 px band inside the edge, lit from the top-left
    inner = poly(W, H, [(15, 4), (W - 16, 4), (W - 5, 13), (W - 5, H - 5), (4, H - 5), (4, 13)])
    band = body & ~inner
    paint(cv, band, BRASS, base=2, noise=0.2, seed=seed + 2)
    edge_in = inner & ~poly(W, H, [(16, 5), (W - 17, 5), (W - 6, 14), (W - 6, H - 6), (5, H - 6), (5, 14)])
    cv.put(edge_in, BRASS[0])
    cv.put(body & ~shift(body, 0, -1) | body & ~shift(body, -1, 0), BRASS[3])
    cv.put(body & (~shift(body, 0, 1) | ~shift(body, 1, 0)), BRASS[0])
    # corner brackets and rivets
    for (x, y, dx, dy) in ((7, H - 8, 1, -1), (W - 8, H - 8, -1, -1), (7, 16, 1, 1), (W - 8, 16, -1, 1)):
        cv.put(line(W, H, [(x, y), (x + dx * 7, y)]) | line(W, H, [(x, y), (x, y + dy * 7)]), BRASS[3])
        cv.put(pixels(W, H, [(x + dx, y + dy)]), BRASS[1])
    rivets(cv, [(3, 20), (W - 4, 20), (3, H - 12), (W - 4, H - 12), (W // 2 - 20, H - 4), (W // 2 + 19, H - 4)])
    # punch hole in a heavy brass ring, a short chain up
    cx, cy = W // 2, 7
    cv.put(circle(W, H, cx - 0.5, cy - 0.5, 4.6) & body, BRASS[3])
    cv.put(circle(W, H, cx - 0.5, cy - 0.5, 4.6) & ~circle(W, H, cx - 0.5, cy - 1.5, 3.8) & body, BRASS[1])
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


# ---------------------------------------------------------------- title logo and paint splat

def _stencil_mask(word, scale):
    """Mask of `word` in the stencil font at an integer scale (1 cell gap between glyphs)."""
    rows = [_S[ch].split("|") for ch in word]
    w = sum(len(r[0]) + 1 for r in rows) - 1
    m = np.zeros((STENCIL_H * scale, w * scale), bool)
    x = 0
    for r in rows:
        for ry, row in enumerate(r):
            for rx, c in enumerate(row):
                if c == "#":
                    m[ry * scale:(ry + 1) * scale, (x + rx) * scale:(x + rx + 1) * scale] = True
        x += len(r[0]) + 1
    return m


def _spray(cv, m, ramp, seed):
    """Spray-paints mask `m`: ragged edges, overspray specks, drips and chipped paint."""
    H, W = m.shape
    rng = np.random.default_rng(seed)
    edge = m & ~(shift(m, 1, 0) & shift(m, -1, 0) & shift(m, 0, 1) & shift(m, 0, -1))
    body = m & ~(edge & (rng.random((H, W)) < 0.12))
    near = (shift(m, 1, 0) | shift(m, -1, 0) | shift(m, 0, 1) | shift(m, 0, -1)
            | shift(m, 2, 0) | shift(m, 0, 2) | shift(m, -2, 0) | shift(m, 0, -2)) & ~m
    specks = near & (rng.random((H, W)) < 0.09)
    # drips run down from a few bottom edges
    bottom = m & ~shift(m, 0, -1)
    ys, xs = np.nonzero(bottom)
    drips = np.zeros_like(m)
    for i in rng.choice(len(xs), size=max(1, len(xs) // 26), replace=False):
        x, y, n = xs[i], ys[i], int(rng.integers(3, 10))
        drips[y:min(H, y + n), x] = True
        if y + n < H:
            drips[y + n - 1:min(H, y + n + 1), x:min(W, x + 2)] = True
    paint_m = body | drips
    n = value_noise(H, W, 6, seed)
    ra = np.array([rgb(c) for c in ramp])
    lvl = np.clip((n * (len(ramp) - 0.01) + bayer(H, W) * 0.6 - 0.3).astype(int), 0, len(ramp) - 1)
    cv.put(paint_m, ra[lvl])
    cv.put(specks, ra[max(0, len(ramp) - 2)], alpha=0.55)
    # chipped paint shows the metal through
    chips = body & (value_noise(H, W, 3, seed + 7) > 0.86) & (rng.random((H, W)) < 0.5)
    cv.put(chips, RUST[2])


def logo(seed=21, words=True):
    """Title plate. words=False leaves the sheet blank: the game sets the title in its display font."""
    W, H = 316, 62
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    # two mismatched sheets, welded, with a cut-off corner and a bent lower edge
    left = poly(W, H, [(3, 6), (176, 2), (178, 57), (8, 59), (1, 32)])
    right = poly(W, H, [(176, 4), (306, 1), (314, 10), (311, 56), (178, 58)])
    paint(cv, left, RUST[:4], base=1, noise=0.45, seed=seed, depth=2)
    paint(cv, right, STEEL[:4], base=1, noise=0.4, seed=seed + 1, depth=2)
    sheet = left | right
    weather(cv, sheet, seed, holes=0, dents=6, scratches=14, streaks=10)
    weld(cv, [(177, 4), (178, 57)])
    rivets(cv, [(7, 10), (170, 7), (8, 53), (171, 52), (183, 8), (306, 7), (184, 52), (305, 51)]
           + [(40 + 33 * i, 6 - i // 3) for i in range(4)] + [(214 + 30 * i, 5) for i in range(3)])
    if not words:
        for _ in range(9):
            cx, cy = rng.uniform(12, W - 12), rng.uniform(10, H - 10)
            if cy > 14 and cy < 50:  # keep the lettering band clear of holes
                continue
            rim = circle(W, H, cx, cy, 2.4) & sheet
            cv.put(rim & ~shift(rim, -1, -1), STEEL[4])
            cv.put(rim & ~shift(rim, 1, 1), RUST[0])
            cv.a[circle(W, H, cx, cy, 1.3)] = 0
        outline(cv, OUTLINE)
        return cv
    # the words, stencilled across the seam
    scale = 4
    a = _stencil_mask("BULLET", scale)
    b = _stencil_mask("HWAVEN", scale)
    gap = 10
    tw = a.shape[1] + gap + b.shape[1]
    x0, y0 = (W - tw) // 2, 15
    ma = np.zeros((H, W), bool)
    mb = np.zeros((H, W), bool)
    ma[y0:y0 + a.shape[0], x0:x0 + a.shape[1]] = a
    xb = x0 + a.shape[1] + gap
    mb[y0:y0 + b.shape[0], xb:xb + b.shape[1]] = b
    _spray(cv, ma & sheet, BONE[3:], seed + 3)
    _spray(cv, mb & sheet, FIRE[3:6], seed + 4)
    # bullet holes punched through sheet and paint, lit from the top-left
    for _ in range(9):
        cx, cy = rng.uniform(12, W - 12), rng.uniform(10, H - 10)
        rim = circle(W, H, cx, cy, 2.4) & sheet
        cv.put(rim & ~shift(rim, -1, -1), STEEL[4])
        cv.put(rim & ~shift(rim, 1, 1), RUST[0])
        hole = circle(W, H, cx, cy, 1.3)
        cv.a[hole] = 0
    outline(cv, OUTLINE)
    return cv


def splat(seed=4):
    """16x16 paint splat in light greys (tinted by the game): a blob with spatters and one drip."""
    N2 = 16
    cv = Canvas(N2, N2)
    rng = np.random.default_rng(seed)
    m = blob(N2, N2, 7.5, 7.0, 5.2, 4.8, rough=0.25, seed=seed, cell=3)
    for _ in range(5):
        a = rng.uniform(0, 2 * np.pi)
        d = rng.uniform(5.5, 7.0)
        m |= circle(N2, N2, 7.5 + np.cos(a) * d, 7.0 + np.sin(a) * d, rng.uniform(0.6, 1.2))
    m |= rect(N2, N2, 9, 10, 9, 14)
    m |= rect(N2, N2, 9, 14, 10, 14)
    ramp = ["#8a8a8a", "#b4b4b4", "#dcdcdc", "#ffffff"]
    paint(cv, m, ramp, base=2, noise=0.2, seed=seed)
    cv.put(circle(N2, N2, 5.5, 5.0, 1.2) & m, "#ffffff")
    outline(cv, OUTLINE)
    return cv
