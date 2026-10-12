"""Sprite definitions. All vehicles face north (up); light comes from the top-left."""

import math

import numpy as np

from palette import (BONE, BRASS, BURLAP, CHITIN, CRYSTAL, GLASS, GLOW, HAZARD, KHAKI, LEATHER, OUTLINE,
                     PLAYERS, ROCK, RUST, SAND, STEEL, TYRE, VOLATILE)
from pixel import (Canvas, blob, circle, ellipse, line, outline, paint, paste, pixels, polar, poly,
                   rect, rgb, shift, value_noise)


# ---------------------------------------------------------------- shared parts

def px(cv, pts, color, emissive=False):
    cv.put(pixels(cv.w, cv.h, pts), color, emissive=emissive)


def shade(cv, m, f):
    """Darken (f < 1) or brighten (f > 1) already painted pixels, keeping their material colour."""
    m = m & cv.solid()
    cv.rgb[m] = np.clip(cv.rgb[m] * f, 0, 255)


def _interior(area):
    return area & shift(area, 1, 0) & shift(area, -1, 0) & shift(area, 0, 1) & shift(area, 0, -1)


def _pick(area, rng):
    ys, xs = np.nonzero(_interior(area))
    if len(ys) == 0:
        return None
    i = rng.integers(len(ys))
    return int(xs[i]), int(ys[i])


def weather(cv, area, seed, holes=0, dents=0, scratches=0, streaks=0):
    """Battle damage on an already painted surface: dents, bullet holes, scratches, rust streaks."""
    rng = np.random.default_rng(seed)
    W, H = cv.w, cv.h
    area = area & cv.solid()
    for _ in range(dents):
        p = _pick(area, rng)
        if not p:
            break
        x, y = p
        rx, ry = rng.uniform(1.2, 2.4), rng.uniform(1.0, 1.8)
        d = ellipse(W, H, x - rx, y - ry, x + rx, y + ry) & area
        shade(cv, d, 0.85)
        shade(cv, d & ~shift(d, 1, 1), 1.3)    # far rim catches the light (concave)
        shade(cv, d & ~shift(d, -1, -1), 0.8)  # near rim in shadow
    for _ in range(holes):
        p = _pick(area, rng)
        if not p:
            break
        x, y = p
        px(cv, [(x, y)], OUTLINE)
        shade(cv, pixels(W, H, [(x + 1, y), (x, y + 1)]) & area, 1.35)
        shade(cv, pixels(W, H, [(x - 1, y), (x, y - 1)]) & area, 0.75)
    for _ in range(scratches):
        p = _pick(area, rng)
        if not p:
            break
        x, y = p
        a, ln = rng.uniform(0, math.pi), rng.integers(2, 5)
        shade(cv, line(W, H, [(x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln)], 1) & area, 1.3)
    for _ in range(streaks):
        p = _pick(area, rng)
        if not p:
            break
        x, y = p
        m = line(W, H, [(x, y), (x, y + rng.integers(2, 6))], 1) & area
        cv.put(m, RUST[2], alpha=0.55)
        px(cv, [(x, y)], RUST[1])


def chip(cv, area, frac, seed, color):
    """Knock clustered flecks out of a paint job to show the metal underneath."""
    area = area & cv.solid()
    if not area.any():
        return
    r = 0.7 * value_noise(cv.h, cv.w, 2, seed) + 0.3 * np.random.default_rng(seed).random((cv.h, cv.w))
    cut = np.quantile(r[area], 1 - frac)
    cv.put(area & (r > cut), color)


def weld(cv, pts):
    """Welded seam: a low bead with a little heat tint."""
    m = line(cv.w, cv.h, pts, 1)
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    cv.put(m, STEEL[3])
    cv.put(m & ((xs + ys) % 2 == 0), STEEL[4])
    cv.put(m & ((xs * 7 + ys * 3) % 6 == 0), RUST[4])


def chain(cv, pts):
    m = line(cv.w, cv.h, pts, 1)
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    cv.put(m, STEEL[4])
    cv.put(m & ((xs + ys) % 3 == 0), STEEL[1])


def barbed(cv, p0, p1):
    """Barbed wire between two points (spikes every 3 px)."""
    cv.put(line(cv.w, cv.h, [p0, p1], 1), STEEL[1])
    n = int(max(abs(p1[0] - p0[0]), abs(p1[1] - p0[1])))
    dx, dy = (p1[0] - p0[0]) / max(n, 1), (p1[1] - p0[1]) / max(n, 1)
    for i in range(1, n, 3):
        x, y = p0[0] + dx * i, p0[1] + dy * i
        px(cv, [(round(x - dy), round(y + dx)), (round(x + dy), round(y - dx))], STEEL[3])


def sandbag(cv, x0, y0, x1, y1, seed=0):
    m = ellipse(cv.w, cv.h, x0, y0, x1, y1)
    paint(cv, m, BURLAP, base=3, noise=0.3, seed=seed)
    cy = (y0 + y1) / 2
    cv.put(line(cv.w, cv.h, [(x0 + 2, cy), (x1 - 2, cy)], 1) & m, BURLAP[1])
    px(cv, [(round(x1 - 1), round(cy))], BURLAP[0])


