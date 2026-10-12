"""Sprite definitions. All vehicles face north (up); light comes from the top-left."""

import math

import numpy as np

from palette import (BONE, CHITIN, CRYSTAL, GLASS, GLOW, HAZARD, KHAKI, LEATHER, OUTLINE, PLAYERS,
                     ROCK, RUST, SAND, STEEL, TYRE, VOLATILE)
from pixel import (Canvas, blob, circle, ellipse, line, outline, paint, paste, pixels, polar, poly,
                   rect, rgb, shift, value_noise)


# ---------------------------------------------------------------- shared parts

def wheel(cv, x, y, w, h, seed=0):
    W, H = cv.w, cv.h
    paint(cv, rect(W, H, x, y, x + w - 1, y + h - 1), TYRE, base=1)
    tread = np.zeros((H, W), bool)
    for yy in range(y + 1, y + h - 1, 2):
        tread[yy, x + 1:x + w - 1] = True
    cv.put(tread & rect(W, H, x, y, x + w - 1, y + h - 1), TYRE[3])
    cv.put(rect(W, H, x + w // 2, y + 2, x + w // 2, y + h - 3), TYRE[0])  # centre groove


def rivets(cv, pts):
    cv.put(pixels(cv.w, cv.h, pts), STEEL[5])
    cv.put(pixels(cv.w, cv.h, [(x, y + 1) for x, y in pts]), STEEL[0])


def hazard_stripes(cv, m, period=4):
    ys, xs = np.mgrid[0:cv.h, 0:cv.w]
    stripe = ((xs + ys) // (period // 2)) % 2 == 0
    cv.put(m & stripe, HAZARD)
    cv.put(m & ~stripe, OUTLINE)


def turret(cv, cx, cy, r, ang, length, barrels=1, bw=2, ramp=STEEL, seed=0):
    W, H = cv.w, cv.h
    paint(cv, circle(W, H, cx, cy, r), ramp, noise=0.15, seed=seed)
    paint(cv, circle(W, H, cx, cy, max(1, r - 2)), ramp, base=len(ramp) // 2 - 1, light=False)
    perp = ang + math.pi / 2
    offs = [0.0] if barrels == 1 else [-(bw / 2 + 0.6), bw / 2 + 0.6]
    for o in offs:
        sx, sy = cx + math.sin(perp) * o, cy - math.cos(perp) * o
        ex, ey = polar(sx, sy, ang, length)
        paint(cv, line(W, H, [(sx, sy), (ex, ey)], width=bw), STEEL[:5], base=2)
        mx, my = polar(sx, sy, ang, length - 0.5)
        cv.put(pixels(W, H, [(round(mx), round(my))]), STEEL[0])
    cv.put(pixels(W, H, [(round(cx - 1), round(cy - 1))]), STEEL[5])


# ---------------------------------------------------------------- vehicles

def buggy(player="red", gun_angle=0.0, seed=1):
    """Starter vehicle: welded scrap buggy with one pintle MG (about 34x50)."""
    W, H = 36, 52
    cv = Canvas(W, H)
    pc = PLAYERS[player]
    for x, y in [(3, 8), (26, 8), (3, 34), (26, 34)]:
        wheel(cv, x, y, 7, 11, seed)
    # suspension arms
    for (a, b) in [((9, 12), (13, 12)), ((26, 12), (22, 12)), ((9, 39), (13, 39)), ((26, 39), (22, 39))]:
        cv.put(line(W, H, [a, b], 2), STEEL[1])
    paint(cv, poly(W, H, [(11, 4), (24, 4), (28, 10), (28, 42), (25, 47), (10, 47), (7, 42), (7, 10)]),
          RUST, noise=0.35, seed=seed, depth=2)
    # bolted-on hood plate with player stripes
    hood = poly(W, H, [(12, 6), (23, 6), (25, 11), (25, 18), (10, 18), (10, 11)])
    paint(cv, hood, STEEL, noise=0.2, seed=seed + 1)
    for sx in (13, 20):
        paint(cv, rect(W, H, sx, 6, sx + 1, 18) & hood, pc, base=2, light=False)
    rivets(cv, [(11, 11), (24, 11), (11, 16), (24, 16)])
    cv.put(rect(W, H, 13, 4, 22, 4), STEEL[1])  # grille
    cv.put(pixels(W, H, [(14, 4), (16, 4), (18, 4), (20, 4)]), STEEL[3])
    # open cockpit
    paint(cv, rect(W, H, 10, 20, 25, 35), STEEL[:3], base=1, light=False)
    paint(cv, circle(W, H, 17.5, 29, 2.8), LEATHER, base=2)  # driver helmet
    cv.put(pixels(W, H, [(16, 27), (19, 27)]), GLASS[2])  # goggles glint
    # roll cage
    for seg in [[(9, 20), (26, 20)], [(9, 36), (26, 36)], [(9, 20), (9, 36)], [(26, 20), (26, 36)]]:
        paint(cv, line(W, H, seg, 1), STEEL, base=3, light=False)
    # rear deck: spare tyre + jerrycan
    paint(cv, rect(W, H, 9, 37, 26, 45), STEEL, base=2, noise=0.3, seed=seed + 3)
    paint(cv, circle(W, H, 14, 41, 3.4), TYRE, base=2)
    cv.put(circle(W, H, 14, 41, 1.2), STEEL[3])
    paint(cv, rect(W, H, 20, 38, 24, 44), RUST[1:], base=3)
    cv.put(pixels(W, H, [(22, 38), (22, 39)]), STEEL[1])
    cv.put(pixels(W, H, [(10, 47), (25, 47)]), STEEL[0])  # exhausts
    # pintle machine gun
    turret(cv, 17.5, 22, 2.5, gun_angle, 14, barrels=1, bw=2, seed=seed)
    paint(cv, rect(W, H, 21, 21, 24, 24), KHAKI, base=2)  # ammo box
    outline(cv, OUTLINE)
    return cv


def war_rig_cab(player="red", aim=(0.0,), seed=3):
    """Late-game tractor: V-plow, supercharged V8, armoured cabin, roof twin-MG (48x72)."""
    W, H = 48, 72
    cv = Canvas(W, H)
    pc = PLAYERS[player]
    for x, y in [(1, 16), (40, 16), (1, 46), (40, 46), (1, 58), (40, 58)]:
        wheel(cv, x, y, 7, 11, seed)
    # chassis + side skirts
    paint(cv, rect(W, H, 8, 12, 39, 68), STEEL[:4], base=1, light=False)
    for x0 in (6, 38):
        sk = rect(W, H, x0, 30, x0 + 3, 44)
        paint(cv, sk, STEEL, noise=0.2, seed=seed)
        rivets(cv, [(x0 + 1, 32), (x0 + 1, 38), (x0 + 1, 42)])
    # engine bay / hood
    hood = poly(W, H, [(10, 12), (37, 12), (39, 16), (39, 33), (8, 33), (8, 16)])
    paint(cv, hood, RUST, noise=0.35, seed=seed + 1, depth=2)
    paint(cv, rect(W, H, 18, 13, 29, 24), STEEL, noise=0.1, seed=seed + 2, depth=2)  # blower
    for yy in range(15, 24, 2):
        cv.put(rect(W, H, 19, yy, 28, yy), STEEL[1])
    paint(cv, rect(W, H, 20, 10, 27, 13), STEEL[1:], base=2)  # intake scoop
    for sx in (11, 33):
        paint(cv, circle(W, H, sx + 1.5, 28, 2.6), STEEL[:3], base=1)  # exhaust stacks
        cv.put(circle(W, H, sx + 1.5, 28, 1.0), OUTLINE)
    for sx in (12, 34):
        paint(cv, rect(W, H, sx, 15, sx + 1, 26) & hood, pc, base=2, light=False)
    # V-plow with spikes and a mite skull trophy
    plow = poly(W, H, [(3, 11), (24, 2), (44, 11), (44, 14), (24, 6), (3, 14)])
    paint(cv, plow, STEEL, noise=0.25, seed=seed + 4)
    for i, x in enumerate(range(5, 44, 5)):
        y = 11 - (x if x < 24 else 48 - x) * 9 / 21
        paint(cv, poly(W, H, [(x - 1, y), (x + 1, y), (x - 1 if x < 24 else x + 1, y - 3)]), STEEL[2:], base=2)
    paint(cv, ellipse(W, H, 21, 3, 26, 7), BONE, base=3)
    cv.put(pixels(W, H, [(22, 5), (25, 5)]), OUTLINE)
    # cabin
    cab = rect(W, H, 8, 33, 39, 50)
    paint(cv, cab, STEEL, noise=0.25, seed=seed + 5, depth=2)
    cv.put(rect(W, H, 10, 34, 37, 35), STEEL[0])  # windscreen slit
    cv.put(pixels(W, H, [(13, 34), (14, 34), (30, 35)]), GLASS[1])
    paint(cv, rect(W, H, 8, 40, 39, 41), pc, base=2, light=False)
    rivets(cv, [(10, 37), (37, 37), (10, 48), (37, 48)])
    # rear deck
    deck = rect(W, H, 8, 51, 39, 67)
    paint(cv, deck, RUST, noise=0.4, seed=seed + 6)
    for i, (x, y) in enumerate([(10, 53), (10, 60)]):
        paint(cv, rect(W, H, x, y, x + 6, y + 5), KHAKI, base=2)
        cv.put(rect(W, H, x, y + 2, x + 6, y + 2), KHAKI[1])
    paint(cv, rect(W, H, 30, 53, 37, 66), RUST[1:], base=2)  # fuel drum stack
    hazard_stripes(cv, rect(W, H, 30, 64, 37, 66))
    paint(cv, rect(W, H, 21, 67, 26, 71), STEEL[:4], base=2)  # hitch
    turret(cv, 23.5, 45, 5, aim[0], 15, barrels=2, bw=2, seed=seed)
    outline(cv, OUTLINE)
    return cv


def war_rig_trailer(player="red", aim=(0.0, 0.0, math.pi), seed=5):
    """Trailer = extra chassis grid: turrets, ammo, mortar, fuel tank, rear MG, armour edges (52x88)."""
    W, H = 52, 90
    cv = Canvas(W, H)
    pc = PLAYERS[player]
    for x, y in [(1, 62), (44, 62), (1, 75), (44, 75)]:
        wheel(cv, x, y, 7, 11, seed)
    paint(cv, rect(W, H, 23, 0, 28, 5), STEEL[:4], base=2)  # tongue
    paint(cv, rect(W, H, 7, 4, 44, 86), STEEL, base=2, noise=0.3, seed=seed)
    for yy in range(10, 86, 6):  # tread-plate texture
        cv.put(pixels(W, H, [(x, yy + (x // 3) % 2) for x in range(9, 43, 3)]), STEEL[3])
    # module grid lines (the chassis grid is visible on the bed)
    for yy in (24, 46, 60):
        cv.put(rect(W, H, 9, yy, 42, yy), STEEL[0])
    # armour edges with player hazard paint
    for x0 in (4, 43):
        plates = rect(W, H, x0, 6, x0 + 4, 58)
        paint(cv, plates, STEEL, noise=0.25, seed=seed + x0, depth=1)
        for yy in range(6, 58, 13):
            cv.put(rect(W, H, x0, yy, x0 + 4, yy), STEEL[1])
            rivets(cv, [(x0 + 2, yy + 3), (x0 + 2, yy + 9)])
        paint(cv, rect(W, H, x0 + 1, 22, x0 + 3, 30), pc, base=2, light=False)
    # row 1: ammo crates | MG turret | ammo crate
    for x, y in [(10, 7), (10, 15), (35, 7)]:
        paint(cv, rect(W, H, x, y, x + 6, y + 6), KHAKI, base=2, noise=0.15, seed=x + y)
        cv.put(rect(W, H, x, y + 3, x + 6, y + 3), KHAKI[1])
        cv.put(pixels(W, H, [(x + 1, y + 1)]), KHAKI[4])
    paint(cv, rect(W, H, 35, 15, 41, 22), STEEL, base=2)  # generator
    cv.put(pixels(W, H, [(37, 17), (39, 17), (37, 19), (39, 19)]), STEEL[0])
    # row 2: mortar | heavy cannon
    paint(cv, circle(W, H, 16, 35, 6.5), STEEL, noise=0.2, seed=seed + 7)
    paint(cv, circle(W, H, 16, 35, 3.5), STEEL[:3], base=2)
    cv.put(circle(W, H, 16, 35, 2.2), OUTLINE)
    # row 3: fuel tank capsule
    tank = ellipse(W, H, 9, 48, 42, 58)
    paint(cv, tank, RUST, noise=0.25, seed=seed + 8, depth=2)
    hazard_stripes(cv, rect(W, H, 9, 48, 13, 58) & tank)
    hazard_stripes(cv, rect(W, H, 38, 48, 42, 58) & tank)
    cv.put(rect(W, H, 14, 51, 37, 51), RUST[5])
    # row 4: rear deck with crates, spare tyre, flag
    paint(cv, rect(W, H, 10, 63, 17, 70), KHAKI, base=2)
    paint(cv, circle(W, H, 14, 78, 4), TYRE, base=2)
    cv.put(circle(W, H, 14, 78, 1.3), STEEL[3])
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
