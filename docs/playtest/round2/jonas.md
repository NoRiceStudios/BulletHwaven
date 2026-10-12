# Playtest round 2: Jonas (persona 2, "the ranked strategist")

**Run:** seed 202, FFA against `balanced`, `pvp_hunter` and `focus_cannon`, driver JONAS (colour 5). Same seed and lobby as round 1.

**Three sessions from one fork:**

| Session | Doctrine from round 4 | Result | Decision points |
|---|---|---|---|
| **Engaged** (main) | kite + players first | **1st**, won in **round 6**, fuel 100 at the end | 5 |
| **Passive** (branch) | kite + nearest, switched to players first at workshop 8 | **1st**, won in round 10, fuel 39 | 9 |
| **Turtle** (branch of passive) | kite + nearest for the whole game | Losing: fuel 1 against BALANCED's 20 after round 14, so elimination is all but certain | 13 |

**Shared build (rounds 1 to 3):** rerolled at workshop 1 (Reinforced Hull, Flamethrower, Caterpillar Tracks became Siege Cannon, Ablative Scrap, V8 Engine) and took Siege Cannon. W2: Nitro Injection, then held 73 scrap for interest. W3: Siege Cannon L2, Welded Frame and Rangefinder, then the fork.

**Engaged path:** W4 Ablative Scrap (armour 4). W5 Siege Cannon L3, Bolt-on Plating and Hardened Rounds. Round 4 went badly: I was wrecked twice (14 s by FOCUS CANNON, 47 s by PVP HUNTER) and dropped from 100 to 60 fuel, though I stole 20 back. Round 5 decided the game: 5 rig kills, +40 fuel stolen (60 to 100), and PVP HUNTER and FOCUS CANNON were both eliminated. In round 6 I finished BALANCED at 38 s.

## Scores

| # | Criterion | Score | R1 | Reason |
|---|---|---|---|---|
| 1 | First impression and onboarding | 7 | 6 | The new "Last round" panel, the hint line ("FOCUS CANNON HUNTS YOU - ARMOUR UP") and the Underdog badge teach the rules as they happen, but the workshop still doesn't warn that PvP starts next round, and it doesn't say that HP resets between rounds. |
| 2 | Visual appeal and art direction | 8 | 8 | Same strong scrap-desert look; the new overlays (kill feed, edge arrows with HP and fuel bars, skull over the leader) fit the style; one card's text runs over its footer (Siege Cannon L2>3 "SPLASH" line). |
| 3 | Readability in combat | 7 | 4 | Edge indicators, a kill feed ("PVP HUNTER -> JONAS MG") and a death recap that names the killer and weapon fix most of my round-1 complaint; the remaining gap is burst deaths: I went from 100% to wrecked in about 4 s right after the grace period ended, with no warning. |
| 4 | Sense of agency | 9 | 8 | One doctrine switch (nearest to players first) took BALANCED from 75 to 1 fuel in a single round, and the recap even offers a one-click "TARGET PLAYERS 1ST" button: decisions visibly move the game. |
| 5 | Upgrade choices | 6 | 5 | A reroll now gives 3 fresh cards, which makes rerolling a real decision, but cards still show pre-tech values ("range 310>320" while my cannon had 335), Off-road Tyres still shows up as filler, and "Vulture: +25% vs weak targets" still doesn't say what counts as weak. |
| 6 | Progression and power fantasy | 7 | 6 | Splash on cannon L2, a reachable Third Hardpoint by round 8 and visible regen and armour make the rig grow, but the fast win ended the main run at round 6 with only 4 of 15 techs built. |
| 7 | Difficulty and pacing | 6 | 4 | Late PvE now bites (hive HP +131%, boulders dealt 300 to 450 per round, and I died to acid once), but rounds 1 to 3 were again 0 damage taken, and FFA collapses from 4 rigs to 2 in round 5. |
| 8 | Strategic depth and balance | 6 | 4 | My round-1 dominant line is dead: the turtle bleeds out to the fuel drain (5 per round from round 8) while BALANCED stays ahead. But players first won every branch I tried, and fuel stealing snowballs very hard. |
| 9 | PvP and multiplayer fun | 7 | 5 | Kills now steal fuel and the leader carries a visible bounty skull, so fights matter; the downside is that the bots wipe each other out by round 5, so the endgame is a short 1v1. |
| 10 | UI and UX | 7 | 6 | The recap panel with a damage-share bar by source is exactly what I asked for; there is still no current-HP readout, scouting is hover-only, and the workshop never shows that I'm the bounty leader (the harness says so, the screen doesn't). |
| 11 | "One more run" factor | 7 | 7 | I want to test this against harder bot mixes, but I won all three openings with the same doctrine flip, so I suspect the bots are now the weak link rather than the rules. |
| 12 | Technical quality | 8 | 8 | Deterministic and fast (about 1 s per replay), no crashes; minor issues: the card text overflow, the interest preview "+7/9" paid +11 (the cap rose before payout), and in the harness the game-over summary prints OPPONENTS and FINAL STANDINGS twice and lists an unnamed "kind-1" alien. |

