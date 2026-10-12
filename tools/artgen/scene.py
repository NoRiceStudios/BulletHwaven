"""Mock-up screenshot: a late-game war rig in the Dune Sea vs. a mixed horde (640x360 native)."""

import math

import numpy as np

from palette import FIRE, GLOW, OUTLINE, PLAYERS, SAND, SMOKE, UI_PLATE, UI_TEXT
from pixel import (Canvas, angle_to, bayer, blob, cast_shadow, circle, line, paint, paste, pixels,
                   polar, poly, rect, rgb, text, text_width, value_noise)
from sprites import (boulder_back, buggy, dune_worm, glass_wing, hull_plate, mite_carcass, ribcage,
                     rock_cluster, sand_mite, scrap_bit, spitter, war_rig_cab, war_rig_trailer)
from terrain import dune_sea

W, H = 640, 360


# ---------------------------------------------------------------- helpers

def box_blur(a, r):
    def blur1(x, axis):
        pad = [(0, 0)] * x.ndim
        pad[axis] = (r + 1, r)
        c = np.cumsum(np.pad(x, pad), axis=axis)
        n = x.shape[axis]
        return (np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
                - np.take(c, np.arange(n), axis=axis)) / (2 * r + 1)
    return blur1(blur1(a, 0), 1)


def bloom(rgb_img, emit, radius, strength, steps=4, gain=2.2):
    """Banded, dithered glow spilling from emissive pixels."""
    e = rgb_img * emit[..., None]
    b = box_blur(box_blur(e, radius), radius)
    lum = b.max(axis=2)
    level = np.floor(np.clip(lum / 255 * gain, 0, 1) * steps + bayer(*lum.shape) * 0.999) / steps
    hue = b / np.maximum(lum, 1e-3)[..., None]
    return rgb_img + hue * 255 * (level * strength)[..., None]


def facing_rot(sprite, ang):
    """Sprites face north; rotate to the nearest of 4 directions."""
    k = int(round(ang / (math.pi / 2))) % 4
    return sprite.rot90(-k)


def dithered_circle(cv, cx, cy, r, color, density, seed=0):
    grain = np.random.default_rng(seed).random((cv.h, cv.w))
    m = circle(cv.w, cv.h, cx, cy, r) & (grain < density)
    cv.put(m, color)


