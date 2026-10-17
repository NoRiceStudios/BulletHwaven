class_name UiFont
extends RefCounted
## UI text (design doc section 11f). The HUD and menus are laid out in 640x360 units but drawn on
## the full-resolution root canvas (the world alone renders at 640x360), so text is set in real
## fonts that stay crisp at any integer scale:
## - body:  Barlow Semi Condensed SemiBold, 8 units (cap height ~5.6, the old 3x5 cell row)
## - big:   Barlow Condensed ExtraBold, 10 units per `scale` step (headings, numbers)
## - title: Black Ops One, the stencil display face (screen titles and the logo only)
## All text is upper case. `pos` is the top-left corner of the capitals, as with the old pixel font,
## so callers keep laying text out in rows; `shadow` is drawn a hair down-right.

const BODY_FONT := preload("res://assets/fonts/BarlowSemiCondensed-SemiBold.ttf")
const BIG_FONT := preload("res://assets/fonts/BarlowCondensed-ExtraBold.ttf")
const TITLE_FONT := preload("res://assets/fonts/BlackOpsOne-Regular.ttf")

const SIZE := 8
const SMALL_SIZE := 7  ## dense fine print (card effects, info boxes)
const HEIGHT := 6  ## capital height in 640x360 units (rounded up)
const BIG_SIZE := 10
const BIG_HEIGHT := 7
const CAP := 0.70  ## Barlow cap height / em
const TITLE_CAP := 0.648  ## Black Ops One cap height / em
const SHADOW_OFFSET := Vector2(0.67, 0.67)  ## two screen pixels at 1080p

static var _body: FontVariation = null
static var _big: FontVariation = null
static var _title: FontVariation = null


static func _variant(base: FontFile, spacing: int) -> FontVariation:
	base.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	base.hinting = TextServer.HINTING_NONE
	base.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_ONE_QUARTER
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = spacing
	# tabular figures: timers and counters do not wobble as digits change
	f.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	return f


static func _ensure() -> void:
	if _body == null:
		_body = _variant(BODY_FONT, 0)
		_big = _variant(BIG_FONT, 0)
		_title = _variant(TITLE_FONT, 0)


static func body_font() -> Font:
	_ensure()
	return _body


static func width(text: String) -> int:
	_ensure()
	return ceili(_body.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x)


static func width_big(text: String, scale: int = 1) -> int:
	_ensure()
	return ceili(_big.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, BIG_SIZE * scale).x)


static func width_title(text: String, size: int) -> int:
	_ensure()
	return ceili(_title.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)


static func _put(ci: CanvasItem, f: Font, size: int, cap: float, text: String, pos: Vector2, color: Color, shadow: Color) -> float:
	var t: String = text.to_upper()
	var base := Vector2(floorf(pos.x), floorf(pos.y) + roundf(cap * float(size) * 3.0) / 3.0)
	if shadow.a > 0.0:
		ci.draw_string(f, base + SHADOW_OFFSET * maxf(1.0, float(size) / 12.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, shadow)
	ci.draw_string(f, base, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return base.x + f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Body text with its top-left at `pos`; returns the x after the last glyph.
static func draw(ci: CanvasItem, text: String, pos: Vector2, color: Color, shadow: Color = Color(0, 0, 0, 0)) -> float:
	_ensure()
	return _put(ci, _body, SIZE, CAP, text, pos, color, shadow)


## Fine print (7 units, cap ~4.9): dense lists where the body size does not fit.
static func draw_small(ci: CanvasItem, text: String, pos: Vector2, color: Color, shadow: Color = Color(0, 0, 0, 0)) -> float:
	_ensure()
	return _put(ci, _body, SMALL_SIZE, CAP, text, pos, color, shadow)


static func width_small(text: String) -> int:
	_ensure()
	return ceili(_body.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL_SIZE).x)


## Heading / number face; `scale` multiplies the size (2 = big counters).
static func draw_big(ci: CanvasItem, text: String, pos: Vector2, color: Color, shadow: Color = Color(0, 0, 0, 0), scale: int = 1) -> float:
	_ensure()
	return _put(ci, _big, BIG_SIZE * scale, CAP, text, pos, color, shadow)


## Heading face at any `size` (units) with a dark rim on all four sides, for numbers drawn over the
## busy battlefield (the kill combo). Returns the x after the last glyph.
static func draw_big_rim(ci: CanvasItem, text: String, pos: Vector2, color: Color, rim: Color, size: int, title: bool = false) -> float:
	_ensure()
	var f: Font = _title if title else _big
	var cap: float = TITLE_CAP if title else CAP
	var t: String = text.to_upper()
	var base := Vector2(floorf(pos.x), floorf(pos.y) + roundf(cap * float(size) * 3.0) / 3.0)
	var o: float = SHADOW_OFFSET.x * maxf(1.0, float(size) / 14.0)
	for d: Vector2 in [Vector2(-o, 0), Vector2(o, 0), Vector2(0, -o), Vector2(0, o), Vector2(o, o) * 1.5]:
		ci.draw_string(f, base + d, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, rim)
	ci.draw_string(f, base, t, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	return base.x + f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func width_big_px(text: String, size: int, title: bool = false) -> int:
	_ensure()
	return ceili((_title if title else _big).get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)


## Stencil display face at `size` units (screen titles).
static func draw_title(ci: CanvasItem, text: String, pos: Vector2, color: Color, size: int, shadow: Color = Color(0, 0, 0, 0)) -> float:
	_ensure()
	return _put(ci, _title, size, TITLE_CAP, text, pos, color, shadow)


static func _wrap(text: String, max_w: int, measure: Callable) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var cand: String = word if line == "" else line + " " + word
		if line != "" and int(measure.call(cand)) > max_w:
			out.append(line)
			line = word
		else:
			line = cand
	if line != "":
		out.append(line)
	return out


## Greedy word wrap for the body font.
static func wrap(text: String, max_w: int) -> PackedStringArray:
	return _wrap(text, max_w, func(s: String) -> int: return width(s))


## Greedy word wrap for the fine print.
static func wrap_small(text: String, max_w: int) -> PackedStringArray:
	return _wrap(text, max_w, func(s: String) -> int: return width_small(s))


## Greedy word wrap for the heading font.
static func wrap_big(text: String, max_w: int) -> PackedStringArray:
	return _wrap(text, max_w, func(s: String) -> int: return width_big(s))
