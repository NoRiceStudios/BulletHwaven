extends TestCase
## The hive-signature species: Glass Wings (flyers), Brood Carriers (burst into mites), Shriekers (buff pulse),
## and the per-match signature that decides which two of them come, and from which round.


## One rig that neither moves nor shoots and cannot die; no spawning.
func _arena(armor: float = 0.0) -> SimWorld:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	var v := w.add_vehicle(1, Vector2(600, 600))
	v.weapons.clear()
	v.speed = 0.0
	v.armor = armor
	v.max_hp = 1.0e7
	v.hp = v.max_hp
	return w


func _count(w: SimWorld, kind: int) -> int:
	var n: int = 0
	for i in w.enemy_count:
		if w.enemy_kind[i] == kind and w.enemy_hp[i] > 0.0:
			n += 1
	return n


func _events(w: SimWorld, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in w.events:
		if e["type"] == type:
			out.append(e)
	return out


# ---------------------------------------------------------------- hive signature

func test_signature_is_deterministic_and_has_two_species() -> void:
	var seen_skipped := {}
	var firsts := {}
	for seed in range(1, 120):
		var a: PackedInt32Array = Species.signature(seed)
		assert_eq(a, Species.signature(seed), "same seed, same signature")
		var active: int = 0
		for i in 3:
			if a[i] > 0:
				active += 1
				assert_true(a[i] >= Species.FIRST_MIN and a[i] <= Species.FIRST_MAX, "first round %d in 3..7" % a[i])
				firsts[a[i]] = true
			else:
				seen_skipped[i] = true
		assert_eq(active, 2, "exactly two of three species, seed %d" % seed)
	assert_eq(seen_skipped.size(), 3, "every species gets left out for some seed")
	assert_gt(float(firsts.size()), 3.0, "the first rounds vary")
	var w1 := SimWorld.new(77)
	var w2 := SimWorld.new(77)
	assert_eq(w1.hive_first, w2.hive_first)
	assert_eq(w1.hive_first, Species.signature(77))
	assert_eq(Species.list(w1).size(), 2)


func test_signature_does_not_touch_the_world_rng() -> void:
	var w := SimWorld.new(31)
	var ref := RandomNumberGenerator.new()
	ref.seed = 31
	assert_eq(w.rng.randi(), ref.randi(), "world.rng is still seeded straight from the seed")


# ---------------------------------------------------------------- spawning

func _run_round(seed: int, first: PackedInt32Array, rnd: int, ticks: int) -> Dictionary:
	var w := SimWorld.new(seed)
	w.hive_first = first
	w.round = rnd
	w.phase_ticks_left = w.combat_duration(rnd)
	var v := w.add_vehicle(1, Vector2(1280, 720))
	v.weapons.clear()
	v.speed = 0.0
	v.max_hp = 1.0e7
	v.hp = v.max_hp
	var peak := [0, 0, 0]
	for t in ticks:
		w.step()
		if t % 10 == 0:
			var c: PackedInt32Array = Species.count_alive(w)
			for i in 3:
				peak[i] = maxi(peak[i], c[i])
	return {"w": w, "peak": peak}


func test_only_active_species_spawn_and_not_before_their_round() -> void:
	var early: Dictionary = _run_round(8, PackedInt32Array([4, 0, 6]), 3, 900)
	assert_eq(early["peak"], [0, 0, 0], "nothing before the first round")
	var late: Dictionary = _run_round(8, PackedInt32Array([4, 0, 6]), 7, 1500)
	var peak: Array = late["peak"]
	assert_gt(float(peak[0]), 0.0, "glass wings spawn")
	assert_eq(peak[1], 0, "an inactive species never spawns")
	assert_gt(float(peak[2]), 0.0, "shriekers spawn")
	assert_true(int(peak[0]) <= Species.cap(0, 7, 4) + Species.GLASS_FLOCK_MAX, "glass cap respected (%d)" % int(peak[0]))
	assert_true(int(peak[2]) <= Species.cap(2, 7, 6), "shrieker cap respected (%d)" % int(peak[2]))


func test_spawns_are_deterministic() -> void:
	var a: Dictionary = _run_round(12, PackedInt32Array([3, 3, 0]), 6, 600)
	var b: Dictionary = _run_round(12, PackedInt32Array([3, 3, 0]), 6, 600)
	assert_eq((a["w"] as SimWorld).checksum(), (b["w"] as SimWorld).checksum())
	assert_gt(float((a["peak"] as Array)[0] + (a["peak"] as Array)[1]), 0.0, "something spawned")


# ---------------------------------------------------------------- glass wings

func test_glass_wings_dive_and_only_hurt_while_diving() -> void:
	var w := _arena()
	var v: SimVehicle = w.vehicles[0]
	w.round = 5
	for k in 4:
		w.spawn_enemy(SimWorld.GLASS, Vector2(900 + k * 6, 600))
	var hurt_ticks: int = 0
	var hurt_outside_dive: int = 0
	var dive_ticks_seen: int = 0
	var last_hp: float = v.hp
	var min_d: float = INF
	for t in 450:
		w.step()
		var diving_any: bool = false
		for i in w.enemy_count:
			if Species.glass_diving(w.tick - 1, w.enemy_id[i]):
				diving_any = true
		if diving_any:
			dive_ticks_seen += 1
		if v.hp < last_hp:
			hurt_ticks += 1
			if not diving_any:
				hurt_outside_dive += 1
		last_hp = v.hp
		for i in w.enemy_count:
			min_d = minf(min_d, w.enemy_pos[i].distance_to(v.pos))
	assert_gt(float(hurt_ticks), 5.0, "the dives hurt (%d ticks)" % hurt_ticks)
	assert_eq(hurt_outside_dive, 0, "no contact damage outside a dive")
	assert_gt(float(dive_ticks_seen), 20.0)
	assert_lt(min_d, SimVehicle.RADIUS + 12.0, "a dive reaches the hull")


func test_glass_wings_pull_away_and_circle_loosely() -> void:
	var w := _arena()
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.GLASS, Vector2(760, 600))
	var far: float = 0.0
	for t in 300:
		w.step()
		far = maxf(far, w.enemy_pos[0].distance_to(v.pos))
	assert_gt(far, 100.0, "pulled away after the dive (%f)" % far)