class Scene:
    def __init__(self, seed=4):
        self.cv = Canvas(W, H)
        self.cv.rgb[:] = dune_sea(W, H, seed)
        self.cv.a[:] = 1
        self.lights = []   # (x, y, radius, colour, intensity) for the night pass
        self.cones = []    # headlight cones (apex, angle, length, half-angle)
        self.rng = np.random.default_rng(seed)

    def sprite(self, spr, x, y, shadow=(2, 3), strength=0.45):
        if shadow:
            cast_shadow(self.cv, spr, x, y, *shadow, strength=strength)
        paste(self.cv, spr, x, y)

    # ground marks ---------------------------------------------------
    def track(self, pts, width=4, depth=0.86):
        """Tyre ruts: a soft trough with irregular, clumpy tread marks (no repeating pattern)."""
        m = line(W, H, pts, width)
        clumps = value_noise(H, W, 2, len(pts)) > 0.55
        self.cv.rgb[m] *= depth
        self.cv.rgb[m & clumps] *= 0.9
        rim = line(W, H, pts, width + 2) & ~m & (self.rng.random((H, W)) < 0.5)
        self.cv.rgb[rim] = np.minimum(self.cv.rgb[rim] * 1.08, 255)  # sand pushed up at the edges

    def goo(self, x, y, r, seed):
        m = blob(W, H, x, y, r, r * 0.8, 0.5, seed, 2)
        paint(self.cv, m, GLOW[:2], base=0, light=False, noise=0.3, seed=seed)
        for i in range(4):
            a = self.rng.uniform(0, 2 * math.pi)
            px, py = polar(x, y, a, r + self.rng.uniform(1, 4))
            self.cv.put(pixels(W, H, [(round(px), round(py))]), GLOW[1])

    def scorch(self, x, y, r, seed):
        m = blob(W, H, x, y, r, r * 0.85, 0.45, seed, 2)
        self.cv.rgb[m] *= 0.55
        self.cv.rgb[m & (bayer(H, W) < 0.4)] *= 0.7

    def dust(self, x, y, r, density=0.55):
        dithered_circle(self.cv, x, y, r, SAND[5], density, int(x))
        dithered_circle(self.cv, x - 1, y - 1, r * 0.6, SAND[5], min(1, density + 0.25), int(y))

    # effects ----------------------------------------------------------
    def tracer(self, x0, y0, x1, y1, spacing=17, length=5, width=1, phase=0.0):
        d = math.hypot(x1 - x0, y1 - y0)
        ux, uy = (x1 - x0) / d, (y1 - y0) / d
        t = 8 + phase * spacing
        while t < d - 2:
            hx, hy = x0 + ux * t, y0 + uy * t
            tx, ty = hx - ux * length, hy - uy * length
            self.cv.put(line(W, H, [(tx, ty), (hx, hy)], width), FIRE[4], emissive=True)
            self.cv.put(line(W, H, [(hx - ux * 2, hy - uy * 2), (hx, hy)], width), FIRE[6], emissive=True)
            self.lights.append((hx, hy, 10, FIRE[4], 0.5))
            t += spacing

    def muzzle(self, x, y, ang, size=3):
        pts = [polar(x, y, ang, i) for i in range(size + 1)]
        perp = [polar(x, y, ang + s * math.pi / 2, 1.2) for s in (-1, 1)]
        self.cv.put(line(W, H, pts, 2), FIRE[5], emissive=True)
        self.cv.put(pixels(W, H, [(round(px), round(py)) for px, py in perp]), FIRE[4], emissive=True)
        self.cv.put(pixels(W, H, [(round(x), round(y))]), FIRE[6], emissive=True)
        self.lights.append((x, y, 34, FIRE[4], 1.0))

    def sparks(self, x, y, n=5, color=FIRE[5]):
        pts = [(round(x + self.rng.normal(0, 2.5)), round(y + self.rng.normal(0, 2.5))) for _ in range(n)]
        self.cv.put(pixels(W, H, pts), color, emissive=True)

    def explosion(self, x, y, r, seed):
        self.scorch(x + 2, y + 3, r * 1.2, seed)
        smoke = blob(W, H, x + 2, y - 2, r * 1.25, r * 1.1, 0.5, seed, 2)
        paint(self.cv, smoke, SMOKE, base=2, noise=0.4, seed=seed)
        paint(self.cv, blob(W, H, x, y, r * 0.95, r * 0.85, 0.45, seed + 1, 2), FIRE[1:5], base=2,
              noise=0.4, seed=seed, emissive=True)
        paint(self.cv, blob(W, H, x - 1, y - 1, r * 0.55, r * 0.5, 0.4, seed + 2, 2), FIRE[4:], base=1,
              light=False, emissive=True)
        for _ in range(14):
            a = self.rng.uniform(0, 2 * math.pi)
            px, py = polar(x, y, a, self.rng.uniform(r * 1.1, r * 2.0))
            col = FIRE[5] if self.rng.random() < 0.6 else OUTLINE
            self.cv.put(pixels(W, H, [(round(px), round(py))]), col, emissive=col != OUTLINE)
        self.lights.append((x, y, r * 7, FIRE[3], 1.2))

    def acid(self, x0, y0, x1, y1, ts=(0.35, 0.6, 0.85)):
        ang = math.atan2(y1 - y0, x1 - x0)
        for t in ts:
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            for k in range(1, 4):  # dripping trail
                tx, ty = x - math.cos(ang) * k * 2.2, y - math.sin(ang) * k * 2.2 + k * 0.4
                self.cv.put(pixels(W, H, [(round(tx), round(ty))]), GLOW[2 if k < 3 else 1], emissive=True)
            paint(self.cv, circle(W, H, x, y, 1.8), GLOW[2:], base=2, emissive=True)
            self.cv.put(pixels(W, H, [(round(x - 0.5), round(y - 0.5))]), GLOW[5], emissive=True)
            self.lights.append((x, y, 16, GLOW[3], 0.7))


# ---------------------------------------------------------------- composition

