class_name DoctrineEditor
extends Control
## Rule editor (design doc section 6, layer 2): an amber CRT where the player programs IF-THEN
## rules for the rig and for every weapon on its own. In combat P opens it as a full-screen overlay
## (P / Esc / CLOSE close it; the game keeps running behind it). In the workshop it is the RULES
## view: WorkshopUi embeds it into its body (open_embedded) under the top bar, owns the clicks and
## forwards them here, and P / Esc switch the workshop view instead.
##
## Immediate-mode like WorkshopUi: _draw() records hit rects, clicks go through activate(). The
## open tab's rules are a local working copy (so quick clicks never fight snapshot lag); every edit
## sends the whole list as one set_rules command. Base settings are read from the synced vehicle.
## Only reads sim state; everything it changes goes through `send_command`.

const PANEL := Rect2(18, 10, 604, 340)
const ROW_H := 27.0
const MENU_W := 118.0

const COND_LABELS := {
	"hp": "OWN HP", "swarm": "ALIENS NEAR", "rivals": "RIVALS NEAR", "t_dist": "TGT DISTANCE", "t_hp": "TGT HP",
	"t_player": "TGT IS RIVAL", "t_boulder": "TGT IS BOULDER", "t_spitter": "TGT IS SPITTER", "pvp": "PVP ON",
	"has_target": "HAS TARGET",
}
const COND_HELP := {
	"hp": "YOUR RIG'S HP IN PERCENT OF ITS MAXIMUM.",
	"swarm": "ALIENS WITHIN 220 PX OF THE RIG.",
	"rivals": "RIVAL RIGS WITHIN 380 PX (COUNTS ONLY WHILE PVP IS ON).",
	"t_dist": "DISTANCE TO THE CURRENT TARGET IN PX. NO TARGET: NEVER TRUE.",
	"t_hp": "THE TARGET'S HP IN PERCENT. NO TARGET: NEVER TRUE.",
	"t_player": "THE TARGET IS A RIVAL RIG.",
	"t_boulder": "THE TARGET IS A BOULDER.",
	"t_spitter": "THE TARGET IS A SPITTER.",
	"pvp": "PLAYERS CAN HURT EACH OTHER (FROM ROUND 4).",
	"has_target": "THERE IS SOMETHING TO SHOOT AT.",
}
const ACTION_LABELS := {
	"drive:circle": "CIRCLE", "drive:kite": "KITE", "drive:charge": "CHARGE", "drive:flee": "FLEE",
	"drive:hold": "HOLD POSITION",
	"target:nearest": "TGT NEAREST", "target:strongest": "TGT STRONGEST", "target:weakest": "TGT WEAKEST",
	"target:players_first": "TGT RIVALS", "target:boulders": "TGT BOULDERS", "target:spitters": "TGT SPITTERS",
	"target:follow": "FOLLOW RIG", "fire:hold": "HOLD FIRE", "fire:free": "FIRE AT WILL",
	"ammo:fire": "LOAD FIRE", "ammo:shrapnel": "LOAD SHRAPNEL", "ammo:ap": "LOAD AP",
}
const ACTION_HELP := {
	"drive:circle": "ORBIT THE TARGET WITH GUNS OUT.",
	"drive:kite": "KEEP AT WEAPON RANGE, BACK OFF WHEN THEY CLOSE IN.",
	"drive:charge": "RAM STRAIGHT IN (RAM DAMAGE).",
	"drive:flee": "TURN AWAY FROM THE TARGET AND RUN.",
	"drive:hold": "STOP AND FACE THE TARGET.",
	"target:nearest": "WHATEVER IS CLOSEST.",
	"target:strongest": "THE ALIEN WITH THE MOST HP IN RANGE.",
	"target:weakest": "THE ALIEN WITH THE LEAST HP IN RANGE: FINISH THEM OFF.",
	"target:players_first": "RIVAL RIGS IN RANGE FIRST (BOUNTY LEADER FIRST), THEN ALIENS.",
	"target:boulders": "THE NEAREST BOULDER, ELSE THE NEAREST ALIEN.",
	"target:spitters": "THE NEAREST SPITTER, ELSE THE NEAREST ALIEN.",
	"target:follow": "SHOOT WHAT THE RIG IS AIMING AT.",
	"fire:hold": "THIS GUN DOES NOT SHOOT.",
	"fire:free": "THIS GUN SHOOTS (OVERRIDES A LOWER HOLD FIRE).",
	"ammo:fire": "LOAD INCENDIARY ROUNDS: HITS BURN FOR 2 S.",
	"ammo:shrapnel": "LOAD SHRAPNEL: KILLS BURST INTO 3 SHARDS.",
	"ammo:ap": "LOAD ARMOUR PIERCING: +1 PIERCE, MORE DAMAGE VS BOULDERS AND RIVALS.",
}
## Quick-add rules per scope: [label, text form].
const TEMPLATES_RIG: Array = [
	["RETREAT BELOW 30% HP", "hp<30|drive:flee"],
	["KITE WHEN SWARMED", "swarm>20|drive:kite"],
	["HUNT WOUNDED RIVALS", "t_player=1&t_hp<40|drive:charge"],
	["RIVALS FIRST IN PVP", "pvp=1&rivals>0|target:players_first"],
]
const TEMPLATES_WEAPON: Array = [
	["SAVE AMMO ON BOULDERS", "t_boulder=1|fire:hold"],
	["FINISH WEAK ONES", "|target:weakest"],
	["SNIPE SPITTERS", "|target:spitters"],
	["ONLY AT CLOSE RANGE", "t_dist>110|fire:hold"],
]

