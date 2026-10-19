class_name NetSession
extends Node
## Host-authoritative session. See docs/architecture.md ("Net contract").
##
## The host (or solo player) owns the SimWorld and steps it at the physics rate (30 Hz). Clients
## own a passive SimWorld (spawning disabled) that is rewritten from snapshots. All clients are
## untrusted: commands are validated against an allow-list and rate limited.
##
## Lifecycle: IDLE -> LOBBY (host opened it / client joined; the sim is not stepped) -> MATCH
## (start_match()) -> game over -> rematch() -> a fresh MATCH. Solo skips the lobby.
##
## RPCs are matched by node path, so the NetSession must sit at the same path on every peer
## (it names itself "NetSession" to help).

signal peer_joined(id: int)
signal peer_left(id: int)
signal session_started
signal connection_failed
signal disconnected  ## client lost the host
signal lobby_changed  ## lobby_players changed (join / leave / profile / ready)
signal match_started  ## a new match began (also on rematch); `world` is a fresh SimWorld
signal match_ended(winner_peer: int)  ## the match reached game over (-1 = nobody / solo loss)
signal join_rejected(reason: String)  ## client: the host refused us (match in progress, lobby full)

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 7
const MAX_VEHICLES := Snapshot.MAX_VEHICLES
const SNAPSHOT_EVERY := 2  ## ticks
const MAX_PENDING_EVENTS := SimWorld.MAX_EVENTS
const MAX_COMMANDS_PER_SEC := 20
const MAX_LOBBY_COMMANDS_PER_SEC := 4  ## profile / lobby_ready changes, on top of the general limit
const MAX_PLAYERS := 8  ## host + MAX_CLIENTS; one paint colour each
const MAX_RAW_NAME := 64  ## longer raw names are junk and rejected; shorter ones are sanitised to 16

## Allow-list of client commands with a fixed set of string values: type -> permitted values.
const COMMANDS := {
	"set_drive": ["circle", "kite", "charge"],
	"set_target": Doctrine.RIG_TARGETS,
	"use_ability": Abilities.IDS,
}
## Commands without a value (any "value" key is dropped).
const VALUELESS_COMMANDS: PackedStringArray = ["reroll", "ready"]
const LOBBY_COMMANDS: PackedStringArray = ["profile", "lobby_ready"]
const MARK_MARGIN := 64.0  ## "mark" points may lie this far outside the arena
const OFFER_SLOTS := Cards.OFFER_COUNT + 1  ## pick_card / reserve_card take an offer index 0..OFFER_SLOTS-1 (a lucky strike adds a fourth offer)

enum Mode { NONE, SOLO, HOST, CLIENT }
enum State { IDLE, LOBBY, MATCH }

var world: SimWorld = null
## Optional: set before host()/start_solo() for a reproducible world; -1 = random. The n-th match of
## a session (rematch) uses world_seed + n.
var world_seed: int = -1
## Applied to every match world (equivalent to setting `world.fast_rounds` right after it is built).
var fast_rounds: bool = false
## Host: accept peers that connect while a match is running (they get a vehicle at once). host()
## sets it to its `auto_start` argument; lobby-driven sessions reject late joiners.
var allow_late_join: bool = false

var state: State = State.IDLE
## The roster, host first: [{"peer_id": int, "name": String, "color_index": int, "ready": bool,
## "is_host": bool}]. Authoritative on the host, mirrored to clients on every change. Read-only
## for callers; connect to `lobby_changed`. During a match it is the roster of connected players.
var lobby_players: Array[Dictionary] = []

var _mode: Mode = Mode.NONE
var _pending_events: Array[Dictionary] = []
var _departed: Dictionary = {}  # vehicle id -> true (slot may be reused)
var _rate: Dictionary = {}  # peer id -> [window_start_ms, count]
var _refused: Dictionary = {}  # peer id -> true: told to go away, closing, gets nothing more
var _lobby_rate: Dictionary = {}  # peer id -> [window_start_ms, count] for LOBBY_COMMANDS
var _my_name: String = SimVehicle.DEFAULT_NAME  # local profile (sent as the hello when joining)
var _my_color: int = 0
var _match_count: int = 0  # matches built so far (seeds world_seed + n)
var _ended: bool = false  # match_ended already emitted for this match


func _init() -> void:
	name = &"NetSession"


# ---------------------------------------------------------------- public API

