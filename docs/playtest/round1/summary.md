# Playtest round 1: summary

The personas played the build at commit `a8b359e` (balance iteration 2) through the playtest harness. Full reports are in `mia.md`, `jonas.md` and `sam.md`.

| Criterion | Mia (solo) | Jonas (FFA) | Sam (FFA) | Avg |
|---|---|---|---|---|
| Onboarding | 6 | 6 | 7 | 6.3 |
| Visual appeal | 8 | 8 | 8 | **8.0** |
| Combat readability | 4 | 4 | 6 | 4.7 |
| Sense of agency | 5 | 8 | 7 | 6.7 |
| Upgrade choices | 4 | 5 | 6 | 5.0 |
| Progression / power fantasy | 4 | 6 | 5 | 5.0 |
| Difficulty / pacing | 3 | 4 | 7 | 4.7 |
| Depth / balance | 5 | 4 | 5 | 4.7 |
| PvP / multiplayer | 3* | 5 | 6 | 4.7 |
| UI / UX | 7 | 6 | 7 | 6.7 |
| One more run | 5 | 7 | 7 | 6.3 |
| Technical quality | 8 | 8 | 8 | **8.0** |
| **Average** | 5.2 | 5.9 | 6.6 | **5.9** |

\* Mia played solo only.

**Strengths everyone named:** the art direction, stability, the lobby and rematch flow, and the workshop screen's look.

## Consolidated issues and planned fixes (iteration 1)

| # | Issue (who raised it) | Fix | Owner |
|---|---|---|---|
| 1 | End-of-round spike: alive aliens snowball in the last 15 s and cause most deaths (Mia) | Flatten the in-round spawn curve; cap boulders alive; spread spitter waves | sim |
| 2 | Deaths unexplained, doctrine fix hidden (all) | Per-round damage-by-source and death-cause stats; workshop "last round" recap plus a doctrine hint; kill feed; off-screen rival indicators; HP numbers | sim + UI |
| 3 | Passive play beats engaging in FFA (Jonas) | Kills steal fuel; slow fuel drain from a late round on (only kills refuel); leader bounty also pays fuel | sim |
| 4 | Newbies farmed (Sam) | 3 s respawn and round-start invulnerability; 10 s PvP-on grace at round 4; `players_first` prefers the leader; underdog bonus (lowest fuel loses less fuel per death); diminishing reward for killing the same victim repeatedly | sim |
| 5 | Elimination is dead air (Sam) | Spectator mode: follow the leader or fights (Tab cycles), spectator panel instead of the workshop | UI |
| 6 | The rig doesn't visibly grow, rigs look alike (Mia, Sam) | Bolt-on visuals per card (guns, plates, spikes, nitro flames), hull growth with engineering, bigger paint panels, own-rig ground ring | visual |
| 7 | Thin, repetitive drafts (Mia, Jonas, Sam) | Guarantee a weapon offer while a gun slot is free; never 3 cards of one category; a reroll never repeats the previous offer; early weapon variety; thin out filler commons | sim |
| 8 | Economy saturates (Jonas) | Interest becomes 10% of held scrap, with a cap that scales by round; more scrap sinks later | sim |
| 9 | Ram fantasy fights boulders (Sam) | Spiked/berserker take reduced contact damage; the charge AI avoids boulders unless berserk | sim |
| 10 | No scouting (Jonas) | Expandable convoy rows: rivals' guns and levels, armour, HP, fuel, tech, doctrine | UI |
| 11 | Big moments uncelebrated (Sam) | Explosion and shake on rival kills, "PVP ON" banner, bounty skull over the leader, end-of-match awards | visual/UI |
| 12 | Late-combat readability (Mia) | Boulder outline and shadow, bigger acid with a trail, corpses fade or desaturate, low-HP vignette | visual |
| 13 | Rounds 1–3 are autopilot (Jonas) | Partly addressed by #1, #7 and #8 (more decisions); elites and early objectives are deferred to the alien-variety feature | later |
| 14 | Power curve flat versus hive scaling (Mia) | Re-check with the bot league after the fixes; scale weapon cards and tech harder if needed | sim |

Round 2 re-tests the same personas on the improved build.
