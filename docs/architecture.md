# Architecture

## Tech stack (decided)

- **Engine:** Godot 4.7.2 (pinned in `scripts/setup-godot.sh`, installed by the SessionStart hook to `~/.local/bin/godot`). Compatibility renderer (OpenGL 3.3): right for 2D pixel art, runs on old PCs and the Steam Deck, and on CPU-only cloud containers.
- **Language:** statically typed GDScript. Hot loops can move to a GDExtension later if profiling demands it.
- **Multiplayer:** host-authoritative. ENet over LAN now; later Steam relay via GodotSteam's MultiplayerPeer (same high-level code) and/or a headless dedicated server export.
- **Steam:** GodotSteam (later).
- **Rendering:** 640x360 native viewport, integer-scaled. Large entity counts are drawn with `MultiMeshInstance2D`, never one node per bullet or enemy.

## Project layout (`game/`)

| Path | Layer | Rule |
|---|---|---|
| `sim/` | Simulation | Pure GDScript (`RefCounted`). No `Node`, scene tree, `Input`, `OS`, `Time`, or global `randf()`/`randi()`. Deterministic: all randomness comes from `world.rng`. Fixed tick 30 Hz. |
| `net/` | Networking | Host runs the sim. Clients send commands and receive snapshots. |
| `render/` | Presentation | Reads sim state every frame and never mutates it. |
| `tools/` | Dev tools | Screenshot scenarios. |
| `tests/` | Tests | Headless runner, no external addons. |
| `assets/` | Art | PNGs exported by `tools/artgen` (`python tools/artgen/generate.py --export-game-assets`). |

## Sim contract (`sim/`)

`SimWorld` (`sim/sim_world.gd`, `class_name SimWorld extends RefCounted`)
- Constants: `TICK_RATE := 30`, `DT := 1.0 / 30.0`, `ARENA := Rect2(0, 0, 1280, 720)`.
- State read by render/net:
  - `tick: int`, `seed: int`, `rng: RandomNumberGenerator`
  - `vehicles: Array[SimVehicle]`
  - Enemies as dense struct-of-arrays (length == `enemy_count`, swap-remove on death): `enemy_id: PackedInt32Array` (stable ids), `enemy_kind: PackedByteArray` (`SimWorld.MITE = 0`, `BOULDER = 1`, `SPITTER = 2`), `enemy_pos`, `enemy_vel: PackedVector2Array`, `enemy_hp: PackedFloat32Array`.
  - Projectiles as dense struct-of-arrays (length == `proj_count`): `proj_pos`, `proj_vel: PackedVector2Array`, `proj_ttl`, `proj_damage: PackedFloat32Array`, `proj_owner: PackedInt32Array` (vehicle id, `-1` = alien).
  - `events: Array[Dictionary]`: this tick's events, cleared at the start of `step()`. `{"type": "fire"|"hit"|"kill"|"vehicle_destroyed", "pos": Vector2, "owner": int, "kind": int}`.
- Methods:
  - `_init(p_seed: int)`
  - `add_vehicle(peer_id: int, pos: Vector2) -> SimVehicle`
  - `get_vehicle_for_peer(peer_id: int) -> SimVehicle` (or `null`)
  - `apply_command(peer_id: int, cmd: Dictionary)`. Commands: `{"type": "set_drive", "value": "circle"|"kite"|"charge"}`, `{"type": "set_target", "value": "nearest"|"strongest"|"players_first"}`.
  - `step()`: advances one tick (spawning, enemy AI, vehicle AI, weapons, projectiles, collisions via a spatial hash, deaths, scrap, events).
  - `checksum() -> int`: hash of the full state, for determinism and desync tests.

`SimVehicle` (`sim/sim_vehicle.gd`, `class_name SimVehicle extends RefCounted`)
- `id: int`, `peer_id: int`, `pos: Vector2`, `vel: Vector2`, `heading: float` (radians, Godot convention: 0 = +X/east; sprites face north, so render rotation = `heading + PI / 2`), `hp`, `max_hp: float`, `alive: bool`, `scrap: int`, `kills: int`.
- `doctrine: Dictionary = {"drive": "circle", "target": "nearest"}`.
- `weapons: Array[Dictionary]`, each `{"kind": "mg", "damage": float, "range": float, "cooldown_ticks": int, "cooldown": int, "aim": float}`. `aim` is the world angle, updated by the sim so render can rotate turrets.

