## Proposed changes

Three runs with identical bots, seeds and settings (10 solo seeds per policy, 300 for `random`, 80 ffa matches, 20-round cap) are compared:

- **before**: `docs/balance/baseline/` (original numbers).
- **after**: this report (the one change that was applied, see below).
- **what-if**: `docs/balance/whatif/`, a throw-away copy of the project with the whole proposal package below (not applied; it touches `sim_world.gd` and a test).

Noise: with 10 seeds, differences below about 1 round (solo) or about 10 points of win rate (ffa) are within run-to-run noise. `balanced` moved 20.2 -> 19.4 between before and after although the shotgun is the only change (the shotgun is one of its weapons, and a card change reshuffles the random streams).

### Applied (number changes in `game/sim/cards.gd`)

| file | constant | old | new | rationale |
|---|---|---|---|---|
| `game/sim/cards.gd` | `WEAPONS["shotgun"]["damage"]` | `[3.0, 3.5, 4.0]` | `[3.5, 4.0, 4.5]` | The shotgun is the weakest weapon in every view: `focus_shotgun` scores 12.8 vs 14.5-15.0 for mg/flamer/cannon (-12 to -15%), has the worst ffa placement of the weapon specialists (avg place 3.17, 0% wins) and a random-policy lift of only +0.1 round (mg +1.2, cannon +1.0). Damage is the least intrusive lever (+17%, about 32 -> 37.5 dps at level 1 with all pellets hitting). |

Effect: `focus_shotgun` 12.8 -> 13.8 solo; ffa avg place 3.17 -> 3.08; random-policy lift +0.10 -> +0.25. Direction is right, size is near the noise floor; if the shotgun still lags in the next run, the range (150) is the next lever.

### Proposed, not applied

**Update:** rows 1 to 6 were applied in iteration 2 (see the end of `report.md`; row 6 became the PvP grace period plus return fire). Rows 7 and 8 are still open.

All figures are measured on frozen copies of the sim (exploration runs of 6 seeds, plus the what-if run above).

| # | file | constant | old | new | rationale / evidence | confidence |
|---|---|---|---|---|---|---|
| 1 | `game/sim/tech.gd` | `TIER_COSTS` | `[15, 30, 55]` | `[70, 160, 300]` | Economy: a `balanced` rig earns about 11,000 scrap over 20 rounds, finishes all 15 techs by round 4 (12 of 15 by round 3) and ends with about 10,600 unspent. Tech, rerolls and interest are therefore free. At the new prices the tree (2,650 total) is done around round 12, 7.5 techs by round 5; `tech_rush` (all-in tech) drops 18.0 -> 11.8, `saver` 11.5 -> 9.2, `balanced` 20.3 -> 16.5 (isolated 6-seed run). **Blocked:** `tests/test_rounds.gd::test_tech_changes_derived_stats` gives the vehicle `scrap = 1000` and buys 13 techs (1,960 at the new prices); change line 419 to `v.scrap = 3000`. `docs/architecture.md` ("Tech costs: 15 / 30 / 55") needs the new numbers too. | high |
| 2 | `game/sim/sim_world.gd` | `HP_SCALE_PER_ROUND` | `0.12` | `0.15` | Pacing. A decent build (`balanced`, `balanced_kite`, `greedy_damage`) reaches the 20-round cap in 50-80% of runs, far beyond the design's "about 14 rounds" (section 7j). Alone, #1 brings `balanced` to 16.5; #1 plus 0.18/0.12 was too hard (balanced 10.2). With #1 + 0.15 / 0.11 (what-if) `balanced` reaches 14.1, `random` 6.7, `never_upgrade` 5.0, nothing is capped. | medium |
| 3 | `game/sim/sim_world.gd` | `SPAWN_SCALE_PER_ROUND` | `0.10` | `0.11` | see #2 | medium |
| 4 | `game/sim/sim_world.gd` | `CONTACT_ARMOR_FACTOR` | `0.04` | `0.08` | 70-97% of vehicle losses are caused by boulders (1.5 damage per tick at the start). Armour reduces contact damage by only `0.04 x armor` per tick, so one level of Steel Plates removes 2.7% of a boulder's damage and the armour cards show no lift (steel_plates +0.4, ablative +0.4, spiked -0.3 rounds with the random policy). The `tank` policy (armour first, but with weapons) trails `balanced` by 7-8 rounds. Isolated run with 0.10: `tank` 11.2 -> 12.8. | medium |
| 5 | `game/sim/sim_world.gd` | `REROLL_COST_START` | `2` | `6` | Rerolls cost 2, 3, 4... while rigs hold thousands of scrap; bots with a reroll habit use about 3 per workshop at no real cost. Interest (+5 max) is irrelevant for the same reason. Combine with #1; the step (+1 per reroll) is hard-coded in `apply_command`. | low |
| 6 | `game/sim/vehicle_ai.gd` | `players_first` targeting (code, not a constant) | any round | ignore vehicles while `round < 4` | PvP: `pvp_hunter` (players_first + charge) wins 74% (before) to 83% (what-if) of 4-player games at 25% fair share and finishes games early (median winning round 5 to 7), because every rival loses 30 fuel (`FUEL_LOSS_PVP`) per death and the other bots never fight back. Design section 7j has rounds 1-3 without PvP. If it stays constant-only: `FUEL_LOSS_PVP` 30 -> 20 and `PVP_KILL_SCRAP` 15 -> 10 slow it but do not remove the problem. | high (problem), low (fix) |
| 7 | `game/sim/vehicle_ai.gd` | `CHARGE_RAM_DAMAGE` | `2.0` | `3.5` | The `charge` doctrine is a trap in PvE: `balanced_charge` scores 15.1 vs 20.2 (circle) and 20.4 (kite), 97% of its losses are boulders (and 0% ffa wins). Either charge needs a payoff or it is a deliberate risk option. Untested. | low |
| 8 | `game/sim/cards.gd` | `regenerator` `regen`, `steel_plates` / `reinforced_hull` / `caterpillar_tracks` `hp` | `1.5`; `40`, `80`, `30` | `3.0`; `60`, `110`, `45` | Non-weapon cards all sit within +-0.5 round of zero (random-policy lift): armour, mobility and scrap cards do not move survival. `speedster` (mobility first, with weapons) trails `balanced` by 9-10 rounds, `tank` by 7-8. A level 3 Regenerator heals 4.5 hp/s against 45 damage/s from one boulder. Untested, listed as the next experiment after #1-#4 are in. | low |

Cards that are fine as measured: `mg` and `cannon` give the strongest lift (+1.2 / +1.0) but all four single-weapon focus builds land within 13-15 (the `balanced` mix with two weapons plus tech reaches 20), so there is no weapon to nerf. `vulture` is dead in PvE (-0.8 round) but strong in PvP (ffa lift +43 points), which suits its design; `scrap_magnet` only matters once scrap is scarce (re-check after #1).
