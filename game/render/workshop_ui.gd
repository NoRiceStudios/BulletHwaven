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
	"boulders": "BOULDERS", "spitters": "SPITTERS", "boss": "BOSS", "shriekers": "SHRIEKERS", "intruders": "INTRUDERS"}
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
var _deploy_shown: bool = false  ## the deploy screen (phase PHASE_DEPLOY) is up

## Deploy screen (before round 1): starting doctrine presets in a column on the left, the rule editor on the right.
const DEPLOY_COL := Rect2(6, 34, 126, 310)
const DEPLOY_EDITOR := Rect2(138, 34, 496, 310)
const PRESET_H := 56.0  ## five starting doctrines fit DEPLOY_COL
## Pending tech swap waiting for confirmation in the TECH view ({"from", "to"}; {} = none).
var confirm: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false


func _process(delta: float) -> void:
	var was: bool = visible
	var was_deploy: bool = _deploy_shown
	_deploy_shown = world != null and world.phase == SimWorld.PHASE_DEPLOY and _local() != null
	visible = world != null and (world.phase == SimWorld.PHASE_WORKSHOP or _deploy_shown) and _local() != null
	if _deploy_shown:
		_toast_left = maxf(_toast_left - delta, 0.0)
		_blink += delta
		if rules != null and (not rules.is_open or rules._embed != DEPLOY_EDITOR):
			rules.open_embedded(DEPLOY_EDITOR)
		queue_redraw()
		return
	if was_deploy and rules != null and rules.embedded():
		rules.close()  # round 1 starts: the dock and P take over
		was = false
	_toast_left = maxf(_toast_left - delta, 0.0)
	_blink += delta
	if visible and not was:
		_scout_pin = -1
		if use_real_pointer:
			TechGuide.persist = true
			if world.round <= 1:
				TechGuide.note_match(world)  # the first workshop of a match: beginner-view counter
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


## The UI pointer (mouse, or the screenshot override).
func pointer() -> Vector2:
	return _pointer()


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
	confirm = {}
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
		KEY_1, KEY_2, KEY_3, KEY_4:
			activate("pick", int(key - KEY_1))
		KEY_5:
			if _deploy_shown:  # the fifth starting doctrine (the workshop has three cards)
				activate("pick", 4)
			else:
				handled = false
		KEY_R:
			activate("reroll", null)
		KEY_SPACE, KEY_ENTER:
			if not confirm.is_empty():
				activate("swap_ok" if key == KEY_ENTER else "swap_cancel", null)
			else:
				activate("ready", null)
		KEY_H:
			activate("hint", 0)
		KEY_T:
			activate("tab", "parts" if _tab == "tech" else "tech")
		KEY_ESCAPE:
			if not confirm.is_empty():
				activate("swap_cancel", null)
			elif _tab != "parts":
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
	if (_tab == "rules" or _deploy_shown) and rules != null and rules.menu_open():
		return rules.click_at(p)  # an open picker may reach over the top bar: it gets the click first
	var h: Array = _hit_at(p)
	if h.is_empty():
		if (_tab == "rules" or _deploy_shown) and rules != null and rules.is_open:
			return rules.click_at(p)
		return false
	activate(h[1], h[2])
	return true


## Every button, card, node and key ends here. Illegal actions only show a toast.
func activate(action: String, arg: Variant) -> void:
	var v: SimVehicle = _local()
	if v == null:
		return
	if world.phase == SimWorld.PHASE_DEPLOY:
		_activate_deploy(v, action, arg)
		return
	if world.phase != SimWorld.PHASE_WORKSHOP:
		return
	if v.eliminated and action in ["pick", "reroll", "tech", "ready", "hint", "tab", "ammo", "ability", "swap_ok"]:
		return  # spectator: read-only
	match action:
		"tab":
			var t: String = str(arg).get_slice(":", 0)  # "tech:<branch>" from the compact column
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
					if _tab != "tech":
						_set_tab("tech")
					confirm = {"from": swap_from, "to": id}  # TechTreeView.draw_confirm asks first
				else:
					_say("CANNOT SWAP %s NOW" % UiKit.tech_name(swap_from))
			elif Tech.missing(v, id) != "":
				_say("BUILD %s FIRST" % UiKit.tech_name(Tech.next_step(v, id)))
			elif v.scrap < Tech.price(v, id):
				_say("NEED %d SCRAP" % Tech.price(v, id))
			else:
				_send({"type": "buy_tech", "value": id})
		"swap_ok":  # the confirmed respec
			if not confirm.is_empty():
				var f: String = str(confirm["from"])
				var t2: String = str(confirm["to"])
				confirm = {}
				if Tech.can_respec(v, f, t2, world.round):
					_send({"type": "respec_tech", "from": f, "value": t2})
					_say("SWAPPED IN %s" % UiKit.tech_name(t2))
		"swap_cancel":
			confirm = {}
		"tpl":  # follow a build template (client-side, this match)
			TechGuide.set_template(world, str(arg))
		"beginner":
			TechGuide.set_beginner(bool(arg))
		"expand":  # beginner view: open / fold a branch under MORE
			TechGuide.toggle_opened(str(arg))
		"ammo":  # [weapon kind, ammo id]
			var a: Array = arg
			var cur: Array = v.ammo.get(str(a[0]), [])
			if not cur.is_empty() and cur[0] == str(a[1]):
				_say("ALREADY LOADED")
			else:
				_send({"type": "set_ammo", "scope": str(a[0]), "value": str(a[1])})
				_say("%s: %s LOADED" % [UiKit.weapon_short(Cards.weapon_kind_index(str(a[0]))), TechGuide.AMMO_NAMES.get(str(a[1]), "")])
		"ability":  # [slot, ability id]
			var b: Array = arg
			_send({"type": "set_ability", "slot": int(b[0]), "value": str(b[1])})
		"buy_next":  # the plan's next node, from the compact tech column
			activate("tech", arg)
		"accept":  # a contract offer
			if int(arg) >= 0 and int(arg) < v.contract_offers.size():
				_send({"type": "accept_contract", "value": int(arg)})
				_say("CONTRACT ACCEPTED")
		"reserve":  # haggler: keep an offered card for the next workshop
			var ri: int = int(arg)
			if v.picked or ri < 0 or ri >= v.offers.size():
				_say("NOTHING TO RESERVE")
			else:
				_send({"type": "reserve_card", "value": ri})
				_say("RESERVE CLEARED" if v.reserved_card == v.offers[ri] else "RESERVED FOR NEXT TIME")
		"scrap":  # scrap press: sell one level of an owned card
			var sid: String = str(arg)
			if not v.cards.has(sid):
				_say("NO SUCH PART")
			elif Cards.is_weapon(sid) and int(v.cards[sid]) <= 1 and Cards.weapon_cards_owned(v) <= 1:
				_say("KEEP YOUR LAST GUN")
			else:
				_send({"type": "scrap_card", "value": sid})
				_say("SCRAPPED +%d" % (int(v.cards[sid]) * Salvage.PRESS_PER_LEVEL))
		"ready":
			if not v.ready:
				_send({"type": "ready"})


