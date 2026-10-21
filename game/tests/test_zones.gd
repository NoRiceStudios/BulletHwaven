extends TestCase
## PvP control zones (sim/zones.gd): placement, grace lock, capture, contest, scoring, fuel bonus,
## doctrine conditions and actions, snapshot, determinism.

## A multiplayer world at the start of round 4 combat, PvP already on (no grace), two or more rigs.
func _world(rigs: int = 2, p_seed: int = 5) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	w.fast_rounds = true
	for i in rigs:
		var v: SimVehicle = w.add_vehicle(i + 1, Vector2(200.0 + 150.0 * i, 200.0))
		v.max_hp = 1.0e6
		v.hp = 1.0e6
		w.apply_command(i + 1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	w.round = SimWorld.PVP_START_ROUND - 1
	w.phase = SimWorld.PHASE_WORKSHOP
	w._begin_combat()
	w.phase_ticks_left = 100000
	return w


func _put(v: SimVehicle, p: Vector2) -> void:
	v.pos = p
	v.vel = Vector2.ZERO
	v.invuln_ticks = 0


func _zc(w: SimWorld, i: int = 0) -> Vector2:
	return w.zones[i]["pos"]


func test_no_zones_solo_or_before_round_four() -> void:
	var s := SimWorld.new(2)
	s.add_vehicle(1, Vector2(500, 500))
	s.round = 5
	s.phase = SimWorld.PHASE_WORKSHOP
	s._begin_combat()
	assert_eq(s.zones.size(), 0, "solo")
	var w := SimWorld.new(2)
	w.add_vehicle(1, Vector2(500, 500))
	w.add_vehicle(2, Vector2(800, 500))
	w.round = 2
	w.phase = SimWorld.PHASE_WORKSHOP
	w._begin_combat()
	assert_eq(w.round, 3)
	assert_eq(w.zones.size(), 0, "round 3")
	w.phase = SimWorld.PHASE_WORKSHOP
	w._begin_combat()
	assert_eq(w.round, 4)
	assert_eq(w.zones.size(), 1, "round 4, two rigs")


func test_zone_count_and_spacing() -> void:
	var c: Vector2 = SimWorld.ARENA.get_center()
	for rigs in [2, 3, 4, 6]:
		var w := _world(rigs, 11 + rigs)
		assert_eq(w.zones.size(), clampi(rigs - 1, 1, 3), "rigs %d" % rigs)
		for i in w.zones.size():
			var d: Vector2 = (_zc(w, i) - c) / Zones.ZONE_CENTRE_REACH
			assert_true(d.length() <= 1.001, "inside the reach ellipse")
			for j in range(i + 1, w.zones.size()):
				assert_true(_zc(w, i).distance_to(_zc(w, j)) >= Zones.ZONE_MIN_SPACING - 0.01, "spacing")


func test_locked_during_grace_then_opens() -> void:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	var a: SimVehicle = w.add_vehicle(1, Vector2(300, 300))
	w.add_vehicle(2, Vector2(2000, 1200))
	for v in w.vehicles:
		v.max_hp = 1.0e6
		v.hp = 1.0e6
	w.round = SimWorld.PVP_START_ROUND - 1
	w.phase = SimWorld.PHASE_WORKSHOP
	w._begin_combat()
	assert_gt(float(w.pvp_grace_ticks), 0.0)
	assert_eq(w.zones.size(), 1)
	_put(a, _zc(w))
	for i in Zones.CAPTURE_TICKS + 10:
		_put(a, _zc(w))
		w.step()
	assert_false(w.zones_active, "locked")
	assert_eq(int(w.zones[0]["owner"]), -1, "no capture during the grace")
	w.pvp_grace_ticks = 1
	w.step()
	assert_true(w.zones_active)
	assert_true(w.events.any(func(e: Dictionary) -> bool: return e["type"] == "zones_open" and e["kind"] == 1))


func test_capture_after_three_seconds_alone() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	_put(w.vehicles[1], Vector2(100, 100))
	var captured: bool = false
	var prev: int = 99
	for i in Zones.CAPTURE_TICKS + 2:
		_put(a, _zc(w))
		w.step()
		for e in w.events:
			if e["type"] == "zone_captured":
				captured = true
				prev = int(e["prev"])
				assert_eq(int(e["owner"]), a.id)
				assert_eq(int(e["kind"]), 0)
		if captured:
			break
	assert_true(captured)
	assert_eq(prev, -1)
	assert_eq(int(w.zones[0]["owner"]), a.id)
	assert_eq(Zones.held_by(w, a), 1)
	assert_eq(Zones.progress(w.zones[0]), 0.0)


func test_progress_and_decay() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	_put(w.vehicles[1], Vector2(100, 100))
	for i in 30:
		_put(a, _zc(w))
		w.step()
	assert_eq(int(w.zones[0]["cap_id"]), a.id)
	assert_eq(int(w.zones[0]["cap_ticks"]), 30)
	assert_true(absf(Zones.progress(w.zones[0]) - 30.0 / 90.0) < 0.001)
	_put(a, Vector2(100, 150))
	for i in 10:
		w.step()
	assert_eq(int(w.zones[0]["cap_ticks"]), 20)
	for i in 25:
		w.step()
	assert_eq(int(w.zones[0]["cap_ticks"]), 0)
	assert_eq(int(w.zones[0]["cap_id"]), -1)


func test_contested_freezes() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	for i in 20:
		_put(a, _zc(w))
		_put(b, Vector2(100, 100))
		w.step()
	assert_eq(int(w.zones[0]["cap_ticks"]), 20)
	for i in 40:
		_put(a, _zc(w))
		_put(b, _zc(w) + Vector2(30, 0))
		w.step()
	assert_true(w.zones[0]["contested"])
	assert_eq(int(w.zones[0]["cap_ticks"]), 20, "frozen")
	assert_true(Zones.contested_for(w, a))
	assert_true(Zones.intruder_in(w, a, 0))
	assert_eq(int(w.zones[0]["owner"]), -1)


func _own(w: SimWorld, v: SimVehicle) -> void:
	w.zones[0]["owner"] = v.id


func test_owner_scores_only_inside() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	_put(w.vehicles[1], Vector2(100, 100))
	_own(w, a)
	var scrap0: int = a.scrap
	for i in 90:
		_put(a, _zc(w))
		w.step()
	assert_eq(a.scrap - scrap0, 3)
	assert_eq(int(a.round_stats["zone_points"]), 3)
	assert_eq(int(a.match_stats["zone_points"]), 3)
	assert_eq(int(a.round_stats["scrap_earned"]), 3)
	_put(a, Vector2(100, 150))
	for i in 90:
		w.step()
	assert_eq(a.scrap - scrap0, 3, "no points away from the zone")
	assert_eq(int(w.zones[0]["owner"]), a.id, "keeps the flag")


func test_rival_recaptures() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	_own(w, a)
	_put(a, Vector2(100, 100))
	var ev: Dictionary = {}
	for i in Zones.CAPTURE_TICKS + 1:
		_put(b, _zc(w))
		w.step()
		for e in w.events:
			if e["type"] == "zone_captured":
				ev = e
	assert_eq(int(w.zones[0]["owner"]), b.id)
	assert_eq(int(ev.get("prev", -9)), a.id)
	assert_eq(Zones.held_by(w, a), 0)


func test_fuel_bonus_at_round_end() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.fuel = 50
	b.fuel = 50
	a.round_stats["zone_points"] = 12
	b.round_stats["zone_points"] = 4
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(a.fuel, 50 + Zones.ZONE_FUEL_BONUS)
	assert_eq(b.fuel, 50)
	assert_true(w.events.any(func(e: Dictionary) -> bool: return e["type"] == "zone_bonus" and int(e["owner"]) == a.id and int(e["kind"]) == Zones.ZONE_FUEL_BONUS))
	assert_eq(w.zones.size(), 0, "cleared")
	assert_false(w.zones_active)


func test_fuel_bonus_tie_and_minimum() -> void:
	var w := _world()
	w.vehicles[0].fuel = 50
	w.vehicles[1].fuel = 50
	w.vehicles[0].round_stats["zone_points"] = 15
	w.vehicles[1].round_stats["zone_points"] = 15
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.vehicles[0].fuel, 50, "tie = nobody")
	assert_eq(w.vehicles[1].fuel, 50)
	var w2 := _world()
	w2.vehicles[0].fuel = 50
	w2.vehicles[0].round_stats["zone_points"] = Zones.ZONE_FUEL_MIN_POINTS - 1
	w2.phase_ticks_left = 1
	w2.step()
	assert_eq(w2.vehicles[0].fuel, 50, "below the minimum")


