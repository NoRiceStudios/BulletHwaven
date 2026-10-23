class_name DoctrineEditor
extends Control
## Rule editor (design doc section 6, layer 2): an amber CRT where the player programs IF-THEN
## rules for the rig and for every weapon on its own. In combat P opens it as a full-screen overlay
## (P / Esc / CLOSE close it; the game keeps running behind it). In the workshop it is the RULES
## view: WorkshopUi embeds it into its body (open_embedded) under the top bar, owns the clicks and
## forwards them here (an open picker gets them first), and P / Esc switch the workshop view instead.
##
## Layout: tabs (rig, every gun) on top; a left column with the base behaviour (what runs when no
## rule matches) and the target priority list; the rule list on the right. Rules show as one-line
## summaries; the selected one unfolds into an edit card (conditions, ALL / ANY, action, hold time).
## Every list choice opens a picker: grouped columns that always fit inside the panel, with the
## hovered entry's help underneath and locked entries naming the tech that unlocks them.
##
## Immediate-mode like WorkshopUi: _draw() records hit rects, clicks go through activate(). The
## open tab's rules and priority list are local working copies (so quick clicks never fight
## snapshot lag); every edit sends the whole list as one set_rules / set_priority command, and an
## undo stack (UNDO, Ctrl+Z) re-sends earlier copies. Base settings are read from the synced vehicle.
## Only reads sim state; everything it changes goes through `send_command`.

const PANEL := Rect2(18, 10, 604, 340)
const ROW := 12.0  ## one line of the rule card / priority list
const FOOT_H := 26.0  ## help lines under the columns
const UNDO_MAX := 30

const COND_LABELS := {
	"hp": "OWN HP", "swarm": "ALIENS NEAR", "rivals": "RIVALS NEAR", "t_dist": "TGT DISTANCE", "t_hp": "TGT HP",
	"t_player": "TGT IS RIVAL", "t_boulder": "TGT IS BOULDER", "t_spitter": "TGT IS SPITTER", "pvp": "PVP ON",
	"has_target": "HAS TARGET",
	"boulders": "BOULDERS NEAR", "fuel": "OWN FUEL", "rival_weaker": "RIVAL WEAKER", "ability_ready": "ABILITY READY",
	"t_leader": "TGT IS LEADER", "boss_active": "BOSS ACTIVE", "shrieker_near": "SHRIEKER NEAR", "mark_active": "MARK ACTIVE", "radio_active": "RADIO ACTIVE",
	"in_zone": "IN ZONE", "zone_dist": "ZONE DISTANCE", "zone_contested": "ZONE CONTESTED", "zones_held": "ZONES HELD",
	"mites": "MITES NEAR", "spitters": "SPITTERS NEAR", "flyers": "FLYERS NEAR", "momentum": "MOMENTUM", "round_time": "ROUND TIME",
	"t_mite": "TGT IS MITE", "t_glass": "TGT IS FLYER", "t_brood": "TGT IS BROOD", "t_shrieker": "TGT IS SHRIEKER", "t_boss": "TGT IS BOSS",
	"under_fire": "UNDER FIRE",
}
const COND_HELP := {
	"hp": "YOUR RIG'S HP IN PERCENT OF ITS MAXIMUM.",
	"swarm": "ALIENS OF ANY KIND WITHIN 220 PX OF THE RIG.",
	"rivals": "RIVAL RIGS WITHIN 380 PX (COUNTS ONLY WHILE PVP IS ON).",
	"t_dist": "DISTANCE TO THE CURRENT TARGET IN PX. NO TARGET: NEVER TRUE.",
	"t_hp": "THE TARGET'S HP IN PERCENT. NO TARGET: NEVER TRUE.",
	"t_player": "THE TARGET IS A RIVAL RIG.",
	"t_boulder": "THE TARGET IS A BOULDER.",
	"t_spitter": "THE TARGET IS A SPITTER.",
	"pvp": "PVP IS ON (FROM ROUND 4, AFTER THE GRACE PERIOD).",
	"has_target": "THE RIG (OR THIS GUN) HAS SOMETHING TO SHOOT AT.",
	"boulders": "BOULDERS WITHIN 220 PX OF THE RIG (RANGEFINDER).",
	"fuel": "YOUR RIG'S FUEL (RADAR ARRAY).",
	"rival_weaker": "A RIVAL WITHIN 380 PX HAS LESS HP (IN PERCENT) THAN YOU (RADAR ARRAY).",
	"ability_ready": "AN EQUIPPED ABILITY IS OFF COOLDOWN (TARGETING COMPUTER).",
	"t_leader": "THE TARGET IS THE MARKED BOUNTY LEADER (HUNTER-KILLER LOGIC).",
	"boss_active": "A BOSS IS ON THE FIELD.",
	"shrieker_near": "A SHRIEKER IS WITHIN 360 PX OF THE RIG.",
	"mark_active": "YOUR TARGET MARK IS RUNNING (RIGHT-CLICK AN ALIEN: ALL GUNS ON IT FOR 6 S).",
	"radio_active": "A RADIO CALL (Z X C V) IS RUNNING AND OVERRIDES THE OTHER RULES FOR 5 S.",
	"in_zone": "YOUR RIG IS INSIDE A CONTROL ZONE (FROM ROUND 4, ONCE PVP IS ON).",
	"zone_dist": "DISTANCE TO THE NEAREST CONTROL ZONE YOU DO NOT HOLD, IN PX. NO SUCH ZONE: NEVER TRUE.",
	"zone_contested": "A RIVAL STANDS IN OR IS CAPTURING THE ZONE YOU ARE IN.",
	"zones_held": "CONTROL ZONES YOU HOLD.",
	"mites": "MITES WITHIN 220 PX OF THE RIG.",
	"spitters": "SPITTERS WITHIN 300 PX OF THE RIG.",
	"flyers": "GLASS WINGS (FLYERS) WITHIN 300 PX OF THE RIG.",
	"momentum": "YOUR RIG'S MOMENTUM, 0 TO 100 (TUNED ENGINE).",
	"round_time": "SECONDS SINCE THIS COMBAT ROUND BEGAN (RADAR ARRAY).",
	"t_mite": "THE TARGET IS A MITE.",
	"t_glass": "THE TARGET IS A GLASS WINGS FLYER.",
	"t_brood": "THE TARGET IS A BROOD CARRIER.",
	"t_shrieker": "THE TARGET IS A SHRIEKER.",
	"t_boss": "THE TARGET IS A BOSS (OR A COLOSSUS SHARD).",
	"under_fire": "YOUR RIG TOOK DAMAGE IN THE LAST 2 S (RADAR ARRAY).",
}
const ACTION_LABELS := {
	"drive:circle": "CIRCLE", "drive:kite": "KITE", "drive:charge": "CHARGE", "drive:flee": "FLEE",
	"drive:hold": "HOLD POSITION",
	"target:nearest": "TGT NEAREST", "target:strongest": "TGT STRONGEST", "target:weakest": "TGT WEAKEST",
	"target:players_first": "TGT RIVALS", "target:boulders": "TGT BOULDERS", "target:spitters": "TGT SPITTERS", "target:boss": "TGT BOSS", "target:shriekers": "TGT SHRIEKERS",
	"drive:zone": "HOLD ZONE", "target:intruders": "TGT INTRUDERS",
	"target:priority": "TGT PRIORITY LIST", "target:mites": "TGT MITES", "target:flyers": "TGT FLYERS", "target:broods": "TGT BROODS",
	"target:follow": "FOLLOW RIG", "fire:hold": "HOLD FIRE", "fire:free": "FIRE AT WILL",
	"ammo:fire": "LOAD FIRE", "ammo:shrapnel": "LOAD SHRAPNEL", "ammo:ap": "LOAD AP",
	"fire:focus": "FOCUS FIRE", "ability:nitro": "USE NITRO", "ability:emp": "USE EMP", "ability:smoke": "USE SMOKE",
	"ability:salvo": "USE SALVO",
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
	"target:boss": "THE NEAREST BOSS BODY IN RANGE, ELSE THE NEAREST ALIEN.",
	"target:shriekers": "THE NEAREST SHRIEKER, ELSE THE NEAREST ALIEN.",
	"target:mites": "THE NEAREST MITE, ELSE THE NEAREST ALIEN.",
	"target:flyers": "THE NEAREST GLASS WINGS FLYER, ELSE THE NEAREST ALIEN.",
	"target:broods": "THE NEAREST BROOD CARRIER, ELSE THE NEAREST ALIEN.",
	"target:priority": "GO DOWN THE TARGET PRIORITY LIST (LEFT): THE FIRST KIND WITH SOMETHING IN RANGE GETS SHOT.",
	"drive:zone": "DRIVE INTO THE NEAREST ZONE YOU DO NOT HOLD (ELSE YOUR OWN) AND ORBIT ITS BEACON WHILE THE GUNS KEEP FIRING. ALONE INSIDE 3 S TAKES IT. NO ZONE OPEN: CIRCLE.",
	"target:intruders": "RIVALS INSIDE (OR RIGHT NEXT TO) THE ZONE YOU ARE IN OR HOLD, ELSE THE NEAREST ALIEN.",
	"target:follow": "SHOOT WHAT THE RIG IS AIMING AT.",
	"fire:hold": "THIS GUN DOES NOT SHOOT.",
	"fire:free": "THIS GUN SHOOTS (OVERRIDES A LOWER HOLD FIRE).",
	"ammo:fire": "LOAD INCENDIARY ROUNDS: HITS BURN FOR 2 S.",
	"ammo:shrapnel": "LOAD SHRAPNEL: KILLS BURST INTO 3 SHARDS.",
	"ammo:ap": "LOAD ARMOUR PIERCING: +1 PIERCE, MORE DAMAGE VS BOULDERS AND RIVALS.",
	"fire:focus": "EVERY GUN SHOOTS THE RIG'S TARGET (FIRE CONTROL RELAY).",
	"ability:nitro": "FIRE THE NITRO NOW (NEEDS 50 MOMENTUM). A RULE FOR IT REPLACES ITS AUTO-CAST.",
	"ability:emp": "FIRE THE EMP NOW. A RULE FOR IT REPLACES ITS AUTO-CAST.",
	"ability:smoke": "FIRE THE SMOKE SCREEN NOW. A RULE FOR IT REPLACES ITS AUTO-CAST.",
	"ability:salvo": "FIRE THE SALVO NOW. A RULE FOR IT REPLACES ITS AUTO-CAST.",
}
const LOCKED_HELP := "LOCKED: UNLOCK IT IN THE TECH TREE."
## Condition picker columns: [title, ids]. Ids the sim does not know are skipped, unlisted ones go to OTHER.
const COND_GROUPS: Array = [
	["OWN RIG", ["hp", "fuel", "momentum", "under_fire", "ability_ready"]],
	["AROUND THE RIG", ["swarm", "mites", "boulders", "spitters", "flyers", "shrieker_near", "rivals", "rival_weaker"]],
	["CURRENT TARGET", ["has_target", "t_dist", "t_hp", "t_player", "t_leader", "t_mite", "t_boulder", "t_spitter", "t_glass", "t_brood", "t_shrieker", "t_boss"]],
	["MATCH", ["pvp", "boss_active", "round_time", "mark_active", "radio_active", "in_zone", "zone_dist", "zone_contested", "zones_held"]],
]
const ACTION_GROUP_TITLES := {"drive": "DRIVING", "target": "TARGET CHOICE", "fire": "TRIGGER", "ammo": "AMMO", "ability": "ABILITIES"}
## What a rule's action group is called on its summary line.
const GROUP_TAGS := {"drive": "DRIVE", "target": "TARGET", "fire": "TRIGGER", "ammo": "AMMO", "ability": "ABILITY"}
const PRIO_LABELS := {"boss": "BOSS", "shrieker": "SHRIEKER", "spitter": "SPITTER", "brood": "BROOD CARRIER",
	"glass": "GLASS WINGS", "boulder": "BOULDER", "mite": "MITE", "rival": "RIVAL RIGS"}
