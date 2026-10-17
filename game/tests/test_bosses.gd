extends TestCase
## Boss rounds: schedule, spawn timing, phases, Colossus split, rewards, retreat, targeting, determinism, snapshot.


## One immortal, motionless, unarmed rig in the arena centre in boss round `rnd`; the seed is chosen so `want_kind`
## (BOSS_A / BOSS_B, -1 = any) is that round's boss. Regular spawns are off, the boss is forced.
func _duel(rnd: int = 4, want_kind: int = -1) -> SimWorld:
	var s: int = 21
	while want_kind >= 0 and Bosses.kind_for_round(Bosses.first_for_seed(s), rnd) != want_kind:
		s += 1
	var w := SimWorld.new(s)
	w.boss_forced = true
	w.spawning_enabled = false
	w.round = rnd
	w.phase_ticks_left = w.combat_duration(rnd)
	var v := w.add_vehicle(1, SimWorld.ARENA.get_center())
	v.weapons.clear()
	v.speed = 0.0
	v.max_hp = 1.0e7
	v.hp = v.max_hp
	return w


func _step_until_active(w: SimWorld) -> void:
	var guard: int = 0
	while w.boss_state != Bosses.ST_ACTIVE and guard < 3000:
		w.step()
		guard += 1


func _events(w: SimWorld, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in w.events:
		if e["type"] == type:
			out.append(e)
	return out


func _boss_index(w: SimWorld) -> int:
	for i in w.enemy_count:
		if w.enemy_kind[i] >= SimWorld.BOSS_A and w.enemy_hp[i] > 0.0:
			return i
	return -1


func _bodies(w: SimWorld) -> int:
	var n: int = 0
	for i in w.enemy_count:
		if w.enemy_kind[i] >= SimWorld.BOSS_A and w.enemy_hp[i] > 0.0:
			n += 1
	return n


# ---------------------------------------------------------------- schedule

func test_schedule_rounds_and_alternation() -> void:
	for r in [1, 2, 3, 5, 6, 7, 9, 13, 19]:
		assert_false(Bosses.is_boss_round(r), "round %d" % r)
		assert_eq(Bosses.kind_for_round(0, r), -1)
	for r in [4, 8, 12, 16, 20]:
		assert_true(Bosses.is_boss_round(r), "round %d" % r)
	for first in [0, 1]:
		var seq: Array = []
		for r in [4, 8, 12, 16, 20]:
			seq.append(Bosses.kind_for_round(first, r))
		var a: int = SimWorld.BOSS_A + first
		var b: int = SimWorld.BOSS_A + (1 - first)
		assert_eq(seq, [a, b, a, b, a], "alternates, first=%d" % first)
	assert_false(Bosses.enraged_in(8))
	assert_true(Bosses.enraged_in(12))
	assert_true(Bosses.enraged_in(20))


func test_seed_decides_first_boss_and_is_known_at_start() -> void:
	var seen := {}
	for s in 40:
		var w := SimWorld.new(s)
		assert_eq(w.boss_first, Bosses.first_for_seed(s))
		var nb: Dictionary = Bosses.next_boss(w)
		assert_eq(int(nb["round"]), 4, "next boss at match start is round 4")
		assert_eq(int(nb["kind"]), SimWorld.BOSS_A + w.boss_first)
		assert_false(bool(nb["enraged"]))
		assert_true(str(nb["name"]) != "")
		seen[w.boss_first] = true
	assert_eq(seen.size(), 2, "both orders occur across seeds")
	var w2 := SimWorld.new(3)
	w2.round = 4
	w2.phase = SimWorld.PHASE_COMBAT
	assert_eq(int(Bosses.next_boss(w2)["round"]), 8, "during the boss round the next one is round 8")
	w2.phase = SimWorld.PHASE_WORKSHOP
	assert_eq(int(Bosses.next_boss(w2)["round"]), 8, "workshop after round 4 shows round 8")
	w2.round = 3
	assert_eq(int(Bosses.next_boss(w2)["round"]), 4, "workshop after round 3 shows round 4")


# ---------------------------------------------------------------- spawn

func test_warning_three_seconds_before_the_first_surge() -> void:
	var w := _duel()
	var dur: int = w.combat_duration(4)
	var start: int = SimWorld.surge_starts(dur)[0]
	var warn_tick: int = -1
	var spawn_tick: int = -1
	var warn_pos := Vector2.ZERO
	for t in dur:
		w.step()
		for e in _events(w, "boss"):
			warn_tick = t
			warn_pos = e["pos"]
			assert_eq(int(e["in_ticks"]), Bosses.WARN_TICKS)
			assert_eq(int(e["kind"]), w.boss_kind)
		if not _events(w, "boss_spawn").is_empty() and spawn_tick < 0:
			spawn_tick = t
	assert_eq(warn_tick, start - Bosses.WARN_TICKS, "warning 3 s before the surge")
	assert_eq(spawn_tick, start, "spawns with the first surge")
	var edge: float = minf(minf(warn_pos.y, SimWorld.ARENA.end.y - warn_pos.y), minf(warn_pos.x, SimWorld.ARENA.end.x - warn_pos.x))
	assert_lt(edge, 60.0, "from the arena edge")
	assert_eq(w.boss_state, Bosses.ST_RETREATED if w.phase == SimWorld.PHASE_WORKSHOP else Bosses.ST_ACTIVE)


func test_boss_comes_from_the_edge_nearest_the_rigs() -> void:
	var w := _duel()
	w.vehicles[0].pos = Vector2(200.0, 700.0)
	_step_until_active(w)
	var i: int = _boss_index(w)
	assert_true(i >= 0)
	assert_lt(w.enemy_pos[i].x, 120.0, "left edge")
	var w2 := _duel()
	w2.vehicles[0].pos = Vector2(1300.0, 1380.0)
	_step_until_active(w2)
	assert_gt(w2.enemy_pos[_boss_index(w2)].y, SimWorld.ARENA.end.y - 120.0, "bottom edge")


func test_no_boss_in_ordinary_rounds() -> void:
	var w := _duel(5)
	for t in 1500:
		w.step()
	assert_eq(w.boss_state, Bosses.ST_NONE)
	assert_eq(_bodies(w), 0)


func test_regular_spawns_run_at_half_while_a_boss_is_up() -> void:
	var w := SimWorld.new(21)
	w.round = 4
	w.phase_ticks_left = w.combat_duration(4)
	assert_eq(Bosses.BOSS_SPAWN_FACTOR, 0.5)
	assert_false(Bosses.engaged(w))
	w.boss_state = Bosses.ST_ACTIVE
	assert_true(Bosses.engaged(w))
	w.boss_state = Bosses.ST_KILLED
	assert_false(Bosses.engaged(w), "full spawns again after the kill")


func test_hp_scales_with_round_and_vehicles() -> void:
	assert_gt(Bosses.max_hp_for(8, 1), Bosses.max_hp_for(4, 1))
	assert_gt(Bosses.max_hp_for(4, 3), Bosses.max_hp_for(4, 1) * 2.0)
	var w := _duel()
	w.add_vehicle(2, Vector2(900, 700))
	_step_until_active(w)
	assert_eq(w.boss_max_hp, Bosses.max_hp_for(4, 2))
	assert_eq(w.enemy_hp[_boss_index(w)], w.boss_max_hp)


# ---------------------------------------------------------------- phases

func test_phases_at_66_and_33_percent() -> void:
	var w := _duel(4, SimWorld.BOSS_A)
	_step_until_active(w)
	assert_eq(w.boss_phase, 1)
	var i: int = _boss_index(w)
	w.enemy_hp[i] = w.boss_max_hp * 0.6
	w.step()
	assert_eq(w.boss_phase, 2)
	var ph: Array[Dictionary] = _events(w, "boss_phase")
	assert_eq(ph.size(), 1)
	assert_eq(int(ph[0]["kind"]), 2)
	w.enemy_hp[_boss_index(w)] = w.boss_max_hp * 0.3
	w.step()
	assert_eq(w.boss_phase, 3)
	assert_eq(int(_events(w, "boss_phase")[0]["kind"]), 3)
	w.step()
	assert_true(_events(w, "boss_phase").is_empty(), "one event per change")
	assert_true(absf(w.boss_hp_frac - 0.3) < 0.01)


func test_enraged_from_round_twelve() -> void:
	var w := _duel(12)
	_step_until_active(w)
	assert_true(w.boss_enraged)
	var w2 := _duel(8)
	_step_until_active(w2)
	assert_false(w2.boss_enraged)
	assert_gt(Bosses.speed_of(w, SimWorld.BOSS_A, 1), Bosses.speed_of(w2, SimWorld.BOSS_A, 1))


# ---------------------------------------------------------------- Tripod Queen

func test_tripod_shells_have_a_telegraph_then_splash() -> void:
	var w := _duel(4, SimWorld.BOSS_A)
	var v: SimVehicle = w.vehicles[0]
	_step_until_active(w)
	var mark: Dictionary = {}
	var seen_tick: int = -1
	for t in 600:
		w.step()
		if not w.boss_marks.is_empty():
			mark = w.boss_marks[0].duplicate()
			seen_tick = t
			break
	assert_false(mark.is_empty(), "a shell marker appears")
	assert_eq(int(mark["k"]), Bosses.MARK_SHELL)
	assert_eq(int(mark["total"]), Bosses.SHELL_TICKS)
	# park the rig on the marker, let it land
	v.pos = mark["pos"]
	var hp0: float = v.hp
	for t in Bosses.SHELL_TICKS + 2:
		w.step()
	assert_lt(v.hp, hp0, "the shell hurt the rig standing on the marker")
	assert_gt(seen_tick, 0)


func test_tripod_phase_two_births_mites_and_phase_three_fires_volleys() -> void:
	var w := _duel(4, SimWorld.BOSS_A)
	_step_until_active(w)
	var mites0: int = 0
	w.enemy_hp[_boss_index(w)] = w.boss_max_hp * 0.5
	for t in 400:
		w.step()
	for i in w.enemy_count:
		if w.enemy_kind[i] == SimWorld.MITE:
			mites0 += 1
	assert_gt(mites0, 3, "brood mites")
	w.enemy_hp[_boss_index(w)] = w.boss_max_hp * 0.2
	var max_marks: int = 0
	for t in 500:
		w.step()
		max_marks = maxi(max_marks, w.boss_marks.size())
	assert_gt(max_marks, 2, "volleys of three shells")


# ---------------------------------------------------------------- Shard Colossus

func test_colossus_ring_is_telegraphed_and_dodgeable() -> void:
	var w := _duel(4, SimWorld.BOSS_B)
	_step_until_active(w)
	var glow: bool = false
	var released: int = 0
	for t in 500:
		w.step()
		for m in w.boss_marks:
			if int(m["k"]) == Bosses.MARK_RING:
				glow = true
				assert_eq(int(m["total"]), Bosses.RING_WINDUP)
		released += _events(w, "boss_ring").size()
		if released > 0:
			break
	assert_true(glow, "a glow marker precedes the ring")
	assert_eq(released, 1)
	var shards: int = 0
	for p in w.proj_count:
		if w.proj_owner[p] < 0:
			shards += 1
			assert_lt(w.proj_vel[p].length(), 120.0, "slow shards")
	assert_eq(shards, Bosses.RING_COUNT)


func test_colossus_charge_in_phase_two() -> void:
	var w := _duel(4, SimWorld.BOSS_B)
	_step_until_active(w)
	w.enemy_hp[_boss_index(w)] = w.boss_max_hp * 0.5
	var charged: bool = false
	var line: bool = false
	for t in 900:
		w.step()
		for m in w.boss_marks:
			if int(m["k"]) == Bosses.MARK_CHARGE:
				line = true
		if not _events(w, "boss_charge").is_empty():
			charged = true
		if charged and line:
			break
	assert_true(charged and line, "charge with a telegraph line")


func test_colossus_splits_at_33_percent_and_dies_with_its_shards() -> void:
	var w := _duel(4, SimWorld.BOSS_B)
	var v: SimVehicle = w.vehicles[0]
	_step_until_active(w)
	var hp_full: float = w.boss_max_hp
	# a huge hit cannot kill the body before the split
	w._hit_enemy(_boss_index(w), hp_full * 5.0, 0)
	assert_eq(w.boss_state, Bosses.ST_ACTIVE)
	w.enemy_hp[_boss_index(w)] = hp_full * 0.3
	w.step()
	assert_eq(w.boss_phase, 3)
	assert_false(_events(w, "boss_split").is_empty())
	w.step()
	assert_eq(_bodies(w), 3, "three shards")
	for i in w.enemy_count:
		if w.enemy_kind[i] == SimWorld.BOSS_SHARD:
			assert_true(absf(w.enemy_hp[i] - hp_full / 6.0) < 0.5)
	# kill two: still active
	var killed: int = 0
	for i in w.enemy_count:
		if w.enemy_kind[i] == SimWorld.BOSS_SHARD and killed < 2:
			w._hit_enemy(i, 1.0e9, v.id)
			killed += 1
	w.step()
	assert_eq(w.boss_state, Bosses.ST_ACTIVE)
	assert_true(_events(w, "boss_kill").is_empty())
	assert_eq(_bodies(w), 1)
	w._hit_enemy(_boss_index(w), 1.0e9, v.id)
	assert_eq(w.boss_state, Bosses.ST_KILLED)
	assert_eq(_events(w, "boss_kill").size(), 1)


# ---------------------------------------------------------------- rewards, retreat

func test_kill_pays_bounties_and_the_killer_gets_a_rare_draft() -> void:
	var w := _duel(4, SimWorld.BOSS_A)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.add_vehicle(2, Vector2(900, 700))
	var c: SimVehicle = w.add_vehicle(3, Vector2(1700, 700))
	for o in [b, c]:
		o.weapons.clear()
		o.speed = 0.0
		o.max_hp = 1.0e7
		o.hp = o.max_hp
	_step_until_active(w)
	var i: int = _boss_index(w)
	var max_hp: float = w.boss_max_hp
	w._hit_enemy(i, max_hp * 0.2, 1)  # b: 20%
	w._hit_enemy(i, max_hp * 0.05, 2)  # c: 5%, below the threshold
	var scrap_a: int = a.scrap
	var scrap_b: int = b.scrap
	var scrap_c: int = c.scrap
	w._hit_enemy(i, max_hp * 2.0, 0)  # a: the killing blow (about 75%)
	assert_eq(w.boss_state, Bosses.ST_KILLED)
	var bounty: int = Bosses.BOUNTY_BASE + Bosses.BOUNTY_PER_ROUND * 4
	assert_eq(b.scrap - scrap_b, bounty, "a helper with >= 10% is paid")
	assert_eq(c.scrap - scrap_c, 0, "a bystander with 5% is not")
	assert_gt(a.scrap - scrap_a, bounty, "the killing blow pays more")
	var ev: Array[Dictionary] = _events(w, "boss_kill")
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0]["owner"]), 0)
	assert_eq(a.bonus_offers, 1)
	assert_true(a.boss_rare)
	assert_false(b.boss_rare)
	# the next draft: 4 offers with a rare or better card
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(a.offers.size(), Cards.OFFER_COUNT + 1)
	var rare: bool = false
	for id in a.offers:
		if str(Cards.def(id)["rarity"]) != "common":
			rare = true
	assert_true(rare, "guaranteed rare-or-better")
	assert_false(a.boss_rare, "consumed")
	assert_eq(b.offers.size(), Cards.OFFER_COUNT)