# ---------------------------------------------------------------- deploy (before round 1)

func _activate_deploy(v: SimVehicle, action: String, arg: Variant) -> void:
	match action:
		"pick", "preset":
			var i: int = int(arg)
			if i < 0 or i >= DoctrinePresets.LIST.size():
				return
			var p: Dictionary = DoctrinePresets.LIST[i]
			for cmd in DoctrinePresets.commands(p):
				_send(cmd)
			if rules != null:
				rules.show_work(Doctrine.SCOPE_RIG, Doctrine.parse(p["rules"], Doctrine.SCOPE_RIG))
			_say("%s LOADED" % p["name"])
		"ready":
			if not v.ready:
				_send({"type": "ready"})


func _draw_deploy(v: SimVehicle, vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.035, 0.03, 0.55))
	_draw_deploy_bar(v)
	var col: Rect2 = DEPLOY_COL
	UiKit.section(self, "STARTING DOCTRINE", col.position + Vector2(0, 2), col.size.x)
	var cur: String = DoctrinePresets.current(v)
	var y: float = col.position.y + 14.0
	for i in DoctrinePresets.LIST.size():
		_draw_preset(DoctrinePresets.LIST[i], i, Rect2(col.position.x, y, col.size.x, PRESET_H - 4.0), cur)
		y += PRESET_H
	var custom: bool = cur == "" and not v.rules.is_empty()
	var note: String = "CUSTOM - EDITED BY HAND" if custom else "PICK ONE, THEN TUNE IT ON THE RIGHT"
	UiFont.draw_small(self, note, Vector2(col.position.x + 2, y + 1), Gfx.CRT_HI if custom else Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiKit.footer(self, "1-5  PRESET    SPACE  ROLL OUT    IN COMBAT: CLICK THE DOCK TO SWITCH    RIGHT-CLICK  MARK    Z X C V  RADIO", vs)
	_draw_toast(vs)


func _draw_deploy_bar(v: SimVehicle) -> void:
	var r: Rect2 = BAR
	UiKit.plate(self, r)
	_hits.append([r, "none", null])
	var y: float = r.position.y
	UiFont.draw_big(self, "DEPLOYMENT", Vector2(r.position.x + 7, y + 5), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw_small(self, "BEFORE ROUND 1", Vector2(r.position.x + 7, y + 15), Gfx.UI_DIM)
	var mx: float = r.position.x + 98.0
	UiFont.draw(self, "SET HOW YOUR RIG DRIVES AND WHAT IT SHOOTS", Vector2(mx, y + 4), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiFont.draw_small(self, "YOU CAN CHANGE IT ANY TIME DURING THE ROUND", Vector2(mx, y + 14), Gfx.UI_DIM)
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
		var rt := "%d/%d READY" % [ready_n, need]
		UiFont.draw_small(self, rt, Vector2(tx - 4.0 - UiFont.width_small(rt), y + 14), Gfx.HAZARD if ready_n > 0 else Gfx.UI_DIM)
	if v.ready:
		UiKit.go_button(self, br, "WAITING", "%d / %d READY" % [ready_n, need], false, false)
	else:
		UiKit.go_button(self, br, "ROLL OUT", "SPACE", _is_hover("ready"), true, fmod(_blink, 1.0) < 0.6)
	_hits.append([br, "ready", null])


## One starting doctrine as a CRT card: key, name, tag, three plain lines; lit when the rig runs exactly it.
func _draw_preset(p: Dictionary, i: int, r: Rect2, cur: String) -> void:
	var on: bool = cur == p["id"]
	var hov: bool = _is_hover("preset", i)
	draw_rect(r.grow(1), Gfx.OUTLINE)
	draw_rect(r, Gfx.CRT_BG)
	if hov and not on:
		draw_rect(r, Color(Gfx.CRT_TEXT, 0.12))
	UiKit.outline_rect(self, r.grow(-1), Gfx.CRT_HI if on else (Gfx.CRT_TEXT if hov else Gfx.CRT_DIM))
	var head := Rect2(r.position + Vector2(2, 2), Vector2(r.size.x - 4, 12))
	if on:
		draw_rect(head, Gfx.CRT_TEXT)
	var hc: Color = Gfx.CRT_BG if on else Gfx.CRT_HI
	var x: float = UiFont.draw(self, "%d " % (i + 1), head.position + Vector2(3, 2), Gfx.CRT_BG if on else Gfx.CRT_DIM)
	UiFont.draw(self, p["name"], Vector2(x, head.position.y + 2), hc)
	var tag: String = "ACTIVE" if on else str(p["tag"])
	UiFont.draw_small(self, tag, Vector2(head.end.x - 3 - UiFont.width_small(tag), head.position.y + 3), Gfx.CRT_BG if on else Gfx.CRT_DIM)
	var y: float = head.end.y + 3.0
	for line: String in p["lines"]:
		UiFont.draw_small(self, line, Vector2(r.position.x + 6, y), Gfx.CRT_TEXT)
		y += 8.0
	var lbl: String = "%s / %s" % [str(DoctrineEditor.ACTION_LABELS.get("drive:" + str(p["drive"]), "")),
		str(DoctrineEditor.ACTION_LABELS.get("target:" + str(p["target"]), "")).trim_prefix("TGT ")]
	UiFont.draw_small(self, lbl, Vector2(r.position.x + 6, r.end.y - 10), Gfx.CRT_DIM)
	_hits.append([r, "preset", i])


func _send(cmd: Dictionary) -> void:
	if send_command.is_valid():
		send_command.call(cmd)


func _say(text: String) -> void:
	_toast = text
	_toast_left = TOAST_SECS


## A longer toast from outside (WorldView: the zone king bonus as the workshop opens).
func say(text: String, secs: float = 4.0) -> void:
	_toast = text
	_toast_left = secs


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
	if world.phase == SimWorld.PHASE_DEPLOY:
		_draw_deploy(v, vs)
		return

	if v.eliminated:
		_draw_spectator(v, vs)
		return
	match _tab:
		"tech":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.035, 0.03, 0.55))
			TechTreeView.draw(self, v, body_rect())
			if not confirm.is_empty():
				TechTreeView.draw_confirm(self, v, body_rect())
			UiKit.footer(self, "CLICK  BUILD OR SWAP      HOVER  DETAILS      T  BACK TO PARTS      SPACE  READY", vs)
		"rules":
			# the editor draws itself into the body (DoctrineEditor.open_embedded)
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.035, 0.03, 0.55))
			UiKit.footer(self, "P  BACK TO PARTS      SPACE  READY", vs)
		_:
			_draw_rig_panel(v)
			_draw_abilities(v)
			_draw_tech_compact(v)
			_draw_cards(v, vs)
			_draw_contracts(v, vs)
			_draw_recap(v)
			_draw_hive()
			_draw_convoy(v)
			var scout: SimVehicle = _scout_target()
			if scout != null:
				_draw_dossier(scout, Rect2(RIGHT_X - COL_W - 6.0, BODY_Y, COL_W, 226), _scout_pin == scout.id)
			UiKit.footer(self, "1 2 3  PICK      R  REROLL      T  TECH      P  RULES      SPACE  READY", vs)
	_draw_bar(v, vs)
	if _tab == "parts":
		_draw_next_boss()
	_draw_toast(vs)
	if view != null and _tab == "parts":  # a weapon just evolved: the banner over the panels, between the columns
		var gap_cx: float = floorf((LEFT_X + COL_W + RIGHT_X - 108.0) / 2.0)  # between the rig and tech panels
		Hud.draw_evolved_banner(self, view.juice, world.tick, gap_cx, BAR.end.y + 22.0, true)
	TechTreeView.draw_gloss(self)


