"""Bosses and late species (design doc 7a, 7f, 11d): Tripod Queen, Shard Colossus, Glass Wings,
Brood Carrier, Shrieker, plus their projectiles, telegraphs and carcass decals.

All aliens face north (up), light comes from the top-left. Builders return *un-outlined* canvases:
the exporter rotates them with RotSprite and outlines every frame afterwards (export_assets.strip);
the samples call `finish()` to outline a single unrotated frame.

Mineral biology: sandstone mounds, salt crystal, fused glass. At rest the shells sit in the desert
ramps; GLOW (cyan) only marks what is active: eyes, sacs, charged crystal, projectiles.
"""

import math

import numpy as np

from palette import (BONE, CANYON, CHITIN, CRYSTAL, GLASS, GLOW, OUTLINE, ROCK, SALT, SAND)
from pixel import (Canvas, bayer, blob, circle, ellipse, line, outline, paint, pixels, polar, poly,
                   shift, value_noise)

SANDSTONE = [CANYON[2], CANYON[3], SAND[1], SAND[2], SAND[3], SAND[4], SAND[5]]
STONE = ["#4f3524", "#75502f", "#9c7444", "#c09a5e", "#dcc088", "#f1e0b4"]  # fused sand glass (amber)
ICE = [CRYSTAL[1], CRYSTAL[2], CRYSTAL[3], SALT[3], SALT[4]]       # cool grey salt crystal (not GLOW)
LEAD = "#2a1e1e"            # dark seams between fused-glass panes
MEMBRANE = ["#5e5448", "#7f7464", "#a39783", "#c7bca4", "#e4dcc6"]   # milky, bleached sac skin
MURK = ["#3b3a33", "#4f4c41", "#6a6555"]                             # the sac's cloudy inside
DEAD_GOO = ["#24302f", "#34403d", "#4a5450"]
LIGHT2 = np.array([-0.70710678, -0.70710678])  # sun direction on screen (top-left)


def finish(cv):
    outline(cv, OUTLINE)
    return cv


def px(cv, pts, color, emissive=False):
    cv.put(pixels(cv.w, cv.h, [(int(math.floor(x)), int(math.floor(y))) for x, y in pts]), color,
           emissive=emissive)


# ---------------------------------------------------------------- shading helpers

def _grain(shape, seed):
    """Clustered 0..1 noise (blotches plus speckle) for rough, non-periodic shading."""
    return 0.65 * value_noise(*shape, 2, seed) + 0.35 * np.random.default_rng(seed).random(shape)


def sphere(cv, m, ramp, cx, cy, rx, ry, lo=0, hi=None, grain=0.6, seed=0, emissive=False):
    """Fill a mask as a lit dome (sun from the top-left, a little from above) with rough grain."""
    if not m.any():
        return
    hi = len(ramp) - 1 if hi is None else hi
    ys, xs = np.mgrid[0:cv.h, 0:cv.w] + 0.5
    nx, ny = (xs - cx) / rx, (ys - cy) / ry
    nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
    lum = np.clip(-0.5 * nx - 0.6 * ny + 0.62 * nz, 0, 1)
    t = lo + lum * (hi - lo + 0.6) + (_grain(m.shape, seed) - 0.5) * grain
    idx = np.clip(np.floor(t), 0, len(ramp) - 1).astype(int)
    rim = m & ~(shift(m, 0, 1) & shift(m, 1, 0))  # bottom-right rim falls into shadow
    idx[rim] = np.maximum(idx[rim] - 1, 0)
    cv.put(m, np.stack([np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)], np.float32)
                        for c in ramp])[idx], emissive=emissive)


def facet_tip(cv, cx, cy, r, ramp, base, rot=0.0, emissive=False, squash=1.0):
    """A hexagonal crystal standing up, seen from above: six facets meeting at a lit tip."""
    W, H = cv.w, cv.h
    v = [(cx + r * math.cos(rot + i * math.pi / 3), cy + r * squash * math.sin(rot + i * math.pi / 3))
         for i in range(6)]
    for i in range(6):
        a = rot + (i + 0.5) * math.pi / 3
        lum = math.cos(a) * LIGHT2[0] + math.sin(a) * LIGHT2[1]
        k = int(np.clip(round(base + 1.4 * lum), 0, len(ramp) - 1))
        cv.put(poly(W, H, [(cx, cy), v[i], v[(i + 1) % 6]]), ramp[k], emissive=emissive)
    px(cv, [(cx - 0.5, cy - 0.5)], ramp[-1], emissive)


def shard(cv, p0, p1, w, ramp, base, emissive=False, ridge=True):
    """A crystal blade lying from p0 to p1: two flat facets split by a ridge, lit from the top-left."""
    W, H = cv.w, cv.h
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = max(1e-3, math.hypot(dx, dy))
    ux, uy = dx / ln, dy / ln
    nx, ny = -uy, ux
    sh = (p0[0] + dx * 0.3, p0[1] + dy * 0.3)
    lum = nx * LIGHT2[0] + ny * LIGHT2[1]
    for s in (1, -1):
        k = int(np.clip(round(base + s * 1.3 * lum), 0, len(ramp) - 1))
        half = poly(W, H, [p0, (p0[0] + s * nx * w * 0.3, p0[1] + s * ny * w * 0.3),
                           (sh[0] + s * nx * w / 2, sh[1] + s * ny * w / 2), p1])
        cv.put(half, ramp[k], emissive=emissive)
    if ridge and ln > 4:
        cv.put(line(W, H, [p0, (p1[0] - ux, p1[1] - uy)], 1), ramp[min(len(ramp) - 1, base + 1)],
               emissive=emissive)


def limb(cv, p0, p1, w0, w1, ramp, base=2, seed=0, noise=0.3):
    """Tapered leg / arm segment with the light on its top-left edge."""
    W, H = cv.w, cv.h
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = max(1e-3, math.hypot(dx, dy))
    nx, ny = -dy / ln, dx / ln
    m = poly(W, H, [(p0[0] + nx * w0 / 2, p0[1] + ny * w0 / 2), (p1[0] + nx * w1 / 2, p1[1] + ny * w1 / 2),
                    (p1[0] - nx * w1 / 2, p1[1] - ny * w1 / 2), (p0[0] - nx * w0 / 2, p0[1] - ny * w0 / 2)])
    m |= line(W, H, [p0, p1], max(1, int(round(min(w0, w1)))))
    paint(cv, m, ramp, base=base, noise=noise, seed=seed)
    return m


def walk(rng, x, y, ang, steps, wiggle=0.55):
    pts = [(x, y)]
    for _ in range(steps):
        ang += rng.uniform(-wiggle, wiggle)
        x, y = x + math.cos(ang), y + math.sin(ang)
        pts.append((x, y))
    return pts


def cracks(W, H, cx, cy, n, length, seed, spread=3.0):
    rng = np.random.default_rng(seed)
    m = np.zeros((H, W), bool)
    for _ in range(n):
        for x, y in walk(rng, cx + rng.uniform(-spread, spread), cy + rng.uniform(-spread, spread),
                         rng.uniform(0, 2 * math.pi), length):
            if 0 <= int(y) < H and 0 <= int(x) < W:
                m[int(y), int(x)] = True
    return m


GLASS_TINTS = [  # fused-sand glass: amber, rose, milky salt, smoke, a little sea-glass; desaturated
    ([SAND[2], SAND[3], SAND[4], SAND[5]], 1),
    ([SAND[1], SAND[2], SAND[3], SAND[4]], 2),
    ([CANYON[3], CANYON[4], CANYON[5], BONE[3]], 1),
    ([CANYON[2], CANYON[3], CANYON[4], CANYON[5]], 2),
    ([SALT[0], SALT[1], SALT[2], SALT[3], SALT[4]], 2),
    ([ROCK[2], ROCK[3], ROCK[4], ROCK[5]], 1),
    (GLASS, 1),
    ([CRYSTAL[1], CRYSTAL[2], CRYSTAL[3], CRYSTAL[4]], 1),]


