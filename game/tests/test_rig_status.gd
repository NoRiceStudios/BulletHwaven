extends TestCase
## The combat RIG panel (render/rig_status.gd): gun dps, the effect list with numbers, ability timers and
## where the panel sits.


func _rig() -> SimVehicle:
	var w := SimWorld.new(5)
	return w.add_vehicle(1, Vector2(1000, 700))


func _row(rows: Array[Dictionary], label: String) -> Dictionary:
	for r in rows:
		if str(r["label"]) == label:
			return r
	return {}


func test_weapon_dps_counts_pellets_rate_and_salvo() -> void:
	var v := _rig()
	var w := {"damage": 5.0, "pellets": 3, "cooldown_ticks": 10.0}
	assert_true(absf(RigStatus.weapon_dps(v, w) - (5.0 * 3.0 * float(SimWorld.TICK_RATE) / 10.0)) < 0.001)
	v.salvo_ticks = 10
	assert_true(absf(RigStatus.weapon_dps(v, w) - (5.0 * 3.0 * float(SimWorld.TICK_RATE) * (1.0 + Abilities.SALVO_RATE) / 10.0)) < 0.001)


func test_starting_rig_has_one_gun_and_no_effects() -> void:
	var v := _rig()
	assert_eq(v.weapons.size(), 1)
	assert_true(RigStatus.weapon_dps(v, v.weapons[0]) > 0.0)
	assert_eq(RigStatus.effects(v).size(), 0)
	assert_eq(RigStatus.timers(v).size(), 0)


func test_regenerator_shows_repair_per_second() -> void:
	var v := _rig()
	Cards.grant(v, "regenerator")
	Cards.grant(v, "regenerator")
	var r: Dictionary = _row(RigStatus.effects(v), "REPAIR")
	assert_false(r.is_empty(), "repair row")
	assert_eq(str(r["value"]), "+5 HP/S")
	assert_true(bool(r.get("heal", false)))


func test_timers_show_seconds_left() -> void:
	var v := _rig()
	v.nitro_ticks = 30
	v.rules_off_ticks = 45
	var t: Array[Dictionary] = RigStatus.timers(v)
	assert_eq(t.size(), 2)
	assert_eq(str(t[0]["label"]), "EMP'D", "bad news first")
	assert_true(bool(t[0]["bad"]))
	assert_eq(int(_row(t, "NITRO")["left"]), 30)


func test_panel_sits_under_the_standings() -> void:
	var w := SimWorld.new(5)
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	assert_true(absf(RigStatus.panel_rect(w, a).position.y - (RigStatus.MARGIN)) < 0.001)
	w.add_vehicle(2, Vector2(1200, 700))
	var r: Rect2 = RigStatus.panel_rect(w, a)
	assert_true(absf(r.position.y - (RigStatus.MARGIN + 18.0 + 20.0 + RigStatus.GAP)) < 0.001)
	Cards.grant(a, "regenerator")
	assert_true(RigStatus.panel_rect(w, a).size.y > r.size.y, "an effect row makes it taller")
