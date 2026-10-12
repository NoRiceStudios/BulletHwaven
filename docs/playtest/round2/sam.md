# Playtest round 2: Sam, 29, "the LAN-night host"

## The run

- **Setup flow (screens, seed 1):** rendered and reviewed `lobby` (30 ticks), plus `gameover_mp`, `eliminated`, `spectator` and `awards` (700 ticks each), all at 1080p.
- **Match:** `scripts/playtest.sh new ... --seed 303 --mode ffa --opponents random,balanced,never_upgrade --name SAM --color 3` (green). This is the same seed and lobby as round 1: the bots stand in for my LAN crew, with RANDOM as the average friend, BALANCED as the decent one and NEVER UPGRADE as the newbie.
- **My build (flashy flamer brawler):** I rerolled once in workshop 1, which turned up **Flamethrower and Berserker side by side**. I took the Flamethrower and levelled it to L3 by workshop 3, then added Spiked Plating. Tech was Engineering 1, Propulsion 1 and Electronics 1. Doctrine was charge from round 2 and players-first from round 4.
- I used 8 decision points (plus one reroll), and 3 of them were spectating.

| Round | What happened |
|---|---|
| 1–2 | Calm PvE: 0.7 hp lost, then 0 hp lost. Round 2 peaked at 10 aliens on the whole map. |
| 3 | Charge drove me into a boulder cluster: **309 of the 310 damage I took came from boulders**, and I ended at 9 % hp. The new debrief said "Boulders 100 % – try kite" with a SET KITE button. |
| 4 | A full-width **PVP ON** banner with a 10 s grace period. I flamed NEVER UPGRADE to death at 15 s. BALANCED then killed me twice (17 s, 33 s), and a boulder got me at 50 s. Fuel went 100 → 30. **NEVER UPGRADE was eliminated at 58 s, in his very first PvP round** (killed by me, then RANDOM ×3). |
| 5 | Underdog tag ("-30 % fuel loss"). RANDOM rammed me at 10 s, I rammed RANDOM to death at 19 s (my big moment!), then a boulder got me at 35 s and BALANCED's siege cannon at 45 s. **I was eliminated in round 5.** |
| 6–7 | Spectating. The two survivors mostly fought aliens: each round, one death to mites or boulders. |
| 8 | BALANCED shot RANDOM twice and won at 32 s. |

**Final standings:**

| Place | Rig | Kills | Result | Round 1 result |
|---|---|---|---|---|
| 1 | BALANCED | 501 | Won with 51 fuel | Won |
| 2 | RANDOM | 421 | Eliminated in round 8 | Eliminated in round 8 |
| 3 | SAM | 211 | **Eliminated in round 5** | Eliminated in round 7 |
| 4 | NEVER UPGRADE | 100 | **Eliminated in round 4** (58 s into PvP) | Eliminated in round 6 |

The match ran about 10 minutes over 8 rounds. The newbie spent **about 6 of those minutes watching** and I spent about 5.

## Scores