def stained_glass(cv, m, n_cells, seed, cx, cy, rx, ry, tints=None, lead=LEAD, glow_lead=0.0,
                  glints=0.4, emissive_cells=()):
    """Fused-glass panes (Voronoi cells) in a dome shape: each pane its own tint, dark leading,
    a lit top-left corner and a few refraction glints. glow_lead > 0 lights that share of the seams."""
    tints = GLASS_TINTS if tints is None else tints
    W, H = cv.w, cv.h
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(m)
    if len(ys) == 0:
        return
    pick = rng.choice(len(ys), size=min(n_cells, len(ys)), replace=False)
    sx, sy = xs[pick].astype(float), ys[pick].astype(float)
    gy, gx = np.mgrid[0:H, 0:W]
    d = (gx[..., None] - sx) ** 2 + (gy[..., None] - sy) ** 2
    cell = np.argmin(d, axis=2)
    cell[~m] = -1
    nxs, nys = (gx + 0.5 - cx) / rx, (gy + 0.5 - cy) / ry
    nz = np.sqrt(np.clip(1 - nxs ** 2 - nys ** 2, 0, 1))
    lum = np.clip(-0.5 * nxs - 0.6 * nys + 0.62 * nz, 0, 1)
    grain = _grain(m.shape, seed)
    for k in range(len(sx)):
        cm = cell == k
        if not cm.any():
            continue
        ramp, base = tints[rng.integers(len(tints))]
        ramp = list(ramp)
        cyx = np.argwhere(cm).mean(axis=0)
        # pane gradient: the corner toward the sun catches light, the far corner refracts darker
        local = ((gx - cyx[1]) + (gy - cyx[0])) / 6.0
        t = base + (lum - 0.5) * 1.8 - np.clip(local, -1, 1) * 0.8 + (grain - 0.5) * 0.5
        idx = np.clip(np.round(t), 0, len(ramp) - 1).astype(int)
        cols = np.stack([np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)], np.float32) for c in ramp])
        cv.put(cm, cols[idx], emissive=k in emissive_cells)
        if rng.random() < glints and cm.sum() > 10:  # refraction glint: a short bright diagonal
            ys2, xs2 = np.nonzero(cm & shift(cm, 2, 2) & shift(cm, -2, -2))
            if len(ys2):
                i = rng.integers(len(ys2))
                gxy = (xs2[i], ys2[i])
                cv.put(line(W, H, [gxy, (gxy[0] + 1.6, gxy[1] - 1.6)], 1) & cm, SALT[4])
    border = m & ((cell != shift(cell + 1, 1, 0) - 1) | (cell != shift(cell + 1, 0, 1) - 1))
    border &= shift(m, 1, 0) & shift(m, 0, 1)
    cv.put(border, lead)
    if glow_lead > 0:
        sel = border & (_grain(m.shape, seed + 9) < glow_lead)
        cv.put(sel, GLOW[3], emissive=True)
        cv.put(sel & (_grain(m.shape, seed + 10) < 0.3), GLOW[5], emissive=True)
    return cell


def _rgb(c):
    return np.array([int(c[i:i + 2], 16) for i in (1, 3, 5)], np.float32)


# ---------------------------------------------------------------- 1. Tripod Queen (boss)

TRIPOD_SIZE = 120   # canvas; exported in 128 px frames
TRIPOD_FRAME = 128
TRIPOD_ROWS = ("walk0", "walk1", "walk2", "walk3", "aim", "fire")