func test_doctrine_conditions() -> void:
	for id in ["in_zone", "zone_dist", "zone_contested", "zones_held"]:
		assert_true(Doctrine.COND_IDS.has(id))
		assert_true(Doctrine.CONDS.has(id))
	assert_true(Doctrine.parse("in_zone=1&zone_dist<300&zones_held>0|drive:zone", "rig") != null)
	assert_true(Doctrine.parse("zone_contested=1|target:intruders", "rig") != null)
	assert_true(Doctrine.parse("in_zone=1|target:intruders", "mg") != null)
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	_put(w.vehicles[1], Vector2(100, 100))
	_put(a, _zc(w) + Vector2(250, 0))
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "in_zone=1|drive:charge;zone_dist<300&zones_held<1|drive:kite"})
	w.step()
	assert_eq(a.eff_drive, "kite", "near a zone, none held")
	_put(a, _zc(w))
	w.step()
	assert_eq(a.eff_drive, "charge", "inside")
	assert_eq(Doctrine._value(w, a, "in_zone", 0, -1, -1, Vector2.ZERO, {}), 1.0)
	_own(w, a)
	assert_eq(Doctrine._value(w, a, "zones_held", 0, -1, -1, Vector2.ZERO, {}), 1.0)
	assert_true(is_nan(Doctrine._value(w, a, "zone_dist", 0, -1, -1, Vector2.ZERO, {})), "no unheld zone left")
	var w2 := SimWorld.new(1)
	var s: SimVehicle = w2.add_vehicle(1, Vector2(500, 500))
	assert_eq(Doctrine._value(w2, s, "in_zone", 0, -1, -1, Vector2.ZERO, {}), 0.0, "no zones")
	assert_eq(Doctrine._value(w2, s, "zones_held", 0, -1, -1, Vector2.ZERO, {}), 0.0)


