"""Export 1x sprites for the Godot project into game/assets/ (docs/architecture.md, "assets/").

Rotation: pixel art rotated by the GPU at arbitrary angles turns into jaggy, shimmering mush at
640x360. Instead every directional sprite is pre-rendered here as a horizontal strip of frames:
- hand-built sprites (buggy hull, aliens) go through RotSprite (Scale2x three times, nearest
  rotation, sampled back at 1x) *before* the 1px outline is drawn, so each frame gets a clean
  outline and no orphan pixels;
- sprites that are drawn from lines anyway (turret, tracers, muzzle flash, acid) are drawn
  natively at every angle.
Frame k shows the sprite rotated k * 360 / N degrees clockwise from north. Emissive pixels get a
matching *_glow strip (banded, dithered halo) that the game draws with additive blending.
Rows (top to bottom) are variants of the same sprite.
"""

import contextlib
import math
import os

import numpy as np

import sprites
from palette import (BONE, FIRE, GLOW, OUTLINE, PLAYERS, ROCK, SAND, SHADOW, SMOKE, UI_PLATE)
from pixel import (Canvas, bayer, blob, cast_shadow, circle, line, outline, paint, paste, pixels,
                   polar, rect, rgb, value_noise, _GLYPHS)
from scene import box_blur
from terrain import dune_sea

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "game", "assets")

VEHICLE_DIRS = 32
ENEMY_DIRS = 16
FX_DIRS = 16
FONT_CHARS = " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.+-/()!',"
ARENA_W, ARENA_H = 1280, 720


# ---------------------------------------------------------------- RotSprite

@contextlib.contextmanager
def no_outline():
    """Sprite builders end with outline(); rotate the bare sprite and outline each frame instead."""
    orig = sprites.outline
    sprites.outline = lambda *a, **k: None
    try:
        yield
    finally:
        sprites.outline = orig


def _encode(cv):
    """Canvas -> int64 colour keys (0 = transparent, bit 25 = emissive)."""
    c = np.clip(np.round(cv.rgb), 0, 255).astype(np.int64)
    key = ((c[..., 0] << 16) | (c[..., 1] << 8) | c[..., 2]) + 1 + (cv.emit.astype(np.int64) << 25)
    key[~cv.solid()] = 0
    return key


def _decode(key):
    h, w = key.shape
    cv = Canvas(w, h)
    solid = key > 0
    k = np.where(solid, key - 1, 0)
    cv.emit = solid & (((k >> 25) & 1) == 1)
    k &= (1 << 24) - 1
    cv.rgb = np.dstack([(k >> 16) & 255, (k >> 8) & 255, k & 255]).astype(np.float32)
    cv.a = solid.astype(np.float32)
    return cv


def _scale2x(k):
    h, w = k.shape
    p = np.pad(k, 1)
    b, d, f, hh = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 2:], p[2:, 1:-1]
    out = np.empty((2 * h, 2 * w), k.dtype)
    out[0::2, 0::2] = np.where((b == d) & (b != f) & (d != hh), d, k)
    out[0::2, 1::2] = np.where((b == f) & (b != d) & (f != hh), f, k)
    out[1::2, 0::2] = np.where((d == hh) & (d != b) & (hh != f), d, k)
    out[1::2, 1::2] = np.where((hh == f) & (d != hh) & (b != f), f, k)
    return out


def rotsprite(cv, ang, size):
    """Rotate cv clockwise by ang (radians) into a size x size canvas centred on cv's centre."""
    key = _encode(cv)
    h, w = key.shape
    key = np.pad(key, ((0, h % 2), (0, w % 2)))  # even size: the pivot sits on a pixel corner
    h, w = key.shape
    k8 = _scale2x(_scale2x(_scale2x(key)))
    ys, xs = np.mgrid[0:size, 0:size] + 0.5
    rx, ry = xs - size / 2, ys - size / 2
    c, s = math.cos(ang), math.sin(ang)
    ix = np.floor((rx * c + ry * s + w / 2) * 8).astype(int)
    iy = np.floor((-rx * s + ry * c + h / 2) * 8).astype(int)
    ok = (ix >= 0) & (iy >= 0) & (ix < w * 8) & (iy < h * 8)
    out = np.zeros((size, size), np.int64)
    out[ok] = k8[iy[ok], ix[ok]]
    return _decode(out)


def rotated_frames(make, dirs, size):
    with no_outline():
        base = make()
    frames = []
    for k in range(dirs):
        f = rotsprite(base, k * 2 * math.pi / dirs, size)
        outline(f, OUTLINE)
        frames.append(f)
    return frames


# ---------------------------------------------------------------- sheets and glow

