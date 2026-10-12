class_name WorkshopUi
extends Control
## Workshop overlay (phase == PHASE_WORKSHOP, design doc sections 5, 6 and 11f): the convoy camps
## on the darkened battlefield; three draft cards as manila scrap tags, the tech tree, the doctrine
## CRT terminal, loadout, scrap / fuel, the timer and READY.
##
## Immediate-mode UI: _draw() lays everything out and records hit rects; clicks and keys go
## through activate(), which only ever sends commands through `send_command` (NetSession in play,
## the world directly in screenshot mode). All state comes from the local player's vehicle.
## Keys: 1/2/3 pick, R reroll, Space ready.

const CARD_SIZE := Vector2(100, 122)
const CARD_Y := 160.0
const CARD_GAP := 8.0
const LEFT_X := 6.0
const COL_W := 146.0
const RIGHT_X := 488.0
const DRIVES: PackedStringArray = ["circle", "kite", "charge"]
const TARGETS: PackedStringArray = ["nearest", "strongest", "players_first"]
const TARGET_LABELS := {"nearest": "NEAREST", "strongest": "STRONGEST", "players_first": "PLAYERS 1ST"}
const DRIVE_HELP := {"circle": "ORBITS THE SWARM, GUNS OUT", "kite": "KEEPS ITS DISTANCE", "charge": "RAMS STRAIGHT IN"}
const TARGET_HELP := {"nearest": "SHOOTS WHAT IS CLOSEST", "strongest": "FOCUSES THE BIG ONES", "players_first": "RIVAL RIGS BEFORE ALIENS"}
const TOAST_SECS := 1.6

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null
## Callable(cmd: Dictionary): where commands go (NetSession.send_command or the world directly).
var send_command: Callable = Callable()
## Screenshot mode: fixed pointer position instead of the real mouse (x < 0 = no pointer).
var pointer_override: Vector2 = Vector2(-1, -1)
var use_real_pointer: bool = true

var _hits: Array = []  # [Rect2, action: String, arg: Variant], last drawn frame
var _hover: Array = []  # the hit under the pointer ([] = none)
var _offers_cache: Array[String] = []  # last non-empty offers (to show what was picked)
var _offers_round: int = -1
var _picked_index: int = -1
var _toast: String = ""
var _toast_left: float = 0.0
var _blink: float = 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false


func _process(delta: float) -> void:
	visible = world != null and world.phase == SimWorld.PHASE_WORKSHOP and _local() != null
	_toast_left = maxf(_toast_left - delta, 0.0)
	_blink += delta
	if visible:
		queue_redraw()


func _local() -> SimVehicle:
	return world.get_vehicle_for_peer(local_peer) if world != null else null


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


func _is_hover(action: String, arg: Variant = null) -> bool:
	return not _hover.is_empty() and _hover[1] == action and (arg == null or _hover[2] == arg)


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			click_at(mb.position)
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key: Key = (event as InputEventKey).keycode
	var handled: bool = true
	match key:
		KEY_1, KEY_2, KEY_3:
			activate("pick", int(key - KEY_1))
		KEY_R:
			activate("reroll", null)
		KEY_SPACE, KEY_ENTER:
			activate("ready", null)
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Clicks at `p` (viewport pixels) exactly like the mouse does; used by screenshot scenarios too.
func click_at(p: Vector2) -> bool:
	var h: Array = _hit_at(p)
	if h.is_empty():
		return false
	activate(h[1], h[2])
	return true


