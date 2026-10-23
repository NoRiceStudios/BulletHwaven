# BulletHwaven: Game Design Proposal (working title)

> Status: design draft v2, gameplay and art direction only. Nothing technical yet.
> Pitch: a multiplayer PvPvE auto-battler survivor. AI-driven armoured war rigs fight alien hordes and each other on a desert planet, with roguelike drafts plus a tech tree. Last convoy standing wins.

---

## 1. Evaluation of the original idea

**What's strong**
- **Clear, marketable fantasy.** "My war rig grows from a rusty buggy into a rolling fortress of guns" reads well in one screenshot. That's the Wanderburg hook (the base that grows and moves) mixed with the Vampire Survivors hook (the screen fills with bullets).
- **Auto-control fits the genre.** Survivor-likes already cut input down to movement. Handing movement to an AI and moving the skill into *build + behaviour tuning* is a logical next step, and it's a real gap in the market. Auto-battlers (TFT, Backpack Battles, The Bazaar) show that "build, then watch" can be very competitive.
- **Upgrades as a reaction to enemies** (both NPC and players) gives the drafts a purpose. You're not just picking the best card, you're picking a counter.

**Risks to design around** (each is addressed below)
| # | Risk | Why it matters |
|---|------|-------|
| R1 | **"Idle" vs. real-time PvP** | Idle means low attention and offline progress. Last-man-standing needs everyone present at the same time. These pull in opposite directions. |
| R2 | **Lack of agency** | If the AI drives and shoots, players can feel like spectators, especially when they lose. |
| R3 | **Early elimination** | Dying in minute 4 of a 25-minute match and then waiting or leaving is the classic battle-royale frustration. |
| R4 | **Snowballing** | Kills give currency, currency gives power, power gives kills. The leader runs away with the match. |
| R5 | **PvP vs. PvE balance** | One stat curve has to work against hordes (AoE, sustain) and against single vehicles (burst, armour piercing). |
| R6 | **Third-partying / kingmaking** | In a shared arena, the player who stays out of fights and picks off the weak often wins. |
| R7 | **Matchmaking population** | 8-player real-time matches need a large player base. Indie games often die on this. |

**Verdict:** The idea is strong and unusual. I recommend one reframe: it's an **"auto-battler survivor"**, not an idle game. The minute-to-minute play is hands-off (idle feel), but the agency is in build decisions, AI doctrine and a few well-timed active abilities. The real idle part (offline progress) moves into the meta layer between matches (section 9).

---

## 2. Design pillars
1. **Build, don't steer.** Skill is expressed through vehicle layout, card choices and AI doctrine, not reflexes.
2. **The rig grows.** Your vehicle visibly gets bigger, heavier and more absurd every round (Wanderburg).
3. **Read the wasteland.** Every round tells you what's coming (monster type, rival builds) and rewards adapting.
4. **Everyone's in until the end.** No dead time: eliminated players stay involved.
5. **No two matches alike.** Enemies, biomes and events are recombined every match, so the horde forces you to improvise (section 7).
6. **Matches of 20–25 minutes**, clearly split into phases.

---

## 3. Core loop

```
┌─ MATCH (8 players, ~20–25 min, ~14 rounds) ───────────────────────────┐
│                                                                        │
│  [ CONVOY PHASE 45–70 s ]  ──►  [ WORKSHOP ~120 s ]  ──►  next round   │
│   AI drives & fights           Draft 1 of 3 cards (free)                │
│   Collect scrap                Spend scrap: tech tree / rerolls         │
│   Use 1–2 active abilities     Place modules on the chassis grid        │
│   Adjust doctrine live         Adjust doctrine, scout opponents         │
│                                                                        │
│  Every 4th round: BOSS round · from round 6: zones merge → more PvP    │
│  Last convoy standing wins                                             │
└────────────────────────────────────────────────────────────────────────┘
        │ XP, blueprints, cosmetics
        ▼
  META: base camp / garage (idle production, unlocks, drivers)
```

**Pacing (horde pass):** combat is the reward, but the workshop gets enough time to set up parts, tech and rules (120 s, ending early once every player is ready) and combat is long and dense: 45 s in rounds 1–2, 70 s from round 3. Difficulty comes from mass, not sponges: mites arrive in packs (3 in round 1 rising to 8, clustered at one edge point), the alive count climbs to roughly 30–60 by mid round 1, 150 at the peak of round 5 and 300+ by round 10, while alien hp scales gently (+7 % per round plus a small quadratic term). Each combat follows a wave curve: build-up, a first surge at about 35 % of the round, a short lull (6 s), then a final surge that runs until the end-of-round retreat. The sim emits a `surge` event 2 s before each surge so the HUD can show a SWARM INCOMING banner. Mites pay a fraction of a scrap per kill so a bigger horde does not inflate the economy.

**Workshop phases run simultaneously for everyone** (like TFT), so the multiplayer stays fair and synchronous. Vehicles stop in a safe spot during the workshop (story framing: "the convoy makes camp").

---

## 4. The vehicle: chassis grid (the Wanderburg core)

The vehicle isn't a list of stats. It's a **top-down module grid**, like Wanderburg's castle and the Backpack Battles inventory:

- **Start:** a small buggy with a 3×4 grid, one weak machine gun, scrap armour, a weak engine.
- **Modules occupy cells:** weapons (on hardpoints at the edge), armour plates, engine, fuel tank, ammo crates, generators, crew seats, special devices.
- **Adjacency synergies:**
  - Ammo crate next to a ballistic gun: +fire rate
  - Generator next to a tesla coil: +chain range
  - Fuel tank next to the flamethrower: +range, but it explodes when hit (risk/reward)
  - Armour plates on the outer edge protect modules behind them; destroyed modules stop working until the next workshop (localised damage instead of a bare HP bar)
- **Weight vs. power:** every module weighs something, and the engine supplies power. Heavy means slow but tanky; light means fast and kiting. This is the central build tension.
- **Facing matters:** weapons have firing arcs (front, side, rear, turret 360°). This makes AI driving behaviour relevant (section 6).
- **Growing the rig:** tech unlocks **chassis upgrades** (buggy → pickup → truck → war rig) and **trailers**. Each trailer adds a grid segment, so the vehicle literally becomes a convoy. A 3-trailer war rig in the late game is the hero image.

---

## 5. Upgrade systems: draft + tech tree

Two systems with clearly separate jobs:

| | **Draft (roguelike)** | **Tech tree (deterministic)** |
|---|---|---|
| Answers | **WHAT** do I have? (new modules/effects) | **HOW GOOD / HOW MUCH** is it? (stats, slots, rules) |
| Cost | 1 pick of 3 per workshop, free | Scrap, prices go up |
| Randomness | High (rerolls cost scrap) | None, always plannable |
| Feeling | Surprise, build identity | Long-term plan, control |

