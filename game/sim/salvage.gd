class_name Salvage
extends RefCounted
## Salvage branch mechanics (tech tree v2.3, section 4.5): contracts (offered at the workshop start, accepted by
## command, tracked in combat, paid when the combat ends), the haggler's reserved card, the loan shark, insurance
## and jerrycans on death, the scrap press, the baron's damage bonus and the raider's PvP scrap theft. Pure static
## code over SimWorld / SimVehicle; deterministic (randomness only through `world.rng`).

# Contract kinds (index = the byte in snapshots; only append).
const K_BOULDERS := 0  ## kill N boulders
const K_SPITTERS := 1  ## kill N spitters
const K_ALIENS := 2  ## kill N aliens
const K_RAM := 3  ## deal N ram damage
const K_NO_DEATH := 4  ## do not get destroyed this round (also pays +4 fuel)
const K_LEADER := 5  ## bounty office, PvP: hit the leader 10 times
const K_COUNT := 6
const K_NAMES: PackedStringArray = ["BOULDERS", "SPITTERS", "ALIENS", "RAM", "NO DEATH", "LEADER"]

const REWARD_MIN := 40
const REWARD_MAX := 80
const NO_DEATH_FUEL := 4
const LEADER_HITS := 10
const LEADER_REWARD := 150
const MAX_OFFERS := 2

const LOAN_PAYOUT := 250
const LOAN_INSTALMENT := 110
const LOAN_INSTALMENTS := 3
const LOAN_DEBT := LOAN_INSTALMENT * LOAN_INSTALMENTS
const LOAN_SHORTFALL_RATE := 0.10  ## the unpaid part of an instalment grows by this

const HOARDER_CAP_BONUS := 10  ## hoarder: cap 15 + 6 x round instead of 5 + 2 x round (the 5 are the base cap)
const HOARDER_CAP_PER_ROUND := 6
const HOARDER_PCT := 12

const PRESS_PER_LEVEL := 50
const SAW_DAMAGE := 20.0
const SAW_SPEED := 240.0
const SAW_TTL := 1.4
const SAW_PIERCE := 2

const JERRY_RADIUS := 50.0
const JERRY_DAMAGE := 40.0
const JERRY_FIRE_RADIUS := 30.0
const JERRY_FIRE_TICKS := 90

const BARON_STEP := 100  ## scrap per step
const BARON_PER_STEP := 0.03
const BARON_MAX := 0.24
const BARON_LOOT := 0.10  ## the killer of a baron takes this share of its scrap
const RAID_PER_SCRAP := 20.0  ## raider: damage per stolen scrap
const BOUNTY_MULT := 2  ## bounty office doubles the player-kill bounty


# ---------------------------------------------------------------- contracts

## Contract offers per workshop: the summed `contracts` fx (hooks 1, black market +1), at most 2, and `contracts_max`
## (the raider) as a ceiling.
static func offer_count(v: SimVehicle) -> int:
	var n: int = int(v.tech_fx.get("contracts", 0.0))
	if v.tech_fx.has("contracts_max"):
		n = mini(n, int(v.tech_fx["contracts_max"]))
	return clampi(n, 0, MAX_OFFERS)


## The contract kinds that can be offered for combat round `r` (deterministic order).
static func _pool(w: SimWorld, v: SimVehicle, r: int) -> Array[int]:
	var out: Array[int] = [K_ALIENS, K_NO_DEATH]
	if r >= 3:
		out.append(K_BOULDERS)
	if r >= SimWorld.SPITTER_MIN_ROUND:
		out.append(K_SPITTERS)
	if v.thorns > 0.0 or v.contact_damage > 0.0 or v.ram_mult > 1.0 or str(v.doctrine.get("drive", "")) == "charge":
		out.append(K_RAM)
	if float(v.tech_fx.get("bounty_office", 0.0)) > 0.0 and r >= SimWorld.PVP_START_ROUND:
		var alive: int = 0
		for o in w.vehicles:
			if not o.eliminated:
				alive += 1
		if alive >= 2:
			out.append(K_LEADER)
	return out


## Need and base reward (scrap) of a contract of `kind` in combat round `r`.
static func make(kind: int, r: int) -> Vector3i:
	var need: int = 1
	var reward: int = REWARD_MIN
	match kind:
		K_BOULDERS:
			need = 3 + r / 4
			reward = 50 + 3 * r
		K_SPITTERS:
			need = 3 + r / 3
			reward = 55 + 3 * r
		K_ALIENS:
			need = 20 + 6 * r
			reward = 40 + 3 * r
		K_RAM:
			need = 120 + 40 * r
			reward = 45 + 3 * r
		K_NO_DEATH:
			need = 1
			reward = 40 + 2 * r
		K_LEADER:
			return Vector3i(kind, LEADER_HITS, LEADER_REWARD)
	return Vector3i(kind, need, clampi(reward, REWARD_MIN, REWARD_MAX))