var world: SimWorld = null
var local_peer: int = 1
## Callable(cmd: Dictionary): where commands go (NetSession.send_command or the world directly).
var send_command: Callable = Callable()
var pointer_override: Vector2 = Vector2(-1, -1)
var use_real_pointer: bool = true
var is_open: bool = false
var scope: String = Doctrine.SCOPE_RIG

var _work: Array = []  # working copy of the open scope's rules
var _hits: Array = []  # [Rect2, action, arg]
var _hover: Array = []
var _clicked: Rect2 = Rect2()  # rect of the hit being activated (dropdowns open under it)
var _menu: Dictionary = {}  # open dropdown: {"rect", "kind", "ri", "ci", "options": [[value, label, help]]}
var _toast: String = ""
var _toast_left: float = 0.0
var _blink: float = 0.0
var _embed: Rect2 = Rect2()  ## the workshop body while embedded (zero size = overlay)
## The workshop whose RULES view this editor is (set by WorldView).
var workshop: WorkshopUi = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func _local() -> SimVehicle:
	return world.get_vehicle_for_peer(local_peer) if world != null else null


## Opens the editor on `p_scope` ("rig" or an owned weapon kind).
func open(p_scope: String = Doctrine.SCOPE_RIG) -> void:
	if _local() == null:
		return
	is_open = true
	_select(p_scope)


## Opens (or moves) the editor into `r`, the workshop body; the workshop forwards the clicks.
func open_embedded(r: Rect2) -> void:
	if _local() == null:
		return
	if not is_open:
		open(Doctrine.SCOPE_RIG)
	_embed = r
	_menu = {}
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func embedded() -> bool:
	return _embed.size.x > 0.0


func close() -> void:
	is_open = false
	_menu = {}
	_embed = Rect2()
	mouse_filter = Control.MOUSE_FILTER_STOP


## The CRT housing: the workshop body when embedded, else the overlay panel.
func _panel() -> Rect2:
	return _embed if embedded() else PANEL


## Top of the first rule row (the embedded view has no title line).
func _rows_y() -> float:
	return _panel().position.y + (92.0 if embedded() else 102.0)


func toggle() -> void:
	if is_open:
		close()
	else:
		open(scope)


func _select(p_scope: String) -> void:
	var v: SimVehicle = _local()
	if p_scope != Doctrine.SCOPE_RIG and not _owns_weapon(v, p_scope):
		p_scope = Doctrine.SCOPE_RIG
	scope = p_scope
	_menu = {}
	var src: Array = v.rules if scope == Doctrine.SCOPE_RIG else Doctrine.weapon_doc(v, scope)["rules"]
	_work = src.duplicate(true)


func _owns_weapon(v: SimVehicle, kind: String) -> bool:
	for w in v.weapons:
		if str(w["kind"]) == kind:
			return true
	return false


