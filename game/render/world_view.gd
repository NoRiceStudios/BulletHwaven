class_name WorldView
extends Node2D
## Renders a SimWorld every frame without mutating it (docs/architecture.md, "render/").
## Display positions are extrapolated by velocity since the last sim tick and then eased toward
## that target, so 30 Hz host ticks and 15 Hz client snapshots both look smooth at 60 fps.
## Events are consumed once per sim tick (when world.tick changes), never once per frame.

const SMOOTH_RATE := 22.0  ## 1/s, easing toward the extrapolated sim position
const SNAP_DIST := 48.0  ## px, farther jumps (respawn, snapshot correction) snap instead of easing
const MAX_LEAD := 0.1  ## s, never extrapolate further than this past the last tick
const TRAIL_STEP := 3.0  ## px of travel between tyre-track stamps
const SHOT_EFFECT_TICKS := 10  ## screenshot mode: transient effects from the last N ticks
const WORKSHOP_CAM_LIFT := 88.0  ## px: in the workshop the camped rig sits between the top bar and the cards
const SPECTATE_CAM_LIFT := 84.0  ## the same for the watched rig in the spectator workshop (above the standings)
const CAM_EASE := 4.0  ## 1/s, easing of that lift

var world: SimWorld = null
var local_peer: int = 1
## Menu backdrop: with no local rig the camera drifts slowly over the arena (driven by world.tick,
## so screenshots are deterministic) instead of staying put.
var attract: bool = false
## HUD, workshop and game over overlays (hidden behind the menus).
var ui_visible: bool = true:
	set(value):
		ui_visible = value
		if _hud_layer != null:
			_hud_layer.visible = value
## Screenshot mode: no extrapolation, easing or effect ageing; the frame shows the sim state as is.
var frozen: bool = false:
	set(value):
		frozen = value
		if _effects != null:
			_effects.frozen = value

var _ground: Sprite2D
var _decals: DecalLayer
var _effects: EffectsLayer
var _enemy_layers: Array[SheetLayer] = []
var _tracers: SheetLayer
var _acid: SheetLayer
var _halos: Node2D
var _labels: Node2D
var _camera: Camera2D
var _hud: Hud
var minimap: Minimap
var _hud_layer: CanvasLayer
var workshop: WorkshopUi
var game_over: GameOverUi
var rules: DoctrineEditor  ## the rule editor (P), on top of the workshop
var _cam_lift: float = 0.0
var _shake: float = 0.0  ## 0..1, screen shake from rigs blowing up (decays; never in screenshot mode)
var _shake_t: float = 0.0
var _ring: Node2D
## world.tick at which PvP last switched on (-1 = not seen): the HUD's "PVP ON" banner.
var pvp_on_tick: int = -1
var _pvp_prev: bool = false
## Match log for the information UI (kill feed, workshop recap), filled from world events once per
## sim tick (and by prime() in screenshot mode), so it works the same on host and clients:
## kill_log: player kills {tick, round, killer, victim, weapon}; wreck_log: rigs destroyed
## {tick, round, id, cause, killer}; drain_log: fuel drained at a workshop {tick, round, id, amount}.
var kill_log: Array[Dictionary] = []
var wreck_log: Array[Dictionary] = []
var drain_log: Array[Dictionary] = []
const LOG_CAP := 96
## Spectator mode (local rig eliminated): vehicle id picked with Tab / arrows (-1 = auto: the
## nearest fight, else the leader). The auto choice is re-evaluated every SPECTATE_RECHECK ticks.
var spectate_id: int = -1
const SPECTATE_RECHECK := 90
const ELIM_HOLD_TICKS := 90  ## after the local rig is eliminated: 3 s on the wreck before spectating
const FIGHT_DIST := 300.0
var _auto_id: int = -1
var _auto_tick: int = -100000

