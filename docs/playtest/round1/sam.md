# Playtest round 1: Sam, 29, "the LAN-night host"

## The run

- **Setup flow (screens):** rendered and reviewed `menu`, `join`, `lobby`, `pause`, `gameover_mp` and `eliminated` (seed 1). `gameover_mp` and `eliminated` only show their overlay after about 600 ticks; at 30 ticks they are plain round 1 frames.
- **Match:** `scripts/playtest.sh new ... --seed 303 --mode ffa --opponents random,balanced,never_upgrade --name SAM --color 3` (green). The bots played my LAN crew: an average friend (RANDOM), a decent one (BALANCED) and the newbie who never upgrades (NEVER UPGRADE).
- **My build (flashy brawler):** Machine Gun, then Scatter Gun after one reroll, Spiked Plating, Nitro Injection L2, Ablative Scrap and Berserker Doctrine. Tech: Engineering 1–2, Propulsion 1–2, Ballistics 1–2 and Electronics 1. Doctrine from round 2 was **charge**, and from round 4 (when PvP turns on) **players first**.
- **What happened:**

| Round | What happened |
|---|---|
| 1–3 | Calm PvE. Round 1 cost me 0 damage. |
| 4 | PvP switched on and I was the leader with a bounty on me. I killed NEVER UPGRADE **3 seconds into the round** and rammed RANDOM to death, then died to RANDOM's shots at 60 s. |
| 5–6 | I farmed the newbie: I destroyed him at 50 s (a ram), 23 s (a ram) and 48 s. Every one of his four deaths was to me, and he was **eliminated in round 6**. |
| 7 | Berserker online: I rammed BALANCED at 4 s and finished RANDOM twice. Boulders then flattened me at 37 s and BALANCED's shotgun finished me at 59 s. I was **eliminated in round 7**. |
| 8 | Spectating. BALANCED killed RANDOM 12 s in. |

- **Final standings:**

| Place | Rig | Kills | Result |
|---|---|---|---|
| 1 | BALANCED | 284 | Won with 70 fuel |
| 2 | RANDOM | 296 | Eliminated in round 8 |
| 3 | SAM | **477** (most of anyone) | Eliminated in round 7 |
| 4 | NEVER UPGRADE | 155 | Eliminated in round 6 |

  The match took about 10 minutes of real time over 8 rounds and 7 workshops.

## Scores

| # | Criterion | Score | Why |
|---|---|---|---|
| 1 | First impression and onboarding | 7 | The menu reads at a glance: three big buttons, a driver card on the right and a control hint at the bottom. Nothing explains fuel, elimination or "PvP from round 4" before it hits you. |
| 2 | Visual appeal and art direction | 8 | The desert, the scrap-welded rigs and the cyan glow on camouflaged aliens look great on a TV. Kill and destruction moments are visually quiet, though. |
| 3 | Readability in combat | 6 | Alien threats are clear (cyan means danger), but my own rig has no name tag. The rigs look almost identical apart from small paint accents, the camera often leaves my rig at the screen edge, and I never saw that boulder contact was killing me. |
| 4 | Sense of agency | 7 | Switching to charge plus players-first turned me into a ramming menace (8 rival kills, 5 of them rams), so doctrine visibly matters. |
| 5 | Upgrade choices | 6 | Spiked Plating, Nitro and Berserker are exactly my fantasy, but many offers are flat stat bumps, cards share icons, and in 21 cards (6 offers plus 1 reroll) I never saw a flamer. |
| 6 | Progression and power fantasy | 5 | Speed rose to 152 % and armour from 0 to 4.5, but in round 7 my rig looked nearly the same as in round 1, and both my guns were still level 1. |
| 7 | Difficulty and pacing | 7 | About 10 minutes per match with 25-second workshops is a great LAN length. Rounds 1–2 are sleepy (0 damage in round 1), then the late rounds turn into a boulder avalanche. |
| 8 | Strategic depth and balance | 5 | The charge doctrine drives straight into boulders: they did 496 of the 690 damage I took in round 6. The leader bounty paints a target on the aggressor, and my 477 kills (most of anyone) were worth nothing at the end. |
| 9 | PvP and multiplayer fun | 6 | The lobby is solid and ram kills are hilarious, but the newbie was farmed and knocked out first, and spectating is dead air. |
| 10 | UI and UX | 7 | The workshop layout, hotkeys, convoy ready list and crossed-out taken paints are all good. Issues: a ghosted "HIVE RETREATS" banner sits behind the cards, an eliminated player still gets the full workshop, black paint is hard to read, and on the client game-over screen the "waiting for host" tag overlaps the panel. |
| 11 | "One more run" factor | 7 | I hit Rematch straight away to try a flamer or berserker build that dodges boulders. Whether my friends would is less sure. |
| 12 | Technical quality | 8 | No crashes or stalls, and the deterministic replay was quick. Only cosmetic problems: overlapping banners, camera framing, and small-font M/N mix-ups ("MAD MAREK" reads "NAD NAREK" in the menu preview). |