**Average: 7.1** (round 1: 5.9)

## Balance probes

- **Passive play no longer wins, which was my main round-1 finding.** Same seed, same build, only doctrine changed:
  - The engaged run (players first from round 4) won in round 6 with full fuel.
  - The passive run (nearest) was at 53 fuel against BALANCED's 80 after round 7, with 0 rival shots exchanged in round 6. From round 8 a fuel drain of 5 per round starts ("only rig kills refuel you"), so a stand-off now loses for whoever is behind.
  - The turtle (nearest, never engaging) went from 53 to 1 fuel over rounds 7 to 14 through drain alone (plus one acid death), while BALANCED sat at 20. That is a loss.
  - The drain fixes the core exploit. It starts late, though (round 8), and is small (5 to 6 per round), so a passive player can still coast through rounds 4 to 7.
- **Players first now looks like the default answer.** Switching the passive branch to players first at workshop 8 took BALANCED from 75 to 1 fuel in one round (3 kills, +15 fuel stolen), and the engaged run took 5 rig kills in round 5. I couldn't find a scenario where staying passive was right after round 4. The counter to a hunter should be a build or doctrine choice, not "always hunt".
- **Fuel stealing snowballs hard.** Engaged run, round 5: +40 fuel stolen, two rivals eliminated in the same round, and the game was over by round 6. In both branches PVP HUNTER and FOCUS CANNON were eliminated in round 5, mostly by each other. The Underdog rule (-30% fuel loss for the lowest fuel) is a nice touch but doesn't slow this down.
- **The first PvP round is a coin flip.** In both doctrines I was wrecked at 14 s of round 4, 4 s after the 10 s grace ended: once by FOCUS CANNON's cannon (players first), once by a PVP HUNTER ram (nearest). Each death cost 30 fuel before I could react, so spawn proximity decides it, not build.
- **Economy: better, still loose.** The interest cap now grows by +2 per round (7, 9, ... 25), so interest stays relevant longer. But I hit the cap every round from round 3 on (181 held against a cap of 11, 357 against 15). Holding scrap is never a sacrifice. The engaged run ended with 214 scrap and the passive run with 47, so spending did matter in the end.
- **Reroll is now worth it.** 6 scrap gave 3 new cards (and found the Siege Cannon I wanted), a clear improvement over round 1's 2-of-3 repeats.
- **The cannon farming lead is smaller.** FOCUS CANNON had 63 kills against my 43 after round 2, but with my own cannon I was at 105 against its 119 by round 3. That's still an edge for the early cannon, but no longer decisive.
- **Leader and Underdog at the same time.** In the passive branch I was marked "LEADER: bounty on you" (apparently by kills) and "UNDERDOG (lowest fuel)" in the same round. Two catch-up systems with opposite meanings and different metrics are confusing, and only the Underdog one shows in the workshop.

## What improved

