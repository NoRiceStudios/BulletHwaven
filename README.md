# BulletHwaven

A multiplayer **PvPvE auto-battler survivor**. AI-driven, scrap-welded war rigs fight alien hordes, and each other, on a desert planet. Steer the battle through roguelike upgrade drafts, a tech tree and **AI doctrine**: the last convoy standing wins.

> Status: pre-production. The design and art direction are drafted, and a playable Godot 4 prototype exists: rounds with a workshop phase (card draft, tech tree, AI doctrine), fuel reserves and last-convoy-standing, LAN multiplayer, and headless tests (see [`docs/architecture.md`](docs/architecture.md)).

**In-game, current build:**

| Combat | Workshop (between rounds) |
|---|---|
| ![In-game combat](docs/screenshots/ingame_combat.png) | ![Workshop](docs/screenshots/ingame_workshop.png) |
| ![In-game skirmish](docs/screenshots/ingame_skirmish.png) | ![In-game horde](docs/screenshots/ingame_horde.png) |

**Art-style target:**

| Day | Night |
|---|---|
| ![Day mock-up](art/samples/mockup_day.png) | ![Night mock-up](art/samples/mockup_night.png) |

## Repository layout

| Path | What's in it |
|---|---|
| [`game/`](game/) | Godot 4.7 project: `sim/` (deterministic simulation), `net/` (LAN multiplayer), `render/`, `tools/`, `tests/` |
| [`docs/architecture.md`](docs/architecture.md) | Tech stack decision and the layer and API contract |
| [`scripts/`](scripts/) | `setup-godot.sh` (installs the pinned Godot), `test.sh`, `shot.sh`, `lan-smoke.sh`, `input-test.sh` (real X11 mouse/keyboard end-to-end test), `export.sh` (release builds) |
| [`docs/game-design.md`](docs/game-design.md) | Game design document: core loop, vehicle grid, draft and tech tree, AI doctrine, enemy variety, PvP, meta progression, art direction |
| [`art/samples/`](art/samples/) | Art-style samples: mock-up screenshots (day/night), sprite sheet, biome tiles, palette |
| [`tools/artgen/`](tools/artgen/) | Python generator that draws the sample art procedurally from the master palette |

## Running the game

Install [Godot 4.7.2](https://godotengine.org/download) (or run `scripts/setup-godot.sh` on Linux), then:

```bash
godot --path game                         # main menu: solo, host / join a LAN game, driver profile
godot --path game -- --solo               # straight into a solo game
godot --path game -- --host               # host a LAN game that starts at once (late joiners welcome)
godot --path game -- --join=192.168.1.20  # join a LAN game
godot --path game -- --fast               # short rounds (4 s combat), for quick testing
scripts/test.sh                           # headless tests
scripts/shot.sh <scenario> <seed> <ticks> out.png   # screenshot a scenario (also: menu, join, lobby, pause, rematch, waiting)
```

Or open `game/project.godot` in the Godot editor.

### Controls

- **Menu:** mouse, or arrow keys and Enter. Click the name field to type your driver name; pick one of 8 paint colours. The profile is saved to `user://profile.cfg`.
- **LAN:** *Host LAN game* opens a lobby (shown to others under *Join LAN game*, or join by IP). Players ready up; the host starts when everyone is ready, or forces the start.
- **Combat:** `1` / `2` / `3` drive circle / kite / charge; `Q` / `W` / `E` target nearest / strongest / players first.
- **Workshop:** `1` / `2` / `3` pick a card, `R` reroll, `Space` ready; click tech nodes to build.
- **Esc:** pause (solo) or the in-match menu (LAN: the match keeps running): resume or leave to the menu.
- **Game over:** `Enter` restart (solo) or rematch (host); clients wait for the host. `Esc` leaves to the menu.

## Builds

CI (`.github/workflows/ci.yml`) runs the headless tests and the LAN smoke test on every push and pull request, then exports release builds. Download them from the run's **Artifacts** section on the Actions tab (`BulletHwaven-builds`: `BulletHwaven-linux-x86_64.zip` and `BulletHwaven-windows-x86_64.zip`, kept for 14 days).

To build locally:

```bash
scripts/export.sh [linux|windows|all]   # default: all
```

It installs Godot and the matching export templates if missing (about 1 GB download, 180 MB installed), then writes `build/linux/`, `build/windows/` and the zips in `build/`. The export presets live in `game/export_presets.cfg`.

## Art-style samples

- `mockup_day.png` / `mockup_night.png`: an in-game mock-up at 640×360 native, rendered ×3 (1920×1080)
- `mockup_day_1x.png`: the same frame at native resolution, to judge the real pixel scale
- `sprites.png`: vehicles, aliens at rest vs. active, mutations, props
- `biomes.png`: the six biomes (Dune Sea, Salt Flats, Canyon, Glass Crater, Wreck Field, Spore Basin)
- `palette.png`: the master palette ramps

Regenerate them with:

```bash
pip install -r tools/artgen/requirements.txt
python tools/artgen/generate.py            # --scale N for a different upscale
```

These are **placeholder / style-target art**, generated from code to pin down the palette, the readability rules and the scale. Final art would be hand-pixelled on top of these rules.