## Observations

### Spectacle and vehicle fantasy
- The late-round frames are lovely: a pile of cyan-veined boulders and glowing spitters around my rig in round 6 is a screenshot you would put on the store page. The early rounds are thin, with a handful of mites and tiny muzzle sparks.
- **Rigs don't grow visually.** After Spiked Plating, Nitro L2, Ablative Scrap, Berserker and 7 tech tiers, my rig looked like the starter truck with a few extra spikes. For a Crossout or Mad Max fan, half the fun is seeing the bolted-on junk. Nitro should leave flame trails, Ablative Scrap should add slabs, and a second gun should show a second barrel.
- **Big moments land quietly.** A ram kill on a friend leaves a dark wreck: no big fireball, no screen shake, no "SAM RAMMED RANDOM" in a kill feed. On LAN night those are the moments everyone yells about.
- Paint is the only thing that tells rigs apart, and it is only a small accent on a shared orange-and-grey body. On a shared TV, or when you glance at a friend's screen, it reads poorly. Rivals carry name tags; my own rig doesn't.

### Lobby and multiplayer flow
- **Menu:** the name and paint picker sits right on the main menu with a live preview of the rig in your colour. That's great: everyone can sort out their identity before they even join.
- **Join:** the auto-discovered LAN list shows host, address, rigs (3/8) and status, plus a direct-IP field pre-filled with `192.168.1.` It's the right amount of friction. A game already "in match" is struck through, which is clear.
- **Lobby:** numbered slots, a host badge, a READY or NOT READY tag per player and a "2 / 3 ready" counter. **Roll Out** waits for ready and **Force Start** doesn't wait, which covers the "Dave is still getting a drink" case. Paints that are already taken are crossed out, so there are no colour fights.
- **What's missing in the lobby:**
  - an "add bot" button to fill empty slots when only 2 friends show up;
  - a kick or swap control for the host;
  - any game settings (round length, PvP start round, map).
- The black "Nightcrawler" name needed a light label patch behind it to be readable. It works, but it looks like a bug. Black and dark-blue paints are weak choices on this UI.
- **Pause (LAN):** the menu says "the fight goes on – your rig drives itself" and repeats the controls. That's honest and handy for friends who forgot the keys.
- **Game over:** a clean table of fuel, kills and tech per rig, "Favourite part", **Enter – Rematch** for the host and "waiting for the host to call a rematch" for clients. The rematch loop is there and it's one key. It is thin on bragging material, though: no awards, no "who killed whom", no damage dealt.

