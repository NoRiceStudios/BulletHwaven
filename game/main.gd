extends Node
## Entry point (docs/architecture.md, "Entry point and command line"). User args after `--`:
##   (none)                solo game
##   --host                host a LAN game
##   --join=<ip>           join a host
##   --fast                (solo / host) fast_rounds: 4 s combat, 1.5 s workshop, for UI testing
##   --shot=<png> --scenario=<name> --seed=<n> --ticks=<n> [--hover=x,y] [--click=x,y;x,y...]
##                         screenshot: build tools/scenarios.gd, step it, save <png> (640x360)
##                         and <png minus .png>_1080p.png (3x nearest), then quit (exit 1 on error).
##                         --hover puts the UI pointer at x,y (viewport px); --click clicks there
##                         through the workshop UI's own click path (commands go to the world).
## Keys (combat): 1/2/3 drive circle/kite/charge, Q/W/E target nearest/strongest/players_first.
## Workshop and game over keys are handled by render/workshop_ui.gd and render/game_over_ui.gd.

const NET_SESSION_PATH := "res://net/net_session.gd"
const DRIVE_KEYS := {KEY_1: "circle", KEY_2: "kite", KEY_3: "charge"}
const TARGET_KEYS := {KEY_Q: "nearest", KEY_W: "strongest", KEY_E: "players_first"}

@onready var _view: WorldView = $WorldView

## The NetSession, loaded by path so screenshot mode never depends on game/net.
var _session: Node = null


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	if args.has("shot"):
		_run_shot(args)
	else:
		_start_session(args)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


# ---------------------------------------------------------------- normal modes

func _start_session(args: Dictionary) -> void:
	var script: Script = load(NET_SESSION_PATH)
	if script == null:
		push_error("main: cannot load %s" % NET_SESSION_PATH)
		get_tree().quit(1)
		return
	_session = script.new()
	add_child(_session)  # must sit at the same path (/root/Main/NetSession) on every peer
	# One log line per network event, so LAN sessions can be debugged from the console.
	_session.connect("peer_joined", func(id: int) -> void: print("net: peer %d joined" % id))
	_session.connect("peer_left", func(id: int) -> void: print("net: peer %d left" % id))
	_session.connect("session_started", func() -> void: print("net: session started (peer %d)" % _session.call("local_peer_id")))
	_session.connect("connection_failed", func() -> void: print("net: connection failed"))
	var err: int = OK
	if args.has("host"):
		err = _session.call("host")
	elif args.has("join"):
		var address: String = args["join"] if args["join"] != "" else "127.0.0.1"
		err = _session.call("join", address)
	else:
		_session.call("start_solo")
	if err != OK:
		push_error("main: network start failed (%s)" % error_string(err))
		get_tree().quit(1)
		return
	var w: SimWorld = _session.get("world")
	if args.has("fast") and w != null and not args.has("join"):
		w.fast_rounds = true
	_view.workshop.send_command = func(cmd: Dictionary) -> void: _session.call("send_command", cmd)
	_view.game_over.quit = func() -> void: get_tree().quit(0)
	if not args.has("host") and not args.has("join"):
		_view.game_over.restart = func() -> void: _session.call("start_solo")


func _process(_delta: float) -> void:
	if _session == null:
		return
	var w: SimWorld = _session.get("world")
	var peer: int = _session.call("local_peer_id")
	if w != _view.world or peer != _view.local_peer:
		_view.set_world(w, peer)


func _unhandled_input(event: InputEvent) -> void:
	if _session == null or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var w: SimWorld = _session.get("world")
	if w == null or w.phase != SimWorld.PHASE_COMBAT:
		return
	var key: Key = (event as InputEventKey).keycode
	if DRIVE_KEYS.has(key):
		_session.call("send_command", {"type": "set_drive", "value": DRIVE_KEYS[key]})
	elif TARGET_KEYS.has(key):
		_session.call("send_command", {"type": "set_target", "value": TARGET_KEYS[key]})


# ---------------------------------------------------------------- screenshot mode

static func _parse_point(spec: String, fallback: Vector2) -> Vector2:
	var parts: PackedStringArray = spec.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return fallback
	return Vector2(int(parts[0]), int(parts[1]))


func _run_shot(args: Dictionary) -> void:
	var out_path: String = args["shot"]
	var scenario: String = args.get("scenario", "skirmish")
	var sd: int = int(args.get("seed", "1"))
	var ticks: int = int(args.get("ticks", "300"))
	var world: SimWorld = Scenarios.build(scenario, sd)
	if out_path == "" or world == null:
		push_error("main: bad --shot/--scenario (scenarios: %s)" % ", ".join(Scenarios.NAMES))
		get_tree().quit(1)
		return
	var history: Array = []
	for i in ticks:
		Scenarios.step(scenario, world)
		history.append(WorldView.record_tick(world))
	_view.frozen = true
	_view.set_world(world, 1)
	_view.prime(history)
	_view.workshop.send_command = func(cmd: Dictionary) -> void: world.apply_command(1, cmd)
	_view.workshop.use_real_pointer = false
	if world.vehicles.size() < 2:
		_view.game_over.restart = func() -> void: pass  # show the solo screen as played
	_view.workshop.pointer_override = _parse_point(args.get("hover", ""), Vector2(-1, -1))
	for i in 4:
		await get_tree().process_frame
	if args.has("click"):
		for spec: String in str(args["click"]).split(";", false):
			var p: Vector2 = _parse_point(spec, Vector2(-1, -1))
			var ok: bool = _view.workshop.visible and _view.workshop.click_at(p)
			print("SHOT_CLICK %s -> %s" % [spec, "hit" if ok else "miss"])
			await get_tree().process_frame
			await get_tree().process_frame
	# two drawn frames: the first bakes the decal viewport, the second shows it
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("main: viewport capture failed")
		get_tree().quit(1)
		return
	var native := Vector2i(640, 360)
	if img.get_size() != native:  # window-sized capture: the 640x360 frame scaled up by an integer
		img.resize(native.x, native.y, Image.INTERPOLATE_NEAREST)
	var abs_path: String = out_path if out_path.is_absolute_path() else OS.get_environment("PWD").path_join(out_path)
	var err: Error = img.save_png(abs_path)
	var big: Image = img.duplicate()
	big.resize(native.x * 3, native.y * 3, Image.INTERPOLATE_NEAREST)
	var big_path: String = abs_path.get_basename() + "_1080p.png"
	if err == OK:
		err = big.save_png(big_path)
	if err != OK:
		push_error("main: cannot save %s (%s)" % [abs_path, error_string(err)])
		get_tree().quit(1)
		return
	print("SHOT_OK %s %s (tick %d, %d enemies, %d projectiles)" % [abs_path, big_path, world.tick, world.enemy_count, world.proj_count])
	get_tree().quit(0)