### 5a. Draft cards (4 categories, as in the pitch, plus rarity)
- **Weapons:** MG, shotgun cannon, harpoon (pulls enemies in, PvP grapple), flamethrower, mortar, tesla coil, rocket pods, mine layer (rear), sawblade ram (front), flak (needed against flying monsters).
- **Armour:** steel plates, spiked plating (contact damage), reactive armour (vs. explosives), energy shield, repair drone, ablative scrap (cheap, regrows).
- **Mobility:** V8 engine, nitro, caterpillar tracks (slow, ignores terrain), off-road tyres, hover kit (late game, ignores mines).
- **Behaviour mods (the most interesting category):** they change *how* the AI plays. Examples:
  - *Berserker Doctrine:* +40% ram damage, the AI prefers ramming
  - *Ghost Driver:* the AI keeps maximum distance, +range
  - *Scrap Magnet:* the AI makes detours for loot, +pickup radius
  - *Vulture:* the AI targets damaged players, +damage vs. targets under 30% HP
  - *Circle of Death:* the AI circles enemies, side weapons +50%
- **Duplicates level up** (2× = level 2, 3× = level 3, as in TFT/Brotato).
- **Evolutions** (Vampire Survivors): a weapon at max level (3) plus a specific partner card (any level) evolves. **As built:** while eligible, the evolution card (category `evolution`, rarity legendary) replaces offer slot 0 in every draft, rerolls and bonus offers included, so you see it at once; picking it evolves the weapon in place (same slot, same kind, no extra slot) and it is never offered again. The card text names both ingredients and the result. Tech-tree multipliers still apply on top. Four evolutions are built (numbers replace the level 3 row; DPS vs a dense swarm roughly 2.1-2.7x level 3, single target 1.2-1.5x):
  - *Gatling Hell* (Machine Gun + V8 Engine): double fire rate (30 shots/s), 4.5 damage, pierce 1, wider spread, range 275.
  - *Meat Grinder* (Scatter Gun + Spiked Plating): 12 pellets, 4 damage, pierce 2, range 195.
  - *Earthshaker* (Siege Cannon + Caterpillar Tracks): 56 damage, splash radius 38, pierce 3, range 345.
  - *Inferno Spout* (Flamethrower + Nitro Injection): range 150, pierce 5, burns every target it hits, and drops short fire zones (1.5 s, one per five shots) along the stream.
  - Not yet built: harpoon + V8 -> *Chain Drag* (drags enemies behind you). The visual pass (evolved turrets, projectiles, card style) is still to do; the sim exposes `evo` on each weapon and `EVO_BIT` on shots.
- **Rarity:** common, rare, epic, legendary. Tech raises the chance.

### 5b. Tech tree v2.3 (per match, resets every match)
Five branches of six stages, 61 nodes plus 11 fusions = 72 nodes, far more than one match's scrap can buy (playtest feedback: the first 15-node tree was "too small"). Every match you commit to one or two lines and leave the rest. The full node table (ids, effects, costs, requirements, respec rules) is in `docs/tech-tree.md`; the numbers were checked with the bot league (`docs/balance/tech_v2/report.md`). Each branch has one signature mechanic you can see on the rig:
- **Ballistics (ammo):** *load different ammo against different enemies.* Fire, shrapnel and armour-piercing ammo, loaded per weapon, auto-loaded into half the guns when unlocked; per-ammo tracers and muzzle flashes.
- **Engineering (chassis):** *your rig grows: more guns and hp, but heavier.* Buggy, pickup, truck, war rig with trailer (section 11b).
- **Propulsion (momentum):** *driving fast charges momentum, momentum powers ramming and nitro.*
- **Electronics (commands and abilities):** *your rig learns new orders and abilities.* Rule slots and conditions for the doctrine (section 6), plus the active abilities nitro, EMP, smoke and salvo (two slots, auto-cast by a stated rule, rules or a key override it).
- **Salvage (contracts):** *more scrap, contracts, and scrap as a weapon.* Interest, reroll discounts, loans, the scrap press, the scrap baron.

Structure:
- **Six stages per branch:** 1 core (100 scrap), 2 style, pick one of two (140; salvage one of three), 3 core (240, needed for stage 4) plus an optional **prototype** (180, fixed drawback, opens nothing), 4 specialisation, pick one of three (380), 5 mastery, pick one of two (520), 6 keystone, pick one of two (750). Siblings lock each other for the match unless you respec. One branch to its keystone costs 2,130 scrap; a focused good player gets there around round 9-10, a two-branch build reaches its first keystone around round 12-14.
- **Depth pays:** stages 5 and 6 are clearly stronger than stages 1 and 2; five stage-1 entries are never a must-buy. Prototypes trade a sharp drawback for a quick power spike. Equal bonuses add up; tooltips show the net value including the drawback.
- **Fusions:** 6 small (200 scrap, two stage 2 choices from different branches: Thermite Ram, Spotter, Hot Rod, Barbed Wire, Lucky Strike, Fortified Relay) and 5 large (450, a stage 4 choice plus a stage 2 choice of another branch: Burning Wake, War Machine, Scrap Storm, Junkyard Drone, Thunderclap). A fusion greys out while a part is missing, for example after a respec (re-buying it costs half). Every build plan has at least one fusion inside its own two branches.
- **Respec:** swap a stage 2, 4 or 5 choice for a sibling: full refund, full price of the new node; the first respec of a match is free, later ones cost 50% extra. A keystone can only be swapped in the workshop right after buying it. Follow-up nodes stay; chains (Truck Chassis, then War Rig) grey out and the tooltip says so before you swap.
- **Onboarding (UI):** three **build plans** pick two branches and give an ordered path with a three-line cheat sheet: FIREBRAND (ballistics + propulsion: burn everything, drift through the fire), FORTRESS (engineering + electronics: a big self-repairing rig with smart guns), SCRAPPER (salvage + ballistics: contracts and interest, then scrap as ammo). The **beginner view** (first three matches, switchable) opens only the plan's two branches and folds the others under MORE. Glossary words are underlined with a one-line explanation; hovering a node shows the net change on your own rig ("avg DPS 38 > 45") and a "good if you ..." line.
- Per-weapon choices tie the tree to the draft (section 5a): a flamer build wants Belt Feed and Napalm, a cannon build Heavy Shells and HE Shells.
- **Weapon slots:** start with 2, at most 5 (Pickup Chassis, Auxiliary Mount, Sidecar Gunner, War Rig, Featherweight).
- **UI (tech tree v2.3):** the TECH view shows one column per branch with its one-sentence pitch, six stage rows (choices side by side, the prototype clamped to the stage 3 core, keystones with brass corners) and two fusion rows tagged with their two parts; states read at a glance (built, build now, need scrap, locked, struck-out SWAP, idle / dormant, the plan's NEXT). The detail panel of the hovered node gives the effect, what you see, "good if you ...", the net preview, fusion partners, the swap price and what a swap greys out; a swap always asks first. PARTS also holds the ammo per gun (LOADED: ...), the two ability slots and a compact tech column (stage pips per branch, the plan's NEXT buy button, FUSION READY).