const PRIO_HELP := {"boss": "BOSS BODIES AND COLOSSUS SHARDS.", "shrieker": "HEALS AND HASTENS THE ALIENS AROUND IT.",
	"spitter": "KEEPS ITS DISTANCE AND LOBS ACID.", "brood": "BURSTS INTO MITES WHEN IT DIES.", "glass": "FAST FLYERS THAT DIVE INTO RIGS.",
	"boulder": "SLOW AND TANKY.", "mite": "THE SWARM: WEAK AND MANY.", "rival": "OTHER PLAYERS' RIGS (ONLY WHILE PVP IS ON)."}
const PICK_LABELS := {"nearest": "NEAREST", "weakest": "WEAKEST", "strongest": "TOUGHEST"}
const PICK_HELP := {"nearest": "AMONG ONE KIND: SHOOT THE CLOSEST.", "weakest": "AMONG ONE KIND: SHOOT THE ONE WITH THE LEAST HP (FAST KILLS).",
	"strongest": "AMONG ONE KIND: SHOOT THE ONE WITH THE MOST HP."}
const HOLD_MAX := 5
## Quick-add rules per scope: [group, label, text form]. Ones the rig cannot run yet are listed locked.
const TEMPLATES_RIG: Array = [
	["SURVIVE", "RETREAT BELOW 30% HP", "hp<30|drive:flee"],
	["SURVIVE", "KITE WHEN SWARMED", "swarm>20|drive:kite"],
	["SURVIVE", "KITE WHILE UNDER FIRE", "under_fire=1&hp<60|drive:kite"],
	["SURVIVE", "SMOKE BELOW 50% HP", "hp<50|ability:smoke"],
	["HUNT", "PRIORITY LIST IN A SWARM", "swarm>10|target:priority"],
	["HUNT", "SWAT FLYERS FIRST", "flyers>1|target:flyers"],
	["HUNT", "HUNT WOUNDED RIVALS", "t_player=1&t_hp<40|drive:charge"],
	["HUNT", "RIVALS FIRST IN PVP", "pvp=1&rivals>0|target:players_first"],
	["HUNT", "FOCUS FIRE ON BOULDERS", "t_boulder=1|fire:focus"],
	["ABILITIES", "NITRO WHEN CHASED", "swarm>10|ability:nitro"],
	["ABILITIES", "EMP IN A SWARM", "swarm>8|ability:emp"],
	["ABILITIES", "SALVO VS BOULDERS", "boulders>2|ability:salvo"],
]
const TEMPLATES_WEAPON: Array = [
	["TARGETS", "USE THE PRIORITY LIST", "|target:priority"],
	["TARGETS", "FINISH WEAK ONES", "|target:weakest"],
	["TARGETS", "SNIPE SPITTERS", "|target:spitters"],
	["TARGETS", "SHOOT DOWN FLYERS", "flyers>0|target:flyers"],
	["TRIGGER", "SAVE AMMO ON BOULDERS", "t_boulder=1|fire:hold"],
	["TRIGGER", "ONLY AT CLOSE RANGE", "t_dist>110|fire:hold"],
	["AMMO", "AP ROUNDS VS BOULDERS", "t_boulder=1|ammo:ap"],
	["AMMO", "FIRE ROUNDS IN A SWARM", "swarm>15|ammo:fire"],
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
var _prio: Dictionary = {}  # working copy of the open scope's priority list
var _prio_own: bool = true  # a gun with its own list (the rig always has one)
var _sel: int = -1  # the unfolded rule
var _undo: Array = []  # [{"scope", "rules", "prio", "own"}], newest last
var _hits: Array = []  # [Rect2, action, arg]
var _hover: Array = []
var _clicked: Rect2 = Rect2()  # rect of the hit being activated (pickers open next to it)
var _menu: Dictionary = {}  # open picker, see _open_menu
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


## True while a picker is open: it owns every click until it closes (the workshop asks before its own hits).
func menu_open() -> bool:
	return is_open and not _menu.is_empty()


func close() -> void:
	is_open = false
	_menu = {}
	_embed = Rect2()
	mouse_filter = Control.MOUSE_FILTER_STOP


## The CRT housing: the workshop body when embedded, else the overlay panel.
func _panel() -> Rect2:
	return _embed if embedded() else PANEL


func _screen() -> Rect2:
	var p: Rect2 = _panel()
	return Rect2(p.position + Vector2(6, 6), p.size - Vector2(12, 20))


## Replaces the working copy of `p_scope` (when it is the open one) with `p_rules`, e.g. after a preset was sent:
## the sim applies it a tick later, the editor shows it at once.
func show_work(p_scope: String, p_rules: Variant) -> void:
	if is_open and scope == p_scope and p_rules is Array:
		_work = (p_rules as Array).duplicate(true)
		_sel = 0 if not _work.is_empty() else -1
		_menu = {}


func toggle() -> void:
	if is_open:
		close()
	else:
		open(scope)


func _select(p_scope: String) -> void:
	var v: SimVehicle = _local()
	if p_scope != Doctrine.SCOPE_RIG and not _owns_weapon(v, p_scope):
		p_scope = Doctrine.SCOPE_RIG
	if p_scope != scope:
		_sel = -1
	scope = p_scope
	_menu = {}
	var src: Array = v.rules if scope == Doctrine.SCOPE_RIG else Doctrine.weapon_doc(v, scope)["rules"]
	_work = src.duplicate(true)
	_prio = Doctrine.priority_of(v, scope).duplicate(true)
	_prio_own = scope == Doctrine.SCOPE_RIG or Doctrine.weapon_has_own_priority(v, scope)
	if _sel < 0 or _sel >= _work.size():
		_sel = 0 if not _work.is_empty() else -1


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
	var ke := event as InputEventKey
	var key: Key = ke.keycode
	var camp: bool = workshop != null and workshop.visible
	if key == KEY_P and world != null and _local() != null and world.phase != SimWorld.PHASE_GAME_OVER:
		if camp:
			workshop.activate("tab", "parts" if workshop.tab() == "rules" else "rules")
		else:
			toggle()
		get_viewport().set_input_as_handled()
	elif is_open and key == KEY_Z and (ke.ctrl_pressed or ke.meta_pressed):
		activate("undo", null)
		get_viewport().set_input_as_handled()
	elif is_open and key == KEY_ESCAPE:
		if not _menu.is_empty():
			_menu = {}
		elif camp and embedded():
			workshop.activate("tab", "parts")
		else:
			close()
		get_viewport().set_input_as_handled()


## Clicks at `p` (viewport px) like the mouse does; used by screenshot scenarios too. With a picker
## open, a click outside it only closes it.
func click_at(p: Vector2) -> bool:
	var h: Array = _hit_at(p)
	if not _menu.is_empty() and (h.is_empty() or not str(h[1]).begins_with("menu_")):
		if not (_menu["rect"] as Rect2).has_point(p):
			_menu = {}  # a click inside the picker but between entries does nothing
		return true
	if h.is_empty():
		return false
	_clicked = h[0]
	activate(h[1], h[2])
	return true


func activate(action: String, arg: Variant) -> void:
	var v: SimVehicle = _local()
	if v == null:
		return
	if not action.begins_with("menu_"):
		_menu = {}
	match action:
		"close":
			close()
		"tab":
			_select(str(arg))
		"undo":
			_undo_last()
		"sel":
			_sel = -1 if _sel == int(arg) else int(arg)
		"base_drive_menu":
			var opts: Array = []
			for d in Doctrine.BASE_DRIVES:
				var a: String = "drive:" + d
				var ok: bool = Doctrine.action_unlocked(v, a)
				opts.append([d, _label(a), ACTION_HELP.get(a, "") if ok else _action_lock_hint(v, a), not ok])
			_open_menu("base_drive", -1, -1, [["BASE DRIVE", opts]], str(v.doctrine["drive"]))
		"base_target_menu":
			var cur: String = str(v.doctrine["target"]) if scope == Doctrine.SCOPE_RIG else str(Doctrine.weapon_doc(v, scope)["target"])
			var list: PackedStringArray = Doctrine.RIG_TARGETS if scope == Doctrine.SCOPE_RIG else Doctrine.WEAPON_TARGETS
			var topts: Array = []
			for t in list:
				topts.append([t, _target_name(t), ACTION_HELP.get("target:" + t, ""), false])
			_open_menu("base_target", -1, -1, [["BASE TARGET", topts]], cur)
		"use_prio":
			if scope == Doctrine.SCOPE_RIG:
				_send({"type": "set_target", "value": "priority"})
			else:
				_send({"type": "set_weapon_target", "scope": scope, "value": "priority"})
			_say("BASE TARGET: PRIORITY LIST")
		"prio_mode":
			var own: bool = bool(arg)
			if own and not Doctrine.weapon_prio_unlocked(v):
				_say(_fx_hint("prio_weapon", "A GUN'S OWN LIST"))
				return
			if own != _prio_own:
				_push_undo()
				_prio_own = own
				_prio = Doctrine.priority_of(v, Doctrine.SCOPE_RIG).duplicate(true)
				_commit_prio()
		"prio_toggle", "prio_up", "prio_down", "prio_pick":
			if not _prio_own:
				_say("THIS GUN USES THE RIG'S LIST - PICK OWN LIST TO CHANGE IT")
				return
			_edit_prio(action, arg)
		"rule_off":
			_push_undo()
			var r: Dictionary = _work[int(arg)]
			r["off"] = not bool(r.get("off", false))
			_commit()
		"rule_any":
			if bool(arg) and not Doctrine.any_unlocked(v):
				_say(_fx_hint("logic_any", "ANY-OF RULES"))
				return
			_push_undo()
			_work[_sel]["any"] = bool(arg)
			_commit()
		"cond":
			_open_cond_menu("cond", arg[0], arg[1])
		"add_cond":
			_open_cond_menu("add_cond", int(arg), -1)
		"del_cond":
			_push_undo()
			(_work[arg[0]]["if"] as Array).remove_at(int(arg[1]))
			_commit()
		"action":
			_open_action_menu(int(arg))
		"hold_menu":
			var hopts: Array = []
			var hok: bool = Doctrine.hold_unlocked(v)
			for s in HOLD_MAX + 1:
				var lab: String = "OFF" if s == 0 else "%d S" % s
				var help: String = "THE RULE ONLY RUNS WHILE ITS CONDITIONS HOLD." if s == 0 else \
					"ONCE IT MATCHES, THE RULE STAYS ON FOR %d S AFTER ITS CONDITIONS STOP HOLDING (NO FLICKERING)." % s
				hopts.append([s, lab, help if hok or s == 0 else _fx_hint("logic_hold", "HOLD TIMES"), not hok and s > 0])
			_open_menu("hold", int(arg), -1, [["STAY ON FOR", hopts]], int(_work[int(arg)].get("hold", 0)))
		"op":
			_push_undo()
			var c: Array = _work[arg[0]]["if"][arg[1]]
			if bool(Doctrine.CONDS[c[0]]["flag"]):
				c[2] = int(arg[2])
			else:
				c[1] = str(arg[2])
			_commit()
		"dec", "inc":
			_push_undo()
			var c2: Array = _work[arg[0]]["if"][arg[1]]
			var m: Dictionary = Doctrine.CONDS[c2[0]]
			var step: int = int(m["step"]) * (1 if action == "inc" else -1)
			c2[2] = clampi(int(c2[2]) + step, int(m["min"]), int(m["max"]))
			_commit()
		"value_menu":
			var c3: Array = _work[arg[0]]["if"][arg[1]]
			var m3: Dictionary = Doctrine.CONDS[c3[0]]
			var vopts: Array = []
			var n: int = int(m3["min"])
			while n <= int(m3["max"]):
				vopts.append([n, "%d%s" % [n, str(m3.get("unit", ""))], str(COND_HELP.get(c3[0], "")), false])
				n += maxi(int(m3["step"]), 1)
			_open_menu("value", arg[0], arg[1], [[str(COND_LABELS.get(c3[0], c3[0])), vopts]], int(c3[2]))
		"up", "down":
			var i: int = int(arg)
			var j: int = i + (-1 if action == "up" else 1)
			if j >= 0 and j < _work.size():
				_push_undo()
				var tmp: Variant = _work[i]
				_work[i] = _work[j]
				_work[j] = tmp
				_sel = j
				_commit()
		"dup":
			if _work.size() >= Doctrine.slots(v):
				_say("ALL %d SLOTS USED - ELECTRONICS TECH ADDS MORE" % Doctrine.slots(v))
				return
			_push_undo()
			_work.insert(int(arg) + 1, (_work[int(arg)] as Dictionary).duplicate(true))
			_sel = int(arg) + 1
			_commit()
		"delete":
			_push_undo()
			_work.remove_at(int(arg))
			_sel = mini(int(arg), _work.size() - 1)
			_commit()
			_say("RULE DELETED - CTRL+Z OR UNDO BRINGS IT BACK")
		"new_menu":
			_open_new_menu(v)
		"menu_pick":
			var it: Array = _menu["items"][int(arg)]
			_pick(it[1])
		"menu_locked":
			var lk: Array = _menu["items"][int(arg)]
			_say(str(lk[3]))


func _edit_prio(action: String, arg: Variant) -> void:
	_push_undo()
	var order: Array = _prio["order"]
	var off: Array = _prio["off"]
	match action:
		"prio_toggle":
			var t: String = str(arg)
			if off.has(t):
				off.erase(t)
			elif off.size() >= order.size() - 1:
				_undo.pop_back()
				_say("AT LEAST ONE KIND MUST STAY ON THE LIST")
				return
			else:
				off.append(t)
		"prio_up", "prio_down":
			var i: int = int(arg)
			var j: int = i + (-1 if action == "prio_up" else 1)
			if j < 0 or j >= order.size():
				_undo.pop_back()
				return
			var tmp: Variant = order[i]
			order[i] = order[j]
			order[j] = tmp
		"prio_pick":
			_prio["pick"] = str(arg)
	_commit_prio()


func _add_rule(text: String) -> void:
	var v: SimVehicle = _local()
	if _work.size() >= Doctrine.slots(v):
		_say("ALL %d SLOTS USED - ELECTRONICS TECH ADDS MORE" % Doctrine.slots(v))
		return
	var r: Variant = Doctrine.parse(text, scope)
	if r == null or (r as Array).is_empty():
		return
	_push_undo()
	_work.append((r as Array)[0])
	_sel = _work.size() - 1
	_commit()


# ---------------------------------------------------------------- pickers

## Opens a picker next to the clicked control. `groups`: [[title, [[value, label, help, locked], ...]], ...].
## The groups are laid out in columns that always fit inside the panel (a column breaks when the next
## entry would leave it), so every entry stays on screen and clickable.
func _open_menu(kind: String, ri: int, ci: int, groups: Array, cur: Variant) -> void:
	var scr: Rect2 = _screen()
	var max_h: float = scr.size.y - 34.0  # room for the help line under the entries
	var col_w: float = 50.0
	for g: Array in groups:
		col_w = maxf(col_w, UiFont.width_small(str(g[0])) + 10.0)
		for o: Array in g[1]:
			col_w = maxf(col_w, UiFont.width(str(o[1])) + 16.0)
	var items: Array = []  # [rect (relative), value, label, help, locked, is_title]
	var col: int = 0
	var y: float = 0.0
	var tallest: float = 0.0
	for g: Array in groups:
		var opts: Array = g[1]
		if y > 0.0 and y + 11.0 + 9.0 * minf(opts.size(), 3) > max_h:
			col += 1
			y = 0.0
		if str(g[0]) != "":
			items.append([Rect2(col * (col_w + 3.0), y, col_w, 9), null, str(g[0]), "", false, true])
			y += 11.0
		for o: Array in opts:
			if y + 9.0 > max_h:
				col += 1
				y = 0.0
			items.append([Rect2(col * (col_w + 3.0), y, col_w, 9), o[0], str(o[1]), str(o[2]), bool(o[3]), false])
			y += 9.0
			tallest = maxf(tallest, y)
		y += 3.0
	var w: float = maxf((col + 1) * (col_w + 3.0) - 3.0 + 8.0, 170.0)
	w = minf(w, scr.size.x - 4.0)
	var h: float = tallest + 8.0 + 22.0
	var a: Rect2 = _clicked
	var x: float = clampf(a.position.x, scr.position.x + 2.0, scr.end.x - w - 2.0)
	var top: float
	if a.end.y + 2.0 + h <= scr.end.y - 2.0:
		top = a.end.y + 2.0  # below the control
	elif a.position.y - 2.0 - h >= scr.position.y + 2.0:
		top = a.position.y - 2.0 - h  # above it
	else:
		top = clampf(a.end.y + 2.0, scr.position.y + 2.0, scr.end.y - 2.0 - h)  # as low as fits
	var rect := Rect2(x, top, w, h)
	for it: Array in items:
		var rr: Rect2 = it[0]
		it[0] = Rect2(rect.position + Vector2(4, 4) + rr.position, rr.size)
	_menu = {"rect": rect, "kind": kind, "ri": ri, "ci": ci, "items": items, "cur": cur}


func _open_cond_menu(kind: String, ri: int, ci: int) -> void:
	var me: SimVehicle = _local()
	var listed := {}
	var groups: Array = []
	for g: Array in COND_GROUPS:
		var opts: Array = []
		for id: String in g[1]:
			if Doctrine.CONDS.has(id):
				listed[id] = true
				opts.append(_cond_option(me, id))
		if not opts.is_empty():
			groups.append([g[0], opts])
	var rest: Array = []
	for id in Doctrine.COND_IDS:
		if not listed.has(id) and Doctrine.CONDS.has(id):
			rest.append(_cond_option(me, id))
	if not rest.is_empty():
		groups.append(["OTHER", rest])
	var cur: String = ""
	if kind == "cond":
		cur = str(_work[ri]["if"][ci][0])
	_open_menu(kind, ri, ci, groups, cur)


func _cond_option(me: SimVehicle, id: String) -> Array:
	var ok: bool = Doctrine.cond_unlocked(me, id)
	var help: String = str(COND_HELP.get(id, id.to_upper()))
	if not ok:
		help = _fx_hint(str(Doctrine.COND_FX.get(id, "")), str(COND_LABELS.get(id, id)))
	return [id, str(COND_LABELS.get(id, id.to_upper())), help, not ok]


func _open_action_menu(ri: int) -> void:
	var me: SimVehicle = _local()
	var open_ones: PackedStringArray = Doctrine.actions_for(scope, me)
	var by_group := {}
	var order: Array = []
	for a in Doctrine.actions_for(scope):
		var grp: String = Doctrine.action_group(a)
		if not by_group.has(grp):
			by_group[grp] = []
			order.append(grp)
		var ok: bool = open_ones.has(a)
		(by_group[grp] as Array).append([a, _label(a), str(ACTION_HELP.get(a, "")) if ok else _action_lock_hint(me, a), not ok])
	var groups: Array = []
	for grp: String in order:
		groups.append([str(ACTION_GROUP_TITLES.get(grp, grp.to_upper())), by_group[grp]])
	_open_menu("action", ri, -1, groups, str(_work[ri]["do"]))


func _open_new_menu(v: SimVehicle) -> void:
	if _work.size() >= Doctrine.slots(v):
		_say("ALL %d SLOTS USED - ELECTRONICS TECH ADDS MORE" % Doctrine.slots(v))
		return
	var blank: String = ("hp<30|drive:charge" if Mobility.is_juggernaut(v) else "hp<30|drive:flee") if scope == Doctrine.SCOPE_RIG else "t_boulder=1|fire:hold"
	var groups: Array = [["", [[blank, "BLANK RULE", "A SIMPLE RULE TO START FROM: CHANGE ITS CONDITIONS AND ACTION.", false]]]]
	var by_group := {}
	var order: Array = []
	for t: Array in (TEMPLATES_RIG if scope == Doctrine.SCOPE_RIG else TEMPLATES_WEAPON):
		var parsed: Variant = Doctrine.parse(str(t[2]), scope)
		if parsed == null:
			continue
		var ok: bool = Doctrine.rules_allowed(v, parsed)
		var help: String = DoctrineEditor.sentence((parsed as Array)[0], scope) if ok else "LOCKED" + _rule_lock_hint(v, (parsed as Array)[0])
		if not by_group.has(t[0]):
			by_group[t[0]] = []
			order.append(t[0])
		(by_group[t[0]] as Array).append([t[2], t[1], help, not ok])
	for g: String in order:
		groups.append([g, by_group[g]])
	_open_menu("new_rule", -1, -1, groups, "")


func _pick(value: Variant) -> void:
	var kind: String = _menu.get("kind", "")
	var ri: int = int(_menu.get("ri", -1))
	var ci: int = int(_menu.get("ci", -1))
	_menu = {}
	match kind:
		"base_drive":
			_send({"type": "set_drive", "value": str(value)})
			return
		"base_target":
			if scope == Doctrine.SCOPE_RIG:
				_send({"type": "set_target", "value": str(value)})
			else:
				_send({"type": "set_weapon_target", "scope": scope, "value": str(value)})
			return
		"new_rule":
			_add_rule(str(value))
			return
	if ri < 0 or ri >= _work.size():
		return
	_push_undo()
	var rule: Dictionary = _work[ri]
	var conds: Array = rule["if"]
	match kind:
		"action":
			rule["do"] = str(value)
		"cond":
			if str(value) != str(conds[ci][0]):
				conds[ci] = Doctrine.default_cond(str(value))
		"add_cond":
			if conds.size() < Doctrine.max_conds(_local()):
				conds.append(Doctrine.default_cond(str(value)))
		"value":
			conds[ci][2] = int(value)
		"hold":
			rule["hold"] = int(value)
	_commit()


# ---------------------------------------------------------------- commands and undo

func _commit() -> void:
	for r: Dictionary in _work:
		if (r["if"] as Array).size() < 2:
			r["any"] = false
	_send({"type": "set_rules", "scope": scope, "value": Doctrine.encode(_work)})


func _commit_prio() -> void:
	_send({"type": "set_priority", "scope": scope, "value": Doctrine.encode_priority(_prio) if _prio_own else ""})


func _push_undo() -> void:
	_undo.append({"scope": scope, "rules": _work.duplicate(true), "prio": _prio.duplicate(true), "own": _prio_own})
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		_say("NOTHING TO UNDO")
		return
	var u: Dictionary = _undo.pop_back()
	if str(u["scope"]) != scope:
		_select(str(u["scope"]))
	var rules_changed: bool = Doctrine.encode(u["rules"]) != Doctrine.encode(_work)
	_work = (u["rules"] as Array).duplicate(true)
	_prio = (u["prio"] as Dictionary).duplicate(true)
	_prio_own = bool(u["own"])
	_sel = clampi(_sel, -1, _work.size() - 1)
	if rules_changed:
		_commit()
	else:
		_commit_prio()
	_say("UNDONE")


func _send(cmd: Dictionary) -> void:
	if send_command.is_valid():
		send_command.call(cmd)


func _say(text: String) -> void:
	_toast = text
	_toast_left = 2.2


# ---------------------------------------------------------------- lock hints

## "NEEDS RANGEFINDER (ELECTRONICS TECH)" for the tech whose fx key `fx` unlocks something.
static func _fx_hint(fx: String, what: String = "") -> String:
	if fx != "":
		for id in Tech.ids():
			var d: Dictionary = Tech.def(id)
			if (d.get("fx", {}) as Dictionary).has(fx):
				return "LOCKED%s: NEEDS %s (%s TECH)." % [(" - " + what) if what != "" else "", str(d["short"]), str(d["branch"]).to_upper()]
	return LOCKED_HELP


func _action_lock_hint(v: SimVehicle, a: String) -> String:
	match Doctrine.action_group(a):
		"ammo", "ability":
			return _fx_hint(Doctrine.action_group(a) + "_" + Doctrine.action_value(a), _label(a))
		"fire":
			return _fx_hint("act_focus", _label(a))
		"drive":
			if Mobility.is_juggernaut(v):
				return "LOCKED: A JUGGERNAUT CANNOT BACK AWAY."
	return LOCKED_HELP


## Why a parsed rule cannot run on `v` (the first reason found).
func _rule_lock_hint(v: SimVehicle, r: Dictionary) -> String:
	for c: Array in r["if"]:
		if not Doctrine.cond_unlocked(v, c[0]):
			return _fx_hint(str(Doctrine.COND_FX.get(c[0], "")), str(COND_LABELS.get(c[0], c[0]))).trim_prefix("LOCKED")
	if not Doctrine.action_unlocked(v, r["do"]):
		return _action_lock_hint(v, r["do"]).trim_prefix("LOCKED")
	return ""


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
	var scr: Rect2 = _screen()
	draw_rect(scr, Gfx.CRT_BG)
	var x0: float = scr.position.x + 8.0
	var y: float = scr.position.y + 6.0
	if not embedded():
		var px: float = UiFont.draw_big(self, "DOCTRINE.SYS - RULE EDITOR", Vector2(x0, y - 1), Gfx.CRT_HI)
		if fmod(_blink, 1.0) < 0.5:
			draw_rect(Rect2(px + 2, y - 1, 4, 7), Gfx.CRT_TEXT)
		_chip("CLOSE  (P)", Vector2(scr.end.x - 8 - UiFont.width("CLOSE  (P)"), y), false, "close", null)
		y += 13.0
	_draw_tabs(v, Vector2(x0, y), scr)
	y += 15.0
	var side_w: float = 150.0 if scr.size.x >= 560.0 else 138.0
	var bottom: float = scr.end.y - FOOT_H
	var side := Rect2(x0, y, side_w, bottom - y)
	var main_x: float = x0 + side_w + 12.0
	var main := Rect2(main_x, y, scr.end.x - 8.0 - main_x, bottom - y)
	draw_rect(Rect2(main_x - 7.0, y - 2.0, 1, bottom - y - 2.0), Color(Gfx.CRT_DIM, 0.6))
	_draw_side(v, side)
	_draw_rules(v, main)
	_draw_footer(scr)
	# scanlines and glare over the whole tube
	for sy in range(int(scr.position.y) + 1, int(scr.end.y), 2):
		draw_rect(Rect2(scr.position.x, sy, scr.size.x, 1), Color(0, 0, 0, 0.16))
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
	var undo_w: float = UiFont.width("UNDO") + 12.0
	for t: Array in tabs:
		var label: String = t[1]
		var on: bool = scope == t[0]
		var n: int = (v.rules if t[0] == Doctrine.SCOPE_RIG else Doctrine.weapon_doc(v, t[0])["rules"]).size()
		if n > 0:
			label += " (%d)" % n
		var r := Rect2(x - 3, pos.y - 3, UiFont.width(label) + 14, 11)
		if r.end.x > scr.end.x - undo_w - 10.0:
			break
		draw_rect(r, Gfx.CRT_TEXT if on else (Gfx.CRT_DIM * Color(1, 1, 1, 0.35) if _menu.is_empty() and _is_hover("tab", t[0]) else Color(0, 0, 0, 0)))
		UiKit.outline_rect(self, r, Gfx.CRT_TEXT if on else Gfx.CRT_DIM)
		UiFont.draw(self, label, Vector2(x, pos.y), Gfx.CRT_BG if on else Gfx.CRT_TEXT)
		_lamp(Vector2(r.end.x - 7, pos.y + 1), int(t[2]) != 0, on)
		_hits.append([r, "tab", t[0]])
		x = r.end.x + 5.0
	if not _undo.is_empty():
		_chip("UNDO", Vector2(scr.end.x - 8 - undo_w + 7.0, pos.y), false, "undo", null)
	draw_rect(Rect2(scr.position.x + 4, pos.y + 9, scr.size.x - 8, 1), Gfx.CRT_DIM)


# -- left column: base behaviour and the target priority list

func _draw_side(v: SimVehicle, side: Rect2) -> void:
	var x: float = side.position.x
	var y: float = side.position.y + 2.0
	var lx: float = x + 40.0
	var rig: bool = scope == Doctrine.SCOPE_RIG
	_section("WHEN NO RULE MATCHES", Vector2(x, y), side.size.x)
	y += 12.0
	var cur_target: String
	if rig:
		UiFont.draw(self, "DRIVE", Vector2(x, y), Gfx.CRT_DIM)
		_chip(_label("drive:" + str(v.doctrine["drive"])), Vector2(lx, y), false, "base_drive_menu", null, true)
		y += ROW
		cur_target = str(v.doctrine["target"])
	else:
		var wp: Dictionary = {}
		for w in v.weapons:
			if str(w["kind"]) == scope:
				wp = w
		var info := "RANGE %d  DMG %s  %s/S" % [roundi(float(wp.get("range", 0.0))), UiKit.num(float(wp.get("damage", 0.0)) * float(wp.get("pellets", 1))),
			UiKit.num(float(SimWorld.TICK_RATE) / maxf(float(wp.get("cooldown_ticks", 1)), 1.0))]
		UiFont.draw_small(self, info, Vector2(x, y), Gfx.CRT_DIM)
		y += ROW
		cur_target = str(Doctrine.weapon_doc(v, scope)["target"])
	UiFont.draw(self, "TARGET", Vector2(x, y), Gfx.CRT_DIM)
	_chip(_target_name(cur_target), Vector2(lx, y), false, "base_target_menu", null, true)
	y += ROW + 6.0
	_section("TARGET PRIORITY", Vector2(x, y), side.size.x)
	y += 12.0
	if not rig:
		var locked: bool = not Doctrine.weapon_prio_unlocked(v)
		_seg([[false, "RIG'S LIST", false], [true, "OWN LIST", locked]], Vector2(x, y), _prio_own, "prio_mode")
		y += ROW
	var order: Array = _prio.get("order", [])
	var off: Array = _prio.get("off", [])
	var editable: bool = _prio_own
	var rank: int = 0
	for i in order.size():
		var t: String = order[i]
		var is_off: bool = off.has(t)
		var row := Rect2(x - 3, y - 2, side.size.x + 2, 10)
		if editable and _menu.is_empty() and not _hover.is_empty() and (_hover[2] == t or (_hover[2] is int and int(_hover[2]) == i and str(_hover[1]).begins_with("prio_"))):
			draw_rect(row, UiKit.HOVER_WASH)
		var col: Color = Gfx.CRT_DIM if is_off or not editable else Gfx.CRT_TEXT
		if not is_off:
			rank += 1
		UiFont.draw_small(self, "%d" % rank if not is_off else "-", Vector2(x, y), Gfx.CRT_HI if not is_off and editable else Gfx.CRT_DIM)
		_switch(Vector2(x + 9, y), not is_off, "prio_toggle", t, not editable)
		var lw: float = UiFont.draw(self, str(PRIO_LABELS.get(t, t.to_upper())), Vector2(x + 26, y), col)
		if is_off:
			draw_rect(Rect2(x + 25, y + 3, lw - x - 24, 1), Gfx.CRT_DIM)
			UiFont.draw_small(self, "IGNORED", Vector2(lw + 4, y + 1), Gfx.CRT_DIM)
		if editable:
			_arrow(Vector2(side.end.x - 21, y), true, "prio_up", i, i > 0)
			_arrow(Vector2(side.end.x - 10, y), false, "prio_down", i, i < order.size() - 1)
		_hits.append([Rect2(row.position, Vector2(row.size.x - 24, row.size.y)), "prio_row", t])
		y += 10.0
	y += 3.0
	UiFont.draw_small(self, "AMONG ONE KIND, SHOOT THE", Vector2(x, y), Gfx.CRT_DIM)
	y += 9.0
	var picks: Array = []
	for p in Doctrine.PRIO_PICKS:
		picks.append([p, str(PICK_LABELS.get(p, p.to_upper())), false])
	_seg(picks, Vector2(x, y), str(_prio.get("pick", "nearest")), "prio_pick", null, not editable)
	y += ROW + 2.0
	# is the list used at all? Offer the one-click fix when it is not.
	var uses: bool = cur_target == "priority"
	for r: Dictionary in _work:
		if str(r["do"]) == "target:priority" and not bool(r.get("off", false)):
			uses = true
	if not rig and cur_target == "follow" and str(v.doctrine["target"]) == "priority" and not _prio_own:
		uses = true
	if uses:
		_lamp(Vector2(x, y + 1), true, false)
		UiFont.draw_small(self, "IN USE" + (" (BASE TARGET)" if cur_target == "priority" else " (BY A RULE)"), Vector2(x + 7, y), Gfx.CRT_TEXT)
	elif y + 10.0 < side.end.y:
		UiFont.draw_small(self, "NOT IN USE:", Vector2(x, y), Gfx.UI_BAD)
		_chip("USE AS BASE TARGET", Vector2(x + UiFont.width_small("NOT IN USE:") + 6.0, y), false, "use_prio", null)


# -- right column: the rules

func _draw_rules(v: SimVehicle, main: Rect2) -> void:
	var x0: float = main.position.x
	var slots: int = Doctrine.slots(v)
	var active: int = Doctrine.active_slots(v)
	var y: float = main.position.y + 2.0
	_section("RULES  %d/%d SLOTS" % [mini(_work.size(), slots), slots], Vector2(x0, y), main.size.x,
		"TOP RULE WINS - ONE PER KIND" if not _work.is_empty() else "")
	y += 13.0
	var live: int = v.rule_live
	if scope != Doctrine.SCOPE_RIG:
		live = 0
		for w in v.weapons:
			if str(w["kind"]) == scope:
				live = int(w.get("live", 0))
	var combat: bool = world.phase == SimWorld.PHASE_COMBAT
	if _sel >= _work.size():
		_sel = _work.size() - 1
	for i in _work.size():
		var r: Dictionary = _work[i]
		var lit: bool = combat and i < active and not bool(r.get("off", false)) and (live >> i) & 1 == 1
		var status: Array = _status(v, i, active)
		if i == _sel:
			y = _draw_card(v, i, r, Rect2(x0 - 3, y - 3, main.size.x + 3, 0), lit, status) + 4.0
		else:
			_draw_row(i, r, Rect2(x0 - 3, y - 3, main.size.x + 3, 11), lit, status)
			y += 13.0
	y += 2.0
	if _work.size() < slots:
		_chip("+ NEW RULE", Vector2(x0, y), false, "new_menu", null, true)
		if _work.is_empty():
			var msg: String = "NO RULES YET: THIS %s ALWAYS USES ITS BASE SETTING (LEFT). ADD A RULE TO REACT TO WHAT HAPPENS: LOW HP, A SWARM, A BOSS..." % ("RIG" if scope == Doctrine.SCOPE_RIG else "GUN")
			var ly: float = y + 16.0
			for line in UiFont.wrap_small(msg, int(main.size.x) - 4):
				UiFont.draw_small(self, line, Vector2(x0, ly), Gfx.CRT_DIM)
				ly += 8.0
	elif _work.size() < Doctrine.MAX_SLOTS:
		UiFont.draw_small(self, "ALL %d SLOTS USED - ELECTRONICS TECH ADDS MORE" % slots, Vector2(x0, y), Gfx.CRT_DIM)


## [tag, colour, explanation] of rule i, or [] when it runs normally.
func _status(v: SimVehicle, i: int, active: int) -> Array:
	var r: Dictionary = _work[i]
	if i >= Doctrine.slots(v):
		return ["NO SLOT", Gfx.CRT_DIM, "NO SLOT: THIS RIG HAS ONLY %d RULE SLOTS. BUILD ELECTRONICS TECH TO RUN IT." % Doctrine.slots(v)]
	if bool(r.get("off", false)):
		return ["OFF", Gfx.CRT_DIM, "SWITCHED OFF: THE RULE IS KEPT BUT DOES NOT RUN."]
	if i >= active:
		var why: String = _off_text(v)
		return [why, Gfx.UI_BAD, why + ": THIS RULE DOES NOT RUN RIGHT NOW."]
	var lock: String = _rule_lock_hint(v, r)
	if lock == "" and bool(r.get("any", false)) and not Doctrine.any_unlocked(v):
		lock = _fx_hint("logic_any", "ANY-OF RULES").trim_prefix("LOCKED")
	if lock != "":
		return ["LOCKED", Gfx.UI_BAD, "LOCKED" + lock + " UNTIL THEN THE RULE DOES NOT RUN."]
	var key: String = _group_key(str(r["do"]))
	for j in i:
		var o: Dictionary = _work[j]
		if not bool(o.get("off", false)) and (o["if"] as Array).is_empty() and _group_key(str(o["do"])) == key:
			return ["NEVER RUNS", Gfx.UI_BAD, "NEVER RUNS: RULE %d ABOVE HAS NO CONDITION AND ALWAYS WINS. MOVE THIS ONE UP OR GIVE RULE %d A CONDITION." % [j + 1, j + 1]]
	return []


## Rules with the same key compete: the first matching one wins (abilities each on their own).
static func _group_key(a: String) -> String:
	var g: String = Doctrine.action_group(a)
	if g == "ability" or a == "fire:focus":
		return a
	return g


func _draw_row(i: int, r: Dictionary, row: Rect2, lit: bool, status: Array) -> void:
	var hov: bool = _menu.is_empty() and _is_hover("sel", i)
	if lit:
		draw_rect(row, Color(Gfx.CRT_TEXT, 0.14))
	elif hov:
		draw_rect(row, UiKit.HOVER_WASH)
	UiKit.outline_rect(self, row, Gfx.CRT_TEXT if lit or hov else Color(Gfx.CRT_DIM, 0.7))
	_hits.append([row, "sel", i])
	var p := Vector2(row.position.x + 4, row.position.y + 3)
	var dim: bool = not status.is_empty()
	var x: float = UiFont.draw(self, "%d" % (i + 1), p, Gfx.CRT_HI if lit else (Gfx.CRT_DIM if dim else Gfx.CRT_TEXT)) + 3.0
	_lamp(Vector2(x, p.y + 1), lit, false)
	x += 7.0
	x = _switch(Vector2(x, p.y), not bool(r.get("off", false)), "rule_off", i) + 5.0
	var tag: String = str(status[0]) if not status.is_empty() else str(GROUP_TAGS.get(Doctrine.action_group(str(r["do"])), ""))
	var tag_col: Color = status[1] if not status.is_empty() else Gfx.CRT_DIM
	var tw: float = UiFont.width_small(tag)
	var room: float = row.end.x - 8.0 - tw - x - 6.0
	UiFont.draw_small(self, _clip_small(short_text(r), room), Vector2(x, p.y + 1), Gfx.CRT_DIM if dim else Gfx.CRT_TEXT)
	UiFont.draw_small(self, tag, Vector2(row.end.x - 6.0 - tw, p.y + 1), tag_col)


## The unfolded rule: returns the y under it.
func _draw_card(v: SimVehicle, i: int, r: Dictionary, frame: Rect2, lit: bool, status: Array) -> float:
	var conds: Array = r["if"]
	var cmax: int = Doctrine.max_conds(v)
	var inner_w: float = frame.size.x - 10.0
	var sent: PackedStringArray = UiFont.wrap_small(DoctrineEditor.sentence(r, scope), int(inner_w))
	var note: PackedStringArray = UiFont.wrap_small(str(status[2]), int(inner_w)) if not status.is_empty() else PackedStringArray()
	var h: float = 14.0 + (ROW if conds.size() >= 2 else 0.0) + ROW * conds.size() + ROW + ROW + 4.0 + 8.0 * sent.size() + 8.0 * note.size() + 3.0
	var card := Rect2(frame.position, Vector2(frame.size.x, h))
	draw_rect(card, Color(Gfx.CRT_TEXT, 0.16 if lit else 0.07))
	UiKit.outline_rect(self, card, Gfx.CRT_TEXT)
	draw_rect(Rect2(card.position.x, card.position.y, 2, card.size.y), Gfx.CRT_TEXT)
	var x0: float = card.position.x + 6.0
	var y: float = card.position.y + 4.0
	# header: number, lamp, switch, tools
	var x: float = UiFont.draw(self, "RULE %d" % (i + 1), Vector2(x0, y), Gfx.CRT_HI) + 4.0
	_lamp(Vector2(x, y + 1), lit, false)
	x += 8.0
	x = _switch(Vector2(x, y), not bool(r.get("off", false)), "rule_off", i) + 3.0
	UiFont.draw_small(self, "ON" if not bool(r.get("off", false)) else "OFF", Vector2(x, y + 1), Gfx.CRT_DIM)
	var bx: float = card.end.x - 5.0
	bx = _chip_left("X", bx, y, "delete", i)
	if i < _work.size() - 1:
		bx = _chip_left("DN", bx - 2.0, y, "down", i)
	if i > 0:
		bx = _chip_left("UP", bx - 2.0, y, "up", i)
	bx = _chip_left("COPY", bx - 2.0, y, "dup", i)
	_chip_left("FOLD", bx - 6.0, y, "sel", i)
	y += 14.0
	# ALL / ANY
	var any: bool = bool(r.get("any", false))
	if conds.size() >= 2:
		UiFont.draw_small(self, "MATCH WHEN", Vector2(x0, y + 1), Gfx.CRT_DIM)
		_seg([[false, "ALL HOLD", false], [true, "ANY HOLDS", not Doctrine.any_unlocked(v)]], Vector2(x0 + 50, y), any, "rule_any")
		y += ROW
	# conditions, one per line
	var lead_w: float = 26.0
	for ci in conds.size():
		var c: Array = conds[ci]
		var lead: String = "IF" if ci == 0 else ("OR" if any else "AND")
		UiFont.draw(self, lead, Vector2(x0 + lead_w - 4.0 - UiFont.width(lead), y), Gfx.CRT_DIM)
		_draw_cond(i, ci, c, Vector2(x0 + lead_w, y), v)
		_chip_left("X", card.end.x - 5.0, y, "del_cond", [i, ci])
		y += ROW
	if conds.is_empty():
		var ax: float = UiFont.draw(self, "ALWAYS ON -", Vector2(x0 + 4.0, y), Gfx.CRT_DIM)
		_chip("+ CONDITION", Vector2(ax + 6.0, y), false, "add_cond", i, true)
	elif conds.size() < cmax:
		_chip("+ CONDITION", Vector2(x0 + lead_w, y), false, "add_cond", i, true)
	else:
		UiFont.draw_small(self, "MAX %d CONDITIONS PER RULE%s" % [cmax, "" if cmax >= Doctrine.MAX_CONDS else " (TARGETING COMPUTER: +1)"], Vector2(x0 + lead_w, y + 1), Gfx.CRT_DIM)
	y += ROW
	# action and hold
	UiFont.draw(self, "THEN", Vector2(x0 + lead_w - 4.0 - UiFont.width("THEN"), y), Gfx.CRT_HI)
	_chip(_label(str(r["do"])), Vector2(x0 + lead_w, y), false, "action", i, true)
	var hold: int = int(r.get("hold", 0))
	var htxt: String = "OFF" if hold == 0 else "%d S" % hold
	var hx: float = _chip_left(htxt, card.end.x - 5.0, y, "hold_menu", i, true)
	UiFont.draw_small(self, "STAY ON", Vector2(hx - 4.0 - UiFont.width_small("STAY ON"), y + 1), Gfx.CRT_DIM)
	y += ROW + 4.0
	for line in sent:
		UiFont.draw_small(self, line, Vector2(x0, y), Gfx.CRT_DIM if not lit else Gfx.CRT_TEXT)
		y += 8.0
	for line in note:
		UiFont.draw_small(self, line, Vector2(x0, y), status[1])
		y += 8.0
	return card.end.y


## Why a rule slot is switched off: "JAMMED BY <NAME>" in a rival's jammer field, "EMP" after a rival's pulse.
func _off_text(v: SimVehicle) -> String:
	if v.rules_off_ticks > 0:
		return "EMP: RULES OFFLINE"
	if v.jammed_by >= 0 and v.jammed_by < world.vehicles.size():
		return "JAMMED BY " + world.vehicles[v.jammed_by].player_name
	return "OFFLINE"


func _draw_cond(ri: int, ci: int, c: Array, pos: Vector2, v: SimVehicle) -> float:
	var id: String = c[0]
	var m: Dictionary = Doctrine.CONDS[id]
	var locked: bool = not Doctrine.cond_unlocked(v, id)
	var x: float = _chip(str(COND_LABELS.get(id, id.to_upper())), pos, false, "cond", [ri, ci], true, locked) + 4.0
	if bool(m["flag"]):
		return _seg([[1, "YES", false], [0, "NO", false]], Vector2(x, pos.y), int(c[2]), "op", [ri, ci])
	x = _seg([["<", "BELOW", false], [">", "ABOVE", false]], Vector2(x, pos.y), str(c[1]), "op", [ri, ci]) + 4.0
	x = _chip("-", Vector2(x, pos.y), false, "dec", [ri, ci]) + 1.0
	x = _chip("%d%s" % [int(c[2]), str(m.get("unit", ""))], Vector2(x, pos.y), false, "value_menu", [ri, ci], true) + 1.0
	return _chip("+", Vector2(x, pos.y), false, "inc", [ri, ci])


func _draw_footer(scr: Rect2) -> void:
	var x0: float = scr.position.x + 8.0
	var y: float = scr.end.y - FOOT_H + 4.0
	draw_rect(Rect2(scr.position.x + 4, y - 4, scr.size.x - 8, 1), Gfx.CRT_DIM)
	var help: String = _help_text()
	var col: Color = Gfx.CRT_TEXT
	if _toast_left > 0.0:
		help = _toast
		col = Gfx.CRT_HI
	var live_note := ""
	if world.phase == SimWorld.PHASE_COMBAT:
		live_note = "LIVE: A LIT LAMP = THE RULE MATCHES NOW"
	var w: int = int(scr.size.x) - 20 - (UiFont.width_small(live_note) + 12 if live_note != "" else 0)
	for line in UiFont.wrap(help, w).slice(0, 2):
		UiFont.draw(self, line, Vector2(x0, y), col)
		y += 9.0
	if live_note != "":
		UiFont.draw_small(self, live_note, Vector2(scr.end.x - 8 - UiFont.width_small(live_note), scr.end.y - FOOT_H + 5.0), Gfx.CRT_DIM)


func _help_text() -> String:
	if not _menu.is_empty():
		return "PICK AN ENTRY - CLICK OUTSIDE OR ESC TO CANCEL."
	if _hover.is_empty():
		if _sel >= 0:
			return "CLICK A CONDITION OR THE ACTION TO CHANGE IT. RULES RUN TOP TO BOTTOM: THE FIRST MATCHING RULE OF EACH KIND WINS, THE REST FALLS BACK TO THE BASE SETTING."
		return "CLICK A RULE TO OPEN IT. RULES RUN TOP TO BOTTOM: THE FIRST MATCHING RULE OF EACH KIND WINS."
	var a: String = _hover[1]
	var arg: Variant = _hover[2]
	match a:
		"cond", "dec", "inc", "value_menu":
			var c: Array = _work[arg[0]]["if"][arg[1]]
			return str(COND_HELP.get(c[0], ""))
		"op":
			var c2: Array = _work[arg[0]]["if"][arg[1]]
			return "FLIP THE TEST. " + str(COND_HELP.get(c2[0], ""))
		"del_cond":
			return "REMOVE THIS CONDITION."
		"action":
			return str(ACTION_HELP.get(_work[int(arg)]["do"], ""))
		"hold_menu":
			return "STAY ON: ONCE THE RULE MATCHES IT KEEPS RUNNING FOR A FEW SECONDS, SO THE RIG DOES NOT FLIP BACK AND FORTH." + ("" if Doctrine.hold_unlocked(_local()) else " " + _fx_hint("logic_hold"))
		"rule_any":
			return "ALL HOLD: EVERY CONDITION MUST BE TRUE. ANY HOLDS: ONE TRUE CONDITION IS ENOUGH." + ("" if Doctrine.any_unlocked(_local()) else " " + _fx_hint("logic_any", "ANY HOLDS"))
		"rule_off":
			return "SWITCH THE RULE ON OR OFF WITHOUT DELETING IT."
		"sel":
			return "OPEN OR FOLD THIS RULE." if int(arg) != _sel else "FOLD THIS RULE."
		"base_drive_menu":
			return "HOW THE RIG DRIVES WHEN NO RULE SAYS OTHERWISE."
		"base_target_menu":
			return "WHAT THIS %s SHOOTS WHEN NO RULE SAYS OTHERWISE." % ("RIG" if scope == Doctrine.SCOPE_RIG else "GUN")
		"prio_toggle":
			return "ON: THIS KIND IS ON THE LIST. OFF: THE LIST NEVER PICKS IT. " + str(PRIO_HELP.get(arg, ""))
		"prio_up", "prio_down":
			return "MOVE THIS KIND UP OR DOWN: HIGHER KINDS ARE SHOT FIRST WHEN IN RANGE."
		"prio_row":
			return str(PRIO_LABELS.get(arg, "")) + ": " + str(PRIO_HELP.get(arg, ""))
		"prio_pick":
			return str(PICK_HELP.get(arg, ""))
		"prio_mode":
			return "RIG'S LIST: THIS GUN USES THE RIG'S PRIORITIES. OWN LIST: GIVE THIS GUN ITS OWN ORDER." + ("" if Doctrine.weapon_prio_unlocked(_local()) else " " + _fx_hint("prio_weapon", "OWN LIST"))
		"use_prio":
			return "SET THE BASE TARGET TO THE PRIORITY LIST."
		"new_menu":
			return "ADD A RULE: START BLANK OR FROM A READY-MADE ONE."
		"tab":
			return "THE RIG'S RULES STEER IT; EVERY GUN HAS ITS OWN TARGET, PRIORITY LIST AND RULES."
		"add_cond":
			return "ADD A CONDITION TO THIS RULE."
		"delete":
			return "DELETE THIS RULE (UNDO BRINGS IT BACK)."
		"dup":
			return "COPY THIS RULE INTO THE NEXT SLOT."
		"up", "down":
			return "MOVE THE RULE: HIGHER RULES WIN."
		"undo":
			return "UNDO THE LAST CHANGE (CTRL+Z)."
	return ""


func _draw_menu() -> void:
	var r: Rect2 = _menu["rect"]
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Color(0, 0, 0, 0.5))
	draw_rect(r.grow(1.0), Gfx.OUTLINE)
	draw_rect(r, Gfx.CRT_BG)
	UiKit.outline_rect(self, r, Gfx.CRT_TEXT)
	var cur: Variant = _menu.get("cur", "")
	var help: String = ""
	var items: Array = _menu["items"]
	for k in items.size():
		var it: Array = items[k]
		var ir: Rect2 = it[0]
		if bool(it[5]):
			UiFont.draw_small(self, str(it[2]), ir.position + Vector2(1, 1), Gfx.CRT_DIM)
			draw_rect(Rect2(ir.position.x + UiFont.width_small(str(it[2])) + 4.0, ir.position.y + 4.0, ir.size.x - UiFont.width_small(str(it[2])) - 6.0, 1), Color(Gfx.CRT_DIM, 0.5))
			continue
		var locked: bool = bool(it[4])
		var hov: bool = _is_hover("menu_locked" if locked else "menu_pick", k)
		var is_cur: bool = typeof(it[1]) == typeof(cur) and it[1] == cur
		if hov:
			help = str(it[3])
		if not locked and hov:
			draw_rect(Rect2(ir.position - Vector2(1, 0), ir.size + Vector2(2, 0)), Gfx.CRT_TEXT)
		elif is_cur:
			draw_rect(Rect2(ir.position - Vector2(1, 0), ir.size + Vector2(2, 0)), Color(Gfx.CRT_TEXT, 0.25))
		elif locked and hov:
			draw_rect(Rect2(ir.position - Vector2(1, 0), ir.size + Vector2(2, 0)), Color(Gfx.UI_BAD, 0.2))
		var tcol: Color = Gfx.CRT_DIM if locked else (Gfx.CRT_BG if hov else Gfx.CRT_TEXT)
		var tx: float = ir.position.x + 3.0
		if locked:
			_padlock(Vector2(tx, ir.position.y + 1), tcol)
			tx += 6.0
		elif is_cur:
			draw_rect(Rect2(tx, ir.position.y + 2, 3, 3), Gfx.CRT_BG if hov else Gfx.CRT_HI)
			tx += 6.0
		UiFont.draw(self, str(it[2]), Vector2(tx, ir.position.y + 1), tcol)
		_hits.append([ir, "menu_locked" if locked else "menu_pick", k])
	# help line for the hovered entry
	var hy: float = r.end.y - 21.0
	draw_rect(Rect2(r.position.x + 3, hy - 2, r.size.x - 6, 1), Gfx.CRT_DIM)
	if help == "":
		help = "CLICK TO PICK - ESC OR A CLICK OUTSIDE CANCELS."
	for line in UiFont.wrap_small(help, int(r.size.x) - 10).slice(0, 2):
		UiFont.draw_small(self, line, Vector2(r.position.x + 5, hy + 1), Gfx.CRT_HI if help != "" else Gfx.CRT_DIM)
		hy += 8.0


