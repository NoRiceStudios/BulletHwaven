class_name CombatFx
extends Node2D
## Tech tree v2.3 combat look ("Sichtbar als", docs/architecture.md "Combat visuals"): burning aliens,
## fire / ember / oil / smoke ground zones, flamer streams, hot and jammed barrels, nitro jets, the
## repair drone, the scrap baron's chain, swarm-logic and rangefinder lasers, spitter warnings, stun
## crackle, jammer static and contract banners. Reads the SimWorld and the WorldView's display state
## every frame and never mutates either. Many-instance parts (flames, smoke puffs) are MultiMeshes.
## Player effects are warm (FIRE) or steel: cyan stays the aliens' colour.

const SMOKE_GREY := 0
const SMOKE_SOOT := 1
const CONTRACT_BANNERS := 6  ## at most this many contract targets carry a banner

var view: WorldView
## Filled by WorldView._update_enemies every frame (display positions, snapped).
var burn_pos: PackedVector2Array = PackedVector2Array()
var burn_meta: PackedInt32Array = PackedInt32Array()  ## kind | fresh << 3 | id << 4
var stun_pos: PackedVector2Array = PackedVector2Array()
var warn_pos: PackedVector2Array = PackedVector2Array()
var target_pos: PackedVector2Array = PackedVector2Array()  ## contract targets near the watched rig
var flamer_pos: PackedVector2Array = PackedVector2Array()  ## flamer projectiles this frame
## Evolved shots this frame (WorldView._evo_shot): Meat Grinder pellets and Inferno Spout flames, with
## their flight directions.
var grinder_pos: PackedVector2Array = PackedVector2Array()
var grinder_dir: PackedVector2Array = PackedVector2Array()
var inferno_pos: PackedVector2Array = PackedVector2Array()
var inferno_dir: PackedVector2Array = PackedVector2Array()
const CASING_TICKS := 16  ## a gatling casing flies, bounces and lies in the sand this long

var _flames: SheetLayer
var _smoke: SheetLayer
var _ground: Node2D
var _deco: Node2D
var _over: Node2D
var _glow: Node2D
var _stamped: Dictionary = {}  ## fire zones already burnt into the decal layer
var _tick: int = 0


func _ready() -> void:
	_ground = _node(Gfx.Z_RING, _draw_ground)
	_flames = SheetLayer.new()
	add_child(_flames)
	_flames.setup(Gfx.TEX_FLAME, 8, 3, Gfx.Z_FIRE, Gfx.TEX_FLAME_GLOW, Vector2.ZERO, 0.55)
	_smoke = SheetLayer.new()
	add_child(_smoke)
	_smoke.setup(Gfx.TEX_SMOKE, 8, 2, Gfx.Z_EFFECTS)
	_deco = _node(Gfx.Z_RIG_DECO, _draw_deco)
	_over = _node(Gfx.Z_EFFECTS, _draw_over)
	_glow = _node(Gfx.Z_GLOW, _draw_glow)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add


func _node(z: int, fn: Callable) -> Node2D:
	var n := Node2D.new()
	n.z_index = z
	n.draw.connect(fn)
	add_child(n)
	return n


func clear() -> void:
	_stamped.clear()


func begin_frame() -> void:
	burn_pos.clear()
	burn_meta.clear()
	stun_pos.clear()
	warn_pos.clear()
	target_pos.clear()
	flamer_pos.clear()
	grinder_pos.clear()
	grinder_dir.clear()
	inferno_pos.clear()
	inferno_dir.clear()


# ---------------------------------------------------------------- ammo helpers (also used by WorldView)

## Union of the ammo bits loaded in `v`'s guns.
static func rig_mask(v: SimVehicle) -> int:
	var m: int = 0
	for kind: String in v.ammo:
		m |= Ammo.mask(v, kind)
	return m


## Tracer / muzzle row for an ammo mask: with two types loaded (mixed belts) `h` picks one, so a burst
## alternates colours (two-tone belt).
static func ammo_row(mask: int, h: int) -> int:
	var rows: PackedInt32Array = PackedInt32Array()
	if mask & Ammo.FIRE_BIT:
		rows.append(Gfx.TRACER_FIRE)
	if mask & Ammo.SHRAPNEL_BIT:
		rows.append(Gfx.TRACER_SHRAPNEL)
	if mask & Ammo.AP_BIT:
		rows.append(Gfx.TRACER_AP)
	if rows.is_empty():
		return Gfx.TRACER_PLAIN
	return rows[absi(h) % rows.size()]


## Both rows of a two-type belt (or the one row twice).
static func ammo_rows(mask: int) -> PackedInt32Array:
	var a: int = ammo_row(mask, 0)
	return PackedInt32Array([a, ammo_row(mask, 1)])


# ---------------------------------------------------------------- per frame

