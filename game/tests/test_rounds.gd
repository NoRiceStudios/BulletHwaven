extends TestCase
## Round loop: phases, fuel / respawn / elimination, cards, tech, commands, snapshot, determinism.


func _world(players: int = 1, fast: bool = true, spawning: bool = false) -> SimWorld:
	var w := SimWorld.new(21)
	w.fast_rounds = fast
	w.spawning_enabled = spawning
	for i in players:
		w.add_vehicle(i + 1, Vector2(300.0 + 500.0 * float(i), 360.0))
	return w


func _step(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func _to_workshop(w: SimWorld) -> void:
	var guard: int = 0
	while w.phase == SimWorld.PHASE_COMBAT and guard < 5000:
		w.step()
		guard += 1


func _has_event(w: SimWorld, type: String) -> bool:
	for e in w.events:
		if e["type"] == type:
			return true
	return false


func _respawn_wait(w: SimWorld, v: SimVehicle) -> void:
	var guard: int = 0
	while not v.alive and not v.eliminated and guard < 500:
		w.step()
		guard += 1


# ---------------------------------------------------------------- data tables

func test_card_and_tech_tables() -> void:
	assert_eq(Cards.count(), 16, "16 cards")
	var cats := {}
	var seen := {}
	for i in Cards.count():
		var d: Dictionary = Cards.DEFS[i]
		var id: String = d["id"]
		assert_false(seen.has(id), "unique card id " + id)
		seen[id] = true
		assert_eq(Cards.index_of(id), i, "index round trip " + id)
		assert_eq(Cards.id_at(i), id)
		assert_gt(float(d["weight"]), 0.0)
		cats[d["category"]] = int(cats.get(d["category"], 0)) + 1
	for c in ["weapon", "armor", "mobility", "behavior"]:
		assert_eq(int(cats.get(c, 0)), 4, "4 cards in " + c)
	for id in ["mg", "shotgun", "cannon", "flamer", "scrap_magnet", "berserker", "vulture", "regenerator"]:
		assert_true(Cards.has(id), id)
	assert_eq(Cards.index_of("nope"), -1)
	assert_eq(Cards.id_at(99), "")
	assert_eq(Tech.count(), 15, "5 branches x 3 tiers")
	for b in Tech.BRANCHES:
		for t in [1, 2, 3]:
			var id: String = "%s_%d" % [b, t]
			assert_true(Tech.has(id), id)
			assert_eq(Tech.cost(id), Tech.TIER_COSTS[t - 1])
			assert_eq(Tech.prerequisite(id), "" if t == 1 else "%s_%d" % [b, t - 1])
	assert_false(Tech.has("ballistics_4"))
	assert_eq(Tech.cost("nope"), 0)


# ---------------------------------------------------------------- phases

func test_phase_transitions_at_timers() -> void:
	var w := SimWorld.new(1)
	w.spawning_enabled = false
	w.add_vehicle(1, Vector2(300, 360))
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(w.round, 1)
	assert_eq(w.winner_peer, -1)
	assert_eq(w.phase_ticks_left, SimWorld.COMBAT_TICKS_EARLY, "rounds 1-2 are the short ones")
	_step(w, SimWorld.COMBAT_TICKS_EARLY - 1)
	assert_eq(w.phase, SimWorld.PHASE_COMBAT, "still combat one tick before the timer")
	assert_eq(w.phase_ticks_left, 1)
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(w.round, 1, "round number stays during the workshop")
	assert_eq(w.phase_ticks_left, SimWorld.WORKSHOP_TICKS)
	_step(w, SimWorld.WORKSHOP_TICKS - 1)
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(w.round, 2)
	assert_eq(w.phase_ticks_left, SimWorld.COMBAT_TICKS_EARLY)
	assert_eq(w.combat_duration(3), SimWorld.COMBAT_TICKS, "round 3+ is the full length")
	assert_gt(float(SimWorld.COMBAT_TICKS), float(SimWorld.COMBAT_TICKS_EARLY))


func test_fast_rounds() -> void:
	var w := _world(1)
	assert_eq(w.phase_ticks_left, SimWorld.FAST_COMBAT_TICKS, "setter shortens the running timer at tick 0")
	_to_workshop(w)
	assert_eq(w.tick, SimWorld.FAST_COMBAT_TICKS)
	assert_eq(w.phase_ticks_left, SimWorld.FAST_WORKSHOP_TICKS)
	_step(w, SimWorld.FAST_WORKSHOP_TICKS)
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(w.round, 2)
	assert_eq(w.phase_ticks_left, SimWorld.FAST_COMBAT_TICKS)


func test_workshop_clears_field_and_freezes_vehicles() -> void:
	var w := _world(2, true, true)
	_step(w, SimWorld.FAST_COMBAT_TICKS - 5)
	assert_gt(w.enemy_count, 0, "aliens around before the round ends")
	var n_alive_enemies: int = w.enemy_count
	_to_workshop(w)
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(w.enemy_count, 0, "aliens retreated")
	assert_eq(w.proj_count, 0, "projectiles cleared")
	assert_eq(w.enemy_id.size(), 0)
	assert_eq(w.proj_pierce.size(), 0)
	var retreats: int = 0
	for e in w.events:
		if e["type"] == "retreat":
			retreats += 1
			assert_true(int(e["kind"]) >= 0, "retreat carries the enemy kind")
	assert_gt(float(retreats), 0.0, "retreat events emitted")
	assert_true(retreats <= SimWorld.RETREAT_EVENT_CAP and retreats <= n_alive_enemies + 5)
	var before: Array[Vector2] = []
	for v in w.vehicles:
		before.append(v.pos)
		assert_eq(v.vel, Vector2.ZERO, "vehicles stop")
	_step(w, 30)
	assert_eq(w.enemy_count, 0, "no spawns in the workshop")
	for i in w.vehicles.size():
		assert_eq(w.vehicles[i].pos, before[i], "vehicle does not move in the workshop")


func test_big_horde_retreat_event_cap() -> void:
	var w := _world(1)
	for i in 900:
		w.spawn_enemy(SimWorld.MITE, Vector2(20.0 + float(i % 60) * 20.0, 20.0 + float(i / 60) * 40.0))
	w.rebuild_derived()
	_to_workshop(w)
	var retreats: int = 0
	for e in w.events:
		if e["type"] == "retreat":
			retreats += 1
	assert_true(retreats > 0 and retreats <= SimWorld.RETREAT_EVENT_CAP, "thinned to the cap (%d)" % retreats)


func test_ready_skips_workshop() -> void:
	var w := _world(2)
	_to_workshop(w)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	w.apply_command(1, {"type": "ready"})
	assert_true(a.ready)
	_step(w, 5)
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP, "waits for the other player")
	w.apply_command(2, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT, "everyone ready: workshop is skipped")
	assert_eq(w.round, 2)
	assert_false(a.ready or b.ready, "ready resets")
	assert_true(a.offers.is_empty(), "unused offers dropped")
	# A solo player readying up also skips.
	var s := _world(1)
	_to_workshop(s)
	s.apply_command(1, {"type": "ready"})
	s.step()
	assert_eq(s.phase, SimWorld.PHASE_COMBAT)


