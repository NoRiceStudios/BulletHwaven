class_name WorkshopUi
extends Control
## Workshop overlay (phase == PHASE_WORKSHOP, design doc sections 5, 6 and 11f): the convoy camps
## on the darkened battlefield; three draft cards as manila scrap tags, the tech tree, the doctrine
## CRT terminal, loadout, scrap / fuel, the timer and READY.
##
## Immediate-mode UI: _draw() lays everything out and records hit rects; clicks and keys go
## through activate(), which only ever sends commands through `send_command` (NetSession in play,
## the world directly in screenshot mode). All state comes from the local player's vehicle.
## Keys: 1/2/3 pick, R reroll, Space ready, H apply the recap's doctrine hint, P the rule editor
## (DoctrineEditor, opened through `open_rules`).
##
## Information UI (playtest round 1 #2, #5, #10): a LAST ROUND recap strip under the header (what
## wrecked you, damage by source, earnings, fuel, a clickable doctrine hint), interest as
## interest_for / interest_cap_for, an UNDERDOG badge, the fuel-drain notice, and scouting: hover a
## convoy row for a rival's dossier in the tech column (click pins it). An eliminated player gets a
## read-only spectator panel instead of the shop (standings + scouting).

const CARD_SIZE := Vector2(100, 122)
const CARD_Y := 160.0
const CARD_GAP := 8.0
const LEFT_X := 6.0
const COL_W := 146.0
const RIGHT_X := 488.0
const DRIVES: PackedStringArray = ["circle", "kite", "charge"]
const TARGETS: PackedStringArray = ["nearest", "strongest", "players_first"]
const TARGET_LABELS := {"nearest": "NEAREST", "strongest": "STRONGEST", "players_first": "PLAYERS 1ST", "weakest": "WEAKEST",
	"boulders": "BOULDERS", "spitters": "SPITTERS"}
const DRIVE_HELP := {"circle": "ORBITS THE SWARM, GUNS OUT", "kite": "KEEPS ITS DISTANCE", "charge": "RAMS STRAIGHT IN"}
const TARGET_HELP := {"nearest": "SHOOTS WHAT IS CLOSEST", "strongest": "FOCUSES THE BIG ONES", "players_first": "RIVAL RIGS BEFORE ALIENS",
	"weakest": "FINISHES OFF THE WOUNDED", "boulders": "CRACKS BOULDERS FIRST", "spitters": "HUNTS SPITTERS FIRST"}
const TOAST_SECS := 1.6
const RECAP_X := 160.0
const RECAP_Y := 40.0
const RECAP_W := 320.0
const DRAIN_NOTICE_TICKS := 150  ## the "-N FUEL DRAIN" tape flashes this long after the drain
const STANDINGS_Y := 172.0  ## spectator panel: top of the standings plate

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null
## Callable(cmd: Dictionary): where commands go (NetSession.send_command or the world directly).
var send_command: Callable = Callable()
## Callable(scope: String): opens the rule editor (DoctrineEditor.open), set by WorldView.
var open_rules: Callable = Callable()
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
var _scout_pin: int = -1  ## vehicle id whose dossier is pinned in the tech column (-1 = none)
var _hint: Dictionary = {}  ## doctrine hint of the recap, computed once per round (before any click)
var _hint_key: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
		KEY_H:
			activate("hint", 0)
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
	if v.eliminated and action in ["pick", "reroll", "tech", "drive", "target", "ready", "hint", "rules"]:
		return  # spectator: read-only
	match action:
		"hint":
			var opts: Array = _hint.get("options", [])
			var i: int = int(arg)
			if i >= 0 and i < opts.size():
				var opt: Dictionary = opts[i]
				if Recap.applied(v, opt):
					_say("ALREADY SET")
				else:
					_send(opt["cmd"])
					_say("DOCTRINE: %s" % str(opt["label"]).trim_prefix("SET ").trim_prefix("TARGET "))
		"scout":
			_scout_pin = -1 if _scout_pin == int(arg) else int(arg)
		"unscout":
			_scout_pin = -1
		"watch":
			_scout_pin = int(arg)
			if view != null:
				view.spectate_vehicle(int(arg))
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
		"rules":
			if open_rules.is_valid():
				open_rules.call(Doctrine.SCOPE_RIG)
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

	if v.eliminated:
		_draw_spectator(v, vs)
		return
	_draw_header(vs)
	_draw_recap(v)
	_draw_status(v)
	_draw_terminal(v)
	_draw_underdog(v)
	_draw_loadout(v)
	_draw_cards(v, vs)
	var scout: SimVehicle = _scout_target()
	if scout != null:
		_draw_dossier(scout, Rect2(RIGHT_X, 4, COL_W, 196), _scout_pin == scout.id)
	else:
		_draw_tech(v)
	_draw_ready(v, vs)
	if _toast_left > 0.0:
		var tr: Rect2 = UiKit.tape_label(self, _toast, floorf(vs.x / 2.0), 300, Color("#f0b090"))
		_hits.append([tr, "none", null])
	UiKit.footer(self, "1 2 3  PICK      R  REROLL      SPACE  READY      CLICK TECH TO BUILD", vs)


