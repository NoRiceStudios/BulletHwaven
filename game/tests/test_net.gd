extends TestCase


func _make_world(p_seed: int, extra_enemies: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, Vector2(400, 360))
	w.add_vehicle(2, Vector2(880, 360))
	w.add_vehicle(3, Vector2(640, 120))
	w.apply_command(2, {"type": "set_drive", "value": "kite"})
	w.apply_command(2, {"type": "set_target", "value": "strongest"})
	w.apply_command(3, {"type": "set_drive", "value": "charge"})
	var r := RandomNumberGenerator.new()
	r.seed = p_seed + 1
	for i in extra_enemies:
		var kind: int = SimWorld.BOULDER if r.randf() < 0.05 else (SimWorld.SPITTER if r.randf() < 0.1 else SimWorld.MITE)
		w.spawn_enemy(kind, Vector2(r.randf_range(20.0, 1260.0), r.randf_range(20.0, 700.0)))
	return w


func _run_until_events(w: SimWorld, ticks: int) -> void:
	for i in ticks:
		w.step()
	var guard: int = 0
	while w.events.is_empty() and guard < 120:
		w.step()
		guard += 1


func _compare(host: SimWorld, client: SimWorld) -> void:
	assert_eq(client.tick, host.tick, "tick")
	assert_eq(client.next_enemy_id, host.next_enemy_id, "next_enemy_id")
	assert_eq(client.enemy_count, host.enemy_count, "enemy_count")
	assert_eq(client.proj_count, host.proj_count, "proj_count")
	assert_eq(client.enemy_id.size(), host.enemy_count, "enemy arrays sized")
	assert_eq(client.proj_pos.size(), host.proj_count, "proj arrays sized")
	assert_eq(client.vehicles.size(), host.vehicles.size(), "vehicle count")

	var tol: float = Snapshot.POS_ERROR + 0.001
	var worst_pos: float = 0.0
	var bad_kind: int = 0
	var bad_id: int = 0
	var bad_pos: int = 0
	var bad_vel: int = 0
	var bad_hp: int = 0
	for i in host.enemy_count:
		if client.enemy_id[i] != host.enemy_id[i]:
			bad_id += 1
		if client.enemy_kind[i] != host.enemy_kind[i]:
			bad_kind += 1
		var d: float = client.enemy_pos[i].distance_to(host.enemy_pos[i])
		worst_pos = maxf(worst_pos, d)
		if absf(client.enemy_pos[i].x - host.enemy_pos[i].x) > tol or absf(client.enemy_pos[i].y - host.enemy_pos[i].y) > tol:
			bad_pos += 1
		var kind: int = host.enemy_kind[i]
		var speed: float = SimWorld.ENEMY_SPEED[kind]
		# 1/7 speed steps (+ half step) and 128 headings (<= 1.4 deg at full speed).
		if client.enemy_vel[i].distance_to(host.enemy_vel[i]) > speed * (0.5 / 7.0 + 0.03) + 0.01:
			bad_vel += 1
		var max_hp: float = SimWorld.ENEMY_HP[kind]
		if client.enemy_hp[i] < host.enemy_hp[i] - 0.001 or client.enemy_hp[i] > host.enemy_hp[i] + max_hp / 15.0 + 0.001:
			bad_hp += 1
	assert_eq(bad_id, 0, "enemy ids equal")
	assert_eq(bad_kind, 0, "enemy kinds equal")
	assert_eq(bad_pos, 0, "enemy positions within quantization (worst %f)" % worst_pos)
	assert_eq(bad_vel, 0, "enemy velocity within quantization")
	assert_eq(bad_hp, 0, "enemy hp within quantization")

	var bad_proj: int = 0
	for i in host.proj_count:
		if client.proj_owner[i] != host.proj_owner[i] \
				or absf(client.proj_pos[i].x - host.proj_pos[i].x) > tol \
				or absf(client.proj_pos[i].y - host.proj_pos[i].y) > tol \
				or client.proj_vel[i].distance_to(host.proj_vel[i]) > 0.75 \
				or absf(client.proj_ttl[i] - host.proj_ttl[i]) > 0.0051 \
				or absf(client.proj_damage[i] - host.proj_damage[i]) > 0.126:
			bad_proj += 1
	assert_eq(bad_proj, 0, "projectiles within quantization")

	for i in host.vehicles.size():
		var a: SimVehicle = host.vehicles[i]
		var b: SimVehicle = client.vehicles[i]
		assert_eq(b.id, a.id, "vehicle id")
		assert_eq(b.peer_id, a.peer_id, "vehicle peer")
		assert_eq(b.alive, a.alive, "vehicle alive")
		assert_eq(b.scrap, a.scrap, "vehicle scrap")
		assert_eq(b.kills, a.kills, "vehicle kills")
		assert_eq(b.doctrine, a.doctrine, "vehicle doctrine")
		assert_lt(b.pos.distance_to(a.pos), 0.001, "vehicle pos")
		assert_lt(absf(b.hp - a.hp), 0.001, "vehicle hp")
		assert_lt(absf(b.max_hp - a.max_hp), 0.001, "vehicle max_hp")
		assert_lt(absf(b.heading - a.heading), 0.0001, "vehicle heading")
		assert_eq(b.weapons.size(), a.weapons.size(), "weapon count")
		for k in a.weapons.size():
			assert_eq(str(b.weapons[k]["kind"]), str(a.weapons[k]["kind"]), "weapon kind")
			assert_lt(absf(float(b.weapons[k]["aim"]) - float(a.weapons[k]["aim"])), 0.0001, "weapon aim")
			assert_eq(int(b.weapons[k]["cooldown"]), int(a.weapons[k]["cooldown"]), "weapon cooldown")
			assert_lt(absf(float(b.weapons[k]["range"]) - float(a.weapons[k]["range"])), 0.001, "weapon range")

	assert_eq(client.events.size(), host.events.size(), "event count")
	for i in mini(client.events.size(), host.events.size()):
		var ea: Dictionary = host.events[i]
		var eb: Dictionary = client.events[i]
		assert_eq(eb["type"], ea["type"], "event type")
		assert_eq(eb["owner"], ea["owner"], "event owner")
		assert_eq(eb["kind"], ea["kind"], "event kind")
		assert_lt(absf((eb["pos"] as Vector2).x - (ea["pos"] as Vector2).x), tol, "event pos x")
		assert_lt(absf((eb["pos"] as Vector2).y - (ea["pos"] as Vector2).y), tol, "event pos y")