## Opens a lobby on `port` with the local player (see set_profile) in it. With `auto_start` (the
## default, the legacy `--host` behaviour) the match starts at once and late joiners are accepted;
## the menu passes false, lets people gather in the lobby and calls start_match().
func host(port: int = DEFAULT_PORT, auto_start: bool = true) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_mode = Mode.HOST
	_open_lobby()
	allow_late_join = auto_start
	if auto_start:
		start_match()
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
	state = State.LOBBY  # waiting for the host's lobby
	world = _new_lobby_world()
	return OK


## Starts a single-player match immediately (also the way to restart one; see rematch()).
func start_solo(p_name: String = SimVehicle.DEFAULT_NAME, p_color: int = 0) -> void:
	stop()
	_my_name = SimVehicle.sanitize_name(p_name)
	_my_color = clampi(p_color, 0, SimVehicle.COLOR_COUNT - 1)
	_mode = Mode.SOLO
	_open_lobby()
	start_match()
	session_started.emit()


## Host only, from the lobby: builds a fresh world with one vehicle per lobby player and starts
## stepping. Allowed with any number of players >= 1 and whether or not everyone is ready (the host
## may force; see lobby_all_ready()). Returns OK or an error (ERR_UNAUTHORIZED: not the host,
## ERR_UNAVAILABLE: not in the lobby).
func start_match() -> Error:
	if _mode != Mode.HOST and _mode != Mode.SOLO:
		return ERR_UNAUTHORIZED
	if state != State.LOBBY:
		return ERR_UNAVAILABLE
	if lobby_players.is_empty():
		return ERR_UNCONFIGURED
	_begin_match()
	return OK


## Host only, after game over: a new seed, the same connected players with their names and colours,
## straight into a fresh match (no trip through the lobby; ready flags are reset). Works in solo too.
## Returns OK, ERR_UNAUTHORIZED (not the host) or ERR_UNAVAILABLE (match not over).
func rematch() -> Error:
	if _mode != Mode.HOST and _mode != Mode.SOLO:
		return ERR_UNAUTHORIZED
	if state != State.MATCH or world == null or world.phase != SimWorld.PHASE_GAME_OVER:
		return ERR_UNAVAILABLE
	for e in lobby_players:
		e["ready"] = false
	_begin_match()
	return OK


## Local player's name / paint colour. Before host() / join() / start_solo() it only stores them
## (they become the host's lobby entry, or the client's hello); afterwards it also sends a validated
## "profile" command. The host uniquifies the name and keeps colours unique (a taken colour is
## refused and the current one stays). Names are sanitised (printable ASCII, max 16 chars).
func set_profile(p_name: String, p_color: int) -> void:
	_my_name = SimVehicle.sanitize_name(p_name)
	_my_color = clampi(p_color, 0, SimVehicle.COLOR_COUNT - 1)
	if _mode != Mode.NONE:
		send_command({"type": "profile", "name": _my_name, "color_index": _my_color})


## Lobby ready toggle for the local player.
func set_lobby_ready(is_ready: bool) -> void:
	send_command({"type": "lobby_ready", "value": is_ready})


## True when every non-host player in the lobby is ready (a lone host counts as all ready).
func lobby_all_ready() -> bool:
	for e in lobby_players:
		if not bool(e.get("is_host", false)) and not bool(e.get("ready", false)):
			return false
	return true


func in_lobby() -> bool:
	return state == State.LOBBY


func in_match() -> bool:
	return state == State.MATCH


## "lobby" or "match" (shown in the LAN beacon).
func state_name() -> String:
	return "match" if state == State.MATCH else "lobby"


## The local player's lobby entry ({} if not in the roster yet).
func local_player() -> Dictionary:
	var pid: int = local_peer_id()
	for e in lobby_players:
		if int(e["peer_id"]) == pid:
			return e
	return {}


## Leaves the session: closes the connection (a client drops out of the host's roster, a host's
## clients get `disconnected`), forgets the lobby. `world` is kept for inspection. Same as stop().
func leave() -> void:
	stop()


## Tears down the network peer (if any) and the mode; `world` is kept for inspection.
func stop() -> void:
	if is_inside_tree():
		_disconnect_signals()
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			multiplayer.multiplayer_peer.close()
			multiplayer.multiplayer_peer = null
	_mode = Mode.NONE
	state = State.IDLE
	lobby_players = []
	allow_late_join = false
	_match_count = 0
	_ended = false
	_pending_events.clear()
	_departed.clear()
	_rate.clear()
	_lobby_rate.clear()
	_refused.clear()