func _process(delta: float) -> void:
	if is_open and (world == null or _local() == null or world.phase == SimWorld.PHASE_GAME_OVER):
		close()
	visible = is_open
	_toast_left = maxf(_toast_left - delta, 0.0)
	_blink += delta
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
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var layer: CanvasLayer = get_parent() as CanvasLayer
	if layer != null and not layer.visible:
		return  # behind the menus (attract mode, main menu)
	var key: Key = (event as InputEventKey).keycode
	var camp: bool = workshop != null and workshop.visible
	if key == KEY_P and world != null and _local() != null and world.phase != SimWorld.PHASE_GAME_OVER:
		if camp:
			workshop.activate("tab", "parts" if workshop.tab() == "rules" else "rules")
		else:
			toggle()
		get_viewport().set_input_as_handled()
	elif is_open and key == KEY_ESCAPE:
		if not _menu.is_empty():
			_menu = {}
		elif camp and embedded():
			workshop.activate("tab", "parts")
		else:
			close()
		get_viewport().set_input_as_handled()


## Clicks at `p` (viewport px) like the mouse does; used by screenshot scenarios too.
func click_at(p: Vector2) -> bool:
	var h: Array = _hit_at(p)
	if h.is_empty():
		_menu = {}
		return false
	_clicked = h[0]
	activate(h[1], h[2])
	return true


func activate(action: String, arg: Variant) -> void:
	var v: SimVehicle = _local()
	if v == null:
		return
	if action != "menu_pick":
		_menu = {}
	match action:
		"close":
			close()
		"tab":
			_select(str(arg))
		"base_drive":
			_send({"type": "set_drive", "value": str(arg)})
		"base_target":
			_send({"type": "set_target", "value": str(arg)})
		"weapon_target":
			_send({"type": "set_weapon_target", "scope": scope, "value": str(arg)})
		"cond":
			_open_menu("cond", arg[0], arg[1])
		"add_cond":
			_open_menu("add_cond", int(arg), -1)
		"action":
			_open_menu("action", int(arg), -1)
		"op":
			var c: Array = _work[arg[0]]["if"][arg[1]]
			if bool(Doctrine.CONDS[c[0]]["flag"]):
				c[2] = 1 - int(c[2])
			else:
				c[1] = ">" if c[1] == "<" else "<"
			_commit()
		"dec", "inc":
			var c2: Array = _work[arg[0]]["if"][arg[1]]
			var m: Dictionary = Doctrine.CONDS[c2[0]]
			var step: int = int(m["step"]) * (1 if action == "inc" else -1)
			c2[2] = clampi(int(c2[2]) + step, int(m["min"]), int(m["max"]))
			_commit()
		"up", "down":
			var i: int = int(arg)
			var j: int = i + (-1 if action == "up" else 1)
			if j >= 0 and j < _work.size():
				var tmp: Variant = _work[i]
				_work[i] = _work[j]
				_work[j] = tmp
				_commit()
		"delete":
			_work.remove_at(int(arg))
			_commit()
		"add_rule":
			_add_rule("hp<30|drive:flee" if scope == Doctrine.SCOPE_RIG else "t_boulder=1|fire:hold")
		"template":
			_add_rule(str(arg))
		"menu_pick":
			_pick(arg)


func _add_rule(text: String) -> void:
	var v: SimVehicle = _local()
	if _work.size() >= Doctrine.slots(v):
		_say("ALL %d SLOTS USED - ELECTRONICS TECH ADDS MORE" % Doctrine.slots(v))
		return
	var r: Variant = Doctrine.parse(text, scope)
	if r == null or (r as Array).is_empty():
		return
	_work.append((r as Array)[0])
	_commit()


func _open_menu(kind: String, ri: int, ci: int) -> void:
	var opts: Array = []
	if kind == "action":
		for a in Doctrine.actions_for(scope, _local()):
			opts.append([a, ACTION_LABELS[a], ACTION_HELP[a]])
	else:
		for id in Doctrine.COND_IDS:
			opts.append([id, COND_LABELS[id], COND_HELP[id]])
		if kind == "cond":
			opts.append(["", "REMOVE CONDITION", "DROP THIS CONDITION FROM THE RULE."])
	var anchor: Rect2 = _clicked
	var h: float = float(opts.size()) * 9.0 + 6.0
	var y: float = anchor.end.y + 2.0
	if y + h > _panel().end.y - 4.0:
		y = anchor.position.y - h - 2.0
	var x: float = minf(anchor.position.x, _panel().end.x - MENU_W - 6.0)
	_menu = {"rect": Rect2(x, y, MENU_W, h), "kind": kind, "ri": ri, "ci": ci, "options": opts}