def sheet(rows):
    """rows: list of lists of equally sized canvases -> one grid canvas."""
    cw, ch = rows[0][0].w, rows[0][0].h
    out = Canvas(cw * max(len(r) for r in rows), ch * len(rows))
    for j, row in enumerate(rows):
        for i, f in enumerate(row):
            out.rgb[j * ch:(j + 1) * ch, i * cw:(i + 1) * cw] = f.rgb
            out.a[j * ch:(j + 1) * ch, i * cw:(i + 1) * cw] = f.a
            out.emit[j * ch:(j + 1) * ch, i * cw:(i + 1) * cw] = f.emit
    return out


def glow_of(cv, radius=2, gain=3.0, steps=3, strength=0.8):
    """Additive halo around the emissive pixels: rgb = hue, alpha = banded, dithered intensity."""
    e = cv.rgb * cv.emit[..., None]
    b = box_blur(box_blur(e, radius), radius)
    lum = b.max(axis=2)
    level = np.floor(np.clip(lum / 255 * gain, 0, 1) * steps + bayer(*lum.shape) * 0.999) / steps
    out = Canvas(cv.w, cv.h)
    out.rgb = (b / np.maximum(lum, 1e-3)[..., None] * 255).astype(np.float32)
    out.a = (level * strength).astype(np.float32)
    return out


def glow_sheet(rows, **kw):
    return sheet([[glow_of(f, **kw) for f in row] for row in rows])


def halo_tex(r, color, strength, steps=4):
    size = 2 * int(math.ceil(r)) + 2
    ys, xs = np.mgrid[0:size, 0:size] + 0.5
    d = np.sqrt((xs - size / 2) ** 2 + (ys - size / 2) ** 2) / r
    f = np.clip(1 - d, 0, 1) ** 1.6
    lvl = np.floor(f * steps + bayer(size, size) * 0.999) / steps
    cv = Canvas(size, size)
    cv.rgb[:] = rgb(color)
    cv.a = (lvl * strength).astype(np.float32)
    return cv


# ---------------------------------------------------------------- directional effects (native)

def tracer(ang, size=16, length=6):
    cv = Canvas(size, size)
    c = size / 2
    tail = polar(c, c, ang, -length)
    cv.put(line(size, size, [tail, polar(c, c, ang, -length * 0.45)], 1), FIRE[3], emissive=True)
    cv.put(line(size, size, [polar(c, c, ang, -length * 0.45), (c, c)], 1), FIRE[4], emissive=True)
    cv.put(line(size, size, [polar(c, c, ang, -1.5), (c, c)], 1), FIRE[6], emissive=True)
    return cv


def acid(ang, size=16):
    cv = Canvas(size, size)
    c = size / 2
    for k in range(1, 4):  # dripping trail
        tx, ty = polar(c, c, ang, -k * 2.2)
        cv.put(pixels(size, size, [(round(tx), round(ty))]), GLOW[2 if k < 3 else 1], emissive=True)
    paint(cv, circle(size, size, c - 0.5, c - 0.5, 1.8), GLOW[1:5], base=2, emissive=True)
    cv.put(pixels(size, size, [(int(c - 1), int(c - 1))]), GLOW[4], emissive=True)
    return cv


def muzzle(ang, size=16, n=3):
    cv = Canvas(size, size)
    c = size / 2
    pts = [polar(c, c, ang, i) for i in range(n + 1)]
    perp = [polar(c, c, ang + s * math.pi / 2, 1.5) for s in (-1, 1)]
    cv.put(line(size, size, pts, 2), FIRE[5], emissive=True)
    cv.put(pixels(size, size, [(math.floor(x), math.floor(y)) for x, y in perp]), FIRE[4], emissive=True)
    tip = polar(c, c, ang, n + 1.5)
    cv.put(pixels(size, size, [(math.floor(tip[0]), math.floor(tip[1]))]), FIRE[4], emissive=True)
    cv.put(pixels(size, size, [(math.floor(c), math.floor(c))]), FIRE[6], emissive=True)
    return cv


def turret_frame(ang, size=36):
    cv = Canvas(size, size)
    sprites.turret(cv, 17.5, 18, 2.5, ang, 14, barrels=1, bw=2, seed=1)
    outline(cv, OUTLINE)
    return cv


# ---------------------------------------------------------------- explosion + decals

