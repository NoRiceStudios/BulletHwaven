class_name AudioDirector
extends Node
## Music and sound effects (docs/architecture.md, "Audio"). Presentation only: it reads the world the
## WorldView shows and its events once per sim tick, exactly like render/, and never touches the sim.
## All audio is procedural (tools/audiogen), so there is nothing to license.
##
## Add it as a child of the WorldView: positional effects are AudioStreamPlayer2D nodes in the world's
## SubViewport, whose camera is the listener (main.gd turns the viewport's 2D listener on).
## Volumes (master / music / sfx, 0..1) and mute live in the [audio] section of user://profile.cfg.

const PROFILE_PATH := "user://profile.cfg"
const BUSES: PackedStringArray = ["Music", "SFX"]
const LEVEL_KEYS: PackedStringArray = ["master", "music", "sfx"]
const DEFAULT_LEVELS := {"master": 0.8, "music": 0.7, "sfx": 0.8}
const LEVEL_STEPS := 10  ## the UI moves levels in tenths

const MUSIC_DIR := "res://assets/audio/music/"
const SFX_DIR := "res://assets/audio/sfx/"
const TRACKS: PackedStringArray = ["menu", "workshop", "combat", "boss"]
const MUSIC_FADE := 1.4  ## s crossfade between tracks
const MUSIC_DUCK_DB := -9.0  ## while a win / lose sting plays

const VOICES := 40  ## positional voices (oldest is stolen)
const FLAT_VOICES := 10  ## non-positional voices (UI, alarms, stings)
const HEAR_RANGE := 760.0  ## px from the camera; farther events are skipped
const PITCH_JITTER := 0.06

## Sound name -> [volume dB, min interval s between two starts, max starts per tick].
## The interval keeps a 40-gun horde from turning into white noise; the focus rig's guns get their own lane.
const SOUNDS := {
	"mg": [-9.0, 0.05, 2], "shotgun": [-6.0, 0.08, 2], "cannon": [-4.0, 0.1, 2], "flamer": [-10.0, 0.14, 1],
	"ram": [-3.0, 0.12, 1],
	"hit": [-14.0, 0.035, 2], "hit_heavy": [-8.0, 0.06, 1], "acid_hit": [-7.0, 0.1, 1],
	"kill_mite": [-8.0, 0.04, 3], "kill_spitter": [-6.0, 0.06, 2], "kill_boulder": [-4.0, 0.08, 2],
	"kill_glass": [-5.0, 0.06, 2], "kill_big": [-3.0, 0.08, 2],
	"spit": [-9.0, 0.08, 2], "brood": [-5.0, 0.15, 1], "shriek": [-6.0, 0.4, 1],
	"explosion": [0.0, 0.12, 2], "explosion_small": [-3.0, 0.1, 2], "shock": [-2.0, 0.2, 1],
	"emp": [-4.0, 0.2, 1], "zap": [-6.0, 0.06, 2], "nitro": [-6.0, 0.3, 1], "boom": [-3.0, 0.25, 1],
	"jam": [-6.0, 0.2, 1], "steam": [-9.0, 0.25, 1], "saw": [-8.0, 0.12, 1], "sparks": [-6.0, 0.1, 1],
	"shrapnel": [-6.0, 0.08, 1], "execute": [-2.0, 0.1, 1], "cash": [-4.0, 0.3, 1], "dodge": [-6.0, 0.15, 1],
	"shed": [-5.0, 0.15, 1], "respawn": [-4.0, 0.5, 1], "drain": [-4.0, 0.5, 1],
	"surge": [-3.0, 2.0, 1], "klaxon": [-3.0, 3.0, 1], "bounty": [-4.0, 2.0, 1],
	"boss_warn": [0.0, 4.0, 1], "boss_roar": [-1.0, 1.5, 1], "boss_kill": [0.0, 3.0, 1], "boss_charge": [-3.0, 1.0, 1],
	"ui_click": [-8.0, 0.03, 1], "ui_pick": [-4.0, 0.08, 1], "ui_reroll": [-4.0, 0.08, 1], "ui_buy": [-4.0, 0.08, 1],
	"ui_deny": [-6.0, 0.15, 1], "ui_ready": [-4.0, 0.3, 1], "round_start": [-3.0, 1.0, 1], "round_end": [-4.0, 1.0, 1],
	"win": [-1.0, 3.0, 1], "lose": [-1.0, 3.0, 1],
}
## Sounds that are not placed in the world (alarms for everybody, the HUD's own voice).
const FLAT: PackedStringArray = ["surge", "klaxon", "bounty", "boss_warn", "ui_click", "ui_pick", "ui_reroll", "ui_buy",
	"ui_deny", "ui_ready", "round_start", "round_end", "win", "lose", "respawn"]
