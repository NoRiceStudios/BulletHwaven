class_name Tech
extends RefCounted
## Tech tree data (design doc section 5b). Pure data plus static helpers.
##
## Shape: 5 branches. Each branch has a spine of 6 core tiers (`<branch>_1` .. `<branch>_6`, tier N
## needs tier N-1), plus two specialisation forks: after core tier 2 and after core tier 4 the
## player picks ONE of 2-3 spec nodes (nodes sharing a `group` exclude each other for the rest of
## the match). Five fusion nodes need core tier 3 in two branches each. 57 nodes in total, far more
## than a match's scrap can buy, so every build is a plan.
##
## Entry fields: id, branch ("fusion" for fusions), tier (layout row 1..6), kind ("core", "spec",
## "fusion"), name, short (label for the small spec / fusion nodes), cost, requires (all needed),
## group (exclusive choice, "" = none), fx. Effects are flat and summed by `Cards.recompute()`
## together with the card effects. Tech ids travel in snapshots as indices into `DEFS`, so only
## ever append to the table.
##
## fx keys (see Cards.recompute): hp, armor, speed, turn, scrap, regen, contact, ram, vulture,
## creduce, thorns, dmg, range, rate (additive), slots, interest, pierce, reroll (integers),
## luck (rare+ card offer weight), dmg_<weapon> / rate_<weapon> / range_<weapon> (per weapon
## kind), pellets_<weapon>, splash_<weapon> (flat). `fuel` is a one-off grant paid out by buy().

const BRANCHES: PackedStringArray = ["ballistics", "engineering", "propulsion", "electronics", "salvage"]
const TIER_COSTS: PackedInt32Array = [70, 160, 300, 450, 700, 1000]
const MAX_TIER := 6
const SPEC_COSTS := {2: 130, 4: 380}  ## spec node cost by the core tier it hangs off
const FUSION_COST := 480
const FUSION_TIER := 3  ## core tier needed in both parent branches