# ---------------------------------------------------------------- widgets

## A CRT button; `drop` adds a small down-arrow (opens a picker). Returns the x after it.
func _chip(text: String, pos: Vector2, on: bool, action: String, arg: Variant, drop: bool = false, warn: bool = false) -> float:
	var w: float = UiFont.width(text) + (11.0 if drop else 5.0)
	var r := Rect2(pos - Vector2(2, 2), Vector2(w, 10))
	var hov: bool = _menu.is_empty() and _is_hover(action, arg)
	if on:
		draw_rect(r, Gfx.CRT_TEXT)
	elif hov:
		draw_rect(r, Color(Gfx.CRT_TEXT, 0.22))
	var edge: Color = Gfx.UI_BAD if warn else (Gfx.CRT_TEXT if on or hov else Gfx.CRT_DIM)
	UiKit.outline_rect(self, r, edge)
	var tc: Color = Gfx.CRT_BG if on else (Gfx.UI_BAD if warn else (Gfx.CRT_HI if hov else Gfx.CRT_TEXT))
	UiFont.draw(self, text, pos + Vector2(1, 0), tc)
	if drop:
		var ax: float = r.end.x - 7.0
		draw_rect(Rect2(ax, pos.y + 2, 5, 1), tc)
		draw_rect(Rect2(ax + 1, pos.y + 3, 3, 1), tc)
		draw_rect(Rect2(ax + 2, pos.y + 4, 1, 1), tc)
	_hits.append([r, action, arg])
	return r.end.x


