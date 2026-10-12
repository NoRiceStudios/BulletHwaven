# Playtest round 2: summary

The personas played the build at commit `cbf67de` (iteration 1: sim fixes, growing rigs, recap, kill feed, scouting, spectator mode, awards) on the same seeds as round 1. Full reports are in `mia.md`, `jonas.md` and `sam.md`.

| Criterion | Mia | Jonas | Sam | Avg R2 | Avg R1 | Δ |
|---|---|---|---|---|---|---|
| Onboarding | 7 | 7 | 8 | 7.3 | 6.3 | +1.0 |
| Visual appeal | 8 | 8 | 8 | 8.0 | 8.0 | ±0 |
| Combat readability | 7 | 7 | 7 | 7.0 | 4.7 | **+2.3** |
| Sense of agency | 6 | 9 | 6 | 7.0 | 6.7 | +0.3 |
| Upgrade choices | 6 | 6 | 7 | 6.3 | 5.0 | +1.3 |
| Progression / power fantasy | 5 | 7 | 5 | 5.7 | 5.0 | +0.7 |
| Difficulty / pacing | 4 | 6 | 5 | 5.0 | 4.7 | +0.3 |
| Depth / balance | 5 | 6 | 4 | 5.0 | 4.7 | +0.3 |
| PvP / multiplayer | 3* | 7 | 6 | 5.3 | 4.7 | +0.7 |
| UI / UX | 8 | 7 | 8 | 7.7 | 6.7 | +1.0 |
| One more run | 6 | 7 | 7 | 6.7 | 6.3 | +0.3 |
| Technical quality | 8 | 8 | 8 | 8.0 | 8.0 | ±0 |
| **Average** | 6.1 (5.2) | 7.1 (5.9) | 6.6 (6.6) | **6.6** | **5.9** | **+0.7** |

\* Solo only.

## What worked
- **Readability (+2.3):** boulder rims, acid trails, HP numbers, the low-HP vignette and the death recap were all named.
- **Spectator mode, awards, the PVP ON banner, the bounty skull and the debrief** (Sam).
- **Passive play no longer wins** (Jonas): a full turtle line loses on fuel drain by round 14.
- **Mia kills 40% more aliens** on the same seed.

## Remaining issues → iteration 2 plan

| # | Issue (who) | Proposed fix | Owner |
|---|---|---|---|
| 1 | Most deaths still happen in a round's last ~15 s with 80–130 aliens alive, and nothing really counters boulders (Mia, Sam) | Boulders telegraph their charge; the AI dodges telegraphed charges; kite avoids corners and arena edges; the last 10 s become a "hive falls back" phase instead of peak pressure; berserker/spiked builds take far less ram damage | sim |
| 2 | Doctrine hints backfire and repeat (Mia) | Hints weigh all damage sources (never "charge" when boulders are present), stop repeating after being followed, and show expected benefit | sim + UI |
| 3 | Knockout cascade and fuel-steal snowball: half the lobby spectates for 5–6 min, two bots out by round 5 (Sam, Jonas) | Cap fuel steal per round; stronger underdog catch-up (and fix it never triggering for the newbie); bots less suicidal; consider a shorter FFA (fewer rounds / faster drain once players are out) | sim |
| 4 | Spectators can't act (Sam) | "Horde Warlord" lite (design doc 8): eliminated players spend a small budget each round to send an alien pack at a chosen rival | sim + UI |
| 5 | PvP round 4 opens with an instant 30-fuel loss from spawn proximity (Jonas) | Spread spawns at PvP start, a spawn shield, and a "PVP NEXT ROUND" warning in the workshop | sim + UI |
| 6 | Hidden information: current HP, post-tech card values, armour formula, leader rule; scouting is hover-only (Jonas) | Show HP and post-tech values on cards, armour/leader tooltips, scouting by click and keyboard | UI |
| 7 | Auto spectator camera leaves fights at the screen edge (Sam) | Frame the fight centroid | UI |

The harness can't hover, so Jonas couldn't verify the scouting dossier. A harness `--hover` option or keyboard scouting would close that gap.