Sim details (clarifications, no contract change): `enemy_vel`/`proj_vel` are px/s; `proj_ttl` is seconds; event `kind` is the enemy kind hit/killed (`-1` for a vehicle), `fire` kind is `0` (mg), and for `vehicle_destroyed` `owner` is the destroyed vehicle's id. Extras on `SimWorld`: `spawning_enabled`, `spawn_enemy(kind, pos)`, `spawn_projectile(...)`, `query_enemies(...)`, `rebuild_derived()` (call after a snapshot rewrites the arrays: resets `enemy_count`/`proj_count` and the spatial hash). `checksum()` covers contract state only (not rng state or AI scratch).

Skeleton gameplay: vehicles drive themselves according to their doctrine; weapons auto-fire at targets in range. Mites chase the nearest vehicle and deal contact damage; boulders are slow and tanky. Spawn rate grows over time. Projectiles hit enemies and other players' vehicles (PvP), never their owner. Kills give scrap.

## Net contract (`net/`)

- `NetSession` (`net/net_session.gd`, `class_name NetSession extends Node`): `host(port := 24680) -> Error`, `join(address: String, port := 24680) -> Error`, `start_solo()`, `is_host() -> bool`, `local_peer_id() -> int`, `send_command(cmd: Dictionary)`, `var world: SimWorld`. Signals: `peer_joined(id)`, `peer_left(id)`, `session_started`.
  - The host steps the sim in `_physics_process` (30 Hz), applies client commands with the sender's peer id, and sends a snapshot every 2 ticks (unreliable-ordered).
  - Clients apply snapshots to their local `world`. Render smooths positions.
- `Snapshot` (`net/snapshot.gd`): `static func encode(world: SimWorld) -> PackedByteArray`, `static func apply(world: SimWorld, bytes: PackedByteArray)`. Positions quantized, events included.
- `LanDiscovery` (`net/lan_discovery.gd`): the host broadcasts a UDP beacon on port 24681 once per second; clients emit `host_found(address: String, info: Dictionary)`.

Net details (as built):
- `NetSession` names itself `"NetSession"` and must sit at the same node path on every peer, because RPCs match by path.
- Extras: `player_count()`, `stop()`, signals `connection_failed` and `disconnected`.
- Client commands are validated against an allow-list and rate-limited to 20 per second per peer.
- `Snapshot.encode(world, events_override := [])` carries the events accumulated since the last snapshot. `Snapshot.apply()` returns `false` and leaves the world untouched on malformed data.
- Size: about 8 bytes per enemy, 13 per projectile, 7 per event and about 110 per vehicle (about 8.4 kB at 1,000 enemies, sent every 2 ticks).
- `world.events` holds only the latest tick's events, so render must consume them once per sim tick, not once per frame.
- `LanDiscovery` also emits `host_lost`.

Render details (as built):
- Every sprite that turns is pre-rendered by `tools/artgen/export_assets.py` as a strip of frames: 32 directions for hulls and 16 for aliens, using RotSprite with the outline drawn after rotating. Turrets, tracers and acid are drawn fresh at each angle.
- Godot only picks a frame and never rotates pixels on the GPU, which would make pixels jagged and shimmer at 640x360. Trade-off: the baked top-left lighting turns with the sprite.
- Effects consume `world.events` once per sim tick. Goo, scorch marks and tyre ruts persist in a decal layer.

## Entry point and command line

`main.tscn` / `main.gd` parse `OS.get_cmdline_user_args()`:
- *(no args)*: solo
- `--host`: host a LAN game
- `--join=<ip>`: join a host
- `--shot=<png> --scenario=<name> --seed=<n> --ticks=<n>`: screenshot mode (see `tools/`)

## Dev scripts (`scripts/`)

- `test.sh`: runs the headless test suite and exits non-zero on failure.
- `shot.sh <scenario> <seed> <ticks> <out.png>`: renders a scenario under Xvfb and saves a screenshot.
- `lan-smoke.sh`: starts a headless host and a headless client on localhost and checks they sync.

## Round loop contract (design doc sections 3, 5 and 8)

