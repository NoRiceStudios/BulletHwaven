"""Combat effect sprites for the tech tree visual pass (tech tree v2.3, "Sichtbar als").

Everything warm: fire, embers, tracers per ammo and the player's own tricks use FIRE / STEEL /
SMOKE (palette rules: GLOW cyan stays reserved for aliens). Exported by export_assets.export_fx():
- fx_flame.png (+ _glow): 8 flicker frames x 3 sizes (small, medium, tall), 16x24 cells, base at the
  cell's bottom centre (FLAME_BASE px above the bottom edge).
- fx_smoke.png: 8 life frames (puff grows, thins out) x 2 rows (grey smoke, black dirty-fuel soot), 24x24.
- fx_oil.png: 3 oil puddle variants, 48x40.
- decal_burn.png: 4 small scorch marks, 24x24 (burnt ground under fire trails).
- tracer.png rows: plain, fire, shrapnel, armour piercing, shard, saw blade (16 spin frames); muzzle.png
  rows: plain, fire, shrapnel, armour piercing.
- fx_kill.png: the "KILL" pop (2 frames: white-hot flash, settled), 32x12.
- fx_banner.png: the contract pennant on a pole (2 wave frames), 14x18.
- rig_drone.png: the repair drone, 16 directions x 2 rotor frames, 20x20.
- zone_beacon.png: the PvP control zone beacon, a scrap derrick on sandbags with a lamp cage and a pennant
  (2 wave frames) x 3 rows (neutral bone cloth, paint-keyed cloth for the owner, locked: cloth furled), 24x36.
"""

import math

import numpy as np

from palette import BONE, BRASS, FIRE, KHAKI, OUTLINE, RUST, SMOKE, STEEL, TYRE
from pixel import Canvas, blob, circle, ellipse, line, outline, paint, pixels, polar, poly, rect, value_noise

FLAME_W, FLAME_H = 16, 24
FLAME_BASE = 3
FLAME_FRAMES = 8
SMOKE_SIZE = 24
SOOT = ["#0e0b0c", "#1a1517", "#2a2426", "#3a3233", "#4a4040"]


def _put(cv, pts, color, emissive=False):
    cv.put(pixels(cv.w, cv.h, [(math.floor(x), math.floor(y)) for x, y in pts]), color, emissive=emissive)


# ---------------------------------------------------------------- fire

def flame(size, phase, seed=3):
    """One flame tongue rising from the cell's bottom centre. size 0..2, phase 0..FLAME_FRAMES-1."""
    W, H = FLAME_W, FLAME_H
    cv = Canvas(W, H)
    r = [2.4, 3.3, 4.4][size]
    hgt = [8.0, 12.0, 17.0][size]
    by = H - FLAME_BASE
    cx = W / 2 - 0.5
    t = phase / FLAME_FRAMES * 2 * math.pi
    hgt *= 1.0 + 0.12 * math.sin(t * 2 + seed)
    ys, xs = np.mgrid[0:H, 0:W] + 0.5
    u = np.clip((by - ys) / hgt, -1, 2)  # 0 at the base, 1 at the tip
    sway = (1.4 + size * 0.5) * np.sin(t + u * 3.2 + seed) * np.clip(u, 0, 1) ** 1.2
    half = r * np.clip(1 - u, 0, 1) ** 0.75 * (1 + 0.18 * np.sin(t * 3 + u * 9))
    base = ((xs - cx) / (r * 1.05)) ** 2 + ((ys - by) / (r * 0.7)) ** 2 < 1
    body = (np.abs(xs - cx - sway) < half) & (u >= 0) & (u < 1)
    m = base | body
    # a detached tongue above the tip on every other frame
    if phase % 2 == 0:
        tx = cx + (1.5 + size) * math.sin(t + 2.6 + seed)
        ty = by - hgt * (1.05 + 0.08 * math.sin(t))
        m |= ellipse(W, H, tx - 0.6 - size * 0.3, ty - 1.2 - size * 0.4, tx + 0.6 + size * 0.3, ty + 1.0)
    noise = value_noise(H, W, 2, seed + phase * 7)
    m &= ~((u > 0.55) & (noise < 0.22))  # ragged upper edge
    inner = m & (np.abs(xs - cx - sway * 0.8) < half * 0.62) & (u < 0.8)
    core = m & (np.abs(xs - cx - sway * 0.6) < half * 0.32) & (u < 0.5)
    hot = m & (((xs - cx) / (r * 0.6)) ** 2 + ((ys - by + 0.5) / (r * 0.45)) ** 2 < 1)
    cv.put(m, FIRE[2], emissive=True)
    cv.put(m & (u > 0.72), FIRE[1], emissive=True)  # dark red licks at the top
    cv.put(inner, FIRE[3], emissive=True)
    cv.put(core, FIRE[4], emissive=True)
    cv.put(hot, FIRE[5], emissive=True)
    cv.put(hot & (np.abs(xs - cx) < 1) & (ys > by - 1.5), FIRE[6], emissive=True)
    # sparks flying off
    rng = np.random.default_rng(seed * 31 + phase)
    for _ in range(1 + size):
        sx = cx + rng.uniform(-r - 1, r + 1)
        sy = by - hgt * rng.uniform(0.5, 1.25)
        if 0 <= sx < W and 0 <= sy < H:
            _put(cv, [(sx, sy)], FIRE[5] if rng.random() < 0.5 else FIRE[4], emissive=True)
    return cv


