class_name EffectsLayer
extends Node2D
## Short-lived effects (muzzle flashes, sparks, ichor, explosions, dust, and the tech tree's combat
## effects: fire puffs, armour-piercing flashes, shrapnel, KILL pops, shockwaves, EMP rings, chain
## bolts, dodge streaks) drawn immediately each frame, plus their additive light on a child canvas
## item. No node per effect. Player effects stay warm or steel: cyan is the aliens' colour.

enum Kind { MUZZLE, SPARKS, ICHOR, EXPLOSION, DUST, EXPLOSION_BIG, DEBRIS, FIRE_PUFF, AP_FLASH, SHARDS, KILL,
	SHOCK, EMP, BOLT, DODGE, SPARK_BURST, FLARE, SOOT, STEAM }

const LIFE: PackedFloat32Array = [0.07, 0.18, 0.3, 0.8, 0.6, 1.1, 0.9, 0.35, 0.16, 0.4, 0.8,
	0.45, 0.5, 0.22, 0.25, 0.35, 0.3, 0.9, 0.7]
const MAX_EFFECTS := 1500

var frozen: bool = false
## Each effect: [kind, pos, angle, age, sd, param]. MUZZLE: sd = muzzle row (Gfx.TRACER_*); SHOCK / EMP /
## SPARK_BURST: param = radius px (SHOCK sd 1 = electric); BOLT: param = the far end (Vector2).
var _fx: Array[Array] = []
var _glow: Node2D


func _ready() -> void:
	z_index = Gfx.Z_EFFECTS
	_glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = mat
	_glow.z_index = Gfx.Z_GLOW
	_glow.z_as_relative = false
	_glow.draw.connect(_draw_glow)
	add_child(_glow)


func clear() -> void:
	_fx.clear()


func spawn(kind: Kind, pos: Vector2, angle: float = 0.0, age: float = 0.0, sd: int = 0, param: Variant = 0.0) -> void:
	if _fx.size() >= MAX_EFFECTS:
		return
	if age < LIFE[kind]:
		_fx.append([kind, pos, angle, age, sd, param])


func _process(delta: float) -> void:
	if not frozen:
		var keep: Array[Array] = []
		for e in _fx:
			e[3] = float(e[3]) + delta
			if float(e[3]) < LIFE[int(e[0])]:
				keep.append(e)
		_fx = keep
	queue_redraw()
	_glow.queue_redraw()


func _draw() -> void:
	for e in _fx:
		var kind: int = e[0]
		var pos: Vector2 = Gfx.snap(e[1])
		var t: float = float(e[3]) / LIFE[kind]
		var sd: int = e[4]
		match kind:
			Kind.MUZZLE:
				_cell(Gfx.TEX_MUZZLE, Gfx.FX_DIRS, 4, Gfx.frame_for_angle(e[2], Gfx.FX_DIRS), clampi(sd, 0, 3), pos)
			Kind.SPARKS:
				_burst(pos, e[2], sd, 5, 40.0, t, [Gfx.FIRE[6], Gfx.FIRE[5], Gfx.FIRE[4]])
			Kind.ICHOR:
				_burst(pos, e[2], sd, 6, 30.0, t, [Gfx.GLOW[4], Gfx.GLOW[3], Gfx.GLOW[2]])
			Kind.EXPLOSION:
				_cell(Gfx.TEX_EXPLOSION, 8, 1, mini(7, int(t * 8.0)), 0, pos)
			Kind.DUST:
				_dust(pos, sd, t)
			Kind.EXPLOSION_BIG:
				_cell(Gfx.TEX_EXPLOSION_BIG, 10, 1, mini(9, int(t * 10.0)), 0, pos)
			Kind.DEBRIS:
				_debris(pos, sd, t)
			Kind.FIRE_PUFF:
				_fire_puff(pos, sd, t)
			Kind.AP_FLASH:
				_ap_flash(pos, e[2], t)
			Kind.SHARDS:
				_shards(pos, sd, t)
			Kind.KILL:
				var kp: Vector2 = pos + Vector2(0, -12.0 - 10.0 * minf(1.0, t * 2.5))
				if t < 0.85 or (int(t * 40.0) % 2 == 0):
					_cell(Gfx.TEX_KILL, 2, 1, 0 if t < 0.1 else 1, 0, Gfx.snap(kp))
			Kind.SHOCK:
				_shock(pos, float(e[5]), sd, t)
			Kind.EMP:
				_emp(pos, float(e[5]), sd, t)
			Kind.BOLT:
				_bolt(pos, e[5], sd, t)
			Kind.DODGE:
				_dodge(pos, e[2], t)
			Kind.SPARK_BURST:
				_spark_burst(pos, float(e[5]), sd, t)
			Kind.FLARE:
				_flare(pos, t)
			Kind.SOOT, Kind.STEAM:
				var row: int = 1 if kind == Kind.SOOT else 0
				_cell(Gfx.TEX_SMOKE, 8, 2, mini(7, 2 + int(t * 6.0)), row, Gfx.snap(pos + Vector2(float(sd % 5 - 2), -10.0 * t)))


