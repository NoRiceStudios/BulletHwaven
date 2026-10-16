class_name Abilities
extends RefCounted
## Active abilities (tech tree v2.3, sections 3 and 4.3 / 4.4): nitro, EMP, smoke and salvo. A rig has two
## ability slots (`v.abilities`), filled in purchase order and swappable in the workshop (`set_ability`).
## Each slot has a cooldown (`v.ab_cd`, ticks); the effects run on timers on the vehicle (`nitro_ticks`,
## `salvo_ticks`, `smoke_ticks`, `decoy_ticks`, ...). By default every ability casts itself under a fixed
## rule (see `auto_wanted`); an `ability:<id>` rig rule for that ability replaces the default, and the
## `use_ability` command casts by hand. Pure static code over SimWorld / SimVehicle; deterministic.

const IDS: PackedStringArray = ["nitro", "emp", "smoke", "salvo"]  ## index = bit in the synced / rule masks. Only append.
const SLOTS := 2
const BASE_COOLDOWN: PackedInt32Array = [180, 600, 450, 360]  ## ticks: 6 s, 20 s, 15 s, 12 s
const CD_MIN_FACTOR := 0.2  ## cooldown reductions never go below this share

const NITRO_COST := 50.0  ## momentum
const NITRO_TICKS := 60  ## 2 s
const NITRO_SPEED := 0.6  ## +60 % speed
const NITRO_TARGET_RANGE := 200.0  ## auto: a target this close ...
const NITRO_LOW_HP := 0.30  ## ... or hp below this share
const DIRTY_EVERY := 4  ## dirty fuel: every 4th nitro sputters
const SPUTTER_TICKS := 30  ## 1 s of coughing, no boost
const TRAIL_PERIOD := 6  ## ticks between puddles / smoke puffs while the nitro burns
const OIL_RADIUS := 22.0
const OIL_TICKS := 90
const OIL_SLOW_TICKS := 60  ## enemies on oil: -40 % speed for 2 s (Mobility.OIL_SLOW)
const PUFF_RADIUS := 26.0  ## dirty fuel smoke
const PUFF_TICKS := 75
const BLIND_TICKS := 30  ## aliens in smoke lose their target for 1 s
const PHANTOM_INVULN_TICKS := 15  ## 0.5 s
const DECOY_TICKS := 30  ## 1 s
const PHANTOM_KILL_CD := 15  ## each kill takes 0.5 s off the nitro cooldown ...
const PHANTOM_MIN_CD := 90  ## ... but not below 3 s

const EMP_RADIUS := 120.0
const EMP_MIN_ALIENS := 5
const EMP_STUN_TICKS := 45  ## 1.5 s
const EMP_RULES_OFF_TICKS := 90  ## rivals' rules off for 3 s

const SMOKE_HP := 0.40
const SMOKE_TICKS := 90  ## 3 s untargetable
const SMOKE_ZONE_RADIUS := 40.0
const SMOKE_ZONE_TICKS := 120

const SALVO_ALIENS := 15
const SALVO_BOULDERS := 3
const SALVO_TICKS := 60  ## 2 s
const SALVO_RATE := 0.5  ## +50 % fire rate


static func index_of(id: String) -> int:
	return IDS.find(id)


static func is_unlocked(v: SimVehicle, id: String) -> bool:
	return IDS.has(id) and float(v.tech_fx.get("ability_" + id, 0.0)) > 0.0


## Unlocked ability ids in purchase order.
static func unlocked(v: SimVehicle) -> Array[String]:
	var out: Array[String] = []
	for tid in v.tech:
		if not Tech.active(v, tid):
			continue
		var fx: Dictionary = Tech.def(tid)["fx"]
		for id in IDS:
			if fx.has("ability_" + id) and not out.has(id):
				out.append(id)
	return out


## Keeps the slots in line with the tech: a slot whose ability is gone empties, free slots fill with the
## unlocked abilities that are not equipped yet, in purchase order. Called by Cards.recompute().
static func sync(v: SimVehicle) -> void:
	if v.abilities.size() != SLOTS:
		v.abilities = ["", ""]
	if v.ab_cd.size() != SLOTS:
		v.ab_cd = PackedInt32Array([0, 0])
	var un: Array[String] = unlocked(v)
	for s in SLOTS:
		if v.abilities[s] != "" and not un.has(v.abilities[s]):
			v.abilities[s] = ""
			v.ab_cd[s] = 0
	for id in un:
		if v.abilities.has(id):
			continue
		var s: int = v.abilities.find("")
		if s < 0:
			break
		v.abilities[s] = id
		v.ab_cd[s] = 0


