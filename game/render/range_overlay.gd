class_name RangeOverlay
extends Control
## Weapon range rings (player request): a dotted circle around the watched rig for every gun kind it
## carries, at the gun's real reach (Weapon "range" after cards and tech, the same number the sim fires
## at), in a warm colour per gun with the gun's name where the ring is on screen. Guns that reach the
## same distance share one ring and one label. R toggles it during combat (kept in user://profile.cfg
## [ui] ranges, off by default; in the workshop R is the reroll). Sits under the HUD panels. Reads sim
## state and the WorldView only.

const PROFILE_PATH := "user://profile.cfg"
const MERGE_PX := 3.0  ## guns whose reach differs by less than this share one ring
const DASH_STEP := 12.0  ## px of arc per dash and gap
const DASH_FILL := 0.6  ## part of each step the dash covers
const LABEL_ANGLE := -PI / 4.0  ## labels sit upper right of the rig ...
const LABEL_SCAN := PI / 36.0  ## ... or as close to that as the screen allows (5 degree steps)
const EDGE := 6.0  ## labels keep this far from the screen edge
const ALPHA := 0.9

var view: WorldView = null
var shown: bool = false
var force: bool = false  ## screenshot mode: show it whatever the player's preference


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		shown = bool(cfg.get_value("ui", "ranges", false))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active() or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_R:
		shown = not shown
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_PATH)  # keep the other sections
		cfg.set_value("ui", "ranges", shown)
		if cfg.save(PROFILE_PATH) != OK:
			push_warning("range_overlay: cannot save %s" % PROFILE_PATH)
		get_viewport().set_input_as_handled()


func active() -> bool:
	return view != null and view.world != null and not view.attract and view.world.phase == SimWorld.PHASE_COMBAT


func visible_now() -> bool:
	return (shown or force) and active() and _rig() != null


func _rig() -> SimVehicle:
	var v: SimVehicle = view.focus_vehicle()
	return v if v != null and v.alive else null


# ---------------------------------------------------------------- rings (pure, tested)

## The rings to draw for `v`: [{"radius": px, "kinds": [gun kinds]}], smallest first, one per distinct
## reach (each kind at the longest reach of its guns; kinds within MERGE_PX of each other share a ring).
static func rings(v: SimVehicle) -> Array[Dictionary]:
	var reach: Dictionary = {}  # kind -> px
	for w in v.weapons:
		var k: String = str(w.get("kind", ""))
		reach[k] = maxf(float(reach.get(k, 0.0)), float(w.get("range", 0.0)))
	var kinds: Array = reach.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool:
		return float(reach[a]) < float(reach[b]) or (float(reach[a]) == float(reach[b]) and a < b))
	var out: Array[Dictionary] = []
	for k: String in kinds:
		var r: float = float(reach[k])
		if r <= 0.0:
			continue
		if not out.is_empty() and r - float(out[-1]["radius"]) < MERGE_PX:
			(out[-1]["kinds"] as Array).append(k)
			out[-1]["radius"] = r  # the longer reach of the two
		else:
			out.append({"radius": r, "kinds": [k]})
	return out


## Ring colour of gun `kind`: warm only (player fire), each gun its own step so the rings tell apart.
static func kind_color(kind: String) -> Color:
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


## Where a ring of radius `r` around `c` carries its label: the point nearest LABEL_ANGLE that lies on
## screen (`vs`) with EDGE to spare, scanning both ways round the ring; Vector2.INF if none does.
static func label_anchor(c: Vector2, r: float, vs: Vector2) -> Vector2:
	var area := Rect2(Vector2.ZERO, vs).grow(-EDGE)
	for i in int(PI / LABEL_SCAN) + 1:
		for s: float in [1.0, -1.0]:
			var p: Vector2 = c + Vector2.from_angle(LABEL_ANGLE + s * float(i) * LABEL_SCAN) * r
			if area.has_point(p):
				return p
	return Vector2.INF


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not visible_now():
		return
	var v: SimVehicle = _rig()
	var c: Vector2 = view.screen_pos(v)
	var vs: Vector2 = get_viewport_rect().size
	var screen := Rect2(Vector2.ZERO, vs)
	for ring: Dictionary in rings(v):
		var r: float = float(ring["radius"])
		var kinds: Array = ring["kinds"]
		var col: Color = kind_color(str(kinds[-1]))
		# dashed circle on a dark rim, so it reads on bright sand and in a horde alike
		var n: int = maxi(int(TAU * r / DASH_STEP), 12)
		for i in n:
			var a0: float = TAU * float(i) / float(n)
			var a1: float = a0 + TAU / float(n) * DASH_FILL
			var mid: Vector2 = c + Vector2.from_angle((a0 + a1) / 2.0) * r
			if not screen.grow(DASH_STEP).has_point(mid):
				continue
			draw_arc(c, r, a0, a1, 4, Color(Gfx.OUTLINE, 0.55), 3.0)
			draw_arc(c, r, a0, a1, 4, Color(col, ALPHA), 1.0)
		var a: Vector2 = label_anchor(c, r, vs)
		if a == Vector2.INF:
			continue
		var names: PackedStringArray = []
		for k: String in kinds:
			names.append(weapon_label(v, k))
		var text: String = " + ".join(names)
		var w: float = float(UiFont.width(text))
		var pos := Vector2(clampf(a.x - floorf(w / 2.0), EDGE, vs.x - EDGE - w), clampf(a.y - 8.0, EDGE, vs.y - EDGE - 6.0))
		UiFont.draw(self, text, pos.floor(), col, Gfx.UI_SHADOW)


## Short label of gun `kind` on `v`: the card name, or the evolution's once evolved.
static func weapon_label(v: SimVehicle, kind: String) -> String:
	if Cards.is_evolved(v, kind):
		var evo: String = RigArt.evolution_card(kind)
		if evo != "":
			return UiKit.card_name(evo)
	return UiKit.card_name(kind)