const DEFS: Array = [
	# ---- core tiers 1-3 (the original 15; keep this order, indices travel in snapshots)
	{"id": "ballistics_1", "branch": "ballistics", "tier": 1, "name": "Hardened Rounds", "fx": {"dmg": 0.10}},
	{"id": "ballistics_2", "branch": "ballistics", "tier": 2, "name": "Armour Piercing", "fx": {"dmg": 0.12}},
	{"id": "ballistics_3", "branch": "ballistics", "tier": 3, "name": "Overcharged Loads", "fx": {"dmg": 0.15}},
	{"id": "engineering_1", "branch": "engineering", "tier": 1, "name": "Welded Frame", "fx": {"hp": 40.0, "armor": 1.0}},
	{"id": "engineering_2", "branch": "engineering", "tier": 2, "name": "Bolt-on Plating", "fx": {"hp": 60.0, "armor": 1.0}},
	{"id": "engineering_3", "branch": "engineering", "tier": 3, "name": "Third Hardpoint", "fx": {"hp": 60.0, "slots": 1}},
	{"id": "propulsion_1", "branch": "propulsion", "tier": 1, "name": "Tuned Engine", "fx": {"speed": 0.08, "turn": 0.10}},
	{"id": "propulsion_2", "branch": "propulsion", "tier": 2, "name": "Racing Gearbox", "fx": {"speed": 0.08, "turn": 0.10}},
	{"id": "propulsion_3", "branch": "propulsion", "tier": 3, "name": "Dune Suspension", "fx": {"speed": 0.10, "turn": 0.15}},
	{"id": "electronics_1", "branch": "electronics", "tier": 1, "name": "Rangefinder", "fx": {"range": 0.08, "rate": 0.10}},
	{"id": "electronics_2", "branch": "electronics", "tier": 2, "name": "Targeting Computer", "fx": {"range": 0.08, "rate": 0.10}},
	{"id": "electronics_3", "branch": "electronics", "tier": 3, "name": "Radar Array", "fx": {"range": 0.10, "rate": 0.15}},
	{"id": "salvage_1", "branch": "salvage", "tier": 1, "name": "Scrap Hooks", "fx": {"scrap": 0.10}},
	{"id": "salvage_2", "branch": "salvage", "tier": 2, "name": "Accounting", "fx": {"scrap": 0.10, "interest": 2}},
	{"id": "salvage_3", "branch": "salvage", "tier": 3, "name": "Black Market", "fx": {"scrap": 0.15, "interest": 3}},

	# ---- core tiers 4-6
	{"id": "ballistics_4", "branch": "ballistics", "tier": 4, "name": "Tungsten Cores", "fx": {"dmg": 0.08}},
	{"id": "ballistics_5", "branch": "ballistics", "tier": 5, "name": "Hot Barrels", "fx": {"dmg": 0.08, "rate": 0.05}},
	{"id": "ballistics_6", "branch": "ballistics", "tier": 6, "name": "Depleted Uranium", "fx": {"dmg": 0.12, "pierce": 1}},
	{"id": "engineering_4", "branch": "engineering", "tier": 4, "name": "Roll Cage", "fx": {"hp": 80.0, "armor": 1.5}},
	{"id": "engineering_5", "branch": "engineering", "tier": 5, "name": "Reinforced Chassis", "fx": {"hp": 120.0, "creduce": 0.10}},
	{"id": "engineering_6", "branch": "engineering", "tier": 6, "name": "Fortress Hull", "fx": {"hp": 180.0, "armor": 2.0}},
	{"id": "propulsion_4", "branch": "propulsion", "tier": 4, "name": "Supercharger", "fx": {"speed": 0.10, "turn": 0.05}},
	{"id": "propulsion_5", "branch": "propulsion", "tier": 5, "name": "Turbine Swap", "fx": {"speed": 0.08, "turn": 0.10, "hp": 50.0}},
	{"id": "propulsion_6", "branch": "propulsion", "tier": 6, "name": "Afterburner Rig", "fx": {"speed": 0.12, "ram": 0.40, "turn": 0.10}},
	{"id": "electronics_4", "branch": "electronics", "tier": 4, "name": "Gyro Stabilisers", "fx": {"range": 0.06, "rate": 0.10}},
	{"id": "electronics_5", "branch": "electronics", "tier": 5, "name": "Ballistic Computer", "fx": {"rate": 0.08, "vulture": 0.10}},
	{"id": "electronics_6", "branch": "electronics", "tier": 6, "name": "Neural Fire Control", "fx": {"rate": 0.10, "range": 0.06}},
	{"id": "salvage_4", "branch": "salvage", "tier": 4, "name": "Wreck Strippers", "fx": {"scrap": 0.15}},
	{"id": "salvage_5", "branch": "salvage", "tier": 5, "name": "Salvage Crane", "fx": {"scrap": 0.15, "interest": 3}},
	{"id": "salvage_6", "branch": "salvage", "tier": 6, "name": "Scrap Baron", "fx": {"scrap": 0.25, "interest": 5}},

	# ---- specialisations after tier 2 (pick one per branch)
	{"id": "ballistics_belt_feed", "branch": "ballistics", "tier": 2, "kind": "spec", "group": "ballistics_a",
		"name": "Belt Feed", "short": "BELT FEED", "fx": {"rate_mg": 0.25, "rate_flamer": 0.15}},
	{"id": "ballistics_heavy_shells", "branch": "ballistics", "tier": 2, "kind": "spec", "group": "ballistics_a",
		"name": "Heavy Shells", "short": "HEAVY", "fx": {"dmg_cannon": 0.20, "dmg_shotgun": 0.15}},
	{"id": "engineering_spikes", "branch": "engineering", "tier": 2, "kind": "spec", "group": "engineering_a",
		"name": "Spike Skirts", "short": "SPIKES", "fx": {"contact": 0.5, "thorns": 0.4, "creduce": 0.08}},
	{"id": "engineering_welder", "branch": "engineering", "tier": 2, "kind": "spec", "group": "engineering_a",
		"name": "Field Welder", "short": "WELDER", "fx": {"regen": 2.0}},
	{"id": "propulsion_ram_bumper", "branch": "propulsion", "tier": 2, "kind": "spec", "group": "propulsion_a",
		"name": "Ram Bumper", "short": "BUMPER", "fx": {"ram": 0.35, "hp": 30.0}},
	{"id": "propulsion_drift", "branch": "propulsion", "tier": 2, "kind": "spec", "group": "propulsion_a",
		"name": "Drift Tuning", "short": "DRIFT", "fx": {"turn": 0.25, "speed": 0.04}},
	{"id": "electronics_hunter", "branch": "electronics", "tier": 2, "kind": "spec", "group": "electronics_a",
		"name": "Hunter-Killer Logic", "short": "HUNTER", "fx": {"vulture": 0.20}},
	{"id": "electronics_relay", "branch": "electronics", "tier": 2, "kind": "spec", "group": "electronics_a",
		"name": "Fire Control Relay", "short": "RELAY", "fx": {"rate": 0.08}},
	{"id": "salvage_haggler", "branch": "salvage", "tier": 2, "kind": "spec", "group": "salvage_a",
		"name": "Haggler", "short": "HAGGLER", "fx": {"reroll": 3}},
	{"id": "salvage_lucky", "branch": "salvage", "tier": 2, "kind": "spec", "group": "salvage_a",
		"name": "Lucky Charm", "short": "LUCKY", "fx": {"luck": 0.6}},

	# ---- specialisations after tier 4 (pick one per branch)
	{"id": "ballistics_buckshot", "branch": "ballistics", "tier": 4, "kind": "spec", "group": "ballistics_b",
		"name": "Buckshot Packing", "short": "BUCKSHOT", "fx": {"pellets_shotgun": 2, "range_shotgun": 0.10}},
	{"id": "ballistics_napalm", "branch": "ballistics", "tier": 4, "kind": "spec", "group": "ballistics_b",
		"name": "Napalm Mix", "short": "NAPALM", "fx": {"dmg_flamer": 0.25, "range_flamer": 0.15}},
	{"id": "ballistics_he_shells", "branch": "ballistics", "tier": 4, "kind": "spec", "group": "ballistics_b",
		"name": "HE Shells", "short": "HE SHELL", "fx": {"splash_cannon": 14.0, "dmg_cannon": 0.10, "dmg_mg": 0.15}},
	{"id": "engineering_reactive", "branch": "engineering", "tier": 4, "kind": "spec", "group": "engineering_b",
		"name": "Reactive Plates", "short": "REACTIVE", "fx": {"armor": 2.5}},
	{"id": "engineering_drone", "branch": "engineering", "tier": 4, "kind": "spec", "group": "engineering_b",
		"name": "Repair Drone", "short": "DRONE", "fx": {"regen": 4.0, "hp": 40.0}},
	{"id": "engineering_dozer", "branch": "engineering", "tier": 4, "kind": "spec", "group": "engineering_b",
		"name": "Dozer Blade", "short": "DOZER", "fx": {"creduce": 0.15, "contact": 0.8, "ram": 0.30}},
	{"id": "propulsion_battering", "branch": "propulsion", "tier": 4, "kind": "spec", "group": "propulsion_b",
		"name": "Battering Ram", "short": "BATTER", "fx": {"ram": 0.60, "contact": 0.6, "creduce": 0.10}},
	{"id": "propulsion_ghost", "branch": "propulsion", "tier": 4, "kind": "spec", "group": "propulsion_b",
		"name": "Ghost Runner", "short": "GHOST", "fx": {"speed": 0.10, "range": 0.06}},
	{"id": "electronics_optics", "branch": "electronics", "tier": 4, "kind": "spec", "group": "electronics_b",
		"name": "Long-Range Optics", "short": "OPTICS", "fx": {"range_cannon": 0.20, "range_mg": 0.15}},
	{"id": "electronics_overclock", "branch": "electronics", "tier": 4, "kind": "spec", "group": "electronics_b",
		"name": "Overclocked Servos", "short": "OVERCLOCK", "fx": {"rate": 0.12, "range": -0.05}},
	{"id": "salvage_jerrycans", "branch": "salvage", "tier": 4, "kind": "spec", "group": "salvage_b",
		"name": "Spare Jerrycans", "short": "JERRYCAN", "fx": {"fuel": 15}},
	{"id": "salvage_loan_shark", "branch": "salvage", "tier": 4, "kind": "spec", "group": "salvage_b",
		"name": "Loan Shark", "short": "LOANSHARK", "fx": {"interest": 6}},

	# ---- fusions: core tier 3 in two branches
	{"id": "fusion_smart_rounds", "branch": "fusion", "tier": 3, "kind": "fusion", "requires": ["ballistics_3", "electronics_3"],
		"name": "Smart Rounds", "short": "SMART RND", "fx": {"dmg": 0.06, "range": 0.06, "vulture": 0.10}},
	{"id": "fusion_war_rig", "branch": "fusion", "tier": 3, "kind": "fusion", "requires": ["engineering_3", "propulsion_3"],
		"name": "War Rig Armour", "short": "WAR RIG", "fx": {"hp": 100.0, "armor": 1.0, "ram": 0.30}},
	{"id": "fusion_scrap_rounds", "branch": "fusion", "tier": 3, "kind": "fusion", "requires": ["ballistics_3", "salvage_3"],
		"name": "Scrap Rounds", "short": "SCRAP RND", "fx": {"dmg": 0.05, "scrap": 0.10}},
	{"id": "fusion_workshop", "branch": "fusion", "tier": 3, "kind": "fusion", "requires": ["engineering_3", "salvage_3"],
		"name": "Mobile Workshop", "short": "WORKSHOP", "fx": {"regen": 3.0, "scrap": 0.05}},
	{"id": "fusion_sensor_drive", "branch": "fusion", "tier": 3, "kind": "fusion", "requires": ["propulsion_3", "electronics_3"],
		"name": "Sensor Drive", "short": "SENSOR", "fx": {"speed": 0.08, "rate": 0.05}},
]

