extends TestCase
## Tech tree v2.3 stage 3, the Salvage branch: contracts (offers, accept, progress, payout, bonuses, PvP leader contract),
## haggler's reserved card, loan shark, insurance, jerrycans, scrap press, hoarder, baron, raider, snapshot and determinism.

const HOOKS: Array = ["salvage_hooks"]
const HAGGLER: Array = ["salvage_hooks", "salvage_haggler"]
const LUCKY: Array = ["salvage_hooks", "salvage_lucky"]
const LOAN: Array = ["salvage_hooks", "salvage_loan"]
const MARKET: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market"]
const INSURANCE: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_insurance"]
const JERRY: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_jerrycans"]
const PRESS: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_press"]
const HOARDER: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_hoarder"]
const CRANE: Array = ["salvage_hooks", "salvage_lucky", "salvage_black_market", "salvage_jerrycans", "salvage_crane"]
const BOUNTY: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_hoarder", "salvage_bounty"]
const BARON: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_hoarder", "salvage_crane", "salvage_baron"]
const RAIDER: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_hoarder", "salvage_crane", "salvage_raider"]


func _buy(v: SimVehicle, ids: Array) -> void:
	v.scrap = 99999
	for id: String in ids:
		assert_true(Tech.buy(v, id, 1), "buy " + id)


## A one-rig world (round 1, no spawner, fast rounds) with the tech `ids`; the rig is tough and stands still.
func _world(ids: Array, p_seed: int = 7) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	w.fast_rounds = true
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	_buy(v, ids)
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	v.invuln_ticks = 0
	v.scrap = 1000
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


