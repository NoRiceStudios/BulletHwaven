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

RIG_W, RIG_H = 56, 80
RIG_FRAME = 80
TRAILER_W, TRAILER_H = 40, 48
TRAILER_FRAME = 64
GUN_FRAME = 40
FLAME_FRAME = 32

PROBE_A = PLAYERS["red"]
PROBE_B = PLAYERS["green"]
PAINT_STEPS = 5


class Foot:
    def __init__(self, name, oy, length, wheels, flank, plate_slots, deck=None):
        self.name, self.ox, self.oy, self.L = name, 10, oy, length
        self.wheels = wheels  # (x, y, w, h, side) in footprint coordinates
        self.flank = flank  # y range of the free flank between the first two axles
        self.plate_slots = plate_slots  # flank plate y ranges per steel-plates level
        self.deck = deck  # B: flatbed y range


FOOT_A = Foot("A", 14, 52, [(3, 8, 7, 11, "L"), (26, 8, 7, 11, "R"), (2, 33, 8, 13, "L"), (26, 33, 8, 13, "R")],
              (20, 31), [[(19, 31)], [(33, 46)], [(6, 18)]])
FOOT_B = Foot("B", 8, 64, [(3, 8, 7, 11, "L"), (26, 8, 7, 11, "R"), (2, 33, 8, 12, "L"), (26, 33, 8, 12, "R"),
                           (2, 48, 8, 13, "L"), (26, 48, 8, 13, "R")],
              (20, 31), [[(19, 31)], [(33, 45), (47, 60)], [(6, 18)]], deck=(37, 48))
FEET = [FOOT_A, FOOT_B]


def _rel(foot, x, y):
    """Footprint coordinates -> offset from the rig centre (facing north)."""
    return (x + foot.ox - RIG_W / 2, y + foot.oy - RIG_H / 2)


# Anchors relative to the rig centre, facing north (px). Mirrored in game/render/rig_art.gd.
RIG_ANCHORS = {
    "A": {"mounts": [_rel(FOOT_A, 17.5, 22), _rel(FOOT_A, 17.5, 11)],
          "exhausts": [_rel(FOOT_A, 9, 51), _rel(FOOT_A, 26, 51)],
          "rear_wheels": [_rel(FOOT_A, 5.5, 40), _rel(FOOT_A, 29.5, 40)],
          "hitch": _rel(FOOT_A, 17.5, 52)},
    "B": {"mounts": [_rel(FOOT_B, 17.5, 22), _rel(FOOT_B, 17.5, 42.5)],
          "exhausts": [_rel(FOOT_B, 9, 63), _rel(FOOT_B, 26, 63)],
          "rear_wheels": [_rel(FOOT_B, 5.5, 55), _rel(FOOT_B, 29.5, 55)],
          "hitch": _rel(FOOT_B, 17.5, 64)},
}
TRAILER_MOUNT = (0.0, 0.0)  # gun on the trailer, relative to the trailer centre
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

def body(pc, foot, tier, seed=1):
    """Welded scrap hull. Big paint: the whole hood and a rim along the tub flanks."""
    cv = new_rig()
    p = P(cv, foot)
    L = foot.L
    # spare tyre strapped to the left flank, jerrycan to the right
    fy0 = foot.flank[0] + 1
    paint(cv, p.rect(3, fy0, 6, fy0 + 9), TYRE, base=2)
    cv.put(p.rect(4, fy0 + 1, 5, fy0 + 8), TYRE[0])
    cv.put(p.rect(3, fy0 + 4, 6, fy0 + 4), LEATHER[2])
    paint(cv, p.rect(28, fy0, 32, fy0 + 8), RUST[1:], base=2, noise=0.3, seed=seed)
    px(cv, p.pts([(30, fy0), (31, fy0)]), STEEL[1])
    cv.put(p.rect(28, fy0 + 4, 32, fy0 + 4), LEATHER[1])
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
    paint(cv, left, pc, base=3, noise=0.3, seed=seed + 1)
    paint(cv, right, pc, base=2, noise=0.35, seed=seed + 2)
    chip(cv, left, 0.12, seed, STEEL[2])
    chip(cv, right, 0.18, seed + 3, STEEL[3])
    cv.put(p.line([(19, 17), (25, 11)], 1) & right, KHAKI[3])  # a stripe of the old olive coat
    weld(cv, p.pts([(17, 6), (17, 18)]))
    weld(cv, p.pts([(9, 19), (26, 19)]))
    weather(cv, tub | left | right, seed, holes=4, dents=3, scratches=6, streaks=4)
    rivets(cv, p.pts([(10, 12), (25, 12), (10, 16), (25, 16)]))
    headlight(cv, *p.xy(11, 8))
    headlight(cv, *p.xy(24, 8), broken=True)
    # ram bar
    paint(cv, p.line([(7, 4), (28, 4)], 2), STEEL, base=3)
    for x in (8, 13, 22, 27):
        paint(cv, p.poly([(x - 1, 4), (x + 1, 4), (x, 1)]), STEEL[1:], base=2)
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
    # pintle MG ammo box
    paint(cv, p.rect(21, 21, 24, 24), KHAKI, base=2)
    ammo_belt(cv, p.pts([(21, 22), (19, 22)]))
    return cv


