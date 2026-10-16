class_name Ammo
extends RefCounted
## Ballistics ammo (tech tree v2.3, section 4.1): which ammo types a rig has unlocked, what each weapon
## kind has loaded (`v.ammo`: weapon kind -> Array of ammo ids, index 0 = primary), auto-loading when
## a type is unlocked and switching. The effects themselves (burn, shards, armour piercing) live in
## SimWorld. Pure data and static functions; deterministic.

const IDS: PackedStringArray = ["fire", "shrapnel", "ap"]  ## canonical order; the tech flags are "ammo_<id>"
const FIRE_BIT := 1
const SHRAPNEL_BIT := 2
const AP_BIT := 4
const SHARD_BIT := 8  ## marks a shrapnel shard itself (never shatters again, never executes)
const EVO_BIT := 16  ## marks a shot of an evolved weapon (Cards.EVOLVED); not an ammo type, ignored by effect_scale
const SWITCH_TICKS := 30  ## the weapon is silent this long after a switch (1 s) unless ammo_instant
const MIXED_FACTOR := 0.7  ## mixed belts: every loaded effect works at this fraction
const AP_BONUS := 0.5  ## armour piercing: extra damage fraction vs boulders and rival vehicles


static func bit(id: String) -> int:
	match id:
		"fire":
			return FIRE_BIT
		"shrapnel":
			return SHRAPNEL_BIT
		"ap":
			return AP_BIT
	return 0


static func is_valid_id(id: String) -> bool:
	return IDS.has(id)


static func is_unlocked(v: SimVehicle, id: String) -> bool:
	return IDS.has(id) and float(v.tech_fx.get("ammo_" + id, 0.0)) > 0.0


## Unlocked ammo ids in canonical order.
static func unlocked(v: SimVehicle) -> Array[String]:
	var out: Array[String] = []
	for id in IDS:
		if is_unlocked(v, id):
			out.append(id)
	return out


## How many ammo types one weapon loads at once (2 with mixed belts).
static func max_loaded(v: SimVehicle) -> int:
	return 2 if float(v.tech_fx.get("mixed_belts", 0.0)) > 0.0 else 1


## Bit mask of what weapon kind `kind` has loaded.
static func mask(v: SimVehicle, kind: String) -> int:
	var m: int = 0
	var list: Variant = v.ammo.get(kind)
	if list != null:
		for id: String in list:
			m |= bit(id)
	return m


## Strength of the ammo effects for a loaded `m` mask: 1 + ammo_fx, times MIXED_FACTOR with two types.
static func effect_scale(v: SimVehicle, m: int) -> float:
	m &= ~EVO_BIT
	var s: float = 1.0 + float(v.tech_fx.get("ammo_fx", 0.0))
	if (m & (m - 1)) != 0:  # more than one bit set
		s *= MIXED_FACTOR
	return s


static func _load_list(old: Array, id: String, cap: int) -> Array[String]:
	var out: Array[String] = [id]
	for o: String in old:
		if o != id and out.size() < cap:
			out.append(o)
	return out


## Brings `v.ammo` in line with the unlocked types after a recompute (workshop, never mid-fight, so no
## switch delay): drops what is no longer unlocked, auto-loads newly unlocked types (the first type
## everywhere, every later one into the last ceil(n/2) weapons), fills mixed belts to two types and
## gives every weapon at least the first unlocked type.
static func sync(v: SimVehicle) -> void:
	var unl: Array[String] = unlocked(v)
	var prev: Array[String] = v.ammo_known
	var cap: int = max_loaded(v)
	var kinds: Array[String] = []
	for w in v.weapons:
		kinds.append(str(w["kind"]))
	var ammo := {}
	for k in kinds:
		var keep: Array[String] = []
		var cur: Variant = v.ammo.get(k)
		if cur != null:
			for id: String in cur:
				if unl.has(id) and not keep.has(id):
					keep.append(id)
		ammo[k] = keep
	for id in unl:
		if prev.has(id):
			continue
		var from: int = 0
		if not prev.is_empty():
			from = kinds.size() - ceili(float(kinds.size()) / 2.0)
		for i in range(from, kinds.size()):
			ammo[kinds[i]] = _load_list(ammo[kinds[i]], id, cap)
	for k in kinds:
		var list: Array[String] = ammo[k]
		if list.is_empty() and not unl.is_empty():
			list.append(unl[0])
		if cap > 1 and list.size() < cap:
			for id in unl:
				if list.size() < cap and not list.has(id):
					list.append(id)
		while list.size() > cap:
			list.pop_back()
		ammo[k] = list
	v.ammo = ammo
	v.ammo_known = unl


## Makes `id` the primary ammo of weapon kind `kind`. Returns false (and changes nothing) if the weapon
## is not there, the ammo is not unlocked or already primary. Loading a type that was not loaded starts
## the SWITCH_TICKS pause unless ammo_instant; with mixed belts the old primary becomes the second type.
static func select(v: SimVehicle, kind: String, id: String) -> bool:
	if not is_unlocked(v, id) or not v.ammo.has(kind):
		return false
	var cur: Array = v.ammo[kind]
	if not cur.is_empty() and cur[0] == id:
		return false
	var was_loaded: bool = cur.has(id)
	v.ammo[kind] = _load_list(cur, id, max_loaded(v))
	if not was_loaded and float(v.tech_fx.get("ammo_instant", 0.0)) <= 0.0:
		for w in v.weapons:
			if str(w["kind"]) == kind:
				w["sw"] = SWITCH_TICKS
	return true