## Two rigs in PvP (round 4, no grace); `a` has the tech `ids`, `b` stands 150 px east.
func _duel(ids: Array) -> SimWorld:
	var w := SimWorld.new(9)
	w.spawning_enabled = false
	w.fast_rounds = true
	w.round = 4
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	var b: SimVehicle = w.add_vehicle(2, Vector2(1150, 700))
	_buy(a, ids)
	for v: SimVehicle in [a, b]:
		v.max_hp = 1.0e6
		v.hp = 1.0e6
		v.invuln_ticks = 0
		v.scrap = 1000
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	w.apply_command(2, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


func _to_workshop(w: SimWorld) -> void:
	for t in 4000:
		if w.phase == SimWorld.PHASE_WORKSHOP:
			return
		w.step()
	assert_true(false, "workshop never started")


## Ends the workshop (everybody ready) and runs the combat to the next workshop.
func _next_workshop(w: SimWorld) -> void:
	for v in w.vehicles:
		w.apply_command(v.peer_id, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	_to_workshop(w)


func _enemy(w: SimWorld, kind: int, dx: float, hp: float, dy: float = 0.0) -> int:
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(kind, v.pos + Vector2(dx, dy))
	var i: int = w.enemy_count - 1
	w.enemy_hp[i] = hp
	w.rebuild_derived()
	return i


func _count_events(w: SimWorld, type: String) -> int:
	var c: int = 0
	for e in w.events:
		if e["type"] == type:
			c += 1
	return c


# ---------------------------------------------------------------- contracts

func test_offers_follow_the_tech() -> void:
	var none: SimWorld = _world([])
	_to_workshop(none)
	assert_eq(none.vehicles[0].contract_offers.size(), 0, "no tech, no offers")
	var one: SimWorld = _world(HOOKS)
	_to_workshop(one)
	assert_eq(one.vehicles[0].contract_offers.size(), 1, "scrap hooks: one offer")
	var two: SimWorld = _world(MARKET)
	_to_workshop(two)
	assert_eq(two.vehicles[0].contract_offers.size(), 2, "black market: two offers")
	assert_ne(two.vehicles[0].contract_offers[0].x, two.vehicles[0].contract_offers[1].x, "two different kinds")
	var raider: SimWorld = _world(RAIDER)
	_to_workshop(raider)
	assert_eq(raider.vehicles[0].contract_offers.size(), 1, "raider: contracts_max 1")


func test_offer_values_are_in_range() -> void:
	for r in [1, 2, 3, 5, 8, 12, 20]:
		for k in [Salvage.K_BOULDERS, Salvage.K_SPITTERS, Salvage.K_ALIENS, Salvage.K_RAM, Salvage.K_NO_DEATH]:
			var c: Vector3i = Salvage.make(k, r)
			assert_true(c.z >= 40 and c.z <= 80, "reward %d of kind %d round %d" % [c.z, k, r])
			assert_true(c.y >= 1)
	assert_eq(Salvage.make(Salvage.K_LEADER, 5), Vector3i(Salvage.K_LEADER, 10, 150))
	# Early rounds only offer what can happen: no boulders before round 3, no spitters before SPITTER_MIN_ROUND.
	var w: SimWorld = _world(MARKET)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	for o in v.contract_offers:
		assert_true(o.x == Salvage.K_ALIENS or o.x == Salvage.K_NO_DEATH or o.x == Salvage.K_RAM, "round 2 pool, got kind %d" % o.x)


func test_accept_contract_command() -> void:
	var w: SimWorld = _world(MARKET)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	var chosen: Vector3i = v.contract_offers[1]
	w.apply_command(1, {"type": "accept_contract", "value": 5})
	assert_eq(v.contract_kind, -1, "bad index ignored")
	w.apply_command(1, {"type": "accept_contract", "value": 1})
	assert_eq(v.contract_kind, chosen.x)
	assert_eq(v.contract_need, chosen.y)
	assert_eq(v.contract_reward, chosen.z)
	assert_true(v.contract_offers.is_empty(), "the other offer is gone")
	# Not in combat.
	var w2: SimWorld = _world(HOOKS)
	_to_workshop(w2)
	w2.apply_command(1, {"type": "ready"})
	w2.step()
	w2.vehicles[0].contract_offers = [Salvage.make(Salvage.K_ALIENS, 2)]
	w2.apply_command(1, {"type": "accept_contract", "value": 0})
	assert_eq(w2.vehicles[0].contract_kind, -1, "workshop only")


func test_contract_progress_and_payout() -> void:
	var w: SimWorld = _world(HOOKS)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	v.contract_offers = [Vector3i(Salvage.K_ALIENS, 3, 60)]
	w.apply_command(1, {"type": "accept_contract", "value": 0})
	w.apply_command(1, {"type": "ready"})
	w.step()
	for k in 3:
		var i: int = _enemy(w, SimWorld.MITE, 50.0 + 10.0 * float(k), 1.0)
		w._hit_enemy(i, 10.0, v.id)
	assert_eq(v.contract_prog, 3.0)
	assert_true(Salvage.is_done(v))
	var before: int = v.scrap
	var events: int = 0
	for t in 4000:
		w.step()
		events += _count_events(w, "contract_done")
		if w.phase == SimWorld.PHASE_WORKSHOP:
			break
	assert_eq(events, 1, "contract_done event")
	assert_true(v.scrap >= before + 60, "paid 60 (+ interest): %d vs %d" % [v.scrap, before])
	assert_eq(v.contract_kind, -1, "cleared")


func test_contract_unfinished_pays_nothing() -> void:
	var w: SimWorld = _world(HOOKS)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	v.scrap = 0
	v.contract_offers = [Vector3i(Salvage.K_ALIENS, 30, 60)]
	w.apply_command(1, {"type": "accept_contract", "value": 0})
	_next_workshop(w)
	assert_eq(v.scrap, 0, "nothing paid")
	assert_eq(v.contract_kind, -1)


func test_contract_kinds_count_the_right_things() -> void:
	var w: SimWorld = _world(HOOKS)
	var v: SimVehicle = w.vehicles[0]
	v.contract_kind = Salvage.K_BOULDERS
	v.contract_need = 2
	var m: int = _enemy(w, SimWorld.MITE, 60.0, 1.0)
	var b: int = _enemy(w, SimWorld.BOULDER, 70.0, 1.0)
	var s: int = _enemy(w, SimWorld.SPITTER, 80.0, 1.0)
	w._hit_enemy(m, 5.0, v.id)
	w._hit_enemy(s, 5.0, v.id)
	assert_eq(v.contract_prog, 0.0, "only boulders count")
	w._hit_enemy(b, 500.0, v.id)
	assert_eq(v.contract_prog, 1.0)
	v.contract_kind = Salvage.K_SPITTERS
	v.contract_prog = 0.0
	var s2: int = _enemy(w, SimWorld.SPITTER, 90.0, 1.0)
	w._hit_enemy(s2, 5.0, v.id)
	assert_eq(v.contract_prog, 1.0)
	# ram damage counts only as ram damage
	v.contract_kind = Salvage.K_RAM
	v.contract_prog = 0.0
	var r: int = _enemy(w, SimWorld.MITE, 100.0, 1000.0)
	w._hit_enemy(r, 7.0, v.id)
	assert_eq(v.contract_prog, 0.0, "a shot is not a ram")
	w._hit_enemy(r, 7.0, v.id, true)
	assert_eq(v.contract_prog, 7.0)


func test_no_death_contract_fails_on_death_and_pays_fuel() -> void:
	var w: SimWorld = _world(HOOKS)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	v.contract_offers = [Vector3i(Salvage.K_NO_DEATH, 1, 50)]
	w.apply_command(1, {"type": "accept_contract", "value": 0})
	w.apply_command(1, {"type": "ready"})
	w.step()
	var fuel: int = v.fuel
	var scrap: int = v.scrap
	_to_workshop(w)
	assert_eq(v.fuel, fuel + Salvage.NO_DEATH_FUEL, "+4 fuel")
	assert_true(v.scrap >= scrap + 50)
	# a death fails it
	v.contract_offers = [Vector3i(Salvage.K_NO_DEATH, 1, 50)]
	w.apply_command(1, {"type": "accept_contract", "value": 0})
	w.apply_command(1, {"type": "ready"})
	w.step()
	v.invuln_ticks = 0
	w._damage_vehicle(v, 1.0e9, -1)
	assert_false(v.alive)
	assert_eq(v.contract_prog, -1.0, "failed")
	assert_false(Salvage.is_done(v))
	fuel = v.fuel
	_to_workshop(w)
	assert_eq(v.fuel, fuel, "no payout")


func test_contract_bonus_and_fuel_per_contract() -> void:
	# Lucky Charm +25 %, Salvage Crane +20 % (stack), Spare Jerrycans +1 fuel per contract.
	var w: SimWorld = _world(CRANE)
	var v: SimVehicle = w.vehicles[0]
	assert_true(absf(float(v.tech_fx["contract_bonus"]) - 0.45) < 0.0001)
	assert_eq(Salvage.payout(v, 60), 87, "60 x 1.45")
	_to_workshop(w)
	v.scrap = 0
	v.contract_offers = [Vector3i(Salvage.K_ALIENS, 1, 60)]
	w.apply_command(1, {"type": "accept_contract", "value": 0})
	w.apply_command(1, {"type": "ready"})
	w.step()
	var fuel: int = v.fuel
	var i: int = _enemy(w, SimWorld.MITE, 60.0, 1.0)
	w._hit_enemy(i, 5.0, v.id)
	var scrap: int = v.scrap
	_to_workshop(w)
	assert_eq(v.fuel, fuel + 1, "+1 fuel per contract")
	assert_true(v.scrap >= scrap + 87 and v.scrap <= scrap + 87 + 40, "87 scrap (+ interest), got %d from %d" % [v.scrap, scrap])


func test_leader_contract_and_bounty_office() -> void:
	var w: SimWorld = _duel(BOUNTY)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	# offered once PvP is on for the next combat (round 4+) and a second rig is in
	var found: bool = false
	for seed_i in 12:
		var w2: SimWorld = _duel(BOUNTY)
		w2.rng.seed = 100 + seed_i
		w2.round = 3
		_to_workshop_from_combat(w2)
		for o in w2.vehicles[0].contract_offers:
			if o.x == Salvage.K_LEADER:
				found = true
				assert_eq(o, Vector3i(Salvage.K_LEADER, 10, 150))
	assert_true(found, "the leader contract shows up in the pool")
	# progress: ten shots on the leader
	a.contract_kind = Salvage.K_LEADER
	a.contract_need = 10
	a.contract_reward = 150
	w.leader_peer = b.peer_id
	for k in 9:
		w._damage_vehicle(b, 5.0, a.id, true, SimWorld.SRC_PLAYER)
	assert_eq(a.contract_prog, 9.0)
	w.leader_peer = a.peer_id
	w._damage_vehicle(b, 5.0, a.id, true, SimWorld.SRC_PLAYER)
	assert_eq(a.contract_prog, 9.0, "hits on a non-leader do not count")
	w.leader_peer = b.peer_id
	w._damage_vehicle(b, 5.0, a.id, true, SimWorld.SRC_PLAYER)
	assert_true(Salvage.is_done(a))
	# bounties x2
	var w3: SimWorld = _duel(BOUNTY)
	var w4: SimWorld = _duel(HOOKS)
	var gain: Array[int] = []
	for ww: SimWorld in [w3, w4]:
		var av: SimVehicle = ww.vehicles[0]
		var bv: SimVehicle = ww.vehicles[1]
		var s0: int = av.scrap
		ww._damage_vehicle(bv, 1.0e9, av.id, true, SimWorld.SRC_PLAYER)
		gain.append(av.scrap - s0)
	assert_eq(gain[1], SimWorld.PVP_KILL_SCRAP)
	assert_eq(gain[0], SimWorld.PVP_KILL_SCRAP * 2, "bounty office: x2")


## `w` is in combat of round `w.round`: runs it to the workshop.
func _to_workshop_from_combat(w: SimWorld) -> void:
	w.phase_ticks_left = 2
	_to_workshop(w)


# ---------------------------------------------------------------- haggler

func test_reserve_card_returns_next_workshop() -> void:
	var w: SimWorld = _world(HAGGLER)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	var keep: String = "cannon" if v.offers[0] != "cannon" else "flamer"
	v.offers = [keep, "steel_plates", "v8_engine"] as Array[String]
	w.apply_command(1, {"type": "reserve_card", "value": 0})
	assert_eq(v.reserved_card, keep)
	w.apply_command(1, {"type": "reserve_card", "value": 0})
	assert_eq(v.reserved_card, "", "the same index again takes it back")
	w.apply_command(1, {"type": "reserve_card", "value": 0})
	w.apply_command(1, {"type": "pick_card", "value": 1})
	assert_eq(v.reserved_card, keep, "picking another card keeps the reservation")
	_next_workshop(w)
	assert_true(v.offers.has(keep), "the reserved card is offered again: %s" % str(v.offers))
	assert_eq(v.reserved_card, "", "used up")
	assert_eq(v.offers.size(), 3)
	# without the tech: nothing happens
	var w0: SimWorld = _world(HOOKS)
	_to_workshop(w0)
	w0.apply_command(1, {"type": "reserve_card", "value": 0})
	assert_eq(w0.vehicles[0].reserved_card, "")


# ---------------------------------------------------------------- loan

func test_loan_payout_and_repayment() -> void:
	var w: SimWorld = _world([])
	var v: SimVehicle = w.vehicles[0]
	_buy(v, ["salvage_hooks"])
	v.scrap = 500
	var cost: int = Tech.cost("salvage_loan")
	assert_true(Tech.buy(v, "salvage_loan", 1))
	assert_eq(v.scrap, 500 - cost + 250, "+250 on purchase")
	assert_eq(v.loan_debt, 330)
	assert_eq(v.loan_left, 3)
	_to_workshop(w)
	# three instalments of 110, one at each workshop start
	var debts: Array[int] = [v.loan_debt]
	var lefts: Array[int] = [v.loan_left]
	for k in 2:
		v.scrap = 5000
		_next_workshop(w)
		debts.append(v.loan_debt)
		lefts.append(v.loan_left)
	assert_eq(debts, [220, 110, 0] as Array[int], "330 owed, 110 per workshop")
	assert_eq(lefts, [2, 1, 0] as Array[int])


func test_loan_shortfall_grows_and_never_blocks_buying() -> void:
	var w: SimWorld = _world(["salvage_hooks"])
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 1000
	assert_true(Tech.buy(v, "salvage_loan", 1))
	v.scrap = 0
	assert_eq(v.loan_debt, 330)
	_to_workshop(w)
	assert_eq(v.loan_debt, 330 + 11, "nothing paid: the 110 due grows by 10 %")
	# never blocks buying: with debt and scrap, a purchase still works
	v.scrap = 500
	assert_true(Tech.can_buy(v, "ballistics_ammo_bench"))
	assert_true(Tech.buy(v, "ballistics_ammo_bench", w.round))
	# partial payment
	var w2: SimWorld = _world(["salvage_hooks"])
	var v2: SimVehicle = w2.vehicles[0]
	v2.scrap = 1000
	Tech.buy(v2, "salvage_loan", 1)
	v2.scrap = 60
	v2.loan_left = 3
	Salvage.repay(w2, v2)
	assert_eq(v2.scrap, 0, "pays what it can")
	assert_eq(v2.loan_debt, 330 - 60 + 5, "50 short: +10 % of the shortfall")
	assert_eq(v2.loan_left, 2)
	# the last instalment takes everything that is left
	v2.loan_left = 1
	v2.loan_debt = 80
	v2.scrap = 500
	Salvage.repay(w2, v2)
	assert_eq(v2.loan_debt, 0)
	assert_eq(v2.scrap, 420)


func test_loan_respec_keeps_debt_and_pays_nothing_extra() -> void:
	var w: SimWorld = _world(["salvage_hooks"])
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 1000
	Tech.buy(v, "salvage_loan", 1)
	var scrap: int = v.scrap
	var debt: int = v.loan_debt
	assert_true(Tech.respec(v, "salvage_loan", "salvage_haggler", 1))
	assert_eq(v.loan_debt, debt, "debt stays")
	assert_eq(v.scrap, scrap + Tech.cost("salvage_loan") - Tech.cost("salvage_haggler"), "refund of the node price only")
	assert_eq(float(v.tech_fx.get("loan", 0.0)), 0.0)
	# repayments continue without the node
	v.scrap = 1000
	Salvage.repay(w, v)
	assert_eq(v.loan_debt, debt - 110)


# ---------------------------------------------------------------- insurance, jerrycans

func test_insurance_pays_on_every_own_death() -> void:
	var w: SimWorld = _world(INSURANCE)
	var v: SimVehicle = w.vehicles[0]
	v.max_hp = 100.0
	v.hp = 100.0
	assert_true(absf(float(v.tech_fx["hp_pct"]) + 0.1) < 0.0001)
	var s0: int = v.scrap
	w._damage_vehicle(v, 1.0e9, -1)
	assert_eq(v.scrap, s0 + 60)
	v.alive = true
	v.hp = 10.0
	v.invuln_ticks = 0
	w._damage_vehicle(v, 1.0e9, -1)
	assert_eq(v.scrap, s0 + 120, "each death")
	var plain: SimWorld = _world(HAGGLER)
	var p0: int = plain.vehicles[0].scrap
	plain._damage_vehicle(plain.vehicles[0], 1.0e9, -1)
	assert_eq(plain.vehicles[0].scrap, p0)


func test_jerrycans_explode_on_death() -> void:
	var w: SimWorld = _world(JERRY)
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.fuel, 115, "+15 fuel on purchase")
	var near: int = _enemy(w, SimWorld.MITE, 30.0, 25.0)
	var far: int = _enemy(w, SimWorld.MITE, 120.0, 25.0)
	var tough: int = _enemy(w, SimWorld.BOULDER, 20.0, 1000.0)
	var far_id: int = w.enemy_id[far]
	var tough_id: int = w.enemy_id[tough]
	w.events.clear()
	w._damage_vehicle(v, 1.0e9, -1)
	assert_eq(_count_events(w, "jerry_blast"), 1)
	assert_true(w.enemy_hp[near] <= 0.0, "the near mite is blown up")
	assert_eq(w.enemy_hp[_find(w, far_id)], 25.0, "outside 50 px: untouched")
	assert_eq(w.enemy_hp[_find(w, tough_id)], 960.0, "40 damage")
	var fire: bool = false
	for z in w.zone_count:
		if w.zone_kind[z] == SimWorld.ZONE_FIRE:
			fire = true
	assert_true(fire, "a fire zone burns where it stood")
	var w2: SimWorld = _world(HAGGLER)
	_enemy(w2, SimWorld.MITE, 30.0, 25.0)
	w2.events.clear()
	w2._damage_vehicle(w2.vehicles[0], 1.0e9, -1)
	assert_eq(_count_events(w2, "jerry_blast"), 0)


func _find(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1


# ---------------------------------------------------------------- scrap press

func test_scrap_press_removes_a_level_and_credits_scrap() -> void:
	var w: SimWorld = _world(PRESS)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	v.cards = {"mg": 1, "steel_plates": 3}
	Cards.recompute(v)
	v.scrap = 0
	var hp0: float = v.max_hp
	w.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	assert_eq(v.cards["steel_plates"], 2)
	assert_eq(v.scrap, 150, "level 3 x 50")
	w.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	w.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	assert_false(v.cards.has("steel_plates"), "gone at level 0")
	assert_eq(v.scrap, 150 + 100 + 50)
	assert_eq(v.saws, 3)
	assert_true(hp0 > 0.0)
	w.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	assert_eq(v.scrap, 300, "not owned: nothing")
	w.apply_command(1, {"type": "scrap_card", "value": "mg"})
	assert_true(v.cards.has("mg"), "the last gun stays")
	assert_eq(v.scrap, 300)
	# not without the tech
	var w0: SimWorld = _world(HAGGLER)
	_to_workshop(w0)
	w0.vehicles[0].cards = {"mg": 1, "steel_plates": 2}
	w0.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	assert_eq(w0.vehicles[0].cards["steel_plates"], 2)


func test_scrapped_cards_fly_as_saws() -> void:
	var w: SimWorld = _world(PRESS)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	v.cards = {"mg": 1, "steel_plates": 2}
	Cards.recompute(v)
	w.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	w.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	w.apply_command(1, {"type": "ready"})
	w.step()
	assert_eq(_count_events(w, "saw"), 2, "one saw event per scrapped level")
	assert_eq(v.saws, 0)
	var saws: int = 0
	for p in w.proj_count:
		if w.proj_owner[p] == v.id and is_equal_approx(w.proj_damage[p], Salvage.SAW_DAMAGE):
			saws += 1
	assert_eq(saws, 2, "20-damage saw projectiles")
	# a saw hurts an alien in its path
	var w2: SimWorld = _world(PRESS)
	_to_workshop(w2)
	var v2: SimVehicle = w2.vehicles[0]
	v2.weapons.clear()
	v2.cards = {"mg": 1, "steel_plates": 1}
	Cards.recompute(v2)
	w2.apply_command(1, {"type": "scrap_card", "value": "steel_plates"})
	w2.apply_command(1, {"type": "ready"})
	w2.step()
	var dir: Vector2 = w2.proj_vel[w2.proj_count - 1].normalized()
	var e: int = _enemy(w2, SimWorld.MITE, 0.0, 1000.0)
	w2.enemy_pos[e] = v2.pos + dir * 60.0
	w2.rebuild_derived()
	for t in 12:
		w2.step()
	assert_true(w2.enemy_hp[e] < 1000.0 or e >= w2.enemy_count, "the saw cut it")


# ---------------------------------------------------------------- hoarder

func test_hoarder_interest() -> void:
	var plain: SimWorld = _world(MARKET)
	var hoard: SimWorld = _world(HOARDER)
	for w: SimWorld in [plain, hoard]:
		w.round = 5
		w.vehicles[0].scrap = 2000
	var p: SimVehicle = plain.vehicles[0]
	var h: SimVehicle = hoard.vehicles[0]
	assert_eq(plain.interest_cap_for(p), 5 + 4 + 2 * 5, "5 + black market 4 + 2 per round")
	assert_eq(hoard.interest_cap_for(h), 5 + 4 + 10 + 6 * 5, "hoarder: +10 and 6 per round")
	assert_eq(plain.interest_for(p), 19, "10 % capped")
	assert_eq(hoard.interest_for(h), 49, "12 % of 2000 capped at 49")
	h.scrap = 100
	assert_eq(hoard.interest_for(h), 12, "12 % of 100")
	p.scrap = 100
	assert_eq(plain.interest_for(p), 10)


# ---------------------------------------------------------------- baron and raider

func test_baron_damage_scales_with_scrap() -> void:
	var w: SimWorld = _world(BARON)
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 0
	assert_eq(Salvage.baron_mult(v), 1.0)
	v.scrap = 250
	assert_true(absf(Salvage.baron_mult(v) - 1.06) < 0.0001, "+3 % per full 100")
	v.scrap = 5000
	assert_true(absf(Salvage.baron_mult(v) - 1.24) < 0.0001, "capped at +24 %")
	var plain: SimVehicle = _world(HOARDER).vehicles[0]
	plain.scrap = 5000
	assert_eq(Salvage.baron_mult(plain), 1.0, "only with the tech")
	# end to end: the projectile carries the bonus
	var dmgs: Array[float] = []
	for scrap in [0, 800]:
		var ww: SimWorld = _world(BARON)
		var vv: SimVehicle = ww.vehicles[0]
		vv.scrap = scrap
		_enemy(ww, SimWorld.MITE, 100.0, 1.0e6)
		for t in 6:
			ww.step()
			if ww.proj_count > 0:
				break
		assert_true(ww.proj_count > 0)
		dmgs.append(ww.proj_damage[0])
	assert_true(absf(dmgs[1] / dmgs[0] - 1.24) < 0.001, "damage ratio %f" % (dmgs[1] / dmgs[0]))


func test_baron_killer_takes_ten_percent() -> void:
	var w: SimWorld = _duel(BARON)
	w.leader_peer = -1
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.scrap = 1000
	b.scrap = 100
	var s0: int = b.scrap
	w._damage_vehicle(a, 1.0e9, b.id, true, SimWorld.SRC_PLAYER)
	assert_eq(a.scrap, 900, "the baron loses 10 %")
	assert_eq(b.scrap, s0 + 100 + SimWorld.PVP_KILL_SCRAP, "the killer got the loot and the bounty")
	# aliens do not loot
	var w2: SimWorld = _world(BARON)
	var v: SimVehicle = w2.vehicles[0]
	v.scrap = 1000
	w2._damage_vehicle(v, 1.0e9, -1)
	assert_eq(v.scrap, 1000)


func test_raider_steals_scrap_per_damage() -> void:
	var w: SimWorld = _duel(RAIDER)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.scrap = 100
	b.scrap = 100
	w._damage_vehicle(b, 19.0, a.id, true, SimWorld.SRC_PLAYER)
	assert_eq(b.scrap, 100, "under 20 damage: nothing yet")
	w._damage_vehicle(b, 41.0, a.id, true, SimWorld.SRC_PLAYER)
	assert_eq(a.scrap, 103, "60 damage = 3 scrap")
	assert_eq(b.scrap, 97)
	b.scrap = 1
	w._damage_vehicle(b, 400.0, a.id, true, SimWorld.SRC_PLAYER)
	assert_eq(b.scrap, 0, "never below zero")
	assert_eq(a.scrap, 104)
	# the victim can be hit by a rival without the tech: no theft
	var before: int = a.scrap
	w._damage_vehicle(a, 100.0, b.id, true, SimWorld.SRC_PLAYER)
	assert_eq(a.scrap, before)


# ---------------------------------------------------------------- net, snapshot, determinism

func test_validate_salvage_commands() -> void:
	assert_eq(NetSession.validate_command({"type": "accept_contract", "value": 1}), {"type": "accept_contract", "value": 1})
	assert_eq(NetSession.validate_command({"type": "accept_contract", "value": 1.0}), {"type": "accept_contract", "value": 1})
	for bad: Variant in [2, -1, 1.5, "0", null, true]:
		assert_true(NetSession.validate_command({"type": "accept_contract", "value": bad}).is_empty(), "rejected contract %s" % str(bad))
	assert_eq(NetSession.validate_command({"type": "reserve_card", "value": 3}), {"type": "reserve_card", "value": 3})
	assert_true(NetSession.validate_command({"type": "reserve_card", "value": 4}).is_empty())
	assert_eq(NetSession.validate_command({"type": "scrap_card", "value": "steel_plates"}), {"type": "scrap_card", "value": "steel_plates"})
	assert_true(NetSession.validate_command({"type": "scrap_card", "value": "nonsense"}).is_empty())
	assert_true(NetSession.validate_command({"type": "scrap_card", "value": 3}).is_empty())


func test_snapshot_round_trip() -> void:
	var w: SimWorld = _world(MARKET)
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 1000
	_to_workshop(w)
	v.loan_debt = 220
	v.loan_left = 2
	v.reserved_card = "cannon"
	v.bonus_offers = 1
	var offers: Array[Vector3i] = v.contract_offers.duplicate()
	assert_eq(offers.size(), 2)
	var bytes: PackedByteArray = Snapshot.encode(w)
	var w2 := SimWorld.new(1)
	w2.add_vehicle(1, Vector2.ZERO)
	assert_true(Snapshot.apply(w2, bytes))
	var c: SimVehicle = w2.vehicles[0]
	assert_eq(c.contract_offers, offers)
	assert_eq(c.loan_debt, 220)
	assert_eq(c.loan_left, 2)
	assert_eq(c.reserved_card, "cannon")
	assert_eq(c.bonus_offers, 1)
	# an accepted, progressing contract
	v.contract_offers = []
	v.contract_kind = Salvage.K_RAM
	v.contract_need = 400
	v.contract_reward = 70
	v.contract_prog = 123.7
	bytes = Snapshot.encode(w)
	assert_true(Snapshot.apply(w2, bytes))
	assert_eq(c.contract_kind, Salvage.K_RAM)
	assert_eq(c.contract_need, 400)
	assert_eq(c.contract_reward, 70)
	assert_eq(c.contract_prog, 123.0)
	assert_true(c.contract_offers.is_empty())
	# a failed no-death contract
	v.contract_kind = Salvage.K_NO_DEATH
	v.contract_prog = -1.0
	assert_true(Snapshot.apply(w2, Snapshot.encode(w)))
	assert_eq(c.contract_prog, -1.0)
	# nothing set: the group costs no bytes
	var empty: SimWorld = _world([])
	var n0: int = Snapshot.encode(empty).size()
	empty.vehicles[0].loan_debt = 5
	assert_true(Snapshot.encode(empty).size() > n0)
	# truncated data is rejected
	var cut: PackedByteArray = Snapshot.encode(w).slice(0, 120)
	assert_false(Snapshot.apply(w2, cut))


func test_events_survive_the_snapshot() -> void:
	for type in ["contract_done", "saw", "shockwave", "chain", "jerry_blast"]:
		assert_true(Snapshot.EVENT_TYPES.has(type), type)
	var w: SimWorld = _world(HOOKS)
	w._emit("saw", Vector2(100, 100), 0, 0)
	w._emit("contract_done", Vector2(120, 100), 0, 2)
	var w2 := SimWorld.new(1)
	w2.add_vehicle(1, Vector2.ZERO)
	assert_true(Snapshot.apply(w2, Snapshot.encode(w)))
	assert_eq(w2.events[0]["type"], "saw")
	assert_eq(w2.events[1]["type"], "contract_done")
	assert_eq(w2.events[1]["kind"], 2)


func test_checksum_covers_salvage_state() -> void:
	var w: SimWorld = _world(MARKET)
	var base: int = w.checksum()
	var v: SimVehicle = w.vehicles[0]
	for mutate: Callable in [
			func() -> void: v.loan_debt += 1,
			func() -> void: v.contract_prog += 1.0,
			func() -> void: v.reserved_card = "mg",
			func() -> void: v.bonus_offers += 1,
			func() -> void: v.raid_acc += 1.0,
			func() -> void: v.saws += 1,
			func() -> void: v.contract_offers = [Vector3i(1, 2, 3)]]:
		var before: int = w.checksum()
		mutate.call()
		assert_ne(w.checksum(), before)
	assert_ne(w.checksum(), base)


func test_determinism_over_several_rounds() -> void:
	var sums: Array[int] = []
	for run in 2:
		var w := SimWorld.new(42)
		w.fast_rounds = true
		var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
		var b: SimVehicle = w.add_vehicle(2, Vector2(1200, 700))
		_buy(a, BOUNTY)
		_buy(b, LOAN)
		a.scrap = 800
		b.scrap = 800
		for t in 1500:
			if w.phase == SimWorld.PHASE_WORKSHOP:
				for v in w.vehicles:
					if not v.contract_offers.is_empty():
						w.apply_command(v.peer_id, {"type": "accept_contract", "value": 0})
					w.apply_command(v.peer_id, {"type": "ready"})
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1], "same seed, same salvage world")