func _pick(value: Variant) -> void:
	var kind: String = _menu.get("kind", "")
	var ri: int = int(_menu.get("ri", -1))
	var ci: int = int(_menu.get("ci", -1))
	_menu = {}
	if ri < 0 or ri >= _work.size():
		return
	var rule: Dictionary = _work[ri]
	var conds: Array = rule["if"]
	match kind:
		"action":
			rule["do"] = str(value)
		"cond":
			if str(value) == "":
				conds.remove_at(ci)
			elif str(value) != str(conds[ci][0]):
				conds[ci] = Doctrine.default_cond(str(value))
		"add_cond":
			if conds.size() < Doctrine.MAX_CONDS:
				conds.append(Doctrine.default_cond(str(value)))
	_commit()


func _commit() -> void:
	_send({"type": "set_rules", "scope": scope, "value": Doctrine.encode(_work)})


func _send(cmd: Dictionary) -> void:
	if send_command.is_valid():
		send_command.call(cmd)


func _say(text: String) -> void:
	_toast = text
	_toast_left = 1.8


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var v: SimVehicle = _local()
	if v == null:
		return
	_hover = _hit_at(_pointer())
	_hits.clear()
	var vs: Vector2 = get_viewport_rect().size
	var panel: Rect2 = _panel()
	if not embedded():
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.04, 0.02, 0.02, 0.6))
	UiKit.steel(self, panel)
	var scr := Rect2(panel.position + Vector2(6, 6), panel.size - Vector2(12, 20))
	draw_rect(scr, Gfx.CRT_BG)
	var x0: float = scr.position.x + 8.0
	var y: float = scr.position.y + 6.0
	if not embedded():
		var px: float = UiFont.draw_big(self, "DOCTRINE.SYS - RULE EDITOR", Vector2(x0, y - 1), Gfx.CRT_HI)
		if fmod(_blink, 1.0) < 0.5:
			draw_rect(Rect2(px + 2, y - 1, 4, 7), Gfx.CRT_TEXT)
		_chip("CLOSE  (P)", Vector2(scr.end.x - 8 - UiFont.width("CLOSE  (P)"), y), false, "close", null)
		y += 10.0
	UiFont.draw_small(self, "RULES RUN TOP TO BOTTOM: THE FIRST MATCHING RULE OF EACH KIND WINS. NOTHING MATCHES: BASE SETTING.", Vector2(x0, y), Gfx.CRT_DIM)
	y += 14.0
	_draw_tabs(v, Vector2(x0, y), scr)
	y += 16.0
	if scope == Doctrine.SCOPE_RIG:
		_draw_base_rig(v, Vector2(x0, y))
	else:
		_draw_base_weapon(v, Vector2(x0, y))
	_draw_rules(v, scr)
	_draw_footer(v, scr)
	# scanlines and glare over the whole tube
	for sy in range(int(scr.position.y) + 1, int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(scr.position.x + 2, scr.position.y + 1, scr.size.x - 4, 1), Color(1, 0.8, 0.5, 0.08))
	UiFont.draw_small(self, "COLONY NAV-COMP  -  DOCTRINE.SYS  -  BEHAVIOUR PROGRAMMING", Vector2(panel.position.x + 8, panel.end.y - 11), Gfx.STEEL[4], Gfx.STEEL[0])
	draw_rect(Rect2(panel.end.x - 12, panel.end.y - 10, 3, 3), Gfx.CRT_TEXT)
	if not _menu.is_empty():
		_draw_menu()