func is_host() -> bool:
	return _mode == Mode.HOST or _mode == Mode.SOLO


func is_client() -> bool:
	return _mode == Mode.CLIENT


func local_peer_id() -> int:
	if _mode == Mode.CLIENT:
		if not is_inside_tree() or multiplayer.multiplayer_peer == null \
				or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return 0
		return multiplayer.get_unique_id()
	return 1


## Number of players currently in the session (for the LAN beacon / lobby).
func player_count() -> int:
	if not lobby_players.is_empty():
		return lobby_players.size()
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


## Returns a sanitised copy ({"type"} or {"type", "value"}) if `cmd` is an allowed command, else {}.
## pick_card takes an integral number 0..2 (an int or a whole float, since JSON / RPC may deliver
## either; returned as int); buy_tech takes a known tech id; respec_tech takes two ("from", "value"); reroll and ready take no value;
## set_rules / set_weapon_target / set_ammo take a "scope" and are re-encoded in canonical form (Doctrine);
## use_ability takes an ability id, set_ability a "slot" (0..1) and an ability id; reserve_card an offer index 0..3, accept_contract a
## contract index 0..1, scrap_card a card id.
static func validate_command(cmd: Variant) -> Dictionary:
	if typeof(cmd) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = cmd
	var t: Variant = d.get("type")
	if typeof(t) != TYPE_STRING:
		return {}
	var type_s: String = t
	if type_s.length() > 32:
		return {}
	var v: Variant = d.get("value")
	if VALUELESS_COMMANDS.has(type_s):
		return {"type": type_s}
	if type_s == "profile":  # lobby hello / profile change: {"name": String, "color_index": 0..7}
		var raw_name: Variant = d.get("name")
		if typeof(raw_name) != TYPE_STRING or String(raw_name).length() > MAX_RAW_NAME:
			return {}
		var color: int = _small_int(d.get("color_index"), SimVehicle.COLOR_COUNT)
		if color < 0:
			return {}
		return {"type": type_s, "name": SimVehicle.sanitize_name(raw_name), "color_index": color}
	if type_s == "lobby_ready":  # {"value": bool}
		if typeof(v) != TYPE_BOOL:
			return {}
		return {"type": type_s, "value": v}
	if type_s == "set_rules" or type_s == "set_weapon_target":
		# {"scope": "rig" | weapon kind, "value": Doctrine text form | weapon target mode}
		var scope: Variant = d.get("scope")
		if typeof(scope) != TYPE_STRING or typeof(v) != TYPE_STRING:
			return {}
		var scope_s: String = scope
		if type_s == "set_weapon_target":
			if not Doctrine.is_weapon_scope(scope_s) or not Doctrine.WEAPON_TARGETS.has(String(v)):
				return {}
			return {"type": type_s, "scope": scope_s, "value": String(v)}
		if scope_s != Doctrine.SCOPE_RIG and not Doctrine.is_weapon_scope(scope_s):
			return {}
		var parsed: Variant = Doctrine.parse(String(v), scope_s)
		if parsed == null:
			return {}
		return {"type": type_s, "scope": scope_s, "value": Doctrine.encode(parsed)}
	if type_s == "set_ammo":  # {"scope": weapon kind, "value": ammo id} (the sim checks it is unlocked)
		var ascope: Variant = d.get("scope")
		if typeof(ascope) != TYPE_STRING or typeof(v) != TYPE_STRING:
			return {}
		if not Doctrine.is_weapon_scope(String(ascope)) or not Ammo.is_valid_id(String(v)):
			return {}
		return {"type": type_s, "scope": String(ascope), "value": String(v)}
	if type_s == "mark":  # {"x": float, "y": float} inside the arena (grown by MARK_MARGIN)
		var mx: Variant = d.get("x")
		var my: Variant = d.get("y")
		if (typeof(mx) != TYPE_INT and typeof(mx) != TYPE_FLOAT) or (typeof(my) != TYPE_INT and typeof(my) != TYPE_FLOAT):
			return {}
		var fx: float = float(mx)
		var fy: float = float(my)
		if not is_finite(fx) or not is_finite(fy) or not SimWorld.ARENA.grow(MARK_MARGIN).has_point(Vector2(fx, fy)):
			return {}
		return {"type": type_s, "x": fx, "y": fy}
	if type_s == "set_ability":  # {"slot": 0..SLOTS-1, "value": ability id} (the sim checks it is unlocked)
		var slot: int = _small_int(d.get("slot"), Abilities.SLOTS)
		if slot < 0 or typeof(v) != TYPE_STRING or not Abilities.IDS.has(String(v)):
			return {}
		return {"type": type_s, "slot": slot, "value": String(v)}
	if type_s == "respec_tech":  # {"from": owned tech id, "value": tech id to swap to}
		var from_v: Variant = d.get("from")
		if typeof(from_v) != TYPE_STRING or typeof(v) != TYPE_STRING:
			return {}
		if String(from_v).length() > 32 or String(v).length() > 32 or not Tech.has(String(from_v)) or not Tech.has(String(v)):
			return {}
		return {"type": type_s, "from": String(from_v), "value": String(v)}
	if type_s == "pick_card" or type_s == "reserve_card":
		var idx: int = -1
		if typeof(v) == TYPE_INT:
			idx = v
		elif typeof(v) == TYPE_FLOAT:
			var f: float = v
			if is_finite(f) and f == floorf(f) and f >= 0.0 and f < float(OFFER_SLOTS):
				idx = int(f)
		if idx < 0 or idx >= OFFER_SLOTS:
			return {}
		return {"type": type_s, "value": idx}
	if type_s == "accept_contract":  # {"value": contract offer index 0..MAX_OFFERS-1}
		var cidx: int = _small_int(v, Salvage.MAX_OFFERS)
		if cidx < 0:
			return {}
		return {"type": type_s, "value": cidx}
	if typeof(v) != TYPE_STRING:
		return {}
	var value_s: String = v
	if value_s.length() > 32:
		return {}
	if type_s == "buy_tech":
		if not Tech.has(value_s):
			return {}
		return {"type": type_s, "value": value_s}
	if type_s == "scrap_card":
		if not Cards.has(value_s):
			return {}
		return {"type": type_s, "value": value_s}
	if not COMMANDS.has(type_s):
		return {}
	var allowed: Variant = COMMANDS[type_s]
	if not allowed.has(value_s):
		return {}
	return {"type": type_s, "value": value_s}