def tripod_queen(row="walk0", seed=41):
    """Three-legged artillery walker: a termite-mound / geode dome on three long sandstone legs, a mortar
    sac with a chimney mouth on top. Walk frames step one leg at a time; `aim` swells and lights the sac,
    the geode pockets and the vents; `fire` squeezes the sac and flashes the mouth."""
    W = H = TRIPOD_SIZE
    cv = Canvas(W, H)
    cx, cy = 60.0, 60.0
    mode = "walk" if row.startswith("walk") else row
    ph = int(row[-1]) if mode == "walk" else 0
    lit = mode in ("aim", "fire")
    rng = np.random.default_rng(seed)
    LEG = [CANYON[1], CANYON[2], CANYON[3], SAND[2], SAND[3], SAND[4]]

    # legs: front-left, front-right, rear. Per frame one leg swings forward, the planted ones slide back.
    leg_ang = (-1.05, 1.05, math.pi)
    for i, a0 in enumerate(leg_ang):
        t = ((ph / 4.0) + i / 3.0) % 1.0
        swing = mode == "walk" and t < 0.34
        f = (t / 0.34) if swing else 1 - (t - 0.34) / 0.66   # 0..1 forward position of the foot
        fwd = (f - 0.5) * 12.0 if mode == "walk" else 0.0
        a_foot = a0 + (0.1 if i == 0 else -0.1 if i == 1 else 0) * (mode != "walk")
        root = polar(cx, cy, a0, 14)
        knee = polar(cx, cy, a0, 31 - 2 * swing)
        knee = (knee[0], knee[1] - fwd * 0.4)
        foot = polar(cx, cy, a_foot, 55 - 5 * swing + 2 * (mode != "walk"))
        foot = (foot[0], foot[1] - fwd)
        # upper segment: banded sandstone plates; lower: dark chitin shin; lifted legs read lighter
        up = limb(cv, root, knee, 9, 7, LEG, base=3 + swing, seed=seed + i, noise=0.35)
        for tt in (0.3, 0.62):
            bx, by = root[0] + (knee[0] - root[0]) * tt, root[1] + (knee[1] - root[1]) * tt
            band = line(W, H, [polar(bx, by, a0 - math.pi / 2, 5), polar(bx, by, a0 + math.pi / 2, 5)], 1) & up
            cv.put(band, LEG[1])
        lo = limb(cv, knee, foot, 6, 3, CHITIN, base=2 + swing, seed=seed + 10 + i)
        mid = ((knee[0] + foot[0]) / 2, (knee[1] + foot[1]) / 2)
        cv.put(line(W, H, [polar(mid[0], mid[1], a0 - 1.57, 3), polar(mid[0], mid[1], a0 + 1.57, 3)], 1) & lo,
               CHITIN[0])
        # foot: three dark claws dug into the sand
        fa = math.atan2(foot[0] - knee[0], -(foot[1] - knee[1]))
        for d in (-0.6, 0.0, 0.6):
            tip = polar(foot[0], foot[1], fa + d, 4)
            cv.put(line(W, H, [foot, tip], 1), CHITIN[0])
        # raised knee: the highest point of the leg, a big lit joint with a spur
        kr = 4.8 + 0.6 * swing
        sphere(cv, circle(W, H, knee[0], knee[1], kr), SANDSTONE, knee[0], knee[1], kr, kr, lo=1,
               seed=seed + 20 + i)
        spur = polar(knee[0], knee[1], a0 - 0.5, kr + 4)
        shard(cv, polar(knee[0], knee[1], a0 - 0.5, kr - 1), spur, 3, BONE, 2, ridge=False)

    # body: a lumpy termite mound with spires, sandstone strata and geode pockets
    body = blob(W, H, cx, cy, 24, 22, rough=0.16, seed=seed, cell=5)
    sphere(cv, body, SANDSTONE, cx, cy - 2, 25, 23, lo=0, grain=0.9, seed=seed)
    ys, xs = np.mgrid[0:H, 0:W]
    n = value_noise(H, W, 3, seed + 3)
    strata = body & (np.sin((ys + 3.5 * np.sin(xs / 6.0 + seed)) / 1.9) > 0.86) & (n > 0.3)
    cv.rgb[strata] *= 0.82
    spires = [(-2.5, 15, 5.0), (-1.4, 17, 4.4), (1.3, 16, 4.8), (2.6, 13, 4.0), (0.4, 19, 3.6),
              (-0.5, 19, 3.4), (3.4, 18, 3.8), (-3.6, 10, 3.2)]
    for k, (a, r, rr) in enumerate(spires):  # termite spires: little lit cones with a vent on top
        bx, by = polar(cx, cy, a, r)
        m = blob(W, H, bx, by, rr, rr * 0.92, 0.25, seed + 30 + k, 2) & body
        drop = shift(m, -2, -2) & body & ~m  # each spire shades the mound behind it
        cv.rgb[drop] *= 0.72
        sphere(cv, m, SANDSTONE, bx, by, rr, rr, lo=1, hi=6, grain=0.5, seed=seed + 40 + k)
        cv.put(m & ~shift(m, 1, 1), CANYON[2])  # shaded far side
        vx, vy = bx - rr * 0.15, by - rr * 0.15
        cv.put(ellipse(W, H, vx - 1.1, vy - 0.9, vx + 1.1, vy + 0.9), OUTLINE)
        if lit and k % 2 == 0:
            px(cv, [(vx, vy)], GLOW[3], emissive=True)
    for k, (a, r, gr) in enumerate([(-2.0, 13, 5.0), (2.1, 15, 3.6)]):  # geodes: cracked-open shell
        gx, gy = polar(cx, cy, a, r)
        pocket = blob(W, H, gx, gy, gr, gr * 0.8, 0.35, seed + 60 + k, 2) & body
        cv.put(pocket, ROCK[0])
        lip = blob(W, H, gx, gy, gr + 1.3, gr * 0.8 + 1.3, 0.35, seed + 60 + k, 2) & body & ~pocket
        cv.put(lip & shift(pocket, 1, 1), SAND[5])      # broken far rim catches the sun
        cv.put(lip & ~shift(pocket, 1, 1), SALT[2])
        for j in range(5 if gr > 4 else 3):
            tx, ty = gx + rng.uniform(-gr + 1.5, gr - 1.5), gy + rng.uniform(-gr * 0.6 + 1, gr * 0.6 - 1)
            if lit:
                facet_tip(cv, tx, ty, 1.8, GLOW[1:], 2, rot=rng.uniform(0, 1), emissive=True)
            else:
                facet_tip(cv, tx, ty, 1.8, SALT, 2, rot=rng.uniform(0, 1))

    # head at the front rim: plated brow, hooked mandibles, two pairs of eyes
    hx, hy = cx, cy - 23
    head = ellipse(W, H, hx - 7, hy - 4, hx + 7, hy + 4)
    paint(cv, head, CHITIN, base=3, noise=0.3, seed=seed + 5)
    for s in (-1, 1):
        cv.put(line(W, H, [(hx + s * 4, hy - 3), (hx + s * 6, hy - 7), (hx + s * 3, hy - 10)], 2), CHITIN[1])
        px(cv, [(hx + s * 3, hy - 10)], CHITIN[0])
    cv.put(line(W, H, [(hx - 5, hy + 2), (hx + 5, hy + 2)], 1), CHITIN[1])
    px(cv, [(hx - 3, hy - 1), (hx + 2, hy - 1), (hx - 5, hy + 0), (hx + 4, hy + 0)], GLOW[4], emissive=True)

    # mortar sac on the crown: a puffball of gill-ribbed membrane around a chimney mouth
    sx, sy = cx + 1, cy + 2
    sr = {"walk": 10.0, "aim": 12.5, "fire": 9.0}[mode]
    sac = blob(W, H, sx, sy, sr, sr * 0.95, 0.1, seed + 7, 3)
    collar = blob(W, H, sx, sy, sr + 2, sr * 0.95 + 2, 0.1, seed + 7, 3) & ~sac
    cv.put(collar & ~shift(collar, 1, 1), SAND[5])
    cv.put(collar & shift(collar, 1, 1), CANYON[2])
    if mode == "walk":
        sphere(cv, sac, MEMBRANE, sx, sy, sr, sr, lo=0, hi=4, grain=0.6, seed=seed + 8)
    else:
        sphere(cv, sac, GLOW[1:], sx, sy, sr, sr, lo=0 if mode == "fire" else 1, hi=4, grain=0.5,
               seed=seed + 8, emissive=True)
    for k in range(12):  # gill ribs radiating from the mouth
        a = k * math.pi / 6 + 0.2
        rib = line(W, H, [polar(sx, sy, a, 5), polar(sx, sy, a, sr - 1)], 1) & sac
        cv.put(rib, MEMBRANE[0] if mode == "walk" else GLOW[0])
    if mode == "walk":
        pores = sac & (_grain(sac.shape, seed + 2) > 0.8) & ~circle(W, H, sx, sy, 5)
        cv.put(pores, GLOW[2], emissive=True)  # a faint pulse
    rim = circle(W, H, sx, sy, 4.6)
    sphere(cv, rim, SANDSTONE, sx, sy, 4.6, 4.6, lo=2, seed=seed + 11)
    cv.put(circle(W, H, sx, sy, 2.6), OUTLINE)
    if mode == "walk":
        cv.put(circle(W, H, sx, sy, 1.2), GLOW[2], emissive=True)
    elif mode == "aim":
        cv.put(circle(W, H, sx, sy, 2.1), GLOW[3], emissive=True)
        cv.put(circle(W, H, sx - 0.5, sy - 0.5, 1.0), GLOW[5], emissive=True)
    else:  # fire: a cold white flash out of the mouth and a ring of vapour
        cv.put(circle(W, H, sx, sy, 3.8), GLOW[4], emissive=True)
        cv.put(circle(W, H, sx, sy, 2.3), GLOW[5], emissive=True)
        ring = circle(W, H, sx, sy, sr + 6) & ~circle(W, H, sx, sy, sr + 4.4) & (bayer(H, W) < 0.5)
        cv.put(ring, GLOW[3], emissive=True)
        for k in range(8):
            px(cv, [polar(sx, sy, k * math.pi / 4 + 0.3, sr + 8)], GLOW[4], emissive=True)
    return cv


def tripod_shell(ang, size=16):
    """Mortar round: a geode seed of fused sand around a glowing core, with a short cyan trail."""
    cv = Canvas(size, size)
    c = size / 2
    for d, r in ((4.4, 0.9), (5.3, 0.6)):
        x, y = polar(c - 0.5, c - 0.5, ang, -d)
        px(cv, [(x, y)], GLOW[2] if r > 0.8 else GLOW[1], emissive=True)
    cv.put(line(size, size, [(c - 0.5, c - 0.5), polar(c - 0.5, c - 0.5, ang, -4)], 2), GLOW[2], emissive=True)
    sphere(cv, circle(size, size, c - 0.5, c - 0.5, 3.4), GLOW[1:], c - 0.5, c - 0.5, 3.4, 3.4, lo=1, hi=4,
           grain=0.3, seed=3, emissive=True)
    # rock crust plates riding on the glob (dark, so it reads as a lump, not a bullet)
    for k, a in enumerate((ang + 2.2, ang + 3.6, ang + 0.9)):
        x, y = polar(c - 0.5, c - 0.5, a, 2.6)
        px(cv, [(x, y)], ROCK[2] if k else ROCK[3])
    px(cv, [(c - 1.5, c - 1.5)], GLOW[5], emissive=True)
    outline(cv, GLOW[0])
    return cv