func test_snapshot_roundtrip() -> void:
	var host := _make_world(99, 300)
	_run_until_events(host, 300)
	assert_gt(host.enemy_count, 10, "enemies exist")
	assert_gt(host.proj_count + host.events.size(), 0, "something is flying / happened")
	assert_gt(host.events.size(), 0, "events present")
	var bytes: PackedByteArray = Snapshot.encode(host)

	# Client world starts out with unrelated stale content.
	var client := SimWorld.new(0)
	client.spawning_enabled = false
	client.add_vehicle(9, Vector2(5, 5))
	client.spawn_enemy(SimWorld.MITE, Vector2(1, 1))
	var held: SimVehicle = client.vehicles[0]
	assert_true(Snapshot.apply(client, bytes), "apply succeeds")
	_compare(host, client)
	assert_eq(client.vehicles.size(), 3)
	assert_true(client.vehicles[0] == held, "vehicle objects updated in place when ids match")
	# The rebuilt spatial hash is usable on the client.
	var buf := PackedInt32Array()
	buf.resize(SimWorld.MAX_ENEMIES)
	var found: int = client.query_enemies(client.vehicles[0].pos, 100000.0, buf)
	assert_eq(found, client.enemy_count, "hash rebuilt (query over the whole arena finds all)")

	# Re-applying a later snapshot also works (and shrinks/grows arrays).
	for i in 60:
		host.step()
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	_compare(host, client)


