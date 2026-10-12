class_name EffectsLayer
extends Node2D
## Short-lived effects (muzzle flashes, sparks, ichor, explosions, dust) drawn immediately each
## frame, plus their additive light on a child canvas item. No node per effect.

enum Kind { MUZZLE, SPARKS, ICHOR, EXPLOSION, DUST, EXPLOSION_BIG, DEBRIS }

const LIFE: PackedFloat32Array = [0.07, 0.18, 0.3, 0.8, 0.6, 1.1, 0.9]
const MAX_EFFECTS := 1500

var frozen: bool = false
## Each effect: [kind, pos, angle, age, sd]
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


func spawn(kind: Kind, pos: Vector2, angle: float = 0.0, age: float = 0.0, sd: int = 0) -> void:
	if _fx.size() >= MAX_EFFECTS:
		return
	if age < LIFE[kind]:
		_fx.append([kind, pos, angle, age, sd])


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
				_cell(Gfx.TEX_MUZZLE, Gfx.FX_DIRS, 1, Gfx.frame_for_angle(e[2], Gfx.FX_DIRS), 0, pos)
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


func _draw_glow() -> void:
	for e in _fx:
		var kind: int = e[0]
		var pos: Vector2 = Gfx.snap(e[1])
		var t: float = float(e[3]) / LIFE[kind]
		match kind:
			Kind.MUZZLE:
				_cell_on(_glow, Gfx.TEX_MUZZLE_GLOW, Gfx.FX_DIRS, 1, Gfx.frame_for_angle(e[2], Gfx.FX_DIRS), 0, pos)
				_center_on(_glow, Gfx.TEX_HALO_WARM, pos, Color(1, 1, 1, 0.5))
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


func _cell(tex: Texture2D, cols: int, rows: int, col: int, row: int, pos: Vector2) -> void:
	_cell_on(self, tex, cols, rows, col, row, pos)


func _cell_on(ci: CanvasItem, tex: Texture2D, cols: int, rows: int, col: int, row: int, pos: Vector2) -> void:
	var src: Rect2 = Gfx.cell_rect(tex, cols, rows, col, row)
	ci.draw_texture_rect_region(tex, Rect2(pos - src.size / 2.0, src.size), src)


func _center_on(ci: CanvasItem, tex: Texture2D, pos: Vector2, mod: Color) -> void:
	var s := Vector2(tex.get_size())
	ci.draw_texture_rect(tex, Rect2(pos - s / 2.0, s), false, mod)


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