def flame_rows():
    return [[flame(s, ph, seed=3 + s * 5) for ph in range(FLAME_FRAMES)] for s in range(3)]


# ---------------------------------------------------------------- smoke, oil, burnt ground

def smoke_puff(frame, ramp, seed=5, n=8):
    """A rolling puff: grows, drifts up and thins out with frame (0..n-1). Lit from the top-left."""
    S = SMOKE_SIZE
    cv = Canvas(S, S)
    t = frame / (n - 1)
    r = 3.5 + 6.0 * t ** 0.7
    cy = S / 2 + 2 - t * 3
    m = blob(S, S, S / 2 - 0.5, cy, r, r * 0.85, 0.35, seed, 3)
    m |= blob(S, S, S / 2 + r * 0.45, cy - r * 0.35, r * 0.6, r * 0.55, 0.3, seed + 1, 2)
    grain = np.random.default_rng(seed + frame).random((S, S))
    m &= grain > max(0.0, t - 0.35) * 1.1  # dithered thinning at the end of its life
    paint(cv, m, ramp, base=2 if t < 0.5 else 1, noise=0.35, seed=seed + frame, depth=2)
    return cv


def smoke_rows():
    return [[smoke_puff(f, SMOKE, seed=5) for f in range(8)], [smoke_puff(f, SOOT, seed=9) for f in range(8)]]


def oil(seed):
    """Slipstream oil: a black, glossy puddle with splashes and a warm sheen (never a cold rainbow)."""
    W, H = 48, 40
    cv = Canvas(W, H)
    m = blob(W, H, W / 2, H / 2, 18, 13, 0.45, seed, 4)
    rng = np.random.default_rng(seed)
    for _ in range(7):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(15, 21)
        x, y = polar(W / 2, H / 2, a, d)
        y = H / 2 + (y - H / 2) * 0.75
        m |= circle(W, H, x, y, rng.uniform(0.8, 2.2))
    cv.put(m, "#120d0e")
    inner = m & blob(W, H, W / 2 - 1, H / 2 - 1, 13, 9, 0.4, seed + 1, 4)
    cv.put(inner, "#1c1517")
    sheen = inner & blob(W, H, W / 2 - 6, H / 2 - 4, 6, 2.5, 0.5, seed + 2, 2)
    cv.put(sheen, "#3a2c2a")
    cv.put(sheen & blob(W, H, W / 2 - 7, H / 2 - 5, 3, 1.2, 0.4, seed + 3, 2), "#6b5047")
    cv.put(inner & blob(W, H, W / 2 + 5, H / 2 + 3, 4, 1.5, 0.5, seed + 4, 2), "#2e2230")
    ring = m & ~(np.roll(m, 1, 0) & np.roll(m, -1, 0) & np.roll(m, 1, 1) & np.roll(m, -1, 1))
    cv.put(ring, "#2a1d18")
    return cv


