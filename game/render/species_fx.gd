class_name SpeciesFx
extends Node2D
## Render side of the hive-signature species (Species in sim/species.gd): the airborne drop shadow of Glass
## Wings, the burst frame of a Brood Carrier that has just died and the additive pulse ring of a Shrieker. The
## aliens themselves are ordinary SheetLayers of WorldView; this node owns what does not fit the generic path.
## It only reads the world: poses come from `Species` pure functions of (tick, id), the transient bits from the
## "brood" and "shriek" events (aged like the other effects, frozen in screenshot mode).

const BURST_LIFE := 0.5  ## s a brood burst frame stays (held 0.2 s, the mites hatch, then it fades)
const BURST_HOLD := 0.2
const RING_LIFE := 0.55  ## s of the six ring frames
const RING_FRAMES := 6
const RING_SCALE := 3.0  ## the ring art reaches 30 px at frame 5 at 1x: 3x covers the 90 px buff radius (Species.SHRIEK_RADIUS)
const MAX_RINGS := 24
const MAX_BURSTS := 24

var view: WorldView
var frozen: bool = false

var _shadow: SheetLayer  ## glass wings' shadow: normal blend, offset by Gfx.GLASS_SHADOW_OFFSET
var _bursts: Array = []  ## [pos, age, frame, hatched]
var _rings: Array = []  ## [pos, age]
var _ring_node: Node2D


func _ready() -> void:
	_shadow = SheetLayer.new()
	_shadow.position = Gfx.GLASS_SHADOW_OFFSET
	add_child(_shadow)
	_shadow.setup(Gfx.TEX_GLASS_SHADOW, Gfx.ENEMY_DIRS, 4, Gfx.Z_SHADOWS)
	_ring_node = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ring_node.material = add
	_ring_node.z_index = Gfx.Z_GLOW
	_ring_node.draw.connect(_draw_rings)
	add_child(_ring_node)
	z_index = Gfx.Z_ENEMIES


func clear() -> void:
	_bursts.clear()
	_rings.clear()


## Frame sheet row of an alien of `kind` / `id` at `tick` (the generic mite / boulder / spitter rule is id % 2).
static func row_for(kind: int, id: int, tick: int) -> int:
	match kind:
		SimWorld.GLASS:  # flap0..3 (spread, half, edge-on, half); flaps faster in a dive
			return (tick / (2 if Species.glass_diving(tick, id) else 3) + id) % 4
		SimWorld.BROOD:  # pulse0..2 ping-pong 0-1-2-1 (row 3 is the burst frame, shown by the death effect)
			return [0, 1, 2, 1][(tick / 7 + id) % 4]
		SimWorld.SHRIEKER:  # idle, shriek while the pipes charge
			return 1 if Species.shriek_charging(tick, id) else 0
	return id % 2


func begin(expected: int) -> void:
	_shadow.begin(expected)


## A glass wing drawn at `p` (display position) gets its shadow.
func add_glass_shadow(p: Vector2, frame: int, row: int) -> void:
	_shadow.add(p, frame, row)


func finish() -> void:
	_shadow.finish()


## "brood" (kind 1 = hatched, 0 = burned / blasted with it) and "shriek" events.
func on_event(e: Dictionary, age: float) -> void:
	var pos: Vector2 = e.get("pos", Vector2.ZERO)
	match str(e.get("type", "")):
		"brood":
			if _bursts.size() < MAX_BURSTS and age < BURST_LIFE:
				var h: int = Gfx.hash_pos(pos, 11)
				_bursts.append([pos, age, h % Gfx.ENEMY_DIRS, int(e.get("kind", 1)) == 1])
		"shriek":
			if _rings.size() < MAX_RINGS and age < RING_LIFE:
				_rings.append([pos, age])


func _process(delta: float) -> void:
	if not frozen:
		var keep: Array = []
		for b: Array in _bursts:
			b[1] = float(b[1]) + delta
			if float(b[1]) < BURST_LIFE:
				keep.append(b)
		_bursts = keep
		var keep2: Array = []
		for r: Array in _rings:
			r[1] = float(r[1]) + delta
			if float(r[1]) < RING_LIFE:
				keep2.append(r)
		_rings = keep2
	queue_redraw()
	_ring_node.queue_redraw()


## The burst frame of a dying brood carrier: row 3 of the sheet, torn sac with the mites spilling out.
func _draw() -> void:
	for b: Array in _bursts:
		var t: float = float(b[1])
		var cell: Rect2 = Gfx.cell_rect(Gfx.TEX_BROOD, Gfx.ENEMY_DIRS, 4, int(b[2]), 3)
		var p: Vector2 = Gfx.snap(b[0])
		var a: float = 1.0 if t < BURST_HOLD else clampf(1.0 - (t - BURST_HOLD) / (BURST_LIFE - BURST_HOLD), 0.0, 1.0)
		draw_texture_rect_region(Gfx.TEX_BROOD, Rect2(p - cell.size / 2.0, cell.size), cell, Color(1, 1, 1, a))


func _draw_rings() -> void:
	for r: Array in _rings:
		var f: int = clampi(int(float(r[1]) / RING_LIFE * float(RING_FRAMES)), 0, RING_FRAMES - 1)
		var cell: Rect2 = Gfx.cell_rect(Gfx.TEX_SHRIEK_RING, RING_FRAMES, 1, f, 0)
		var size: Vector2 = cell.size * RING_SCALE
		var p: Vector2 = Gfx.snap(r[0])
		_ring_node.draw_texture_rect_region(Gfx.TEX_SHRIEK_RING, Rect2(p - size / 2.0, size), cell, Color(1, 1, 1, 0.9))
