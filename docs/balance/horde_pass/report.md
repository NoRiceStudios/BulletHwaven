# Horde pass: balance regression and fix

League settings for every column: `scripts/bot-league.sh --solo-seeds 4 --ffa-matches 20 --random-seeds 40` (round cap 20). The confirmation column used `--solo-seeds 8 --ffa-matches 40`. Numbers are mean rounds survived (score) unless noted; with 4 seeds a single bad run moves a mean by about 1 round, so treat differences under 1.5 as noise.

- **Before** = frozen copy of the commit before PR #9 (`aee0d4a^1`).
- **After PR 9** = `aee0d4a` (merge of PR #9), no bosses.
- **After fix** = this branch, which also contains the boss rounds merge.

| metric | before (pre-PR 9) | after PR 9 | after fix (reduced) | after fix (confirmation, 8 solo seeds / 40 ffa) |
|---|---|---|---|---|
| balanced | 20.8 | 17.4 (one bad seed; 20.8 median) | 20.9 | 20.9 |
| tank | 16.4 | 13.8 | 20.6 | 20.5 |
| speedster | 20.1 | 16.2 | 17.5 | 18.3 |
| turtle | 20.5 | 19.4 | 20.4 | 20.3 |
| greedy_damage | 20.8 | 20.8 | 20.9 | 20.9 |
| random (40 seeds) | 10.1 | 8.8 | 10.1 | 10.1 |
| never_upgrade | 6.8 | 5.5 | 6.8 | 6.6 |
| dominant solo policies (> balanced + 1.5) | none | 8 (the balanced one dropped) | none | none |
| balanced scrap earned per run | 11181 | 9406 | 12717 (+13.7 %) | 12788 (+14.4 %) |
| FFA decided before the cap | 25 % | 20 % (caller's run: 0 %) | 80 % | 70 % |

The "after PR 9" run with 4 seeds is noisy (balanced median was 20.8, mean 17.4); a separate 8-seed run of the same code is not stored, so tank/speedster there are indicative only.

## Diagnosis

1. **Boulders scale with the spawn rate.** The boulder roll is per spawn event, and PR 9 raised the spawn rate about 3.5x at round 10 (base 3.0 instead of 1.5, 0.35 instead of 0.15 per round, surges x2.2 / x2.8). The alive cap (8 + 3r) was unchanged, so the boulder cap was reached much sooner and boulders were ~75-90 % of vehicle losses for every low-damage build. Tank and speedster have few kills, so they cannot thin boulders.
2. **Armour no longer matters against mites.** Mite contact (0.15 per tick) was already at the 25 % armour floor, so armour only helps against boulders, which got more frequent. I tested `CONTACT_ARMOR_FACTOR` 0.12: tank went to 20.6 while speedster did not move, so it was reverted to 0.08 (kept as the original).
3. **Mites are as fast as a kiting rig.** Mite speed 90 versus `SPEED_KITE` 96: packs catch a kiting rig whenever it turns, and the speed cards (+10 to +30 %) were wasted. Slower mites helped speedster and tank at once.
4. **FFA stalls.** Fewer deaths (easier alien phase, bots rarely hunt each other), and the fuel drain never eliminates by itself (floor 1), so 5-player-free-for-all matches ran to the cap.
5. The `WAVE_BUILD_FROM 0.5 -> 0.8` tweak was included in every "after" measurement here (no regression found).

## Changes

| constant | old | new |
|---|---|---|
| `BOULDER_CHANCE` | 0.04 | 0.02 |
| `BOULDER_CHANCE_PER_ROUND` | 0.03 | 0.013 |
| `BOULDER_CHANCE_MAX` | 0.4 | 0.2 |
| `ENEMY_SPEED[MITE]` | 90 | 74 |
| `MITE_SCRAP_START` | 0.22 | 0.19 (keeps balanced scrap within +15 %) |
| `FUEL_DRAIN_START_ROUND` / `FUEL_DRAIN_BASE` | 8 / 5 | 7 / 6 |
| `FUEL_DRAIN_LETHAL_ROUND` (new) | none | 18: from the workshop after round 18 the drain can eliminate every rig except the one with the most fuel (first on ties) |

Tests: `test_fuel_drain_from_round_seven_multiplayer_only` updated, `test_lethal_drain_spares_only_the_fuel_leader` added, `test_net.gd::test_snapshot_size` bound raised from 9.0 to 9.2 bytes per enemy (the fixed snapshot part grew with the boss merge, the result sat at 9.015 bytes).

## Notes and caveats

- Tank (20.5) is now clearly above its pre-PR-9 value of 16.4 (still not dominant: it is below balanced). Cause: boulders and slower mites help every armour build more than they hurt. Pulling the boulder chance back up would hurt speedster, which is the weaker archetype. A later pass could remove the tank bonus via `CONTACT_ARMOR_FACTOR` or the tank policy's card weights.
- Speedster is 1.8 rounds below its pre-PR-9 value in the confirmation run (3 in the reduced run); it still earns little scrap (2378 per run), kills about half as much as balanced.
- FFA decided-before-cap is 70-80 % (target >= 20 %, was 25 %). That is more decisive than before; `FUEL_DRAIN_LETHAL_ROUND` 20 would soften it.
- The weak build (never_upgrade) is back at 6.6-6.8 rounds (pre-PR-9: 6.8).