## Workshop start: draws fresh offers (replacing unaccepted ones) with the world rng. No draw without the tech.
static func roll(w: SimWorld, v: SimVehicle) -> void:
	v.contract_offers = []
	var n: int = offer_count(v)
	if n <= 0:
		return
	var r: int = w.round + 1  # the combat that follows
	var pool: Array[int] = _pool(w, v, r)
	for _i in n:
		if pool.is_empty():
			break
		var k: int = pool.pop_at(w.rng.randi() % pool.size())
		v.contract_offers.append(make(k, r))


## Accepts offer `idx`: it becomes the active contract and the other offers go. Workshop only (the caller checks).
static func accept(v: SimVehicle, idx: int) -> bool:
	if idx < 0 or idx >= v.contract_offers.size() or v.contract_kind >= 0:
		return false
	var o: Vector3i = v.contract_offers[idx]
	v.contract_kind = o.x
	v.contract_need = o.y
	v.contract_reward = o.z
	v.contract_prog = 0.0
	v.contract_offers = []
	return true


## Scrap a finished contract pays: the base reward scaled by contract_bonus (Lucky Charm, Salvage Crane).
static func payout(v: SimVehicle, base: int) -> int:
	return roundi(float(base) * (1.0 + float(v.tech_fx.get("contract_bonus", 0.0))))


static func is_done(v: SimVehicle) -> bool:
	if v.contract_kind < 0:
		return false
	if v.contract_kind == K_NO_DEATH:
		return v.contract_prog >= 0.0
	return v.contract_prog >= float(v.contract_need)


## An alien of `ekind` was killed by `v`.
static func on_kill(v: SimVehicle, ekind: int) -> void:
	match v.contract_kind:
		K_BOULDERS:
			if ekind == SimWorld.BOULDER:
				v.contract_prog += 1.0
		K_SPITTERS:
			if ekind == SimWorld.SPITTER:
				v.contract_prog += 1.0
		K_ALIENS:
			v.contract_prog += 1.0


## `v` was destroyed: a no-death contract fails.
static func on_destroyed(v: SimVehicle) -> void:
	if v.contract_kind == K_NO_DEATH:
		v.contract_prog = -1.0


## Combat end: pays a fulfilled contract (scrap, +fuel_per_contract, +4 fuel for a no-death one) and clears it.
static func settle(w: SimWorld, v: SimVehicle) -> void:
	if v.contract_kind < 0:
		return
	if is_done(v):
		var scrap: int = payout(v, v.contract_reward)
		v.scrap += scrap
		w._note_scrap(v, scrap)
		var fuel: int = int(v.tech_fx.get("fuel_per_contract", 0.0))
		if v.contract_kind == K_NO_DEATH:
			fuel += NO_DEATH_FUEL
		v.fuel += fuel
		w._emit("contract_done", v.pos, v.id, v.contract_kind)
	v.contract_kind = -1
	v.contract_need = 0
	v.contract_reward = 0
	v.contract_prog = 0.0


# ---------------------------------------------------------------- haggler

## Reserves offer `idx` for the next workshop (the same index again takes the reservation back).
static func reserve(v: SimVehicle, idx: int) -> bool:
	if float(v.tech_fx.get("reserve_card", 0.0)) <= 0.0 or v.picked or idx < 0 or idx >= v.offers.size():
		return false
	var id: String = v.offers[idx]
	v.reserved_card = "" if v.reserved_card == id else id
	return true


## Workshop start, after the offers were drawn: the reserved card takes the last offer slot (if it can still be
## offered and is not there already). The reservation is used up either way.
static func apply_reserve(v: SimVehicle) -> void:
	var id: String = v.reserved_card
	v.reserved_card = ""
	if id == "" or v.offers.is_empty() or v.offers.has(id) or not Cards.is_offerable(v, id):
		return
	v.offers[v.offers.size() - 1] = id


# ---------------------------------------------------------------- loan

## Called by Tech.buy with the bought node's fx: the loan shark pays out at once and starts the debt.
static func on_buy(v: SimVehicle, fx: Dictionary) -> void:
	if fx.has("loan"):
		v.scrap += LOAN_PAYOUT
		v.loan_debt += LOAN_DEBT
		v.loan_left = LOAN_INSTALMENTS


## Workshop start: one instalment (110; the last one takes whatever is owed). What the scrap cannot cover is
## carried with +10 % and never blocks buying. Keeps running after the loan node is respecced away.
static func repay(w: SimWorld, v: SimVehicle) -> void:
	if v.loan_debt <= 0:
		v.loan_debt = 0
		v.loan_left = 0
		return
	var due: int = mini(LOAN_INSTALMENT, v.loan_debt) if v.loan_left > 1 else v.loan_debt
	var paid: int = mini(due, v.scrap)
	v.scrap -= paid
	v.loan_debt -= paid
	var short: int = due - paid
	if short > 0:
		v.loan_debt += ceili(float(short) * LOAN_SHORTFALL_RATE)
	v.loan_left = maxi(v.loan_left - 1, 1) if v.loan_debt > 0 else 0