func test_rams_and_ground_effects_miss_flyers_but_bullets_hit() -> void:
	var w := _arena()
	var v: SimVehicle = w.vehicles[0]
	v.ram_damage = 500.0
	v.ramming = true
	var j: int = w.spawn_enemy(SimWorld.GLASS, v.pos + Vector2(10, 0))
	w.enemy_status[j] = 0
	# put it into its dive so that it touches the rig
	var id: int = w.enemy_id[j]
	while not Species.glass_diving(w.tick, id):
		w.tick += 1
	var hp0: float = w.enemy_hp[j]
	w.step()
	assert_eq(w.enemy_hp[0], hp0, "a ram does not hurt a flyer")
	# ground effects
	var w2 := _arena()
	w2.spawn_enemy(SimWorld.GLASS, Vector2(800, 800))
	w2.spawn_enemy(SimWorld.MITE, Vector2(800, 800))
	w2._add_zone(Vector2(800, 800), 40.0, SimWorld.ZONE_FIRE, 60, 0)
	w2._add_zone(Vector2(800, 800), 40.0, SimWorld.ZONE_EMBER, 60, 0)
	w2._add_zone(Vector2(800, 800), 40.0, SimWorld.ZONE_OIL, 60, 0)
	for t in 20:
		w2.step()
	var glass_hp: float = 0.0
	var mite_alive: bool = false
	for i in w2.enemy_count:
		if w2.enemy_kind[i] == SimWorld.GLASS:
			glass_hp = w2.enemy_hp[i]
		elif w2.enemy_kind[i] == SimWorld.MITE and w2.enemy_hp[i] > 0.0:
			mite_alive = true
	assert_eq(glass_hp, SimWorld.enemy_max_hp(SimWorld.GLASS, 1), "fire and embers do not reach a flyer")
	assert_false(mite_alive, "the same fire kills a mite")
	# direct hits of an MG shot kill it, a flame jet passes through
	var w3 := _arena()
	w3.spawn_enemy(SimWorld.GLASS, Vector2(700, 600))
	w3.enemy_vel[0] = Vector2.ZERO
	var flamer: int = Cards.weapon_kind_index("flamer")
	w3.spawn_projectile(Vector2(660, 600), Vector2(400, 0), 0.5, 50.0, 0, 0, 0.0, flamer)
	for t in 6:
		w3.enemy_pos[0] = Vector2(700, 600)
		w3.step()
	assert_eq(_count(w3, SimWorld.GLASS), 1, "the flame jet flies through")
	w3.spawn_projectile(Vector2(660, 600), Vector2(400, 0), 0.5, 50.0, 0, 0, 0.0, 0)
	for t in 6:
		if w3.enemy_count > 0:
			w3.enemy_pos[0] = Vector2(700, 600)
		w3.step()
	assert_eq(_count(w3, SimWorld.GLASS), 0, "an MG round kills it")


