"""Layered player rig: hull base + bolt-on attachment layers (design doc 11b, playtest round 1 #6).

Every layer is drawn facing north on the same RIG_W x RIG_H canvas whose centre is the sim position,
so after RotSprite every layer's frame k lines up with the hull's frame k: the game just stacks
sprites that show the same frame (anchor points per direction come for free). Things that turn on
their own (guns, the trailer) or are animated (nitro flames) get their own strips and anchors in
RIG_ANCHORS (mirrored in game/render/rig_art.gd).

Footprints: "A" is the starter buggy (36x52, engineering tiers 0-1), "B" the stretched six-wheel
truck (36x64, engineering tier 2+). Tier 3 adds an articulated trailer with the third gun mount.

Paint: layers are drawn with a probe paint ramp and then paint-keyed (see paint_key): every pixel
that depends on the paint becomes a key colour (255, 0, 8 + 16 * step) that the game's paint
shader swaps for the owner's PLAYERS ramp, so one strip serves all eight paint jobs.
"""

import math

import numpy as np

from palette import (BONE, BRASS, BURLAP, FIRE, GLASS, HAZARD, KHAKI, LEATHER, OUTLINE, PLAYERS, RUST,
                     STEEL, TYRE)
from pixel import Canvas, blob, circle, ellipse, line, paint, pixels, polar, poly, rect, rgb, shift
from sprites import (ammo_belt, barbed, chain, chip, hazard_stripes, headlight, px, rivets, sandbag, shade,
                     tarp, weather, weld, wheel)

RIG_W, RIG_H = 72, 80  # wide enough for the sidecar and the dozer blade (the frame stays 80x80)
RIG_FRAME = 80
TRAILER_W, TRAILER_H = 40, 48
TRAILER_FRAME = 64
GUN_FRAME = 40
FLAME_FRAME = 32

PROBE_A = PLAYERS["red"]
PROBE_B = PLAYERS["green"]
PAINT_STEPS = 5


class Foot:
    def __init__(self, name, oy, length, wheels, flank, plate_slots, deck=None, engine_y=None, bed=None):
        self.name, self.ox, self.oy, self.L = name, (RIG_W - 36) // 2, oy, length
        self.wheels = wheels  # (x, y, w, h, side) in footprint coordinates
        self.flank = flank  # y range of the free flank between the first two axles
        self.plate_slots = plate_slots  # flank plate y ranges per steel-plates level
        self.deck = deck  # B: flatbed y range
        self.engine_y = length - 15 if engine_y is None else engine_y  # top of the engine block (P: under the hood)
        self.bed = bed  # P: open load bed y range


FOOT_A = Foot("A", 14, 52, [(3, 8, 7, 11, "L"), (26, 8, 7, 11, "R"), (2, 33, 8, 13, "L"), (26, 33, 8, 13, "R")],
              (20, 31), [[(19, 31)], [(33, 46)], [(6, 18)]])
FOOT_B = Foot("B", 8, 64, [(3, 8, 7, 11, "L"), (26, 8, 7, 11, "R"), (2, 33, 8, 12, "L"), (26, 33, 8, 12, "R"),
                           (2, 48, 8, 13, "L"), (26, 48, 8, 13, "R")],
              (20, 31), [[(19, 31)], [(33, 45), (47, 60)], [(6, 18)]], deck=(37, 48))
# Pickup (chassis 2): front engine under a long hood, closed cab, open load bed, four big wheels.
FOOT_P = Foot("P", 11, 58, [(3, 6, 7, 11, "L"), (26, 6, 7, 11, "R"), (2, 40, 8, 13, "L"), (26, 40, 8, 13, "R")],
              (19, 37), [[(19, 37)], [(39, 54)], [(4, 16)]], engine_y=5, bed=(31, 54))
FEET = [FOOT_A, FOOT_B, FOOT_P]  # row groups of every hull strip (render: RigArt footprint index)


def _rel(foot, x, y):
    """Footprint coordinates -> offset from the rig centre (facing north)."""
    return (x + foot.ox - RIG_W / 2, y + foot.oy - RIG_H / 2)


SIDECAR_X = (39, 50)  # sidecar tub, footprint x range (right of the hull)


def _sidecar_y(foot):
    return (foot.flank[0] - 3, foot.flank[1] + 5)


# Anchors relative to the rig centre, facing north (px). Mirrored in game/render/rig_art.gd.
# mounts: hull gun rings in fill order (cab / cockpit, deck or bed, then the extras).
RIG_ANCHORS = {
    "A": {"mounts": [_rel(FOOT_A, 17.5, 22), _rel(FOOT_A, 17.5, 11), _rel(FOOT_A, 17.5, 42), _rel(FOOT_A, 17.5, 31)],
          "exhausts": [_rel(FOOT_A, 9, 51), _rel(FOOT_A, 26, 51)],
          "rear_wheels": [_rel(FOOT_A, 5.5, 40), _rel(FOOT_A, 29.5, 40)],
          "hitch": _rel(FOOT_A, 17.5, 52)},
    "B": {"mounts": [_rel(FOOT_B, 17.5, 22), _rel(FOOT_B, 17.5, 42.5), _rel(FOOT_B, 17.5, 10), _rel(FOOT_B, 17.5, 55)],
          "exhausts": [_rel(FOOT_B, 9, 63), _rel(FOOT_B, 26, 63)],
          "rear_wheels": [_rel(FOOT_B, 5.5, 55), _rel(FOOT_B, 29.5, 55)],
          "hitch": _rel(FOOT_B, 17.5, 64)},
    "P": {"mounts": [_rel(FOOT_P, 17.5, 23), _rel(FOOT_P, 17.5, 40), _rel(FOOT_P, 17.5, 50), _rel(FOOT_P, 17.5, 9)],
          "exhausts": [_rel(FOOT_P, 9, 57), _rel(FOOT_P, 26, 57)],
          "rear_wheels": [_rel(FOOT_P, 5.5, 47), _rel(FOOT_P, 29.5, 47)],
          "hitch": _rel(FOOT_P, 17.5, 58)},
}
for _f in FEET:
    _y0, _y1 = _sidecar_y(_f)
    RIG_ANCHORS[_f.name]["sidecar"] = _rel(_f, (SIDECAR_X[0] + SIDECAR_X[1]) / 2, (_y0 + _y1) / 2)
TRAILER_MOUNTS = [(0.0, 0.0), (0.0, 13.0)]  # guns on the trailer, relative to the trailer centre
TRAILER_MOUNT = TRAILER_MOUNTS[0]
TRAILER_TONGUE = 26.0  # hitch -> trailer centre (px)
GUN_KINDS = ["mg", "shotgun", "cannon", "flamer"]
BARREL = {"mg": [14, 15, 15], "shotgun": [10, 11, 11], "cannon": [16, 18, 20], "flamer": [10, 10, 11]}


class P:
    """Pen that draws in footprint coordinates onto a rig canvas."""

    def __init__(self, cv, foot):
        self.cv, self.f = cv, foot
        self.ox, self.oy = foot.ox, foot.oy

    def xy(self, x, y):
        return (x + self.ox, y + self.oy)

    def pts(self, pts):
        return [self.xy(x, y) for x, y in pts]

    def rect(self, x0, y0, x1, y1):
        return rect(self.cv.w, self.cv.h, x0 + self.ox, y0 + self.oy, x1 + self.ox, y1 + self.oy)

    def poly(self, pts):
        return poly(self.cv.w, self.cv.h, self.pts(pts))

    def line(self, pts, width=1):
        return line(self.cv.w, self.cv.h, self.pts(pts), width)

    def ellipse(self, x0, y0, x1, y1):
        return ellipse(self.cv.w, self.cv.h, x0 + self.ox, y0 + self.oy, x1 + self.ox, y1 + self.oy)

    def circle(self, cx, cy, r):
        return circle(self.cv.w, self.cv.h, cx + self.ox, cy + self.oy, r)

    def pix(self, pts):
        return pixels(self.cv.w, self.cv.h, [(round(x + self.ox), round(y + self.oy)) for x, y in pts])

    def blob(self, cx, cy, rx, ry, rough=0.15, seed=0, cell=4):
        return blob(self.cv.w, self.cv.h, cx + self.ox, cy + self.oy, rx, ry, rough, seed, cell)


def new_rig():
    return Canvas(RIG_W, RIG_H)


# ---------------------------------------------------------------- paint keying

def paint_key(build):
    """build(ramp) -> Canvas. Pixels that change with the paint ramp become paint keys."""
    a, b = build(PROBE_A), build(PROBE_B)
    diff = (np.abs(a.rgb - b.rgb).max(axis=2) > 1.0) & a.solid()
    if diff.any():
        ra = np.stack([rgb(c) for c in PROBE_A])
        d = ((a.rgb[diff][:, None, :] - ra[None, :, :]) ** 2).sum(axis=2)
        k = d.argmin(axis=1)
        keys = np.stack([np.full_like(k, 255), np.zeros_like(k), 8 + 16 * k], axis=1).astype(np.float32)
        a.rgb[diff] = keys
    return a


def apply_paint(cv, ramp):
    """Resolve paint keys with a PLAYERS ramp (for flat previews and the menu buggy strips)."""
    out = Canvas(cv.w, cv.h)
    out.rgb, out.a, out.emit = cv.rgb.copy(), cv.a.copy(), cv.emit.copy()
    key = (cv.rgb[..., 0] > 254) & (cv.rgb[..., 1] < 1) & cv.solid()
    idx = np.clip(((cv.rgb[..., 2] - 8) / 16).round().astype(int), 0, PAINT_STEPS - 1)
    ra = np.stack([rgb(c) for c in ramp])
    out.rgb[key] = ra[idx[key]]
    return out


def ramps_texture():
    """PAINT_STEPS x 8 texture: row = SimVehicle.color_index, column = paint step."""
    cv = Canvas(PAINT_STEPS, len(PLAYERS))
    for j, ramp in enumerate(PLAYERS.values()):
        for i, c in enumerate(ramp):
            cv.rgb[j, i] = rgb(c)
            cv.a[j, i] = 1
    return cv


