class_name Cards
extends RefCounted
## Draft card data (design doc section 5a) plus the code that turns cards and tech into a
## vehicle's derived stats. Pure data and static functions; randomness only via the passed rng.
## Card ids travel in snapshots as indices into `DEFS`, so only ever append to the table.
##
## `fx` amounts are PER LEVEL (a level 3 card applies them 3 times). Keys:
##   hp (max hp), armor (flat damage reduction), speed / turn (additive multipliers),
##   scrap (scrap multiplier), regen (hp/s), contact (damage per tick to touching enemies),
##   ram (extra "charge" ram multiplier), vulture (extra damage vs targets under 30% hp),
##   dmg / range / rate (weapon damage, range and fire rate multipliers, additive).
##   Tech adds `slots` (weapon slots) and `interest` (interest cap) on top (see tech.gd).

const MAX_LEVEL := 3
const BASE_WEAPON_SLOTS := 2
const BASE_INTEREST_CAP := 5
const OFFER_COUNT := 3
const VULTURE_HP_FRACTION := 0.3

const WEAPON_KINDS: PackedStringArray = ["mg", "shotgun", "cannon", "flamer"]

## Weapon variants. Per-level arrays hold levels 1..3. `speed` is projectile px/s; `spread` is the
## half-angle in radians; flame projectiles live only range / speed seconds (very short ttl).
const WEAPONS := {
	"mg": {
		"damage": [4.0, 5.0, 6.0], "cooldown": [3, 3, 2], "range": [240.0, 250.0, 260.0],
		"pellets": [1, 1, 1], "pierce": [0, 0, 0], "splash": [0.0, 0.0, 0.0],
		"speed": 400.0, "spread": 0.04,
	},
	"shotgun": {
		"damage": [3.0, 3.5, 4.0], "cooldown": [14, 13, 12], "range": [150.0, 160.0, 170.0],
		"pellets": [5, 6, 8], "pierce": [0, 0, 0], "splash": [0.0, 0.0, 0.0],
		"speed": 380.0, "spread": 0.30,
	},
	"cannon": {
		"damage": [26.0, 34.0, 44.0], "cooldown": [24, 22, 20], "range": [300.0, 310.0, 320.0],
		"pellets": [1, 1, 1], "pierce": [1, 1, 2], "splash": [0.0, 22.0, 28.0],
		"speed": 460.0, "spread": 0.02,
	},
	"flamer": {
		"damage": [1.8, 2.4, 3.0], "cooldown": [2, 2, 2], "range": [95.0, 105.0, 115.0],
		"pellets": [1, 1, 1], "pierce": [2, 3, 4], "splash": [0.0, 0.0, 0.0],
		"speed": 230.0, "spread": 0.22,
	},
}

