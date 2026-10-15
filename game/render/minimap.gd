class_name Minimap
extends Control
## Combat minimap (playtest round 3): a riveted plate in the bottom-right corner with the whole arena
## scaled to fit. Shows the alien density (cyan, the only cold colour), every rig still in the game in
## its paint (the watched one as a heading arrow, the bounty leader ringed in hazard yellow, shielded
## rigs blinking warm, respawning rigs hollow), a fire ping where a rig was just wrecked and the
## camera's view as a bone-white frame. Scales with whatever arena the sim uses, so a bigger map only
## changes the scale factor. M toggles it (kept in user://profile.cfg [ui] minimap); a click on it
## while spectating watches the rig nearest that spot. Reads sim state and the WorldView only.

const MAX_INNER := Vector2(112, 64)  ## largest map area (px); the arena's aspect decides the rest
const BORDER := 4.0  ## plate rim around the map area
const MARGIN := 6.0  ## distance from the screen corner
const FIELD_TINT := Color(0.42, 0.36, 0.34)  ## the ground texture, darkened so the marks read
const FIELD_FILL := Color("#4a3428")  ## plain field when the ground texture does not span the arena
const PING_TICKS := 60  ## a wreck ping lasts this long (2 s)
const PROFILE_PATH := "user://profile.cfg"

var view: WorldView = null
var shown: bool = true

var _img: Image = null
var _tex: ImageTexture = null
var _count: PackedByteArray = PackedByteArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		shown = bool(cfg.get_value("ui", "minimap", true))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active():
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and visible_now() and view.spectating():
		var fr: Rect2 = frame_rect(get_viewport_rect().size)
		if fr.has_point(mb.position):
			var id: int = nearest_rig(view, from_map(mb.position, arena(), _inner(fr)))
			if id >= 0:
				view.spectate_vehicle(id)
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_M:
		shown = not shown
		_save_pref()
		get_viewport().set_input_as_handled()


func _save_pref() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PROFILE_PATH)  # keep the other sections (the driver profile from main.gd)
	cfg.set_value("ui", "minimap", shown)
	if cfg.save(PROFILE_PATH) != OK:
		push_warning("minimap: cannot save %s" % PROFILE_PATH)


## The spectatable rig nearest world point `p` (-1 if none).
static func nearest_rig(v: WorldView, p: Vector2) -> int:
	var best: int = -1
	var best_d: float = INF
	for r: SimVehicle in v.spectate_candidates():
		var d: float = r.pos.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = r.id
	return best


## The arena the map covers (one place to change if the arena stops being a constant).
static func arena() -> Rect2:
	return SimWorld.ARENA


## Map area for an arena: as large as fits in MAX_INNER at the arena's aspect, whole pixels.
static func inner_size(a: Rect2) -> Vector2:
	var s: float = minf(MAX_INNER.x / a.size.x, MAX_INNER.y / a.size.y)
	return Vector2(maxf(floorf(a.size.x * s), 8.0), maxf(floorf(a.size.y * s), 8.0))


## The plate's rect on a viewport of size `vs` (the HUD keeps rival arrows clear of it).
static func frame_rect(vs: Vector2) -> Rect2:
	var outer: Vector2 = inner_size(arena()) + Vector2(BORDER, BORDER) * 2.0
	return Rect2(vs - outer - Vector2(MARGIN, MARGIN), outer)


## Pixel of a map area -> world position (inverse of to_map, pixel centres).
static func from_map(q: Vector2, a: Rect2, inner: Rect2) -> Vector2:
	var t: Vector2 = ((q.floor() + Vector2(0.5, 0.5) - inner.position) / (inner.size - Vector2.ONE)).clamp(Vector2.ZERO, Vector2.ONE)
	return a.position + t * a.size


static func _inner(fr: Rect2) -> Rect2:
	return Rect2(fr.position + Vector2(BORDER, BORDER), fr.size - Vector2(BORDER, BORDER) * 2.0)


## World position -> pixel inside a map area `inner` (top-left at inner.position).
static func to_map(p: Vector2, a: Rect2, inner: Rect2) -> Vector2:
	var t: Vector2 = ((p - a.position) / a.size).clamp(Vector2.ZERO, Vector2.ONE)
	return (inner.position + t * (inner.size - Vector2.ONE)).floor()


## Drawn at all: during combat (the HUD layer hides it with the rest of the HUD).
func active() -> bool:
	return view != null and view.world != null and not view.attract and view.world.phase == SimWorld.PHASE_COMBAT


## Screenshot mode always shows it, whatever the player's preference.
func visible_now() -> bool:
	return (shown or view.frozen) and active()


func _draw() -> void:
	if not visible_now():
		return
	var w: SimWorld = view.world
	var vs: Vector2 = get_viewport_rect().size
	var a: Rect2 = arena()
	var fr: Rect2 = frame_rect(vs)
	var inner: Rect2 = _inner(fr)
	UiKit.plate(self, fr)
	draw_rect(inner.grow(1.0), Gfx.OUTLINE)
	if Vector2(Gfx.TEX_GROUND.get_size()) == a.size:
		draw_texture_rect(Gfx.TEX_GROUND, inner, false, FIELD_TINT)
	else:
		draw_rect(inner, FIELD_FILL)
	_draw_hive(w, a, inner)
	_draw_camera(a, inner)
	_draw_pings(w, a, inner)
	_draw_rigs(w, a, inner)


