extends TestCase
## Tech tree v2.3 (stage 1): node table, costs, requirements, exclusive choices, active versus
## owned, dormant fusions, respec, snapshot and determinism.


func _vehicle(scrap: int = 9000) -> SimVehicle:
	var v := SimVehicle.new(0, 1, Vector2(100, 100))
	v.scrap = scrap
	return v


func _buy_all(v: SimVehicle, ids: Array, world_round: int = 1) -> void:
	for id: String in ids:
		assert_true(Tech.buy(v, id, world_round), "buy " + id)


func _workshop(players: int = 1) -> SimWorld:
	var w := SimWorld.new(21)
	w.fast_rounds = true
	w.spawning_enabled = false
	for i in players:
		w.add_vehicle(i + 1, Vector2(300.0 + 500.0 * float(i), 360.0))
	var guard: int = 0
	while w.phase == SimWorld.PHASE_COMBAT and guard < 5000:
		w.step()
		guard += 1
	return w


const WAR_RIG_CHAIN: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_drone",
	"engineering_truck", "engineering_war_rig"]


func test_table_and_costs() -> void:
	assert_eq(Tech.count(), 72)
	var branch_nodes: int = 0
	for b in Tech.BRANCHES:
		branch_nodes += Tech.ids(b).size()
	assert_eq(branch_nodes, 61, "61 branch nodes")
	assert_eq(Tech.ids("", "fusion_s").size(), 6)
	assert_eq(Tech.ids("", "fusion_l").size(), 5)
	var costs := {"ballistics_ammo_bench": 100, "ballistics_belt_feed": 140, "ballistics_tables": 240,
		"ballistics_hot_loads": 180, "ballistics_scatter": 380, "ballistics_tungsten": 520, "ballistics_glowing": 750,
		"salvage_loan": 140, "propulsion_dirty_fuel": 180, "fusion_thermite": 200, "fusion_burning_wake": 450}
	for id: String in costs:
		assert_eq(Tech.cost(id), int(costs[id]), id)
	assert_eq(Tech.choices("salvage", 2).size(), 3, "salvage has three styles")
	assert_eq(Tech.choices("ballistics", 2).size(), 2)
	for i in Tech.count():
		assert_eq(Tech.index_of(Tech.id_at(i)), i)


func test_requirements() -> void:
	var v := _vehicle()
	assert_false(Tech.can_buy(v, "ballistics_belt_feed"), "stage 2 needs stage 1")
	_buy_all(v, ["ballistics_ammo_bench", "ballistics_belt_feed"])
	assert_false(Tech.can_buy(v, "ballistics_scatter"), "stage 4 needs the stage 3 core")
	assert_true(Tech.can_buy(v, "ballistics_hot_loads"), "the prototype needs a stage 2 choice")
	assert_true(Tech.can_buy(v, "ballistics_tables"))
	assert_eq(Tech.missing(v, "ballistics_scatter"), "ballistics_tables")
	assert_eq(Tech.missing(v, "ballistics_tungsten"), "ballistics_scatter", "stage 5 needs a stage 4 choice")
	assert_eq(Tech.missing(v, "fusion_thermite"), "propulsion_bumper")
	assert_eq(Tech.requirements("engineering_war_rig"), ["engineering_truck"], "explicit override")