func _draw_glow() -> void:
	for e in _fx:
		var kind: int = e[0]
		var pos: Vector2 = Gfx.snap(e[1])
		var t: float = float(e[3]) / LIFE[kind]
		match kind:
			Kind.MUZZLE:
				_cell_on(_glow, Gfx.TEX_MUZZLE_GLOW, Gfx.FX_DIRS, 4, Gfx.frame_for_angle(e[2], Gfx.FX_DIRS), clampi(int(e[4]), 0, 3), pos)
				_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 1, 1, 0.65 if int(e[4]) == Gfx.TRACER_FIRE else 0.5))
			Kind.SPARKS:
				if t < 0.5:
					_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 1, 1, 0.35))
			Kind.EXPLOSION:
				_cell_on(_glow, Gfx.TEX_EXPLOSION_GLOW, 8, 1, mini(7, int(t * 8.0)), 0, pos)
				_center_on(_glow, Gfx.TEX_HALO_WARM_BIG, pos, Color(1, 1, 1, clampf(1.0 - t * 1.4, 0.0, 1.0)))
			Kind.EXPLOSION_BIG:
				_cell_on(_glow, Gfx.TEX_EXPLOSION_BIG_GLOW, 10, 1, mini(9, int(t * 10.0)), 0, pos)
				var a: float = clampf(1.0 - t * 1.2, 0.0, 1.0)
				_center_on(_glow, Gfx.TEX_HALO_WARM_BIG, pos, Color(1, 1, 1, a))
				if t < 0.25:  # the first flash lights up the whole neighbourhood
					var s := Vector2(Gfx.TEX_HALO_WARM_BIG.get_size()) * 2.0
					_glow.draw_texture_rect(Gfx.TEX_HALO_WARM_BIG, Rect2(pos - s / 2.0, s), false, Color(1, 1, 1, 0.6 * (1.0 - t * 4.0)))
			Kind.FIRE_PUFF:  # many per shotgun burst on one boulder: keep each one faint so they do not wash out
				_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 0.75, 0.55, 0.22 * (1.0 - t)))
			Kind.FLARE:
				_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 0.8, 0.6, 0.7 * (1.0 - t)))
			Kind.AP_FLASH:
				_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 1, 1, 0.8 * (1.0 - t)))
			Kind.SHARDS:
				if t < 0.4:
					_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 1, 1, 0.5))
			Kind.KILL:
				var kp: Vector2 = pos + Vector2(0, -12.0 - 10.0 * minf(1.0, t * 2.5))
				_cell_on(_glow, Gfx.TEX_KILL_GLOW, 2, 1, 0 if t < 0.1 else 1, 0, Gfx.snap(kp))
				if t < 0.3:
					_center_on(_glow, Gfx.TEX_HALO_WARM, Gfx.snap(kp), Color(1, 1, 1, 0.6))
			Kind.SHOCK, Kind.EMP, Kind.SPARK_BURST:
				if kind == Kind.EMP:  # the pulse front glows warm-white as it travels
					var er: float = float(e[5]) * minf(1.0, 0.12 + t * 1.8)
					_glow.draw_set_transform(pos, 0.0, Vector2(1.0, 0.85))
					_glow.draw_arc(Vector2.ZERO, er, 0.0, TAU, 72, Color(1.0, 0.92, 0.8, 0.3 * clampf(1.3 - t * 1.3, 0.0, 1.0)), 4.0)
					_glow.draw_set_transform(Vector2.ZERO)
				if t < 0.35:
					var r: float = float(e[5]) * 1.6
					var hs := Vector2(r, r)
					var col: Color = Color(1, 0.95, 0.85, 0.25) if kind == Kind.EMP or int(e[4]) == 1 else Color(1, 1, 1, 0.3)
					_glow.draw_texture_rect(Gfx.TEX_HALO_WARM_BIG, Rect2(pos - hs, hs * 2.0), false, Color(col, col.a * (1.0 - t / 0.35)))
			Kind.BOLT:
				_center_on(_glow, Gfx.TEX_HALO_WARM, Gfx.snap(e[5]), Color(1, 1, 1, 0.6 * (1.0 - t)))


