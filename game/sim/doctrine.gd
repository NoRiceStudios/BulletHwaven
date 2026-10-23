class_name Doctrine
extends RefCounted
## Programmable behaviour (design doc section 6, layer 2): "IF ... THEN ..." rules for the rig and
## for every weapon on its own. Pure data, parsing and deterministic evaluation; no rendering.
##
## A rule is {"if": [[cond_id, op, value], ...], "do": action}. All conditions must hold (AND, at
## most MAX_CONDS; none = always). Rules are read top to bottom and the first matching rule of each
## action group wins: one group for the rig's driving style ("drive:*"), one for its target choice
## ("target:*"), one for a weapon's target ("target:*") and one for a weapon's trigger ("fire:*").
## What no rule sets falls back to the base setting (the rig's doctrine, the weapon's base target).
##
## Rule options: "any" (match when at least one condition holds; needs >= 2 conditions), "off" (disabled)
## and "hold" (0..MAX_HOLD seconds a matched rule stays matched after its conditions stop holding).
##
## Text form (commands, tests, tools): rules joined by ";", each "cond&cond|action", a condition
## "id<n", "id>n" or "id=0/1" (flags). Example: "hp<30|drive:flee;swarm>20&t_dist<120|drive:charge".
## A leading "-" marks an off rule, "/" instead of "&" means any (never mixed), "@N" after the action sets
## hold: "-hp<30/swarm>20|drive:flee@2".
## The snapshot uses a compact binary form built on the index tables COND_IDS / ACTIONS: only ever
## append to them.

const SCOPE_RIG := "rig"
const MAX_CONDS := 4  ## absolute cap per rule; the vehicle's own limit is max_conds()
const BASE_CONDS := 3  ## conditions per rule before the Targeting Computer
const BASE_SLOTS := 2  ## rule slots per list without Electronics tech
const MAX_SLOTS := 6  ## hard cap per list (rules beyond the vehicle's slots are stored, not run)
const MAX_TEXT := 400  ## longest accepted text form of one list
const SWARM_RADIUS := 220.0  ## "swarm": aliens within this many px of the rig
const RIVAL_RADIUS := 380.0  ## "rivals": rival rigs within this many px (only while PvP is on)
const SPECIES_RADIUS := 300.0  ## "spitters" / "flyers": aliens of that kind within this many px
const MAX_HOLD := 5  ## seconds a rule can be held
const HOLD_TICKS_PER_S := 30
const UNDER_FIRE_TICKS := 60  ## "under_fire": the rig took damage within this many ticks

## Index tables for the binary form. Only append.
const COND_IDS: PackedStringArray = ["hp", "swarm", "rivals", "t_dist", "t_hp", "t_player", "t_boulder", "t_spitter", "pvp", "has_target",
	"boulders", "fuel", "rival_weaker", "ability_ready", "t_leader", "boss_active", "shrieker_near", "mark_active", "radio_active",
	"in_zone", "zone_dist", "zone_contested", "zones_held",
	"mites", "spitters", "flyers", "momentum", "round_time", "t_mite", "t_glass", "t_brood", "t_shrieker", "t_boss", "under_fire"]
const OPS: PackedStringArray = ["<", ">", "="]
const ACTIONS: PackedStringArray = [
	"drive:circle", "drive:kite", "drive:charge", "drive:flee", "drive:hold",
	"target:nearest", "target:strongest", "target:weakest", "target:players_first", "target:boulders",
	"target:spitters", "target:follow", "fire:hold", "fire:free",
	"ammo:fire", "ammo:shrapnel", "ammo:ap",
	"fire:focus", "ability:nitro", "ability:emp", "ability:smoke", "ability:salvo",
	"target:boss", "target:shriekers",
	"drive:zone", "target:intruders",
	"target:priority", "target:mites", "target:flyers", "target:broods",
]

## Target priority list: every type once, in order of importance (text "boss,-rival,...:weakest").
const PRIO_TYPES: PackedStringArray = ["boss", "shrieker", "spitter", "brood", "glass", "boulder", "mite", "rival"]
const PRIO_PICKS: PackedStringArray = ["nearest", "weakest", "strongest"]
const DEFAULT_PRIO := "boss,shrieker,spitter,brood,glass,mite,boulder,rival:nearest"