## A compact plate hanging under the top bar, over the gap between the rig panel and the tech column:
## "NEXT BOSS  ROUND 8  SHARD COLOSSUS" (Bosses.next_boss). When the boss comes in the very next round it
## gets a hazard edge and blinks "NEXT ROUND"; an enraged one carries an ENRAGED tag.
func _draw_next_boss() -> void:
	var nb: Dictionary = Bosses.next_boss(world)
	if int(nb.get("kind", -1)) < 0:
		return
	var r_n: int = int(nb["round"])
	var soon: bool = r_n == world.round + 1
	var name_s: String = str(nb["name"])
	var lead: String = "NEXT ROUND" if soon else "ROUND %d" % r_n
	var enr: bool = bool(nb["enraged"])
	var w: float = UiFont.width_small("NEXT BOSS") + UiFont.width(lead) + UiFont.width_title(name_s, 10) + 30.0
	if enr:
		w += UiFont.width_small("ENRAGED") + 12.0
	var cx: float = floorf((LEFT_X + COL_W + RIGHT_X - 108.0) / 2.0)
	var r := Rect2(floorf(cx - w / 2.0), BAR.end.y + 3.0, w, 15)
	UiKit.panel(self, r)
	if soon:
		UiKit.hazard_band(self, Rect2(r.position.x + 1, r.end.y - 3, r.size.x - 2, 2))
	_hits.append([r, "none", null])
	var y: float = r.position.y + 4.0
	var x: float = UiFont.draw_small(self, "NEXT BOSS", Vector2(r.position.x + 6, y + 1), Gfx.UI_DIM) + 6.0
	var hot: bool = soon and fmod(_blink, 1.0) < 0.6
	x = UiFont.draw(self, lead, Vector2(x, y), Gfx.UI_BAD if hot else Gfx.FIRE[4], Gfx.UI_SHADOW) + 6.0
	x = UiFont.draw_title(self, name_s, Vector2(x, y - 1), Gfx.GLOW[4] if soon else Gfx.GLOW[3], 10, Gfx.OUTLINE) + 6.0
	if enr:
		var tr := Rect2(x, y - 2, UiFont.width_small("ENRAGED") + 6.0, 9)
		draw_rect(tr, Gfx.OUTLINE)
		draw_rect(tr.grow(-1.0), Gfx.UI_BAD)
		UiFont.draw_small(self, "ENRAGED", tr.position + Vector2(3, 2), Gfx.BONE_LIGHT)


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
	if Salvage.baron_mult(v) > 1.0:
		stats.append(["BARON", "+%s DMG" % UiKit.pct(Salvage.baron_mult(v) - 1.0)])
	for i in stats.size():
		var sx: float = x0 + (i % 2) * floorf(w / 2.0)
		var sy: float = y + (i / 2) * 18.0
		UiFont.draw_small(self, stats[i][0], Vector2(sx, sy), Gfx.UI_DIM)
		UiFont.draw_big(self, stats[i][1], Vector2(sx, sy + 7), Gfx.UI_TEXT, Gfx.OUTLINE)
	y += ceilf(stats.size() / 2.0) * 18.0 + 4.0
	if v.loan_debt > 0:  # loan shark: what is still owed
		var dt := "DEBT %d  (%d LEFT)" % [v.loan_debt, maxi(v.loan_left, 1)]
		draw_rect(Rect2(x0 - 1, y - 2, w + 2, 10), Color(0.35, 0.08, 0.06, 0.7))
		UiFont.draw(self, dt, Vector2(x0 + 2, y), Gfx.UI_BAD, Gfx.UI_SHADOW)
		y += 11.0
	# guns, then the other parts
	var press: bool = float(v.tech_fx.get("scrap_press", 0.0)) > 0.0
	UiKit.section(self, "GUNS", Vector2(x0, y), w, "%d/%d SLOTS" % [Cards.weapon_cards_owned(v), v.weapon_slots])
	y += 10.0
	var has_ammo: bool = not Ammo.unlocked(v).is_empty()
	for id: String in v.cards:
		if Cards.is_weapon(id):
			_part_row(id, int(v.cards[id]), x0, xr, y, press)
			y += 10.0
			if has_ammo and v.ammo.has(id):
				_ammo_row(v, id, x0 + 10.0, xr, y)
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
			_part_row(id, int(v.cards[id]), x0, xr, y, press)
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


