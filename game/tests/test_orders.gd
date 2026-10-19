extends TestCase
## Live order "target mark" (sim/orders.gd): cast / miss / cooldown, forced rig target and gun focus,
## end on target death, rivals only with PvP, phases, round reset, snapshot, determinism, validation.

func _world(p_seed: int = 3) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


func _enemy(w: SimWorld, kind: int, dx: float, dy: float = 0.0, hp: float = 5000.0) -> int:
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(kind, v.pos + Vector2(dx, dy))
	var i: int = w.enemy_count - 1
	w.enemy_hp[i] = hp
	w.rebuild_derived()
	return w.enemy_id[i]


func _index(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1


func _mark(w: SimWorld, p: Vector2) -> void:
	w.apply_command(1, {"type": "mark", "x": p.x, "y": p.y})


func _duel() -> SimWorld:
	var w := SimWorld.new(9)
	w.spawning_enabled = false
	w.round = 4
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	var b: SimVehicle = w.add_vehicle(2, Vector2(1150, 700))
	for v: SimVehicle in [a, b]:
		v.max_hp = 1.0e6
		v.hp = 1.0e6
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	w.apply_command(2, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


func test_cast_hits_nearest_in_radius() -> void:
	var w := _world()
	var far_id: int = _enemy(w, SimWorld.MITE, 200.0, 20.0)
	var near_id: int = _enemy(w, SimWorld.MITE, 210.0, 0.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(214.0, 4.0))
	assert_eq(v.mark_order_id, near_id)
	assert_ne(v.mark_order_id, far_id)
	assert_eq(v.mark_order_kind, 1)
	assert_eq(v.mark_order_ticks, Orders.MARK_TICKS)
	assert_eq(v.mark_order_cd, Orders.MARK_COOLDOWN)
	var ev: Array = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "mark")
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0]["owner"]), v.id)
	assert_eq(int(ev[0]["kind"]), SimWorld.MITE)


func test_miss_sets_no_cooldown() -> void:
	var w := _world()
	_enemy(w, SimWorld.MITE, 200.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(200.0, 100.0))  # 100 px from the alien
	assert_eq(v.mark_order_cd, 0)
	assert_eq(v.mark_order_ticks, 0)
	_enemy(w, SimWorld.MITE, 700.0)  # in pick radius but beyond MARK_MAX_DIST
	_mark(w, v.pos + Vector2(700.0, 0.0))
	assert_eq(v.mark_order_cd, 0)


func test_cooldown_blocks_second_cast() -> void:
	var w := _world()
	var a: int = _enemy(w, SimWorld.MITE, 200.0)
	var b: int = _enemy(w, SimWorld.MITE, 0.0, 250.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(200.0, 0.0))
	assert_eq(v.mark_order_id, a)
	for i in 10:
		w.step()
	_mark(w, v.pos + Vector2(0.0, 250.0))
	assert_eq(v.mark_order_id, a, "blocked while cooling down")
	for i in Orders.MARK_COOLDOWN:
		w.step()
	assert_eq(v.mark_order_cd, 0)
	_mark(w, w.enemy_pos[_index(w, b)])
	assert_eq(v.mark_order_id, b)


func test_rig_and_weapons_follow_mark() -> void:
	var w := _world()
	var near_id: int = _enemy(w, SimWorld.MITE, 120.0)
	var far_id: int = _enemy(w, SimWorld.BOULDER, -300.0, 0.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(-300.0, 0.0))
	assert_eq(v.mark_order_id, far_id)
	for i in 5:
		w.step()
		assert_true(Orders.active(w, v))
		assert_eq(v.target_kind, 1)
		assert_eq(v.target_id, far_id, "rig target is the mark, not the nearer mite")
		assert_eq(v.target_index, _index(w, far_id))
		assert_true(v.focus)
		for wp: Dictionary in v.weapons:
			assert_eq(int(wp.get("tk", 0)), 0, "guns follow the rig target")
	assert_true(Orders.target_pos(w, v).distance_to(w.enemy_pos[_index(w, far_id)]) < 0.01)
	assert_ne(near_id, far_id)


func test_mark_ends_on_target_death() -> void:
	var w := _world()
	var id: int = _enemy(w, SimWorld.MITE, 150.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(150.0, 0.0))
	w.step()
	assert_true(Orders.active(w, v))
	w.enemy_hp[_index(w, id)] = 0.0
	w.step()
	assert_eq(v.mark_order_ticks, 0)
	assert_false(Orders.active(w, v))
	assert_gt(float(v.mark_order_cd), 0.0, "the cooldown keeps running")


func test_mark_expires() -> void:
	var w := _world()
	_enemy(w, SimWorld.BOULDER, 150.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(150.0, 0.0))
	for i in Orders.MARK_TICKS - 1:
		w.step()
	assert_true(Orders.active(w, v))
	w.step()
	assert_false(Orders.active(w, v))