## Condition metadata: numeric ones take "<" / ">" and a value in [min, max] (UI step `step`);
## flags take "=" with 0 or 1.
const CONDS := {
	"hp": {"flag": false, "min": 0, "max": 100, "step": 10, "def": 30, "unit": "%"},
	"swarm": {"flag": false, "min": 0, "max": 80, "step": 5, "def": 15, "unit": ""},
	"rivals": {"flag": false, "min": 0, "max": 7, "step": 1, "def": 0, "unit": ""},
	"t_dist": {"flag": false, "min": 0, "max": 600, "step": 25, "def": 120, "unit": "px"},
	"t_hp": {"flag": false, "min": 0, "max": 100, "step": 10, "def": 50, "unit": "%"},
	"t_player": {"flag": true, "def": 1},
	"t_boulder": {"flag": true, "def": 1},
	"t_spitter": {"flag": true, "def": 1},
	"pvp": {"flag": true, "def": 1},
	"has_target": {"flag": true, "def": 0},
	"boulders": {"flag": false, "min": 0, "max": 20, "step": 1, "def": 3, "unit": ""},
	"fuel": {"flag": false, "min": 0, "max": 100, "step": 10, "def": 30, "unit": ""},
	"rival_weaker": {"flag": true, "def": 1},
	"ability_ready": {"flag": true, "def": 1},
	"t_leader": {"flag": true, "def": 1},
	"boss_active": {"flag": true, "def": 1},
	"shrieker_near": {"flag": true, "def": 1},
	"mark_active": {"flag": true, "def": 1},
	"radio_active": {"flag": true, "def": 1},
	"in_zone": {"flag": true, "def": 1},
	"zone_dist": {"flag": false, "min": 0, "max": 1000, "step": 50, "def": 300, "unit": "px"},
	"zone_contested": {"flag": true, "def": 1},
	"zones_held": {"flag": false, "min": 0, "max": 3, "step": 1, "def": 0, "unit": ""},
	"mites": {"flag": false, "min": 0, "max": 80, "step": 5, "def": 10, "unit": ""},
	"spitters": {"flag": false, "min": 0, "max": 20, "step": 1, "def": 2, "unit": ""},
	"flyers": {"flag": false, "min": 0, "max": 20, "step": 1, "def": 2, "unit": ""},
	"momentum": {"flag": false, "min": 0, "max": 100, "step": 10, "def": 50, "unit": ""},
	"round_time": {"flag": false, "min": 0, "max": 300, "step": 10, "def": 30, "unit": "s"},
	"t_mite": {"flag": true, "def": 1},
	"t_glass": {"flag": true, "def": 1},
	"t_brood": {"flag": true, "def": 1},
	"t_shrieker": {"flag": true, "def": 1},
	"t_boss": {"flag": true, "def": 1},
	"under_fire": {"flag": true, "def": 1},
}
## Conditions the tech tree unlocks: condition id -> tech fx key (anything else is always available).
const COND_FX := {
	"boulders": "cond_boulders", "fuel": "cond_fuel", "rival_weaker": "cond_rival_weaker",
	"ability_ready": "cond_ability_ready", "t_leader": "cond_t_leader",
	"under_fire": "cond_under_fire", "round_time": "cond_round_time",
}

const DRIVES: PackedStringArray = ["circle", "kite", "charge", "flee", "hold", "zone"]
const BASE_DRIVES: PackedStringArray = ["circle", "kite", "charge", "zone"]  ## base doctrine (set_drive)
const RIG_TARGETS: PackedStringArray = ["nearest", "strongest", "weakest", "players_first", "boulders", "spitters", "boss", "shriekers", "intruders",
	"priority", "mites", "flyers", "broods"]
const WEAPON_TARGETS: PackedStringArray = ["follow", "nearest", "strongest", "weakest", "players_first", "boulders", "spitters", "boss", "shriekers", "intruders",
	"priority", "mites", "flyers", "broods"]


## Rule slots of a list for this vehicle: BASE_SLOTS plus the `rule_slots` of the active tech.
static func slots(v: SimVehicle) -> int:
	return clampi(BASE_SLOTS + roundi(float(v.tech_fx.get("rule_slots", 0.0))), 1, MAX_SLOTS)


## Rule slots that actually run: none while EMP'd by a rival, one fewer inside a rival's jammer field.
static func active_slots(v: SimVehicle) -> int:
	if v.rules_off_ticks > 0:
		return 0
	return maxi(slots(v) - (1 if v.jammed_by >= 0 else 0), 0)


