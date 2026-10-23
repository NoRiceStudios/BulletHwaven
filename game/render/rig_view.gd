class_name RigView
extends Node2D
## The sprite stack of one player rig (RigArt): drop shadow, articulated trailer, hull-fixed layers
## (running gear, hull, armour, engine and behaviour kit), turning guns and nitro exhaust flames.
## Layers are only rebuilt when the loadout changes (RigArt.signature); per frame the stack just
## picks one strip frame per sprite, so there is no per-frame compositing.

const NITRO_MIN_SPEED := 25.0  ## px/s: the nitro only burns while the rig is really moving
const DEAD_TINT := Color(0.32, 0.27, 0.27)

var foot: int = 0
var guns: Array = []  ## [[kind, level, evolved], ...] in weapon order
var _sig: String = ""
var _mat: ShaderMaterial
var _shadow: Sprite2D
var _trailer_shadow: Sprite2D
var _trailer: Sprite2D
var _layers: Array[Sprite2D] = []
var _guns: Array[Sprite2D] = []
var _gun_shadows: Dictionary = {}  ## gun index -> Sprite2D: every gun casts a shadow on the hull, so it stands off it
var _gun_mats: Array[ShaderMaterial] = []  ## per gun: light rim, lifted metal, hot rim after a shot (gun.gdshader)
const GUN_SHADOW := Vector2(2, 3)
const GUN_SHADER := preload("res://render/gun.gdshader")
const GUN_HOT_TICKS := 3  ## the rim glows hot this long after the gun fired
const KICK := 1.0  ## px every plain gun jerks back along its barrel on the tick it fires
var _flames: Array[Sprite2D] = []  ## [flame, glow] per exhaust
var _trailer_dir: Vector2 = Vector2.ZERO  ## trailer forward direction (world), ZERO = not placed yet
var _trailer_pos: Vector2 = Vector2.ZERO
var _p: Vector2 = Vector2.ZERO  ## last placed display position and hull frame rotation
var _rot: float = 0.0
var _nitro: int = 0  ## nitro card level (0 = none): idle exhaust flames while rolling
var _nitro_ab: bool = false  ## the nitro ability (propulsion tech): a big jet while it burns
var _mounts: Array = []  ## per gun: [0 hull / 1 trailer / 2 sidecar, index]
var jitter: PackedInt32Array = PackedInt32Array()  ## per gun: 1 = shaking this frame (jammed barrel)
## Recent "fire" ticks per weapon kind index (newest last, at most FIRE_LOG): evolved guns animate from
## them (gatling spin, earthshaker recoil) and CombatFx throws the gatling's brass casings.
var fire_log: Dictionary = {}
const FIRE_LOG := 16
const RECOIL: PackedFloat32Array = [3.0, 2.0, 1.0]  ## earthshaker barrel kick (px) for the ticks after a shot

func _init() -> void:
	_mat = RigArt.paint_material(0)
	_shadow = _sprite(RigArt.TEX_SHADOW, Gfx.Z_SHADOWS, _rows(RigArt.TEX_SHADOW, RigArt.FRAME))
	var sil := ShaderMaterial.new()
	sil.shader = Gfx.SILHOUETTE_SHADER
	_shadow.material = sil
	_trailer_shadow = _sprite(RigArt.TEX_TRAILER, Gfx.Z_SHADOWS, 1)
	_trailer_shadow.material = sil
	_trailer = _sprite(RigArt.TEX_TRAILER, Gfx.Z_VEHICLES, 1)
	_trailer.material = _mat