func _draw_tabs(v: SimVehicle, pos: Vector2, scr: Rect2) -> void:
	var x: float = pos.x
	var tabs: Array = [[Doctrine.SCOPE_RIG, "RIG (DRIVING)", v.rule_live]]
	for w in v.weapons:
		tabs.append([str(w["kind"]), UiKit.card_name(str(w["kind"])), int(w.get("live", 0))])
	for t: Array in tabs:
		var label: String = t[1]
		var on: bool = scope == t[0]
		var n: int = (v.rules if t[0] == Doctrine.SCOPE_RIG else Doctrine.weapon_doc(v, t[0])["rules"]).size()
		if n > 0:
			label += " (%d)" % n
		var r := Rect2(x - 3, pos.y - 3, UiFont.width(label) + 14, 11)
		draw_rect(r, Gfx.CRT_TEXT if on else (Gfx.CRT_DIM * Color(1, 1, 1, 0.35) if _is_hover("tab", t[0]) else Color(0, 0, 0, 0)))
		UiKit.outline_rect(self, r, Gfx.CRT_TEXT if on else Gfx.CRT_DIM)
		UiFont.draw(self, label, Vector2(x, pos.y), Gfx.CRT_BG if on else Gfx.CRT_TEXT)
		_lamp(Vector2(r.end.x - 7, pos.y + 1), int(t[2]) != 0, on)
		_hits.append([r, "tab", t[0]])
		x = r.end.x + 5.0
	draw_rect(Rect2(scr.position.x + 4, pos.y + 9, scr.size.x - 8, 1), Gfx.CRT_DIM)


func _draw_base_rig(v: SimVehicle, pos: Vector2) -> void:
	var y: float = pos.y
	UiFont.draw(self, "BASE DRIVE", Vector2(pos.x, y), Gfx.CRT_DIM)
	var x: float = pos.x + 62.0
	for d in Doctrine.BASE_DRIVES:
		x = _chip(ACTION_LABELS["drive:" + d], Vector2(x, y), str(v.doctrine["drive"]) == d, "base_drive", d) + 5.0
	y += 11.0
	UiFont.draw(self, "BASE TARGET", Vector2(pos.x, y), Gfx.CRT_DIM)
	x = pos.x + 62.0
	for t in Doctrine.RIG_TARGETS:
		x = _chip(ACTION_LABELS["target:" + t].trim_prefix("TGT "), Vector2(x, y), str(v.doctrine["target"]) == t, "base_target", t) + 5.0


func _draw_base_weapon(v: SimVehicle, pos: Vector2) -> void:
	var y: float = pos.y
	var wp: Dictionary = {}
	for w in v.weapons:
		if str(w["kind"]) == scope:
			wp = w
	var info := "RANGE %d  DAMAGE %s  SHOTS/S %s" % [roundi(float(wp.get("range", 0.0))), UiKit.num(float(wp.get("damage", 0.0)) * float(wp.get("pellets", 1))),
		UiKit.num(float(SimWorld.TICK_RATE) / maxf(float(wp.get("cooldown_ticks", 1)), 1.0))]
	UiFont.draw(self, info, Vector2(pos.x, y), Gfx.CRT_DIM)
	y += 11.0
	UiFont.draw(self, "BASE TARGET", Vector2(pos.x, y), Gfx.CRT_DIM)
	var x: float = pos.x + 62.0
	var cur: String = Doctrine.weapon_doc(v, scope)["target"]
	for t in Doctrine.WEAPON_TARGETS:
		x = _chip(ACTION_LABELS["target:" + t].trim_prefix("TGT "), Vector2(x, y), cur == t, "weapon_target", t) + 5.0


func _draw_rules(v: SimVehicle, scr: Rect2) -> void:
	var x0: float = scr.position.x + 8.0
	var slots: int = Doctrine.slots(v)
	var rows_y: float = _rows_y()
	var y: float = rows_y - 14.0
	UiFont.draw(self, "RULES  %d/%d SLOTS" % [mini(_work.size(), slots), slots], Vector2(x0, y), Gfx.CRT_HI)
	var note := "+1 SLOT PER ELECTRONICS TIER" if slots < Doctrine.MAX_SLOTS else "ALL SLOTS UNLOCKED"
	UiFont.draw(self, note, Vector2(scr.end.x - 8 - UiFont.width(note), y), Gfx.CRT_DIM)
	var live: int = v.rule_live
	if scope != Doctrine.SCOPE_RIG:
		live = 0
		for w in v.weapons:
			if str(w["kind"]) == scope:
				live = int(w.get("live", 0))
	var combat: bool = world.phase == SimWorld.PHASE_COMBAT
	for i in _work.size():
		var ry: float = rows_y + ROW_H * float(i)
		var row := Rect2(x0 - 4, ry - 5, scr.size.x - 8, ROW_H - 4)
		var locked: bool = i >= slots
		var lit: bool = combat and not locked and (live >> i) & 1 == 1
		if lit:
			draw_rect(row, Color(Gfx.CRT_TEXT, 0.14))
		UiKit.outline_rect(self, row, Gfx.CRT_DIM if not lit else Gfx.CRT_TEXT)
		_draw_rule(i, _work[i], Vector2(x0, ry + 1), row, locked, lit)
	var ay: float = rows_y + ROW_H * float(_work.size())
	if _work.size() < slots:
		_chip("+ ADD RULE", Vector2(x0, ay), false, "add_rule", null)
	elif _work.size() < Doctrine.MAX_SLOTS:
		UiFont.draw(self, "SLOTS FULL - BUILD ELECTRONICS TECH FOR MORE", Vector2(x0, ay), Gfx.CRT_DIM)
	if _work.is_empty():
		UiFont.draw(self, "NO RULES: THIS %s ALWAYS USES ITS BASE SETTING." % ("RIG" if scope == Doctrine.SCOPE_RIG else "GUN"), Vector2(x0 + 60, ay), Gfx.CRT_DIM)