TELEGRAPH_FRAME = 48
TELEGRAPH_FRAMES = 6


def tripod_telegraph(i, n=TELEGRAPH_FRAMES, size=TELEGRAPH_FRAME):
    """Ground marker where a mortar round lands: a dithered cyan ring with four ticks that fills in
    as the round falls (frame 0 = just fired, frame n-1 = impact next)."""
    cv = Canvas(size, size)
    c = size / 2 - 0.5
    t = i / (n - 1)
    R = size / 2 - 3
    ring = circle(size, size, c, c, R) & ~circle(size, size, c, c, R - 1.6)
    cv.put(ring, GLOW[3] if i % 2 == 0 else GLOW[2], emissive=True)
    outer = circle(size, size, c, c, R + 1.2) & ~circle(size, size, c, c, R) & (bayer(size, size) < 0.5)
    cv.put(outer, GLOW[1], emissive=True)
    for k in range(4):  # ticks pointing in, the crosshair of the hive's gunner
        a = k * math.pi / 2 + math.pi / 4
        cv.put(line(size, size, [polar(c, c, a, R - 1), polar(c, c, a, R - 5)], 1), GLOW[4], emissive=True)
    # inner fill: an ordered-dither disc closing in from the rim
    inner = circle(size, size, c, c, R - 2) & ~circle(size, size, c, c, (R - 2) * (1 - t))
    cv.put(inner & (bayer(size, size) < 0.18 + 0.32 * t), GLOW[2], emissive=True)
    cv.put(circle(size, size, c, c, 1.2), GLOW[4 if i < n - 1 else 5], emissive=True)
    cv.a[cv.a > 0] = 0.55 + 0.4 * t
    return cv


# ---------------------------------------------------------------- 2. Shard Colossus (boss) + Shard

COLOSSUS_SIZE = 112
COLOSSUS_FRAME = 128
COLOSSUS_ROWS = ("walk0", "walk1", "walk2", "walk3", "windup0", "windup1", "hurt")


def _crystal_fist(cv, x, y, a, s, seed, charge):
    """A club of salt and glass blades (charge 0..2 lights it from inside); a points where it swings."""
    rng = np.random.default_rng(seed)
    W, H = cv.w, cv.h
    core = blob(W, H, x, y, 5.0 * s, 4.6 * s, 0.3, seed, 2)
    sphere(cv, core, STONE, x, y, 5 * s, 4.6 * s, lo=1, seed=seed)
    blades = sorted([(a + rng.uniform(-1.1, 1.1), rng.uniform(7, 10.5) * s) for _ in range(5)],
                    key=lambda b: -math.cos(b[0]))  # far blades first
    for k, (b, ln) in enumerate(blades):
        p0 = polar(x, y, b, 1.5 * s)
        p1 = polar(x, y, b, ln)
        if charge >= 2:
            shard(cv, p0, p1, 4 * s, GLOW[1:], 2, emissive=True)
        else:
            shard(cv, p0, p1, 4 * s, SALT if k % 2 else ICE, 2)
            if charge == 1:
                cv.put(line(W, H, [p0, polar(x, y, b, ln * 0.6)], 1), GLOW[3], emissive=True)


def shard_colossus(row="walk0", seed=57):
    """Crystal giant of fused glass and salt seen from above, knuckle-walking: a stained-glass back with a
    spine of salt crystals, crystal pauldrons, two huge crystal clubs on the ground in front. Walk swings
    the clubs against the feet; windup pulls them back and lights the seams (windup1 = about to fire the
    shard ring / charge); hurt recoils with the clubs up and fresh fractures."""
    W = H = COLOSSUS_SIZE
    cv = Canvas(W, H)
    cx, cy = 56.0, 60.0
    mode = "walk" if row.startswith("walk") else ("windup" if row.startswith("windup") else "hurt")
    ph = int(row[-1]) if mode != "hurt" else 0
    charge = 0 if mode != "windup" else ph + 1
    swing = math.sin(ph * math.pi / 2) if mode == "walk" else 0.0
    if mode == "hurt":
        cy += 3
    rng = np.random.default_rng(seed + 20)

    # feet behind the bulk
    for s in (-1, 1):
        fx, fy = cx + s * 14, cy + 20 + s * swing * 6
        foot = blob(W, H, fx, fy, 7, 7.5, 0.25, seed + 3 + s, 2)
        sphere(cv, foot, STONE, fx, fy, 7, 7.5, seed=seed + s)
        for d in (-3, 0, 3):
            px(cv, [(fx + d, fy + 7)], OUTLINE)
    # arms: shoulder -> elbow -> club
    for i, s in enumerate((-1, 1)):
        sx, sy = cx + s * 20, cy - 8
        if mode == "walk":
            elbow = (cx + s * 33, cy - 6 - s * swing * 4)
            fist = (cx + s * 31, cy - 25 - s * swing * 9)
        elif mode == "windup":
            k = 0.5 + 0.5 * ph
            elbow = (cx + s * (33 + 2 * k), cy - 2 + 2 * k)
            fist = (cx + s * (40 + 2 * k), cy + 2 + 12 * k)
        else:  # hurt: clubs thrown up in front of the head
            elbow = (cx + s * 27, cy - 18)
            fist = (cx + s * 12, cy - 30)
        upper = limb(cv, (sx, sy), elbow, 11, 9, STONE, base=3, seed=seed + 5 + i, noise=0.4)
        fore = limb(cv, elbow, fist, 9, 8, STONE, base=3, seed=seed + 7 + i, noise=0.4)
        # salt crust and a few glass panes on the forearm
        crust = (upper | fore) & (_grain(upper.shape, seed + i) > 0.78)
        cv.put(crust, SALT[3])
        cv.put(crust & ~shift(crust, 1, 1), SALT[4])
        fa = math.atan2(fist[0] - elbow[0], -(fist[1] - elbow[1]))
        mid = ((elbow[0] + fist[0]) / 2, (elbow[1] + fist[1]) / 2)
        shard(cv, mid, polar(mid[0], mid[1], fa + s * 1.9, 7), 3.5, GLOW[1:] if charge == 2 else ICE, 2,
              emissive=charge == 2)
        sphere(cv, circle(W, H, elbow[0], elbow[1], 5), STONE, elbow[0], elbow[1], 5, 5, lo=2, seed=seed + i)
        _crystal_fist(cv, fist[0], fist[1], fa, 1.2, seed + 11 + i, charge)

    # back: a dome of stained glass with dark leading
    torso = blob(W, H, cx, cy, 24, 20, 0.12, seed, 5)
    glow_lead = {1: 0.35, 2: 0.9}.get(charge, 0.3 if mode == "hurt" else 0.0)
    stained_glass(cv, torso, 10, seed + 2, cx, cy - 3, 25, 21, glow_lead=glow_lead, glints=0.7)
    cv.put(torso & ~shift(torso, -1, -1) & ~shift(torso, 1, 1), LEAD)
    if charge == 2:  # the core shows through the glass
        core = blob(W, H, cx, cy + 1, 8, 7, 0.3, seed + 4, 2) & torso
        sphere(cv, core, GLOW[2:], cx, cy + 1, 8, 7, lo=0, hi=3, seed=seed + 4, emissive=True)
    # pauldrons: clusters of salt blades on the shoulders, pointing out and back
    for s in (-1, 1):
        for k, (a, ln, w) in enumerate([(2.0, 14, 6), (2.6, 10, 5)]):
            p0 = (cx + s * 17, cy - 8)
            p1 = polar(p0[0], p0[1], s * a, ln)
            if mode == "hurt" and s > 0 and k == 0:
                p1 = polar(p0[0], p0[1], s * a, 6)  # snapped off
            if charge == 2 or (charge == 1 and k == 0):
                shard(cv, p0, p1, w, GLOW[1:], 2, emissive=True)
            else:
                shard(cv, p0, p1, w, SALT if k != 1 else ICE, 2)
    # spine: big standing salt crystals down the back
    spine = [(cx, cy - 6, 4.2), (cx + 1, cy + 4, 5.2), (cx - 1, cy + 13, 3.8), (cx + 9, cy + 10, 2.8)]
    for k, (x, y, r) in enumerate(spine):
        if mode == "hurt" and k in (2, 3):
            cv.put(circle(W, H, x, y, r * 0.7), LEAD)
            facet_tip(cv, x, y, r * 0.45, SALT, 1, rot=0.5)
            continue
        if charge == 2 or (charge == 1 and k < 2):
            facet_tip(cv, x, y, r, GLOW[1:], 2, rot=rng.uniform(0, 1), emissive=True)
        else:
            facet_tip(cv, x, y, r, SALT if k % 2 == 0 else ICE, 2, rot=rng.uniform(0, 1))
        cv.put(circle(W, H, x, y, r + 0.8) & ~circle(W, H, x, y, r) & torso & ~shift(circle(W, H, x, y, r), 1, 1),
               LEAD)
    # head: a small glass dome low between the shoulders, a salt brow and an eye slit
    hx, hy = cx, cy - 22
    head = blob(W, H, hx, hy, 7, 5.5, 0.12, seed + 30, 2)
    stained_glass(cv, head, 3, seed + 31, hx, hy, 7, 6, glints=1.0)
    brow = line(W, H, [(hx - 6, hy - 2), (hx, hy - 4), (hx + 6, hy - 2)], 2) & head
    cv.put(brow, SALT[3])
    cv.put(line(W, H, [(hx - 4, hy), (hx + 4, hy)], 1), OUTLINE)
    eye = GLOW[5] if charge else GLOW[4]
    px(cv, [(hx - 3, hy), (hx - 2, hy), (hx + 1, hy), (hx + 2, hy)], eye, emissive=True)
    if mode == "hurt":  # fresh fractures leaking light, a chunk knocked out
        fr = cracks(W, H, cx + 6, cy - 2, 4, 12, seed + 40, spread=4) & torso
        cv.put(fr, SALT[4])
        cv.put(fr & (_grain(fr.shape, seed) > 0.5), GLOW[4], emissive=True)
        chip = blob(W, H, cx + 17, cy + 6, 5, 4, 0.4, seed + 41, 2) & torso
        cv.put(chip, ROCK[0])
        cv.put(chip & shift(chip, -1, -1) & ~shift(chip, 1, 1), GLOW[2], emissive=True)
        for p in [(cx + 26, cy - 4), (cx + 29, cy + 1), (cx + 27, cy + 8), (cx + 31, cy - 8)]:
            shard(cv, p, (p[0] + 2, p[1] - 2), 2, SALT, 2, ridge=False)  # flying splinters
    return cv