def body_for_tier(tier):
    return (FOOT_B if tier >= 2 else FOOT_A), min(tier, 2)


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
    e0 = foot.L - 15
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
    e0 = foot.L - 15
    spots = [(10, e0 - 9), (22, e0 - 9), (6, e0 - 2), (26, e0 - 2)][:[1, 2, 4][level - 1]]
    if foot.deck:  # B: the bottles ride on the flatbed's sides
        spots = [(x, y - 1) for x, y in spots]
    for i, (x, y) in enumerate(spots):
        b = p.rect(x, y, x + 3, y + 7)
        paint(cv, b, BRASS, base=2)
        cv.put(p.rect(x, y + 3, x + 3, y + 3), OUTLINE)
        hazard_stripes(cv, p.rect(x, y + 4, x + 3, y + 5))
        paint(cv, p.rect(x + 1, y - 1, x + 2, y - 1), STEEL, base=4)
        cv.put(p.line([(x + 1.5, y + 7), (17.5, e0 + 4)], 1) & ~p.rect(11, e0, 24, e0 + 9), TYRE[2])
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
    build: {"paint": name, "tier": 0..3, "cards": {card id: level}}."""
    tier = build.get("tier", 0)
    cards = build.get("cards", {})
    foot, btier = body_for_tier(tier)
    gk = "tracks" if "caterpillar_tracks" in cards else ("offroad" if "off_road_tyres" in cards else "wheels")
    out = [gear(foot, gk), paint_key(lambda r: body(r, foot, btier))]
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
    if tier >= 3:  # trailer straight behind
        hx, hy = RIG_ANCHORS[foot.name]["hitch"]
        tx, ty = hx, hy + TRAILER_TONGUE
        rx = tx * math.cos(ang) - ty * math.sin(ang)
        ry = tx * math.sin(ang) + ty * math.cos(ang)
        t = _rotate_outlined(paint_key(trailer), ang, TRAILER_FRAME)
        paste(out, apply_paint(t, ramp), round(c + rx - TRAILER_FRAME / 2), round(c + ry - TRAILER_FRAME / 2))
    for lay in layers:
        f = apply_paint(_rotate_outlined(lay, ang, RIG_FRAME), ramp)
        paste(out, f, round(c - RIG_FRAME / 2), round(c - RIG_FRAME / 2))
    mounts = list(RIG_ANCHORS[foot.name]["mounts"])
    guns = build.get("guns", [("mg", 1)])
    for i, (kind, lv) in enumerate(guns):
        if i < 2:
            mx, my = mounts[i]
        else:
            hx, hy = RIG_ANCHORS[foot.name]["hitch"]
            mx, my = hx + TRAILER_MOUNT[0], hy + TRAILER_TONGUE + TRAILER_MOUNT[1]
        rx = mx * math.cos(ang) - my * math.sin(ang)
        ry = mx * math.sin(ang) + my * math.cos(ang)
        g = gun(kind, lv, ang if aim is None else aim)
        paste(out, g, round(c + rx - GUN_FRAME / 2), round(c + ry - GUN_FRAME / 2))
    return out


# Line-up for art/samples/rigs.png (same builds as the "rig_growth" screenshot scenario).
SAMPLE_BUILDS = [
    ("STARTER", {"paint": "red", "tier": 0, "cards": {}, "guns": [("mg", 1)]}),
    ("PLATES 2 V8", {"paint": "magenta", "tier": 1, "cards": {"steel_plates": 2, "v8_engine": 1},
                     "guns": [("mg", 2), ("shotgun", 1)]}),
    ("SPIKES 3 TRACKS", {"paint": "blue", "tier": 2, "cards": {"spiked_plating": 3, "nitro": 2, "berserker": 1,
                                                                "caterpillar_tracks": 1},
                         "guns": [("shotgun", 3), ("flamer", 2)]}),
    ("TRAILER", {"paint": "green", "tier": 3, "cards": {"reinforced_hull": 3, "ablative_scrap": 2,
                                                        "off_road_tyres": 1, "scrap_magnet": 1},
                 "guns": [("cannon", 3), ("mg", 3), ("flamer", 3)]}),
    ("ABLATIVE 3", {"paint": "white", "tier": 2, "cards": {"steel_plates": 3, "ablative_scrap": 3, "vulture": 1,
                                                           "regenerator": 1, "v8_engine": 3},
                    "guns": [("mg", 1), ("cannon", 1)]}),
    ("NITRO FLAMER", {"paint": "purple", "tier": 0, "cards": {"spiked_plating": 1, "nitro": 1},
                      "guns": [("mg", 1), ("flamer", 1)]}),
    ("REINFORCED", {"paint": "lime", "tier": 1, "cards": {"reinforced_hull": 1, "steel_plates": 1},
                    "guns": [("mg", 3), ("cannon", 2)]}),
    ("BRAWLER", {"paint": "black", "tier": 2, "cards": {"spiked_plating": 2, "steel_plates": 1, "v8_engine": 2,
                                                        "off_road_tyres": 1},
                 "guns": [("mg", 1), ("shotgun", 2)]}),
]