func test_ready_ignored_in_combat() -> void:
	var w := _world(1)
	w.apply_command(1, {"type": "ready"})
	assert_false(w.vehicles[0].ready)
	w.apply_command(1, {"type": "pick_card", "value": 0})
	w.apply_command(1, {"type": "reroll"})
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_1"})
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.cards, {"mg": 1})
	assert_eq(v.tech.size(), 0)


func test_vehicles_repaired_for_next_round() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	v.hp = 50.0
	_to_workshop(w)
	assert_lt(v.hp, v.max_hp, "damage persists into the workshop")
	w.apply_command(1, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(v.hp, v.max_hp, "repaired when the next round starts")


# ---------------------------------------------------------------- interest

func test_interest() -> void:
	var w := _world(3)
	w.vehicles[0].scrap = 47
	w.vehicles[1].scrap = 9
	w.vehicles[2].scrap = 400
	_to_workshop(w)
	assert_eq(w.vehicles[0].scrap, 47 + 4, "+1 per 10 held")
	assert_eq(w.vehicles[1].scrap, 9, "under 10: nothing")
	assert_eq(w.vehicles[2].scrap, 405, "capped at +5")
	# Salvage tech raises the cap.
	var s := _world(1)
	var v: SimVehicle = s.vehicles[0]
	v.tech = ["salvage_1", "salvage_2", "salvage_3"]
	Cards.recompute(v)
	assert_eq(v.interest_cap, 10)
	v.scrap = 400
	_to_workshop(s)
	assert_eq(v.scrap, 410)


# ---------------------------------------------------------------- offers and picking

func test_offers_and_pick() -> void:
	var w := _world(2)
	_to_workshop(w)
	for v in w.vehicles:
		assert_eq(v.offers.size(), 3, "3 offers")
		var uniq := {}
		for id in v.offers:
			assert_true(Cards.has(id), "valid card id")
			uniq[id] = true
		assert_eq(uniq.size(), 3, "distinct offers")
		assert_false(v.picked)
		assert_eq(v.reroll_cost, SimWorld.REROLL_COST_START)
	var v1: SimVehicle = w.vehicles[0]
	var choice: String = v1.offers[1]
	var before: int = int(v1.cards.get(choice, 0))
	w.apply_command(1, {"type": "pick_card", "value": 7})
	w.apply_command(1, {"type": "pick_card", "value": -1})
	w.apply_command(1, {"type": "pick_card", "value": 1.5})
	w.apply_command(1, {"type": "pick_card", "value": "1"})
	w.apply_command(1, {"type": "pick_card"})
	assert_false(v1.picked, "bad indices ignored")
	assert_eq(v1.offers.size(), 3)
	w.apply_command(1, {"type": "pick_card", "value": 1.0})  # JSON / RPC may deliver a float
	assert_true(v1.picked)
	assert_eq(v1.offers.size(), 0, "offers empty once picked")
	assert_eq(int(v1.cards.get(choice, 0)), before + 1, "pick applied")
	var snapshot_cards: Dictionary = v1.cards.duplicate()
	w.apply_command(1, {"type": "pick_card", "value": 0})
	assert_eq(v1.cards, snapshot_cards, "only one pick per workshop")
	assert_eq(w.vehicles[1].offers.size(), 3, "other player unaffected")
	# New offers next workshop.
	w.apply_command(1, {"type": "ready"})
	w.apply_command(2, {"type": "ready"})
	w.step()
	_to_workshop(w)
	assert_eq(v1.offers.size(), 3)
	assert_false(v1.picked)


func test_pick_levels_up_duplicates_and_max_not_offered() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	for lvl in [1, 2, 3]:
		v.offers = ["steel_plates", "v8_engine", "vulture"]
		v.picked = false
		w.apply_command(1, {"type": "pick_card", "value": 0})
		assert_eq(int(v.cards.get("steel_plates", 0)), lvl, "duplicate raises the level")
	assert_eq(v.max_hp, SimVehicle.MAX_HP + 3.0 * 40.0, "3 levels of steel plates")
	assert_eq(v.armor, 3.0)
	# Maxed cards are never offered.
	assert_false(Cards.is_offerable(v, "steel_plates"))
	for i in 60:
		var offers: Array[String] = Cards.roll_offers(w.rng, v)
		assert_eq(offers.size(), 3)
		assert_false(offers.has("steel_plates"), "maxed card not offered")
	# A pick of a maxed card (forged offers) does nothing.
	v.offers = ["steel_plates", "v8_engine", "vulture"]
	v.picked = false
	w.apply_command(1, {"type": "pick_card", "value": 0})
	assert_eq(int(v.cards["steel_plates"]), 3)
	assert_false(v.picked)
	# mg starts at level 1 and levels up like any card.
	assert_true(Cards.grant(v, "mg"))
	assert_eq(int(v.cards["mg"]), 2)
	assert_eq(float(v.weapons[0]["damage"]), 5.0)


func test_offers_respect_weapon_slots() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.weapon_slots, 2)
	Cards.grant(v, "shotgun")
	assert_eq(v.weapons.size(), 2)
	for i in 80:
		var offers: Array[String] = Cards.roll_offers(w.rng, v)
		assert_false(offers.has("cannon") or offers.has("flamer"), "no new weapon when the slots are full")
	assert_true(Cards.is_offerable(v, "shotgun"), "owned weapons can still level up")
	assert_true(Cards.is_offerable(v, "mg"))
	v.tech = ["engineering_1", "engineering_2", "engineering_3"]
	Cards.recompute(v)
	assert_eq(v.weapon_slots, 3, "engineering_3 adds a slot")
	assert_true(Cards.is_offerable(v, "cannon"))
	Cards.grant(v, "cannon")
	assert_eq(v.weapons.size(), 3)
	var kinds: Array[String] = []
	for wp in v.weapons:
		kinds.append(str(wp["kind"]))
	assert_eq(kinds, ["mg", "shotgun", "cannon"])


func test_offers_are_seeded_and_weighted() -> void:
	var a := _world(1)
	var b := _world(1)
	_to_workshop(a)
	_to_workshop(b)
	assert_eq(a.vehicles[0].offers, b.vehicles[0].offers, "same seed, same offers")
	var seen := {}
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 200:
		for id in Cards.roll_offers(r, a.vehicles[0]):
			seen[id] = int(seen.get(id, 0)) + 1
	assert_eq(seen.size(), Cards.count(), "every card shows up")


