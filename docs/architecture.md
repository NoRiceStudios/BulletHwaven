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
  - `events: Array[Dictionary]`: this tick's events, cleared at the start of `step()`. `{"type": "fire"|"hit"|"kill"|"vehicle_destroyed"|"spit", "pos": Vector2, "owner": int, "kind": int}` (more types are listed under the round loop).
- Methods:
  - `_init(p_seed: int)`
  - `add_vehicle(peer_id: int, pos: Vector2, p_name := "DRIVER", p_color := -1) -> SimVehicle` (name sanitised; colour < 0 keeps the default `id % 8`)
  - `get_vehicle_for_peer(peer_id: int) -> SimVehicle` (or `null`)
  - `apply_command(peer_id: int, cmd: Dictionary)`. Commands: `{"type": "set_drive", "value": "circle"|"kite"|"charge"}`, `{"type": "set_target", "value": "nearest"|"strongest"|"players_first"}`.
  - `step()`: advances one tick (spawning, enemy AI, vehicle AI, weapons, projectiles, collisions via a spatial hash, deaths, scrap, events).
  - `checksum() -> int`: hash of the full state, for determinism and desync tests.

`SimVehicle` (`sim/sim_vehicle.gd`, `class_name SimVehicle extends RefCounted`)
- `id: int`, `peer_id: int`, `player_name: String` (default `"DRIVER"`; 1..16 printable ASCII chars), `color_index: int` (0..7 paint colour, default `id % 8`; 0 = red, 1 = magenta as in the current art, 2..7 reserved for more paints). `SimVehicle.sanitize_name(raw)` is the one place names are cleaned (printable ASCII only, spaces collapsed and trimmed, max `MAX_NAME_LEN = 16`, empty becomes `"DRIVER"`); `COLOR_COUNT = 8`.
- `pos: Vector2`, `vel: Vector2`, `heading: float` (radians, Godot convention: 0 = +X/east; sprites face north, so render rotation = `heading + PI / 2`), `hp`, `max_hp: float`, `alive: bool`, `scrap: int`, `kills: int`.
- `doctrine: Dictionary = {"drive": "circle", "target": "nearest"}`.
- `weapons: Array[Dictionary]`, each `{"kind": "mg", "damage": float, "range": float, "cooldown_ticks": int, "cooldown": int, "aim": float}`. `aim` is the world angle, updated by the sim so render can rotate turrets.

Sim details (clarifications, no contract change): `enemy_vel`/`proj_vel` are px/s; `proj_ttl` is seconds; event `kind` is the enemy kind hit/killed (`-1` for a vehicle), `fire` kind is `0` (mg), and for `vehicle_destroyed` `owner` is the destroyed vehicle's id. Extras on `SimWorld`: `spawning_enabled`, `spawn_enemy(kind, pos)`, `spawn_projectile(...)`, `query_enemies(...)`, `rebuild_derived()` (call after a snapshot rewrites the arrays: resets `enemy_count`/`proj_count` and the spatial hash). `checksum()` covers contract state only (not rng state or AI scratch).

Skeleton gameplay: vehicles drive themselves according to their doctrine; weapons auto-fire at targets in range. Mites chase the nearest vehicle and deal contact damage; boulders are slow and tanky. Spawn rate grows over time. Projectiles hit enemies and other players' vehicles (PvP), never their owner. Kills give scrap.

## Net contract (`net/`)

- `NetSession` (`net/net_session.gd`, `class_name NetSession extends Node`): `host(port := 24680, auto_start := true) -> Error`, `join(address: String, port := 24680) -> Error`, `start_solo(name := "DRIVER", color_index := 0)`, `is_host() -> bool`, `local_peer_id() -> int`, `send_command(cmd: Dictionary)`, `var world: SimWorld` (never null after host/join/start_solo; in the lobby it is an empty placeholder that is not stepped). Signals: `peer_joined(id)`, `peer_left(id)`, `session_started`, plus the lobby signals below.
  - The host steps the sim in `_physics_process` (30 Hz) **only while a match runs**, applies client commands with the sender's peer id, and sends a snapshot every 2 ticks (unreliable-ordered).
  - Clients apply snapshots to their local `world` (only while in a match). Render smooths positions.