| # | Criterion | R2 | R1 | Why |
|---|---|---|---|---|
| 1 | First impression and onboarding | 8 | 7 | The PvP ON banner ("rival rigs are fair game – bounty on the leader"), the after-round debrief with a one-click tip ("Balanced hunts you – fight back or kite away") and the underdog tag finally explain the rules as they hit you. |
| 2 | Visual appeal and art direction | 8 | 8 | Same gorgeous desert. Paint panels are bigger, the flamer cone looks great, and BALANCED's round-8 rig is visibly heavier and pinker than at the start. Kill moments are still quiet (no fireball I could spot). |
| 3 | Readability in combat | 7 | 6 | My rig now has a coloured ground ring, rivals off-screen get coloured arrows, the leader carries a bounty skull and there is a kill feed ("BALANCED → SAM CANNON"). The camera still parks the action at the screen edge. |
| 4 | Sense of agency | 6 | 7 | Doctrine and the flamer clearly changed how I fought, but every flashy choice (charge, players first, spikes) got me farmed faster, and the debrief's advice is basically "stop playing your fantasy". |
| 5 | Upgrade choices | 7 | 6 | A flamer and berserker on the first reroll, and Spiked Plating now has real trade-offs (thorns, alien contact reduction). The two gun slots fill by round 2, though, so my Machine Gun sat at L1 all game. |
| 6 | Progression and power fantasy | 5 | 5 | Rigs do grow with tech (BALANCED's 7-tier rig looked chunky), but I was out before my rig changed much. Round 2 versus round 4 looked like the same truck with a nozzle. |
| 7 | Difficulty and pacing | 5 | 7 | Rounds 1–2 are still sleepy (0 damage), then round 4 is a meat grinder. Half the lobby was out by round 5, and the last 3 rounds were a mostly-PvE duel for two spectators. |
| 8 | Strategic depth and balance | 4 | 5 | Charge still drives into boulders (309 hp in round 3, 2 of my 6 deaths). The defensive BALANCED build won again, and the aggressive player was eliminated earlier than in round 1. |
| 9 | PvP and multiplayer fun | 6 | 6 | Spectator mode, awards and the PvP banner are big wins, but the newbie lasted 58 seconds of PvP, and the lobby still has no add-bot, kick or settings. |
| 10 | UI and UX | 8 | 7 | The debrief bar with damage share by rival colour, the eliminated workshop (stats, scout report, standings) and the spectator HUD are excellent. Leftover bugs are listed below. |
| 11 | "One more run" factor | 7 | 7 | The awards make me want to hit Rematch for the Ram King title. Knowing my newbie friend would spectate for 6 minutes again, I'd hesitate to call it for the group. |
| 12 | Technical quality | 8 | 8 | No crashes and a quick replay. Small issues: the ghost "HIVE RETREATS" banner is still behind the workshop, the debrief is wrong for eliminated players, and the font still shows "NAD NAREK". |

## What improved

- **Spectating is a real mode now.** Being out shows a "SPECTATING: RANDOM – AUTO CAM, TAB/<> SWITCH RIG" header and a live standings panel. The workshop becomes an "OUT OF FUEL – your convoy is watching" card with my stats (aliens, rigs wrecked, times wrecked, scrap, **nemesis BALANCED ×3**), a scout report on the leader (guns, parts, tech pips, doctrine) and a standings table with fuel bars and camp status. This fixes my number-2 issue from round 1 on the "information" side.
- **End-of-match celebration:** six award cards (Top Hive Killer, Most Player Kills, Ram King, Scrap Baron, Most Deaths, **Nemesis "haunted → SAM ×3"**) around a big "BALANCED WINS" in the winner's paint colour, plus "Favourite part: Flamethrower LV 3". The client "waiting for the host" tag no longer overlaps the panel.
- **Big moments are announced.** There is a full-width PVP ON banner with skulls, a bounty skull over the leader (on-screen and on the off-screen arrow) and a kill feed line.
- **My rig is findable:** a green ground ring, bigger paint panels, and coloured off-screen arrows for each rival.
- **Last-round debrief:** "Wrecked 3× – last at 0:50 by a boulder" with a damage bar split by source in rival colours, fuel lost/stolen, and a contextual one-click doctrine tip. This is the clearest "why did I die" panel I've seen in a game like this.
- **Comeback mechanics exist:** a 10 s PvP grace period at round 4 and an underdog -30 % fuel loss (I saw it apply: 30 → 9 instead of 30 → 0).
- **Card variety:** the flamer and berserker showed up in workshop 1, and Spiked Plating now reads as a ram build (ram damage, thorns, less alien contact damage).

## What still bugs me

- **The newbie is out even faster.** In round 1 he lasted until round 6; this time he was **eliminated 58 s into round 4, his first PvP round**: killed at 15 s (me), 27 s, 39 s (ram) and 58 s (all RANDOM), so roughly every 12 s. His fuel went 100 → 70 → 40 → 10 → 0, so **the underdog discount never applied to him**: it seems to be decided at round start, when all four of us were tied at 100. The grace period only delayed the first kill by 5 seconds.
- **I was out in round 5 as well**, after 6 deaths in 2 rounds. From round 5 on, 2 of 4 players watched a mostly-PvE match: in rounds 6 and 7 the survivors died only to mites and boulders. On a LAN night that is half the room on their phones for 5–6 minutes.
- **Spectators still can't do anything.** It's great to watch, but there is no input apart from switching camera.
- **Auto cam frames the action badly.** In round 8 the decisive duel happened at the right screen edge with an empty bone field in the middle. In round 5 it followed the leader through a quiet area while 57 aliens were alive.
- **Charge still eats boulders.** 309 hp in round 3, plus deaths at 50 s (round 4) and 35 s (round 5). Spiked Plating didn't stop it, and the game's answer is "try kite", which is the opposite of my build.
- **Awards favour the winner.** BALANCED took 4 of 6 cards (Top Hive Killer, Most Player Kills, Scrap Baron, Nemesis). SAM and NEVER UPGRADE got none, even though I tied for most deaths (6). "Ram King: 60 kills by ramming" counts aliens, while "Most Player Kills" counts rigs, which is confusing. The results table isn't sorted by placement or numbered: SAM (3rd) is listed first.
- **Leftover UI bugs:**
  - The ghost "HIVE RETREATS – MAKE CAMP" banner is still visible behind every workshop; in the spectator workshop it overlaps the rig and the standings.
  - The eliminated player's debrief says "CLEAN ROUND – NOT A SCRATCH, nothing got through the plating", because I wasn't there.
  - The rig preview still renders "MAD MAREK" as "NAD NAREK".
  - Nightcrawler still needs a label patch.
  - The lobby still has no add-bot, kick or match settings.
- My Machine Gun stayed L1 all game, because both gun slots were full by round 2 and no MG offers turned up.

## Top 5 issues (by impact)

1. **The knockout cascade at PvP start.** The newbie was out in 58 s and I was out a round later, so half the lobby watched more than half the match.
   - *Suggestion:* recompute underdog status live after every death, not at round start.
   - Cap PvP fuel loss at 2 deaths per round, so the third and later deaths cost no fuel.
   - Add a "bully tax": killing the same rig twice in one round yields no fuel or bounty.
   - Don't allow elimination before round 6.
2. **Spectators have nothing to do.**
   - *Suggestion:* give out players a "ghost" action each round: drop a scrap crate on a chosen friend, spawn a boulder or alien pack on the leader, or vote on a hazard.
   - Alternatively, let them respawn as a small scrap drone that can harass rivals and earn back 10 fuel to rejoin.
   - Separately, have the auto cam frame the midpoint of the nearest PvP fight (zooming out to fit both rigs) instead of following a single rig.
3. **The ram fantasy still fights the boulders.**
   - *Suggestion:* teach the charge AI to path around boulders unless it is chasing a rig.
   - Let Spiked Plating and Berserker reduce boulder contact damage too, not just alien contact.
   - Make the debrief tip suggest a ram-friendly fix ("add plating", "target players first") before suggesting kite.
4. **Awards should spread the glory.**
   - *Suggestion:* give each rig at most one award (next-best goes to someone else), and add consolation titles such as First Blood, Kamikaze (most boulder deaths), Stubborn (most respawns) and Hive Snack.
   - Rename Ram King to count rig rams, or label it "aliens rammed".
   - Sort the results table by placement with #1–#4 numbers, and split kills into aliens and rigs.
5. **UI leftovers.**
   - *Suggestion:* hide the "HIVE RETREATS" banner once the workshop opens.
   - Show "You were out this round" in the eliminated player's debrief.
   - Fix the M/N glyph in the small font.
   - Add add-bot, kick and match settings (PvP start round, round length) to the lobby, so a 2-friend night still fills 4 slots.

## What I loved

- **The awards board.** "NEMESIS: BALANCED – haunted → SAM ×3" is exactly the trash-talk fuel a LAN night needs. Winner text in the winner's paint and "Favourite part: Flamethrower LV 3" are lovely touches.
- **The eliminated workshop.** My personal stats plus "nemesis", the scout report on the leader and the standings table make being out feel like part of the match, not a crash.
- **The PvP ON banner and bounty skull.** The moment round 4 starts, everyone in the room knows it's on.
- **The debrief bar:** a single strip coloured by who hurt me (BALANCED 82 %, NEVER UPGRADE 12 %, boulder) with "Wrecked 3× – last at 0:50 by a boulder". Instant blame assignment for the couch.
- **Ramming RANDOM to death at 19 s in round 5 with a flamer truck**, one life from elimination. That's still the Mad Max moment, and the flamer cone looks great.
- **The lobby** is still the fastest LAN setup I know: paint picker with crossed-out taken colours, ready states and Force Start.