## A chip whose right edge is at `right`; returns its left edge.
func _chip_left(text: String, right: float, y: float, action: String, arg: Variant, drop: bool = false) -> float:
	var w: float = UiFont.width(text) + (11.0 if drop else 5.0)
	_chip(text, Vector2(right - w + 2.0, y), false, action, arg, drop)
	return right - w


## Segmented control: options [[value, label, locked], ...], the one equal to `cur` lit. A click sends
## `action` with the value (or [arg..., value] when `arg` is an Array). Returns the x after it.
func _seg(options: Array, pos: Vector2, cur: Variant, action: String, arg: Variant = null, disabled: bool = false) -> float:
	var x: float = pos.x
	for o: Array in options:
		var val: Variant = o[0]
		var a: Variant = val
		if arg is Array:
			a = (arg as Array) + [val]
		var w: float = UiFont.width(str(o[1])) + 6.0 + (6.0 if bool(o[2]) else 0.0)
		var r := Rect2(x - 2, pos.y - 2, w, 10)
		var on: bool = typeof(val) == typeof(cur) and val == cur
		var hov: bool = not disabled and _menu.is_empty() and _is_hover(action, a)
		if on:
			draw_rect(r, Gfx.CRT_TEXT if not disabled else Gfx.CRT_DIM)
		elif hov:
			draw_rect(r, Color(Gfx.CRT_TEXT, 0.22))
		UiKit.outline_rect(self, r, Gfx.CRT_TEXT if on and not disabled else Gfx.CRT_DIM)
		var tc: Color = Gfx.CRT_BG if on else (Gfx.CRT_DIM if bool(o[2]) or disabled else (Gfx.CRT_HI if hov else Gfx.CRT_TEXT))
		var tx: float = x + 1.0
		if bool(o[2]):
			_padlock(Vector2(tx, pos.y), tc)
			tx += 6.0
		UiFont.draw(self, str(o[1]), Vector2(tx, pos.y), tc)
		_hits.append([r, action, a])
		x = r.end.x - 1.0
	return x + 1.0