## Conditions allowed per rule: 3, 4 with the Targeting Computer (`max_conds` fx).
static func max_conds(v: SimVehicle) -> int:
	return clampi(BASE_CONDS + roundi(float(v.tech_fx.get("max_conds", 0.0))), BASE_CONDS, MAX_CONDS)


static func is_weapon_scope(scope: String) -> bool:
	return Cards.WEAPONS.has(scope)


## Is condition `id` available to `v` (unlocked by its tech)?
static func cond_unlocked(v: SimVehicle, id: String) -> bool:
	var key: String = str(COND_FX.get(id, ""))
	return key == "" or float(v.tech_fx.get(key, 0.0)) > 0.0


## Rule option "any" (Rangefinder, fx logic_any).
static func any_unlocked(v: SimVehicle) -> bool:
	return float(v.tech_fx.get("logic_any", 0.0)) > 0.0


## Rule option "hold" (Targeting Computer, fx logic_hold).
static func hold_unlocked(v: SimVehicle) -> bool:
	return float(v.tech_fx.get("logic_hold", 0.0)) > 0.0


## A weapon's own target priority list (Targeting Computer, fx prio_weapon).
static func weapon_prio_unlocked(v: SimVehicle) -> bool:
	return float(v.tech_fx.get("prio_weapon", 0.0)) > 0.0


## Is action `a` available to `v`? ammo needs the ammo, focus the relay, ability:<id> that ability, and a
## juggernaut cannot back away (no kite / flee).
static func action_unlocked(v: SimVehicle, a: String) -> bool:
	match action_group(a):
		"ammo":
			return Ammo.is_unlocked(v, action_value(a))
		"ability":
			return Abilities.is_unlocked(v, action_value(a))
		"fire":
			return a != "fire:focus" or float(v.tech_fx.get("act_focus", 0.0)) > 0.0
		"drive":
			return not ((a == "drive:kite" or a == "drive:flee") and Mobility.is_juggernaut(v))
	return true


## Conditions `v` has unlocked, in COND_IDS order (the editor greys the rest).
static func conds_for(v: SimVehicle) -> PackedStringArray:
	var out := PackedStringArray()
	for id in COND_IDS:
		if cond_unlocked(v, id):
			out.append(id)
	return out


## Actions a rule may use in `scope` ("rig" or a weapon kind). With a vehicle `v` the list is limited to
## what it has unlocked (editor); without one everything is listed (parsing, snapshots: the sim checks the
## unlock, see rules_allowed()). Rig scope: drive, target, `fire:focus`, `ability:<id>`; weapon scope:
## target, fire hold / free, `ammo:<id>`.
static func actions_for(scope: String, v: SimVehicle = null) -> PackedStringArray:
	var out := PackedStringArray()
	for a in ACTIONS:
		var grp: String = action_group(a)
		var ok: bool
		if scope == SCOPE_RIG:
			ok = grp == "drive" or grp == "ability" or a == "fire:focus" or (grp == "target" and a != "target:follow")
		else:
			ok = grp == "ammo" or grp == "target" or (grp == "fire" and a != "fire:focus")
		if ok and (v == null or action_unlocked(v, a)):
			out.append(a)
	return out


## False if a parsed rule list uses something `v` has not unlocked (options any / hold, conditions, `ammo:<id>`, `fire:focus`,
## `ability:<id>`, kite / flee as a juggernaut) or more conditions per rule than it may.
static func rules_allowed(v: SimVehicle, rules: Array) -> bool:
	var cmax: int = max_conds(v)
	for r: Dictionary in rules:
		if not action_unlocked(v, r["do"]):
			return false
		var conds: Array = r["if"]
		if conds.size() > cmax:
			return false
		if rule_any(r) and not any_unlocked(v):
			return false
		if rule_hold(r) > 0 and not hold_unlocked(v):
			return false
		for c: Array in conds:
			if not cond_unlocked(v, c[0]):
				return false
	return true


static func action_group(action: String) -> String:
	return action.get_slice(":", 0)


static func action_value(action: String) -> String:
	return action.get_slice(":", 1)


# ---------------------------------------------------------------- text form