func _draw_header(vs: Vector2) -> void:
	var r := Rect2(floorf(vs.x / 2.0) - 92, 4, 184, 30)
	UiKit.plate(self, r)
	UiFont.draw_big(self, "WORKSHOP", r.position + Vector2(7, 6), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw(self, "AFTER ROUND %d" % world.round, r.position + Vector2(7, 18), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var t: String = UiKit.clock(world.phase_ticks_left)
	var low: bool = world.phase_ticks_left < 5 * SimWorld.TICK_RATE
	var col: Color = Gfx.UI_BAD if low and fmod(_blink, 0.5) < 0.25 else Gfx.FIRE[4]
	UiFont.draw_big(self, t, Vector2(r.end.x - 7 - UiFont.width_big(t, 2), r.position.y + 7), col, Gfx.OUTLINE, 2)
	UiFont.draw(self, "ROLL OUT IN", Vector2(r.end.x - 11 - UiFont.width_big(t, 2) - UiFont.width("ROLL OUT IN"), r.position.y + 18), Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_status(v: SimVehicle) -> void:
	var r := Rect2(LEFT_X, 4, COL_W, 42)
	UiKit.plate(self, r)
	UiKit.icon(self, "scrap", r.position + Vector2(5, 4))
	UiFont.draw_big(self, str(v.scrap), r.position + Vector2(23, 5), Gfx.UI_TEXT, Gfx.OUTLINE, 2)
	UiFont.draw(self, "SCRAP", r.position + Vector2(6, 23), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var ix: float = UiFont.draw(self, "INTEREST +%d" % world.interest_for(v), r.position + Vector2(6, 32), Gfx.FIRE[4], Gfx.UI_SHADOW)
	UiFont.draw(self, " / %d" % world.interest_cap_for(v), Vector2(ix, r.position.y + 32), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var fx: float = r.position.x + 82.0
	UiKit.icon(self, "fuel", Vector2(fx, r.position.y + 4))
	var fcol: Color = Gfx.FIRE[3] if v.fuel > 40 else Gfx.UI_BAD
	UiFont.draw_big(self, str(maxi(v.fuel, 0)), Vector2(fx + 18, r.position.y + 6), fcol, Gfx.OUTLINE)
	UiFont.draw(self, "FUEL", Vector2(fx, r.position.y + 23), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiKit.bar(self, Rect2(fx, r.position.y + 33, r.end.x - fx - 6, 5), float(v.fuel) / float(SimWorld.START_FUEL), fcol)
	var dr: Dictionary = _drain_now(v)
	if not dr.is_empty() and (int(world.tick - int(dr["tick"])) / 8) % 2 == 0:
		UiFont.draw(self, "-%d DRAIN" % int(dr["amount"]), Vector2(fx + 22, r.position.y + 23), Gfx.UI_BAD, Gfx.UI_SHADOW)


## UNDERDOG badge taped across the status plate and the terminal (drawn after both).
func _draw_underdog(v: SimVehicle) -> void:
	if not world.is_underdog(v):
		return
	var ut := "UNDERDOG: -30% FUEL LOSS"
	var ur := Rect2(LEFT_X + COL_W - UiFont.width(ut) - 14.0, 44, UiFont.width(ut) + 10.0, 10)
	UiKit.tape(self, ur, Color("#e8dcc4"))
	UiFont.draw(self, ut, ur.position + Vector2(5, 2), Gfx.INK)


## This workshop's fuel drain of `v` from the WorldView log while the notice is up ({} = none).
func _drain_now(v: SimVehicle) -> Dictionary:
	if view == null:
		return {}
	for i in range(view.drain_log.size() - 1, -1, -1):
		var e: Dictionary = view.drain_log[i]
		if int(e["id"]) == v.id and int(e["round"]) == world.round and world.tick - int(e["tick"]) < DRAIN_NOTICE_TICKS:
			return e
	return {}


# ---------------------------------------------------------------- doctrine terminal

func _draw_terminal(v: SimVehicle) -> void:
	var r := Rect2(LEFT_X, 50, COL_W, 98)
	UiKit.steel(self, r)
	var scr := Rect2(r.position + Vector2(5, 5), r.size - Vector2(10, 14))
	draw_rect(scr, Gfx.CRT_BG)
	# rounded tube corners
	for p: Vector2 in [scr.position, Vector2(scr.end.x - 1, scr.position.y), Vector2(scr.position.x, scr.end.y - 1), scr.end - Vector2.ONE]:
		draw_rect(Rect2(p, Vector2.ONE), Gfx.STEEL[1])
	var x0: float = scr.position.x + 4.0
	var y: float = scr.position.y + 4.0
	var px: float = UiFont.draw(self, "> DOCTRINE.SYS", Vector2(x0, y), Gfx.CRT_DIM)
	if fmod(_blink, 1.0) < 0.5:
		draw_rect(Rect2(px + 2, y, 3, 6), Gfx.CRT_TEXT)
	y += 11.0
	UiFont.draw_small(self, "DRIVE", Vector2(x0, y), Gfx.CRT_DIM)
	y += 9.0
	var x: float = x0 + 2.0
	for d in DRIVES:
		x = _crt_chip(d.to_upper(), Vector2(x, y), v.doctrine["drive"] == d, "drive", d) + 4.0
	y += 12.0
	UiFont.draw_small(self, "TARGET", Vector2(x0, y), Gfx.CRT_DIM)
	y += 9.0
	x = x0 + 2.0
	for t in TARGETS:
		x = _crt_chip(TARGET_LABELS[t], Vector2(x, y), v.doctrine["target"] == t, "target", t) + 4.0
	y += 13.0
	var help: String = DRIVE_HELP.get(str(v.doctrine["drive"]), "")
	if not _hover.is_empty() and (_hover[1] == "drive" or _hover[1] == "target"):
		help = (DRIVE_HELP if _hover[1] == "drive" else TARGET_HELP).get(str(_hover[2]), "")
	elif _is_hover("rules"):
		help = "IF-THEN RULES FOR THE RIG AND EACH GUN"
	if help != "":
		UiFont.draw(self, UiFont.wrap(help, int(scr.size.x) - 8)[0], Vector2(x0, y), Gfx.CRT_TEXT)
	var n_rules: int = v.rules.size()
	for k: String in v.weapon_doctrine:
		n_rules += (v.weapon_doctrine[k]["rules"] as Array).size()
	x = _crt_chip("PROGRAM RULES (P)", Vector2(x0 + 2.0, y + 11.0), not _is_hover("rules"), "rules", "rig") + 4.0
	UiFont.draw_small(self, "%d SET" % n_rules, Vector2(x, y + 11.0), Gfx.CRT_DIM)
	# scanlines and a faint top glare
	for sy in range(int(scr.position.y) + 1, int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(scr.position.x + 2, scr.position.y + 1, scr.size.x - 4, 1), Color(1, 0.8, 0.5, 0.08))
	# housing label + power lamp
	UiFont.draw_small(self, "COLONY NAV-COMP", Vector2(r.position.x + 6, r.end.y - 7), Gfx.STEEL[4], Gfx.STEEL[0])
	draw_rect(Rect2(r.end.x - 10, r.end.y - 7, 3, 3), Gfx.CRT_TEXT)


func _crt_chip(text: String, pos: Vector2, on: bool, action: String, arg: String) -> float:
	var w: float = UiFont.width(text) + 5.0
	var r := Rect2(pos - Vector2(2, 2), Vector2(w, 10))
	var hov: bool = _is_hover(action, arg)
	if on:
		draw_rect(r, Gfx.CRT_TEXT)
		UiFont.draw(self, text, pos, Gfx.CRT_BG)
	else:
		if hov:
			UiKit.outline_rect(self, r, Gfx.CRT_DIM)
		UiFont.draw(self, text, pos, Gfx.CRT_HI if hov else Gfx.CRT_TEXT)
	_hits.append([r, action, arg])
	return r.end.x


# ---------------------------------------------------------------- loadout

func _draw_loadout(v: SimVehicle) -> void:
	var rows: int = v.cards.size()
	var r := Rect2(LEFT_X, 158, COL_W, 17 + rows * 10 + 26 + (9 if v.regen > 0.0 else 0))
	UiKit.plate(self, r)
	UiKit.tape_label(self, "RIG LOADOUT", r.position.x + 36, r.position.y - 3)
	var slots := "GUNS %d/%d" % [Cards.weapon_cards_owned(v), v.weapon_slots]
	UiFont.draw(self, slots, Vector2(r.end.x - 6 - UiFont.width(slots), r.position.y + 6), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var y: float = r.position.y + 17.0
	for id: String in v.cards:
		var lvl: int = int(v.cards[id])
		draw_rect(Rect2(r.position.x + 6, y, 6, 6), UiKit.card_color(id))
		UiKit.outline_rect(self, Rect2(r.position.x + 5, y - 1, 8, 8), Gfx.OUTLINE)
		UiFont.draw(self, UiKit.card_name(id), Vector2(r.position.x + 15, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		for k in Cards.MAX_LEVEL:
			var pr := Rect2(r.end.x - 23 + k * 5, y + 1, 4, 4)
			draw_rect(pr.grow(1.0), Gfx.OUTLINE)
			draw_rect(pr, Gfx.FIRE[4] if k < lvl else Gfx.UI_PLATE_DARK)
		y += 10.0
	y += 4.0
	draw_rect(Rect2(r.position.x + 5, y - 3, r.size.x - 10, 1), Gfx.OUTLINE)
	var l1 := "HP %d  ARMOUR %s" % [roundi(v.max_hp), UiKit.num(v.armor)]
	var l2 := "SPEED %s  SCRAP X%s" % [UiKit.pct(v.speed), UiKit.num(v.scrap_mult)]
	UiFont.draw(self, l1, Vector2(r.position.x + 6, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw(self, l2, Vector2(r.position.x + 6, y + 9), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var l3 := "REPAIR %s/S" % UiKit.num(v.regen) if v.regen > 0.0 else ""
	if l3 != "":
		UiFont.draw(self, l3, Vector2(r.position.x + 6, y + 18), Gfx.UI_DIM, Gfx.UI_SHADOW)


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
	var lw: float = UiFont.width(label) + 6.0 + 9.0 + UiFont.width(cost)
	var lx: float = floorf(cx - lw / 2.0)
	UiFont.draw(self, label, Vector2(lx, rr.position.y + 5), Gfx.UI_TEXT if can else Gfx.UI_DIM, Gfx.OUTLINE)
	_scrap_pip(Vector2(lx + UiFont.width(label) + 6, rr.position.y + 5))
	UiFont.draw(self, cost, Vector2(lx + UiFont.width(label) + 15, rr.position.y + 5),
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
	UiFont.draw(self, cat.to_upper(), tr.position + Vector2(4, 2), ink)
	var rar: String = str(Cards.def(id).get("rarity", "")).to_upper()
	UiFont.draw(self, rar, Vector2(tr.end.x - 4 - UiFont.width(rar), tr.position.y + 2), ink)
	# stencilled name, up to two lines
	var lines: PackedStringArray = UiFont.wrap_big(UiKit.card_name(id), int(CARD_SIZE.x) - 12)
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
		UiFont.draw_big(self, "NEW", Vector2(lx, iy + 2), Gfx.INK_RED * mod)
	else:
		UiFont.draw(self, "LV %d > %d" % [level, level + 1], Vector2(lx, iy + 3), ink)
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
		for sub in UiFont.wrap_small(ln, int(CARD_SIZE.x) - 16):
			if y > pos.y + 101.0:
				break
			UiFont.draw_small(self, sub, Vector2(pos.x + 9, y), ink)
			y += 7.0
	# footer: key hint
	if state == 0:
		var key := "%d" % (index + 1)
		var kr := Rect2(pos.x + 8, pos.y + CARD_SIZE.y - 15, 9, 9)
		draw_rect(kr, ink)
		UiFont.draw(self, key, kr.position + Vector2(3, 2), Gfx.BONE_LIGHT)
		UiFont.draw(self, "PICK" if not hov else "FIT IT", Vector2(kr.end.x + 3, kr.position.y + 2), ink)
		if Cards.is_weapon(id) and level == 0:
			var slot := "+1 GUN"
			UiFont.draw(self, slot, Vector2(pos.x + CARD_SIZE.x - 9 - UiFont.width(slot), kr.position.y + 2), Gfx.INK_RED)
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
	UiFont.draw_big(self, "TECH", r.position + Vector2(6, 5), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw(self, "BUILT FOR SCRAP", r.position + Vector2(36, 6), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var hover_id: String = ""
	var y: float = r.position.y + 17.0
	for b in Tech.BRANCHES:
		UiKit.icon(self, b, Vector2(r.position.x + 4, y + 4))
		UiFont.draw(self, b.to_upper(), Vector2(r.position.x + 22, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
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
		UiFont.draw(self, "SAVE SCRAP FOR TECH", info.position + Vector2(4, 4), Gfx.UI_DIM)
		UiFont.draw_small(self, "+1 INTEREST PER 10 HELD", info.position + Vector2(4, 13), Gfx.UI_DIM)
		return
	var td: Dictionary = Tech.def(show_id)
	UiFont.draw_small(self, "%s %s" % [str(td["branch"]).to_upper(), "I".repeat(int(td["tier"]))], info.position + Vector2(4, 3), Gfx.UI_DIM)
	UiFont.draw(self, UiKit.tech_name(show_id), info.position + Vector2(4, 10), Gfx.UI_TEXT)
	var ly: float = info.position.y + 18.0
	for ln in UiKit.tech_lines(show_id):
		UiFont.draw_small(self, ln, Vector2(info.position.x + 4, ly), Gfx.FIRE[4])
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
	for ln in UiFont.wrap_small(status, int(info.size.x) - 8):
		UiFont.draw_small(self, ln, Vector2(info.position.x + 4, ly + 1), scol)
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
	var tw: float = UiFont.width(txt) + 2.0 + 7.0
	var tx: float = floorf(nr.get_center().x - tw / 2.0)
	_scrap_pip(Vector2(tx, nr.position.y + 4))
	UiFont.draw(self, txt, Vector2(tx + 9, nr.position.y + 4), Gfx.UI_TEXT if afford else Gfx.UI_BAD, Gfx.OUTLINE)


## Tiny 5x5 scrap marker (a nut) for prices.
func _scrap_pip(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(1, 0), Vector2(5, 5)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(0, 1), Vector2(7, 3)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(5, 3)), Gfx.STEEL[4])
	draw_rect(Rect2(p + Vector2(3, 2), Vector2(1, 1)), Gfx.OUTLINE)


# ---------------------------------------------------------------- ready

func _draw_ready(v: SimVehicle, vs: Vector2) -> void:
	var n: int = world.vehicles.size()
	var r := Rect2(RIGHT_X, vs.y - 18 - 48 - n * 10, COL_W, 48 + n * 10)
	UiKit.plate(self, r)
	UiFont.draw(self, "CONVOY", r.position + Vector2(6, 5), Gfx.UI_DIM, Gfx.UI_SHADOW)
	if n > 1:
		var sh := "HOVER TO SCOUT"
		UiFont.draw(self, sh, Vector2(r.end.x - 6 - UiFont.width(sh), r.position.y + 5), Gfx.STEEL[4], Gfx.UI_SHADOW)
	var y: float = r.position.y + 16.0
	var ready_n: int = 0
	var need: int = 0
	for o in world.vehicles:
		if o != v:
			var rr := Rect2(r.position.x + 3, y - 2, r.size.x - 6, 10)
			if _is_hover("scout", o.id) or _scout_pin == o.id:
				draw_rect(rr, Color(1.0, 0.8, 0.5, 0.14))
				UiKit.outline_rect(self, rr, Gfx.HAZARD if _scout_pin == o.id else Gfx.UI_DIM)
			_hits.append([rr, "scout", o.id])
		UiKit.swatch(self, Rect2(r.position.x + 5, y - 1, 7, 7), o.color_index)
		var nx: float = UiKit.paint_text(self, UiKit.player_name(o), Vector2(r.position.x + 15, y), o.color_index)
		if o == v:
			UiFont.draw(self, "(YOU)", Vector2(nx + 3, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		var st: String = "OUT" if o.eliminated else ("READY" if o.ready else "TINKERING")
		var sc: Color = Gfx.UI_DIM if o.eliminated else (Gfx.HAZARD if o.ready else Gfx.UI_DIM)
		UiFont.draw(self, st, Vector2(r.end.x - 6 - UiFont.width(st), y), sc, Gfx.UI_SHADOW)
		if not o.eliminated:
			need += 1
			ready_n += 1 if o.ready else 0
		y += 10.0
	var br := Rect2(r.position.x + 5, r.end.y - 30, r.size.x - 10, 25)
	var hov: bool = _is_hover("ready")
	if v.ready:
		UiKit.steel(self, br, Color(0.6, 0.55, 0.55))
		UiKit.center_big(self, "WAITING", br.get_center().x, br.position.y + 4, Gfx.UI_DIM, Gfx.OUTLINE)
		UiKit.center_text(self, "%d / %d READY" % [ready_n, need], br.get_center().x, br.position.y + 15, Gfx.UI_DIM, Gfx.OUTLINE)
	else:
		UiKit.steel(self, br)
		UiKit.hazard_frame(self, br, 3.0, Color.WHITE if hov or fmod(_blink, 1.0) < 0.6 else Color(0.75, 0.75, 0.75))
		UiKit.center_big(self, "ROLL OUT", br.get_center().x, br.position.y + 5, Gfx.FIRE[5] if hov else Gfx.UI_TEXT, Gfx.OUTLINE)
		UiKit.center_small(self, "SPACE - I AM READY", br.get_center().x, br.position.y + 15, Gfx.UI_DIM, Gfx.OUTLINE)
	_hits.append([br, "ready", null])


# ---------------------------------------------------------------- last round recap (#2)

## The vehicle's round stats if they belong to the round just played ({} = none or stale).
func _round_stats(v: SimVehicle) -> Dictionary:
	var rs: Dictionary = v.round_stats
	if rs.is_empty() or int(rs.get("round", -1)) != world.round:
		return {}
	return rs


## The recap's doctrine hint, computed once per round and rig so a click shows as applied.
func _round_hint(v: SimVehicle) -> Dictionary:
	var key := "%d:%d:%d" % [v.id, world.round, Recap.deaths(v).size()]
	if key != _hint_key:
		_hint_key = key
		_hint = Recap.hint(world, v)
	return _hint


func _draw_recap(v: SimVehicle) -> void:
	var rs: Dictionary = _round_stats(v)
	if rs.is_empty():
		return
	var h: Dictionary = _round_hint(v) if not v.eliminated else {}
	var r := Rect2(RECAP_X, RECAP_Y, RECAP_W, 46 + (16 if not h.is_empty() else 0))
	UiKit.plate(self, r)
	_hits.append([r, "none", null])
	UiKit.tape_label(self, "LAST ROUND %d" % int(rs["round"]), r.position.x + 40, r.position.y - 4, Color("#e8dcc4"))
	var x0: float = r.position.x + 6.0
	var y: float = r.position.y + 8.0
	var tot: float = Recap.total_taken(v)
	_recap_headline(v, Vector2(x0, y), tot)
	var tt := "%d HP TAKEN" % roundi(tot)
	UiFont.draw(self, tt, Vector2(r.end.x - 6 - UiFont.width(tt), y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 9.0
	# damage by source: one stacked bar, then a legend of the big slices
	var segs: Array[Dictionary] = Recap.segments(world, v)
	var bar := Rect2(x0, y, r.size.x - 12.0, 6)
	draw_rect(bar, Gfx.OUTLINE)
	var inner: Rect2 = bar.grow(-1.0)
	draw_rect(inner, Gfx.UI_PLATE_DARK)
	var bx: float = inner.position.x
	for i in segs.size():
		var sw: float = inner.end.x - bx if i == segs.size() - 1 else roundf(inner.size.x * float(segs[i]["frac"]))
		if sw <= 0.0:
			continue
		var col: Color = segs[i]["color"]
		draw_rect(Rect2(bx, inner.position.y, sw, inner.size.y), col)
		draw_rect(Rect2(bx, inner.position.y, sw, 1), col.lightened(0.3))
		if i > 0:
			draw_rect(Rect2(bx, inner.position.y, 1, inner.size.y), Gfx.OUTLINE)
		bx += sw
	y += 9.0
	var lx: float = x0
	for sg: Dictionary in segs:
		if float(sg["frac"]) < 0.05 or lx > r.end.x - 60.0:
			continue
		var col: Color = sg["color"]
		draw_rect(Rect2(lx, y, 5, 5), Gfx.OUTLINE)
		draw_rect(Rect2(lx + 1, y + 1, 3, 3), col)
		lx += 8.0
		if int(sg["paint"]) >= 0:
			lx = UiKit.paint_text(self, str(sg["label"]), Vector2(lx, y), int(sg["paint"]))
		else:
			lx = UiFont.draw(self, str(sg["label"]), Vector2(lx, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		lx = UiFont.draw(self, " " + UiKit.pct(float(sg["frac"])), Vector2(lx, y), Gfx.UI_DIM, Gfx.UI_SHADOW) + 9.0
	if segs.is_empty():
		UiFont.draw(self, "NOTHING GOT THROUGH THE PLATING", Vector2(lx, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 9.0
	# earnings left, fuel right
	var ex: float = x0
	ex = _kv("KILLS", str(int(rs.get("kills", 0))), Vector2(ex, y), Gfx.UI_TEXT)
	if int(rs.get("kills_players", 0)) > 0 or world.vehicles.size() > 1:
		ex = _kv("RIGS", str(int(rs.get("kills_players", 0))), Vector2(ex, y), Gfx.UI_TEXT)
	ex = _kv("SCRAP", "+%d" % int(rs.get("scrap_earned", 0)), Vector2(ex, y), Gfx.FIRE[4])
	_kv("INTEREST", "+%d" % int(rs.get("interest", 0)), Vector2(ex, y), Gfx.FIRE[4])
	var parts: Array = []  # [text, colour]
	if int(rs.get("fuel_lost", 0)) > 0:
		parts.append(["-%d LOST" % int(rs["fuel_lost"]), Gfx.UI_BAD])
	if int(rs.get("fuel_gained", 0)) > 0:
		parts.append(["+%d STOLEN" % int(rs["fuel_gained"]), Gfx.FIRE[4]])
	if int(rs.get("fuel_drained", 0)) > 0:
		parts.append(["-%d DRAIN" % int(rs["fuel_drained"]), Gfx.UI_BAD])
	if parts.is_empty():
		parts.append(["NO LOSS", Gfx.UI_DIM])
	var fw: float = UiFont.width("FUEL")
	for pt: Array in parts:
		fw += 5.0 + UiFont.width(pt[0])
	var fxp: float = r.end.x - 6.0 - fw
	fxp = UiFont.draw(self, "FUEL", Vector2(fxp, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	for pt: Array in parts:
		fxp = UiFont.draw(self, pt[0], Vector2(fxp + 5.0, y), pt[1], Gfx.UI_SHADOW)
	y += 9.0
	if not h.is_empty():
		_draw_hint(v, h, Rect2(x0 - 1, y, r.size.x - 10, 13))


## "WRECKED 0:57 BY A BOULDER" / "WRECKED 2X - LAST 0:57 BY <rival> - SIEGE CANNON" / survived.
func _recap_headline(v: SimVehicle, pos: Vector2, tot: float) -> void:
	var ds: Array = Recap.deaths(v)
	if ds.is_empty():
		var ok: String = "CLEAN ROUND - NOT A SCRATCH" if tot < 1.0 else "SURVIVED THE ROUND"
		UiFont.draw(self, ok, pos, Gfx.FIRE[4], Gfx.UI_SHADOW)
		return
	var last: Dictionary = ds[-1]
	var when: String = UiKit.clock(int(last.get("t", 0)))
	var head: String
	if v.eliminated:
		head = "RAN DRY AT %s" % when
	elif ds.size() > 1:
		head = "WRECKED %dX - LAST AT %s" % [ds.size(), when]
	else:
		head = "WRECKED AT %s" % when
	var x: float = UiFont.draw(self, head + " BY ", pos, Gfx.UI_BAD, Gfx.UI_SHADOW)
	var cause: String = str(last.get("cause", ""))
	var killer: SimVehicle = UiKit.vehicle_by_id(world, int(last.get("killer", -1)))
	if killer != null and (cause == "player" or cause == "ram"):
		x = UiKit.paint_text(self, UiKit.player_name(killer), Vector2(x, pos.y), killer.color_index)
		var wk: int = Recap.killer_weapon(view, v.id, killer.id, world.round)
		var wt: String = UiKit.weapon_long(wk) if wk >= 0 else ("RAMMED" if cause == "ram" else "")
		if wt != "":
			UiFont.draw(self, " - " + wt, Vector2(x, pos.y), Gfx.FIRE[4] if wt == "RAMMED" else Gfx.UI_TEXT, Gfx.UI_SHADOW)
	else:
		UiFont.draw(self, str(UiKit.CAUSE_TEXT.get(cause, "THE HIVE")), Vector2(x, pos.y), Gfx.UI_TEXT, Gfx.UI_SHADOW)


## "LABEL value" pair in the recap; returns the x for the next pair.
func _kv(label: String, value: String, pos: Vector2, col: Color) -> float:
	var x: float = UiFont.draw(self, label, pos, Gfx.UI_DIM, Gfx.UI_SHADOW) + 4.0
	return UiFont.draw(self, value, Vector2(x, pos.y), col, Gfx.UI_SHADOW) + 7.0


## The doctrine hint as a line on the nav-comp's amber CRT, with clickable doctrine chips.
func _draw_hint(v: SimVehicle, h: Dictionary, r: Rect2) -> void:
	draw_rect(r, Gfx.STEEL[1])
	var scr: Rect2 = r.grow(-1.0)
	draw_rect(scr, Gfx.CRT_BG)
	var opts: Array = h.get("options", [])
	# chips right-aligned
	var cx: float = scr.end.x - 2.0
	var chips: Array = []
	for i in range(opts.size() - 1, -1, -1):
		var opt: Dictionary = opts[i]
		var on: bool = Recap.applied(v, opt)
		var label: String = ("%s SET" % str(opt["label"]).trim_prefix("SET ").trim_prefix("TARGET ")) if on else str(opt["label"])
		var w: float = UiFont.width(label) + 6.0
		var cr := Rect2(cx - w, scr.position.y + 1, w, scr.size.y - 2)
		chips.append([cr, label, on, i])
		cx -= w + 3.0
	UiFont.draw(self, "> " + str(h["text"]), Vector2(scr.position.x + 3, scr.position.y + 3), Gfx.CRT_TEXT)
	for sy in range(int(scr.position.y) + 1, int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.22))
	for ch: Array in chips:
		var cr: Rect2 = ch[0]
		var hov: bool = _is_hover("hint", ch[3])
		if ch[2]:
			draw_rect(cr, Gfx.CRT_BG)
			UiKit.outline_rect(self, cr, Gfx.CRT_DIM)
			UiFont.draw(self, ch[1], cr.position + Vector2(3, 2), Gfx.CRT_HI)
		else:
			var lit: bool = hov or fmod(_blink, 1.0) < 0.6
			draw_rect(cr, Gfx.CRT_TEXT if lit else Gfx.CRT_DIM)
			UiFont.draw(self, ch[1], cr.position + Vector2(3, 2), Gfx.CRT_BG)
			if hov:
				UiKit.outline_rect(self, cr.grow(1.0), Gfx.CRT_HI)
		_hits.append([cr, "hint", ch[3]])


# ---------------------------------------------------------------- scouting (#10)

## Whose dossier the tech column shows: the hovered convoy row, else the pinned one (null = tech).
func _scout_target() -> SimVehicle:
	var id: int = _scout_pin
	if not _hover.is_empty() and _hover[1] == "scout":
		id = int(_hover[2])
	return UiKit.vehicle_by_id(world, id)


## A rival's build at a glance: fuel, hp, armour, speed, guns with levels, other parts, tech per
## branch, doctrine. All from the synced vehicle state (also used by the spectator panel).
func _draw_dossier(o: SimVehicle, r: Rect2, closable: bool) -> void:
	var guns: int = Cards.weapon_cards_owned(o)
	var need: float = 70.0 + 9.0 * guns + 9.0 * maxi(o.cards.size() - guns, 0) + 52.0
	r.size.y = minf(r.size.y, need)
	UiKit.plate(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var xr: float = r.end.x - 6.0
	var y: float = r.position.y + 5.0
	UiFont.draw_big(self, "SCOUT", Vector2(x0, y), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw(self, "REPORT", Vector2(x0 + UiFont.width_big("SCOUT") + 4, y + 1), Gfx.UI_DIM, Gfx.UI_SHADOW)
	if closable:
		var cr := Rect2(xr - 30, y - 2, 31, 10)
		UiKit.steel(self, cr)
		UiKit.center_text(self, "CLOSE", cr.get_center().x, cr.position.y + 2, Gfx.FIRE[5] if _is_hover("unscout") else Gfx.UI_TEXT, Gfx.OUTLINE)
		_hits.append([cr, "unscout", null])
	y += 12.0
	UiKit.swatch(self, Rect2(x0, y, 8, 8), o.color_index)
	var nx: float = UiKit.paint_big(self, UiKit.player_name(o), Vector2(x0 + 11, y + 1), o.color_index)
	if o.peer_id == world.leader_peer:
		draw_texture(Gfx.TEX_SKULL, Vector2(nx + 3, y - 1))
	if o.eliminated:
		UiFont.draw(self, "OUT", Vector2(xr - UiFont.width("OUT"), y + 2), Gfx.UI_BAD, Gfx.UI_SHADOW)
	elif o.ready:
		UiFont.draw(self, "READY", Vector2(xr - UiFont.width("READY"), y + 2), Gfx.HAZARD, Gfx.UI_SHADOW)
	y += 12.0
	# fuel and hull
	var fcol: Color = Gfx.FIRE[3] if o.fuel > 40 else Gfx.UI_BAD
	UiFont.draw(self, "FUEL", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var ft := str(maxi(o.fuel, 0))
	UiKit.bar(self, Rect2(x0 + 20, y, xr - x0 - 26 - UiFont.width(ft), 5), float(o.fuel) / float(SimWorld.START_FUEL), fcol)
	UiFont.draw(self, ft, Vector2(xr - UiFont.width(ft), y), fcol, Gfx.UI_SHADOW)
	y += 9.0
	var lx: float = _kv("HP", str(roundi(o.max_hp)), Vector2(x0, y), Gfx.UI_TEXT)
	lx = _kv("ARM", UiKit.num(o.armor), Vector2(lx, y), Gfx.UI_TEXT)
	_kv("SPD", UiKit.pct(o.speed), Vector2(lx, y), Gfx.UI_TEXT)
	y += 9.0
	lx = _kv("KILLS", str(o.kills), Vector2(x0, y), Gfx.UI_TEXT)
	_kv("SCRAP", str(o.scrap), Vector2(lx, y), Gfx.FIRE[4])
	y += 9.0
	draw_rect(Rect2(x0 - 1, y - 1, xr - x0 + 2, 1), Gfx.OUTLINE)
	# guns, then the other parts: name and level pips (as in RIG LOADOUT)
	y += 2.0
	UiFont.draw(self, "GUNS %d/%d" % [Cards.weapon_cards_owned(o), o.weapon_slots], Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 9.0
	for id: String in o.cards:
		if Cards.is_weapon(id):
			_dossier_row(id, int(o.cards[id]), x0, xr, y)
			y += 9.0
	y += 2.0
	# other parts
	var parts: Array[String] = []
	for id: String in o.cards:
		if not Cards.is_weapon(id):
			parts.append(id)
	UiFont.draw(self, "PARTS" if not parts.is_empty() else "PARTS - NONE YET", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 9.0
	var room: int = int((r.end.y - y - 41.0) / 9.0)
	for i in parts.size():
		if i >= room and parts.size() > room:
			UiFont.draw(self, "+%d MORE" % (parts.size() - i), Vector2(x0 + 8, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
			y += 9.0
			break
		_dossier_row(parts[i], int(o.cards[parts[i]]), x0, xr, y)
		y += 9.0
	# tech per branch
	y = maxf(y + 2.0, r.end.y - 39.0)
	UiFont.draw(self, "TECH %d/%d" % [o.tech.size(), Tech.count()], Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 9.0
	var tw: float = floorf((xr - x0) / float(Tech.BRANCHES.size()))
	for bi in Tech.BRANCHES.size():
		var b: String = Tech.BRANCHES[bi]
		var bx0: float = x0 + bi * tw
		var tier: int = Tech.branch_tier(o, b)
		UiFont.draw(self, b.left(3).to_upper(), Vector2(bx0, y), Gfx.UI_TEXT if tier > 0 else Gfx.STEEL[3], Gfx.UI_SHADOW)
		UiKit.pips(self, Vector2(bx0 - 1, y + 8), tier, Tech.MAX_TIER, Gfx.BRASS[3])
	y += 15.0
	# doctrine on a sliver of CRT
	var dr := Rect2(x0 - 1, y, xr - x0 + 2, 11)
	draw_rect(dr, Gfx.STEEL[1])
	draw_rect(dr.grow(-1.0), Gfx.CRT_BG)
	var doc := "> %s / %s" % [str(o.doctrine["drive"]).to_upper(), TARGET_LABELS.get(str(o.doctrine["target"]), "?")]
	UiFont.draw(self, doc, dr.position + Vector2(3, 3), Gfx.CRT_TEXT)


func _dossier_row(id: String, lvl: int, x0: float, xr: float, y: float) -> void:
	draw_rect(Rect2(x0, y - 1, 7, 7), Gfx.OUTLINE)
	draw_rect(Rect2(x0 + 1, y, 5, 5), UiKit.card_color(id))
	UiFont.draw(self, UiKit.card_name(id), Vector2(x0 + 10, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiKit.pips(self, Vector2(xr - 16, y), lvl, Cards.MAX_LEVEL, Gfx.FIRE[4])


# ---------------------------------------------------------------- spectator workshop (#5)

## Eliminated: no shop. Header, your recap, standings (click a rig to watch and scout it) and the
## dossier of the watched rig.
func _draw_spectator(v: SimVehicle, vs: Vector2) -> void:
	_draw_header(vs)
	_draw_out(v)
	_draw_recap(v)
	var watched: SimVehicle = view.focus_vehicle() if view != null else null
	_draw_standings_panel(v, watched, vs)
	var scout: SimVehicle = null
	if not _hover.is_empty() and _hover[1] == "watch":
		scout = UiKit.vehicle_by_id(world, int(_hover[2]))
	if scout == null:
		scout = watched
	if scout != null:
		_draw_dossier(scout, Rect2(RIGHT_X, 4, COL_W, 226), false)
	UiKit.footer(self, "SPECTATING      TAB  < >  SWITCH RIG      CLICK A RIG TO WATCH IT      ESC  MENU", vs)


## Left column: you are out, and your match so far.
func _draw_out(v: SimVehicle) -> void:
	var r := Rect2(LEFT_X, 4, COL_W, 78 if int(v.match_stats.get("nemesis", -1)) < 0 else 89)
	UiKit.plate(self, r)
	UiKit.hazard_band(self, Rect2(r.position.x + 5, r.position.y + 5, r.size.x - 10, 4))
	UiFont.draw_big(self, "OUT OF FUEL", r.position + Vector2(6, 13), Gfx.UI_BAD, Gfx.OUTLINE)
	UiFont.draw(self, "YOUR CONVOY IS WATCHING", r.position + Vector2(6, 24), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var ms: Dictionary = v.match_stats
	var y: float = r.position.y + 34.0
	var rows: Array = [["ALIENS KILLED", str(int(ms.get("kills", 0)))], ["RIGS WRECKED", str(int(ms.get("player_kills", 0)))],
		["TIMES WRECKED", str(int(ms.get("deaths", 0)))], ["SCRAP EARNED", str(int(ms.get("scrap_earned", 0)))]]
	for row: Array in rows:
		UiFont.draw(self, row[0], Vector2(r.position.x + 6, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
		UiFont.draw(self, row[1], Vector2(r.end.x - 6 - UiFont.width(row[1]), y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		y += 9.0
	var nem: SimVehicle = UiKit.vehicle_by_id(world, int(ms.get("nemesis", -1)))
	if nem != null:
		var x: float = UiFont.draw(self, "NEMESIS ", Vector2(r.position.x + 6, y + 2), Gfx.UI_DIM, Gfx.UI_SHADOW)
		x = UiKit.paint_text(self, UiKit.player_name(nem), Vector2(x, y + 2), nem.color_index)
		UiFont.draw(self, " X%d" % int(ms.get("nemesis_n", 0)), Vector2(x, y + 2), Gfx.UI_TEXT, Gfx.UI_SHADOW)


## Centre: every rig with fuel, kills, rigs wrecked, tech and workshop status; click to watch.
func _draw_standings_panel(me: SimVehicle, watched: SimVehicle, vs: Vector2) -> void:
	var rows: Array[SimVehicle] = UiKit.standings(world)
	var r := Rect2(RECAP_X, STANDINGS_Y, RECAP_W, 22 + rows.size() * 11)
	UiKit.plate(self, r)
	UiKit.tape_label(self, "STANDINGS", r.get_center().x, r.position.y - 4, Color("#e8dcc4"))
	var cols: Array[float] = [r.position.x + 8, r.position.x + 22, r.position.x + 120, r.position.x + 182, r.position.x + 212, r.position.x + 240, r.end.x - 8]
	var y: float = r.position.y + 9.0
	for i in 5:
		UiFont.draw(self, ["#", "RIG", "FUEL", "KILLS", "RIGS"][i], Vector2(cols[i], y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw(self, "TECH", Vector2(cols[5], y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw(self, "CAMP", Vector2(cols[6] - UiFont.width("CAMP"), y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 10.0
	for i in rows.size():
		var o: SimVehicle = rows[i]
		var rr := Rect2(r.position.x + 4, y - 2, r.size.x - 8, 10)
		var hov: bool = _is_hover("watch", o.id)
		if o == watched or hov:
			draw_rect(rr, Color(1.0, 0.8, 0.5, 0.14 if o == watched else 0.08))
			if o == watched:
				UiKit.outline_rect(self, rr, Gfx.HAZARD)
		var out: bool = o.eliminated
		var dim: Color = Gfx.UI_DIM
		UiFont.draw(self, str(i + 1), Vector2(cols[0], y), dim if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiKit.swatch(self, Rect2(cols[1] - 1, y - 1, 7, 7), o.color_index)
		var nx: float
		if out:
			nx = UiFont.draw(self, UiKit.player_name(o), Vector2(cols[1] + 9, y), dim, Gfx.UI_SHADOW)
		else:
			nx = UiKit.paint_text(self, UiKit.player_name(o), Vector2(cols[1] + 9, y), o.color_index)
		if o == me:
			UiFont.draw(self, "(YOU)", Vector2(nx + 3, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		elif o.peer_id == world.leader_peer:
			draw_texture(Gfx.TEX_SKULL, Vector2(nx + 2, y - 3))
		if out:
			UiFont.draw(self, "OUT", Vector2(cols[2], y), dim, Gfx.UI_SHADOW)
		else:
			var fcol: Color = Gfx.FIRE[3] if o.fuel > 40 else Gfx.UI_BAD
			UiKit.bar(self, Rect2(cols[2], y, 40, 5), float(o.fuel) / float(SimWorld.START_FUEL), fcol)
			UiFont.draw(self, str(o.fuel), Vector2(cols[2] + 44, y), fcol, Gfx.UI_SHADOW)
		UiFont.draw(self, str(o.kills), Vector2(cols[3], y), dim if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiFont.draw(self, str(int(o.match_stats.get("player_kills", 0))), Vector2(cols[4], y), dim if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiFont.draw(self, "%d/%d" % [o.tech.size(), Tech.count()], Vector2(cols[5], y), dim if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		var st: String = "-" if out else ("READY" if o.ready else "TINKERING")
		UiFont.draw(self, st, Vector2(cols[6] - UiFont.width(st), y), Gfx.HAZARD if o.ready and not out else dim, Gfx.UI_SHADOW)
		if not out and o != me:
			_hits.append([rr, "watch", o.id])
		y += 11.0