## An int (or integral float, as JSON / RPC may deliver) in [0, limit), else -1.
static func _small_int(v: Variant, limit: int) -> int:
	var n: int = -1
	if typeof(v) == TYPE_INT:
		n = v
	elif typeof(v) == TYPE_FLOAT:
		var f: float = v
		if is_finite(f) and f == floorf(f) and f >= 0.0 and f < float(limit):
			n = int(f)
	return n if n >= 0 and n < limit else -1


## Validates a lobby roster received from the host: returns the sanitised list, or [] if it is
## malformed (wrong types, more than MAX_PLAYERS entries, duplicate peers / colours, no host).
static func parse_lobby(list: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if typeof(list) != TYPE_ARRAY:
		return out
	var arr: Array = list
	if arr.is_empty() or arr.size() > MAX_PLAYERS:
		return out
	var peers: Dictionary = {}
	var colors: Dictionary = {}
	var hosts: int = 0
	for item: Variant in arr:
		if typeof(item) != TYPE_DICTIONARY:
			return []
		var e: Dictionary = item
		if typeof(e.get("peer_id")) != TYPE_INT or typeof(e.get("name")) != TYPE_STRING \
				or typeof(e.get("ready")) != TYPE_BOOL or typeof(e.get("is_host")) != TYPE_BOOL:
			return []
		var pid: int = e["peer_id"]
		var color: int = _small_int(e.get("color_index"), SimVehicle.COLOR_COUNT)
		if pid < 1 or color < 0 or peers.has(pid) or colors.has(color) or String(e["name"]).length() > MAX_RAW_NAME:
			return []
		peers[pid] = true
		colors[color] = true
		if e["is_host"]:
			hosts += 1
		out.append({
			"peer_id": pid, "name": SimVehicle.sanitize_name(e["name"]), "color_index": color,
			"ready": e["ready"], "is_host": e["is_host"],
		})
	if hosts != 1:
		return []
	return out


# ---------------------------------------------------------------- stepping

func _physics_process(_delta: float) -> void:
	if world == null or (_mode != Mode.HOST and _mode != Mode.SOLO) or state == State.LOBBY:
		return
	world.step()
	if world.phase == SimWorld.PHASE_GAME_OVER and not _ended:
		_ended = true
		match_ended.emit(world.winner_peer)
	if _mode != Mode.HOST:
		return
	for e in world.events:
		if _pending_events.size() < MAX_PENDING_EVENTS:
			_pending_events.append(e)
	if world.tick % SNAPSHOT_EVERY == 0:
		if _net_ready():
			var bytes: PackedByteArray = Snapshot.encode(world, _pending_events)
			for p in multiplayer.get_peers():
				if not _refused.has(p):
					_rpc_snapshot.rpc_id(p, bytes)
		_pending_events.clear()


## True when RPCs can go out (in the tree with at least one connected peer).
func _net_ready() -> bool:
	return is_inside_tree() and multiplayer.multiplayer_peer != null and not multiplayer.get_peers().is_empty()


# ---------------------------------------------------------------- RPCs

@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(bytes: PackedByteArray) -> void:
	if _mode != Mode.CLIENT or world == null or state != State.MATCH:
		return
	if Snapshot.apply(world, bytes) and world.phase == SimWorld.PHASE_GAME_OVER and not _ended:
		_ended = true
		match_ended.emit(world.winner_peer)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_command(cmd: Variant) -> void:
	if _mode != Mode.HOST:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	var now: int = Time.get_ticks_msec()
	if not _rate_ok(sender, now):
		return
	var clean: Dictionary = validate_command(cmd)
	if clean.is_empty():
		return
	if LOBBY_COMMANDS.has(str(clean["type"])) and not _window_ok(_lobby_rate, sender, now, MAX_LOBBY_COMMANDS_PER_SEC):
		return
	_apply_command(sender, clean)


## Host -> clients: the full roster (reliable, on every change).
@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(list: Variant) -> void:
	if _mode != Mode.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	var parsed: Array[Dictionary] = parse_lobby(list)
	if parsed.is_empty():
		return
	lobby_players = parsed
	var me: Dictionary = local_player()
	if not me.is_empty():  # adopt the name / colour the host assigned
		_my_name = me["name"]
		_my_color = me["color_index"]
	lobby_changed.emit()


## Host -> clients: a (new) match began; start from a fresh passive world and wait for snapshots.
@rpc("authority", "call_remote", "reliable")
func _rpc_match_started() -> void:
	if _mode != Mode.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	_new_world(false)
	state = State.MATCH
	_ended = false
	match_started.emit()


## Host -> a refused client (just before it is disconnected).
@rpc("authority", "call_remote", "reliable")
func _rpc_rejected(reason: Variant) -> void:
	if _mode != Mode.CLIENT or multiplayer.get_remote_sender_id() != 1:
		return
	join_rejected.emit(str(reason).left(64))


## Validates and applies a command from `peer_id`. Anything not on the allow-list is ignored.
func _handle_command(peer_id: int, cmd: Variant) -> void:
	if world == null:
		return
	var clean: Dictionary = validate_command(cmd)
	if clean.is_empty():
		return
	_apply_command(peer_id, clean)


func _apply_command(peer_id: int, clean: Dictionary) -> void:
	match str(clean["type"]):
		"profile":
			_lobby_set_profile(peer_id, str(clean["name"]), int(clean["color_index"]))
		"lobby_ready":
			_lobby_set_ready(peer_id, bool(clean["value"]))
		_:
			if world != null:
				world.apply_command(peer_id, clean)


## Fixed one-second window limiter per peer.
func _rate_ok(peer_id: int, now_ms: int) -> bool:
	return _window_ok(_rate, peer_id, now_ms, MAX_COMMANDS_PER_SEC)


func _window_ok(table: Dictionary, peer_id: int, now_ms: int, limit: int) -> bool:
	var entry: Array = table.get(peer_id, [now_ms, 0])
	if now_ms - int(entry[0]) >= 1000:
		entry = [now_ms, 0]
	entry[1] = int(entry[1]) + 1
	table[peer_id] = entry
	return int(entry[1]) <= limit


# ---------------------------------------------------------------- lobby (host side)

## Placeholder world for the lobby: no vehicles, not stepped, so `world` is never null.
func _new_lobby_world() -> SimWorld:
	var w := SimWorld.new(0)
	w.spawning_enabled = false
	return w


## Host / solo: opens the lobby with the local player as its only entry.
func _open_lobby() -> void:
	state = State.LOBBY
	world = _new_lobby_world()
	lobby_players = []
	_lobby_add(1, _my_name, _my_color, true)
	lobby_changed.emit()


func _lobby_find(peer_id: int) -> int:
	for i in lobby_players.size():
		if int(lobby_players[i]["peer_id"]) == peer_id:
			return i
	return -1


func _name_taken(p_name: String, except_peer: int) -> bool:
	var low: String = p_name.to_lower()
	for e in lobby_players:
		if int(e["peer_id"]) != except_peer and String(e["name"]).to_lower() == low:
			return true
	return false


func _color_taken(color: int, except_peer: int) -> bool:
	for e in lobby_players:
		if int(e["peer_id"]) != except_peer and int(e["color_index"]) == color:
			return true
	return false


## `raw` made unique among the other players ("BOB", "BOB 2", "BOB 3", ...; case-insensitive).
func _unique_name(raw: String, peer_id: int) -> String:
	var base: String = SimVehicle.sanitize_name(raw)
	var cand: String = base
	var n: int = 2
	while _name_taken(cand, peer_id) and n < 100:
		var suffix: String = " %d" % n
		cand = base.left(SimVehicle.MAX_NAME_LEN - suffix.length()).strip_edges() + suffix
		n += 1
	return cand


## `preferred` if free, else `fallback` if it is a free colour, else the lowest free colour.
func _free_color(preferred: int, peer_id: int, fallback: int = -1) -> int:
	if preferred >= 0 and preferred < SimVehicle.COLOR_COUNT and not _color_taken(preferred, peer_id):
		return preferred
	if fallback >= 0 and fallback < SimVehicle.COLOR_COUNT and not _color_taken(fallback, peer_id):
		return fallback
	for c in SimVehicle.COLOR_COUNT:
		if not _color_taken(c, peer_id):
			return c
	return clampi(preferred, 0, SimVehicle.COLOR_COUNT - 1)


func _lobby_add(peer_id: int, p_name: String, color: int, host_entry: bool = false) -> Dictionary:
	var e := {
		"peer_id": peer_id, "name": _unique_name(p_name, peer_id),
		"color_index": _free_color(color, peer_id), "ready": false, "is_host": host_entry,
	}
	lobby_players.append(e)
	return e


func _lobby_set_profile(peer_id: int, p_name: String, color: int) -> void:
	var i: int = _lobby_find(peer_id)
	if i < 0:
		return
	var e: Dictionary = lobby_players[i]
	var new_name: String = _unique_name(p_name, peer_id)
	var new_color: int = _free_color(color, peer_id, int(e["color_index"]))
	if new_name == e["name"] and new_color == int(e["color_index"]):
		return
	e["name"] = new_name
	e["color_index"] = new_color
	var v: SimVehicle = world.get_vehicle_for_peer(peer_id) if world != null else null
	if v != null:  # profile changes mid-match show up on the vehicle
		v.player_name = new_name
		v.color_index = new_color
	_lobby_changed()


func _lobby_set_ready(peer_id: int, value: bool) -> void:
	if state != State.LOBBY:
		return
	var i: int = _lobby_find(peer_id)
	if i < 0 or lobby_players[i]["ready"] == value:
		return
	lobby_players[i]["ready"] = value
	_lobby_changed()


func _lobby_changed() -> void:
	lobby_changed.emit()
	if _mode == Mode.HOST and _net_ready():
		for p in multiplayer.get_peers():
			if not _refused.has(p):
				_rpc_lobby.rpc_id(p, lobby_players)


## Host: builds the match world from the roster and starts it.
func _begin_match() -> void:
	_pending_events.clear()
	_departed.clear()
	_new_world(true)
	for i in lobby_players.size():
		var e: Dictionary = lobby_players[i]
		world.add_vehicle(int(e["peer_id"]), spawn_position(i), e["name"], int(e["color_index"]))
	world.begin_deploy()
	state = State.MATCH
	_ended = false
	if _mode == Mode.HOST and _net_ready():
		for p in multiplayer.get_peers():
			if not _refused.has(p):
				_rpc_match_started.rpc_id(p)
				_rpc_lobby.rpc_id(p, lobby_players)  # (ready flags are reset on a rematch)
	match_started.emit()


## Tells a peer why it is refused, then closes its connection once the message has been flushed
## (a plain disconnect_peer() drops queued packets). The peer gets no snapshots or lobby updates.
func _reject(peer_id: int, reason: String) -> void:
	_refused[peer_id] = true
	if is_inside_tree() and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer
		_rpc_rejected.rpc_id(peer_id, reason)
		var pp: ENetPacketPeer = enet.get_peer(peer_id)
		if pp != null:
			pp.peer_disconnect_later()
		else:
			enet.disconnect_peer(peer_id)


# ---------------------------------------------------------------- peers

func _new_world(is_authority: bool) -> void:
	var keep_fast: bool = fast_rounds or (world != null and world.fast_rounds and is_authority)
	var s: int
	if world_seed >= 0:
		s = world_seed + _match_count
	else:
		s = randi()
	if is_authority:
		_match_count += 1
	world = SimWorld.new(s)
	world.spawning_enabled = is_authority
	if keep_fast:
		world.fast_rounds = true
	_pending_events.clear()


## Spawn position for the n-th player: spread on an ellipse around the arena centre.
static func spawn_position(slot: int) -> Vector2:
	var a: float = float(slot % 8) * TAU / 8.0
	var c: Vector2 = SimWorld.ARENA.get_center()
	return c + Vector2(cos(a) * SimWorld.SPAWN_ELLIPSE.x, sin(a) * SimWorld.SPAWN_ELLIPSE.y)


func _spawn_vehicle_for(peer_id: int) -> SimVehicle:
	if world.get_vehicle_for_peer(peer_id) != null:
		return null
	var li: int = _lobby_find(peer_id)
	var v: SimVehicle = null
	# Reuse the slot of a departed player so vehicle ids (= array index) stay bounded.
	for i in world.vehicles.size():
		if _departed.has(world.vehicles[i].id):
			var old: SimVehicle = world.vehicles[i]
			var fresh := SimVehicle.new(old.id, peer_id, spawn_position(i))
			fresh.heading = (SimWorld.ARENA.get_center() - fresh.pos).angle()
			world.vehicles[i] = fresh
			world.prepare_vehicle(fresh)
			_departed.erase(old.id)
			v = fresh
			break
	if v == null:
		if world.vehicles.size() >= MAX_VEHICLES:
			return null
		v = world.add_vehicle(peer_id, spawn_position(world.vehicles.size()))
	if li >= 0:
		v.player_name = lobby_players[li]["name"]
		v.color_index = int(lobby_players[li]["color_index"])
	return v


func _on_peer_connected(id: int) -> void:
	if _mode != Mode.HOST:
		return
	if state == State.LOBBY:
		if lobby_players.size() >= MAX_PLAYERS:
			_reject(id, "lobby full")
			return
		_lobby_add(id, SimVehicle.DEFAULT_NAME, 0)
		peer_joined.emit(id)
		_lobby_changed()
		return
	# A match is running (or the legacy auto-started session): late join or refuse.
	if not allow_late_join:
		_reject(id, "match in progress")
		return
	if lobby_players.size() >= MAX_PLAYERS:
		_reject(id, "game full")
		return
	var e: Dictionary = _lobby_add(id, SimVehicle.DEFAULT_NAME, 0)
	if _spawn_vehicle_for(id) == null:
		lobby_players.erase(e)
		_reject(id, "game full")
		return
	if _net_ready():
		_rpc_match_started.rpc_id(id)
	peer_joined.emit(id)
	_lobby_changed()


func _on_peer_disconnected(id: int) -> void:
	_rate.erase(id)
	_lobby_rate.erase(id)
	_refused.erase(id)
	if _mode != Mode.HOST or world == null:
		peer_left.emit(id)
		return
	var known: bool = false
	var v: SimVehicle = world.get_vehicle_for_peer(id)
	if v != null:
		known = true
		if v.alive:
			v.alive = false
			v.hp = 0.0
			v.vel = Vector2.ZERO
			v.target_kind = 0
			if _pending_events.size() < MAX_PENDING_EVENTS:
				_pending_events.append({"type": "vehicle_destroyed", "pos": v.pos, "owner": v.id, "kind": -1})
		v.eliminated = true  # a departed player is out of the round loop (no respawn, no ready needed)
		v.offers = []
		v.peer_id = 0  # no longer addressable by commands
		_departed[v.id] = true
	var li: int = _lobby_find(id)
	if li >= 0:
		known = true
		lobby_players.remove_at(li)
		_lobby_changed()
	if known:
		peer_left.emit(id)


func _on_connected_to_server() -> void:
	# The hello: our local profile; the host answers with the full roster.
	send_command({"type": "profile", "name": _my_name, "color_index": _my_color})
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
