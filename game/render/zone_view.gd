class_name ZoneView
extends Node2D
## PvP control zones on the ground (docs/architecture.md "Control zones"; sim/zones.gd). Each zone is a
## scrap beacon (assets/zone_beacon.png: a rusty derrick on sandbags with a lamp cage and a pennant in the
## owner's paint) in the middle of a ring of stakes strung with tape. Under the aliens: a spray-painted
## boundary on the sand, a faint wash of the owner's paint and the cast shadows. Over the aliens (so the
## zone still reads in a horde): the stakes, the tape, the beacon, the capture progress arc in the
## capturer's paint and a burst when a zone changes hands. Neutral zones are bone, locked ones (PvP grace)
## are dim with the pennant furled, contested ones flicker in hazard stripes with a red lamp. Warm and
## paint colours only (cyan stays the aliens'). Stake layout comes from a hash of the zone's position,
## so every zone (and every round) looks a bit different. Reads the SimWorld only; zone_captured events
## arrive through note_event().

const TEX_BEACON := preload("res://assets/zone_beacon.png")
const BEACON_COLS := 2  ## wave frames
const BEACON_ROWS := 3
const ROW_NEUTRAL := 0
const ROW_PAINT := 1
const ROW_LOCKED := 2
const BEACON_FOOT := Vector2(18, 51)  ## tools/artgen/fx.py ZONE_FOOT: the mast's foot in a cell
const LAMP_OFS := Vector2(-1, -37)  ## top-left of the lamp relative to the foot (fx.ZONE_LAMP, 1 px up)
const STAKES := 24
const FLASH_TICKS := 26  ## the burst when a zone changes hands
const LETTERS := "ABC"
const TIMBER := Color("#5e2f1e")  ## palette RUST[1]: old timber stakes

var view: WorldView
var _ground: Node2D
var _posts: Node2D
var _over: Node2D
var _glow: Node2D
var _beacons: Array[Sprite2D] = []
var _rows: PackedInt32Array = PackedInt32Array()  ## paint row set on each beacon's material (-1 = none yet)
var _flash: Dictionary = {}  ## zone index -> [tick, new owner id]
## Redraw only on change: the ground layer when a zone moves or changes hands, the stakes and tape also on
## contested / flash ticks, the arcs and glow once per sim tick. A few thousand pixel rects stay cached.
var _sig_ground: String = ""
var _sig_posts: String = ""
var _last_tick: int = -1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ground = _node(Gfx.Z_RING, _draw_ground)
	_posts = _node(Gfx.Z_FIRE, _draw_posts)
	for i in Zones.MAX_ZONES:
		var s := Sprite2D.new()
		s.texture = TEX_BEACON
		s.centered = false
		s.region_enabled = true
		s.z_index = Gfx.Z_FIRE
		s.visible = false
		s.material = RigArt.paint_material(0)
		add_child(s)
		_beacons.append(s)
		_rows.append(-1)
	_over = _node(Gfx.Z_FIRE, _draw_over)
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
	_flash.clear()
	_sig_ground = ""
	_sig_posts = ""
	_last_tick = -1


## WorldView._consume_events hands over every event; only zone_captured matters here.
func note_event(e: Dictionary, tick: int) -> void:
	if str(e.get("type", "")) == "zone_captured":
		_flash[int(e.get("kind", -1))] = [tick, int(e.get("owner", -1))]