## On/off switch (11 x 7): the knob sits right and lit when on.
func _switch(pos: Vector2, on: bool, action: String, arg: Variant, disabled: bool = false) -> float:
	var r := Rect2(pos.x, pos.y - 1, 13, 8)
	var hov: bool = not disabled and _menu.is_empty() and _is_hover(action, arg)
	draw_rect(r, Color(Gfx.CRT_TEXT, 0.3) if on and not disabled else Gfx.CRT_BG)
	UiKit.outline_rect(self, r, Gfx.CRT_HI if hov else (Gfx.CRT_TEXT if on and not disabled else Gfx.CRT_DIM))
	var knob := Rect2(r.position.x + (7.0 if on else 2.0), r.position.y + 2.0, 4, 4)
	draw_rect(knob, (Gfx.CRT_HI if on else Gfx.CRT_DIM) if not disabled else Gfx.CRT_DIM)
	if not disabled:
		_hits.append([r.grow(1.0), action, arg])
	return r.end.x


## Small up / down arrow button.
func _arrow(pos: Vector2, up: bool, action: String, arg: Variant, enabled: bool) -> void:
	var r := Rect2(pos.x - 1, pos.y - 2, 9, 9)
	var hov: bool = enabled and _menu.is_empty() and _is_hover(action, arg)
	if hov:
		draw_rect(r, Color(Gfx.CRT_TEXT, 0.22))
	UiKit.outline_rect(self, r, Gfx.CRT_TEXT if hov else Color(Gfx.CRT_DIM, 0.8 if enabled else 0.3))
	var c: Color = (Gfx.CRT_HI if hov else Gfx.CRT_TEXT) if enabled else Color(Gfx.CRT_DIM, 0.4)
	for k in 3:
		var yy: float = pos.y + (1.0 + k if up else 3.0 - k)
		draw_rect(Rect2(pos.x + 3.0 - k, yy, 1 + 2 * k, 1), c)
	if enabled:
		_hits.append([r, action, arg])


