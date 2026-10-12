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
const REAR_WHEELS: Array[Vector2] = [Vector2(-12, 13), Vector2(12, 13)]  ## buggy, facing north
const SHOT_EFFECT_TICKS := 10  ## screenshot mode: transient effects from the last N ticks
const WORKSHOP_CAM_LIFT := 92.0  ## px: in the workshop the camera shows the camped rig near the top
const CAM_EASE := 4.0  ## 1/s, easing of that lift

var world: SimWorld = null
var local_peer: int = 1
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
var workshop: WorkshopUi
var game_over: GameOverUi
var _cam_lift: float = 0.0

var _vehicle_nodes: Dictionary = {}  # vehicle id -> [shadow, hull, turret] Sprite2D
var _veh_disp: Dictionary = {}  # vehicle id -> Vector3(x, y, heading)
var _veh_trail: Dictionary = {}  # vehicle id -> [position, wheel positions...] at the last track stamp
var _veh_steps: Dictionary = {}  # vehicle id -> int, track stamps so far (dust cadence)
var _enemy_disp: Dictionary = {}  # enemy id -> Vector3(x, y, frame)
var _acid_pos: PackedVector2Array = PackedVector2Array()
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

	var kinds: Array = [  # [texture, glow, rows, shadow offset] per SimWorld enemy kind
		[Gfx.TEX_MITE, Gfx.TEX_MITE_GLOW, 2, Vector2(1, 2)],
		[Gfx.TEX_BOULDER, Gfx.TEX_BOULDER_GLOW, 2, Vector2(3, 4)],
		[Gfx.TEX_SPITTER, Gfx.TEX_SPITTER_GLOW, 1, Vector2(2, 3)],
	]
	for k in kinds:
		var layer := SheetLayer.new()
		add_child(layer)
		layer.setup(k[0], Gfx.ENEMY_DIRS, k[2], Gfx.Z_ENEMIES, k[1], k[3])
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
	add_child(hud_layer)
	_hud = Hud.new()
	_hud.view = self
	hud_layer.add_child(_hud)
	workshop = WorkshopUi.new()
	workshop.view = self
	hud_layer.add_child(workshop)
	game_over = GameOverUi.new()
	game_over.view = self
	hud_layer.add_child(game_over)


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
		for n: Node in _vehicle_nodes[id]:
			n.queue_free()
	_vehicle_nodes.clear()
	_decals.clear()
	_effects.clear()
	_hud.world = w
	_hud.local_peer = peer
	workshop.world = w
	workshop.local_peer = peer
	game_over.world = w
	game_over.local_peer = peer


## Snapshot of one tick for prime(): events plus vehicle poses (for tyre tracks).
static func record_tick(w: SimWorld) -> Dictionary:
	var veh: Array = []
	for v in w.vehicles:
		veh.append([v.id, v.pos, v.heading, v.alive])
	return {"tick": w.tick, "events": w.events.duplicate(), "vehicles": veh}


## Screenshot mode: replays recorded ticks so the frame shows the match's history (persistent goo,
## scorch and tracks from every tick, transient effects from the last few ticks at their age).
func prime(history: Array) -> void:
	if world == null or history.is_empty():
		return
	var last_tick: int = history[-1]["tick"]
	for h: Dictionary in history:
		var age: float = float(last_tick - int(h["tick"])) * SimWorld.DT
		for vd: Array in h["vehicles"]:
			if vd[3]:
				_trail(vd[0], vd[1], vd[2], age if age < EffectsLayer.LIFE[EffectsLayer.Kind.DUST] else -1.0)
		_consume_events(h["events"], age, last_tick - int(h["tick"]) < SHOT_EFFECT_TICKS)
	_last_tick = world.tick
	_veh_trail.clear()