func update(w: SimWorld) -> void:
	for i in _beacons.size():
		var s: Sprite2D = _beacons[i]
		s.visible = w != null and i < w.zones.size() and _shown(w)
		if not s.visible:
			continue
		var z: Dictionary = w.zones[i]
		var owner: SimVehicle = UiKit.vehicle_by_id(w, int(z["owner"]))
		var row: int = ROW_LOCKED if not w.zones_active else (ROW_PAINT if owner != null else ROW_NEUTRAL)
		var frame: int = ((w.tick + i * 5) / 9) % BEACON_COLS
		s.region_rect = Gfx.cell_rect(TEX_BEACON, BEACON_COLS, BEACON_ROWS, frame, row)
		s.position = Gfx.snap(z["pos"]) - BEACON_FOOT
		var paint: int = owner.color_index if owner != null else 0
		if paint != _rows[i]:
			(s.material as ShaderMaterial).set_shader_parameter("paint_row", Gfx.color_slot(paint))
			_rows[i] = paint
	var shown: bool = w != null and _shown(w)
	var g: String = ""
	var anim: bool = false
	if shown:
		g = "1" if w.zones_active else "0"
		for z: Dictionary in w.zones:
			var zp: Vector2 = z["pos"]
			g += "|%d,%d,%d" % [int(zp.x), int(zp.y), int(z["owner"])]
	var p: String = g
	if shown:
		for i in w.zones.size():
			var hot: bool = w.zones_active and bool(w.zones[i]["contested"])
			var fl: bool = _flash_age(w, i) >= 0
			p += ("c" if hot else "-") + ("f" if fl else "-")
			anim = anim or hot or fl
	var new_tick: bool = w != null and w.tick != _last_tick
	if g != _sig_ground:
		_sig_ground = g
		_ground.queue_redraw()
	if p != _sig_posts or (anim and new_tick):
		_sig_posts = p
		_posts.queue_redraw()
	if new_tick or not shown:
		_over.queue_redraw()
		_glow.queue_redraw()
	_last_tick = w.tick if w != null else -1


func _shown(w: SimWorld) -> bool:
	return not view.attract and w.phase == SimWorld.PHASE_COMBAT and not w.zones.is_empty()


## Paint of a zone owner (or capturer) id in the world: the paint step, steel for black paint, bone if nobody.
static func zone_color(w: SimWorld, id: int) -> Color:
	var v: SimVehicle = UiKit.vehicle_by_id(w, id)
	if v == null:
		return Gfx.BONE_LIGHT
	var slot: int = Gfx.player_index(v)
	return Gfx.STEEL[3] if slot == Gfx.DARK_PAINT else Gfx.PLAYER_COLORS[slot]


static func letter(i: int) -> String:
	return LETTERS[i] if i >= 0 and i < LETTERS.length() else "?"


## The zones that touch the camera's view (with margin for the beacon and stakes).
func _visible_zones(w: SimWorld) -> Array[int]:
	var out: Array[int] = []
	if w == null or not _shown(w):
		return out
	var inv: Transform2D = get_viewport().get_canvas_transform().affine_inverse()
	var view_r := Rect2(inv * Vector2.ZERO, get_viewport_rect().size).grow(Zones.ZONE_RADIUS + 24.0)
	for i in w.zones.size():
		if view_r.has_point(w.zones[i]["pos"]):
			out.append(i)
	return out


## Every zone (the cached layers draw them all, at most three).
func _all_zones(w: SimWorld) -> Array[int]:
	var out: Array[int] = []
	if w != null and _shown(w):
		for i in w.zones.size():
			out.append(i)
	return out


func _flash_age(w: SimWorld, i: int) -> int:
	if not _flash.has(i):
		return -1
	var age: int = w.tick - int(_flash[i][0])
	return age if age >= 0 and age < FLASH_TICKS else -1


## Smooth hash noise around the ring: a few sines with phases from the zone's position (no repeats).
static func _wobble(a: float, h: int, k: int) -> float:
	var p1: float = float((h >> (k * 3)) % 628) / 100.0
	var p2: float = float((h >> (k * 3 + 7)) % 628) / 100.0
	return 0.6 * sin(a * float(5 + k) + p1) + 0.4 * sin(a * float(11 + 2 * k) + p2)


# ---------------------------------------------------------------- under the aliens

