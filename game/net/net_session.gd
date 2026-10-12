class_name NetSession
extends Node
## Host-authoritative session. See docs/architecture.md ("Net contract").
##
## The host (or solo player) owns the SimWorld and steps it at the physics rate (30 Hz). Clients
## own a passive SimWorld (spawning disabled) that is rewritten from snapshots. All clients are
## untrusted: commands are validated against an allow-list and rate limited.
##
## RPCs are matched by node path, so the NetSession must sit at the same path on every peer
## (it names itself "NetSession" to help).

signal peer_joined(id: int)
signal peer_left(id: int)
signal session_started
signal connection_failed
signal disconnected  ## client lost the host

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 7
const MAX_VEHICLES := Snapshot.MAX_VEHICLES
const SNAPSHOT_EVERY := 2  ## ticks
const MAX_PENDING_EVENTS := SimWorld.MAX_EVENTS
const MAX_COMMANDS_PER_SEC := 20

## Allow-list of client commands: type -> permitted values.
const COMMANDS := {
	"set_drive": ["circle", "kite", "charge"],
	"set_target": ["nearest", "strongest", "players_first"],
}

enum Mode { NONE, SOLO, HOST, CLIENT }

var world: SimWorld = null
## Optional: set before host()/start_solo() for a reproducible world; -1 = random.
var world_seed: int = -1

var _mode: Mode = Mode.NONE
var _pending_events: Array[Dictionary] = []
var _departed: Dictionary = {}  # vehicle id -> true (slot may be reused)
var _rate: Dictionary = {}  # peer id -> [window_start_ms, count]


func _init() -> void:
	name = &"NetSession"


# ---------------------------------------------------------------- public API

func host(port: int = DEFAULT_PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_mode = Mode.HOST
	_new_world(true)
	_spawn_vehicle_for(1)
	session_started.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_mode = Mode.CLIENT
	_new_world(false)
	return OK


func start_solo() -> void:
	stop()
	_mode = Mode.SOLO
	_new_world(true)
	_spawn_vehicle_for(1)
	session_started.emit()


## Tears down the network peer (if any) and the mode; `world` is kept for inspection.
func stop() -> void:
	if is_inside_tree():
		_disconnect_signals()
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
	_mode = Mode.NONE
	_pending_events.clear()
	_departed.clear()
	_rate.clear()


func is_host() -> bool:
	return _mode == Mode.HOST or _mode == Mode.SOLO


func is_client() -> bool:
	return _mode == Mode.CLIENT


func local_peer_id() -> int:
	if _mode == Mode.CLIENT:
		if not is_inside_tree() or multiplayer.multiplayer_peer == null:
			return 0
		return multiplayer.get_unique_id()
	return 1


## Number of players currently in the session (for the LAN beacon / lobby).
func player_count() -> int:
	if world == null:
		return 0
	var n: int = 0
	for v in world.vehicles:
		if not _departed.has(v.id):
			n += 1
	return n


func send_command(cmd: Dictionary) -> void:
	var clean: Dictionary = validate_command(cmd)
	if clean.is_empty():
		push_warning("NetSession.send_command: rejected command %s" % str(cmd))
		return
	match _mode:
		Mode.SOLO, Mode.HOST:
			_handle_command(1, clean)
		Mode.CLIENT:
			if multiplayer.multiplayer_peer != null \
					and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				_rpc_command.rpc_id(1, clean)


## Returns a sanitised copy ({"type", "value"}) if `cmd` is an allowed command, else {}.
static func validate_command(cmd: Variant) -> Dictionary:
	if typeof(cmd) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = cmd
	var t: Variant = d.get("type")
	var v: Variant = d.get("value")
	if typeof(t) != TYPE_STRING or typeof(v) != TYPE_STRING:
		return {}
	var type_s: String = t
	var value_s: String = v
	if type_s.length() > 32 or value_s.length() > 32 or not COMMANDS.has(type_s):
		return {}
	var allowed: Array = COMMANDS[type_s]
	if not allowed.has(value_s):
		return {}
	return {"type": type_s, "value": value_s}


# ---------------------------------------------------------------- stepping

func _physics_process(_delta: float) -> void:
	if world == null or (_mode != Mode.HOST and _mode != Mode.SOLO):
		return
	world.step()
	if _mode != Mode.HOST:
		return
	for e in world.events:
		if _pending_events.size() < MAX_PENDING_EVENTS:
			_pending_events.append(e)
	if world.tick % SNAPSHOT_EVERY == 0:
		if not multiplayer.get_peers().is_empty():
			_rpc_snapshot.rpc(Snapshot.encode(world, _pending_events))
		_pending_events.clear()


# ---------------------------------------------------------------- RPCs

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	if _mode != Mode.CLIENT or world == null:
		return
	Snapshot.apply(world, bytes)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Variant) -> void:
	if _mode != Mode.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	if not _rate_ok(sender, Time.get_ticks_msec()):
		return
	_handle_command(sender, cmd)


