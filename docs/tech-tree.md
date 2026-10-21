# Tech tree v2.3: node table

Source of truth in code: `game/sim/tech.gd` (data), with the effects implemented in `sim/cards.gd` (`recompute`), `sim/ammo.gd`, `sim/mobility.gd`, `sim/abilities.gd`, `sim/salvage.gd` and `sim/fusions.gd`. Design rationale: `docs/game-design.md` section 5b. Balance numbers: `docs/balance/tech_v2/report.md`. This file lists the tree as it stands in code, including the tuning from the bot league.

## Shape

5 branches of 6 stages, 61 branch nodes, plus 11 fusions = **72 nodes**.

| Stage | Content | Cost |
|---|---|---|
| 1 | **Core**: unlocks the branch's signature mechanic | 100 |
| 2 | **Style**: pick one (salvage: one of three) | 140 |
| 3 | **Core** (required for stage 4) plus an optional **prototype** (3P: fixed drawback, opens nothing) | 240 / 180 |
| 4 | **Specialisation**: pick one of three | 380 |
| 5 | **Mastery**: pick one of two | 520 |
| 6 | **Keystone**: pick one of two | 750 |
| Fusion | small (two stage 2 choices) / large (a stage 4 and a stage 2 choice, other branches) | 200 / 450 |

One branch to its keystone costs 2,130 scrap (100 + 140 + 240 + 380 + 520 + 750).

## Rules

- **Requirements:** a stage N > 1 node needs any owned non-prototype node of stage N-1 in its branch; stage 4 needs the stage 3 core; War Rig additionally needs Truck Chassis (chassis chain); a fusion needs both of its parts. Choices of one stage exclude each other (one exclusive group per branch and stage).
- **Owned versus active:** only active nodes (owned and every requirement active) apply their effect. A node can be owned but inactive after a respec (War Rig after Truck Chassis was swapped for the Roll Cage); it works again for free once the requirement is back. A fusion that loses a part moves to the dormant list; buying it again costs 50% (`Tech.REBUY_PCT`).
- **Respec:** swaps an owned choice of stage 2, 4, 5 or 6 for another choice of the same stage (the TECH view asks first and names what greys out). The old node is refunded in full and the new one paid in full. The **first respec of a match is free** (no surcharge); every further one costs an extra 50% of the new node's price (`Tech.RESPEC_FEE_PCT`). A stage 6 keystone can only be swapped until one round after it was bought (`Tech.KEYSTONE_RESPEC_ROUNDS`). Follow-up nodes stay owned; fusions that lose a part go dormant. Command `respec_tech {from, value}`.
- **Weapon slots:** start 2, maximum 5. Sources: Pickup Chassis, Auxiliary Mount (prototype), Sidecar Gunner, War Rig, Featherweight.
- **Ammo:** Ammo Bench loads fire ammo into every weapon. Each later ammo (shrapnel, AP) is loaded automatically into the last ceil(n/2) weapons and the matching rule template appears at once. Switching takes 1 s of silence, instant with Ballistic Tables. Command `set_ammo`, rule action `ammo:<id>`.
- **Abilities** (Nitro, EMP, Smoke, Salvo) come only from the tree; two slots, swapping is free in the workshop (`set_ability`); default is an auto-cast rule named in the tooltip, a key press or a rig rule overrides it.
- **Contracts:** Scrap Hooks offers one contract per workshop (Black Market two, Raider caps at one); `accept_contract` takes one.
- **Whole tree, own goals:** the TECH view always shows all five branches side by side; there is no plan mode and no folded view. The player right-clicks nodes to flag them as goals; the tree frames the way there and pulses the next node. The build names itself after the two branches most scrap went into ("BALLISTICS + SALVAGE, LIKE SCRAPPER"). The ideas FIREBRAND (ballistics + propulsion), FORTRESS (engineering + electronics) and SCRAPPER (salvage + ballistics) keep their path and three-line cheat sheet (`render/tech_guide.gd`, `TEMPLATES`) but only seed goals (deepest node per branch plus the fusions), which the player then changes freely.
- **Net effect on the rig:** tooltips show the net value including the drawback (for example "fire rate effectively +38%").

