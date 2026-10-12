# BulletHwaven: notes for Claude

- `docs/game-design.md` is the source of truth for gameplay and art direction. Update it when design decisions change, and keep section numbers and cross-references ("section 7d") consistent.
- The project is in pre-production. No engine has been chosen yet, so don't scaffold engine code without asking.
- Art direction rules (enforced in `tools/artgen/palette.py`):
  - top-down view, detailed but rough pixel art, light from the top-left, 1px dark outline (`OUTLINE`)
  - environment and aliens at rest use warm, desaturated desert ramps; aliens are camouflaged
  - bioluminescent cyan (`GLOW`) is the only cold saturated colour, used for active aliens and alien projectiles
  - player projectiles, muzzle flashes and fire are always warm (`FIRE`); players are marked by paint colour (`PLAYERS`)
- Art generator: `python tools/artgen/generate.py` writes to `art/samples/`. Modules: `palette.py` (ramps), `pixel.py` (canvas, masks, ramp shading, outline, dithering, 3x5 font), `sprites.py`, `terrain.py` (biomes), `scene.py` (mock-up plus day/night render passes). After changing the generator, regenerate the samples and look at them before committing.
