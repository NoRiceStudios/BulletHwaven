class_name TargetMarks
extends Node2D
## Target marks (player request): what the watched rig and each of its guns are on right now. Every
## gun puts a corner bracket in its own warm colour (the range ring hues) on its target, with a dotted
## aim line from its muzzle while the target is in reach; guns on the same target nest their brackets.
## The rig's own target (what its drive circles, charges, kites or flees from) gets a pin above it and
## a turning dashed ring, both in the rig's paint. T toggles it during combat (user://profile.cfg [ui] targets, on by
## default; in the workshop T switches tabs). Reads sim state and the WorldView only.

const PROFILE_PATH := "user://profile.cfg"
const BRACKET_PAD := 3.0  ## px between the target's body and the first bracket
const BRACKET_STEP := 3.0  ## each further gun on the same target sits this much farther out
const BRACKET_ARM := 5.0  ## length of a bracket arm
const DOT_STEP := 3.0  ## px between the dots of an aim line
const RING_PAD := 8.0  ## the rig target's ring sits this far out from the drawn body (1.3 x its radius)
const PIN_LIFT := 7.0  ## the rig target's pin floats this far above the body

var view: WorldView = null
var shown: bool = true
var force: bool = false  ## screenshot mode: show it whatever the player's preference


func _ready() -> void:
	z_index = Gfx.Z_EFFECTS
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		shown = bool(cfg.get_value("ui", "targets", true))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active() or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_T:
		shown = not shown
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_PATH)  # keep the other sections
		cfg.set_value("ui", "targets", shown)
		if cfg.save(PROFILE_PATH) != OK:
			push_warning("target_marks: cannot save %s" % PROFILE_PATH)
		get_viewport().set_input_as_handled()


func active() -> bool:
	return view != null and view.world != null and not view.attract and view.world.phase == SimWorld.PHASE_COMBAT


func _rig() -> SimVehicle:
	if not (shown or force) or not active():
		return null
	var v: SimVehicle = view.focus_vehicle()
	return v if v != null and v.alive else null


# ---------------------------------------------------------------- grouping (pure, tested)

