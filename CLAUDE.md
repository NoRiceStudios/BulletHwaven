# BulletHwaven: notes for Claude

- `docs/game-design.md` is the source of truth for gameplay and art direction. Update it when design decisions change, and keep section numbers and cross-references ("section 7d") consistent.
- `docs/architecture.md` is the binding tech contract: Godot 4.7.2, typed GDScript, layer rules (`sim/` is pure and deterministic; `render/` only reads; `net/` is host-authoritative) and the sim/net APIs. Keep it in sync with the code.
- Godot is installed by the SessionStart hook (`scripts/setup-godot.sh`) to `~/.local/bin/godot`. There is no GPU: use `--headless` for logic, and `scripts/shot.sh` (Xvfb plus software OpenGL) for screenshots.
- Before committing game code, run `scripts/test.sh` (headless tests) and, for visual changes, `scripts/shot.sh` and look at the result.

## Working style (requested by the user)

- Be mindful of token usage. Delegate routine work (logic, networking, tests, refactors, docs) to cheaper models via subagents (`model: "sonnet"`, or `"haiku"` for trivial tasks), with tight prompts that point at `docs/architecture.md` instead of restating it.
- Visual work (art, sprites, rendering, VFX, UI look, screenshot review) is always handled by Opus on high effort (`model: "opus"`, `effort: "high"`).

## Art direction rules (enforced in `tools/artgen/palette.py`)

- Top-down view, detailed but rough pixel art, light from the top-left, 1px dark outline (`OUTLINE`).
- The environment and aliens at rest use warm, desaturated desert ramps; aliens are camouflaged.
- Bioluminescent cyan (`GLOW`) is the only cold saturated colour: active aliens and alien projectiles.
- Player projectiles, muzzle flashes and fire are always warm (`FIRE`); players are marked by paint colour (`PLAYERS`).
- No repeating patterns on the ground; vehicles look scrap-built (see design doc 11b).
- Art generator: `python tools/artgen/generate.py` writes to `art/samples/` (`--export-game-assets` writes game sprites to `game/assets/`). Modules: `palette.py`, `pixel.py`, `sprites.py`, `terrain.py`, `scene.py`. After changing it, regenerate and look at the output before committing.