Phases (`SimWorld` constants): `PHASE_COMBAT = 0`, `PHASE_WORKSHOP = 1`, `PHASE_GAME_OVER = 2`.
- `world.phase: int`, `world.round: int` (starts at 1), `world.phase_ticks_left: int`, `world.winner_peer: int` (`-1` until game over).
- Durations are tunable constants: `COMBAT_TICKS` (default 60 s; rounds 1–2 shorter, 40 s) and `WORKSHOP_TICKS` (25 s). `world.fast_rounds: bool` (tests and screenshots) shortens both.
- **Combat:** enemies spawn and scale per round (hp and spawn-rate multipliers; boulders more frequent later).
- **Combat → workshop:** enemies retreat (all removed, with a `"retreat"` event), projectiles are cleared and vehicles stop. Every vehicle earns interest (+1 scrap per 10 held, max +5) and gets 3 fresh card offers.
- **Workshop → combat:** when the timer runs out, or when every alive, non-eliminated player is ready. Then `round += 1`.
- **Fuel reserves:** each vehicle starts with `fuel = 100`. Destroyed: lose 20 fuel (30 if a player killed it, and that player gains 15 scrap as a bounty) and respawn after 3 s (`respawn_ticks`) at full hp, at a free spot. At `fuel <= 0` the vehicle is `eliminated`.
- **Game over:** when at most one player remains in a multiplayer game (`winner_peer` = the survivor), or when the only player is eliminated in solo.

`SimVehicle` additions:
- `fuel: int`, `respawn_ticks: int`, `eliminated: bool`, `ready: bool`
- `offers: Array[String]` (3 card ids, empty once picked), `picked: bool`, `reroll_cost: int` (starts at 2, +1 per reroll, resets each workshop)
- `cards: Dictionary` (card id → level 1..3), `tech: Array[String]` (owned tech ids)
- Derived stats recomputed from the base values plus cards plus tech: `max_hp`, `armor` (flat damage reduction), `speed`, `turn_rate`, `scrap_mult`. Weapons are rebuilt from the weapon cards.

Data (`sim/cards.gd`, `sim/tech.gd`, pure data plus apply functions):
- **Cards:** about 16 to start, in 4 categories (`weapon`, `armor`, `mobility`, `behavior`) with a rarity weight. A duplicate pick raises the level (max 3); level 3 cards are no longer offered.
  - Weapons: `mg` (starter), `shotgun` (spread, short range), `cannon` (slow, heavy, pierce 1), `flamer` (very short range, fast ticks).
  - Weapon slots: 2, +1 from tech.
- **Tech:** 5 branches × 3 tiers. Ids are `ballistics_1..3`, `engineering_1..3`, `propulsion_1..3`, `electronics_1..3` and `salvage_1..3`. Tier N requires N-1 in the same branch. Costs grow by tier (e.g. 6/12/20).
  - Effects: ballistics = damage; engineering = hp, armor and (tier 3) a weapon slot; propulsion = speed and turn rate; electronics = range and fire rate; salvage = scrap multiplier and interest cap.
- Card offers and rerolls use `world.rng` only, so they stay deterministic.

Commands (validated by `NetSession` allow-lists; ignored in the wrong phase):
- `{"type": "pick_card", "value": int 0..2}`
- `{"type": "reroll"}`
- `{"type": "buy_tech", "value": "<tech id>"}`
- `{"type": "ready"}`
- `set_drive` and `set_target` stay valid in every phase.

Snapshots carry all of the above. Card and tech ids are encoded as indices into the data tables.

### Round loop: as built (details and deviations)

Implemented in `sim/sim_world.gd`, `sim/cards.gd`, `sim/tech.gd`, `net/snapshot.gd` (format version 2) and `net/net_session.gd`; tests in `tests/test_rounds.gd`.