func _process(delta: float) -> void:
	if world == null:
		return
	if world.tick != _last_tick:
		_consume_events(world.events, 0.0, true)
		_last_tick = world.tick
		_tick_age = 0.0
	elif not frozen:
		_tick_age += delta
	var lead: float = 0.0 if frozen else minf(_tick_age, MAX_LEAD)
	var k: float = 1.0 if frozen else 1.0 - exp(-SMOOTH_RATE * delta)
	_update_vehicles(lead, k)
	_update_enemies(lead, k)
	_update_projectiles(lead)
	_update_camera(1.0 if frozen else 1.0 - exp(-CAM_EASE * delta))
	_halos.queue_redraw()
	_labels.queue_redraw()


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

		var nodes: Array = _vehicle_nodes.get(v.id, [])
		if nodes.is_empty():
			nodes = _make_vehicle_nodes(v)
			_vehicle_nodes[v.id] = nodes
		var shadow: Sprite2D = nodes[0]
		var hull: Sprite2D = nodes[1]
		var turret: Sprite2D = nodes[2]
		var tex: Texture2D = Gfx.TEX_BUGGY[Gfx.player_index(v)]
		hull.texture = tex
		shadow.texture = tex
		var frame: int = Gfx.frame_for_angle(head, Gfx.VEHICLE_DIRS)
		hull.position = Gfx.snap(p)
		hull.frame = frame
		shadow.position = hull.position + Vector2(3, 4)
		shadow.frame = frame
		hull.modulate = Color.WHITE if v.alive else Color(0.32, 0.27, 0.27)
		turret.visible = v.alive
		if v.alive:
			turret.position = hull.position + Gfx.snap(_turret_pivot(frame))
			var aim: float = float(v.weapons[0]["aim"]) if not v.weapons.is_empty() else head
			turret.frame = Gfx.frame_for_angle(aim, Gfx.VEHICLE_DIRS)
			_trail(v.id, p, head, -1.0 if frozen else 0.0)
	for id in _vehicle_nodes.keys():
		if not seen.has(id):
			for n: Node in _vehicle_nodes[id]:
				n.queue_free()
			_vehicle_nodes.erase(id)
			_veh_disp.erase(id)


func _make_vehicle_nodes(v: SimVehicle) -> Array:
	var tex: Texture2D = Gfx.TEX_BUGGY[Gfx.player_index(v)]
	var shadow := Sprite2D.new()
	shadow.texture = tex
	shadow.hframes = Gfx.VEHICLE_DIRS
	shadow.z_index = Gfx.Z_SHADOWS
	var mat := ShaderMaterial.new()
	mat.shader = Gfx.SILHOUETTE_SHADER
	shadow.material = mat
	var hull := Sprite2D.new()
	hull.texture = tex
	hull.hframes = Gfx.VEHICLE_DIRS
	hull.z_index = Gfx.Z_VEHICLES
	var turret := Sprite2D.new()
	turret.texture = Gfx.TEX_TURRET
	turret.hframes = Gfx.VEHICLE_DIRS
	turret.z_index = Gfx.Z_TURRETS
	for n in [shadow, hull, turret]:
		add_child(n)
	return [shadow, hull, turret]


func _turret_pivot(frame: int) -> Vector2:
	return Gfx.TURRET_PIVOT.rotated(Gfx.frame_rotation(frame, Gfx.VEHICLE_DIRS))


## Tyre tracks (persistent) and dust puffs (transient, `dust_age` < 0 = none) behind the rear wheels.
func _trail(id: int, p: Vector2, head: float, dust_age: float) -> void:
	var last: Variant = _veh_trail.get(id)
	if last != null and p.distance_to(last[0]) < TRAIL_STEP:
		return
	var rot: float = head + PI / 2.0
	var cur: Array = [p]
	for w in REAR_WHEELS:
		cur.append(p + w.rotated(rot))
	_veh_trail[id] = cur
	if last == null or p.distance_to(last[0]) > SNAP_DIST:
		return
	var steps: int = int(_veh_steps.get(id, 0)) + 1
	_veh_steps[id] = steps
	for i in range(1, cur.size()):
		_decals.track(last[i], cur[i])
		if dust_age >= 0.0 and steps % 3 == 0:
			_effects.spawn(EffectsLayer.Kind.DUST, cur[i] - Vector2.from_angle(head) * 4.0, 0.0, dust_age, steps * 31 + i)


# ---------------------------------------------------------------- enemies and projectiles

func _update_enemies(lead: float, k: float) -> void:
	var n: int = world.enemy_count
	for layer in _enemy_layers:
		layer.begin(n)
	var disp: Dictionary = {}
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
		_halos.draw_texture_rect(Gfx.TEX_HALO_CYAN, Rect2(p - s / 2.0, s), false, Color(1, 1, 1, 0.35))


# ---------------------------------------------------------------- events