var _vehicle_nodes: Dictionary = {}  # vehicle id -> RigView
var _veh_disp: Dictionary = {}  # vehicle id -> Vector3(x, y, heading)
var _veh_trail: Dictionary = {}  # vehicle id -> [position, wheel positions...] at the last track stamp
var _veh_steps: Dictionary = {}  # vehicle id -> int, track stamps so far (dust cadence)
var _enemy_disp: Dictionary = {}  # enemy id -> Vector3(x, y, frame)
var _acid_pos: PackedVector2Array = PackedVector2Array()
var _burn_pos: PackedVector2Array = PackedVector2Array()  ## burning enemies this frame (warm flickering halo)
var _stun_pos: PackedVector2Array = PackedVector2Array()  ## EMP-stunned enemies this frame
var _warn_pos: PackedVector2Array = PackedVector2Array()  ## spitters about to spit (radar array of the watched rig)
var _rings: Array = []  ## expanding rings from events: [pos, radius px, born tick, life ticks, colour]
var _decoys: Dictionary = {}  ## vehicle id -> RigView, the faint phantom decoy copy
var _last_tick: int = -1
var _tick_age: float = 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground = Sprite2D.new()
	_ground.texture = Gfx.TEX_GROUND
	_ground.centered = false
	_ground.position = SimWorld.ARENA.position
	_ground.z_index = Gfx.Z_GROUND
	add_child(_ground)

	_decals = DecalLayer.new()
	_decals.z_index = Gfx.Z_DECALS
	add_child(_decals)

	_ring = Node2D.new()
	_ring.z_index = Gfx.Z_RING
	_ring.draw.connect(_draw_ring)
	add_child(_ring)

	var kinds: Array = [  # [texture, glow, rows, shadow offset, shadow alpha] per SimWorld enemy kind
		[Gfx.TEX_MITE, Gfx.TEX_MITE_GLOW, 2, Vector2(1, 2), 0.45],
		# boulders cast a longer, darker shadow so a pile reads as separate rocks (#12)
		[Gfx.TEX_BOULDER, Gfx.TEX_BOULDER_GLOW, 2, Vector2(4, 6), 0.62],
		[Gfx.TEX_SPITTER, Gfx.TEX_SPITTER_GLOW, 1, Vector2(2, 3), 0.45],
	]
	for k in kinds:
		var layer := SheetLayer.new()
		add_child(layer)
		layer.setup(k[0], Gfx.ENEMY_DIRS, k[2], Gfx.Z_ENEMIES, k[1], k[3], 1.0, k[4])
		_enemy_layers.append(layer)

	_tracers = SheetLayer.new()
	add_child(_tracers)
	_tracers.setup(Gfx.TEX_TRACER, Gfx.FX_DIRS, 1, Gfx.Z_PROJECTILES, Gfx.TEX_TRACER_GLOW)
	_acid = SheetLayer.new()
	add_child(_acid)
	_acid.setup(Gfx.TEX_ACID, Gfx.FX_DIRS, 1, Gfx.Z_PROJECTILES, Gfx.TEX_ACID_GLOW)

	_halos = Node2D.new()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halos.material = add_mat
	_halos.z_index = Gfx.Z_GLOW
	_halos.draw.connect(_draw_halos)
	add_child(_halos)

	_effects = EffectsLayer.new()
	_effects.frozen = frozen
	add_child(_effects)

	_labels = Node2D.new()
	_labels.z_index = Gfx.Z_LABELS
	_labels.draw.connect(_draw_labels)
	add_child(_labels)

	_camera = Camera2D.new()
	_camera.limit_left = int(SimWorld.ARENA.position.x)
	_camera.limit_top = int(SimWorld.ARENA.position.y)
	_camera.limit_right = int(SimWorld.ARENA.end.x)
	_camera.limit_bottom = int(SimWorld.ARENA.end.y)
	_camera.position = SimWorld.ARENA.get_center()
	add_child(_camera)
	_camera.make_current()

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.visible = ui_visible
	_hud_layer = hud_layer
	# The world renders into a 640x360 SubViewport (pixel exact, scaled up by whole pixels); the
	# HUD and overlays live on the full-resolution root canvas so their text stays crisp.
	if owner != null and owner.get_viewport() != get_viewport():
		owner.add_child.call_deferred(hud_layer)
	else:
		add_child(hud_layer)
	_hud = Hud.new()
	_hud.view = self
	hud_layer.add_child(_hud)
	minimap = Minimap.new()
	minimap.view = self
	hud_layer.add_child(minimap)
	workshop = WorkshopUi.new()
	workshop.view = self
	hud_layer.add_child(workshop)
	game_over = GameOverUi.new()
	game_over.view = self
	hud_layer.add_child(game_over)
	rules = DoctrineEditor.new()
	rules.send_command = func(cmd: Dictionary) -> void:
		if workshop.send_command.is_valid():
			workshop.send_command.call(cmd)
	hud_layer.add_child(rules)
	workshop.rules = rules
	rules.workshop = workshop


## Shows `w` from the point of view of `peer` (camera, HUD). Clears all marks of a previous world.
func set_world(w: SimWorld, peer: int) -> void:
	world = w
	local_peer = peer
	_last_tick = w.tick if w != null else -1
	_tick_age = 0.0
	_enemy_disp.clear()
	_veh_disp.clear()
	_veh_trail.clear()
	_veh_steps.clear()
	for id in _vehicle_nodes:
		(_vehicle_nodes[id] as Node).queue_free()
	_vehicle_nodes.clear()
	_decals.clear()
	_effects.clear()
	_shake = 0.0
	pvp_on_tick = -1
	kill_log.clear()
	wreck_log.clear()
	drain_log.clear()
	spectate_id = -1
	_auto_id = -1
	_auto_tick = -100000
	_pvp_prev = w != null and w.pvp_enabled()
	_hud.world = w
	_hud.local_peer = peer
	workshop.world = w
	workshop.local_peer = peer
	game_over.world = w
	game_over.local_peer = peer
	rules.world = w
	rules.local_peer = peer
	rules.close()


## Snapshot of one tick for prime(): events plus vehicle poses (for tyre tracks).
static func record_tick(w: SimWorld) -> Dictionary:
	var veh: Array = []
	for v in w.vehicles:
		veh.append([v.id, v.pos, v.heading, v.alive])
	return {"tick": w.tick, "round": w.round, "events": w.events.duplicate(), "vehicles": veh, "pvp": w.pvp_enabled()}