## Every button, card, node and key ends here. Illegal actions only show a toast.
func activate(action: String, arg: Variant) -> void:
	var v: SimVehicle = _local()
	if v == null or world.phase != SimWorld.PHASE_WORKSHOP:
		return
	match action:
		"pick":
			var i: int = int(arg)
			if v.picked or v.eliminated:
				_say("PART ALREADY FITTED")
			elif i < 0 or i >= v.offers.size():
				_say("NO SUCH PART")
			else:
				_picked_index = i
				_send({"type": "pick_card", "value": i})
		"reroll":
			if v.picked:
				_say("ALREADY FITTED A PART")
			elif v.scrap < v.reroll_cost:
				_say("NEED %d SCRAP TO REROLL" % v.reroll_cost)
			else:
				_send({"type": "reroll"})
		"tech":
			var id: String = str(arg)
			if v.tech.has(id):
				_say("ALREADY BUILT")
			elif Tech.prerequisite(id) != "" and not v.tech.has(Tech.prerequisite(id)):
				_say("BUILD %s FIRST" % UiKit.tech_name(Tech.prerequisite(id)))
			elif v.scrap < Tech.cost(id):
				_say("NEED %d SCRAP" % Tech.cost(id))
			else:
				_send({"type": "buy_tech", "value": id})
		"drive":
			_send({"type": "set_drive", "value": str(arg)})
		"target":
			_send({"type": "set_target", "value": str(arg)})
		"ready":
			if not v.ready:
				_send({"type": "ready"})


func _send(cmd: Dictionary) -> void:
	if send_command.is_valid():
		send_command.call(cmd)


func _say(text: String) -> void:
	_toast = text
	_toast_left = TOAST_SECS


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var v: SimVehicle = _local()
	if v == null:
		return
	if not v.offers.is_empty():
		if _offers_round != world.round or _offers_cache != v.offers:
			_picked_index = -1
		_offers_cache = v.offers.duplicate()
		_offers_round = world.round
	_hover = _hit_at(_pointer())
	_hits.clear()
	var vs: Vector2 = get_viewport_rect().size

	var c: Vector2 = view.local_screen_pos() if view else Vector2(vs.x / 2.0, 90)
	var vig := Vector2(Gfx.TEX_VIGNETTE.get_size())
	draw_texture(Gfx.TEX_VIGNETTE, (c - vig / 2.0).floor())

	_draw_header(vs)
	_draw_status(v)
	_draw_terminal(v)
	_draw_loadout(v)
	_draw_cards(v, vs)
	_draw_tech(v)
	_draw_ready(v, vs)
	if _toast_left > 0.0:
		var tr: Rect2 = UiKit.tape_label(self, _toast, floorf(vs.x / 2.0), 300, Color("#f0b090"))
		_hits.append([tr, "none", null])
	UiKit.center_text(self, "1 2 3 PICK   R REROLL   SPACE READY   CLICK TECH TO BUILD", floorf(vs.x / 2.0), vs.y - 9, Gfx.UI_DIM, Gfx.OUTLINE)


