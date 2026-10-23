class_name Tech
extends RefCounted
## Tech tree data (tech tree v2.3, design doc section 5b). Pure data plus static helpers.
##
## Shape: 5 branches of 6 stages. Stage 1 is the branch's core, stage 2 a pick-one style, stage 3 a
## core (needed for stage 4) plus an optional prototype with a fixed drawback that opens nothing,
## stage 4 a pick-one specialisation, stage 5 a pick-one mastery, stage 6 a pick-one keystone.
## 61 branch nodes plus 11 fusions (6 small, 5 large) that join two stage 2 / 4 choices of
## different branches.
##
## Entry fields: id, branch ("fusion" for fusions), tier (1..6, 0 for fusions), kind ("core",
## "choice", "proto", "fusion_s", "fusion_l"), name, short (label for small nodes), fx and the
## fields filled in by `_ensure_index()`: cost, requires (ids that must ALL be active), any (at
## least one of these must be active), group (exclusive choice group = branch + tier, "" = none).
## Tech ids travel in snapshots as indices into `DEFS`, so only ever append to the table.
##
## Requirement rules: a tier N > 1 node needs any owned non-proto node of tier N-1 of its branch
## (`any`), tier 4 choices need the tier 3 core, `engineering_war_rig` needs `engineering_truck`
## (chassis chain), fusions need their two ids. Nodes of one choice group exclude each other.
##
## Owned versus active: only ACTIVE nodes (owned and every requirement active) apply their fx. A
## respec can leave a node owned but inactive (War Rig after Truck was swapped for the Roll Cage);
## it works again for free once the requirement is back. Fusions that lose a requirement move to
## `v.tech_dormant`; buying one again costs half (`price()`).
##
## fx keys: see `Cards.recompute()` (stats; every active key is also summed into `v.tech_fx`). The
## one-off `fuel` grant is paid out by buy().

const BRANCHES: PackedStringArray = ["ballistics", "engineering", "propulsion", "electronics", "salvage"]
const STAGE_COSTS: PackedInt32Array = [100, 140, 240, 380, 520, 750]
const PROTO_COST := 180
const SMALL_FUSION_COST := 200
const LARGE_FUSION_COST := 450
const MAX_TIER := 6
const REBUY_PCT := 50  ## dormant fusion: percent of the price to buy it again
const RESPEC_FEE_PCT := 50  ## extra percent of the new node's price per respec after the first (free) one
const KEYSTONE_RESPEC_ROUNDS := 1  ## a tier 6 choice can be swapped until bought_round + this