def burn_mark(seed, size=24):
    """Scorched sand under a fire trail: soot, a charred core and a few cooled embers."""
    cv = Canvas(size, size)
    c = size / 2
    m = blob(size, size, c, c, 8.5, 6.5, 0.5, seed, 3)
    grain = np.random.default_rng(seed).random((size, size))
    ys, xs = np.mgrid[0:size, 0:size] + 0.5
    d = np.sqrt(((xs - c) / 8.5) ** 2 + ((ys - c) / 6.5) ** 2)
    cv.put(m & (grain > d * 0.75), "#2e2220", alpha=0.55)
    core = m & (d < 0.55) & (grain > 0.25)
    cv.put(core, "#1c1416", alpha=0.6)
    rng = np.random.default_rng(seed + 7)
    for _ in range(3):
        x, y = c + rng.uniform(-4, 4), c + rng.uniform(-3, 3)
        _put(cv, [(x, y)], RUST[2])
    return cv


# ---------------------------------------------------------------- projectiles and muzzle flashes per ammo

def tracer_ammo(kind, ang, size=16):
    """Tracers per ammo. kind: plain, fire, shrapnel, ap, shard."""
    cv = Canvas(size, size)
    c = size / 2

    def seg(d0, d1, col, w=1):
        cv.put(line(size, size, [polar(c, c, ang, -d0), polar(c, c, ang, -d1)], w), col, emissive=True)

    if kind == "plain":
        seg(6, 2.7, FIRE[3])
        seg(2.7, 0, FIRE[4])
        seg(1.5, 0, FIRE[6])
    elif kind == "fire":  # a fat red-orange bolt with a flickering flame tail
        seg(8, 5, FIRE[1])
        seg(5, 2, FIRE[2], 2)
        seg(3, 0, FIRE[3], 2)
        seg(1.5, 0, FIRE[5])
        for s in (-1, 1):
            _put(cv, [polar(*polar(c, c, ang, -6.5), ang + s * math.pi / 2, 1.3)], FIRE[2], emissive=True)
    elif kind == "shrapnel":  # a short white-hot slug trailing loose sparks
        seg(4, 0, FIRE[5])
        seg(1.5, 0, FIRE[6])
        for d, s in ((5.5, 1), (7.5, -1)):
            _put(cv, [polar(*polar(c, c, ang, -d), ang + s * math.pi / 2, 1.5)], FIRE[4], emissive=True)
    elif kind == "ap":  # a long steel-white needle with a hot tip
        seg(9, 5, STEEL[4])
        seg(5, 1, STEEL[5])
        seg(1.5, 0, FIRE[6])
        _put(cv, [polar(c, c, ang, -9.5)], FIRE[3], emissive=True)
    elif kind == "shard":  # a tumbling sliver of steel, hot along one edge
        a, b = polar(c, c, ang + 0.6, 2.0), polar(c, c, ang + 0.6 + math.pi, 1.5)
        cv.put(line(size, size, [a, b], 1), STEEL[4])
        _put(cv, [a], FIRE[5], emissive=True)
        _put(cv, [polar(c, c, ang, -3)], FIRE[3], emissive=True)
        outline(cv, OUTLINE)
    return cv


