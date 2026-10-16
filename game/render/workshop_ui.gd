class_name WorkshopUi
extends Control
## Workshop overlay (phase == PHASE_WORKSHOP, design doc sections 5, 6 and 11f), laid out as one
## shell with three views (UI revamp):
## - a fixed top bar: WORKSHOP and the round, scrap with interest, fuel, the view tabs PARTS /
##   TECH (T) / RULES (P) with badges, the countdown and the ROLL OUT button next to it;
## - PARTS (start view): YOUR RIG on the left (stats, guns, parts, doctrine summary), the camped
##   rig and the three draft cards with reroll in the middle, LAST ROUND and CONVOY on the right;
## - TECH: the full tree (render/tech_tree_view.gd) over the whole body;
## - RULES: the rule editor (DoctrineEditor) embedded in the body, so the clock and READY stay
##   in view. In combat P still opens the editor as an overlay; it moves into this tab when camp
##   starts.
##
## Immediate-mode UI: _draw() lays everything out and records hit rects; clicks and keys go
## through activate(), which only ever sends commands through `send_command` (NetSession in play,
## the world directly in screenshot mode). All state comes from the local player's vehicle.
## Keys: 1/2/3 pick, R reroll, Space ready, H apply the recap's doctrine hint, T the TECH view,
## P the RULES view (both toggle back to PARTS), Esc back to PARTS.
##
## Information UI (playtest round 1 #2, #5, #10): the LAST ROUND recap (what wrecked you, damage by
## source, earnings, fuel, a clickable doctrine hint), interest as interest_for / interest_cap_for,
## an UNDERDOG badge, the fuel-drain notice, and scouting: hover a convoy row for a rival's dossier
## (click pins it). An eliminated player gets a read-only spectator layout instead of the shop.

const BAR := Rect2(4, 4, 632, 24)
const BODY_Y := 34.0
const BODY_BOTTOM := 344.0
const CARD_SIZE := Vector2(100, 122)
const CARD_Y := 160.0
const CARD_GAP := 6.0
const LEFT_X := 6.0
const COL_W := 150.0
const RIGHT_X := 484.0
const TAB_X := 246.0
const TAB_W := 66.0
const TABS: PackedStringArray = ["parts", "tech", "rules"]
const TAB_LABELS := {"parts": "PARTS", "tech": "TECH", "rules": "RULES"}
const TAB_KEYS := {"parts": "", "tech": "T", "rules": "P"}
const TARGET_LABELS := {"nearest": "NEAREST", "strongest": "STRONGEST", "players_first": "PLAYERS 1ST", "weakest": "WEAKEST",
	"boulders": "BOULDERS", "spitters": "SPITTERS"}
const TOAST_SECS := 1.6
const DRAIN_NOTICE_TICKS := 150  ## the "-N FUEL DRAIN" tape flashes this long after the drain

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null
## Callable(cmd: Dictionary): where commands go (NetSession.send_command or the world directly).
var send_command: Callable = Callable()
## The rule editor, drawn into the body while the RULES view is open (set by WorldView).
var rules: DoctrineEditor = null
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
var _scout_pin: int = -1  ## vehicle id whose dossier is pinned next to the convoy (-1 = none)
var _hint: Dictionary = {}  ## doctrine hint of the recap, computed once per round (before any click)
var _hint_key: String = ""
var _tab: String = "parts"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false


func _process(delta: float) -> void:
	var was: bool = visible
	visible = world != null and world.phase == SimWorld.PHASE_WORKSHOP and _local() != null
	_toast_left = maxf(_toast_left - delta, 0.0)
	_blink += delta
	if visible and not was:
		_scout_pin = -1
		# the editor was open as a combat overlay: camp continues in the RULES view
		if rules != null and rules.is_open and not _local().eliminated:
			_set_tab("rules")
	elif was and not visible:
		_set_tab("parts")
	if visible and _local().eliminated and _tab != "parts":
		_set_tab("parts")
	if visible and rules != null and _tab == "rules" and not rules.is_open:
		_tab = "parts"  # closed from inside (Esc, game over)
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


# Helpers for TechTreeView, which draws into this canvas.
func is_hover(action: String, arg: Variant = null) -> bool:
	return _is_hover(action, arg)


## The argument of the hovered hit if its action is `action` (null = none).
func hover_arg(action: String) -> Variant:
	return _hover[2] if not _hover.is_empty() and _hover[1] == action else null


func add_hit(r: Rect2, action: String, arg: Variant) -> void:
	_hits.append([r, action, arg])


func blink() -> float:
	return _blink


func scrap_pip(p: Vector2) -> void:
	_scrap_pip(p)


## The open view: "parts", "tech" or "rules".
func tab() -> String:
	return _tab


## The body area under the top bar (the TECH and RULES views fill it).
static func body_rect() -> Rect2:
	return Rect2(LEFT_X, BODY_Y, 640.0 - 2.0 * LEFT_X, BODY_BOTTOM - BODY_Y)