func _draw_rule(i: int, rule: Dictionary, pos: Vector2, row: Rect2, locked: bool, lit: bool) -> void:
	var col: Color = Gfx.CRT_DIM if locked else Gfx.CRT_TEXT
	var x: float = UiFont.draw(self, "%d" % (i + 1), pos, Gfx.CRT_HI if lit else col) + 3.0
	_lamp(Vector2(x, pos.y + 1), lit, false)
	x += 9.0
	if locked:
		UiFont.draw(self, "LOCKED: THIS RIG HAS ONLY %d SLOTS - BUILD ELECTRONICS TECH TO RUN IT" % Doctrine.slots(_local()), Vector2(x, pos.y), Gfx.CRT_DIM)
		_chip("X", Vector2(row.end.x - 12, pos.y), false, "delete", i)
		return
	var conds: Array = rule["if"]
	UiFont.draw_small(self, sentence(rule, scope), Vector2(pos.x + 12, pos.y + 11), Gfx.CRT_DIM)
	x = UiFont.draw(self, "IF" if not conds.is_empty() else "ALWAYS", Vector2(x, pos.y), Gfx.CRT_DIM) + 5.0
	for ci in conds.size():
		if ci > 0:
			x = UiFont.draw(self, "AND", Vector2(x, pos.y), Gfx.CRT_DIM) + 5.0
		x = _draw_cond(i, ci, conds[ci], Vector2(x, pos.y)) + 6.0
	if conds.size() < Doctrine.MAX_CONDS:
		x = _chip("+ IF" if conds.is_empty() else "+ AND", Vector2(x, pos.y), false, "add_cond", i) + 6.0
	x = maxf(x, row.position.x + 404.0)
	x = UiFont.draw(self, "THEN", Vector2(x, pos.y), Gfx.CRT_DIM) + 5.0
	_chip(ACTION_LABELS[rule["do"]], Vector2(x, pos.y), false, "action", i, true)
	var bx: float = row.end.x - 44.0
	if i > 0:
		_chip("UP", Vector2(bx, pos.y), false, "up", i)
	if i < _work.size() - 1:
		_chip("DN", Vector2(bx + 13, pos.y), false, "down", i)
	_chip("X", Vector2(bx + 28, pos.y), false, "delete", i)


## The rule as a plain sentence ("IF OWN HP IS BELOW 30%: THE RIG FLEES.").
static func sentence(rule: Dictionary, p_scope: String) -> String:
	var parts := PackedStringArray()
	for c: Array in rule["if"]:
		parts.append(_cond_phrase(c))
	var who: String = "THE RIG" if p_scope == Doctrine.SCOPE_RIG else "THIS GUN"
	var a: String = rule["do"]
	var v: String = Doctrine.action_value(a)
	var act: String
	match Doctrine.action_group(a):
		"drive":
			act = {"circle": "CIRCLES THE TARGET", "kite": "KITES AT RANGE", "charge": "CHARGES IN", "flee": "FLEES",
				"hold": "HOLDS POSITION"}.get(v, v)
		"fire":
			act = "HOLDS FIRE" if v == "hold" else "FIRES AT WILL"
		"ammo":
			act = "LOADS " + {"fire": "INCENDIARY ROUNDS", "shrapnel": "SHRAPNEL", "ap": "ARMOUR PIERCING"}.get(v, v)
		_:
			act = "FOLLOWS THE RIG'S TARGET" if v == "follow" else "TARGETS " + {"nearest": "THE NEAREST ALIEN",
				"strongest": "THE TOUGHEST ALIEN", "weakest": "THE WEAKEST ALIEN", "players_first": "RIVAL RIGS FIRST",
				"boulders": "BOULDERS FIRST", "spitters": "SPITTERS FIRST"}.get(v, v)
	if parts.is_empty():
		return "ALWAYS: %s %s." % [who, act]
	return "IF %s: %s %s." % [" AND ".join(parts), who, act]