## Parses the text form for `scope`. Returns the rule list, or null if anything is malformed
## (unknown ids, values out of range, an action the scope does not allow, more than MAX_SLOTS).
static func parse(text: String, scope: String) -> Variant:
	var rules: Array = []
	if text.length() > MAX_TEXT:
		return null
	if text.strip_edges() == "":
		return rules
	var allowed: PackedStringArray = actions_for(scope)
	for part in text.split(";", false):
		var halves: PackedStringArray = part.split("|")
		if halves.size() != 2:
			return null
		var action: String = halves[1].strip_edges()
		var hold: int = 0
		if action.contains("@"):
			var hp: PackedStringArray = action.split("@")
			if hp.size() != 2 or not hp[1].strip_edges().is_valid_int():
				return null
			hold = hp[1].strip_edges().to_int()
			if hold < 0 or hold > MAX_HOLD:
				return null
			action = hp[0].strip_edges()
		if not allowed.has(action):
			return null
		var conds: Array = []
		var ctext: String = halves[0].strip_edges()
		var off: bool = false
		if ctext.begins_with("-"):
			off = true
			ctext = ctext.substr(1).strip_edges()
		var any: bool = false
		if ctext != "":
			var has_and: bool = ctext.contains("&")
			var has_or: bool = ctext.contains("/")
			if has_and and has_or:
				return null
			any = has_or
			for c in ctext.split("/" if has_or else "&"):
				var cond: Variant = _parse_cond(c.strip_edges())
				if cond == null:
					return null
				conds.append(cond)
		if conds.size() > MAX_CONDS:
			return null
		rules.append(make_rule(conds, action, any, off, hold))
	if rules.size() > MAX_SLOTS:
		return null
	return rules


## A rule dict with the options normalised ("any" only counts with >= 2 conditions, hold in 0..MAX_HOLD).
static func make_rule(conds: Array, action: String, any: bool = false, off: bool = false, hold: int = 0) -> Dictionary:
	return {"if": conds, "do": action, "any": any and conds.size() >= 2, "off": off, "hold": clampi(hold, 0, MAX_HOLD)}


static func rule_any(rule: Dictionary) -> bool:
	return bool(rule.get("any", false)) and (rule["if"] as Array).size() >= 2


static func rule_off(rule: Dictionary) -> bool:
	return bool(rule.get("off", false))


static func rule_hold(rule: Dictionary) -> int:
	return clampi(int(rule.get("hold", 0)), 0, MAX_HOLD)


## Does a per-condition mask (bit j = condition j holds) satisfy `rule`? All conditions, or at least one with "any".
static func rule_matches_mask(rule: Dictionary, cond_mask: int) -> bool:
	var n: int = (rule["if"] as Array).size()
	if rule_any(rule):
		return cond_mask != 0
	return cond_mask == (1 << n) - 1


static func _parse_cond(c: String) -> Variant:
	for op in OPS:
		var at: int = c.find(op)
		if at <= 0:
			continue
		var id: String = c.substr(0, at)
		var num: String = c.substr(at + 1)
		if not num.is_valid_int():
			return null
		return make_cond(id, op, num.to_int())
	return null


## A validated condition [id, op, value], or null.
static func make_cond(id: String, op: String, value: int) -> Variant:
	if not CONDS.has(id):
		return null
	var m: Dictionary = CONDS[id]
	if bool(m["flag"]):
		if op != "=" or (value != 0 and value != 1):
			return null
	elif op == "=" or not OPS.has(op) or value < int(m["min"]) or value > int(m["max"]):
		return null
	return [id, op, value]


static func encode(rules: Array) -> String:
	var parts := PackedStringArray()
	for r: Dictionary in rules:
		var cs := PackedStringArray()
		for c: Array in r["if"]:
			cs.append("%s%s%d" % [c[0], c[1], int(c[2])])
		var hold: int = rule_hold(r)
		parts.append("%s%s|%s%s" % ["-" if rule_off(r) else "", ("/" if rule_any(r) else "&").join(cs), r["do"], "@%d" % hold if hold > 0 else ""])
	return ";".join(parts)


## A fresh condition with the metadata's default (numeric: "<" default value; flag: "= def").
static func default_cond(id: String) -> Array:
	var m: Dictionary = CONDS[id]
	return [id, "=" if bool(m["flag"]) else "<", int(m["def"])]


# ---------------------------------------------------------------- vehicle state

## The weapon doctrine of `kind` on `v`: {"target": String, "rules": Array} (defaults if unset).
static func weapon_doc(v: SimVehicle, kind: String) -> Dictionary:
	var d: Variant = v.weapon_doctrine.get(kind)
	if d == null:
		return {"target": "follow", "rules": []}
	return d