func update(world: SimWorld) -> void:
	_tick = world.tick
	_flames.begin(burn_pos.size() * 2 + flamer_pos.size() + inferno_pos.size() * 2 + world.zone_count * 8)
	_smoke.begin(world.zone_count * 6)
	# burning aliens: flickering flames on their backs (boulders carry three), a tall flare when fresh
	for i in burn_pos.size():
		var p: Vector2 = burn_pos[i]
		var meta: int = burn_meta[i]
		var kind: int = meta & 7
		var id: int = meta >> 4
		var f: int = (_tick / 2 + id * 3) % 8
		match kind:
			SimWorld.BOULDER:
				_flame(p + Vector2(-4, 1), 1, f)
				_flame(p + Vector2(5, -2), 0, (f + 3) % 8)
			SimWorld.SPITTER:
				_flame(p + Vector2(0, 1), 1, f)
				_flame(p + Vector2(4, -1), 0, (f + 4) % 8)
			_:
				_flame(p + Vector2(0, 2), 0, f)
		if (meta >> 3) & 1:  # just caught fire (napalm jumping over): a tall flare
			_flame(p + Vector2(0, 2), 2 if kind == SimWorld.BOULDER else 1, (_tick + id) % 8)
	for i in flamer_pos.size():
		_flame(flamer_pos[i] + Vector2(0, 3), 0 if i % 3 else 1, (_tick + i * 3) % 8)
	for i in inferno_pos.size():  # Inferno Spout: a fat, tall stream, licking out to both sides
		var side: Vector2 = inferno_dir[i].orthogonal() * (3.0 if (i + _tick / 2) % 2 == 0 else -3.0)
		_flame(inferno_pos[i] + Vector2(0, 3), 2 if i % 3 == 1 else 1, (_tick + i * 3) % 8)
		_flame(Gfx.snap(inferno_pos[i] + side - inferno_dir[i] * 4.0) + Vector2(0, 3), 0 if i % 2 else 1, (_tick + i * 5 + 2) % 8)
	for zi in mini(world.zone_count, world.zone_pos.size()):
		_zone(world, zi)
	for v in world.vehicles:
		if v.alive:
			_rig_smoke(v)
	_flames.finish()
	_smoke.finish()
	_ground.queue_redraw()
	_deco.queue_redraw()
	_over.queue_redraw()
	_glow.queue_redraw()


## A flame whose foot stands at `foot`: size 0..2, frame 0..7.
func _flame(foot: Vector2, size: int, frame: int) -> void:
	_flames.add(foot - Vector2(0, Gfx.FLAME_BASE_Y), frame, size)


func _zone(world: SimWorld, zi: int) -> void:
	var kind: int = world.zone_kind[zi]
	var c: Vector2 = Gfx.snap(world.zone_pos[zi])
	var r: float = world.zone_radius[zi]
	var ttl: int = world.zone_ttl[zi]
	match kind:
		SimWorld.ZONE_FIRE:
			var key := Vector3i(int(c.x), int(c.y), kind)
			if not _stamped.has(key):  # the fire leaves burnt ground for the rest of the match
				_stamped[key] = true
				if _stamped.size() > 3000:
					_stamped.clear()
				view.stamp_decal(Gfx.TEX_BURN, 4, absi(key.x * 7 + key.y * 3) % 4, c)
			var n: int = clampi(int(r * r / 85.0), 3, 11)
			var dying: bool = ttl < 20
			for k in n:
				if dying and k % 2 == 1:
					continue
				var a: float = float(k) * 2.399963 + float(zi) * 1.3
				var d: float = r * 0.85 * sqrt((float(k) + 0.5) / float(n))
				var row: int = 0 if dying else (1 if d < r * 0.45 else 0)
				_flame(Gfx.snap(c + Vector2(cos(a) * d, sin(a) * d * 0.75)), row, (_tick / 2 + k * 3 + zi) % 8)
		SimWorld.ZONE_EMBER:  # a single small licking flame over the glowing coals (drawn on the ground)
			if ttl > 12:
				var a2: float = float(zi) * 2.4
				_flame(Gfx.snap(c + Vector2(cos(a2), sin(a2) * 0.7) * r * 0.3), 0, (_tick / 2 + zi * 3) % 8)
		SimWorld.ZONE_SMOKE:
			var o: int = world.zone_owner[zi]
			var soot: bool = r < Abilities.SMOKE_ZONE_RADIUS - 1.0 and o >= 0 and o < world.vehicles.size() \
					and float(world.vehicles[o].tech_fx.get("dirty_fuel", 0.0)) > 0.0
			var n2: int = clampi(int(r * r / 120.0), 4, 14)
			for k in n2:
				var a3: float = float(k) * 2.399963 + float(zi) * 0.7
				var d2: float = r * 0.8 * sqrt((float(k) + 0.5) / float(n2))
				var fr: int = (_tick / 5 + k * 3) % 8
				if ttl < 30:
					fr = maxi(fr, 8 - ttl / 5)
				fr = mini(fr, 7)
				_smoke.add(Gfx.snap(c + Vector2(cos(a3) * d2, sin(a3) * d2 * 0.8 - float(fr))), fr, SMOKE_SOOT if soot else SMOKE_GREY)


