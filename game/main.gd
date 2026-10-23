extends Node
## Entry point and front-end controller (docs/architecture.md, "Entry point and command line").
## User args after `--`:
##   (none)                the main menu (solo, host / join a LAN game, driver profile)
##   --solo                straight into a solo game (the old no-args behaviour)
##   --host                host a LAN game that starts at once and takes late joiners (auto_start)
##   --join=<ip>           join a host (its lobby or, for an auto-start host, its match)
##   --fast                (solo / host) fast_rounds: 4 s combat, 1.5 s workshop, for UI testing
##   --shot=<png> --scenario=<name> --seed=<n> --ticks=<n> [--hover=x,y] [--click=x,y;x,y...]
##                         screenshot: build tools/scenarios.gd, step it, save <png> (640x360 preview)
##                         and <png minus .png>_1080p.png (full resolution), then quit (exit 1 on error).
##                         --hover puts the UI pointer at x,y (viewport px); --click clicks there
##                         through the visible UI's own click path (menu or workshop).
##   --scenario=replay --session=<dir> --frames=<frames.json>   (playtest harness, scripts/playtest.sh)
##   --windowed            start in a window (default: fullscreen, toggled with F11 / Alt+Enter and remembered)
## Keys (any screen): F11 or Alt+Enter toggles fullscreen.
## Keys (combat): 1/2/3 drive circle/kite/charge, Q/W/E target nearest/strongest/players_first,
## P the rule editor (render/doctrine_editor.gd, any phase),
## Esc the pause / menu overlay (solo pauses the sim). Workshop and game over keys are handled by
## render/workshop_ui.gd and render/game_over_ui.gd, menu keys by render/menu_ui.gd.
##
## The menu passes auto_start = false to NetSession.host(); the profile (driver name and paint)
## is kept in user://profile.cfg.

const NET_SESSION_PATH := "res://net/net_session.gd"
const LAN_DISCOVERY_PATH := "res://net/lan_discovery.gd"
const PROFILE_PATH := "user://profile.cfg"
const PORT := 24680
const DRIVE_KEYS := {KEY_1: "circle", KEY_2: "kite", KEY_3: "charge", KEY_4: "zone"}
const TARGET_KEYS := {KEY_Q: "nearest", KEY_W: "strongest", KEY_E: "players_first"}
const ABILITY_KEYS := {KEY_F: 0, KEY_G: 1}  ## cast the ability in slot 0 / 1 by hand
const RADIO_KEYS := {KEY_Z: "fall_back", KEY_X: "all_in", KEY_C: "hold", KEY_V: "boss"}  ## radio commands (Orders)
const FIT_INTEGER_MIN := 0.94  ## whole-pixel scaling only while it fills at least this much of the window
const DEMO_TICKS := 30 * 120  ## the menu's attract battle restarts after this many ticks

@onready var _view: WorldView = $Stage/World/WorldView

var _menu: MenuUi = null
var _audio: AudioDirector = null  ## music and sound effects (not in screenshot mode)
## The NetSession and LanDiscovery, loaded by path so screenshot mode never depends on game/net.
## Each is created once and reused (the session must keep its node path for RPCs).
var _session: Node = null
var _lan: Node = null
var _demo: SimWorld = null  ## attract-mode battle behind the menus
var _fast: bool = false
var _paused: bool = false
var _solo: bool = false  ## the running session is a solo game (pause really pauses)
var _in_match: bool = false
var _join_target: String = ""  ## "ip:port" we are connecting to (join screen)
var _home: MenuUi.Screen = MenuUi.Screen.MAIN  ## menu screen shown while no session runs