func test_drive_zone_enters_and_holds() -> void:
	var w := _world()
	var a: SimVehicle = w.vehicles[0]
	_put(w.vehicles[1], Vector2(100, 100))
	_put(a, _zc(w) + Vector2(450, 120))
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": ""})
	w.apply_command(1, {"type": "set_drive", "value": "zone"})
	assert_eq(a.doctrine["drive"], "zone")
	var steps: int = 0
	while Zones.zone_at(w, a.pos) < 0 and steps < 900:
		w.vehicles[1].pos = Vector2(100, 100)
		w.step()
		steps += 1
	assert_lt(float(steps), 900.0, "reached the zone")
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": ""})
	for i in 300:
		w.vehicles[1].pos = Vector2(100, 100)
		w.step()
		assert_true(a.pos.distance_to(_zc(w)) < Zones.ZONE_RADIUS, "stays in the zone")
	assert_eq(int(w.zones[0]["owner"]), a.id, "captured it")
	assert_true(Doctrine.parse("pvp=1|drive:zone", "rig") != null)


func test_drive_zone_without_zones_is_circle() -> void:
	var w := SimWorld.new(3)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(900, 700))
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	w.apply_command(1, {"type": "set_drive", "value": "zone"})
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(200, 0))
	w.rebuild_derived()
	for i in 30:
		w.step()
	assert_gt(v.vel.length(), 1.0, "moves like circle")


func test_target_intruders() -> void:
	var w := _world(3)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	var c: SimVehicle = w.vehicles[2]
	assert_true(Doctrine.RIG_TARGETS.has("intruders"))
	assert_true(Doctrine.WEAPON_TARGETS.has("intruders"))
	_put(a, _zc(w))
	_put(b, _zc(w) + Vector2(150, 0))  # inside the margin, outside the zone
	_put(c, _zc(w) + Vector2(60, 0))  # inside the zone, nearer
	var t: Vector3i = VehicleAI.find_target(w, a, "intruders", 0.0)
	assert_eq(t.x, 2)
	assert_eq(t.z, c.id)
	_put(c, _zc(w) + Vector2(900, 0))
	t = VehicleAI.find_target(w, a, "intruders", 0.0)
	assert_eq(t.z, b.id, "within 60 px of the zone")
	_put(b, _zc(w) + Vector2(900, 0))
	w.spawn_enemy(SimWorld.MITE, a.pos + Vector2(200, 0))
	w.rebuild_derived()
	t = VehicleAI.find_target(w, a, "intruders", 0.0)
	assert_eq(t.x, 1, "falls back to the nearest alien")