# ---------------------------------------------------------------- brood carrier

func _brood_kill(how: String) -> Dictionary:
	var w := _arena()
	var j: int = w.spawn_enemy(SimWorld.BROOD, Vector2(1000, 1000))
	var mites0: int = _count(w, SimWorld.MITE)
	match how:
		"burn":
			w._ignite(j, 5.0, 0)
			w._hit_enemy(j, 1000.0, 0)
		"splash":
			w._hash.rebuild(w.enemy_pos, w.enemy_count)
			w._splash_damage(Vector2(1000, 1000), 30.0, 1000.0, 0, -1)
		_:
			w._hit_enemy(j, 1000.0, 0)
	var evs: Array[Dictionary] = _events(w, "brood")
	for t in 20:
		w.step()
		evs.append_array(_events(w, "brood"))
	return {"mites": _count(w, SimWorld.MITE) - mites0, "events": evs, "w": w}


func test_brood_carrier_bursts_into_mites() -> void:
	var r: Dictionary = _brood_kill("bullet")
	assert_true(int(r["mites"]) >= 6 and int(r["mites"]) <= 8, "6..8 mites hatch (%d)" % int(r["mites"]))
	var evs: Array = r["events"]
	assert_eq(evs.size(), 1)
	assert_eq(int(evs[0]["kind"]), 1, "event says the brood hatched")


func test_brood_dies_with_fire_and_splash() -> void:
	for how in ["burn", "splash"]:
		var r: Dictionary = _brood_kill(how)
		assert_eq(int(r["mites"]), 0, "no mites after a %s kill" % how)
		var evs: Array = r["events"]
		assert_eq(evs.size(), 1)
		assert_eq(int(evs[0]["kind"]), 0, "event says the brood died")


func test_brood_mites_come_after_the_burst_frame() -> void:
	var w := _arena()
	var j: int = w.spawn_enemy(SimWorld.BROOD, Vector2(1000, 1000))
	w._hit_enemy(j, 1000.0, 0)
	w.step()
	assert_eq(_count(w, SimWorld.MITE), 0, "not on the very next tick")
	for t in Species.BROOD_DELAY + 2:
		w.step()
	assert_gt(float(_count(w, SimWorld.MITE)), 5.0)


# ---------------------------------------------------------------- shrieker

func test_shrieker_holds_its_distance() -> void:
	var w := _arena()
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.SHRIEKER, Vector2(1300, 600))
	var min_d: float = INF
	for t in 400:
		w.step()
		if t > 100:
			min_d = minf(min_d, w.enemy_pos[0].distance_to(v.pos))
	assert_gt(min_d, Species.SHRIEKER_KEEP_MIN - 25.0, "never closes in (%f)" % min_d)
	assert_lt(w.enemy_pos[0].distance_to(v.pos), Species.SHRIEKER_KEEP_MAX + 30.0, "creeps in to its post")


