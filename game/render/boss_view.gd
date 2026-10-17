class_name BossView
extends Node2D
## Boss fights on screen (design doc 7f / 11h, docs/architecture.md "Bosses (as built)" and "Boss visuals").
## Reads the world only: boss bodies are enemies of kind >= SimWorld.BOSS_A (positions from the WorldView's
## smoothed enemy positions), the telegraphs are `world.boss_marks`, the moments come from the `boss_*` events
## (WorldView._consume_events hands them to `on_event`, also from `prime()` in screenshot mode).
## - Bodies: the real sprite sheets (Tripod Queen walk / aim / fire, Shard Colossus walk / windup / hurt, the
##   shard minions) with silhouette shadows, additive glow sheets and the white hit flash of other aliens.
## - Projectiles: the Colossus ring shards (alien projectiles at Bosses.RING_SPEED, told from spitter acid by
##   their speed) and the Queen's mortar rounds arcing from her sac to the telegraph (the sim only has the marker).
## - Telegraphs: shell landing circles filling in (tripod_telegraph.png, 1:1 at the blast reach) with a
##   countdown sweep, the Colossus wind-up glow and a dithered cyan charge lane with running chevrons.
## - Moments: churning sand before the spawn, the eruption, the phase roar, the crystal split, the multi-stage
##   death with a warm scrap fountain, the retreat burrow; carcass decals. Positions and particles are analytic
##   in (moment tick, seed), so screenshots show the same thing. The HUD reads the moment ticks below.
## Palette: alien light is cyan (GLOW) only while active; debris drains to the desert ramps; scrap stays warm.

const TEX_TRIPOD := preload("res://assets/tripod_queen.png")  ## 128 px cells: walk0..3, aim, fire
const TEX_TRIPOD_GLOW := preload("res://assets/tripod_queen_glow.png")
const TEX_COLOSSUS := preload("res://assets/shard_colossus.png")  ## 128 px: walk0..3, windup0, windup1, hurt
const TEX_COLOSSUS_GLOW := preload("res://assets/shard_colossus_glow.png")
const TEX_MINION := preload("res://assets/shard_minion.png")  ## 48 px: walk0, walk1
const TEX_MINION_GLOW := preload("res://assets/shard_minion_glow.png")
const TEX_SHELL := preload("res://assets/tripod_shell.png")  ## 16 px, 16 directions
const TEX_SHELL_GLOW := preload("res://assets/tripod_shell_glow.png")
const TEX_SHARD := preload("res://assets/crystal_shard.png")  ## 16 px, 16 directions
const TEX_SHARD_GLOW := preload("res://assets/crystal_shard_glow.png")
const TEX_TELEGRAPH := preload("res://assets/tripod_telegraph.png")  ## 6 frames, ring radius 63 px (the blast reach)
const TEX_CARCASS_TRIPOD := preload("res://assets/decal_carcass_tripod.png")
const TEX_CARCASS_COLOSSUS := preload("res://assets/decal_carcass_colossus.png")
const TEX_CARCASS_SHARD := preload("res://assets/decal_carcass_shard.png")  ## 2 variants

const ROW_AIM := 4
const ROW_FIRE := 5
const ROW_WINDUP0 := 4
const ROW_WINDUP1 := 5
const ROW_HURT := 6
const TELEGRAPH_FRAMES := 6
const FLASH := 0.5  ## hit flash on a boss body (a little softer than small aliens: it is under fire all the time)
const SHARD_SPEED_TOL := 8.0
const FIRE_HOLD := 9  ## ticks the Queen shows her fire row after a volley
const AIM_LEAD := 24  ## ticks before a volley she swells the sac (aim row)
const CHARGE_SPEED_MIN := 250.0  ## a Colossus faster than this is charging

const GLASS: Array[Color] = [Color("#7fa9ae"), Color("#a9cfd0"), Color("#cfe8e6"), Color("#eef8f6")]
const CHITIN: Array[Color] = [Color("#3a2a24"), Color("#5a4234"), Color("#7d5d45"), Color("#a07c5a"), Color("#c4a076"), Color("#dcc099")]
const RUST := Color("#843f24")
const BAYER4: PackedInt32Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## Moment lifetimes (s).
const LIFE := {"spawn": 1.8, "phase": 1.1, "split": 1.6, "kill": 2.6, "retreat": 1.8, "blast": 0.8, "ring": 0.4,
	"brood": 0.6, "shard_death": 1.0, "charge": 0.5}
const MAX_MOMENTS := 48

# particle styles
const P_SAND := 0
const P_PLATE := 1
const P_GLASS := 2
const P_GOO := 3
const P_SCRAP := 4
const P_DUST := 5

var view: WorldView
var world: SimWorld

## HUD-facing state, from the events (screenshots rebuild it through WorldView.prime).
var warn_tick: int = -100000
var spawn_tick: int = -100000
var phase_tick: int = -100000
var phase_n: int = 0
var split_tick: int = -100000
var end_tick: int = -100000  ## boss_kill or boss_retreat
var end_kill: bool = false
var end_kind: int = -1
var end_killer: int = -1  ## vehicle id of the killing blow (-1 = none)
var end_round: int = 0
var end_pos: Vector2 = Vector2.ZERO

var _last_shell_tick: int = -100000
var _moments: Array[Dictionary] = []
var _seen_tick: int = -1
var _frame_of: Dictionary = {}  ## enemy id -> last facing frame (held while standing)
var _last_frame: Dictionary = {}  ## boss kind -> facing frame of the last body seen (the dying body keeps it)

var _tripod: SheetLayer
var _colossus: SheetLayer
var _minion: SheetLayer
var _shards: SheetLayer
var _ground: Node2D
var _over: Node2D
var _glow: Node2D
var _dither: Array[ImageTexture] = []
## This frame's bodies: [kind, display pos, enemy id, facing frame, row, windup 0..1].
var _bodies: Array[Array] = []
var _shard_pos: PackedVector2Array = PackedVector2Array()
var _shell_pos: PackedVector2Array = PackedVector2Array()  ## mortar rounds in flight this frame (glow pass)


func _ready() -> void:
	_tripod = _layer(TEX_TRIPOD, TEX_TRIPOD_GLOW, 6, Vector2(8, 11), 0.5)
	_colossus = _layer(TEX_COLOSSUS, TEX_COLOSSUS_GLOW, 7, Vector2(6, 9), 0.5)
	_minion = _layer(TEX_MINION, TEX_MINION_GLOW, 2, Vector2(3, 4), 0.45)
	_shards = SheetLayer.new()
	add_child(_shards)
	_shards.setup(TEX_SHARD, Gfx.FX_DIRS, 1, Gfx.Z_PROJECTILES, TEX_SHARD_GLOW, Vector2(2, 3), 0.9, 0.35)
	_ground = Node2D.new()
	_ground.z_index = Gfx.Z_RING
	_ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_over = Node2D.new()
	_over.z_index = Gfx.Z_EFFECTS
	_over.draw.connect(_draw_over)
	add_child(_over)
	_glow = Node2D.new()
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add_mat
	_glow.z_index = Gfx.Z_GLOW
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	for level in 5:  # ordered-dither tiles (4x4 Bayer), 3/16 .. 15/16 coverage; tinted by the draw colour
		var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		for k in 16:
			if BAYER4[k] < 3 + level * 3:
				img.set_pixel(k % 4, k / 4, Color.WHITE)
		_dither.append(ImageTexture.create_from_image(img))