def saw(frame, size=16, n=16):
    """A scrap-press saw blade spinning (frame = rotation step)."""
    cv = Canvas(size, size)
    c = size / 2 - 0.5
    rot = frame / n * 2 * math.pi / 4  # 8 teeth: a quarter turn repeats every 4 teeth
    teeth = []
    for k in range(8):
        a = rot + k * math.pi / 4
        teeth.append(polar(c, c, a, 5.6))
        teeth.append(polar(c, c, a + 0.32, 4.0))
        teeth.append(polar(c, c, a + math.pi / 4 - 0.05, 4.0))
    m = poly(size, size, teeth)
    paint(cv, m, STEEL, base=3, light=False)
    cv.put(circle(size, size, c, c, 2.8) & ~circle(size, size, c, c, 1.6), RUST[3])
    cv.put(circle(size, size, c, c, 0.9), OUTLINE)
    for k in range(8):
        _put(cv, [polar(c, c, rot + k * math.pi / 4, 5.2)], STEEL[5])
    a = rot * 4
    _put(cv, [polar(c, c, a, 3.5)], FIRE[5], emissive=True)  # hot glint
    outline(cv, OUTLINE)
    return cv


def muzzle_ammo(kind, ang, size=16):
    cv = Canvas(size, size)
    c = size / 2

    def ray(d0, d1, off, col, w=1):
        p0 = polar(*polar(c, c, ang + math.pi / 2, off), ang, d0)
        p1 = polar(*polar(c, c, ang + math.pi / 2, off), ang, d1)
        cv.put(line(size, size, [p0, p1], w), col, emissive=True)

    if kind == "plain":
        ray(0, 3, 0, FIRE[5], 2)
        _put(cv, [polar(c, c, ang + s * math.pi / 2, 1.5) for s in (-1, 1)], FIRE[4], emissive=True)
        _put(cv, [polar(c, c, ang, 4.5)], FIRE[4], emissive=True)
        _put(cv, [(c, c)], FIRE[6], emissive=True)
    elif kind == "fire":  # a fat red-orange blossom with licking tongues
        m = ellipse(size, size, c - 3, c - 3, c + 3, c + 3)
        cx, cy = polar(c, c, ang, 2.5)
        m = circle(size, size, cx, cy, 3.2)
        cv.put(m, FIRE[2], emissive=True)
        cv.put(circle(size, size, *polar(c, c, ang, 1.8), 2.0), FIRE[3], emissive=True)
        cv.put(circle(size, size, *polar(c, c, ang, 1.2), 1.0), FIRE[5], emissive=True)
        for s in (-0.6, 0.0, 0.6):
            ray(4, 6.5, s * 3, FIRE[2] if s else FIRE[3])
        _put(cv, [(c, c)], FIRE[6], emissive=True)
    elif kind == "shrapnel":  # a spiky white-yellow star
        for a in (-0.7, 0.0, 0.7):
            p1 = polar(c, c, ang + a, 5 if a == 0 else 3.5)
            cv.put(line(size, size, [(c, c), p1], 1), FIRE[5], emissive=True)
            _put(cv, [p1], FIRE[6], emissive=True)
        for s in (-1, 1):
            _put(cv, [polar(c, c, ang + s * 1.6, 2.5)], FIRE[4], emissive=True)
        _put(cv, [(c, c)], FIRE[6], emissive=True)
    elif kind == "ap":  # a long, narrow, white-hot jet
        ray(0, 7, 0, STEEL[5])
        ray(0, 4, 0, FIRE[6], 2)
        _put(cv, [polar(c, c, ang + s * math.pi / 2, 1.5) for s in (-1, 1)], FIRE[5], emissive=True)
    return cv


EVO_TRACER_SIZE = 24
EVO_TRACER_KINDS = ["gatling", "grinder", "shell"]  # tracer_evo.png rows (render: Gfx.EVO_*)