func _padlock(pos: Vector2, c: Color) -> void:
	draw_rect(Rect2(pos.x + 1, pos.y, 2, 1), c)
	draw_rect(Rect2(pos.x, pos.y + 1, 1, 2), c)
	draw_rect(Rect2(pos.x + 3, pos.y + 1, 1, 2), c)
	draw_rect(Rect2(pos.x - 1, pos.y + 3, 6, 4), c)


func _section(text: String, pos: Vector2, w: float, right: String = "") -> void:
	var tx: float = UiFont.draw(self, text, pos, Gfx.CRT_HI)
	var rx: float = pos.x + w
	if right != "":
		rx -= UiFont.width_small(right)
		UiFont.draw_small(self, right, Vector2(rx, pos.y + 1), Gfx.CRT_DIM)
		rx -= 5.0
	if rx > tx + 6.0:
		draw_rect(Rect2(tx + 4.0, pos.y + 4.0, rx - tx - 6.0, 1), Color(Gfx.CRT_DIM, 0.6))


## Rule lamp: lit while the rule matches (combat only).
func _lamp(pos: Vector2, lit: bool, inverted: bool) -> void:
	draw_rect(Rect2(pos - Vector2.ONE, Vector2(5, 5)), Gfx.CRT_BG if not inverted else Gfx.CRT_TEXT)
	draw_rect(Rect2(pos, Vector2(3, 3)), Gfx.CRT_HI if lit else (Gfx.CRT_DIM if not inverted else Gfx.CRT_BG))