func test_snapshot_carries_override_events() -> void:
	var host := _make_world(5, 20)
	for i in 5:
		host.step()
	var evs: Array[Dictionary] = [
		{"type": "kill", "pos": Vector2(100.5, 200.25), "owner": 1, "kind": 2},
		{"type": "vehicle_destroyed", "pos": Vector2(-10.0, 730.0), "owner": 2, "kind": -1},
		{"type": "hit", "pos": Vector2(1300.0, 10.0), "owner": 0, "kind": -1},
	]
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host, evs)))
	assert_eq(client.events.size(), 3)
	assert_eq(client.events[1]["type"], "vehicle_destroyed")
	assert_eq(client.events[1]["owner"], 2)
	assert_lt(((client.events[1]["pos"] as Vector2) - Vector2(-10.0, 730.0)).length(), 0.05, "event pos outside arena")
	assert_lt(((client.events[2]["pos"] as Vector2) - Vector2(1300.0, 10.0)).length(), 0.05)


func test_snapshot_wide_ids() -> void:
	var host := SimWorld.new(1)
	host.add_vehicle(1, Vector2(640, 360))
	host.spawn_enemy(SimWorld.BOULDER, Vector2(10, 10))
	host.next_enemy_id = 200000
	host.spawn_enemy(SimWorld.MITE, Vector2(20, 20))
	host.next_enemy_id = 4000000000
	host.spawn_enemy(SimWorld.SPITTER, Vector2(30, 30))
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	assert_eq(client.enemy_id, host.enemy_id, "wide ids survive")
	assert_eq(client.next_enemy_id, host.next_enemy_id)


func test_snapshot_size() -> void:
	var host := _make_world(7, 1000)
	for i in 30:
		host.step()
	var n: int = host.enemy_count
	assert_gt(n, 800, "~1000 enemies alive")
	var bytes: PackedByteArray = Snapshot.encode(host)
	# Fixed part = same snapshot with no enemies / projectiles / events.
	var empty := SimWorld.new(0)
	Snapshot.apply(empty, bytes)
	empty.enemy_id.clear()
	empty.enemy_kind.clear()
	empty.enemy_pos.clear()
	empty.enemy_vel.clear()
	empty.enemy_hp.clear()
	empty.proj_pos.clear()
	empty.proj_vel.clear()
	empty.proj_ttl.clear()
	empty.proj_damage.clear()
	empty.proj_owner.clear()
	empty.events = []
	empty.rebuild_derived()
	var fixed: int = Snapshot.encode(empty).size()
	var per_enemy: float = float(bytes.size() - fixed - host.proj_count * Snapshot.PROJ_BYTES
		- host.events.size() * Snapshot.EVENT_BYTES) / float(n)
	print("      net: %d enemies, %d projectiles, %d events, snapshot %d bytes (~%.1f bytes/enemy)" % [
		n, host.proj_count, host.events.size(), bytes.size(), per_enemy])
	assert_lt(float(bytes.size()) / float(n), 9.2, "about 9 bytes per enemy overall (fixed part included; it sat at 9.0 after the boss merge)")
	assert_lt(per_enemy, 8.5, "enemy payload close to 8 bytes")
	# 15 snapshots/s per client must stay modest.
	assert_lt(float(bytes.size()), 12000.0, "1000-enemy snapshot under 12 kB")