## Smoke from jammed / overheated barrels and a coughing nitro.
func _rig_smoke(v: SimVehicle) -> void:
	var rv: RigView = view.rig_view(v.id)
	if rv == null:
		return
	var jam_fx: bool = RigArt.fx(v, "jam")
	var hot_fx: bool = RigArt.fx(v, "overheat")
	if jam_fx or hot_fx:
		for i in mini(rv.gun_count(), v.weapons.size()):
			var w: Dictionary = v.weapons[i]
			var paused: bool = int(w.get("jam", 0)) > 0
			var heat: float = _heat(v, w)
			if not paused and heat < 0.75:
				continue
			var tip: Vector2 = rv.barrel(i)[0]
			for k in (2 if paused else 1):
				var fr: int = (_tick / 3 + k * 4 + i * 2) % 8
				_smoke.add(Gfx.snap(tip + Vector2(float(k * 3 - 1), -4.0 - float(fr) * 1.5)), fr, SMOKE_SOOT if jam_fx else SMOKE_GREY)
	if v.sputter_ticks > 0:
		for e: Vector2 in rv.exhausts():
			var fr2: int = (_tick / 2 + v.id) % 8
			_smoke.add(Gfx.snap(e + Vector2(0, -float(fr2))), fr2, SMOKE_SOOT)


## 0..1: how close weapon `w` is to its jam / overheat limit (1 while it pauses).
static func _heat(v: SimVehicle, w: Dictionary) -> float:
	var limit: int = 0
	if RigArt.fx(v, "overheat"):
		limit = SimWorld.OVERHEAT_FIRE_TICKS
	elif RigArt.fx(v, "jam"):
		limit = SimWorld.JAM_FIRE_TICKS
	if limit <= 0:
		return 0.0
	if int(w.get("jam", 0)) > 0:
		return 1.0
	return clampf(float(w.get("heat", 0)) / float(limit), 0.0, 1.0)


# ---------------------------------------------------------------- drawing

func _px(ci: CanvasItem, p: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(Gfx.snap(p), Vector2.ONE), c)


func _halo(p: Vector2, scale: float, c: Color) -> void:
	var s := Vector2(Gfx.TEX_HALO_WARM.get_size()) * scale
	_glow.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(p - s / 2.0, s), false, c)


## Ground level: oil puddles, glowing coals in fire and ember zones.
func _draw_ground() -> void:
	var w: SimWorld = view.world
	if w == null:
		return
	for zi in mini(w.zone_count, w.zone_pos.size()):
		var kind: int = w.zone_kind[zi]
		var c: Vector2 = Gfx.snap(w.zone_pos[zi])
		var fade: float = clampf(float(w.zone_ttl[zi]) / 30.0, 0.0, 1.0)
		if kind == SimWorld.ZONE_OIL:
			var src: Rect2 = Gfx.cell_rect(Gfx.TEX_OIL, 3, 1, zi % 3, 0)
			_ground.draw_texture_rect_region(Gfx.TEX_OIL, Rect2(c - src.size / 2.0, src.size), src, Color(1, 1, 1, 0.9 * fade))
		elif kind == SimWorld.ZONE_FIRE or kind == SimWorld.ZONE_EMBER:
			var r: float = w.zone_radius[zi]
			for k in 10:
				var a: float = float(k) * 2.399963 + float(zi)
				var d: float = r * 0.9 * sqrt((float(k) + 0.5) / 10.0)
				var hot: bool = (k + _tick / 4 + zi) % 3 != 0
				var cp: Vector2 = c + Vector2(cos(a) * d, sin(a) * d * 0.75)
				_px(_ground, cp, Color(Gfx.FIRE[4] if hot else Gfx.FIRE[2], fade))
				_px(_ground, cp + Vector2(1, 0), Color(Gfx.FIRE[1], fade))


## On the hull, under the guns: the scrap baron's gold chain.
func _draw_deco() -> void:
	var w: SimWorld = view.world
	if w == null:
		return
	for v in w.vehicles:
		if v.alive and RigArt.fx(v, "baron"):
			_gold_chain(v)


## A gold chain draped over the hood; it grows longer, heavier and gets a bigger medallion with the
## scrap the baron holds (one step per 100, as the damage bonus).
func _gold_chain(v: SimVehicle) -> void:
	var rv: RigView = view.rig_view(v.id)
	if rv == null:
		return
	var d: Vector3 = view.display(v)
	var p: Vector2 = Gfx.snap(Vector2(d.x, d.y))
	var rot: float = Gfx.frame_rotation(Gfx.frame_for_angle(d.z, Gfx.VEHICLE_DIRS), Gfx.VEHICLE_DIRS)
	var steps: int = clampi(v.scrap / Salvage.BARON_STEP, 0, 8)
	var y0: float = RigArt.FRONT[rv.foot] + 8.0
	var half: float = 6.0 + float(steps) * 0.75
	var sag: float = 2.0 + float(steps) * 0.7
	var strands: int = 1 if steps < 4 else 2
	for s in strands:
		var hw: float = half - float(s) * 2.0
		var n: int = int(hw * 2.0)
		for i in n + 1:
			var x: float = -hw + float(i)
			var y: float = y0 + float(s) * 2.0 + sag * (1.0 - (x / hw) * (x / hw))
			var q: Vector2 = Gfx.snap(p + Vector2(x, y).rotated(rot))
			_deco.draw_rect(Rect2(q + Vector2(1, 1), Vector2.ONE), Gfx.OUTLINE)
			_deco.draw_rect(Rect2(q, Vector2.ONE), Gfx.BRASS[3] if (i + s) % 2 == 0 else Gfx.BRASS[2])
	var m: Vector2 = Gfx.snap(p + Vector2(0, y0 + sag + 1.0 + float(strands - 1) * 2.0).rotated(rot))
	var ms: float = 2.0 if steps < 6 else 3.0
	_deco.draw_rect(Rect2(m - Vector2(ms, ms) / 2.0 - Vector2.ONE, Vector2(ms, ms) + Vector2(2, 2)), Gfx.OUTLINE)
	_deco.draw_rect(Rect2(m - Vector2(ms, ms) / 2.0, Vector2(ms, ms)), Gfx.BRASS[3])
	_deco.draw_rect(Rect2(m - Vector2(ms, ms) / 2.0, Vector2.ONE), Gfx.FIRE[6] if (_tick / 8) % 3 == 0 else Gfx.FIRE[5])


