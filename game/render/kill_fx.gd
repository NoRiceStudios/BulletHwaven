class_name KillFx
extends Node2D
## Kill feedback that scales with mass (docs/architecture.md "Combat visuals", design doc 11e):
## mites pop in a small burst of chitin bits and cyan goo, boulders crack into hopping shell
## fragments with a dust puff, spitters burst in an acid splash. Kills by the watched rig also throw
## warm scrap sparkles that fly to the rig (cosmetic only). All particles of a frame are one MultiMesh
## of 1 px quads (outline quads first), positions are analytic in (origin, velocity, age), so
## screenshot mode (frozen, primed with ages) shows the same thing. Spawns are capped per sim tick.
## Alien bits are cyan (GLOW) only while fresh, debris stays in the desert ramps, scrap is warm.

const MAX_PARTS := 900  ## live particles
const BURSTS_PER_TICK := 18  ## kill bursts per sim tick (the rest only leave their decal)
const SPARKLES_PER_TICK := 6
const MAX_SPARKLES := 40
const MAX_POPS := 40
const SPARKLE_LIFE := 0.5

## Particle styles.
const CHITIN_BIT := 0  ## mite shell bits, hop and land
const SHELL := 1  ## boulder shell plates (bigger, outlined)
const GOO := 2  ## cyan goo droplets that cool to dark teal
const ACID := 3  ## spitter acid spray, bright cyan with a hop
const DUST := 4  ## desert dust from a boulder going down
const FLASH := 5  ## the instant of death: a square of white-cyan light for a frame or two

const CHITIN: Array[Color] = [Color("#3a2a24"), Color("#5a4234"), Color("#7d5d45"), Color("#a07c5a"), Color("#c4a076"), Color("#dcc099")]

var view: WorldView
var frozen: bool = false

var _o: PackedVector2Array = PackedVector2Array()  ## origin
var _v: PackedVector2Array = PackedVector2Array()  ## launch velocity px/s (decelerates to a stop at the end of life)
var _age: PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _hop: PackedFloat32Array = PackedFloat32Array()  ## peak hop height px
var _style: PackedInt32Array = PackedInt32Array()  ## style | size << 4 | shade << 8

var _sp_o: PackedVector2Array = PackedVector2Array()  ## scrap sparkles: origin, age, arc side
var _sp_age: PackedFloat32Array = PackedFloat32Array()
var _sp_arc: PackedFloat32Array = PackedFloat32Array()
var _pops: Array = []  ## additive kill pops: [pos, age, kind]

var _bursts_tick: int = 0
var _sparkles_tick: int = 0
var _mm: MultiMesh
var _glow: Node2D


func _ready() -> void:
	z_index = Gfx.Z_EFFECTS
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_colors = true
	_mm.mesh = _unit_quad()
	_mm.instance_count = 512
	_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.multimesh = _mm
	add_child(mmi)
	_glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.z_index = Gfx.Z_GLOW
	_glow.z_as_relative = false
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


## A 1x1 quad from (0, 0): scaled per instance to w x h pixels, its top-left on a whole pixel.
static func _unit_quad() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func clear() -> void:
	_o.clear()
	_v.clear()
	_age.clear()
	_life.clear()
	_hop.clear()
	_style.clear()
	_sp_o.clear()
	_sp_age.clear()
	_sp_arc.clear()
	_pops.clear()


## Called once per consumed sim tick: resets the per-tick spawn budget.
func begin_tick() -> void:
	_bursts_tick = 0
	_sparkles_tick = 0


func particle_count() -> int:
	return _o.size()


func sparkle_count() -> int:
	return _sp_o.size()


# ---------------------------------------------------------------- spawning

func _add(o: Vector2, v: Vector2, age: float, life: float, hop: float, style: int, size: int, shade: int) -> void:
	if _o.size() >= MAX_PARTS or age >= life:
		return
	_o.append(o)
	_v.append(v)
	_age.append(age)
	_life.append(life)
	_hop.append(hop)
	_style.append(style | (size << 4) | (shade << 8))