const WEAPON_SOUNDS: PackedStringArray = ["mg", "shotgun", "cannon", "flamer"]  ## by fire event kind (Cards.WEAPON_KINDS)
## Workshop command type -> UI sound.
const COMMAND_SOUNDS := {"pick_card": "ui_pick", "reroll": "ui_reroll", "buy_tech": "ui_buy", "respec_tech": "ui_reroll",
	"ready": "ui_ready", "scrap_card": "ui_click", "reserve_card": "ui_click", "accept_contract": "ui_buy"}

var levels: Dictionary = DEFAULT_LEVELS.duplicate()
var muted: bool = false
var view: WorldView = null  ## the world to listen to (set by main.gd)

var _streams: Dictionary = {}  ## name -> AudioStream
var _voices: Array[AudioStreamPlayer2D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _next_flat: int = 0
var _last_start: Dictionary = {}  ## name (or "focus:" + name) -> time of the last start (s)
var _tick_count: Dictionary = {}  ## name -> starts this tick
var _music: Array[AudioStreamPlayer] = []  ## two players for crossfades
var _music_on: int = 0
var _track: String = ""
var _duck_until: float = 0.0
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()
var _last_tick: int = -1
var _last_world: SimWorld = null
var _last_phase: int = -1


func _ready() -> void:
	_rng.randomize()
	ensure_buses()
	for n: String in SOUNDS:
		var s: AudioStream = load(SFX_DIR + n + ".wav")
		if s != null:
			_streams[n] = s
	for i in VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = HEAR_RANGE * 1.6
		p.attenuation = 1.4
		p.panning_strength = 0.8
		add_child(p)
		_voices.append(p)
	for i in FLAT_VOICES:
		var f := AudioStreamPlayer.new()
		f.bus = "SFX"
		add_child(f)
		_flat.append(f)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	load_settings()


## Creates the Music and SFX buses (sending to Master) if the project has none.
static func ensure_buses() -> void:
	for b: String in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


# ---------------------------------------------------------------- settings

static func clamp_level(v: Variant) -> float:
	var f: float = float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 1.0
	return snappedf(clampf(f, 0.0, 1.0), 1.0 / LEVEL_STEPS)


## Linear level 0..1 -> bus dB (0 is silence).
static func level_db(level: float) -> float:
	return -80.0 if level <= 0.001 else linear_to_db(level * level)  # squared: a perceptually even slider


func set_level(key: String, value: float) -> void:
	if key in LEVEL_KEYS:
		levels[key] = clamp_level(value)
		apply_levels()
		save_settings()


func set_muted(on: bool) -> void:
	muted = on
	apply_levels()
	save_settings()


func apply_levels() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master, level_db(float(levels["master"])))
	AudioServer.set_bus_mute(master, muted)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), level_db(float(levels["music"])))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), level_db(float(levels["sfx"])))


func load_settings(path: String = PROFILE_PATH) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for k: String in LEVEL_KEYS:
			levels[k] = clamp_level(cfg.get_value("audio", k, DEFAULT_LEVELS[k]))
		muted = cfg.get_value("audio", "muted", false) == true
	apply_levels()