## Ammo of one gun (tech tree v2.3 section 3): "LOADED: FIRE" (two types with mixed belts) and a chip per
## other unlocked type; a click loads it (set_ammo, the old one stays as the second type on mixed belts).
func _ammo_row(v: SimVehicle, kind: String, x0: float, xr: float, y: float) -> void:
	var loaded: Array = v.ammo.get(kind, [])
	var names: PackedStringArray = []
	for a: String in loaded:
		names.append(str((TechGuide.AMMO_SHORT if loaded.size() > 1 else TechGuide.AMMO_NAMES).get(a, a)))
	var x: float = UiFont.draw_small(self, "LOADED: ", Vector2(x0, y), Gfx.UI_DIM)
	UiFont.draw_small(self, " + ".join(names) if not names.is_empty() else "NOTHING", Vector2(x, y), Gfx.FIRE[4])
	var cx: float = xr
	var un: Array[String] = Ammo.unlocked(v)
	for i in range(un.size() - 1, -1, -1):
		var a2: String = un[i]
		if loaded.has(a2):
			continue
		var label: String = str(TechGuide.AMMO_SHORT.get(a2, a2))
		var cw: float = UiFont.width_small(label) + 6.0
		var cr := Rect2(cx - cw, y - 2.0, cw, 9.0)
		var hov: bool = _is_hover("ammo", [kind, a2])
		draw_rect(cr, Gfx.OUTLINE)
		draw_rect(cr.grow(-1.0), Color(0.24, 0.15, 0.08) if hov else Color(0.13, 0.09, 0.07))
		UiKit.outline_rect(self, cr.grow(-1.0), Gfx.FIRE[3] if hov else UiKit.PANEL_EDGE)
		UiFont.draw_small(self, label, cr.position + Vector2(3, 2), Gfx.FIRE[5] if hov else Gfx.UI_TEXT)
		_hits.append([cr, "ammo", [kind, a2]])
		cx = cr.position.x - 2.0