## Swaps `id` into `slot` (workshop). An ability already equipped in the other slot trades places with it.
static func set_slot(v: SimVehicle, slot: int, id: String) -> bool:
	if slot < 0 or slot >= SLOTS or not is_unlocked(v, id):
		return false
	var other: int = v.abilities.find(id)
	if other == slot:
		return true
	if other >= 0:
		v.abilities[other] = v.abilities[slot]
		var cd: int = v.ab_cd[other]
		v.ab_cd[other] = v.ab_cd[slot]
		v.ab_cd[slot] = cd
	v.abilities[slot] = id
	if other < 0:
		v.ab_cd[slot] = 0
	return true


## Cooldown of ability `id` for `v` in ticks (electronics_overclock shortens it).
static func cooldown_for(v: SimVehicle, id: String) -> int:
	var f: float = maxf(1.0 + float(v.tech_fx.get("ability_cd", 0.0)), CD_MIN_FACTOR)
	return maxi(1, roundi(float(BASE_COOLDOWN[IDS.find(id)]) * f))


static func slot_of(v: SimVehicle, id: String) -> int:
	return v.abilities.find(id)


## Off cooldown and (nitro) enough momentum.
static func is_ready(v: SimVehicle, id: String) -> bool:
	var s: int = v.abilities.find(id)
	if s < 0 or v.ab_cd[s] > 0 or not v.alive:
		return false
	if id == "nitro":
		return v.momentum >= NITRO_COST and v.nitro_ticks <= 0 and v.sputter_ticks <= 0
	return true


## True if any equipped ability can be cast now (the `ability_ready` rule condition).
static func any_ready(v: SimVehicle) -> bool:
	for id in v.abilities:
		if id != "" and is_ready(v, id):
			return true
	return false


## Speed multiplier from a burning nitro (a sputtering one gives none).
static func speed_mult(v: SimVehicle) -> float:
	return 1.0 + NITRO_SPEED if v.nitro_ticks > 0 else 1.0


# ---------------------------------------------------------------- per tick

## Counts the timers down, lays the nitro trail (smoke with dirty fuel, oil with slipstream).
static func tick(w: SimWorld, v: SimVehicle) -> void:
	for s in SLOTS:
		if v.ab_cd[s] > 0:
			v.ab_cd[s] -= 1
	if v.salvo_ticks > 0:
		v.salvo_ticks -= 1
	if v.smoke_ticks > 0:
		v.smoke_ticks -= 1
	if v.decoy_ticks > 0:
		v.decoy_ticks -= 1
	if v.rules_off_ticks > 0:
		v.rules_off_ticks -= 1
	if v.sputter_ticks > 0:
		v.sputter_ticks -= 1
	if v.nitro_ticks > 0:
		v.nitro_ticks -= 1
		if (w.tick + v.id) % TRAIL_PERIOD == 0:
			_trail(w, v)


static func _trail(w: SimWorld, v: SimVehicle) -> void:
	var fx: Dictionary = v.tech_fx
	if float(fx.get("dirty_fuel", 0.0)) > 0.0:
		w._add_zone(v.pos, PUFF_RADIUS, SimWorld.ZONE_SMOKE, PUFF_TICKS, v.id)
	if float(fx.get("slipstream", 0.0)) > 0.0:
		w._add_zone(v.pos, OIL_RADIUS, SimWorld.ZONE_OIL, OIL_TICKS, v.id)


## Phantom drive: every kill takes 0.5 s off the nitro cooldown, never below 3 s.
static func on_kill(v: SimVehicle) -> void:
	if float(v.tech_fx.get("phantom", 0.0)) <= 0.0:
		return
	var s: int = v.abilities.find("nitro")
	if s >= 0 and v.ab_cd[s] > PHANTOM_MIN_CD:
		v.ab_cd[s] = maxi(PHANTOM_MIN_CD, v.ab_cd[s] - PHANTOM_KILL_CD)


## Drops all running effects (destroyed, respawned, new round).
static func clear_effects(v: SimVehicle) -> void:
	v.nitro_ticks = 0
	v.sputter_ticks = 0
	v.salvo_ticks = 0
	v.smoke_ticks = 0
	v.decoy_ticks = 0
	v.rules_off_ticks = 0