SHARD_SIZE = 40
SHARD_FRAME = 48
SHARD_ROWS = ("walk0", "walk1")


def shard_minion(row="walk0", seed=71):
    """A splinter of the Colossus: a glass crab with salt crystals on its back and blade pincers."""
    W = H = SHARD_SIZE
    cv = Canvas(W, H)
    cx, cy = 20.0, 22.0
    ph = int(row[-1])
    for k, a in enumerate((0.95, 1.55, 2.15)):  # three legs a side, alternating step
        for s in (-1, 1):
            off = 0.18 if (k + ph + (s > 0)) % 2 else -0.18
            ang = s * (a + off)
            r0 = polar(cx, cy, ang, 6)
            kn = polar(cx, cy, ang, 11)
            ft = polar(kn[0], kn[1], ang + s * 0.7, 6)
            cv.put(line(W, H, [r0, kn], 2), STONE[2])
            cv.put(line(W, H, [kn, ft], 1), ICE[1])
            px(cv, [kn], SALT[3])
    for s in (-1, 1):  # blade pincers
        base = (cx + s * 4.5, cy - 7)
        a = s * (0.3 + 0.15 * ph)
        tip = polar(base[0], base[1], a, 8)
        limb(cv, base, tip, 3, 2.5, STONE, base=3, seed=seed + s)
        shard(cv, tip, polar(tip[0], tip[1], a - s * 0.35, 6), 3.4, SALT, 2)
        shard(cv, tip, polar(tip[0], tip[1], a + s * 0.9, 4), 2.6, ICE, 2, ridge=False)
    body = blob(W, H, cx, cy, 9, 8, 0.15, seed, 3)
    stained_glass(cv, body, 5, seed + 1, cx, cy - 1, 10, 9, glints=0.9)
    cv.put(body & ~shift(body, -1, -1) & ~shift(body, 1, 1), LEAD)
    facet_tip(cv, cx - 3, cy + 2.5, 3.4, SALT, 2, rot=0.2)
    facet_tip(cv, cx + 3.5, cy + 3, 2.8, ICE, 2, rot=0.6)
    facet_tip(cv, cx + 0.5, cy - 2.5, 2.4, SALT, 2, rot=0.9)
    hx, hy = cx, cy - 8
    paint(cv, ellipse(W, H, hx - 4, hy - 2, hx + 4, hy + 2), STONE, base=3)
    px(cv, [(hx - 2, hy - 1), (hx + 2, hy - 1)], GLOW[4], emissive=True)
    return cv


def crystal_shard(ang, size=16):
    """The Colossus' projectile: a cold cyan blade with a glittering wake. Never warm."""
    cv = Canvas(size, size)
    c = size / 2 - 0.5
    tip = polar(c, c, ang, 4.5)
    tail = polar(c, c, ang, -4.5)
    for d, col in ((-5.0, GLOW[2]), (-5.8, GLOW[1])):
        x, y = polar(c, c, ang + 0.3 * (1 if d < -5.4 else -1), d)
        px(cv, [(x + 0.5, y + 0.5)], col, emissive=True)
    shard(cv, tail, tip, 3.6, GLOW[1:], 2, emissive=True)
    cv.put(line(size, size, [polar(c, c, ang, -1.5), polar(c, c, ang, 3.0)], 1), GLOW[5], emissive=True)
    outline(cv, GLOW[0])
    return cv


# ---------------------------------------------------------------- 3. Glass Wings (flyer)

WING_SIZE = 26
WING_FRAME = 36
WING_ROWS = ("flap0", "flap1", "flap2", "flap3")
_WING_SPAN = (1.0, 0.72, 0.42, 0.72)