## Alien density: one pixel per map cell, brighter cyan where more aliens crowd; boulders and
## spitters stand out as the brightest specks.
func _draw_hive(w: SimWorld, a: Rect2, inner: Rect2) -> void:
	var iw: int = int(inner.size.x)
	var ih: int = int(inner.size.y)
	if _img == null or _img.get_width() != iw or _img.get_height() != ih:
		_img = Image.create(iw, ih, false, Image.FORMAT_RGBA8)
		_tex = null
		_count.resize(iw * ih)
	_img.fill(Color(0, 0, 0, 0))
	_count.fill(0)
	var sx: float = float(iw) / a.size.x
	var sy: float = float(ih) / a.size.y
	for i in w.enemy_count:
		var p: Vector2 = w.enemy_pos[i] - a.position
		var x: int = clampi(int(p.x * sx), 0, iw - 1)
		var y: int = clampi(int(p.y * sy), 0, ih - 1)
		var k: int = y * iw + x
		_count[k] = mini(_count[k] + (1 if w.enemy_kind[i] == SimWorld.MITE else 16), 255)
	for k in _count.size():
		var c: int = _count[k]
		if c == 0:
			continue
		var col: Color = Gfx.GLOW[5] if c >= 16 else (Gfx.GLOW[2] if c == 1 else (Gfx.GLOW[3] if c < 4 else Gfx.GLOW[4]))
		_img.set_pixel(k % iw, k / iw, col)
	if _tex == null:
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
	draw_texture(_tex, inner.position)


## The part of the arena on screen right now (from the world canvas transform), as a bone frame.
func _draw_camera(a: Rect2, inner: Rect2) -> void:
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * Vector2.ZERO
	var br: Vector2 = inv * get_viewport_rect().size
	var p0: Vector2 = to_map(tl, a, inner)
	var p1: Vector2 = to_map(br, a, inner)
	var r := Rect2(p0, (p1 - p0).max(Vector2(2, 2)))
	UiKit.outline_rect(self, r, Color(Gfx.BONE_LIGHT, 0.55))


## A fire ring growing out of every spot where a rig went up in the last PING_TICKS.
func _draw_pings(w: SimWorld, a: Rect2, inner: Rect2) -> void:
	for i in range(view.wreck_log.size() - 1, -1, -1):
		var e: Dictionary = view.wreck_log[i]
		var age: int = w.tick - int(e["tick"])
		if age >= PING_TICKS:
			break
		if age < 0 or not e.has("pos"):
			continue
		var p: Vector2 = to_map(e["pos"], a, inner)
		var rad: float = 2.0 + floorf(float(age) / 10.0)
		var col: Color = Color(Gfx.FIRE[4] if age < 20 else Gfx.FIRE[3], 1.0 - float(age) / float(PING_TICKS))
		UiKit.outline_rect(self, Rect2(p - Vector2(rad, rad), Vector2(rad, rad) * 2.0 + Vector2.ONE), col)


## Rigs in the game: paint dots with a dark outline (hollow while respawning, a warm blink while
## shielded); the watched rig as a heading arrow on top.
func _draw_rigs(w: SimWorld, a: Rect2, inner: Rect2) -> void:
	var focus: SimVehicle = view.focus_vehicle()
	for v: SimVehicle in w.vehicles:
		if v == focus or v.eliminated:
			continue
		var p: Vector2 = to_map(v.pos, a, inner)
		if not v.alive:
			UiKit.outline_rect(self, Rect2(p - Vector2(1, 1), Vector2(3, 3)), Color(UiKit.bar_color(v.color_index), 0.7))
			continue
		if v.peer_id == w.leader_peer and w.vehicles.size() > 1:
			UiKit.outline_rect(self, Rect2(p - Vector2(3, 3), Vector2(7, 7)), Gfx.HAZARD)
		var shield: bool = v.invuln_ticks > 0 and (w.tick / 6) % 2 == 0
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Gfx.FIRE[4] if shield else Gfx.OUTLINE)
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), UiKit.bar_color(v.color_index))
	if focus == null or focus.eliminated:
		return
	var fp: Vector2 = to_map(focus.pos, a, inner)
	if not focus.alive:
		# wrecked, respawning: a blinking cross where it went up
		if (w.tick / 8) % 2 == 0:
			for d in range(-2, 3):
				draw_rect(Rect2(fp + Vector2(d, d), Vector2.ONE), Gfx.UI_BAD)
				draw_rect(Rect2(fp + Vector2(d, -d), Vector2.ONE), Gfx.UI_BAD)
		return
	if focus.peer_id == w.leader_peer and w.vehicles.size() > 1:
		UiKit.outline_rect(self, Rect2(fp - Vector2(4, 4), Vector2(9, 9)), Gfx.HAZARD)
	var dir := Vector2.from_angle(focus.heading)
	UiKit.pointer(self, fp + Vector2(0.5, 0.5) + dir * 3.0, dir, 6.0, UiKit.bar_color(focus.color_index))