static func _clip_small(text: String, w: float) -> String:
	if UiFont.width_small(text) <= w:
		return text
	var t: String = text
	while t.length() > 1 and UiFont.width_small(t + "...") > w:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "..."


# ---------------------------------------------------------------- texts

static func _label(a: String) -> String:
	return str(ACTION_LABELS.get(a, a.to_upper()))


static func _target_name(t: String) -> String:
	return "PRIORITY LIST" if t == "priority" else _label("target:" + t).trim_prefix("TGT ")


## The rule in a few words for its summary line ("HP < 30% -> FLEE").
static func short_text(rule: Dictionary) -> String:
	var parts := PackedStringArray()
	for c: Array in rule["if"]:
		var id: String = c[0]
		var lab: String = str(COND_LABELS.get(id, id.to_upper()))
		var m: Dictionary = Doctrine.CONDS.get(id, {"flag": true})
		if bool(m["flag"]):
			parts.append(lab if int(c[2]) == 1 else "NOT " + lab)
		else:
			parts.append("%s %s %d%s" % [lab, c[1], int(c[2]), str(m.get("unit", ""))])
	var head: String = "ALWAYS" if parts.is_empty() else (" OR " if bool(rule.get("any", false)) else " & ").join(parts)
	var hold: int = int(rule.get("hold", 0))
	return "%s  >  %s%s" % [head, _label(str(rule["do"])).trim_prefix("TGT "), (" (%dS)" % hold) if hold > 0 else ""]


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
				"hold": "HOLDS POSITION", "zone": "DRIVES INTO A CONTROL ZONE AND HOLDS IT"}.get(v, v)
		"fire":
			act = {"hold": "HOLDS FIRE", "focus": "FOCUSES ALL GUNS ON ONE TARGET"}.get(v, "FIRES AT WILL")
		"ammo":
			act = "LOADS " + {"fire": "INCENDIARY ROUNDS", "shrapnel": "SHRAPNEL", "ap": "ARMOUR PIERCING"}.get(v, v)
		"ability":
			act = "USES " + v.to_upper()
		_:
			act = "FOLLOWS THE RIG'S TARGET" if v == "follow" else "TARGETS " + {"nearest": "THE NEAREST ALIEN",
				"strongest": "THE TOUGHEST ALIEN", "weakest": "THE WEAKEST ALIEN", "players_first": "RIVAL RIGS FIRST",
				"boulders": "BOULDERS FIRST", "spitters": "SPITTERS FIRST", "boss": "THE BOSS FIRST", "shriekers": "SHRIEKERS FIRST",
				"intruders": "RIVALS IN ITS ZONE FIRST", "priority": "BY THE PRIORITY LIST", "mites": "MITES FIRST",
				"flyers": "FLYERS FIRST", "broods": "BROOD CARRIERS FIRST"}.get(v, v)
	var hold: int = int(rule.get("hold", 0))
	var tail: String = (" AND KEEPS AT IT FOR %d S" % hold) if hold > 0 else ""
	var pre: String = "(OFF) " if bool(rule.get("off", false)) else ""
	if parts.is_empty():
		return "%sALWAYS: %s %s%s." % [pre, who, act, tail]
	return "%sIF %s: %s %s%s." % [pre, (" OR " if bool(rule.get("any", false)) else " AND ").join(parts), who, act, tail]