def tarp(cv, x0, y0, x1, y1, seed=0):
    """Tarp-covered cargo lashed down with crossed ropes."""
    m = blob(cv.w, cv.h, (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, 0.15, seed, 3)
    paint(cv, m, KHAKI, base=2, noise=0.45, seed=seed, depth=2)
    for a, b in [((x0, y0 + 2), (x1, y1 - 2)), ((x0, y1 - 2), (x1, y0 + 2))]:
        cv.put(line(cv.w, cv.h, [a, b], 1) & m, BURLAP[4])


def headlight(cv, cx, cy, broken=False):
    paint(cv, circle(cv.w, cv.h, cx, cy, 1.7), STEEL[1:], base=2)
    if broken:
        px(cv, [(round(cx), round(cy))], OUTLINE)
        px(cv, [(round(cx) - 1, round(cy))], GLASS[1])
    else:
        px(cv, [(round(cx), round(cy)), (round(cx) - 1, round(cy))], GLASS[3])
        px(cv, [(round(cx) - 1, round(cy) - 1)], "#ffffff")


def wheel(cv, x, y, w, h, side="L", spikes=True, fender=True):
    """Chunky off-road tyre: staggered lugs, dark outer sidewall, hub spikes, rusty fender."""
    W, H = cv.w, cv.h
    paint(cv, rect(W, H, x, y, x + w - 1, y + h - 1), TYRE, base=1)
    for i, yy in enumerate(range(y + 1, y + h - 1, 2)):
        if i % 2 == 0:
            cv.put(rect(W, H, x + 1, yy, x + w // 2, yy), TYRE[3])
        else:
            cv.put(rect(W, H, x + w // 2, yy, x + w - 2, yy), TYRE[3])
    outer = x if side == "L" else x + w - 1
    cv.put(rect(W, H, outer, y + 1, outer, y + h - 2), TYRE[0])
    if spikes:
        cy = y + h // 2
        tip = [(outer - 1, cy), (outer - 2, cy)] if side == "L" else [(outer + 1, cy), (outer + 2, cy)]
        px(cv, tip[:1], STEEL[4])
        px(cv, tip[1:], STEEL[2])
    if fender:
        f = poly(W, H, [(x - 1, y + 3), (x, y), (x + w - 1, y), (x + w, y + 3)])
        paint(cv, f, RUST, base=3, noise=0.4, seed=x * 7 + y)


def rivets(cv, pts):
    cv.put(pixels(cv.w, cv.h, pts), STEEL[5])
    cv.put(pixels(cv.w, cv.h, [(x, y + 1) for x, y in pts]), STEEL[0])


def hazard_stripes(cv, m, period=4):
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    stripe = ((xs + ys) // (period // 2)) % 2 == 0
    cv.put(m & stripe, HAZARD)
    cv.put(m & ~stripe, OUTLINE)


def ammo_belt(cv, pts):
    m = line(cv.w, cv.h, pts, 1)
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    cv.put(m, BRASS[3])
    cv.put(m & ((xs + ys) % 2 == 0), BRASS[1])


def turret(cv, cx, cy, r, ang, length, barrels=1, bw=2, ramp=STEEL, seed=0):
    W, H = cv.w, cv.h
    paint(cv, circle(W, H, cx, cy, r), ramp, noise=0.25, seed=seed)
    paint(cv, circle(W, H, cx, cy, max(1, r - 2)), ramp, base=len(ramp) // 2 - 1, light=False)
    perp = ang + math.pi / 2
    offs = [0.0] if barrels == 1 else [-(bw / 2 + 0.6), bw / 2 + 0.6]
    for o in offs:
        sx, sy = cx + math.sin(perp) * o, cy - math.cos(perp) * o
        ex, ey = polar(sx, sy, ang, length)
        paint(cv, line(W, H, [(sx, sy), (ex, ey)], width=bw), STEEL[:5], base=2)
        # cooling-jacket bands along the barrel
        for t in range(4, int(length) - 2, 4):
            bx, by = polar(sx, sy, ang, t)
            px(cv, [(round(bx), round(by))], STEEL[4])
        mx, my = polar(sx, sy, ang, length - 0.5)
        px(cv, [(round(mx), round(my))], OUTLINE)
    # gun shield plate on the side facing the target
    sh = [polar(cx, cy, ang + d, r + 0.5) for d in (-0.9, -0.45, 0.0, 0.45, 0.9)]
    cv.put(line(W, H, sh, 2), ramp[2])
    cv.put(line(W, H, sh[1:4], 1), ramp[4])
    px(cv, [(round(cx - 1), round(cy - 1))], STEEL[5])


# ---------------------------------------------------------------- vehicles

def buggy(player="red", gun_angle=0.0, seed=1):
    """Starter vehicle: welded scrap buggy with one pintle MG (36x52)."""
    W, H = 36, 52
    cv = Canvas(W, H)
    pc = PLAYERS[player]
    for x, y, w, h, side in [(3, 8, 7, 11, "L"), (26, 8, 7, 11, "R"), (2, 33, 8, 13, "L"), (26, 33, 8, 13, "R")]:
        wheel(cv, x, y, w, h, side)
    for a, b in [((9, 13), (13, 13)), ((26, 13), (22, 13)), ((9, 39), (13, 39)), ((26, 39), (22, 39))]:
        cv.put(line(W, H, [a, b], 2), STEEL[1])
    # spare tyre strapped to the left flank, jerrycan to the right
    paint(cv, rect(W, H, 3, 21, 6, 30), TYRE, base=2)
    cv.put(rect(W, H, 4, 22, 5, 29), TYRE[0])
    cv.put(rect(W, H, 3, 25, 6, 25), LEATHER[2])
    paint(cv, rect(W, H, 28, 21, 32, 29), RUST[1:], base=2, noise=0.3, seed=seed)
    px(cv, [(30, 21), (31, 21)], STEEL[1])
    cv.put(rect(W, H, 28, 25, 32, 25), LEATHER[1])
    # body tub
    body = poly(W, H, [(11, 5), (24, 5), (28, 10), (28, 43), (25, 47), (10, 47), (7, 43), (7, 10)])
    paint(cv, body, RUST, noise=0.4, seed=seed, depth=2)
    # mismatched salvaged hood plates, welded together
    left = poly(W, H, [(11, 6), (17, 6), (17, 18), (9, 18), (9, 11)])
    right = poly(W, H, [(18, 6), (24, 6), (26, 11), (26, 18), (18, 18)])
    paint(cv, left, STEEL, noise=0.3, seed=seed + 1)
    paint(cv, right, KHAKI, base=3, noise=0.35, seed=seed + 2)
    stripes = (rect(W, H, 12, 7, 13, 17) & left) | (line(W, H, [(19, 16), (24, 9)], 2) & right)
    paint(cv, stripes, pc, base=2, light=False)
    chip(cv, stripes, 0.3, seed, STEEL[2])
    weld(cv, [(17, 6), (17, 18)])
    weld(cv, [(9, 19), (26, 19)])
    weather(cv, body | left | right, seed, holes=4, dents=3, scratches=6, streaks=4)
    rivets(cv, [(10, 12), (25, 12), (10, 16), (25, 16)])
    headlight(cv, 11, 8)
    headlight(cv, 24, 8, broken=True)
    # spiked ram bar
    paint(cv, line(W, H, [(7, 4), (28, 4)], 2), STEEL, base=3)
    for x in (8, 13, 22, 27):
        paint(cv, poly(W, H, [(x - 1, 4), (x + 1, 4), (x, 0)]), STEEL[1:], base=2)
    # open cockpit seen from above: seat back, jacket shoulders, steel pot helmet, scarf
    paint(cv, rect(W, H, 10, 20, 25, 35), STEEL[:3], base=1, light=False)
    paint(cv, rect(W, H, 14, 30, 21, 34), LEATHER[:3], base=1)
    paint(cv, ellipse(W, H, 12, 25, 23, 31), LEATHER, base=1, noise=0.3, seed=seed)
    cv.put(rect(W, H, 15, 30, 20, 30), pc[1])
    px(cv, [(21, 31), (22, 32)], pc[1])
    paint(cv, circle(W, H, 17.5, 27, 2.3), STEEL, base=3)
    # roll cage with welded joints and barbed wire
    for seg in [[(9, 20), (26, 20)], [(9, 36), (26, 36)], [(9, 20), (9, 36)], [(26, 20), (26, 36)]]:
        paint(cv, line(W, H, seg, 1), STEEL, base=3, light=False)
    px(cv, [(9, 20), (26, 20), (9, 36), (26, 36)], STEEL[5])
    barbed(cv, (8, 22), (8, 34))
    # exposed rear engine: cylinder heads, air filter, curling exhausts
    paint(cv, rect(W, H, 11, 37, 24, 46), STEEL, noise=0.25, seed=seed + 3, depth=2)
    for i in range(3):
        paint(cv, rect(W, H, 12, 38 + i * 3, 14, 39 + i * 3), STEEL, base=4)
        paint(cv, rect(W, H, 21, 38 + i * 3, 23, 39 + i * 3), STEEL, base=4)
    paint(cv, circle(W, H, 17.5, 41.5, 2.3), STEEL[1:], base=3)
    px(cv, [(17, 41), (18, 42)], STEEL[0])
    for pts in ([(12, 45), (9, 48), (9, 51)], [(23, 45), (26, 48), (26, 51)]):
        paint(cv, line(W, H, pts, 2), RUST[1:], base=2)
        px(cv, [pts[-1]], OUTLINE)
    # antenna with a tattered flag streaming backwards
    px(cv, [(27, 44)], STEEL[1])
    paint(cv, poly(W, H, [(27, 44), (31, 45), (29, 46), (31, 48), (28, 48)]), pc, base=3)
    # pintle MG fed by an ammo belt
    paint(cv, rect(W, H, 21, 21, 24, 24), KHAKI, base=2)
    ammo_belt(cv, [(21, 22), (19, 22)])
    turret(cv, 17.5, 22, 2.5, gun_angle, 14, barrels=1, bw=2, seed=seed)
    outline(cv, OUTLINE)
    return cv


def war_rig_cab(player="red", aim=(0.0,), seed=3):
    """Late-game tractor: spiked V-plow, supercharged V8, armoured cabin, roof twin-MG (48x72)."""
    W, H = 48, 72
    cv = Canvas(W, H)
    pc = PLAYERS[player]
    for x, y, side in [(1, 16, "L"), (40, 16, "R"), (1, 46, "L"), (40, 46, "R"), (1, 58, "L"), (40, 58, "R")]:
        wheel(cv, x, y, 7, 11, side, fender=(y != 58))
    paint(cv, rect(W, H, 8, 12, 39, 68), STEEL[:4], base=1, light=False)
    # side skirts with barbed wire
    for x0, bx in ((5, 4), (39, 43)):
        sk = rect(W, H, x0, 29, x0 + 3, 44)
        paint(cv, sk, STEEL, noise=0.3, seed=seed + x0)
        weather(cv, sk, seed + x0, holes=1, scratches=2)
        barbed(cv, (bx, 30), (bx, 43))
    # hood: three salvaged panels
    hl = poly(W, H, [(10, 12), (17, 12), (17, 33), (8, 33), (8, 16)])
    hc = rect(W, H, 18, 12, 29, 33)
    hr = poly(W, H, [(30, 12), (37, 12), (39, 16), (39, 33), (30, 33)])
    paint(cv, hl, RUST, noise=0.4, seed=seed + 1, depth=2)
    paint(cv, hc, STEEL, noise=0.3, seed=seed + 2, depth=2)
    paint(cv, hr, KHAKI, base=3, noise=0.4, seed=seed + 3, depth=2)
    stripes = rect(W, H, 11, 14, 12, 31) | rect(W, H, 34, 14, 35, 31)
    paint(cv, stripes, pc, base=2, light=False)
    chip(cv, stripes, 0.35, seed, STEEL[2])
    weld(cv, [(17, 12), (17, 33)])
    weld(cv, [(30, 12), (30, 33)])
    # cabin: half steel, half rust
    cab_l, cab_r = rect(W, H, 8, 33, 23, 50), rect(W, H, 24, 33, 39, 50)
    paint(cv, cab_l, STEEL, noise=0.3, seed=seed + 5, depth=2)
    paint(cv, cab_r, RUST, base=2, noise=0.4, seed=seed + 6, depth=2)
    roof_stripe = rect(W, H, 8, 40, 39, 41)
    paint(cv, roof_stripe, pc, base=2, light=False)
    chip(cv, roof_stripe, 0.4, seed + 1, STEEL[2])
    weld(cv, [(23, 33), (23, 50)])
    deck = rect(W, H, 8, 51, 39, 67)
    paint(cv, deck, RUST, noise=0.45, seed=seed + 7)
    weather(cv, hl | hc | hr | cab_l | cab_r | deck, seed, holes=7, dents=5, scratches=10, streaks=6)
    # blower, intake and hoses
    paint(cv, rect(W, H, 18, 13, 29, 24), STEEL, noise=0.15, seed=seed + 2, depth=2)
    for yy in range(15, 24, 2):
        cv.put(rect(W, H, 19, yy, 28, yy), STEEL[1])
    paint(cv, rect(W, H, 20, 9, 27, 13), STEEL[1:], base=2)
    cv.put(rect(W, H, 21, 10, 26, 10), OUTLINE)
    for pts in ([(18, 20), (15, 22), (15, 27)], [(29, 20), (32, 22), (32, 27)]):
        cv.put(line(W, H, pts, 2), TYRE[2])
        px(cv, [pts[0]], STEEL[4])
    # exhaust stacks with soot
    for sx in (12.5, 34.5):
        soot = circle(W, H, sx, 28, 4) & (value_noise(H, W, 2, seed) > 0.35)
        shade(cv, soot, 0.6)
        paint(cv, circle(W, H, sx, 28, 2.6), STEEL[:3], base=1)
        cv.put(circle(W, H, sx, 28, 1.0), OUTLINE)
    headlight(cv, 10, 14)
    headlight(cv, 37, 14)
    # V-plow: spikes, draped chain, mite-skull trophy
    plow = poly(W, H, [(3, 11), (24, 2), (44, 11), (44, 14), (24, 6), (3, 14)])
    paint(cv, plow, STEEL, noise=0.35, seed=seed + 4)
    weather(cv, plow, seed + 4, holes=2, scratches=4, streaks=3)
    for x in range(5, 44, 5):
        y = 11 - (x if x < 24 else 48 - x) * 9 / 21
        paint(cv, poly(W, H, [(x - 1, y), (x + 1, y), (x - 1 if x < 24 else x + 1, y - 3)]), STEEL[2:], base=2)
    chain(cv, [(7, 12), (12, 14), (17, 12)])
    chain(cv, [(30, 12), (35, 14), (40, 12)])
    paint(cv, ellipse(W, H, 21, 3, 26, 7), BONE, base=3)
    px(cv, [(22, 5), (25, 5)], OUTLINE)
    # windscreen slit behind a welded mesh
    cv.put(rect(W, H, 10, 34, 37, 36), OUTLINE)
    for x in range(10, 38, 3):
        cv.put(rect(W, H, x, 34, x, 36), STEEL[3])
    px(cv, [(14, 35), (31, 35)], GLASS[1])
    rivets(cv, [(10, 38), (37, 38), (10, 48), (37, 48)])
    # roof: sandbags around the gun ring
    for i, (x0, y0) in enumerate([(9, 43), (9, 46), (32, 43), (32, 46)]):
        sandbag(cv, x0, y0, x0 + 6, y0 + 3, seed + i)
    # rear deck: ammo crates, tarp-covered cargo, fuel drums
    for x, y in [(10, 53), (10, 60)]:
        paint(cv, rect(W, H, x, y, x + 6, y + 5), KHAKI, base=2, noise=0.2, seed=x + y)
        cv.put(rect(W, H, x, y + 2, x + 6, y + 2), KHAKI[1])
    tarp(cv, 18, 52, 28, 65, seed + 8)
    paint(cv, rect(W, H, 30, 53, 37, 66), RUST[1:], base=2, noise=0.3, seed=seed + 9)
    cv.put(rect(W, H, 30, 59, 37, 59), RUST[0])
    hazard_stripes(cv, rect(W, H, 30, 64, 37, 66))
    paint(cv, rect(W, H, 21, 67, 26, 71), STEEL[:4], base=2)
    turret(cv, 23.5, 45, 5, aim[0], 15, barrels=2, bw=2, seed=seed)
    outline(cv, OUTLINE)
    return cv


def war_rig_trailer(player="red", aim=(0.0, 0.0, math.pi), seed=5):
    """Trailer = extra chassis grid: turrets, ammo, mortar, fuel tank, rear MG, armour edges (52x90)."""
    W, H = 52, 90
    cv = Canvas(W, H)
    pc = PLAYERS[player]
    for x, y, side in [(1, 62, "L"), (44, 62, "R"), (1, 75, "L"), (44, 75, "R")]:
        wheel(cv, x, y, 7, 11, side, fender=(y == 62))
    paint(cv, rect(W, H, 23, 0, 28, 5), STEEL[:4], base=2)  # tongue
    bed = rect(W, H, 7, 4, 44, 86)
    paint(cv, bed, STEEL[:4], base=1, noise=0.35, seed=seed)  # dark bed so the modules pop
    for yy in range(10, 86, 6):  # tread-plate texture
        cv.put(pixels(W, H, [(x, yy + (x // 3) % 2) for x in range(9, 43, 3)]), STEEL[2])
    for yy in (24, 46, 60):  # the module grid is visible on the bed
        cv.put(rect(W, H, 9, yy, 42, yy), STEEL[0])
        weld(cv, [(9, yy + 1), (16, yy + 1)])
        weld(cv, [(31, yy + 1), (42, yy + 1)])
    weather(cv, bed, seed, holes=6, dents=4, scratches=10, streaks=6)
    # uneven armour plates, welded, with barbed wire on the outside
    rng = np.random.default_rng(seed)
    for x0, bx in ((4, 3), (43, 48)):
        y = 6
        while y < 58:
            hgt = int(rng.integers(9, 15))
            wob = int(rng.integers(0, 2))
            plate_m = rect(W, H, x0 - wob * (x0 < 20), y, x0 + 4 + wob * (x0 > 20), min(57, y + hgt - 1))
            paint(cv, plate_m, STEEL if rng.random() < 0.6 else RUST, noise=0.35, seed=seed + y + x0)
            weather(cv, plate_m, seed + y, holes=1, scratches=1, streaks=1)
            weld(cv, [(x0, y), (x0 + 4, y)])
            rivets(cv, [(x0 + 2, y + 3)])
            y += hgt
        paint(cv, rect(W, H, x0 + 1, 22, x0 + 3, 30), pc, base=2, light=False)
        chip(cv, rect(W, H, x0 + 1, 22, x0 + 3, 30), 0.3, seed + x0, STEEL[2])
        barbed(cv, (bx, 8), (bx, 56))
    # front sandbag wall
    for i, x0 in enumerate((8, 15, 30, 37)):
        sandbag(cv, x0, 3, x0 + 6, 6, seed + i)
    # row 1: ammo crates feeding the twin MG, generator
    for x, y in [(10, 8), (10, 16), (35, 8)]:
        paint(cv, rect(W, H, x, y, x + 6, y + 6), KHAKI, base=2, noise=0.25, seed=x + y)
        cv.put(rect(W, H, x, y + 3, x + 6, y + 3), KHAKI[1])
        px(cv, [(x + 1, y + 1)], KHAKI[4])
    ammo_belt(cv, [(17, 11), (20, 12), (22, 14)])
    paint(cv, rect(W, H, 35, 16, 41, 23), STEEL, base=2)
    px(cv, [(37, 18), (39, 18), (37, 20), (39, 20)], STEEL[0])
    cv.put(line(W, H, [(38, 23), (38, 27), (35, 30)], 1), OUTLINE)  # cable to the cannon
    # row 2: mortar with a rack of shells
    paint(cv, circle(W, H, 16, 35, 6.5), STEEL, noise=0.3, seed=seed + 7)
    paint(cv, circle(W, H, 16, 35, 3.5), STEEL[:3], base=2)
    cv.put(circle(W, H, 16, 35, 2.2), OUTLINE)
    for i in range(4):
        paint(cv, rect(W, H, 9 + i * 2, 42, 9 + i * 2, 44), BRASS, base=2, light=False)
        px(cv, [(9 + i * 2, 42)], BRASS[3])
    # row 3: fuel tank, shot through and leaking
    tank = ellipse(W, H, 9, 48, 42, 58)
    paint(cv, tank, RUST, noise=0.35, seed=seed + 8, depth=2)
    hazard_stripes(cv, rect(W, H, 9, 48, 13, 58) & tank)
    hazard_stripes(cv, rect(W, H, 38, 48, 42, 58) & tank)
    cv.put(rect(W, H, 14, 51, 37, 51), RUST[5])
    weather(cv, tank & rect(W, H, 14, 48, 37, 58), seed + 8, holes=3, dents=2, streaks=3)
    chain(cv, [(12, 47), (12, 59)])
    chain(cv, [(39, 47), (39, 59)])
    # row 4: rear deck with tarp cargo, spare tyre, flag
    tarp(cv, 9, 62, 21, 72, seed + 9)
    paint(cv, circle(W, H, 14, 79, 4), TYRE, base=2)
    cv.put(circle(W, H, 14, 79, 1.3), STEEL[3])
    cv.put(line(W, H, [(40, 84), (40, 70)], 1), STEEL[1])
    paint(cv, poly(W, H, [(40, 70), (47, 71), (45, 73), (48, 75), (40, 75)]), pc, base=3)
    # weapons last so barrels overlap the bed
    turret(cv, 25.5, 14, 5.5, aim[0], 14, barrels=2, bw=2, seed=seed)
    turret(cv, 34, 35, 6.5, aim[1], 18, barrels=1, bw=3, seed=seed + 1)
    turret(cv, 27, 77, 4.5, aim[2], 12, barrels=1, bw=2, seed=seed + 2)
    outline(cv, OUTLINE)
    return cv


# ---------------------------------------------------------------- aliens

def sand_mite(active=True, seed=0, volatile=False):
    """Swarm alien: sand-coloured beetle-tick. At rest only dark eyes; active = glowing eyes."""
    W, H = 15, 15
    cv = Canvas(W, H)
    legs = [[(5, 6), (2, 4), (1, 2)], [(5, 8), (2, 8), (1, 9)], [(5, 10), (3, 12), (2, 13)]]
    for lg in legs:
        cv.put(line(W, H, lg, 1), CHITIN[1])
        cv.put(line(W, H, [(14 - x, y) for x, y in lg], 1), CHITIN[1])
    tint = int(seed) % 2
    paint(cv, ellipse(W, H, 4, 5, 10, 13), CHITIN[1 + tint:], noise=0.3, seed=seed)
    paint(cv, ellipse(W, H, 5, 2, 9, 6), CHITIN[:5], base=2)
    cv.put(pixels(W, H, [(5, 1), (9, 1)]), CHITIN[0])  # mandibles
    cv.put(rect(W, H, 7, 7, 7, 12), CHITIN[1])  # shell seam
    eye = GLOW[4] if active else CHITIN[0]
    cv.put(pixels(W, H, [(6, 3), (8, 3)]), eye, emissive=active)
    if volatile:
        for cx, cy in [(5.5, 9.5), (8.5, 10.5)]:
            paint(cv, circle(W, H, cx, cy, 1.6), VOLATILE, base=3, emissive=True)
    outline(cv, OUTLINE)
    return cv


def boulder_back(active=False, hardened=False, seed=7):
    """Brute: shell like a desert boulder. Resting = a rock. Active = glowing fissures."""
    W, H = 46, 42
    cv = Canvas(W, H)
    # stubby legs peeking out
    for y in (14, 22, 30):
        paint(cv, rect(W, H, 3, y, 7, y + 2), CHITIN[:4], base=1)
        paint(cv, rect(W, H, 38, y, 42, y + 2), CHITIN[:4], base=1)
    # head + mandibles
    paint(cv, ellipse(W, H, 17, 2, 28, 10), CHITIN, base=2)
    cv.put(line(W, H, [(18, 4), (16, 1)], 1), CHITIN[0])
    cv.put(line(W, H, [(27, 4), (29, 1)], 1), CHITIN[0])
    eye = GLOW[4] if active else CHITIN[0]
    cv.put(pixels(W, H, [(20, 5), (25, 5)]), eye, emissive=active)
    shell = blob(W, H, 22.5, 22, 17, 15, rough=0.25, seed=seed, cell=5)
    paint(cv, shell, ROCK, noise=0.35, seed=seed, depth=3)
    # mottled lichen/sand on top
    n = value_noise(H, W, 3, seed + 5)
    dust = shell & shift(shell, 0, 2) & shift(shell, 2, 0) & (n > 0.7)
    cv.put(dust, SAND[3])
    cv.put(dust & (n > 0.8), SAND[4])
    # fissures (random walks)
    rng = np.random.default_rng(seed)
    crack = np.zeros((H, W), bool)
    for _ in range(5):
        x, y = 22.5 + rng.uniform(-4, 4), 22 + rng.uniform(-3, 3)
        ang = rng.uniform(0, 2 * math.pi)
        for _ in range(13):
            ang += rng.uniform(-0.6, 0.6)
            x, y = x + math.cos(ang), y + math.sin(ang)
            if 0 <= int(y) < H and 0 <= int(x) < W:
                crack[int(y), int(x)] = True
    crack &= shell & shift(shell, 0, 1) & shift(shell, 0, -1)
    if active:
        cv.put(crack, GLOW[3], emissive=True)
        cv.put(crack & ~shift(crack, 1, 0), GLOW[5], emissive=True)
    else:
        cv.put(crack, ROCK[0])
    if hardened:
        for i, (cx, cy, a, l) in enumerate([(14, 16, -0.6, 8), (30, 14, 0.5, 9), (22, 12, 0.05, 7),
                                            (34, 26, 1.2, 7), (11, 27, -1.3, 7)]):
            tip = polar(cx, cy, a, l)
            p1 = polar(cx, cy, a + math.pi / 2, 2.2)
            p2 = polar(cx, cy, a - math.pi / 2, 2.2)
            paint(cv, poly(W, H, [p1, tip, p2]), CRYSTAL, base=3, seed=i)
            cv.put(line(W, H, [(cx, cy), tip], 1), CRYSTAL[4])
    outline(cv, OUTLINE)
    return cv


def spitter(active=True, seed=11):
    """Ranged alien: long body with a translucent acid sac that lights up before it spits."""
    W, H = 22, 32
    cv = Canvas(W, H)
    for y, dx in [(8, 6), (11, 7), (14, 7)]:
        cv.put(line(W, H, [(9, y), (9 - dx, y - 2), (9 - dx - 1, y + 3)], 1), CHITIN[1])
        cv.put(line(W, H, [(12, y), (12 + dx, y - 2), (12 + dx + 1, y + 3)], 1), CHITIN[1])
    sac = ellipse(W, H, 3, 14, 18, 30)
    if active:
        paint(cv, sac, GLOW[1:5], base=2, emissive=True)
        paint(cv, ellipse(W, H, 7, 19, 13, 26), GLOW[3:], base=1, light=False, emissive=True)
    else:
        paint(cv, sac, [GLOW[0], GLOW[1], CHITIN[2], CHITIN[3]], base=1, noise=0.3, seed=seed)
    for yy in (18, 22, 26):  # chitin bands over the sac
        cv.put(line(W, H, [(4, yy), (17, yy)], 1) & sac, CHITIN[1])
    paint(cv, ellipse(W, H, 7, 6, 14, 15), CHITIN, noise=0.25, seed=seed)
    paint(cv, ellipse(W, H, 8, 1, 13, 7), CHITIN, base=2)
    cv.put(pixels(W, H, [(10, 1), (11, 1)]), OUTLINE)
    if active:
        cv.put(pixels(W, H, [(10, 0), (11, 0)]), GLOW[4], emissive=True)
    cv.put(pixels(W, H, [(9, 3), (12, 3)]), GLOW[4] if active else CHITIN[0], emissive=active)
    outline(cv, OUTLINE)
    return cv


def glass_wing(active=True, seed=13):
    """Flyer: chitin dragonfly with stained-glass wings of fused sand."""
    W, H = 36, 30
    cv = Canvas(W, H)
    wings = [
        [(17, 9), (3, 3), (1, 7), (5, 11), (16, 12)],
        [(17, 13), (4, 15), (5, 19), (10, 19), (17, 15)],
    ]
    vein_col = GLOW[3] if active else CHITIN[1]
    for wpts in wings:
        for mirror in (False, True):
            pts = [(35 - x, y) for x, y in wpts] if mirror else wpts
            wm = poly(W, H, pts)
            paint(cv, wm, GLASS, base=2, alpha=0.7, noise=0.3, seed=seed)
            edge = wm & ~(shift(wm, 1, 0) & shift(wm, -1, 0) & shift(wm, 0, 1) & shift(wm, 0, -1))
            cv.put(edge, CHITIN[1])
            root = pts[0]
            for tip in pts[1:-1]:
                mid = ((root[0] + tip[0]) / 2, (root[1] + tip[1]) / 2 + 1)
                cv.put(line(W, H, [root, mid], 1) & wm, vein_col, emissive=active)
    paint(cv, rect(W, H, 17, 14, 18, 28), CHITIN, base=2)
    cv.put(pixels(W, H, [(17, 18), (18, 22), (17, 25)]), CHITIN[0])
    paint(cv, ellipse(W, H, 15, 7, 20, 15), CHITIN, base=3, noise=0.2, seed=seed)
    paint(cv, ellipse(W, H, 15, 3, 20, 8), CHITIN, base=2)
    cv.put(pixels(W, H, [(16, 4), (19, 4)]), GLOW[4] if active else CHITIN[0], emissive=active)
    outline(cv, OUTLINE)
    return cv


def dune_worm(seed=17):
    """Burrower breaching the sand: debris ring, lip, rings of bone teeth, glowing throat."""
    W, H = 56, 56
    cv = Canvas(W, H)
    c = 27.5
    debris = blob(W, H, c, c, 26, 24, rough=0.35, seed=seed, cell=4)
    paint(cv, debris, SAND, noise=0.55, seed=seed, depth=2)
    rng = np.random.default_rng(seed)
    for _ in range(9):
        a = rng.uniform(0, 2 * math.pi)
        x, y = polar(c, c, a, rng.uniform(18, 24))
        paint(cv, blob(W, H, x, y, 2.5, 2, 0.4, rng.integers(99), 2), ROCK, noise=0.3, seed=int(x))
    lip = circle(W, H, c, c, 17)
    paint(cv, lip, CHITIN, base=2, noise=0.3, seed=seed + 1, depth=2)
    for i in range(14):
        a = i / 14 * 2 * math.pi
        cv.put(line(W, H, [polar(c, c, a, 14), polar(c, c, a, 17)], 1), CHITIN[1])
    throat = circle(W, H, c, c, 13.5)
    cv.put(throat, "#120c10")
    paint(cv, circle(W, H, c, c, 6), GLOW[:5], base=2, emissive=True)
    paint(cv, circle(W, H, c, c, 3), GLOW[3:], base=1, light=False, emissive=True)
    for ring_r, n, size in [(13.5, 16, 3.5), (9, 11, 2.5)]:
        for i in range(n):
            a = (i + 0.5 * (ring_r < 10)) / n * 2 * math.pi
            base_l = polar(c, c, a - 0.13, ring_r)
            base_r = polar(c, c, a + 0.13, ring_r)
            tip = polar(c, c, a, ring_r - size)
            paint(cv, poly(W, H, [base_l, tip, base_r]), BONE, base=3)
    outline(cv, OUTLINE)
    return cv


# ---------------------------------------------------------------- props

def boulder(rx, ry, seed=0):
    """Single faceted desert boulder: lit cap, dark underside, a crack or two."""
    W, H = int(rx * 2 + 4), int(ry * 2 + 5)
    cv = Canvas(W, H)
    cx, cy = W / 2 - 0.5, H / 2 - 1
    body = blob(W, H, cx, cy, rx, ry, 0.3, seed, 3)
    paint(cv, body, ROCK, base=2, noise=0.3, seed=seed, depth=3)
    cap = blob(W, H, cx - rx * 0.25, cy - ry * 0.3, rx * 0.6, ry * 0.5, 0.35, seed + 1, 3) & body
    paint(cv, cap & shift(body, 1, 1), ROCK, base=4, noise=0.3, seed=seed + 2, light=False)
    rng = np.random.default_rng(seed)
    x, y, ang = cx + rng.uniform(-2, 2), cy - ry * 0.6, rng.uniform(1.2, 2.0)
    crack = []
    for _ in range(int(ry * 1.2)):
        crack.append((x, y))
        ang += rng.uniform(-0.5, 0.5)
        x, y = x + math.cos(ang), y + math.sin(ang)
    cv.put(line(W, H, crack, 1) & body & shift(body, 0, 1), ROCK[1])
    outline(cv, OUTLINE)
    return cv


def rock_cluster(seed=0, scale=1.0):
    W, H = int(44 * scale), int(34 * scale)
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    parts = sorted([(rng.uniform(5, 11) * scale, rng.uniform(4, 8) * scale) for _ in range(4)], reverse=True)
    for i, (rx, ry) in enumerate(parts):
        b = boulder(rx, ry, seed + i * 7)
        x = rng.uniform(0, max(1, W - b.w))
        y = rng.uniform(0, max(1, H - b.h))
        paste(cv, b, x, y)
    return cv


def ribcage(seed=0):
    """Bleached ribs of a giant creature half-buried in the dunes."""
    W, H = 110, 74
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    sy = 37
    paint(cv, line(W, H, [(4, sy + 2), (36, sy - 1), (70, sy - 1), (104, sy + 3)], 4), BONE, base=2,
          noise=0.25, seed=seed)
    for i, x in enumerate(range(18, 92, 13)):
        for sgn in (-1, 1):
            if rng.random() < 0.12:
                continue  # rib lost to the sand
            length = rng.uniform(0.55, 0.8) if rng.random() < 0.25 else 1.0
            pts = [(x + 15 * t * t, sy + sgn * 24 * math.sin(t * math.pi * 0.6))
                   for t in np.linspace(0, length, 12)]
            paint(cv, line(W, H, pts[:7], 3), BONE, base=3, noise=0.3, seed=seed + i)
            paint(cv, line(W, H, pts[6:], 2), BONE, base=3, noise=0.3, seed=seed + i)
    for i in range(6):  # vertebra knobs
        x = 12 + i * 15
        paint(cv, circle(W, H, x, sy, 3), BONE, base=3)
    outline(cv, OUTLINE)
    return cv


def hull_plate(seed=0):
    """Colony-ship debris: a big panel with seams and rust, partly drowned in sand."""
    W, H = 96, 64
    cv = Canvas(W, H)
    m = poly(W, H, [(6, 14), (70, 2), (92, 20), (86, 58), (20, 62), (2, 40)])
    paint(cv, m, STEEL, noise=0.3, seed=seed, depth=2)
    n = value_noise(H, W, 6, seed + 1)
    cv.put(m & (n > 0.66), RUST[2])
    cv.put(m & (n > 0.76), RUST[3])
    for seg in [[(8, 28), (88, 18)], [(12, 46), (88, 38)], [(40, 6), (46, 60)]]:
        cv.put(line(W, H, seg, 1) & m, STEEL[1])
    rivets(cv, [(20, 24), (34, 22), (60, 19), (24, 42), (52, 40), (74, 37)])
    # panel stencil (colony ship registry)
    cv.put(rect(W, H, 56, 44, 76, 50) & m, STEEL[1])
    for i, x in enumerate(range(57, 76, 4)):
        cv.put(rect(W, H, x, 45, x + 2, 49) & m, HAZARD if i % 2 == 0 else STEEL[4])
    # sand drift swallowing the lower edge
    drift = blob(W, H, 50, 70, 60, 22, 0.35, seed + 2, 4) & m
    paint(cv, drift, SAND, base=4, noise=0.4, seed=seed + 3, light=False)
    outline(cv, OUTLINE)
    return cv


def scrap_bit(seed=0):
    W, H = 7, 7
    cv = Canvas(W, H)
    rng = np.random.default_rng(seed)
    pts = [(rng.uniform(0.5, 2.5), rng.uniform(0.5, 2.5)), (rng.uniform(4, 6), rng.uniform(1, 3)),
           (rng.uniform(4, 6), rng.uniform(4, 6)), (rng.uniform(1, 3), rng.uniform(4, 6))]
    paint(cv, poly(W, H, pts), STEEL, base=4, noise=0.4, seed=seed)
    cv.put(pixels(W, H, [(2, 2)]), STEEL[5])
    return cv


def mite_carcass(seed=0):
    """Dead mite: flipped, legs curled, teal ichor."""
    W, H = 14, 13
    cv = Canvas(W, H)
    paint(cv, blob(W, H, 7, 7, 6.5, 5, 0.5, seed, 2), GLOW[:2], base=0, light=False, alpha=0.85)
    paint(cv, ellipse(W, H, 4, 4, 9, 10), CHITIN[:4], base=1, noise=0.4, seed=seed)
    for (a, b) in [((4, 5), (2, 3)), ((9, 5), (11, 3)), ((4, 9), (2, 11)), ((9, 9), (11, 11))]:
        cv.put(line(W, H, [a, b], 1), CHITIN[0])
    return cv
