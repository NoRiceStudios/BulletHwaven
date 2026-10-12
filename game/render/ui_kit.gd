class_name UiKit
extends RefCounted
## Shared drawing helpers and text for the diegetic UI (design doc section 11f): rusty plates,
## steel housings, tinted masking tape, hazard stripes, icons, and the card / tech effect text.
## Card and tech numbers are read from sim/cards.gd and sim/tech.gd, never duplicated here.

static var _plate: StyleBoxTexture = null
static var _steel: StyleBoxTexture = null
static var _tape: StyleBoxTexture = null

## Tape tint behind black-paint names.
const PAINT_TAPE := Color("#d6cfbf")


static func _box(tex: Texture2D) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_texture_margin_all(4)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


## Rusty riveted plate (the mock-up HUD panels).
static func plate(ci: CanvasItem, r: Rect2, modulate: Color = Color.WHITE) -> void:
	if _plate == null:
		_plate = _box(Gfx.TEX_UI_PLATE)
	_plate.modulate_color = modulate
	ci.draw_style_box(_plate, r)


## Bare steel plate (CRT housing, buttons, tech nodes).
static func steel(ci: CanvasItem, r: Rect2, modulate: Color = Color.WHITE) -> void:
	if _steel == null:
		_steel = _box(Gfx.TEX_STEEL)
	_steel.modulate_color = modulate
	ci.draw_style_box(_steel, r)


## Masking tape strip tinted `tint` (9-slice, so the torn ends stay crisp at any size).
static func tape(ci: CanvasItem, r: Rect2, tint: Color = Color.WHITE) -> void:
	if _tape == null:
		_tape = _box(Gfx.TEX_TAPE)
		_tape.set_texture_margin_all(3)
	_tape.modulate_color = tint
	ci.draw_style_box(_tape, r)


## Tape label with small dark text, centred on `center_x` (returns the tape rect).
static func tape_label(ci: CanvasItem, text: String, center_x: float, y: float, tint: Color = Color.WHITE) -> Rect2:
	var w: float = PixelFont.width(text) + 10.0
	var r := Rect2(floorf(center_x - w / 2.0), y, w, 9)
	tape(ci, r, tint)
	PixelFont.draw(ci, text, Vector2(r.position.x + 5, y + 2), Gfx.INK)
	return r


## Hazard-striped frame (thickness `t`) around `r`.
static func hazard_frame(ci: CanvasItem, r: Rect2, t: float = 3.0, modulate: Color = Color.WHITE) -> void:
	for band: Rect2 in [Rect2(r.position, Vector2(r.size.x, t)), Rect2(r.position.x, r.end.y - t, r.size.x, t),
			Rect2(r.position.x, r.position.y + t, t, r.size.y - 2.0 * t), Rect2(r.end.x - t, r.position.y + t, t, r.size.y - 2.0 * t)]:
		ci.draw_texture_rect_region(Gfx.TEX_HAZARD, band, Rect2(band.position, band.size), modulate)
	outline_rect(ci, r, Gfx.OUTLINE)


## Plain hazard-striped band filling `r`, with a dark edge.
static func hazard_band(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_texture_rect_region(Gfx.TEX_HAZARD, r, Rect2(r.position, r.size))
	outline_rect(ci, r.grow(1.0), Gfx.OUTLINE)


## 1px rectangle outline inside `r` (pixel exact; draw_rect(filled=false) blurs half pixels).
static func outline_rect(ci: CanvasItem, r: Rect2, col: Color) -> void:
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), col)
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), col)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 1, 1, r.size.y - 2), col)
	ci.draw_rect(Rect2(r.end.x - 1, r.position.y + 1, 1, r.size.y - 2), col)


static func icon(ci: CanvasItem, name: String, pos: Vector2, modulate: Color = Color.WHITE) -> void:
	var i: int = Gfx.ICON_NAMES.find(name)
	if i < 0:
		return
	var s: float = Gfx.ICON_SIZE
	ci.draw_texture_rect_region(Gfx.TEX_ICONS, Rect2(pos.floor(), Vector2(s, s)), Rect2(i * s, 0, s, s), modulate)