func test_shrieker_pulse_heals_and_hastens_but_not_bosses() -> void:
	var w := _arena()
	w.round = 5
	w.hive_first = PackedInt32Array([0, 0, 3])
	var si: int = w.spawn_enemy(SimWorld.SHRIEKER, Vector2(1000, 1000))
	var id: int = w.enemy_id[0]
	var bj: int = w.spawn_enemy(SimWorld.BOULDER, Vector2(1040, 1000))
	var mj: int = w.spawn_enemy(SimWorld.MITE, Vector2(1000, 1050))
	var far: int = w.spawn_enemy(SimWorld.BOULDER, Vector2(1000, 1400))
	var boss: int = w.spawn_enemy(SimWorld.BOSS_A, Vector2(1000, 960))
	w.enemy_hp[boss] = 100.0
	w.boss_max_hp = 1000.0
	var max_b: float = w.enemy_max_hp_of(bj)
	w.enemy_hp[bj] = max_b * 0.3
	w.enemy_hp[far] = max_b * 0.3
	w._hash.rebuild(w.enemy_pos, w.enemy_count)
	# run until the pulse
	var pulses: int = 0
	var before: float = w.enemy_hp[bj]
	for t in Species.SHRIEK_PERIOD + 2:
		w.step()
		pulses += _events(w, "shriek").size()
		if pulses > 0:
			break
	assert_eq(pulses, 1, "one pulse event")
	assert_true(w.enemy_hp[bj] > before + 0.15 * max_b, "the boulder healed (%f -> %f)" % [before, w.enemy_hp[bj]])
	assert_true(Species.haste_of(w.enemy_status[bj]) > 0, "and was hastened")
	assert_true(Species.haste_of(w.enemy_status[mj]) > 0, "the mite too")
	assert_lt(absf(w.enemy_hp[far] - max_b * 0.3), 0.01, "far away is not healed")
	assert_eq(w.enemy_hp[boss], 100.0, "bosses are not healed")
	assert_eq(Species.haste_of(w.enemy_status[boss]), 0, "or hastened")
	assert_eq(si, 0)
	assert_eq(id, w.enemy_id[0])


func test_haste_runs_out_and_speeds_movement() -> void:
	var w := _arena()
	var a: int = w.spawn_enemy(SimWorld.BOULDER, Vector2(1400, 600))
	var b: int = w.spawn_enemy(SimWorld.BOULDER, Vector2(1400, 700))
	w._status_enemy(b, Species.HASTE_SHIFT, Species.SHRIEK_HASTE_TICKS)
	for t in 30:
		w.step()
	var da: float = Vector2(1400, 600).distance_to(w.enemy_pos[a])
	var db: float = Vector2(1400, 700).distance_to(w.enemy_pos[b])
	assert_gt(db, da * 1.2, "the hasted boulder is clearly faster (%f vs %f)" % [db, da])
	for t in 120:
		w.step()
	assert_eq(Species.haste_of(w.enemy_status[b]), 0, "haste wore off")


func test_shrieker_has_low_hp() -> void:
	assert_true(SimWorld.ENEMY_HP[SimWorld.SHRIEKER] <= 20.0)
	assert_true(SimWorld.ENEMY_HP[SimWorld.GLASS] <= 10.0)


# ---------------------------------------------------------------- doctrine

func test_shriekers_target_mode_and_condition() -> void:
	assert_true(Doctrine.RIG_TARGETS.has("shriekers"))
	assert_true(Doctrine.WEAPON_TARGETS.has("shriekers"))
	assert_true(Doctrine.COND_IDS.has("shrieker_near"))
	assert_true(Doctrine.ACTIONS.has("target:shriekers"))
	var w := _arena()
	var v: SimVehicle = w.vehicles[0]
	var m: int = w.spawn_enemy(SimWorld.MITE, Vector2(660, 600))
	var s: int = w.spawn_enemy(SimWorld.SHRIEKER, Vector2(760, 600))
	w._hash.rebuild(w.enemy_pos, w.enemy_count)
	var t: Vector3i = VehicleAI.find_target(w, v, "shriekers", 0.0)
	assert_eq(t.y, s, "the shrieker is picked over the nearer mite")
	assert_eq(VehicleAI.find_target(w, v, "nearest", 0.0).y, m)
	assert_true(Species.shrieker_near(w, v), "shrieker 160 px away is near")
	w.enemy_pos[s] = Vector2(1500, 600)
	w._hash.rebuild(w.enemy_pos, w.enemy_count)
	assert_false(Species.shrieker_near(w, v), "900 px away it is not")
	# the rule text round-trips
	var rules: Variant = Doctrine.parse("shrieker_near=1|target:shriekers", "rig")
	assert_true(rules != null and (rules as Array).size() == 1, "rule parses")