### Newbie experience (the NEVER UPGRADE friend)
- Round 4 is the first round with PvP, and he was **destroyed 3 seconds into it**, by me.
- All four of his deaths were mine (two rams and two shot kills). He was eliminated in round 6, about 6–7 minutes into a 10-minute match, then watched for about 3 more minutes.
- His fuel went 100 → 70 → 40 → 10 → 0. Nothing slowed the snowball: there was no respawn shield, no underdog scrap or fuel, and nothing stopped "players first" from homing in on the weakest rig.
- **What an eliminated player sees:** the camera stays on his own wreck, the HUD shows HP 0 and fuel 0, and the doctrine bar is still there. In the workshop he still gets the full screen: scrap counter, buildable-looking tech buttons, a reroll button, "no parts left in the pile" and a Roll Out button. He can't follow the fight or do anything. On a real LAN night he would pick up his phone.
- The same thing happened to me, the host, in round 7, so even good players spend the end of the match as passive spectators.

## Top 5 issues (by impact)

1. **Newbies get farmed and knocked out first.** The weakest rig died the moment PvP turned on, kept dying to the same player and was out with 2 rounds to go.
   - *Suggestion:* give 3 seconds of respawn and round-start invulnerability, plus PvP-on grace for the first 10 seconds of round 4.
   - Make "players first" prefer the leader or bounty target rather than the nearest or weakest rig.
   - Add an underdog bonus for the lowest-fuel rig: smaller fuel loss per death, or extra scrap.
2. **Being eliminated is dead air.** The camera stays on your own wreck and the workshop UI stays up as if you could still act.
   - *Suggestion:* when you're out, auto-follow the closest fight or the leader (cycle with Tab or arrow keys), replace the workshop with a spectator panel (live standings, who is building what) and swap the HUD for "SPECTATING: BALANCED".
   - Better still, give ghosts something to do: a scavenger drone that drops scrap to a chosen friend, or calling in one alien wave on the leader.
3. **The rig doesn't visibly grow, and rigs look alike.** Six cards and seven tech tiers changed almost nothing on the sprite, and paint is a small accent.
   - *Suggestion:* give each card a visible bolt-on (bigger spikes per Spiked Plating level, nitro exhaust flames, ablative slabs, a second barrel per gun) and grow the hull with engineering tiers.
   - Paint larger panels in the player colour, and give your own rig a name tag or coloured ground ring too.
4. **Big moments aren't celebrated.** Ram kills, rival destructions, "PvP is on" and "bounty on the leader" all pass silently (I only learned about the bounty from the summary).
   - *Suggestion:* add a big explosion with screen shake and a kill feed line ("SAM rammed RANDOM"), a full-width "PvP ON" banner at round 4, and a visible bounty skull over the leader.
   - On the game-over screen, add LAN-night awards: Most Rams, Top Hive Killer, Most Deaths, "Nemesis: SAM → NEVER UPGRADE". I had the most kills by far and came 3rd with zero recognition.
5. **The ram fantasy fights the boulders, and the flashy weapons are rare.** The charge doctrine drives straight into boulders: 496 of the 690 damage I took in round 6, and it caused one of my two deaths in round 7. I saw no flamer in 21 cards, and there are only 2 gun slots.
   - *Suggestion:* have spiked and berserker rigs take reduced contact damage, or reflect it, so ramming is a build rather than a trap.
   - Teach the charge AI to route around boulders unless it's going berserk.
   - Weight the early offers towards weapon variety, so flamer or cannon builds can start by round 2 or 3.

## What I loved

- **The setup flow is genuinely LAN-ready:** name and paint on the main menu with a live preview, an auto-discovered game list, a prefilled IP, ready-up with Force Start, crossed-out taken paints and one-key rematch. Getting 4 friends in takes under a minute.
- **Ramming a rival to death with a spiked, nitro-boosted truck** (the summary says "ram by SAM" five times) is exactly the Mad Max moment I came for. Charge plus players-first does what it says.
- **The late-round art:** cyan-veined boulders rolling in among glowing spitters, with tyre tracks churned all over the dunes, looks fantastic.
- **The workshop is readable from the couch:** big cards with level pips, a clear tech grid, the doctrine terminal with a one-line explanation ("rams straight in / rival rigs before aliens") and a convoy panel showing who is still tinkering.
- **Match length:** about 10 minutes with short workshops is perfect for "one more" between pizza slices.