func _layer(tex: Texture2D, glow: Texture2D, rows: int, shadow: Vector2, alpha: float) -> SheetLayer:
	var l := SheetLayer.new()
	add_child(l)
	l.setup(tex, Gfx.ENEMY_DIRS, rows, Gfx.Z_ENEMIES, glow, shadow, 1.0, alpha)
	return l


func clear() -> void:
	warn_tick = -100000
	spawn_tick = -100000
	phase_tick = -100000
	phase_n = 0
	split_tick = -100000
	end_tick = -100000
	end_kill = false
	end_kind = -1
	end_killer = -1
	end_pos = Vector2.ZERO
	_last_shell_tick = -100000
	_moments.clear()
	_frame_of.clear()
	_last_frame.clear()
	_seen_tick = -1


# ---------------------------------------------------------------- events

## One boss event (or the death of a boss body). `age` s since it happened, `transient`: recent enough for
## one-off EffectsLayer effects (screenshots replay the last few ticks only), `tick` when it happened.
func on_event(type: String, e: Dictionary, age: float, transient: bool, tick: int) -> void:
	world = view.world
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	var kind: int = int(e.get("kind", -1))
	var h: int = Gfx.hash_pos(pos, tick + 13)
	var fx: EffectsLayer = view._effects
	match type:
		"boss":
			warn_tick = tick
		"boss_spawn":
			spawn_tick = tick
			phase_n = 1
			_moment("spawn", pos, tick, kind)
			if transient:
				fx.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, 78.0)
				for i in 5:
					fx.spawn(EffectsLayer.Kind.DUST, pos + Vector2.from_angle(float(i) * 1.26 + 0.3) * 26.0, 0.0, age + 0.06 * float(i), h + i)
			_jolt(pos, 0.75)
		"boss_phase":
			phase_tick = tick
			phase_n = kind
			_moment("phase", pos, tick, kind)
			_jolt(pos, 0.62)
		"boss_split":
			split_tick = tick
			var sm: Dictionary = _moment("split", pos, tick, kind)
			sm["body"] = SimWorld.BOSS_B
			sm["frame"] = int(_last_frame.get(SimWorld.BOSS_B, 8))
			view.stamp_decal(TEX_CARCASS_COLOSSUS, 1, 0, pos)  # the husk stays where it shattered
			if transient:
				fx.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 1, 70.0)
			_jolt(pos, 0.8)
		"boss_kill":
			end_tick = tick
			end_kill = true
			end_kind = kind
			end_killer = int(e.get("owner", -1))
			end_round = world.round if world != null else 0
			end_pos = pos
			var km: Dictionary = _moment("kill", pos, tick, kind)
			var body: int = SimWorld.BOSS_A if kind == SimWorld.BOSS_A else SimWorld.BOSS_SHARD  # the Colossus dies as its last shard
			km["body"] = body
			km["frame"] = int(_last_frame.get(body, 8))
			if kind == SimWorld.BOSS_A:
				view.stamp_decal(TEX_CARCASS_TRIPOD, 1, 0, pos)
			for i in 3:
				view.stamp_decal(Gfx.TEX_GOO_BIG, 2, (h + i) % 2, pos + Vector2.from_angle(float(h % 7) + float(i) * 2.1) * 22.0)
			if transient:
				fx.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, 96.0)
				fx.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age + 0.35, 0, 60.0)
		"boss_retreat":
			end_tick = tick
			end_kill = false
			end_kind = world.boss_kind if world != null else -1
			end_killer = -1
			end_round = world.round if world != null else 0
			end_pos = pos
			_moment("retreat", pos, tick, end_kind)
		"boss_shell":
			_last_shell_tick = tick
		"boss_blast":  # a mortar round lands: a geode bursts, sand fountains, goo stains the ground
			_moment("blast", pos, tick, kind)
			view.stamp_decal(Gfx.TEX_GOO_BIG, 2, h % 2, pos)
			view.stamp_decal(Gfx.TEX_GOO, 4, h % 4, pos + Vector2(float(h % 13) - 6.0, float((h / 13) % 9) - 4.0))
			if transient:
				fx.spawn(EffectsLayer.Kind.SHOCK, pos, 0.0, age, 0, float(kind))
				fx.spawn(EffectsLayer.Kind.DUST, pos, 0.0, age + 0.05, h)
				fx.spawn(EffectsLayer.Kind.DUST, pos + Vector2(12, 4), 0.0, age + 0.12, h + 1)
			_jolt(pos, 0.45)
		"boss_ring":
			_moment("ring", pos, tick, kind)
		"boss_brood":
			_moment("brood", pos, tick, kind)
		"boss_charge":
			_moment("charge", pos, tick, kind)
		"kill":  # a Colossus shard dies (the last one also brings boss_kill)
			if kind == SimWorld.BOSS_SHARD:
				_moment("shard_death", pos, tick, kind)
				view.stamp_decal(TEX_CARCASS_SHARD, 2, h % 2, pos)
				_jolt(pos, 0.5)


func _moment(type: String, pos: Vector2, tick: int, kind: int) -> Dictionary:
	if _moments.size() >= MAX_MOMENTS:
		_moments.remove_at(0)
	var m := {"type": type, "pos": pos, "tick": tick, "kind": kind, "seed": Gfx.hash_pos(pos, tick * 7 + type.length())}
	_moments.append(m)
	return m


## A camera jolt for a moment on screen (never in screenshot mode).
func _jolt(pos: Vector2, amount: float) -> void:
	if view.frozen or not view._on_screen(pos):
		return
	view._shake = maxf(view._shake, amount)


# ---------------------------------------------------------------- per frame

func _process(_delta: float) -> void:
	if view == null or view.world == null:
		return
	world = view.world
	var lead: float = 0.0 if view.frozen else minf(view._tick_age, WorldView.MAX_LEAD)
	_update_bodies()
	_update_shards(lead)
	if world.tick != _seen_tick:
		_seen_tick = world.tick
		_rumble()
	if not view.frozen:  # the death throes shake slower and longer than a blast
		var kt: float = _since(end_tick)
		if end_kill and kt < 1.5:
			view._shake = maxf(view._shake, 0.95 * (1.0 - kt / 1.5) * (0.75 + 0.25 * sin(kt * 17.0)))
	var keep: Array[Dictionary] = []
	for m in _moments:
		if _since(int(m["tick"])) < float(LIFE[m["type"]]):
			keep.append(m)
	_moments = keep
	_ground.queue_redraw()
	_over.queue_redraw()
	_glow.queue_redraw()