func test_set_target_command_accepts_shriekers() -> void:
	var w := _arena()
	w.apply_command(1, {"type": "set_target", "value": "shriekers"})
	assert_eq(w.vehicles[0].doctrine["target"], "shriekers")


# ---------------------------------------------------------------- snapshot

func test_snapshot_round_trip_of_species_and_signature() -> void:
	var w := _arena()
	w.hive_first = PackedInt32Array([5, 0, 3])
	w.spawn_enemy(SimWorld.GLASS, Vector2(900, 700))
	w.spawn_enemy(SimWorld.BROOD, Vector2(1000, 700))
	w.spawn_enemy(SimWorld.SHRIEKER, Vector2(1100, 700))
	w.spawn_enemy(SimWorld.MITE, Vector2(1200, 700))
	w.step()
	var bytes: PackedByteArray = Snapshot.encode(w)
	var c := SimWorld.new(999)
	assert_true(Snapshot.apply(c, bytes), "applies")
	assert_eq(c.hive_first, PackedInt32Array([5, 0, 3]), "signature travels")
	assert_eq(c.enemy_count, 4)
	for i in 4:
		assert_eq(int(c.enemy_kind[i]), int(w.enemy_kind[i]), "kind %d" % i)
	assert_true(c.enemy_pos[0].distance_to(w.enemy_pos[0]) < 0.1)
	assert_true(absf(c.enemy_hp[1] - w.enemy_hp[1]) < 0.1 * SimWorld.ENEMY_HP[SimWorld.BROOD], "hp within a step")


func test_snapshot_carries_species_events_and_stats() -> void:
	var w := _arena()
	var j: int = w.spawn_enemy(SimWorld.BROOD, Vector2(1000, 1000))
	w._hit_enemy(j, 1000.0, 0)
	var evs: Array[Dictionary] = []
	evs.append({"type": "shriek", "pos": Vector2(500, 500), "owner": -1, "kind": SimWorld.SHRIEKER})
	evs.append_array(w.events)
	w.step()
	var bytes: PackedByteArray = Snapshot.encode(w, evs)
	var c := SimWorld.new(1)
	assert_true(Snapshot.apply(c, bytes))
	var types: Array = []
	for e in c.events:
		types.append(e["type"])
	assert_true(types.has("shriek"), "shriek event over the wire")
	assert_true(types.has("brood"), "brood event over the wire")
	# damage stats of the new sources
	var v: SimVehicle = w.vehicles[0]
	(v.round_stats["taken"] as Dictionary)["glass"] = 12.0
	(v.round_stats["taken"] as Dictionary)["brood"] = 7.0
	(v.round_stats["taken"] as Dictionary)["shrieker"] = 3.0
	w.phase = SimWorld.PHASE_WORKSHOP
	var c2 := SimWorld.new(1)
	assert_true(Snapshot.apply(c2, Snapshot.encode(w)))
	var tk: Dictionary = c2.vehicles[0].round_stats["taken"]
	assert_eq(int(tk["glass"]), 12)
	assert_eq(int(tk["brood"]), 7)
	assert_eq(int(tk["shrieker"]), 3)


func test_contact_damage_is_booked_per_species() -> void:
	var w := _arena()
	var v: SimVehicle = w.vehicles[0]
	w.round = 3
	w.spawn_enemy(SimWorld.BROOD, v.pos + Vector2(20, 0))
	for t in 30:
		w.step()
	var tk: Dictionary = v.round_stats["taken"]
	assert_gt(float(tk["brood"]), 0.5, "brood carrier bites are booked")
	assert_eq(float(tk["glass"]), 0.0)
