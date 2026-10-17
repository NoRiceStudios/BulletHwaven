"""Render the BulletHwaven art-style samples into art/samples/.

Usage:  python tools/artgen/generate.py [--scale 3]
        python tools/artgen/generate.py --export-game-assets   (1x sprites into game/assets/)
"""

import argparse
import math
import os

import numpy as np

import scene
from palette import OUTLINE, RAMPS, SAND, UI_PLATE, UI_TEXT
from pixel import Canvas, cast_shadow, paste, rect, rgb, text, text_width
from sprites import (boulder_back, buggy, dune_worm, glass_wing, hull_plate, ribcage, rock_cluster,
                     sand_mite, spitter, war_rig_cab, war_rig_trailer)
from terrain import BIOMES, dune_sea

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "samples")


def label(cv, s, cx, y, color=UI_TEXT):
    text(cv, s, int(cx - text_width(s) / 2), y, color, OUTLINE)


def palette_sheet():
    sw = 14
    w = 8 + 64 + max(len(r) for r in RAMPS.values()) * (sw + 1)
    h = 8 + len(RAMPS) * (sw + 3)
    cv = Canvas(w, h)
    cv.put(rect(w, h, 0, 0, w - 1, h - 1), UI_PLATE[0])
    for i, (name, ramp) in enumerate(RAMPS.items()):
        y = 6 + i * (sw + 3)
        text(cv, name, 6, y + sw // 2 - 2, UI_TEXT)
        for j, c in enumerate(ramp):
            cv.put(rect(w, h, 72 + j * (sw + 1), y, 72 + j * (sw + 1) + sw - 1, y + sw - 1), c)
    return cv


def sprite_sheet():
    W, H = 560, 350
    cv = Canvas(W, H)
    cv.rgb[:] = dune_sea(W, H, seed=11) * 0.55 + rgb(SAND[2]) * 0.45  # calm backdrop
    cv.a[:] = 1

    def put(spr, cx, cy, name="", shadow=(2, 3)):
        x, y = cx - spr.w // 2, cy - spr.h // 2
        if shadow:
            cast_shadow(cv, spr, x, y, *shadow, strength=0.4)
        paste(cv, spr, x, y)
        if name:
            label(cv, name, cx, cy + spr.h // 2 + 6)

    def heading(s, x0, x1, y):
        text(cv, s, x0, y, UI_TEXT, OUTLINE)
        cv.put(rect(W, H, x0, y + 7, x1, y + 7), OUTLINE)

    heading("VEHICLES: THE RIG GROWS", 10, 240, 8)
    put(buggy("red"), 40, 62, "STARTER BUGGY")
    put(buggy("magenta", gun_angle=0.6, seed=4), 110, 62, "RIVAL")
    cab, tr = war_rig_cab("red", aim=(0.5,)), war_rig_trailer("red", aim=(-0.7, 0.8, math.pi))
    rig = Canvas(54, 162)
    paste(rig, tr, 1, 70)
    paste(rig, cab, 3, 0)
    cast_shadow(cv, rig, 170, 22, 4, 5, 0.4)
    paste(cv, rig, 170, 22)
    label(cv, "WAR RIG + TRAILER", 197, 190)

    heading("ALIENS: AT REST (CAMOUFLAGED) VS ACTIVE (GLOWING)", 262, W - 10, 8)
    put(sand_mite(False, seed=1), 280, 42)
    put(sand_mite(True, seed=1), 300, 42)
    label(cv, "SAND MITE", 290, 56)
    put(boulder_back(False, seed=7), 360, 52)
    put(boulder_back(True, seed=7), 410, 52)
    label(cv, "BOULDER BACK", 385, 80)
    put(spitter(False), 470, 50)
    put(spitter(True), 500, 50)
    label(cv, "SPITTER", 485, 72)
    put(glass_wing(False), 300, 112)
    put(glass_wing(True), 345, 112)
    label(cv, "GLASS WING", 322, 133)
    put(dune_worm(), 450, 124, "DUNE WORM", shadow=None)

    heading("MUTATIONS", 262, W - 10, 166)
    put(boulder_back(True, hardened=True, seed=9), 300, 202, "HARDENED")
    put(sand_mite(True, seed=3, volatile=True), 370, 198, "VOLATILE")
    put(sand_mite(True, seed=4).rot90(-1), 420, 198, "")
    put(sand_mite(True, seed=5).rot90(2), 440, 198, "")
    label(cv, "4-WAY FACING", 430, 208)

    heading("PROPS: NOT EVERY ROCK IS A ROCK", 10, W - 10, 236)
    put(rock_cluster(3, 1.1), 50, 286, "ROCKS")
    put(boulder_back(False, seed=12), 116, 286, "...OR NOT?")
    put(ribcage(2), 220, 286, "GIANT BONES")
    put(hull_plate(1), 360, 286, "COLONY SHIP HULL")
    put(rock_cluster(8, 0.9), 470, 280)
    put(boulder_back(False, seed=31).rot90(1), 520, 290)
    label(cv, "SPOT THE ALIEN", 495, 316)
    return cv


def biome_sheet():
    tw, th, gap = 150, 96, 6
    W = 3 * tw + 4 * gap
    H = 2 * (th + 14) + 2 * gap
    cv = Canvas(W, H)
    cv.put(rect(W, H, 0, 0, W - 1, H - 1), UI_PLATE[0])
    for i, (name, fn) in enumerate(BIOMES.items()):
        x = gap + (i % 3) * (tw + gap)
        y = gap + (i // 3) * (th + 14 + gap)
        cv.rgb[y:y + th, x:x + tw] = fn(tw, th, seed=5 + i)
        label(cv, name, x + tw // 2, y + th + 4)
    return cv


def rig_sheet():
    """The layered rig (rig.py): eight builds, one per paint, facing north and turned."""
    import rig
    tile = 128
    W, H = tile * 8, tile * 2 + 24
    cv = Canvas(W, H)
    cv.rgb[:] = dune_sea(W, H, seed=11) * 0.55 + rgb(SAND[2]) * 0.45
    cv.a[:] = 1
    text(cv, "THE RIG GROWS: BUGGY, PICKUP, TRUCK, WAR RIG + BOLT-ON LAYERS PER CARD AND TECH", 6, 4, UI_TEXT, OUTLINE)
    for i, (name, b) in enumerate(rig.SAMPLE_BUILDS):
        for j, ang in enumerate((0.0, 2.4)):
            r = rig.compose(b, ang, aim=ang + 0.6, size=tile)
            cast_shadow(cv, r, i * tile, 14 + j * tile, 3, 4, strength=0.4)
            paste(cv, r, i * tile, 14 + j * tile)
        label(cv, name, i * tile + tile // 2, H - 9)
    return cv


def alien_preview(seed=21):
    """Bosses and late species (aliens.py) at game scale on the Dune Sea, next to mites, boulders and
    spitters, built exactly like the exported frames (RotSprite + outline, additive glow, drop shadows)."""
    import aliens
    import export_assets as E
    from sprites import boulder_back
    W, H = 640, 360
    cv = Canvas(W, H)
    cv.rgb[:] = dune_sea(W, H, seed)
    cv.a[:] = 1
    glows = []

    def frame(spr, ang, size):
        with E.no_outline():
            base = spr() if callable(spr) else spr
        f = E.rotsprite(base, ang, size)
        E.outline(f, OUTLINE)
        return f

    def put(f, cx, cy, sh=(2, 3), strength=0.45, glow=None, name=""):
        x, y = cx - f.w // 2, cy - f.h // 2
        if sh:
            cast_shadow(cv, f, x, y, *sh, strength=strength)
        paste(cv, f, x, y)
        if glow:
            glows.append((E.glow_of(f, **glow), x, y))
        if name:
            label(cv, name, cx, cy + f.h // 2 - 4)

    def decal(d, cx, cy):
        paste(cv, d, cx - d.w // 2, cy - d.h // 2)

    rng = np.random.default_rng(seed)
    # carcass decals first (they lie on the ground)
    decal(aliens.carcass_tripod(seed=1), 70, 300)
    decal(aliens.carcass_colossus(seed=1), 600, 300)
    for i, (fn, x, y) in enumerate([(aliens.carcass_shard, 420, 214), (aliens.carcass_wings, 200, 330),
                                    (aliens.carcass_brood, 300, 330), (aliens.carcass_shrieker, 520, 340),
                                    (aliens.carcass_brood, 160, 230), (aliens.carcass_shard, 560, 230)]):
        decal(fn(seed=i * 7 + 1), x, y)
    from export_assets import carcass
    for i in range(6):
        decal(carcass(i), rng.uniform(220, 420), rng.uniform(260, 350))

    # Tripod Queen shelling a spot to the right: telegraph on the ground, a round in flight
    tele = aliens.tripod_telegraph(3)  # normal alpha blend: additive cyan turns green on orange sand
    paste(cv, tele, 262 - tele.w // 2, 150 - tele.h // 2)
    put(frame(lambda: aliens.tripod_queen("walk1"), 0.35, aliens.TRIPOD_FRAME), 92, 92, sh=(8, 11),
        strength=0.5, glow={"radius": 3, "gain": 1.8, "strength": 0.45}, name="TRIPOD QUEEN")
    put(frame(lambda: aliens.tripod_queen("aim"), 0.0, aliens.TRIPOD_FRAME), 92, 232, sh=(8, 11),
        strength=0.5, glow={"radius": 3, "gain": 1.8, "strength": 0.45}, name="AIM")
    shell = aliens.tripod_shell(1.9)
    put(shell, 222, 132, sh=(5, 12), strength=0.35, glow={"radius": 2, "gain": 2.5, "strength": 0.45})

    # Shard Colossus winding up, shards in a ring, minions
    put(frame(lambda: aliens.shard_colossus("windup1"), -0.3, aliens.COLOSSUS_FRAME), 520, 92, sh=(6, 9),
        strength=0.5, glow={"radius": 3, "gain": 1.8, "strength": 0.45}, name="SHARD COLOSSUS")
    put(frame(lambda: aliens.shard_colossus("walk1"), 3.4, aliens.COLOSSUS_FRAME), 400, 70, sh=(6, 9),
        strength=0.5, glow={"radius": 3, "gain": 1.8, "strength": 0.45})
    for k in range(10):
        a = k * 2 * math.pi / 10 + 0.2
        x, y = 520 + math.sin(a) * 58, 92 - math.cos(a) * 52
        if 0 < y < H:
            put(aliens.crystal_shard(a), int(x), int(y), sh=None,
                glow={"radius": 2, "gain": 2.5, "strength": 0.45})
    for k, (x, y, a) in enumerate([(440, 180, -1.8), (470, 205, -1.2), (600, 190, 2.6)]):
        put(frame(lambda k=k: aliens.shard_minion(f"walk{k % 2}"), a, aliens.SHARD_FRAME), x, y,
            glow={"radius": 2, "gain": 2.0, "strength": 0.4}, name="SHARD" if k == 0 else "")

    # the old crowd for scale: mites, a boulder, a spitter
    for k in range(14):
        x, y = rng.uniform(220, 400), rng.uniform(170, 260)
        put(frame(lambda k=k: sand_mite(True, seed=k % 2 + 1), rng.uniform(0, 6.3), 32), int(x), int(y),
            sh=(1, 2), glow={"radius": 1, "gain": 3.0, "strength": 0.35})
    put(frame(lambda: boulder_back(True, seed=7), 0.5, 64), 360, 300, sh=(4, 6), strength=0.6,
        glow={"radius": 2, "gain": 1.6, "strength": 0.3}, name="BOULDER")
    put(frame(lambda: spitter(True, seed=11), -0.6, 48), 250, 296, glow={"radius": 2, "gain": 2.0, "strength": 0.4},
        name="SPITTER")

    # Brood Carriers: pulsing, and one bursting into mites
    for k, (x, y, a, row) in enumerate([(190, 190, 0.9, "pulse0"), (300, 140, 2.2, "pulse2"), (175, 285, -0.4, "burst")]):
        put(frame(lambda row=row: aliens.brood_carrier(row), a, aliens.BROOD_FRAME), x, y,
            glow={"radius": 2, "gain": 2.0, "strength": 0.4}, name="BROOD" if k == 0 else "")
    # Shriekers at the back: one idle, one shrieking with its buff ring
    ring = aliens.shrieker_ring(3)
    glows.append((ring, 470 - ring.w // 2, 280 - ring.h // 2))
    put(frame(lambda: aliens.shrieker("shriek"), 0.4, aliens.SHRIEKER_FRAME), 470, 280,
        glow={"radius": 2, "gain": 2.0, "strength": 0.4}, name="SHRIEKER")
    put(frame(lambda: aliens.shrieker("idle"), -0.7, aliens.SHRIEKER_FRAME), 540, 262,
        glow={"radius": 2, "gain": 2.0, "strength": 0.4})

    # Glass Wings flying over everything: shadow far below-right
    for k, (x, y, a) in enumerate([(300, 40, 1.2), (330, 28, 1.4), (322, 58, 1.0), (590, 245, -2.2)]):
        f = frame(lambda k=k: aliens.glass_wings(f"flap{k % 4}"), a, aliens.WING_FRAME)
        shd = aliens.soft_shadow(f)
        sx, sy = x - f.w // 2 + 7, y - f.h // 2 + 12
        for yy in range(shd.h):
            for xx in range(shd.w):
                if shd.a[yy, xx] > 0 and 0 <= sy + yy < H and 0 <= sx + xx < W:
                    al = shd.a[yy, xx]
                    cv.rgb[sy + yy, sx + xx] = cv.rgb[sy + yy, sx + xx] * (1 - al) + shd.rgb[yy, xx] * al
        put(f, x, y, sh=None, glow={"radius": 1, "gain": 2.5, "strength": 0.35}, name="GLASS WINGS" if k == 2 else "")

    for g, x, y in glows:  # additive glow pass, as the game draws the *_glow sheets
        for yy in range(g.h):
            ty = y + yy
            if not 0 <= ty < H:
                continue
            x0, x1 = max(0, x), min(W, x + g.w)
            if x0 >= x1:
                continue
            cv.rgb[ty, x0:x1] += g.rgb[yy, x0 - x:x1 - x] * g.a[yy, x0 - x:x1 - x, None]
    cv.rgb[:] = np.clip(cv.rgb, 0, 255)
    return cv


def alien_frames():
    """Every animation row of the new aliens (facing north and turned 45 degrees), 2x, for render wiring."""
    import aliens
    import export_assets as E
    groups = [("TRIPOD QUEEN", aliens.tripod_queen, aliens.TRIPOD_ROWS, aliens.TRIPOD_FRAME),
              ("SHARD COLOSSUS", aliens.shard_colossus, aliens.COLOSSUS_ROWS, aliens.COLOSSUS_FRAME),
              ("SHARD", aliens.shard_minion, aliens.SHARD_ROWS, aliens.SHARD_FRAME),
              ("GLASS WINGS", aliens.glass_wings, aliens.WING_ROWS, aliens.WING_FRAME),
              ("BROOD CARRIER", aliens.brood_carrier, aliens.BROOD_ROWS, aliens.BROOD_FRAME),
              ("SHRIEKER", aliens.shrieker, aliens.SHRIEKER_ROWS, aliens.SHRIEKER_FRAME)]
    W = 8 + max(len(rows) * (fr + 4) for _, _, rows, fr in groups)
    H = sum(2 * fr + 22 for *_, fr in groups) + 8
    cv = Canvas(W, H)
    cv.rgb[:] = dune_sea(W, H, seed=11) * 0.55 + rgb(SAND[2]) * 0.45
    cv.a[:] = 1
    y = 6
    for name, fn, rows, fr in groups:
        text(cv, name, 6, y, UI_TEXT, OUTLINE)
        for i, r in enumerate(rows):
            for j, ang in enumerate((0.0, math.pi / 4)):
                with E.no_outline():
                    base = fn(r)
                f = E.rotsprite(base, ang, fr)
                E.outline(f, OUTLINE)
                paste(cv, f, 6 + i * (fr + 4), y + 8 + j * fr)
            label(cv, r.upper(), 6 + i * (fr + 4) + fr // 2, y + 10 + 2 * fr)
        y += 2 * fr + 22
    return cv


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--export-game-assets", action="store_true",
                    help="write 1x game sprites to game/assets/ instead of the samples")
    args = ap.parse_args()
    if args.export_game_assets:
        import export_assets
        export_assets.export()
        return
    os.makedirs(OUT, exist_ok=True)
    s = args.scale

    palette_sheet().to_image(s).save(os.path.join(OUT, "palette.png"))
    sprite_sheet().to_image(s).save(os.path.join(OUT, "sprites.png"))
    biome_sheet().to_image(s).save(os.path.join(OUT, "biomes.png"))
    rig_sheet().to_image(s).save(os.path.join(OUT, "rigs.png"))
    al = alien_preview()  # game scale (1x) on top, the same scene zoomed 3x below
    pv = Canvas(al.w * 3, al.h * 4 + 12)
    pv.put(rect(pv.w, pv.h, 0, 0, pv.w - 1, pv.h - 1), UI_PLATE[0])
    paste(pv, al, 0, 0)
    text(pv, "GAME SCALE (1X)  -  BELOW: 3X ZOOM", al.w + 12, 8, UI_TEXT)
    z = Canvas(al.w * 3, al.h * 3)
    z.rgb = np.repeat(np.repeat(al.rgb, 3, 0), 3, 1)
    z.a[:] = 1
    paste(pv, z, 0, al.h + 12)
    pv.to_image(1).save(os.path.join(OUT, "aliens_preview.png"))
    alien_frames().to_image(2).save(os.path.join(OUT, "aliens_frames.png"))
    sc = scene.build()
    scene.finish(scene.render_day(sc)).to_image(s).save(os.path.join(OUT, "mockup_day.png"))
    scene.finish(scene.render_night(sc)).to_image(s).save(os.path.join(OUT, "mockup_night.png"))
    scene.finish(scene.render_day(sc)).to_image(1).save(os.path.join(OUT, "mockup_day_1x.png"))
    print("wrote samples to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
