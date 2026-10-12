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
│  [ CONVOY PHASE ~75 s ]  ──►  [ WORKSHOP ~25 s ]  ──►  next round      │
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
- **Evolutions** (Vampire Survivors): a weapon plus a specific passive or module evolves at max level. Examples: flamethrower + fuel tank → *Inferno Spout*; MG + ammo crate ×2 → *Gatling Hell*; harpoon + V8 → *Chain Drag* (drags enemies behind you).
- **Rarity:** common, rare, epic, legendary. Tech raises the chance.

### 5b. Tech tree (per match, resets every match)
Five branches, each with about 4–6 tiers:
- **Ballistics:** weapon damage per category, armour piercing, crit
- **Engineering:** armour, repair rate, module HP, more grid cells
- **Propulsion:** engine power (more weight capacity), speed, chassis upgrades / trailers
- **Electronics:** **doctrine slots** (smarter AI), radar (see further ahead, scout opponents), active-ability cooldown
- **Salvage:** economy: more scrap per kill, interest, cheaper rerolls, wreck looting

**Interest mechanic (TFT):** +1 scrap per 10 saved at the end of each round (max +5). This creates a "save or spend" decision.

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
| **Glass Wings** (flyers) | Ignore terrain and rams | Flak, tesla |
| **Leeches** (sappers) | Latch onto the vehicle and eat modules | Spiked plating, electric shock, ramming walls |
| **Brood Carriers** | Slow; burst into a swarm when they die | Kill them at range, AoE |
| **Shriekers** (support) | Buff and heal nearby aliens, stay at the back | **Target priority** in doctrine ("support first") |
| **Hive Nests** (stationary) | Keep spawning until destroyed | **Aggression** in doctrine (attack vs. avoid) |
| **Mimics** | Look like scrap pickups or rocks | Loot greed in doctrine (Scrap Magnet becomes a risk) |
| **Stalkers** (camouflaged) | Invisible until close, burst attack | Radar tech, armour |
| **Tripod Walkers** (mini-boss) | Huge, slow, artillery | Burst DPS, mobility |

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
A pool of about 8 bosses. Each boss has **3 phases**, and each phase is drawn from 2–3 variants, so the same boss plays differently. Examples:
- **The Dune Mother:** a giant worm that circles the arena; phases: devour / spawn brood / sandstorm
- **The Shard Colossus:** a crystal giant; phases: split into shards / laser refraction / regenerate from the ground
- **The Choir:** a group of three Shriekers that buff each other; they must die at the same time
- **The Tripod Queen:** artillery from the edge of the screen, places nests

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
- **Rounds 1–3:** 1–2 species, no mutations, each player in their own sector (no PvP). Learn the build basics.
- **Rounds 4, 8, 12:** **Boss rounds** from the match's boss trio. Optionally a contested world boss.
- **From round 5:** mutations start appearing, the next round is announced, and random events become possible.
- **From round 6:** **the Blight** (a battle-royale zone) closes, sectors merge, and PvP becomes common. The hive starts to adapt.
- **Rounds 11+:** one shared arena, mixed species with 2–3 mutations, nemeses come back, final fights.

---

## 8. PvP: more than "shoot at each other"

**Layers of player interaction**
1. **Direct:** vehicles meet, and doctrine decides whether they fight or avoid each other.
2. **Indirect, sending monsters** (Tetris 99 / Legion TD / Bloons Battles): *Lure Beacon* cards or kill streaks send extra monsters into a chosen rival's sector. This makes PvP possible early without direct contact.
3. **Contested objectives:** supply drops, fuel depots, the world boss.
4. **Wreck salvage:** a destroyed rival vehicle drops scrap **and one of its modules** that you can steal. This is very satisfying, and it's where your "upgrades react to other players" idea pays off.
5. **Scouting:** in the workshop you can inspect every rival's vehicle and doctrine (TFT) and counter-build. Example: rival X runs explosives, so I take reactive armour.

**Life system instead of instant elimination (against R3)**
- Each player has **Fuel Reserves** (e.g. 100), a TFT-style player-HP model.
- Vehicle destroyed = respawn after a few seconds, but you lose fuel (more if a *player* killed you, and the killer gets a bounty) **plus 1 random module**.
- Fuel 0 = eliminated. Each loss also drains fuel slowly, so the match ends reliably.
- Result: a bad round is a setback, not game over. Elimination usually only happens in the second half.

**Anti-snowball (against R4/R6)**
- **Bounty on the leader:** the player with the most kills or the strongest vehicle is visible on the map and worth a big reward.
- **Underdog bonus:** players in the bottom places get +scrap and a better card rarity in the draft.
- **Third-party protection:** after a PvP kill you get a short shield / repair burst, so fights aren't pure losses.
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
- **Persistent traces:** tyre tracks, wrecks, craters and goo stay on the map for the whole match. Late in the match, the map tells the story of the fights.
- **Day/night cycle:** night rounds with dynamic headlights, muzzle flashes as light sources, and glowing aliens. These are the planned "screenshot moments".
- **Weather:** heat shimmer, sandstorms (screen-filling dust particles), spore fog.
- **Background details:** giant bones of ancient creatures, colony ship parts, wind turbines made from wreckage, old landing beacons.

### 11f. UI style
- **Diegetic and improvised:** rusty metal sheets, stencil fonts, tape labels, hand-written markings.
- **Workshop:** a top-down view of the vehicle on a garage floor. Cards are like scrap tags or crumpled blueprints.
- **Doctrine:** looks like an old onboard computer / CRT terminal salvaged from the colony ship (green or amber monochrome), a nice contrast to the warm desert.

### 11g. Visual references
- **Hyper Light Drifter:** detailed pixel art, atmosphere, colour mood
- **Nuclear Throne / Enter the Gungeon:** top-down readability under chaos
- **Mad Max: Fury Road:** vehicle design, orange/teal colour grading, kitbashing
- **Dune:** desert ecology, worms, living with the planet
- **Nausicaä of the Valley of the Wind:** aliens as an ecosystem, not as evil
- **Starship Troopers / The Riftbreaker:** alien hordes, nests, top-down horde chaos
- **Death Stranding / Kenshi:** the feel of an empty, rough, beautiful world

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
3. **Platform and controls:** PC/Steam first, or mobile too? This affects how complex the grid building and doctrine UI can be.
4. **Hands-off level:** should active abilities stay optional, or be removed entirely for a pure idle feel?
5. **Monetisation:** cosmetics only (recommended, since it's PvP) or something else?
6. **Tone:** the art direction (section 11) points to rough and atmospheric. How much dark humour fits alongside it (names like "Old Grandmother Saltjaw", vehicle trophies)?
7. **Hive adaptation strength:** how hard can the horde counter the lobby meta before it feels unfair? This needs to be tested in the prototype.
8. **Pixel scale:** does horde density still read well with detailed sprites at the planned zoom level? Make an early mock-up screenshot.

## 14. Recommended next step (still design, no code)
A **paper/spreadsheet prototype** of the core loop to test: 1 chassis, about 15 cards, 4 species + 4 mutations, 1 hive signature, a doctrine with 3 basic settings plus 1 rule slot, played as a "Ghost Raid" against 2 fixed rival builds. The goal is to answer one question: *is it fun to build, tune the doctrine and watch, and does the enemy randomness force interesting adaptations?* In parallel, make an **art mock-up**: one static screenshot (war rig, horde with glow accents, Dune Sea biome) to validate readability.
