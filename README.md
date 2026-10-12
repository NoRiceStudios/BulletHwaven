# BulletHwaven

A multiplayer **PvPvE auto-battler survivor**. AI-driven, scrap-welded war rigs fight alien hordes, and each other, on a desert planet. Steer the battle through roguelike upgrade drafts, a tech tree and **AI doctrine**: the last convoy standing wins.

> Status: pre-production. The game design and art direction are drafted, and sample art exists. Engine and tech stack are not chosen yet.

| Day | Night |
|---|---|
| ![Day mock-up](art/samples/mockup_day.png) | ![Night mock-up](art/samples/mockup_night.png) |

## Repository layout

| Path | What's in it |
|---|---|
| [`docs/game-design.md`](docs/game-design.md) | Game design document: core loop, vehicle grid, draft and tech tree, AI doctrine, enemy variety, PvP, meta progression, art direction |
| [`art/samples/`](art/samples/) | Art-style samples: mock-up screenshots (day/night), sprite sheet, biome tiles, palette |
| [`tools/artgen/`](tools/artgen/) | Python generator that draws the sample art procedurally from the master palette |

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