func test_rare_guarantee_holds_over_many_seeds() -> void:
	for s in 60:
		var w := SimWorld.new(s)
		var v := w.add_vehicle(1, Vector2(500, 500))
		var offers: Array[String] = Cards.roll_offers(w.rng, v, 4, 4, [], true)
		assert_eq(offers.size(), 4)
		var rare: bool = false
		for id in offers:
			if str(Cards.def(id)["rarity"]) != "common":
				rare = true
		assert_true(rare, "seed %d" % s)


func test_boss_alive_at_round_end_retreats_without_penalty() -> void:
	var w := _duel(4, SimWorld.BOSS_A)
	var v: SimVehicle = w.vehicles[0]
	var fuel: int = v.fuel
	var retreat: int = 0
	var guard: int = 0
	while w.phase == SimWorld.PHASE_COMBAT and guard < 4000:
		w.step()
		retreat += _events(w, "boss_retreat").size()
		guard += 1
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(retreat, 1)
	assert_eq(w.boss_state, Bosses.ST_RETREATED)
	assert_eq(v.fuel, fuel, "no penalty")
	assert_eq(w.enemy_count, 0)
	assert_true(w.boss_marks.is_empty())


# ---------------------------------------------------------------- interactions

func test_ramming_a_boss_is_weak_and_costs_the_rammer() -> void:
	var w := _duel(4, SimWorld.BOSS_B)
	var v: SimVehicle = w.vehicles[0]
	_step_until_active(w)
	var i: int = _boss_index(w)
	w.enemy_pos[i] = v.pos + Vector2(40, 0)
	v.ram_damage = 100.0
	v.ramming = true
	v.max_hp = 5000.0
	v.hp = 5000.0
	var hp0: float = w.enemy_hp[i]
	w._update_enemies()
	var dealt: float = hp0 - w.enemy_hp[i]
	assert_gt(dealt, 0.0)
	assert_lt(dealt, 100.0 * Bosses.RAM_DAMAGE_FACTOR + 0.01, "reduced ram damage")
	assert_lt(v.hp, 5000.0, "the rammer is hurt")


