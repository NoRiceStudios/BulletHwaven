class_name PixelFont
extends RefCounted
## The artgen pixel fonts (white on transparent, one cell per glyph, variable width):
## - small: assets/font_3x5.png, 4x5 cells (body text)
## - big:   assets/font_stencil.png, 6x7 cells, the spray-painted stencil font (headings)
## `scale` draws a font at an integer multiple (titles only).

const CHARS := " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:.+-/()!',%><?*=#"
const CELL_W := 4
const HEIGHT := 5
const BIG_CHARS := " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789:!-'./+%"
const BIG_CELL_W := 6
const BIG_HEIGHT := 7

static var _widths: PackedInt32Array = PackedInt32Array()
static var _big_widths: PackedInt32Array = PackedInt32Array()


static func _measure(tex: Texture2D, chars: String, cell: int, h: int) -> PackedInt32Array:
	var img: Image = tex.get_image()
	var out := PackedInt32Array()
	out.resize(chars.length())
	for i in chars.length():
		var w: int = 0
		for x in cell:
			for y in h:
				if img.get_pixel(i * cell + x, y).a > 0.5:
					w = x + 1
		out[i] = w if w > 0 else (2 if cell == CELL_W else 3)  # space
	return out


static func _ensure_widths() -> void:
	if _widths.is_empty():
		_widths = _measure(Gfx.TEX_FONT, CHARS, CELL_W, HEIGHT)
		_big_widths = _measure(Gfx.TEX_STENCIL, BIG_CHARS, BIG_CELL_W, BIG_HEIGHT)


static func width(text: String) -> int:
	_ensure_widths()
	var w: int = 0
	for ch in text.to_upper():
		var i: int = CHARS.find(ch)
		w += (_widths[i] if i >= 0 else 3) + 1
	return maxi(0, w - 1)


static func width_big(text: String, scale: int = 1) -> int:
	_ensure_widths()
	var w: int = 0
	for ch in text.to_upper():
		var i: int = BIG_CHARS.find(ch)
		w += (_big_widths[i] if i >= 0 else 4) + 1
	return maxi(0, w - 1) * scale


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


## Stencil heading font; `shadow` is drawn 1 * scale px down-right.
static func draw_big(ci: CanvasItem, text: String, pos: Vector2, color: Color, shadow: Color = Color(0, 0, 0, 0), scale: int = 1) -> float:
	_ensure_widths()
	if shadow.a > 0.0:
		draw_big(ci, text, pos + Vector2.ONE * scale, shadow, Color(0, 0, 0, 0), scale)
	var x: float = floorf(pos.x)
	var y: float = floorf(pos.y)
	var s: float = float(scale)
	for ch in text.to_upper():
		var i: int = BIG_CHARS.find(ch)
		if i < 0:
			x += 5.0 * s
			continue
		var w: int = _big_widths[i]
		if i > 0:
			ci.draw_texture_rect_region(Gfx.TEX_STENCIL, Rect2(x, y, w * s, BIG_HEIGHT * s), Rect2(i * BIG_CELL_W, 0, w, BIG_HEIGHT), color)
		x += float(w + 1) * s
	return x


## Greedy word wrap for the small font.
static func wrap(text: String, max_w: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var cand: String = word if line == "" else line + " " + word
		if line != "" and width(cand) > max_w:
			out.append(line)
			line = word
		else:
			line = cand
	if line != "":
		out.append(line)
	return out


## Greedy word wrap for the stencil font.
static func wrap_big(text: String, max_w: int) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var cand: String = word if line == "" else line + " " + word
		if line != "" and width_big(cand) > max_w:
			out.append(line)
			line = word
		else:
			line = cand
	if line != "":
		out.append(line)
	return out