def glass_wings(row="flap0", seed=13):
    """Small dragonfly with four stained-glass wings of fused sand (cyan vein = alive and flying).
    Flap frames foreshorten the wings: 0 spread, 1 half, 2 nearly edge-on, 3 half (loop 0-1-2-3)."""
    W = H = WING_SIZE
    cv = Canvas(W, H)
    cx = W / 2 - 0.5
    k = int(row[-1])
    span = _WING_SPAN[k]
    fwd = (0.0, -1.0, -2.0, -1.0)[k]  # wings sweep forward a little on the down stroke
    wings = [  # root, leading tip, trailing tip, back root; x = distance out from the body axis
        ((1.0, 8.0), (12.5, 4.5 + fwd), (12.0, 9.0 + fwd * 0.5), (1.0, 11.0)),
        ((1.0, 11.5), (12.0, 13.0 + fwd * 0.5), (9.5, 18.5), (1.0, 14.5)),
    ]
    tints = [([SAND[2], SAND[3], SAND[4], SAND[5]], 2), (GLASS, 1), ([CANYON[3], CANYON[4], CANYON[5], BONE[3]], 2),
             ([SALT[1], SALT[2], SALT[3], SALT[4]], 2)]
    for wi, pts in enumerate(wings):
        for s in (-1, 1):
            p = [(cx + s * x * (span if i in (1, 2) else 1), y) for i, (x, y) in enumerate(pts)]
            m = poly(W, H, p)
            # two panes per wing split by a cross vein, each its own tint
            a0 = ((p[0][0] + p[3][0]) / 2, (p[0][1] + p[3][1]) / 2)
            a1 = ((p[1][0] + p[2][0]) / 2, (p[1][1] + p[2][1]) / 2)
            split = poly(W, H, [p[0], p[1], a1, a0])
            for j, pane in enumerate((m & split, m & ~split)):
                ramp, base = tints[(wi * 2 + j + (s > 0)) % len(tints)]
                sphere(cv, pane, ramp, cx + s * 5 * span, 8, 7 * span + 2, 7, lo=max(0, base - 1),
                       hi=len(ramp) - 1, grain=0.6, seed=seed + wi * 3 + j + s)
            cv.put(line(W, H, [a0, a1], 1) & m, LEAD)
            edge = m & ~(shift(m, 1, 0) & shift(m, -1, 0) & shift(m, 0, 1) & shift(m, 0, -1))
            cv.put(edge, CHITIN[1])
            cv.put(line(W, H, [p[0], p[1]], 1) & m, GLOW[3], emissive=True)  # the living leading vein
            if span > 0.6:
                px(cv, [(cx + s * 7 * span, (p[1][1] + p[2][1]) / 2 + 1)], SALT[4])  # glint
    # body: head, thorax, a long segmented tail
    paint(cv, ellipse(W, H, cx - 1.2, 11, cx + 1.2, 25), CHITIN, base=3, noise=0.3, seed=seed)
    for y in (15, 18, 21):
        px(cv, [(cx - 1, y), (cx + 1, y)], CHITIN[1])
    paint(cv, ellipse(W, H, cx - 2.5, 6, cx + 2.5, 13), SANDSTONE, base=4, noise=0.2, seed=seed + 1)
    paint(cv, ellipse(W, H, cx - 2.5, 2, cx + 2.5, 7), CHITIN, base=3)
    px(cv, [(cx - 1.5, 3), (cx + 1.5, 3)], GLOW[4], emissive=True)
    return cv


def soft_shadow(frame):
    """Drop shadow for a flyer: its silhouette, softened by one dithered pixel, wings lighter than the
    body. Colour = palette SHADOW, the alpha carries the shape; the game draws it offset on the ground."""
    from scene import box_blur
    from palette import SHADOW
    sol = frame.solid().astype(np.float32)
    bright = frame.rgb.mean(axis=2) / 255.0
    dens = np.where(frame.solid(), np.where(bright > 0.55, 0.7, 1.0), 0.0)  # pale glass lets light through
    b = box_blur(dens.astype(np.float64), 1)
    lvl = np.floor(np.clip(b, 0, 1) * 3 + bayer(*b.shape) * 0.999) / 3
    out = Canvas(frame.w, frame.h)
    out.rgb[:] = _rgb(SHADOW)
    out.a = (lvl * 0.5).astype(np.float32)
    out.a[sol > 0] = np.maximum(out.a[sol > 0], 0.33)
    return out


# ---------------------------------------------------------------- 4. Brood Carrier

BROOD_SIZE = 40
BROOD_FRAME = 48
BROOD_ROWS = ("pulse0", "pulse1", "pulse2", "burst")


def _baby_mite(cv, x, y, a, col, eye=None, emissive=False):
    W, H = cv.w, cv.h
    for s in (-1, 1):
        for d in (-0.8, 0.8):
            b = polar(x, y, a, d)
            cv.put(line(W, H, [b, polar(b[0], b[1], a + s * 1.6, 2.4)], 1), col)
    cv.put(line(W, H, [polar(x, y, a, -1.8), polar(x, y, a, 1.8)], 2), col)
    if eye:
        e1 = polar(x, y, a - 0.5, 1.6)
        e2 = polar(x, y, a + 0.5, 1.6)
        px(cv, [e1, e2], eye, emissive=emissive)


def brood_carrier(row="pulse0", seed=83):
    """Slow sac-beetle: small armoured front, a bloated milky belly with curled mites inside.
    pulse0..2 swell the belly and light it from within (loop 0-1-2-1); burst = torn open, mites spill."""
    W = H = BROOD_SIZE
    cv = Canvas(W, H)
    cx = W / 2 - 0.5
    burst = row == "burst"
    k = 0 if burst else int(row[-1])
    sw = (1.0, 1.05, 1.1)[k] if not burst else 1.0
    rng = np.random.default_rng(seed)
    for y, dx in ((8, 7), (11, 8), (14, 8)):  # stubby legs under the front half
        for s in (-1, 1):
            cv.put(line(W, H, [(cx + s * 3, y), (cx + s * dx, y - 1), (cx + s * (dx + 2), y + 2)], 1), CHITIN[1])
    bcx, bcy, rx, ry = cx, 25.0, 13.0 * sw, 12.0 * sw
    belly = blob(W, H, bcx, bcy, rx, ry, 0.08, seed, 4)
    if not burst:
        inner = blob(W, H, bcx, bcy + 0.5, rx - 2.4, ry - 2.4, 0.12, seed + 1, 3)
        sphere(cv, belly, MEMBRANE, bcx, bcy, rx, ry, lo=1, hi=4, grain=0.5, seed=seed + 2)
        if k == 0:
            sphere(cv, inner, MURK + [MEMBRANE[1]], bcx, bcy, rx, ry, lo=0, hi=3, grain=0.6, seed=seed + 3)
        else:  # lit from within: the brood wakes up
            sphere(cv, inner, GLOW[0:3] if k == 1 else GLOW[1:4], bcx, bcy + 1, rx - 2, ry - 2, lo=0,
                   hi=2, grain=0.5, seed=seed + 3, emissive=True)
        veins = cracks(W, H, bcx, bcy, 5, 9, seed + 5, spread=7) & belly & ~inner
        cv.put(veins, MEMBRANE[0])
        # curled mites inside: dark silhouettes with awake eyes
        for j, (a, r) in enumerate([(0.5, 5.8), (2.1, 6.0), (3.7, 5.6), (5.3, 6.2)]):
            mx, my = polar(bcx, bcy + 1, a, r * sw)
            _baby_mite(cv, mx, my, a + 2.0 + j, CHITIN[0], eye=GLOW[4] if k else GLOW[2], emissive=True)
        # milky veil: the skin's top-left catches the light
        veil = belly & ~shift(belly, -2, -2)
        cv.put(veil & (_grain(belly.shape, seed + 4) > 0.3), MEMBRANE[4])
    else:
        # torn sac: ragged flaps peeled back, a bright pool of ichor, mites crawling out
        sphere(cv, belly, MEMBRANE, bcx, bcy, rx, ry, lo=0, hi=3, grain=0.8, seed=seed + 2)
        hole = blob(W, H, bcx, bcy + 1, rx - 3, ry - 3, 0.45, seed + 7, 2)
        sphere(cv, hole, GLOW[1:5], bcx, bcy + 1, rx - 3, ry - 3, lo=0, hi=3, grain=0.6, seed=seed + 8,
               emissive=True)
        for j in range(7):  # flaps
            a = j / 7 * 2 * math.pi + rng.uniform(-0.2, 0.2)
            p0 = polar(bcx, bcy + 1, a, rx - 4)
            p1 = polar(bcx, bcy + 1, a, rx + 1.5)
            cv.put(line(W, H, [p0, p1], 2) & ~hole, MEMBRANE[3])
            cv.put(line(W, H, [p0, p1], 1) & hole, MEMBRANE[1])
        for j in range(5):
            a, r = j / 5 * 2 * math.pi + 0.5, rng.uniform(5, 11)
            mx, my = polar(bcx, bcy + 1, a, r)
            _baby_mite(cv, mx, my, a + rng.uniform(-0.4, 0.4), CHITIN[1], eye=GLOW[4], emissive=True)
        splash = [polar(bcx, bcy, rng.uniform(0, 2 * math.pi), rng.uniform(rx, rx + 3)) for _ in range(8)]
        px(cv, splash, GLOW[3], emissive=True)
    # pronotum shield over the front of the belly, small head with mandibles
    shield = ellipse(W, H, cx - 8, 9, cx + 8, 18) & ~ellipse(W, H, cx - 12, 16, cx + 12, 26)
    sphere(cv, shield, CHITIN, cx, 12, 8, 5, lo=1, grain=0.6, seed=seed + 9)
    px(cv, [(cx - 4, 12), (cx + 3, 13), (cx - 1, 11)], CHITIN[5])
    paint(cv, ellipse(W, H, cx - 4, 3, cx + 4, 10), CHITIN, base=2)
    px(cv, [(cx - 3, 2), (cx + 3, 2), (cx - 2, 1), (cx + 2, 1)], CHITIN[0])
    px(cv, [(cx - 2, 5), (cx + 2, 5)], GLOW[4], emissive=True)
    return cv