func test_emp_only_slows_a_boss() -> void:
	var w := _duel(4, SimWorld.BOSS_B)
	_step_until_active(w)
	var i: int = _boss_index(w)
	w.stun_enemy(i, 90)
	assert_eq(w.enemy_status[i] & 255, 0, "no stun")
	assert_gt((w.enemy_status[i] >> 8) & 255, 0, "a slow instead")
	assert_true(((w.enemy_status[i] >> 8) & 255) <= Bosses.EMP_SLOW_MAX)


func test_doctrine_boss_target_and_condition() -> void:
	var w := _duel(4, SimWorld.BOSS_A)
	var v: SimVehicle = w.vehicles[0]
	_step_until_active(w)
	assert_true(Doctrine.RIG_TARGETS.has("boss"))
	assert_true(Doctrine.WEAPON_TARGETS.has("boss"))
	assert_true(Doctrine.COND_IDS.has("boss_active"))
	assert_true(Doctrine.ACTIONS.has("target:boss"))
	w.enemy_pos[_boss_index(w)] = v.pos + Vector2(250, 0)
	w._hash.rebuild(w.enemy_pos, w.enemy_count)
	var mite: int = w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(60, 0))
	w._hash.rebuild(w.enemy_pos, w.enemy_count)
	assert_true(mite >= 0)
	var t: Vector3i = VehicleAI.find_target(w, v, "boss", 0.0)
	assert_eq(t.x, 1)
	assert_true(w.enemy_kind[t.y] >= SimWorld.BOSS_A, "picks the boss over the nearer mite")
	var s: Vector3i = VehicleAI.find_target(w, v, "strongest", 400.0)
	assert_true(w.enemy_kind[s.y] >= SimWorld.BOSS_A, "strongest picks the boss")
	var cond: Variant = Doctrine.make_cond("boss_active", "=", 1)
	assert_true(Doctrine._holds(w, v, [cond], 0, -1, -1, Vector2.ZERO, {}), "boss active")
	w.boss_state = Bosses.ST_KILLED
	assert_false(Doctrine._holds(w, v, [cond], 0, -1, -1, Vector2.ZERO, {}), "not any more")
	w.boss_state = Bosses.ST_ACTIVE
	w.apply_command(1, {"type": "set_target", "value": "boss"})
	assert_eq(v.doctrine["target"], "boss")
	w.apply_command(1, {"type": "set_weapon_target", "scope": "mg", "value": "boss"})