static func set_rules(v: SimVehicle, scope: String, rules: Array) -> void:
	if scope == SCOPE_RIG:
		v.rules = rules
	elif is_weapon_scope(scope):
		var d: Dictionary = weapon_doc(v, scope).duplicate()
		d["rules"] = rules
		v.weapon_doctrine[scope] = d
	else:
		return
	clear_hold(v, scope)


## Forgets the held rules of one list (all lists without a scope).
static func clear_hold(v: SimVehicle, scope: String = "") -> void:
	if scope == "":
		v.rule_hold.clear()
		return
	var prefix: String = scope + ":"
	for k: String in v.rule_hold.keys():
		if k.begins_with(prefix):
			v.rule_hold.erase(k)


static func set_weapon_target(v: SimVehicle, kind: String, mode: String) -> void:
	if not is_weapon_scope(kind) or not WEAPON_TARGETS.has(mode):
		return
	var d: Dictionary = weapon_doc(v, kind).duplicate()
	d["target"] = mode
	v.weapon_doctrine[kind] = d


## Stable text of everything programmable on `v` (checksums, tests). The priority lists are only part of
## it once they differ from the default / follow the rig, so an unprogrammed rig stays "".
static func fingerprint(v: SimVehicle) -> String:
	var s: String = encode(v.rules)
	var rp: String = encode_priority(v.target_prio)
	if rp != DEFAULT_PRIO:
		s += "~" + rp
	var kinds: Array = v.weapon_doctrine.keys()
	kinds.sort()
	for k: String in kinds:
		var d: Dictionary = v.weapon_doctrine[k]
		s += "#%s:%s:%s" % [k, d["target"], encode(d["rules"])]
		if weapon_has_own_priority(v, k):
			s += "!" + encode_priority(d["prio"])
	return s


# ---------------------------------------------------------------- target priority

static func default_priority() -> Dictionary:
	return parse_priority(DEFAULT_PRIO) as Dictionary


## Parses "type,-type,...:pick": every PRIO_TYPES entry exactly once, "-" = off, the pick optional (nearest).
## Returns {"order", "off", "pick"} or null.
static func parse_priority(text: String) -> Variant:
	if text.length() > MAX_TEXT or text.strip_edges() == "":
		return null
	var halves: PackedStringArray = text.split(":")
	if halves.size() > 2:
		return null
	var pick: String = halves[1].strip_edges() if halves.size() == 2 else PRIO_PICKS[0]
	if not PRIO_PICKS.has(pick):
		return null
	var order: Array[String] = []
	var off: Array[String] = []
	for tok in halves[0].split(","):
		var t: String = tok.strip_edges()
		var is_off: bool = t.begins_with("-")
		if is_off:
			t = t.substr(1).strip_edges()
		if not PRIO_TYPES.has(t) or order.has(t):
			return null
		order.append(t)
		if is_off:
			off.append(t)
	if order.size() != PRIO_TYPES.size():
		return null
	return {"order": order, "off": off, "pick": pick}


static func encode_priority(p: Dictionary) -> String:
	var parts := PackedStringArray()
	var off: Array = p.get("off", [])
	for t: String in p["order"]:
		parts.append(("-" if off.has(t) else "") + t)
	return "%s:%s" % [",".join(parts), p.get("pick", PRIO_PICKS[0])]


## The list `scope` ("rig" or a weapon kind) targets with: a weapon's own list (once Targeting Computer
## lets it have one), else the rig's.
static func priority_of(v: SimVehicle, scope: String) -> Dictionary:
	if scope != SCOPE_RIG and weapon_prio_unlocked(v) and weapon_has_own_priority(v, scope):
		return v.weapon_doctrine[scope]["prio"]
	return v.target_prio


## Does the weapon `kind` store a list of its own (unlocked or not)?
static func weapon_has_own_priority(v: SimVehicle, kind: String) -> bool:
	var d: Variant = v.weapon_doctrine.get(kind)
	if d == null:
		return false
	var p: Variant = (d as Dictionary).get("prio")
	return typeof(p) == TYPE_DICTIONARY and not (p as Dictionary).is_empty()


## Stores a list for the rig or a weapon; an empty dictionary on a weapon makes it follow the rig's list.
static func set_priority(v: SimVehicle, scope: String, p: Dictionary) -> void:
	if scope == SCOPE_RIG:
		if not p.is_empty():
			v.target_prio = p
	elif is_weapon_scope(scope):
		if p.is_empty():
			if v.weapon_doctrine.has(scope):
				var d0: Dictionary = (v.weapon_doctrine[scope] as Dictionary).duplicate()
				d0.erase("prio")
				v.weapon_doctrine[scope] = d0
			return
		var d: Dictionary = weapon_doc(v, scope).duplicate()
		d["prio"] = p
		v.weapon_doctrine[scope] = d


