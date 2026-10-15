class_name MenuUi
extends Control
## Front end in the diegetic UI style (design doc 11f): the main menu (logo, Solo / Host / Join /
## Quit, driver profile), the LAN join screen (discovered hosts on a salvaged CRT, direct IP), the
## lobby (roster, paint, ready, start) and the in-match pause / menu overlay.
##
## Pure presentation: main.gd fills the model fields below every frame and reacts to `action`.
## It never touches NetSession, so screenshot scenarios can drive it with fake data.
## Actions: "solo", "host", "join_screen", "quit", "back", "join" (arg: host Dictionary),
## "join_ip" (arg: String), "profile" (arg: [name, color_index]), "ready" (arg: bool), "start",
## "force_start", "leave", "resume", "leave_match".

signal action(name: String, arg: Variant)

enum Screen { NONE, MAIN, JOIN, LOBBY, PAUSE }

const NAME_MAX := SimVehicle.MAX_NAME_LEN
const IP_MAX := 40
const PANEL_W := 196.0
const MAX_ROWS := 8
const BUTTON_H := 24.0

var screen: Screen = Screen.NONE:
	set(value):
		if value != screen:
			_unfocus(true)
			_sel = -1
		screen = value
		visible = value != Screen.NONE

# ---- model (filled by main.gd)
var profile_name: String = SimVehicle.DEFAULT_NAME
var profile_color: int = 0
## Discovered LAN hosts: {"address": String, "port": int, "name": String, "players": int, "state": "lobby"|"match"}.
var hosts: Array[Dictionary] = []
var scanning: bool = true  ## the LAN listener is up (else only direct IP works)
## Lobby roster as NetSession.lobby_players: {"peer_id", "name", "color_index", "ready", "is_host"}.
var lobby_players: Array[Dictionary] = []
var local_peer: int = 1
var is_host: bool = false
var lobby_info: String = ""  ## e.g. "HOSTING ON PORT 24680"
var status: String = ""  ## last error / notice (empty = none)
var status_error: bool = true
var busy: String = ""  ## e.g. "CONNECTING TO 10.0.0.4" (join screen)
var pause_solo: bool = true  ## pause screen: the sim really pauses (solo) or keeps running (LAN)
var ip_text: String = ""

## Screenshot mode: fixed pointer position instead of the real mouse (x < 0 = no pointer).
var pointer_override: Vector2 = Vector2(-1, -1)
var use_real_pointer: bool = true

var _hits: Array = []  # [Rect2, action, arg, enabled], last drawn frame
var _nav: Array = []  # [action, arg] of the enabled buttons, in draw order (keyboard navigation)
var _hover: Array = []
var _sel: int = -1  # keyboard selection index into _nav (-1 = follow the pointer)
var _last_pointer: Vector2 = Vector2(-9, -9)
var _focus: String = ""  # "" | "name" | "ip"
var _edit: String = ""  # name being typed
var _t: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = screen != Screen.NONE


func _process(delta: float) -> void:
	_t += delta
	if visible:
		queue_redraw()


func _pointer() -> Vector2:
	if pointer_override.x >= 0.0 or not use_real_pointer:
		return pointer_override
	return get_local_mouse_position()


func _hit_at(p: Vector2) -> Array:
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if (h[0] as Rect2).has_point(p):
			return h
	return []


func _is_hot(act: String, arg: Variant = null) -> bool:
	if _sel >= 0 and _sel < _nav.size():
		return _nav[_sel][0] == act and _same(_nav[_sel][1], arg)
	return not _hover.is_empty() and _hover[1] == act and _same(_hover[2], arg) and bool(_hover[3])


