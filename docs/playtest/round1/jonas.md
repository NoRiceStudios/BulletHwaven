# Playtest round 1: Jonas (persona 2, "the ranked strategist")

**Run:** seed 202, FFA against `balanced`, `pvp_hunter` and `focus_cannon`, driver JONAS (colour 5).
**Main run result:** **2nd of 4**, eliminated in round 7 (FOCUS CANNON won with 10 fuel left). 7 decision points.
**Branch probe** (same seed, identical choices through workshop 5, then *one* doctrine difference): **1st of 4**, won in round 9 without dying again. 9 decision points.

**Build path (main run):**
- R1: Siege Cannon (2nd gun slot). R2: one reroll (6 scrap), then Steel Plates.
- R3: Rangefinder (electronics 1), MG L2.
- R4 (first PvP round, died twice to PVP HUNTER, fuel 100 to 40): Welded Frame (engineering 1), Ablative Scrap, drive switched to **kite**.
- R5: Bolt-on Plating (engineering 2), Vulture, target switched to **players first**.
- R6 (killed BALANCED once, traded deaths with FOCUS CANNON, fuel 10): Targeting Computer, Hardened Rounds, MG L3.
- R7: killed FOCUS CANNON once (it respawned at 10 fuel) and died to it 12 s later. Eliminated.

**Branch:** at workshop 5 I kept **target = nearest** instead of players first; everything else was the same. In round 6 I took 53 damage instead of 529 with no deaths. The bots wore each other down, and I only had to finish FOCUS CANNON at 57 s of round 9. I ended with **451 unspent scrap**.

## Scores

| # | Criterion | Score | Reason |
|---|---|---|---|
| 1 | First impression and onboarding | 6 | The workshop reads well and the doctrine terminal explains each rule in plain words, but the game never says on screen that PvP starts in round 4, what a death costs in fuel (30), or whether HP carries over between rounds. |
| 2 | Visual appeal and art direction | 8 | Strong, coherent scrap-desert look; the card tags, the doctrine terminal and the tech board feel hand-made, and alien and player projectiles are clearly cold and warm. |
| 3 | Readability in combat | 4 | When FOCUS CANNON deleted 425 HP in about 12 s, it was off-screen: no edge indicator, no hit direction, no kill feed and no death recap, so I only learned who killed me from the harness log. |
| 4 | Sense of agency | 8 | Decisions visibly matter: armor stacking plus kite cut my damage taken from 680 to 150 in one round, and a single doctrine toggle turned 2nd place into a win. |
| 5 | Upgrade choices | 5 | Some real trade-offs (Caterpillar Tracks, Berserker), but the pool feels thin: Off-road Tyres appeared 5 times. A reroll replaced only 1 of 3 cards, and many commons are obvious skips. |
| 6 | Progression and power fantasy | 6 | Numbers climb nicely (HP 300 to 480, armor 0 to 5, MG 40 to about 100 dps), but the gun cap stays at 2 until a 300-scrap tech, and the rig barely changes on screen. |
| 7 | Difficulty and pacing | 4 | PvE is no threat (0 damage taken in rounds 1 to 3, 4 HP in branch round 7), so the first three rounds are autopilot and all real danger comes from rival rigs from round 4 on. |
| 8 | Strategic depth and balance | 4 | Passive third-partying (nearest + kite) beats engaging, interest is irrelevant after round 3, and flat armor hard-counters MG and shotgun builds; I suspect a dominant line. |
| 9 | PvP and multiplayer fun | 5 | The duels with FOCUS CANNON were tense (mutual kill at 44 s), but the winning play was to avoid fights and let bots kill each other, and the leader bounty is invisible in-game. |
| 10 | UI and UX | 6 | The workshop layout is clean, with costs, "need X more" and hotkeys, but it lacks a rival scouting panel, a last-round recap, current HP (it shows max HP only) and DPS or post-tech numbers on cards. |
| 11 | "One more run" factor | 7 | The 2nd-to-1st flip from one toggle makes me want to map the doctrine matchups, though partly because I suspect it is solvable. |
| 12 | Technical quality | 8 | Fully deterministic and fast (about 1 s replays), with no crashes; minor issues: card ranges show base values ("range 250>260" while my MG already had 270) and the game-over round awards +0 interest. |

**Average: 5.9**

## Observations