func test_reroll() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	_to_workshop(w)
	var first: Array[String] = v.offers.duplicate()
	w.apply_command(1, {"type": "reroll"})
	assert_eq(v.offers, first, "no scrap, no reroll")
	var c0: int = SimWorld.REROLL_COST_START
	assert_eq(v.reroll_cost, c0)
	v.scrap = 100
	w.apply_command(1, {"type": "reroll"})
	assert_eq(v.scrap, 100 - c0, "first reroll costs the start price")
	assert_eq(v.reroll_cost, c0 + 1, "cost goes up by 1")
	assert_eq(v.offers.size(), 3)
	w.apply_command(1, {"type": "reroll"})
	assert_eq(v.scrap, 100 - c0 - (c0 + 1))
	assert_eq(v.reroll_cost, c0 + 2)
	v.scrap = c0 + 1
	w.apply_command(1, {"type": "reroll"})
	assert_eq(v.scrap, c0 + 1, "cannot afford the next one")
	v.scrap = 100
	w.apply_command(1, {"type": "pick_card", "value": 0})
	w.apply_command(1, {"type": "reroll"})
	assert_eq(v.scrap, 100, "no reroll after the pick")
	# The cost resets every workshop.
	w.apply_command(1, {"type": "ready"})
	w.step()
	_to_workshop(w)
	assert_eq(v.reroll_cost, c0)


func test_late_joiner_gets_offers_in_workshop() -> void:
	var w := _world(1)
	_to_workshop(w)
	var late: SimVehicle = w.add_vehicle(9, Vector2(900, 300))
	assert_eq(late.offers.size(), 3)
	assert_eq(late.fuel, SimWorld.START_FUEL)
	var w2 := _world(1)
	var late2: SimVehicle = w2.add_vehicle(9, Vector2(900, 300))
	assert_eq(late2.offers.size(), 0, "no offers during combat")


# ---------------------------------------------------------------- tech

func test_tech_prerequisites_and_cost() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 500
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_1"})
	assert_eq(v.tech.size(), 0, "not in combat")
	_to_workshop(w)
	var scrap: int = v.scrap  # includes interest
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_2"})
	assert_eq(v.tech.size(), 0, "tier 2 needs tier 1")
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_3"})
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_9"})
	w.apply_command(1, {"type": "buy_tech", "value": ""})
	w.apply_command(1, {"type": "buy_tech", "value": 3})
	assert_eq(v.tech.size(), 0)
	assert_eq(v.scrap, scrap)
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_1"})
	assert_eq(v.tech, ["ballistics_1"] as Array[String])
	assert_eq(v.scrap, scrap - Tech.cost("ballistics_1"), "tier 1 cost paid")
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_1"})
	assert_eq(v.tech.size(), 1, "cannot buy twice")
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_2"})
	assert_eq(v.tech.size(), 2)
	assert_eq(v.scrap, scrap - Tech.cost("ballistics_1") - Tech.cost("ballistics_2"))
	assert_gt(float(Tech.cost("ballistics_2")), float(Tech.cost("ballistics_1")), "costs grow by tier")
	assert_gt(float(Tech.cost("ballistics_3")), float(Tech.cost("ballistics_2")))
	# Can't afford tier 3.
	v.scrap = Tech.cost("ballistics_3") - 1
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_3"})
	assert_eq(v.tech.size(), 2, "too poor")
	assert_eq(Tech.branch_tier(v, "ballistics"), 2)
	assert_eq(Tech.branch_tier(v, "salvage"), 0)


func test_tech_changes_derived_stats() -> void:
	var v := SimVehicle.new(0, 1, Vector2(100, 100))
	var base_damage: float = float(v.weapons[0]["damage"])
	var base_range: float = float(v.weapons[0]["range"])
	var base_cd: int = int(v.weapons[0]["cooldown_ticks"])
	assert_eq(v.max_hp, 300.0)
	assert_eq(v.hp, 300.0)
	assert_eq(v.armor, 0.0)
	assert_eq(v.speed, 1.0)
	assert_eq(v.turn_rate, 1.0)
	assert_eq(v.scrap_mult, 1.0)
	assert_eq(v.weapon_slots, 2)
	assert_eq(v.interest_cap, 5)
	v.scrap = 3000
	for id in ["ballistics_1", "ballistics_2", "engineering_1", "propulsion_1", "electronics_1", "salvage_1"]:
		assert_true(Tech.buy(v, id), id)
	assert_gt(float(v.weapons[0]["damage"]), base_damage, "ballistics: damage")
	assert_gt(v.max_hp, 300.0, "engineering: hp")
	assert_eq(v.hp, v.max_hp, "extra hp is granted")
	assert_gt(v.armor, 0.0, "engineering: armor")
	assert_gt(v.speed, 1.0, "propulsion: speed")
	assert_gt(v.turn_rate, 1.0, "propulsion: turn")
	assert_gt(float(v.weapons[0]["range"]), base_range, "electronics: range")
	assert_true(int(v.weapons[0]["cooldown_ticks"]) <= base_cd, "electronics: fire rate")
	assert_gt(v.scrap_mult, 1.0, "salvage: scrap")
	assert_true(Tech.buy(v, "electronics_2") and Tech.buy(v, "electronics_3"))
	assert_true(int(v.weapons[0]["cooldown_ticks"]) < base_cd, "faster fire")
	assert_true(Tech.buy(v, "engineering_2") and Tech.buy(v, "engineering_3"))
	assert_eq(v.weapon_slots, 3)
	assert_true(Tech.buy(v, "salvage_2"))
	assert_eq(v.interest_cap, 7)
	assert_true(Tech.buy(v, "salvage_3"))
	assert_eq(v.interest_cap, 10)