const DEFS: Array = [
	# ---- ballistics
	{"id": "ballistics_ammo_bench", "branch": "ballistics", "tier": 1, "kind": "core", "name": "Ammo Bench", "short": "AMMO BENCH",
		"fx": {"ammo_fire": 1}},
	{"id": "ballistics_belt_feed", "branch": "ballistics", "tier": 2, "kind": "choice", "name": "Belt Feed", "short": "BELT FEED",
		"fx": {"rate": 0.2, "rate_mg": 0.1, "rate_flamer": 0.1, "ammo_shrapnel": 1}},
	{"id": "ballistics_heavy_shells", "branch": "ballistics", "tier": 2, "kind": "choice", "name": "Heavy Shells", "short": "HEAVY",
		"fx": {"dmg": 0.15, "dmg_cannon": 0.1, "dmg_shotgun": 0.1, "ammo_ap": 1}},
	{"id": "ballistics_tables", "branch": "ballistics", "tier": 3, "kind": "core", "name": "Ballistic Tables", "short": "TABLES",
		"fx": {"dmg": 0.12, "ammo_instant": 1, "ammo_fx": 0.25}},
	{"id": "ballistics_hot_loads", "branch": "ballistics", "tier": 3, "kind": "proto", "name": "Hot Loads", "short": "HOT LOADS",
		"fx": {"dmg": 0.35, "jam": 1}},
	{"id": "ballistics_scatter", "branch": "ballistics", "tier": 4, "kind": "choice", "name": "Scatter Packing", "short": "SCATTER",
		"fx": {"pellets_shotgun": 2, "scatter": 1}},
	{"id": "ballistics_napalm", "branch": "ballistics", "tier": 4, "kind": "choice", "name": "Napalm Mix", "short": "NAPALM",
		"fx": {"napalm": 30}},
	{"id": "ballistics_he", "branch": "ballistics", "tier": 4, "kind": "choice", "name": "HE Shells", "short": "HE SHELLS",
		"fx": {"splash_cannon": 14.0, "burn_bonus": 0.15}},
	{"id": "ballistics_tungsten", "branch": "ballistics", "tier": 5, "kind": "choice", "name": "Tungsten Stock", "short": "TUNGSTEN",
		"fx": {"dmg": 0.15, "pierce": 1, "ember": 1}},
	{"id": "ballistics_mixed_belts", "branch": "ballistics", "tier": 5, "kind": "choice", "name": "Mixed Belts", "short": "MIXED",
		"fx": {"mixed_belts": 1}},
	{"id": "ballistics_glowing", "branch": "ballistics", "tier": 6, "kind": "choice", "name": "Glowing Barrels", "short": "GLOWING",
		"fx": {"rate": 0.6, "overheat": 1}},
	{"id": "ballistics_one_shot", "branch": "ballistics", "tier": 6, "kind": "choice", "name": "One Shot, One Kill", "short": "ONE SHOT",
		"fx": {"dmg": 1.0, "rate": -0.15, "execute": 0.3}},
	# ---- engineering
	{"id": "engineering_frame", "branch": "engineering", "tier": 1, "kind": "core", "name": "Welded Frame", "short": "FRAME",
		"fx": {"hp": 40.0, "armor": 1.0}},
	{"id": "engineering_spikes", "branch": "engineering", "tier": 2, "kind": "choice", "name": "Spike Skirts", "short": "SPIKES",
		"fx": {"contact": 0.5, "thorns": 0.4, "creduce": 0.08}},
	{"id": "engineering_welder", "branch": "engineering", "tier": 2, "kind": "choice", "name": "Field Welder", "short": "WELDER",
		"fx": {"regen": 3.0}},
	{"id": "engineering_pickup", "branch": "engineering", "tier": 3, "kind": "core", "name": "Pickup Chassis", "short": "PICKUP",
		"fx": {"chassis": 2, "slots": 1, "hp": 80.0, "speed": -0.05}},
	{"id": "engineering_scrap_armour", "branch": "engineering", "tier": 3, "kind": "proto", "name": "Scrap Armour", "short": "SCRAP ARMOUR",
		"fx": {"armor": 3.0, "armor_shed": 1}},
	{"id": "engineering_reactive", "branch": "engineering", "tier": 4, "kind": "choice", "name": "Reactive Plates", "short": "REACTIVE",
		"fx": {"armor": 2.5, "blast_resist": 0.3}},
	{"id": "engineering_drone", "branch": "engineering", "tier": 4, "kind": "choice", "name": "Repair Drone", "short": "DRONE",
		"fx": {"regen": 4.0, "drone": 1}},
	{"id": "engineering_dozer", "branch": "engineering", "tier": 4, "kind": "choice", "name": "Dozer Blade", "short": "DOZER",
		"fx": {"creduce": 0.15, "ram": 0.3, "dozer": 1}},
	{"id": "engineering_truck", "branch": "engineering", "tier": 5, "kind": "choice", "name": "Truck Chassis", "short": "TRUCK",
		"fx": {"chassis": 3, "hp": 200.0, "speed": -0.06, "range": 0.12}},
	{"id": "engineering_roll_cage", "branch": "engineering", "tier": 5, "kind": "choice", "name": "Roll Cage", "short": "ROLL CAGE",
		"fx": {"armor": 3.0, "speed_penalty_half": 1, "knock_immune": 1}},
	{"id": "engineering_war_rig", "branch": "engineering", "tier": 6, "kind": "choice", "requires": ["engineering_truck"], "name": "War Rig", "short": "WAR RIG",
		"fx": {"chassis": 4, "slots": 1, "hp": 350.0, "speed": -0.08, "turn": -0.15}},
	{"id": "engineering_featherweight", "branch": "engineering", "tier": 6, "kind": "choice", "name": "Featherweight", "short": "FEATHER",
		"fx": {"no_speed_penalty": 1, "speed": 0.2, "slots": 1, "dodge": 0.1, "hp_pct": -0.15}},
	# ---- propulsion
	{"id": "propulsion_tuned", "branch": "propulsion", "tier": 1, "kind": "core", "name": "Tuned Engine", "short": "TUNED",
		"fx": {"speed": 0.08, "momentum": 1, "momentum_ram": 0.5}},
	{"id": "propulsion_bumper", "branch": "propulsion", "tier": 2, "kind": "choice", "name": "Ram Bumper", "short": "BUMPER",
		"fx": {"ram": 0.35, "ram_free": 1, "sparks": 1}},
	{"id": "propulsion_drift", "branch": "propulsion", "tier": 2, "kind": "choice", "name": "Drift Tuning", "short": "DRIFT",
		"fx": {"turn": 0.25, "speed": 0.05, "drift_momentum": 1}},
	{"id": "propulsion_nitro", "branch": "propulsion", "tier": 3, "kind": "core", "name": "Nitro Injector", "short": "NITRO",
		"fx": {"ability_nitro": 1}},
	{"id": "propulsion_dirty_fuel", "branch": "propulsion", "tier": 3, "kind": "proto", "name": "Dirty Fuel", "short": "DIRTY FUEL",
		"fx": {"dirty_fuel": 1}},
	{"id": "propulsion_battering", "branch": "propulsion", "tier": 4, "kind": "choice", "name": "Battering Ram", "short": "BATTER",
		"fx": {"ram": 0.45, "knockback": 1}},
	{"id": "propulsion_ghost", "branch": "propulsion", "tier": 4, "kind": "choice", "name": "Ghost Runner", "short": "GHOST",
		"fx": {"ghost": 0.2}},
	{"id": "propulsion_slipstream", "branch": "propulsion", "tier": 4, "kind": "choice", "name": "Slipstream", "short": "SLIPSTREAM",
		"fx": {"slipstream": 1}},
	{"id": "propulsion_turbine", "branch": "propulsion", "tier": 5, "kind": "choice", "name": "Turbine Swap", "short": "TURBINE",
		"fx": {"speed": 0.12, "hp": 60.0, "momentum_decay_half": 1, "turbine_boom": 1}},
	{"id": "propulsion_sidecar", "branch": "propulsion", "tier": 5, "kind": "choice", "name": "Sidecar Gunner", "short": "SIDECAR",
		"fx": {"slots": 1, "sidecar": 1}},
	{"id": "propulsion_juggernaut", "branch": "propulsion", "tier": 6, "kind": "choice", "name": "Juggernaut", "short": "JUGGERNAUT",
		"fx": {"juggernaut": 1}},
	{"id": "propulsion_phantom", "branch": "propulsion", "tier": 6, "kind": "choice", "name": "Phantom Drive", "short": "PHANTOM",
		"fx": {"phantom": 1, "hp_pct": -0.2}},
	# ---- electronics
	{"id": "electronics_rangefinder", "branch": "electronics", "tier": 1, "kind": "core", "name": "Rangefinder", "short": "RANGEFINDER",
		"fx": {"rule_slots": 1, "cond_boulders": 1, "logic_any": 1, "laser": 1, "dmg": 0.08}},
	{"id": "electronics_radar", "branch": "electronics", "tier": 2, "kind": "choice", "name": "Radar Array", "short": "RADAR",
		"fx": {"cond_fuel": 1, "cond_rival_weaker": 1, "cond_under_fire": 1, "cond_round_time": 1, "scout_rules": 1, "spit_warn": 1}},
	{"id": "electronics_relay", "branch": "electronics", "tier": 2, "kind": "choice", "name": "Fire Control Relay", "short": "RELAY",
		"fx": {"rate": 0.15, "act_focus": 1}},
	{"id": "electronics_targeting", "branch": "electronics", "tier": 3, "kind": "core", "name": "Targeting Computer", "short": "TARGETING",
		"fx": {"rule_slots": 1, "max_conds": 1, "cond_ability_ready": 1, "logic_hold": 1, "prio_weapon": 1, "dmg": 0.08}},
	{"id": "electronics_aux_mount", "branch": "electronics", "tier": 3, "kind": "proto", "name": "Auxiliary Mount", "short": "AUX MOUNT",
		"fx": {"slots": 1, "range": -0.1}},
	{"id": "electronics_emp", "branch": "electronics", "tier": 4, "kind": "choice", "name": "EMP Pulse", "short": "EMP",
		"fx": {"ability_emp": 1}},
	{"id": "electronics_smoke", "branch": "electronics", "tier": 4, "kind": "choice", "name": "Smoke Launcher", "short": "SMOKE",
		"fx": {"ability_smoke": 1}},
	{"id": "electronics_hunter", "branch": "electronics", "tier": 4, "kind": "choice", "name": "Hunter-Killer Logic", "short": "HUNTER",
		"fx": {"vulture": 0.2, "cond_t_leader": 1}},
	{"id": "electronics_neural", "branch": "electronics", "tier": 5, "kind": "choice", "name": "Neural Fire Control", "short": "NEURAL",
		"fx": {"rule_slots": 1, "ability_salvo": 1}},
	{"id": "electronics_overclock", "branch": "electronics", "tier": 5, "kind": "choice", "name": "Overclock", "short": "OVERCLOCK",
		"fx": {"ability_cd": -0.3, "range": -0.05}},
	{"id": "electronics_swarm", "branch": "electronics", "tier": 6, "kind": "choice", "name": "Swarm Logic", "short": "SWARM",
		"fx": {"swarm_logic": 0.35}},
	{"id": "electronics_jammer", "branch": "electronics", "tier": 6, "kind": "choice", "name": "Jammer", "short": "JAMMER",
		"fx": {"jammer": 200, "range": -0.1}},
	# ---- salvage
	{"id": "salvage_hooks", "branch": "salvage", "tier": 1, "kind": "core", "name": "Scrap Hooks", "short": "HOOKS",
		"fx": {"scrap": 0.06, "contracts": 1}},
	{"id": "salvage_haggler", "branch": "salvage", "tier": 2, "kind": "choice", "name": "Haggler", "short": "HAGGLER",
		"fx": {"reroll": 3, "reserve_card": 1}},
	{"id": "salvage_lucky", "branch": "salvage", "tier": 2, "kind": "choice", "name": "Lucky Charm", "short": "LUCKY",
		"fx": {"luck": 0.6, "contract_bonus": 0.25}},
	{"id": "salvage_loan", "branch": "salvage", "tier": 2, "kind": "choice", "name": "Loan Shark", "short": "LOAN",
		"fx": {"loan": 1}},
	{"id": "salvage_black_market", "branch": "salvage", "tier": 3, "kind": "core", "name": "Black Market", "short": "BLACK MKT",
		"fx": {"interest": 4, "contracts": 1}},
	{"id": "salvage_insurance", "branch": "salvage", "tier": 3, "kind": "proto", "name": "Insurance Fraud", "short": "INSURANCE",
		"fx": {"insurance": 60, "hp_pct": -0.1}},
	{"id": "salvage_jerrycans", "branch": "salvage", "tier": 4, "kind": "choice", "name": "Spare Jerrycans", "short": "JERRYCAN",
		"fx": {"fuel": 15, "fuel_per_contract": 1, "jerry_blast": 1}},
	{"id": "salvage_press", "branch": "salvage", "tier": 4, "kind": "choice", "name": "Scrap Press", "short": "PRESS",
		"fx": {"scrap_press": 1}},
	{"id": "salvage_hoarder", "branch": "salvage", "tier": 4, "kind": "choice", "name": "Hoarder", "short": "HOARDER",
		"fx": {"hoarder": 1}},
	{"id": "salvage_crane", "branch": "salvage", "tier": 5, "kind": "choice", "name": "Salvage Crane", "short": "CRANE",
		"fx": {"scrap": 0.12, "contract_bonus": 0.2}},
	{"id": "salvage_bounty", "branch": "salvage", "tier": 5, "kind": "choice", "name": "Bounty Office", "short": "BOUNTY",
		"fx": {"bounty_office": 1}},
	{"id": "salvage_baron", "branch": "salvage", "tier": 6, "kind": "choice", "name": "Scrap Baron", "short": "BARON",
		"fx": {"baron": 1}},
	{"id": "salvage_raider", "branch": "salvage", "tier": 6, "kind": "choice", "name": "Raider", "short": "RAIDER",
		"fx": {"raider": 1, "contracts_max": 1}},

	# ---- fusions (small, then large)
	{"id": "fusion_thermite", "branch": "fusion", "tier": 0, "kind": "fusion_s", "requires": ["propulsion_bumper", "ballistics_belt_feed"], "name": "Thermite Ram", "short": "THERMITE",
		"fx": {"thermite": 1}},
	{"id": "fusion_spotter", "branch": "fusion", "tier": 0, "kind": "fusion_s", "requires": ["electronics_radar", "ballistics_heavy_shells"], "name": "Spotter", "short": "SPOTTER",
		"fx": {"spotter": 0.5}},
	{"id": "fusion_hot_rod", "branch": "fusion", "tier": 0, "kind": "fusion_s", "requires": ["propulsion_drift", "engineering_welder"], "name": "Hot Rod", "short": "HOT ROD",
		"fx": {"drift_regen": 10}},
	{"id": "fusion_barbed", "branch": "fusion", "tier": 0, "kind": "fusion_s", "requires": ["engineering_spikes", "salvage_haggler"], "name": "Barbed Wire", "short": "BARBED",
		"fx": {"barbed": 3}},
	{"id": "fusion_lucky_strike", "branch": "fusion", "tier": 0, "kind": "fusion_s", "requires": ["salvage_lucky", "electronics_relay"], "name": "Lucky Strike", "short": "LUCKY STRIKE",
		"fx": {"lucky_strike": 0.02}},
	{"id": "fusion_fortified", "branch": "fusion", "tier": 0, "kind": "fusion_s", "requires": ["engineering_welder", "electronics_relay"], "name": "Fortified Relay", "short": "FORTIFIED",
		"fx": {"fortified": 2}},
	{"id": "fusion_burning_wake", "branch": "fusion", "tier": 0, "kind": "fusion_l", "requires": ["ballistics_napalm", "propulsion_drift"], "name": "Burning Wake", "short": "BURN WAKE",
		"fx": {"burning_wake": 1}},
	{"id": "fusion_war_machine", "branch": "fusion", "tier": 0, "kind": "fusion_l", "requires": ["propulsion_battering", "engineering_spikes"], "name": "War Machine", "short": "WAR MACHINE",
		"fx": {"war_machine": 1}},
	{"id": "fusion_scrap_storm", "branch": "fusion", "tier": 0, "kind": "fusion_l", "requires": ["salvage_press", "ballistics_heavy_shells"], "name": "Scrap Storm", "short": "SCRAP STORM",
		"fx": {"scrap_storm": 1}},
	{"id": "fusion_junkyard", "branch": "fusion", "tier": 0, "kind": "fusion_l", "requires": ["engineering_drone", "electronics_relay"], "name": "Junkyard Drone", "short": "JUNKYARD",
		"fx": {"junkyard": 1}},
	{"id": "fusion_thunderclap", "branch": "fusion", "tier": 0, "kind": "fusion_l", "requires": ["electronics_emp", "engineering_spikes"], "name": "Thunderclap", "short": "THUNDER",
		"fx": {"thunderclap": 1}},
]

