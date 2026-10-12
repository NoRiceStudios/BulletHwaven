class_name Tech
extends RefCounted
## Tech tree data (design doc section 5b): 5 branches x 3 tiers. Pure data plus static helpers.
## Tier N needs tier N-1 of the same branch. Effects are flat (`fx`) and summed by
## `Cards.recompute()` together with the card effects. Tech ids travel in snapshots as indices
## into `DEFS`, so only ever append to the table.
##
## fx keys (see Cards.recompute): hp, armor, speed, turn, scrap, regen, contact, ram, vulture,
## dmg, range, rate (all additive) and slots, interest (integers).

const BRANCHES: PackedStringArray = ["ballistics", "engineering", "propulsion", "electronics", "salvage"]
const TIER_COSTS: PackedInt32Array = [15, 30, 55]
const MAX_TIER := 3

const DEFS: Array = [
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
]

static var _index: Dictionary = {}


static func count() -> int:
	return DEFS.size()


static func _ensure_index() -> void:
	if _index.is_empty():
		for i in DEFS.size():
			_index[str((DEFS[i] as Dictionary)["id"])] = i


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


## The table entry for `id` ({} if unknown).
static func def(id: String) -> Dictionary:
	var i: int = index_of(id)
	return DEFS[i] if i >= 0 else {}


static func cost(id: String) -> int:
	var d: Dictionary = def(id)
	if d.is_empty():
		return 0
	return TIER_COSTS[int(d["tier"]) - 1]


## The id that must be owned before `id` can be bought ("" for tier 1 or unknown ids).
static func prerequisite(id: String) -> String:
	var d: Dictionary = def(id)
	if d.is_empty() or int(d["tier"]) <= 1:
		return ""
	return "%s_%d" % [d["branch"], int(d["tier"]) - 1]


## Owned tier of `branch` (0..3).
static func branch_tier(v: SimVehicle, branch: String) -> int:
	var t: int = 0
	for id in v.tech:
		var d: Dictionary = def(id)
		if not d.is_empty() and d["branch"] == branch:
			t = maxi(t, int(d["tier"]))
	return t


static func can_buy(v: SimVehicle, id: String) -> bool:
	if not has(id) or v.tech.has(id):
		return false
	var pre: String = prerequisite(id)
	if pre != "" and not v.tech.has(pre):
		return false
	return v.scrap >= cost(id)


## Buys `id` for `v` if allowed: pays the cost and recomputes the vehicle's derived stats.
static func buy(v: SimVehicle, id: String) -> bool:
	if not can_buy(v, id):
		return false
	v.scrap -= cost(id)
	v.tech.append(id)
	Cards.recompute(v)
	return true