## Screenshot mode: replays recorded ticks so the frame shows the match's history (persistent goo,
## scorch and tracks from every tick, transient effects from the last few ticks at their age).
func prime(history: Array) -> void:
	if world == null or history.is_empty():
		return
	var last_tick: int = history[-1]["tick"]
	var was_pvp: bool = bool(history[0].get("pvp", false))
	for h: Dictionary in history:
		var pvp: bool = bool(h.get("pvp", false))
		if pvp and not was_pvp:
			pvp_on_tick = int(h["tick"])
		was_pvp = pvp
		var age: float = float(last_tick - int(h["tick"])) * SimWorld.DT
		for vd: Array in h["vehicles"]:
			if vd[3]:
				_trail(vd[0], vd[1], vd[2], age if age < EffectsLayer.LIFE[EffectsLayer.Kind.DUST] else -1.0)
		_consume_events(h["events"], age, last_tick - int(h["tick"]) < SHOT_EFFECT_TICKS, int(h["tick"]), int(h.get("round", world.round)))
	_last_tick = world.tick
	_veh_trail.clear()


func _process(delta: float) -> void:
	if world == null:
		return
	if world.tick != _last_tick:
		_consume_events(world.events, 0.0, true, world.tick, world.round)
		_last_tick = world.tick
		_tick_age = 0.0
		var pvp: bool = world.pvp_enabled()
		if pvp and not _pvp_prev:
			pvp_on_tick = world.tick
		_pvp_prev = pvp
	elif not frozen:
		_tick_age += delta
	var lead: float = 0.0 if frozen else minf(_tick_age, MAX_LEAD)
	var k: float = 1.0 if frozen else 1.0 - exp(-SMOOTH_RATE * delta)
	_update_vehicles(lead, k)
	_update_enemies(lead, k)
	_update_projectiles(lead)
	_update_camera(1.0 if frozen else 1.0 - exp(-CAM_EASE * delta))
	if not frozen:
		_shake = maxf(0.0, _shake - delta * 2.2)
		_shake_t += delta
	_halos.queue_redraw()
	_labels.queue_redraw()
	_ring.queue_redraw()


# ---------------------------------------------------------------- vehicles

func _vehicle_display(v: SimVehicle) -> Vector3:
	var d: Variant = _veh_disp.get(v.id)
	return d if d != null else Vector3(v.pos.x, v.pos.y, v.heading)


func _update_vehicles(lead: float, k: float) -> void:
	var seen: Dictionary = {}
	for v in world.vehicles:
		seen[v.id] = true
		var target: Vector2 = v.pos + (v.vel * lead if v.alive else Vector2.ZERO)
		var d: Vector3 = _vehicle_display(v)
		var p := Vector2(d.x, d.y)
		var head: float = d.z
		if p.distance_to(target) > SNAP_DIST or not _veh_disp.has(v.id):
			p = target
			head = v.heading
		else:
			p = p.lerp(target, k)
			head = lerp_angle(head, v.heading, k)
		_veh_disp[v.id] = Vector3(p.x, p.y, head)

		var rv: RigView = _vehicle_nodes.get(v.id)
		if rv == null:
			rv = RigView.new()
			add_child(rv)
			_vehicle_nodes[v.id] = rv
		rv.setup(v)
		rv.place(v, Gfx.snap(p), head, world.tick, frozen)
		rv.set_flash(_protect_flash(v))
		_update_decoy(v, head)
		if v.alive:
			_trail(v.id, p, head, -1.0 if frozen else 0.0)
	for id in _vehicle_nodes.keys():
		if not seen.has(id):
			(_vehicle_nodes[id] as Node).queue_free()
			_vehicle_nodes.erase(id)
			_veh_disp.erase(id)
			if _decoys.has(id):
				(_decoys[id] as Node).queue_free()
				_decoys.erase(id)


## Phantom drive: a faint copy of the rig stands where the nitro was cast while the decoy lasts.
func _update_decoy(v: SimVehicle, head: float) -> void:
	var dv: RigView = _decoys.get(v.id)
	if v.decoy_ticks <= 0 or not v.alive:
		if dv != null:
			dv.visible = false
		return
	if dv == null:
		dv = RigView.new()
		add_child(dv)
		_decoys[v.id] = dv
	dv.visible = true
	dv.setup(v)
	dv.place(v, Gfx.snap(v.decoy_pos), head, world.tick, frozen)
	dv.modulate = Color(1, 1, 1, 0.35)


## Protection shimmer strength for this frame (third-party protection, respawn shields).
func _protect_flash(v: SimVehicle) -> float:
	if not v.alive or protect_ticks(v) <= 0:
		return 0.0
	var t: int = world.tick
	return 0.15 if (t / 3) % 2 == 0 else 0.0


## Ticks of damage protection left: PvP third-party protection plus any respawn/round-start shield
## the sim may add (read by name so render keeps working whichever field exists).
static func protect_ticks(v: SimVehicle) -> int:
	var n: int = v.protect_ticks
	for f: String in ["invuln_ticks", "spawn_protect_ticks", "shield_ticks"]:
		var x: Variant = v.get(f)
		if x != null:
			n = maxi(n, int(x))
	return n