static var _index: Dictionary = {}
static var _full: Array = []  # DEFS with cost / requires / any / group filled in


static func count() -> int:
	return DEFS.size()


static func _ensure_index() -> void:
	if not _index.is_empty():
		return
	for i in DEFS.size():
		var d: Dictionary = (DEFS[i] as Dictionary).duplicate(true)
		var kind: String = str(d["kind"])
		var tier: int = int(d["tier"])
		var b: String = str(d["branch"])
		d["short"] = str(d.get("short", d["name"])).to_upper()
		d["group"] = "%s_%d" % [b, tier] if kind == "choice" else ""
		match kind:
			"proto": d["cost"] = PROTO_COST
			"fusion_s": d["cost"] = SMALL_FUSION_COST
			"fusion_l": d["cost"] = LARGE_FUSION_COST
			_: d["cost"] = STAGE_COSTS[tier - 1]
		_full.append(d)
		_index[str(d["id"])] = i
	# Requirements need the whole table (the any-of lists name the previous tier's nodes).
	for d: Dictionary in _full:
		var kind2: String = str(d["kind"])
		var tier2: int = int(d["tier"])
		var b2: String = str(d["branch"])
		var req: Array = d.get("requires", [])
		var any: Array = []
		if req.is_empty() and kind2 != "fusion_s" and kind2 != "fusion_l" and tier2 > 1:
			if tier2 == 4:
				req = [_core3(b2)]
			else:
				for o: Dictionary in _full:
					if o["branch"] == b2 and int(o["tier"]) == tier2 - 1 and o["kind"] != "proto":
						any.append(str(o["id"]))
		d["requires"] = req
		d["any"] = any