## Start of a combat round: effects and cooldowns reset.
static func reset_round(v: SimVehicle) -> void:
	clear_effects(v)
	v.ab_cd[0] = 0
	v.ab_cd[1] = 0
	v.boom_cd = 0
	v.momentum = 0.0


# ---------------------------------------------------------------- casting

## The default auto-cast rule of `id` (design doc 4.3 / 4.4); the ability must already be ready.
static func auto_wanted(w: SimWorld, v: SimVehicle, id: String) -> bool:
	match id:
		"nitro":
			if v.hp < NITRO_LOW_HP * v.max_hp:
				return true
			return v.target_kind != 0 and v.pos.distance_squared_to(v.target_pos) <= NITRO_TARGET_RANGE * NITRO_TARGET_RANGE
		"emp":
			return w.query_enemies(v.pos, EMP_RADIUS, w.ai_buf) >= EMP_MIN_ALIENS
		"smoke":
			return v.hp < SMOKE_HP * v.max_hp
		"salvo":
			var n: int = w.query_enemies(v.pos, Doctrine.SWARM_RADIUS, w.ai_buf)
			if n >= SALVO_ALIENS:
				return true
			var boulders: int = 0
			for q in n:
				if w.enemy_kind[w.ai_buf[q]] == SimWorld.BOULDER:
					boulders += 1
			return boulders >= SALVO_BOULDERS
	return false


## Casts every ready ability whose rule says so: an `ability:<id>` rule when the rig has one for it, else
## the default rule.
static func auto_cast(w: SimWorld, v: SimVehicle) -> void:
	for s in SLOTS:
		var id: String = v.abilities[s]
		if id == "" or v.ab_cd[s] > 0:
			continue
		var bit: int = 1 << IDS.find(id)
		if (v.ab_rule_any & bit) != 0:
			if (v.ab_rule_hit & bit) != 0:
				cast(w, v, id)
		elif is_ready(v, id) and auto_wanted(w, v, id):
			cast(w, v, id)


## Casts `id` now (cooldown and cost apply). Returns false if it is not equipped or not ready.
static func cast(w: SimWorld, v: SimVehicle, id: String) -> bool:
	if not is_ready(v, id):
		return false
	var s: int = v.abilities.find(id)
	match id:
		"nitro":
			v.momentum -= NITRO_COST
			v.nitro_count += 1
			var fx: Dictionary = v.tech_fx
			var sputter: bool = float(fx.get("dirty_fuel", 0.0)) > 0.0 and v.nitro_count % DIRTY_EVERY == 0
			if sputter:
				v.sputter_ticks = SPUTTER_TICKS
				w._add_zone(v.pos, PUFF_RADIUS, SimWorld.ZONE_SMOKE, PUFF_TICKS, v.id)
			else:
				v.nitro_ticks = NITRO_TICKS
			if float(fx.get("phantom", 0.0)) > 0.0:
				v.invuln_ticks = maxi(v.invuln_ticks, PHANTOM_INVULN_TICKS)
				v.decoy_ticks = DECOY_TICKS
				v.decoy_pos = v.pos
			w._emit("nitro", v.pos, v.id, 1 if sputter else 0)
		"emp":
			var cnt: int = w.query_enemies(v.pos, EMP_RADIUS, w.ai_buf)
			for q in cnt:
				w.stun_enemy(w.ai_buf[q], EMP_STUN_TICKS)
			if w.pvp_enabled():
				var reach: float = EMP_RADIUS + SimVehicle.RADIUS
				for o in w.vehicles:
					if o != v and o.alive and o.invuln_ticks <= 0 and v.pos.distance_squared_to(o.pos) <= reach * reach:
						o.rules_off_ticks = EMP_RULES_OFF_TICKS
			w._emit("emp", v.pos, v.id, 0)
		"smoke":
			v.smoke_ticks = SMOKE_TICKS
			w._add_zone(v.pos, SMOKE_ZONE_RADIUS, SimWorld.ZONE_SMOKE, SMOKE_ZONE_TICKS, v.id)
			w._emit("smoke", v.pos, v.id, 0)
		"salvo":
			v.salvo_ticks = SALVO_TICKS
			w._emit("salvo", v.pos, v.id, 0)
		_:
			return false
	v.ab_cd[s] = cooldown_for(v, id)
	return true
