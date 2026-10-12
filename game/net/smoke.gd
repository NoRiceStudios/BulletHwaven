extends SceneTree
## Headless LAN smoke harness (driven by scripts/lan-smoke.sh):
##   godot --headless --path game -s res://net/smoke.gd -- --role=host|client|late [--seconds=N]
##       [--until=<unix ms>] [--address=127.0.0.1] [--port=24680] [--discovery]
## host: opens a lobby as "Hosty" (colour 3), starts the match once the client is ready.
## client: joins as "hosty" (same name modulo case, same colour: the host must uniquify both),
##         readies up, then plays (sends a command).
## late: joins after the match started and must be refused (join_rejected).
## Prints exactly one JSON result line prefixed with "SMOKE_RESULT ".

var _role: String = "host"
var _address: String = "127.0.0.1"
var _port: int = NetSession.DEFAULT_PORT
var _discovery_on: bool = false
var _deadline_ms: int = 0
var _session: NetSession
var _lan: LanDiscovery
var _connected: bool = false
var _command_sent_ms: int = 0
var _found: Array[String] = []
var _found_states: Array[String] = []
var _match: bool = false
var _ready_sent: bool = false
var _lobby_at_start: Array = []  # host: roster when it pressed start; client: roster at match_started
var _rejected: String = ""
var _lan_error: int = OK
var _finished: bool = false


func _initialize() -> void:
	var seconds: float = 6.0
	var until_ms: int = 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			_role = a.substr(7)
		elif a.begins_with("--seconds="):
			seconds = a.substr(10).to_float()
		elif a.begins_with("--until="):
			until_ms = int(a.substr(8))
		elif a.begins_with("--address="):
			_address = a.substr(10)
		elif a.begins_with("--port="):
			_port = int(a.substr(7))
		elif a == "--discovery":
			_discovery_on = true
	if until_ms > 0:
		_deadline_ms = Time.get_ticks_msec() + maxi(until_ms - int(Time.get_unix_time_from_system() * 1000.0), 0)
	else:
		_deadline_ms = Time.get_ticks_msec() + int(seconds * 1000.0)

	_session = NetSession.new()
	_session.world_seed = 4242
	_lan = LanDiscovery.new()
	# The root is still busy during _initialize: add the nodes (and start) deferred.
	root.add_child.call_deferred(_session)
	root.add_child.call_deferred(_lan)
	_start.call_deferred()


func _start() -> void:
	_session.match_started.connect(func() -> void:
		_match = true
		if _role == "client":
			_lobby_at_start = _roster())
	if _role == "host":
		_session.set_profile("Hosty", 3)
		var err: Error = _session.host(_port, false)  # lobby first, like the menu
		if err != OK:
			_fail("host() failed: %s" % error_string(err))
			return
		if _discovery_on:
			_lan.session = _session
			_lan_error = _lan.start_beacon(_port)
	else:
		_session.session_started.connect(func() -> void: _connected = true)
		_session.connection_failed.connect(func() -> void: _fail("connection failed"))
		_session.join_rejected.connect(func(reason: String) -> void: _rejected = reason)
		if _role == "client":
			_session.set_profile("hosty", 3)
		if _discovery_on and _role == "client":
			_lan.host_found.connect(func(addr: String, info: Dictionary) -> void:
				_found.append("%s:%d" % [addr, int(info.get("port", 0))])
				_found_states.append("%s/%d" % [info.get("state", "?"), int(info.get("players", 0))]))
			_lan_error = _lan.start_listening()
		var err2: Error = _session.join(_address, _port)
		if err2 != OK:
			_fail("join() failed: %s" % error_string(err2))


func _process(_delta: float) -> bool:
	if _finished:
		return true
	var now: int = Time.get_ticks_msec()
	if _role == "host" and not _match and _session.lobby_players.size() >= 2 and _session.lobby_all_ready():
		_lobby_at_start = _roster()
		var err: Error = _session.start_match()
		if err != OK:
			_fail("start_match() failed: %s" % error_string(err))
			return true
	if _role == "client" and _connected and not _match and not _ready_sent and not _session.local_player().is_empty():
		_ready_sent = true
		_session.set_lobby_ready(true)
	if _role == "client" and _match and _session.world != null:
		# Send the command once the match runs, then retry once a second until it is visible.
		var mine: SimVehicle = _session.world.get_vehicle_for_peer(_session.local_peer_id())
		var done: bool = mine != null and mine.doctrine.get("drive", "") == "kite"
		if not done and now - _command_sent_ms >= 1000:
			_command_sent_ms = now
			_session.send_command({"type": "set_drive", "value": "kite"})
	if _role == "late" and _rejected != "":
		_report()
		_finished = true
		quit(0)
		return true
	if now >= _deadline_ms:
		_report()
		_finished = true
		quit(0)
	return false


func _roster() -> Array:
	var out: Array = []
	for e in _session.lobby_players:
		out.append({"peer_id": e["peer_id"], "name": e["name"], "color_index": e["color_index"], "ready": e["ready"]})
	return out


func _report() -> void:
	var w: SimWorld = _session.world
	var vehicles: Array = []
	for v in w.vehicles:
		vehicles.append({
			"id": v.id, "peer_id": v.peer_id, "alive": v.alive,
			"drive": v.doctrine.get("drive", ""), "target": v.doctrine.get("target", ""),
			"name": v.player_name, "color": v.color_index,
		})
	var res := {
		"role": _role,
		"tick": w.tick,
		"enemy_count": w.enemy_count,
		"proj_count": w.proj_count,
		"vehicle_count": w.vehicles.size(),
		"vehicles": vehicles,
		"local_peer_id": _session.local_peer_id(),
		"in_match": _match,
		"lobby_at_start": _lobby_at_start,
		"roster": _roster(),
		"rejected": _rejected,
	}
	if _role == "client":
		var mine: SimVehicle = w.get_vehicle_for_peer(_session.local_peer_id())
		res["own_vehicle_exists"] = mine != null
		res["own_drive_is_kite"] = mine != null and mine.doctrine.get("drive", "") == "kite"
	if _discovery_on:
		res["discovery_error"] = _lan_error
		if _role == "host":
			res["beacons_sent"] = _lan.beacons_sent
			res["beacon_send_error"] = _lan.last_send_error
		else:
			res["discovery_found"] = _found
			res["discovery_states"] = _found_states
	print("SMOKE_RESULT " + JSON.stringify(res))


func _fail(msg: String) -> void:
	printerr("smoke: " + msg)
	print("SMOKE_RESULT " + JSON.stringify({"role": _role, "error": msg}))
	_finished = true
	quit(1)
