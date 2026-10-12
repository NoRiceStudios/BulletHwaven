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