func _ready() -> void:
	var args: Dictionary = _parse_args(OS.get_cmdline_user_args())
	_menu = _make_menu()
	if args.has("shot"):
		_run_shot(args)
		return
	_fast = args.has("fast")
	_load_profile()
	_audio = AudioDirector.new()
	_audio.view = _view
	_view.get_viewport().audio_listener_enable_2d = true  # the world camera is the ear for positional sounds
	_view.add_child(_audio)
	_menu.audio_levels = _audio.levels
	_menu.audio_muted = _audio.muted
	_setup_display(args.has("windowed"))
	_menu.action.connect(_on_menu_action)
	_view.game_over.quit = _leave_to_menu
	if args.has("host") or args.has("join") or args.has("solo"):
		_start_cli(args)
	else:
		_show_home(MenuUi.Screen.MAIN)


static func _parse_args(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a in raw:
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func _make_menu() -> MenuUi:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var m := MenuUi.new()
	layer.add_child(m)
	return m


# ---------------------------------------------------------------- session plumbing

func _ensure_session() -> bool:
	if _session != null:
		return true
	var script: Script = load(NET_SESSION_PATH)
	if script == null:
		push_error("main: cannot load %s" % NET_SESSION_PATH)
		return false
	_session = script.new()
	add_child(_session)  # must sit at the same path (/root/Main/NetSession) on every peer
	# One log line per network event, so LAN sessions can be debugged from the console.
	_session.connect("peer_joined", func(id: int) -> void: print("net: peer %d joined" % id))
	_session.connect("peer_left", func(id: int) -> void: print("net: peer %d left" % id))
	_session.connect("session_started", func() -> void: print("net: session started (peer %d)" % _session.call("local_peer_id")))
	_session.connect("connection_failed", _on_connection_failed)
	_session.connect("disconnected", _on_disconnected)
	_session.connect("join_rejected", _on_join_rejected)
	_session.connect("match_started", func() -> void: print("net: match started"))
	_session.connect("match_ended", func(w: int) -> void: print("net: match ended (winner peer %d)" % w))
	return true


func _ensure_lan() -> bool:
	if _lan != null:
		return true
	var script: Script = load(LAN_DISCOVERY_PATH)
	if script == null:
		return false
	_lan = script.new()
	add_child(_lan)
	_lan.connect("host_found", _on_host_found)
	_lan.connect("host_lost", _on_host_lost)
	return true


func _session_active() -> bool:
	return _session != null and (bool(_session.call("is_host")) or bool(_session.call("is_client")))


func _start_cli(args: Dictionary) -> void:
	if not _ensure_session():
		get_tree().quit(1)
		return
	_session.call("set_profile", _menu.profile_name, _menu.profile_color)
	_session.set("fast_rounds", _fast)
	var err: int = OK
	_solo = not args.has("host") and not args.has("join")
	if args.has("host"):
		err = _session.call("host", PORT, true)
		if err == OK:
			_beacon()
	elif args.has("join"):
		var address: String = args["join"] if args["join"] != "" else "127.0.0.1"
		_join_target = "%s:%d" % [address, PORT]
		_home = MenuUi.Screen.JOIN
		err = _session.call("join", address, PORT)
	else:
		_session.call("start_solo", _menu.profile_name, _menu.profile_color)
	if err != OK:
		push_error("main: network start failed (%s)" % error_string(err))
		get_tree().quit(1)


func _beacon() -> void:
	if _ensure_lan():
		_lan.set("session", _session)
		if _lan.call("start_beacon", PORT) != OK:
			print("net: LAN beacon unavailable")


# ---------------------------------------------------------------- menu actions

func _on_menu_action(act: String, arg: Variant) -> void:
	if _audio != null and act not in ["volume", "mute"]:
		_audio.play("ui_click")
	match act:
		"volume":  # [key, level]
			var va: Array = arg
			_audio.set_level(str(va[0]), float(va[1]))
			_audio.play("ui_click")
		"mute":
			_audio.set_muted(not _audio.muted)
			_menu.audio_muted = _audio.muted
		"solo":
			if _ensure_session():
				_solo = true
				_session.set("fast_rounds", _fast)
				_session.call("start_solo", _menu.profile_name, _menu.profile_color)
		"host":
			if not _ensure_session():
				return
			_session.call("set_profile", _menu.profile_name, _menu.profile_color)
			_session.set("fast_rounds", _fast)
			_solo = false
			var err: int = _session.call("host", PORT, false)
			if err != OK:
				_notice("CANNOT OPEN PORT %d (%s)" % [PORT, error_string(err).to_upper()])
				return
			_beacon()
		"join_screen":
			_show_home(MenuUi.Screen.JOIN)
		"back":
			_leave_to_menu()
		"quit":
			get_tree().quit(0)
		"join":
			var h: Dictionary = arg
			_join(str(h.get("address", "")), int(h.get("port", PORT)))
		"join_ip":
			var spec: String = str(arg).strip_edges()
			var port: int = PORT
			var colon: int = spec.rfind(":")
			if colon > 0 and spec.substr(colon + 1).is_valid_int():
				port = clampi(int(spec.substr(colon + 1)), 1, 65535)
				spec = spec.left(colon)
			_join(spec, port)
		"profile":
			var p: Array = arg
			_menu.profile_name = SimVehicle.sanitize_name(str(p[0]))
			_menu.profile_color = clampi(int(p[1]), 0, SimVehicle.COLOR_COUNT - 1)
			_save_profile()
			if _session_active():
				_session.call("set_profile", _menu.profile_name, _menu.profile_color)
		"ready":
			if _session_active():
				_session.call("set_lobby_ready", bool(arg))
		"start", "force_start":
			if _session_active():
				var e: int = _session.call("start_match")
				if e != OK:
					_notice("CANNOT START (%s)" % error_string(e).to_upper())
		"leave", "leave_match":
			_leave_to_menu()
		"resume":
			_set_paused(false)


func _join(address: String, port: int) -> void:
	if address == "" or not _ensure_session():
		_notice("TYPE AN ADDRESS FIRST")
		return
	_session.call("set_profile", _menu.profile_name, _menu.profile_color)
	_solo = false
	_join_target = "%s:%d" % [address, port]
	var err: int = _session.call("join", address, port)
	if err != OK:
		_notice("CANNOT REACH %s (%s)" % [_join_target, error_string(err).to_upper()])
	else:
		_menu.status = ""


func _notice(text: String, is_error: bool = true) -> void:
	_menu.status = text
	_menu.status_error = is_error


func _on_connection_failed() -> void:
	print("net: connection failed")
	_leave_session()
	_show_home(MenuUi.Screen.JOIN)
	_notice("NO ANSWER FROM %s" % _join_target)


func _on_join_rejected(reason: String) -> void:
	print("net: join rejected (%s)" % reason)
	_leave_session()
	_show_home(MenuUi.Screen.JOIN)
	_notice("REFUSED: %s" % reason.to_upper())


func _on_disconnected() -> void:
	print("net: disconnected from host")
	var was_joining: bool = not _in_match and _menu.screen == MenuUi.Screen.JOIN
	_leave_session()
	_show_home(MenuUi.Screen.JOIN if was_joining else MenuUi.Screen.MAIN)
	if _menu.status == "":
		_notice("LOST THE HOST")


func _on_host_found(address: String, info: Dictionary) -> void:
	for i in _menu.hosts.size():
		if _menu.hosts[i]["address"] == address:
			_menu.hosts.remove_at(i)
			break
	_menu.hosts.append({"address": address, "port": int(info.get("port", PORT)), "name": str(info.get("name", "")),
		"players": int(info.get("players", 0)), "state": str(info.get("state", "lobby"))})


func _on_host_lost(address: String) -> void:
	for i in _menu.hosts.size():
		if _menu.hosts[i]["address"] == address:
			_menu.hosts.remove_at(i)
			return


func _leave_session() -> void:
	if _session != null:
		_session.call("leave")
	_set_paused(false)


func _leave_to_menu() -> void:
	_leave_session()
	_menu.status = ""
	_show_home(MenuUi.Screen.MAIN)


## Menu screens without a session: the attract battle behind them; the join screen listens for hosts.
func _show_home(scr: MenuUi.Screen) -> void:
	_home = scr
	_in_match = false
	_menu.busy = ""
	if _lan != null:
		_lan.call("stop")
	_menu.hosts.clear()
	if scr == MenuUi.Screen.JOIN:
		_menu.scanning = _ensure_lan() and _lan.call("start_listening") == OK
	_show_demo()
	_menu.screen = scr


func _show_demo() -> void:
	if _demo == null or _demo.phase == SimWorld.PHASE_GAME_OVER or _demo.tick > DEMO_TICKS:
		_demo = Scenarios.attract(randi())
	_view.attract = true
	_view.ui_visible = false
	if _view.world != _demo:
		_view.set_world(_demo, 0)


func _set_paused(on: bool) -> void:
	_paused = on
	if _session != null:
		# Solo only: stop stepping the sim (NetSession steps in _physics_process); LAN games run on.
		_session.set_physics_process(not (on and _solo))
	if on:
		_menu.pause_solo = _solo
		_menu.screen = MenuUi.Screen.PAUSE
	elif _menu.screen == MenuUi.Screen.PAUSE:
		_menu.screen = MenuUi.Screen.NONE


# ---------------------------------------------------------------- per frame

func _physics_process(_delta: float) -> void:
	if _demo != null and _view.world == _demo:
		Scenarios.step("menu", _demo)
		if _demo.phase == SimWorld.PHASE_GAME_OVER or _demo.tick > DEMO_TICKS:
			_demo = null
			_show_demo()


func _process(_delta: float) -> void:
	if _session == null or not _session_active():
		if _in_match:
			_show_home(MenuUi.Screen.MAIN)
		return
	var host: bool = _session.call("is_host")
	if bool(_session.call("in_match")):
		var w: SimWorld = _session.get("world")
		var peer: int = _session.call("local_peer_id")
		if not _in_match:
			_enter_match(host)
		if w != _view.world or peer != _view.local_peer:
			_view.set_world(w, peer)
		if _paused and w != null and w.phase == SimWorld.PHASE_GAME_OVER:
			_set_paused(false)
		return
	# lobby (or still connecting)
	_in_match = false
	_show_demo()
	var players: Array[Dictionary] = _session.get("lobby_players")
	var me: Dictionary = _session.call("local_player")
	if me.is_empty():
		_menu.screen = MenuUi.Screen.JOIN
		_menu.busy = "CONNECTING TO %s" % _join_target
		return
	if _lan != null and not host and bool(_lan.call("is_active")):
		_lan.call("stop")
	_menu.busy = ""
	_menu.lobby_players = players
	_menu.local_peer = _session.call("local_peer_id")
	_menu.is_host = host
	_menu.lobby_info = ("HOSTING ON PORT %d - FRIENDS FIND YOU UNDER JOIN LAN GAME" % PORT) if host \
		else "CONNECTED TO %s" % _join_target
	if _menu.screen != MenuUi.Screen.LOBBY:
		_menu.status = ""
	_menu.screen = MenuUi.Screen.LOBBY


func _enter_match(host: bool) -> void:
	_in_match = true
	_paused = false
	_menu.screen = MenuUi.Screen.NONE
	_view.attract = false
	_view.ui_visible = true
	_view.workshop.send_command = func(cmd: Dictionary) -> void:
		_session.call("send_command", cmd)
		if _audio != null:
			_audio.on_command(cmd)
	if host:
		_view.game_over.restart = func() -> void: _session.call("rematch")
		_view.game_over.restart_label = "RESTART" if _solo else "REMATCH"
	else:
		_view.game_over.restart = Callable()
	_view.game_over.quit = _leave_to_menu
	_view.game_over.quit_label = "LEAVE TO MENU"


func _unhandled_input(event: InputEvent) -> void:
	if not _in_match or _session == null or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var w: SimWorld = _session.get("world")
	if w == null:
		return
	var key: Key = (event as InputEventKey).keycode
	if key == KEY_ESCAPE and w.phase != SimWorld.PHASE_GAME_OVER:
		_set_paused(true)
		get_viewport().set_input_as_handled()
		return
	if w.phase != SimWorld.PHASE_COMBAT:
		return
	if DRIVE_KEYS.has(key):
		_session.call("send_command", {"type": "set_drive", "value": DRIVE_KEYS[key]})
	elif TARGET_KEYS.has(key):
		_session.call("send_command", {"type": "set_target", "value": TARGET_KEYS[key]})
	elif RADIO_KEYS.has(key):
		_view.hud().radio(RADIO_KEYS[key])
	elif ABILITY_KEYS.has(key):
		var me: SimVehicle = w.get_vehicle_for_peer(int(_session.call("local_peer_id")))
		if me != null and me.abilities[ABILITY_KEYS[key]] != "":
			_session.call("send_command", {"type": "use_ability", "value": me.abilities[ABILITY_KEYS[key]]})


# ---------------------------------------------------------------- profile

func _load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) != OK:
		return
	_menu.profile_name = SimVehicle.sanitize_name(str(cfg.get_value("profile", "name", SimVehicle.DEFAULT_NAME)))
	var c: Variant = cfg.get_value("profile", "color_index", 0)
	_menu.profile_color = clampi(int(c) if typeof(c) in [TYPE_INT, TYPE_FLOAT] else 0, 0, SimVehicle.COLOR_COUNT - 1)


