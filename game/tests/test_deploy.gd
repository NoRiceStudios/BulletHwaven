extends TestCase
## Pre-match deploy phase: doctrine setup before round 1.


func _world(players: int = 1, fast: bool = true) -> SimWorld:
	var w := SimWorld.new(33)
	w.fast_rounds = fast
	for i in players:
		w.add_vehicle(i + 1, Vector2(300.0 + 500.0 * float(i), 360.0))
	w.begin_deploy()
	return w


func _step(w: SimWorld, n: int) -> void:
	for i in n:
		w.step()


func test_plain_world_starts_in_combat() -> void:
	var w := SimWorld.new(1)
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)


func test_begin_deploy_sets_phase_and_duration() -> void:
	var w := SimWorld.new(1)
	w.add_vehicle(1, Vector2(300, 300))
	w.vehicles[0].ready = true
	w.begin_deploy()
	assert_eq(w.phase, SimWorld.PHASE_DEPLOY)
	assert_eq(w.phase_ticks_left, SimWorld.DEPLOY_TICKS)
	assert_false(w.vehicles[0].ready)
	var f := SimWorld.new(1)
	f.fast_rounds = true
	f.begin_deploy()
	assert_eq(f.phase_ticks_left, SimWorld.FAST_DEPLOY_TICKS)
	# fast_rounds set after begin_deploy keeps deploy
	var g := SimWorld.new(1)
	g.begin_deploy()
	g.fast_rounds = true
	assert_eq(g.phase, SimWorld.PHASE_DEPLOY)
	assert_eq(g.phase_ticks_left, SimWorld.FAST_DEPLOY_TICKS)
	var h := SimWorld.new(1)
	h.begin_deploy(5)
	assert_eq(h.phase_ticks_left, 5)
	h.step()
	h.begin_deploy()  # too late: ignored
	assert_eq(h.phase_ticks_left, 4)


func test_nothing_happens_in_deploy() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	var pos: Vector2 = v.pos
	_step(w, SimWorld.FAST_DEPLOY_TICKS - 1)
	assert_eq(w.phase, SimWorld.PHASE_DEPLOY)
	assert_eq(w.enemy_count, 0)
	assert_eq(w.proj_count, 0)
	assert_eq(v.pos, pos)
	assert_eq(w.tick, SimWorld.FAST_DEPLOY_TICKS - 1)


func test_timer_ends_deploy() -> void:
	var w := _world()
	_step(w, SimWorld.FAST_DEPLOY_TICKS)
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(w.round, 1)
	assert_eq(w.phase_ticks_left, w.combat_duration(1))
	assert_eq(w.vehicles[0].invuln_ticks, 0)


func test_ready_skip_single_and_multi() -> void:
	var w := _world()
	w.apply_command(1, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_false(w.vehicles[0].ready)
	var m := _world(2)
	m.apply_command(1, {"type": "ready"})
	_step(m, 3)
	assert_eq(m.phase, SimWorld.PHASE_DEPLOY)
	m.apply_command(2, {"type": "ready"})
	m.step()
	assert_eq(m.phase, SimWorld.PHASE_COMBAT)
	assert_eq(m.round, 1)


func test_doctrine_persists_into_round_one() -> void:
	var w := _world()
	w.apply_command(1, {"type": "set_drive", "value": "charge"})
	w.apply_command(1, {"type": "set_target", "value": "weakest"})
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "IF hp < 30% THEN kite"})
	w.apply_command(1, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.doctrine["drive"], "charge")
	assert_eq(v.doctrine["target"], "weakest")


func test_shop_and_ability_ignored_in_deploy() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 100
	w.apply_command(1, {"type": "reroll"})
	w.apply_command(1, {"type": "pick_card", "value": 0})
	w.apply_command(1, {"type": "buy_tech", "value": "armor_1"})
	w.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(v.scrap, 100)
	assert_eq(v.cards, {"mg": 1})
	assert_false(v.picked)
	assert_eq(w.phase, SimWorld.PHASE_DEPLOY)


func test_snapshot_round_trip_in_deploy() -> void:
	var w := _world(2)
	_step(w, 7)
	var bytes: PackedByteArray = Snapshot.encode(w)
	var r := SimWorld.new(33)
	assert_true(Snapshot.apply(r, bytes))
	assert_eq(r.phase, SimWorld.PHASE_DEPLOY)
	assert_eq(r.phase_ticks_left, w.phase_ticks_left)
	assert_eq(r.round, 1)


func test_net_session_starts_in_deploy() -> void:
	var s := NetSession.new()
	s.world_seed = 5
	s.fast_rounds = true
	s.start_solo("T", 0)
	assert_eq(s.world.phase, SimWorld.PHASE_DEPLOY)
	assert_eq(s.world.phase_ticks_left, SimWorld.FAST_DEPLOY_TICKS)
	s.stop()
	s.free()


func test_determinism() -> void:
	var a := _world(2)
	var b := _world(2)
	for w in [a, b]:
		w.apply_command(1, {"type": "set_drive", "value": "kite"})
		w.apply_command(2, {"type": "ready"})
	for i in 200:
		a.step()
		b.step()
	assert_eq(a.checksum(), b.checksum())
	assert_ne(a.phase, SimWorld.PHASE_DEPLOY)


func test_presets_run_on_a_fresh_rig() -> void:
	for p: Dictionary in DoctrinePresets.LIST:
		var w := _world(1)
		var v: SimVehicle = w.vehicles[0]
		var parsed: Variant = Doctrine.parse(p["rules"], Doctrine.SCOPE_RIG)
		assert_true(parsed is Array, "%s parses" % p["id"])
		assert_true((parsed as Array).size() <= Doctrine.slots(v), "%s fits the base slots" % p["id"])
		assert_true(Doctrine.rules_allowed(v, parsed), "%s needs no tech" % p["id"])
		for cmd in DoctrinePresets.commands(p):
			w.apply_command(1, cmd)
		assert_eq(DoctrinePresets.current(v), p["id"])
		assert_eq(v.rules.size(), (parsed as Array).size())