- **Timers:** `COMBAT_TICKS_EARLY = 1200` (rounds 1–2), `COMBAT_TICKS = 1800`, `WORKSHOP_TICKS = 750`; with `fast_rounds` they are `FAST_COMBAT_TICKS = 120` and `FAST_WORKSHOP_TICKS = 45`. Set `fast_rounds` right after constructing the world (at tick 0 the setter also resets the running timer). A phase flips on the `step()` that brings `phase_ticks_left` to 0. Ready-skip needs at least one non-eliminated player and is evaluated on the next `step()` after the last `ready`.
- **Retreat:** one `"retreat"` event per enemy (`pos`, `owner = -1`, `kind` = enemy kind), thinned by a stride to at most `RETREAT_EVENT_CAP = 150`. `"respawn"` events carry `pos` and `owner` = vehicle id.
- **Repair and respawn timing (additions):** vehicles are repaired to `max_hp` when the next combat round starts. A vehicle that is destroyed when combat ends respawns at once for the workshop, so every non-eliminated player is alive in the workshop. Respawn picks the first free slot of the 8 arena-ellipse slots (starting at the vehicle's own), without using `rng`.
- **Game over:** checked every tick. Multiplayer means `vehicles.size() >= 2`. On game over the field freezes (nothing moves; aliens and projectiles are left as they were). `winner_peer` is the survivor's peer id, `-1` if nobody survives (or in solo). `NetSession` marks a departed peer's vehicle `eliminated`, so a lone host wins when the last client leaves.
- **Scaling (per round r):** hp x `1 + 0.12 (r-1)`, spawn rate x `1 + 0.10 (r-1)` (the in-round ramp of +0.5/s per 10 s restarts every round), boulder chance `0.10 + 0.025 (r-1)` capped at 0.4, contact damage x `1 + 0.03 (r-1)`. `SimWorld.enemy_max_hp(kind, round)` is the hp an enemy spawns with; snapshots encode enemy hp relative to it.
- **Derived stats:** `speed` and `turn_rate` are multipliers (1.0 = base). `armor` is a flat reduction per hit (floor 25% of the hit, also applies to ram damage); per touching enemy per tick it counts `0.04x`. Extra derived fields: `regen` (hp/s), `contact_damage` (damage per tick to touching enemies, from spikes and berserker; added to `ram_damage`), `ram_mult` (scales the charge ram), `vulture`, `weapon_slots`, `interest_cap`, `scrap_frac` (scrap_mult remainder). Scrap from kills is `ENEMY_SCRAP * scrap_mult` with the fraction carried. PvP kill bounty is `PVP_KILL_SCRAP = 15`.
- **Cards:** `cards` starts as `{"mg": 1}`, so the starter weapon is the level 1 mg card (it can be offered as an upgrade). A weapon card that is not yet owned is not offered when `weapon_slots` are full. Offers are weighted-random without replacement from `Cards.roll_offers(world.rng, v)`; maxed cards are never offered. `pick_card` on an index that is out of range, a second pick, or any card command in combat or game over, is ignored.
- **Cards (16):** weapon `mg`, `shotgun`, `cannon`, `flamer`; armor `steel_plates`, `spiked_plating`, `reinforced_hull`, `ablative_scrap`; mobility `v8_engine`, `off_road_tyres`, `nitro`, `caterpillar_tracks`; behavior `scrap_magnet`, `berserker`, `vulture`, `regenerator`.
- **Tech costs:** 15 / 30 / 55 for tiers 1 / 2 / 3. `Tech.buy(v, id)` pays and recomputes stats.
- **Weapons:** a weapon dict now also has `pellets`, `spread` (half angle), `pierce`, `splash` (radius, applies half damage to other enemies), `speed` (px/s). Projectile ttl = `range / speed + 0.05`, so flames live under half a second. Projectiles gained `proj_pierce: PackedByteArray`, `proj_splash: PackedFloat32Array`, `proj_last: PackedInt32Array` (id of the last pierced enemy); `spawn_projectile(pos, vel, ttl, damage, owner, pierce := 0, splash := 0.0)`. The `"fire"` event `kind` is now the weapon kind index (`Cards.WEAPON_KINDS`: mg 0, shotgun 1, cannon 2, flamer 3) and a volley emits one event. The driving AI orients on `SimVehicle.engage_range()` (mean weapon range).
- **Commands (`NetSession.validate_command`):** `pick_card` accepts an int or an integral float 0..2 (returned as int); `buy_tech` accepts only known tech ids; `reroll` and `ready` ignore any `value`. The 20 commands/s per-peer limit is unchanged.
- **Snapshot:** header gained `phase`, `round`, `phase_ticks_left`, `winner_peer`; vehicles carry fuel, respawn ticks, flag bits, reroll cost, scrap fraction, offers, cards (index + level) and tech (indices), and full weapon dicts. Out-of-range card/tech indices, levels outside 1..3 or an unknown phase make `apply()` return false with the world untouched. Clients recompute derived stats from cards and tech. Event types `retreat` and `respawn` were appended to `Snapshot.EVENT_TYPES`. Projectile pierce/splash are not sent (clients are passive).
- **Checksum** now also covers phase, round, timers, winner, all new vehicle state (fuel, flags, offers, cards, tech, derived stats, full weapon dicts) and the new projectile arrays. It still excludes rng state.
- **Late joiners:** `SimWorld.prepare_vehicle(v)` (called by `add_vehicle` and by `NetSession` when it reuses a slot) sets fuel and, during a workshop, rolls offers.
