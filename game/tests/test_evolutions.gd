extends TestCase
## Weapon evolutions (design doc 5a): eligibility, guaranteed offer in slot 0, evolve in place, never offered twice,
## determinism and the snapshot round trip.

const PAIRS := [
	["mg", "v8_engine", "evo_gatling"],
	["shotgun", "spiked_plating", "evo_grinder"],
	["cannon", "caterpillar_tracks", "evo_earthshaker"],
	["flamer", "nitro", "evo_inferno"],
]


func _veh(cards: Dictionary) -> SimVehicle:
	var v := SimVehicle.new(0, 1, Vector2(500, 500))
	v.cards = cards.duplicate()
	Cards.recompute(v)
	return v


func test_eligibility() -> void:
	for p in PAIRS:
		var el: Array[String] = Cards.eligible_evolutions(_veh({p[0]: 3, p[1]: 1}))
		assert_eq(el.size(), 1, p[2])
		assert_eq(el[0], p[2])
		assert_true(Cards.eligible_evolutions(_veh({p[0]: 2, p[1]: 3})).is_empty(), "weapon below max level")
		assert_true(Cards.eligible_evolutions(_veh({p[0]: 3})).is_empty(), "partner missing")
		assert_true(Cards.eligible_evolutions(_veh({p[1]: 3})).is_empty(), "weapon missing")
		assert_true(Cards.is_offerable(_veh({p[0]: 3, p[1]: 1}), p[2]))
		assert_false(Cards.is_offerable(_veh({p[0]: 2, p[1]: 1}), p[2]))
		var d: Dictionary = Cards.def(p[2])
		assert_eq(d["category"], "evolution")
		assert_eq(d["rarity"], "legendary")
		assert_true(str(d["text"]).length() > 20)


func test_never_in_ordinary_draws() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var v := _veh({"shotgun": 2, "v8_engine": 1})
	for i in 300:
		for id in Cards.roll_offers(rng, v, 3, 1 + i % 8):
			assert_false(Cards.is_evolution(id), "no evolution without the ingredients")


func test_offer_guaranteed_in_slot_zero_and_rerolls_keep_it() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for p in PAIRS:
		var v := _veh({p[0]: 3, p[1]: 1, "steel_plates": 1})
		var prev: Array[String] = []
		for i in 100:
			var offers: Array[String] = Cards.roll_offers(rng, v, 3, 1 + i % 8, prev)
			assert_eq(offers.size(), 3)
			assert_eq(offers[0], p[2], "slot 0 is the evolution")
			var uniq := {}
			for id in offers:
				uniq[id] = true
			assert_eq(uniq.size(), 3, "distinct")
			prev = offers
		assert_eq(Cards.roll_offers(rng, v, 4, 2)[0], p[2], "bonus offers keep it too")


func test_evolve_in_place_and_not_offered_twice() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for p in PAIRS:
		var v := _veh({"steel_plates": 1, p[1]: 1, p[0]: 3})
		assert_eq(v.weapons.size(), 1)
		var before: Dictionary = (v.weapons[0] as Dictionary).duplicate()
		assert_false(bool(before["evo"]))
		assert_true(Cards.grant(v, p[2]))
		assert_eq(v.weapons.size(), 1, "same number of weapons")
		var w: Dictionary = v.weapons[0]
		assert_eq(w["kind"], p[0], "same kind")
		assert_true(bool(w["evo"]), "evo flag")
		assert_eq(int(v.cards[p[0]]), 3, "weapon card level unchanged")
		var dps_before: float = float(before["damage"]) / float(before["cooldown_ticks"]) * float(before["pellets"])
		var dps_after: float = float(w["damage"]) / float(w["cooldown_ticks"]) * float(w["pellets"])
		assert_gt(dps_after, dps_before * 0.95, "not weaker")
		assert_true(int(w["pierce"]) > int(before["pierce"]) or float(w["splash"]) > float(before["splash"]))
		assert_false(Cards.is_offerable(v, p[2]), "owned")
		assert_true(Cards.eligible_evolutions(v).is_empty())
		assert_false(Cards.grant(v, p[2]) and int(v.cards[p[2]]) > 1, "no second level")
		for i in 100:
			assert_false(Cards.roll_offers(rng, v, 3, 1 + i % 8).has(p[2]))


func test_evolved_numbers() -> void:
	var v := _veh({"mg": 3, "v8_engine": 1, "evo_gatling": 1})
	var w: Dictionary = v.weapons[0]
	assert_eq(float(w["cooldown_ticks"]), 1.0, "double fire rate")
	assert_eq(int(w["pierce"]), 1)
	assert_gt(float(w["spread"]), float(Cards.WEAPONS["mg"]["spread"]))
	v = _veh({"shotgun": 3, "spiked_plating": 1, "evo_grinder": 1})
	assert_eq(int(v.weapons[0]["pellets"]), 12)
	assert_eq(int(v.weapons[0]["pierce"]), 2)
	v = _veh({"cannon": 3, "caterpillar_tracks": 1, "evo_earthshaker": 1})
	assert_eq(int(v.weapons[0]["pierce"]), 3)
	assert_gt(float(v.weapons[0]["splash"]), 28.0)
	v = _veh({"flamer": 3, "nitro": 1, "evo_inferno": 1})
	assert_gt(float(v.weapons[0]["range"]), 115.0)
	assert_gt(float(v.weapons[0]["pierce"]), 4.0)


func test_evolution_card_cannot_be_scrapped_and_needs_max_weapon() -> void:
	var v := _veh({"mg": 3, "v8_engine": 1, "evo_gatling": 1})
	v.tech_fx["scrap_press"] = 1.0
	assert_false(Salvage.scrap_card(v, "evo_gatling"))
	assert_true(Cards.is_evolved(v, "mg"))
	v.cards["mg"] = 2
	Cards.recompute(v)
	assert_false(bool(v.weapons[0]["evo"]), "evolution pauses below max level")


func _fight(seed_: int) -> SimWorld:
	var w := SimWorld.new(seed_)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	v.cards = {"flamer": 3, "nitro": 1, "evo_inferno": 1}
	Cards.recompute(v)
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	for i in 12:
		w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(80 + i * 6, (i % 4) * 7 - 10))
	w.rebuild_derived()
	return w


func test_inferno_leaves_fire_zones_and_is_deterministic() -> void:
	var a := _fight(21)
	var b := _fight(21)
	var zones: int = 0
	for t in 120:
		a.step()
		b.step()
		for z in a.zone_count:
			if a.zone_kind[z] == SimWorld.ZONE_FIRE:
				zones += 1
	assert_gt(float(zones), 0.0, "fire zones appear")
	assert_lt(float(a.zone_count), 40.0, "capped rate")
	assert_eq(a.checksum(), b.checksum(), "deterministic")


func test_snapshot_round_trip_keeps_evo_flag() -> void:
	var w := _fight(4)
	for t in 10:
		w.step()
	var r := SimWorld.new(1)
	assert_true(Snapshot.apply(r, Snapshot.encode(w)))
	var v: SimVehicle = r.vehicles[0]
	assert_true(Cards.is_evolved(v, "flamer"))
	assert_true(bool(v.weapons[0]["evo"]), "weapon carries evo after decode")
	assert_eq(int(v.cards["evo_inferno"]), 1)