## Seconds since `tick` (sub-tick smooth while playing; whole ticks in screenshot mode).
func _since(tick: int) -> float:
	var t: float = float(world.tick - tick) * SimWorld.DT
	if not view.frozen:
		t += minf(view._tick_age, SimWorld.DT)
	return t


## Footsteps under the sand while the boss is announced: thumps every 18 ticks, harder as it nears.
func _rumble() -> void:
	if view.frozen or world.boss_state != Bosses.ST_WARNED:
		return
	var left: int = world.boss_warn_left
	if left % 18 == 0 or left < 8:
		var p: float = 1.0 - float(left) / float(Bosses.WARN_TICKS)
		view._shake = maxf(view._shake, 0.42 + 0.33 * p)


func _update_bodies() -> void:
	_bodies.clear()
	var tripod_n: int = 0
	_tripod.begin(1)
	_colossus.begin(1)
	_minion.begin(3)
	for i in world.enemy_count:
		var kind: int = world.enemy_kind[i]
		if kind < SimWorld.BOSS_A or world.enemy_hp[i] <= 0.0:
			continue
		var id: int = world.enemy_id[i]
		var sim_p: Vector2 = world.enemy_pos[i]
		var d: Variant = view._enemy_disp.get(id)
		var p: Vector2 = Gfx.snap(Vector2((d as Vector3).x, (d as Vector3).y) if d != null else sim_p)
		var vel: Vector2 = world.enemy_vel[i]
		var spd: float = vel.length()
		var frame: int = int(_frame_of.get(id, (d as Vector3).z if d != null else 8))
		var wind: float = _windup(p, kind)
		var mark: Dictionary = _mark_for(p, Bosses.MARK_CHARGE)
		if kind == SimWorld.BOSS_A:  # she turns her mortar to the nearest rig
			var vi: int = Bosses.nearest_vehicle(world, sim_p)
			if vi >= 0:
				frame = Gfx.frame_for_angle((world.vehicles[vi].pos - sim_p).angle(), Gfx.ENEMY_DIRS)
		elif not mark.is_empty():
			frame = Gfx.frame_for_angle(((mark["pos2"] as Vector2) - (mark["pos"] as Vector2)).angle(), Gfx.ENEMY_DIRS)
		elif spd > 4.0:
			frame = Gfx.frame_for_angle(vel.angle(), Gfx.ENEMY_DIRS)
		_frame_of[id] = frame
		_last_frame[kind] = frame
		var row: int = 0
		var step: int = 3 if spd > SimWorld.ENEMY_SPEED[kind] * 1.6 else 6
		var walk: int = ((world.tick + id * 3) / step) % 4 if spd > 3.0 else 0
		var fl: float = _flash(sim_p, SimWorld.ENEMY_RADIUS[kind] + 4.0)
		match kind:
			SimWorld.BOSS_A:
				tripod_n += 1
				row = walk
				var since_fire: int = world.tick - _last_shell_tick
				if since_fire >= 0 and since_fire < FIRE_HOLD:
					row = ROW_FIRE
					wind = 1.0
				else:
					var to_volley: int = _ticks_to_volley(id)
					if to_volley <= AIM_LEAD:
						row = ROW_AIM
						wind = 1.0 - float(to_volley) / float(AIM_LEAD)
				_tripod.add(p, frame, row, fl)
			SimWorld.BOSS_B:
				row = walk
				if spd > CHARGE_SPEED_MIN:
					row = ROW_WINDUP1
					wind = 1.0
				elif wind > 0.0:
					row = ROW_WINDUP0 if wind < 0.5 else ROW_WINDUP1
				elif (world.tick >= phase_tick and world.tick - phase_tick < 14) or _recovering(id):
					row = ROW_HURT
				_colossus.add(p, frame, row, fl)
			_:
				row = ((world.tick + id * 5) / 4) % 2 if spd > 3.0 else 0
				_minion.add(p, frame, row, fl)
		_bodies.append([kind, p, id, frame, row, wind])
	_tripod.finish()
	_colossus.finish()
	_minion.finish()


## Ticks to the Queen's next volley: exact on the host (its attack state), else predicted from the last
## volley and the cadence (clients and screenshots see the same aim beat).
func _ticks_to_volley(id: int) -> int:
	var st: Dictionary = world.boss_ents.get(id, {})
	if not st.is_empty():
		return int(st.get("cd", 999))
	var period: int = Bosses._cd(world, Bosses.VOLLEY_TICKS_P3 if world.boss_phase >= 3 else Bosses.VOLLEY_TICKS)
	var from: int = _last_shell_tick if _last_shell_tick > spawn_tick else spawn_tick
	var first: int = 90 if from == spawn_tick else period
	return from + first - world.tick


## Host: the Colossus recoils after a charge (clients see the recoil at phase changes only).
func _recovering(id: int) -> bool:
	var st: Dictionary = world.boss_ents.get(id, {})
	return not st.is_empty() and int(st.get("mode", 0)) == Bosses.M_RECOVER


## The wind-up (0..1) of the body at `p`: a ring or charge marker on it. Markers carry no enemy id on clients,
## so they are matched by position (a ring marker follows the body, a charge starts where it stands).
func _windup(p: Vector2, kind: int) -> float:
	if kind == SimWorld.BOSS_A:
		return 0.0
	var best: float = 0.0
	for m: Dictionary in world.boss_marks:
		var k: int = int(m["k"])
		if k == Bosses.MARK_SHELL or (m["pos"] as Vector2).distance_squared_to(p) > 24.0 * 24.0:
			continue
		best = maxf(best, 1.0 - float(m["left"]) / maxf(float(m["total"]), 1.0))
	return best


func _mark_for(p: Vector2, k: int) -> Dictionary:
	for m: Dictionary in world.boss_marks:
		if int(m["k"]) == k and (m["pos"] as Vector2).distance_squared_to(p) <= 24.0 * 24.0:
			return m
	return {}


## Hit flash: any hit of this tick on the body (WorldView registers hits in 24 px cells and their 8 neighbours).
func _flash(p: Vector2, r: float) -> float:
	if view._hit_cells.is_empty():
		return 0.0
	var c := Vector2i(floori(p.x / WorldView.HIT_CELL), floori(p.y / WorldView.HIT_CELL))
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var hits: Variant = view._hit_cells.get(Vector2i(c.x + dx, c.y + dy))
			if hits == null:
				continue
			for q: Vector2 in (hits as PackedVector2Array):
				if q.distance_squared_to(p) <= r * r:
					return FLASH
	return 0.0