## Above the rigs: barrels, lasers, drones, banners, warnings, crackle.
func _draw_over() -> void:
	var w: SimWorld = view.world
	if w == null or view.attract:
		return
	for v in w.vehicles:
		if not v.alive:
			continue
		var rv: RigView = view.rig_view(v.id)
		if rv == null:
			continue
		_barrels(v, rv)
		if RigArt.fx(v, "laser") and v.target_kind != 0 and v.mark_id < 0:
			_rangefinder(v, rv)
		if v.mark_id >= 0:
			_swarm(v, rv)
		if v.salvo_ticks > 0:
			_salvo(v, rv)
		if RigArt.fx(v, "regen") or RigArt.fx(v, "drift_regen"):
			_welder(v, rv)
		if RigArt.fx(v, "jammer"):
			_jammer(v)
		if v.jammed_by >= 0:
			_static(v, rv)
		if RigArt.fx(v, "drone"):
			_drone(v, rv)
		if RigArt.evo_mask(v) & 1:  # Gatling Hell: brass casings spray out of the side
			_casings(v, rv)
	for v in w.vehicles:
		var ea: int = view.evo_flash_age(v.id)
		if ea >= 0:
			_evolve_burst(v, ea)
	for i in grinder_pos.size():  # Meat Grinder pellets shed sparks
		var hs: int = (_tick * 7 + i * 13) & 255
		var back: Vector2 = -grinder_dir[i]
		_px(_over, grinder_pos[i] + back * float(4 + hs % 4) + grinder_dir[i].orthogonal() * float(hs % 3 - 1), Gfx.FIRE[5])
		if hs % 3 == 0:
			_px(_over, grinder_pos[i] + back * float(8 + hs % 5) + grinder_dir[i].orthogonal() * float((hs >> 3) % 5 - 2), Gfx.FIRE[3])
	for sp in stun_pos:  # EMP / thunderclap stun: a warm-white crackle (never cyan)
		for k in 3:
			var hsh: int = (_tick * 13 + k * 7 + int(sp.x) * 3 + int(sp.y)) & 1023
			var o := Vector2(float(hsh % 11) - 5.0, float((hsh >> 4) % 9) - 6.0)
			_px(_over, sp + o, Gfx.FIRE[6] if k == 0 else Gfx.STEEL[5])
			_px(_over, sp + o + Vector2(1, 1), Gfx.STEEL[4])
	var blink: bool = (_tick / 3) % 2 == 0
	for wp in warn_pos:  # radar array: the spitter is about to spit
		_warn_marker(wp + Vector2(0, -16), blink)
		var n: int = 20
		for i in n:
			if (i + _tick / 2) % 2 == 0:
				var a: float = TAU * float(i) / float(n)
				_px(_over, wp + Vector2(cos(a), sin(a) * 0.85) * 12.0, Gfx.UI_BAD if blink else Gfx.FIRE[4])
	_contract_banners(w)