# ---------------------------------------------------------------- determinism, snapshot

func _fight(seed_value: int, ticks: int) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.round = 8
	w.phase_ticks_left = w.combat_duration(8)
	w.add_vehicle(1, Vector2(1200, 700))
	w.add_vehicle(2, Vector2(1400, 740))
	for t in ticks:
		w.step()
	return w


func test_determinism() -> void:
	var a := _fight(7, 1100)
	var b := _fight(7, 1100)
	assert_true(a.boss_state != Bosses.ST_NONE, "the boss was in this run")
	assert_eq(a.checksum(), b.checksum())
	assert_eq(a.boss_hp_frac, b.boss_hp_frac)


func test_snapshot_round_trip() -> void:
	for seed_value in [3, 4]:
		var a := _fight(seed_value, 900)
		# put every marker kind and a phase on the record
		a.boss_marks.append({"k": Bosses.MARK_CHARGE, "pos": Vector2(500, 400), "pos2": Vector2(700, 420), "r": 34.0, "left": 12, "total": 30})
		var bytes: PackedByteArray = Snapshot.encode(a)
		var b := SimWorld.new(1)
		assert_true(Snapshot.apply(b, bytes))
		assert_eq(b.boss_first, a.boss_first)
		assert_eq(b.boss_kind, a.boss_kind)
		assert_eq(b.boss_state, a.boss_state)
		assert_eq(b.boss_phase, a.boss_phase)
		assert_eq(b.boss_enraged, a.boss_enraged)
		assert_eq(b.boss_marks.size(), a.boss_marks.size())
		assert_true(absf(b.boss_hp_frac - a.boss_hp_frac) < 0.002)
		assert_true(absf(b.boss_max_hp - a.boss_max_hp) < 1.0)
		assert_eq(b.enemy_count, a.enemy_count)
		var found: int = 0
		for i in a.enemy_count:
			if a.enemy_kind[i] >= SimWorld.BOSS_A:
				found += 1
				assert_eq(b.enemy_kind[i], a.enemy_kind[i], "real boss kind survives the 2-bit enemy table")
				assert_true(absf(b.enemy_hp[i] - a.enemy_hp[i]) <= 1.0)
		assert_gt(found, 0, "a boss body was sent")
		var m: Dictionary = b.boss_marks[b.boss_marks.size() - 1]
		assert_eq(int(m["k"]), Bosses.MARK_CHARGE)
		assert_true((m["pos2"] as Vector2).distance_to(Vector2(700, 420)) < 0.1)
		assert_eq(int(m["left"]), 12)