# ---------------------------------------------------------------- running gear

def _track(cv, p, x, y0, y1, side, seed):
    """Caterpillar track: steel-cleated tread loop with sprockets at both ends and a rusty guard."""
    w = 8
    paint(cv, p.rect(x, y0, x + w - 1, y1), TYRE, base=1)
    ys = np.arange(cv.h)[:, None]
    for yy in range(y0 + 1, y1, 2):
        cv.put(p.rect(x + 1, yy, x + w - 2, yy), TYRE[3])
        px(cv, [p.xy(x + 1 + (yy // 2) % 2 * (w - 3), yy)], STEEL[3])
    outer = x if side == "L" else x + w - 1
    cv.put(p.rect(outer, y0 + 1, outer, y1 - 1), TYRE[0])
    for cy in (y0 + 3, y1 - 3):
        paint(cv, p.circle(x + w / 2 - 0.5, cy, 2.6), STEEL[1:], base=2)
        px(cv, [p.xy(x + w // 2 - 1, cy), p.xy(x + w // 2, cy)], STEEL[0])
    guard = p.rect(x + (2 if side == "L" else 0), y0 + 6, x + w - (1 if side == "L" else 3), y1 - 6)
    paint(cv, guard, RUST, base=2, noise=0.4, seed=seed)
    weather(cv, guard, seed, holes=1, scratches=2, streaks=1)
    cv.put(p.rect(x + (2 if side == "L" else 0), y0 + 6, x + w - (1 if side == "L" else 3), y0 + 6), RUST[4])


def gear(foot, kind, seed=1):
    """kind: 'wheels', 'offroad' (oversized paddle tyres) or 'tracks'."""
    cv = new_rig()
    p = P(cv, foot)
    if kind == "tracks":
        for side, x in (("L", 1), ("R", 27)):
            _track(cv, p, x, 6, foot.L - 5, side, seed + x)
        for y in (13, foot.L - 12):
            cv.put(p.line([(9, y), (26, y)], 2), STEEL[1])
        return cv
    for x, y, w, h, side in foot.wheels:
        if kind == "offroad":
            x, y, w, h = (x - 1 if side == "L" else x), y - 1, w + 1, h + 2
        wheel(cv, x + p.ox, y + p.oy, w, h, side)
        if kind == "offroad":  # chunky paddles poking out of the tread
            outer = x - 1 if side == "L" else x + w
            for yy in range(y + 1, y + h - 1, 3):
                px(cv, [p.xy(outer, yy)], TYRE[2])
        cy = y + h // 2
        a, b = ((x + w - 1, cy), (x + w + 3, cy)) if side == "L" else ((x, cy), (x - 4, cy))
        cv.put(p.line([a, b], 2), STEEL[1])
    return cv


# ---------------------------------------------------------------- hull body

BODY_STYLES = ["buggy", "buggy_frame", "truck", "pickup", "warrig"]  # rows of rig_body.png
STYLE_FOOT = {"buggy": FOOT_A, "buggy_frame": FOOT_A, "truck": FOOT_B, "pickup": FOOT_P, "warrig": FOOT_B}


def body(pc, style, seed=1):
    """Welded scrap hull per chassis (design doc 11b): open buggy (bare, then with the welded frame:
    canopy, cage, rear rack), pickup (front engine, closed cab, open bed), six-wheel truck (closed cab,
    flatbed) and the war rig tractor (armoured cab, exhaust stacks, heavy bumper)."""
    foot = STYLE_FOOT[style]
    if style == "pickup":
        return _pickup(pc, foot, seed)
    tier = 0 if style == "buggy" else 1
    closed = style in ("truck", "warrig")
    war = style == "warrig"
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    fy0 = foot.flank[0] + 1
    if not war:  # spare tyre strapped to the left flank, jerrycan to the right
        paint(cv, p.rect(3, fy0, 6, fy0 + 9), TYRE, base=2)
        cv.put(p.rect(4, fy0 + 1, 5, fy0 + 8), TYRE[0])
        cv.put(p.rect(3, fy0 + 4, 6, fy0 + 4), LEATHER[2])
        paint(cv, p.rect(28, fy0, 32, fy0 + 8), RUST[1:], base=2, noise=0.3, seed=seed)
        px(cv, p.pts([(30, fy0), (31, fy0)]), STEEL[1])
        cv.put(p.rect(28, fy0 + 4, 32, fy0 + 4), LEATHER[1])
    else:  # armoured side skirts with barbed wire
        for x0, bx in ((3, 2), (28, 33)):
            sk = p.rect(x0, fy0 - 1, x0 + 4, fy0 + 10)
            paint(cv, sk, STEEL, noise=0.3, seed=seed + x0)
            weather(cv, sk, seed + x0, holes=1, scratches=2)
            rivets(cv, p.pts([(x0 + 1, fy0), (x0 + 3, fy0 + 9)]))
            barbed(cv, p.xy(bx, fy0), p.xy(bx, fy0 + 9))
    # body tub with a painted rim along the flanks
    tub = p.poly([(11, 5), (24, 5), (28, 10), (28, L - 9), (25, L - 5), (10, L - 5), (7, L - 9), (7, 10)])
    paint(cv, tub, RUST, noise=0.4, seed=seed, depth=2)
    inner = p.poly([(12, 7), (23, 7), (26, 11), (26, L - 10), (24, L - 7), (11, L - 7), (9, L - 10), (9, 11)])
    rim = tub & ~inner & p.rect(0, 18, 35, L - 8)
    paint(cv, rim, pc, base=2)
    chip(cv, rim, 0.22, seed + 4, RUST[2])
    # salvaged hood plates, both in paint (different coats), welded together
    left = p.poly([(11, 6), (17, 6), (17, 18), (9, 18), (9, 11)])
    right = p.poly([(18, 6), (24, 6), (26, 11), (26, 18), (18, 18)])
    if war:  # armoured hood: steel centre plate between painted cheeks
        paint(cv, left, pc, base=2, noise=0.3, seed=seed + 1)
        paint(cv, right, pc, base=2, noise=0.35, seed=seed + 2)
        mid = p.rect(14, 6, 21, 18)
        paint(cv, mid, STEEL, base=3, noise=0.3, seed=seed + 5)
        rivets(cv, p.pts([(15, 8), (20, 8), (15, 16), (20, 16)]))
        weld(cv, p.pts([(14, 6), (14, 18)]))
        weld(cv, p.pts([(21, 6), (21, 18)]))
    else:
        paint(cv, left, pc, base=3, noise=0.3, seed=seed + 1)
        paint(cv, right, pc, base=2, noise=0.35, seed=seed + 2)
        cv.put(p.line([(19, 17), (25, 11)], 1) & right, KHAKI[3])  # a stripe of the old olive coat
        weld(cv, p.pts([(17, 6), (17, 18)]))
    chip(cv, left, 0.12, seed, STEEL[2])
    chip(cv, right, 0.18, seed + 3, STEEL[3])
    weld(cv, p.pts([(9, 19), (26, 19)]))
    weather(cv, tub | left | right, seed, holes=4, dents=3, scratches=6, streaks=4)
    rivets(cv, p.pts([(10, 12), (25, 12), (10, 16), (25, 16)]))
    headlight(cv, *p.xy(11, 8))
    headlight(cv, *p.xy(24, 8), broken=True)
    if war:  # heavy bumper with hazard stripes and corner horns
        bum = p.rect(5, 1, 30, 4)
        paint(cv, bum, STEEL, base=3, noise=0.3, seed=seed + 9)
        hazard_stripes(cv, p.rect(8, 2, 27, 3))
        for x in (5, 30):
            paint(cv, p.poly([(x - 1, 4), (x + 1, 4), (x, -1)]), STEEL[1:], base=3)
    else:  # ram bar
        paint(cv, p.line([(7, 4), (28, 4)], 2), STEEL, base=3)
        for x in (8, 13, 22, 27):
            paint(cv, p.poly([(x - 1, 4), (x + 1, 4), (x, 1)]), STEEL[1:], base=2)
    if closed:
        _cab(cv, p, pc, war, seed)
    else:
        # open cockpit: seat back, jacket, helmet, scarf in paint
        paint(cv, p.rect(10, 20, 25, 35), STEEL[:3], base=1, light=False)
        paint(cv, p.rect(14, 30, 21, 34), LEATHER[:3], base=1)
        paint(cv, p.ellipse(12, 25, 23, 31), LEATHER, base=1, noise=0.3, seed=seed)
        cv.put(p.rect(15, 30, 20, 30), pc[1])
        px(cv, p.pts([(21, 31), (22, 32)]), pc[1])
        paint(cv, p.circle(17.5, 27, 2.3), STEEL, base=3)
        if tier >= 1:  # sun canopy in paint over the back of the cockpit
            can = p.rect(10, 31, 25, 35)
            paint(cv, can, pc, base=2, noise=0.3, seed=seed + 7)
            for x in (13, 17, 21):
                cv.put(p.rect(x, 31, x, 35) & can, pc[1])
        for seg in [[(9, 20), (26, 20)], [(9, 36), (26, 36)], [(9, 20), (9, 36)], [(26, 20), (26, 36)]]:
            paint(cv, p.line(seg, 1), STEEL, base=3, light=False)
        if tier >= 1:
            for seg in [[(9, 20), (26, 36)], [(26, 20), (9, 36)]]:
                cv.put(p.line(seg, 1) & ~p.rect(12, 24, 23, 32), STEEL[3])
            # the welded frame: fresh seams along the tub and over the hood
            for seg in ([(8, 11), (8, L - 10)], [(27, 11), (27, L - 10)], [(10, 13), (25, 13)]):
                weld(cv, p.pts(seg))
        px(cv, p.pts([(9, 20), (26, 20), (9, 36), (26, 36)]), STEEL[5])
        barbed(cv, p.xy(8, 22), p.xy(8, 34))
    # B: flatbed between the cab and the engine (gun mount 2)
    if foot.deck:
        d0, d1 = foot.deck
        bed = p.rect(9, d0, 26, d1)
        paint(cv, bed, STEEL[:4], base=2, noise=0.3, seed=seed + 11)
        for yy in range(d0 + 1, d1, 3):
            cv.put(p.pix([(x, yy + (x // 3) % 2) for x in range(10, 26, 3)]), STEEL[3])
        for x, y in [(10, d0 + 1), (22, d0 + 6)]:
            paint(cv, p.rect(x, y, x + 3, y + 4), KHAKI, base=2, noise=0.2, seed=x + y)
            cv.put(p.rect(x, y + 2, x + 3, y + 2), KHAKI[1])
        paint(cv, p.circle(17.5, (d0 + d1) / 2, 4.5), STEEL[1:4], base=1, light=False)  # turret ring
        weld(cv, p.pts([(9, d1 + 1), (26, d1 + 1)]))
    # exposed rear engine: cylinder heads, air filter, exhausts
    e0 = L - 15
    paint(cv, p.rect(11, e0, 24, e0 + 9), STEEL, noise=0.25, seed=seed + 3, depth=2)
    for i in range(3):
        paint(cv, p.rect(12, e0 + 1 + i * 3, 14, e0 + 2 + i * 3), STEEL, base=4)
        paint(cv, p.rect(21, e0 + 1 + i * 3, 23, e0 + 2 + i * 3), STEEL, base=4)
    paint(cv, p.circle(17.5, e0 + 4.5, 2.3), STEEL[1:], base=3)
    px(cv, p.pts([(17, e0 + 4), (18, e0 + 5)]), STEEL[0])
    for pts in ([(12, L - 7), (9, L - 4), (9, L - 1)], [(23, L - 7), (26, L - 4), (26, L - 1)]):
        paint(cv, p.line(pts, 2), RUST[1:], base=2)
        px(cv, [p.xy(*pts[-1])], OUTLINE)
    if tier >= 1:  # rear bumper with a jerrycan rack
        paint(cv, p.line([(5, L - 3), (30, L - 3)], 2), STEEL, base=2)
        for x in (4, 28):
            paint(cv, p.rect(x, L - 6, x + 3, L), RUST[1:] if x < 20 else KHAKI, base=2, noise=0.3, seed=seed + x)
            px(cv, p.pts([(x + 1, L - 6)]), STEEL[1])
    # antenna with a tattered flag in paint
    px(cv, p.pts([(27, L - 8)]), STEEL[1])
    paint(cv, p.poly([(27, L - 8), (32, L - 7), (30, L - 6), (32, L - 3), (28, L - 3)]), pc, base=3)
    if not closed:  # pintle MG ammo box
        paint(cv, p.rect(21, 21, 24, 24), KHAKI, base=2)
        ammo_belt(cv, p.pts([(21, 22), (19, 22)]))
    if war:  # exhaust stacks either side of the cab, sooted
        for sx in (4.5, 30.5):
            soot = p.circle(sx, 18, 3.5)
            shade(cv, soot & ~tub, 0.55)
            paint(cv, p.circle(sx, 18, 2.4), STEEL[:4], base=2)
            cv.put(p.circle(sx, 18, 0.9), OUTLINE)
    return cv


def _cab(cv, p, pc, war, seed):
    """Closed cab over the cockpit (truck, war rig): windscreen, painted (or armoured) roof, gun ring."""
    cab = p.rect(9, 20, 26, 36)
    if war:
        paint(cv, p.rect(9, 20, 17, 36), STEEL, noise=0.3, seed=seed + 5, depth=2)
        paint(cv, p.rect(18, 20, 26, 36), RUST, base=2, noise=0.4, seed=seed + 6, depth=2)
        stripe = p.rect(9, 30, 26, 31)
        paint(cv, stripe, pc, base=2, light=False)
        chip(cv, stripe, 0.35, seed + 1, STEEL[2])
        weld(cv, p.pts([(17, 20), (17, 36)]))
        rivets(cv, p.pts([(10, 23), (25, 23), (10, 35), (25, 35)]))
        cv.put(p.rect(10, 20, 25, 21), OUTLINE)  # slit windscreen behind a welded mesh
        for x in range(10, 26, 3):
            cv.put(p.rect(x, 20, x, 21), STEEL[3])
        px(cv, p.pts([(13, 21), (22, 21)]), GLASS[1])
    else:
        paint(cv, cab, pc, base=2, noise=0.3, seed=seed + 5, depth=2)
        chip(cv, cab, 0.15, seed + 6, STEEL[2])
        cv.put(p.rect(10, 20, 25, 21), OUTLINE)  # windscreen
        px(cv, p.pts([(12, 20), (13, 21), (21, 20)]), GLASS[1])
        px(cv, p.pts([(11, 20)]), GLASS[3])
        weld(cv, p.pts([(9, 33), (26, 33)]))
        for x in (9, 26):  # dark side windows
            cv.put(p.rect(x, 23, x, 28), OUTLINE)
        paint(cv, p.rect(19, 30, 24, 32), STEEL, base=2)  # roof box
    weather(cv, cab, seed + 7, holes=2, dents=2, scratches=3, streaks=2)
    paint(cv, p.circle(17.5, 25.5, 4.5), STEEL[1:4], base=1, light=False)  # roof gun ring
    px(cv, p.pts([(6, 21), (29, 21)]), STEEL[3])  # mirrors
    px(cv, p.pts([(5, 21), (30, 21)]), STEEL[1])


def _pickup(pc, foot, seed):
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    b0, b1 = foot.bed
    # running boards between the axles
    for x0 in (5, 28):
        paint(cv, p.rect(x0, 19, x0 + 2, 37), STEEL[:4], base=2, noise=0.3, seed=seed + x0)
    tub = p.poly([(10, 3), (25, 3), (28, 7), (28, L - 4), (26, L - 2), (9, L - 2), (7, L - 4), (7, 7)])
    paint(cv, tub, RUST, noise=0.4, seed=seed, depth=2)
    # long hood over the front engine, two painted panels with a louvred centre strip
    hl = p.poly([(10, 4), (17, 4), (17, 15), (8, 15), (8, 8)])
    hr = p.poly([(18, 4), (25, 4), (27, 8), (27, 15), (18, 15)])
    paint(cv, hl, pc, base=3, noise=0.3, seed=seed + 1)
    paint(cv, hr, pc, base=2, noise=0.35, seed=seed + 2)
    chip(cv, hl, 0.12, seed, STEEL[2])
    chip(cv, hr, 0.2, seed + 3, STEEL[3])
    for yy in (7, 9, 11, 13):
        cv.put(p.rect(15, yy, 20, yy), pc[0])
    weld(cv, p.pts([(17, 4), (17, 15)]))
    cv.put(p.line([(19, 14), (26, 8)], 1) & hr, KHAKI[3])
    headlight(cv, *p.xy(10, 5))
    headlight(cv, *p.xy(25, 5))
    # bull bar
    paint(cv, p.line([(6, 2), (29, 2)], 2), STEEL, base=3)
    for x in (6, 29):
        paint(cv, p.line([(x, 2), (x, 6)], 2), STEEL, base=2)
    # windscreen and closed cab with a painted roof
    cv.put(p.rect(9, 16, 26, 17), OUTLINE)
    px(cv, p.pts([(11, 16), (12, 17), (20, 16), (21, 17)]), GLASS[1])
    px(cv, p.pts([(10, 16)]), GLASS[3])
    roof = p.rect(9, 18, 26, 29)
    paint(cv, roof, pc, base=2, noise=0.3, seed=seed + 5, depth=2)
    chip(cv, roof, 0.15, seed + 6, STEEL[2])
    for x in (9, 26):
        cv.put(p.rect(x, 20, x, 26), OUTLINE)
    paint(cv, p.circle(17.5, 23, 4.5), STEEL[1:4], base=1, light=False)  # roof gun ring
    cv.put(p.rect(10, 29, 25, 30), OUTLINE)  # rear window
    px(cv, p.pts([(6, 18), (29, 18)]), STEEL[3])  # mirrors
    px(cv, p.pts([(5, 18), (30, 18)]), STEEL[1])
    # open load bed: ribbed floor, painted side boards, tailgate
    floor = p.rect(9, b0, 26, b1)
    paint(cv, floor, STEEL[:4], base=1, noise=0.3, seed=seed + 11)
    for x in (11, 14, 21, 24):
        cv.put(p.rect(x, b0 + 1, x, b1 - 1), STEEL[2])
    for x0 in (7, 27):
        board = p.rect(x0, b0, x0 + 1, b1 + 1)
        paint(cv, board, pc, base=2, noise=0.3, seed=seed + x0, light=False)
        chip(cv, board, 0.3, seed + x0, RUST[2])
        rivets(cv, p.pts([(x0, b0 + 2), (x0, b1 - 2)]))
    gate = p.rect(8, b1 + 1, 27, b1 + 3)
    paint(cv, gate, RUST, base=3, noise=0.3, seed=seed + 12)
    hazard_stripes(cv, p.rect(11, b1 + 2, 24, b1 + 2))
    paint(cv, p.circle(17.5, 40, 4.5), STEEL[1:4], base=1, light=False)  # bed gun ring
    paint(cv, p.rect(10, 46, 14, 50), KHAKI, base=2, noise=0.2, seed=seed + 13)  # ammo crate
    cv.put(p.rect(10, 48, 14, 48), KHAKI[1])
    tarp(cv, 19, 46, 25, 52, seed + 3)
    weather(cv, tub | hl | hr | roof, seed, holes=4, dents=3, scratches=6, streaks=4)
    # exhausts run under the bed and poke out at the back
    for x in (9, 26):
        paint(cv, p.line([(x, L - 5), (x, L - 1)], 2), RUST[1:], base=2)
        px(cv, [p.xy(x, L - 1)], OUTLINE)
    # antenna with a tattered flag in paint on the cab corner
    px(cv, p.pts([(26, 29)]), STEEL[1])
    paint(cv, p.poly([(26, 29), (31, 30), (29, 31), (31, 33), (27, 33)]), pc, base=3)
    return cv


def body_for_tier(tier):
    """Sample / preview builds: tier 0 bare buggy, 1 framed buggy, 2 pickup, 3 truck, 4 war rig."""
    style = ["buggy", "buggy_frame", "pickup", "truck", "warrig"][max(0, min(tier, 4))]
    return STYLE_FOOT[style], style


# ---------------------------------------------------------------- armour layers

def steel_plates(pc, foot, level, seed=31):
    """Bolted flank plates, the middle ones in paint; more of the flank per level."""
    cv = new_rig()
    p = P(cv, foot)
    for li in range(level):
        for (y0, y1) in foot.plate_slots[li]:
            for side, (x0, x1) in (("L", (0, 7)), ("R", (28, 35))):
                m = p.poly([(x0, y0 + 1), (x0 + 1, y0), (x1, y0), (x1, y1), (x0 + 1, y1), (x0, y1 - 1)])
                if li == 0:
                    paint(cv, m, pc, base=3, noise=0.3, seed=seed + y0 + x0)
                    chip(cv, m, 0.2, seed + y0 + x0, STEEL[3])
                    cv.put(p.rect(x0, (y0 + y1) // 2, x1, (y0 + y1) // 2 + 1) & m, STEEL[2])  # welded strap
                else:
                    paint(cv, m, STEEL, base=3, noise=0.35, seed=seed + y0 + x0)
                    band = p.rect(x0 + 2, y0, x0 + 4, y1) if side == "L" else p.rect(x1 - 4, y0, x1 - 2, y1)
                    paint(cv, band & m, pc, base=2, light=False)
                    chip(cv, band & m, 0.3, seed + y1, STEEL[2])
                weather(cv, m, seed + y0 + x0, holes=1, dents=1, scratches=2, streaks=1)
                rivets(cv, p.pts([(x0 + 1, y0 + 1), (x1 - 1, y0 + 1), (x0 + 1, y1 - 2), (x1 - 1, y1 - 2)]))
    return cv


def reinforced(foot, level, seed=41):
    """Welded girders: a heavy front bumper, then a rear girder, then braced flanks and a hood slab."""
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    girder = p.rect(3, 0, 32, 3)
    paint(cv, girder, STEEL, base=3, noise=0.3, seed=seed)
    hazard_stripes(cv, p.rect(12, 1, 23, 2))
    rivets(cv, p.pts([(5, 1), (30, 1)]))
    weather(cv, girder, seed, holes=1, scratches=2)
    if level >= 2:
        rg = p.rect(4, L - 4, 31, L - 2)
        paint(cv, rg, STEEL, base=2, noise=0.3, seed=seed + 1)
        rivets(cv, p.pts([(6, L - 4), (29, L - 4)]))
        for x in (8, 27):  # gussets back to the chassis
            cv.put(p.line([(x, L - 4), (x + (2 if x < 17 else -2), L - 8)], 2), STEEL[2])
    if level >= 3:
        for y in (19, L - 17):  # cross girders welded over the tub, sticking out past the flanks
            gm = p.rect(5, y - 1, 30, y + 1)
            paint(cv, gm, STEEL, base=2, noise=0.25, seed=seed + y)
            cv.put(p.rect(5, y, 30, y), STEEL[4])
            rivets(cv, p.pts([(6, y - 1), (29, y - 1)]))
        for x in (3, 32):  # corner posts on the front bumper
            paint(cv, p.rect(x - 1, -1, x + 1, 5), STEEL, base=3)
    return cv


def ablative(foot, level, seed=51):
    """Rough slabs of rusty scrap and old tyres strapped on, to be shot off."""
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    rng = np.random.default_rng(seed)

    def slab(pts, sd):
        m = p.poly(pts)
        paint(cv, m, RUST if sd % 3 else STEEL, base=2, noise=0.5, seed=sd)
        weather(cv, m, sd, holes=2, dents=1, scratches=2, streaks=2)
        ys, xs = np.nonzero(m)
        if len(xs):
            cx, cy = int(xs.mean()), int(ys.mean())
            px(cv, [(cx, cy)], STEEL[5])
        return m

    for x0, s in ((1, 1), (34, -1)):  # rear quarters
        slab([(x0, L - 13), (x0 + 6 * s, L - 14), (x0 + 8 * s, L - 4), (x0 + 1 * s, L - 3)], seed + x0)
        chain(cv, p.pts([(x0 + 3 * s, L - 14), (x0 + 5 * s, L - 17)]))
    if level >= 2:
        for x0, s in ((2, 1), (33, -1)):  # front corners
            slab([(x0, 2), (x0 + 7 * s, 1), (x0 + 8 * s, 6), (x0 + 1 * s, 7)], seed + 10 + x0)
    if level >= 3:
        for cx in (0.5, 34.5):  # tyres hung on the flanks
            cy = foot.flank[0] + 5
            paint(cv, p.circle(cx, cy, 4.2), TYRE, base=2)
            cv.put(p.circle(cx, cy, 1.6), TYRE[0])
            cv.put(p.pix([(cx - 1, cy - 3), (cx + 1, cy - 3)]), TYRE[3])
        for i, (x, y) in enumerate([(11, L - 4), (19, L - 4)]):
            sandbag(cv, *p.xy(x, y), *p.xy(x + 6, y + 3), seed + i)
    return cv


def spikes(foot, level, seed=61):
    """Welded spikes; they get longer and more numerous per level."""
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    ln = [3, 5, 6][level - 1]

    def spike(x, y, ang, length, w=1.2):
        tip = polar(x, y, ang, length)
        b1 = polar(x, y, ang + math.pi / 2, w)
        b2 = polar(x, y, ang - math.pi / 2, w)
        m = p.poly([b1, tip, b2])
        paint(cv, m, STEEL[1:], base=3)
        tx, ty = polar(x, y, ang, length - 0.5)
        px(cv, [p.xy(round(tx), round(ty))], STEEL[5])
        bx, by = polar(x, y, ang, 0.5)
        px(cv, [p.xy(round(bx), round(by))], RUST[2])

    fronts = [8, 13, 17.5, 22, 27] if level < 3 else [6, 10, 14, 17.5, 21, 25, 29]
    for x in fronts:
        spike(x, 4, (x - 17.5) * 0.03, ln + (1 if abs(x - 17.5) < 3 else 0))
    for x, s in ((1, -1), (34, 1)):  # flanks, pointing out
        ys = [foot.flank[0] + 2, foot.flank[1] - 2]
        if level >= 2:
            ys.append(L - 12)
        if level >= 3:
            ys += [(foot.flank[0] + foot.flank[1]) / 2, L - 20]
        for y in ys:
            spike(x, y, s * math.pi / 2, ln - 1)
    if level >= 2:  # rear corners
        for x, s in ((6, -1), (29, 1)):
            spike(x, L - 4, math.pi + s * -0.7, ln - 1)
    if level >= 3:
        barbed(cv, p.xy(1, foot.flank[0]), p.xy(1, L - 10))
        barbed(cv, p.xy(34, foot.flank[0]), p.xy(34, L - 10))
    return cv


# ---------------------------------------------------------------- engine and behaviour kit

def v8(foot, level, seed=71):
    """Supercharger blower through the rear engine; then zoomie headers, then a twin scoop."""
    cv = new_rig()
    p = P(cv, foot)
    e0 = foot.engine_y
    if level >= 2:
        for side, xs in (("L", (9, 6)), ("R", (26, 29))):
            for i in range(3):
                y = e0 + 1 + i * 3
                paint(cv, p.line([(xs[0], y + 1), (xs[1], y - 1)], 2), STEEL[2:], base=2)
                px(cv, [p.xy(xs[1], y - 1)], OUTLINE)
    blower = p.rect(13, e0 - 1, 22, e0 + 8)
    paint(cv, blower, STEEL, base=3, depth=2, noise=0.15, seed=seed)
    for yy in range(e0, e0 + 8, 2):
        cv.put(p.rect(14, yy, 21, yy), STEEL[1])
    cv.put(p.line([(13, e0 + 8), (22, e0 + 8)], 1), BRASS[2])  # drive belt
    scoops = [(14.5, 18.5)] if level < 3 else [(13.5, 17.5), (18.5, 22.5)]
    for x0, x1 in scoops:
        sc = p.rect(x0, e0 - 4, x1, e0 + 1)
        paint(cv, sc, STEEL[1:], base=3)
        cv.put(p.rect(x0 + 1, e0 - 3, x1 - 1, e0 - 3), OUTLINE)
        px(cv, [p.xy(round(x0) + 1, e0 - 2)], STEEL[5])
    return cv


def nitro_bottles(foot, level, seed=81):
    """Brass nitrous bottles with hazard bands beside the engine, hoses to the manifold."""
    cv = new_rig()
    p = P(cv, foot)
    e0 = foot.engine_y
    spots = [(10, e0 - 9), (22, e0 - 9), (6, e0 - 2), (26, e0 - 2)][:[1, 2, 4][level - 1]]
    if foot.deck:  # B: the bottles ride on the flatbed's sides
        spots = [(x, y - 1) for x, y in spots]
    if foot.bed:  # P: the bottles ride in the load bed, hoses run forward under the cab
        spots = [(10, 32), (22, 32), (10, 41), (22, 41)][:[1, 2, 4][level - 1]]
    for i, (x, y) in enumerate(spots):
        b = p.rect(x, y, x + 3, y + 7)
        paint(cv, b, BRASS, base=2)
        cv.put(p.rect(x, y + 3, x + 3, y + 3), OUTLINE)
        hazard_stripes(cv, p.rect(x, y + 4, x + 3, y + 5))
        paint(cv, p.rect(x + 1, y - 1, x + 2, y - 1), STEEL, base=4)
        if not foot.bed:
            cv.put(p.line([(x + 1.5, y + 7), (17.5, e0 + 4)], 1) & ~p.rect(11, e0, 24, e0 + 9), TYRE[2])
        else:
            cv.put(p.line([(x + 1.5, y), (x + 1.5, y - 2)], 1), TYRE[2])
    return cv


def kit(foot, card, seed=91):
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    if card == "scrap_magnet":  # electromagnet disc on a boom off the right rear
        cv.put(p.line([(26, L - 18), (34, L - 12)], 2), STEEL[2])
        paint(cv, p.circle(34, L - 12, 4.5), STEEL, base=3)
        cv.put(p.circle(34, L - 12, 3.0) & ~p.circle(34, L - 12, 1.8), BRASS[2])
        px(cv, p.pts([(33, L - 13)]), BRASS[3])
        cv.put(p.circle(34, L - 12, 1.0), STEEL[1])
    elif card == "berserker":  # horned skull on the ram, trophy teeth on the bar
        for s in (-1, 1):
            cv.put(p.line([(17.5 + s * 3, 4), (17.5 + s * 7, 1), (17.5 + s * 8, -2)], 2), BONE[3])
            px(cv, [p.xy(17.5 + s * 8, -3)], BONE[4])
        paint(cv, p.ellipse(14, 2, 21, 8), BONE, base=3)
        px(cv, p.pts([(15.5, 5), (19.5, 5)]), OUTLINE)
        cv.put(p.rect(16, 7, 19, 7), BONE[1])
    elif card == "vulture":  # vulture skull and feathers lashed to the cage, bones on a string
        paint(cv, p.ellipse(4, 18, 9, 23), BONE, base=3)
        cv.put(p.line([(4, 20), (1, 22)], 1), BONE[2])
        px(cv, p.pts([(6, 20)]), OUTLINE)
        for i, (dx, dy) in enumerate([(-2, 4), (0, 5), (2, 4)]):
            cv.put(p.line([(6.5, 23), (6.5 + dx, 23 + dy)], 1), LEATHER[1 + i % 2])
        chain(cv, p.pts([(26, 37), (30, 39)]))
        cv.put(p.line([(30, 39), (32, 42)], 1), BONE[3])
    elif card == "regenerator":  # welding rig: gas bottles and a torch arm with a live spark
        for x in (23, 26):
            paint(cv, p.rect(x, 25, x + 2, 32), KHAKI, base=3)
            px(cv, p.pts([(x + 1, 24)]), STEEL[4])
        cv.put(p.line([(25, 31), (31, 33), (32, 29)], 1), STEEL[3])
        px(cv, p.pts([(32, 28)]), FIRE[5], emissive=True)
        px(cv, p.pts([(33, 27)]), FIRE[4], emissive=True)
    return cv


KIT_CARDS = ["scrap_magnet", "berserker", "vulture", "regenerator"]


# ---------------------------------------------------------------- tech bolt-ons (tech tree v2.3, "Sichtbar als")

TECH_KIT = ["dozer", "cage", "sidecar", "jerrycans", "scrap_pile"]  # rows of rig_tech.png per footprint


def tech_kit(pc, foot, name, seed=101):
    """Hull-fixed tech bolt-ons: dozer blade, roll cage, sidecar (paint keyed), jerrycans, hoard of scrap."""
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    if name == "dozer":
        # push arms and hydraulic rams back to the front axle
        for x in (7, 28):
            paint(cv, p.line([(x, -1), (x, 8)], 2), STEEL[1:], base=2)
        for x, s in ((11, 1), (24, -1)):
            cv.put(p.line([(x, 0), (x + s * 2, 6)], 1), STEEL[4])
            px(cv, p.pts([(x + s * 2, 6)]), BRASS[2])
        # a wide, slightly curved blade, wider than the hull
        blade = p.poly([(-5, -3), (6, -6), (29, -6), (40, -3), (40, 1), (29, -2), (6, -2), (-5, 1)])
        paint(cv, blade, STEEL, base=3, noise=0.35, seed=seed, depth=2)
        weather(cv, blade, seed, holes=1, dents=2, scratches=4, streaks=3)
        cv.put(p.line([(-5, -3), (6, -6), (29, -6), (40, -3)], 1), STEEL[5])  # scraped cutting edge
        hazard_stripes(cv, p.rect(8, -4, 27, -3) & blade)
        rivets(cv, p.pts([(-2, -1), (4, -3), (31, -3), (37, -1)]))
        for x in (-4, 39):  # end caps
            paint(cv, p.rect(x - 1, -4, x + 1, 2), STEEL[1:], base=2)
        cv.put(p.pix([(12, -5), (20, -5), (25, -4)]), RUST[3])
    elif name == "cage":
        # a heavy tube roll cage over the whole body: side rails, hoops, a diagonal brace
        y0, y1 = 9, L - 9
        hoops = [y0, foot.flank[0] - 1, foot.flank[1] + 4, y1]
        for x in (5, 30):
            paint(cv, p.line([(x, y0), (x, y1)], 2), STEEL, base=4)
        for y in hoops:
            paint(cv, p.line([(5, y), (31, y)], 1), STEEL, base=4, light=False)
        cv.put(p.line([(6, hoops[1]), (30, hoops[2])], 1), STEEL[3])
        for x in (5, 30):
            for y in hoops:
                paint(cv, p.rect(x - 1, y - 1, x + 2, y + 2), STEEL[1:], base=2)  # welded joints
                px(cv, p.pts([(x, y)]), RUST[4])
        for y in (hoops[1] + 3, hoops[2] - 3):  # padding on the cross bar
            paint(cv, p.rect(15, y, 20, y + 1), LEATHER, base=2)
    elif name == "sidecar":
        x0, x1 = SIDECAR_X
        sy0, sy1 = _sidecar_y(foot)
        cy = (sy0 + sy1) / 2
        for y in (sy0 + 3, sy1 - 3):  # struts across to the hull
            paint(cv, p.line([(29, y), (x0 + 1, y)], 2), STEEL[1:], base=2)
        wheel(cv, *p.xy(x1 + 1, int(cy) - 5), 5, 10, "R")
        tub = p.poly([(x0 + 2, sy0), (x1 - 2, sy0), (x1, sy0 + 4), (x1, sy1 - 2), (x1 - 2, sy1), (x0 + 1, sy1),
                      (x0, sy1 - 3), (x0, sy0 + 5)])
        paint(cv, tub, pc, base=2, noise=0.3, seed=seed, depth=2)
        chip(cv, tub, 0.2, seed + 1, RUST[2])
        weather(cv, tub, seed + 2, holes=1, dents=1, scratches=2, streaks=1)
        nose = p.poly([(x0 + 2, sy0), (x1 - 2, sy0), (x1 - 4, sy0 - 3), (x0 + 4, sy0 - 3)])
        paint(cv, nose, STEEL, base=3)
        paint(cv, p.circle((x0 + x1) / 2, cy, 4.0), STEEL[1:4], base=1, light=False)  # gun ring
        paint(cv, p.ellipse(x0 + 2, sy1 - 6, x1 - 2, sy1 - 1), LEATHER, base=2)  # gunner's seat
        rivets(cv, p.pts([(x0 + 1, sy0 + 6), (x1 - 1, sy0 + 6), (x0 + 1, sy1 - 4), (x1 - 1, sy1 - 4)]))
    elif name == "jerrycans":
        # spare fuel: red jerrycans strapped along both rear quarters (they go up when the rig dies)
        ys = [L - 21, L - 14] if foot.name != "P" else [foot.bed[0] + 2, foot.bed[0] + 9]
        xs = [(1, 5), (30, 34)] if foot.name != "P" else [(9, 13), (22, 26)]
        for i, (xa, xb) in enumerate(xs):
            for j, y in enumerate(ys):
                can = p.rect(xa, y, xb, y + 6)
                paint(cv, can, ["#3b1210", "#6a1d16", "#94291c", "#b8402a", "#d4654a"], base=2, noise=0.2,
                      seed=seed + i * 7 + j)
                cv.put(p.line([(xa + 1, y + 1), (xb - 1, y + 5)], 1) & can, "#d4654a")  # embossed X
                cv.put(p.line([(xb - 1, y + 1), (xa + 1, y + 5)], 1) & can, "#6a1d16")
                px(cv, p.pts([(xa + 1, y), (xa + 2, y)]), STEEL[3])  # cap and handle
                cv.put(p.rect(xa, y + 3, xb, y + 3) & can, HAZARD)
        if foot.name != "P":  # strap
            cv.put(p.line([(3, ys[0] - 1), (3, ys[1] + 7)], 1), LEATHER[1])
    elif name == "scrap_pile":
        # the hoard: a heap of scrap, a tyre and a pipe lashed onto the rear deck
        cy = foot.engine_y + 4 if foot.name != "P" else (foot.bed[0] + foot.bed[1]) / 2 + 3
        if foot.deck:
            cy = (foot.deck[0] + foot.deck[1]) / 2 + 1
        rng = np.random.default_rng(seed)
        heap = p.blob(17.5, cy, 8.5, 6.0, 0.35, seed, 3)
        paint(cv, heap, RUST, base=2, noise=0.5, seed=seed, depth=2)
        for k in range(9):
            x = 17.5 + rng.uniform(-7, 7)
            y = cy + rng.uniform(-5, 4)
            ramp = [STEEL, RUST, BRASS, KHAKI][k % 4]
            paint(cv, p.rect(x - 1, y - 1, x + rng.integers(1, 3), y + rng.integers(0, 2)), ramp, base=2)
        paint(cv, p.circle(13.5, cy - 2, 3.0), TYRE, base=2)
        cv.put(p.circle(13.5, cy - 2, 1.0), TYRE[0])
        paint(cv, p.line([(16, cy + 4), (25, cy - 4)], 2), STEEL, base=3)
        px(cv, p.pts([(20, cy - 3), (22, cy + 1)]), BRASS[3])
        chain(cv, p.pts([(9, cy - 5), (26, cy + 5)]))
    return cv


# ---------------------------------------------------------------- trailer (engineering tier 3)

def trailer(pc, seed=5):
    """Two-axle gun trailer: painted side boards, ammo crates and the third gun's ring mount."""
    W, H = TRAILER_W, TRAILER_H
    cv = Canvas(W, H)
    cx = W / 2 - 0.5
    for x, y, side in [(3, 25, "L"), (30, 25, "R"), (3, 36, "L"), (30, 36, "R")]:
        wheel(cv, x, y, 7, 10, side, fender=(y == 25))
    paint(cv, rect(W, H, cx - 2.5, 0, cx + 2.5, 8), STEEL[:4], base=2)  # tongue
    cv.put(line(W, H, [(cx, 1), (cx, 7)], 1), STEEL[4])
    bed = rect(W, H, 8, 7, 31, 46)
    paint(cv, bed, STEEL[:4], base=1, noise=0.35, seed=seed)
    for yy in range(9, 46, 5):
        cv.put(pixels(W, H, [(x, yy + (x // 3) % 2) for x in range(10, 30, 3)]), STEEL[2])
    for x0, x1 in ((6, 9), (30, 33)):  # painted side boards
        sb = rect(W, H, x0, 8, x1, 45)
        paint(cv, sb, pc, base=2, noise=0.3, seed=seed + x0)
        chip(cv, sb, 0.2, seed + x0, RUST[2])
        weld(cv, [(x0, 26), (x1, 26)])
    weather(cv, bed, seed, holes=3, dents=2, scratches=5, streaks=3)
    paint(cv, circle(W, H, cx, 18 + 6, 6), STEEL[1:4], base=1, light=False)  # gun ring
    rivets(cv, [(round(cx - 5), 24), (round(cx + 5), 24)])
    for x, y in [(11, 34), (21, 34)]:
        paint(cv, rect(W, H, x, y, x + 6, y + 5), KHAKI, base=2, noise=0.25, seed=x + y)
        cv.put(rect(W, H, x, y + 2, x + 6, y + 2), KHAKI[1])
    tarp(cv, 10, 41, 29, 46, seed + 3)
    hazard_stripes(cv, rect(W, H, 8, 45, 31, 46))
    for x in (9, 30):
        headlight(cv, x, 46, broken=(x == 30))
    return cv


# ---------------------------------------------------------------- guns (drawn natively per angle)

def _barrel(cv, cx, cy, ang, length, bw, off=0.0, ramp=STEEL, bands=True):
    W, H = cv.w, cv.h
    perp = ang + math.pi / 2
    sx, sy = cx + math.sin(perp) * off, cy - math.cos(perp) * off
    ex, ey = polar(sx, sy, ang, length)
    paint(cv, line(W, H, [(sx, sy), (ex, ey)], width=bw), ramp[:5], base=2)
    if bands:
        for t in range(4, int(length) - 2, 4):
            bx, by = polar(sx, sy, ang, t)
            px(cv, [(round(bx), round(by))], ramp[4])
    mx, my = polar(sx, sy, ang, length - 0.5)
    px(cv, [(round(mx), round(my))], OUTLINE)
    return ex, ey


def _base(cv, cx, cy, r, ang, ramp, seed):
    W, H = cv.w, cv.h
    paint(cv, circle(W, H, cx, cy, r), ramp, noise=0.25, seed=seed)
    paint(cv, circle(W, H, cx, cy, max(1, r - 2)), ramp, base=len(ramp) // 2 - 1, light=False)


def _shield(cv, cx, cy, r, ang, ramp, spread=0.9):
    W, H = cv.w, cv.h
    sh = [polar(cx, cy, ang + d, r + 0.5) for d in np.linspace(-spread, spread, 5)]
    cv.put(line(W, H, sh, 2), ramp[2])
    cv.put(line(W, H, sh[1:4], 1), ramp[4])


def gun(kind, level, ang, size=GUN_FRAME, seed=1):
    """Turret of `kind` at `level` (1..3), aimed at ang (0 = north, clockwise)."""
    cv = Canvas(size, size)
    W = H = size
    cx, cy = size / 2 - 0.5, size / 2
    perp = ang + math.pi / 2
    L = BARREL[kind][level - 1]
    if kind == "mg":
        _base(cv, cx, cy, 2.5 + (level >= 2) * 0.5, ang, STEEL, seed)
        offs = [0.0] if level == 1 else [-1.6, 1.6]
        for o in offs:
            _barrel(cv, cx, cy, ang, L, 2, o)
        _shield(cv, cx, cy, 2.5 + (level >= 2), ang, STEEL)
        if level >= 3:  # side ammo drum
            dx, dy = polar(cx, cy, ang - math.pi / 2, 4.5)
            paint(cv, circle(W, H, dx, dy, 2.3), BRASS, base=2)
            px(cv, [(round(dx), round(dy))], BRASS[0])
        px(cv, [(round(cx - 1), round(cy - 1))], STEEL[5])
    elif kind == "shotgun":
        _base(cv, cx, cy, 3.0, ang, RUST, seed)
        n = [2, 3, 4][level - 1]
        for i in range(n):
            o = (i - (n - 1) / 2) * 2.0
            _barrel(cv, cx, cy, ang, L, 2, o, bands=False)
        a = polar(cx, cy, ang, L - 1.0)  # bell-mouthed muzzle clamp
        p0 = polar(*a, perp, n + 0.5)
        p1 = polar(*a, perp, -(n + 0.5))
        cv.put(line(W, H, [p0, p1], 2), STEEL[3])
        _shield(cv, cx, cy, 3.0, ang, RUST, 1.1)
        if level >= 3:
            dx, dy = polar(cx, cy, ang + math.pi, 3.5)
            paint(cv, circle(W, H, dx, dy, 2.6), KHAKI, base=2)
            px(cv, [(round(dx), round(dy))], KHAKI[0])
    elif kind == "cannon":
        _base(cv, cx, cy, 4.0 + (level >= 3) * 0.5, ang, KHAKI, seed)
        if level >= 2:  # recoil cylinders
            for o in (-2.2, 2.2):
                _barrel(cv, cx, cy, ang, L * 0.45, 1, o, ramp=STEEL, bands=False)
        ex, ey = _barrel(cv, cx, cy, ang, L, 3, 0.0)
        bx, by = polar(cx, cy, ang, L - 2)  # muzzle brake
        cv.put(line(W, H, [polar(bx, by, perp, 2.4), polar(bx, by, perp, -2.4)], 2), STEEL[2])
        mx, my = polar(cx, cy, ang, L - 0.5)
        px(cv, [(round(mx), round(my))], OUTLINE)
        if level >= 3:  # mantlet
            _shield(cv, cx, cy, 4.5, ang, KHAKI, 1.2)
        rx, ry = polar(cx, cy, ang + math.pi, 3.5)  # breech block
        paint(cv, circle(W, H, rx, ry, 2.0), STEEL, base=2)
        px(cv, [(round(cx - 1), round(cy - 1))], KHAKI[4])
    elif kind == "flamer":
        _base(cv, cx, cy, 2.5, ang, STEEL, seed)
        tanks = [0.0] if level == 1 else [-2.4, 2.4]
        r = 2.4 if level < 3 else 2.8
        for o in tanks:
            tx, ty = polar(*polar(cx, cy, perp, o), ang + math.pi, 4.5)
            m = circle(W, H, tx, ty, r)
            paint(cv, m, RUST, base=3)
            if level >= 3:
                hazard_stripes(cv, m & line(W, H, [polar(tx, ty, perp, -3), polar(tx, ty, perp, 3)], 1))
        ex, ey = _barrel(cv, cx, cy, ang, L, 2, 0.0, bands=False)
        nx, ny = polar(cx, cy, ang, L - 2)
        cv.put(line(W, H, [polar(nx, ny, perp, 1.5), polar(nx, ny, perp, -1.5)], 1), BRASS[2])
        tip = polar(cx, cy, ang, L + 0.5)
        px(cv, [(math.floor(tip[0]), math.floor(tip[1]))], FIRE[5], emissive=True)  # pilot light
    from pixel import outline
    outline(cv, OUTLINE)
    return cv


# ---------------------------------------------------------------- evolved guns (design doc 5a, 11b)
# The four legendary weapons replace the level 3 gun on the same mount: clearly bigger and more absurd,
# still welded together from scrap. Drawn natively per angle (lit from the top-left) on a bigger frame.
# Rows of gun_evo.png: kind (GUN_KINDS order) x phase (0, 1): the gatling's barrels turn, the grinder's
# teeth chatter, the earthshaker's brace lamp blinks, the inferno's pilot flame flickers.

GUN_EVO_FRAME = 56
BARREL_EVO = {"mg": 21, "shotgun": 15, "cannon": 29, "flamer": 18}  # muzzle distance from the pivot (px)


class _Local:
    """Pen in gun coordinates: u along the barrel (forward), v to the right of it."""

    def __init__(self, cv, cx, cy, ang):
        self.cv, self.cx, self.cy = cv, cx, cy
        self.f = (math.sin(ang), -math.cos(ang))
        self.r = (math.cos(ang), math.sin(ang))

    def p(self, u, v):
        return (self.cx + self.f[0] * u + self.r[0] * v, self.cy + self.f[1] * u + self.r[1] * v)

    def poly(self, pts):
        return poly(self.cv.w, self.cv.h, [self.p(u, v) for u, v in pts])

    def box(self, u0, u1, v0, v1):
        return self.poly([(u0, v0), (u1, v0), (u1, v1), (u0, v1)])

    def line(self, pts, width=1):
        return line(self.cv.w, self.cv.h, [self.p(u, v) for u, v in pts], width)

    def circle(self, u, v, r):
        x, y = self.p(u, v)
        return circle(self.cv.w, self.cv.h, x, y, r)

    def dot(self, u, v):
        x, y = self.p(u, v)
        return pixels(self.cv.w, self.cv.h, [(math.floor(x), math.floor(y))])


def _belt(cv, L, pts, phase):
    """A brass ammo belt (two pixels wide: cartridges with dark links), feeding along pts."""
    m = L.line(pts, 2)
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    cv.put(m, BRASS[2])
    cv.put(m & ((xs + ys + phase) % 3 == 0), BRASS[0])
    cv.put(m & ((xs + ys + phase) % 3 == 1), BRASS[3])


def gun_evo(kind, ang, phase=0, size=GUN_EVO_FRAME, seed=7):
    """Evolved turret of `kind` (Gatling Hell, Meat Grinder, Earthshaker, Inferno Spout), aimed at ang."""
    from pixel import outline
    cv = Canvas(size, size)
    W = H = size
    cx, cy = size / 2 - 0.5, size / 2
    L = _Local(cv, cx, cy, ang)
    B = BARREL_EVO[kind]
    late = []  # (mask, colour) drawn after the outline: lamps and flames stay crisp and unoutlined
    if kind == "mg":  # GATLING HELL: rotary six-barrel cluster, motor housing, side ammo can and a belt
        can = L.box(-6, 4, -12.5, -7)  # ammo can on the left, scrap khaki with a stencil stripe
        paint(cv, can, KHAKI, base=2, noise=0.2, seed=seed)
        cv.put(can & L.box(-1.5, -0.5, -12.5, -7), HAZARD)
        cv.put(L.line([(-5, -11.5), (3, -11.5)]), KHAKI[4])
        _belt(cv, L, [(2.5, -8.0), (5.0, -6.5), (5.5, -4.5)], phase)  # the belt arcs into the breech
        _base(cv, cx, cy, 5.5, ang, STEEL, seed)
        motor = L.box(-9, -2, -4, 4)  # motor housing behind the pivot, cooling fins
        paint(cv, motor, RUST, base=2, noise=0.25, seed=seed + 1)
        for u in (-8, -6, -4):
            cv.put(L.line([(u, -3.5), (u, 3.5)]) & motor, STEEL[1])
        cv.put(L.circle(-7.5, 2.5, 1.2), RUST[3])  # a mismatched rusty cap
        body = L.box(0, B - 6, -3.8, 3.8)  # the barrel cluster
        paint(cv, body, STEEL, base=3, light=True)
        grooves = [-1.9, 1.9] if phase == 0 else [-2.8, 0.0, 2.8]  # the barrels roll round
        for v in grooves:
            cv.put(L.line([(1, v), (B - 6, v)]) & body, STEEL[0])
        hi = -1.0 if phase == 0 else -1.7
        cv.put(L.line([(1, hi), (B - 7, hi)]) & body, STEEL[5])
        tips = (-2.6, 0.0, 2.6) if phase == 0 else (-1.4, 1.4)  # bare barrel ends past the front clamp
        for v in tips:
            cv.put(L.line([(B - 6, v), (B - 0.5, v)], 1), STEEL[4] if v < 0.5 else STEEL[3])
            cv.put(L.dot(B - 0.8, v), OUTLINE)
        for u in (2.5, 8.5, B - 6.5):  # brass clamp rings (a legendary gun wears its trophies)
            cv.put(L.box(u - 0.6, u + 0.9, -4.6, 4.6), BRASS[3])
            cv.put(L.line([(u + 0.9, -4.2), (u + 0.9, 4.2)]), BRASS[1])
        cv.put(L.box(B - 2.6, B - 1.6, -3.4, 3.4), STEEL[2])  # muzzle spider
        _shield(cv, cx, cy, 5.8, ang, STEEL, 1.0)
        cv.put(L.dot(-1.0, -1.5), STEEL[5])
        weld(cv, [L.p(-2, -4.3), L.p(-2, 4.3)])
    elif kind == "shotgun":  # MEAT GRINDER: a drum-fed scatter maw ringed with saw teeth
        drum = L.circle(-7.5, 0, 6.2)  # the drum magazine
        paint(cv, drum, KHAKI, base=2, noise=0.25, seed=seed)
        cv.put(drum & ~L.circle(-7.5, 0, 4.6), KHAKI[1])
        for a in range(4):
            aa = a * math.pi / 4 + phase * math.pi / 8
            cv.put(L.line([(-7.5 + 4.4 * math.cos(aa), 4.4 * math.sin(aa)), (-7.5 - 4.4 * math.cos(aa), -4.4 * math.sin(aa))])
                   & drum, KHAKI[3])
        cv.put(L.circle(-7.5, 0, 1.4), RUST[2])
        _base(cv, cx, cy, 4.5, ang, RUST, seed)
        body = L.box(-2.5, 6, -5, 5)
        paint(cv, body, RUST, base=3, noise=0.3, seed=seed + 2)
        for v in (-5.5, 5.5):  # spiked side rails (the spiked plating, bolted on)
            cv.put(L.line([(-1.5, v), (5.5, v)]), STEEL[3])
            for u in (-0.5, 2.5, 5.0):
                sgn = 1 if v > 0 else -1
                cv.put(L.line([(u, v), (u - 1.0, v + sgn * 2.5)]), STEEL[5])
        maw = L.poly([(5.5, -5.5), (B, -9.5), (B, 9.5), (5.5, 5.5)])  # the flared maw
        paint(cv, maw, STEEL, base=2, light=True)
        inner = L.poly([(6.5, -3.8), (B - 1.0, -7.5), (B - 1.0, 7.5), (6.5, 3.8)])
        cv.put(inner, TYRE[0])
        for v in (-4.5, -1.5, 1.5, 4.5):  # barrels deep in the throat
            cv.put(L.line([(6.5, v * 0.6), (B - 3.0, v)]), STEEL[3])
            cv.put(L.dot(B - 2.6, v), STEEL[5])
        for k in range(10):  # saw teeth round the lip, chattering between frames
            v = -9.0 + k * 2.0 + (1.0 if phase else 0.0)
            if abs(v) > 9.5:
                continue
            tooth = L.poly([(B - 0.5, v - 0.9), (B + 2.6, v), (B - 0.5, v + 0.9)])
            cv.put(tooth, STEEL[5] if k % 2 == 0 else STEEL[4])
        for s in (-1, 1):  # teeth down the flanks of the maw
            for t in (0.35, 0.7):
                u = 5.5 + (B - 5.5) * t
                v = s * (5.5 + 4.0 * t)
                cv.put(L.poly([(u - 1.0, v), (u + 0.2, v + s * 2.4), (u + 1.0, v)]), STEEL[4])
        cv.put(L.line([(B - 0.5, -9.5), (B - 0.5, 9.5)]), BRASS[3])
        cv.put(L.line([(5.5, -5.5), (B, -9.5)]) | L.line([(5.5, 5.5), (B, 9.5)]), BRASS[2])
        for u, v in ((0, -3.5), (0, 3.5), (4.5, -3.5), (4.5, 3.5)):
            cv.put(L.dot(u, v), STEEL[5])
    elif kind == "cannon":  # EARTHSHAKER: a huge long-barrelled siege piece on a braced cradle
        for s in (-1, 1):  # recoil brace: struts back to dug-in spades (track pads)
            cv.put(L.line([(-2, s * 4.5), (-12.5, s * 9.5)], 2), STEEL[2])
            cv.put(L.line([(-2, s * 4.5), (-12.5, s * 9.5)]), STEEL[4])
            spade = L.box(-15.5, -11.5, s * 7.5, s * 12.0)
            paint(cv, spade, TYRE, base=2)
            hazard_stripes(cv, spade & L.box(-12.8, -11.5, -12.5, 12.5))
            for u in (-14.5, -13.5):
                cv.put(L.line([(u, s * 7.8), (u, s * 11.7)]), TYRE[3])
        _base(cv, cx, cy, 7.0, ang, KHAKI, seed)
        breech = L.box(-9.5, -2, -3.5, 3.5)  # breech block and a shell rack
        paint(cv, breech, STEEL, base=2, noise=0.2, seed=seed + 3)
        for v in (-2.0, 0.0, 2.0):
            cv.put(L.circle(-8.0, v, 0.9), BRASS[3])
        cradle = L.box(-1, 11, -4.5, 4.5)  # the cradle sleeve
        paint(cv, cradle, KHAKI, base=3, noise=0.25, seed=seed + 4)
        barrel = L.box(10, B - 1, -2.4, 2.4)
        paint(cv, barrel, STEEL, base=3)
        for u in range(14, B - 4, 5):
            cv.put(L.box(u - 0.5, u + 0.5, -2.8, 2.8), BRASS[3])
        cv.put(L.line([(11, -1.0), (B - 4, -1.0)]), STEEL[5])
        for s in (-1, 1):  # hydraulic recoil cylinders along the cradle
            cyl = L.box(-1.5, 12.5, s * 4.0 - 0.9, s * 4.0 + 0.9)
            cv.put(cyl, STEEL[5])
            cv.put(L.line([(9.5, s * 4.0), (14.5, s * 4.0)]), STEEL[5])
        brake = L.box(B - 4.5, B, -4.2, 4.2)  # a fat muzzle brake with vent slots
        paint(cv, brake, STEEL, base=2)
        for u in (B - 3.5, B - 1.5):
            cv.put(L.line([(u, -4.0), (u, -2.0)]), OUTLINE)
            cv.put(L.line([(u, 2.0), (u, 4.0)]), OUTLINE)
        cv.put(L.dot(B - 0.5, 0.0), OUTLINE)
        _shield(cv, cx, cy, 7.5, ang, KHAKI, 1.15)
        weld(cv, [L.p(11, -4.5), L.p(11, 4.5)])
        cv.put(L.dot(-1, -2.5), KHAKI[4])
        late.append((L.dot(-5.0, 2.0), FIRE[5] if phase == 0 else RUST[2]))  # a lamp on the breech
    elif kind == "flamer":  # INFERNO SPOUT: big bell nozzle, twin fuel tanks, hoses and a pilot flame
        for s in (-1, 1):  # twin fuel tanks behind (capsules, hazard bands, brass caps)
            tank = L.poly([(-15, s * 3.0), (-14, s * 1.6), (-2.5, s * 1.6), (-1.5, s * 3.0), (-1.5, s * 7.8),
                           (-2.5, s * 9.2), (-14, s * 9.2), (-15, s * 7.8)])
            paint(cv, tank, RUST, base=3, noise=0.25, seed=seed + 5 + s)
            hazard_stripes(cv, tank & L.box(-9.5, -7.5, -10, 10))
            cv.put(L.circle(-15.2, s * 5.4, 1.3), BRASS[3])
            cv.put(L.line([(-13, s * 2.6), (-3, s * 2.6)]) & tank, RUST[5])
        for s in (-1, 1):  # hoses from the tanks round to the pump
            cv.put(L.line([(-2.0, s * 6.0), (1.5, s * 5.5), (3.0, s * 2.5)], 2), TYRE[2])
            cv.put(L.line([(-2.0, s * 6.0), (1.5, s * 5.5)]), TYRE[3])
        _base(cv, cx, cy, 4.5, ang, STEEL, seed)
        pump = L.box(-2.5, 6, -3.2, 3.2)
        paint(cv, pump, STEEL, base=2, noise=0.2, seed=seed + 6)
        cv.put(L.circle(1.5, 0, 1.6), BRASS[2])
        pipe = L.box(5, B - 5, -1.8, 1.8)
        paint(cv, pipe, STEEL, base=2)
        cv.put(L.box(8.5, 9.5, -2.4, 2.4), BRASS[2])
        bell = L.poly([(B - 5.5, -2.0), (B, -5.2), (B, 5.2), (B - 5.5, 2.0)])
        paint(cv, bell, BRASS, base=2)
        cv.put(L.line([(B - 0.5, -5.0), (B - 0.5, 5.0)]), BRASS[1])
        cv.put(L.poly([(B - 2.5, -2.4), (B - 0.3, -3.8), (B - 0.3, 3.8), (B - 2.5, 2.4)]), RUST[0])
        weld(cv, [L.p(5, -2.6), L.p(5, 2.6)])
        f0 = [FIRE[5], FIRE[4]][phase]  # the pilot flame, licking out of the bell
        late.append((L.line([(B + 0.5, -1.0), (B + 2.5 + phase, 0.0)]) | L.line([(B + 0.5, 1.0), (B + 2.0, 0.5)]), FIRE[3]))
        late.append((L.dot(B + 0.8, 0.0) | L.dot(B + 1.6, -0.4 + phase * 0.8), f0))
        late.append((L.dot(B + 0.2, 0.0), FIRE[6]))
    outline(cv, OUTLINE)
    for m, col in late:
        cv.put(m, col, emissive=True)
    return cv


def gun_evo_rows(v_ang):
    """gun_evo.png rows: kind x phase."""
    return [[gun_evo(k, a, ph) for a in v_ang] for k in GUN_KINDS for ph in (0, 1)]


# ---------------------------------------------------------------- nitro flame (native per angle)

def nitro_flame(ang, level, phase, size=FLAME_FRAME):
    """Exhaust jet leaving the pipe at the centre along ang. Level = length, phase = flicker."""
    cv = Canvas(size, size)
    c = size / 2
    ln = [5, 7, 9][level - 1] + (1 if phase else 0)
    W = H = size
    cv.put(line(W, H, [polar(c, c, ang, 0.5), polar(c, c, ang, ln)], 3 if level >= 2 else 2), FIRE[2], emissive=True)
    cv.put(line(W, H, [polar(c, c, ang, 0.5), polar(c, c, ang, ln * 0.7)], 2), FIRE[3], emissive=True)
    cv.put(line(W, H, [polar(c, c, ang, 0.5), polar(c, c, ang, ln * 0.45)], 1), FIRE[5], emissive=True)
    tip = polar(c, c, ang + (0.25 if phase else -0.25), ln + 1)
    px(cv, [(math.floor(tip[0]), math.floor(tip[1]))], FIRE[4], emissive=True)
    return cv


# ---------------------------------------------------------------- builds (previews, samples, menu strips)

ARMOUR_LAYERS = [("steel_plates", "plates"), ("reinforced_hull", "reinforced"), ("ablative_scrap", "ablative"),
                 ("spiked_plating", "spikes")]


def layer_canvases(build):
    """Flat (facing north, unrotated) canvases of a build, bottom to top, paint keyed.
    build: {"paint": name, "tier": 0..4, "cards": {card id: level}, "tech": [TECH_KIT names]}."""
    tier = build.get("tier", 0)
    cards = build.get("cards", {})
    foot, style = body_for_tier(tier)
    gk = "tracks" if "caterpillar_tracks" in cards else ("offroad" if "off_road_tyres" in cards else "wheels")
    out = [gear(foot, gk), paint_key(lambda r: body(r, style))]
    for card, name in ARMOUR_LAYERS:
        lv = cards.get(card, 0)
        if lv:
            if name == "plates":
                out.append(paint_key(lambda r, lv=lv: steel_plates(r, foot, lv)))
            elif name == "reinforced":
                out.append(reinforced(foot, lv))
            elif name == "ablative":
                out.append(ablative(foot, lv))
            else:
                out.append(spikes(foot, lv))
    if cards.get("v8_engine"):
        out.append(v8(foot, cards["v8_engine"]))
    if cards.get("nitro"):
        out.append(nitro_bottles(foot, cards["nitro"]))
    for card in KIT_CARDS:
        if cards.get(card):
            out.append(kit(foot, card))
    for name in TECH_KIT:
        if name in build.get("tech", []):
            out.append(paint_key(lambda r, name=name: tech_kit(r, foot, name)))
    return foot, out


def _rotate_outlined(cv, ang, size):
    import export_assets
    f = export_assets.rotsprite(cv, ang, size)
    from pixel import outline
    outline(f, OUTLINE)
    return f


def compose(build, ang=0.0, aim=None, size=RIG_FRAME + 24):
    """A whole rig (layers RotSprite'd and outlined one by one, guns natively drawn) on one canvas."""
    from pixel import paste
    ramp = PLAYERS[build.get("paint", "red")]
    foot, layers = layer_canvases(build)
    out = Canvas(size, size)
    c = size / 2
    tier = build.get("tier", 0)
    anchors = RIG_ANCHORS[foot.name]

    def rot(x, y):
        return x * math.cos(ang) - y * math.sin(ang), x * math.sin(ang) + y * math.cos(ang)

    trailer_c = None
    if tier >= 4:  # trailer straight behind
        hx, hy = anchors["hitch"]
        trailer_c = (hx, hy + TRAILER_TONGUE)
        rx, ry = rot(*trailer_c)
        t = _rotate_outlined(paint_key(trailer), ang, TRAILER_FRAME)
        paste(out, apply_paint(t, ramp), round(c + rx - TRAILER_FRAME / 2), round(c + ry - TRAILER_FRAME / 2))
    for lay in layers:
        f = apply_paint(_rotate_outlined(lay, ang, RIG_FRAME), ramp)
        paste(out, f, round(c - RIG_FRAME / 2), round(c - RIG_FRAME / 2))
    guns = build.get("guns", [("mg", 1)])
    spots = list(anchors["mounts"][:2])
    if trailer_c:
        spots += [(trailer_c[0] + mx, trailer_c[1] + my) for mx, my in TRAILER_MOUNTS]
    spots += anchors["mounts"][2:]
    if "sidecar" in build.get("tech", []) and len(guns) >= 3:
        spots = spots[:len(guns) - 1] + [anchors["sidecar"]]
    for i, (kind, lv) in enumerate(guns):
        rx, ry = rot(*spots[min(i, len(spots) - 1)])
        g = gun(kind, lv, ang if aim is None else aim)
        paste(out, g, round(c + rx - GUN_FRAME / 2), round(c + ry - GUN_FRAME / 2))
    return out


# Line-up for art/samples/rigs.png (same builds as the "rig_growth" screenshot scenario).
SAMPLE_BUILDS = [
    ("STARTER", {"paint": "red", "tier": 0, "cards": {}, "guns": [("mg", 1)]}),
    ("FRAME PLATES V8", {"paint": "magenta", "tier": 1, "cards": {"steel_plates": 2, "v8_engine": 1},
                         "guns": [("mg", 2), ("shotgun", 1)]}),
    ("PICKUP DOZER", {"paint": "blue", "tier": 2, "cards": {"spiked_plating": 3, "nitro": 2, "berserker": 1,
                                                             "caterpillar_tracks": 1}, "tech": ["dozer"],
                      "guns": [("shotgun", 3), ("flamer", 2), ("mg", 1)]}),
    ("WAR RIG", {"paint": "green", "tier": 4, "cards": {"reinforced_hull": 3, "ablative_scrap": 2,
                                                        "off_road_tyres": 1, "scrap_magnet": 1}, "tech": ["jerrycans"],
                 "guns": [("cannon", 3), ("mg", 3), ("flamer", 3), ("mg", 2)]}),
    ("TRUCK CAGE HOARD", {"paint": "white", "tier": 3, "cards": {"steel_plates": 3, "vulture": 1,
                                                                 "regenerator": 1, "v8_engine": 3},
                          "tech": ["cage", "scrap_pile"], "guns": [("mg", 1), ("cannon", 1), ("mg", 2)]}),
    ("SIDECAR", {"paint": "purple", "tier": 0, "cards": {"spiked_plating": 1, "nitro": 1}, "tech": ["sidecar"],
                 "guns": [("mg", 1), ("flamer", 1), ("mg", 2)]}),
    ("REINFORCED", {"paint": "lime", "tier": 1, "cards": {"reinforced_hull": 1, "steel_plates": 1},
                    "tech": ["jerrycans"], "guns": [("mg", 3), ("cannon", 2)]}),
    ("BRAWLER", {"paint": "black", "tier": 3, "cards": {"spiked_plating": 2, "steel_plates": 1, "v8_engine": 2,
                                                        "off_road_tyres": 1}, "tech": ["dozer", "jerrycans"],
                 "guns": [("mg", 1), ("shotgun", 2), ("cannon", 1)]}),
]