func test_card_effects() -> void:
	var v := SimVehicle.new(0, 1, Vector2(100, 100))
	Cards.grant(v, "steel_plates")
	assert_eq(v.max_hp, 340.0)
	assert_eq(v.armor, 1.0)
	Cards.grant(v, "v8_engine")
	assert_eq(v.speed, 1.1)
	Cards.grant(v, "off_road_tyres")
	assert_gt(v.turn_rate, 1.0)
	Cards.grant(v, "scrap_magnet")
	assert_eq(v.scrap_mult, 1.15)
	Cards.grant(v, "regenerator")
	assert_eq(v.regen, 1.5)
	Cards.grant(v, "berserker")
	assert_eq(v.contact_damage, 0.8)
	assert_eq(v.ram_mult, 1.4)
	Cards.grant(v, "vulture")
	assert_eq(v.vulture, 0.25)
	Cards.grant(v, "caterpillar_tracks")
	assert_lt(v.speed, 1.1 + 0.03 + 0.001, "tracks are slower")
	assert_false(Cards.grant(v, "does_not_exist"))
	# Weapon variants.
	Cards.grant(v, "flamer")
	var flamer: Dictionary = v.weapons[1]
	assert_eq(str(flamer["kind"]), "flamer")
	assert_lt(float(flamer["range"]) / float(flamer["speed"]), 0.5, "very short ttl")
	assert_true(int(flamer["pierce"]) > 0)
	assert_true(int(flamer["cooldown_ticks"]) <= 2)
	var w2 := SimVehicle.new(0, 1, Vector2.ZERO)
	Cards.grant(w2, "shotgun")
	assert_true(int(w2.weapons[1]["pellets"]) >= 5, "shotgun pellets")
	assert_gt(float(w2.weapons[1]["spread"]), 0.1)
	var w3 := SimVehicle.new(0, 1, Vector2.ZERO)
	Cards.grant(w3, "cannon")
	assert_true(int(w3.weapons[1]["pierce"]) >= 1, "cannon pierces")
	assert_gt(float(w3.weapons[1]["damage"]), 20.0, "cannon is heavy")
	assert_gt(float(w3.weapons[1]["cooldown_ticks"]), 10.0, "cannon is slow")
	Cards.grant(w3, "cannon")
	assert_gt(float(w3.weapons[1]["splash"]), 0.0, "cannon level 2 has splash")


func test_scrap_magnet_pays_more() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	for i in 3:
		Cards.grant(v, "scrap_magnet")
	assert_eq(v.scrap_mult, 1.0 + 0.45)
	for i in 100:
		var id: int = w.spawn_enemy(SimWorld.MITE, Vector2(1000, 600))
		assert_true(id >= 0)
		w._hit_enemy(w.enemy_count - 1, 100.0, v.id)
	assert_true(v.scrap >= 144 and v.scrap <= 145, "100 mites x 1.45 (got %d)" % v.scrap)
	assert_eq(v.kills, 100)


func test_regenerator_heals_in_combat() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	Cards.grant(v, "regenerator")
	v.hp = 100.0
	_step(w, 30)
	assert_gt(v.hp, 100.0 + 1.0, "about +1.5 hp per second")
	assert_lt(v.hp, 110.0)
	var other := _world(1)
	other.vehicles[0].hp = 100.0
	_step(other, 30)
	assert_eq(other.vehicles[0].hp, 100.0, "no regen without the card")


func test_berserker_adds_contact_damage() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	w.step()
	assert_eq(v.ram_damage, 0.0, "circle doctrine: no ram damage")
	Cards.grant(v, "berserker")
	w.step()
	assert_eq(v.ram_damage, 0.8, "contact damage even when circling")
	w.apply_command(1, {"type": "set_drive", "value": "charge"})
	w.spawn_enemy(SimWorld.BOULDER, Vector2(700, 360))
	w.rebuild_derived()
	w.step()
	assert_gt(v.ram_damage, VehicleAI.CHARGE_RAM_DAMAGE, "charge ram is boosted too")
	# A mite pressed against a berserker dies fast.
	var m := _world(1)
	var mv: SimVehicle = m.vehicles[0]
	Cards.grant(mv, "berserker")
	Cards.grant(mv, "berserker")
	m.step()
	m.spawn_enemy(SimWorld.MITE, mv.pos + Vector2(14, 0))
	m.enemy_vel[0] = Vector2.ZERO
	m.rebuild_derived()
	for i in 12:
		m.step()
	assert_eq(m.enemy_count, 0, "touching mite is shredded")
	assert_eq(mv.kills, 1)


func test_vulture_bonus_vs_weak_targets() -> void:
	var v_dmg: Array[float] = []
	for weak in [false, true]:
		var w := _world(1)
		var v: SimVehicle = w.vehicles[0]
		Cards.grant(v, "vulture")
		Cards.grant(v, "vulture")
		w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(150, 0))
		w.enemy_hp[0] = 10.0 if weak else 80.0
		w.rebuild_derived()
		var guard: int = 0
		while w.proj_count == 0 and guard < 30:
			w.step()
			guard += 1
		assert_gt(float(w.proj_count), 0.0, "vehicle fired")
		v_dmg.append(w.proj_damage[0])
	assert_eq(v_dmg[0], 4.0, "full hp target: base damage")
	assert_eq(v_dmg[1], 4.0 * 1.5, "target under 30%: +25% per level")


func test_armor_reduces_hits() -> void:
	var w := _world(2)
	var v: SimVehicle = w.vehicles[0]
	Cards.grant(v, "ablative_scrap")  # armour 2
	assert_eq(v.armor, 2.0)
	var hp: float = v.hp
	w._damage_vehicle(v, 6.0, 1)
	assert_eq(v.hp, hp - 4.0, "flat reduction")
	hp = v.hp
	w._damage_vehicle(v, 1.0, 1)
	assert_eq(v.hp, hp - 0.25, "never below 25%")
	Cards.grant(v, "ablative_scrap")
	Cards.grant(v, "ablative_scrap")
	hp = v.hp
	w._damage_vehicle(v, 5.0, 1)  # 5 - 6 -> floor
	assert_eq(v.hp, hp - 1.25)


# ---------------------------------------------------------------- weapons in the sim

func test_shotgun_fires_pellets() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	v.cards = {"shotgun": 1}
	Cards.recompute(v)
	assert_eq(v.weapons.size(), 1)
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(100, 0))
	w.enemy_hp[0] = 1.0e9
	w.rebuild_derived()
	var guard: int = 0
	while w.proj_count == 0 and guard < 30:
		w.step()
		guard += 1
	assert_eq(w.proj_count, 5, "one volley of 5 pellets")
	var fire_events: int = 0
	for e in w.events:
		if e["type"] == "fire":
			fire_events += 1
			assert_eq(int(e["kind"]), Cards.weapon_kind_index("shotgun"))
	assert_eq(fire_events, 1, "one fire event per volley")
	var dirs := {}
	for i in w.proj_count:
		dirs[snappedf(w.proj_vel[i].angle(), 0.001)] = true
	assert_gt(float(dirs.size()), 1.0, "pellets spread out")


func test_piercing_projectile_goes_through() -> void:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	w.add_vehicle(1, Vector2(60, 60))
	w.vehicles[0].weapons.clear()
	for x in [600.0, 612.0, 624.0]:
		var i: int = w.spawn_enemy(SimWorld.MITE, Vector2(x, 400))
		assert_true(i >= 0)
	w.rebuild_derived()
	w.spawn_projectile(Vector2(560, 400), Vector2(400, 0), 1.0, 100.0, 0, 1)
	assert_eq(w.proj_pierce[0], 1)
	var killed: int = 0
	for i in 8:
		w.step()
		for e in w.events:
			if e["type"] == "kill":
				killed += 1
	assert_eq(killed, 2, "pierce 1 = two enemies hit")
	assert_eq(w.proj_count, 0, "then it is spent")
	assert_eq(w.enemy_count, 1, "third survives")
	# Without pierce only one dies.
	var w2 := SimWorld.new(5)
	w2.spawning_enabled = false
	w2.add_vehicle(1, Vector2(60, 60))
	w2.vehicles[0].weapons.clear()
	for x in [600.0, 612.0, 624.0]:
		w2.spawn_enemy(SimWorld.MITE, Vector2(x, 400))
	w2.rebuild_derived()
	w2.spawn_projectile(Vector2(560, 400), Vector2(400, 0), 1.0, 100.0, 0)
	for i in 8:
		w2.step()
	assert_eq(w2.enemy_count, 2)