## Index into PRIO_TYPES of an alien kind (SimWorld.MITE ... BOSS_A+).
static func prio_index_of_kind(kind: int) -> int:
	if kind >= SimWorld.BOSS_A:
		return 0
	match kind:
		SimWorld.SHRIEKER:
			return 1
		SimWorld.SPITTER:
			return 2
		SimWorld.BROOD:
			return 3
		SimWorld.GLASS:
			return 4
		SimWorld.BOULDER:
			return 5
	return 6


# ---------------------------------------------------------------- evaluation

## Runs the rig's rules: sets v.eff_drive / v.eff_target, v.focus, the ability rule masks and v.rule_live
## (bit i = rule i matched). A rule with an unlocked-no-more item (after a respec) never runs. A juggernaut
## cannot back away: kite becomes circle and flee becomes charge.
static func apply_rig(w: SimWorld, v: SimVehicle) -> void:
	var drive: String = str(v.doctrine.get("drive", "circle"))
	var target: String = str(v.doctrine.get("target", "nearest"))
	var live: int = 0
	var clive: int = 0
	var got_drive: bool = false
	var got_target: bool = false
	var got_focus: bool = false
	var focus: bool = float(v.tech_fx.get("swarm_logic", 0.0)) > 0.0
	var ab_any: int = 0
	var ab_hit: int = 0
	var ctx := {}
	var n: int = mini(v.rules.size(), active_slots(v))
	for i in n:
		var r: Dictionary = v.rules[i]
		if rule_off(r) or (rule_any(r) and not any_unlocked(v)):
			continue
		var a: String = r["do"]
		var grp: String = action_group(a)
		if not action_unlocked(v, a):
			continue
		var abit: int = 0
		if grp == "ability":
			abit = 1 << Abilities.index_of(action_value(a))
			ab_any |= abit
		var cm: int = _cond_mask(w, v, r["if"], v.target_kind, v.target_index, v.target_id, v.target_pos, ctx)
		clive |= cm << (i * MAX_CONDS)
		if not _rule_hit(v, "rig:%d" % i, r, cm):
			continue
		live |= 1 << i
		if grp == "drive" and not got_drive:
			drive = action_value(a)
			got_drive = true
		elif grp == "target" and not got_target:
			target = action_value(a)
			got_target = true
		elif a == "fire:focus" and not got_focus:
			focus = true
			got_focus = true
		elif grp == "ability":
			ab_hit |= abit
	if Mobility.is_juggernaut(v):
		if drive == "kite":
			drive = "circle"
		elif drive == "flee":
			drive = "charge"
	v.eff_drive = drive
	v.eff_target = target
	v.focus = focus
	v.ab_rule_any = ab_any
	v.ab_rule_hit = ab_hit
	v.rule_live = live
	v.rule_conds = clive


## Runs a weapon's rules. Returns [target mode, hold fire?, wanted ammo id or ""] and stores the match
## mask in wp["live"]. An `ammo:<id>` action only counts while that ammo is unlocked.
## Target conditions look at the weapon's own target if it has one, else at the rig's.
static func apply_weapon(w: SimWorld, v: SimVehicle, wp: Dictionary) -> Array:
	var d: Dictionary = weapon_doc(v, str(wp["kind"]))
	var mode: String = d["target"]
	var hold: bool = false
	var ammo: String = ""
	var rules: Array = d["rules"]
	var live: int = 0
	var clive: int = 0
	if not rules.is_empty():
		var tk: int = int(wp.get("tk", 0))
		var ti: int = int(wp.get("ti", -1))
		var tid: int = int(wp.get("tid", -1))
		var tp: Vector2 = wp.get("tp", Vector2.ZERO)
		if tk == 0:
			tk = v.target_kind
			ti = v.target_index
			tid = v.target_id
			tp = v.target_pos
		var got_target: bool = false
		var got_fire: bool = false
		var got_ammo: bool = false
		var ctx := {}
		var n: int = mini(rules.size(), active_slots(v))
		for i in n:
			var r: Dictionary = rules[i]
			if rule_off(r) or (rule_any(r) and not any_unlocked(v)):
				continue
			var cm: int = _cond_mask(w, v, r["if"], tk, ti, tid, tp, ctx)
			clive |= cm << (i * MAX_CONDS)
			if not _rule_hit(v, "%s:%d" % [wp["kind"], i], r, cm):
				continue
			live |= 1 << i
			var a: String = r["do"]
			if action_group(a) == "target" and not got_target:
				mode = action_value(a)
				got_target = true
			elif action_group(a) == "fire" and not got_fire:
				hold = action_value(a) == "hold"
				got_fire = true
			elif action_group(a) == "ammo" and not got_ammo and Ammo.is_unlocked(v, action_value(a)):
				ammo = action_value(a)
				got_ammo = true
	wp["live"] = live
	wp["clive"] = clive
	return [mode, hold, ammo]