def tracer_evo(kind, ang, size=EVO_TRACER_SIZE):
    """Shots of the evolved weapons: bigger, brighter, still warm. Head at the cell centre, tail behind."""
    cv = Canvas(size, size)
    c = size / 2

    def seg(d0, d1, col, w=1, off=0.0):
        p0 = polar(*polar(c, c, ang + math.pi / 2, off), ang, -d0)
        p1 = polar(*polar(c, c, ang + math.pi / 2, off), ang, -d1)
        cv.put(line(size, size, [p0, p1], w), col, emissive=True)

    if kind == "gatling":  # a long white-hot streak: the stream reads as one solid line of tracers
        seg(11, 6, FIRE[2])
        seg(6, 2, FIRE[4])
        seg(3, 0, FIRE[5], 2)
        seg(1.5, 0, FIRE[6])
    elif kind == "grinder":  # a fat glowing slug shedding sparks
        seg(4, 0, FIRE[4], 2)
        seg(2, 0, FIRE[6], 2)
        for d, s, col in ((5.5, 1.4, FIRE[5]), (7.5, -1.6, FIRE[4]), (9.5, 0.8, FIRE[3]), (11.0, -0.6, FIRE[2])):
            _put(cv, [polar(*polar(c, c, ang, -d), ang + math.pi / 2, s)], col, emissive=True)
    elif kind == "shell":  # a giant shell with a burning trail
        seg(12, 7, FIRE[1], 2)
        seg(9, 4, FIRE[2], 3)
        seg(6, 3, FIRE[3], 2)
        body = line(size, size, [polar(c, c, ang, -3.5), polar(c, c, ang, 1.5)], 3)
        cv.put(body, STEEL[2])
        cv.put(line(size, size, [polar(c, c, ang, -3.0), polar(c, c, ang, 0.5)], 1), STEEL[4])
        cv.put(line(size, size, [polar(*polar(c, c, ang, -2.0), ang + math.pi / 2, -1.5),
                                 polar(*polar(c, c, ang, -2.0), ang + math.pi / 2, 1.5)], 1), BRASS[3])
        outline(cv, OUTLINE, skip_emissive=True)
        _put(cv, [polar(c, c, ang, 1.8)], FIRE[6], emissive=True)  # the nose glows from the air friction
        _put(cv, [polar(c, c, ang, 2.6)], FIRE[5], emissive=True)
    return cv


def tracer_evo_rows(fx_ang):
    return [[tracer_evo(k, a) for a in fx_ang] for k in EVO_TRACER_KINDS]


TRACER_KINDS = ["plain", "fire", "shrapnel", "ap", "shard"]
MUZZLE_KINDS = ["plain", "fire", "shrapnel", "ap"]


def tracer_rows(fx_ang):
    rows = [[tracer_ammo(k, a) for a in fx_ang] for k in TRACER_KINDS]
    rows.append([saw(i) for i in range(len(fx_ang))])
    return rows


def muzzle_rows(fx_ang):
    return [[muzzle_ammo(k, a) for a in fx_ang] for k in MUZZLE_KINDS]


# ---------------------------------------------------------------- one-offs

_BIG = {  # 5x7 block letters
    "K": ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    "I": ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"],
    "L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
}


def kill_word(flash):
    W, H = 32, 12
    cv = Canvas(W, H)
    x = 2
    fill = np.zeros((H, W), bool)
    for ch in "KILL":
        g = _BIG[ch]
        for ry, row in enumerate(g):
            for rx, c in enumerate(row):
                if c == "#":
                    fill[2 + ry, x + rx] = True
        x += len(g[0]) + 2
    fill |= np.roll(fill, 1, 1)  # bold: every stem two pixels wide
    ys = np.mgrid[0:H, 0:W][0]
    if flash:
        cv.put(fill, FIRE[6], emissive=True)
    else:
        cv.put(fill, FIRE[3], emissive=True)
        cv.put(fill & (ys <= 4), FIRE[5], emissive=True)
        cv.put(fill & (ys == 5), FIRE[4], emissive=True)
        cv.put(fill & (ys >= 8), FIRE[2], emissive=True)
    shadow = np.roll(np.roll(fill, 1, 0), 1, 1) & ~fill
    cv.put(shadow, FIRE[0])
    outline(cv, OUTLINE)
    return cv