func test_splash_hits_neighbours() -> void:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	w.add_vehicle(1, Vector2(60, 60))
	w.vehicles[0].weapons.clear()
	w.spawn_enemy(SimWorld.MITE, Vector2(600, 400))
	w.spawn_enemy(SimWorld.BOULDER, Vector2(600, 430))
	w.rebuild_derived()
	w.spawn_projectile(Vector2(570, 400), Vector2(400, 0), 1.0, 20.0, 0, 0, 40.0)
	for i in 3:
		w.step()
	var boulder_hp: float = -1.0
	for i in w.enemy_count:
		if w.enemy_kind[i] == SimWorld.BOULDER:
			boulder_hp = w.enemy_hp[i]
	assert_lt(boulder_hp, SimWorld.ENEMY_HP[SimWorld.BOULDER] - 5.0, "boulder took splash damage")


func test_projectile_arrays_stay_in_sync() -> void:
	var w := _world(1, true, true)
	var v: SimVehicle = w.vehicles[0]
	Cards.grant(v, "cannon")
	for i in 400:
		w.step()
		assert_eq(w.proj_pierce.size(), w.proj_count)
		assert_eq(w.proj_splash.size(), w.proj_count)
		assert_eq(w.proj_last.size(), w.proj_count)
		if w.proj_pierce.size() != w.proj_count:
			return


# ---------------------------------------------------------------- scaling

func test_enemy_scaling_per_round() -> void:
	assert_eq(SimWorld.enemy_hp_mult(1), 1.0)
	assert_eq(SimWorld.spawn_rate_mult(1), 1.0)
	assert_eq(SimWorld.boulder_chance(1), SimWorld.BOULDER_CHANCE)
	for r in range(2, 15):
		assert_gt(SimWorld.enemy_hp_mult(r), SimWorld.enemy_hp_mult(r - 1))
		assert_gt(SimWorld.spawn_rate_mult(r), SimWorld.spawn_rate_mult(r - 1))
		assert_true(SimWorld.boulder_chance(r) >= SimWorld.boulder_chance(r - 1))
	assert_true(SimWorld.boulder_chance(500) <= SimWorld.BOULDER_CHANCE_MAX)
	var w := SimWorld.new(1)
	w.spawn_enemy(SimWorld.BOULDER, Vector2(10, 10))
	w.round = 6
	w.spawn_enemy(SimWorld.BOULDER, Vector2(20, 20))
	assert_eq(w.enemy_hp[0], SimWorld.ENEMY_HP[SimWorld.BOULDER])
	assert_eq(w.enemy_hp[1], SimWorld.ENEMY_HP[SimWorld.BOULDER] * SimWorld.enemy_hp_mult(6))
	# More enemies spawn in a later round.
	var counts: Array[int] = []
	for r in [1, 8]:
		var s := SimWorld.new(4)
		s.round = r
		s.phase_ticks_left = s.combat_duration(r)
		var made: int = 0
		for i in 600:
			s.step()
			made = s.next_enemy_id
		counts.append(made)
	assert_gt(float(counts[1]), float(counts[0]) * 1.4, "round 8 spawns more")


func test_starter_survives_early_rounds_but_not_late_ones() -> void:
	var w := SimWorld.new(31)
	var v: SimVehicle = w.add_vehicle(1, Vector2(640, 360))
	var steps: int = 0
	while w.round <= 2 and w.phase != SimWorld.PHASE_GAME_OVER and steps < 20000:
		w.step()
		steps += 1
		if w.phase == SimWorld.PHASE_WORKSHOP:
			w.apply_command(1, {"type": "ready"})
	assert_eq(w.round, 3, "reached round 3")
	assert_eq(v.fuel, SimWorld.START_FUEL, "starter vehicle lost no fuel in rounds 1-2")
	# A late round without upgrades is a different story.
	var l := SimWorld.new(31)
	var lv: SimVehicle = l.add_vehicle(1, Vector2(640, 360))
	l.round = 9
	l.phase_ticks_left = l.combat_duration(9)
	for i in 1800:
		l.step()
		if lv.fuel < SimWorld.START_FUEL:
			break
	assert_lt(float(lv.fuel), float(SimWorld.START_FUEL), "unupgraded vehicle is overwhelmed in round 9")


# ---------------------------------------------------------------- fuel, respawn, elimination

func test_death_costs_fuel_and_respawns() -> void:
	var w := _world(1)
	var v: SimVehicle = w.vehicles[0]
	v.pos = Vector2(100, 100)
	w._damage_vehicle(v, 1.0e6, -1)
	assert_false(v.alive)
	assert_eq(v.fuel, 80, "aliens cost 20 fuel")
	assert_eq(v.respawn_ticks, SimWorld.RESPAWN_TICKS)
	assert_false(v.eliminated)
	assert_true(_has_event(w, "vehicle_destroyed"))
	w.events.clear()
	var respawn_event: Dictionary = {}
	var ticks: int = 0
	while not v.alive and ticks < 200:
		w.step()
		ticks += 1
		for e in w.events:
			if e["type"] == "respawn":
				respawn_event = e
	assert_true(v.alive, "respawned")
	assert_true(absi(ticks - SimWorld.RESPAWN_TICKS) <= 1, "after about 3 s (%d)" % ticks)
	assert_eq(v.hp, v.max_hp, "full hp")
	assert_false(respawn_event.is_empty(), "respawn event")
	assert_eq(int(respawn_event["owner"]), v.id)
	assert_lt((respawn_event["pos"] as Vector2).distance_to(v.pos), 6.0, "event at the respawn spot")
	assert_true(SimWorld.ARENA.has_point(v.pos))
	assert_eq(v.fuel, 80)


func test_respawn_picks_a_free_spot() -> void:
	var w := _world(2)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	w._damage_vehicle(a, 1.0e6, -1)
	# Park the other vehicle on A's home slot (id 0 -> angle 0).
	var c: Vector2 = SimWorld.ARENA.get_center()
	b.pos = c + Vector2(480, 0)
	_respawn_wait(w, a)
	assert_true(a.alive)
	assert_gt(a.pos.distance_to(b.pos), SimWorld.SPAWN_SPOT_CLEARANCE - 1.0, "not on top of the other vehicle")