func test_snapshot_rejects_malformed() -> void:
	var host := _make_world(11, 50)
	for i in 40:
		host.step()
	var good: PackedByteArray = Snapshot.encode(host)
	var client := SimWorld.new(0)
	client.add_vehicle(1, Vector2(1, 2))
	var sum_before: int = client.checksum()
	assert_false(Snapshot.apply(client, PackedByteArray()), "empty")
	assert_false(Snapshot.apply(client, good.slice(0, 10)), "truncated header")
	assert_false(Snapshot.apply(client, good.slice(0, good.size() - 3)), "truncated body")
	var wrong_version: PackedByteArray = good.duplicate()
	wrong_version[0] = 200
	assert_false(Snapshot.apply(client, wrong_version), "wrong version")
	var junk := PackedByteArray()
	junk.resize(300)
	junk.fill(0xFF)
	assert_false(Snapshot.apply(client, junk), "junk")
	assert_eq(client.checksum(), sum_before, "world untouched by rejected snapshots")
	assert_true(Snapshot.apply(client, good), "good one still applies")


func test_command_validation_rejects_junk() -> void:
	var junk: Array = [
		null, 5, "set_drive", [], PackedByteArray(), {}, {"type": "set_drive"},
		{"value": "kite"}, {"type": "set_drive", "value": "warp"}, {"type": "set_drive", "value": 5},
		{"type": "set_drive", "value": ["kite"]}, {"type": 7, "value": "kite"},
		{"type": "set_drive", "value": "KITE"}, {"type": "set_drive", "value": "kite "},
		{"type": "set_target", "value": "kite"}, {"type": "set_drive", "value": "nearest"},
		{"type": "give_scrap", "value": "9999"}, {"type": "add_vehicle", "value": "circle"},
		{"type": "set_drive", "value": "x".repeat(10000)},
		{"type": "x".repeat(10000), "value": "kite"}, {"type": "", "value": ""},
	]
	for j: Variant in junk:
		assert_true(NetSession.validate_command(j).is_empty(), "rejected: %s" % str(j).left(40))

	var ok: Dictionary = NetSession.validate_command({"type": "set_drive", "value": "kite", "hp": 999999, "extra": [1]})
	assert_eq(ok, {"type": "set_drive", "value": "kite"}, "valid command is sanitised (extra keys dropped)")
	for d in ["circle", "kite", "charge"]:
		assert_false(NetSession.validate_command({"type": "set_drive", "value": d}).is_empty(), d)
	for t in ["nearest", "strongest", "players_first"]:
		assert_false(NetSession.validate_command({"type": "set_target", "value": t}).is_empty(), t)


func test_host_ignores_junk_and_applies_valid() -> void:
	var s := NetSession.new()
	s.start_solo()
	assert_true(s.is_host())
	assert_eq(s.local_peer_id(), 1)
	assert_eq(s.world.vehicles.size(), 1)
	s.world.add_vehicle(2, Vector2(100, 100))
	var v2: SimVehicle = s.world.get_vehicle_for_peer(2)
	s._handle_command(2, {"type": "set_drive", "value": "warp"})
	s._handle_command(2, {"type": "set_drive", "value": "kite", "hp": -1})
	s._handle_command(2, "garbage")
	s._handle_command(2, null)
	s._handle_command(2, {"type": "set_drive", "value": "kite"})
	assert_eq(v2.doctrine["drive"], "kite")
	assert_eq(s.world.get_vehicle_for_peer(1).doctrine["drive"], "circle", "other player unaffected")
	s.send_command({"type": "set_target", "value": "players_first"})
	assert_eq(s.world.get_vehicle_for_peer(1).doctrine["target"], "players_first", "solo send_command applies as peer 1")
	s.send_command({"type": "set_target", "value": "bogus"})
	assert_eq(s.world.get_vehicle_for_peer(1).doctrine["target"], "players_first", "invalid solo command ignored")
	s._physics_process(1.0 / 30.0)
	assert_eq(s.world.tick, 1, "solo steps the world")
	s.free()


func test_rate_limit() -> void:
	var s := NetSession.new()
	var accepted: int = 0
	for i in 100:
		if s._rate_ok(5, 1000 + i):
			accepted += 1
	assert_eq(accepted, NetSession.MAX_COMMANDS_PER_SEC, "burst limited")
	assert_true(s._rate_ok(5, 2100), "window resets after a second")
	assert_true(s._rate_ok(6, 1050), "per peer")
	s.free()