static func _core3(b: String) -> String:
	for d: Dictionary in DEFS:
		if d["branch"] == b and int(d["tier"]) == 3 and d["kind"] == "core":
			return str(d["id"])
	return ""


## Table index of a tech id, or -1 if unknown.
static func index_of(id: String) -> int:
	_ensure_index()
	return int(_index.get(id, -1))


static func has(id: String) -> bool:
	return index_of(id) >= 0


static func id_at(i: int) -> String:
	if i < 0 or i >= DEFS.size():
		return ""
	return str((DEFS[i] as Dictionary)["id"])


## The table entry for `id` with all fields filled in ({} if unknown). Do not modify it.
static func def(id: String) -> Dictionary:
	var i: int = index_of(id)
	return _full[i] if i >= 0 else {}


## Ids of a branch's nodes of `kind` ("core", "choice", "proto", "fusion_s", "fusion_l"; "" = any),
## branch "" = any, in table order.
static func ids(branch: String = "", kind: String = "") -> Array[String]:
	_ensure_index()
	var out: Array[String] = []
	for d: Dictionary in _full:
		if (branch == "" or d["branch"] == branch) and (kind == "" or d["kind"] == kind):
			out.append(str(d["id"]))
	return out


## The choice nodes of `tier` of `branch` (one exclusive group).
static func choices(branch: String, tier: int) -> Array[String]:
	var out: Array[String] = []
	for id in ids(branch, "choice"):
		if int(def(id)["tier"]) == tier:
			out.append(id)
	return out