## Tyre tracks (persistent) and dust puffs (transient, `dust_age` < 0 = none) behind the rear wheels.
func _trail(id: int, p: Vector2, head: float, dust_age: float) -> void:
	var last: Variant = _veh_trail.get(id)
	if last != null and p.distance_to(last[0]) < TRAIL_STEP:
		return
	var rot: float = head + PI / 2.0
	var cur: Array = [p]
	var rv: RigView = _vehicle_nodes.get(id)
	var foot: int = rv.foot if rv != null else 0
	for w: Vector2 in RigArt.REAR_WHEELS[foot]:
		cur.append(p + w.rotated(rot))
	_veh_trail[id] = cur
	if last == null or p.distance_to(last[0]) > SNAP_DIST:
		return
	var steps: int = int(_veh_steps.get(id, 0)) + 1
	_veh_steps[id] = steps
	for i in range(1, cur.size()):
		_decals.track(last[i], cur[i], _track_width(id))
		if dust_age >= 0.0 and steps % 3 == 0:
			_effects.spawn(EffectsLayer.Kind.DUST, cur[i] - Vector2.from_angle(head) * 4.0, 0.0, dust_age, steps * 31 + i)


# ---------------------------------------------------------------- enemies and projectiles

func _update_enemies(lead: float, k: float) -> void:
	var n: int = world.enemy_count
	for layer in _enemy_layers:
		layer.begin(n)
	var disp: Dictionary = {}
	_burn_pos.clear()
	_stun_pos.clear()
	_warn_pos.clear()
	var burn_n: int = world.enemy_burn_ticks.size()
	var stun_n: int = world.enemy_status.size()
	var fv: SimVehicle = focus_vehicle()
	var warn: bool = fv != null and float(fv.tech_fx.get("spit_warn", 0.0)) > 0.0
	for i in n:
		var id: int = world.enemy_id[i]
		var vel: Vector2 = world.enemy_vel[i]
		var target: Vector2 = world.enemy_pos[i] + vel * lead
		var prev: Variant = _enemy_disp.get(id)
		var p: Vector2 = target
		var frame: int = 0
		if prev != null:
			var pv: Vector3 = prev
			frame = int(pv.z)
			var old := Vector2(pv.x, pv.y)
			if old.distance_to(target) < SNAP_DIST:
				p = old.lerp(target, k)
		if vel.length_squared() > 4.0:
			frame = Gfx.frame_for_angle(vel.angle(), Gfx.ENEMY_DIRS)
		disp[id] = Vector3(p.x, p.y, frame)
		if i < burn_n and world.enemy_burn_ticks[i] > 0:
			_burn_pos.append(Gfx.snap(p))
		if i < stun_n and (world.enemy_status[i] & 255) > 0:
			_stun_pos.append(Gfx.snap(p))
		if warn and world.enemy_kind[i] == SimWorld.SPITTER and SimWorld.spit_warning(world.tick, id):
			_warn_pos.append(Gfx.snap(p))
		var kind: int = world.enemy_kind[i]
		if kind < _enemy_layers.size():
			_enemy_layers[kind].add(p, frame, id % 2)
	_enemy_disp = disp
	for layer in _enemy_layers:
		layer.finish()


func _update_projectiles(lead: float) -> void:
	var n: int = world.proj_count
	_tracers.begin(n)
	_acid.begin(0)
	_acid_pos.clear()
	for i in n:
		var vel: Vector2 = world.proj_vel[i]
		var p: Vector2 = world.proj_pos[i] + vel * lead
		var frame: int = Gfx.frame_for_angle(vel.angle(), Gfx.FX_DIRS)
		if world.proj_owner[i] >= 0:
			_tracers.add(p, frame)
		else:
			_acid.add(p, frame)
			_acid_pos.append(Gfx.snap(p))
	_tracers.finish()
	_acid.finish()


func _draw_halos() -> void:
	var s := Vector2(Gfx.TEX_HALO_CYAN.get_size())
	for p in _acid_pos:
		_halos.draw_texture_rect(Gfx.TEX_HALO_CYAN, Rect2(p - s / 2.0, s), false, Color(1, 1, 1, 0.6))
	# Burning enemies: a warm halo that flickers (tick-hash, no randomness); ember zones: a dim warm glow.
	var ws := Vector2(Gfx.TEX_HALO_WARM.get_size())
	for bi in _burn_pos.size():
		var bp: Vector2 = _burn_pos[bi]
		var fl: float = 0.45 + 0.2 * float((world.tick + bi * 5) % 4)
		_halos.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(bp - ws / 2.0, ws), false, Color(1, 1, 1, fl))
	for zi in mini(world.zone_count, world.zone_pos.size()):
		if world.zone_kind[zi] != SimWorld.ZONE_EMBER and world.zone_kind[zi] != SimWorld.ZONE_FIRE:
			continue
		var zr: float = world.zone_radius[zi] * 2.0
		var zk := Vector2(zr, zr)
		var za: float = clampf(float(world.zone_ttl[zi]) / 30.0, 0.0, 1.0) * 0.35
		_halos.draw_texture_rect(Gfx.TEX_HALO_WARM_BIG, Rect2(Gfx.snap(world.zone_pos[zi]) - zk / 2.0, zk), false, Color(1, 1, 1, za))
	# Stunned aliens: a pale halo; spitters that are about to spit: a warm warning pip over them.
	for sp in _stun_pos:
		_halos.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(sp - ws / 2.0, ws), false, Color(0.8, 0.8, 0.9, 0.5))
	for wp in _warn_pos:
		var blink: bool = (world.tick / 3) % 2 == 0
		_halos.draw_rect(Rect2(wp + Vector2(-1, -14), Vector2(3, 6)), Gfx.FIRE[4] if blink else Gfx.FIRE[2])
		_halos.draw_rect(Rect2(wp + Vector2(-1, -7), Vector2(3, 2)), Gfx.FIRE[4] if blink else Gfx.FIRE[2])