func test_spawn_positions_spread() -> void:
	var seen: Dictionary = {}
	for i in 8:
		var p: Vector2 = NetSession.spawn_position(i)
		assert_true(SimWorld.ARENA.grow(-30.0).has_point(p), "inside arena")
		seen[p.snapped(Vector2(1, 1))] = true
	assert_eq(seen.size(), 8, "distinct spawn slots")


func test_beacon_parsing() -> void:
	var good: PackedByteArray = JSON.stringify({"game": "BulletHwaven", "version": 1, "port": 24680, "players": 3, "name": "Jord"}).to_utf8_buffer()
	var info: Dictionary = LanDiscovery.parse_beacon(good)
	assert_eq(info.get("port"), 24680)
	assert_eq(info.get("players"), 3)
	for bad: String in ["", "nope", "[]", "{}", '{"game":"Other","version":1,"port":1}',
			'{"game":"BulletHwaven","version":2,"port":24680}', '{"game":"BulletHwaven","version":1,"port":0}',
			'{"game":"BulletHwaven","version":1,"port":"x"}', '{"game":"BulletHwaven","version":1,"port":70000}']:
		assert_true(LanDiscovery.parse_beacon(bad.to_utf8_buffer()).is_empty(), "rejected: " + bad)


func test_snapshot_carries_identity() -> void:
	var host := SimWorld.new(3)
	host.add_vehicle(1, Vector2(100, 100), "Ace", 5)
	host.add_vehicle(2, Vector2(200, 200), "Bob the Builder", 7)
	host.add_vehicle(3, Vector2(300, 300))
	assert_eq(host.vehicles[2].color_index, 2, "default colour = vehicle id")
	assert_eq(host.vehicles[2].player_name, "DRIVER")
	var client := SimWorld.new(0)
	var held: SimVehicle = client.add_vehicle(9, Vector2(5, 5))
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	assert_eq(client.vehicles.size(), 3)
	assert_true(client.vehicles[0] == held, "updated in place")
	for i in 3:
		assert_eq(client.vehicles[i].player_name, host.vehicles[i].player_name, "name %d" % i)
		assert_eq(client.vehicles[i].color_index, host.vehicles[i].color_index, "colour %d" % i)
	assert_eq(client.vehicles[1].player_name, "Bob the Builder")
	assert_eq(client.vehicles[1].color_index, 7)
	var twin := SimWorld.new(3)
	twin.add_vehicle(1, Vector2(100, 100), "Ace", 5)
	var base: int = twin.checksum()
	twin.vehicles[0].color_index = 6
	assert_ne(twin.checksum(), base, "colour is part of the checksum")
	twin.vehicles[0].color_index = 5
	assert_eq(twin.checksum(), base)
	twin.vehicles[0].player_name = "Zed"
	assert_ne(twin.checksum(), base, "name is part of the checksum")

	# A bad colour index or an unprintable name in a snapshot is rejected / cleaned.
	var solo := SimWorld.new(1)
	solo.add_vehicle(1, Vector2(1, 1), "ACE", 3)
	var bytes: PackedByteArray = Snapshot.encode(solo)
	var color_at: int = Snapshot.HEADER_BYTES + 1 + 4 + 1 + 3
	assert_eq(bytes[color_at], 3, "colour byte where expected")
	var bad: PackedByteArray = bytes.duplicate()
	bad[color_at] = 8
	var c2 := SimWorld.new(0)
	assert_false(Snapshot.apply(c2, bad), "colour index out of range")
	assert_eq(c2.vehicles.size(), 0, "world untouched")
	var ugly: PackedByteArray = bytes.duplicate()
	ugly[color_at - 2] = 7  # control character inside the name
	assert_true(Snapshot.apply(c2, ugly))
	assert_eq(c2.vehicles[0].player_name, "AE", "control char stripped on receipt")
