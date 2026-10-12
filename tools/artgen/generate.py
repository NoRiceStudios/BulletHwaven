"""Render the BulletHwaven art-style samples into art/samples/.

Usage:  python tools/artgen/generate.py [--scale 3]
        python tools/artgen/generate.py --export-game-assets   (1x sprites into game/assets/)
"""

import argparse
import math
import os

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
    tile = 104
    W, H = tile * 8, tile * 2 + 24
    cv = Canvas(W, H)
    cv.rgb[:] = dune_sea(W, H, seed=11) * 0.55 + rgb(SAND[2]) * 0.45
    cv.a[:] = 1
    text(cv, "THE RIG GROWS: HULL + BOLT-ON LAYERS PER CARD AND ENGINEERING TIER", 6, 4, UI_TEXT, OUTLINE)
    for i, (name, b) in enumerate(rig.SAMPLE_BUILDS):
        for j, ang in enumerate((0.0, 2.4)):
            r = rig.compose(b, ang, aim=ang + 0.6, size=tile)
            cast_shadow(cv, r, i * tile, 14 + j * tile, 3, 4, strength=0.4)
            paste(cv, r, i * tile, 14 + j * tile)
        label(cv, name, i * tile + tile // 2, H - 9)
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
    sc = scene.build()
    scene.finish(scene.render_day(sc)).to_image(s).save(os.path.join(OUT, "mockup_day.png"))
    scene.finish(scene.render_night(sc)).to_image(s).save(os.path.join(OUT, "mockup_night.png"))
    scene.finish(scene.render_day(sc)).to_image(1).save(os.path.join(OUT, "mockup_day_1x.png"))
    print("wrote samples to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