## Gatling Hell: one brass casing per shot kicked out to the right of the gun; it arcs, bounces once and
## lies in the sand until CASING_TICKS. Analytic in the recent fire ticks (RigView.fire_log), so screenshots
## and every client show the same spray.
func _casings(v: SimVehicle, rv: RigView) -> void:
	var gi: int = rv.gun_of("mg")
	if gi < 0:
		return
	var log: PackedInt32Array = rv.fire_log.get(Cards.weapon_kind_index("mg"), PackedInt32Array())
	var b: Array = rv.barrel(gi)
	var root: Vector2 = b[1]
	var aim: float = b[2]
	var side: Vector2 = Vector2.from_angle(aim + PI / 2.0)
	var back: Vector2 = Vector2.from_angle(aim + PI)
	for t0: int in log:
		var a: int = _tick - t0
		if a < 0 or a >= CASING_TICKS:
			continue
		var hs: int = (t0 * 2654435761) & 0xffff
		var spread: float = float(hs % 9 - 4) * 0.13
		var dir: Vector2 = (side.rotated(spread) + back * 0.35).normalized()
		var reach: float = 17.0 + float(hs % 11)
		var f: float = 1.0 - exp(-float(a) / 3.0)
		var hop: float = 0.0
		if a < 6:
			hop = 7.0 * sin(PI * float(a) / 6.0)
		elif a < 9:
			hop = 1.5 * sin(PI * float(a - 6) / 3.0)
		var at: Vector2 = Gfx.snap(root - v.vel * float(a) * SimWorld.DT + dir * reach * f + Vector2(0, -hop))
		var flip: bool = (a + hs) % 2 == 0 and a < 9
		var sz: Vector2 = Vector2(1, 2) if flip else Vector2(2, 1)
		var lying: bool = a >= 9
		if hop > 0.5:  # its shadow on the ground while it flies
			_over.draw_rect(Rect2(at + Vector2(1, hop + 1.0).floor(), Vector2(2, 1)), Color(Gfx.SHADOW, 0.5))
		_over.draw_rect(Rect2(at - Vector2.ONE, sz + Vector2(2, 2)), Color(Gfx.OUTLINE, 0.85 if not lying else 0.6))
		_over.draw_rect(Rect2(at, sz), Gfx.BRASS[3] if not lying else Gfx.BRASS[2])
		_px(_over, at, Gfx.FIRE[6] if a < 3 else (Gfx.FIRE[5] if not lying else Gfx.BRASS[3]))


## The moment a weapon evolves: a white-hot core, a ring of brass and fire sparks bursting off the rig,
## a second slower ring and embers rising off the new gun. Keyed on the flash's age in ticks.
func _evolve_burst(v: SimVehicle, a: int) -> void:
	var rv: RigView = view.rig_view(v.id)
	if rv == null:
		return
	var p: Vector2 = view.display_pos(v)
	var f: Array = view.evo_flash[v.id]
	var gi: int = rv.gun_of(Cards.WEAPON_KINDS[int(f[1])])
	var gp: Vector2 = rv.barrel(gi)[1] if gi >= 0 else p
	var t: float = float(a) / float(WorldView.EVO_FLASH_TICKS)
	for ring in 2:
		var ra: float = float(a - ring * 5)
		if ra < 0.0:
			continue
		var r: float = (RigArt.RADIUS[rv.foot] + 4.0) + ra * (3.2 - float(ring) * 1.2)
		var n: int = int(r * 4.0)
		for k in n:
			if (k + ring) % 2 == 1 and ra > 12.0:
				continue
			var ang: float = TAU * float(k) / float(n) + float(ring) * 0.08
			var c: Color = Gfx.FIRE[6] if ra < 3.0 else (Gfx.BRASS[3] if k % 3 == 0 else Gfx.FIRE[5 if ring == 0 else 3])
			c.a = clampf(1.0 - ra / 26.0, 0.0, 1.0)
			var dir := Vector2(cos(ang), sin(ang) * 0.85)
			_px(_over, p + dir * r, c)
			if ring == 0 and ra < 12.0:
				_px(_over, p + dir * (r - 1.0), Color(Gfx.FIRE[3], c.a))
	if a < 14:  # a starburst of light off the gun
		for k in 12:
			var ang2: float = TAU * float(k) / 12.0 + 0.13
			var len: float = (18.0 if k % 2 == 0 else 9.0) * (1.0 - float(a) / 14.0) + 2.0
			var r0: float = 5.0 + float(a) * 1.6
			var rc: Color = Color(Gfx.FIRE[6] if k % 2 == 0 else Gfx.FIRE[5], 1.0 - float(a) / 14.0)
			var d2 := Vector2(cos(ang2), sin(ang2))
			for q in int(len):
				_px(_over, gp + d2 * (r0 + float(q)), rc)
	for k in 14:  # embers rising off the gun
		var hs: int = (k * 97 + v.id * 31) & 1023
		var life: float = float((a + hs % 10) % 20) / 20.0
		var o := Vector2(float(hs % 17) - 8.0, -float((hs >> 4) % 4) - life * 22.0)
		if t < 0.9:
			_px(_over, gp + o, Gfx.FIRE[6] if life < 0.3 else (Gfx.FIRE[5] if life < 0.6 else Gfx.FIRE[3]))
	if a < 6:  # the white-hot core on the gun
		var cs: float = float(6 - a)
		_over.draw_rect(Rect2(gp - Vector2(cs, 0.0), Vector2(cs * 2.0 + 1.0, 1.0)), Gfx.FIRE[6])
		_over.draw_rect(Rect2(gp - Vector2(0.0, cs), Vector2(1.0, cs * 2.0 + 1.0)), Gfx.FIRE[6])