func test_snapshot_round_trip() -> void:
	var w := _world(3)
	w.vehicles[0].zone_ticks = 77
	w.zones[0]["owner"] = 1
	w.zones[0]["cap_id"] = 2
	w.zones[0]["cap_ticks"] = 40
	w.zones[1]["contested"] = true
	w.zones_active = true
	w.events.clear()
	w._emit("zone_captured", _zc(w), 1, 0, {"prev": 2, "count": 1})
	w._emit("zones_open", Vector2(1280, 720), -1, 2)
	w._emit("zone_bonus", Vector2(10, 10), 0, 5)
	var bytes: PackedByteArray = Snapshot.encode(w)
	var w2 := SimWorld.new(1)
	assert_true(Snapshot.apply(w2, bytes))
	assert_eq(w2.zones.size(), w.zones.size())
	assert_true(w2.zones_active)
	for i in w.zones.size():
		assert_true((w2.zones[i]["pos"] as Vector2).distance_to(_zc(w, i)) < 0.1)
		for k in ["owner", "cap_id", "cap_ticks"]:
			assert_eq(int(w2.zones[i][k]), int(w.zones[i][k]), k)
		assert_eq(w2.zones[i]["contested"], w.zones[i]["contested"])
	assert_eq(w2.vehicles[0].zone_ticks, 77)
	var types: Array = []
	for e in w2.events:
		types.append(e["type"])
		if e["type"] == "zone_captured":
			assert_eq(int(e["prev"]), 2)
			assert_eq(int(e["count"]), 1)
	assert_eq(types, ["zone_captured", "zones_open", "zone_bonus"])
	# a malformed zone block is rejected
	var bad: PackedByteArray = bytes.duplicate()
	var at: int = Snapshot.HEADER_BYTES - 2  # no ground zones here: the last two header bytes are control zone active / count
	assert_eq(bad[at], 1)
	bad[at + 1] = 9
	assert_false(Snapshot.apply(SimWorld.new(1), bad))
	assert_eq(Snapshot.VERSION, 18)
	assert_true(Snapshot.EVENT_TYPES.has("zone_bonus"))


func test_snapshot_stats() -> void:
	var w := _world()
	w.phase = SimWorld.PHASE_WORKSHOP
	w.vehicles[0].round_stats["zone_points"] = 7
	w.vehicles[0].match_stats["zone_points"] = 19
	var w2 := SimWorld.new(1)
	assert_true(Snapshot.apply(w2, Snapshot.encode(w)))
	assert_eq(int(w2.vehicles[0].round_stats["zone_points"]), 7)
	assert_eq(int(w2.vehicles[0].match_stats["zone_points"]), 19)


func test_net_allow_list() -> void:
	assert_true(NetSession.COMMANDS["set_drive"].has("zone"))
	assert_true(NetSession.COMMANDS["set_target"].has("intruders"))


func test_determinism_and_checksum() -> void:
	var sums: Array[int] = []
	var zpos: Array[Vector2] = []
	for run in 2:
		var w := _world(3, 31)
		w.apply_command(1, {"type": "set_drive", "value": "zone"})
		w.apply_command(2, {"type": "set_rules", "scope": "rig", "value": "pvp=1|drive:zone"})
		for i in 400:
			w.step()
		sums.append(w.checksum())
		zpos.append(_zc(w))
	assert_eq(sums[0], sums[1])
	assert_eq(zpos[0], zpos[1])
	var w3 := _world()
	var c1: int = w3.checksum()
	w3.zones[0]["cap_ticks"] = 5
	assert_ne(c1, w3.checksum(), "zones are in the checksum")
	w3.zones[0]["cap_ticks"] = 0
	w3.vehicles[0].zone_ticks = 3
	assert_ne(c1, w3.checksum(), "zone_ticks is in the checksum")


func test_bot_rules() -> void:
	var w := _world()
	w.apply_command(2, {"type": "set_rules", "scope": "rig", "value": ""})
	var bot := BotPolicy.create("pvp_hunter", 1)
	var cmds: Array[Dictionary] = bot.doctrine_commands(w, w.vehicles[1])
	var texts: Array = []
	for c in cmds:
		if c["type"] == "set_rules" and c["scope"] == "rig":
			texts.append(c["value"])
	assert_eq(texts.size(), 1)
	assert_true(String(texts[0]).contains("drive:zone") and String(texts[0]).contains("target:intruders"))
	assert_true(Doctrine.parse(texts[0], "rig") != null)