func _part_row(id: String, lvl: int, x0: float, xr: float, y: float, scrappable: bool = false) -> void:
	if Cards.is_evolution(id):  # an evolution: gold, no levels, never scrapped
		draw_rect(Rect2(x0, y - 1, 7, 7), Gfx.OUTLINE)
		draw_rect(Rect2(x0 + 1, y, 5, 5), Gfx.BRASS[3])
		draw_rect(Rect2(x0 + 2, y + 1, 1, 1), Gfx.FIRE[6])
		UiFont.draw(self, UiKit.card_name(id), Vector2(x0 + 10, y), Gfx.FIRE[5], Gfx.UI_SHADOW)
		UiFont.draw_small(self, "EVOLVED", Vector2(xr - UiFont.width_small("EVOLVED"), y), Gfx.BRASS[3], Gfx.UI_SHADOW)
		return
	draw_rect(Rect2(x0, y - 1, 7, 7), Gfx.OUTLINE)
	draw_rect(Rect2(x0 + 1, y, 5, 5), UiKit.card_color(id))
	UiFont.draw(self, UiKit.card_name(id), Vector2(x0 + 10, y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiKit.pips(self, Vector2(xr - 16, y), lvl, Cards.MAX_LEVEL, Gfx.FIRE[4])
	if scrappable:  # scrap press: sell one level
		var label := "+%d" % (lvl * Salvage.PRESS_PER_LEVEL)
		var br := Rect2(xr - 20.0 - UiFont.width(label) - 6.0, y - 2.0, UiFont.width(label) + 6.0, 9.0)
		var hov: bool = _is_hover("scrap", id)
		draw_rect(br, Gfx.OUTLINE)
		draw_rect(br.grow(-1.0), Color(0.22, 0.14, 0.08) if hov else Color(0.14, 0.1, 0.08))
		UiFont.draw(self, label, br.position + Vector2(3, 1), Gfx.FIRE[5] if hov else Gfx.FIRE[3])
		_hits.append([br, "scrap", id])


# ---------------------------------------------------------------- abilities and compact tech (centre top)

## Ability slots next to YOUR RIG (tech tree v2.3 section 3): two slots cast with F / G; a click on a
## slot swaps in the next unlocked ability (set_ability). Only shown once an ability is unlocked.
func _draw_abilities(v: SimVehicle) -> void:
	var un: Array[String] = Abilities.unlocked(v)
	if un.is_empty():
		return
	var spare: Array[String] = []
	for a in un:
		if not v.abilities.has(a):
			spare.append(a)
	var r := Rect2(LEFT_X + COL_W + 6.0, BODY_Y, 100.0, 59.0 + (8.0 if not spare.is_empty() else 0.0))
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var w: float = r.size.x - 12.0
	var y: float = r.position.y + 5.0
	UiKit.section(self, "ABILITIES", Vector2(x0, y), w, "%d SLOTS" % Abilities.SLOTS)
	y += 10.0
	var hov_slot: int = -1
	for s in Abilities.SLOTS:
		var cur: String = v.abilities[s] if s < v.abilities.size() else ""
		var nxt: String = cur
		if not un.is_empty():
			var i: int = un.find(cur)
			nxt = un[(i + 1) % un.size()]
		var sr := Rect2(x0 - 1, y - 2, w + 2, 12)
		var hov: bool = _is_hover("ability", [s, nxt])
		if hov:
			hov_slot = s
		draw_rect(sr, Gfx.OUTLINE)
		draw_rect(sr.grow(-1.0), Color(0.2, 0.14, 0.1) if hov else Color(0.12, 0.09, 0.08))
		UiKit.outline_rect(self, sr.grow(-1.0), Gfx.FIRE[3] if hov else UiKit.PANEL_EDGE)
		var kr := Rect2(sr.position.x + 2, sr.position.y + 2, 8, 8)
		draw_rect(kr, Gfx.STEEL[3])
		UiFont.draw_small(self, "F" if s == 0 else "G", kr.position + Vector2(2, 1), Gfx.INK)
		UiFont.draw(self, str(TechGuide.ABILITY_NAMES.get(cur, "- EMPTY")), Vector2(kr.end.x + 4, y), Gfx.UI_TEXT if cur != "" else Gfx.STEEL[3], Gfx.UI_SHADOW)
		if un.size() > 1 or cur == "":
			var sw: String = "SWAP" if cur != "" else "FIT"
			UiFont.draw_small(self, sw, Vector2(sr.end.x - 4 - UiFont.width_small(sw), y), Gfx.FIRE[5] if hov else Gfx.UI_DIM)
			if nxt != cur or cur == "":
				_hits.append([sr, "ability", [s, nxt]])
		y += 13.0
	if not spare.is_empty():
		var names: PackedStringArray = []
		for a in spare:
			names.append(str(TechGuide.ABILITY_NAMES.get(a, a)))
		UiFont.draw_small(self, "SPARE: " + ", ".join(names), Vector2(x0, y), Gfx.UI_DIM)
		y += 8.0
	var tip: String = "CASTS ITSELF, OR BY F / G"
	if hov_slot >= 0 and v.abilities[hov_slot] != "":
		tip = str(TechGuide.ABILITY_AUTO.get(v.abilities[hov_slot], tip))
	for ln in UiFont.wrap_small(tip, int(w)).slice(0, 2):
		UiFont.draw_small(self, ln, Vector2(x0, y), Gfx.BRASS[3])
		y += 7.0


## Compact tech column (design doc 5b): stage pips per branch, the build plan's next node as a buy
## button, and a FUSION READY tag. Clicking a branch row opens the TECH view.
func _draw_tech_compact(v: SimVehicle) -> void:
	var tpl: Dictionary = TechGuide.template_for(world, v)
	var nxt: String = TechGuide.next_on_path(v, tpl)
	var ready_f: Array[String] = TechTreeView.fusions_ready(v)
	var h: float = 15.0 + 5.0 * 9.0 + 32.0 + (13.0 if not ready_f.is_empty() else 0.0)
	var r := Rect2(RIGHT_X - 6.0 - 102.0, BODY_Y, 102.0, h)
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var w: float = r.size.x - 12.0
	var y: float = r.position.y + 5.0
	UiKit.section(self, "TECH", Vector2(x0, y), w, "%d/%d  T" % [v.tech.size(), Tech.count()])
	y += 10.0
	var nb: String = str(Tech.def(nxt).get("branch", "")) if nxt != "" else ""
	for b in Tech.BRANCHES:
		var rr := Rect2(x0 - 2, y - 2, w + 4, 9)
		var hov: bool = _is_hover("tab", "tech:" + b)
		if hov:
			draw_rect(rr, UiKit.HOVER_WASH)
		_hits.append([rr, "tab", "tech:" + b])
		var plan: bool = (tpl["branches"] as Array).has(b)
		UiFont.draw_small(self, b.left(4).to_upper(), Vector2(x0, y), Gfx.FIRE[4] if plan else Gfx.UI_TEXT)
		UiKit.pips(self, Vector2(x0 + 22, y), Tech.branch_tier(v, b), Tech.MAX_TIER, Gfx.BRASS[3])
		var tag: String = ""
		var tcol: Color = Gfx.UI_DIM
		var idle: bool = false
		var buy_n: int = 0
		for id in Tech.ids(b):
			var st: TechTreeView.State = TechTreeView.state(v, id)
			idle = idle or st == TechTreeView.State.INACTIVE
			buy_n += 1 if st == TechTreeView.State.BUYABLE else 0
		if b == nb:
			tag = "NEXT"
			tcol = Gfx.FIRE[4]
		elif idle:
			tag = "IDLE"
			tcol = Gfx.UI_BAD
		elif buy_n > 0:
			tag = "+%d" % buy_n
			tcol = Gfx.HAZARD
		UiFont.draw_small(self, tag, Vector2(x0 + w - UiFont.width_small(tag), y), tcol)
		y += 9.0
	y += 2.0
	UiFont.draw_small(self, ("PLAN: " if TechGuide.is_picked(world) else "TRY: ") + str(tpl["name"]), Vector2(x0, y), Gfx.UI_DIM)
	y += 9.0
	var br := Rect2(x0 - 1, y - 1, w + 2, 18)
	if nxt == "":
		UiFont.draw_small(self, "PLAN COMPLETE", Vector2(x0, y + 4), Gfx.BRASS[3])
	else:
		var st2: TechTreeView.State = TechTreeView.state(v, nxt)
		var can: bool = st2 == TechTreeView.State.BUYABLE
		var hov2: bool = _is_hover("buy_next", nxt)
		UiKit.steel(self, br, Color.WHITE if can else Color(0.7, 0.66, 0.66))
		UiKit.outline_rect(self, br, Gfx.HAZARD if can and (hov2 or fmod(_blink, 1.2) < 0.9) else Gfx.OUTLINE)
		UiFont.draw_small(self, "NEXT", Vector2(x0 + 2, y + 2), Gfx.FIRE[4], Gfx.OUTLINE)
		var nm: String = UiKit.tech_name(nxt)
		if UiFont.width(nm) > w - 34.0:
			nm = str(Tech.def(nxt)["short"])
		UiFont.draw(self, nm, Vector2(x0 + 2, y + 9), Gfx.FIRE[5] if hov2 else Gfx.UI_TEXT, Gfx.OUTLINE)
		var cost := str(Tech.price(v, nxt))
		var cx: float = br.end.x - 4.0 - UiFont.width(cost)
		UiFont.draw(self, cost, Vector2(cx, y + 9), Gfx.UI_TEXT if can else Gfx.UI_BAD, Gfx.OUTLINE)
		_scrap_pip(Vector2(cx - 9, y + 9))
		_hits.append([br, "buy_next", nxt])
	y += 21.0
	if not ready_f.is_empty():
		var fr := Rect2(x0 - 1, y, w + 2, 10)
		var fh: bool = _is_hover("tab", "tech:fusion")
		UiKit.tape(self, fr, Color("#f0c070") if fh or fmod(_blink, 1.4) < 1.0 else Color("#d8b070"))
		var ft: String = ("FUSION READY: " + str(Tech.def(ready_f[0])["short"])) if ready_f.size() == 1 else "%d FUSIONS READY" % ready_f.size()
		UiFont.draw_small(self, ft if UiFont.width_small(ft) <= w - 4 else "FUSION READY", fr.position + Vector2(4, 2), Gfx.INK)
		_hits.append([fr, "tab", "tech:fusion"])


# ---------------------------------------------------------------- draft cards (centre)

func _draw_cards(v: SimVehicle, vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var showing: Array[String] = v.offers
	var picked_view: bool = false
	if v.picked:
		picked_view = true
		showing = _offers_cache if _offers_round == world.round else ([] as Array[String])
	var fitted_at: int = _picked_index
	if picked_view and showing.is_empty() and view != null and view.juice.evo_age(world.tick) >= 0:
		# picked without this UI seeing the offers (a replay, a screenshot): the evolution alone, fitted
		showing = [RigArt.evolution_card(view.juice.evo_kind)] as Array[String]
		fitted_at = 0
	# three cards side by side; a lucky strike's fourth one makes them overlap
	var step: float = CARD_SIZE.x + CARD_GAP
	if showing.size() > 3:
		step = floorf((324.0 - CARD_SIZE.x) / float(showing.size() - 1))
	var total: float = step * float(maxi(showing.size(), 3) - 1) + CARD_SIZE.x
	var x0: float = cx - floorf(total / 2.0)
	if showing.size() == 1:
		x0 = cx - floorf(CARD_SIZE.x / 2.0)
	var can_reserve: bool = float(v.tech_fx.get("reserve_card", 0.0)) > 0.0
	var title: String = "PICK ONE PART - FREE" if not v.picked else "PART FITTED"
	UiKit.tape_label(self, title, cx, CARD_Y - 15.0, Color("#e8dcc4"))
	if showing.is_empty():
		var msg := "THE CREW IS BOLTING IT ON" if v.picked else "NO PARTS LEFT IN THE PILE"
		UiKit.center_text(self, msg, cx, CARD_Y + 50.0, Gfx.UI_TEXT, Gfx.OUTLINE)
	for i in showing.size():
		var id: String = showing[i]
		var pos := Vector2(x0 + float(i) * step, CARD_Y)
		var hov: bool = not picked_view and _is_hover("pick", i)
		var state: int = 0  # 0 offer, 1 fitted, 2 scrapped
		if picked_view:
			state = 1 if i == fitted_at else 2
		_draw_card(id, i, pos + (Vector2(0, -3) if hov else Vector2.ZERO), int(v.cards.get(id, 0)) - (1 if state == 1 else 0), hov, state)
		if not picked_view:
			_hits.append([Rect2(pos, CARD_SIZE), "pick", i])
			if can_reserve:
				var kept: bool = v.reserved_card == id
				var rb := Rect2(pos.x + 6.0, pos.y + 2.0, 42.0, 10.0)
				var rh: bool = _is_hover("reserve", i)
				draw_rect(rb, Gfx.OUTLINE)
				draw_rect(rb.grow(-1.0), Color(0.4, 0.28, 0.1) if kept else (Color(0.26, 0.2, 0.14) if rh else Color(0.14, 0.1, 0.08)))
				UiFont.draw(self, "KEPT" if kept else "RESERVE", rb.position + Vector2(3, 2), Gfx.FIRE[5] if kept or rh else Gfx.UI_TEXT)
				_hits.append([rb, "reserve", i])
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


## Bottom centre: the contract offers with ACCEPT, or the accepted contract with its progress.
func _draw_contracts(v: SimVehicle, vs: Vector2) -> void:
	if v.contract_offers.is_empty() and v.contract_kind < 0:
		return
	var cx: float = floorf(vs.x / 2.0)
	var r := Rect2(cx - 158.0, 309.0, 316.0, 32.0)
	UiKit.panel(self, r)
	_hits.append([r, "none", null])
	var x0: float = r.position.x + 6.0
	var w: float = r.size.x - 12.0
	if v.contract_kind >= 0:
		UiKit.section(self, "CONTRACT ACCEPTED", Vector2(x0, r.position.y + 4.0), w, UiKit.contract_reward_text(v, v.contract_reward), Gfx.FIRE[4])
		UiFont.draw(self, UiKit.contract_title(v.contract_kind, v.contract_need), Vector2(x0, r.position.y + 16.0), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiFont.draw(self, "FINISH IT IN THE NEXT ROUND", Vector2(x0, r.position.y + 24.0), Gfx.UI_DIM, Gfx.UI_SHADOW)
		return
	var n: int = v.contract_offers.size()
	UiKit.section(self, "CONTRACT OFFER" if n == 1 else "CONTRACTS - PICK ONE", Vector2(x0, r.position.y + 4.0), w, "PAID AT THE END OF THE ROUND", Gfx.UI_DIM)
	var col_w: float = floorf(w / float(n))
	for i in n:
		var o: Vector3i = v.contract_offers[i]
		var cx0: float = x0 + float(i) * col_w
		UiFont.draw(self, UiKit.contract_title(o.x, o.y), Vector2(cx0, r.position.y + 15.0), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiFont.draw(self, UiKit.contract_reward_text(v, o.z), Vector2(cx0, r.position.y + 23.0), Gfx.FIRE[4], Gfx.UI_SHADOW)
		var br := Rect2(cx0 + col_w - 50.0, r.position.y + 15.0, 44.0, 14.0)
		var hov: bool = _is_hover("accept", i)
		UiKit.button(self, br, "ACCEPT", hov)
		_hits.append([br, "accept", i])


## One draft card. `level` = owned level before the pick (0 = new).
func _draw_card(id: String, index: int, pos: Vector2, level: int, hov: bool, state: int) -> void:
	if Cards.is_evolution(id):
		_draw_evo_card(id, index, pos, hov, state)
		return
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


## Short labels of the evolution partners under their icon on the card.
const EVO_PARTNER_SHORT := {"v8_engine": "V8", "spiked_plating": "SPIKES", "caterpillar_tracks": "TRACKS", "nitro": "NITRO"}


## An evolution offer (legendary): gunmetal in a riveted brass frame, the recipe as icons (the maxed weapon +
## the partner part = the evolved gun itself) and what it does. Fitted, it is stamped EVOLVED.
func _draw_evo_card(id: String, index: int, pos: Vector2, hov: bool, state: int) -> void:
	var mod: Color = Color.WHITE if state != 2 else Color(0.5, 0.45, 0.45)
	var d: Dictionary = Cards.def(id)
	var kind: String = str(d.get("weapon", "mg"))
	var partner: String = str(d.get("partner", ""))
	var sh := Rect2(pos + Vector2(3, 6 if hov else 3), CARD_SIZE - Vector2(4, 4))
	draw_rect(sh, Color(0.08, 0.05, 0.06, 0.45))
	if state == 0:  # a warm glow round the legendary tag, breathing
		var pulse: float = 0.5 + 0.5 * sin(_blink * 4.0)
		var body := Rect2(pos + Vector2(1, 12), CARD_SIZE - Vector2(2, 14))
		for g in 3:
			draw_rect(body.grow(float(3 - g) * 2.0), Color(Gfx.FIRE[4], (0.06 + 0.06 * pulse) * float(g + 1) / 3.0))
	if hov:
		draw_rect(Rect2(pos.x + 8, pos.y + CARD_SIZE.y + 4, CARD_SIZE.x - 16, 2), Gfx.BRASS[3])
		draw_rect(Rect2(pos.x + 8, pos.y + CARD_SIZE.y + 6, CARD_SIZE.x - 16, 1), Gfx.OUTLINE)
	draw_texture(Gfx.TEX_CARD_EVO, pos, mod)
	var ink: Color = Gfx.INK * mod
	var light: Color = Gfx.BONE_LIGHT * mod
	var gold: Color = Gfx.FIRE[5] * mod
	# brass tape: EVOLUTION ... LEGENDARY
	var tr := Rect2(pos + Vector2(8, 14), Vector2(CARD_SIZE.x - 16, 9))
	UiKit.tape(self, tr, Gfx.BRASS[3] * mod)
	UiFont.draw_small(self, "EVOLUTION", tr.position + Vector2(4, 2), ink)
	var rar: String = str(d.get("rarity", "legendary")).to_upper()
	UiFont.draw_small(self, rar, Vector2(tr.end.x - 4 - UiFont.width_small(rar), tr.position.y + 2), ink)
	UiKit.center_big(self, UiKit.card_name(id), pos.x + CARD_SIZE.x / 2.0, pos.y + 27.0, gold, Gfx.OUTLINE)
	# the recipe: [weapon] + [partner] > the evolved gun
	var iy: float = pos.y + 43.0
	var boxes: Array = [[kind, Vector2(pos.x + 8, iy)], [UiKit.card_icon(partner), Vector2(pos.x + 32, iy)]]
	for b: Array in boxes:
		var br := Rect2(b[1], Vector2(18, 18))
		draw_rect(br, Color(0.08, 0.06, 0.06) * mod)
		UiKit.outline_rect(self, br, Gfx.BRASS[2] * mod)
		UiKit.icon(self, str(b[0]), br.position + Vector2(1, 1), mod)
	UiFont.draw_big(self, "+", Vector2(pos.x + 27, iy + 5), gold)
	UiKit.arrow_glyph(self, Vector2(pos.x + 52, iy + 6), gold)
	var res := Rect2(pos.x + 59, pos.y + 36, 34, 34)
	draw_rect(res, Color(0.05, 0.04, 0.04) * mod)
	UiKit.outline_rect(self, res, Gfx.BRASS[3] * mod)
	UiKit.outline_rect(self, res.grow(-1.0), Gfx.BRASS[0] * mod)
	var fs: float = float(RigArt.GUN_EVO_FRAME)
	var ki: int = Cards.weapon_kind_index(kind)
	var src := Rect2(4.0 * fs + 11.0, float(ki * 2) * fs + 11.0, 34.0, 34.0)  # aimed up-right, cropped to the box
	draw_texture_rect_region(RigArt.GUN_EVO_TEX, Rect2(res.position, res.size), src, mod)
	UiKit.center_small(self, UiKit.weapon_short(ki) + " L3", pos.x + 17, iy + 21, light)
	UiKit.center_small(self, str(EVO_PARTNER_SHORT.get(partner, "PART")), pos.x + 41, iy + 21, light)
	# what it does (the text after the recipe)
	var text: String = str(d.get("text", ""))
	var at: int = text.find(": ")
	var y: float = pos.y + 76.0
	for sub in UiFont.wrap_small(text.substr(at + 2) if at >= 0 else text, int(CARD_SIZE.x) - 18):
		if y > pos.y + 101.0:
			break
		UiFont.draw_small(self, sub, Vector2(pos.x + 9, y), light)
		y += 7.0
	if state == 0:
		var kr := Rect2(pos.x + 8, pos.y + CARD_SIZE.y - 15, 9, 9)
		draw_rect(kr, Gfx.BRASS[3])
		UiFont.draw(self, "%d" % (index + 1), kr.position + Vector2(3, 2), Gfx.INK)
		UiFont.draw(self, "PICK" if not hov else "EVOLVE IT", Vector2(kr.end.x + 3, kr.position.y + 2), light)
		var ev := "NO SLOT"
		UiFont.draw_small(self, ev, Vector2(pos.x + CARD_SIZE.x - 16 - UiFont.width_small(ev), kr.position.y + 2), Gfx.BRASS[3])
	elif state == 1:
		var st := Rect2(pos.x + 7, pos.y + 45, CARD_SIZE.x - 14, 26)
		draw_rect(st, Color(0.13, 0.1, 0.09, 0.94))
		UiKit.outline_rect(self, st, Gfx.BRASS[3])
		UiKit.outline_rect(self, st.grow(-2.0), Gfx.FIRE[4])
		UiKit.center_big(self, "EVOLVED", st.get_center().x, st.position.y + 6, Gfx.FIRE[5], Gfx.OUTLINE, 2)


## Tiny 5x5 scrap marker (a nut) for prices.
func _scrap_pip(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(1, 0), Vector2(5, 5)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(0, 1), Vector2(7, 3)), Gfx.OUTLINE)
	draw_rect(Rect2(p + Vector2(1, 1), Vector2(5, 3)), Gfx.STEEL[4])
	draw_rect(Rect2(p + Vector2(3, 2), Vector2(1, 1)), Gfx.OUTLINE)


# ---------------------------------------------------------------- convoy (right, bottom)

## The hive signature (this match's species, the next boss) stacked above the convoy panel.
func _draw_hive() -> void:
	var bottom: float = BODY_BOTTOM - 4.0
	var n: int = world.vehicles.size()
	if n >= 2:
		bottom -= 18.0 + n * 10.0 + 4.0
	var h: float = HivePanel.height(world, COL_W)
	var r := Rect2(RIGHT_X, bottom - h, COL_W, h)
	HivePanel.draw(self, world, r)
	_hits.append([r, "none", null])


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
		ex = _kv("RIGS", str(int(rs.get("kills_players", 0))), Vector2(ex, y), Gfx.UI_TEXT)
	var zone_pts: int = int(rs.get("zone_points", 0))
	if zone_pts > 0:  # seconds held alone in an own control zone = scrap (already in SCRAP below)
		_kv("ZONES", "+%d" % zone_pts, Vector2(ex, y), Gfx.FIRE[4])
	y += 9.0
	ex = _kv("SCRAP", "+%d" % int(rs.get("scrap_earned", 0)), Vector2(x0, y), Gfx.FIRE[4])
	_kv("INTEREST", "+%d" % int(rs.get("interest", 0)), Vector2(ex, y), Gfx.FIRE[4])
	y += 9.0
	var fx: float = UiFont.draw(self, "FUEL", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var parts: Array = []  # [text, colour]
	if int(rs.get("fuel_lost", 0)) > 0:
		parts.append(["-%d LOST" % int(rs["fuel_lost"]), Gfx.UI_BAD])
	var king: int = view.zone_bonus_for(v.id, int(rs.get("round", world.round))) if view != null else 0
	var stolen: int = int(rs.get("fuel_gained", 0)) - king
	if stolen > 0:
		parts.append(["+%d STOLEN" % stolen, Gfx.FIRE[4]])
	if king > 0:
		parts.append(["+%d ZONE KING" % king, Gfx.FIRE[5]])
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