func _draw_header(vs: Vector2) -> void:
	var r := Rect2(floorf(vs.x / 2.0) - 92, 4, 184, 30)
	UiKit.plate(self, r)
	PixelFont.draw_big(self, "WORKSHOP", r.position + Vector2(7, 6), Gfx.UI_TEXT, Gfx.OUTLINE)
	PixelFont.draw(self, "AFTER ROUND %d" % world.round, r.position + Vector2(7, 18), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var t: String = UiKit.clock(world.phase_ticks_left)
	var low: bool = world.phase_ticks_left < 5 * SimWorld.TICK_RATE
	var col: Color = Gfx.UI_BAD if low and fmod(_blink, 0.5) < 0.25 else Gfx.FIRE[4]
	PixelFont.draw_big(self, t, Vector2(r.end.x - 7 - PixelFont.width_big(t, 2), r.position.y + 7), col, Gfx.OUTLINE, 2)
	PixelFont.draw(self, "ROLL OUT IN", Vector2(r.end.x - 11 - PixelFont.width_big(t, 2) - PixelFont.width("ROLL OUT IN"), r.position.y + 18), Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_status(v: SimVehicle) -> void:
	var r := Rect2(LEFT_X, 4, COL_W, 38)
	UiKit.plate(self, r)
	UiKit.icon(self, "scrap", r.position + Vector2(4, 4))
	PixelFont.draw_big(self, str(v.scrap), r.position + Vector2(22, 5), Gfx.UI_TEXT, Gfx.OUTLINE, 2)
	PixelFont.draw(self, "SCRAP", r.position + Vector2(4, 22), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var interest: int = mini(v.scrap / SimWorld.INTEREST_PER, v.interest_cap)
	PixelFont.draw(self, "INTEREST +%d" % interest, r.position + Vector2(4, 30), Gfx.FIRE[4], Gfx.UI_SHADOW)
	var fx: float = r.position.x + 82.0
	UiKit.icon(self, "fuel", Vector2(fx, r.position.y + 4))
	var fcol: Color = Gfx.FIRE[3] if v.fuel > 40 else Gfx.UI_BAD
	PixelFont.draw_big(self, str(maxi(v.fuel, 0)), Vector2(fx + 18, r.position.y + 6), fcol, Gfx.OUTLINE)
	PixelFont.draw(self, "FUEL", Vector2(fx, r.position.y + 22), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiKit.bar(self, Rect2(fx, r.position.y + 30, r.end.x - fx - 5, 5), float(v.fuel) / float(SimWorld.START_FUEL), fcol)


# ---------------------------------------------------------------- doctrine terminal

func _draw_terminal(v: SimVehicle) -> void:
	var r := Rect2(LEFT_X, 46, COL_W, 86)
	UiKit.steel(self, r)
	var scr := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 14))
	draw_rect(scr, Gfx.CRT_BG)
	# rounded tube corners
	for p: Vector2 in [scr.position, Vector2(scr.end.x - 1, scr.position.y), Vector2(scr.position.x, scr.end.y - 1), scr.end - Vector2.ONE]:
		draw_rect(Rect2(p, Vector2.ONE), Gfx.STEEL[1])
	var x0: float = scr.position.x + 4.0
	var y: float = scr.position.y + 4.0
	var px: float = PixelFont.draw(self, "> DOCTRINE.SYS", Vector2(x0, y), Gfx.CRT_DIM)
	if fmod(_blink, 1.0) < 0.5:
		draw_rect(Rect2(px + 2, y, 3, 5), Gfx.CRT_TEXT)
	y += 9.0
	PixelFont.draw(self, "DRIVE", Vector2(x0, y), Gfx.CRT_DIM)
	y += 7.0
	var x: float = x0
	for d in DRIVES:
		x = _crt_chip(d.to_upper(), Vector2(x, y), v.doctrine["drive"] == d, "drive", d) + 3.0
	y += 10.0
	PixelFont.draw(self, "TARGET", Vector2(x0, y), Gfx.CRT_DIM)
	y += 7.0
	x = x0
	for t in TARGETS:
		x = _crt_chip(TARGET_LABELS[t], Vector2(x, y), v.doctrine["target"] == t, "target", t) + 3.0
	y += 11.0
	var help: String = DRIVE_HELP.get(str(v.doctrine["drive"]), "")
	var help2: String = TARGET_HELP.get(str(v.doctrine["target"]), "")
	if not _hover.is_empty() and (_hover[1] == "drive" or _hover[1] == "target"):
		help = (DRIVE_HELP if _hover[1] == "drive" else TARGET_HELP).get(str(_hover[2]), "")
		help2 = ""
	PixelFont.draw(self, help, Vector2(x0, y), Gfx.CRT_TEXT)
	PixelFont.draw(self, help2, Vector2(x0, y + 7), Gfx.CRT_TEXT)
	# scanlines and a faint top glare
	for sy in range(int(scr.position.y) + 1, int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(scr.position.x + 2, scr.position.y + 1, scr.size.x - 4, 1), Color(1, 0.8, 0.5, 0.08))
	# housing label + power lamp
	PixelFont.draw(self, "COLONY NAV-COMP", Vector2(r.position.x + 6, r.end.y - 8), Gfx.STEEL[4], Gfx.STEEL[0])
	draw_rect(Rect2(r.end.x - 10, r.end.y - 7, 3, 3), Gfx.CRT_TEXT)


func _crt_chip(text: String, pos: Vector2, on: bool, action: String, arg: String) -> float:
	var w: float = PixelFont.width(text) + 4.0
	var r := Rect2(pos - Vector2(2, 1), Vector2(w, 7))
	var hov: bool = _is_hover(action, arg)
	if on:
		draw_rect(r, Gfx.CRT_TEXT)
		PixelFont.draw(self, text, pos, Gfx.CRT_BG)
	else:
		if hov:
			UiKit.outline_rect(self, r, Gfx.CRT_DIM)
		PixelFont.draw(self, text, pos, Gfx.CRT_HI if hov else Gfx.CRT_TEXT)
	_hits.append([r, action, arg])
	return r.end.x


# ---------------------------------------------------------------- loadout

func _draw_loadout(v: SimVehicle) -> void:
	var rows: int = v.cards.size()
	var r := Rect2(LEFT_X, 140, COL_W, 15 + rows * 9 + 24 + (8 if v.regen > 0.0 else 0))
	UiKit.plate(self, r)
	UiKit.tape_label(self, "RIG LOADOUT", r.position.x + 36, r.position.y - 3)
	var slots := "GUNS %d/%d" % [Cards.weapon_cards_owned(v), v.weapon_slots]
	PixelFont.draw(self, slots, Vector2(r.end.x - 6 - PixelFont.width(slots), r.position.y + 6), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var y: float = r.position.y + 15.0
	for id: String in v.cards:
		var lvl: int = int(v.cards[id])
		draw_rect(Rect2(r.position.x + 6, y, 5, 5), UiKit.card_color(id))
		UiKit.outline_rect(self, Rect2(r.position.x + 5, y - 1, 7, 7), Gfx.OUTLINE)
		PixelFont.draw(self, UiKit.card_name(id), Vector2(r.position.x + 15, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		for k in Cards.MAX_LEVEL:
			var pr := Rect2(r.end.x - 21 + k * 5, y + 1, 4, 3)
			draw_rect(pr.grow(1.0), Gfx.OUTLINE)
			draw_rect(pr, Gfx.FIRE[4] if k < lvl else Gfx.UI_PLATE_DARK)
		y += 9.0
	y += 4.0
	draw_rect(Rect2(r.position.x + 5, y - 3, r.size.x - 10, 1), Gfx.OUTLINE)
	var l1 := "HP %d  ARMOUR %s" % [roundi(v.max_hp), UiKit.num(v.armor)]
	var l2 := "SPEED %s  SCRAP X%s" % [UiKit.pct(v.speed), UiKit.num(v.scrap_mult)]
	PixelFont.draw(self, l1, Vector2(r.position.x + 6, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	PixelFont.draw(self, l2, Vector2(r.position.x + 6, y + 8), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var l3 := "REPAIR %s/S" % UiKit.num(v.regen) if v.regen > 0.0 else ""
	if l3 != "":
		PixelFont.draw(self, l3, Vector2(r.position.x + 6, y + 16), Gfx.UI_DIM, Gfx.UI_SHADOW)


# ---------------------------------------------------------------- draft cards

func _draw_cards(v: SimVehicle, vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var total: float = 3.0 * CARD_SIZE.x + 2.0 * CARD_GAP
	var x0: float = cx - floorf(total / 2.0)
	var showing: Array[String] = v.offers
	var picked_view: bool = false
	if v.picked:
		picked_view = true
		showing = _offers_cache if _offers_round == world.round else ([] as Array[String])
	var title: String = "PICK ONE PART - FREE" if not v.picked else "PART FITTED"
	UiKit.tape_label(self, title, cx, CARD_Y - 15.0, Color("#e8dcc4"))
	if showing.is_empty():
		var msg := "THE CREW IS BOLTING IT ON" if v.picked else "NO PARTS LEFT IN THE PILE"
		UiKit.center_text(self, msg, cx, CARD_Y + 50.0, Gfx.UI_TEXT, Gfx.OUTLINE)
	for i in showing.size():
		var id: String = showing[i]
		var pos := Vector2(x0 + i * (CARD_SIZE.x + CARD_GAP), CARD_Y)
		var hov: bool = not picked_view and _is_hover("pick", i)
		var state: int = 0  # 0 offer, 1 fitted, 2 scrapped
		if picked_view:
			state = 1 if i == _picked_index else 2
		_draw_card(id, i, pos + (Vector2(0, -3) if hov else Vector2.ZERO), int(v.cards.get(id, 0)) - (1 if state == 1 else 0), hov, state)
		if not picked_view:
			_hits.append([Rect2(pos, CARD_SIZE), "pick", i])
	# reroll button
	var rr := Rect2(cx - 50, CARD_Y + CARD_SIZE.y + 6.0, 100, 15)
	var can: bool = not v.picked and v.scrap >= v.reroll_cost
	var hov_r: bool = _is_hover("reroll")
	UiKit.steel(self, rr, Color.WHITE if can else Color(0.6, 0.55, 0.55))
	if hov_r and can:
		UiKit.outline_rect(self, rr, Gfx.HAZARD)
	var label := "REROLL"
	var cost := "%d" % v.reroll_cost
	var lw: float = PixelFont.width(label) + 6.0 + 9.0 + PixelFont.width(cost)
	var lx: float = floorf(cx - lw / 2.0)
	PixelFont.draw(self, label, Vector2(lx, rr.position.y + 5), Gfx.UI_TEXT if can else Gfx.UI_DIM, Gfx.OUTLINE)
	_scrap_pip(Vector2(lx + PixelFont.width(label) + 6, rr.position.y + 5))
	PixelFont.draw(self, cost, Vector2(lx + PixelFont.width(label) + 15, rr.position.y + 5),
		(Gfx.FIRE[4] if can else (Gfx.UI_BAD if not v.picked else Gfx.UI_DIM)), Gfx.OUTLINE)
	_hits.append([rr, "reroll", null])


## One draft card. `level` = owned level before the pick (0 = new).
func _draw_card(id: String, index: int, pos: Vector2, level: int, hov: bool, state: int) -> void:
	var mod: Color = Color.WHITE if state != 2 else Color(0.5, 0.45, 0.45)
	# drop shadow, then the tag
	var sh := Rect2(pos + Vector2(3, 6 if hov else 3), CARD_SIZE - Vector2(4, 4))
	draw_rect(sh, Color(0.08, 0.05, 0.06, 0.45))
	if hov:  # work lamp under the hovered tag
		draw_rect(Rect2(pos.x + 8, pos.y + CARD_SIZE.y + 4, CARD_SIZE.x - 16, 2), Gfx.HAZARD)
		draw_rect(Rect2(pos.x + 8, pos.y + CARD_SIZE.y + 6, CARD_SIZE.x - 16, 1), Gfx.OUTLINE)
	draw_texture(Gfx.TEX_CARD, pos, mod)
	var ink: Color = Gfx.INK * mod
	var cat: String = UiKit.card_category(id)
	var cat_col: Color = UiKit.card_color(id)
	# category tape
	var tr := Rect2(pos + Vector2(8, 14), Vector2(CARD_SIZE.x - 16, 9))
	UiKit.tape(self, tr, cat_col * mod)
	PixelFont.draw(self, cat.to_upper(), tr.position + Vector2(4, 2), ink)
	var rar: String = str(Cards.def(id).get("rarity", "")).to_upper()
	PixelFont.draw(self, rar, Vector2(tr.end.x - 4 - PixelFont.width(rar), tr.position.y + 2), ink)
	# stencilled name, up to two lines
	var lines: PackedStringArray = PixelFont.wrap_big(UiKit.card_name(id), int(CARD_SIZE.x) - 12)
	var y: float = pos.y + 27.0
	for ln in lines.slice(0, 2):
		UiKit.center_big(self, ln, pos.x + CARD_SIZE.x / 2.0, y, ink)
		y += 9.0
	# icon in an inspection-stamp box + level
	var iy: float = pos.y + 47.0
	var stamp := Rect2(pos.x + 9, iy, 22, 22)
	UiKit.outline_rect(self, stamp, Gfx.INK_RED * mod)
	UiKit.outline_rect(self, stamp.grow(-1.0), Color(Gfx.INK_RED, 0.35) * mod)
	UiKit.icon(self, UiKit.card_icon(id), stamp.position + Vector2(3, 3), mod)
	var lx: float = pos.x + 37.0
	if level == 0:
		PixelFont.draw_big(self, "NEW", Vector2(lx, iy + 2), Gfx.INK_RED * mod)
	else:
		PixelFont.draw(self, "LV %d > %d" % [level, level + 1], Vector2(lx, iy + 3), ink)
	for k in Cards.MAX_LEVEL:
		var pr := Rect2(lx + k * 9, iy + 13, 7, 5)
		UiKit.outline_rect(self, pr, ink)
		if k < level:
			draw_rect(pr.grow(-1.0), ink)
		elif k == level:
			draw_rect(pr.grow(-1.0), Gfx.INK_RED * mod)
	# effect text
	y = pos.y + 74.0
	for ln in UiKit.card_lines(id, level):
		for sub in PixelFont.wrap(ln, int(CARD_SIZE.x) - 16):
			if y > pos.y + 104.0:
				break
			PixelFont.draw(self, sub, Vector2(pos.x + 9, y), ink)
			y += 7.0
	# footer: key hint
	if state == 0:
		var key := "%d" % (index + 1)
		var kr := Rect2(pos.x + 8, pos.y + CARD_SIZE.y - 15, 9, 9)
		draw_rect(kr, ink)
		PixelFont.draw(self, key, kr.position + Vector2(3, 2), Gfx.BONE_LIGHT)
		PixelFont.draw(self, "PICK" if not hov else "FIT IT", Vector2(kr.end.x + 3, kr.position.y + 2), ink)
		if Cards.is_weapon(id) and level == 0:
			var slot := "+1 GUN"
			PixelFont.draw(self, slot, Vector2(pos.x + CARD_SIZE.x - 9 - PixelFont.width(slot), kr.position.y + 2), Gfx.INK_RED)
	elif state == 1:
		var st := Rect2(pos.x + 7, pos.y + 45, CARD_SIZE.x - 14, 26)
		draw_rect(st, Color(Gfx.BONE_LIGHT, 0.92))
		UiKit.outline_rect(self, st, Gfx.INK_RED)
		UiKit.outline_rect(self, st.grow(-2.0), Gfx.INK_RED)
		UiKit.center_big(self, "FITTED", st.get_center().x, st.position.y + 6, Gfx.INK_RED, Color(0, 0, 0, 0), 2)


# ---------------------------------------------------------------- tech tree

func _draw_tech(v: SimVehicle) -> void:
	var r := Rect2(RIGHT_X, 4, COL_W, 196)
	UiKit.plate(self, r)
	PixelFont.draw_big(self, "TECH", r.position + Vector2(6, 5), Gfx.UI_TEXT, Gfx.OUTLINE)
	PixelFont.draw(self, "BUILT FOR SCRAP", r.position + Vector2(36, 6), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var hover_id: String = ""
	var y: float = r.position.y + 17.0
	for b in Tech.BRANCHES:
		UiKit.icon(self, b, Vector2(r.position.x + 4, y + 4))
		PixelFont.draw(self, b.to_upper(), Vector2(r.position.x + 22, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		for t in Tech.MAX_TIER:
			var id: String = "%s_%d" % [b, t + 1]
			var nr := Rect2(r.position.x + 22 + t * 41, y + 8, 37, 13)
			if t > 0:
				draw_rect(Rect2(nr.position.x - 4, nr.position.y + 6, 4, 1), Gfx.OUTLINE)
			_draw_tech_node(v, id, nr)
			_hits.append([nr, "tech", id])
			if _is_hover("tech", id):
				hover_id = id
		y += 27.0
	# info box: hovered node, else the cheapest thing you can build next
	var info := Rect2(r.position.x + 4, y + 1, r.size.x - 8, r.end.y - y - 5)
	draw_rect(info, Color(0.08, 0.05, 0.06, 0.55))
	var show_id: String = hover_id
	if show_id == "":
		for b in Tech.BRANCHES:
			var nid: String = "%s_%d" % [b, Tech.branch_tier(v, b) + 1]
			if Tech.has(nid) and Tech.can_buy(v, nid) and (show_id == "" or Tech.cost(nid) < Tech.cost(show_id)):
				show_id = nid
	if show_id == "":
		PixelFont.draw(self, "SAVE SCRAP FOR TECH", info.position + Vector2(3, 3), Gfx.UI_DIM)
		PixelFont.draw(self, "+1 INTEREST PER 10 HELD", info.position + Vector2(3, 11), Gfx.UI_DIM)
		return
	var td: Dictionary = Tech.def(show_id)
	PixelFont.draw(self, "%s %s" % [str(td["branch"]).to_upper(), "I".repeat(int(td["tier"]))], info.position + Vector2(3, 3), Gfx.UI_DIM)
	PixelFont.draw(self, UiKit.tech_name(show_id), info.position + Vector2(3, 10), Gfx.UI_TEXT)
	var ly: float = info.position.y + 18.0
	for ln in UiKit.tech_lines(show_id):
		PixelFont.draw(self, ln, Vector2(info.position.x + 3, ly), Gfx.FIRE[4])
		ly += 7.0
	var pre: String = Tech.prerequisite(show_id)
	var status: String
	var scol: Color = Gfx.UI_DIM
	if v.tech.has(show_id):
		status = "BUILT"
	elif pre != "" and not v.tech.has(pre):
		status = "NEEDS %s FIRST" % UiKit.tech_name(pre)
		scol = Gfx.UI_BAD
	elif v.scrap < Tech.cost(show_id):
		status = "%d MORE SCRAP" % (Tech.cost(show_id) - v.scrap)
		scol = Gfx.UI_BAD
	else:
		status = "CLICK TO BUILD - %d SCRAP" % Tech.cost(show_id)
		scol = Gfx.HAZARD
	for ln in PixelFont.wrap(status, int(info.size.x) - 6):
		PixelFont.draw(self, ln, Vector2(info.position.x + 3, ly + 2), scol)
		ly += 7.0


func _draw_tech_node(v: SimVehicle, id: String, nr: Rect2) -> void:
	var owned: bool = v.tech.has(id)
	var pre: String = Tech.prerequisite(id)
	var unlocked: bool = pre == "" or v.tech.has(pre)
	var cost: int = Tech.cost(id)
	var afford: bool = v.scrap >= cost
	var hov: bool = _is_hover("tech", id)
	if owned:
		draw_rect(nr, Gfx.OUTLINE)
		draw_rect(nr.grow(-1.0), Gfx.BRASS[2])
		draw_rect(Rect2(nr.position + Vector2.ONE, Vector2(nr.size.x - 2, 1)), Gfx.BRASS[3])
		UiKit.center_text(self, "BUILT", nr.get_center().x, nr.position.y + 4, Gfx.INK)
		return
	if not unlocked:
		draw_rect(nr, Gfx.UI_DIM if hov else Gfx.OUTLINE)
		draw_rect(nr.grow(-1.0), Gfx.STEEL[1])
		UiKit.center_text(self, str(cost), nr.get_center().x, nr.position.y + 4, Gfx.STEEL[3])
		return
	UiKit.steel(self, nr, Color.WHITE if afford else Color(0.75, 0.7, 0.7))
	if afford:
		UiKit.outline_rect(self, nr, Gfx.HAZARD if (hov or fmod(_blink, 1.2) < 0.9) else Gfx.OUTLINE)
	elif hov:
		UiKit.outline_rect(self, nr, Gfx.UI_BAD)
	var txt := str(cost)
	var tw: float = PixelFont.width(txt) + 2.0 + 7.0
	var tx: float = floorf(nr.get_center().x - tw / 2.0)
	_scrap_pip(Vector2(tx, nr.position.y + 4))
	PixelFont.draw(self, txt, Vector2(tx + 9, nr.position.y + 4), Gfx.UI_TEXT if afford else Gfx.UI_BAD, Gfx.OUTLINE)


## Tiny 5x5 scrap marker (a nut) for prices.
func _scrap_pip(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(1, 0), Vector2(5, 5)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(0, 1), Vector2(7, 3)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(5, 3)), Gfx.STEEL[4])
	draw_rect(Rect2(p + Vector2(3, 2), Vector2(1, 1)), Gfx.OUTLINE)


# ---------------------------------------------------------------- ready

func _draw_ready(v: SimVehicle, vs: Vector2) -> void:
	var n: int = world.vehicles.size()
	var r := Rect2(RIGHT_X, vs.y - 18 - 46 - n * 8, COL_W, 46 + n * 8)
	UiKit.plate(self, r)
	PixelFont.draw(self, "CONVOY", r.position + Vector2(6, 5), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var y: float = r.position.y + 14.0
	var ready_n: int = 0
	var need: int = 0
	for o in world.vehicles:
		UiKit.swatch(self, Rect2(r.position.x + 5, y - 1, 7, 7), o.color_index)
		var nx: float = UiKit.paint_text(self, UiKit.player_name(o), Vector2(r.position.x + 15, y), o.color_index)
		if o == v:
			PixelFont.draw(self, "(YOU)", Vector2(nx + 3, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		var st: String = "OUT" if o.eliminated else ("READY" if o.ready else "TINKERING")
		var sc: Color = Gfx.UI_DIM if o.eliminated else (Gfx.HAZARD if o.ready else Gfx.UI_DIM)
		PixelFont.draw(self, st, Vector2(r.end.x - 6 - PixelFont.width(st), y), sc, Gfx.UI_SHADOW)
		if not o.eliminated:
			need += 1
			ready_n += 1 if o.ready else 0
		y += 8.0
	var br := Rect2(r.position.x + 5, r.end.y - 30, r.size.x - 10, 25)
	var hov: bool = _is_hover("ready")
	if v.ready:
		UiKit.steel(self, br, Color(0.6, 0.55, 0.55))
		UiKit.center_big(self, "WAITING", br.get_center().x, br.position.y + 5, Gfx.UI_DIM, Gfx.OUTLINE)
		UiKit.center_text(self, "%d / %d READY" % [ready_n, need], br.get_center().x, br.position.y + 15, Gfx.UI_DIM, Gfx.OUTLINE)
	else:
		UiKit.steel(self, br)
		UiKit.hazard_frame(self, br, 3.0, Color.WHITE if hov or fmod(_blink, 1.0) < 0.6 else Color(0.75, 0.75, 0.75))
		UiKit.center_big(self, "ROLL OUT", br.get_center().x, br.position.y + 6, Gfx.FIRE[5] if hov else Gfx.UI_TEXT, Gfx.OUTLINE)
		UiKit.center_text(self, "SPACE - I AM READY", br.get_center().x, br.position.y + 16, Gfx.UI_DIM, Gfx.OUTLINE)
	_hits.append([br, "ready", null])
