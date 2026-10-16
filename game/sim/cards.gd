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
##   creduce (fraction of enemy contact damage ignored, total capped at MAX_CONTACT_REDUCTION),
##   thorns (fraction of the contact damage an enemy deals that it takes back, per touching enemy and tick),
##   dmg / range / rate (weapon damage, range and fire rate multipliers, additive).
##   Tech adds `slots` (weapon slots), `interest` (interest cap), `pierce`, `reroll` (reroll discount),
##   `luck` (offer weight bonus for rare+ cards) and per-weapon keys `dmg_<kind>`, `rate_<kind>`,
##   `range_<kind>`, `pellets_<kind>`, `splash_<kind>` on top (see tech.gd).

const MAX_LEVEL := 3
const BASE_WEAPON_SLOTS := 2
const BASE_INTEREST_CAP := 5
const OFFER_COUNT := 3
const VULTURE_HP_FRACTION := 0.3
const EARLY_ROUNDS := 3  ## rounds 1..3 favour weapon variety in drafts
const MAX_CONTACT_REDUCTION := 0.6

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
		"damage": [3.5, 4.0, 4.5], "cooldown": [14, 13, 12], "range": [150.0, 160.0, 170.0],
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
	{"id": "steel_plates", "name": "Steel Plates", "category": "armor", "rarity": "common", "weight": 8, "fx": {"hp": 60.0, "armor": 1.5}},
	{"id": "spiked_plating", "name": "Spiked Plating", "category": "armor", "rarity": "common", "weight": 7, "fx": {"armor": 0.5, "contact": 0.6, "creduce": 0.10, "thorns": 0.5}},
	{"id": "reinforced_hull", "name": "Reinforced Hull", "category": "armor", "rarity": "common", "weight": 6, "fx": {"hp": 110.0}},
	{"id": "ablative_scrap", "name": "Ablative Scrap", "category": "armor", "rarity": "rare", "weight": 5, "fx": {"armor": 3.0}},
	# mobility
	{"id": "v8_engine", "name": "V8 Engine", "category": "mobility", "rarity": "common", "weight": 6, "fx": {"speed": 0.10}},
	{"id": "off_road_tyres", "name": "Off-road Tyres", "category": "mobility", "rarity": "common", "weight": 5, "fx": {"turn": 0.15, "speed": 0.03}},
	{"id": "nitro", "name": "Nitro Injection", "category": "mobility", "rarity": "rare", "weight": 5, "fx": {"speed": 0.18}},
	{"id": "caterpillar_tracks", "name": "Caterpillar Tracks", "category": "mobility", "rarity": "rare", "weight": 6, "fx": {"hp": 30.0, "armor": 0.5, "speed": -0.05}},
	# behaviour mods
	{"id": "scrap_magnet", "name": "Scrap Magnet", "category": "behavior", "rarity": "common", "weight": 6, "fx": {"scrap": 0.15}},
	{"id": "berserker", "name": "Berserker Doctrine", "category": "behavior", "rarity": "rare", "weight": 6, "fx": {"contact": 0.8, "ram": 0.4, "creduce": 0.12}},
	{"id": "vulture", "name": "Vulture", "category": "behavior", "rarity": "rare", "weight": 6, "fx": {"vulture": 0.25}},
	{"id": "regenerator", "name": "Regenerator", "category": "behavior", "rarity": "rare", "weight": 7, "fx": {"regen": 2.5}},
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
## Draft rules (balance iteration 3):
##  - never `count` cards of one category (a third card of a category already drawn twice is skipped);
##  - while the vehicle has a free weapon slot and a weapon it does not own is offerable, one offer is
##    a new weapon (so a free slot never stays empty because the dice said no);
##  - in the early rounds (`round_no` 1..EARLY_ROUNDS) unowned weapons weigh double (weapon variety);
##  - cards in `exclude` (the previous offer, for a reroll) are not offered again, unless that would
##    leave fewer than `count` cards to choose from.
static func roll_offers(rng: RandomNumberGenerator, v: SimVehicle, count: int = OFFER_COUNT, round_no: int = 0, exclude: Array[String] = []) -> Array[String]:
	var pool: Array[String] = []
	var weights: Array[int] = []
	for d: Dictionary in DEFS:
		var id: String = d["id"]
		if is_offerable(v, id) and not exclude.has(id):
			pool.append(id)
			weights.append(_offer_weight(v, d, round_no))
	if pool.size() < count:  # not enough fresh cards: allow repeats of the previous offer
		pool.clear()
		weights.clear()
		for d: Dictionary in DEFS:
			var id2: String = d["id"]
			if is_offerable(v, id2):
				pool.append(id2)
				weights.append(_offer_weight(v, d, round_no))
	var out: Array[String] = []
	var cats: Dictionary = {}
	# Guarantee: a free weapon slot gets a new weapon offer.
	if weapon_cards_owned(v) < v.weapon_slots:
		var cand: Array[int] = []
		for k in pool.size():
			if WEAPONS.has(pool[k]) and int(v.cards.get(pool[k], 0)) == 0:
				cand.append(k)
		if not cand.is_empty():
			var kk: int = _draw(rng, weights, cand)
			out.append(pool[kk])
			cats["weapon"] = 1
			_remove(pool, weights, kk)
	while out.size() < count and not pool.is_empty():
		var allowed: Array[int] = []
		for k in pool.size():
			var cat: String = str(def(pool[k])["category"])
			# a card that would be the `count`-th of one category is skipped
			if int(cats.get(cat, 0)) >= count - 1 and count >= 3:
				continue
			allowed.append(k)
		if allowed.is_empty():
			for k in pool.size():
				allowed.append(k)
		var pick: int = _draw(rng, weights, allowed)
		var pcat: String = str(def(pool[pick])["category"])
		cats[pcat] = int(cats.get(pcat, 0)) + 1
		out.append(pool[pick])
		_remove(pool, weights, pick)
	# Shuffle so the guaranteed weapon is not always first (Fisher-Yates with the world rng).
	for k in range(out.size() - 1, 0, -1):
		var m: int = rng.randi() % (k + 1)
		var tmp: String = out[k]
		out[k] = out[m]
		out[m] = tmp
	return out