### Balance probes
- **Passive doctrine is (probably) dominant in FFA.** Same seed, same build: `players_first` gave 529 damage taken and 1 death in round 6, then elimination in round 7 (2nd place). `nearest` gave 53 damage, 0 deaths, and a win in round 9. Bots with `players_first`/hunter logic trade fuel with each other while a passive rig farms aliens. Fuel only drops on death, and aliens don't threaten a mid-game rig, so a rig that avoids PvP never loses.
- **Flat armor stacking is very strong against high-rate, low-damage guns.** MG and shotgun pellets hit for 4 to 6. Going from armor 1 to 4 (Ablative Scrap + Welded Frame) cut PvP shot damage taken from 522 to 127 per round. Cannons (26+ per hit) ignore that, so the counter-triangle exists, but players can't see it: no armor formula, and no rival armor value.
- **The economy saturates.** The interest cap is +5 per round, while income was 70 to 190 scrap per round from round 3 on. After round 3, holding scrap for interest is meaningless. I ended the branch run with 451 scrap and nothing worth buying (two 300 tiers, everything else bought or weak). The interest decision only matters in rounds 1 and 2.
- **Kill-count snowball from the cannon.** FOCUS CANNON had 34 kills in round 1 against my 20 (pierce clears mite lines), so it had more scrap from the start. It is not decisive, but the early cannon pick looks strictly correct.
- **Reroll value is low.** Rerolling at R2 for 6 scrap returned 2 of the same 3 cards (Off-road Tyres, Steel Plates). Over the run Off-road Tyres was offered 5 times and never taken. Reroll costs only +1 per use, but a thin pool makes it a waste.
- **Mutual destruction:** in round 6 FOCUS CANNON and I killed each other in the same second (44 s). That is fine, but with 10 fuel left it decided the game, and nothing on screen warned me that I was one death from elimination.

### Information gaps (as a player, without the harness summary)
- **No in-game scouting:** the convoy panel shows only READY or OUT. I can't see rivals' fuel, HP, guns, armor or tech, which is the core TFT habit. The harness listed rival loadouts, the game doesn't.
- **No damage or death attribution in-game:** the harness gives "shots from PVP HUNTER 522, ram 148"; the game gives nothing, not even a "destroyed by" banner.
- **HP state is ambiguous:** the workshop shows "HP 440" (max). The end-of-round HP (351/440) seemed to reset to full by round start, but nothing says so.
- **Fuel rules are unexplained:** I had to infer that a death costs 30 fuel and that fuel doesn't drain otherwise.
- **Card text is fuzzy:** "Vulture: +25% dmg vs wounded" (what threshold?), Caterpillar Tracks is tagged *mobility* but is a defensive card, cards show base and pre-tech values, and there is no DPS line.
- **The leader bounty is invisible:** the harness says "LEADER: bounty on you"; the game never tells me.
- **Off-screen threats:** in the round-7 late frame I'm at 40% HP taking tracer fire from below, and the shooter isn't on screen.

### Suspected dominant strategies
1. `target=nearest` + `kite` + armor stacking. Avoid PvP, let bots trade fuel, finish the last one. Fuel only drops on death, so there is no cost to waiting.
2. An early Siege Cannon for pierce-farming (more kills, so more scrap).

## Top 5 issues (by impact)

1. **Passive play beats engaging, so PvP is optional.** Make avoiding fights cost something. For example: killing a rival steals some of its fuel (a refund for the attacker), a slow fuel drain from round N on (or a shrinking arena) that only kills refuel, and a leader bounty paid in fuel. Then `players_first` becomes a real gamble rather than a trap.
2. **Combat doesn't explain damage or death.** Add edge-of-screen rival indicators with HP and fuel pips, hit-direction flashes, a small kill feed, and a death recap in the next workshop ("Destroyed by FOCUS CANNON: cannon L3, 425 dmg in 12 s").
3. **No scouting in the workshop.** Make the convoy rows expandable or hoverable: guns with levels, armor, max HP, fuel, tech count and doctrine. Without this, "builds that counter other players" is guesswork.
4. **The economy saturates, and interest and reroll stop being decisions.** Scale the interest cap (or use a percentage), add scrap sinks (buy an extra card, sell or scrap parts, lock offers), and make a reroll give 3 cards not in the previous offer. Thin the pool of filler commons (Off-road Tyres).
5. **PvE gives no pressure, so rounds 1 to 3 are autopilot.** I took 0 damage in rounds 1 to 3 and 4 HP in a later round. Give the hive a real threat curve (elites, spitter volleys that punish turtling) and an early PvE objective with a fuel or scrap reward, so pre-PvP rounds involve decisions and the turtle line carries risk.

*(Honourable mention: card numbers. Show DPS, post-tech values, the armor formula and the "wounded" threshold in tooltips.)*

## What I loved

- **The doctrine system is deterministic and legible.** "KEEPS ITS DISTANCE / RIVAL RIGS BEFORE ALIENS" tells me exactly what the AI will do, and the outcome followed from it: one toggle flipped a 2nd place into a win. That kind of predictable lever is what I want from an auto-battler.
- **The counter-building works when you find it.** Armor against pellet guns was a clear, rewarding read: 680 damage per round down to 150 after one workshop.
- **The tech board** is readable at a glance (tiers, costs, BUILT state, "need X more"), and the card art and tags look great.
- **The tense endgame duel:** 10 fuel against 10 fuel, with a mutual kill at 44 s. When PvP happens, it's exciting.
- **The harness's damage-source breakdown** is the best information in the game. Put it in the workshop.