## Glowing barrels heat up red; a pause shows them white-hot. Hot loads jam: the barrel stutters (RigView)
## and smokes (_rig_smoke).
func _barrels(v: SimVehicle, rv: RigView) -> void:
	if not RigArt.fx(v, "overheat") and not RigArt.fx(v, "jam"):
		return
	var over: bool = RigArt.fx(v, "overheat")
	for i in mini(rv.gun_count(), v.weapons.size()):
		var f: float = _heat(v, v.weapons[i])
		if f < 0.2:
			continue
		var b: Array = rv.barrel(i)
		var tip: Vector2 = b[0]
		var root: Vector2 = b[1]
		var steps: int = int(tip.distance_to(root))
		var hot_len: float = f if over else f * 0.5  # the heat creeps back from the muzzle
		for k in steps + 1:
			var t: float = float(k) / float(maxi(steps, 1))
			if t < 1.0 - hot_len:
				continue
			var heat: float = (t - (1.0 - hot_len)) / maxf(hot_len, 0.01)
			var c: Color = Gfx.FIRE[1]
			if f >= 1.0:
				c = Gfx.FIRE[5] if heat > 0.5 else Gfx.FIRE[4]
			elif heat > 0.66 and f > 0.6:
				c = Gfx.FIRE[3]
			elif heat > 0.3:
				c = Gfx.FIRE[2]
			_px(_over, root.lerp(tip, t), c)


func _rangefinder(v: SimVehicle, rv: RigView) -> void:
	var from: Vector2 = rv.barrel(0)[0] if rv.gun_count() > 0 else view.display_pos(v)
	var to: Vector2 = Gfx.snap(v.target_pos)
	var dist: float = from.distance_to(to)
	var n: int = int(dist / 3.0)
	for i in range(1, n):
		_px(_over, from.lerp(to, float(i) / float(n)), Color(Gfx.UI_BAD, 0.4))
	_over.draw_rect(Rect2(to - Vector2.ONE, Vector2(2, 2)), Gfx.FIRE[6])
	_over.draw_rect(Rect2(to - Vector2(1, 0), Vector2(1, 1)), Gfx.UI_BAD)


## Swarm logic: every gun's red laser on the shared mark, pulses running down the beams, a reticle.
func _swarm(v: SimVehicle, rv: RigView) -> void:
	var to: Vector2 = Gfx.snap(v.mark_pos)
	for i in rv.gun_count():
		var from: Vector2 = rv.barrel(i)[0]
		var dist: float = from.distance_to(to)
		var n: int = maxi(int(dist), 1)
		var pulse: int = (_tick * 6 + i * 17) % maxi(n, 1)
		for k in range(2, n, 2):
			var p: Vector2 = from.lerp(to, float(k) / float(n))
			var hot: bool = absi(k - pulse) < 3
			_px(_over, p, Color(Gfx.FIRE[5] if hot else Gfx.UI_BAD, 0.95 if hot else 0.6))
	var s: float = 7.0 + float((_tick / 4) % 2)
	for cx: float in [-1.0, 1.0]:
		for cy: float in [-1.0, 1.0]:
			var c: Vector2 = Gfx.snap(to + Vector2(cx, cy) * s)
			_over.draw_rect(Rect2(c - Vector2(2.0 if cx > 0.0 else 0.0, 0), Vector2(3, 1)), Gfx.UI_BAD)
			_over.draw_rect(Rect2(c - Vector2(0, 2.0 if cy > 0.0 else 0.0), Vector2(1, 3)), Gfx.UI_BAD)
	_over.draw_rect(Rect2(to - Vector2.ONE, Vector2(2, 2)), Gfx.FIRE[6])


## Neural fire control salvo: a storm of muzzle flashes on every gun.
func _salvo(v: SimVehicle, rv: RigView) -> void:
	for i in rv.gun_count():
		if (_tick + i) % 2 != 0:
			continue
		var b: Array = rv.barrel(i)
		var kind: String = str(rv.guns[i][0])
		var row: int = ammo_row(Ammo.mask(v, kind), _tick / 2 + i)
		var src: Rect2 = Gfx.cell_rect(Gfx.TEX_MUZZLE, Gfx.FX_DIRS, 4, Gfx.frame_for_angle(b[2], Gfx.FX_DIRS), row)
		var tip: Vector2 = Gfx.snap(b[0] + Vector2.from_angle(b[2]) * 2.0)
		_over.draw_texture_rect_region(Gfx.TEX_MUZZLE, Rect2(tip - src.size / 2.0, src.size), src)


## Field welder / hot rod: welding sparks on the hull while it is damaged.
func _welder(v: SimVehicle, rv: RigView) -> void:
	if v.hp >= v.max_hp - 0.5:
		return
	var p: Vector2 = view.display_pos(v)
	var r: float = RigArt.RADIUS[rv.foot] * 0.6
	var k: int = (_tick / 6 + v.id) % 4
	var at: Vector2 = p + Vector2([-0.6, 0.6, -0.5, 0.5][k] * r, [-0.4, 0.2, 0.6, -0.7][k] * r)
	for j in 4:
		var hsh: int = (_tick * 7 + j * 31 + v.id) % 97
		_px(_over, at + Vector2(float(hsh % 7 - 3), float((hsh / 7) % 5 - 3)), Gfx.FIRE[6] if j == 0 else Gfx.FIRE[5])


