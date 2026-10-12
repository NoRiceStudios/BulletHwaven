extends TestCase


func _make_world(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, Vector2(400, 360))
	w.add_vehicle(2, Vector2(880, 360))
	w.apply_command(2, {"type": "set_drive", "value": "kite"})
	w.apply_command(2, {"type": "set_target", "value": "strongest"})
	return w


func _run(w: SimWorld, ticks: int) -> void:
	for i in ticks:
		w.step()
		if i == 300:
			w.apply_command(1, {"type": "set_drive", "value": "charge"})


func _arrays_consistent(w: SimWorld) -> bool:
	var n: int = w.enemy_count
	var m: int = w.proj_count
	return (
		w.enemy_id.size() == n and w.enemy_kind.size() == n and w.enemy_pos.size() == n
		and w.enemy_vel.size() == n and w.enemy_hp.size() == n
		and w.proj_pos.size() == m and w.proj_vel.size() == m and w.proj_ttl.size() == m
		and w.proj_damage.size() == m and w.proj_owner.size() == m
	)


func test_determinism() -> void:
	var a := _make_world(1234)
	var b := _make_world(1234)
	var c := _make_world(4321)
	assert_eq(a.checksum(), b.checksum(), "initial checksums")
	_run(a, 900)
	_run(b, 900)
	_run(c, 900)
	assert_eq(a.tick, 900)
	assert_eq(a.checksum(), b.checksum(), "same seed after 900 ticks")
	assert_ne(a.checksum(), c.checksum(), "different seed")
	assert_gt(a.next_enemy_id, 0, "enemies were spawned")


func test_enemies_spawn_and_die() -> void:
	var w := SimWorld.new(7)
	var v := w.add_vehicle(1, Vector2(640, 360))
	var max_seen: int = 0
	var saw_kill_event := false
	var saw_fire_event := false
	var saw_hit_event := false
	for i in 600:
		w.step()
		max_seen = maxi(max_seen, w.enemy_count)
		for e in w.events:
			match e["type"]:
				"kill":
					saw_kill_event = true
				"fire":
					saw_fire_event = true
				"hit":
					saw_hit_event = true
	assert_gt(w.next_enemy_id, 20, "enemies spawned over time")
	assert_gt(max_seen, 0)
	assert_gt(v.kills, 0, "vehicle got kills")
	assert_gt(v.scrap, 0, "vehicle got scrap")
	assert_true(saw_kill_event and saw_fire_event and saw_hit_event, "fire/hit/kill events emitted")
	assert_true(v.alive, "vehicle survives the first 20 s")
	assert_true(SimWorld.ARENA.has_point(v.pos), "vehicle inside arena")


func test_spawn_rate_ramps() -> void:
	var w := SimWorld.new(3)  # no vehicles: nothing kills the enemies
	var first_10s: int = 0
	for i in 600:
		w.step()
		if i == 299:
			first_10s = w.enemy_count
	var second_10s: int = w.enemy_count - first_10s
	assert_gt(second_10s, first_10s, "rate ramps over time")
	for i in w.enemy_count:
		assert_true(SimWorld.ARENA.has_point(w.enemy_pos[i]), "enemy inside arena")


func test_pvp_damage() -> void:
	var w := SimWorld.new(99)
	w.spawning_enabled = false
	w.round = SimWorld.PVP_START_ROUND  # no PvP before this round (see test_pvp.gd)
	var a := w.add_vehicle(1, Vector2(600, 360))
	var b := w.add_vehicle(2, Vector2(690, 360))
	for p in [1, 2]:
		w.apply_command(p, {"type": "set_target", "value": "players_first"})
	var destroyed := false
	for i in 300:
		w.step()
		for e in w.events:
			if e["type"] == "vehicle_destroyed":
				destroyed = true
	assert_lt(a.hp, a.max_hp, "A took damage")
	assert_lt(b.hp, b.max_hp, "B took damage")
	assert_true(a.hp >= 0.0 and b.hp >= 0.0)
	# Keep going: someone eventually dies, the survivor gets the kill.
	for i in 1500:
		if destroyed:
			break
		w.step()
		for e in w.events:
			if e["type"] == "vehicle_destroyed":
				destroyed = true
	assert_true(destroyed, "a vehicle was destroyed")
	assert_true(a.alive != b.alive, "exactly one survivor")
	var winner: SimVehicle = a if a.alive else b
	assert_eq(winner.kills, 1)