# ---------------------------------------------------------------- events

func _consume_events(events: Array, age: float, transient: bool, tick: int = -1, rnd: int = 0) -> void:
	for e: Dictionary in events:
		_log_event(e, tick, rnd)
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var owner: int = int(e.get("owner", -1))
		var kind: int = int(e.get("kind", -1))
		var h: int = Gfx.hash_pos(pos, owner + 7)
		match str(e.get("type", "")):
			"emp":
				_add_ring(pos, Abilities.EMP_RADIUS, tick, 14, Gfx.STEEL[5])
			"boom":
				_add_ring(pos, Mobility.BOOM_RADIUS, tick, 10, Gfx.FIRE[4])
			"sparks":
				_add_ring(pos, Mobility.SPARKS_RADIUS, tick, 6, Gfx.FIRE[5])
				if transient:
					_effects.spawn(EffectsLayer.Kind.SPARKS, pos, float(h % 628) / 100.0, age, h)
			"nitro":
				_add_ring(pos, 16.0, tick, 8, Gfx.FIRE[3] if kind == 0 else Gfx.UI_DIM)
			"smoke", "salvo":
				_add_ring(pos, 24.0 if str(e.get("type", "")) == "smoke" else 30.0, tick, 10, Gfx.UI_DIM if str(e.get("type", "")) == "smoke" else Gfx.FIRE[5])
			"dodge":
				_add_ring(pos, 12.0, tick, 6, Gfx.UI_TEXT)
			"fire":
				if transient:
					_muzzle_flash(owner, pos, kind, age)
			"hit":
				if transient:
					var ang: float = float(h % 628) / 100.0
					if owner < 0:  # acid splashing on a rig
						_effects.spawn(EffectsLayer.Kind.ICHOR, pos, ang, age, h)
					else:
						_effects.spawn(EffectsLayer.Kind.SPARKS, pos, ang, age, h)
			"kill":
				if kind < 0:
					continue  # player kill: the wreck comes from "vehicle_destroyed", no alien goo
				_kill_decal(pos, kind, h)
				if transient:
					_effects.spawn(EffectsLayer.Kind.ICHOR, pos, float(h % 628) / 100.0, age, h + 1)
			"vehicle_destroyed":  # a rig goes up: big blast, flying scrap, shake (#11)
				_decals.stamp(Gfx.TEX_SCORCH, 2, 1, h % 2, 0, pos)
				for i in 3:
					var off := Vector2(float((h >> (i * 4)) % 33 - 16), float((h >> (i * 4 + 2)) % 25 - 12))
					_decals.stamp(Gfx.TEX_WRECK, 4, 1, (h + i) % 4, 0, pos + off)
				if transient:
					_effects.spawn(EffectsLayer.Kind.EXPLOSION_BIG, pos, 0.0, age, h)
					_effects.spawn(EffectsLayer.Kind.DEBRIS, pos, 0.0, age, h + 5)
					for i in 3:
						_effects.spawn(EffectsLayer.Kind.SPARKS, pos, float(i) * 2.1, age, h + 3 + i)
					_effects.spawn(EffectsLayer.Kind.EXPLOSION, pos + Vector2(9, -6), 0.0, age + 0.12, h + 9)
					if age < 0.05 and not frozen and _on_screen(pos):
						_shake = 1.0


## Books kills, wrecks and fuel drains for the UI (feed, recap). `tick` / `rnd`: when it happened.
func _log_event(e: Dictionary, tick: int, rnd: int) -> void:
	var type: String = str(e.get("type", ""))
	var log: Array[Dictionary]
	var entry: Dictionary = {"tick": tick, "round": rnd}
	match type:
		"kill":
			if int(e.get("kind", 0)) >= 0 or not e.has("victim"):
				return
			entry.merge({"killer": int(e.get("owner", -1)), "victim": int(e["victim"]), "weapon": int(e.get("weapon", -1))})
			log = kill_log
		"vehicle_destroyed":
			entry.merge({"id": int(e.get("owner", -1)), "cause": int(e.get("cause", -1)), "killer": int(e.get("killer", -1)), "pos": e.get("pos", Vector2.ZERO)})
			log = wreck_log
		"drain":
			entry.merge({"id": int(e.get("owner", -1)), "amount": int(e.get("kind", 0))})
			log = drain_log
		_:
			return
	log.append(entry)
	if log.size() > LOG_CAP:
		log.remove_at(0)