static func _cond_phrase(c: Array) -> String:
	var id: String = c[0]
	var lt: bool = c[1] == "<"
	var n: int = int(c[2])
	var yes: bool = n == 1
	var nt: String = "" if yes else "NOT "
	match id:
		"hp":
			return "OWN HP IS %s %d%%" % ["BELOW" if lt else "ABOVE", n]
		"swarm":
			return "%s THAN %d ALIENS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"mites":
			return "%s THAN %d MITES ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"spitters":
			return "%s THAN %d SPITTERS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"flyers":
			return "%s THAN %d FLYERS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"rivals":
			return "%s THAN %d RIVALS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"t_dist":
			return "THE TARGET IS %s THAN %d PX" % ["CLOSER" if lt else "FURTHER", n]
		"t_hp":
			return "THE TARGET HAS %s THAN %d%% HP" % ["LESS" if lt else "MORE", n]
		"t_player":
			return "THE TARGET IS %sA RIVAL" % nt
		"t_boulder":
			return "THE TARGET IS %sA BOULDER" % nt
		"t_spitter":
			return "THE TARGET IS %sA SPITTER" % nt
		"t_mite":
			return "THE TARGET IS %sA MITE" % nt
		"t_glass":
			return "THE TARGET IS %sA FLYER" % nt
		"t_brood":
			return "THE TARGET IS %sA BROOD CARRIER" % nt
		"t_shrieker":
			return "THE TARGET IS %sA SHRIEKER" % nt
		"t_boss":
			return "THE TARGET IS %sA BOSS" % nt
		"pvp":
			return "PVP IS %s" % ["ON" if yes else "OFF"]
		"has_target":
			return "THERE IS %sTARGET" % ["A " if yes else "NO "]
		"boss_active":
			return "A BOSS IS %sON THE FIELD" % nt
		"shrieker_near":
			return "A SHRIEKER IS %sNEAR" % nt
		"mark_active":
			return "A TARGET MARK IS %sRUNNING" % nt
		"radio_active":
			return "A RADIO CALL IS %sRUNNING" % nt
		"boulders":
			return "%s THAN %d BOULDERS ARE NEAR" % ["FEWER" if lt else "MORE", n]
		"fuel":
			return "OWN FUEL IS %s %d" % ["BELOW" if lt else "ABOVE", n]
		"momentum":
			return "MOMENTUM IS %s %d" % ["BELOW" if lt else "ABOVE", n]
		"round_time":
			return "THE ROUND IS %s THAN %d S OLD" % ["LESS" if lt else "MORE", n]
		"under_fire":
			return "THE RIG IS %sUNDER FIRE" % nt
		"rival_weaker":
			return "A NEARBY RIVAL IS %sWEAKER THAN YOU" % nt
		"ability_ready":
			return "AN ABILITY IS %sREADY" % nt
		"t_leader":
			return "THE TARGET IS %sTHE LEADER" % nt
		"in_zone":
			return "OWN RIG IS %sIN A CONTROL ZONE" % nt
		"zone_dist":
			return "A ZONE YOU DO NOT HOLD IS %s THAN %d PX AWAY" % ["CLOSER" if lt else "FURTHER", n]
		"zone_contested":
			return "THE ZONE YOU ARE IN IS %sCONTESTED" % nt
		"zones_held":
			return "YOU HOLD %s THAN %d ZONES" % ["FEWER" if lt else "MORE", n]
	return id.to_upper()