## All fusion ids (small first, as in the table).
static func fusions() -> Array[String]:
	var out: Array[String] = ids("", "fusion_s")
	out.append_array(ids("", "fusion_l"))
	return out


static func is_fusion(id: String) -> bool:
	return str(def(id).get("branch", "")) == "fusion"


## Fusions that use `id` as one of their two parts ("Fusion possible with" in the tooltip); the
## other part is `requirements(fusion)` minus `id`.
static func fusion_partners(id: String) -> Array[String]:
	var out: Array[String] = []
	for f in fusions():
		if (def(f)["requires"] as Array).has(id):
			out.append(f)
	return out


## Base price of `id` (what a respec refunds). What a vehicle pays is `price()`.
static func cost(id: String) -> int:
	var d: Dictionary = def(id)
	return int(d["cost"]) if not d.is_empty() else 0


## What `v` pays for `id` now: the base price, half for a dormant fusion.
static func price(v: SimVehicle, id: String) -> int:
	if v.tech_dormant.has(id):
		return cost(id) * REBUY_PCT / 100
	return cost(id)


## Ids that matter for `id` (display / path walking): the explicit requirements, else the any-of
## candidates.
static func requirements(id: String) -> Array:
	var d: Dictionary = def(id)
	if d.is_empty():
		return []
	var req: Array = d["requires"]
	return req if not req.is_empty() else d["any"]