func _consume_events(events: Array, age: float, transient: bool) -> void:
	for e: Dictionary in events:
		var pos: Vector2 = e.get("pos", Vector2.ZERO)
		var owner: int = int(e.get("owner", -1))
		var kind: int = int(e.get("kind", -1))
		var h: int = Gfx.hash_pos(pos, owner + 7)
		match str(e.get("type", "")):
			"fire":
				if transient:
					_muzzle_flash(owner, pos, age)
			"hit":
				if transient:
					var ang: float = float(h % 628) / 100.0
					if owner < 0:  # acid splashing on a rig
						_effects.spawn(EffectsLayer.Kind.ICHOR, pos, ang, age, h)
					else:
						_effects.spawn(EffectsLayer.Kind.SPARKS, pos, ang, age, h)
			"kill":
				_kill_decal(pos, kind, h)
				if transient:
					_effects.spawn(EffectsLayer.Kind.ICHOR, pos, float(h % 628) / 100.0, age, h + 1)
			"vehicle_destroyed":
				_decals.stamp(Gfx.TEX_SCORCH, 2, 1, h % 2, 0, pos)
				if transient:
					_effects.spawn(EffectsLayer.Kind.EXPLOSION, pos, 0.0, age, h)
					_effects.spawn(EffectsLayer.Kind.SPARKS, pos, 0.0, age, h + 3)


func _muzzle_flash(vehicle_id: int, muzzle: Vector2, age: float) -> void:
	if vehicle_id < 0 or vehicle_id >= world.vehicles.size():
		return
	var v: SimVehicle = world.vehicles[vehicle_id]
	var ang: float = (muzzle - v.pos).angle()
	# Put the flash on the drawn barrel tip rather than the sim's muzzle point.
	var d: Vector3 = _vehicle_display(v)
	var frame: int = Gfx.frame_for_angle(d.z, Gfx.VEHICLE_DIRS)
	var pivot: Vector2 = Gfx.snap(Vector2(d.x, d.y)) + Gfx.snap(_turret_pivot(frame))
	var aim_frame: int = Gfx.frame_for_angle(ang, Gfx.VEHICLE_DIRS)
	var aim: float = Gfx.frame_rotation(aim_frame, Gfx.VEHICLE_DIRS) - PI / 2.0
	_effects.spawn(EffectsLayer.Kind.MUZZLE, pivot + Vector2.from_angle(aim) * Gfx.BARREL_LENGTH, aim, age)


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

## Where the local rig is drawn, in viewport pixels (UI vignettes centre on it).
func local_screen_pos() -> Vector2:
	var vs: Vector2 = get_viewport_rect().size
	if world == null:
		return vs / 2.0
	var v: SimVehicle = world.get_vehicle_for_peer(local_peer)
	if v == null:
		return vs / 2.0
	var d: Vector3 = _vehicle_display(v)
	return (get_viewport().get_canvas_transform() * Gfx.snap(Vector2(d.x, d.y))).floor()


func _update_camera(k: float) -> void:
	var v: SimVehicle = world.get_vehicle_for_peer(local_peer)
	if v == null:
		return
	var d: Vector3 = _vehicle_display(v)
	var half := get_viewport_rect().size / 2.0
	var lift: float = WORKSHOP_CAM_LIFT if world.phase == SimWorld.PHASE_WORKSHOP else 0.0
	_cam_lift = lerpf(_cam_lift, lift, k)
	var c := Vector2(d.x, d.y + _cam_lift)
	c.x = clampf(c.x, SimWorld.ARENA.position.x + half.x, SimWorld.ARENA.end.x - half.x)
	c.y = clampf(c.y, SimWorld.ARENA.position.y + half.y, SimWorld.ARENA.end.y - half.y)
	_camera.position = Gfx.snap(c)
	_camera.force_update_scroll()


## Paint-coloured tags and hp ticks over rival rigs (readability, design doc section 11c).
func _draw_labels() -> void:
	if world == null:
		return
	for v in world.vehicles:
		if v.peer_id == local_peer or not v.alive:
			continue
		var d: Vector3 = _vehicle_display(v)
		var p: Vector2 = Gfx.snap(Vector2(d.x, d.y))
		var idx: int = Gfx.player_index(v)
		var tag: String = Gfx.PLAYER_NAMES[idx]
		var top: float = p.y - 36.0
		PixelFont.draw(_labels, tag, Vector2(p.x - floorf(PixelFont.width(tag) / 2.0), top), Gfx.PLAYER_COLORS[idx], Gfx.OUTLINE)
		var bw: float = 20.0
		_labels.draw_rect(Rect2(p.x - bw / 2.0 - 1.0, top + 7.0, bw + 2.0, 3.0), Gfx.OUTLINE)
		_labels.draw_rect(Rect2(p.x - bw / 2.0, top + 8.0, floorf(bw * clampf(v.hp / v.max_hp, 0.0, 1.0)), 1.0), Gfx.PLAYER_COLORS[idx])