## The burst of an alien of `kind` dying at `pos`, `age` s ago; `h` seeds the spray. Returns false
## when this tick's budget is spent.
func burst(kind: int, pos: Vector2, age: float, h: int) -> bool:
	if _bursts_tick >= BURSTS_PER_TICK:
		return false
	_bursts_tick += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	match kind:
		SimWorld.BOULDER:  # cracked shell: heavy plates hop out, goo spills, dust rolls
			_add(pos, Vector2.ZERO, age, 0.13, 0.0, FLASH, 11, 0)
			for i in 8:
				var a: float = float(i) / 8.0 * TAU + rng.randf_range(-0.35, 0.35)
				var sp: float = rng.randf_range(45.0, 85.0)
				_add(pos + Vector2.from_angle(a) * 2.0, Vector2(cos(a), sin(a) * 0.8) * sp, age, rng.randf_range(0.55, 0.75),
						rng.randf_range(6.0, 12.0), SHELL, 2 + (i % 2), 2 + i % 3)
			for i in 8:
				var a2: float = rng.randf() * TAU
				_add(pos, Vector2(cos(a2), sin(a2) * 0.8) * rng.randf_range(30.0, 70.0), age, rng.randf_range(0.3, 0.45),
						rng.randf_range(2.0, 6.0), GOO, 1 + i % 2, 0)
			for i in 8:
				var a3: float = float(i) / 8.0 * TAU + rng.randf_range(-0.2, 0.2)
				_add(pos + Vector2(cos(a3), sin(a3) * 0.8) * 9.0, Vector2(cos(a3), sin(a3) * 0.8) * rng.randf_range(18.0, 34.0), age,
						rng.randf_range(0.45, 0.65), 0.0, DUST, 1, i % 2)
		SimWorld.SPITTER:  # the acid sac bursts: a cyan spray, a few chitin bits
			_add(pos, Vector2.ZERO, age, 0.11, 0.0, FLASH, 9, 0)
			for i in 16:
				var a4: float = rng.randf() * TAU
				_add(pos, Vector2(cos(a4), sin(a4) * 0.8) * rng.randf_range(40.0, 110.0), age, rng.randf_range(0.35, 0.55),
						rng.randf_range(3.0, 10.0), ACID, 1 + int(i % 3 == 0), i % 2)
			for i in 3:
				var a5: float = rng.randf() * TAU
				_add(pos, Vector2(cos(a5), sin(a5) * 0.8) * rng.randf_range(30.0, 60.0), age, rng.randf_range(0.4, 0.55),
						rng.randf_range(4.0, 8.0), CHITIN_BIT, 2, i % 2)
		_:  # mite: a small pop of chitin bits and goo
			_add(pos, Vector2.ZERO, age, 0.09, 0.0, FLASH, 7, 0)
			for i in 4:
				var a6: float = rng.randf() * TAU
				_add(pos, Vector2(cos(a6), sin(a6) * 0.8) * rng.randf_range(40.0, 80.0), age, rng.randf_range(0.4, 0.55),
						rng.randf_range(3.0, 8.0), CHITIN_BIT, 1 + int(i < 2), i % 2)
			for i in 6:
				var a7: float = rng.randf() * TAU
				_add(pos, Vector2(cos(a7), sin(a7) * 0.8) * rng.randf_range(30.0, 70.0), age, rng.randf_range(0.25, 0.4),
						rng.randf_range(1.0, 5.0), GOO, 1 + int(i < 2), 0)
	if _pops.size() < MAX_POPS:
		_pops.append([pos, age, kind])
	return true