## An expanding ring of `radius` px that fades over `life` ticks (EMP, boom, sparks, ability casts).
func _add_ring(pos: Vector2, radius: float, tick: int, life: int, col: Color) -> void:
	if _rings.size() < 32:
		_rings.append([pos, radius, tick if tick >= 0 else world.tick, life, col])


func _muzzle_flash(vehicle_id: int, muzzle: Vector2, kind: int, age: float) -> void:
	if vehicle_id < 0 or vehicle_id >= world.vehicles.size():
		return
	var v: SimVehicle = world.vehicles[vehicle_id]
	var rv: RigView = _vehicle_nodes.get(v.id)
	if rv == null:
		return
	# Put the flash on the drawn barrel tip of that gun rather than the sim's muzzle point.
	var m: Array = rv.muzzle(kind, (muzzle - v.pos).angle())
	_effects.spawn(EffectsLayer.Kind.MUZZLE, m[0], m[1], age)
	if kind == Cards.weapon_kind_index("cannon"):
		_effects.spawn(EffectsLayer.Kind.SPARKS, m[0], m[1] + PI, age, Gfx.hash_pos(m[0], 3))


func _track_width(id: int) -> float:
	if id >= 0 and id < world.vehicles.size() and RigArt.uses_tracks(world.vehicles[id]):
		return 5.0
	return 3.0


func _kill_decal(pos: Vector2, kind: int, h: int) -> void:
	match kind:
		SimWorld.BOULDER:
			_decals.stamp(Gfx.TEX_GOO_BIG, 2, 1, h % 2, 0, pos)
		SimWorld.SPITTER:
			_decals.stamp(Gfx.TEX_GOO, 4, 1, 3, 0, pos)
			_decals.stamp(Gfx.TEX_GOO, 4, 1, h % 3, 0, pos + Vector2(4, -3))
		_:
			_decals.stamp(Gfx.TEX_GOO, 4, 1, h % 4, 0, pos)
			if h % 10 < 6:
				_decals.stamp(Gfx.TEX_CARCASS, 4, 1, (h / 7) % 4, 0, pos + Vector2(h % 3 - 1, (h / 3) % 3 - 1))


# ---------------------------------------------------------------- camera and labels

func _on_screen(p: Vector2) -> bool:
	var half: Vector2 = get_viewport_rect().size / 2.0
	return Rect2(_camera.position - half, half * 2.0).grow(24.0).has_point(p)


## Where the local rig (or the spectated one) is drawn, in viewport pixels (UI vignettes centre on it).
func local_screen_pos() -> Vector2:
	var vs: Vector2 = get_viewport_rect().size
	if world == null:
		return vs / 2.0
	var v: SimVehicle = focus_vehicle()
	if v == null:
		return vs / 2.0
	return screen_pos(v)


## Collision radius of `v`'s drawn rig (buggy or truck footprint), in pixels.
func rig_radius(v: SimVehicle) -> float:
	var rv: RigView = _vehicle_nodes.get(v.id)
	return RigArt.RADIUS[rv.foot if rv != null else 0]


## Where vehicle `v` is drawn, in viewport pixels (may be off-screen).
func screen_pos(v: SimVehicle) -> Vector2:
	var d: Vector3 = _vehicle_display(v)
	return (get_viewport().get_canvas_transform() * Gfx.snap(Vector2(d.x, d.y))).floor()


# ---------------------------------------------------------------- spectator

## True while the local rig is eliminated and the match goes on with others (spectator mode). The
## camera stays on the wreck for ELIM_HOLD_TICKS first (the HUD shows ELIMINATED meanwhile).
func spectating() -> bool:
	if world == null or attract or world.phase == SimWorld.PHASE_GAME_OVER:
		return false
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	if me == null or not me.eliminated or spectate_candidates().is_empty():
		return false
	return world.tick - last_wreck_tick(me.id) >= ELIM_HOLD_TICKS


## Tick of the latest "vehicle_destroyed" of vehicle `id` seen (very old if none).
func last_wreck_tick(id: int) -> int:
	for i in range(wreck_log.size() - 1, -1, -1):
		if int(wreck_log[i]["id"]) == id:
			return int(wreck_log[i]["tick"])
	return -(1 << 30)


## Rigs still in the game, other than the local one (in vehicle order).
func spectate_candidates() -> Array[SimVehicle]:
	var out: Array[SimVehicle] = []
	if world == null:
		return out
	for v in world.vehicles:
		if not v.eliminated and v.peer_id != local_peer:
			out.append(v)
	return out


## The rig the camera follows: the local one, or the spectated one when eliminated.
func focus_vehicle() -> SimVehicle:
	if world == null:
		return null
	if spectating():
		return spectated()
	return world.get_vehicle_for_peer(local_peer)


