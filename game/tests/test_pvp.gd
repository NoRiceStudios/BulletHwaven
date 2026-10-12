extends TestCase
## PvP grace period (rounds before SimWorld.PVP_START_ROUND) and anti-snowball rules (leader bounty,
## third-party protection). Design doc sections 7j and 8.


func _duel(round_n: int, drive: String = "circle") -> SimWorld:
	var w := SimWorld.new(99)
	w.spawning_enabled = false
	w.round = round_n
	for i in 2:
		var v := w.add_vehicle(i + 1, Vector2(600.0 + 80.0 * float(i), 360.0))
		w.apply_command(i + 1, {"type": "set_target", "value": "players_first"})
		w.apply_command(i + 1, {"type": "set_drive", "value": drive})
	return w


func _three(round_n: int) -> SimWorld:
	var w := SimWorld.new(7)
	w.spawning_enabled = false
	w.round = round_n
	for i in 3:
		var v := w.add_vehicle(i + 1, Vector2(200.0 + 400.0 * float(i), 360.0))
		v.weapons.clear()
		v.speed = 0.0
	return w


func test_pvp_enabled_by_round() -> void:
	var w := SimWorld.new(1)
	assert_eq(SimWorld.PVP_START_ROUND, 4)
	for r in [1, 2, 3]:
		w.round = r
		assert_false(w.pvp_enabled(), "grace round %d" % r)
	for r in [4, 5, 12]:
		w.round = r
		assert_true(w.pvp_enabled(), "round %d" % r)


func test_no_shooting_in_grace_rounds() -> void:
	var w := _duel(3)
	for i in 300:
		w.step()
		for v in w.vehicles:
			assert_ne(v.target_kind, 2, "no player is targeted")
	assert_eq(w.vehicles[0].hp, w.vehicles[0].max_hp)
	assert_eq(w.vehicles[1].hp, w.vehicles[1].max_hp)
	assert_eq(w.proj_count, 0, "nobody fired")


func test_stray_player_projectiles_pass_through_in_grace() -> void:
	var w := _duel(2)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.weapons.clear()
	b.weapons.clear()
	a.speed = 0.0
	b.speed = 0.0
	b.pos = a.pos + Vector2(60, 0)
	w.spawn_projectile(a.pos + Vector2(20, 0), Vector2(400, 0), 1.0, 50.0, a.id)
	for i in 20:
		w.step()
	assert_eq(b.hp, b.max_hp, "player projectile does not hurt a rival in the grace period")
	# The same shot hurts from the first PvP round on.
	var w2 := _duel(SimWorld.PVP_START_ROUND)
	var b2: SimVehicle = w2.vehicles[1]
	w2.vehicles[0].weapons.clear()
	b2.weapons.clear()
	w2.vehicles[0].speed = 0.0
	b2.speed = 0.0
	b2.pos = w2.vehicles[0].pos + Vector2(60, 0)
	w2.spawn_projectile(w2.vehicles[0].pos + Vector2(20, 0), Vector2(400, 0), 1.0, 50.0, 0)
	for i in 20:
		w2.step()
	assert_lt(b2.hp, b2.max_hp)


func test_alien_projectiles_still_hit_in_grace() -> void:
	var w := _duel(1)
	var b: SimVehicle = w.vehicles[1]
	for v in w.vehicles:
		v.weapons.clear()
		v.speed = 0.0
	w.spawn_projectile(b.pos + Vector2(-40, 0), Vector2(300, 0), 1.0, 20.0, -1)
	for i in 10:
		w.step()
	assert_lt(b.hp, b.max_hp, "acid hurts in every round")