## Validates and applies a command from `peer_id`. Anything not on the allow-list is ignored.
func _handle_command(peer_id: int, cmd: Variant) -> void:
	if world == null:
		return
	var clean: Dictionary = validate_command(cmd)
	if clean.is_empty():
		return
	world.apply_command(peer_id, clean)


## Fixed one-second window limiter per peer.
func _rate_ok(peer_id: int, now_ms: int) -> bool:
	var entry: Array = _rate.get(peer_id, [now_ms, 0])
	if now_ms - int(entry[0]) >= 1000:
		entry = [now_ms, 0]
	entry[1] = int(entry[1]) + 1
	_rate[peer_id] = entry
	return int(entry[1]) <= MAX_COMMANDS_PER_SEC


# ---------------------------------------------------------------- peers

func _new_world(is_authority: bool) -> void:
	var s: int = world_seed if world_seed >= 0 else randi()
	world = SimWorld.new(s)
	world.spawning_enabled = is_authority
	_pending_events.clear()


## Spawn position for the n-th player: spread on an ellipse around the arena centre.
static func spawn_position(slot: int) -> Vector2:
	var a: float = float(slot % 8) * TAU / 8.0
	var c: Vector2 = SimWorld.ARENA.get_center()
	return c + Vector2(cos(a) * 480.0, sin(a) * 240.0)


func _spawn_vehicle_for(peer_id: int) -> SimVehicle:
	if world.get_vehicle_for_peer(peer_id) != null:
		return null
	# Reuse the slot of a departed player so vehicle ids (= array index) stay bounded.
	for i in world.vehicles.size():
		if _departed.has(world.vehicles[i].id):
			var old: SimVehicle = world.vehicles[i]
			var fresh := SimVehicle.new(old.id, peer_id, spawn_position(i))
			fresh.heading = (SimWorld.ARENA.get_center() - fresh.pos).angle()
			world.vehicles[i] = fresh
			_departed.erase(old.id)
			return fresh
	if world.vehicles.size() >= MAX_VEHICLES:
		return null
	return world.add_vehicle(peer_id, spawn_position(world.vehicles.size()))


func _on_peer_connected(id: int) -> void:
	if _mode != Mode.HOST:
		return
	if _spawn_vehicle_for(id) == null:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	_rate.erase(id)
	if _mode != Mode.HOST or world == null:
		peer_left.emit(id)
		return
	var v: SimVehicle = world.get_vehicle_for_peer(id)
	if v != null:
		if v.alive:
			v.alive = false
			v.hp = 0.0
			v.vel = Vector2.ZERO
			v.target_kind = 0
			if _pending_events.size() < MAX_PENDING_EVENTS:
				_pending_events.append({"type": "vehicle_destroyed", "pos": v.pos, "owner": v.id, "kind": -1})
		v.peer_id = 0  # no longer addressable by commands
		_departed[v.id] = true
	peer_left.emit(id)


func _on_connected_to_server() -> void:
	session_started.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	disconnected.emit()


func _disconnect_signals() -> void:
	var m: SceneMultiplayer = multiplayer as SceneMultiplayer
	if m == null:
		return
	if m.peer_connected.is_connected(_on_peer_connected):
		m.peer_connected.disconnect(_on_peer_connected)
	if m.peer_disconnected.is_connected(_on_peer_disconnected):
		m.peer_disconnected.disconnect(_on_peer_disconnected)
	if m.connected_to_server.is_connected(_on_connected_to_server):
		m.connected_to_server.disconnect(_on_connected_to_server)
	if m.connection_failed.is_connected(_on_connection_failed):
		m.connection_failed.disconnect(_on_connection_failed)
	if m.server_disconnected.is_connected(_on_server_disconnected):
		m.server_disconnected.disconnect(_on_server_disconnected)