# ---------------------------------------------------------------- 5. Shrieker (support)

SHRIEKER_SIZE = 32
SHRIEKER_FRAME = 40
SHRIEKER_ROWS = ("idle", "shriek")


def shrieker(row="idle", seed=97):
    """Support alien: a squat sandstone body carrying a fan of resonating salt-crystal pipes on its back
    (hollow ends point back). idle = dark pipe mouths; shriek = mouths lit, cyan sound rings behind it."""
    W = H = SHRIEKER_SIZE
    cv = Canvas(W, H)
    cx, cy = W / 2 - 0.5, 13.0
    on = row == "shriek"
    if on:  # sound rings leaving the pipes (dithered arcs behind the body)
        for r, dens in ((12.5, 0.75), (15.5, 0.45)):
            ring = circle(W, H, cx, cy + 4, r) & ~circle(W, H, cx, cy + 4, r - 1.3)
            ring &= ~(poly(W, H, [(cx, cy + 4), (-10, -12), (W + 10, -12)]))
            cv.put(ring & (bayer(H, W) < dens), GLOW[3], emissive=True)
    for y, dx in ((10, 6), (13, 7), (16, 6)):
        for s in (-1, 1):
            cv.put(line(W, H, [(cx + s * 3, y), (cx + s * dx, y - 2), (cx + s * (dx + 2), y + 1)], 1), CHITIN[1])
    pipes = [(math.pi, 14.0, 3.8), (math.pi - 0.62, 12.5, 3.4), (math.pi + 0.62, 12.5, 3.4),
             (math.pi - 1.2, 10.0, 3.0), (math.pi + 1.2, 10.0, 3.0)]
    ends = []
    for k, (a, ln, w) in sorted(enumerate(pipes), key=lambda kp: kp[1][1]):
        p0 = polar(cx, cy + 2, a, 2)
        p1 = polar(cx, cy + 2, a, ln)
        tube = limb(cv, p0, p1, w * 0.7, w, SALT, base=2, seed=seed + k, noise=0.2)
        cv.put(tube & ~(shift(tube, 1, 0) & shift(tube, -1, 0) & shift(tube, 0, 1) & shift(tube, 0, -1)), ROCK[2])
        cv.put(line(W, H, [p0, p1], 1) & tube & shift(tube, 1, 1) & shift(tube, -1, -1), SALT[4])
        ends.append((p1, w))
    body = blob(W, H, cx, cy, 5.5, 6.5, 0.12, seed, 3)
    sphere(cv, body, SANDSTONE, cx, cy, 6, 7, lo=0, grain=0.8, seed=seed)
    for (x, y), w in ends:  # the open mouths of the pipes
        m = circle(W, H, x, y, w * 0.42)
        cv.put(m, GLOW[3] if on else OUTLINE, emissive=on)
        if on:
            px(cv, [(x - 0.5, y - 0.5)], GLOW[5], emissive=True)
    paint(cv, ellipse(W, H, cx - 3.5, 3, cx + 3.5, 9), CHITIN, base=2, noise=0.2, seed=seed + 1)
    for s in (-1, 1):
        cv.put(line(W, H, [(cx + s * 2, 4), (cx + s * 4, 1), (cx + s * 5, 0)], 1), CHITIN[1])
    px(cv, [(cx - 1.5, 5), (cx + 1.5, 5)], GLOW[4], emissive=True)
    return cv


RING_FRAME = 64
RING_FRAMES = 6


def shrieker_ring(i, n=RING_FRAMES, size=RING_FRAME):
    """Buff pulse: a cyan ring expanding from the Shrieker and thinning out (frame 0 small, n-1 widest).
    Fully emissive: draw it with additive blending, scaled to the buff radius."""
    cv = Canvas(size, size)
    c = size / 2 - 0.5
    t = i / (n - 1)
    R = 6 + t * (size / 2 - 8)
    w = 2.6 - 1.2 * t
    ring = circle(size, size, c, c, R) & ~circle(size, size, c, c, R - w)
    dens = 0.95 - 0.6 * t
    cv.put(ring & (bayer(size, size) < dens), GLOW[3] if t < 0.6 else GLOW[2], emissive=True)
    inner = circle(size, size, c, c, R - w) & ~circle(size, size, c, c, R - w - 2)
    cv.put(inner & (bayer(size, size) < dens * 0.3), GLOW[2], emissive=True)
    rng = np.random.default_rng(i + 3)
    for _ in range(int(10 + 10 * t)):  # notes of the shriek: sparks riding the ring
        x, y = polar(c, c, rng.uniform(0, 2 * math.pi), R + rng.uniform(-1, 1))
        px(cv, [(x + 0.5, y + 0.5)], GLOW[4], emissive=True)
    cv.a[cv.a > 0] = 0.9 - 0.45 * t
    return cv


# ---------------------------------------------------------------- carcasses (bleached decals)

def bleach(cv, alpha=0.6):
    """Same treatment as decal_carcass: pale, flat, half transparent, no outline."""
    sol = cv.a > 0
    lum = cv.rgb[sol].mean(axis=1, keepdims=True)
    cv.rgb[sol] = cv.rgb[sol] * 0.35 + (lum * 0.5 + np.array([[150, 135, 115]]) * 0.5) * 0.65
    cv.a[sol] = cv.a[sol] * alpha
    cv.emit[:] = False
    return cv


def _ichor(cv, cx, cy, rx, ry, seed):
    paint(cv, blob(cv.w, cv.h, cx, cy, rx, ry, 0.5, seed, 2), GLOW[:2], base=0, light=False, alpha=0.85)