- **Death and damage attribution:** "WRECKED 2X - LAST AT 0:47 BY PVP HUNTER - MACHINE GUN", a colour bar of damage share per source (FOCUS CANNON 45%, PVP HUNTER 40%, BALANCED 14%, acid...), and a kill feed in combat. This fixes my #2 issue.
- **Edge-of-screen rival arrows with HP and fuel bars,** plus a bounty skull over the leader rig. I now know where the shots come from.
- **Fuel economy:** kills steal fuel, a late drain punishes stalling, and the Underdog relief exists. This fixes my #1 issue.
- **Reroll gives 3 new cards,** and the interest cap scales with the round. This partly fixes my #4 issue.
- **The workshop teaches:** contextual advice ("BALANCED HUNTS YOU - FIGHT BACK OR KITE AWAY") with a one-click doctrine button.
- **Late PvE has teeth:** the hive HP scaling and the boulder and acid damage mean a turtle can actually die to aliens.
- **The game-over screen** (Top Hive Killer, Ram King, Nemesis, Scrap Baron, favourite part, tech x/15) is a great recap.

## What still bugs me

- I can't see rivals' builds without hovering ("HOVER TO SCOUT"). There is no keyboard or always-visible option, and I couldn't check what the hover panel shows (doctrine? armour?).
- The workshop still shows max HP only. HP clearly resets each round (7/340 at the end of round 4, 100% at the start of round 5), but nothing says so.
- Cards show base or pre-tech numbers, and there is no DPS line. The armour formula is still invisible, so armour against pellets remains guesswork.
- Nothing in the round-3 workshop says "PvP starts next round".
- The leader rule is unexplained, and I was leader and underdog at once.
- FFA is effectively over after round 5: two bots die in the same round in every branch.

## Top 5 issues (by impact)

1. **Fuel stealing snowballs, and players first is the new default.** Games end in round 6, with two eliminations per round. *Suggestion:* cap the fuel stolen per round (for example 20), or scale the steal down when the victim is low, and pay the leader bounty in scrap rather than fuel. Make the hunter bots avoid suicidal trades below 30 fuel, so FFA stays three-way for longer and staying passive in a three-way fight is sometimes right.
2. **The first PvP seconds decide fuel by spawn proximity.** Both doctrines lost 30 fuel at 14 s of round 4. *Suggestion:* spawn rigs further apart or give a short spawn shield after the grace, add a 3-2-1 "PvP LIVE" countdown in the HUD, and put a "PvP starts next round" banner in the round-3 workshop.
3. **Remaining hidden information.** *Suggestion:* show current HP and "HP resets each round" in the rig panel; show post-tech values and DPS on cards; add an armour tooltip ("reduces each hit by X, minimum Y"); show the leader rule and the bounty in the workshop; make the convoy scout panel toggleable with a key (Tab) and include each rival's doctrine and armour.
4. **The economy is still loose mid-game.** I was over the interest cap in every workshop from round 3 on. *Suggestion:* let the cap grow by +3 or +4 per round, or use stepped interest (1 per 10 scrap held, up to the cap, with the cap shown on screen), and add scrap sinks such as locking an offer, buying a second card for N scrap, or selling a part. Also make the interest preview use the cap that will actually apply ("+7/9" paid +11).
5. **Rounds 1 to 3 are still autopilot.** I took 0 damage in each of them again. *Suggestion:* add an early elite or spitter wave that forces a doctrine or armour decision before PvP, and start the fuel drain earlier but softer (for example 2 per round from round 5), so stalling costs something before round 8.

*(Honourable mention: polish. Fix the Siege Cannon card text overflow, name the "kind-1" alien in the harness, and stop printing the game-over sections twice.)*

## What I loved

- **The round-recap panel** is the best UI in the game: who wrecked me, with what, the damage-share bar, fuel lost and stolen, and a suggested counter with a one-click button. This is exactly the transparency a ranked player wants.
- **The fuel drain killed the turtle cleanly.** I tested my own round-1 exploit for 13 decision points and watched it lose by attrition. That is a well-targeted fix.
- **Doctrine is still the deterministic lever I love:** one toggle swung 74 fuel in a round. It's now the right kind of decisive, rewarding aggression, not passivity.
- **Reroll and interest now ask real (if mild) questions,** and the reroll found the exact card I was fishing for.
- **The game-over awards** (Nemesis, Ram King, Scrap Baron) give the match a story.