def build(seed=4):
    sc = Scene(seed)
    rng = sc.rng
    cv = sc.cv

    rig_x, cab_y = 296, 118
    trailer_y = cab_y + 70
    rig_cx, rig_cy = rig_x + 24, cab_y + 75

    # --- old tracks & props
    sc.track([(0, 330), (120, 300), (260, 318), (400, 352)], 3, depth=0.93)  # old, half blown over
    sc.track([(0, 337), (120, 307), (260, 325), (400, 359)], 3, depth=0.93)
    sc.sprite(hull_plate(1), -14, 70, shadow=(3, 4))
    sc.sprite(ribcage(2), 4, 168, shadow=(2, 3), strength=0.35)
    for (x, y, s, sd) in [(250, 8, 1.0, 3), (575, 12, 1.2, 8), (40, 292, 1.3, 11), (600, 300, 0.9, 5)]:
        sc.sprite(rock_cluster(sd, s), x, y, shadow=(3, 4))

    # --- tracks behind the rig, swerving in from the bottom
    for wx in (rig_x + 3, rig_x + 44):
        pts = [(wx + 10 * math.sin((y - 280) / 38.0) * ((y - 280) / 80.0), y) for y in range(trailer_y + 80, H + 4, 4)]
        sc.track(pts, 5)

    # --- dead aliens around the rig (it has been fighting for a while)
    for i in range(16):
        a = rng.uniform(0, 2 * math.pi)
        x, y = polar(rig_cx, rig_cy, a, rng.uniform(62, 120))
        sc.goo(x, y, rng.uniform(2.5, 5), seed=i)
        if rng.random() < 0.7:
            m = mite_carcass(i)
            paste(cv, m, x - 7, y - 6)
    for i in range(10):
        x, y = polar(rig_cx, rig_cy, rng.uniform(0, 2 * math.pi), rng.uniform(55, 140))
        paste(cv, scrap_bit(i), x, y)

    # --- explosion site (mortar) inside the swarm, top right
    boom = (452, 112)

    # --- the horde
    mites = []
    def place_mites(cx, cy, n, spread, seed0, ang_range=None, min_d=70):
        placed = 0
        tries = 0
        while placed < n and tries < 2000:
            tries += 1
            x, y = cx + rng.normal(0, spread), cy + rng.normal(0, spread * 0.8)
            if math.hypot(x - rig_cx, y - rig_cy) < min_d or not (6 < x < W - 12 and 30 < y < H - 12):
                continue
            if any(math.hypot(x - mx, y - my) < 10 for mx, my, *_ in mites):
                continue
            if math.hypot(x - boom[0], y - boom[1]) < 18:
                continue
            mites.append((x, y, seed0 + placed))
            placed += 1

    place_mites(440, 110, 34, 34, 100)   # main swarm from the north-east
    place_mites(470, 215, 22, 30, 200)   # flanking pack from the east
    place_mites(215, 60, 10, 22, 300, min_d=60)   # pack harassing the rival
    place_mites(380, 300, 8, 20, 400)
    for i, (x, y, sd) in enumerate(mites):
        target = (rig_cx, rig_cy) if x > 260 else (150, 78)
        ang = angle_to(x, y, *target)
        spr = facing_rot(sand_mite(active=True, seed=sd, volatile=(i % 11 == 5)), ang)
        sc.sprite(spr, x - spr.w / 2, y - spr.h / 2, shadow=(1, 2), strength=0.4)

    # resting boulder backs: camouflaged among real rocks
    sc.sprite(boulder_back(active=False, seed=21).rot90(-1), 82, 300, shadow=(3, 4))
    sc.sprite(boulder_back(active=False, seed=22), 540, 2, shadow=(3, 4))
    # an active, hardened boulder back charging from the south-west
    bb = boulder_back(active=True, hardened=True, seed=23).rot90(-1)
    sc.sprite(bb, 196, 248, shadow=(3, 4))
    for i in range(5):
        sc.dust(196 - 4 - i * 7, 258 + rng.normal(0, 6), 4 - i * 0.5, 0.5 - i * 0.07)

    # spitters on the west flank, sacs lit, mid-volley
    spitters = [(168, 186), (142, 222), (186, 300)]
    for i, (x, y) in enumerate(spitters):
        ang = angle_to(x, y, rig_cx, rig_cy)
        spr = facing_rot(spitter(active=True, seed=30 + i), ang)
        sc.sprite(spr, x - spr.w / 2, y - spr.h / 2, shadow=(2, 3))
    sc.acid(180, 186, rig_x + 4, cab_y + 52, ts=(0.3, 0.62))
    sc.acid(155, 222, rig_x + 6, trailer_y + 20, ts=(0.45, 0.78))
    sc.acid(196, 292, rig_x + 2, trailer_y + 60, ts=(0.5,))

    # dune worm breaching to the south-east
    sc.sprite(dune_worm(17), 498, 244, shadow=None)
    sc.lights.append((526, 272, 46, GLOW[3], 1.1))

    # --- rival player (magenta buggy) to the north-west, heading east
    rival_ang = angle_to(150, 78, 215, 58)
    rv = buggy("magenta", gun_angle=rival_ang - math.pi / 2, seed=9).rot90(-1)
    rvx, rvy = 126, 60
    for i in range(6):
        sc.dust(rvx - 2 - i * 6, rvy + 12 + rng.normal(0, 3), 4.5 - i * 0.5, 0.55 - i * 0.07)
    sc.sprite(rv, rvx, rvy)
    gx, gy = rvx + 29, rvy + 17.5  # gun mount after rotating the buggy to face east
    sc.muzzle(*polar(gx, gy, rival_ang, 14), rival_ang)
    sc.tracer(gx, gy, 214, 58, spacing=15)
    sc.sparks(214, 58)
    sc.cones.append(((rvx + 48, rvy + 17.5), math.pi / 2, 120, 0.42))

    # --- the player's war rig
    tgt_cab = (430, 92)
    tgt_t1 = (470, 208)
    tgt_t2 = spitters[0]
    tgt_rear = (214, 262)
    cab_turret = (rig_x + 23.5, cab_y + 45)
    t1 = (rig_x - 2 + 25.5, trailer_y + 14)
    t2 = (rig_x - 2 + 34, trailer_y + 35)
    t3 = (rig_x - 2 + 27, trailer_y + 77)
    aims = [angle_to(*cab_turret, *tgt_cab), angle_to(*t1, *tgt_t1),
            angle_to(*t2, *tgt_t2), angle_to(*t3, *tgt_rear)]
    for i in range(7):  # dust kicked up by the rear wheels
        for wx in (rig_x + 2, rig_x + 46):
            sc.dust(wx + rng.normal(0, 2), trailer_y + 90 + i * 7, 5 - i * 0.55, 0.6 - i * 0.07)
    trailer = war_rig_trailer("red", aim=(aims[1], aims[2], aims[3]))
    cab = war_rig_cab("red", aim=(aims[0],))
    sc.sprite(trailer, rig_x - 2, trailer_y, shadow=(4, 5))
    sc.sprite(cab, rig_x, cab_y, shadow=(4, 5))
    sc.cones.append(((rig_x + 8, cab_y + 8), 0.0, 150, 0.38))
    sc.cones.append(((rig_x + 40, cab_y + 8), 0.0, 150, 0.38))

    # fire!
    for (cx, cy), ang, tgt, length, kw in [
        (cab_turret, aims[0], tgt_cab, 15, {}),
        (t1, aims[1], tgt_t1, 14, {"phase": 0.4}),
        (t2, aims[2], tgt_t2, 18, {"width": 2, "length": 7, "spacing": 40}),
        (t3, aims[3], tgt_rear, 12, {"phase": 0.7}),
    ]:
        perp = ang + math.pi / 2
        offs = [-1.6, 1.6] if tgt in (tgt_cab, tgt_t1) else [0]
        for o in offs:
            sx, sy = cx + math.sin(perp) * o, cy - math.cos(perp) * o
            mx, my = polar(sx, sy, ang, length + 1)
            sc.muzzle(mx, my, ang)
            sc.tracer(mx, my, *tgt, **kw)
        sc.sparks(*tgt)

    # mortar shell landing in the swarm
    sc.explosion(*boom, 9, seed=5)

    # glass wings overhead: shadows fall far away = they are high up
    for x, y, sd in [(468, 36, 40), (404, 60, 41)]:
        gw = facing_rot(glass_wing(active=True, seed=sd), angle_to(x, y, rig_cx, rig_cy))
        sc.sprite(gw, x, y, shadow=(16, 26), strength=0.3)

    return sc