def carcass_tripod(seed=0, size=TRIPOD_FRAME):
    """Collapsed Tripod Queen: the mound cracked open, the sac burst, three legs broken and splayed."""
    W = H = size
    cv = Canvas(W, H)
    c = size / 2
    rng = np.random.default_rng(seed)
    _ichor(cv, c, c, 30, 25, seed)
    for i, a0 in enumerate((-0.95 + rng.uniform(-0.3, 0.3), 0.95 + rng.uniform(-0.3, 0.3), math.pi + rng.uniform(-0.4, 0.4))):
        root = polar(c, c, a0, 16)
        knee = polar(c, c, a0 + rng.uniform(-0.2, 0.2), 32)
        limb(cv, root, knee, 6, 5, SANDSTONE[:-1], base=2, seed=seed + i)
        a1 = a0 + rng.uniform(0.5, 1.2) * (1 if rng.random() < 0.5 else -1)   # broken, bent sideways
        k2 = polar(knee[0], knee[1], a1, 2.5)
        limb(cv, k2, polar(k2[0], k2[1], a1, 16), 4, 2, CHITIN, base=2, seed=seed + 10 + i)
    body = blob(W, H, c, c, 24, 21, 0.3, seed + 1, 4)
    sphere(cv, body, SANDSTONE, c, c, 25, 22, lo=0, grain=1.0, seed=seed + 2)
    cr = cracks(W, H, c, c, 7, 18, seed + 3, spread=5) & body
    cv.put(cr, CANYON[1])
    crater = blob(W, H, c + 1, c + 2, 8, 7, 0.45, seed + 4, 2)
    cv.put(crater, ROCK[0])
    for j in range(7):
        a = j / 7 * 2 * math.pi
        cv.put(line(W, H, [polar(c + 1, c + 2, a, 5), polar(c + 1, c + 2, a, 10)], 2), MEMBRANE[2])
    for _ in range(9):  # sandstone chunks
        x, y = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(24, 34))
        paint(cv, blob(W, H, x, y, 2.6, 2.1, 0.4, rng.integers(99), 1), SANDSTONE, base=3)
    return bleach(cv)


def carcass_colossus(seed=0, size=COLOSSUS_FRAME):
    """Shattered Colossus: a heap of glass panes, salt crystals and two broken clubs."""
    W = H = size
    cv = Canvas(W, H)
    c = size / 2
    rng = np.random.default_rng(seed)
    _ichor(cv, c, c, 26, 22, seed)
    torso = blob(W, H, c, c, 22, 17, 0.45, seed + 1, 3)
    stained_glass(cv, torso, 16, seed + 2, c, c, 22, 18)
    cv.put(cracks(W, H, c, c, 6, 16, seed + 3, spread=6) & torso, LEAD)
    for _ in range(18):  # scattered shards and panes
        a, r = rng.uniform(0, 2 * math.pi), rng.uniform(18, 46)
        p0 = polar(c, c, a, r)
        p1 = polar(p0[0], p0[1], rng.uniform(0, 2 * math.pi), rng.uniform(4, 9))
        shard(cv, p0, p1, rng.uniform(2.5, 4.5), SALT if rng.random() < 0.5 else CRYSTAL[1:], 2)
    for s in (-1, 1):
        x, y = c + s * rng.uniform(28, 36), c + rng.uniform(-14, 14)
        _crystal_fist(cv, x, y, rng.uniform(0, 6.3), 0.9, seed + 5 + s, 0)
    for k in range(5):
        x, y = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(4, 14))
        facet_tip(cv, x, y, rng.uniform(2.5, 4.0), SALT, 2, rot=rng.uniform(0, 1))
    return bleach(cv)


def carcass_shard(seed=0, size=SHARD_FRAME):
    W = H = size
    cv = Canvas(W, H)
    c = size / 2
    rng = np.random.default_rng(seed)
    _ichor(cv, c, c, 9, 7, seed)
    body = blob(W, H, c, c, 8, 6.5, 0.4, seed + 1, 2)
    stained_glass(cv, body, 5, seed + 2, c, c, 8, 7)
    for _ in range(7):
        p0 = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(7, 15))
        p1 = polar(p0[0], p0[1], rng.uniform(0, 2 * math.pi), rng.uniform(3, 6))
        shard(cv, p0, p1, 2.6, SALT, 2, ridge=False)
    for _ in range(5):  # snapped legs
        p0 = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(6, 11))
        cv.put(line(W, H, [p0, polar(p0[0], p0[1], rng.uniform(0, 6.3), 5)], 1), CRYSTAL[2])
    return bleach(cv)


def carcass_wings(seed=0, size=WING_FRAME):
    W = H = size
    cv = Canvas(W, H)
    c = size / 2
    rng = np.random.default_rng(seed)
    _ichor(cv, c, c, 4, 3, seed)
    a = rng.uniform(0, 2 * math.pi)
    body = line(W, H, [polar(c, c, a, -7), polar(c, c, a, 6)], 2)
    paint(cv, body, CHITIN, base=2, seed=seed)
    for _ in range(4):  # broken wing panes lying around
        p = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(3, 10))
        q = [polar(p[0], p[1], rng.uniform(0, 6.3), rng.uniform(2, 5)) for _ in range(3)]
        m = poly(W, H, [p] + q)
        paint(cv, m, GLASS if rng.random() < 0.5 else SAND[2:], base=2, seed=seed + 1)
        edge = m & ~(shift(m, 1, 0) & shift(m, -1, 0) & shift(m, 0, 1) & shift(m, 0, -1))
        cv.put(edge, CHITIN[1])
    return bleach(cv)


def carcass_brood(seed=0, size=BROOD_FRAME):
    W = H = size
    cv = Canvas(W, H)
    c = size / 2
    rng = np.random.default_rng(seed)
    _ichor(cv, c, c + 2, 15, 13, seed)
    sac = blob(W, H, c, c + 3, 12, 11, 0.45, seed + 1, 2)
    paint(cv, sac, MEMBRANE, base=2, light=False, noise=0.5, seed=seed)
    cv.put(blob(W, H, c, c + 3, 8, 7, 0.5, seed + 2, 2), DEAD_GOO[1])
    for j in range(8):  # flaps
        a = j / 8 * 2 * math.pi + rng.uniform(-0.2, 0.2)
        cv.put(line(W, H, [polar(c, c + 3, a, 7), polar(c, c + 3, a, 13 + rng.uniform(0, 3))], 2), MEMBRANE[3])
    paint(cv, ellipse(W, H, c - 6, c - 12, c + 6, c - 4), CHITIN, base=2, noise=0.3, seed=seed + 3)
    for (p, q) in [((c - 5, c - 8), (c - 9, c - 11)), ((c + 5, c - 8), (c + 9, c - 5)), ((c - 5, c - 6), (c - 9, c - 2))]:
        cv.put(line(W, H, [p, q], 1), CHITIN[0])
    return bleach(cv)


def carcass_shrieker(seed=0, size=SHRIEKER_FRAME):
    W = H = size
    cv = Canvas(W, H)
    c = size / 2
    rng = np.random.default_rng(seed)
    _ichor(cv, c, c, 9, 8, seed)
    body = blob(W, H, c, c, 7, 7.5, 0.4, seed + 1, 2)
    sphere(cv, body, SANDSTONE, c, c, 7, 8, grain=1.0, seed=seed)
    for k in range(4):  # cracked pipes, some knocked over
        x, y = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(1, 11))
        facet_tip(cv, x, y, rng.uniform(1.8, 2.8), SALT, 2, rot=rng.uniform(0, 1))
        cv.put(circle(W, H, x, y, 1.0), ROCK[1])
    for s in (-1, 1):
        cv.put(line(W, H, [(c + s * 5, c - 2), (c + s * 10, c - 5)], 1), CHITIN[0])
        cv.put(line(W, H, [(c + s * 5, c + 3), (c + s * 9, c + 7)], 1), CHITIN[0])
    return bleach(cv)