## Branches

### Ballistics: ammo

| Stage | Node | id | Cost | Needs | Effect |
|---|---|---|---|---|---|
| 1 | **Ammo Bench** | `ballistics_ammo_bench` | 100 | - | Ammo slot and **fire ammo** in every weapon: hits burn for 2 s (25% of the hit as damage over time). |
| 2a | **Belt Feed** | `ballistics_belt_feed` | 140 | any stage 1 node (not a prototype) | +20% fire rate (MG and flamer +30%). **Shrapnel ammo**: kills burst into 3 shards (40% damage; shard kills do not shatter again). |
| 2b | **Heavy Shells** | `ballistics_heavy_shells` | 140 | any stage 1 node (not a prototype) | +15% damage (cannon and shotgun +25%). **AP ammo**: +1 pierce, +50% against boulders, bosses and rivals. |
| 3 | **Ballistic Tables** | `ballistics_tables` | 240 | any stage 2 node (not a prototype) | +12% damage, ammo switches instantly, ammo effects +25%. |
| 3P | **Hot Loads** | `ballistics_hot_loads` | 180 | any stage 2 node (not a prototype) | +35% damage; after 4 s of continuous fire the barrel jams for 0.8 s (net about +12%). |
| 4a | **Scatter Packing** | `ballistics_scatter` | 380 | the stage 3 core | Shotgun +2 pellets; other weapons fire every 4th shot as a mini burst (3 x 40%). |
| 4b | **Napalm Mix** | `ballistics_napalm` | 380 | the stage 3 core | Burning spreads to enemies within 30 px. |
| 4c | **HE Shells** | `ballistics_he` | 380 | the stage 3 core | Cannon +14 splash damage; all other weapons +15% against burning targets. |
| 5a | **Tungsten Stock** | `ballistics_tungsten` | 520 | any stage 4 node (not a prototype) | +15% damage, +1 pierce; piercing shots leave an ember trail (20 damage/s, 2 s) that carries fire. |
| 5b | **Mixed Belts** | `ballistics_mixed_belts` | 520 | any stage 4 node (not a prototype) | Every weapon loads two ammo types at once; each ammo effect works at 70%. |
| 6a | **Glowing Barrels** | `ballistics_glowing` | 750 | any stage 5 node (not a prototype) | +60% fire rate; overheats after 6 s of continuous fire for a 1 s pause (net about +38%); replaces Hot Loads' jam. |
| 6b | **One Shot, One Kill** | `ballistics_one_shot` | 750 | any stage 5 node (not a prototype) | +100% damage, -15% fire rate; hits on targets below 30% hp kill outright (not bosses or rivals). |

### Engineering: chassis