func test_pvp_kill_costs_more_fuel_and_pays_bounty() -> void:
	var w := _world(2)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	var scrap_before: int = b.scrap
	w._damage_vehicle(a, 1.0e6, b.id)
	assert_eq(a.fuel, 70, "30 fuel for a player kill")
	assert_eq(b.kills, 1)
	assert_eq(b.scrap, scrap_before + 15, "15 scrap bounty")
	assert_eq(SimWorld.PVP_KILL_SCRAP, 15)


func test_elimination_and_game_over_two_players() -> void:
	var w := _world(2, false)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	for i in 3:
		w._damage_vehicle(a, 1.0e6, b.id)
		_respawn_wait(w, a)
		assert_true(a.alive, "still in the game after %d deaths" % (i + 1))
		assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(a.fuel, 10)
	w._damage_vehicle(a, 1.0e6, b.id)
	assert_eq(a.fuel, 0)
	assert_true(a.eliminated)
	assert_false(a.alive)
	_step(w, SimWorld.RESPAWN_TICKS + 10)
	assert_false(a.alive, "eliminated vehicles do not respawn")
	assert_eq(w.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(w.winner_peer, 2, "the survivor wins")
	# Game over is final: nothing moves, commands are ignored.
	var tick: int = w.tick
	var pos: Vector2 = b.pos
	_step(w, 30)
	assert_eq(w.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(w.tick, tick + 30, "tick still advances")
	assert_eq(b.pos, pos)
	w.apply_command(2, {"type": "ready"})
	w.apply_command(2, {"type": "buy_tech", "value": "salvage_1"})
	assert_false(b.ready)
	assert_eq(w.winner_peer, 2)


func test_game_over_in_workshop_when_a_player_leaves() -> void:
	var w := _world(2)
	_to_workshop(w)
	w.vehicles[0].eliminated = true  # what NetSession does for a departed peer
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(w.winner_peer, 2)


func test_solo_game_over() -> void:
	var w := _world(1, false)
	var v: SimVehicle = w.vehicles[0]
	for i in 4:
		w._damage_vehicle(v, 1.0e6, -1)
		_respawn_wait(w, v)
		assert_eq(w.phase, SimWorld.PHASE_COMBAT, "solo play continues after %d deaths" % (i + 1))
	assert_eq(v.fuel, 20)
	w._damage_vehicle(v, 1.0e6, -1)
	assert_true(v.eliminated)
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(w.winner_peer, -1, "no winner")


func test_both_eliminated_no_winner() -> void:
	var w := _world(2)
	for v in w.vehicles:
		v.fuel = 20
		v.pos = Vector2(100, 100)
		w._damage_vehicle(v, 1.0e6, -1)
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(w.winner_peer, -1)


func test_dead_vehicle_respawns_for_the_workshop() -> void:
	var w := _world(2)
	var a: SimVehicle = w.vehicles[0]
	_step(w, SimWorld.FAST_COMBAT_TICKS - 10)
	w._damage_vehicle(a, 1.0e6, -1)
	_to_workshop(w)
	assert_true(a.alive, "back for the workshop")
	assert_eq(a.offers.size(), 3)
	assert_eq(a.fuel, 80)


func test_eliminated_vehicle_cannot_shop() -> void:
	var w := _world(3)
	_to_workshop(w)
	var a: SimVehicle = w.vehicles[0]
	a.eliminated = true
	a.offers = ["steel_plates", "v8_engine", "vulture"]
	w.apply_command(1, {"type": "pick_card", "value": 0})
	w.apply_command(1, {"type": "ready"})
	assert_false(a.picked or a.ready)
	# Ready-skip only waits for the others.
	w.apply_command(2, {"type": "ready"})
	w.apply_command(3, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)


# ---------------------------------------------------------------- snapshot

func _play_some(w: SimWorld) -> void:
	w.apply_command(1, {"type": "set_drive", "value": "charge"})
	_to_workshop(w)
	for v in w.vehicles:
		v.scrap = 200
	w.apply_command(1, {"type": "pick_card", "value": 0})
	w.apply_command(1, {"type": "buy_tech", "value": "ballistics_1"})
	w.apply_command(1, {"type": "buy_tech", "value": "engineering_1"})
	w.apply_command(2, {"type": "reroll"})
	w.vehicles[1].scrap_frac = 0.25


func _compare_round_state(host: SimWorld, client: SimWorld) -> void:
	assert_eq(client.phase, host.phase, "phase")
	assert_eq(client.round, host.round, "round")
	assert_eq(client.phase_ticks_left, host.phase_ticks_left, "phase_ticks_left")
	assert_eq(client.winner_peer, host.winner_peer, "winner_peer")
	assert_eq(client.leader_peer, host.leader_peer, "leader_peer")
	assert_eq(client.vehicles.size(), host.vehicles.size())
	for i in host.vehicles.size():
		var a: SimVehicle = host.vehicles[i]
		var b: SimVehicle = client.vehicles[i]
		assert_eq(b.fuel, a.fuel, "fuel")
		assert_eq(b.respawn_ticks, a.respawn_ticks, "respawn_ticks")
		assert_eq(b.eliminated, a.eliminated, "eliminated")
		assert_eq(b.ready, a.ready, "ready")
		assert_eq(b.picked, a.picked, "picked")
		assert_eq(b.reroll_cost, a.reroll_cost, "reroll_cost")
		assert_eq(b.protect_ticks, a.protect_ticks, "protect_ticks")
		assert_eq(b.offers, a.offers, "offers")
		assert_eq(b.cards, a.cards, "cards")
		assert_eq(b.tech, a.tech, "tech")
		assert_eq(b.scrap, a.scrap)
		assert_lt(absf(b.scrap_frac - a.scrap_frac), 0.0001, "scrap_frac")
		assert_lt(absf(b.max_hp - a.max_hp), 0.001, "max_hp")
		assert_lt(absf(b.armor - a.armor), 0.0001, "armor")
		assert_lt(absf(b.speed - a.speed), 0.0001, "speed")
		assert_lt(absf(b.turn_rate - a.turn_rate), 0.0001, "turn_rate")
		assert_lt(absf(b.scrap_mult - a.scrap_mult), 0.0001, "scrap_mult")
		assert_eq(b.weapon_slots, a.weapon_slots)
		assert_eq(b.interest_cap, a.interest_cap)
		assert_eq(b.weapons.size(), a.weapons.size(), "weapons")
		for k in a.weapons.size():
			for key in ["pellets", "pierce"]:
				assert_eq(int(b.weapons[k][key]), int(a.weapons[k][key]), key)
			for key in ["damage", "range", "spread", "splash", "speed"]:
				assert_lt(absf(float(b.weapons[k][key]) - float(a.weapons[k][key])), 0.0001, key)
			assert_eq(int(b.weapons[k]["cooldown_ticks"]), int(a.weapons[k]["cooldown_ticks"]))


func test_snapshot_round_trip_of_round_state() -> void:
	var host := _world(2)
	_play_some(host)
	assert_eq(host.phase, SimWorld.PHASE_WORKSHOP)
	assert_gt(float(host.vehicles[0].cards.size()), 1.0, "picked a card")
	assert_eq(host.vehicles[0].tech.size(), 2)
	var client := SimWorld.new(0)
	client.add_vehicle(9, Vector2(1, 1))  # stale content
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	_compare_round_state(host, client)
	assert_eq(client.vehicles[1].reroll_cost, SimWorld.REROLL_COST_START + 1)
	# Mid-combat with a dead vehicle, then game over with a winner.
	host.apply_command(1, {"type": "ready"})
	host.apply_command(2, {"type": "ready"})
	host.step()
	host.vehicles[0].fuel = 10
	host._damage_vehicle(host.vehicles[0], 1.0e6, -1)
	host.step()
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	_compare_round_state(host, client)
	assert_eq(client.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(client.winner_peer, 2)
	assert_true(client.vehicles[0].eliminated)


func test_snapshot_events_retreat_and_respawn() -> void:
	var host := _world(1)
	var evs: Array[Dictionary] = [
		{"type": "retreat", "pos": Vector2(100, 200), "owner": -1, "kind": 1},
		{"type": "respawn", "pos": Vector2(300, 400), "owner": 0, "kind": -1},
	]
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host, evs)))
	assert_eq(client.events.size(), 2)
	assert_eq(client.events[0]["type"], "retreat")
	assert_eq(client.events[0]["kind"], 1)
	assert_eq(client.events[1]["type"], "respawn")
	assert_eq(client.events[1]["owner"], 0)


