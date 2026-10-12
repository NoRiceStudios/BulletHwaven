class_name DecalLayer
extends Node2D
## Persistent ground marks (goo, carcasses, scorch, tyre tracks) for the whole match.
## New marks are drawn exactly once into an arena-sized SubViewport that is never cleared, so the
## cost stays constant no matter how many marks pile up ("late in the match, the map tells the
## story of the fights", design doc section 11e).

const TRACK_COLOR := Color(0.2, 0.13, 0.1, 0.16)

var _vp: SubViewport
var _painter: Node2D
var _display: Sprite2D
## Each stamp: [texture, src Rect2, dest Rect2, modulate Color] or a track segment
## [null, Rect2(from), Rect2(to), Color, width].
var _stamps: Array[Array] = []
var _in_draw: int = 0  ## stamps recorded by the painter's last _draw
var _drawn: int = 0  ## stamps confirmed rendered into the viewport (safe to drop)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SimWorld.ARENA.size)
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_painter = Node2D.new()
	_painter.draw.connect(_on_painter_draw)
	_vp.add_child(_painter)
	_display = Sprite2D.new()
	_display.centered = false
	_display.position = SimWorld.ARENA.position
	_display.texture = _vp.get_texture()
	add_child(_display)
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)


func clear() -> void:
	_stamps.clear()
	_drawn = 0
	_in_draw = 0
	if _vp != null:
		_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE


## Stamps cell (col, row) of a decal sheet centred at `pos`.
func stamp(tex: Texture2D, cols: int, rows: int, col: int, row: int, pos: Vector2, modulate_color: Color = Color.WHITE) -> void:
	var src: Rect2 = Gfx.cell_rect(tex, cols, rows, col, row)
	var dst := Rect2(Gfx.snap(pos - SimWorld.ARENA.position - src.size / 2.0), src.size)
	_stamps.append([tex, src, dst, modulate_color])


## A rut segment under one wheel (butt-capped line, so consecutive segments barely overlap).
func track(from: Vector2, to: Vector2, width: float = 3.0) -> void:
	var o: Vector2 = SimWorld.ARENA.position
	_stamps.append([null, Rect2(Gfx.snap(from - o), Vector2.ZERO), Rect2(Gfx.snap(to - o), Vector2.ZERO), TRACK_COLOR, width])


func _process(_delta: float) -> void:
	if _drawn > 0:
		_stamps = _stamps.slice(_drawn)
		_drawn = 0
		_in_draw = 0
		_painter.queue_redraw()  # an empty redraw keeps already baked marks from being re-blended
	if not _stamps.is_empty():
		_painter.queue_redraw()


func _on_painter_draw() -> void:
	for s in _stamps:
		var tex: Texture2D = s[0]
		if tex == null:
			_painter.draw_line(s[1].position, s[2].position, s[3], s[4])
		else:
			_painter.draw_texture_rect_region(tex, s[2], s[1], s[3])
	_in_draw = _stamps.size()


## Only drop stamps after a frame that really rendered them (the first frames after start-up can
## be processed without being drawn).
func _on_frame_drawn() -> void:
	_drawn = _in_draw