## Horizontal bar with a dark frame; `frac` 0..1.
static func bar(ci: CanvasItem, r: Rect2, frac: float, col: Color) -> void:
	ci.draw_rect(r, Gfx.OUTLINE)
	var inner := r.grow(-1.0)
	var fill: float = floorf(inner.size.x * clampf(frac, 0.0, 1.0))
	if fill > 0.0:
		ci.draw_rect(Rect2(inner.position, Vector2(fill, inner.size.y)), col)
		ci.draw_rect(Rect2(inner.position, Vector2(fill, 1)), col.lightened(0.25))


static func center_text(ci: CanvasItem, text: String, cx: float, y: float, col: Color, shadow: Color = Color(0, 0, 0, 0)) -> void:
	PixelFont.draw(ci, text, Vector2(floorf(cx - PixelFont.width(text) / 2.0), y), col, shadow)


static func center_big(ci: CanvasItem, text: String, cx: float, y: float, col: Color, shadow: Color = Color(0, 0, 0, 0), scale: int = 1) -> void:
	PixelFont.draw_big(ci, text, Vector2(floorf(cx - PixelFont.width_big(text, scale) / 2.0), y), col, shadow, scale)


## "m:ss" for a tick count (rounded up, so 0:00 only when the timer has run out).
static func clock(ticks: int) -> String:
	var secs: int = ceili(float(maxi(ticks, 0)) / float(SimWorld.TICK_RATE))
	return "%d:%02d" % [secs / 60, secs % 60]


static func num(x: float) -> String:
	if is_equal_approx(x, roundf(x)):
		return str(roundi(x))
	return ("%.1f" % x) if absf(x * 10.0 - roundf(x * 10.0)) < 0.01 else ("%.2f" % x)


static func pct(x: float) -> String:
	return "%d%%" % roundi(x * 100.0)


## The driver's name (sanitised by the sim, printable ASCII).
static func player_name(v: SimVehicle) -> String:
	return v.player_name


static func player_color(v: SimVehicle) -> Color:
	return Gfx.PLAYER_COLORS[Gfx.player_index(v)]


## Text in paint colour `color_index` (small font) with a dark drop shadow. Black paint is sprayed
## on a strip of masking tape instead, so it stays readable on dark plates and night ground.
## Returns the x after the text.
static func paint_text(ci: CanvasItem, text: String, pos: Vector2, color_index: int) -> float:
	var slot: int = Gfx.color_slot(color_index)
	if slot == Gfx.DARK_PAINT:
		tape(ci, Rect2(pos.floor() - Vector2(3, 2), Vector2(PixelFont.width(text) + 6.0, 9)), PAINT_TAPE)
		return PixelFont.draw(ci, text, pos, Gfx.PLAYER_COLORS[slot])
	return PixelFont.draw(ci, text, pos, Gfx.PLAYER_COLORS[slot], Gfx.OUTLINE)


## The same in the stencil font (lobby roster).
static func paint_big(ci: CanvasItem, text: String, pos: Vector2, color_index: int) -> float:
	var slot: int = Gfx.color_slot(color_index)
	if slot == Gfx.DARK_PAINT:
		tape(ci, Rect2(pos.floor() - Vector2(4, 2), Vector2(PixelFont.width_big(text) + 8.0, 11)), PAINT_TAPE)
		return PixelFont.draw_big(ci, text, pos, Gfx.PLAYER_COLORS[slot])
	return PixelFont.draw_big(ci, text, pos, Gfx.PLAYER_COLORS[slot], Gfx.OUTLINE)


## A fill colour for bars and swatches on dark UI: the paint, or steel grey for black paint.
static func bar_color(color_index: int) -> Color:
	var slot: int = Gfx.color_slot(color_index)
	return Gfx.STEEL[4] if slot == Gfx.DARK_PAINT else Gfx.PLAYER_COLORS[slot]


## Small square paint chip inside `r` (1px dark frame; black paint gets a light frame).
static func swatch(ci: CanvasItem, r: Rect2, color_index: int) -> void:
	var slot: int = Gfx.color_slot(color_index)
	ci.draw_rect(r, Gfx.STEEL[4] if slot == Gfx.DARK_PAINT else Gfx.OUTLINE)
	ci.draw_rect(r.grow(-1.0), Gfx.PLAYER_COLORS[slot])
	ci.draw_rect(Rect2(r.position + Vector2.ONE, Vector2(r.size.x - 2.0, 1)), Gfx.PLAYER_COLORS[slot].lightened(0.3))