## Does the rule count as matched this tick? Its conditions hold (rule_matches_mask), or it was matched
## within the last `hold` seconds (hold needs the Targeting Computer). Host scratch: v.rule_hold.
static func _rule_hit(v: SimVehicle, key: String, rule: Dictionary, cm: int) -> bool:
	var h: int = rule_hold(rule) if hold_unlocked(v) else 0
	if rule_matches_mask(rule, cm):
		if h > 0:
			v.rule_hold[key] = h * HOLD_TICKS_PER_S
		return true
	if h > 0:
		var left: int = int(v.rule_hold.get(key, 0))
		if left > 0:
			v.rule_hold[key] = left - 1
			return true
	return false


static func _holds(w: SimWorld, v: SimVehicle, conds: Array, tk: int, ti: int, tid: int, tp: Vector2, ctx: Dictionary) -> bool:
	return _cond_mask(w, v, conds, tk, ti, tid, tp, ctx) == (1 << conds.size()) - 1


## Evaluates every condition of a rule (no short-circuit, pure: no rng, no state): bit j = condition j holds.
## The rule matches when all of its bits are set. `ctx` caches the world queries per tick.
static func _cond_mask(w: SimWorld, v: SimVehicle, conds: Array, tk: int, ti: int, tid: int, tp: Vector2, ctx: Dictionary) -> int:
	var mask: int = 0
	var j: int = 0
	for c: Array in conds:
		var x: float = _value(w, v, c[0], tk, ti, tid, tp, ctx)
		if not is_nan(x):  # a target condition without a target never holds
			var val: float = float(c[2])
			var ok: bool
			match str(c[1]):
				"<":
					ok = x < val
				">":
					ok = x > val
				_:
					ok = x == val
			if ok:
				mask |= 1 << j
		j += 1
	return mask