func _set_tab(t: String) -> void:
	_tab = t
	if rules == null:
		return
	if t == "rules":
		rules.open_embedded(body_rect())
	elif rules.embedded():
		rules.close()


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
		KEY_T:
			activate("tab", "parts" if _tab == "tech" else "tech")
		KEY_ESCAPE:
			if _tab != "parts":
				activate("tab", "parts")
			elif _scout_pin >= 0:
				_scout_pin = -1
			else:
				handled = false
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


## Clicks at `p` (viewport pixels) exactly like the mouse does; used by screenshot scenarios too.
## In the RULES view everything below the top bar belongs to the embedded editor.
func click_at(p: Vector2) -> bool:
	var h: Array = _hit_at(p)
	if h.is_empty():
		if _tab == "rules" and rules != null and rules.is_open:
			return rules.click_at(p)
		return false
	activate(h[1], h[2])
	return true


## Every button, card, node and key ends here. Illegal actions only show a toast.
func activate(action: String, arg: Variant) -> void:
	var v: SimVehicle = _local()
	if v == null or world.phase != SimWorld.PHASE_WORKSHOP:
		return
	if v.eliminated and action in ["pick", "reroll", "tech", "ready", "hint", "tab"]:
		return  # spectator: read-only
	match action:
		"tab":
			var t: String = str(arg)
			if t in TABS:
				_set_tab(t)
		"tree":  # old name of the TECH view (kept for scenarios and muscle memory)
			_set_tab("tech" if arg == null or bool(arg) else "parts")
		"rules":
			_set_tab("rules")
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
			if _tab != "parts":
				_set_tab("parts")
			if v.picked or v.eliminated:
				_say("PART ALREADY FITTED")
			elif i < 0 or i >= v.offers.size():
				_say("NO SUCH PART")
			else:
				_picked_index = i
				_send({"type": "pick_card", "value": i})
		"reroll":
			if _tab != "parts":
				_set_tab("parts")
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
			elif Tech.blocked_by(v, id) != "":
				var swap_from: String = Tech.blocked_by(v, id)
				if Tech.can_respec(v, swap_from, id, world.round):
					_send({"type": "respec_tech", "from": swap_from, "value": id})
				else:
					_say("CANNOT SWAP %s NOW" % UiKit.tech_name(swap_from))
			elif Tech.missing(v, id) != "":
				_say("BUILD %s FIRST" % UiKit.tech_name(Tech.next_step(v, id)))
			elif v.scrap < Tech.price(v, id):
				_say("NEED %d SCRAP" % Tech.price(v, id))
			else:
				_send({"type": "buy_tech", "value": id})
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
	match _tab:
		"tech":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.035, 0.03, 0.55))
			TechTreeView.draw(self, v, body_rect())
			UiKit.footer(self, "CLICK A NODE  BUILD      T  BACK TO PARTS      SPACE  READY", vs)
		"rules":
			# the editor draws itself into the body (DoctrineEditor.open_embedded)
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.035, 0.03, 0.55))
			UiKit.footer(self, "P  BACK TO PARTS      SPACE  READY", vs)
		_:
			_draw_rig_panel(v)
			_draw_cards(v, vs)
			_draw_recap(v)
			_draw_convoy(v)
			var scout: SimVehicle = _scout_target()
			if scout != null:
				_draw_dossier(scout, Rect2(RIGHT_X - COL_W - 6.0, BODY_Y, COL_W, 226), _scout_pin == scout.id)
			UiKit.footer(self, "1 2 3  PICK      R  REROLL      T  TECH      P  RULES      SPACE  READY", vs)
	_draw_bar(v, vs)
	_draw_toast(vs)


func _draw_toast(vs: Vector2) -> void:
	if _toast_left > 0.0:
		var tr: Rect2 = UiKit.tape_label(self, _toast, floorf(vs.x / 2.0), BAR.end.y + 6.0, Color("#f0b090"))
		_hits.append([tr, "none", null])


# ---------------------------------------------------------------- top bar