func test_snapshot_enemy_hp_scales_with_round() -> void:
	var host := _world(1)
	host.round = 8
	host.spawn_enemy(SimWorld.BOULDER, Vector2(400, 400))
	host.spawn_enemy(SimWorld.MITE, Vector2(500, 400))
	host.enemy_hp[1] *= 0.5
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	assert_eq(client.round, 8)
	assert_lt(absf(client.enemy_hp[0] - host.enemy_hp[0]), 0.01, "full hp boulder survives the round trip")
	assert_lt(absf(client.enemy_hp[1] - host.enemy_hp[1]), SimWorld.enemy_max_hp(SimWorld.MITE, 8) / 15.0 + 0.01)


func test_snapshot_rejects_bad_round_state() -> void:
	var host := SimWorld.new(1)
	host.add_vehicle(1, Vector2(300, 300))  # no enemies / events / projectiles: the tail is the vehicle block
	var good: PackedByteArray = Snapshot.encode(host)
	var client := SimWorld.new(0)
	client.add_vehicle(1, Vector2(1, 2))
	assert_true(Snapshot.apply(client, good))
	client = SimWorld.new(0)
	client.add_vehicle(1, Vector2(1, 2))
	# Tail: ... cards n=1, idx, level, tech n=0, protect_ticks.
	var n: int = good.size()
	assert_eq(good[n - 5], 1, "one card")
	var bad_level: PackedByteArray = good.duplicate()
	bad_level[n - 3] = 9
	assert_false(Snapshot.apply(client, bad_level), "level out of range")
	var zero_level: PackedByteArray = good.duplicate()
	zero_level[n - 3] = 0
	assert_false(Snapshot.apply(client, zero_level), "level 0")
	var bad_card: PackedByteArray = good.duplicate()
	bad_card[n - 4] = 200
	assert_false(Snapshot.apply(client, bad_card), "card index out of range")
	var bad_tech: PackedByteArray = good.duplicate()
	bad_tech[n - 2] = 1
	bad_tech[n - 1] = 250
	bad_tech.append(0)
	assert_false(Snapshot.apply(client, bad_tech), "tech index out of range")
	var bad_phase: PackedByteArray = good.duplicate()
	bad_phase[21] = 7
	assert_false(Snapshot.apply(client, bad_phase), "unknown phase")
	var zero_round: PackedByteArray = good.duplicate()
	zero_round[22] = 0
	zero_round[23] = 0
	assert_false(Snapshot.apply(client, zero_round), "round 0")
	for cut in [1, 2, 5, 9, 20]:
		assert_false(Snapshot.apply(client, good.slice(0, n - cut)), "truncated by %d" % cut)
	assert_eq(client.vehicles[0].pos, Vector2(1, 2), "world untouched by rejected snapshots")
	assert_eq(client.phase, SimWorld.PHASE_COMBAT)


# ---------------------------------------------------------------- determinism

func _scripted_workshop(w: SimWorld) -> void:
	# Same policy for every run: pick the first offer, spend on tech in a fixed order, reroll once.
	for v in w.vehicles:
		if v.eliminated or v.ready:
			continue
		v.scrap += 40  # fast rounds earn little: top up identically in every run
		if w.round % 2 == 0:
			w.apply_command(v.peer_id, {"type": "reroll"})
		w.apply_command(v.peer_id, {"type": "pick_card", "value": (w.round + v.id) % 3})
		for t in ["engineering_1", "ballistics_1", "salvage_1", "electronics_1", "engineering_2", "ballistics_2"]:
			w.apply_command(v.peer_id, {"type": "buy_tech", "value": t})
		w.apply_command(v.peer_id, {"type": "ready"})