static func _offer_weight(v: SimVehicle, d: Dictionary, round_no: int) -> int:
	var w: int = int(d["weight"])
	if v.card_luck > 0.0 and str(d["rarity"]) != "common":
		w = roundi(float(w) * (1.0 + v.card_luck))
	if round_no >= 1 and round_no <= EARLY_ROUNDS and str(d["category"]) == "weapon" and int(v.cards.get(str(d["id"]), 0)) == 0:
		w *= 2
	return w


## Weighted pick among the pool indices in `allowed`.
static func _draw(rng: RandomNumberGenerator, weights: Array[int], allowed: Array[int]) -> int:
	var total: int = 0
	for k in allowed:
		total += weights[k]
	var roll: int = rng.randi() % maxi(total, 1)
	for k in allowed:
		if roll < weights[k]:
			return k
		roll -= weights[k]
	return allowed[allowed.size() - 1]


static func _remove(pool: Array[String], weights: Array[int], k: int) -> void:
	pool.remove_at(k)
	weights.remove_at(k)


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
		"creduce": 0.0, "thorns": 0.0,
	}
	for id: String in v.cards:
		var d: Dictionary = def(id)
		if d.is_empty():
			continue
		var lvl: int = clampi(int(v.cards[id]), 0, MAX_LEVEL)
		var fx: Dictionary = d["fx"]
		for k: String in fx:
			st[k] = float(st.get(k, 0.0)) + float(fx[k]) * float(lvl)
	var tech_fx := {}
	var chassis: int = 1
	var eng_penalty: float = 0.0  ## negative speed of engineering nodes, scaled below
	for id in v.tech:
		if not Tech.active(v, id):
			continue
		var td: Dictionary = Tech.def(id)
		var tfx: Dictionary = td["fx"]
		for k: String in tfx:
			var a: float = float(tfx[k])
			tech_fx[k] = float(tech_fx.get(k, 0.0)) + a
			if k == "chassis":
				chassis = maxi(chassis, int(a))
			elif k == "speed" and a < 0.0 and td["branch"] == "engineering":
				eng_penalty += a
			else:
				st[k] = float(st.get(k, 0.0)) + a
	if float(tech_fx.get("no_speed_penalty", 0.0)) > 0.0:
		eng_penalty = 0.0
	elif float(tech_fx.get("speed_penalty_half", 0.0)) > 0.0:
		eng_penalty *= 0.5
	st["speed"] = float(st["speed"]) + eng_penalty
	v.tech_fx = tech_fx
	v.chassis = chassis

	var old_max: float = v.max_hp
	v.max_hp = maxf((SimVehicle.MAX_HP + float(st["hp"])) * (1.0 + float(st.get("hp_pct", 0.0))), 1.0)
	if adjust_hp and v.alive and v.max_hp > old_max:
		v.hp = minf(v.hp + (v.max_hp - old_max), v.max_hp)
	v.hp = minf(v.hp, v.max_hp)
	v.armor = float(st["armor"])
	v.speed = maxf(1.0 + float(st["speed"]), 0.3)
	v.turn_rate = maxf(1.0 + float(st["turn"]), 0.3)
	v.scrap_mult = maxf(1.0 + float(st["scrap"]), 0.0)
	v.regen = float(st["regen"])
	v.contact_damage = float(st["contact"])
	v.contact_reduction = clampf(float(st["creduce"]), 0.0, MAX_CONTACT_REDUCTION)
	v.thorns = float(st["thorns"])
	v.ram_mult = 1.0 + float(st["ram"])
	v.vulture = float(st["vulture"])
	v.weapon_slots = BASE_WEAPON_SLOTS + int(st["slots"])
	v.interest_cap = BASE_INTEREST_CAP + int(st["interest"])
	v.reroll_discount = int(st.get("reroll", 0.0))
	v.card_luck = maxf(float(st.get("luck", 0.0)), 0.0)
	if rebuild_weapons:
		_rebuild_weapons(v, st)