func _sprite(tex: Texture2D, z: int, rows: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.hframes = Gfx.VEHICLE_DIRS
	s.vframes = rows
	s.z_index = z
	add_child(s)
	return s


static func _rows(tex: Texture2D, frame_size: int) -> int:
	return maxi(1, tex.get_height() / frame_size)


## Rebuilds the stack if the rig's look changed since the last call.
func setup(v: SimVehicle) -> void:
	var sig: String = RigArt.signature(v)
	if sig == _sig:
		return
	_sig = sig
	_mat.set_shader_parameter("paint_row", Gfx.color_slot(v.color_index))
	foot = RigArt.footprint(v)
	for s in _layers + _guns:
		s.queue_free()
	for k in _gun_shadows:
		(_gun_shadows[k] as Node).queue_free()
	_gun_shadows.clear()
	_gun_mats.clear()
	for s in _flames:
		s.queue_free()
	_layers.clear()
	_guns.clear()
	_flames.clear()
	for l: Array in RigArt.hull_layers(v):
		var s := _sprite(l[0], Gfx.Z_VEHICLES, _rows(l[0], RigArt.FRAME))
		s.frame_coords = Vector2i(0, l[1])
		s.material = _mat
		_layers.append(s)
	guns = RigArt.guns(v)
	_mounts = _mount_plan(guns.size(), RigArt.has_trailer(v), RigArt.has_sidecar(v))
	for g: Array in guns:
		var s: Sprite2D
		var tex: Texture2D = RigArt.GUN_EVO_TEX if bool(g[2]) else RigArt.GUN_TEX[g[0]]
		var rows: int = 8 if bool(g[2]) else 3
		s = _sprite(tex, Gfx.Z_TURRETS, rows)
		s.frame_coords = Vector2i(0, Cards.weapon_kind_index(str(g[0])) * 2 if bool(g[2]) else int(g[1]) - 1)
		var gm := ShaderMaterial.new()
		gm.shader = GUN_SHADER
		s.material = gm
		_gun_mats.append(gm)
		var sh := _sprite(tex, Gfx.Z_RIG_DECO, rows)
		var sm := ShaderMaterial.new()
		sm.shader = Gfx.SILHOUETTE_SHADER
		sm.set_shader_parameter("shadow_color", Color(0.12, 0.1, 0.16, 0.55))
		sh.material = sm
		_gun_shadows[_guns.size()] = sh
		_guns.append(s)
	_shadow.frame_coords = Vector2i(0, RigArt.shadow_row(v))
	var trailer: bool = RigArt.has_trailer(v)
	_trailer.visible = trailer
	_trailer_shadow.visible = trailer
	_nitro = RigArt.card_level(v, "nitro")
	_nitro_ab = RigArt.fx(v, "ability_nitro")
	if _nitro > 0 or _nitro_ab:
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		for i in 2:
			var f := _sprite(RigArt.TEX_FLAME, Gfx.Z_VEHICLES, 6)
			move_child(f, 0)  # under the hull: the jet comes out from under the exhaust tip
			var g := _sprite(RigArt.TEX_FLAME_GLOW, Gfx.Z_GLOW, 6)
			g.material = add
			_flames.append(f)
			_flames.append(g)


## Places the stack for this frame. `p` is the (snapped) display position, `head` the display heading.
func place(v: SimVehicle, p: Vector2, head: float, tick: int, frozen: bool) -> void:
	var frame: int = Gfx.frame_for_angle(head, Gfx.VEHICLE_DIRS)
	var rot: float = Gfx.frame_rotation(frame, Gfx.VEHICLE_DIRS)
	_p = p
	_rot = rot
	modulate = Color.WHITE if v.alive else DEAD_TINT
	_shadow.position = p + Vector2(3, 4)
	_shadow.frame_coords.x = frame
	for s in _layers:
		s.position = p
		s.frame_coords.x = frame
	# trailer: its tongue follows the hitch, the trailer swings in behind
	if _trailer.visible:
		var hitch: Vector2 = Vector2(p) + RigArt.HITCH[foot].rotated(rot)
		var fwd: Vector2 = Vector2.from_angle(head)
		if frozen or _trailer_dir == Vector2.ZERO or not v.alive:
			_trailer_dir = fwd
		else:
			var d: Vector2 = hitch - _trailer_pos
			if d.length() > 0.5:
				_trailer_dir = d.normalized()
			if _trailer_dir.dot(fwd) < 0.2:  # never jack-knife past the cab (snaps after respawns)
				_trailer_dir = fwd
		_trailer_pos = hitch - _trailer_dir * RigArt.TRAILER_TONGUE
		var tframe: int = Gfx.frame_for_angle(_trailer_dir.angle(), Gfx.VEHICLE_DIRS)
		_trailer.position = Gfx.snap(_trailer_pos)
		_trailer.frame_coords.x = tframe
		_trailer_shadow.position = _trailer.position + Vector2(3, 4)
		_trailer_shadow.frame_coords.x = tframe
	for i in _guns.size():
		var g: Sprite2D = _guns[i]
		g.visible = v.alive
		g.position = mount_position(i, p, rot)
		if i < jitter.size() and jitter[i] != 0:  # a jammed barrel stutters
			g.position += Vector2(((tick + i) % 2) * 2 - 1, 0)
		var aim: float = float(v.weapons[i].get("aim", head)) if i < v.weapons.size() else head
		g.frame_coords.x = Gfx.frame_for_angle(aim, Gfx.VEHICLE_DIRS)
		var since: int = tick - last_fire(Cards.weapon_kind_index(str(guns[i][0])))
		if bool(guns[i][2]):
			_animate_evo(i, g, v, tick)
		elif since == 0 and v.alive and not frozen:
			var a: float = Gfx.frame_rotation(g.frame_coords.x, Gfx.VEHICLE_DIRS) - PI / 2.0
			g.position -= Gfx.snap(Vector2.from_angle(a) * KICK)
		_gun_mats[i].set_shader_parameter("heat", 1.0 - float(since) / float(GUN_HOT_TICKS) if since >= 0 and since < GUN_HOT_TICKS else 0.0)
		var sh: Sprite2D = _gun_shadows.get(i)
		if sh != null:
			sh.visible = g.visible
			sh.position = g.position + GUN_SHADOW
			sh.frame_coords = g.frame_coords
	if not _flames.is_empty():
		var boost: bool = v.nitro_ticks > 0 and v.sputter_ticks <= 0
		var burning: bool = v.alive and (boost or (_nitro > 0 and v.vel.length() > NITRO_MIN_SPEED))
		var fframe: int = Gfx.frame_for_angle(head + PI, Gfx.VEHICLE_DIRS)
		var lvl: int = 3 if boost else maxi(_nitro, 1)
		var row: int = (lvl - 1) * 2 + (tick / 2 + v.id) % 2
		for i in 2:
			var pos: Vector2 = p + Gfx.snap(RigArt.EXHAUSTS[foot][i].rotated(rot))
			for s: Sprite2D in [_flames[i * 2], _flames[i * 2 + 1]]:
				s.visible = burning
				s.position = pos
				s.frame_coords = Vector2i(fframe, row)


## Evolved guns live a little: the gatling's barrels spin and it shudders while it fires, the grinder's
## teeth chatter, the earthshaker kicks back after a shot (brace lamp blinking), the inferno's pilot flickers.
func _animate_evo(i: int, g: Sprite2D, v: SimVehicle, tick: int) -> void:
	var ki: int = Cards.weapon_kind_index(str(guns[i][0]))
	var since: int = tick - last_fire(ki)
	var firing: bool = since >= 0 and since <= 3
	var phase: int = 0
	match str(guns[i][0]):
		"mg":
			phase = tick % 2 if firing else 0
			if firing and v.alive:
				g.position += Vector2(0, (tick % 2))
		"shotgun":
			phase = (tick / 2) % 2 if firing else 0
		"cannon":
			phase = (tick / 8 + v.id) % 2
			if since >= 0 and since < RECOIL.size():
				var a: float = Gfx.frame_rotation(g.frame_coords.x, Gfx.VEHICLE_DIRS) - PI / 2.0
				g.position -= Gfx.snap(Vector2.from_angle(a) * RECOIL[since])
		"flamer":
			phase = (tick / 2 + v.id) % 2
	g.frame_coords.y = ki * 2 + phase


## A "fire" event of weapon kind `kind_index` at `tick`.
func note_fire(kind_index: int, tick: int) -> void:
	var log: PackedInt32Array = fire_log.get(kind_index, PackedInt32Array())
	if not log.is_empty() and log[log.size() - 1] >= tick:
		return
	log.append(tick)
	if log.size() > FIRE_LOG:
		log.remove_at(0)
	fire_log[kind_index] = log


## The tick weapon kind `kind_index` last fired (-100000 = never).
func last_fire(kind_index: int) -> int:
	var log: PackedInt32Array = fire_log.get(kind_index, PackedInt32Array())
	return log[log.size() - 1] if not log.is_empty() else -100000


## Index of the first gun of weapon kind `kind` (-1 = none).
func gun_of(kind: String) -> int:
	for i in guns.size():
		if str(guns[i][0]) == kind:
			return i
	return -1


## Where each of `n` guns sits: hull rings 0 and 1, then the trailer's two rings (war rig), then the hull
## extras; with a sidecar (and at least three guns) the last gun rides the sidecar.
static func _mount_plan(n: int, trailer: bool, sidecar: bool) -> Array:
	var spots: Array = [[0, 0], [0, 1]]
	if trailer:
		spots += [[1, 0], [1, 1]]
	spots += [[0, 2], [0, 3]]
	var out: Array = []
	for i in n:
		out.append(spots[mini(i, spots.size() - 1)])
	if sidecar and n >= 3:
		out[n - 1] = [2, 0]
	return out


## Centre of gun sprite `i` (display space).
func mount_position(i: int, p: Vector2, rot: float) -> Vector2:
	var m: Array = _mounts[i] if i < _mounts.size() else [0, mini(i, 3)]
	match int(m[0]):
		1:
			if _trailer.visible:
				var tf: int = _trailer.frame_coords.x
				return _trailer.position + Gfx.snap((RigArt.TRAILER_MOUNTS[int(m[1])] as Vector2).rotated(Gfx.frame_rotation(tf, Gfx.VEHICLE_DIRS)))
		2:
			return p + Gfx.snap((RigArt.SIDECAR_MOUNT[foot] as Vector2).rotated(rot))
	return p + Gfx.snap((RigArt.MOUNTS[foot][int(m[1])] as Vector2).rotated(rot))


## Exhaust tips in display space (as last placed).
func exhausts() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for e: Vector2 in RigArt.EXHAUSTS[foot]:
		out.append(_p + Gfx.snap(e.rotated(_rot)))
	return out


## Number of gun sprites (sim weapons and guns share the order).
func gun_count() -> int:
	return _guns.size()


## Drawn barrel of gun `i`: [muzzle position, barrel start, aim angle of the drawn frame].
func barrel(i: int) -> Array:
	if i < 0 or i >= _guns.size():
		return [position, position, 0.0]
	var g: Sprite2D = _guns[i]
	var a: float = Gfx.frame_rotation(g.frame_coords.x, Gfx.VEHICLE_DIRS) - PI / 2.0
	var length: float = RigArt.barrel_length(guns[i])
	var d := Vector2.from_angle(a)
	return [g.position + d * length, g.position + d * 3.0, a]


## Muzzle of the first gun of weapon kind `kind` (Cards.WEAPON_KINDS index): [position, aim angle].
func muzzle(kind_index: int, aim: float) -> Array:
	var idx: int = 0
	for i in guns.size():
		if Cards.weapon_kind_index(str(guns[i][0])) == kind_index:
			idx = i
			break
	if _guns.is_empty():
		return [position, aim]
	var g: Sprite2D = _guns[idx]
	var aim_frame: int = Gfx.frame_for_angle(aim, Gfx.VEHICLE_DIRS)
	var a: float = Gfx.frame_rotation(aim_frame, Gfx.VEHICLE_DIRS) - PI / 2.0
	var length: float = RigArt.barrel_length(guns[idx])
	return [g.position + Vector2.from_angle(a) * length, a]


## Shimmer while protected (0 = off).
func set_flash(f: float) -> void:
	_mat.set_shader_parameter("flash", f)
	for m in _gun_mats:
		m.set_shader_parameter("flash", f)
