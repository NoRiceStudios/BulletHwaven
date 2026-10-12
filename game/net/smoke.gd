extends SceneTree
## Headless LAN smoke harness (driven by scripts/lan-smoke.sh):
##   godot --headless --path game -s res://net/smoke.gd -- --role=host|client [--seconds=N]
##       [--until=<unix ms>] [--address=127.0.0.1] [--port=24680] [--discovery]
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
	if _role == "host":
		var err: Error = _session.host(_port)
		if err != OK:
			_fail("host() failed: %s" % error_string(err))
			return
		if _discovery_on:
			_lan_error = _lan.start_beacon(_port)
	else:
		_session.session_started.connect(func() -> void: _connected = true)
		_session.connection_failed.connect(func() -> void: _fail("connection failed"))
		if _discovery_on:
			_lan.host_found.connect(func(addr: String, info: Dictionary) -> void:
				_found.append("%s:%d" % [addr, int(info.get("port", 0))]))
			_lan_error = _lan.start_listening()
		var err2: Error = _session.join(_address, _port)
		if err2 != OK:
			_fail("join() failed: %s" % error_string(err2))


func _process(_delta: float) -> bool:
	if _finished:
		return true
	var now: int = Time.get_ticks_msec()
	if _role == "client" and _connected and _session.world != null:
		# Send the command once on connect, then retry once a second until it is visible.
		var mine: SimVehicle = _session.world.get_vehicle_for_peer(_session.local_peer_id())
		var done: bool = mine != null and mine.doctrine.get("drive", "") == "kite"
		if not done and now - _command_sent_ms >= 1000:
			_command_sent_ms = now
			_session.send_command({"type": "set_drive", "value": "kite"})
	if _role == "host" and _discovery_on:
		_lan.player_count = _session.player_count()
	if now >= _deadline_ms:
		_report()
		_finished = true
		quit(0)
	return false


func _report() -> void:
	var w: SimWorld = _session.world
	var vehicles: Array = []
	for v in w.vehicles:
		vehicles.append({
			"id": v.id, "peer_id": v.peer_id, "alive": v.alive,
			"drive": v.doctrine.get("drive", ""), "target": v.doctrine.get("target", ""),
		})
	var res := {
		"role": _role,
		"tick": w.tick,
		"enemy_count": w.enemy_count,
		"proj_count": w.proj_count,
		"vehicle_count": w.vehicles.size(),
		"vehicles": vehicles,
		"local_peer_id": _session.local_peer_id(),
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
	print("SMOKE_RESULT " + JSON.stringify(res))


func _fail(msg: String) -> void:
	printerr("smoke: " + msg)
	print("SMOKE_RESULT " + JSON.stringify({"role": _role, "error": msg}))
	_finished = true
	quit(1)