## The current value of condition `id` (NAN when it needs a target and there is none).
static func _value(w: SimWorld, v: SimVehicle, id: String, tk: int, ti: int, tid: int, tp: Vector2, ctx: Dictionary) -> float:
	match id:
		"hp":
			return 100.0 * v.hp / maxf(v.max_hp, 1.0)
		"swarm", "boulders", "mites":
			if not ctx.has("swarm"):
				var near: int = w.query_enemies(v.pos, SWARM_RADIUS, w.ai_buf)
				var rocks: int = 0
				var mites: int = 0
				for q in near:
					var e: int = w.ai_buf[q]
					if w.enemy_hp[e] <= 0.0:
						continue
					if w.enemy_kind[e] == SimWorld.BOULDER:
						rocks += 1
					elif w.enemy_kind[e] == SimWorld.MITE:
						mites += 1
				ctx["swarm"] = near
				ctx["boulders"] = rocks
				ctx["mites"] = mites
			if id == "boulders" and not cond_unlocked(v, id):
				return NAN
			return float(ctx[id])
		"spitters", "flyers":
			if not ctx.has("spitters"):
				var sn: int = w.query_enemies(v.pos, SPECIES_RADIUS, w.ai_buf)
				var sp: int = 0
				var fl: int = 0
				var r2: float = SPECIES_RADIUS * SPECIES_RADIUS
				for q in sn:
					var e2: int = w.ai_buf[q]
					if w.enemy_hp[e2] <= 0.0 or v.pos.distance_squared_to(w.enemy_pos[e2]) > r2:
						continue
					if w.enemy_kind[e2] == SimWorld.SPITTER:
						sp += 1
					elif w.enemy_kind[e2] == SimWorld.GLASS:
						fl += 1
				ctx["spitters"] = sp
				ctx["flyers"] = fl
			return float(ctx[id])
		"momentum":
			return v.momentum
		"round_time":
			if not cond_unlocked(v, id):
				return NAN
			if w.phase != SimWorld.PHASE_COMBAT:
				return 0.0
			return float(w.combat_duration(w.round) - w.phase_ticks_left) / float(HOLD_TICKS_PER_S)
		"under_fire":
			if not cond_unlocked(v, id):
				return NAN
			return 1.0 if v.hurt_ticks > 0 else 0.0
		"fuel":
			return float(v.fuel) if cond_unlocked(v, id) else NAN
		"rival_weaker":
			if not cond_unlocked(v, id):
				return NAN
			var mine: float = v.hp / maxf(v.max_hp, 1.0)
			if w.pvp_enabled():
				for o in w.vehicles:
					if o.id != v.id and o.alive and o.invuln_ticks <= 0 and o.hp / maxf(o.max_hp, 1.0) < mine \
							and v.pos.distance_squared_to(o.pos) <= RIVAL_RADIUS * RIVAL_RADIUS:
						return 1.0
			return 0.0
		"ability_ready":
			if not cond_unlocked(v, id):
				return NAN
			return 1.0 if Abilities.any_ready(v) else 0.0
		"rivals":
			if not ctx.has("rivals"):
				var n: int = 0
				if w.pvp_enabled():
					for o in w.vehicles:
						if o.id != v.id and o.alive and o.invuln_ticks <= 0 and v.pos.distance_squared_to(o.pos) <= RIVAL_RADIUS * RIVAL_RADIUS:
							n += 1
				ctx["rivals"] = n
			return float(ctx["rivals"])
		"pvp":
			return 1.0 if w.pvp_enabled() else 0.0
		"has_target":
			return 1.0 if tk != 0 else 0.0
		"boss_active":
			return 1.0 if w.boss_state == Bosses.ST_ACTIVE else 0.0
		"mark_active":
			return 1.0 if Orders.active(w, v) else 0.0
		"radio_active":
			return 1.0 if Orders.radio_active(v) else 0.0
		"in_zone":
			return 1.0 if w.zones_active and Zones.zone_at(w, v.pos) >= 0 else 0.0
		"zone_dist":
			var zd: float = Zones.nearest_unheld_dist(w, v)
			return NAN if zd < 0.0 else zd
		"zone_contested":
			return 1.0 if Zones.contested_for(w, v) else 0.0
		"zones_held":
			return float(Zones.held_by(w, v)) if w.zones_active else 0.0
		"shrieker_near":
			if not ctx.has("shrieker_near"):
				ctx["shrieker_near"] = Species.shrieker_near(w, v)
			return 1.0 if ctx["shrieker_near"] else 0.0
	if tk == 0:
		return NAN
	match id:
		"t_dist":
			return v.pos.distance_to(tp)
		"t_hp":
			if tk == 1:
				if ti < 0 or ti >= w.enemy_count:
					return NAN
				return 100.0 * w.enemy_hp[ti] / maxf(w.enemy_max_hp_of(ti), 1.0)
			var t: SimVehicle = w.vehicles[tid]
			return 100.0 * t.hp / maxf(t.max_hp, 1.0)
		"t_player":
			return 1.0 if tk == 2 else 0.0
		"t_leader":
			if not cond_unlocked(v, id):
				return NAN
			return 1.0 if tk == 2 and tid >= 0 and tid < w.vehicles.size() and w.vehicles[tid].peer_id == w.leader_peer else 0.0
		"t_boulder", "t_spitter", "t_mite", "t_glass", "t_brood", "t_shrieker", "t_boss":
			if tk != 1 or ti < 0 or ti >= w.enemy_count:
				return 0.0
			var ek: int = w.enemy_kind[ti]
			match id:
				"t_boulder":
					return 1.0 if ek == SimWorld.BOULDER else 0.0
				"t_spitter":
					return 1.0 if ek == SimWorld.SPITTER else 0.0
				"t_mite":
					return 1.0 if ek == SimWorld.MITE else 0.0
				"t_glass":
					return 1.0 if ek == SimWorld.GLASS else 0.0
				"t_brood":
					return 1.0 if ek == SimWorld.BROOD else 0.0
				"t_shrieker":
					return 1.0 if ek == SimWorld.SHRIEKER else 0.0
				_:
					return 1.0 if ek >= SimWorld.BOSS_A else 0.0
	return NAN