func _draw_ground() -> void:
	var w: SimWorld = view.world if view != null else null
	for i in _all_zones(w):
		var z: Dictionary = w.zones[i]
		var c: Vector2 = Gfx.snap(z["pos"])
		var h: int = Gfx.hash_pos(c, 31)
		var owner: int = int(z["owner"])
		var col: Color = zone_color(w, owner)
		var live: bool = w.zones_active
		var r: float = Zones.ZONE_RADIUS
		if live and owner >= 0:
			_ground.draw_circle(c, r, Color(col, 0.07))
		# spray-painted boundary: thicker and thinner runs, a gap where the can coughed
		var steps: int = int(TAU * r)
		var a_spray: float = (0.5 if owner >= 0 else 0.32) if live else 0.16
		for s in steps:
			var a: float = TAU * float(s) / float(steps)
			var dir := Vector2(cos(a), sin(a))
			var n: float = _wobble(a, h, 0)
			if n > 0.82:
				continue
			var p: Vector2 = Gfx.snap(c + dir * r)
			var thick: float = 2.0 if n < -0.35 else 1.0
			_ground.draw_rect(Rect2(p, Vector2(thick, thick)), Color(col, a_spray))
			if s % 2 == 0:  # the scuffed furrow just outside, darker on the shadow side (bottom right)
				var shade: float = 0.12 + 0.12 * clampf(dir.dot(Vector2(0.7, 0.7)), 0.0, 1.0)
				_ground.draw_rect(Rect2(Gfx.snap(c + dir * (r + 2.0)), Vector2.ONE), Color(Gfx.SAND[0], shade))
		# stake shadows (light from the top left: shadows fall to the bottom right)
		for k in STAKES:
			var st: Array = _stake(c, h, k)
			var base: Vector2 = st[0]
			if bool(st[3]):
				continue
			var len: int = int(st[2])
			for d in range(1, len - 1):
				_ground.draw_rect(Rect2(base + Vector2(d, floorf(float(d) * 0.5)), Vector2.ONE), Color(Gfx.SHADOW, 0.32))
		# the beacon's shadow: sandbag ring, then the derrick and mast as long strokes to the bottom right
		_ground.draw_rect(Rect2(c + Vector2(-13, -2), Vector2(30, 5)), Color(Gfx.SHADOW, 0.24))
		for d in range(3, 34):
			var sp: Vector2 = c + Vector2(d, floorf(float(d) * 0.5))
			var wid: float = 6.0 - floorf(float(d) / 7.0)
			_ground.draw_rect(Rect2(sp + Vector2(0, -floorf(wid / 2.0)), Vector2(1, maxf(wid, 1.0))), Color(Gfx.SHADOW, 0.26))
		if live and owner >= 0:  # the pennant's shadow off the end of the mast's
			_ground.draw_rect(Rect2(c + Vector2(34, 15), Vector2(12, 4)), Color(Gfx.SHADOW, 0.22))


## Stake k of a zone: [base (ground point), top, height, fallen]. Spacing, height and lean from the hash.
func _stake(c: Vector2, h: int, k: int) -> Array:
	var hk: int = (h >> (k % 11)) ^ (k * 2654435761)
	hk = absi(hk)
	var a: float = TAU * (float(k) + 0.35 * (float(hk % 100) / 100.0 - 0.5)) / float(STAKES)
	var base: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a)) * (Zones.ZONE_RADIUS + 1.0))
	var height: int = 5 + hk % 3
	var lean: float = float((hk / 7) % 3 - 1)
	var fallen: bool = (hk / 13) % 10 == 0
	return [base, base + Vector2(lean, -height), height, fallen, hk]


# ---------------------------------------------------------------- over the aliens