| Stage | Node | id | Cost | Needs | Effect |
|---|---|---|---|---|---|
| 1 | **Welded Frame** | `engineering_frame` | 100 | - | +40 hp, +1 armour. |
| 2a | **Spike Skirts** | `engineering_spikes` | 140 | any stage 1 node (not a prototype) | Contact damage +50%, thorns, -8% contact damage taken. |
| 2b | **Field Welder** | `engineering_welder` | 140 | any stage 1 node (not a prototype) | +3 hp/s. |
| 3 | **Pickup Chassis** | `engineering_pickup` | 240 | any stage 2 node (not a prototype) | **Chassis 2**: +1 weapon slot, +80 hp, -5% speed. |
| 3P | **Scrap Armour** | `engineering_scrap_armour` | 180 | any stage 2 node (not a prototype) | +3 armour; a hit over 15% of max hp tears off 1 armour as a flying plate (20 damage); restored in the workshop. |
| 4a | **Reactive Plates** | `engineering_reactive` | 380 | the stage 3 core | +2.5 armour, explosions and acid -30%. |
| 4b | **Repair Drone** | `engineering_drone` | 380 | the stage 3 core | +4 hp/s, a repair drone flies along. |
| 4c | **Dozer Blade** | `engineering_dozer` | 380 | the stage 3 core | -15% contact damage taken, +30% ram damage, pushes mites aside. |
| 5a | **Truck Chassis** | `engineering_truck` | 520 | any stage 4 node (not a prototype) | **Chassis 3**: +200 hp, -6% speed, weapons +12% range. |
| 5b | **Roll Cage** | `engineering_roll_cage` | 520 | any stage 4 node (not a prototype) | No chassis change: +3 armour, speed penalties halved, no knockback. |
| 6a | **War Rig** | `engineering_war_rig` | 750 | Truck Chassis | **Chassis 4** with trailer: +1 weapon slot, +350 hp, -8% speed, wider turning circle. Needs Truck Chassis. |
| 6b | **Featherweight** | `engineering_featherweight` | 750 | any stage 5 node (not a prototype) | No speed penalties, +20% speed, +1 weapon slot, 10% dodge, max hp -15%. |

### Propulsion: momentum

| Stage | Node | id | Cost | Needs | Effect |
|---|---|---|---|---|---|
| 1 | **Tuned Engine** | `propulsion_tuned` | 100 | - | +8% speed, **momentum** active. At 100 momentum ram damage +50%. |
| 2a | **Ram Bumper** | `propulsion_bumper` | 140 | any stage 1 node (not a prototype) | Ramming costs no momentum, +35% ram damage, spark burst (30 px, 15 damage). |
| 2b | **Drift Tuning** | `propulsion_drift` | 140 | any stage 1 node (not a prototype) | Turning builds momentum twice as fast, +25% turn rate. |
| 3 | **Nitro Injector** | `propulsion_nitro` | 240 | any stage 2 node (not a prototype) | Ability **Nitro**: 50 momentum, 2 s of +60% speed, 6 s cooldown. Auto-cast: momentum >= 50 and (target within 200 px or hp < 30%). |
| 3P | **Dirty Fuel** | `propulsion_dirty_fuel` | 180 | any stage 2 node (not a prototype) | Momentum builds twice as fast; nitro leaves black smoke (aliens inside lose their target for 1 s); every 4th nitro sputters (no boost). |
| 4a | **Battering Ram** | `propulsion_battering` | 380 | the stage 3 core | +45% ram damage, enemies are thrown back. |
| 4b | **Ghost Runner** | `propulsion_ghost` | 380 | the stage 3 core | +20% dodge above 70 momentum. |
| 4c | **Slipstream** | `propulsion_slipstream` | 380 | the stage 3 core | Nitro leaves an oil trail: enemies on it move 40% slower for 2 s. |
| 5a | **Turbine Swap** | `propulsion_turbine` | 520 | any stage 4 node (not a prototype) | +12% speed, +60 hp, momentum decays at half speed; at 100 momentum a boost boom every 10 s (40 px, 30 damage). |
| 5b | **Sidecar Gunner** | `propulsion_sidecar` | 520 | any stage 4 node (not a prototype) | +1 weapon slot (sidecar, 200 degree arc), no speed penalty. |
| 6a | **Juggernaut** | `propulsion_juggernaut` | 750 | any stage 5 node (not a prototype) | Momentum grants armour (up to +5), ramming does not slow you; no reversing (the KITE drive style falls back). |
| 6b | **Phantom Drive** | `propulsion_phantom` | 750 | any stage 5 node (not a prototype) | Nitro makes you invulnerable for 0.5 s and leaves a ghost decoy (1 s); kills cut 0.5 s off the nitro cooldown (min 3 s); max hp -20%. |

### Electronics: commands and abilities