## The rig being watched in spectator mode (manual pick, else the auto choice).
func spectated() -> SimVehicle:
	var cands: Array[SimVehicle] = spectate_candidates()
	if cands.is_empty():
		return null
	for v in cands:
		if v.id == spectate_id:
			return v
	spectate_id = -1
	var cur: SimVehicle = null
	for v in cands:
		if v.id == _auto_id:
			cur = v
	if cur == null or absi(world.tick - _auto_tick) >= SPECTATE_RECHECK:
		cur = _auto_pick(cands)
		_auto_id = cur.id
		_auto_tick = world.tick
	return cur


## Auto camera: one side of the closest rival pair within FIGHT_DIST (the leader, else the higher
## score), else the bounty leader, else the best score.
func _auto_pick(cands: Array[SimVehicle]) -> SimVehicle:
	var best_d: float = FIGHT_DIST
	var pair: Array[SimVehicle] = []
	for i in cands.size():
		for j in range(i + 1, cands.size()):
			var a: SimVehicle = cands[i]
			var b: SimVehicle = cands[j]
			if not a.alive or not b.alive:
				continue
			var d: float = a.pos.distance_to(b.pos)
			if d < best_d:
				best_d = d
				pair = [a, b]
	var pool: Array[SimVehicle] = pair if not pair.is_empty() else cands
	var top: SimVehicle = pool[0]
	for v in pool:
		if v.peer_id == world.leader_peer:
			return v
		if world.leader_score(v) > world.leader_score(top):
			top = v
	return top


## Tab / arrows: step through the remaining rigs (dir +1 / -1); leaves auto mode.
func cycle_spectate(dir: int) -> void:
	var cands: Array[SimVehicle] = spectate_candidates()
	if cands.is_empty():
		return
	var cur: SimVehicle = spectated()
	var i: int = cands.find(cur)
	spectate_id = cands[posmod(i + dir, cands.size())].id


## Back to the automatic camera.
func spectate_auto() -> void:
	spectate_id = -1
	_auto_tick = -100000


## Selects a rig to watch by vehicle id (spectator panel clicks).
func spectate_vehicle(id: int) -> void:
	spectate_id = id


func _update_camera(k: float) -> void:
	var v: SimVehicle = focus_vehicle()
	if v == null:
		if attract:
			var t: float = float(world.tick) / float(SimWorld.TICK_RATE)
			var half := get_viewport_rect().size / 2.0
			var c: Vector2 = SimWorld.ARENA.get_center() + Vector2(sin(t * 0.045) * 300.0, sin(t * 0.032 + 1.3) * 170.0)
			c.x = clampf(c.x, SimWorld.ARENA.position.x + half.x, SimWorld.ARENA.end.x - half.x)
			c.y = clampf(c.y, SimWorld.ARENA.position.y + half.y, SimWorld.ARENA.end.y - half.y)
			_camera.position = Gfx.snap(c)
			_camera.force_update_scroll()
		return
	var d: Vector3 = _vehicle_display(v)
	var half := get_viewport_rect().size / 2.0
	var lift: float = (SPECTATE_CAM_LIFT if spectating() else WORKSHOP_CAM_LIFT) if world.phase == SimWorld.PHASE_WORKSHOP else 0.0
	_cam_lift = lerpf(_cam_lift, lift, k)
	var c := Vector2(d.x, d.y + _cam_lift)
	c.x = clampf(c.x, SimWorld.ARENA.position.x + half.x, SimWorld.ARENA.end.x - half.x)
	c.y = clampf(c.y, SimWorld.ARENA.position.y + half.y, SimWorld.ARENA.end.y - half.y)
	_camera.position = Gfx.snap(c)
	# shake: whole-pixel jolts on top of the clamped camera (the ground has margin to spare)
	_camera.offset = Gfx.snap(Vector2(sin(_shake_t * 61.0), cos(_shake_t * 47.0)) * 4.0 * _shake * _shake)
	_camera.force_update_scroll()


## Your own rig stands on a ring of its paint colour, so you find it at a glance (#6).
func _draw_ring() -> void:
	if world == null or attract:
		return
	for zi in mini(world.zone_count, world.zone_pos.size()):  # oil puddles on the ground
		if world.zone_kind[zi] == SimWorld.ZONE_OIL:
			var fade: float = clampf(float(world.zone_ttl[zi]) / 30.0, 0.0, 1.0)
			_ring.draw_circle(Gfx.snap(world.zone_pos[zi]), world.zone_radius[zi], Color(0.07, 0.05, 0.05, 0.55 * fade))
	var v: SimVehicle = focus_vehicle()
	if v == null or not v.alive:
		return
	var rv: RigView = _vehicle_nodes.get(v.id)
	var d: Vector3 = _vehicle_display(v)
	var c: Vector2 = Gfx.snap(Vector2(d.x, d.y))
	var r: float = RigArt.RADIUS[rv.foot if rv != null else 0]
	var col: Color = Gfx.PLAYER_COLORS[Gfx.player_index(v)]
	if v.color_index == Gfx.DARK_PAINT:
		col = Gfx.STEEL[3]
	var n: int = int(r * 4.0)
	var spin: int = world.tick / 3
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var p: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a) * 0.8) * r)
		var dash: bool = ((i + spin) / 3) % 2 == 0
		_ring.draw_rect(Rect2(p, Vector2.ONE), Color(col, 0.75 if dash else 0.3))
		_ring.draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.25))