- **Lobby and match lifecycle** (host-authoritative). `state` is `NetSession.State.IDLE | LOBBY | MATCH` (`in_lobby()`, `in_match()`, `state_name()` = `"lobby"|"match"`).
  - `host(port, auto_start)` opens a lobby with the local player (profile from `set_profile()`, default `"DRIVER"`/0) and does not step the sim. `auto_start = true` (legacy `--host`, the default for now) calls `start_match()` immediately and accepts late joiners (`allow_late_join = true`). **The menu passes `auto_start = false`**, lets people gather, then calls `start_match()`. `join()` puts a client in the LOBBY state until the host's roster arrives; on connect it sends its profile as the hello.
  - `lobby_players: Array[Dictionary]`, host first, `{"peer_id", "name", "color_index", "ready", "is_host"}`; read-only for callers. Authoritative on the host, re-sent (reliable) to clients on every change and validated by `NetSession.parse_lobby()` on receipt. During a match it is the roster of connected players (a departed peer is removed). `local_player() -> Dictionary` is the local entry (`{}` until the roster arrived), `lobby_all_ready()` is true when every non-host player is ready.
  - Signals: `lobby_changed`, `match_started` (also on a rematch; `world` is then a fresh `SimWorld`, so re-bind render), `match_ended(winner_peer: int)` (game over reached, once per match, host and clients; -1 = nobody/solo loss), `join_rejected(reason: String)` (client only, followed by `disconnected`).
  - `set_profile(name, color_index)`: before host/join/start_solo it only stores the profile; afterwards it sends the validated command `{"type": "profile", "name": String (raw <= 64 chars), "color_index": 0..7}` (the same command is the client's hello). The host sanitises the name (`SimVehicle.sanitize_name`), makes it unique among players (case-insensitive: `"BOB"`, `"BOB 2"`, ... within 16 chars) and keeps colours unique: a new player gets the preferred colour if free else the lowest free one; a player who asks for a taken colour keeps the current one. Profile changes are accepted in the lobby and also during a match (the vehicle is updated).
  - `set_lobby_ready(bool)` sends `{"type": "lobby_ready", "value": bool}`; only meaningful in the lobby.
  - `start_match() -> Error` (host/solo only, state LOBBY, at least 1 player; ready flags are not required, so the host may force): builds a fresh world (seed `world_seed + n` for the n-th match of the session, random if `world_seed < 0`; `fast_rounds` applied), one vehicle per roster entry in roster order with its name and colour, then emits `match_started` (clients get a reliable `match_started` RPC and start from a fresh passive world). Errors: `ERR_UNAUTHORIZED` (not host), `ERR_UNAVAILABLE` (not in lobby), `ERR_UNCONFIGURED` (empty roster).
  - `rematch() -> Error` (host/solo only, only when `world.phase == PHASE_GAME_OVER`, else `ERR_UNAVAILABLE`): **chosen behaviour: straight into a new match**, not back to the lobby: new seed, same connected players with their names and colours, ready flags reset, `match_started` again. Solo restart uses the same call (`start_solo()` also still works and restarts at once).
  - **Late join:** a peer that connects while a match runs is **refused** (simplest robust option; no spectator mode): the host sends `join_rejected("match in progress")` and closes the connection after the message is flushed. Exception: sessions started with `auto_start = true` (`allow_late_join`) still take late joiners as players, as before. A full lobby (8 players) is refused with `"lobby full"`.
  - `leave()` (same as `stop()`): closes the connection and forgets the lobby; `world` is kept for inspection. Extras: `fast_rounds` (applied to every match world; `--fast` still works by setting `world.fast_rounds` after `host()`/`start_solo()`), `allow_late_join`, `player_count()` (roster size).
  - **Security:** every client message (game and lobby) goes through `validate_command` (allow-list, types, ranges, lengths) and the 20/s per-peer limit; `profile` and `lobby_ready` additionally share a stricter limit of 4/s per peer. Clients never send start/rematch (host-only API, no command exists for them). Host-to-client messages (`lobby`, `match_started`, `rejected`) are accepted only from peer 1 and the lobby list is validated (max 8 entries, unique peers and colours, exactly one host, sanitised names).
- `Snapshot` (`net/snapshot.gd`, format version 3): `static func encode(world: SimWorld) -> PackedByteArray`, `static func apply(world: SimWorld, bytes: PackedByteArray)`. Positions quantized, events included. Vehicles carry `player_name` and `color_index` (right after `peer_id`; a colour index >= 8 makes `apply()` return false, names are re-sanitised on receipt). Projectile ttl is sent in 1/100 s (acid lives about 1.8 s). Event type `spit` was appended to `EVENT_TYPES`.
- `LanDiscovery` (`net/lan_discovery.gd`): the host broadcasts a UDP beacon on port 24681 once per second; clients emit `host_found(address: String, info: Dictionary)`. Beacon fields: `game`, `version` (1), `port`, `players`, `name`, `state` (`"lobby"` or `"match"`; unknown values parse as `"lobby"`). Set `lan.session = <NetSession>` and every beacon refreshes `players` (roster size), `name` (host's player name) and `state` from it; the plain fields `player_count`, `host_name`, `match_state` still work without a session.

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
- *(no args)*: main menu (Solo, Host LAN game, Join LAN game with discovered hosts, driver profile saved in `user://profile.cfg`). The menu hosts with `auto_start = false`, giving a lobby.
- `--solo`: straight into a solo match (the old default)
- `--host`: host a LAN game
- `--join=<ip>`: join a host
- `--shot=<png> --scenario=<name> --seed=<n> --ticks=<n>`: screenshot mode (see `tools/`). Scenarios: `menu`, `join`, `lobby`, `pause`, `skirmish`, `horde`, `workshop` (about 400 ticks), `gameover` (about 300), `gameover_mp` (about 200), `eliminated` (about 220). `--hover=x,y` and `--click=x,y;...` simulate the mouse in screenshot mode, through the same code path as real input.
- `--fast`: short rounds (`fast_rounds`) for quick manual testing.
- Network events are logged as `net: ...` lines on the console.
- Input: mouse; `1`/`2`/`3` pick a card, `R` reroll, `Space` ready, `Enter` restart (solo), `Esc` quit. All actions go through `NetSession.send_command`.

## Dev scripts (`scripts/`)

- `test.sh`: runs the headless test suite and exits non-zero on failure.
- `shot.sh <scenario> <seed> <ticks> <out.png>`: renders a scenario under Xvfb and saves a screenshot.
- `lan-smoke.sh`: starts a headless host and client on localhost through the whole flow (host opens a lobby, the client joins with a colliding name and colour and readies up, the host starts the match, both play) and checks tick sync, command round trip, enemy counts and that names and colours were made unique and agree on both sides; a third client that joins mid-match must get `join_rejected("match in progress")`. LAN discovery (state and player count in the beacon) is checked when UDP broadcast works, else skipped. The harness is `net/smoke.gd` (`--role=host|client|late`).

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

## Spitters (as built)

Constants on `SimWorld`: `SPITTER_MIN_ROUND = 3`, spawn chance `spitter_chance(r)` = 0 before round 3, then `0.08 + 0.03 (r-3)` capped at 0.25 (rolled after the boulder roll; no extra rng draw before round 3, so rounds 1-2 are unchanged). A spitter (hp 20, speed 55 px/s) holds 180 to 230 px from the nearest living vehicle (`SPITTER_KEEP_MIN/MAX`: backs away with a sideways drift when closer, closes in when farther, strafes slowly in between) and every `SPIT_PERIOD = 60` ticks (2 s, staggered by enemy id, so there is no extra per-enemy state) lobs one acid glob if the target is within `SPIT_RANGE = 260`: speed `SPIT_SPEED = 170` px/s, damage `SPIT_DAMAGE = 8` x `enemy_damage_mult(round)`, aimed with target lead and +-0.08 rad error (from `world.rng`), ttl about 1.8 s. The projectile has `owner = -1`; it damages vehicles only (armour applies, the kill costs fuel as an alien kill) and passes aliens by. Each shot emits `{"type": "spit", "pos": muzzle, "owner": -1, "kind": SPITTER}` for render. The old screenshot scenarios that fake spitter fire in `tools/scenarios.gd` now double up with the real thing and can drop their fake.

## Tests

`tests/test_lobby.gd` (lobby join, profile/colour uniqueness, name sanitising, validation of junk, start_match, rematch, late-join policy, solo defaults, beacon state, roster parsing), `tests/test_spitter.gd` (spawn rounds, distance keeping, acid damage and armour, determinism, spit event over the snapshot), `tests/test_net.gd::test_snapshot_carries_identity`.