# ---------------------------------------------------------------- HUD

def plate(cv, x, y, w, h):
    m = rect(W, H, x, y, x + w - 1, y + h - 1)
    paint(cv, m, UI_PLATE, base=1, noise=0.25, seed=x + y)
    edge = m & ~rect(W, H, x + 1, y + 1, x + w - 2, y + h - 2)
    cv.put(edge, OUTLINE)
    for px, py in [(x + 2, y + 2), (x + w - 3, y + 2), (x + 2, y + h - 3), (x + w - 3, y + h - 3)]:
        cv.put(pixels(W, H, [(px, py)]), UI_PLATE[3])


def hud(cv):
    sh = UI_PLATE[0]
    plate(cv, 6, 6, 104, 34)
    text(cv, "ROUND 07", 12, 11, UI_TEXT, sh)
    text(cv, "0:42", 86, 11, FIRE[4], sh)
    text(cv, "FUEL", 12, 20, UI_TEXT, sh)
    bar = rect(W, H, 32, 20, 103, 24)
    cv.put(bar, OUTLINE)
    paint(cv, rect(W, H, 33, 21, 33 + 48, 23), PLAYERS["red"], base=3)
    text(cv, "SCRAP 1,284", 12, 29, UI_TEXT, sh)

    msg1 = "NEXT: GLASS WINGS + VOLATILE"
    msg2 = "THE HIVE ADAPTS TO FIRE..."
    w = max(text_width(msg1), text_width(msg2)) + 14
    plate(cv, W - w - 6, 6, w, 25)
    text(cv, msg1, W - w + 1, 11, UI_TEXT, sh)
    text(cv, msg2, W - w + 1, 20, GLOW[3], sh)

    doc = "DOCTRINE: CIRCLE  /  TARGET: SPITTERS FIRST"
    w = text_width(doc) + 14
    plate(cv, 6, H - 22, w, 16)
    text(cv, doc, 13, H - 16, UI_TEXT, sh)

    # name tag over the rival
    tag = "RUSTJAW"
    text(cv, tag, 150 - text_width(tag) // 2, 50, PLAYERS["magenta"][4], OUTLINE)


# ---------------------------------------------------------------- render passes

def render_day(sc):
    out = bloom(sc.cv.rgb.copy(), sc.cv.emit, radius=3, strength=0.45)
    return np.clip(out, 0, 255)


def render_night(sc):
    base = sc.cv.rgb.copy()
    light = np.ones((H, W, 3)) * np.array([0.17, 0.2, 0.36])
    ys, xs = np.mgrid[0:H, 0:W]
    bay = bayer(H, W)
    for (x, y, r, col, inten) in sc.lights:
        d = np.sqrt((xs - x) ** 2 + (ys - y) ** 2) / r
        f = np.clip(1 - d, 0, 1) ** 1.5 * inten
        f = np.floor(f * 4 + bay * 0.999) / 4
        light += (rgb(col) / 255)[None, None, :] * f[..., None]
    for (ax, ay), ang, length, half in sc.cones:
        rel_a = np.arctan2(xs - ax, -(ys - ay)) - ang
        rel_a = (rel_a + np.pi) % (2 * np.pi) - np.pi
        d = np.sqrt((xs - ax) ** 2 + (ys - ay) ** 2)
        inside = (np.abs(rel_a) < half) & (d < length)
        f = np.where(inside, np.clip(1 - d / length, 0, 1) ** 0.8 * (1 - (np.abs(rel_a) / half) ** 3), 0) * 1.1
        f = np.floor(f * 5 + bay * 0.999) / 5
        light += np.array([1.0, 0.85, 0.6])[None, None, :] * f[..., None]
    out = base * light
    out[sc.cv.emit] = base[sc.cv.emit]  # emissive pixels ignore darkness
    out = bloom(out, sc.cv.emit, radius=4, strength=0.75, gain=2.6)
    return np.clip(out, 0, 255)


def finish(rgb_img):
    """Wrap a rendered frame in a canvas and draw the HUD on top."""
    cv = Canvas(W, H)
    cv.rgb[:] = rgb_img
    cv.a[:] = 1
    hud(cv)
    return cv