## Paint splat swatch (16x16) in paint colour `color_index`, top-left at `pos`.
static func splat(ci: CanvasItem, pos: Vector2, color_index: int, alpha: float = 1.0) -> void:
	var col: Color = Gfx.PLAYER_COLORS[Gfx.color_slot(color_index)]
	col.a = alpha
	ci.draw_texture(Gfx.TEX_SPLAT, pos.floor(), col)


# ---------------------------------------------------------------- card and tech text

## One line per effect key (amounts as given: per level for cards, flat for tech).
static func fx_lines(fx: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for k: String in fx:
		var a: float = float(fx[k])
		var sgn: String = "+" if a >= 0.0 else "-"
		var m: float = absf(a)
		match k:
			"hp": out.append("%s%s MAX HP" % [sgn, num(m)])
			"armor": out.append("%s%s ARMOUR" % [sgn, num(m)])
			"speed": out.append("%s%s SPEED" % [sgn, pct(m)])
			"turn": out.append("%s%s TURNING" % [sgn, pct(m)])
			"scrap": out.append("%s%s SCRAP" % [sgn, pct(m)])
			"regen": out.append("%s%s HP/S REPAIR" % [sgn, num(m)])
			"contact": out.append("%s%s RAM DMG/TICK" % [sgn, num(m)])
			"ram": out.append("%s%s CHARGE RAM" % [sgn, pct(m)])
			"vulture": out.append("%s%s DMG VS WOUNDED" % [sgn, pct(m)])
			"dmg": out.append("%s%s WEAPON DMG" % [sgn, pct(m)])
			"range": out.append("%s%s RANGE" % [sgn, pct(m)])
			"rate": out.append("%s%s FIRE RATE" % [sgn, pct(m)])
			"slots": out.append("%s%s WEAPON SLOT" % [sgn, num(m)])
			"interest": out.append("%s%s INTEREST CAP" % [sgn, num(m)])
			_: out.append("%s %s" % [k.to_upper(), num(a)])
	return out


## Weapon stats at `level` (1..3) as [damage text, range, shots per second, pierce, splash].
static func _weapon_stats(id: String, level: int) -> Dictionary:
	var b: Dictionary = Cards.WEAPONS[id]
	var li: int = clampi(level, 1, Cards.MAX_LEVEL) - 1
	var pel: int = int((b["pellets"] as Array)[li])
	var dmg: String = num(float((b["damage"] as Array)[li]))
	return {
		"DMG": dmg + ("X%d" % pel if pel > 1 else ""),
		"RANGE": num(float((b["range"] as Array)[li])),
		"RATE": ("%.1f" % (float(SimWorld.TICK_RATE) / float((b["cooldown"] as Array)[li]))).trim_suffix(".0") + "/S",
		"PIERCE": str(int((b["pierce"] as Array)[li])),
		"SPLASH": num(float((b["splash"] as Array)[li])),
	}


## Short effect text of card `id` when going from `level` to `level + 1` (level 0 = new card).
static func card_lines(id: String, level: int) -> PackedStringArray:
	if Cards.is_weapon(id):
		var out := PackedStringArray()
		var nxt: Dictionary = _weapon_stats(id, level + 1)
		if level == 0:
			for k: String in ["DMG", "RANGE", "RATE", "PIERCE", "SPLASH"]:
				if (k == "PIERCE" or k == "SPLASH") and (nxt[k] == "0"):
					continue
				out.append("%s %s" % [k, nxt[k]])
		else:
			var cur: Dictionary = _weapon_stats(id, level)
			for k: String in ["DMG", "RANGE", "RATE", "PIERCE", "SPLASH"]:
				if cur[k] != nxt[k]:
					out.append("%s %s>%s" % [k, cur[k], nxt[k]])
		return out
	var d: Dictionary = Cards.def(id)
	return fx_lines(d.get("fx", {}))


static func card_name(id: String) -> String:
	return str(Cards.def(id).get("name", id)).to_upper()


static func card_category(id: String) -> String:
	return str(Cards.def(id).get("category", ""))


## Icon cell for a card: weapons have their own, the rest use the category icon.
static func card_icon(id: String) -> String:
	return id if Cards.is_weapon(id) else card_category(id)


static func card_color(id: String) -> Color:
	return Gfx.CATEGORY_COLORS.get(card_category(id), Color.WHITE)


static func tech_name(id: String) -> String:
	return str(Tech.def(id).get("name", id)).to_upper()


static func tech_lines(id: String) -> PackedStringArray:
	return fx_lines(Tech.def(id).get("fx", {}))