| Stage | Node | id | Cost | Needs | Effect |
|---|---|---|---|---|---|
| 1 | **Rangefinder** | `electronics_rangefinder` | 100 | - | +1 rule slot, condition *boulders near*, laser dot on the current target, +8% damage. |
| 2a | **Radar Array** | `electronics_radar` | 140 | any stage 1 node (not a prototype) | Conditions *fuel below* and *rival weaker than me*; scouting shows rival rules; spitters are marked 1 s before they spit. |
| 2b | **Fire Control Relay** | `electronics_relay` | 140 | any stage 1 node (not a prototype) | Action **focus fire** (all guns on one target), +15% fire rate. |
| 3 | **Targeting Computer** | `electronics_targeting` | 240 | any stage 2 node (not a prototype) | +1 rule slot, 4 conditions per rule, condition *ability ready*, +8% damage. |
| 3P | **Auxiliary Mount** | `electronics_aux_mount` | 180 | any stage 2 node (not a prototype) | +1 weapon slot, all weapons -10% range. |
| 4a | **EMP Pulse** | `electronics_emp` | 380 | the stage 3 core | Ability **EMP**: aliens within 120 px stunned 1.5 s, rival rules off for 3 s, 20 s cooldown. Auto-cast: 5 or more aliens within 120 px. |
| 4b | **Smoke Launcher** | `electronics_smoke` | 380 | the stage 3 core | Ability **Smoke**: 3 s untargetable, aliens lose their target, 15 s cooldown. Auto-cast: hp < 40%. |
| 4c | **Hunter-Killer Logic** | `electronics_hunter` | 380 | the stage 3 core | +20% damage below 30% hp, condition *target is leader*. |
| 5a | **Neural Fire Control** | `electronics_neural` | 520 | any stage 4 node (not a prototype) | +1 rule slot, ability **Salvo**: 2 s of +50% fire rate, 12 s cooldown. Auto-cast: boss active or 15+ aliens near. |
| 5b | **Overclock** | `electronics_overclock` | 520 | any stage 4 node (not a prototype) | Ability cooldowns -30%, weapons -5% range. |
| 6a | **Swarm Logic** | `electronics_swarm` | 750 | any stage 5 node (not a prototype) | All weapons share one marked target: +35% damage on it, the mark jumps on a kill. |
| 6b | **Jammer** | `electronics_jammer` | 750 | any stage 5 node (not a prototype) | Rivals within 200 px lose their lowest rule slot, aliens there move 20% slower; own range -10%. |

### Salvage: contracts

| Stage | Node | id | Cost | Needs | Effect |
|---|---|---|---|---|---|
| 1 | **Scrap Hooks** | `salvage_hooks` | 100 | - | +6% scrap, 1 **contract** per workshop (for example *kill 3 boulders: +60*, *do not die: +4 fuel*). |
| 2a | **Haggler** | `salvage_haggler` | 140 | any stage 1 node (not a prototype) | Rerolls cost 3 less, one offered card can be reserved for the next workshop. |
| 2b | **Lucky Charm** | `salvage_lucky` | 140 | any stage 1 node (not a prototype) | Rare cards 60% more likely, contract rewards +25%. |
| 2c | **Loan Shark** | `salvage_loan` | 140 | any stage 1 node (not a prototype) | At once +250 scrap, then 110 back for 3 rounds; an unpaid part grows 10% per round (never blocks buying). |
| 3 | **Black Market** | `salvage_black_market` | 240 | any stage 2 node (not a prototype) | +4 interest cap, 2 contracts to choose from. |
| 3P | **Insurance Fraud** | `salvage_insurance` | 180 | any stage 2 node (not a prototype) | +60 scrap on each own death; max hp -10%. |
| 4a | **Spare Jerrycans** | `salvage_jerrycans` | 380 | the stage 3 core | +15 fuel once, +1 fuel per completed contract; the cans explode on your death (50 px, 40 damage, fire). |
| 4b | **Scrap Press** | `salvage_press` | 380 | the stage 3 core | Scrap cards (level x 50 scrap, never the last weapon); the card flies into the field as a saw blade (20 damage, pierce 2). |
| 4c | **Hoarder** | `salvage_hoarder` | 380 | the stage 3 core | Interest cap 15 + 6 x round (instead of 5 + 2 x round), interest 12% instead of 10%. |
| 5a | **Salvage Crane** | `salvage_crane` | 520 | any stage 4 node (not a prototype) | +12% scrap, contract rewards +20%. |
| 5b | **Bounty Office** | `salvage_bounty` | 520 | any stage 4 node (not a prototype) | PvP contracts (*hit the leader 10 times: +150*), bounties doubled. |
| 6a | **Scrap Baron** | `salvage_baron` | 750 | any stage 5 node (not a prototype) | +3% damage per 100 scrap held (max +24%); whoever destroys you takes 10% of your scrap. The gold chain grows with it. |
| 6b | **Raider** | `salvage_raider` | 750 | any stage 5 node (not a prototype) | PvP hits knock scrap out of rivals (1 per 20 damage); only 1 contract per workshop. |