const DEFS: Array = [
	# weapons (mg is the starter, so it only ever shows up as an upgrade)
	{"id": "mg", "name": "Machine Gun", "category": "weapon", "rarity": "common", "weight": 6, "fx": {}},
	{"id": "shotgun", "name": "Scatter Gun", "category": "weapon", "rarity": "common", "weight": 10, "fx": {}},
	{"id": "cannon", "name": "Siege Cannon", "category": "weapon", "rarity": "rare", "weight": 6, "fx": {}},
	{"id": "flamer", "name": "Flamethrower", "category": "weapon", "rarity": "rare", "weight": 6, "fx": {}},
	# armour
	{"id": "steel_plates", "name": "Steel Plates", "category": "armor", "rarity": "common", "weight": 10, "fx": {"hp": 40.0, "armor": 1.0}},
	{"id": "spiked_plating", "name": "Spiked Plating", "category": "armor", "rarity": "common", "weight": 7, "fx": {"armor": 0.5, "contact": 0.6}},
	{"id": "reinforced_hull", "name": "Reinforced Hull", "category": "armor", "rarity": "common", "weight": 7, "fx": {"hp": 80.0}},
	{"id": "ablative_scrap", "name": "Ablative Scrap", "category": "armor", "rarity": "rare", "weight": 5, "fx": {"armor": 2.0}},
	# mobility
	{"id": "v8_engine", "name": "V8 Engine", "category": "mobility", "rarity": "common", "weight": 10, "fx": {"speed": 0.10}},
	{"id": "off_road_tyres", "name": "Off-road Tyres", "category": "mobility", "rarity": "common", "weight": 8, "fx": {"turn": 0.15, "speed": 0.03}},
	{"id": "nitro", "name": "Nitro Injection", "category": "mobility", "rarity": "rare", "weight": 5, "fx": {"speed": 0.18}},
	{"id": "caterpillar_tracks", "name": "Caterpillar Tracks", "category": "mobility", "rarity": "rare", "weight": 6, "fx": {"hp": 30.0, "armor": 0.5, "speed": -0.05}},
	# behaviour mods
	{"id": "scrap_magnet", "name": "Scrap Magnet", "category": "behavior", "rarity": "common", "weight": 8, "fx": {"scrap": 0.15}},
	{"id": "berserker", "name": "Berserker Doctrine", "category": "behavior", "rarity": "rare", "weight": 6, "fx": {"contact": 0.8, "ram": 0.4}},
	{"id": "vulture", "name": "Vulture", "category": "behavior", "rarity": "rare", "weight": 6, "fx": {"vulture": 0.25}},
	{"id": "regenerator", "name": "Regenerator", "category": "behavior", "rarity": "rare", "weight": 7, "fx": {"regen": 1.5}},
]

static var _index: Dictionary = {}


static func count() -> int:
	return DEFS.size()


static func _ensure_index() -> void:
	if _index.is_empty():
		for i in DEFS.size():
			_index[str((DEFS[i] as Dictionary)["id"])] = i


## Table index of a card id, or -1 if unknown.
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


static func is_weapon(id: String) -> bool:
	return WEAPONS.has(id)


## Index of a weapon kind in WEAPON_KINDS (the "kind" of a "fire" event); 0 if unknown.
static func weapon_kind_index(kind: String) -> int:
	return maxi(WEAPON_KINDS.find(kind), 0)


# ---------------------------------------------------------------- offers and picking

static func weapon_cards_owned(v: SimVehicle) -> int:
	var n: int = 0
	for id: String in v.cards:
		if WEAPONS.has(id):
			n += 1
	return n


## Whether `id` may be offered to `v`: known, below max level, and (for a new weapon) a free slot.
static func is_offerable(v: SimVehicle, id: String) -> bool:
	if not has(id):
		return false
	var lvl: int = int(v.cards.get(id, 0))
	if lvl >= MAX_LEVEL:
		return false
	if lvl == 0 and WEAPONS.has(id) and weapon_cards_owned(v) >= v.weapon_slots:
		return false
	return true


## Draws up to `count` distinct offerable card ids, weighted by rarity weight. Uses `rng` only.
static func roll_offers(rng: RandomNumberGenerator, v: SimVehicle, count: int = OFFER_COUNT) -> Array[String]:
	var pool: Array[String] = []
	var weights: Array[int] = []
	var total: int = 0
	for d: Dictionary in DEFS:
		var id: String = d["id"]
		if is_offerable(v, id):
			pool.append(id)
			weights.append(int(d["weight"]))
			total += int(d["weight"])
	var out: Array[String] = []
	while out.size() < count and not pool.is_empty():
		var roll: int = rng.randi() % total
		var k: int = 0
		while k < pool.size() - 1 and roll >= weights[k]:
			roll -= weights[k]
			k += 1
		out.append(pool[k])
		total -= weights[k]
		pool.remove_at(k)
		weights.remove_at(k)
	return out


## Adds one level of `id` to `v` (new cards start at level 1) and recomputes its stats.
## Returns false if the card is unknown or already at max level.
static func grant(v: SimVehicle, id: String) -> bool:
	if not has(id):
		return false
	var lvl: int = int(v.cards.get(id, 0))
	if lvl >= MAX_LEVEL:
		return false
	v.cards[id] = lvl + 1
	recompute(v)
	return true