def banner(phase):
    """The contract pennant: a brass-capped pole with a bone cloth and a red stencil stripe."""
    W, H = 14, 18
    cv = Canvas(W, H)
    cv.put(rect(W, H, 2, 2, 2, 17), STEEL[3])
    cv.put(rect(W, H, 3, 3, 3, 17), STEEL[1])
    cv.put(rect(W, H, 1, 1, 3, 2), BRASS[3])
    wave = [0, 1] if phase == 0 else [1, 0]
    pts = [(4, 3), (8, 3 + wave[0]), (12, 3), (11, 6 + wave[1]), (12, 9), (8, 9 + wave[0]), (4, 9)]
    m = poly(W, H, pts)
    paint(cv, m, BONE, base=3, light=False)
    cv.put(m & rect(W, H, 4, 5, 12, 6), "#a8341f")
    cv.put(m & rect(W, H, 4, 9, 12, 9), BONE[1])
    outline(cv, OUTLINE)
    return cv


def drone(ang, phase, size=20):
    """Repair drone, top down: a scrap quadcopter. Four arms off a khaki hull with a welding arm at the front,
    outlined; the rotors on top are see-through blur discs with one bright blade streak (no outline), so
    they read as spinning over the sand."""
    cv = Canvas(size, size)
    c = size / 2 - 0.5
    hubs = []
    for k in range(4):
        a = ang + math.pi / 4 + k * math.pi / 2
        rx, ry = polar(c, c, a, 5.0)
        hubs.append((rx, ry))
        cv.put(line(size, size, [(c, c), (rx, ry)], 1), STEEL[2])
        cv.put(circle(size, size, rx, ry, 1.0), STEEL[1])  # motor can
    body = circle(size, size, c, c, 2.9)
    paint(cv, body, KHAKI, base=3)
    hx, hy = polar(c, c, ang, 4.5)
    cv.put(line(size, size, [polar(c, c, ang, 2.0), (hx, hy)], 1), STEEL[3])
    outline(cv, OUTLINE)
    _put(cv, [polar(c, c, ang + math.pi * 0.75, 1.2)], STEEL[4])  # a lit rivet / sensor (top-left light)
    _put(cv, [polar(c, c, ang + math.pi, 1.6)], RUST[2])
    _put(cv, [(hx, hy)], FIRE[5] if phase == 0 else FIRE[3], emissive=True)
    for k, (rx, ry) in enumerate(hubs):
        disc = circle(size, size, rx, ry, 3.0)
        cv.put(disc, TYRE[1], alpha=0.38)
        ba = phase * math.pi / 2 + k * 0.9  # the blade streak, turned a quarter each frame
        bx0, by0 = polar(rx, ry, ba, 2.6)
        bx1, by1 = polar(rx, ry, ba + math.pi, 2.6)
        cv.put(line(size, size, [(bx0, by0), (bx1, by1)], 1) & disc, STEEL[5], alpha=0.9)
        _put(cv, [(rx, ry)], STEEL[1])
    return cv


ZONE_W, ZONE_H = 40, 56
ZONE_FOOT = (18, 51)  ## the mast's foot in a zone beacon cell (the ground point under the zone centre)
ZONE_LAMP = (17, 15)  ## top-left pixel of the 2x2 lamp in the cage at the top of the derrick
BURLAP_DUSTY = ["#3e3424", "#5c4b33", "#7a6646", "#998259", "#b39d72"]