func _draw_posts() -> void:
	var w: SimWorld = view.world if view != null else null
	for i in _all_zones(w):
		var z: Dictionary = w.zones[i]
		var c: Vector2 = Gfx.snap(z["pos"])
		var h: int = Gfx.hash_pos(c, 31)
		var live: bool = w.zones_active
		var owner: int = int(z["owner"])
		var contested: bool = live and bool(z["contested"])
		var col: Color = zone_color(w, owner) if live else Gfx.STEEL[3]
		var fa: int = _flash_age(w, i)
		var stakes: Array = []
		for k in STAKES:
			stakes.append(_stake(c, h, k))
		# tape between neighbouring standing stakes, sagging; contested: marching hazard stripes
		var tape_a: float = 0.95 if live else 0.5
		for k in STAKES:
			var s0: Array = stakes[k]
			var s1: Array = stakes[(k + 1) % STAKES]
			if bool(s0[3]) or bool(s1[3]):
				if not bool(s0[3]):  # a torn end hangs off the stake
					var t: Vector2 = s0[1]
					for d in 3:
						_px(t + Vector2(1, 1 + d), col if not contested else Gfx.HAZARD, tape_a)
				continue
			var a: Vector2 = s0[1] + Vector2(0, 1)
			var b: Vector2 = s1[1] + Vector2(0, 1)
			var n: int = int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
			var sag: float = 1.0 + float(int(s0[4]) % 2)
			for j in range(1, n):
				var t: float = float(j) / float(n)
				var p: Vector2 = Gfx.snap(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
				var pc: Color = col
				if contested:
					pc = Gfx.HAZARD if ((j + k * 5 + w.tick / 3) / 2) % 2 == 0 else Gfx.OUTLINE
				_posts.draw_rect(Rect2(p + Vector2(0, 1), Vector2.ONE), Color(Gfx.OUTLINE, 0.55 * tape_a))
				_posts.draw_rect(Rect2(p, Vector2.ONE), Color(pc, tape_a))
		# the stakes: rebar or timber, outlined, the tip sprayed in the owner's paint
		for k in STAKES:
			var st: Array = stakes[k]
			var base: Vector2 = st[0]
			var hk: int = int(st[4])
			var timber: bool = hk % 3 == 0
			var body: Color = TIMBER if timber else Gfx.STEEL[2]
			var lit: Color = Gfx.SAND[1] if timber else Gfx.STEEL[4]
			if bool(st[3]):  # knocked flat: lies in the sand
				var dx: float = 1.0 if hk % 2 == 0 else -1.0
				_posts.draw_rect(Rect2(base + Vector2(minf(0, dx * 4.0) - 1.0, -1), Vector2(6, 3)), Gfx.OUTLINE)
				_posts.draw_rect(Rect2(base + Vector2(minf(0, dx * 4.0), 0), Vector2(4, 1)), body)
				continue
			var top: Vector2 = st[1]
			var height: int = int(st[2])
			var lean: float = top.x - base.x
			_posts.draw_rect(Rect2(base.x - 1.0 + minf(lean, 0.0), top.y - 1.0, 4.0 + absf(lean), float(height) + 2.0), Gfx.OUTLINE)
			for y in height:
				var x: float = base.x + roundf(lean * float(height - y) / float(height))
				var yy: float = base.y - float(y) - 1.0
				_posts.draw_rect(Rect2(x, yy, 1, 1), lit)
				_posts.draw_rect(Rect2(x + 1.0, yy, 1, 1), body)
			var tip: Color = col
			if fa >= 0:
				tip = Gfx.FIRE[6] if fa < 6 or (fa / 3) % 2 == 0 else zone_color(w, int(_flash[i][1]))
			elif not live:
				tip = Gfx.STEEL[3]
			_posts.draw_rect(Rect2(top + Vector2(0, -1), Vector2(2, 2)), tip)


func _draw_over() -> void:
	var w: SimWorld = view.world if view != null else null
	for i in _visible_zones(w):
		var z: Dictionary = w.zones[i]
		var c: Vector2 = Gfx.snap(z["pos"])
		var r: float = Zones.ZONE_RADIUS + 5.0
		var prog: float = Zones.progress(z)
		if w.zones_active and prog > 0.0:
			# capture progress: a thick arc in the capturer's paint, clockwise from the top, a white-hot head
			var col: Color = zone_color(w, int(z["cap_id"]))
			var steps: int = int(TAU * r)
			var end: int = int(float(steps) * prog)
			for s in steps:
				var a: float = -PI / 2.0 + TAU * float(s) / float(steps)
				var dir := Vector2(cos(a), sin(a))
				if s >= end:
					if s % 3 == 0:
						_over.draw_rect(Rect2(Gfx.snap(c + dir * r), Vector2.ONE), Color(Gfx.OUTLINE, 0.45))
					continue
				_over.draw_rect(Rect2(Gfx.snap(c + dir * (r - 1.0)), Vector2(2, 2)), Gfx.OUTLINE)
				_over.draw_rect(Rect2(Gfx.snap(c + dir * (r + 1.0)), Vector2(2, 2)), Gfx.OUTLINE)
			for s in end:
				var a: float = -PI / 2.0 + TAU * float(s) / float(steps)
				var dir := Vector2(cos(a), sin(a))
				var pc: Color = Gfx.FIRE[6] if s > end - 4 else col
				_over.draw_rect(Rect2(Gfx.snap(c + dir * r), Vector2(2, 2)), pc)
		# the lamp: a red blink while contested, dark while locked
		var lamp: Vector2 = c + LAMP_OFS
		if w.zones_active and bool(z["contested"]):
			var on: bool = (w.tick / 5) % 2 == 0
			_over.draw_rect(Rect2(lamp, Vector2(3, 3)), Gfx.UI_BAD if on else Gfx.FIRE[1])
		# a zone changing hands: a ring of the new paint rushing out to the stakes, sparks on the beacon
		var fa: int = _flash_age(w, i)
		if fa >= 0:
			var k: float = float(fa) / float(FLASH_TICKS)
			var fc: Color = zone_color(w, int(_flash[i][1]))
			var rad: float = lerpf(8.0, Zones.ZONE_RADIUS, sqrt(k))
			var n: int = int(TAU * rad / 2.0)
			for s in n:
				if (s + fa) % 4 == 0:
					continue
				var a: float = TAU * float(s) / float(n)
				var p: Vector2 = Gfx.snap(c + Vector2(cos(a), sin(a)) * rad)
				_over.draw_rect(Rect2(p, Vector2(2, 2)), Color(Gfx.FIRE[6] if k < 0.25 else fc, 1.0 - k * 0.7))


func _draw_glow() -> void:
	var w: SimWorld = view.world if view != null else null
	for i in _visible_zones(w):
		if not w.zones_active:
			continue
		var z: Dictionary = w.zones[i]
		var lamp: Vector2 = Gfx.snap(z["pos"]) + LAMP_OFS + Vector2(1.5, 1.5)
		var a: float = 0.55
		var tint := Color(1, 0.85, 0.6)
		if bool(z["contested"]):
			a = 0.85 if (w.tick / 5) % 2 == 0 else 0.25
			tint = Color(1, 0.45, 0.3)
		var s := Vector2(Gfx.TEX_HALO_WARM.get_size())
		_glow.draw_texture_rect(Gfx.TEX_HALO_WARM, Rect2(lamp - s / 2.0, s), false, Color(tint, a))
		var fa: int = _flash_age(w, i)
		if fa >= 0:
			var sb := Vector2(Gfx.TEX_HALO_WARM_BIG.get_size())
			_glow.draw_texture_rect(Gfx.TEX_HALO_WARM_BIG, Rect2(lamp - sb / 2.0, sb), false, Color(1, 0.8, 0.55, 0.8 * (1.0 - float(fa) / float(FLASH_TICKS))))


func _px(p: Vector2, col: Color, a: float) -> void:
	_posts.draw_rect(Rect2(Gfx.snap(p), Vector2.ONE), Color(col, a))