func test_prototype_does_not_open_stage_4() -> void:
	var v := _vehicle()
	_buy_all(v, ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_hot_loads"])
	assert_eq(Tech.branch_tier(v, "ballistics"), 2, "the prototype is not a tier")
	for id in ["ballistics_scatter", "ballistics_napalm", "ballistics_he"]:
		assert_false(Tech.can_buy(v, id), id)
	assert_true(Tech.buy(v, "ballistics_tables"))
	assert_true(Tech.can_buy(v, "ballistics_napalm"))
	assert_eq(Tech.cost("ballistics_hot_loads"), Tech.PROTO_COST)


func test_exclusive_choices_per_branch_and_stage() -> void:
	var v := _vehicle()
	_buy_all(v, ["salvage_hooks", "salvage_haggler"])
	assert_eq(Tech.blocked_by(v, "salvage_lucky"), "salvage_haggler")
	assert_false(Tech.can_buy(v, "salvage_loan"))
	assert_true(Tech.buy(v, "salvage_black_market"), "the core is not part of a group")
	assert_true(Tech.buy(v, "salvage_insurance"), "prototype next to the core")
	assert_true(Tech.buy(v, "salvage_press"))
	assert_false(Tech.can_buy(v, "salvage_hoarder"))
	assert_eq(Tech.blocked_by(v, "salvage_hoarder"), "salvage_press")


func test_active_applies_fx_only() -> void:
	var v := _vehicle()
	_buy_all(v, WAR_RIG_CHAIN.slice(0, 5))
	assert_eq(v.chassis, 3)
	var hp: float = v.max_hp
	v.tech.append("engineering_war_rig")
	Cards.recompute(v)
	assert_eq(v.chassis, 4)
	assert_gt(v.max_hp, hp)
	v.tech.assign(["engineering_war_rig"])  # owned but its whole chain is missing
	Cards.recompute(v)
	assert_false(Tech.active(v, "engineering_war_rig"))
	assert_eq(v.chassis, 1)
	assert_eq(v.max_hp, SimVehicle.MAX_HP)
	assert_eq(float(v.tech_fx.get("chassis", 0.0)), 0.0)


func test_war_rig_chain_survives_respec() -> void:
	var v := _vehicle()
	_buy_all(v, WAR_RIG_CHAIN)
	assert_true(Tech.active(v, "engineering_war_rig"))
	assert_eq(v.chassis, 4)
	var scrap: int = v.scrap
	assert_true(Tech.respec(v, "engineering_truck", "engineering_roll_cage", 1))
	assert_eq(v.scrap, scrap, "first respec is free")
	assert_true(v.tech.has("engineering_war_rig"), "follow-up nodes stay owned")
	assert_false(Tech.active(v, "engineering_war_rig"), "but the chain is broken")
	assert_eq(v.chassis, 2, "back to the pickup")
	assert_eq(float(v.tech_fx.get("slots", 0.0)), 1.0, "only the pickup slot counts")
	assert_true(Tech.respec(v, "engineering_roll_cage", "engineering_truck", 1))
	assert_eq(v.scrap, scrap - Tech.cost("engineering_truck") / 2, "second respec costs 50% of the new node")
	assert_true(Tech.active(v, "engineering_war_rig"), "active again for free")
	assert_eq(v.chassis, 4)
	assert_eq(v.respecs, 2)


func test_speed_penalties() -> void:
	var v := _vehicle()
	_buy_all(v, ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_drone", "engineering_truck"])
	assert_true(absf(v.speed - (1.0 - 0.05 - 0.06)) < 0.0001, "pickup and truck slow the rig")
	assert_true(Tech.respec(v, "engineering_truck", "engineering_roll_cage", 1))
	assert_true(absf(v.speed - (1.0 - 0.05 * 0.5)) < 0.0001, "roll cage halves the penalty")
	v.tech.append_array(["engineering_featherweight"])
	Cards.recompute(v)
	assert_true(absf(v.speed - 1.20) < 0.0001, "featherweight removes penalties and adds speed")
	assert_true(absf(v.max_hp - (SimVehicle.MAX_HP + 40.0 + 80.0) * 0.85) < 0.01, "hp_pct scales after flat hp")


func test_fusion_goes_dormant_and_rebuys_at_half() -> void:
	var v := _vehicle()
	_buy_all(v, ["ballistics_ammo_bench", "ballistics_belt_feed", "propulsion_tuned", "propulsion_bumper", "fusion_thermite"])
	assert_true(Tech.active(v, "fusion_thermite"))
	assert_eq(float(v.tech_fx.get("thermite", 0.0)), 1.0)
	assert_true(Tech.respec(v, "propulsion_bumper", "propulsion_drift", 1))
	assert_false(v.tech.has("fusion_thermite"), "moved out of the owned list")
	assert_true(v.tech_dormant.has("fusion_thermite"))
	assert_eq(float(v.tech_fx.get("thermite", 0.0)), 0.0)
	assert_false(Tech.can_buy(v, "fusion_thermite"), "requirements are not met")
	assert_true(Tech.respec(v, "propulsion_drift", "propulsion_bumper", 1))
	assert_true(v.tech_dormant.has("fusion_thermite"), "swapping back does not revive it by itself")
	assert_eq(Tech.price(v, "fusion_thermite"), Tech.SMALL_FUSION_COST / 2)
	var scrap: int = v.scrap
	assert_true(Tech.buy(v, "fusion_thermite", 2))
	assert_eq(v.scrap, scrap - 100, "50% re-buy")
	assert_true(v.tech.has("fusion_thermite"))
	assert_true(v.tech_dormant.is_empty())
	assert_eq(Tech.price(v, "fusion_thermite"), Tech.SMALL_FUSION_COST, "base price once it is owned again")


func test_respec_pricing_and_validation() -> void:
	var v := _vehicle(1100)
	_buy_all(v, ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_scatter"])
	var scrap: int = v.scrap
	assert_eq(Tech.respec_cost(v, "ballistics_he"), 0)
	assert_false(Tech.can_respec(v, "ballistics_scatter", "ballistics_tungsten", 1), "different stage")
	assert_false(Tech.can_respec(v, "ballistics_tables", "ballistics_hot_loads", 1), "only choices swap")
	assert_false(Tech.can_respec(v, "ballistics_napalm", "ballistics_he", 1), "from must be owned")
	assert_false(Tech.can_respec(v, "ballistics_scatter", "ballistics_scatter", 1))
	assert_true(Tech.respec(v, "ballistics_scatter", "ballistics_napalm", 1))
	assert_eq(v.scrap, scrap, "first respec is free")
	assert_eq(v.tech.find("ballistics_napalm"), 3, "swapped in place")
	assert_eq(Tech.respec_cost(v, "ballistics_he"), 190)
	assert_true(Tech.respec(v, "ballistics_napalm", "ballistics_he", 1))
	assert_eq(v.scrap, scrap - 190)
	v.scrap = 189
	assert_false(Tech.respec(v, "ballistics_he", "ballistics_scatter", 1), "unaffordable")
	assert_true(v.tech.has("ballistics_he"))
	assert_eq(v.scrap, 189)
	assert_eq(v.respecs, 2)


func test_keystone_respec_window() -> void:
	var v := _vehicle()
	_buy_all(v, ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm", "ballistics_tungsten"])
	assert_true(Tech.buy(v, "ballistics_glowing", 3))
	assert_eq(int(v.tech_round["ballistics_glowing"]), 3)
	assert_true(Tech.can_respec(v, "ballistics_glowing", "ballistics_one_shot", 4), "the round after buying")
	assert_false(Tech.can_respec(v, "ballistics_glowing", "ballistics_one_shot", 5), "window closed")
	assert_true(Tech.can_respec(v, "ballistics_tungsten", "ballistics_mixed_belts", 9), "other stages have no window")
	assert_true(Tech.respec(v, "ballistics_glowing", "ballistics_one_shot", 4))
	assert_eq(int(v.tech_round["ballistics_one_shot"]), 3, "the window does not restart")
	assert_false(v.tech_round.has("ballistics_glowing"))


func test_respec_command_and_validation() -> void:
	var w := _workshop()
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 2000
	for id in ["ballistics_ammo_bench", "ballistics_belt_feed"]:
		w.apply_command(1, {"type": "buy_tech", "value": id})
	assert_eq(int(v.tech_round["ballistics_belt_feed"]), w.round)
	var scrap: int = v.scrap
	w.apply_command(1, {"type": "respec_tech", "from": "ballistics_belt_feed", "value": "ballistics_heavy_shells"})
	assert_true(v.tech.has("ballistics_heavy_shells"))
	assert_eq(v.scrap, scrap)
	assert_eq(v.respecs, 1)
	w.apply_command(1, {"type": "respec_tech", "from": "nope", "value": "ballistics_belt_feed"})
	assert_eq(v.respecs, 1)
	var ok: Dictionary = NetSession.validate_command({"type": "respec_tech", "from": "salvage_haggler", "value": "salvage_lucky", "x": 1})
	assert_eq(ok, {"type": "respec_tech", "from": "salvage_haggler", "value": "salvage_lucky"})
	for bad: Dictionary in [{"type": "respec_tech", "value": "salvage_lucky"}, {"type": "respec_tech", "from": "salvage_lucky"},
			{"type": "respec_tech", "from": "x", "value": "salvage_lucky"}, {"type": "respec_tech", "from": 1, "value": "salvage_lucky"},
			{"type": "respec_tech", "from": ["salvage_lucky"], "value": "salvage_haggler"}]:
		assert_true(NetSession.validate_command(bad).is_empty(), str(bad))
	# not in combat
	var c := SimWorld.new(3)
	c.add_vehicle(1, Vector2(300, 300))
	c.vehicles[0].scrap = 1000
	c.apply_command(1, {"type": "buy_tech", "value": "ballistics_ammo_bench"})
	assert_eq(c.vehicles[0].tech.size(), 0)


func test_rule_slots_from_tech() -> void:
	var v := _vehicle()
	assert_eq(Doctrine.slots(v), Doctrine.BASE_SLOTS)
	_buy_all(v, ["electronics_rangefinder", "electronics_relay", "electronics_targeting", "electronics_emp", "electronics_neural"])
	assert_eq(Doctrine.slots(v), mini(Doctrine.BASE_SLOTS + 3, Doctrine.MAX_SLOTS))


func test_fusion_partners() -> void:
	var p: Array[String] = Tech.fusion_partners("electronics_relay")
	assert_eq(p.size(), 3)
	for f in ["fusion_lucky_strike", "fusion_fortified", "fusion_junkyard"]:
		assert_true(p.has(f), f)
	assert_true(Tech.fusion_partners("ballistics_tables").is_empty())


func test_snapshot_round_trip_of_tech_state() -> void:
	var host := _workshop(2)
	var v: SimVehicle = host.vehicles[0]
	v.scrap = 5000
	for id in ["ballistics_ammo_bench", "ballistics_belt_feed", "propulsion_tuned", "propulsion_bumper"]:
		host.apply_command(1, {"type": "buy_tech", "value": id})
	host.apply_command(1, {"type": "buy_tech", "value": "fusion_thermite"})
	host.apply_command(1, {"type": "respec_tech", "from": "propulsion_bumper", "value": "propulsion_drift"})
	assert_eq(v.tech_dormant, ["fusion_thermite"] as Array[String])
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	var c: SimVehicle = client.vehicles[0]
	assert_eq(c.tech, v.tech)
	assert_eq(c.tech_dormant, v.tech_dormant)
	assert_eq(c.respecs, 1)
	assert_eq(c.tech_round, v.tech_round)
	assert_eq(c.chassis, v.chassis)
	assert_eq(c.tech_fx, v.tech_fx)
	assert_lt(absf(c.turn_rate - v.turn_rate), 0.0001, "derived stats follow the active tech")
	# the checksum covers the new state
	var base: int = host.checksum()
	v.respecs += 1
	assert_ne(host.checksum(), base, "respecs")
	v.respecs -= 1
	v.tech_dormant.clear()
	assert_ne(host.checksum(), base, "dormant fusions")
	v.tech_dormant.append("fusion_thermite")
	v.tech_round["ballistics_belt_feed"] = 99
	assert_ne(host.checksum(), base, "purchase rounds")


func _scripted(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.fast_rounds = true
	w.spawning_enabled = false
	w.add_vehicle(1, Vector2(300, 360))
	w.add_vehicle(2, Vector2(800, 360))
	for r in 4:
		var guard: int = 0
		while w.phase == SimWorld.PHASE_COMBAT and guard < 5000:
			w.step()
			guard += 1
		for v in w.vehicles:
			v.scrap += 800
			for id in ["ballistics_ammo_bench", "ballistics_belt_feed", "propulsion_tuned", "propulsion_bumper",
					"fusion_thermite", "engineering_frame", "engineering_welder"]:
				w.apply_command(v.peer_id, {"type": "buy_tech", "value": id})
			if r == 1:
				w.apply_command(v.peer_id, {"type": "respec_tech", "from": "propulsion_bumper", "value": "propulsion_drift"})
			if r == 2:
				w.apply_command(v.peer_id, {"type": "respec_tech", "from": "propulsion_drift", "value": "propulsion_bumper"})
				w.apply_command(v.peer_id, {"type": "buy_tech", "value": "fusion_thermite"})
			w.apply_command(v.peer_id, {"type": "ready"})
		w.step()
	return w


func test_determinism() -> void:
	var a := _scripted(77)
	var b := _scripted(77)
	assert_eq(a.checksum(), b.checksum())
	assert_gt(float(a.vehicles[0].respecs), 0.0, "respecs happened")
	assert_true(a.vehicles[0].tech.has("fusion_thermite"), "dormant fusion was re-bought")