## True for an alien projectile flying at the Colossus' ring speed (spitter acid is much faster).
static func is_ring_shard(w: SimWorld, i: int) -> bool:
	return w.proj_owner[i] < 0 and absf(w.proj_vel[i].length() - Bosses.RING_SPEED) < SHARD_SPEED_TOL


func _update_shards(lead: float) -> void:
	_shards.begin(0)
	_shard_pos.clear()
	for i in world.proj_count:
		if not is_ring_shard(world, i):
			continue
		var vel: Vector2 = world.proj_vel[i]
		var p: Vector2 = world.proj_pos[i] + vel * lead
		_shards.add(p, Gfx.frame_for_angle(vel.angle(), Gfx.FX_DIRS))
		_shard_pos.append(Gfx.snap(p))
	_shards.finish()


# ---------------------------------------------------------------- ground: telegraphs, churn, shell shadows

func _draw_ground() -> void:
	if world == null:
		return
	if world.boss_state == Bosses.ST_WARNED:
		_draw_churn(world.boss_spawn_pos, 1.0 - float(world.boss_warn_left) / float(Bosses.WARN_TICKS))
	for m: Dictionary in world.boss_marks:
		var done: float = 1.0 - float(m["left"]) / maxf(float(m["total"]), 1.0)
		match int(m["k"]):
			Bosses.MARK_SHELL:
				_draw_shell_mark(m, done)
			Bosses.MARK_CHARGE:
				_draw_lane(m, done)
			Bosses.MARK_RING:
				_draw_ring_mark(m, done)
	for m in _moments:  # craters left by the spawn and the burrow: a darker dithered bowl that fades
		var t: float = _since(int(m["tick"]))
		if m["type"] == "spawn" or m["type"] == "retreat":
			var f: float = clampf(t / float(LIFE[m["type"]]), 0.0, 1.0)
			_dither_disc(_ground, m["pos"], 34.0 + 10.0 * minf(t * 4.0, 1.0), Color(Gfx.SAND[0], 0.55 * (1.0 - f)), 3)


## Shell landing circle: the art's ring fills in as the round falls (frame 0..5), a bright sweep counts the
## time down around it, the crosshair tightens, and it blinks just before impact.
func _draw_shell_mark(m: Dictionary, done: float) -> void:
	var p: Vector2 = Gfx.snap(m["pos"])
	var left: int = int(m["left"])
	var fr: int = mini(TELEGRAPH_FRAMES - 1, int(done * float(TELEGRAPH_FRAMES)))
	var cell: float = float(TEX_TELEGRAPH.get_height())
	var src := Rect2(float(fr) * cell, 0, cell, cell)
	var hot: bool = left <= 6 and (world.tick / 2) % 2 == 0
	var a: float = 1.0 if not hot else 0.55
	_ground.draw_texture_rect_region(TEX_TELEGRAPH, Rect2(p - Vector2(cell, cell) / 2.0, Vector2(cell, cell)), src, Color(1, 1, 1, a))
	var r: float = cell / 2.0 - 3.0
	# countdown sweep just outside the rim, clockwise from the top, with a dark under-edge to read on sand
	var n: int = int(TAU * (r + 2.0))
	var lit: int = int(float(n) * done)
	for i in lit:
		var ang: float = -PI / 2.0 + TAU * float(i) / float(n)
		var q: Vector2 = Gfx.snap(p + Vector2(cos(ang), sin(ang)) * (r + 2.0))
		_ground.draw_rect(Rect2(q + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.35))
		_ground.draw_rect(Rect2(q, Vector2.ONE), Gfx.GLOW[5] if i > lit - 6 else Gfx.GLOW[4])
	# crosshair brackets closing in on the impact point
	var g: float = floorf(lerpf(r * 0.55, 6.0, done))
	for k in 4:
		var dir: Vector2 = Vector2.from_angle(float(k) * PI / 2.0)
		var side: Vector2 = dir.orthogonal()
		var c: Vector2 = p + dir * g
		for s in range(-3, 4):
			_ground.draw_rect(Rect2(Gfx.snap(c + side * float(s)), Vector2.ONE), Color(Gfx.GLOW[4] if not hot else Gfx.GLOW[5], 0.9))
		_ground.draw_rect(Rect2(Gfx.snap(c - dir), Vector2.ONE), Color(Gfx.GLOW[4], 0.9))


## The Colossus is about to charge: a dithered cyan lane from the body to the end point, denser as the charge
## nears, solid edges, chevrons running toward the end, a stop bar where it lands.
func _draw_lane(m: Dictionary, done: float) -> void:
	var a: Vector2 = m["pos"]
	var b: Vector2 = m["pos2"]
	var dir: Vector2 = (b - a).normalized()
	var side: Vector2 = dir.orthogonal()
	var w: float = float(m["r"])
	var left: int = int(m["left"])
	var hot: bool = left <= 8 and (world.tick / 2) % 2 == 0
	var level: int = 4 if hot else clampi(int(done * 4.0), 0, 3)
	var poly := PackedVector2Array([a + side * w, b + side * w, b - side * w, a - side * w])
	var uv := PackedVector2Array()
	for q in poly:
		uv.append(q / 4.0)
	_ground.draw_colored_polygon(poly, Color(Gfx.GLOW[3], 0.55 + 0.3 * done), uv, _dither[level])
	for s: float in [w, -w]:  # solid edges with a dark outer line
		_ground.draw_line(Gfx.snap(a + side * (s + signf(s))), Gfx.snap(b + side * (s + signf(s))), Color(Gfx.OUTLINE, 0.4), 1.0)
		_ground.draw_line(Gfx.snap(a + side * s), Gfx.snap(b + side * s), Gfx.GLOW[4] if not hot else Gfx.GLOW[5], 1.0)
	var length: float = a.distance_to(b)
	var off: float = fmod(float(world.tick) * 2.5, 22.0)
	var s2: float = 24.0 + off
	while s2 < length - 8.0:
		var c: Vector2 = a + dir * s2
		var arm: float = w * 0.55
		for sg: float in [1.0, -1.0]:
			var tail: Vector2 = c - dir * arm * 0.8 + side * arm * sg
			_ground.draw_line(Gfx.snap(tail + Vector2(0, 1)), Gfx.snap(c + Vector2(0, 1)), Color(Gfx.OUTLINE, 0.35), 1.0)
			_ground.draw_line(Gfx.snap(tail), Gfx.snap(c), Gfx.GLOW[5], 1.0)
		s2 += 22.0
	_ground.draw_line(Gfx.snap(b + side * (w + 3.0)), Gfx.snap(b - side * (w + 3.0)), Gfx.GLOW[5], 2.0)