def explosion_frames(n=8, size=48, seed=5):
    frames = []
    rng = np.random.default_rng(seed)
    debris = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.6, 1.0)) for _ in range(16)]
    c = size / 2
    for i in range(n):
        t = i / (n - 1)
        cv = Canvas(size, size)
        r = 3 + 8 * min(1.0, t * 2.2)
        grain = np.random.default_rng(seed + i).random((size, size))
        fade = max(0.0, (t - 0.45) / 0.55)  # smoke thins out at the end
        if i > 0:
            smoke = blob(size, size, c + 1 + t * 2, c - 1 - t * 4, r * 1.2, r * 1.05, 0.5, seed, 2)
            smoke &= grain > fade * 0.9
            paint(cv, smoke, SMOKE, base=2 if t < 0.6 else 1, noise=0.4, seed=seed)
        fire_r = r * max(0.0, 0.95 - t * 0.9)
        if fire_r > 1:
            fire = blob(size, size, c, c, fire_r, fire_r * 0.9, 0.45, seed + 1, 2)
            paint(cv, fire, FIRE[1:5], base=3 if t < 0.3 else 2, noise=0.4, seed=seed + i, emissive=True)
            core = blob(size, size, c - 1, c - 1, fire_r * 0.55, fire_r * 0.5, 0.4, seed + 2, 2)
            paint(cv, core, FIRE[4:], base=2 if t < 0.2 else 1, light=False, emissive=True)
        if 0 < i < 5:  # flying debris
            for a, f in debris:
                x, y = polar(c, c, a, f * (6 + 16 * t))
                col = FIRE[5] if (a * 10) % 1 < 0.6 else OUTLINE
                cv.put(pixels(size, size, [(math.floor(x), math.floor(y))]), col, emissive=col != OUTLINE)
        frames.append(cv)
    return frames


def goo(size, r, seed, shards=False):
    cv = Canvas(size, size)
    c = size / 2
    rng = np.random.default_rng(seed)
    m = blob(size, size, c, c, r, r * 0.8, 0.5, seed, 2)
    paint(cv, m, GLOW[:2], base=0, light=False, noise=0.3, seed=seed)
    for _ in range(4 + int(r)):
        x, y = polar(c, c, rng.uniform(0, 2 * math.pi), r + rng.uniform(1, 4))
        cv.put(pixels(size, size, [(math.floor(x), math.floor(y))]), GLOW[1])
    if shards:  # chunks of the rock shell
        for i in range(6):
            x, y = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(r * 0.4, r * 1.2))
            paint(cv, blob(size, size, x, y, 2.2, 1.8, 0.4, seed + i, 1), ROCK, base=2)
        outline(cv, OUTLINE)
    return cv


def carcass(seed, size=16):
    cv = Canvas(size, size)
    paste(cv, sprites.mite_carcass(seed), 1, 1)
    return cv


def scorch(size, r, seed):
    cv = Canvas(size, size)
    c = size / 2
    m = blob(size, size, c, c, r, r * 0.85, 0.45, seed, 2)
    cv.put(m, OUTLINE, alpha=0.42)
    core = blob(size, size, c, c, r * 0.6, r * 0.5, 0.5, seed + 1, 2) & (bayer(size, size) < 0.5)
    cv.put(core, OUTLINE, alpha=0.5)
    rng = np.random.default_rng(seed)
    for _ in range(10):  # soot flecks
        x, y = polar(c, c, rng.uniform(0, 2 * math.pi), rng.uniform(r, r * 1.4))
        cv.put(pixels(size, size, [(math.floor(x), math.floor(y))]), OUTLINE, alpha=0.4)
    return cv


# ---------------------------------------------------------------- ground

def _track(cv, pts, width, depth, seed):
    W, H = cv.w, cv.h
    m = line(W, H, pts, width)
    clumps = value_noise(H, W, 2, seed) > 0.55
    cv.rgb[m] *= depth
    cv.rgb[m & clumps] *= 0.94
    rim = line(W, H, pts, width + 2) & ~m & (np.random.default_rng(seed).random((H, W)) < 0.5)
    cv.rgb[rim] = np.minimum(cv.rgb[rim] * 1.06, 255)


def ground(seed=4):
    """Dune Sea arena (1280x720) with flat, decorative props (the sim has no obstacles)."""
    W, H = ARENA_W, ARENA_H
    cv = Canvas(W, H)
    cv.rgb[:] = dune_sea(W, H, seed)
    cv.a[:] = 1
    # old, half blown-over tyre tracks
    for off in (0, 8):
        pts = [(x, 560 + off + 60 * math.sin(x / 210.0) + 25 * math.sin(x / 67.0)) for x in range(-10, W + 20, 8)]
        _track(cv, pts, 3, 0.94, seed + off)
    for off in (0, 7):
        pts = [(890 + off + 40 * math.sin(y / 90.0), y) for y in range(-10, 330, 8)]
        _track(cv, pts, 3, 0.95, seed + 20 + off)

    def put(spr, x, y, sh=(3, 4), strength=0.4):
        cast_shadow(cv, spr, x, y, *sh, strength=strength)
        paste(cv, spr, x, y)

    put(sprites.hull_plate(1), 40, 70)
    put(sprites.ribcage(2), 980, 520, sh=(2, 3), strength=0.35)
    for (x, y, s, sd) in [(560, 20, 1.0, 3), (1180, 60, 1.2, 8), (60, 610, 1.3, 11), (1200, 640, 0.9, 5),
                          (420, 470, 0.8, 14), (760, 650, 0.9, 21)]:
        put(sprites.rock_cluster(sd, s), x, y)
    rng = np.random.default_rng(seed)
    for i in range(18):  # sun-bleached scrap from older fights
        paste(cv, sprites.scrap_bit(i), rng.uniform(20, W - 20), rng.uniform(20, H - 20))
    return cv


