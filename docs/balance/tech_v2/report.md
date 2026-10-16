# Tech tree v2.3: bot league check

Design section 12 says the paper numbers must be checked with the bot league before they are final. This report is that check. Raw data is not committed (`scripts/bot-league.sh --out <dir>`); the numbers below come from runs on the sim as of this commit, 20 round cap, real round timings.

## Bots

New policies in `game/tools/bots.gd` (ammo is auto-loaded by the sim, abilities auto-cast, contracts are accepted, bots never respec):

| Policy | Tech path | Cards / driving |
|---|---|---|
| `tpl_firebrand` | ballistics + propulsion (the FIREBRAND plan, to Glowing Barrels / Phantom Drive) | damage cards, circle |
| `tpl_fortress` | engineering + electronics (FORTRESS plan) | balanced cards, circle |
| `tpl_scrapper` | salvage + ballistics (SCRAPPER plan); sells junk cards to the scrap press | balanced cards, circle |
| `tpl_rammer` | propulsion + engineering to War Machine, Juggernaut, Truck | armour / speed cards, never takes a weapon, charge |
| `tpl_rammer_hunt` | as `tpl_rammer`, targets rivals (`players_first`) | PvP stress test |
| `tpl_press_abuse` | SCRAPPER path, sells every card it can | stress test of the scrap press |
| `probe_<choice id>`, `base_<branch>` | one branch straight to its keystone, one choice swapped | damage cards; node-strength comparison |

The league report gained a "Keystone timing" table (round of the first stage 5 / stage 6 purchase).

## Findings against the design targets

Runs: A = 8 policies x 12 solo seeds + 60 ffa matches (before tuning), B = same with the tuning (plus `tpl_rammer_hunt`), C = 31 probe policies x 8 solo seeds. Scores are rounds survived (capped runs add remaining fuel / 100, cap 20). Seed counts are modest: one standard error of a 12-seed mean is about 1.2 rounds.

**Keystone around round 9-10 for a focused player: met.** One branch straight to its keystone (2,130 scrap): ballistics round 10.0, electronics 10.6, engineering 10.8, salvage 9.5, propulsion 12.4 (stage 5 at round 7.5-8.9, keystone 1.5-3.5 rounds later; propulsion is slower because its nodes add little damage, so the rig earns less). Two-branch plans reach their first keystone later, as designed: scrapper round 12.3, rammer 13.4, firebrand 14.1, FORTRESS 16.2, `balanced` 15.2.

**No template dominates: met after one fix.**

| Template | Solo score A (before) | Solo score B (after) | FFA avg place B (1 = best) |
|---|---|---|---|
| tpl_firebrand | 18.9 | 20.6 | 3.07 |
| tpl_fortress | 13.8 | 18.3 | 2.79 |
| tpl_scrapper | 18.1 | 18.1 | 1.79 |
| tpl_rammer | 17.4 | 17.4 | 2.22 |
| balanced (reference) | 20.7 | 20.9 | 1.59 |

FORTRESS was the clear outlier (13.8, only 8% survived to the cap, 83% of its losses to boulders: its first seven purchases bring no damage). After the fix all four templates sit in a 17-21 band. Solo scores saturate at the cap for good builds, so FFA is the second check: with nine policies in the pool the best template wins 7% of ffa matches (fair share 11%), nobody wins more than 9%.

**Rammer must not dominate: met.** Without any weapon card it scores 17.4 solo (below `balanced` 20.9; it earns 178 scrap per round against 316), has 0 ffa wins in 27 appearances (avg place 2.22) and the PvP variant that hunts rivals is the worst non-stress policy (avg place 3.52, out at round 11.9 on average: charging into rivals costs it its own lives). The persona fear (Battering Ram +60%) is covered by the v2.3 numbers (+45%, War Machine shockwave 1 s per target, 40 momentum). A first look at 4 seeds suggested 20.6, which the larger run did not confirm.

**Salvage is not a trap: met, with a caveat.** The SCRAPPER plan earns the most scrap per round of all (332 against `balanced` 316) and scores 18.1 solo (avg ffa place 1.79, second after `balanced`). Salvage alone is weak: the single-branch probes score 12-13 for every salvage choice against 17-19 for ballistics, engineering and propulsion, because the stage 4-6 salvage nodes are economy or PvP effects (loan, raider, bounty office have no solo value) and a bot cannot turn the scrap into power without a second branch. That is the intended role (pair with a weapon branch), but the Salvage keystones depend on a PvP-capable second branch to look good.

