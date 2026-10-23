extends TestCase
## Radio commands (sim/orders.gd): effects, priority over rules, expiry, charges, lock, refill, juggernaut,
## phases, snapshot, determinism, validation.

const JUGG: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_battering", "propulsion_turbine", "propulsion_juggernaut"]


func _world(rules: String = "hp>0|drive:circle", p_seed: int = 5) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": rules})
	return w


func _radio(w: SimWorld, id: String) -> void:
	w.apply_command(1, {"type": "radio", "value": id})


func _wait_lock(w: SimWorld) -> void:
	for i in Orders.RADIO_LOCK_TICKS:
		w.step()


func test_defaults() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.radio_charges, 3)
	assert_eq(v.radio_cmd, -1)
	assert_false(Orders.radio_active(v))
	assert_eq(Orders.radio_id(v), "")
	assert_eq(Orders.RADIO_IDS, PackedStringArray(["fall_back", "all_in", "hold", "boss"]))


func test_effects_beat_matching_rule() -> void:
	var w := _world("hp>0|drive:kite;hp>0|target:weakest")
	var v: SimVehicle = w.vehicles[0]
	w.step()
	assert_eq(v.eff_drive, "kite")
	assert_eq(v.eff_target, "weakest")
	_radio(w, "fall_back")
	w.step()
	assert_eq(v.eff_drive, "flee")
	assert_eq(Orders.radio_id(v), "fall_back")
	assert_eq(v.eff_target, "weakest")
	_wait_lock(w)
	_radio(w, "all_in")
	w.step()
	assert_eq(v.eff_drive, "charge")
	assert_true(v.focus)
	_wait_lock(w)
	_radio(w, "hold")
	w.step()
	assert_eq(v.eff_drive, "hold")
	assert_eq(v.radio_charges, 0)


func test_boss_command_and_retarget() -> void:
	var w := _world("hp>0|target:weakest")
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(200.0, 0.0))
	w.rebuild_derived()
	w.step()
	assert_eq(v.acquired_mode, "weakest")
	_radio(w, "boss")
	w.step()
	assert_eq(v.eff_target, "boss")
	assert_eq(v.acquired_mode, "boss", "re-targets at once")
	assert_true(v.focus)
	assert_eq(v.radio_cmd, 3)
	assert_eq(v.radio_ticks, Orders.RADIO_TICKS - 1)


func test_mark_still_overrides_target() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(200.0, 0.0))
	w.rebuild_derived()
	var id: int = w.enemy_id[w.enemy_count - 1]
	w.enemy_hp[w.enemy_count - 1] = 5000.0
	w.apply_command(1, {"type": "mark", "x": v.pos.x + 200.0, "y": v.pos.y})
	_radio(w, "boss")
	w.step()
	assert_eq(v.target_id, id)


func test_expiry() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_radio(w, "hold")
	for i in Orders.RADIO_TICKS - 1:
		w.step()
	assert_true(Orders.radio_active(v))
	w.step()
	assert_false(Orders.radio_active(v))
	w.step()
	assert_eq(v.eff_drive, "circle")
	assert_eq(v.radio_charges, 2)


func test_three_charges_then_refused() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	for i in 3:
		_radio(w, "hold")
		assert_eq(v.radio_charges, 2 - i)
		_wait_lock(w)
	_radio(w, "all_in")
	assert_eq(v.radio_charges, 0)
	assert_eq(v.radio_cmd, 2, "refused call changes nothing")


func test_lock_and_replace() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_radio(w, "hold")
	_radio(w, "all_in")
	assert_eq(v.radio_charges, 2, "lock blocks the immediate second call")
	assert_eq(v.radio_cmd, 2)
	_wait_lock(w)
	_radio(w, "all_in")
	assert_eq(v.radio_charges, 1)
	assert_eq(v.radio_cmd, 1)
	assert_eq(v.radio_ticks, Orders.RADIO_TICKS, "replaced, timer restarts")
	var ev: Array = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "radio")
	assert_eq(ev.size(), 1)
	assert_eq(int(ev[0]["kind"]), 1)
	assert_eq(int(ev[0]["owner"]), v.id)