static func _cond_phrase(c: Array) -> String:
	var id: String = c[0]
	var lt: bool = c[1] == "<"
	var n: int = int(c[2])
	var yes: bool = n == 1
	match id:
		"hp":
			return "OWN HP IS %s %d%%" % ["BELOW" if lt else "ABOVE", n]
		"swarm":
			return "%s THAN %d ALIENS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"rivals":
			return "%s THAN %d RIVALS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"t_dist":
			return "THE TARGET IS %s THAN %d PX" % ["CLOSER" if lt else "FURTHER", n]
		"t_hp":
			return "THE TARGET HAS %s THAN %d%% HP" % ["LESS" if lt else "MORE", n]
		"t_player":
			return "THE TARGET IS %sA RIVAL" % ["" if yes else "NOT "]
		"t_boulder":
			return "THE TARGET IS %sA BOULDER" % ["" if yes else "NOT "]
		"t_spitter":
			return "THE TARGET IS %sA SPITTER" % ["" if yes else "NOT "]
		"pvp":
			return "PVP IS %s" % ["ON" if yes else "OFF"]
		"has_target":
			return "THERE IS %sTARGET" % ["A " if yes else "NO "]
	return id


func _draw_cond(ri: int, ci: int, c: Array, pos: Vector2) -> float:
	var id: String = c[0]
	var m: Dictionary = Doctrine.CONDS[id]
	var x: float = _chip(COND_LABELS[id], pos, false, "cond", [ri, ci], true) + 3.0
	if bool(m["flag"]):
		return _chip("YES" if int(c[2]) == 1 else "NO", Vector2(x, pos.y), false, "op", [ri, ci])
	x = _chip(str(c[1]), Vector2(x, pos.y), false, "op", [ri, ci]) + 3.0
	x = _chip("-", Vector2(x, pos.y), false, "dec", [ri, ci]) + 2.0
	x = UiFont.draw(self, "%d%s" % [int(c[2]), str(m["unit"])], Vector2(x, pos.y), Gfx.CRT_HI) + 3.0
	return _chip("+", Vector2(x, pos.y), false, "inc", [ri, ci])


func _draw_footer(v: SimVehicle, scr: Rect2) -> void:
	var x0: float = scr.position.x + 8.0
	var foot: float = 42.0 if embedded() else 46.0
	var y: float = scr.end.y - foot
	draw_rect(Rect2(scr.position.x + 4, y - 5, scr.size.x - 8, 1), Gfx.CRT_DIM)
	UiFont.draw(self, "QUICK ADD", Vector2(x0, y), Gfx.CRT_DIM)
	var x: float = x0 + 50.0
	for t: Array in (TEMPLATES_RIG if scope == Doctrine.SCOPE_RIG else TEMPLATES_WEAPON):
		x = _chip(str(t[0]), Vector2(x, y), false, "template", t[1]) + 7.0
	y += 13.0
	var help: String = _help_text()
	if _toast_left > 0.0:
		help = _toast
	for line in UiFont.wrap(help, int(scr.size.x) - 20).slice(0, 2):
		UiFont.draw(self, line, Vector2(x0, y), Gfx.CRT_HI if _toast_left > 0.0 else Gfx.CRT_TEXT)
		y += 8.0
	if world.phase == SimWorld.PHASE_COMBAT:
		var s := "LIVE: A LIT LAMP MEANS THE RULE MATCHES RIGHT NOW"
		UiFont.draw(self, s, Vector2(scr.end.x - 8 - UiFont.width(s), scr.end.y - foot), Gfx.CRT_DIM)