## The guns of `v` grouped by what they are on: [{"kind": 1 alien / 2 rig, "id", "pos" (sim position),
## "guns": [weapon indices], "reach": [bool per gun: target within its range]}], in order of each
## target's first gun. Guns without a target are left out.
static func groups(v: SimVehicle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at: Dictionary = {}  # Vector2i(kind, id) -> index in out
	for i in v.weapons.size():
		var w: Dictionary = v.weapons[i]
		var k: int = int(w.get("ak", 0))
		if k == 0:
			continue
		var p: Vector2 = w.get("ap", Vector2.ZERO)
		var key := Vector2i(k, int(w.get("aid", -1)))
		if not at.has(key):
			at[key] = out.size()
			out.append({"kind": k, "id": key.y, "pos": p, "guns": [], "reach": []})
		var g: Dictionary = out[at[key]]
		(g["guns"] as Array).append(i)
		(g["reach"] as Array).append(v.pos.distance_to(p) <= float(w.get("range", 0.0)))
	return out


## Mark colour of gun `kind`: warm only (player fire), the same steps as the range rings.
static func gun_color(kind: String) -> Color:
	match kind:
		"flamer":
			return Gfx.FIRE[3]
		"shotgun":
			return Gfx.FIRE[4]
		"mg":
			return Gfx.FIRE[5]
		"cannon":
			return Gfx.BONE_LIGHT
	return Gfx.SAND[4]


# ---------------------------------------------------------------- drawing

## Drawn position and body radius of target (kind, id), falling back to the synced position.
func _target(kind: int, id: int, fallback: Vector2) -> Array:
	var w: SimWorld = view.world
	if kind == 2:
		if id >= 0 and id < w.vehicles.size():
			var t: SimVehicle = w.vehicles[id]
			return [view.display_pos(t), view.rig_radius(t)]
		return [Gfx.snap(fallback), SimVehicle.RADIUS]
	var r: float = 8.0
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			r = SimWorld.ENEMY_RADIUS[w.enemy_kind[i]]
			break
	return [Gfx.snap(view.enemy_display_pos(id, fallback)), r]


func _draw() -> void:
	var v: SimVehicle = _rig()
	if v == null:
		return
	if v.target_kind != 0:
		var rt: Array = _target(v.target_kind, v.target_id, v.target_pos)
		_ring(rt[0], float(rt[1]) * 1.3 + RING_PAD, _paint(v))
		_pin(rt[0], float(rt[1]), _paint(v))
	var rv: RigView = view.rig_view(v.id)
	for g: Dictionary in groups(v):
		var t: Array = _target(int(g["kind"]), int(g["id"]), g["pos"])
		var p: Vector2 = t[0]
		var guns: Array = g["guns"]
		for n in guns.size():
			var wi: int = int(guns[n])
			var col: Color = gun_color(str(v.weapons[wi].get("kind", "")))
			var near: bool = bool(g["reach"][n])
			var s: float = floorf(float(t[1]) + BRACKET_PAD + BRACKET_STEP * float(n))
			if near and rv != null and wi < rv.gun_count():
				_aim_line(rv.barrel(wi)[0], p, s, col)
			_brackets(p, s, Color(col, 1.0 if near else 0.45))


## Dotted line from the muzzle to just outside the bracket, marching towards the target.
func _aim_line(from: Vector2, to: Vector2, stop: float, col: Color) -> void:
	var d: float = from.distance_to(to) - stop - 2.0
	if d <= DOT_STEP:
		return
	var u: Vector2 = from.direction_to(to)
	var off: float = float(view.world.tick % 4)
	var x: float = 3.0 + off
	while x < d:
		var q: Vector2 = Gfx.snap(from + u * x)
		draw_rect(Rect2(q + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.45))
		draw_rect(Rect2(q, Vector2.ONE), Color(col, 0.85))
		x += DOT_STEP


## Four corner brackets of half-size `s` around `c`, each on a dark rim.
func _brackets(c: Vector2, s: float, col: Color) -> void:
	var a: float = BRACKET_ARM
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var k: Vector2 = c + Vector2(sx, sy) * s
			var hx := Rect2(Vector2(k.x - (a - 1.0 if sx > 0.0 else 0.0), k.y), Vector2(a, 1))
			var hy := Rect2(Vector2(k.x, k.y - (a - 1.0 if sy > 0.0 else 0.0)), Vector2(1, a))
			draw_rect(hx.grow(1.0), Color(Gfx.OUTLINE, col.a * 0.6))
			draw_rect(hy.grow(1.0), Color(Gfx.OUTLINE, col.a * 0.6))
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var k: Vector2 = c + Vector2(sx, sy) * s
			draw_rect(Rect2(Vector2(k.x - (a - 1.0 if sx > 0.0 else 0.0), k.y), Vector2(a, 1)), col)
			draw_rect(Rect2(Vector2(k.x, k.y - (a - 1.0 if sy > 0.0 else 0.0)), Vector2(1, a)), col)


## The rig's paint (a light steel for the black paint job, which would vanish on the shadows).
static func _paint(v: SimVehicle) -> Color:
	if v.color_index == Gfx.DARK_PAINT:
		return Gfx.STEEL[3]
	return Gfx.PLAYER_COLORS[Gfx.player_index(v)]


## The rig's own target, from above: a bobbing pin in the rig's paint pointing down at it.
func _pin(c: Vector2, r: float, col: Color) -> void:
	var tip: Vector2 = Gfx.snap(c - Vector2(0, r * 1.3 + PIN_LIFT + float((view.world.tick / 8) % 2)))
	for row in 5:  # a downward triangle, 9 px wide at the top
		var w: float = float(1 + row * 2)
		var at := Vector2(tip.x - floorf(w / 2.0), tip.y - float(row))
		draw_rect(Rect2(at - Vector2(1, 0), Vector2(w + 2.0, 1)), Gfx.OUTLINE)
		draw_rect(Rect2(at, Vector2(w, 1)), col)
	draw_rect(Rect2(tip + Vector2(-5, -5), Vector2(11, 1)), Gfx.OUTLINE)  # dark cap
	draw_rect(Rect2(tip + Vector2(0, 1), Vector2(1, 1)), Gfx.OUTLINE)


## Around the rig's own target: a turning dashed ring (flattened like the own-rig ring) in its paint.
func _ring(c: Vector2, r: float, col: Color) -> void:
	var n: int = maxi(int(TAU * r), 16)  # a dot per px of rim
	var spin: int = view.world.tick / 2
	for i in n:
		if ((i + spin) / 5) % 3 == 2:  # 10 px dashes, 5 px gaps
			continue
		var a: float = TAU * float(i) / float(n)
		var p: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a) * 0.8) * r)
		draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.5))
		draw_rect(Rect2(p, Vector2.ONE), col)