**Interest mechanic (TFT):** 10% of the scrap you hold at the end of each round (cap 5 + 2 per round, raised by Salvage tech). This creates a "save or spend" decision.

---

## 6. AI doctrine: the player's steering wheel

This answers R2 (agency). Inspired by the **Gambit system from Final Fantasy XII** and *Gladiabots*:

**Layer 1: basic settings (always available, sliders/toggles)**
- **Driving style:** Kite / Circle / Charge / Hold Position / Patrol
- **Engagement distance:** close ↔ far
- **Target priority:** nearest / strongest / weakest / players first / monsters first / boss
- **PvP stance:** Avoid / Opportunistic / Hunter
- **Retreat threshold:** retreat to repair below X% HP

**Layer 2: rule slots ("if → then"), unlocked through Electronics tech**
- Start with 1 slot, up to 5 in the late game. Examples:
  - `IF HP < 30% → use smoke + drive away`
  - `IF player within range AND their HP < 50% → Hunter mode`
  - `IF Swarm > 20 → Circle + activate Mortar`
  - `IF boss active → Kite at max range`
- Doctrine can also be changed **during** the convoy phase. Attentive players gain an edge without it being required (idle-friendly).

**As built (rule editor, after playtest feedback "behaviour must be programmable and set per weapon"):**
- Rules exist for the **rig** (driving style and target) and for **every gun on its own**. Each gun has a base target (*follow the rig*, nearest, strongest, weakest, rivals first, boulders, spitters) and its own rule list, so a cannon can hunt the toughest alien while the MG clears mites around the rig.
- A rule is `IF condition [AND condition [AND condition]] THEN action`. Conditions: own HP %, aliens near, rivals near, target distance, target HP %, target is a rival / boulder / spitter, PvP on, has a target. Rig actions: circle, kite, charge, **flee**, **hold position**, or a target mode. Gun actions: a target mode, or **hold fire** / fire at will (for example "hold fire on boulders" to save the cannon for big aliens).
- **Control zones (section 8):** conditions IN ZONE, ZONE DISTANCE (px to the nearest zone you do not hold), ZONE CONTESTED (a rival is in or capturing your zone), ZONES HELD (0 to 3); drive `drive:zone` (HOLD ZONE: drive into the nearest zone, preferring ones you do not own, and orbit its centre while the guns keep firing; a base drive too, key 4 in the picker) and target `target:intruders` (rivals inside or next to the zone you are in or own, else the nearest alien; for the rig and for every gun). All are free from the start (no tech). Example: `IF PvP on AND HP > 40% THEN hold zone; IF in zone AND rivals near THEN target intruders`.
- Rules run top to bottom; the first matching rule of each kind wins (driving and target are separate kinds), otherwise the base setting applies. This keeps lists short and readable like FF XII Gambits.
- Slots: 2 per list to start, +1 per Electronics tier (so 5 with the full branch); rules beyond the slots stay saved but locked.
- The editor (key **P**, or PROGRAM RULES on the workshop's nav-comp) works in the workshop and during combat. Each rule is also shown as a plain sentence, a lamp lights while a rule matches, and quick-add templates cover the common cases (retreat below 30% HP, kite when swarmed, save ammo on boulders, ...). The HUD shows which rig rules are firing.

**Live control (as built, after playtest feedback "I want to adjust my rig's behaviour during the round and set it once before round 1"):**
- **Deploy phase before round 1** (30 s, ends early when everyone is ready): every player picks a starting doctrine from five presets (Orbiter, Long Gun, Brawler, Headhunter, Zone Holder: base drive, base target and two rules each, all usable by a fresh rig) and can tune it in the rule editor next to them.
- **Behaviour picker in combat:** a click on the dock's DRIVE / TARGET block opens a strip above the dock to switch the base drive and base target with one click; it shows the keys (1 2 3 drive, Q W E target) and which rule overrides the base right now. The full editor stays on **P**.
- **Target mark (right-click):** during combat the player right-clicks an alien or (with PvP on) a rival rig. For 6 s every gun and the rig's targeting focus it (the drive mode is unchanged); the order then cools down for 15 s, counted from the cast. A miss costs nothing, and the mark ends at once when the target dies. Rules can react with the condition `MARK ACTIVE` (e.g. charge while a mark is on). Bots never use it.
- **Radio commands (Z X C V or the radio panel):** 3 radio charges per round. FALL BACK, ALL IN, HOLD and BOSS override all rules and the base setting for 5 s (fall back = flee, all in = charge with all guns on the rig target, hold = stand still, boss = target the boss, or the nearest alien without one); a short lock between two calls prevents wasted double presses. Rules can react with the condition `RADIO ACTIVE`. Bots never use it.

- **Rule editor overhaul (as built, after playtest feedback "some dropdown entries cannot be picked; I want more logic and a target priority list"):**
  - **Target priority list** per rig, and per gun if wanted: the eight kinds (boss, shrieker, spitter, brood carrier, glass wings, boulder, mite, rival rigs) in the player's order, each switchable off ("never shoot this with the list"), plus how to choose within one kind (nearest / weakest / toughest). The base target or a rule (`TGT PRIORITY LIST`) uses it: the first kind with something in range gets shot. A gun can follow the rig's list or keep its own (**Targeting Computer**).
  - **More logic:** rules can be switched off without deleting them; **ANY** rules (one true condition is enough, **Rangefinder**); **stay on N s** (a rule that matched keeps running for 1 to 5 s so the rig does not flip back and forth, **Targeting Computer**); new conditions mites / spitters / flyers near, momentum, target is a mite / flyer / brood carrier / shrieker / boss (free), under fire and round time (**Radar Array**); new targets mites, flyers, brood carriers.
  - **Editor UX:** base behaviour and priority list on the left, rules on the right as one-line summaries; a click unfolds a rule into an edit card with one condition per line. Every list opens as a grouped picker that always fits on screen, explains the hovered entry and names the tech for locked ones. Ready-made rules sit in the NEW RULE picker (locked ones visible, with the reason), UNDO / Ctrl+Z reverts any edit, and warnings flag rules that can never run (an always-true rule of the same kind above them, no slot, locked).
- **Live rule monitor:** a panel on the right edge lists the rig's and every gun's rules during combat, lights each condition while it holds and marks which rule WINS right now (L hides it).

**Layer 3: active abilities (1–2 slots, optional)**
- Nitro, EMP, smoke, oil slick, overcharge. They have cooldowns and can be set to **auto-cast** (idle players) or triggered by hand (active players get a slight advantage through timing).

---

## 7. Enemies: variety and randomness

**Goal:** you should never know exactly what's coming, but you should always be able to react. Randomness works on several layers that combine with each other. That gives thousands of combinations, while each layer on its own stays readable.

### 7a. Layer 1: species (the base pool, about 12)
The aliens are the planet's **native wildlife**. They have evolved from sand, salt, stone and glass (see art style, section 11). Each species tests a different part of your build or doctrine:

| Species | Behaviour | Tests / counter |
|---|---|---|
| **Sand Mites** (swarm) | Huge numbers, weak, swarm out of dunes | AoE, flamethrower |
| **Boulder Backs** (brute) | Tanky armoured beetles, ram | Armour piercing, kiting |
| **Spitters** | Ranged acid that corrodes armour | Speed, shields, closing in |
| **Dune Worms** (burrowers) | Dig up under the vehicle | Rear weapons, mines, keep moving |
| **Glass Wings** (flyers) | Ignore terrain and rams | Flak, tesla (**built**, see 7a "As built") |
| **Leeches** (sappers) | Latch onto the vehicle and eat modules | Spiked plating, electric shock, ramming walls |
| **Brood Carriers** | Slow; burst into a swarm when they die | Kill them at range, AoE (**built**) |
| **Shriekers** (support) | Buff and heal nearby aliens, stay at the back | **Target priority** in doctrine ("support first") (**built**) |
| **Hive Nests** (stationary) | Keep spawning until destroyed | **Aggression** in doctrine (attack vs. avoid) |
| **Mimics** | Look like scrap pickups or rocks | Loot greed in doctrine (Scrap Magnet becomes a risk) |
| **Stalkers** (camouflaged) | Invisible until close, burst attack | Radar tech, armour |
| **Tripod Walkers** (mini-boss) | Huge, slow, artillery | Burst DPS, mobility |

**As built (lever 2: variety).** Three species beside mite, boulder and spitter; the numbers live in `sim/species.gd` and `SimWorld.ENEMY_*`.
- **Glass Wings** (hp 7, speed 190, radius 7): flocks of 4 share a 5 s cycle (hunt, dive for about 1 s, pull away). They only hurt a rig while diving (contact 1.0 per tick of overlap). Rams, ground effects (embers, oil, smoke), the flamer and splash do not touch them; MG, scatter, cannon and direct hits do. Their shadow sits at (7, 12) from the body, so they read as flying. Chance per mite event `0.07 + 0.015 n` (max 0.17), alive cap `4 + 2n` (max 14), n = rounds since their first round.
- **Brood Carriers** (hp 70, speed 28, radius 17): slow, tanky. They burst into 6 to 8 sand mites (after a 0.2 s burst frame) when shot dead, but not when the kill came from fire, burn or splash: the brood dies with the carrier. Chance `0.05 + 0.012 n` (max 0.12), cap `2 + n` (max 8).
- **Shriekers** (hp 14, speed 50): hold 250 to 320 px from the nearest rig behind the horde. Every 5 s a ring (radius 90 px, telegraphed by a charge-up pose) heals nearby aliens by 20% of max hp and hastes them (x1.35 speed for 3 s). Bosses are not affected. Chance `0.05 + 0.01 n` (max 0.10), cap `2 + n/2` (max 5). Doctrine: target mode "shriekers", condition "shrieker near".

On top of these come **neutral fauna**: herds of grazers that can be farmed for scrap but stampede when shot at, and scavengers that attack whichever vehicle (player *or* monster) is weakest.

### 7b. Layer 2: mutations (random affixes, Diablo / Risk of Rain elites)
Every enemy can carry **0–3 mutations**. The number and strength go up each round. Examples:
- **Hardened:** +armour, immune to the first X hits
- **Splitting:** splits into two smaller copies on death
- **Volatile:** explodes on death (bad for ram builds)
- **Regenerating:** heals unless burned
- **Swift:** +50% speed
- **Acid Blood:** damages the vehicle on contact or ramming
- **EMP Glands:** briefly disable electronics (doctrine rules, active abilities)
- **Magnetic:** pulls vehicles in and disrupts kiting
- **Hive-Linked:** shares damage with nearby aliens (kill them all at once)
- **Reflective Carapace:** reflects part of energy damage (tesla, laser)
- **Burrowing:** a species that normally walks can now also dig

**Champions:** occasionally an enemy spawns with 3 mutations, a name ("Old Grandmother Saltjaw") and a guaranteed rare drop.

### 7c. Layer 3: the hive signature (random per match)
At the start of every match the planet draws a **hive signature**:
- **6–8 of the 12 species** are active in this match (the rest don't appear)
- **One dominant mutation** that shows up more often (e.g. "Volatile season": many enemies explode)
- **One boss trio** from the boss pool (section 7f)

The signature is **shown in the first workshop**. Your first draft and tech decisions become a bet on this match ("lots of flyers this time, so flak is worth it").

**As built (simplified).** The seed picks **2 of the 3 new species** (glass wings, brood carriers, shriekers). Each gets its own first round between 3 and 7, so one match can be glass wings from round 4 and shriekers from round 6. Mites, boulders and spitters are always in the pool. The boss order is the existing one (`Bosses.next_boss`). The first workshop shows a "HIVE SIGNATURE / THIS MATCH" panel with each species (ACTIVE, NEXT ROUND or ROUND n), a counter tip each, and the next boss with its round (ENRAGED when it will be). Later workshops show the short form. Mutations and the dominant mutation are not built yet.

### 7d. Layer 4: biomes (random per sector)
The map is assembled from random **biome tiles**. Each biome changes the spawn weights, the terrain and the driving:
| Biome | Effect |
|---|---|
| **Dune Sea** | Lots of worms and mites; slows wheels (tracks / hover help) |
| **Salt Flats** | Fast terrain, open space, flyers more common; sniper paradise |
| **Canyon** | Narrow passages, ambushes, Stalkers; good for mines |
| **Glass Crater** (old impact) | Reflective ground, Glass Wings, crystal resources |
| **Wreck Field** (crashed colony ship) | Lots of scrap, cover, Mimics hiding among the scrap |
| **Spore Basin** | Alien flora, nests grow faster, poison fog |

### 7e. Layer 5: the hive evolves (adaptive horde, anti-meta)
The hive **learns from the players**. From the middle of the match, the hive measures which damage type dominates across the lobby and develops a **resistance** to it over the following rounds (telegraphed: "The hive is adapting to fire…").
- This stops a single meta build from dominating.
- It creates an interesting PvP twist: if everyone plays fire, the one player who stayed with ballistics profits.
- Counter-cards: *Genetic Sabotage* (resets one adaptation), *Lure Pheromones* (redirect the adaptation onto another damage type).

### 7f. Bosses (pool with random phases)
*As built: see the end of this section. Two bosses are in (Tripod Queen, Shard Colossus), played in the boss rounds of 7j.*

A pool of about 8 bosses. Each boss has **3 phases**, and each phase is drawn from 2–3 variants, so the same boss plays differently. Examples:
- **The Dune Mother:** a giant worm that circles the arena; phases: devour / spawn brood / sandstorm
- **The Shard Colossus:** a crystal giant; phases: split into shards / laser refraction / regenerate from the ground
- **The Choir:** a group of three Shriekers that buff each other; they must die at the same time
- **The Tripod Queen:** artillery from the edge of the screen, places nests

**As built (boss rounds, lever 2: variety in combat).** Two bosses so far, fought in rounds 4, 8, 12, 16, 20 (7j). The match seed decides which one opens and they alternate (a match with seed s meets, say, Tripod, Colossus, Tripod, ...); the order is known at match start and the workshop shows "next boss in round N: NAME". From round 12 the boss is **enraged** (+25% speed, attack cooldowns x0.7).
- **Arrival:** a "<NAME> APPROACHES" plate 3 s before the first surge of the round (the ground churns and rumbles where it will surface, the screen edge pulses cyan), then the boss bursts out of the sand at the arena edge nearest your convoy. Regular spawns drop to 50% while it lives. Boss hp scales with the round and with the number of rigs alive (one shared pool in multiplayer, so it is a co-op fight with a bounty race). It has three phases at 100 / 66 / 33% hp; every change is announced (shake, event) and shown on the boss bar under the clock.
- **The Tripod Queen** (big, slow artillery walker): lobs shells at where your rig will be; a ground marker shows the impact circle for 1.2 s (drive out of it). Phase 2: also births mite broods from her body. Phase 3: volleys of three shells and a faster walk. Keeps her distance, so you have to close in or out-range her.
- **The Shard Colossus** (crystal brute): glows for 1 s, then fires a ring of slow crystal shards (gaps are dodgeable). Phase 2: charges at the nearest rig along a marked lane (like boulder charges, only bigger). Phase 3: it splits into three shard minibosses (1/6 of its full hp each, smaller rings); the fight ends when all three are dead.
- **Ramming** a boss does reduced damage and hurts you; EMP only slows it. **Reward:** every rig that dealt at least 10% of its hp gets a scrap bounty (25 + 6 x round), the killing blow double, plus the killer's next draft has 4 offers with one guaranteed rare-or-better card. A boss still alive when the round timer ends retreats (it burrows away; no penalty, no bounty). A kill gets a multi-stage death (sac pops, a crystal burst, a scrap fountain) and a "<NAME> DOWN" banner with the killing blow and the bounty.
- **Doctrine:** the rig and gun target `boss` (nearest boss body in range, else the nearest alien) and the rule condition `boss active`; `strongest` picks the boss too.

### 7g. Layer 6: events (random during rounds)
- **Sandworm crossing:** a gigantic, invulnerable worm crosses the map, and everything in its path is destroyed (players *and* aliens). It's telegraphed by ground tremor.
- **Hive Bloom:** nests suddenly appear everywhere.
- **Migration:** a stampede of grazers. Lots of scrap, lots of danger.
- **Meteor fall:** crystal aliens hatch from the impact craters; legendary loot.
- **Night round:** darkness, aliens glow, headlights matter (light module!).
- **Sandstorm / spore storm:** reduced range, enemies with Camouflaged get stronger.
- **Supply drop:** contested PvP loot.

### 7h. Nemesis system (PvPvE twist)
When a **Champion kills a player**, it survives, levels up, gains a mutation and **comes back** in later rounds as a named nemesis, possibly to a *different* player. Whoever kills it gets a large bounty. This creates stories ("Saltjaw has killed three of us already!") and links the PvE and PvP sides.

### 7i. Randomness stays fair: readability rules
- **Telegraph before surprise:** the next round shows species + 1 mutation. The second mutation is revealed only during the round, or earlier with radar tech.
- **Every random element has a counter** in the card pool.
- **Underdog protection:** spawn randomness is *the same* for all players in a round (same species and mutations, only positions differ), so it decides the challenge, not the winner.
- **Clear visual language** for mutations: each one has a consistent visual feature (glow colour, crystal growth, pulsing). Section 11.

### 7j. Round flow (example, about 14 rounds)
- **Rounds 1–3:** 1–2 species, no mutations, each player in their own sector (no PvP). Learn the build basics. *In the current build there are no sectors; the same rule is enforced directly: before round 4 (`PVP_START_ROUND`) vehicles do not target, shoot or ram each other. Section 8 notes the first anti-snowball rules that came with it.*
- **Rounds 4, 8, 12 (16, 20):** **Boss rounds** from the match's boss pool. Optionally a contested world boss. *As built: every 4th round, two bosses alternating from a seed-chosen opener, enraged from round 12; see 7f.*
- **From round 5:** mutations start appearing, the next round is announced, and random events become possible.
- **From round 6:** **the Blight** (a battle-royale zone) closes, sectors merge, and PvP becomes common. The hive starts to adapt.
- **Rounds 11+:** one shared arena, mixed species with 2–3 mutations, nemeses come back, final fights.

---

## 8. PvP: more than "shoot at each other"

**Layers of player interaction**
1. **Direct:** vehicles meet, and doctrine decides whether they fight or avoid each other.
2. **Indirect, sending monsters** (Tetris 99 / Legion TD / Bloons Battles): *Lure Beacon* cards or kill streaks send extra monsters into a chosen rival's sector. This makes PvP possible early without direct contact.
3. **Contested objectives:** supply drops, fuel depots, the world boss. *As built (control zones):* from round 4 (PvP) every combat has 1 to 3 circular **control zones** on the map, between the rig start ring and the centre (one fewer than the number of rigs, at most three; none in solo). A rig that stands alone in a zone for 3 s takes it; two rigs inside freeze it. While a rig owns a zone and stands in it, it earns 1 scrap per second; the owner may leave and keeps the flag until a rival holds it alone for 3 s. The rig with the most zone seconds in a round (at least 10, no ties) gets +5 fuel. During the round-4 grace the zones are visible but locked. *Look:* each zone is a scrap beacon (a rusty derrick on sandbags with a lamp and a pennant in the owner's paint; bone when free, furled while locked) inside a ring of stakes strung with tape in the owner's paint, so the zone reads above a horde; a capture shows as an arc in the capturer's paint, a contested zone flickers in hazard stripes with a red lamp. The HUD shows a zone panel left of the clock (owner badges, zones held, zone points), tags over the beacons, edge markers for zones off screen, captures in the kill feed, a ZONE column in the standings and a CONTROL ZONES OPEN banner. Doctrine reacts to them (section 6): conditions `in zone`, `zone distance`, `zone contested`, `zones held`, drive `hold zone`, target `zone intruders`. Details: `docs/architecture.md`, "Control zones".
4. **Wreck salvage:** a destroyed rival vehicle drops scrap **and one of its modules** that you can steal. This is very satisfying, and it's where your "upgrades react to other players" idea pays off.
5. **Scouting:** in the workshop you can inspect every rival's vehicle and doctrine (TFT) and counter-build. Example: rival X runs explosives, so I take reactive armour.

**Life system instead of instant elimination (against R3)**
- Each player has **Fuel Reserves** (e.g. 100), a TFT-style player-HP model.
- Vehicle destroyed = respawn after a few seconds, but you lose fuel (more if a *player* killed you, and the killer gets a bounty) **plus 1 random module**.
- Fuel 0 = eliminated. Destroying a rival steals 10 of its fuel loss (leader: 10 more), and from round 7 every rig in a multiplayer game loses 6+ fuel per round (never below 1 until round 18, after which the drain eliminates every rig but the one with the most fuel), so only kills offset it: passive play no longer wins by waiting. Solo has no drain.
- Result: a bad round is a setback, not game over. Elimination usually only happens in the second half.

**Anti-snowball (against R4/R6)**
- **Bounty on the leader:** the player with the most kills or the strongest vehicle is visible on the map and worth a big reward.
- **Underdog bonus:** players in the bottom places get +scrap and a better card rarity in the draft.
- **Third-party protection:** after a PvP kill you get a short shield / repair burst, so fights aren't pure losses.
- *Implemented so far (balance iteration 2):* the leader (most kills + scrap/10) is marked and worth 3x the normal kill bounty, and a player kill gives 2 s of halved damage taken. *Balance iteration 3:* the lowest-fuel player loses 30% less fuel per death; rigs are invulnerable for 3 s after a respawn and at each combat start; the first 10 s of round 4 are still PvP-free; repeat kills of the same victim in a round pay 100% / 50% / 0%; `players_first` hunts the leader before anyone else. The leader is ringed in hazard yellow on the combat minimap (bottom right, M toggles it), which also shows the alien density, every rig and the camera's view.
- **Separate PvE and PvP values:** damage against vehicles is calculated through its own armour layer (plating), so swarm-clearing builds don't automatically delete players.

**After elimination: the Horde Warlord (against R3)**
Eliminated players aren't out. They become **Horde Warlords**: with a small budget, they pick which monster packs to send at the surviving players. They keep playing, have a say in the outcome, and can earn small meta rewards ("Warlord kills"). This also gives eliminated players a reason to stay.

---

## 9. Meta progression and the idle layer (resolving R1)

The **idle part** of the pitch lives here, between matches, with **no power advantage in PvP**:
- **Base camp:** a settlement in the wasteland that produces scrap and fuel offline (idle buildings: scrapyard, refinery, workshop). It's spent only on **unlocks** and cosmetics.
- **Unlocks (horizontal, not stronger):** new cards in the draft pool, new chassis variants as starting options, new trailers, paint jobs and decals.
- **Drivers:** selectable characters with a passive and a quirk (Brotato characters). Examples: *Mechanic* (repairs faster, weaker weapons), *Gunner* (more weapon slots, less armour), *Smuggler* (more scrap, higher prices), *Cultist* (behaviour mods stronger, AI unpredictable).
- **Expeditions:** send your vehicle on PvE runs in solo mode while you're offline (real idle play, rewards only for the meta).

---

## 10. Game modes

| Mode | Players | Purpose |
|---|---|---|
| **Wasteland Royale** (main) | 8, real-time | The full design as described |
| **Ghost Raid** (async PvP) | 1 vs. recorded rival builds | Like The Bazaar / Backpack Battles. Solves R7: always playable, no waiting |
| **Endless Run** (solo PvE) | 1 | Classic survivor / idle experience, onboarding, expeditions |
| **Duo Convoy** | 4×2 | Two vehicles, shared fuel reserves, synergy builds |

**Strong recommendation:** develop **Ghost Raid + Endless Run first**. Async PvP tests the core fun (building + doctrine + counters) without needing a real-time player base, and real-time Royale comes later.

---

## 11. Art style and world

### 11a. Setting: the world in two sentences
Humanity's colony ship **crashed on a desert planet**. The survivors live off the wreck: every vehicle is welded together from ship parts, pre-crash machinery and alien bones. *We* are the aliens here, and the planet's wildlife is defending itself.

This explains the scrap economy (the wreck is the resource), the Mad Max look (improvised technology) and why the aliens fit the environment so seamlessly: **they are the environment.**

### 11b. Perspective and pixel art
- **Top-down view** (straight from above). Height is conveyed through **drop shadows** and slight overlap: tall objects (Tripod Walkers, rock towers, trailer superstructures) cast long shadows, so the map gets depth without changing perspective.
- **Detailed pixel art** with a deliberately **rough, worn look**: dithered gradients, scratches, dust, rust.
- **Rough size guide** (art direction, not technical):
  - Sand Mite: about 8–12 px · Spitter: about 16–24 px · Boulder Back: about 32–48 px · Tripod Walker / boss: 96–200 px
  - Starter buggy: about 32×48 px. A fully built war rig with trailers: 100–250 px long, so the vehicle growth is visible on screen.
- **Modules are drawn onto the vehicle.** Each module on the chassis grid is a visible sprite at its grid position (guns rotate, armour plates sit on the edge). From above, your build is readable at a glance, which also helps with scouting rivals.
  - *As built (draft cards, playtest round 1):* every card bolts something on. Each gun card has its own turret (MG, scatter gun, cannon, flamer) and its level shows (twin barrels, ammo drums, longer barrels, extra tanks); the second gun sits on the hood or flatbed, the third on the trailer. Steel plates add painted flank plates, reinforced hull adds girders, ablative scrap adds rusty slabs and tyres, spiked plating adds spikes that grow per level; V8 adds a blower, nitro adds bottles and exhaust flames while driving, tracks and off-road tyres swap the running gear; behaviour cards add a trophy or tool (magnet, horned skull, vulture skull, welding rig). The chassis follows the Engineering core (tech tree v2.3): buggy (with a welded frame once Engineering Frame is built), four-wheel pickup with a painted bed, six-wheel truck with a closed cab, and the war rig tractor with an articulated gun trailer. Tech bolt-ons show as well: dozer blade, roll cage, a sidecar carrying the last gun, jerrycans, a scrap pile, a repair drone circling the rig and the scrap baron's gold chain that grows with scrap. Paint covers the hood, the flanks and the plates so eight rigs stay apart; your own rig stands on a ring in its paint colour.
  - *As built (weapon evolutions, section 5a):* an evolved gun swaps its turret for a bigger, absurd scrap piece readable from above: Gatling Hell is a rotary barrel cluster with brass clamps fed by an ammo belt (spins, spits a white-hot tracer stream and brass casings), Meat Grinder a drum-fed flared maw with saw teeth (heavy slugs with spark trails), Earthshaker a long artillery barrel on spades with recoil cylinders (a giant shell, a big blast with a light camera shake and a scorch mark), Inferno Spout a bell nozzle on twin fuel tanks with a pilot flame (a thicker, longer flame stream). All shots stay warm. The moment it evolves the rig bursts with a warm flash and a brass "EVOLVED: <NAME>" banner slams in; the workshop card is legendary (gunmetal tag, brass frame, both ingredients -> result).
- **Damage is visible:** dented plates, smoke, fire, missing modules, alien goo on the bodywork.
- **Scrap-built, never factory-new:** every vehicle is patched together from mismatched panels (bare steel, rust, faded olive paint) joined by visible weld seams. Standard wear: bullet holes, dents, scratches, rust streaks, chipped player paint. Rugged add-ons break up the silhouette: spiked ram bars and hubs, chains, barbed wire, sandbags, tarp-covered cargo, jerrycans, ammo belts, trophies.
- **Organic ground, no repeating patterns:** dunes are built from irregular noise, never periodic stripes or tiles, and sand texture uses random grain instead of an ordered dither. Ordered (checkerboard) dithering is reserved for light and glow effects.

### 11c. Colour palette and readability
In a bullet heaven there are hundreds of objects on screen at once, so the palette has to deliver **readability**:

| Element | Colour logic |
|---|---|
| **Ground / environment** | Desaturated mid-values: ochre, rust, bleached bone, sandstone, cool blue-grey shadows (an orange/teal look as in *Fury Road*) |
| **Aliens (at rest)** | **Camouflaged in the environment colours.** Chitin in sand, salt and stone tones; Boulder Backs look like rocks |
| **Aliens (active)** | **Bioluminescence** as the only cold, saturated accent (toxic cyan/turquoise) on eyes, glands and wounds. When they attack, they light up, so the danger is readable |
| **Mutations** | Each mutation has a fixed visual feature: Hardened = crystal growth, Volatile = pulsing orange sacs, Regenerating = green veins, EMP = violet sparks, and so on |
| **Player vehicles** | Rust and steel plus **player colour** as paint stripes, flags and smoke trails (8 clearly distinct colours) |
| **Player projectiles** | Warm: yellow/orange tracers, muzzle flashes |
| **Alien projectiles** | Cold: acid green/cyan. They're **never** warm, so you instantly know what's dangerous |

**Core rule:** at rest, the aliens are part of the planet. In action, they glow. That serves both the fantasy ("they fit into the environment") and the gameplay (readability).

### 11d. Alien design: biology from the desert
The aliens look like **plausible desert ecology**, not like classic sci-fi monsters:
- **Mineral biology:** shells of sandstone, salt crystals, fused glass (Glass Wings have wings like stained glass)
- **Desert animals as the base:** scorpions, beetles, ant lions, sandfish, sidewinders, crossed with deep-sea creatures (bioluminescence, translucent bodies)
- **Hive structure:** nests look like termite mounds or crystal geodes; Shriekers have resonating crystal chambers
- **Camouflage as a game mechanic:** Stalkers and Mimics use exactly this look, so the art style *is* the gameplay

### 11e. Environment and atmosphere
- **Biomes** (section 7d), each with its own colour accent: Salt Flats (bright, almost white), Dune Sea (warm orange), Canyon (red-brown, strong shadows), Glass Crater (reflections, glittering), Wreck Field (rusty metal, scrap), Spore Basin (the only biome with alien-coloured vegetation).
- **Arena size:** an arena is 4 x 4 screens (2560x1440 px at the 640x360 view), so convoys have room to manoeuvre and spread out (playtest round 3: 2 x 2 screens felt small and cramped). Aliens still come in from just off-screen around the rigs, so a bigger arena means more room, not emptier fights. Landmarks (colony ship debris, giant ribs, rock clusters, old tyre tracks) are scattered, never tiled, so every part of the arena reads differently.
- **Persistent traces:** tyre tracks, wrecks, craters and goo stay on the map for the whole match. Late in the match, the map tells the story of the fights.
- **Day/night cycle:** night rounds with dynamic headlights, muzzle flashes as light sources, and glowing aliens. These are the planned "screenshot moments".
- **Weather:** heat shimmer, sandstorms (screen-filling dust particles), spore fog.
- **Background details:** giant bones of ancient creatures, colony ship parts, wind turbines made from wreckage, old landing beacons.

### 11f. UI style
- **Diegetic and improvised:** rusty metal sheets, stencil fonts, tape labels, hand-written markings.
- **Readability first:** the world is pixel art, but all UI text is set in clean, condensed fonts drawn at full screen resolution (a stencil display face only for the logo and big titles). Panels are dark and calm inside a rusty frame so text never sits on noisy texture; every line of text has room to breathe (no stacked rows touching).
- **Hierarchy over decoration (UI revamp):** one main task per screen, the biggest thing in the middle; things that belong together sit together; details on hover. Colour only with meaning: amber = scrap and actions, red = danger, cyan = the hive, paint = players. One look per role (information panel, tab, secondary button, one hazard-striped primary button).
- **Combat HUD:** the eye stays on the rig, so everything about your own rig (doctrine, HP, fuel, scrap, kills) is one dock at the bottom centre; round, clock and hive top centre; standings top left in multiplayer (fuel decides the match); kill feed top right; minimap bottom right.
- **Workshop:** a top-down view of the vehicle on a garage floor. Cards are like scrap tags or crumpled blueprints. A fixed top bar holds scrap, fuel, the views PARTS / TECH / RULES, the clock and ROLL OUT, so the clock and the button that ends it are always side by side; the body shows one view at a time (parts draft with your rig and last round, the full tech tree, the rule editor).
- **Doctrine:** looks like an old onboard computer / CRT terminal salvaged from the colony ship (green or amber monochrome), a nice contrast to the warm desert.

### 11g. Visual references
- **Hyper Light Drifter:** detailed pixel art, atmosphere, colour mood
- **Nuclear Throne / Enter the Gungeon:** top-down readability under chaos
- **Mad Max: Fury Road:** vehicle design, orange/teal colour grading, kitbashing
- **Dune:** desert ecology, worms, living with the planet
- **Nausicaä of the Valley of the Wind:** aliens as an ecosystem, not as evil
- **Starship Troopers / The Riftbreaker:** alien hordes, nests, top-down horde chaos
- **Death Stranding / Kenshi:** the feel of an empty, rough, beautiful world

### 11h. Combat feedback: the kill is the reward
The doctrine drives and the player watches, so watching has to feel good. Kill feedback scales with mass and stays readable in hordes of hundreds:
- **Kill bursts:** a mite pops in a white-cyan splat with a few chitin bits and goo droplets; a boulder cracks into hopping shell plates with a dust ring and a light camera jolt; a spitter bursts in an acid spray. Alien bits glow cyan only for the instant of death and cool to dark teal; shell and dust stay in the desert ramps.
- **Hits:** an alien that takes a hit flashes white for a frame (its dark outline stays). Cannon shells land with a hard white-hot star and kick at the muzzle (flare and a smoke puff).
- **Scrap:** kills of your rig throw warm scrap sparkles that fly into the rig; the dock's scrap number ticks up with a short pulse and a floating "+N".
- **Kill combo:** kills within 1.5 s chain; the counter ("x24") stands next to the rig, grows and warms from pale gold to deep fire, and calls out milestones in stencil: ROADKILL (10), SHREDDED (25), BUG BLENDER (50), HIVE BREAKER (100), WASTELAND LEGEND (200).
- **Surges:** two seconds before a hive surge a SWARM INCOMING plate drops in under the clock with a faint cyan pulse on the screen edges (cyan = the hive).

### 11i. Sound and music
Sound follows the colour rule of 11c: **our side is warm and mechanical, the hive is wet and glassy.**
- **Guns and rigs:** dry, punchy, scrap-built. Each weapon has its own voice (machine gun rattle, shotgun bark, cannon boom, flamer roar); rams crunch metal. Your own guns sit centred and slightly louder than everyone else's, so you hear your rig in a horde.
- **Aliens:** deaths are wet squelches and chitin cracks (mites small, boulders a rock crack with rubble, glass wings shatter); shriekers screech, acid sizzles. Alarms that belong to the hive (surge siren, boss horn) carry the same glassy shimmer as the cyan glow.
- **Mass:** in a horde the mix must stay readable, so every sound has a minimum gap and a per-tick cap, distant events are quieter and panned, and far ones are skipped.
- **Music** (all synthesised, no licences): dusty desert western meets scrap-yard industrial, in D phrygian. MENU "Dune Sea" (slow guitar and wind), WORKSHOP "Scrap Yard" (laid-back groove with clanking tools), COMBAT "Convoy" (driving war-rig rock), BOSS "Hive Queen" (half-time and dissonant while a boss is on the field). Tracks crossfade on phase changes; a win or lose sting plays on game over.
- **Settings:** master, music and effects levels plus a mute toggle on the main menu and the pause menu, saved with the profile.

---

## 12. Reference games (gameplay): what we take from each
- **Wanderburg:** the moving, growing fortress; modular grid building; the image of constant travel through a hostile world
- **Vampire Survivors / Brotato:** horde density, weapon evolutions, wave timers, characters with quirks
- **TFT / HS Battlegrounds:** synchronous shop phases, interest, player HP separate from unit HP, scouting, levelling duplicates
- **Backpack Battles / The Bazaar:** spatial inventory with adjacency, async ghost PvP
- **Legion TD 2 / Tetris 99:** PvE waves + sending enemies to opponents, wave preview
- **Final Fantasy XII (Gambits) / Gladiabots:** programmable AI rules as the main skill
- **Crossout / Mad Max:** vehicle aesthetics, localised module damage, ramming and harpoons
- **Battle royale games:** a contracting zone forces encounters
- **Nova Drift:** builds that change behaviour, not just numbers
- **Diablo / Risk of Rain / Path of Exile:** random enemy affixes, elite/champion enemies
- **Middle-earth: Shadow of Mordor:** the nemesis system (enemies that kill you remember it and come back)
- **Left 4 Dead (AI Director) / Hades:** randomised encounters that still feel fair and readable

---

## 13. Open design questions (for the next step)
1. **Real-time vs. async as the main mode:** I recommend async first, but it changes the marketing ("battle royale" vs. "auto-battler").
2. **Session length:** 20–25 min is a guess. Mobile would point to ~12 min with 8 rounds.
3. **Platform and controls:** *Decided:* PC first, published on Steam (Windows, Linux, Steam Deck), built in Godot 4. See [`architecture.md`](architecture.md). Still open: whether a mobile version follows, which would limit how complex the grid building and doctrine UI can be.
4. **Hands-off level:** should active abilities stay optional, or be removed entirely for a pure idle feel?
5. **Monetisation:** cosmetics only (recommended, since it's PvP) or something else?
6. **Tone:** the art direction (section 11) points to rough and atmospheric. How much dark humour fits alongside it (names like "Old Grandmother Saltjaw", vehicle trophies)?
7. **Hive adaptation strength:** how hard can the horde counter the lobby meta before it feels unfair? This needs to be tested in the prototype.
8. **Pixel scale:** does horde density still read well with detailed sprites at the planned zoom level? Make an early mock-up screenshot.

## 14. Recommended next step (still design, no code)
A **paper/spreadsheet prototype** of the core loop to test: 1 chassis, about 15 cards, 4 species + 4 mutations, 1 hive signature, a doctrine with 3 basic settings plus 1 rule slot, played as a "Ghost Raid" against 2 fixed rival builds. The goal is to answer one question: *is it fun to build, tune the doctrine and watch, and does the enemy randomness force interesting adaptations?* In parallel, make an **art mock-up**: one static screenshot (war rig, horde with glow accents, Dune Sea biome) to validate readability.