func test_snapshot_round_trip_with_events_and_shards() -> void:
	var w := _duel(4, SimWorld.BOSS_B)
	_step_until_active(w)
	w.enemy_hp[_boss_index(w)] = w.boss_max_hp * 0.2
	w.step()
	w.step()
	assert_eq(_bodies(w), 3)
	var evs: Array[Dictionary] = [
		{"type": "boss", "pos": Vector2(100, 40), "owner": -1, "kind": 4, "in_ticks": 90, "enraged": 1},
		{"type": "boss_phase", "pos": Vector2(100, 40), "owner": -1, "kind": 3},
	]
	var b := SimWorld.new(1)
	assert_true(Snapshot.apply(b, Snapshot.encode(w, evs)))
	var shards: int = 0
	for i in b.enemy_count:
		if b.enemy_kind[i] == SimWorld.BOSS_SHARD:
			shards += 1
	assert_eq(shards, 3)
	assert_eq(b.events.size(), 2)
	assert_eq(int(b.events[0]["in_ticks"]), 90)
	assert_eq(str(b.events[1]["type"]), "boss_phase")
	# a world without a boss still round-trips (no boss block)
	var plain := SimWorld.new(5)
	plain.add_vehicle(1, Vector2(300, 300))
	var c := SimWorld.new(1)
	assert_true(Snapshot.apply(c, Snapshot.encode(plain)))
	assert_eq(c.boss_state, Bosses.ST_NONE)