## Type-safe equality (GDScript errors on == between some mismatched types).
static func _same(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			click_at(mb.position)
		accept_event()


## While the menu is up it owns the keyboard (typing, arrows, Enter, Esc); game keys stay blocked.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed():
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	if _focus != "":
		_type(k)
		return
	if k.is_echo() and k.keycode not in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		return
	match k.keycode:
		KEY_UP, KEY_LEFT:
			_move_sel(-1)
		KEY_DOWN, KEY_RIGHT, KEY_TAB:
			_move_sel(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			if _sel >= 0 and _sel < _nav.size():
				activate(_nav[_sel][0], _nav[_sel][1])
			elif screen == Screen.LOBBY and k.keycode == KEY_SPACE and not is_host:
				activate("ready", not _local_ready())
		KEY_ESCAPE:
			match screen:
				Screen.PAUSE:
					activate("resume", null)
				Screen.JOIN:
					activate("back", null)


func _move_sel(d: int) -> void:
	if _nav.is_empty():
		return
	_sel = posmod((_sel if _sel >= 0 else (-1 if d > 0 else 0)) + d, _nav.size())


func _type(k: InputEventKey) -> void:
	match k.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			var was: String = _focus
			_unfocus(true)
			if was == "ip" and k.keycode != KEY_TAB:
				activate("join_ip", ip_text)
			return
		KEY_ESCAPE:
			_unfocus(false)
			return
		KEY_BACKSPACE:
			if _focus == "name":
				_edit = _edit.left(-1)
			else:
				ip_text = ip_text.left(-1)
			return
	var u: int = k.unicode
	if u < 32 or u > 126:
		return
	var ch: String = String.chr(u)
	if _focus == "name" and _edit.length() < NAME_MAX:
		_edit += ch.to_upper()
	elif _focus == "ip" and ip_text.length() < IP_MAX and (ch.is_valid_int() or ch in ".:-" or ch.to_lower() != ch.to_upper()):
		ip_text += ch


func _focus_field(id: String) -> void:
	if _focus == id:
		return
	_unfocus(true)
	_focus = id
	if id == "name":
		_edit = _shown_name()
	_sel = -1


## Leaves the text field; `commit` sends a changed name as a profile action.
func _unfocus(commit: bool) -> void:
	if _focus == "name" and commit:
		var n: String = SimVehicle.sanitize_name(_edit)
		if n != _shown_name():
			profile_name = n
			action.emit("profile", [n, _shown_color()])
	_focus = ""


## Clicks at `p` (viewport pixels) exactly like the mouse does; used by screenshot scenarios too.
func click_at(p: Vector2) -> bool:
	var h: Array = _hit_at(p)
	if h.is_empty() or not bool(h[3]):
		_unfocus(true)
		return false
	if h[1] == "focus":
		_focus_field(str(h[2]))
		return true
	_unfocus(true)
	activate(h[1], h[2])
	return true


func activate(act: String, arg: Variant) -> void:
	_sel = -1
	if act == "color":
		var c: int = int(arg)
		if c != _shown_color():
			profile_color = c
			action.emit("profile", [_shown_name(), c])
		return
	if act == "focus":
		_focus_field(str(arg))
		return
	action.emit(act, arg)


# ---------------------------------------------------------------- model helpers

func _me() -> Dictionary:
	for e in lobby_players:
		if int(e["peer_id"]) == local_peer:
			return e
	return {}


func _shown_name() -> String:
	var me: Dictionary = _me() if screen == Screen.LOBBY else {}
	return str(me.get("name", profile_name))


func _shown_color() -> int:
	var me: Dictionary = _me() if screen == Screen.LOBBY else {}
	return int(me.get("color_index", profile_color))


func _local_ready() -> bool:
	return bool(_me().get("ready", false))


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var p: Vector2 = _pointer()
	if p != _last_pointer:
		_last_pointer = p
		_sel = -1 if p.x >= 0.0 else _sel
	_hover = _hit_at(p)
	_hits.clear()
	_nav.clear()
	var vs: Vector2 = get_viewport_rect().size
	match screen:
		Screen.MAIN:
			_draw_main(vs)
		Screen.JOIN:
			_draw_join(vs)
		Screen.LOBBY:
			_draw_lobby(vs)
		Screen.PAUSE:
			_draw_pause(vs)


## Dark wash over the battlefield, heavier on the left where the menu sits.
func _backdrop(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.045, 0.05, 0.5))
	var steps: int = 6
	for i in steps:
		var w: float = 250.0 - float(i) * 24.0
		draw_rect(Rect2(0, 0, w, vs.y), Color(0.07, 0.045, 0.05, 0.09))


func _button(r: Rect2, title: String, sub: String, act: String, arg: Variant = null, enabled: bool = true, accent: bool = false) -> void:
	var hot: bool = enabled and _is_hot(act, arg)
	UiKit.steel(self, r, (Color(0.92, 0.9, 0.9) if hot else Color(0.7, 0.67, 0.67)) if enabled else Color(0.45, 0.42, 0.42))
	if hot or (accent and enabled):
		var pulse: bool = hot or fmod(_t, 1.2) < 0.8
		UiKit.hazard_frame(self, r, 2.0, Color.WHITE if pulse else Color(0.75, 0.75, 0.75))
	var tc: Color = Gfx.FIRE[5] if hot else (Gfx.UI_TEXT if enabled else Gfx.UI_DIM)
	var ty: float = r.position.y + (5.0 if sub != "" else floorf((r.size.y - 7.0) / 2.0))
	UiKit.center_big(self, title, r.get_center().x, ty, tc, Gfx.OUTLINE)
	if sub != "":
		UiKit.center_text(self, sub, r.get_center().x, r.position.y + 15, Gfx.UI_TEXT if hot else Gfx.BONE_LIGHT.darkened(0.25), Gfx.OUTLINE)
	if hot:
		UiFont.draw_big(self, ">", Vector2(r.position.x - 9, ty), Gfx.FIRE[4], Gfx.OUTLINE)
	_hits.append([r, act, arg, enabled])
	if enabled:
		_nav.append([act, arg])


## Text field on a CRT strip; returns its rect.
func _field(r: Rect2, id: String, text: String, placeholder: String) -> void:
	var focused: bool = _focus == id
	var hot: bool = _is_hot("focus", id)
	draw_rect(r, Gfx.OUTLINE)
	draw_rect(r.grow(-1.0), Gfx.CRT_BG)
	for y in range(int(r.position.y) + 2, int(r.end.y) - 1, 2):
		draw_rect(Rect2(r.position.x + 1, y, r.size.x - 2, 1), Color(0, 0, 0, 0.18))
	UiKit.outline_rect(self, r.grow(-1.0), Gfx.CRT_HI if focused else (Gfx.CRT_DIM if hot else Color(Gfx.CRT_DIM, 0.5)))
	var tp := Vector2(r.position.x + 4, floorf(r.get_center().y - 3.0))
	var x: float = tp.x
	if text == "" and not focused:
		UiFont.draw(self, placeholder, tp, Gfx.CRT_DIM)
	else:
		x = UiFont.draw(self, text, tp, Gfx.CRT_HI if focused else Gfx.CRT_TEXT)
	if focused and fmod(_t, 0.9) < 0.55:
		draw_rect(Rect2(x + 1, tp.y, 3, 6), Gfx.CRT_HI)
	_hits.append([r, "focus", id, true])


## Tape header with a stencil title (scale 2) and a small line under it.
func _header(title: String, sub: String, x: float, y: float) -> void:
	var tw: float = UiFont.width_big(title, 2) + 20.0
	UiKit.tape(self, Rect2(x, y, tw, 22), Color("#e8dcc4"))
	UiFont.draw_big(self, title, Vector2(x + 10, y + 4), Gfx.INK, Color(0, 0, 0, 0), 2)
	if sub != "":
		UiFont.draw(self, sub, Vector2(x + 4, y + 27), Gfx.UI_TEXT, Gfx.OUTLINE)


func _status_line(cx: float, y: float) -> void:
	if status == "":
		return
	var w: float = UiFont.width(status) + 14.0
	var r := Rect2(floorf(cx - w / 2.0), y, w, 11)
	UiKit.tape(self, r, Color("#e88a6a") if status_error else Color("#e8dcc4"))
	UiFont.draw(self, status, Vector2(r.position.x + 7, y + 3), Gfx.INK)


func _footer(vs: Vector2, text: String) -> void:
	UiFont.draw(self, text, Vector2(12, vs.y - 11), Gfx.UI_DIM, Gfx.OUTLINE)


# ---------------------------------------------------------------- main menu

func _draw_main(vs: Vector2) -> void:
	_backdrop(vs)
	var logo := Vector2(18, 16)
	draw_texture(Gfx.TEX_LOGO, logo)
	_logo_words(logo)
	var tag := "LAST CONVOY STANDING"
	var tw: float = UiFont.width(tag) + 16.0
	var tr := Rect2(logo.x + Gfx.TEX_LOGO.get_width() - tw - 10, logo.y + Gfx.TEX_LOGO.get_height() - 4, tw, 11)
	UiKit.tape(self, tr, Color("#e8dcc4"))
	UiFont.draw(self, tag, Vector2(tr.position.x + 8, tr.position.y + 3), Gfx.INK_RED)

	var bx: float = 40.0
	var by: float = 110.0
	var items: Array = [
		["SOLO RUN", "YOU AND YOUR RIG VS THE HIVE", "solo"],
		["HOST LAN GAME", "OPEN A LOBBY ON THIS NETWORK", "host"],
		["JOIN LAN GAME", "FIND A CONVOY NEARBY", "join_screen"],
		["QUIT", "", "quit"],
	]
	for it: Array in items:
		var h: float = BUTTON_H if it[1] != "" else 18.0
		_button(Rect2(bx, by, 176, h), it[0], it[1], it[2], null, true, it[2] == "solo")
		by += h + 7.0
	_status_line(bx + 88.0, by + 2.0)
	_profile_panel(Rect2(vs.x - PANEL_W - 18, 96, PANEL_W, 196), {})
	_footer(vs, "MOUSE OR ARROWS + ENTER    CLICK THE NAME TO TYPE")


## "BULLET" in bone on the rusty sheet, "HWAVEN" in fire on the steel one (seam at x 177 of the plate).
func _logo_words(o: Vector2) -> void:
	var sheets: Array = [["BULLET", 4.0, 175.0, Gfx.BONE_LIGHT], ["HWAVEN", 180.0, 310.0, Gfx.FIRE[4]]]
	var size: int = 34
	for s: Array in sheets:
		while size > 16 and UiFont.width_title(s[0], size) > (float(s[2]) - float(s[1])) - 14.0:
			size -= 1
	var cap: float = roundf(UiFont.TITLE_CAP * float(size))
	var y: float = o.y + floorf((float(Gfx.TEX_LOGO.get_height()) - cap) / 2.0)
	for s: Array in sheets:
		var w: float = UiFont.width_title(s[0], size)
		var x: float = o.x + floorf((float(s[1]) + float(s[2]) - w) / 2.0)
		UiFont.draw_title(self, s[0], Vector2(x + 1, y + 2), Color(Gfx.OUTLINE, 0.85), size)
		UiFont.draw_title(self, s[0], Vector2(x, y), s[3], size)


# ---------------------------------------------------------------- driver profile

## Name field, paint picker (colours in `taken` are crossed out) and a turning preview of the rig.
func _profile_panel(r: Rect2, taken: Dictionary) -> void:
	UiKit.plate(self, r)
	UiKit.tape_label(self, "DRIVER", r.get_center().x, r.position.y - 4, Color("#e8dcc4"))
	var x0: float = r.position.x + 9.0
	var y: float = r.position.y + 12.0
	UiFont.draw(self, "NAME", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	_field(Rect2(x0, y + 7, r.size.x - 18, 14), "name", _edit if _focus == "name" else _shown_name(), "TYPE A NAME")
	y += 28.0
	var col: int = _shown_color()
	UiFont.draw(self, "PAINT", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var pname: String = Gfx.PLAYER_NAMES[Gfx.color_slot(col)]
	var px: float = r.end.x - 9.0 - UiFont.width(pname)
	UiKit.paint_text(self, pname, Vector2(px, y), col)
	# test strip: paint splats on masking tape
	var n: int = Gfx.PLAYER_COLORS.size()
	var strip := Rect2(x0, y + 8, r.size.x - 18, 24)
	UiKit.tape(self, strip, Color("#ddd3bf"))
	var step: float = floorf((strip.size.x - 6.0) / float(n))
	for i in n:
		var sp := Vector2(strip.position.x + 3.0 + i * step + floorf((step - 16.0) / 2.0), strip.position.y + 4)
		var cell := Rect2(sp - Vector2(1, 2), Vector2(18, 20))
		var is_taken: bool = taken.has(i) and i != col
		UiKit.splat(self, sp, i, 0.3 if is_taken else 1.0)
		if is_taken:
			draw_line(sp + Vector2(2, 2), sp + Vector2(14, 14), Gfx.INK_RED, 1.0)
			draw_line(sp + Vector2(14, 2), sp + Vector2(2, 14), Gfx.INK_RED, 1.0)
		elif i == col:
			UiKit.outline_rect(self, cell, Gfx.INK)
			draw_rect(Rect2(cell.position.x + 6, cell.end.y, 6, 2), Gfx.INK)
		elif _is_hot("color", i):
			UiKit.outline_rect(self, cell, Gfx.INK_RED)
		_hits.append([cell, "color", i, not is_taken])
	y += 38.0
	# turning preview of the rig on a patch of sand
	var pv := Rect2(x0, y, r.size.x - 18, r.end.y - 8 - y)
	draw_rect(pv, Gfx.OUTLINE)
	var inner: Rect2 = pv.grow(-1.0)
	draw_texture_rect_region(Gfx.TEX_GROUND, inner, Rect2(Vector2(372, 214), inner.size))
	var c: Vector2 = inner.get_center().floor()
	var frame: int = int(_t * 5.0) % Gfx.VEHICLE_DIRS
	var tex: Texture2D = Gfx.TEX_BUGGY[Gfx.color_slot(col)]
	var fs: float = float(RigArt.FRAME)
	var src := Rect2(frame * fs, 0, fs, fs)
	draw_texture_rect_region(tex, Rect2(c - Vector2(fs, fs) / 2.0 + Vector2(3, 4), Vector2(fs, fs)), src, Color(0.18, 0.15, 0.24, 0.45))
	draw_texture_rect_region(tex, Rect2(c - Vector2(fs, fs) / 2.0, Vector2(fs, fs)), src)
	var piv: Vector2 = Gfx.snap(Gfx.TURRET_PIVOT.rotated(Gfx.frame_rotation(frame, Gfx.VEHICLE_DIRS)))
	draw_texture_rect_region(Gfx.TEX_TURRET, Rect2(c + piv - Vector2(18, 18), Vector2(36, 36)), Rect2(frame * 36, 0, 36, 36))
	var nm: String = _edit if _focus == "name" else _shown_name()
	UiKit.paint_text(self, nm, Vector2(floorf(c.x - UiFont.width(nm) / 2.0), inner.position.y + 3), col)


# ---------------------------------------------------------------- join screen

func _draw_join(vs: Vector2) -> void:
	_backdrop(vs)
	_header("JOIN A CONVOY", "LAN GAMES ON THIS NETWORK - CLICK ONE TO JOIN", 30, 16)
	var crt := Rect2(30, 62, 380, 160)
	UiKit.steel(self, crt)
	var scr: Rect2 = crt.grow(-6.0)
	draw_rect(scr, Gfx.CRT_BG)
	var cols: Array[float] = [scr.position.x + 11, scr.position.x + 128, scr.position.x + 236, scr.position.x + 286]
	var y: float = scr.position.y + 6.0
	for i in 4:
		UiFont.draw(self, ["HOST", "ADDRESS", "RIGS", "STATUS"][i], Vector2(cols[i], y), Gfx.CRT_DIM)
	y += 8.0
	draw_rect(Rect2(scr.position.x + 4, y, scr.size.x - 8, 1), Gfx.CRT_DIM)
	y += 4.0
	for hd: Dictionary in hosts.slice(0, 8):
		var playing: bool = str(hd.get("state", "lobby")) == "match"
		var full: bool = int(hd.get("players", 0)) >= MAX_ROWS
		var ok: bool = not playing and not full
		var row := Rect2(scr.position.x + 3, y - 2, scr.size.x - 6, 12)
		var hot: bool = ok and _is_hot("join", hd)
		if hot:
			draw_rect(row, Color(Gfx.CRT_DIM, 0.45))
			UiFont.draw(self, ">", Vector2(row.position.x + 1, y + 1), Gfx.CRT_HI)
		var tc: Color = (Gfx.CRT_HI if hot else Gfx.CRT_TEXT) if ok else Color(Gfx.CRT_DIM, 0.8)
		var hn: String = str(hd.get("name", ""))
		UiFont.draw(self, hn if hn != "" else "UNNAMED RIG", Vector2(cols[0], y + 1), tc)
		UiFont.draw(self, "%s:%d" % [hd.get("address", "?"), int(hd.get("port", 0))], Vector2(cols[1], y + 1), tc)
		UiFont.draw(self, "%d/%d" % [int(hd.get("players", 0)), MAX_ROWS], Vector2(cols[2], y + 1), tc)
		UiFont.draw(self, "IN MATCH" if playing else ("FULL" if full else "LOBBY OPEN"), Vector2(cols[3], y + 1), tc)
		if playing:
			draw_rect(Rect2(cols[0], y + 4, UiFont.width(hn if hn != "" else "UNNAMED RIG"), 1), Gfx.CRT_DIM)
		_hits.append([row, "join", hd, ok])
		if ok:
			_nav.append(["join", hd])
		y += 13.0
	if hosts.is_empty():
		var msg: String = "SCANNING THE AIRWAVES" if scanning else "LAN SCAN UNAVAILABLE - USE DIRECT IP"
		UiFont.draw(self, msg + ("..." if scanning else ""), Vector2(cols[0], y + 2), Gfx.CRT_TEXT)
		if scanning and fmod(_t, 1.0) < 0.5:
			draw_rect(Rect2(cols[0] + UiFont.width(msg + "...") + 3, y + 2, 4, 6), Gfx.CRT_TEXT)
	if busy != "":
		var by: float = scr.end.y - 12.0
		draw_rect(Rect2(scr.position.x + 4, by - 4, scr.size.x - 8, 1), Gfx.CRT_DIM)
		UiFont.draw(self, busy + ".".repeat(int(_t * 3.0) % 4), Vector2(cols[0], by), Gfx.CRT_HI)
	for sy in range(int(scr.position.y), int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.16))

	# direct IP
	var ry: float = crt.end.y + 8.0
	UiKit.plate(self, Rect2(crt.position.x, ry, crt.size.x, 30))
	UiFont.draw(self, "DIRECT IP", Vector2(crt.position.x + 8, ry + 12), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	_field(Rect2(crt.position.x + 52, ry + 8, 200, 14), "ip", ip_text, "E.G. 192.168.1.20")
	_button(Rect2(crt.position.x + 260, ry + 6, 112, 18), "CONNECT", "", "join_ip", ip_text, ip_text.strip_edges() != "" and busy == "")
	_button(Rect2(crt.position.x, vs.y - 34, 90, 18), "BACK", "", "back")
	_status_line(crt.position.x + 240.0, vs.y - 30.0)
	_profile_panel(Rect2(vs.x - PANEL_W - 18, 62, PANEL_W, 196), {})


# ---------------------------------------------------------------- lobby

func _draw_lobby(vs: Vector2) -> void:
	_backdrop(vs)
	_header("CONVOY LOBBY", lobby_info, 30, 16)
	var r := Rect2(30, 62, 380, 32 + MAX_ROWS * 21)
	UiKit.plate(self, r)
	UiKit.hazard_band(self, Rect2(r.position.x + 5, r.position.y + 5, r.size.x - 10, 4))
	var ready_n: int = 0
	var need: int = 0
	for e in lobby_players:
		if not bool(e.get("is_host", false)):
			need += 1
			ready_n += 1 if bool(e.get("ready", false)) else 0
	var head: String = "%d / %d RIGS" % [lobby_players.size(), MAX_ROWS]
	UiFont.draw(self, head, Vector2(r.position.x + 10, r.position.y + 14), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var rd: String = "%d / %d READY" % [ready_n, need] if need > 0 else "WAITING FOR DRIVERS"
	UiFont.draw(self, rd, Vector2(r.end.x - 10 - UiFont.width(rd), r.position.y + 14), Gfx.HAZARD if need > 0 and ready_n == need else Gfx.UI_DIM, Gfx.UI_SHADOW)
	var taken: Dictionary = {}
	var y: float = r.position.y + 24.0
	for i in MAX_ROWS:
		var row := Rect2(r.position.x + 6, y, r.size.x - 12, 19)
		draw_rect(row, Color(0.06, 0.04, 0.04, 0.35 if i % 2 == 0 else 0.2))
		UiFont.draw_big(self, str(i + 1), Vector2(row.position.x + 5, y + 6), Gfx.UI_DIM, Gfx.OUTLINE)
		if i >= lobby_players.size():
			UiFont.draw(self, "- OPEN SLOT -", Vector2(row.position.x + 40, y + 7), Color(Gfx.UI_DIM, 0.6))
			y += 21.0
			continue
		var e: Dictionary = lobby_players[i]
		var ci: int = int(e.get("color_index", 0))
		var me: bool = int(e.get("peer_id", 0)) == local_peer
		if not me:
			taken[ci] = true
		if me:
			UiKit.outline_rect(self, row, Gfx.UI_TEXT)
		UiKit.splat(self, Vector2(row.position.x + 17, y + 2), ci)
		var nm: String = str(e.get("name", "?"))
		var nx: float = UiKit.paint_big(self, nm, Vector2(row.position.x + 40, y + 6), ci)
		if me:
			nx = UiFont.draw(self, "(YOU)", Vector2(nx + 5, y + 8), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		if bool(e.get("is_host", false)):
			var hr := Rect2(nx + 6, y + 5, 26, 9)
			UiKit.tape(self, hr, Gfx.HAZARD.lightened(0.25))
			UiFont.draw(self, "HOST", Vector2(hr.position.x + 5, y + 7), Gfx.INK)
		var st: String
		var sc: Color
		if bool(e.get("is_host", false)):
			st = "CALLS THE START"
			sc = Gfx.UI_DIM
		elif bool(e.get("ready", false)):
			st = "READY"
			sc = Gfx.HAZARD
		else:
			st = "NOT READY"
			sc = Gfx.UI_BAD
		if st == "READY":
			var sw: float = UiFont.width_big(st) + 10.0
			var sr := Rect2(row.end.x - 6 - sw, y + 3, sw, 13)
			UiKit.outline_rect(self, sr, sc)
			UiFont.draw_big(self, st, Vector2(sr.position.x + 5, y + 6), sc, Gfx.OUTLINE)
		else:
			UiFont.draw(self, st, Vector2(row.end.x - 10 - UiFont.width(st), y + 8), sc, Gfx.UI_SHADOW)
		y += 21.0

	# buttons
	var by: float = r.end.y + 8.0
	if is_host:
		var all_ready: bool = ready_n == need
		_button(Rect2(r.position.x, by, 150, BUTTON_H), "ROLL OUT", "START THE MATCH" if all_ready else "WAITING FOR READY", "start", null, all_ready, all_ready)
		if not all_ready:
			_button(Rect2(r.position.x + 158, by, 112, BUTTON_H), "FORCE START", "DON'T WAIT", "force_start")
	else:
		var rdy: bool = _local_ready()
		_button(Rect2(r.position.x, by, 150, BUTTON_H), "NOT READY" if rdy else "READY UP", "SPACE - TOGGLE" if rdy else "SPACE - I AM READY", "ready", not rdy, true, not rdy)
		var wait: String = "WAITING FOR THE HOST TO ROLL OUT"
		UiFont.draw(self, wait, Vector2(r.position.x + 160, by + 10), Gfx.UI_DIM, Gfx.OUTLINE)
	_button(Rect2(r.end.x - 90, by, 90, BUTTON_H), "LEAVE", "", "leave")
	_status_line(r.get_center().x, by + BUTTON_H + 6.0)
	_profile_panel(Rect2(vs.x - PANEL_W - 18, 62, PANEL_W, 196), taken)


# ---------------------------------------------------------------- pause / menu overlay

func _draw_pause(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.07, 0.045, 0.05, 0.6))
	var cx: float = floorf(vs.x / 2.0)
	var r := Rect2(cx - 130, 62, 260, 214)
	UiKit.plate(self, r)
	UiKit.hazard_band(self, Rect2(r.position.x + 5, r.position.y + 5, r.size.x - 10, 5))
	UiKit.center_big(self, "PAUSED" if pause_solo else "MENU", cx, r.position.y + 18, Gfx.UI_TEXT, Gfx.OUTLINE, 2)
	var sub: String = "THE HIVE WAITS FOR YOU" if pause_solo else "THE FIGHT GOES ON - YOUR RIG DRIVES ITSELF"
	UiKit.center_text(self, sub, cx, r.position.y + 38, Gfx.UI_DIM, Gfx.UI_SHADOW)
	_button(Rect2(cx - 90, r.position.y + 52, 180, BUTTON_H), "RESUME", "ESC", "resume", null, true, true)
	_button(Rect2(cx - 90, r.position.y + 82, 180, BUTTON_H), "LEAVE TO MENU", "ABANDON THIS RUN" if pause_solo else "DISCONNECT FROM THE CONVOY", "leave_match")
	# controls card on the salvaged terminal
	var crt := Rect2(r.position.x + 10, r.position.y + 116, r.size.x - 20, r.size.y - 126)
	UiKit.steel(self, crt)
	var scr: Rect2 = crt.grow(-4.0)
	draw_rect(scr, Gfx.CRT_BG)
	var lines: Array = [
		["1 2 3", "DRIVE: CIRCLE / KITE / CHARGE"],
		["Q W E", "TARGET: NEAREST / STRONGEST / PLAYERS"],
		["WORKSHOP", ""],
		["1 2 3", "PICK A CARD"],
		["R", "REROLL THE OFFERS"],
		["SPACE", "READY - ROLL OUT"],
		["ESC", "THIS MENU"],
	]
	var y: float = scr.position.y + 5.0
	UiFont.draw(self, "> CONTROLS", Vector2(scr.position.x + 5, y), Gfx.CRT_HI)
	y += 10.0
	for l: Array in lines:
		if l[1] == "":
			UiFont.draw(self, str(l[0]), Vector2(scr.position.x + 5, y), Gfx.CRT_DIM)
		else:
			UiFont.draw(self, str(l[0]), Vector2(scr.position.x + 12, y), Gfx.CRT_HI)
			UiFont.draw(self, str(l[1]), Vector2(scr.position.x + 62, y), Gfx.CRT_TEXT)
		y += 9.0
	for sy in range(int(scr.position.y), int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.16))