## Jammer: a faint flicker of static at the edge of its 200 px field.
func _jammer(v: SimVehicle) -> void:
	var p: Vector2 = view.display_pos(v)
	var r: float = float(v.tech_fx.get("jammer", 200.0))
	var n: int = 110
	for i in n:
		if (i * 7 + _tick) % 5 != 0:
			continue
		var a: float = TAU * float(i) / float(n)
		var jag: float = float((i * 13 + _tick) % 7) - 3.0
		_px(_over, p + Vector2(cos(a), sin(a) * 0.85) * (r + jag), Color(Gfx.STEEL[4] if i % 2 else Gfx.FIRE[4], 0.35))


## A rig inside a rival's jammer field: static flickers over it.
func _static(v: SimVehicle, rv: RigView) -> void:
	var p: Vector2 = view.display_pos(v)
	var r: float = RigArt.RADIUS[rv.foot]
	for k in 8:
		var hsh: int = (_tick * 29 + k * 53 + v.id * 11) % 997
		var o := Vector2(float(hsh % int(r * 2.0)) - r, float((hsh / 7) % int(r * 2.0)) - r) * 0.8
		_over.draw_rect(Rect2(Gfx.snap(p + o), Vector2(2 + hsh % 3, 1)), Color(Gfx.STEEL[5], 0.7))


## Repair drone: orbits the rig on a little shadow; welds while it is damaged. With the junkyard drone
## fusion it dives at the focus target once a second (in step with the sim's drone hit).
func _drone(v: SimVehicle, rv: RigView) -> void:
	var p: Vector2 = view.display_pos(v)
	var orbit_r: float = RigArt.RADIUS[rv.foot] + 4.0
	var a: float = float(_tick) * 0.06 + float(v.id) * 1.7
	var at: Vector2 = p + Vector2(cos(a), sin(a) * 0.7) * orbit_r + Vector2(0, -6.0 + sin(float(_tick) * 0.2))
	var heading: float = a + PI / 2.0
	var dive: float = 0.0
	if RigArt.fx(v, "junkyard") and v.target_kind == 1 and v.target_pos.distance_to(v.pos) <= Fusions.DRONE_REACH:
		var ph: int = (_tick + v.id) % Fusions.DRONE_PERIOD
		if ph >= 22:
			dive = float(ph - 22) / 8.0
		elif ph <= 8:
			dive = 1.0 - float(ph) / 8.0
		if dive > 0.0:
			var tgt: Vector2 = v.target_pos + Vector2(0, -5)
			heading = (tgt - at).angle() if ph >= 22 else (at - tgt).angle()
			at = at.lerp(tgt, dive * dive * (3.0 - 2.0 * dive))
	at = Gfx.snap(at)
	_over.draw_rect(Rect2(at + Vector2(-3, 9), Vector2(7, 2)), Color(Gfx.SHADOW, 0.45))  # shadow on the sand
	var frame: int = Gfx.frame_for_angle(heading, 16)
	var src: Rect2 = Gfx.cell_rect(RigArt.TEX_DRONE, 16, 2, frame, (_tick / 2) % 2)
	_over.draw_texture_rect_region(RigArt.TEX_DRONE, Rect2(at - src.size / 2.0, src.size), src)
	if dive >= 0.95:
		for k in 5:
			_px(_over, at + Vector2.from_angle(float(k) * 1.3 + float(_tick)) * float(3 + k), Gfx.FIRE[5 + k % 2])
	elif v.hp < v.max_hp - 0.5 and dive <= 0.0:  # a welding beam down to the hull
		var hull: Vector2 = p + (at - p) * 0.35
		var n: int = int(at.distance_to(hull))
		for k in n:
			if (k + _tick) % 3 != 0:
				_px(_over, at.lerp(hull, float(k) / float(maxi(n, 1))), Gfx.FIRE[5])
		_px(_over, hull + Vector2(float(_tick % 3 - 1), -1), Gfx.FIRE[6])


func _warn_marker(at: Vector2, blink: bool) -> void:
	var c: Color = Gfx.FIRE[4] if blink else Gfx.UI_BAD
	for row in 6:  # a warning triangle with an exclamation mark
		var y: float = at.y - 5.0 + float(row)
		var half: int = row / 2 + 1
		_over.draw_rect(Rect2(Vector2(at.x - float(half) - 1.0, y), Vector2(half * 2 + 3, 1)), Gfx.OUTLINE)
		_over.draw_rect(Rect2(Vector2(at.x - float(half), y), Vector2(half * 2 + 1, 1)), c)
	_over.draw_rect(Rect2(at + Vector2(0, -3), Vector2(1, 2)), Gfx.OUTLINE)
	_over.draw_rect(Rect2(at + Vector2(0, 0), Vector2(1, 1)), Gfx.OUTLINE)


