class_name PixelFont
extends RefCounted
## The artgen 3x5 pixel font (assets/font_3x5.png: one 4x5 cell per glyph, white on transparent).

const CHARS := " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.+-/()!',"
const CELL_W := 4
const HEIGHT := 5

static var _widths: PackedInt32Array = PackedInt32Array()


static func _ensure_widths() -> void:
	if not _widths.is_empty():
		return
	var img: Image = Gfx.TEX_FONT.get_image()
	_widths.resize(CHARS.length())
	for i in CHARS.length():
		var w: int = 0
		for x in CELL_W:
			for y in HEIGHT:
				if img.get_pixel(i * CELL_W + x, y).a > 0.5:
					w = x + 1
		_widths[i] = w if w > 0 else 2  # space
	return


static func width(text: String) -> int:
	_ensure_widths()
	var w: int = 0
	for ch in text.to_upper():
		var i: int = CHARS.find(ch)
		w += (_widths[i] if i >= 0 else 3) + 1
	return maxi(0, w - 1)


## Draws `text` with its top-left at `pos`; returns the x after the last glyph.
static func draw(ci: CanvasItem, text: String, pos: Vector2, color: Color, shadow: Color = Color(0, 0, 0, 0)) -> float:
	_ensure_widths()
	if shadow.a > 0.0:
		draw(ci, text, pos + Vector2.ONE, shadow)
	var x: float = floorf(pos.x)
	var y: float = floorf(pos.y)
	for ch in text.to_upper():
		var i: int = CHARS.find(ch)
		if i < 0:
			x += 4.0
			continue
		var w: int = _widths[i]
		if i > 0:
			ci.draw_texture_rect_region(Gfx.TEX_FONT, Rect2(x, y, w, HEIGHT), Rect2(i * CELL_W, 0, w, HEIGHT), color)
		x += float(w + 1)
	return x