func _draw_bar(v: SimVehicle, _vs: Vector2) -> void:
	var r: Rect2 = BAR
	UiKit.plate(self, r)
	_hits.append([r, "none", null])
	var y: float = r.position.y
	UiFont.draw_big(self, "WORKSHOP", Vector2(r.position.x + 7, y + 5), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw_small(self, "AFTER ROUND %d" % world.round, Vector2(r.position.x + 7, y + 15), Gfx.UI_DIM)
	# scrap: big number, interest under the label
	var sx: float = r.position.x + 64.0
	UiKit.icon(self, "scrap", Vector2(sx, y + 4))
	var nx: float = UiFont.draw_big(self, str(v.scrap), Vector2(sx + 17, y + 5), Gfx.UI_TEXT, Gfx.OUTLINE, 2) + 4.0
	UiFont.draw_small(self, "SCRAP", Vector2(nx, y + 5), Gfx.UI_DIM)
	var ix: float = UiFont.draw_small(self, "+%d" % world.interest_for(v), Vector2(nx, y + 14), Gfx.FIRE[4])
	UiFont.draw_small(self, " INTEREST", Vector2(ix, y + 14), Gfx.UI_DIM)
	_hits.append([Rect2(sx, y + 2, nx + 46.0 - sx, 20), "info", "scrap"])
	# fuel
	var fx: float = r.position.x + 162.0
	UiKit.icon(self, "fuel", Vector2(fx, y + 4))
	var fcol: Color = Gfx.FIRE[3] if v.fuel > 40 else Gfx.UI_BAD
	var fnx: float = UiFont.draw_big(self, str(maxi(v.fuel, 0)), Vector2(fx + 17, y + 5), fcol, Gfx.OUTLINE, 2) + 4.0
	var dr: Dictionary = _drain_now(v)
	if not dr.is_empty() and (int(world.tick - int(dr["tick"])) / 8) % 2 == 0:
		UiFont.draw_small(self, "-%d DRAIN" % int(dr["amount"]), Vector2(fnx, y + 5), Gfx.UI_BAD)
	else:
		UiFont.draw_small(self, "FUEL", Vector2(fnx, y + 5), Gfx.UI_DIM)
	UiKit.bar(self, Rect2(fnx, y + 14, 30, 5), float(v.fuel) / float(SimWorld.START_FUEL), fcol)
	_hits.append([Rect2(fx, y + 2, fnx + 32.0 - fx, 20), "info", "fuel"])
	# view tabs
	for i in TABS.size():
		var t: String = TABS[i]
		var tr := Rect2(TAB_X + i * (TAB_W + 3.0), y + 3, TAB_W, 18)
		UiKit.tab(self, tr, TAB_LABELS[t], TAB_KEYS[t], _tab == t, _is_hover("tab", t), _badge(v, t))
		_hits.append([tr, "tab", t])
	# clock and ROLL OUT side by side: the time pressure next to the action that ends it
	var br := Rect2(r.end.x - 96, y + 2, 94, 20)
	var t2: String = UiKit.clock(world.phase_ticks_left)
	var low: bool = world.phase_ticks_left < 5 * SimWorld.TICK_RATE
	var tcol: Color = Gfx.UI_BAD if low and fmod(_blink, 0.5) < 0.25 else Gfx.FIRE[4]
	var tx: float = br.position.x - 6.0 - UiFont.width_big(t2, 2)
	UiFont.draw_big(self, t2, Vector2(tx, y + 6), tcol, Gfx.OUTLINE, 2)
	UiFont.draw_small(self, "ROLL OUT IN", Vector2(tx - 4.0 - UiFont.width_small("ROLL OUT IN"), y + 6), Gfx.UI_DIM)
	var need: int = 0
	var ready_n: int = 0
	for o in world.vehicles:
		if not o.eliminated:
			need += 1
			ready_n += 1 if o.ready else 0
	if need > 1:
		UiFont.draw_small(self, "%d/%d READY" % [ready_n, need], Vector2(tx - 4.0 - UiFont.width_small("%d/%d READY" % [ready_n, need]), y + 14),
			Gfx.HAZARD if ready_n > 0 else Gfx.UI_DIM)
	if v.ready:
		UiKit.go_button(self, br, "WAITING", "%d / %d READY" % [ready_n, need], false, false)
	else:
		UiKit.go_button(self, br, "ROLL OUT", "SPACE", _is_hover("ready"), true, fmod(_blink, 1.0) < 0.6)
	_hits.append([br, "ready", null])


## Small call to action on a tab: a part to pick, tech nodes you can afford, rules in use.
func _badge(v: SimVehicle, t: String) -> String:
	match t:
		"parts":
			return "1" if not v.picked and not v.offers.is_empty() else ""
		"tech":
			var n: int = 0
			for id in Tech.ids():
				if TechTreeView.state(v, id) == TechTreeView.State.BUYABLE:
					n += 1
			return str(n) if n > 0 else ""
		"rules":
			var used: int = v.rules.size()
			for k: String in v.weapon_doctrine:
				used += (v.weapon_doctrine[k]["rules"] as Array).size()
			return str(used) if used > 0 else ""
	return ""


## This workshop's fuel drain of `v` from the WorldView log while the notice is up ({} = none).
func _drain_now(v: SimVehicle) -> Dictionary:
	if view == null:
		return {}
	for i in range(view.drain_log.size() - 1, -1, -1):
		var e: Dictionary = view.drain_log[i]
		if int(e["id"]) == v.id and int(e["round"]) == world.round and world.tick - int(e["tick"]) < DRAIN_NOTICE_TICKS:
			return e
	return {}


# ---------------------------------------------------------------- YOUR RIG (left)

func _draw_rig_panel(v: SimVehicle) -> void:
	var r := Rect2(LEFT_X, BODY_Y, COL_W, BODY_BOTTOM - BODY_Y - 4.0)
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var w: float = r.size.x - 12.0
	var xr: float = x0 + w
	var y: float = r.position.y + 5.0
	UiKit.section(self, "YOUR RIG", Vector2(x0, y), w)
	y += 9.0
	UiKit.swatch(self, Rect2(x0, y, 8, 8), v.color_index)
	UiKit.paint_big(self, UiKit.player_name(v), Vector2(x0 + 11, y + 1), v.color_index)
	y += 14.0
	# stats as a 2-column grid of big numbers
	var stats: Array = [["HP", str(roundi(v.max_hp))], ["ARMOUR", UiKit.num(v.armor)], ["SPEED", UiKit.pct(v.speed)],
		["SCRAP GAIN", "X" + UiKit.num(v.scrap_mult)]]
	if v.regen > 0.0:
		stats.append(["REPAIR", "%s/S" % UiKit.num(v.regen)])
	if v.contact_damage > 0.0:
		stats.append(["RAM", "%s/T" % UiKit.num(v.contact_damage)])
	for i in stats.size():
		var sx: float = x0 + (i % 2) * floorf(w / 2.0)
		var sy: float = y + (i / 2) * 18.0
		UiFont.draw_small(self, stats[i][0], Vector2(sx, sy), Gfx.UI_DIM)
		UiFont.draw_big(self, stats[i][1], Vector2(sx, sy + 7), Gfx.UI_TEXT, Gfx.OUTLINE)
	y += ceilf(stats.size() / 2.0) * 18.0 + 4.0
	# guns, then the other parts
	UiKit.section(self, "GUNS", Vector2(x0, y), w, "%d/%d SLOTS" % [Cards.weapon_cards_owned(v), v.weapon_slots])
	y += 10.0
	for id: String in v.cards:
		if Cards.is_weapon(id):
			_part_row(id, int(v.cards[id]), x0, xr, y)
			y += 10.0
	for k in maxi(v.weapon_slots - Cards.weapon_cards_owned(v), 0):
		UiFont.draw(self, "- FREE SLOT", Vector2(x0 + 10, y), Gfx.STEEL[3])
		y += 10.0
	y += 3.0
	UiKit.section(self, "PARTS", Vector2(x0, y), w)
	y += 10.0
	var parts: int = 0
	for id: String in v.cards:
		if not Cards.is_weapon(id):
			if y > r.end.y - 62.0:
				UiFont.draw(self, "+ MORE", Vector2(x0 + 10, y), Gfx.UI_DIM)
				y += 10.0
				break
			_part_row(id, int(v.cards[id]), x0, xr, y)
			y += 10.0
			parts += 1
	if parts == 0:
		UiFont.draw(self, "NONE YET - PICK ONE", Vector2(x0 + 10, y), Gfx.STEEL[3])
		y += 10.0
	# doctrine summary at the bottom; the RULES view is where it is edited
	var dy: float = r.end.y - 44.0
	UiKit.section(self, "DOCTRINE", Vector2(x0, dy), w)
	dy += 10.0
	var crt := Rect2(x0 - 1, dy - 2, w + 2, 12)
	draw_rect(crt, Gfx.CRT_BG)
	var doc := "> %s / %s" % [str(v.doctrine["drive"]).to_upper(), TARGET_LABELS.get(str(v.doctrine["target"]), "?")]
	UiFont.draw(self, doc, Vector2(x0 + 2, dy + 1), Gfx.CRT_TEXT)
	var n_rules: int = v.rules.size()
	for k: String in v.weapon_doctrine:
		n_rules += (v.weapon_doctrine[k]["rules"] as Array).size()
	var rb := Rect2(x0, dy + 13, w, 13)
	UiKit.button(self, rb, ("EDIT RULES (%d SET)   P" % n_rules) if n_rules > 0 else "PROGRAM RULES   P", _is_hover("tab", "rules"))
	_hits.append([rb, "tab", "rules"])
	if world.is_underdog(v):
		var ut := "UNDERDOG: -30% FUEL LOSS"
		var ur := Rect2(x0 - 1, dy - 26, UiFont.width(ut) + 10.0, 10)
		UiKit.tape(self, ur, Color("#e8dcc4"))
		UiFont.draw(self, ut, ur.position + Vector2(5, 2), Gfx.INK)


func _part_row(id: String, lvl: int, x0: float, xr: float, y: float) -> void:
	draw_rect(Rect2(x0, y - 1, 7, 7), Gfx.OUTLINE)
	draw_rect(Rect2(x0 + 1, y, 5, 5), UiKit.card_color(id))
	UiFont.draw(self, UiKit.card_name(id), Vector2(x0 + 10, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiKit.pips(self, Vector2(xr - 16, y), lvl, Cards.MAX_LEVEL, Gfx.FIRE[4])


# ---------------------------------------------------------------- draft cards (centre)

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
	# reroll: a secondary button with its price
	var rr := Rect2(cx - 50, CARD_Y + CARD_SIZE.y + 8.0, 100, 15)
	var can: bool = not v.picked and v.scrap >= v.reroll_cost
	UiKit.button(self, rr, "", _is_hover("reroll"), can)
	var label := "REROLL  R"
	var cost := "%d" % v.reroll_cost
	var lw: float = UiFont.width(label) + 8.0 + 9.0 + UiFont.width(cost)
	var lx: float = floorf(cx - lw / 2.0)
	UiFont.draw(self, label, Vector2(lx, rr.position.y + 5), (Gfx.FIRE[5] if _is_hover("reroll") else Gfx.UI_TEXT) if can else Gfx.UI_DIM, Gfx.OUTLINE)
	_scrap_pip(Vector2(lx + UiFont.width(label) + 8, rr.position.y + 5))
	UiFont.draw(self, cost, Vector2(lx + UiFont.width(label) + 17, rr.position.y + 5),
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


## Tiny 5x5 scrap marker (a nut) for prices.
func _scrap_pip(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(1, 0), Vector2(5, 5)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(0, 1), Vector2(7, 3)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(5, 3)), Gfx.STEEL[4])
	draw_rect(Rect2(p + Vector2(3, 2), Vector2(1, 1)), Gfx.OUTLINE)


# ---------------------------------------------------------------- convoy (right, bottom)

func _draw_convoy(v: SimVehicle) -> void:
	var n: int = world.vehicles.size()
	if n < 2:
		return
	var h: float = 18.0 + n * 10.0
	var r := Rect2(RIGHT_X, BODY_BOTTOM - 4.0 - h, COL_W, h)
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	UiKit.section(self, "CONVOY", Vector2(x0, r.position.y + 5), r.size.x - 12, "HOVER TO SCOUT")
	var y: float = r.position.y + 15.0
	for o in world.vehicles:
		if o != v:
			var rr := Rect2(r.position.x + 3, y - 2, r.size.x - 6, 10)
			if _is_hover("scout", o.id) or _scout_pin == o.id:
				draw_rect(rr, UiKit.HOVER_WASH)
				UiKit.outline_rect(self, rr, Gfx.HAZARD if _scout_pin == o.id else Gfx.UI_DIM)
			_hits.append([rr, "scout", o.id])
		UiKit.swatch(self, Rect2(x0 - 1, y - 1, 7, 7), o.color_index)
		var nx: float = UiKit.paint_text(self, UiKit.player_name(o), Vector2(x0 + 9, y), o.color_index)
		if o == v:
			UiFont.draw(self, "(YOU)", Vector2(nx + 3, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		var st: String = "OUT" if o.eliminated else ("READY" if o.ready else "TINKERING")
		var sc: Color = Gfx.UI_DIM if o.eliminated else (Gfx.HAZARD if o.ready else Gfx.UI_DIM)
		UiFont.draw(self, st, Vector2(r.end.x - 6 - UiFont.width(st), y), sc, Gfx.UI_SHADOW)
		y += 10.0


# ---------------------------------------------------------------- last round recap (right, #2)

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
	var segs: Array[Dictionary] = Recap.segments(world, v)
	var legend: Array[Dictionary] = []
	for sg: Dictionary in segs:
		if float(sg["frac"]) >= 0.05 and legend.size() < 4:
			legend.append(sg)
	var hint_h: float = 0.0
	var hint_lines: PackedStringArray = []
	if not h.is_empty():
		hint_lines = UiFont.wrap("> " + str(h["text"]), int(COL_W) - 18)
		hint_h = 8.0 + hint_lines.size() * 8.0 + 13.0
	var r := Rect2(RIGHT_X, BODY_Y, COL_W, 75.0 + maxf(legend.size(), 1) * 9.0 + hint_h)
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var w: float = r.size.x - 12.0
	var xr: float = x0 + w
	var y: float = r.position.y + 5.0
	var tot: float = Recap.total_taken(v)
	UiKit.section(self, "LAST ROUND %d" % int(rs["round"]), Vector2(x0, y), w, "%d HP TAKEN" % roundi(tot))
	y += 10.0
	y = _recap_headline(v, Vector2(x0, y), tot, xr)
	# damage by source: one stacked bar, then a legend line per big slice
	var bar := Rect2(x0, y, w, 6)
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
	y += 10.0
	for sg: Dictionary in legend:
		var col2: Color = sg["color"]
		draw_rect(Rect2(x0, y, 5, 5), Gfx.OUTLINE)
		draw_rect(Rect2(x0 + 1, y + 1, 3, 3), col2)
		if int(sg["paint"]) >= 0:
			UiKit.paint_text(self, str(sg["label"]), Vector2(x0 + 8, y), int(sg["paint"]))
		else:
			UiFont.draw(self, str(sg["label"]), Vector2(x0 + 8, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		var pt: String = UiKit.pct(float(sg["frac"]))
		UiFont.draw(self, pt, Vector2(xr - UiFont.width(pt), y), Gfx.UI_DIM, Gfx.UI_SHADOW)
		y += 9.0
	if legend.is_empty():
		UiFont.draw(self, "NOTHING GOT THROUGH", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
		y += 9.0
	y += 3.0
	# earnings and fuel as label / value rows
	var ex: float = _kv("KILLS", str(int(rs.get("kills", 0))), Vector2(x0, y), Gfx.UI_TEXT)
	if world.vehicles.size() > 1:
		_kv("RIGS", str(int(rs.get("kills_players", 0))), Vector2(ex, y), Gfx.UI_TEXT)
	y += 9.0
	ex = _kv("SCRAP", "+%d" % int(rs.get("scrap_earned", 0)), Vector2(x0, y), Gfx.FIRE[4])
	_kv("INTEREST", "+%d" % int(rs.get("interest", 0)), Vector2(ex, y), Gfx.FIRE[4])
	y += 9.0
	var fx: float = UiFont.draw(self, "FUEL", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var parts: Array = []  # [text, colour]
	if int(rs.get("fuel_lost", 0)) > 0:
		parts.append(["-%d LOST" % int(rs["fuel_lost"]), Gfx.UI_BAD])
	if int(rs.get("fuel_gained", 0)) > 0:
		parts.append(["+%d STOLEN" % int(rs["fuel_gained"]), Gfx.FIRE[4]])
	if int(rs.get("fuel_drained", 0)) > 0:
		parts.append(["-%d DRAIN" % int(rs["fuel_drained"]), Gfx.UI_BAD])
	if parts.is_empty():
		parts.append(["NO LOSS", Gfx.UI_DIM])
	for pt2: Array in parts:
		fx = UiFont.draw(self, pt2[0], Vector2(fx + 5.0, y), pt2[1], Gfx.UI_SHADOW)
	y += 11.0
	if not h.is_empty():
		_draw_hint(v, h, hint_lines, Rect2(x0 - 1, y, w + 2, hint_h - 4.0))


## Headline lines ("WRECKED AT 0:57" / "BY A BOULDER", or a clean round); returns the y below.
func _recap_headline(v: SimVehicle, pos: Vector2, tot: float, xr: float) -> float:
	var ds: Array = Recap.deaths(v)
	if ds.is_empty():
		var ok: String = "CLEAN ROUND - NOT A SCRATCH" if tot < 1.0 else "SURVIVED THE ROUND"
		UiFont.draw(self, ok, pos, Gfx.FIRE[4], Gfx.UI_SHADOW)
		return pos.y + 11.0
	var last: Dictionary = ds[-1]
	var when: String = UiKit.clock(int(last.get("t", 0)))
	var head: String
	if v.eliminated:
		head = "RAN DRY AT %s" % when
	elif ds.size() > 1:
		head = "WRECKED %dX - LAST AT %s" % [ds.size(), when]
	else:
		head = "WRECKED AT %s" % when
	UiFont.draw(self, head, pos, Gfx.UI_BAD, Gfx.UI_SHADOW)
	var y: float = pos.y + 9.0
	var x: float = UiFont.draw(self, "BY ", Vector2(pos.x, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var cause: String = str(last.get("cause", ""))
	var killer: SimVehicle = UiKit.vehicle_by_id(world, int(last.get("killer", -1)))
	if killer != null and (cause == "player" or cause == "ram"):
		x = UiKit.paint_text(self, UiKit.player_name(killer), Vector2(x, y), killer.color_index)
		var wk: int = Recap.killer_weapon(view, v.id, killer.id, world.round)
		var wt: String = UiKit.weapon_long(wk) if wk >= 0 else ("RAMMED" if cause == "ram" else "")
		if wt != "":
			if x + UiFont.width(" - " + wt) > xr:
				y += 9.0
				x = pos.x
			UiFont.draw(self, (" - " if x > pos.x else "") + wt, Vector2(x, y), Gfx.FIRE[4] if wt == "RAMMED" else Gfx.UI_TEXT, Gfx.UI_SHADOW)
	else:
		UiFont.draw(self, str(UiKit.CAUSE_TEXT.get(cause, "THE HIVE")), Vector2(x, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	return y + 11.0


## "LABEL value" pair; returns the x for the next pair.
func _kv(label: String, value: String, pos: Vector2, col: Color) -> float:
	var x: float = UiFont.draw(self, label, pos, Gfx.UI_DIM, Gfx.UI_SHADOW) + 4.0
	return UiFont.draw(self, value, Vector2(x, pos.y), col, Gfx.UI_SHADOW) + 8.0


## The doctrine hint on a sliver of the nav-comp's amber CRT: the advice, then clickable chips.
func _draw_hint(v: SimVehicle, h: Dictionary, lines: PackedStringArray, r: Rect2) -> void:
	draw_rect(r, Gfx.STEEL[1])
	var scr: Rect2 = r.grow(-1.0)
	draw_rect(scr, Gfx.CRT_BG)
	var y: float = scr.position.y + 3.0
	for ln in lines:
		UiFont.draw(self, ln, Vector2(scr.position.x + 3, y), Gfx.CRT_TEXT)
		y += 8.0
	var opts: Array = h.get("options", [])
	var cx: float = scr.position.x + 3.0
	for i in opts.size():
		var opt: Dictionary = opts[i]
		var on: bool = Recap.applied(v, opt)
		var label: String = ("%s SET" % str(opt["label"]).trim_prefix("SET ").trim_prefix("TARGET ")) if on else str(opt["label"])
		if i == 0 and not on:
			label += "  H"
		var cw: float = UiFont.width(label) + 6.0
		var cr := Rect2(cx, y, cw, 10)
		var hov: bool = _is_hover("hint", i)
		if on:
			UiKit.outline_rect(self, cr, Gfx.CRT_DIM)
			UiFont.draw(self, label, cr.position + Vector2(3, 2), Gfx.CRT_HI)
		else:
			draw_rect(cr, Gfx.CRT_TEXT if hov or fmod(_blink, 1.0) < 0.6 else Gfx.CRT_DIM)
			UiFont.draw(self, label, cr.position + Vector2(3, 2), Gfx.CRT_BG)
			if hov:
				UiKit.outline_rect(self, cr.grow(1.0), Gfx.CRT_HI)
		_hits.append([cr, "hint", i])
		cx = cr.end.x + 3.0
	for sy in range(int(scr.position.y) + 1, int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.22))


# ---------------------------------------------------------------- scouting (#10)

## Whose dossier to show: the hovered convoy row, else the pinned one (null = none).
func _scout_target() -> SimVehicle:
	var id: int = _scout_pin
	if not _hover.is_empty() and _hover[1] == "scout":
		id = int(_hover[2])
	return UiKit.vehicle_by_id(world, id)


## A rival's build at a glance: fuel, hp, armour, speed, guns with levels, other parts, tech per
## branch, doctrine. All from the synced vehicle state (also used by the spectator layout).
func _draw_dossier(o: SimVehicle, r: Rect2, closable: bool) -> void:
	var guns: int = Cards.weapon_cards_owned(o)
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	var scout_rules: bool = me != null and me != o and float(me.tech_fx.get("scout_rules", 0.0)) > 0.0 and not o.rules.is_empty()
	var need: float = 70.0 + 9.0 * guns + 9.0 * maxi(o.cards.size() - guns, 0) + 52.0 + (18.0 if scout_rules else 0.0)
	r.size.y = minf(r.size.y, need)
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var xr: float = r.end.x - 6.0
	var y: float = r.position.y + 5.0
	UiKit.section(self, "SCOUT REPORT", Vector2(x0, y), xr - x0 - (34.0 if closable else 0.0))
	if closable:
		var cr := Rect2(xr - 30, y - 2, 31, 10)
		UiKit.button(self, cr, "CLOSE", _is_hover("unscout"))
		_hits.append([cr, "unscout", null])
	y += 11.0
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
	y += 11.0
	UiKit.section(self, "GUNS", Vector2(x0, y), xr - x0, "%d/%d" % [Cards.weapon_cards_owned(o), o.weapon_slots])
	y += 9.0
	for id: String in o.cards:
		if Cards.is_weapon(id):
			_part_row(id, int(o.cards[id]), x0, xr, y)
			y += 9.0
	y += 2.0
	var parts: Array[String] = []
	for id: String in o.cards:
		if not Cards.is_weapon(id):
			parts.append(id)
	UiKit.section(self, "PARTS" if not parts.is_empty() else "PARTS - NONE YET", Vector2(x0, y), xr - x0)
	y += 9.0
	var room: int = int((r.end.y - y - 41.0) / 9.0)
	for i in parts.size():
		if i >= room and parts.size() > room:
			UiFont.draw(self, "+%d MORE" % (parts.size() - i), Vector2(x0 + 8, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
			y += 9.0
			break
		_part_row(parts[i], int(o.cards[parts[i]]), x0, xr, y)
		y += 9.0
	# tech per branch
	y = maxf(y + 2.0, r.end.y - 39.0)
	UiKit.section(self, "TECH", Vector2(x0, y), xr - x0, "%d/%d" % [o.tech.size(), Tech.count()])
	y += 9.0
	var tw: float = floorf((xr - x0) / float(Tech.BRANCHES.size()))
	for bi in Tech.BRANCHES.size():
		var b: String = Tech.BRANCHES[bi]
		var bx0: float = x0 + bi * tw
		var tier: int = Tech.branch_tier(o, b)
		UiFont.draw(self, b.left(3).to_upper(), Vector2(bx0, y), Gfx.UI_TEXT if tier > 0 else Gfx.STEEL[3], Gfx.UI_SHADOW)
		UiFont.draw(self, "%d/%d" % [tier, Tech.MAX_TIER], Vector2(bx0, y + 7), Gfx.BRASS[3] if tier > 0 else Gfx.STEEL[3], Gfx.UI_SHADOW)
	y += 14.0
	# doctrine on a sliver of CRT
	var dr := Rect2(x0 - 1, y, xr - x0 + 2, 11)
	draw_rect(dr, Gfx.STEEL[1])
	draw_rect(dr.grow(-1.0), Gfx.CRT_BG)
	var doc := "> %s / %s" % [str(o.doctrine["drive"]).to_upper(), TARGET_LABELS.get(str(o.doctrine["target"]), "?")]
	UiFont.draw(self, doc, dr.position + Vector2(3, 3), Gfx.CRT_TEXT)
	if scout_rules:  # radar array: the rival's rules in plain words (first two rules)
		var ry: float = dr.end.y + 3.0
		for k in mini(2, o.rules.size()):
			UiFont.draw_small(self, DoctrineEditor.sentence(o.rules[k], Doctrine.SCOPE_RIG).left(46), Vector2(x0, ry), Gfx.CRT_DIM)
			ry += 8.0


# ---------------------------------------------------------------- spectator workshop (#5)

## Eliminated: no shop. Top bar, your match on the left with the watched rig's dossier under it,
## standings in the middle (click a rig to watch and scout it), your last round on the right.
func _draw_spectator(v: SimVehicle, vs: Vector2) -> void:
	_draw_spectator_bar(vs)
	var out_r: Rect2 = _draw_out(v)
	_draw_recap(v)
	var watched: SimVehicle = view.focus_vehicle() if view != null else null
	_draw_standings_panel(v, watched, vs)
	var scout: SimVehicle = null
	if not _hover.is_empty() and _hover[1] == "watch":
		scout = UiKit.vehicle_by_id(world, int(_hover[2]))
	if scout == null:
		scout = watched
	if scout != null:
		_draw_dossier(scout, Rect2(LEFT_X, out_r.end.y + 6.0, COL_W, BODY_BOTTOM - 4.0 - out_r.end.y - 6.0), false)
	UiKit.footer(self, "SPECTATING      TAB  < >  SWITCH RIG      CLICK A RIG TO WATCH IT      ESC  MENU", vs)


func _draw_spectator_bar(_vs: Vector2) -> void:
	var r: Rect2 = BAR
	UiKit.plate(self, r)
	var y: float = r.position.y
	UiFont.draw_big(self, "WORKSHOP", Vector2(r.position.x + 7, y + 5), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw_small(self, "AFTER ROUND %d" % world.round, Vector2(r.position.x + 7, y + 15), Gfx.UI_DIM)
	UiKit.hazard_band(self, Rect2(r.position.x + 70, y + 8, 6, 8))
	UiFont.draw_big(self, "OUT OF FUEL - SPECTATING", Vector2(r.position.x + 82, y + 8), Gfx.UI_BAD, Gfx.OUTLINE)
	var t2: String = UiKit.clock(world.phase_ticks_left)
	var tx: float = r.end.x - 7.0 - UiFont.width_big(t2, 2)
	UiFont.draw_big(self, t2, Vector2(tx, y + 6), Gfx.FIRE[4], Gfx.OUTLINE, 2)
	UiFont.draw_small(self, "ROLL OUT IN", Vector2(tx - 4.0 - UiFont.width_small("ROLL OUT IN"), y + 6), Gfx.UI_DIM)


## Left column: you are out, and your match so far. Returns its rect.
func _draw_out(v: SimVehicle) -> Rect2:
	var r := Rect2(LEFT_X, BODY_Y, COL_W, 62 if int(v.match_stats.get("nemesis", -1)) < 0 else 73)
	UiKit.panel(self, r)
	var x0: float = r.position.x + 6.0
	UiKit.section(self, "YOUR MATCH", Vector2(x0, r.position.y + 5), r.size.x - 12)
	var ms: Dictionary = v.match_stats
	var y: float = r.position.y + 16.0
	var rows: Array = [["ALIENS KILLED", str(int(ms.get("kills", 0)))], ["RIGS WRECKED", str(int(ms.get("player_kills", 0)))],
		["TIMES WRECKED", str(int(ms.get("deaths", 0)))], ["SCRAP EARNED", str(int(ms.get("scrap_earned", 0)))]]
	for row: Array in rows:
		UiFont.draw(self, row[0], Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
		UiFont.draw(self, row[1], Vector2(r.end.x - 6 - UiFont.width(row[1]), y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		y += 10.0
	var nem: SimVehicle = UiKit.vehicle_by_id(world, int(ms.get("nemesis", -1)))
	if nem != null:
		var x: float = UiFont.draw(self, "NEMESIS ", Vector2(x0, y + 1), Gfx.UI_DIM, Gfx.UI_SHADOW)
		x = UiKit.paint_text(self, UiKit.player_name(nem), Vector2(x, y + 1), nem.color_index)
		UiFont.draw(self, " X%d" % int(ms.get("nemesis_n", 0)), Vector2(x, y + 1), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	return r


## Centre: every rig with fuel, kills, rigs wrecked, tech and workshop status; click to watch.
func _draw_standings_panel(me: SimVehicle, watched: SimVehicle, vs: Vector2) -> void:
	var rows: Array[SimVehicle] = UiKit.standings(world)
	var w: float = 312.0
	var r := Rect2(floorf(vs.x / 2.0 - w / 2.0), CARD_Y, w, 22 + rows.size() * 11)
	UiKit.panel(self, r)
	var cols: Array[float] = [r.position.x + 8, r.position.x + 22, r.position.x + 120, r.position.x + 182, r.position.x + 212, r.position.x + 240, r.end.x - 8]
	var y: float = r.position.y + 6.0
	for i in 5:
		UiFont.draw_small(self, ["#", "STANDINGS", "FUEL", "KILLS", "RIGS"][i], Vector2(cols[i], y), Gfx.UI_DIM)
	UiFont.draw_small(self, "TECH", Vector2(cols[5], y), Gfx.UI_DIM)
	UiFont.draw_small(self, "CAMP", Vector2(cols[6] - UiFont.width_small("CAMP"), y), Gfx.UI_DIM)
	y += 12.0
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