static var _index: Dictionary = {}
static var _full: Array = []  # DEFS with kind / cost / requires / group / short filled in


static func count() -> int:
	return DEFS.size()


static func _ensure_index() -> void:
	if not _index.is_empty():
		return
	for i in DEFS.size():
		var d: Dictionary = (DEFS[i] as Dictionary).duplicate(true)
		var kind: String = str(d.get("kind", "core"))
		var tier: int = int(d["tier"])
		d["kind"] = kind
		d["group"] = str(d.get("group", ""))
		d["short"] = str(d.get("short", d["name"])).to_upper()
		if not d.has("requires"):
			if kind == "spec":
				d["requires"] = ["%s_%d" % [d["branch"], tier]]
			elif tier > 1:
				d["requires"] = ["%s_%d" % [d["branch"], tier - 1]]
			else:
				d["requires"] = []
		match kind:
			"spec": d["cost"] = int(SPEC_COSTS.get(tier, TIER_COSTS[tier - 1]))
			"fusion": d["cost"] = FUSION_COST
			_: d["cost"] = TIER_COSTS[tier - 1]
		_full.append(d)
		_index[str(d["id"])] = i


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


## Ids of a branch's nodes of `kind` ("core", "spec" or "fusion"; branch "" = any), in table order.
static func ids(branch: String = "", kind: String = "") -> Array[String]:
	_ensure_index()
	var out: Array[String] = []
	for d: Dictionary in _full:
		if (branch == "" or d["branch"] == branch) and (kind == "" or d["kind"] == kind):
			out.append(str(d["id"]))
	return out