func test_commands() -> void:
	var w := SimWorld.new(5)
	var v := w.add_vehicle(42, Vector2(100, 100))
	assert_eq(v.doctrine["drive"], "circle")
	assert_eq(v.doctrine["target"], "nearest")
	w.apply_command(42, {"type": "set_drive", "value": "kite"})
	w.apply_command(42, {"type": "set_target", "value": "players_first"})
	assert_eq(v.doctrine["drive"], "kite")
	assert_eq(v.doctrine["target"], "players_first")
	w.apply_command(42, {"type": "set_drive", "value": "bogus"})
	w.apply_command(42, {"type": "nope", "value": "charge"})
	w.apply_command(99, {"type": "set_drive", "value": "charge"})  # unknown peer
	assert_eq(v.doctrine["drive"], "kite")
	assert_eq(w.get_vehicle_for_peer(42), v)
	assert_eq(w.get_vehicle_for_peer(99), null)


func test_drive_doctrines() -> void:
	# Each doctrine keeps the vehicle in the arena and moving; "charge" closes in on a target.
	for drive in ["circle", "kite", "charge"]:
		var w := SimWorld.new(11)
		w.spawning_enabled = false
		var v := w.add_vehicle(1, Vector2(640, 360))
		w.apply_command(1, {"type": "set_drive", "value": drive})
		w.spawn_enemy(SimWorld.BOULDER, Vector2(1000, 360))
		w.enemy_hp[0] = 1.0e9  # immortal anchor
		w.rebuild_derived()
		var min_d: float = INF
		var max_d: float = 0.0
		for i in 600:
			w.step()
			assert_true(SimWorld.ARENA.has_point(v.pos), "%s stays in arena" % drive)
			var d: float = v.pos.distance_to(w.enemy_pos[0])
			if i > 150:
				min_d = minf(min_d, d)
				max_d = maxf(max_d, d)
		if drive == "charge":
			assert_lt(min_d, 40.0, "charge reaches the target")
		else:
			assert_gt(min_d, 60.0, "%s keeps its distance" % drive)
			assert_lt(max_d, 400.0, "%s stays engaged" % drive)


func test_arrays_stay_dense() -> void:
	var w := _make_world(2024)
	for i in 1800:
		w.step()
		assert_true(_arrays_consistent(w), "arrays consistent at tick %d" % i)
		assert_eq(w.enemy_id.size(), w.enemy_count)
		if not _arrays_consistent(w):
			return
	# Ids are unique.
	var seen := {}
	for i in w.enemy_count:
		assert_false(seen.has(w.enemy_id[i]), "unique enemy id")
		seen[w.enemy_id[i]] = true
	for i in w.proj_count:
		assert_gt(w.proj_ttl[i], 0.0)


func test_spatial_hash_matches_brute_force() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pos := PackedVector2Array()
	for i in 700:
		pos.append(Vector2(rng.randf_range(-20, 1300), rng.randf_range(-20, 740)))
	var h := SpatialHash.new(SimWorld.ARENA, 32.0)
	h.rebuild(pos, pos.size())
	var out := PackedInt32Array()
	for k in 40:
		var c := Vector2(rng.randf_range(0, 1280), rng.randf_range(0, 720))
		var r: float = rng.randf_range(5, 200)
		var n: int = h.query_circle(c, r, pos, out)
		var got: Array[int] = []
		for q in n:
			got.append(out[q])
		got.sort()
		var want: Array[int] = []
		for i in pos.size():
			if c.distance_squared_to(pos[i]) <= r * r:
				want.append(i)
		# Points outside the grid are clamped into edge cells; only in-grid points are guaranteed.
		var inside_only := got.filter(func(i: int) -> bool: return SimWorld.ARENA.has_point(pos[i]))
		var want_inside := want.filter(func(i: int) -> bool: return SimWorld.ARENA.has_point(pos[i]))
		assert_eq(inside_only, want_inside, "query %d" % k)


func test_perf_smoke() -> void:
	var w := SimWorld.new(77)
	w.spawning_enabled = false
	w.add_vehicle(1, Vector2(400, 360))
	w.add_vehicle(2, Vector2(880, 360))
	w.apply_command(1, {"type": "set_target", "value": "strongest"})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var total_us: int = 0
	var steps: int = 60
	for s in steps:
		# Top up to the worst-case population before each timed step.
		while w.enemy_count < 1500:
			var k: int = SimWorld.BOULDER if rng.randf() < 0.1 else SimWorld.MITE
			w.spawn_enemy(k, Vector2(rng.randf_range(10, 1270), rng.randf_range(10, 710)))
		while w.proj_count < 500:
			var ang: float = rng.randf() * TAU
			w.spawn_projectile(Vector2(rng.randf_range(10, 1270), rng.randf_range(10, 710)), Vector2.from_angle(ang) * 400.0, 2.0, 0.5, 0)
		if s == 0:
			w.rebuild_derived()
		var t0: int = Time.get_ticks_usec()
		w.step()
		total_us += Time.get_ticks_usec() - t0
		# rebuild above only matters for the first step; later steps maintain the hash.
	var ms: float = float(total_us) / 1000.0 / float(steps)
	print("      perf: %.2f ms/step (1500 enemies, 500 projectiles, 2 vehicles)" % ms)
	assert_lt(ms, 25.0, "average step time")