func test_rival_mark_needs_pvp() -> void:
	var w := _duel()
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.invuln_ticks = 0
	b.invuln_ticks = 0
	w.pvp_grace_ticks = 100
	w.apply_command(1, {"type": "mark", "x": b.pos.x, "y": b.pos.y})
	assert_eq(a.mark_order_cd, 0, "no rival mark during the PvP grace")
	w.pvp_grace_ticks = 0
	w.apply_command(1, {"type": "mark", "x": b.pos.x + 5.0, "y": b.pos.y})
	assert_eq(a.mark_order_kind, 2)
	assert_eq(a.mark_order_id, b.id)
	var ev: Array = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "mark")
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0]["kind"]), -1)
	w.step()
	assert_eq(a.target_kind, 2)
	assert_eq(a.target_id, b.id)
	assert_true(a.focus)


func test_ignored_outside_combat() -> void:
	var w := _world()
	_enemy(w, SimWorld.MITE, 150.0)
	var v: SimVehicle = w.vehicles[0]
	for ph: int in [SimWorld.PHASE_WORKSHOP, SimWorld.PHASE_DEPLOY]:
		w.phase = ph
		_mark(w, v.pos + Vector2(150.0, 0.0))
		assert_eq(v.mark_order_cd, 0)
		assert_eq(v.mark_order_ticks, 0)


func test_cleared_at_round_start_and_respawn() -> void:
	var w := _world()
	_enemy(w, SimWorld.BOULDER, 150.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(150.0, 0.0))
	w.phase = SimWorld.PHASE_WORKSHOP
	w._begin_combat()
	assert_eq(v.mark_order_ticks, 0)
	assert_eq(v.mark_order_cd, 0)
	_enemy(w, SimWorld.BOULDER, 150.0)
	_mark(w, v.pos + Vector2(150.0, 0.0))
	assert_gt(float(v.mark_order_ticks), 0.0)
	w._respawn(v)
	assert_eq(v.mark_order_ticks, 0)
	assert_eq(v.mark_order_cd, 0)


func test_mark_active_condition() -> void:
	assert_true(Doctrine.COND_IDS.has("mark_active"))
	assert_true(Doctrine.CONDS.has("mark_active"))
	assert_true(Doctrine.parse("mark_active=1|drive:charge", "rig") != null)
	var w := _world()
	_enemy(w, SimWorld.BOULDER, 200.0)
	var v: SimVehicle = w.vehicles[0]
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "mark_active=1|drive:charge"})
	w.step()
	assert_ne(v.eff_drive, "charge")
	_mark(w, v.pos + Vector2(200.0, 0.0))
	w.step()
	assert_eq(v.eff_drive, "charge")


func test_snapshot_round_trip() -> void:
	var w := _world()
	var id: int = _enemy(w, SimWorld.MITE, 150.0)
	var v: SimVehicle = w.vehicles[0]
	_mark(w, v.pos + Vector2(150.0, 0.0))
	for i in 7:
		w.step()
	var bytes: PackedByteArray = Snapshot.encode(w)
	var w2 := SimWorld.new(1)
	assert_true(Snapshot.apply(w2, bytes))
	var v2: SimVehicle = w2.vehicles[0]
	assert_eq(v2.mark_order_ticks, v.mark_order_ticks)
	assert_eq(v2.mark_order_cd, v.mark_order_cd)
	assert_eq(v2.mark_order_kind, 1)
	assert_eq(v2.mark_order_id, id)
	assert_eq(Snapshot.VERSION, 17)
	assert_true(Snapshot.EVENT_TYPES.has("mark"))


func test_determinism() -> void:
	var sums: Array[int] = []
	for run in 2:
		var w := SimWorld.new(21)
		w.spawning_enabled = true
		var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
		v.max_hp = 1.0e6
		v.hp = 1.0e6
		for t in 400:
			if t % 40 == 5 and w.enemy_count > 0:
				w.apply_command(1, {"type": "mark", "x": w.enemy_pos[0].x, "y": w.enemy_pos[0].y})
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])


func test_validate_command() -> void:
	var ok: Dictionary = NetSession.validate_command({"type": "mark", "x": 100, "y": 200.5})
	assert_eq(ok.get("type"), "mark")
	assert_eq(ok.get("x"), 100.0)
	assert_eq(ok.get("y"), 200.5)
	assert_false(NetSession.validate_command({"type": "mark", "x": -60.0, "y": 10.0}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": -70.0, "y": 10.0}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": 100.0, "y": 1600.0}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": NAN, "y": 10.0}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": INF, "y": 10.0}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": "5", "y": 10.0}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": 5}).is_empty())
	assert_true(NetSession.validate_command({"type": "mark", "x": null, "y": 5}).is_empty())