## Contract banners: a pennant over each contract target near the watched rig (boulders, spitters, the
## leader), or over the rig itself for contracts without a target; a progress bar under the cloth.
func _contract_banners(w: SimWorld) -> void:
	var v: SimVehicle = view.focus_vehicle()
	if v == null or v.contract_kind < 0 or not v.alive:
		return
	var spots: PackedVector2Array = PackedVector2Array()
	var lift: float = 14.0
	match v.contract_kind:
		Salvage.K_BOULDERS, Salvage.K_SPITTERS:
			spots = target_pos
			lift = 16.0 if v.contract_kind == Salvage.K_BOULDERS else 11.0
		Salvage.K_LEADER:
			for o in w.vehicles:
				if o.alive and o.peer_id == w.leader_peer and o != v:
					spots.append(view.display_pos(o))
			lift = 40.0
		_:
			spots.append(view.display_pos(v) + Vector2(14, 0))
			lift = 34.0
	var f: float = clampf(v.contract_prog / float(maxi(v.contract_need, 1)), 0.0, 1.0)
	var failed: bool = v.contract_kind == Salvage.K_NO_DEATH and v.contract_prog < 0.0
	for i in mini(spots.size(), CONTRACT_BANNERS):
		var base: Vector2 = Gfx.snap(spots[i] + Vector2(0, -lift))
		var top_left: Vector2 = base - Vector2(2, 17)
		var src: Rect2 = Gfx.cell_rect(Gfx.TEX_BANNER, 2, 1, (_tick / 12 + i) % 2, 0)
		_over.draw_texture_rect_region(Gfx.TEX_BANNER, Rect2(top_left, src.size), src)
		var bar := Rect2(top_left + Vector2(4, 11), Vector2(9, 3))
		_over.draw_rect(bar, Gfx.OUTLINE)
		var fill: float = 7.0 * (1.0 if failed else f)
		if fill >= 1.0:
			_over.draw_rect(Rect2(bar.position + Vector2.ONE, Vector2(floorf(fill), 1)), Gfx.UI_BAD if failed else Gfx.FIRE[4])


## Additive light: hot barrels, laser dots, nitro jets, the juggernaut's glowing front, stun sparks.
func _draw_glow() -> void:
	var w: SimWorld = view.world
	if w == null or view.attract:
		return
	for v in w.vehicles:
		if not v.alive:
			continue
		var rv: RigView = view.rig_view(v.id)
		if rv == null:
			continue
		if RigArt.fx(v, "overheat") or RigArt.fx(v, "jam"):
			for i in mini(rv.gun_count(), v.weapons.size()):
				var f: float = _heat(v, v.weapons[i])
				if f > 0.35:
					var b: Array = rv.barrel(i)
					_halo((b[0] as Vector2).lerp(b[1], 0.3), 0.6 + f * 0.4, Color(1, 0.45, 0.3, 0.35 + 0.4 * f))
		if v.mark_id >= 0:
			_halo(Gfx.snap(v.mark_pos), 0.8, Color(1, 0.35, 0.25, 0.7))
		elif RigArt.fx(v, "laser") and v.target_kind != 0:
			_halo(Gfx.snap(v.target_pos), 0.5, Color(1, 0.35, 0.25, 0.6))
		if v.nitro_ticks > 0 and v.sputter_ticks <= 0:
			for e: Vector2 in rv.exhausts():
				_halo(e, 1.2, Color(1, 0.8, 0.6, 0.7))
		if RigArt.fx(v, "juggernaut") and v.momentum > 30.0:
			var d: Vector3 = view.display(v)
			var front: Vector2 = Vector2(d.x, d.y) + Vector2(0, RigArt.FRONT[rv.foot] + 4.0).rotated(d.z + PI / 2.0)
			_halo(front, 1.6, Color(1, 0.55, 0.35, v.momentum / 100.0 * 0.8))
	for sp in stun_pos:
		_halo(sp, 0.5, Color(1, 0.95, 0.85, 0.35))
	for i in inferno_pos.size():  # the Inferno Spout's stream lights the sand
		if i % 2 == 0:
			_halo(inferno_pos[i], 1.1, Color(1, 0.7, 0.4, 0.3))
	for v in w.vehicles:
		if not v.alive:
			continue
		var rv: RigView = view.rig_view(v.id)
		if rv == null:
			continue
		var em: int = RigArt.evo_mask(v)
		if em & 8:  # the inferno's pilot flame
			var fi: int = rv.gun_of("flamer")
			if fi >= 0:
				_halo(rv.barrel(fi)[0], 0.45, Color(1, 0.7, 0.4, 0.35 + 0.15 * float((_tick / 2 + v.id) % 2)))
		if em & 1:  # the gatling's barrels glow while it hoses
			var gi: int = rv.gun_of("mg")
			if gi >= 0 and _tick - rv.last_fire(0) <= 3:
				_halo(rv.barrel(gi)[0], 0.6, Color(1, 0.6, 0.35, 0.5))
		var ea: int = view.evo_flash_age(v.id)
		if ea >= 0:  # the evolution flash: a big warm bloom that pulses out
			var k: float = 1.0 - float(ea) / float(WorldView.EVO_FLASH_TICKS)
			var s := Vector2(Gfx.TEX_HALO_WARM_BIG.get_size()) * (0.9 + float(ea) * 0.03)
			var c: Vector2 = view.display_pos(v)
			_glow.draw_texture_rect(Gfx.TEX_HALO_WARM_BIG, Rect2(c - s / 2.0, s), false, Color(1, 0.8, 0.55, (0.6 if ea < 4 else 0.3) * k))