## Warm scrap sparkles from a kill of the watched rig flying to it (`n` = scrap worth, capped).
func scrap(pos: Vector2, n: int, age: float, h: int) -> void:
	for i in mini(n, 3):
		if _sparkles_tick >= SPARKLES_PER_TICK or _sp_o.size() >= MAX_SPARKLES or age + float(i) * 0.04 >= SPARKLE_LIFE:
			return
		_sparkles_tick += 1
		_sp_o.append(pos + Vector2(float(i * 3 - 3), 0))
		_sp_age.append(age + float(i) * 0.04)
		_sp_arc.append(1.0 if (h + i) % 2 == 0 else -1.0)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if not frozen:
		_age_all(delta)
	var target := Vector2.INF
	if view != null and view.world != null:
		var fv: SimVehicle = view.focus_vehicle()
		if fv != null and fv.alive:
			target = view.display_pos(fv)
	var n: int = _o.size()
	var need: int = 0
	for i in n:
		var st0: int = _style[i] & 15
		need += 3 if st0 == CHITIN_BIT or st0 == SHELL or st0 == FLASH else 1
	need += _sp_o.size() * 7
	if need > _mm.instance_count:
		_mm.instance_count = nearest_po2(need)
	var k: int = 0
	# outlines first (one draw call: instance order is draw order)
	for i in n:
		var st: int = _style[i] & 15
		if st != CHITIN_BIT and st != SHELL:
			continue
		var sz: int = (_style[i] >> 4) & 15
		var p: Vector2 = _pos(i)
		var w: float = float(sz)
		if st == SHELL:  # plates get the full 1 px outline
			_put(k, p - Vector2.ONE, Vector2(w + 2.0, float(maxi(sz - 1, 1)) + 2.0), Color(Gfx.OUTLINE, _fade(i)))
		else:  # a bit is too small for a ring: just its dark underside (light from the top left)
			_put(k, p + Vector2(0, 1), Vector2(w, 1.0), Color(Gfx.OUTLINE, 0.8 * _fade(i)))
		k += 1
	for i in n:
		var st2: int = _style[i] & 15
		var sz2: int = (_style[i] >> 4) & 15
		var shade: int = (_style[i] >> 8) & 15
		var t: float = _age[i] / _life[i]
		var p2: Vector2 = _pos(i)
		var w2: float = float(sz2)
		var h2: float = 1.0
		var c: Color
		match st2:
			CHITIN_BIT, SHELL:  # dark shell, its top edge lit (light from the top left): reads on bright sand
				h2 = float(maxi(sz2 - 1, 1)) if st2 == SHELL else 1.0
				var a: float = _fade(i)
				_put(k, p2, Vector2(w2, h2), Color(CHITIN[2] if shade % 2 == 0 else CHITIN[1], a))
				_put(k + 1, p2, Vector2.ONE, Color(CHITIN[4 + shade % 2] if st2 == SHELL else CHITIN[4], a))
				k += 2
				continue
			GOO:  # bright while it flies, cooling to dark teal
				c = Gfx.GLOW[4] if t < 0.3 else (Gfx.GLOW[3] if t < 0.6 else Gfx.GLOW[1])
			ACID:
				c = Gfx.GLOW[5 - shade] if t < 0.35 else (Gfx.GLOW[3] if t < 0.7 else Gfx.GLOW[2])
			FLASH:  # a white-cyan splat star: a core and four arms, shrinking over its frames
				var fs: int = maxi(1, sz2 - int(t * 3.0) * 2)
				var cc: Vector2 = Gfx.snap(p2)
				var half: float = float(fs / 2)
				var q: int = maxi(fs / 2 - 1, 1) | 1
				_put(k, cc - Vector2(half, 0), Vector2(fs, 1), Gfx.GLOW[4])
				_put(k + 1, cc - Vector2(0, half), Vector2(1, fs), Gfx.GLOW[4])
				_put(k + 2, cc - Vector2(q / 2, q / 2), Vector2(q, q), Gfx.GLOW[5])
				k += 3
				continue
			_:
				c = Gfx.SAND[5] if t < 0.5 or shade == 0 else Gfx.SAND[4]
		_put(k, p2, Vector2(w2, h2), Color(c, _fade(i)))
		k += 1
	for i in _sp_o.size():
		var t3: float = _sp_age[i] / SPARKLE_LIFE
		var sp: Vector2 = _sparkle_pos(i, t3, target)
		_put(k, _sparkle_pos(i, maxf(t3 - 0.12, 0.0), target), Vector2.ONE, Gfx.FIRE[3])
		_put(k + 1, _sparkle_pos(i, maxf(t3 - 0.06, 0.0), target), Vector2.ONE, Gfx.FIRE[4])
		_put(k + 2, sp, Vector2.ONE, Gfx.FIRE[6])
		k += 3
		if (int(_sp_age[i] * 30.0) + i) % 4 < 2:  # twinkle: a little brass cross
			for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_put(k, sp + d, Vector2.ONE, Gfx.FIRE[5])
				k += 1
	_mm.visible_instance_count = k
	_glow.queue_redraw()