## The first required id ("" for tier 1 or unknown ids). See also missing().
static func prerequisite(id: String) -> String:
	var req: Array = requirements(id)
	return str(req[0]) if not req.is_empty() else ""


## Owned and every requirement active (see the header). Only active nodes apply their fx.
static func active(v: SimVehicle, id: String) -> bool:
	return v.tech.has(id) and missing(v, id) == ""


## The first requirement of `id` that is not active for `v` ("" = none missing); for an any-of
## requirement the first candidate when none is active. Walks down at most 6 tiers.
static func missing(v: SimVehicle, id: String) -> String:
	var d: Dictionary = def(id)
	if d.is_empty():
		return ""
	for r in d["requires"]:
		if not active(v, str(r)):
			return str(r)
	var any: Array = d["any"]
	if not any.is_empty():
		for a in any:
			if active(v, str(a)):
				return ""
		return str(any[0])
	return ""


## The node `v` has to buy first on the way to `id`: follows missing requirements down to one
## whose own requirements are met (`id` itself when nothing is missing).
static func next_step(v: SimVehicle, id: String) -> String:
	var cur: String = id
	for _i in 16:
		var m: String = missing(v, cur)
		if m == "":
			return cur
		cur = m
	return cur


## The owned node that locks `id` out (same exclusive group), or "".
static func blocked_by(v: SimVehicle, id: String) -> String:
	var g: String = str(def(id).get("group", ""))
	if g == "":
		return ""
	for t in v.tech:
		if t != id and str(def(t).get("group", "")) == g:
			return t
	return ""