## Spec nodes hanging off core tier `tier` of `branch` (one exclusive choice group).
static func specs(branch: String, tier: int) -> Array[String]:
	var out: Array[String] = []
	for id in ids(branch, "spec"):
		if int(def(id)["tier"]) == tier:
			out.append(id)
	return out


static func cost(id: String) -> int:
	var d: Dictionary = def(id)
	return int(d["cost"]) if not d.is_empty() else 0


## All ids that must be owned before `id` can be bought.
static func requirements(id: String) -> Array:
	var d: Dictionary = def(id)
	return d["requires"] if not d.is_empty() else []


## The first required id ("" for tier 1 or unknown ids). See also missing().
static func prerequisite(id: String) -> String:
	var req: Array = requirements(id)
	return str(req[0]) if not req.is_empty() else ""


## The first requirement of `id` that `v` does not own ("" = none missing).
static func missing(v: SimVehicle, id: String) -> String:
	for r in requirements(id):
		if not v.tech.has(str(r)):
			return str(r)
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


## Owned core tier of `branch` (0..MAX_TIER).
static func branch_tier(v: SimVehicle, branch: String) -> int:
	var t: int = 0
	for id in v.tech:
		var d: Dictionary = def(id)
		if not d.is_empty() and d["branch"] == branch and d["kind"] == "core":
			t = maxi(t, int(d["tier"]))
	return t


## Whether `v` meets every requirement and no exclusive sibling is owned (cost not checked).
static func unlocked(v: SimVehicle, id: String) -> bool:
	return has(id) and not v.tech.has(id) and missing(v, id) == "" and blocked_by(v, id) == ""


static func can_buy(v: SimVehicle, id: String) -> bool:
	return unlocked(v, id) and v.scrap >= cost(id)


## Buys `id` for `v` if allowed: pays the cost, pays out one-off grants (fuel) and recomputes the
## vehicle's derived stats.
static func buy(v: SimVehicle, id: String) -> bool:
	if not can_buy(v, id):
		return false
	v.scrap -= cost(id)
	v.tech.append(id)
	var fx: Dictionary = def(id)["fx"]
	if fx.has("fuel"):
		v.fuel += int(fx["fuel"])
	var old_discount: int = v.reroll_discount
	Cards.recompute(v)
	v.reroll_cost = maxi(1, v.reroll_cost - (v.reroll_discount - old_discount))
	return true