### Fusions

| Size | Node | id | Cost | Needs (both active) | Effect |
|---|---|---|---|---|---|
| small | **Thermite Ram** | `fusion_thermite` | 200 | Ram Bumper + Belt Feed | Ram sparks grow to 45 px, ignite and throw shrapnel. |
| small | **Spotter** | `fusion_spotter` | 200 | Radar Array + Heavy Shells | Cannon shots at spitters cannot miss and deal +50%. |
| small | **Hot Rod** | `fusion_hot_rod` | 200 | Drift Tuning + Field Welder | Drifting repairs +10 hp/s. |
| small | **Barbed Wire** | `fusion_barbed` | 200 | Spike Skirts + Haggler | Contact kills give +3 scrap (max +45 per round). |
| small | **Lucky Strike** | `fusion_lucky_strike` | 200 | Lucky Charm + Fire Control Relay | Focus-fire kills have a 2% chance of a bonus card pick (at most one every 2 rounds). |
| small | **Fortified Relay** | `fusion_fortified` | 200 | Field Welder + Fire Control Relay | Focus-fire kills repair +2 hp/s for 3 s (stacks to +6 hp/s). |
| large | **Burning Wake** | `fusion_burning_wake` | 450 | Napalm Mix + Drift Tuning | Drifting and nitro leave a burning oil trail; fire spreads. |
| large | **War Machine** | `fusion_war_machine` | 450 | Battering Ram + Spike Skirts | A ram hit with 40+ momentum sends a shockwave (60 px, 30 damage, knockback; costs 40 momentum, 1 s per target). |
| large | **Scrap Storm** | `fusion_scrap_storm` | 450 | Scrap Press + Heavy Shells | Explosion kills throw scrap shrapnel (3 x 25, burning if the victim burned), +1 scrap per kill (max +40 per round). |
| large | **Junkyard Drone** | `fusion_junkyard` | 450 | Repair Drone + Fire Control Relay | The drone rams the focus-fire target (15 damage every 0.5 s). |
| large | **Thunderclap** | `fusion_thunderclap` | 450 | EMP Pulse + Spike Skirts | Contact kills (thorns, ramming) trigger a mini EMP: 1 s stun, chain lightning to 2 more targets, 6 s cooldown. |

## Tuning history (bot league)

v2.3 as designed was checked with the bot league (see `docs/balance/tech_v2/report.md`). Changes against the design paper:

| Node | Design | Code now | Why |
|---|---|---|---|
| Field Welder | +2 hp/s | +3 hp/s | FORTRESS lagged the other templates by about 5 rounds |
| Fire Control Relay | +8% fire rate | +15% fire rate | same |
| Rangefinder | no damage | +8% damage | same (the laser marker now also pays off in damage) |
| Targeting Computer | no damage | +8% damage | same |
| Drift Tuning | +25% turn rate | +25% turn rate, +5% speed | scored about 2 rounds below its sibling Ram Bumper |