# ---------------------------------------------------------------- UI

def font():
    cw, ch = 4, 5
    cv = Canvas(cw * len(FONT_CHARS), ch)
    for i, chr_ in enumerate(FONT_CHARS):
        rows = _GLYPHS.get(chr_, "...|...|...|...|...").split("|")
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    cv.rgb[ry, i * cw + rx] = 255
                    cv.a[ry, i * cw + rx] = 1
    return cv


def ui_plate(size=24):
    W = H = size
    cv = Canvas(W, H)
    m = rect(W, H, 0, 0, W - 1, H - 1)
    paint(cv, m, UI_PLATE, base=1, noise=0.25, seed=3)
    cv.put(m & ~rect(W, H, 1, 1, W - 2, H - 2), OUTLINE)
    cv.put(pixels(W, H, [(2, 2), (W - 3, 2), (2, H - 3), (W - 3, H - 3)]), UI_PLATE[3])
    return cv


# ---------------------------------------------------------------- main

def export(out=OUT):
    os.makedirs(out, exist_ok=True)

    def save(cv, name):
        cv.to_image(1).save(os.path.join(out, name))

    v_ang = [k * 2 * math.pi / VEHICLE_DIRS for k in range(VEHICLE_DIRS)]
    fx_ang = [k * 2 * math.pi / FX_DIRS for k in range(FX_DIRS)]

    # vehicles: hull (RotSprite) + separate turret (drawn natively per angle)
    for player, sd in (("red", 1), ("magenta", 9)):
        save(sheet([rotated_frames(lambda: sprites.buggy(player, seed=sd, gun=False), VEHICLE_DIRS, 64)]),
             f"buggy_{player}.png")
    save(sheet([[turret_frame(a) for a in v_ang]]), "turret_mg.png")

    # aliens (active): rows = variants
    mites = [rotated_frames(lambda s=s: sprites.sand_mite(True, seed=s), ENEMY_DIRS, 32) for s in (1, 2)]
    boulders = [rotated_frames(lambda s=s: sprites.boulder_back(True, seed=s), ENEMY_DIRS, 64) for s in (7, 23)]
    spitters = [rotated_frames(lambda: sprites.spitter(True, seed=11), ENEMY_DIRS, 48)]
    for name, rows, kw in (("mite", mites, {"radius": 1, "gain": 3.0, "strength": 0.35}),
                           ("boulder", boulders, {"radius": 2, "gain": 1.6, "strength": 0.3}),
                           ("spitter", spitters, {"radius": 2, "gain": 2.0, "strength": 0.4})):
        save(sheet(rows), f"{name}.png")
        save(glow_sheet(rows, **kw), f"{name}_glow.png")

    # projectiles and muzzle flash
    for name, fn, kw in (("tracer", tracer, {"radius": 1, "gain": 2.0, "strength": 0.3}),
                         ("acid", acid, {"radius": 2, "gain": 2.5, "strength": 0.45}),
                         ("muzzle", muzzle, {"radius": 2, "gain": 2.5, "strength": 0.5})):
        rows = [[fn(a) for a in fx_ang]]
        save(sheet(rows), f"{name}.png")
        save(glow_sheet(rows, **kw), f"{name}_glow.png")
    save(halo_tex(10, GLOW[3], 0.3), "halo_cyan.png")
    save(halo_tex(16, FIRE[4], 0.6), "halo_warm.png")
    save(halo_tex(40, FIRE[3], 0.7, steps=5), "halo_warm_big.png")

    ex = [explosion_frames()]
    save(sheet(ex), "explosion.png")
    save(glow_sheet(ex, radius=3, gain=2.2, strength=0.6), "explosion_glow.png")

    # decals (persistent ground marks)
    save(sheet([[goo(24, r, i) for i, r in enumerate((3.0, 4.0, 4.5, 5.0))]]), "decal_goo.png")
    save(sheet([[goo(40, r, 10 + i, shards=True) for i, r in enumerate((8.0, 9.5))]]), "decal_goo_big.png")
    save(sheet([[carcass(i) for i in range(4)]]), "decal_carcass.png")
    save(sheet([[scorch(48, r, 30 + i) for i, r in enumerate((12.0, 14.0))]]), "decal_scorch.png")

    save(ground(), "ground_dune_sea.png")
    save(font(), "font_3x5.png")
    save(ui_plate(), "ui_plate.png")
    print("wrote game assets to", os.path.normpath(out))