func save_settings(path: String = PROFILE_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)  # keep the other sections ([profile], [ui])
	for k: String in LEVEL_KEYS:
		cfg.set_value("audio", k, levels[k])
	cfg.set_value("audio", "muted", muted)
	if cfg.save(path) != OK:
		push_warning("audio: cannot save %s" % path)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_time += delta
	var w: SimWorld = view.world if view != null else null
	_update_music(w, delta)
	if w == null:
		return
	if w != _last_world:  # a new match (or the menu's demo): no stings for the jump
		_last_world = w
		_last_phase = w.phase
		_last_tick = w.tick
		return
	if w.tick == _last_tick:
		return
	_last_tick = w.tick
	_tick_count.clear()
	if view.attract:  # the battle behind the menus stays silent
		_last_phase = w.phase
		return
	if w.phase != _last_phase:
		_on_phase(w, _last_phase)
		_last_phase = w.phase
	var focus: SimVehicle = view.focus_vehicle()
	var ear: Vector2 = view.display_pos(focus) if focus != null else _listener_pos()
	for e: Dictionary in w.events:
		var sound: String = sound_for(e, w)
		if sound == "" or (sound == "respawn" and (focus == null or int(e.get("owner", -1)) != focus.id)):
			continue
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var owner: int = int(e.get("owner", -1))
		var mine: bool = focus != null and owner == focus.id and str(e.get("type", "")) == "fire"
		if not mine and not FLAT.has(sound) and pos.distance_to(ear) > HEAR_RANGE:
			continue
		play(sound, pos, mine)


func _listener_pos() -> Vector2:
	var cam: Camera2D = view.get_viewport().get_camera_2d() if view != null else null
	return cam.get_screen_center_position() if cam != null else SimWorld.ARENA.get_center()


func _on_phase(w: SimWorld, from: int) -> void:
	match w.phase:
		SimWorld.PHASE_COMBAT:
			play("round_start")
		SimWorld.PHASE_WORKSHOP:
			if from == SimWorld.PHASE_COMBAT:
				play("round_end")
		SimWorld.PHASE_GAME_OVER:
			var won: bool = w.winner_peer >= 0 and w.winner_peer == view.local_peer
			play("win" if won else "lose")
			_duck_until = _time + 3.0


## Which sound an event makes ("" = none). Pure, so tests can check the mapping.
static func sound_for(e: Dictionary, w: SimWorld = null) -> String:
	var kind: int = int(e.get("kind", -1))
	match str(e.get("type", "")):
		"fire":
			return WEAPON_SOUNDS[kind] if kind >= 0 and kind < WEAPON_SOUNDS.size() else "mg"
		"hit":
			if int(e.get("owner", -1)) < 0:
				return "acid_hit"
			return "hit" if kind >= 0 else "hit_heavy"  # kind -1: a rival's rig was hit
		"kill":
			match kind:
				SimWorld.MITE:
					return "kill_mite"
				SimWorld.BOULDER, SimWorld.BOSS_SHARD:
					return "kill_boulder"
				SimWorld.SPITTER:
					return "kill_spitter"
				SimWorld.GLASS:
					return "kill_glass"
				SimWorld.BROOD, SimWorld.SHRIEKER:
					return "kill_big"
			return ""  # bosses have boss_kill, rigs vehicle_destroyed
		"vehicle_destroyed":
			return "explosion"
		"jerry_blast", "salvo", "boss_shell":
			return "explosion_small"
		"spit":
			return "spit"
		"emp":
			return "emp"
		"chain":
			return "zap"
		"nitro":
			return "nitro"
		"boom":
			return "boom"
		"shockwave", "boss_blast", "boss_ring":
			return "shock"
		"sparks":
			return "ram"
		"jam":
			return "jam"
		"overheat", "smoke":
			return "steam"
		"saw":
			return "saw"
		"shrapnel":
			return "shrapnel"
		"execute":
			return "execute"
		"contract_done":
			return "cash"
		"dodge":
			return "dodge"
		"shed":
			return "shed"
		"drain":
			return "drain"
		"respawn":
			return "respawn"
		"surge":
			return "surge"
		"pvp_on":
			return "klaxon"
		"bounty":
			return "bounty"
		"boss":
			return "boss_warn"
		"boss_spawn", "boss_phase", "boss_retreat":
			return "boss_roar"
		"boss_kill":
			return "boss_kill"
		"boss_charge":
			return "boss_charge"
		"boss_split":
			return "kill_glass"
		"boss_brood", "brood":
			return "brood"
		"shriek":
			return "shriek"
	return ""


