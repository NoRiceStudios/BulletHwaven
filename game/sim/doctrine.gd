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
## Text form (commands, tests, tools): rules joined by ";", each "cond&cond|action", a condition
## "id<n", "id>n" or "id=0/1" (flags). Example: "hp<30|drive:flee;swarm>20&t_dist<120|drive:charge".
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

## Index tables for the binary form. Only append.
const COND_IDS: PackedStringArray = ["hp", "swarm", "rivals", "t_dist", "t_hp", "t_player", "t_boulder", "t_spitter", "pvp", "has_target",
	"boulders", "fuel", "rival_weaker", "ability_ready", "t_leader", "boss_active", "shrieker_near", "mark_active", "radio_active"]
const OPS: PackedStringArray = ["<", ">", "="]
const ACTIONS: PackedStringArray = [
	"drive:circle", "drive:kite", "drive:charge", "drive:flee", "drive:hold",
	"target:nearest", "target:strongest", "target:weakest", "target:players_first", "target:boulders",
	"target:spitters", "target:follow", "fire:hold", "fire:free",
	"ammo:fire", "ammo:shrapnel", "ammo:ap",
	"fire:focus", "ability:nitro", "ability:emp", "ability:smoke", "ability:salvo",
	"target:boss", "target:shriekers",
]

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
}
## Conditions the tech tree unlocks: condition id -> tech fx key (anything else is always available).
const COND_FX := {
	"boulders": "cond_boulders", "fuel": "cond_fuel", "rival_weaker": "cond_rival_weaker",
	"ability_ready": "cond_ability_ready", "t_leader": "cond_t_leader",
}

const DRIVES: PackedStringArray = ["circle", "kite", "charge", "flee", "hold"]
const BASE_DRIVES: PackedStringArray = ["circle", "kite", "charge"]  ## base doctrine (set_drive)
const RIG_TARGETS: PackedStringArray = ["nearest", "strongest", "weakest", "players_first", "boulders", "spitters", "boss", "shriekers"]
const WEAPON_TARGETS: PackedStringArray = ["follow", "nearest", "strongest", "weakest", "players_first", "boulders", "spitters", "boss", "shriekers"]


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


## False if a parsed rule list uses something `v` has not unlocked (conditions, `ammo:<id>`, `fire:focus`,
## `ability:<id>`, kite / flee as a juggernaut) or more conditions per rule than it may.
static func rules_allowed(v: SimVehicle, rules: Array) -> bool:
	var cmax: int = max_conds(v)
	for r: Dictionary in rules:
		if not action_unlocked(v, r["do"]):
			return false
		var conds: Array = r["if"]
		if conds.size() > cmax:
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
		if not allowed.has(action):
			return null
		var conds: Array = []
		var ctext: String = halves[0].strip_edges()
		if ctext != "":
			for c in ctext.split("&"):
				var cond: Variant = _parse_cond(c.strip_edges())
				if cond == null:
					return null
				conds.append(cond)
		if conds.size() > MAX_CONDS:
			return null
		rules.append({"if": conds, "do": action})
	if rules.size() > MAX_SLOTS:
		return null
	return rules


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
		parts.append("%s|%s" % ["&".join(cs), r["do"]])
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


static func set_weapon_target(v: SimVehicle, kind: String, mode: String) -> void:
	if not is_weapon_scope(kind) or not WEAPON_TARGETS.has(mode):
		return
	var d: Dictionary = weapon_doc(v, kind).duplicate()
	d["target"] = mode
	v.weapon_doctrine[kind] = d


## Stable text of everything programmable on `v` (checksums, tests).
static func fingerprint(v: SimVehicle) -> String:
	var s: String = encode(v.rules)
	var kinds: Array = v.weapon_doctrine.keys()
	kinds.sort()
	for k: String in kinds:
		var d: Dictionary = v.weapon_doctrine[k]
		s += "#%s:%s:%s" % [k, d["target"], encode(d["rules"])]
	return s


# ---------------------------------------------------------------- evaluation

## Runs the rig's rules: sets v.eff_drive / v.eff_target, v.focus, the ability rule masks and v.rule_live
## (bit i = rule i matched). A rule with an unlocked-no-more item (after a respec) never runs. A juggernaut
## cannot back away: kite becomes circle and flee becomes charge.
static func apply_rig(w: SimWorld, v: SimVehicle) -> void:
	var drive: String = str(v.doctrine.get("drive", "circle"))
	var target: String = str(v.doctrine.get("target", "nearest"))
	var live: int = 0
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
		var a: String = r["do"]
		var grp: String = action_group(a)
		if not action_unlocked(v, a):
			continue
		var abit: int = 0
		if grp == "ability":
			abit = 1 << Abilities.index_of(action_value(a))
			ab_any |= abit
		if not _holds(w, v, r["if"], v.target_kind, v.target_index, v.target_id, v.target_pos, ctx):
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
			if not _holds(w, v, r["if"], tk, ti, tid, tp, ctx):
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
	return [mode, hold, ammo]


static func _holds(w: SimWorld, v: SimVehicle, conds: Array, tk: int, ti: int, tid: int, tp: Vector2, ctx: Dictionary) -> bool:
	for c: Array in conds:
		var id: String = c[0]
		var x: float = _value(w, v, id, tk, ti, tid, tp, ctx)
		if is_nan(x):
			return false  # a target condition without a target never holds
		var val: float = float(c[2])
		match str(c[1]):
			"<":
				if not x < val:
					return false
			">":
				if not x > val:
					return false
			_:
				if x != val:
					return false
	return true


## The current value of condition `id` (NAN when it needs a target and there is none).
static func _value(w: SimWorld, v: SimVehicle, id: String, tk: int, ti: int, tid: int, tp: Vector2, ctx: Dictionary) -> float:
	match id:
		"hp":
			return 100.0 * v.hp / maxf(v.max_hp, 1.0)
		"swarm", "boulders":
			if not ctx.has("swarm"):
				var near: int = w.query_enemies(v.pos, SWARM_RADIUS, w.ai_buf)
				var rocks: int = 0
				for q in near:
					var e: int = w.ai_buf[q]
					if w.enemy_kind[e] == SimWorld.BOULDER and w.enemy_hp[e] > 0.0:
						rocks += 1
				ctx["swarm"] = near
				ctx["boulders"] = rocks
			if id == "boulders" and not cond_unlocked(v, id):
				return NAN
			return float(ctx[id])
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
		"t_boulder", "t_spitter":
			if tk != 1 or ti < 0 or ti >= w.enemy_count:
				return 0.0
			var want: int = SimWorld.BOULDER if id == "t_boulder" else SimWorld.SPITTER
			return 1.0 if w.enemy_kind[ti] == want else 0.0
	return NAN