func test_no_ram_damage_in_grace() -> void:
	for pair in [[2, true], [SimWorld.PVP_START_ROUND, false]]:
		var w := _duel(int(pair[0]), "charge")
		w.vehicles[1].pos = w.vehicles[0].pos + Vector2(20, 0)  # overlapping hulls
		for i in 60:
			w.step()
		var hurt: bool = w.vehicles[0].hp < w.vehicles[0].max_hp or w.vehicles[1].hp < w.vehicles[1].max_hp
		assert_eq(hurt, not bool(pair[1]), "ram damage only from round %d" % SimWorld.PVP_START_ROUND)


func test_players_first_attacks_from_round_four() -> void:
	var w := _duel(SimWorld.PVP_START_ROUND)
	var saw_target := false
	for i in 30:
		w.step()
		saw_target = saw_target or w.vehicles[0].target_kind == 2
	assert_true(saw_target)
	assert_lt(w.vehicles[1].hp, w.vehicles[1].max_hp)


func test_pvp_rule_flips_when_the_round_advances() -> void:
	var w := _duel(3)
	w.fast_rounds = true
	for i in 100:
		w.step()
	assert_eq(w.vehicles[0].hp, w.vehicles[0].max_hp)
	assert_eq(w.vehicles[1].hp, w.vehicles[1].max_hp)
	w.round = 4
	w.phase = SimWorld.PHASE_COMBAT
	w.phase_ticks_left = 1000
	for i in 100:
		w.step()
	assert_lt(minf(w.vehicles[0].hp, w.vehicles[1].hp), 300.0, "PvP is on in round 4")


func test_leader_is_marked_from_pvp_rounds_only() -> void:
	var w := _three(3)
	w.vehicles[1].kills = 50
	w.step()
	assert_eq(w.leader_peer, -1, "no leader during the grace period")
	w.round = 4
	w.step()
	assert_eq(w.leader_peer, 2, "most kills + scrap/10")
	w.vehicles[2].scrap = 2000  # 200 points
	w.step()
	assert_eq(w.leader_peer, 3)
	w.vehicles[2].eliminated = true
	w.step()
	assert_eq(w.leader_peer, 2, "eliminated vehicles cannot lead")
	w.vehicles[0].eliminated = true
	w.step()
	assert_eq(w.leader_peer, -1, "a lone survivor is not a leader")


func test_leader_ties_keep_the_incumbent() -> void:
	var w := _three(4)
	w.step()
	assert_eq(w.leader_peer, -1, "everybody at 0: nobody is marked")
	w.vehicles[0].kills = 10
	w.step()
	assert_eq(w.leader_peer, 1)
	w.vehicles[1].kills = 10
	w.step()
	assert_eq(w.leader_peer, 1, "tie: the incumbent keeps the mark")
	w.vehicles[2].kills = 10
	w.vehicles[0].kills = 9
	w.vehicles[0].scrap = 0
	w.step()
	assert_eq(w.leader_peer, -1, "tie that excludes the incumbent: nobody")


func test_leader_bounty() -> void:
	var w := _three(4)
	var killer: SimVehicle = w.vehicles[0]
	w.vehicles[2].kills = 30
	w.step()
	assert_eq(w.leader_peer, 3)
	var before: int = killer.scrap
	w._damage_vehicle(w.vehicles[2], 1.0e6, killer.id)
	assert_eq(killer.scrap - before, SimWorld.PVP_KILL_SCRAP * SimWorld.LEADER_BOUNTY_MULT, "leader bounty")
	assert_eq(SimWorld.PVP_KILL_SCRAP * SimWorld.LEADER_BOUNTY_MULT, 45)
	# A normal victim pays the normal bounty.
	before = killer.scrap
	w._damage_vehicle(w.vehicles[1], 1.0e6, killer.id)
	assert_eq(killer.scrap - before, SimWorld.PVP_KILL_SCRAP, "normal bounty")
	assert_eq(killer.kills, 2)