func _run_rounds(p_seed: int, rounds: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.fast_rounds = true
	w.add_vehicle(1, Vector2(400, 360))
	w.add_vehicle(2, Vector2(880, 360))
	w.apply_command(2, {"type": "set_drive", "value": "kite"})
	w.apply_command(2, {"type": "set_target", "value": "players_first"})
	var guard: int = 0
	while w.round <= rounds and w.phase != SimWorld.PHASE_GAME_OVER and guard < 20000:
		w.step()
		guard += 1
		if w.phase == SimWorld.PHASE_WORKSHOP and w.phase_ticks_left == w.workshop_duration() - 3:
			_scripted_workshop(w)
	return w


func test_determinism_across_rounds() -> void:
	var a := _run_rounds(77, 5)
	var b := _run_rounds(77, 5)
	var c := _run_rounds(78, 5)
	assert_true(a.round > 5 or a.phase == SimWorld.PHASE_GAME_OVER, "ran several rounds (round %d)" % a.round)
	assert_gt(float(a.vehicles[0].cards.size()), 1.0, "cards were picked")
	assert_gt(float(a.vehicles[0].tech.size()), 0.0, "tech was bought")
	assert_eq(a.tick, b.tick)
	assert_eq(a.checksum(), b.checksum(), "same seed + same commands = same state")
	assert_ne(a.checksum(), c.checksum(), "different seed")
	for i in a.vehicles.size():
		assert_eq(a.vehicles[i].offers, b.vehicles[i].offers)
		assert_eq(a.vehicles[i].cards, b.vehicles[i].cards)
		assert_eq(a.vehicles[i].tech, b.vehicles[i].tech)


func test_checksum_covers_round_state() -> void:
	var base_world := _world(2)
	_to_workshop(base_world)
	var base: int = base_world.checksum()
	assert_eq(base_world.checksum(), base, "stable")
	var changes: Array[Callable] = [
		func(s: SimWorld) -> void: s.phase_ticks_left -= 1,
		func(s: SimWorld) -> void: s.round += 1,
		func(s: SimWorld) -> void: s.winner_peer = 5,
		func(s: SimWorld) -> void: s.vehicles[0].fuel -= 1,
		func(s: SimWorld) -> void: s.vehicles[0].respawn_ticks += 1,
		func(s: SimWorld) -> void: s.vehicles[0].eliminated = true,
		func(s: SimWorld) -> void: s.vehicles[0].ready = true,
		func(s: SimWorld) -> void: s.vehicles[0].picked = true,
		func(s: SimWorld) -> void: s.vehicles[0].reroll_cost += 1,
		func(s: SimWorld) -> void: s.vehicles[0].scrap_frac += 0.5,
		func(s: SimWorld) -> void: s.vehicles[0].offers = ["vulture", "nitro", "mg"],
		func(s: SimWorld) -> void: s.vehicles[0].cards["steel_plates"] = 2,
		func(s: SimWorld) -> void: s.vehicles[0].tech.append("salvage_1"),
		func(s: SimWorld) -> void: s.vehicles[0].armor += 1.0,
		func(s: SimWorld) -> void: s.vehicles[0].weapons[0]["pierce"] = 3,
	]
	for i in changes.size():
		var sim := _world(2)
		_to_workshop(sim)
		assert_eq(sim.checksum(), base, "identical worlds hash alike (%d)" % i)
		changes[i].call(sim)
		assert_ne(sim.checksum(), base, "checksum covers change %d" % i)


# ---------------------------------------------------------------- command validation (net)

func test_validate_round_commands() -> void:
	for i in [0, 1, 2]:
		assert_eq(NetSession.validate_command({"type": "pick_card", "value": i}), {"type": "pick_card", "value": i})
		var from_float: Dictionary = NetSession.validate_command({"type": "pick_card", "value": float(i)})
		assert_eq(from_float, {"type": "pick_card", "value": i}, "integral float accepted and returned as int")
		assert_eq(typeof(from_float["value"]), TYPE_INT)
	var bad_picks: Array = [3, -1, 100, 1.5, 0.1, 2.0000001, -0.5, NAN, INF, -INF, "1", "0", "", true, null, [1], {"v": 1}, 1.0e30]
	for b: Variant in bad_picks:
		assert_true(NetSession.validate_command({"type": "pick_card", "value": b}).is_empty(), "rejected pick %s" % str(b))
	assert_true(NetSession.validate_command({"type": "pick_card"}).is_empty(), "pick_card needs a value")

	for id in ["ballistics_1", "engineering_3", "salvage_2", "electronics_1", "propulsion_3"]:
		assert_eq(NetSession.validate_command({"type": "buy_tech", "value": id}), {"type": "buy_tech", "value": id})
	var bad_tech: Array = ["", "ballistics_4", "BALLISTICS_1", "ballistics_1 ", "mg", 1, 1.0, null, ["ballistics_1"], "x".repeat(500)]
	for b: Variant in bad_tech:
		assert_true(NetSession.validate_command({"type": "buy_tech", "value": b}).is_empty(), "rejected tech %s" % str(b).left(20))
	assert_true(NetSession.validate_command({"type": "buy_tech"}).is_empty())

	for t in ["reroll", "ready"]:
		assert_eq(NetSession.validate_command({"type": t}), {"type": t})
		assert_eq(NetSession.validate_command({"type": t, "value": null}), {"type": t})
		assert_eq(NetSession.validate_command({"type": t, "value": "x", "hp": 99}), {"type": t}, "value dropped")
	for t in ["Ready", "reroll ", "give_card", "pick", "buy", ""]:
		assert_true(NetSession.validate_command({"type": t}).is_empty(), "rejected type '%s'" % t)
	# Old commands are unchanged.
	assert_false(NetSession.validate_command({"type": "set_drive", "value": "kite"}).is_empty())
	assert_true(NetSession.validate_command({"type": "set_drive", "value": 1}).is_empty())
	assert_true(NetSession.validate_command({"type": "set_drive", "value": "ballistics_1"}).is_empty())


func test_session_round_flow_and_departure() -> void:
	var s := NetSession.new()
	s.start_solo()
	s.world.fast_rounds = true
	s.world.spawning_enabled = false
	var v: SimVehicle = s.world.get_vehicle_for_peer(1)
	s.send_command({"type": "pick_card", "value": 0})
	assert_eq(v.cards, {"mg": 1}, "ignored in combat")
	for i in SimWorld.FAST_COMBAT_TICKS:
		s._physics_process(1.0 / 30.0)
	assert_eq(s.world.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(v.offers.size(), 3)
	var offered: String = v.offers[2]
	s.send_command({"type": "pick_card", "value": 2.0})
	assert_true(v.picked, "float index from JSON / RPC works")
	assert_eq(int(v.cards.get(offered, 0)) >= 1, true)
	v.scrap = 100
	s.send_command({"type": "buy_tech", "value": "salvage_1"})
	assert_eq(v.tech, ["salvage_1"] as Array[String])
	s.send_command({"type": "buy_tech", "value": "salvage_3"})
	assert_eq(v.tech.size(), 1, "prerequisite enforced through the session")
	s.send_command({"type": "ready"})
	s._physics_process(1.0 / 30.0)
	assert_eq(s.world.phase, SimWorld.PHASE_COMBAT)
	assert_eq(s.world.round, 2)
	s.free()

	# A host loses its only client: the host wins.
	var h := NetSession.new()
	h._mode = NetSession.Mode.HOST
	h._new_world(true)
	h.world.spawning_enabled = false
	h._spawn_vehicle_for(1)
	h._spawn_vehicle_for(2)
	assert_eq(h.world.vehicles.size(), 2)
	h._on_peer_disconnected(2)
	var gone: SimVehicle = h.world.vehicles[1]
	assert_true(gone.eliminated and not gone.alive)
	assert_eq(gone.peer_id, 0)
	h.world.step()
	assert_eq(h.world.phase, SimWorld.PHASE_GAME_OVER)
	assert_eq(h.world.winner_peer, 1)
	h.free()