## Ring wind-up on the ground: a dotted ring around the body that swells as the shards are about to fly.
func _draw_ring_mark(m: Dictionary, done: float) -> void:
	var p: Vector2 = Gfx.snap(m["pos"])
	var r: float = float(m["r"]) + 4.0 + 10.0 * done
	var n: int = int(TAU * r / 3.0)
	var spin: int = world.tick / 2
	for i in n:
		if (i + spin) % 3 == 0:
			continue
		var ang: float = TAU * float(i) / float(n)
		var q: Vector2 = Gfx.snap(p + Vector2(cos(ang), sin(ang) * 0.85) * r)
		_ground.draw_rect(Rect2(q + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.3))
		_ground.draw_rect(Rect2(q, Vector2.ONE), Color(Gfx.GLOW[4], 0.4 + 0.6 * done))


## Before the spawn: the sand churns where the boss will come up (a darkening bowl, hopping grains, cyan
## glints from below) and grows as it nears.
func _draw_churn(c: Vector2, p: float) -> void:
	if not view._on_screen(c):
		return
	var r: float = 18.0 + 26.0 * p
	_dither_disc(_ground, c, r, Color(Gfx.SAND[0], 0.25 + 0.4 * p), 1 + int(p * 2.0))
	for k in 18:  # grains hop out of the bowl, staggered
		var ph: int = (world.tick + k * 7) % 20
		var f: float = float(ph) / 20.0
		var ang: float = float(k) * 2.4
		var q: Vector2 = c + Vector2(cos(ang), sin(ang) * 0.8) * (r * 0.4 + f * r * 0.7) - Vector2(0, 10.0 * 4.0 * f * (1.0 - f) * (0.5 + p))
		_ground.draw_rect(Rect2(Gfx.snap(q) + Vector2(0, 1), Vector2(2, 1)), Color(Gfx.OUTLINE, 0.4))
		_ground.draw_rect(Rect2(Gfx.snap(q), Vector2(2, 1)), Gfx.SAND[4] if k % 2 == 0 else Gfx.SAND[3])
	var glints: int = int(4.0 + 14.0 * p)
	for k in glints:
		var hh: int = Gfx.hash_pos(c, k * 31 + (world.tick / 3) * 7)
		var ang2: float = float(hh % 628) / 100.0
		var q2: Vector2 = c + Vector2(cos(ang2), sin(ang2) * 0.8) * float((hh / 628) % int(r))
		_ground.draw_rect(Rect2(Gfx.snap(q2), Vector2.ONE), Gfx.GLOW[4] if hh % 3 else Gfx.GLOW[5])


## A filled disc in an ordered dither (crisp pixels whatever the size).
func _dither_disc(ci: CanvasItem, c: Vector2, r: float, col: Color, level: int) -> void:
	var n: int = maxi(int(r * 0.9), 12)
	var poly := PackedVector2Array()
	var uv := PackedVector2Array()
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var q: Vector2 = c + Vector2(cos(a), sin(a) * 0.85) * r
		poly.append(q)
		uv.append(q / 4.0)
	ci.draw_colored_polygon(poly, col, uv, _dither[clampi(level, 0, 4)])


# ---------------------------------------------------------------- over: shells in flight, moments

func _draw_over() -> void:
	if world == null:
		return
	_shell_pos.clear()
	_draw_shells()
	for m in _moments:
		var t: float = _since(int(m["tick"]))
		if t < 0.0:
			continue
		match str(m["type"]):
			"spawn":
				_m_spawn(m, t)
			"phase":
				_m_phase(m, t)
			"split":
				_m_split(m, t)
			"kill":
				_m_kill(m, t)
			"retreat":
				_m_retreat(m, t)
			"blast":
				_m_blast(m, t)
			"ring":
				_cyan_ring(_over, m["pos"], 30.0 + 60.0 * t / 0.4, 1.0 - t / 0.4)
			"brood":
				var rng := _rng(m)
				_spray(rng, m["pos"], t, 10, 30.0, 70.0, 2.0, 8.0, 0.35, 0.55, P_GOO, 0.0)
				_spray(rng, m["pos"], t, 6, 25.0, 55.0, 4.0, 10.0, 0.4, 0.6, P_PLATE, 0.0)
			"shard_death":
				var rng2 := _rng(m)
				_spray(rng2, m["pos"], t, 34, 40.0, 120.0, 4.0, 16.0, 0.5, 0.95, P_GLASS, 0.0)
				_spray(rng2, m["pos"], t, 12, 30.0, 80.0, 2.0, 8.0, 0.3, 0.5, P_GOO, 0.0)
				_cyan_ring(_over, m["pos"], 14.0 + 50.0 * minf(t / 0.5, 1.0), 1.0 - t / 0.5)
			"charge":
				var rng3 := _rng(m)
				_spray(rng3, m["pos"], t, 14, 20.0, 60.0, 2.0, 6.0, 0.3, 0.5, P_SAND, 0.0)