func _save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)  # keep the other sections ([ui] from render/minimap.gd)
	cfg.set_value("profile", "name", _menu.profile_name)
	cfg.set_value("profile", "color_index", _menu.profile_color)
	var err: Error = cfg.save(PROFILE_PATH)
	if err != OK:
		push_warning("main: cannot save %s (%s)" % [PROFILE_PATH, error_string(err)])


# ---------------------------------------------------------------- display

## Fullscreen by default (the [display] fullscreen pref, --windowed forces a window) and a scale that
## fills the window: whole-pixel scaling only while it fills nearly all of it, else fractional (a
## maximised window on a 1080p desktop is ~1920x1010: whole pixels would leave the game at 2x).
func _setup_display(windowed: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)
	var full: bool = bool(cfg.get_value("display", "fullscreen", true)) and not windowed
	get_window().size_changed.connect(_fit_scale)
	_set_fullscreen(full, false)
	_fit_scale()


func _set_fullscreen(on: bool, save: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
	if save:
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_PATH)
		cfg.set_value("display", "fullscreen", on)
		cfg.save(PROFILE_PATH)


func _fit_scale() -> void:
	var win: Window = get_window()
	var base := Vector2(win.content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0:
		return
	var s: float = minf(float(win.size.x) / base.x, float(win.size.y) / base.y)
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER if s >= 1.0 and floorf(s) / s >= FIT_INTEGER_MIN \
		else Window.CONTENT_SCALE_STRETCH_FRACTIONAL


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode == KEY_F11 or (k.keycode == KEY_ENTER and k.alt_pressed):
		var win: Window = get_window()
		_set_fullscreen(win.mode != Window.MODE_FULLSCREEN and win.mode != Window.MODE_EXCLUSIVE_FULLSCREEN, true)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- screenshot mode

static func _parse_point(spec: String, fallback: Vector2) -> Vector2:
	var parts: PackedStringArray = spec.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return fallback
	return Vector2(int(parts[0]), int(parts[1]))


## UI scenarios: put the menu / game over in the state Scenarios.ui_state() describes.
func _apply_ui_state(ui: Dictionary, world: SimWorld) -> int:
	var peer: int = int(ui.get("local_peer", 1))
	var screens: Dictionary = {"main": MenuUi.Screen.MAIN, "join": MenuUi.Screen.JOIN, "lobby": MenuUi.Screen.LOBBY,
		"pause": MenuUi.Screen.PAUSE}
	if ui.has("profile"):
		_menu.profile_name = ui["profile"][0]
		_menu.profile_color = ui["profile"][1]
	for h: Dictionary in ui.get("hosts", []):
		_menu.hosts.append(h)
	var players: Array[Dictionary] = []
	for e: Dictionary in ui.get("players", []):
		players.append(e)
	_menu.lobby_players = players
	_menu.local_peer = peer
	_menu.is_host = bool(ui.get("is_host", false))
	_menu.lobby_info = str(ui.get("info", ""))
	_menu.ip_text = str(ui.get("ip", ""))
	_menu.pause_solo = bool(ui.get("solo", true))
	var scr: String = str(ui.get("screen", ""))
	if scr == "main" or scr == "join" or scr == "lobby":
		_view.attract = true
		_view.ui_visible = false
		peer = 0
	if screens.has(scr):
		_menu.screen = screens[scr]
	match str(ui.get("game_over", "")):
		"host":
			_view.game_over.restart = func() -> void: pass
			_view.game_over.restart_label = "REMATCH"
		"client":
			_view.game_over.restart = Callable()
	_view.game_over.quit = func() -> void: pass
	return peer


func _run_shot(args: Dictionary) -> void:
	var out_path: String = args["shot"]
	var scenario: String = args.get("scenario", "skirmish")
	if scenario == "replay":  # playtest harness: several frames of one session replay
		await _run_replay_shots(args)
		return
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
	var ui: Dictionary = Scenarios.ui_state(scenario)
	var peer: int = 1
	if world.vehicles.size() < 2:
		_view.game_over.restart = func() -> void: pass  # show the solo screen as played
		_view.game_over.restart_label = "RESTART"
	if not ui.is_empty():
		peer = _apply_ui_state(ui, world)
	_view.set_world(world, peer)
	_view.prime(history)
	_view.workshop.send_command = func(cmd: Dictionary) -> void: world.apply_command(1, cmd)
	_view.workshop.use_real_pointer = false
	_menu.use_real_pointer = false
	var hover: Vector2 = _parse_point(args.get("hover", ""), Vector2(-1, -1))
	_view.workshop.pointer_override = hover
	_view.rules.use_real_pointer = false
	_view.rules.pointer_override = hover
	_menu.pointer_override = hover
	_view.hud().pointer_override = hover
	if ui.has("picker"):
		_view.hud().picker_open = true
	if ui.has("rules"):
		_view.rules.open(str(ui["rules"]))
	if ui.has("workshop_tab"):
		_view.workshop.activate("tab", str(ui["workshop_tab"]))
	for wa: Array in ui.get("workshop_actions", []):  # e.g. ["idea", "fortress"], ["goal", id], ["tech", id]
		_view.workshop.activate(str(wa[0]), wa[1])
	for i in 4:
		await get_tree().process_frame
	if args.has("click"):
		for spec: String in str(args["click"]).split(";", false):
			var p: Vector2 = _parse_point(spec, Vector2(-1, -1))
			var ok: bool = false
			if _menu.visible:
				ok = _menu.click_at(p)
			elif _view.workshop.visible:
				ok = _view.workshop.click_at(p)  # forwards to the embedded rule editor in the RULES view
			elif _view.rules.is_open:
				ok = _view.rules.click_at(p)
			else:
				ok = _view.hud().click_at(p)
			print("SHOT_CLICK %s -> %s" % [spec, "hit" if ok else "miss"])
			await get_tree().process_frame
			await get_tree().process_frame
	# two drawn frames: the first bakes the decal viewport, the second shows it
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not _save_capture(out_path):
		get_tree().quit(1)
		return
	print("SHOT_OK %s %s (tick %d, %d enemies, %d projectiles)" % [_abs_png(out_path), _abs_png(out_path).get_basename() + "_1080p.png", world.tick, world.enemy_count, world.proj_count])
	get_tree().quit(0)


func _abs_png(out_path: String) -> String:
	return out_path if out_path.is_absolute_path() else OS.get_environment("PWD").path_join(out_path)


## Saves the drawn window as <out>_1080p.png (1920x1080: the world scaled up 3x by whole pixels,
## the UI drawn at full resolution) and <out_path> (640x360, filtered down for quick previews).
func _save_capture(out_path: String) -> bool:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("main: viewport capture failed")
		return false
	var full := Vector2i(1920, 1080)
	if img.get_size() != full:
		img.resize(full.x, full.y, Image.INTERPOLATE_NEAREST if img.get_size().x < full.x else Image.INTERPOLATE_LANCZOS)
	var abs_path: String = _abs_png(out_path)
	var big_path: String = abs_path.get_basename() + "_1080p.png"
	var err: Error = img.save_png(big_path)
	var small: Image = img.duplicate()
	small.resize(640, 360, Image.INTERPOLATE_LANCZOS)
	if err == OK:
		err = small.save_png(abs_path)
	if err != OK:
		push_error("main: cannot save %s (%s)" % [abs_path, error_string(err)])
		return false
	return true


## Playtest harness (scripts/playtest.sh): `--scenario=replay --session=<dir> --frames=<frames.json>`
## replays the session (Scenarios.replay_*, the same code tools/playtest.gd used for the summary) once
## and saves a screenshot at every frame tick listed with "render": true (ascending order is not needed).
func _run_replay_shots(args: Dictionary) -> void:
	var dir: String = str(args.get("session", ""))
	var session: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("session.json")))
	var plan: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(args.get("frames", ""))))
	if not (session is Dictionary) or not (plan is Dictionary):
		push_error("main: bad --session / --frames")
		get_tree().quit(1)
		return
	var todo: Array = []
	for f: Dictionary in (plan as Dictionary).get("frames", []):
		if bool(f.get("render", true)):
			todo.append(f)
	todo.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tick"]) < int(b["tick"]))
	var run: Dictionary = Scenarios.replay_new(session)
	var w: SimWorld = run["w"]
	var history: Array = []
	var last_phase: int = w.phase
	for f: Dictionary in todo:
		var want: int = int(f["tick"])
		while w.tick < want and not Scenarios.replay_done(run):
			Scenarios.replay_advance(run)
			if w.phase == SimWorld.PHASE_COMBAT and last_phase != SimWorld.PHASE_COMBAT:
				history.clear()  # a new combat: only its scars are on the ground
			last_phase = w.phase
			if w.phase != SimWorld.PHASE_WORKSHOP:
				history.append(WorldView.record_tick(w))
				var old: int = history.size() - 1 - WorldView.SHOT_EFFECT_TICKS - 2
				if old >= 0:  # long-gone shots leave nothing to draw: drop their events
					history[old]["events"] = (history[old]["events"] as Array).filter(
						func(e: Dictionary) -> bool: return e["type"] != "fire" and e["type"] != "hit")
		if w.tick != want:
			push_error("main: replay is at tick %d, frame wants %d" % [w.tick, want])
			get_tree().quit(1)
			return
		if not await _replay_frame(w, history, f):
			get_tree().quit(1)
			return
		print("SHOT_OK %s (%s, tick %d, %d enemies)" % [f["png"], f["name"], w.tick, w.enemy_count])
	get_tree().quit(0)


func _replay_frame(w: SimWorld, history: Array, f: Dictionary) -> bool:
	_view.frozen = true
	_view.attract = false
	_view.ui_visible = true
	_menu.screen = MenuUi.Screen.NONE
	if w.vehicles.size() < 2:
		_view.game_over.restart = func() -> void: pass  # the solo screen as played
		_view.game_over.restart_label = "RESTART"
	elif bool(f.get("game_over", false)):
		_apply_ui_state(Scenarios.ui_state("rematch"), w)  # a multiplayer host's game over screen
	_view.game_over.quit = func() -> void: pass
	_view.set_world(w, 1)
	_view.prime(history)
	_view.workshop.send_command = func(_cmd: Dictionary) -> void: pass
	_view.workshop.use_real_pointer = false
	_menu.use_real_pointer = false
	_view.workshop.pointer_override = Vector2(-1, -1)
	_view.hud().pointer_override = Vector2(-1, -1)
	_menu.pointer_override = Vector2(-1, -1)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _save_capture(str(f["png"]))
