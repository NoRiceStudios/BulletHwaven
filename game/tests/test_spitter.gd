extends TestCase
## Spitters: ranged aliens that hold their distance and lob slow acid (owner -1) at vehicles.


## One vehicle that does not move or shoot and cannot die, plus a spitter 400 px away.
func _duel(armor: float = 0.0) -> SimWorld:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	var v := w.add_vehicle(1, Vector2(300, 360))
	v.weapons.clear()
	v.speed = 0.0
	v.armor = armor
	v.max_hp = 1.0e6
	v.hp = v.max_hp
	w.spawn_enemy(SimWorld.SPITTER, Vector2(700, 360))
	return w


func test_spitter_chance_by_round() -> void:
	assert_eq(SimWorld.spitter_chance(1), 0.0)
	assert_eq(SimWorld.spitter_chance(2), 0.0)
	assert_eq(SimWorld.spitter_chance(SimWorld.SPITTER_MIN_ROUND), SimWorld.SPITTER_CHANCE_START)
	assert_gt(SimWorld.spitter_chance(6), SimWorld.spitter_chance(3), "grows")
	assert_eq(SimWorld.spitter_chance(99), SimWorld.SPITTER_CHANCE_MAX, "capped")


func _spitters(w: SimWorld) -> int:
	var n: int = 0
	for i in w.enemy_count:
		if w.enemy_kind[i] == SimWorld.SPITTER:
			n += 1
	return n


func test_spitters_spawn_from_round_three() -> void:
	# No vehicles: nothing kills or distracts the spawns.
	var early := SimWorld.new(21)
	for i in 1100:  # all of round 1
		early.step()
	assert_gt(early.enemy_count, 20, "enemies spawned")
	assert_eq(_spitters(early), 0, "no spitters in round 1")
	early.round = 2
	early.phase_ticks_left = 1200
	for i in 600:
		early.step()
	assert_eq(_spitters(early), 0, "no spitters in round 2")

	var late := SimWorld.new(21)
	late.round = 3
	late.phase_ticks_left = 1800
	for i in 1200:
		late.step()
	assert_gt(_spitters(late), 1, "spitters appear in round 3 (%d of %d)" % [_spitters(late), late.enemy_count])
	assert_true(_spitters(late) <= SimWorld.spitter_cap(3), "but never more than the alive cap")
	assert_lt(_spitters(late), late.enemy_count / 2, "but stay a minority")


func test_spitter_keeps_distance_and_spits() -> void:
	var w := _duel()
	var v: SimVehicle = w.vehicles[0]
	var spits: int = 0
	var min_d: float = INF
	var hit_events: int = 0
	for i in 300:
		w.step()
		for e in w.events:
			if e["type"] == "spit":
				spits += 1
				assert_eq(e["owner"], -1, "alien owner")
				assert_eq(e["kind"], SimWorld.SPITTER)
			elif e["type"] == "hit" and e["owner"] == -1:
				hit_events += 1
				assert_eq(e["kind"], -1, "acid hits vehicles")
		if i > 150:
			min_d = minf(min_d, w.enemy_pos[0].distance_to(v.pos))
	var d: float = w.enemy_pos[0].distance_to(v.pos)
	assert_gt(min_d, SimWorld.SPITTER_KEEP_MIN - 20.0, "never closes in (min %f)" % min_d)
	assert_lt(d, SimWorld.SPITTER_KEEP_MAX + 20.0, "approached to firing distance (%f)" % d)
	assert_gt(spits, 2, "spit events emitted (%d)" % spits)
	assert_gt(hit_events, 0, "acid landed on the vehicle")
	assert_lt(v.hp, v.max_hp, "vehicle took acid damage")
	var lost: float = v.max_hp - v.hp
	assert_lt(lost, 10.0 * float(spits) * SimWorld.SPIT_DAMAGE, "damage is per hit, not per tick")


func test_spitter_backs_off_when_approached() -> void:
	var w := _duel()
	w.enemy_pos[0] = Vector2(300 + 90, 360)  # far too close
	for i in 120:
		w.step()
	assert_gt(w.enemy_pos[0].distance_to(w.vehicles[0].pos), SimWorld.SPITTER_KEEP_MIN - 15.0, "backed away")


func test_acid_only_hurts_vehicles_and_armor_applies() -> void:
	var w := _duel()
	# An alien in the line of fire is untouched by acid.
	w.spawn_enemy(SimWorld.BOULDER, Vector2(500, 360))
	w.enemy_hp[1] = 1000.0
	for i in 200:
		w.step()
	assert_eq(w.enemy_hp[1], 1000.0, "acid passes aliens by")

	var plain := _duel(0.0)
	var armored := _duel(100.0)  # maxes out the 75% reduction
	for i in 400:
		plain.step()
		armored.step()
	var lost_plain: float = plain.vehicles[0].max_hp - plain.vehicles[0].hp
	var lost_armored: float = armored.vehicles[0].max_hp - armored.vehicles[0].hp
	assert_gt(lost_plain, 0.0)
	assert_lt(lost_armored, lost_plain * 0.5, "armour reduces acid damage")


func test_acid_can_destroy_a_vehicle() -> void:
	var w := _duel()
	var v: SimVehicle = w.vehicles[0]
	v.max_hp = 20.0
	v.hp = 20.0
	var destroyed: bool = false
	for i in 400:
		w.step()
		for e in w.events:
			if e["type"] == "vehicle_destroyed":
				destroyed = true
	assert_true(destroyed or not v.alive or v.fuel < SimWorld.START_FUEL, "three acid hits kill a 20 hp rig")
	assert_lt(v.fuel, SimWorld.START_FUEL, "alien kill costs fuel")


func test_spitter_determinism_and_snapshot() -> void:
	var a := SimWorld.new(77)
	var b := SimWorld.new(77)
	for w: SimWorld in [a, b]:
		w.round = 4
		w.add_vehicle(1, Vector2(400, 360))
		w.add_vehicle(2, Vector2(880, 360))
	var spits: int = 0
	var carried: bool = false
	var client := SimWorld.new(0)
	for i in 900:
		a.step()
		b.step()
		for e in a.events:
			if e["type"] == "spit":
				spits += 1
		if not a.events.is_empty() and a.events.any(func(e: Dictionary) -> bool: return e["type"] == "spit"):
			assert_true(Snapshot.apply(client, Snapshot.encode(a)))
			carried = carried or client.events.any(func(e: Dictionary) -> bool: return e["type"] == "spit")
	assert_gt(spits, 0, "spits happened")
	assert_true(carried, "spit events survive the snapshot")
	assert_eq(a.checksum(), b.checksum(), "deterministic with spitters")