## Driver names in paint colour and hp ticks over rival rigs (readability, design doc section 11c).
func _draw_labels() -> void:
	if world == null or attract:
		return
	_draw_effects_overlay()
	for v in world.vehicles:
		if not v.alive:
			continue
		var d: Vector3 = _vehicle_display(v)
		var p: Vector2 = Gfx.snap(Vector2(d.x, d.y))
		var rv: RigView = _vehicle_nodes.get(v.id)
		var r: float = RigArt.RADIUS[rv.foot if rv != null else 0]
		var top: float = p.y - r - 9.0
		if protect_ticks(v) > 0:
			_draw_shield(p, r, v.id)
		if v.momentum >= Mobility.FULL_MOMENTUM:  # full momentum: sparks fly off the rig
			for k in 3:
				var a: float = float((world.tick * 7 + k * 5 + v.id * 3) % 63) / 10.0
				var sp: Vector2 = Gfx.snap(p + Vector2(cos(a), sin(a)) * (r + 1.0 + float((world.tick + k) % 3)))
				_labels.draw_rect(Rect2(sp, Vector2.ONE), Gfx.FIRE[5] if k % 2 == 0 else Gfx.FIRE[4])
		if v.mark_id >= 0:  # swarm logic: a red laser line from the rig to its marked target
			_draw_laser(p, v.mark_pos)
		if v.peer_id == world.leader_peer:  # bounty mark (#11)
			var bob: float = float((world.tick / 10) % 2)
			var s := Vector2(Gfx.TEX_SKULL.get_size())
			var sy: float = top - (s.y + 4.0 if v.peer_id != local_peer else 0.0) - bob
			_labels.draw_texture(Gfx.TEX_SKULL, Vector2(p.x - floorf(s.x / 2.0), sy))
		# rival name tags and hp bars are drawn by the HUD (crisp text): Hud._draw_rival_tags


## Rings from events (EMP, boom, sparks, ability casts) and smoke clouds. Minimal: a real visual pass comes later.
func _draw_effects_overlay() -> void:
	var keep: Array = []
	for rg: Array in _rings:
		var age: float = float(world.tick - int(rg[2])) / float(rg[3])
		if age >= 1.0 or age < 0.0:
			continue
		keep.append(rg)
		var col: Color = rg[4]
		var rad: float = float(rg[1]) * minf(1.0, age * 2.5 + 0.2)
		var n: int = maxi(int(rad * 1.4), 12)
		var c: Vector2 = Gfx.snap(rg[0])
		for i in n:
			var a: float = TAU * float(i) / float(n)
			_labels.draw_rect(Rect2(Gfx.snap(c + Vector2(cos(a), sin(a) * 0.85) * rad), Vector2.ONE), Color(col, 0.9 * (1.0 - age)))
	_rings = keep
	for zi in mini(world.zone_count, world.zone_pos.size()):
		if world.zone_kind[zi] != SimWorld.ZONE_SMOKE:
			continue
		var zc: Vector2 = Gfx.snap(world.zone_pos[zi])
		var zr: float = world.zone_radius[zi]
		var fade: float = clampf(float(world.zone_ttl[zi]) / 30.0, 0.0, 1.0)
		for k in 14:  # a puffy cloud: a fixed scatter of dim discs (no randomness, from the zone index)
			var a2: float = float(k) * 2.399963 + float(zi)
			var rr: float = zr * 0.7 * sqrt(float(k + 1) / 14.0)
			_labels.draw_circle(Gfx.snap(zc + Vector2(cos(a2), sin(a2)) * rr), zr * 0.35, Color(0.32, 0.29, 0.27, 0.16 * fade))


## A thin dashed red line (swarm logic mark); warm, never cyan.
func _draw_laser(from: Vector2, to: Vector2) -> void:
	var dist: float = from.distance_to(to)
	var steps: int = int(dist / 4.0)
	for i in range(1, steps):
		if (i + world.tick / 2) % 3 == 0:
			continue
		_labels.draw_rect(Rect2(Gfx.snap(from.lerp(to, float(i) / float(steps))), Vector2.ONE), Color(Gfx.UI_BAD, 0.7))
	_labels.draw_rect(Rect2(Gfx.snap(to) - Vector2.ONE, Vector2(3, 3)), Color(Gfx.UI_BAD, 0.9))


## Protection shimmer: a broken ring of warm-white sparks orbiting the rig (never cyan: cold = alien).
func _draw_shield(c: Vector2, r: float, sd: int) -> void:
	var n: int = 22
	var t: float = float(world.tick) * 0.09 + float(sd)
	for i in n:
		var a: float = TAU * float(i) / float(n) + t
		if (i + world.tick / 2) % 4 == 0:
			continue
		var p: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a) * 0.85) * (r + 2.0))
		var col: Color = Gfx.FIRE[6] if i % 3 == 0 else Gfx.FIRE[5]
		_labels.draw_rect(Rect2(p, Vector2.ONE), Color(col, 0.85))