func _rng(m: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(m["seed"])
	return rng


## Mortar rounds in flight: from the Queen's sac up over the field and down onto their marker; scaled up near
## the top of the arc, a shadow sliding along the ground under them.
func _draw_shells() -> void:
	var from := Vector2.INF
	for b: Array in _bodies:
		if int(b[0]) == SimWorld.BOSS_A:
			from = (b[1] as Vector2) + Vector2(0, -6)
	if from == Vector2.INF:
		return
	for m: Dictionary in world.boss_marks:
		if int(m["k"]) != Bosses.MARK_SHELL:
			continue
		var total: float = maxf(float(m["total"]), 1.0)
		var t: float = clampf((total - float(m["left"]) + (0.0 if view.frozen else view._tick_age / SimWorld.DT)) / total, 0.0, 1.0)
		var to: Vector2 = m["pos"]
		var dist: float = from.distance_to(to)
		var hgt: float = clampf(50.0 + dist * 0.45, 60.0, 190.0)
		var ground: Vector2 = from.lerp(to, t)
		var lift: float = hgt * 4.0 * t * (1.0 - t)
		var p: Vector2 = Gfx.snap(ground - Vector2(0, lift))
		var slope: float = hgt * 4.0 * (1.0 - 2.0 * t)
		var vel: Vector2 = (to - from) - Vector2(0, slope)
		var frame: int = Gfx.frame_for_angle(vel.angle(), Gfx.FX_DIRS)
		# shadow on the ground (drawn here, under the shell, small and faint while it is high)
		var sh: float = 1.0 - lift / hgt
		var sw: float = 3.0 + 4.0 * sh
		_over.draw_rect(Rect2(Gfx.snap(ground) - Vector2(sw, 1.0), Vector2(sw * 2.0, 3.0)), Color(Gfx.SHADOW, 0.25 + 0.35 * sh))
		var big: bool = t > 0.22 and t < 0.78
		var cell: float = 16.0
		var size: float = cell * (2.0 if big else 1.0)
		var src := Rect2(float(frame) * cell, 0, cell, cell)
		_over.draw_texture_rect_region(TEX_SHELL, Rect2(p - Vector2(size, size) / 2.0, Vector2(size, size)), src)
		_shell_pos.append(p)


func _draw_glow() -> void:
	if world == null:
		return
	var hs := Vector2(Gfx.TEX_HALO_CYAN.get_size())
	for p in _shard_pos:
		_glow.draw_texture_rect(Gfx.TEX_HALO_CYAN, Rect2(p - hs / 2.0, hs), false, Color(1, 1, 1, 0.45))
	for b: Array in _bodies:  # wind-ups light the body from inside; phase 3 / enraged bodies pulse
		var kind: int = int(b[0])
		var p: Vector2 = b[1]
		var wind: float = float(b[5])
		var base: float = 0.0
		if world.boss_phase >= 3 or world.boss_enraged:
			base = 0.12 + 0.08 * sin(float(world.tick) * 0.25)
		var k: float = maxf(base, wind)
		if k <= 0.01:
			continue
		var r: float = SimWorld.ENEMY_RADIUS[kind] * (0.7 + 0.5 * wind)
		_banded(_glow, p + (Vector2(0, -4) if kind == SimWorld.BOSS_A else Vector2.ZERO), r, 0.55 * k)
	for m: Dictionary in world.boss_marks:  # the round about to land: the marker glows up in its last moments
		if int(m["k"]) == Bosses.MARK_SHELL and int(m["left"]) < 12:
			_banded(_glow, m["pos"], 22.0, 0.25 * (1.0 - float(m["left"]) / 12.0))
	for m in _moments:
		var t: float = _since(int(m["tick"]))
		var pos: Vector2 = m["pos"]
		match str(m["type"]):
			"spawn":
				if t < 0.4:
					_banded(_glow, pos, 46.0, 0.6 * (1.0 - t / 0.4))
			"phase":
				if t < 0.5:
					_banded(_glow, pos, 50.0 + 30.0 * t, 0.85 * (1.0 - t / 0.5))
			"split":
				if t < 0.7:
					_banded(_glow, pos, 70.0 + 40.0 * t, 1.0 - t / 0.7)
			"kill":
				var d0: float = float((_kill_stages(m)[3] as Array)[0])
				if t < d0:
					var info: Array = _sheet_of(int(m.get("body", SimWorld.BOSS_A)))
					var cell: float = info[2]
					var row: int = ROW_FIRE if int(m.get("body", 0)) == SimWorld.BOSS_A else 0
					var src := Rect2(float(int(m.get("frame", 8))) * cell, float(row) * cell, cell, cell)
					_glow.draw_texture_rect_region(info[1], Rect2(Gfx.snap(pos) - Vector2(cell, cell) / 2.0, Vector2(cell, cell)), src,
						Color(1, 1, 1, 0.6 + 0.4 * t / d0))
				for s in _kill_stages(m):
					var st: float = t - float(s[0])
					if st >= 0.0 and st < 0.45:
						_banded(_glow, pos + (s[1] as Vector2), float(s[2]) * (0.8 + st), (1.0 - st / 0.45) * (1.2 if s[2] > 50.0 else 0.8))
			"blast":
				if t < 0.3:
					_banded(_glow, pos, 34.0, 0.9 * (1.0 - t / 0.3))
			"ring":
				if t < 0.25:
					_banded(_glow, pos, 46.0, 0.6 * (1.0 - t / 0.25))
			"shard_death":
				if t < 0.3:
					_banded(_glow, pos, 34.0, 0.8 * (1.0 - t / 0.3))
	for p2 in _shell_pos:  # the rounds in flight carry their own light
		_glow.draw_texture_rect(Gfx.TEX_HALO_CYAN, Rect2(p2 - hs, hs * 2.0), false, Color(1, 1, 1, 0.55))


## Posterised additive glow: three hard-edged discs (outer teal, mid cyan, white-cyan core).
func _banded(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	if a <= 0.0:
		return
	var p: Vector2 = Gfx.snap(c)
	ci.draw_circle(p, r, Color(Gfx.GLOW[1], 0.16 * a))
	ci.draw_circle(p, r * 0.62, Color(Gfx.GLOW[2], 0.2 * a))
	ci.draw_circle(p, r * 0.3, Color(Gfx.GLOW[4], 0.32 * a))


## A thin cyan shock ring (1 px, squashed for the top-down tilt, dark inner edge so it reads on sand).
func _cyan_ring(ci: CanvasItem, c: Vector2, r: float, a: float) -> void:
	if a <= 0.0:
		return
	var n: int = maxi(int(r * 2.2), 16)
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		var dir := Vector2(cos(ang), sin(ang) * 0.85)
		ci.draw_rect(Rect2(Gfx.snap(c + dir * (r - 1.0)), Vector2.ONE), Color(Gfx.OUTLINE, 0.35 * a))
		ci.draw_rect(Rect2(Gfx.snap(c + dir * r), Vector2.ONE), Color(Gfx.GLOW[5] if i % 3 == 0 else Gfx.GLOW[4], a))


# ---------------------------------------------------------------- moments

func _m_spawn(m: Dictionary, t: float) -> void:
	var rng := _rng(m)
	var pos: Vector2 = m["pos"]
	_spray(rng, pos, t, 70, 40.0, 150.0, 10.0, 46.0, 0.8, 1.5, P_SAND, 0.0)
	_spray(rng, pos, t, 40, 15.0, 45.0, 0.0, 0.0, 1.0, 1.7, P_DUST, 0.05)
	_spray(rng, pos, t, 10, 30.0, 80.0, 6.0, 20.0, 0.5, 0.8, P_GOO, 0.0)
	_sand_ring(pos, 20.0 + 110.0 * minf(t / 0.7, 1.0), 1.0 - t / 0.9)
	if t < 0.6:  # sand still pours off the body as it surfaces: a mound thinning out
		var lv: int = 4 - int(t / 0.6 * 5.0)
		_dither_disc(_over, pos, 40.0 - 10.0 * t, Gfx.SAND[3], lv)
		_dither_disc(_over, pos + Vector2(-3, -3), 24.0, Gfx.SAND[4], lv - 1)


func _m_phase(m: Dictionary, t: float) -> void:
	var pos: Vector2 = m["pos"]
	for k in 3:  # the roar: three rings rolling out
		var st: float = t - float(k) * 0.12
		if st > 0.0 and st < 0.6:
			_cyan_ring(_over, pos, 30.0 + 120.0 * st, 1.0 - st / 0.6)
	_sand_ring(pos, 40.0 + 90.0 * minf(t / 0.8, 1.0), 0.8 - t)
	var rng := _rng(m)
	_spray(rng, pos, t, 22, 30.0, 90.0, 0.0, 0.0, 0.6, 1.0, P_DUST, 0.0)


func _m_split(m: Dictionary, t: float) -> void:
	var rng := _rng(m)
	var pos: Vector2 = m["pos"]
	if t < 0.1:
		_corpse(m, t, 0.1)
	_spray(rng, pos, t, 110, 50.0, 190.0, 6.0, 34.0, 0.7, 1.5, P_GLASS, 0.0)
	_spray(rng, pos, t, 30, 40.0, 110.0, 2.0, 10.0, 0.4, 0.7, P_GOO, 0.0)
	_spray(rng, pos, t, 30, 15.0, 50.0, 0.0, 0.0, 0.9, 1.5, P_DUST, 0.1)
	for k in 2:
		var st: float = t - float(k) * 0.15
		if st > 0.0 and st < 0.7:
			_cyan_ring(_over, pos, 26.0 + 150.0 * st, 1.0 - st / 0.7)
	if t < 0.12:  # the instant it shatters: a white-cyan star
		_star(pos, 26, Gfx.GLOW[5])


## The stages of the death: [delay s, offset, flash radius]. Three sacs rupture over half a second, then the
## body goes in one big burst.
func _kill_stages(m: Dictionary) -> Array:
	var h: int = int(m["seed"])
	var out: Array = []
	for k in 3:
		var a: float = float((h >> (k * 3)) % 628) / 100.0
		out.append([0.18 * float(k), Vector2.from_angle(a) * (14.0 + float(k) * 6.0), 26.0])
	out.append([0.62, Vector2.ZERO, 64.0])
	return out


func _m_kill(m: Dictionary, t: float) -> void:
	var pos: Vector2 = m["pos"]
	var crystal: bool = int(m["kind"]) != SimWorld.BOSS_A
	var rng := _rng(m)
	var stages: Array = _kill_stages(m)
	var d0: float = float((stages[3] as Array)[0])
	if t < d0:  # death throes: the body shakes and flashes white while the sacs burst
		_corpse(m, t, d0)
	for s in stages:  # every stage: a star of light, a goo spray, a ring
		var st: float = t - float(s[0])
		var sp: Vector2 = pos + (s[1] as Vector2)
		var big: bool = float(s[2]) > 50.0
		if st >= 0.0 and st < 0.1:
			_star(sp, 30 if big else 16, Gfx.GLOW[5])
		if st >= 0.0 and st < 0.55:
			_cyan_ring(_over, sp, (20.0 if big else 8.0) + (170.0 if big else 50.0) * st, 1.0 - st / 0.55)
		_spray(rng, sp, t, 18 if big else 12, 40.0, 130.0 if big else 90.0, 4.0, 14.0, 0.4, 0.7, P_GOO, float(s[0]))
	var d: float = d0
	# the final burst: the shell / the glass flies, dust rolls out, scrap fountains up and rains down
	var td: float = t - d
	if td >= 0.0 and td < 0.12:
		_star(pos, 44, Gfx.GLOW[5])
	_spray(rng, pos, t, 80, 30.0, 150.0, 8.0, 40.0, 0.9, 1.7, P_GLASS if crystal else P_PLATE, d)
	_spray(rng, pos, t, 30, 40.0, 140.0, 6.0, 26.0, 0.7, 1.2, P_GLASS, d)
	_spray(rng, pos, t, 60, 18.0, 60.0, 0.0, 0.0, 1.3, 1.9, P_DUST, d)
	_spray(rng, pos, t, 50, 15.0, 80.0, 50.0, 110.0, 1.3, 1.9, P_SCRAP, d + 0.05)
	_sand_ring(pos, 30.0 + 150.0 * clampf((t - d) / 0.9, 0.0, 1.0), 1.0 - (t - d) / 1.1 if t > d else 0.0)


## The dying (or splitting) body: its sprite shaking and strobing white, its sacs blazing (the glow pass adds the
## glow sheet), until the burst at `until` s.
func _corpse(m: Dictionary, t: float, until: float) -> void:
	var body: int = int(m.get("body", SimWorld.BOSS_A))
	var info: Array = _sheet_of(body)
	var tex: Texture2D = info[0]
	var cell: float = info[2]
	var row: int = 0
	match body:
		SimWorld.BOSS_A:
			row = ROW_FIRE if int(t * 20.0) % 2 == 0 else ROW_AIM
		SimWorld.BOSS_B:
			row = ROW_HURT
	var jit := Vector2(float(int(t * 60.0) % 3 - 1), float(int(t * 45.0) % 3 - 1))
	var src := Rect2(float(int(m.get("frame", 8))) * cell, float(row) * cell, cell, cell)
	var hot: float = 1.0 + 0.9 * (t / until) * float(int(t * 30.0) % 2)
	_over.draw_texture_rect_region(tex, Rect2(Gfx.snap(m["pos"]) - Vector2(cell, cell) / 2.0 + jit, Vector2(cell, cell)), src, Color(hot, hot, hot))


## [sheet, glow sheet, cell px] of a boss body kind.
func _sheet_of(kind: int) -> Array:
	match kind:
		SimWorld.BOSS_A:
			return [TEX_TRIPOD, TEX_TRIPOD_GLOW, 128.0]
		SimWorld.BOSS_B:
			return [TEX_COLOSSUS, TEX_COLOSSUS_GLOW, 128.0]
	return [TEX_MINION, TEX_MINION_GLOW, 48.0]


func _m_retreat(m: Dictionary, t: float) -> void:
	var pos: Vector2 = Gfx.snap(m["pos"])
	var kind: int = int(m["kind"])
	var f: float = clampf(t / 1.2, 0.0, 1.0)
	if f < 1.0 and kind >= SimWorld.BOSS_A:  # the body sinks into the sand: drawn lower and fading, a mound over it
		var tex: Texture2D = TEX_TRIPOD if kind == SimWorld.BOSS_A else TEX_COLOSSUS
		var cell: float = 128.0
		var src := Rect2(8.0 * cell, 0, cell, cell * (1.0 - 0.6 * f))
		var dst := Rect2(pos - Vector2(cell / 2.0, cell / 2.0 - floorf(18.0 * f)), Vector2(cell, cell * (1.0 - 0.6 * f)))
		_over.draw_texture_rect_region(tex, dst, src, Color(1, 1, 1, 1.0 - f))
	var rng := _rng(m)
	_spray(rng, pos, t, 50, 30.0, 110.0, 6.0, 28.0, 0.7, 1.3, P_SAND, 0.0)
	_spray(rng, pos, t, 40, 10.0, 40.0, 0.0, 0.0, 1.0, 1.7, P_DUST, 0.0)
	_spray(rng, pos, t, 40, 10.0, 40.0, 0.0, 0.0, 1.0, 1.7, P_DUST, 0.5)


func _m_blast(m: Dictionary, t: float) -> void:
	var rng := _rng(m)
	var pos: Vector2 = m["pos"]
	if t < 0.08:
		_star(pos, 18, Gfx.GLOW[5])
	_cyan_ring(_over, pos, 10.0 + 60.0 * minf(t / 0.35, 1.0), 1.0 - t / 0.35)
	_spray(rng, pos, t, 26, 40.0, 120.0, 6.0, 30.0, 0.5, 0.8, P_SAND, 0.0)
	_spray(rng, pos, t, 16, 50.0, 130.0, 4.0, 12.0, 0.3, 0.55, P_GOO, 0.0)
	_spray(rng, pos, t, 10, 30.0, 70.0, 3.0, 10.0, 0.4, 0.7, P_GLASS, 0.0)


func _sand_ring(c: Vector2, r: float, a: float) -> void:
	if a <= 0.0:
		return
	var n: int = maxi(int(r * 1.6), 16)
	for i in n:
		var ang: float = TAU * float(i) / float(n)
		var dir := Vector2(cos(ang), sin(ang) * 0.85)
		_over.draw_rect(Rect2(Gfx.snap(c + dir * r), Vector2.ONE), Color(Gfx.SAND[5], a))
		if i % 2 == 0:
			_over.draw_rect(Rect2(Gfx.snap(c + dir * (r - 2.0)), Vector2.ONE), Color(Gfx.SAND[4], 0.8 * a))
		if i % 3 == 0:
			_over.draw_rect(Rect2(Gfx.snap(c + dir * (r - 4.0 - float(i % 4))), Vector2.ONE), Color(Gfx.SAND[3], 0.6 * a))


## A splat star of light: a core and four arms.
func _star(c: Vector2, size: int, col: Color) -> void:
	var p: Vector2 = Gfx.snap(c)
	var h: float = float(size / 2)
	_over.draw_rect(Rect2(p - Vector2(h, 0), Vector2(size, 1)), col)
	_over.draw_rect(Rect2(p - Vector2(0, h), Vector2(1, size)), col)
	var q: float = float(maxi(size / 4, 2))
	_over.draw_rect(Rect2(p - Vector2(q, q), Vector2(q * 2.0 + 1.0, q * 2.0 + 1.0)), Gfx.GLOW[4])
	_over.draw_rect(Rect2(p - Vector2(q, q) * 0.5, Vector2(q + 1.0, q + 1.0)), col)


## `n` particles of `style` thrown from `o`, `delay` s after the moment: analytic (launch speed vmin..vmax,
## hop height, life), so every frame and every screenshot of the same moment agrees. Uses `rng` in sequence.
func _spray(rng: RandomNumberGenerator, o: Vector2, t: float, n: int, vmin: float, vmax: float, hmin: float, hmax: float,
		lmin: float, lmax: float, style: int, delay: float) -> void:
	for i in n:
		var a: float = rng.randf() * TAU
		var sp: float = rng.randf_range(vmin, vmax)
		var hop: float = rng.randf_range(hmin, hmax)
		var life: float = rng.randf_range(lmin, lmax)
		var sz: int = 1 + rng.randi() % 3
		var shade: int = rng.randi() % 4
		var tau: float = t - delay - float(i % 5) * 0.012
		if tau < 0.0 or tau >= life:
			continue
		var f: float = tau / life
		var v := Vector2(cos(a), sin(a) * 0.8) * sp
		var p: Vector2 = o + v * tau * (1.0 - 0.5 * f)
		if style == P_DUST:
			p.y -= 10.0 * f
		if hop > 0.0:
			var land: float = minf(f / 0.7, 1.0)
			p.y -= hop * 4.0 * land * (1.0 - land)
		var fade: float = 1.0 if f < 0.75 else clampf((1.0 - f) * 4.0, 0.0, 1.0)
		_part(Gfx.snap(p), style, sz, shade, f, fade)


func _part(p: Vector2, style: int, sz: int, shade: int, f: float, a: float) -> void:
	match style:
		P_SAND:
			var w: float = float(mini(sz, 2))
			_over.draw_rect(Rect2(p + Vector2(0, 1), Vector2(w, 1)), Color(Gfx.OUTLINE, 0.6 * a))
			_over.draw_rect(Rect2(p, Vector2(w, 1)), Color(Gfx.SAND[3 + shade % 3], a))
		P_PLATE:  # chitin chips: lit top-left, a dark underside (light from the top left)
			var w2: float = float(2 + sz % 2)
			var h2: float = float(1 + shade % 2)
			_chip(p, w2, h2, CHITIN[2 + shade % 3], CHITIN[5], a)
		P_GLASS:  # glass shards: lit cyan from inside while fresh, then plain salt glass
			var w3: float = float(1 + sz % 3)
			var h3: float = float(1 + shade % 2)
			if f < 0.2:
				_chip(p, w3, h3, Gfx.GLOW[4], Gfx.GLOW[5], a)
			else:
				_chip(p, w3, h3, GLASS[shade % 3], GLASS[3], a)
		P_GOO:
			var c: Color = Gfx.GLOW[4] if f < 0.3 else (Gfx.GLOW[3] if f < 0.6 else Gfx.GLOW[1])
			_over.draw_rect(Rect2(p, Vector2(float(mini(sz, 2)), float(mini(sz, 2)))), Color(c, a))
		P_SCRAP:  # warm scrap: steel, rust and brass bits, a glint twinkling on the brass
			var cols: Array[Color] = [Gfx.STEEL[3], RUST, Gfx.BRASS[3], Gfx.STEEL[4]]
			_chip(p, float(2 + sz % 2), 1.0 + float(shade % 2), cols[shade], Gfx.STEEL[5] if shade != 1 else Gfx.FIRE[3], a)
			if shade == 2 and int(f * 24.0) % 3 == 0:
				_over.draw_rect(Rect2(p + Vector2(1, -1), Vector2.ONE), Color(Gfx.FIRE[6], a))
				_over.draw_rect(Rect2(p + Vector2(0, -2), Vector2(3, 1)), Color(Gfx.FIRE[5], 0.6 * a))
		P_DUST:
			_over.draw_rect(Rect2(p, Vector2(float(mini(sz, 2)), 1)), Color(Gfx.SAND[5] if shade % 2 == 0 else Gfx.SAND[4], 0.8 * a))


## A w x h chip of `fill` with a lit top-left pixel and a dark underside and right edge.
func _chip(p: Vector2, w: float, h: float, fill: Color, lit: Color, a: float) -> void:
	_over.draw_rect(Rect2(p + Vector2(1, h), Vector2(w, 1)), Color(Gfx.OUTLINE, 0.85 * a))
	_over.draw_rect(Rect2(p + Vector2(w, 1), Vector2(1, h - 1.0 if h > 1.0 else 1.0)), Color(Gfx.OUTLINE, 0.85 * a))
	_over.draw_rect(Rect2(p, Vector2(w, h)), Color(fill, a))
	_over.draw_rect(Rect2(p, Vector2.ONE), Color(lit, a))