# ---------------------------------------------------------------- hoarder

static func is_hoarder(v: SimVehicle) -> bool:
	return float(v.tech_fx.get("hoarder", 0.0)) > 0.0


# ---------------------------------------------------------------- scrap press

## Scraps one level of card `id` (workshop): credits level x 50 and sends a saw blade into the next combat.
## The last weapon card cannot be scrapped. Returns false when it is not allowed.
static func scrap_card(v: SimVehicle, id: String) -> bool:
	if float(v.tech_fx.get("scrap_press", 0.0)) <= 0.0 or not v.cards.has(id):
		return false
	var lvl: int = int(v.cards[id])
	if lvl < 1 or Cards.is_evolution(id):
		return false
	if Cards.is_weapon(id) and lvl <= 1 and Cards.weapon_cards_owned(v) <= 1:
		return false
	if lvl <= 1:
		v.cards.erase(id)
	else:
		v.cards[id] = lvl - 1
	v.scrap += lvl * PRESS_PER_LEVEL
	v.saws += 1
	Cards.recompute(v)
	return true


## Combat start: every scrapped card flies off as a saw blade in a random direction.
static func launch_saws(w: SimWorld, v: SimVehicle) -> void:
	for _i in v.saws:
		var dir: Vector2 = Vector2.from_angle(w.rng.randf() * TAU)
		w.spawn_projectile(v.pos + dir * SimWorld.MUZZLE_OFFSET, dir * SAW_SPEED, SAW_TTL, SAW_DAMAGE, v.id, SAW_PIERCE)
		w._emit("saw", v.pos, v.id, 0)
	v.saws = 0


# ---------------------------------------------------------------- baron and raider

## Scrap baron: +3 % damage per 100 scrap held, at most +24 %. 1.0 without the tech.
static func baron_mult(v: SimVehicle) -> float:
	if float(v.tech_fx.get("baron", 0.0)) <= 0.0:
		return 1.0
	return 1.0 + minf(float(v.scrap / BARON_STEP) * BARON_PER_STEP, BARON_MAX)


## Raider: `applied` damage dealt to rival `victim` moves 1 scrap per 20 damage from the victim to `av`.
static func raid(w: SimWorld, av: SimVehicle, victim: SimVehicle, applied: float) -> void:
	if float(av.tech_fx.get("raider", 0.0)) <= 0.0 or applied <= 0.0:
		return
	av.raid_acc += applied
	var n: int = int(av.raid_acc / RAID_PER_SCRAP)
	if n <= 0:
		return
	av.raid_acc -= float(n) * RAID_PER_SCRAP
	var take: int = mini(n, victim.scrap)
	if take <= 0:
		return
	victim.scrap -= take
	av.scrap += take
	w._note_scrap(av, take)


# ---------------------------------------------------------------- death

## `v` was destroyed: insurance pays, the jerrycans explode.
static func on_death(w: SimWorld, v: SimVehicle) -> void:
	var fx: Dictionary = v.tech_fx
	if fx.is_empty():
		return
	var ins: int = int(fx.get("insurance", 0.0))
	if ins > 0:
		v.scrap += ins
		w._note_scrap(v, ins)
	if float(fx.get("jerry_blast", 0.0)) > 0.0:
		w._splash_damage(v.pos, JERRY_RADIUS, JERRY_DAMAGE, v.id, -1)
		w._add_zone(v.pos, JERRY_FIRE_RADIUS, SimWorld.ZONE_FIRE, JERRY_FIRE_TICKS, v.id)
		if w.pvp_enabled():
			var reach: float = JERRY_RADIUS + SimVehicle.RADIUS
			for o in w.vehicles:
				if o != v and o.alive and o.invuln_ticks <= 0 and v.pos.distance_squared_to(o.pos) <= reach * reach:
					w._damage_vehicle(o, JERRY_DAMAGE, v.id, true, SimWorld.SRC_RAM)
		w._emit("jerry_blast", v.pos, v.id, 0)


## A baron was destroyed by player `killer`: it takes 10 % of the baron's scrap.
static func loot_baron(w: SimWorld, killer: SimVehicle, victim: SimVehicle) -> void:
	if float(victim.tech_fx.get("baron", 0.0)) <= 0.0:
		return
	var take: int = int(float(victim.scrap) * BARON_LOOT)
	if take <= 0:
		return
	victim.scrap -= take
	killer.scrap += take
	w._note_scrap(killer, take)