func _put(k: int, p: Vector2, size: Vector2, c: Color) -> void:
	_mm.set_instance_transform_2d(k, Transform2D(Vector2(size.x, 0), Vector2(0, size.y), Gfx.snap(p)))
	_mm.set_instance_color(k, c)


func _age_all(delta: float) -> void:
	var j: int = 0
	for i in _o.size():
		var a: float = _age[i] + delta
		if a >= _life[i]:
			continue
		_o[j] = _o[i]
		_v[j] = _v[i]
		_age[j] = a
		_life[j] = _life[i]
		_hop[j] = _hop[i]
		_style[j] = _style[i]
		j += 1
	_o.resize(j)
	_v.resize(j)
	_age.resize(j)
	_life.resize(j)
	_hop.resize(j)
	_style.resize(j)
	j = 0
	for i in _sp_o.size():
		var b: float = _sp_age[i] + delta
		if b >= SPARKLE_LIFE:
			continue
		_sp_o[j] = _sp_o[i]
		_sp_age[j] = b
		_sp_arc[j] = _sp_arc[i]
		j += 1
	_sp_o.resize(j)
	_sp_age.resize(j)
	_sp_arc.resize(j)
	var keep: Array = []
	for pp: Array in _pops:
		pp[1] = float(pp[1]) + delta
		if float(pp[1]) < 0.25:
			keep.append(pp)
	_pops = keep


## Analytic position: slides out and stops at the end of life, hopping `hop` px up on the way.
func _pos(i: int) -> Vector2:
	var t: float = _age[i]
	var life: float = _life[i]
	var f: float = t / life
	var p: Vector2 = _o[i] + _v[i] * t * (1.0 - 0.5 * f)
	var hop: float = _hop[i]
	if hop > 0.0:
		var land: float = minf(f / 0.7, 1.0)  # in the air for the first 70 % of life, then lies still
		p.y -= hop * 4.0 * land * (1.0 - land)
	return p


func _fade(i: int) -> float:
	var f: float = _age[i] / _life[i]
	return 1.0 if f < 0.75 else clampf((1.0 - f) * 4.0, 0.0, 1.0)


## A scrap sparkle: pops up and out, then accelerates into the rig (or just pops when there is none).
func _sparkle_pos(i: int, t: float, target: Vector2) -> Vector2:
	var o: Vector2 = _sp_o[i]
	var pop := Vector2(_sp_arc[i] * 10.0, -12.0) * sin(minf(t * 2.0, 1.0) * PI * 0.5)
	if target == Vector2.INF:
		return o + pop
	var e: float = t * t
	var side: Vector2 = (target - o).orthogonal().normalized() * _sp_arc[i] * 14.0 * sin(t * PI)
	return o.lerp(target, e) + pop * (1.0 - e) + side


func _draw_glow() -> void:
	var cyan := Vector2(Gfx.TEX_HALO_CYAN.get_size())
	for pp: Array in _pops:
		var t: float = float(pp[1]) / 0.25
		if t >= 1.0:
			continue
		var k: int = int(pp[2])
		var s: float = 0.7 if k == SimWorld.MITE else (1.5 if k == SimWorld.BOULDER else 1.1)
		var sz: Vector2 = cyan * s * (0.7 + 0.5 * t)
		var p: Vector2 = Gfx.snap(pp[0])
		_glow.draw_texture_rect(Gfx.TEX_HALO_CYAN, Rect2(p - sz / 2.0, sz), false, Color(1, 1, 1, 0.75 * (1.0 - t)))
	if _sp_o.is_empty():
		return
	var warm := Vector2(Gfx.TEX_HALO_WARM.get_size()) * 0.35
	var target := Vector2.INF
	var fv: SimVehicle = view.focus_vehicle() if view != null and view.world != null else null
	if fv != null and fv.alive:
		target = view.display_pos(fv)
	for i in _sp_o.size():
		var sp: Vector2 = Gfx.snap(_sparkle_pos(i, _sp_age[i] / SPARKLE_LIFE, target))
		_glow.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(sp - warm / 2.0, warm), false, Color(1, 1, 1, 0.5))