## Rebuilds the weapon list. `st` holds the summed fx: dmg / range / rate apply to every weapon,
## `<key>_<kind>` only to that kind (multipliers add up), pierce / pellets / splash are flat.
static func _rebuild_weapons(v: SimVehicle, st: Dictionary) -> void:
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
		var dmg_mult: float = 1.0 + float(st.get("dmg", 0.0)) + float(st.get("dmg_" + id, 0.0))
		var range_mult: float = maxf(1.0 + float(st.get("range", 0.0)) + float(st.get("range_" + id, 0.0)), 0.3)
		var rate_mult: float = maxf(1.0 + float(st.get("rate", 0.0)) + float(st.get("rate_" + id, 0.0)), 0.3)
		var base_splash: float = float((b["splash"] as Array)[li])
		fresh.append({
			"kind": id,
			"damage": float((b["damage"] as Array)[li]) * dmg_mult,
			"range": float((b["range"] as Array)[li]) * range_mult,
			"cooldown_ticks": maxf(1.0, float((b["cooldown"] as Array)[li]) / rate_mult),
			"cooldown": float(prev.get("cooldown", 0.0)),
			"aim": float(prev.get("aim", 0.0)),
			"pellets": int((b["pellets"] as Array)[li]) + int(st.get("pellets_" + id, 0.0)),
			"spread": float(b["spread"]),
			"pierce": int((b["pierce"] as Array)[li]) + int(st.get("pierce", 0.0)),
			"splash": base_splash + float(st.get("splash_" + id, 0.0)),
			"speed": float(b["speed"]),
			"heat": int(prev.get("heat", 0)),
			"jam": int(prev.get("jam", 0)),
			"sw": int(prev.get("sw", 0)),
			"shots": int(prev.get("shots", 0)),
		})
	v.weapons = fresh
	Ammo.sync(v)