**The scrap press is not an infinite scrap source: met.** `tpl_press_abuse` (sells every card the moment the press exists) scores 8.5 and earns 135 scrap per round, less than half of the SCRAPPER bot that only sells junk (332): selling gives 50 x level per card and the card is gone, and the cards are the power. At most one pick per round feeds it (about 50-150 scrap per round). Scrap Storm (+1 scrap, 40 per round) and Barbed Wire (+3, 45 per round) are capped by design; neither lifts income visibly (SCRAPPER with Scrap Storm: 332 per round, `balanced`: 316).

**Tech lifts show no node far above or below its siblings.** Probe scores (8 seeds, mean of rounds, higher is better; the same branch path with one choice swapped):

| Stage | Choices (score) |
|---|---|
| Ballistics 2 / 4 / 5 / 6 | Belt Feed 16.8 vs Heavy Shells 18.9; Napalm 16.8, Scatter 18.8, HE 19.4; Tungsten 16.8 vs Mixed Belts 15.2; Glowing 16.8 vs One Shot 18.7 |
| Engineering 2 / 4 / 5 / 6 | Welder 17.1 vs Spikes 15.5; Drone 17.1, Reactive 18.8, Dozer 16.9; Truck 17.1 vs Roll Cage 19.4; War Rig 17.1 vs Featherweight 18.4 |
| Propulsion 2 / 4 / 5 / 6 | Bumper 17.5 vs Drift 13.6 (see tuning); Battering 17.5, Ghost 18.0, Slipstream 19.8; Turbine 17.5 vs Sidecar 16.4; Juggernaut 17.5 vs Phantom 17.2 |
| Electronics 2 / 4 / 5 / 6 | Relay 14.4 vs Radar 13.6; Hunter 14.4, EMP 14.1, Smoke 16.8; Overclock 14.4 vs Neural 13.9; Swarm 14.4 vs Jammer 15.9 |
| Salvage 2 / 4 / 5 / 6 | Lucky 12.6, Haggler 12.2, Loan 12.2; Hoarder 12.6, Jerrycans 12.9, Press 12.4; Crane 12.6 vs Bounty 12.1; Baron 12.6 vs Raider 12.2 |

Spreads inside a stage are within about 2 rounds (one to two standard errors) except Drift Tuning; electronics and salvage trail the others as whole branches because the bots write no doctrine rules and have no PvP use for the Salvage nodes (see risks). The random-policy lift tables of the standard report are dominated by stage 1 and 2 nodes (the random policy never reaches stage 4+), so they were not usable for the deep nodes; the probes replace them.

## Tuning

Small constant changes in `game/sim/tech.gd`, one problem at a time:

| Change | Reason | Before | After |
|---|---|---|---|
| Field Welder regen 2 to 3 hp/s | FORTRESS outlier | FORTRESS 13.8 (n=12) | with the three following: 15.7 (n=24) |
| Fire Control Relay rate +8% to +15% | same | | 15.7 (n=24) |
| Rangefinder +8% damage, Targeting Computer +8% damage | FORTRESS has no damage in its first seven purchases | 15.7 | 18.0 (n=24), 18.3 in run B |
| Drift Tuning +5% speed (turn +25% unchanged) | 2.1 rounds below Ram Bumper at 24 seeds (15.7 against 17.8) | 15.7 | 18.0 (n=24) |

Side effect: the drift change also lifts FIREBRAND (18.9 to 20.6), which now matches `balanced`; its ffa average place stays mid-table (3.07), so it was left there.

## Remaining risks

- Seed counts are modest (12 solo seeds per policy in the template runs, 8 in the probes, 60 ffa matches); differences below about 2 rounds are noise, ffa win rates of single policies are too noisy to rank (about 25 appearances each).
- Bots write no doctrine rules, never switch ammo by rule, never respec and never read the laser or focus-fire conditions, so Electronics and the Relay / Neural / Swarm nodes are probably worth more to a human than the league shows, and Salvage PvP nodes (Raider, Bounty Office, Baron on the loot side) are untested. A PvP-aware bot pair for those would be the next step.
- Keystone timing for two-branch plans (12-16) is later than the 9-10 of a one-branch rush; if playtests find it too slow, lower the stage 5 and 6 costs (520 / 750) before touching effects.
- The solo score saturates at the cap for good builds; a time-to-clear or damage-taken metric would separate the top policies better.
- Slipstream (19.8) and Roll Cage (19.4) scored the highest of the probes; both are defensive or control effects that a bot uses perfectly and are inside the noise, but worth a look in human playtests.