func _help_text() -> String:
	if not _menu.is_empty():
		for k in (_menu["options"] as Array).size():
			if _is_hover("menu_pick", (_menu["options"][k] as Array)[0]):
				return str(_menu["options"][k][2])
	if _hover.is_empty():
		return "CLICK A CONDITION OR ACTION TO CHANGE IT. < > FLIPS THE TEST, - + CHANGES THE NUMBER, UP / DN REORDERS: HIGHER RULES WIN."
	var a: String = _hover[1]
	var arg: Variant = _hover[2]
	match a:
		"cond", "op", "dec", "inc":
			var c: Array = _work[arg[0]]["if"][arg[1]]
			return COND_HELP[c[0]]
		"action":
			return ACTION_HELP[_work[int(arg)]["do"]]
		"base_drive":
			return "WITHOUT A MATCHING RULE: " + ACTION_HELP["drive:" + str(arg)]
		"base_target", "weapon_target":
			return "WITHOUT A MATCHING RULE: " + ACTION_HELP["target:" + str(arg)]
		"template":
			return "ADDS: " + str(arg).to_upper()
		"tab":
			return "THE RIG'S RULES STEER IT; EVERY GUN HAS ITS OWN TARGET AND RULES."
		"add_cond":
			return "ADD A CONDITION: ALL CONDITIONS OF A RULE MUST HOLD."
		"delete":
			return "DELETE THIS RULE."
		"up", "down":
			return "MOVE THE RULE: HIGHER RULES WIN."
	return ""


func _draw_menu() -> void:
	var r: Rect2 = _menu["rect"]
	draw_rect(r.grow(1.0), Gfx.OUTLINE)
	draw_rect(r, Gfx.CRT_BG)
	UiKit.outline_rect(self, r, Gfx.CRT_TEXT)
	var y: float = r.position.y + 3.0
	var cur: String = ""
	var ri: int = int(_menu["ri"])
	if ri >= 0 and ri < _work.size():
		if _menu["kind"] == "action":
			cur = _work[ri]["do"]
		elif _menu["kind"] == "cond":
			cur = _work[ri]["if"][int(_menu["ci"])][0]
	for o: Array in _menu["options"]:
		var orow := Rect2(r.position.x + 2, y - 1, r.size.x - 4, 8)
		var hov: bool = _is_hover("menu_pick", o[0])
		if hov or o[0] == cur:
			draw_rect(orow, Gfx.CRT_TEXT if hov else Color(Gfx.CRT_TEXT, 0.25))
		UiFont.draw(self, o[1], Vector2(r.position.x + 5, y), Gfx.CRT_BG if hov else (Gfx.UI_BAD if o[0] == "" else Gfx.CRT_TEXT))
		_hits.append([orow, "menu_pick", o[0]])
		y += 9.0


## A CRT button; `drop` adds a small down-arrow (opens a list). Returns the x after it.
func _chip(text: String, pos: Vector2, on: bool, action: String, arg: Variant, drop: bool = false) -> float:
	var w: float = UiFont.width(text) + (10.0 if drop else 5.0)
	var r := Rect2(pos - Vector2(2, 2), Vector2(w, 10))
	var hov: bool = _menu.is_empty() and _is_hover(action, arg)
	if on:
		draw_rect(r, Gfx.CRT_TEXT)
	elif hov:
		draw_rect(r, Color(Gfx.CRT_TEXT, 0.22))
	UiKit.outline_rect(self, r, Gfx.CRT_TEXT if on or hov else Gfx.CRT_DIM)
	var tc: Color = Gfx.CRT_BG if on else (Gfx.CRT_HI if hov else Gfx.CRT_TEXT)
	UiFont.draw(self, text, pos + Vector2(1, 0), tc)
	if drop:
		var ax: float = r.end.x - 6.0
		draw_rect(Rect2(ax, pos.y + 2, 3, 1), tc)
		draw_rect(Rect2(ax + 1, pos.y + 3, 1, 1), tc)
	_hits.append([r, action, arg])
	return r.end.x


## Rule lamp: lit while the rule matches (combat only).
func _lamp(pos: Vector2, lit: bool, inverted: bool) -> void:
	draw_rect(Rect2(pos - Vector2.ONE, Vector2(5, 5)), Gfx.CRT_BG if not inverted else Gfx.CRT_TEXT)
	draw_rect(Rect2(pos, Vector2(3, 3)), Gfx.CRT_HI if lit else (Gfx.CRT_DIM if not inverted else Gfx.CRT_BG))