## Highest owned non-prototype tier of `branch` (0..MAX_TIER).
static func branch_tier(v: SimVehicle, branch: String) -> int:
	var t: int = 0
	for id in v.tech:
		var d: Dictionary = def(id)
		if not d.is_empty() and d["branch"] == branch and d["kind"] != "proto":
			t = maxi(t, int(d["tier"]))
	return t


## Whether `v` meets every requirement and no exclusive sibling is owned (cost not checked).
static func unlocked(v: SimVehicle, id: String) -> bool:
	return has(id) and not v.tech.has(id) and missing(v, id) == "" and blocked_by(v, id) == ""


static func can_buy(v: SimVehicle, id: String) -> bool:
	return unlocked(v, id) and v.scrap >= price(v, id)


## Buys `id` for `v` if allowed: pays the price (half for a dormant fusion), pays out one-off
## grants (fuel), notes the round (`world_round`, for the keystone respec window) and recomputes
## the vehicle's derived stats.
static func buy(v: SimVehicle, id: String, world_round: int = 0) -> bool:
	if not can_buy(v, id):
		return false
	v.scrap -= price(v, id)
	v.tech_dormant.erase(id)
	v.tech.append(id)
	v.tech_round[id] = world_round
	var fx: Dictionary = def(id)["fx"]
	if fx.has("fuel"):
		v.fuel += int(fx["fuel"])
	_recompute(v)
	Salvage.on_buy(v, fx)
	return true


## Recompute with the reroll price following a changed reroll discount (haggler).
static func _recompute(v: SimVehicle) -> void:
	var old_discount: int = v.reroll_discount
	Cards.recompute(v)
	v.reroll_cost = maxi(1, v.reroll_cost - (v.reroll_discount - old_discount))


# ---------------------------------------------------------------- respec

## Net price of swapping to `to`: free for the first respec of the match, then half the new node's
## price on top of the full refund of the old one.
static func respec_cost(v: SimVehicle, to: String) -> int:
	return 0 if v.respecs == 0 else cost(to) * RESPEC_FEE_PCT / 100


## Whether the owned choice `from` may be swapped for the unowned choice `to` of the same branch
## and tier: requirements of `to` active, affordable, and a tier 6 keystone only until
## bought round + 1.
static func can_respec(v: SimVehicle, from: String, to: String, world_round: int) -> bool:
	var a: Dictionary = def(from)
	var b: Dictionary = def(to)
	if a.is_empty() or b.is_empty() or from == to or not v.tech.has(from) or v.tech.has(to):
		return false
	if a["kind"] != "choice" or b["kind"] != "choice" or a["group"] != b["group"]:
		return false
	if int(b["tier"]) == MAX_TIER and world_round > int(v.tech_round.get(from, 0)) + KEYSTONE_RESPEC_ROUNDS:
		return false
	if missing(v, to) != "":
		return false
	return v.scrap + cost(from) >= cost(to) + respec_cost(v, to)


## Swaps `from` for `to` in place (acquisition order is kept), refunds `from`, charges `to` plus the
## respec fee, parks fusions that lost a requirement in `v.tech_dormant`. Follow-up nodes stay owned.
static func respec(v: SimVehicle, from: String, to: String, world_round: int) -> bool:
	if not can_respec(v, from, to, world_round):
		return false
	v.scrap += cost(from) - cost(to) - respec_cost(v, to)
	v.tech[v.tech.find(from)] = to
	v.tech_round[to] = int(v.tech_round.get(from, world_round))
	v.tech_round.erase(from)
	v.respecs += 1
	for t in v.tech.duplicate():
		if is_fusion(t) and missing(v, t) != "":
			v.tech.erase(t)
			v.tech_round.erase(t)
			if not v.tech_dormant.has(t):
				v.tech_dormant.append(t)
	_recompute(v)
	return true