func test_invalid_id_and_dead() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_radio(w, "bogus")
	w.apply_command(1, {"type": "radio", "value": 3})
	w.apply_command(1, {"type": "radio"})
	assert_eq(v.radio_charges, 3)
	_radio(w, "hold")
	v.hp = 0.0
	v.alive = false
	v.respawn_ticks = 9999
	_wait_lock(w)
	_radio(w, "hold")
	assert_eq(v.radio_charges, 2, "no call while dead")


func test_death_clears_ticks_respawn_keeps_charges() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_radio(w, "hold")
	v.hp = 0.0
	w._damage_vehicle(v, 1.0, -1, false, SimWorld.SRC_MITE)
	assert_false(v.alive)
	assert_eq(v.radio_ticks, 0)
	w._respawn(v)
	assert_eq(v.radio_charges, 2)
	assert_eq(v.radio_cmd, -1)
	assert_eq(v.radio_lock, 0)


func test_refill_next_combat_and_phases() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_radio(w, "hold")
	_wait_lock(w)
	_radio(w, "hold")
	assert_eq(v.radio_charges, 1)
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_false(Orders.radio_active(v))
	_radio(w, "hold")
	assert_eq(v.radio_charges, 1, "ignored in the workshop")
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(v.radio_charges, 3)


func test_deploy_ignored_and_filled() -> void:
	var w := SimWorld.new(2)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	w.begin_deploy()
	assert_eq(w.phase, SimWorld.PHASE_DEPLOY)
	_radio(w, "hold")
	assert_eq(v.radio_charges, 3)
	assert_eq(v.radio_cmd, -1)
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(v.radio_charges, 3)


func test_juggernaut_fall_back_holds() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	v.scrap = 99999
	for id: String in JUGG:
		assert_true(Tech.buy(v, id, 1), "buy " + id)
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	_radio(w, "fall_back")
	w.step()
	assert_eq(v.eff_drive, "hold")


func test_condition_radio_active() -> void:
	var w := _world("radio_active=1|drive:charge;hp>0|drive:circle")
	var v: SimVehicle = w.vehicles[0]
	assert_true(Doctrine.COND_IDS.has("radio_active"))
	w.step()
	assert_eq(v.eff_drive, "circle")
	_radio(w, "boss")
	w.step()
	assert_eq(v.eff_drive, "charge")


func test_snapshot_round_trip() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_radio(w, "all_in")
	for i in 40:
		w.step()
	var w2 := SimWorld.new(1)
	assert_true(Snapshot.apply(w2, Snapshot.encode(w)))
	var v2: SimVehicle = w2.vehicles[0]
	assert_eq(v2.radio_charges, 2)
	assert_eq(v2.radio_ticks, v.radio_ticks)
	assert_eq(v2.radio_cmd, 1)
	assert_eq(v2.radio_lock, 0)
	assert_eq(Snapshot.VERSION, 17)
	assert_true(Snapshot.EVENT_TYPES.has("radio"))
	_radio(w, "hold")
	var w3 := SimWorld.new(1)
	assert_true(Snapshot.apply(w3, Snapshot.encode(w)))
	assert_eq(w3.vehicles[0].radio_lock, v.radio_lock)


func test_determinism() -> void:
	var sums: Array[int] = []
	for run in 2:
		var w := SimWorld.new(21)
		w.spawning_enabled = true
		var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
		v.max_hp = 1.0e6
		v.hp = 1.0e6
		for t in 500:
			if t % 70 == 5:
				w.apply_command(1, {"type": "radio", "value": Orders.RADIO_IDS[(t / 70) % 4]})
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])


func test_validation() -> void:
	assert_eq(NetSession.validate_command({"type": "radio", "value": "boss"}), {"type": "radio", "value": "boss"})
	assert_eq(NetSession.validate_command({"type": "radio", "value": "nope"}), {})
	assert_eq(NetSession.validate_command({"type": "radio", "value": 1}), {})
	assert_eq(NetSession.validate_command({"type": "radio"}), {})