# ---------------------------------------------------------------- derived stats

## Recomputes the derived stats (max_hp, armor, speed, turn_rate, scrap_mult, regen, ...) of `v`
## from its base values plus cards plus tech. `rebuild_weapons` rebuilds the weapon list from the
## weapon cards (keeping cooldown and aim of weapons that stay); `adjust_hp` raises current hp by
## any max_hp gain so that armour cards do not leave the vehicle looking damaged.
static func recompute(v: SimVehicle, rebuild_weapons: bool = true, adjust_hp: bool = true) -> void:
	var st := {
		"hp": 0.0, "armor": 0.0, "speed": 0.0, "turn": 0.0, "scrap": 0.0, "regen": 0.0, "contact": 0.0,
		"ram": 0.0, "vulture": 0.0, "dmg": 0.0, "range": 0.0, "rate": 0.0, "slots": 0.0, "interest": 0.0,
	}
	for id: String in v.cards:
		var d: Dictionary = def(id)
		if d.is_empty():
			continue
		var lvl: int = clampi(int(v.cards[id]), 0, MAX_LEVEL)
		var fx: Dictionary = d["fx"]
		for k: String in fx:
			st[k] = float(st[k]) + float(fx[k]) * float(lvl)
	for id in v.tech:
		var td: Dictionary = Tech.def(id)
		if td.is_empty():
			continue
		var tfx: Dictionary = td["fx"]
		for k: String in tfx:
			st[k] = float(st[k]) + float(tfx[k])

	var old_max: float = v.max_hp
	v.max_hp = maxf(SimVehicle.MAX_HP + float(st["hp"]), 1.0)
	if adjust_hp and v.alive and v.max_hp > old_max:
		v.hp = minf(v.hp + (v.max_hp - old_max), v.max_hp)
	v.hp = minf(v.hp, v.max_hp)
	v.armor = float(st["armor"])
	v.speed = maxf(1.0 + float(st["speed"]), 0.3)
	v.turn_rate = maxf(1.0 + float(st["turn"]), 0.3)
	v.scrap_mult = maxf(1.0 + float(st["scrap"]), 0.0)
	v.regen = float(st["regen"])
	v.contact_damage = float(st["contact"])
	v.ram_mult = 1.0 + float(st["ram"])
	v.vulture = float(st["vulture"])
	v.weapon_slots = BASE_WEAPON_SLOTS + int(st["slots"])
	v.interest_cap = BASE_INTEREST_CAP + int(st["interest"])
	if rebuild_weapons:
		_rebuild_weapons(v, 1.0 + float(st["dmg"]), 1.0 + float(st["range"]), 1.0 + float(st["rate"]))


static func _rebuild_weapons(v: SimVehicle, dmg_mult: float, range_mult: float, rate_mult: float) -> void:
	var old: Dictionary = {}
	for w in v.weapons:
		old[str(w.get("kind", ""))] = w
	var fresh: Array[Dictionary] = []
	for id: String in v.cards:
		if not WEAPONS.has(id) or fresh.size() >= v.weapon_slots:
			continue
		var lvl: int = clampi(int(v.cards[id]), 1, MAX_LEVEL)
		var b: Dictionary = WEAPONS[id]
		var li: int = lvl - 1
		var prev: Dictionary = old.get(id, {})
		fresh.append({
			"kind": id,
			"damage": float((b["damage"] as Array)[li]) * dmg_mult,
			"range": float((b["range"] as Array)[li]) * range_mult,
			"cooldown_ticks": maxi(1, roundi(float((b["cooldown"] as Array)[li]) / rate_mult)),
			"cooldown": int(prev.get("cooldown", 0)),
			"aim": float(prev.get("aim", 0.0)),
			"pellets": int((b["pellets"] as Array)[li]),
			"spread": float(b["spread"]),
			"pierce": int((b["pierce"] as Array)[li]),
			"splash": float((b["splash"] as Array)[li]),
			"speed": float(b["speed"]),
		})
	v.weapons = fresh