def zone_beacon(state, phase):
    """Control zone beacon, upright like the contract pennant: a rusty tripod derrick on a ring of sandbags
    round a drum, a steel lamp cage at the apex and a big swallowtail pennant on the mast. state 0 neutral
    (bone cloth with a red stencil stripe), 1 owned (paint-keyed cloth and drum band: the paint shader takes
    the owner's ramp), 2 locked (the cloth furled round the mast, the lamp dark)."""
    from rig import paint_key

    def build(ramp):
        W, H = ZONE_W, ZONE_H
        cv = Canvas(W, H)
        cloth = ramp if state == 1 else BONE
        # sandbag ring (back row first), a dented drum in the middle
        for i, (x0, y0, x1, y1) in enumerate(((5, 44, 15, 50), (21, 44, 31, 50))):
            paint(cv, ellipse(W, H, x0, y0, x1, y1), BURLAP_DUSTY, base=2, noise=0.3, seed=7 + i)
        drum = rect(W, H, 14, 41, 22, 50)
        paint(cv, drum, RUST, base=2, noise=0.25, seed=4)
        cv.put(rect(W, H, 14, 44, 22, 45), cloth[3] if state == 1 else STEEL[2])  # band in the owner's paint
        cv.put(rect(W, H, 14, 41, 22, 41), RUST[4])
        # tripod: back leg in shade, the two front legs 2 px (lit left), braces and X bracing
        apex = (18, 17)
        cv.put(line(W, H, [apex, (20, 44)], 1), RUST[0])
        for foot, lit, dark in (((5, 49), RUST[4], RUST[2]), ((31, 49), RUST[3], RUST[1])):
            cv.put(line(W, H, [apex, foot], 1), lit)
            cv.put(line(W, H, [(apex[0] + 1, apex[1]), (foot[0] + 1, foot[1])], 1), dark)
        cv.put(line(W, H, [(10, 37), (27, 37)], 1), STEEL[3])
        cv.put(line(W, H, [(13, 27), (24, 27)], 1), STEEL[3])
        cv.put(line(W, H, [(13, 28), (26, 37)], 1), STEEL[1])
        cv.put(line(W, H, [(24, 28), (11, 37)], 1), STEEL[2])
        cv.put(pixels(W, H, [(10, 37), (13, 27), (27, 37), (24, 27)]), STEEL[5])  # bolt heads catch the light
        # mast and lamp cage
        cv.put(rect(W, H, 18, 1, 18, 16), STEEL[4])
        cv.put(rect(W, H, 19, 1, 19, 16), STEEL[2])
        cv.put(rect(W, H, 17, 0, 19, 0), STEEL[5])
        cage = rect(W, H, 14, 12, 22, 18)
        paint(cv, cage, STEEL, base=2)
        cv.put(rect(W, H, 15, 13, 21, 17), STEEL[0])
        lx, ly = ZONE_LAMP
        lamp = rect(W, H, lx, ly - 1, lx + 2, ly + 1)
        cv.put(lamp, STEEL[1] if state == 2 else FIRE[4], emissive=state != 2)
        if state != 2:
            cv.put(pixels(W, H, [(lx, ly - 1)]), FIRE[6], emissive=True)
        cv.put(pixels(W, H, [(16, 12), (18, 12), (20, 12)]), STEEL[5])  # cage bars
        cv.put(pixels(W, H, [(16, 18), (18, 18), (20, 18)]), STEEL[1])
        if state == 2:
            roll = rect(W, H, 20, 1, 22, 10)
            paint(cv, roll, BONE, base=1)
            cv.put(pixels(W, H, [(21, 3), (21, 6), (21, 9)]), RUST[1])  # lashing
        else:
            w0, w1 = (0, 1) if phase == 0 else (1, 0)
            pts = [(20, 1), (27, 2 + w0), (38, 1 + w1), (33, 6 + w0), (38, 11 + w1), (27, 11 + w0), (20, 11)]
            m = poly(W, H, pts)
            paint(cv, m, cloth, base=3, light=False)
            cv.put(m & rect(W, H, 20, 9, 39, 12), cloth[1])  # the sagging lower edge in shade
            cv.put(m & rect(W, H, 20, 1, 39, 2), cloth[4])  # the top edge in the sun
            for fold in (24 + 2 * phase, 31 - phase):  # folds catch the light / fall in shade
                cv.put(m & rect(W, H, fold, 3, fold, 9), cloth[2])
            if state == 0:
                cv.put(m & rect(W, H, 21, 6, 33, 6), "#a8341f")  # a red stencil stripe on the bare cloth
        outline(cv, OUTLINE)
        return cv

    return paint_key(build)