func _cell(tex: Texture2D, cols: int, rows: int, col: int, row: int, pos: Vector2) -> void:
	_cell_on(self, tex, cols, rows, col, row, pos)


func _cell_on(ci: CanvasItem, tex: Texture2D, cols: int, rows: int, col: int, row: int, pos: Vector2) -> void:
	var src: Rect2 = Gfx.cell_rect(tex, cols, rows, col, row)
	ci.draw_texture_rect_region(tex, Rect2(pos - src.size / 2.0, src.size), src)


func _center_on(ci: CanvasItem, tex: Texture2D, pos: Vector2, mod: Color) -> void:
	var s := Vector2(tex.get_size())
	ci.draw_texture_rect(tex, Rect2(pos - s / 2.0, s), false, mod)


func _px(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(Gfx.snap(p), Vector2.ONE), c)


## A spray of single pixels thrown away from `angle` (opposite the incoming shot).
func _burst(pos: Vector2, angle: float, sd: int, n: int, speed: float, t: float, cols: Array[Color]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in n:
		var a: float = angle + PI + rng.randf_range(-1.1, 1.1)
		var d: float = (2.0 + rng.randf() * speed * LIFE[Kind.SPARKS]) * minf(1.0, t * 2.0 + 0.3)
		var p: Vector2 = Gfx.snap(pos + Vector2.from_angle(a) * d)
		var c: Color = cols[mini(cols.size() - 1, int(t * cols.size() + rng.randf() * 0.8))]
		draw_rect(Rect2(p, Vector2.ONE), c)


## Dithered sand puff kicked up behind a wheel: grows and thins out.
func _dust(pos: Vector2, sd: int, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var r: float = 2.0 + t * 4.0
	var n: int = int(14.0 * (1.0 - t))
	for i in n:
		var a: float = rng.randf() * TAU
		var d: float = sqrt(rng.randf()) * r
		var p: Vector2 = Gfx.snap(pos + Vector2(cos(a) * d, sin(a) * d - t * 3.0))
		draw_rect(Rect2(p, Vector2.ONE), Gfx.SAND[5] if i % 3 != 0 else Gfx.SAND[4])


## Scrap chunks and a burning bit or two thrown out of a wrecked rig, arcing up and falling back.
func _debris(pos: Vector2, sd: int, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in 14:
		var a: float = rng.randf() * TAU
		var v: float = 30.0 + rng.randf() * 55.0
		var d: float = v * t * LIFE[Kind.DEBRIS] * (1.0 - t * 0.35)
		var lift: float = 26.0 * rng.randf() * t * (1.0 - t) * 4.0  # hop up and land
		var p: Vector2 = Gfx.snap(pos + Vector2(cos(a), sin(a) * 0.8) * d - Vector2(0, lift))
		var hot: bool = i % 4 == 0 and t < 0.7
		var c: Color = Gfx.FIRE[4] if hot else (Gfx.STEEL[1 + i % 3] if i % 3 else Color("#843f24"))
		var sz := Vector2(2, 2) if i % 2 == 0 else Vector2(2, 1)
		draw_rect(Rect2(p - Vector2.ONE, sz + Vector2(2, 2)), Gfx.OUTLINE)
		draw_rect(Rect2(p, sz), c)


## Incendiary hit: a short flame lick plus a few burning droplets.
func _fire_puff(pos: Vector2, sd: int, t: float) -> void:
	var fr: int = mini(7, int(t * 8.0) + sd % 3)
	var src: Rect2 = Gfx.cell_rect(Gfx.TEX_FLAME, 8, 3, fr, 0 if t > 0.5 else 1)
	draw_texture_rect_region(Gfx.TEX_FLAME, Rect2(pos - Vector2(src.size.x / 2.0, src.size.y / 2.0 + Gfx.FLAME_BASE_Y - 2.0), src.size), src)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in 4:
		var a: float = rng.randf() * TAU
		var d: float = 2.0 + rng.randf() * 9.0 * t
		_px(pos + Vector2(cos(a) * d, sin(a) * d * 0.7 - 3.0 * t), Gfx.FIRE[2 + i % 3] if t < 0.7 else Gfx.FIRE[1])


## Armour piercing hit: a white-hot star and a streak punching through the target.
func _ap_flash(pos: Vector2, angle: float, t: float) -> void:
	var d: Vector2 = Vector2.from_angle(angle)
	var n: Vector2 = d.orthogonal()
	var arm: float = 4.0 * (1.0 - t)
	var hot: Color = Gfx.FIRE[6] if t < 0.5 else Gfx.FIRE[5]
	for k in range(-int(arm), int(arm) + 1):
		_px(pos + n * float(k), hot)
	for k in range(0, 10):  # the exit streak
		if k > 2 + int(8.0 * (1.0 - t)):
			break
		_px(pos + d * float(k + 1), Gfx.STEEL[5] if k > 3 else hot)
	_px(pos + Vector2(1, -1) * arm * 0.7, Gfx.FIRE[5])
	_px(pos + Vector2(-1, 1) * arm * 0.7, Gfx.FIRE[5])


## Shrapnel kill: steel slivers fly out in three directions, each with a hot tip.
func _shards(pos: Vector2, sd: int, t: float) -> void:
	var a0: float = float(sd % 628) / 100.0
	for k in 3:
		var a: float = a0 + TAU * float(k) / 3.0
		var dir := Vector2.from_angle(a)
		var tip: Vector2 = pos + dir * (3.0 + 26.0 * t)
		_px(tip, Gfx.FIRE[5] if t < 0.6 else Gfx.STEEL[4])
		_px(tip - dir * 1.5, Gfx.STEEL[5])
		_px(tip - dir * 3.0, Gfx.STEEL[3])
	if t < 0.3:  # the burst at the centre
		for k in 6:
			var b: float = a0 + TAU * float(k) / 6.0 + 0.5
			_px(pos + Vector2.from_angle(b) * (2.0 + 6.0 * t), Gfx.FIRE[6])


## An expanding ring: style 0 = a dust and fire shockwave (war machine, turbine boom, jerrycans),
## 1 = an electric crackle (thunderclap stun ring), warm white, never cyan.
func _shock(pos: Vector2, radius: float, style: int, t: float) -> void:
	var r: float = radius * minf(1.0, 0.25 + t * 1.6)
	var n: int = maxi(int(r * (4.0 if style == 1 else 1.5)), 14)
	var fade: float = 1.0 - t
	for i in n:
		var a: float = TAU * float(i) / float(n)
		var dir := Vector2(cos(a), sin(a) * 0.85)
		if style == 1:  # electric (thunderclap): a zigzag arc ring with a dark inner edge
			var tk: int = int(t * 30.0)
			if (i / 8 + tk) % 4 != 0:
				var jag: float = float(absi((i + tk) % 6 - 3)) - 1.5
				_px(pos + dir * (r + jag - 1.0), Color(Gfx.STEEL[1], 0.45 * fade))
				_px(pos + dir * (r + jag), Color(Gfx.FIRE[6] if i % 5 == 0 else Gfx.STEEL[5], fade))
		else:
			_px(pos + dir * r, Color(Gfx.FIRE[5] if t < 0.3 else Gfx.SAND[5], fade))
			if i % 2 == 0:
				_px(pos + dir * (r - 2.0), Color(Gfx.SAND[4], 0.8 * fade))
			if i % 3 == 0:
				_px(pos + dir * (r - 4.0 - float(i % 4)), Color(Gfx.SAND[3], 0.6 * fade))


## EMP pulse: a wide ring of crackling zigzag arcs (steel white, warm-white sparks), with a dark inner
## edge so it reads on bright sand, and a fainter echo ring trailing inside.
func _emp(pos: Vector2, radius: float, sd: int, t: float) -> void:
	var r: float = radius * minf(1.0, 0.12 + t * 1.8)
	var fade: float = clampf(1.3 - t * 1.3, 0.0, 1.0)
	var n: int = maxi(int(r * 5.0), 32)  # about one pixel apart: a solid line, broken into arcs
	var tick: int = int(t * 24.0)
	for i in n:
		var arc: int = i / 10
		if (arc * 5 + tick + sd) % 6 == 0:
			continue
		var a: float = TAU * float(i) / float(n)
		var dir := Vector2(cos(a), sin(a) * 0.85)
		var jag: float = float(absi((i + arc * 3 + tick) % 6 - 3)) - 1.5  # a zigzag that crawls along
		var p: Vector2 = pos + dir * (r + jag)
		_px(p - dir, Color(Gfx.STEEL[1], 0.5 * fade))
		_px(p, Color(Gfx.FIRE[6] if (i + tick * 2) % 9 == 0 else Gfx.STEEL[5], fade))
		if t < 0.7 and i % 3 == 0:
			_px(pos + dir * r * 0.78, Color(Gfx.STEEL[4], 0.45 * fade))
	if t < 0.5:
		for i in 16:
			var a2: float = float((i * 97 + sd) % 628) / 100.0
			var d2: Vector2 = Vector2(cos(a2), sin(a2) * 0.85)
			var p2: Vector2 = pos + d2 * (r + float(i % 4) * 2.0)
			_px(p2, Color(Gfx.FIRE[6], 1.0 - t * 2.0))
			_px(p2 + d2, Color(Gfx.FIRE[5], 0.8 - t * 1.6))


## Chain lightning between two points: a jagged warm-white bolt that flickers out.
func _bolt(a: Vector2, b_v: Variant, sd: int, t: float) -> void:
	var b: Vector2 = b_v
	var seg: int = maxi(3, int(a.distance_to(b) / 7.0))
	var n: Vector2 = (b - a).normalized().orthogonal()
	var prev: Vector2 = a
	var rng := RandomNumberGenerator.new()
	rng.seed = sd + int(t * 6.0)
	for i in range(1, seg + 1):
		var f: float = float(i) / float(seg)
		var p: Vector2 = a.lerp(b, f) + n * (rng.randf_range(-4.0, 4.0) if i < seg else 0.0)
		draw_line(Gfx.snap(prev), Gfx.snap(p), Gfx.FIRE[6] if t < 0.5 else Gfx.FIRE[5], 1.0)
		prev = p
	_px(b, Gfx.FIRE[6])


## Featherweight dodge: speed streaks either side and a flash where the rig hopped from.
func _dodge(pos: Vector2, side: float, t: float) -> void:
	var s := Vector2.from_angle(side)
	var fwd: Vector2 = s.orthogonal()
	for k in 5:
		var o: float = float(k - 2) * 4.0
		var ln: float = 10.0 * (1.0 - t)
		for j in int(ln):
			var p: Vector2 = pos + fwd * o - s * (6.0 + float(j) + 14.0 * t)
			_px(p, Color(Gfx.BONE_LIGHT if j < 3 else Gfx.FIRE[5], 1.0 - t))
	if t < 0.4:
		for k in 8:
			_px(pos + Vector2.from_angle(TAU * float(k) / 8.0) * (8.0 + 10.0 * t), Gfx.FIRE[6])


## Ram sparks (bumper, thermite): a ring of hot sparks thrown out to `radius`.
func _spark_burst(pos: Vector2, radius: float, sd: int, t: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	for i in 18:
		var a: float = rng.randf() * TAU
		var d: float = radius * (0.3 + rng.randf() * 0.7) * minf(1.0, t * 2.2)
		var p: Vector2 = pos + Vector2(cos(a), sin(a) * 0.85) * d
		var c: Color = Gfx.FIRE[6] if t < 0.3 else (Gfx.FIRE[5] if t < 0.6 else Gfx.FIRE[3])
		_px(p, c)
		if i % 3 == 0 and t < 0.6:
			_px(p - Vector2(cos(a), sin(a)) * 1.5, Gfx.FIRE[4])


## A fresh ignition (napalm jumping over, an exhaust pop): a quick tall flame.
func _flare(pos: Vector2, t: float) -> void:
	var src: Rect2 = Gfx.cell_rect(Gfx.TEX_FLAME, 8, 3, int(t * 7.0), 2)
	draw_texture_rect_region(Gfx.TEX_FLAME, Rect2(pos - Vector2(src.size.x / 2.0, src.size.y / 2.0 + Gfx.FLAME_BASE_Y), src.size), src)