## Plays a sound now: at `pos` in the world, or flat (FLAT sounds, or pos = null). `focus`: the
## followed rig's own gun, which is louder and throttled in its own lane. Returns false when throttled.
func play(sound: String, pos: Variant = null, focus: bool = false) -> bool:
	if not _streams.has(sound) or not admit(sound, focus):
		return false
	var spec: Array = SOUNDS[sound]
	var pitch: float = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	var db: float = float(spec[0])
	if pos == null or focus or FLAT.has(sound):
		var f: AudioStreamPlayer = _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
		f.stream = _streams[sound]
		f.volume_db = db - (2.0 if focus else 0.0)
		f.pitch_scale = pitch if not FLAT.has(sound) else 1.0
		f.play()
		return true
	var p: AudioStreamPlayer2D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	p.stream = _streams[sound]
	p.position = pos
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	return true


## Throttle: true (and counted) if `sound` may start now. The focus rig's guns have their own lane.
func admit(sound: String, focus: bool = false) -> bool:
	if not SOUNDS.has(sound):
		return false
	var spec: Array = SOUNDS[sound]
	var lane: String = ("focus:" + sound) if focus else sound
	if _time - float(_last_start.get(lane, -99.0)) < float(spec[1]):
		return false
	if int(_tick_count.get(lane, 0)) >= int(spec[2]):
		return false
	_last_start[lane] = _time
	_tick_count[lane] = int(_tick_count.get(lane, 0)) + 1
	return true


## The workshop's own commands get a UI sound (main.gd wraps WorkshopUi.send_command).
func on_command(cmd: Dictionary) -> void:
	if view == null or not view.attract:
		play(str(COMMAND_SOUNDS.get(str(cmd.get("type", "")), "ui_click")))


# ---------------------------------------------------------------- music

## Which track fits the world now ("" = silence).
static func track_for(w: SimWorld, attract: bool) -> String:
	if w == null or attract:
		return "menu"
	match w.phase:
		SimWorld.PHASE_COMBAT:
			return "boss" if w.boss_state == Bosses.ST_ACTIVE else "combat"
		SimWorld.PHASE_WORKSHOP:
			return "workshop"
	return "menu"


func _update_music(w: SimWorld, delta: float) -> void:
	var want: String = track_for(w, view == null or view.attract)
	if want != _track:
		_track = want
		_music_on = 1 - _music_on
		var m: AudioStreamPlayer = _music[_music_on]
		var s: AudioStream = load(MUSIC_DIR + want + ".ogg") if want != "" else null
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		m.stream = s
		m.volume_db = -40.0
		if s != null:
			m.play()
	var step: float = delta * 60.0 / MUSIC_FADE
	var target: float = MUSIC_DUCK_DB if _time < _duck_until else 0.0
	for i in 2:
		var m: AudioStreamPlayer = _music[i]
		if i == _music_on:
			m.volume_db = move_toward(m.volume_db, target, step)
		else:
			m.volume_db = move_toward(m.volume_db, -60.0, step)
			if m.playing and m.volume_db <= -59.0:
				m.stop()


func current_track() -> String:
	return _track