func test_third_party_protection() -> void:
	var w := _three(4)
	var killer: SimVehicle = w.vehicles[0]
	w._damage_vehicle(w.vehicles[1], 1.0e6, killer.id)
	assert_eq(killer.protect_ticks, SimWorld.PVP_PROTECT_TICKS)
	# Damage is halved while protected (aliens included).
	var hp0: float = killer.hp
	w._damage_vehicle(killer, 10.0, -1, false)
	assert_eq(killer.hp, hp0 - 10.0 * SimWorld.PVP_PROTECT_FACTOR)
	# It wears off after 2 s of combat.
	for i in SimWorld.PVP_PROTECT_TICKS:
		w.step()
	assert_eq(killer.protect_ticks, 0)
	hp0 = killer.hp
	w._damage_vehicle(killer, 10.0, -1, false)
	assert_eq(killer.hp, hp0 - 10.0)
	# An alien kill grants nothing, and the dead victim gets no protection.
	w._damage_vehicle(w.vehicles[2], 1.0e6, -1)
	assert_eq(w.vehicles[2].protect_ticks, 0)


func test_protection_clears_for_the_workshop_and_respawn() -> void:
	var w := _three(4)
	w.fast_rounds = true
	w._damage_vehicle(w.vehicles[1], 1.0e6, 0)
	assert_gt(float(w.vehicles[0].protect_ticks), 0.0)
	w._begin_workshop()
	assert_eq(w.vehicles[0].protect_ticks, 0)


func test_leader_and_protection_snapshot_and_determinism() -> void:
	var host := _three(4)
	host.vehicles[2].kills = 30
	host.step()
	host._damage_vehicle(host.vehicles[0], 1.0e6, 1)  # vehicle 1 kills vehicle 0
	host.step()
	assert_eq(host.leader_peer, 3)
	assert_gt(float(host.vehicles[1].protect_ticks), 0.0)
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	assert_eq(client.leader_peer, 3)
	assert_eq(client.vehicles[1].protect_ticks, host.vehicles[1].protect_ticks)
	# The checksum covers both fields.
	var c0: int = host.checksum()
	host.leader_peer = 1
	assert_ne(host.checksum(), c0)
	host.leader_peer = 3
	assert_eq(host.checksum(), c0)
	host.vehicles[1].protect_ticks += 1
	assert_ne(host.checksum(), c0)
	# Same seed and inputs give the same world through the grace period and into PvP.
	var a := _duel(3)
	var b := _duel(3)
	for i in 400:
		a.step()
		b.step()
		if i == 200:
			a.round = 4
			b.round = 4
	assert_eq(a.checksum(), b.checksum())


func test_return_fire_only_after_a_deliberate_attack() -> void:
	var w := _three(SimWorld.PVP_START_ROUND)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.pos = Vector2(300, 360)
	b.pos = Vector2(420, 360)
	w.vehicles[2].pos = Vector2(1200, 650)
	# A stray shot (the shooter targets something else) is not remembered.
	w._damage_vehicle(b, 1.0, a.id)
	assert_eq(b.retaliate_ticks, 0, "stray hit")
	# A deliberate attack is, and b (doctrine "nearest", with a gun) shoots back at a.
	a.target_kind = 2
	a.target_id = b.id
	w._damage_vehicle(b, 1.0, a.id)
	assert_eq(b.retaliate_id, a.id)
	assert_eq(b.retaliate_ticks, SimWorld.RETALIATE_TICKS)
	Cards.recompute(b, true, false)  # _three() strips the guns: b gets its mg back
	b.speed = 0.0
	w.step()
	assert_eq(b.target_kind, 2, "returns fire")
	assert_eq(b.target_id, a.id)
	# The memory runs out.
	b.retaliate_ticks = 0
	a.target_kind = 0
	for i in 12:
		w.step()
	assert_ne(b.target_kind, 2)


func test_no_return_fire_in_grace_rounds() -> void:
	var w := _three(2)
	var a: SimVehicle = w.vehicles[0]
	a.target_kind = 2
	a.target_id = 1
	w._damage_vehicle(w.vehicles[1], 1.0, 0)
	assert_eq(w.vehicles[1].target_kind, 0)
