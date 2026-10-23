extends TestCase
## Weapon range rings: one ring per distinct reach at the sim's own weapon range, labels kept on screen.


func _rig(cards: Dictionary) -> SimVehicle:
	var v := SimVehicle.new(0, 1, Vector2(500, 500))
	for id: String in cards:
		for i in int(cards[id]):
			Cards.grant(v, id)
	Cards.recompute(v)
	return v


func test_one_ring_per_gun_kind_at_its_reach() -> void:
	var v: SimVehicle = _rig({"flamer": 1})
	var rs: Array[Dictionary] = RangeOverlay.rings(v)
	assert_eq(rs.size(), 2, "starter mg and a flamer")
	assert_eq(rs[0]["kinds"], ["flamer"])
	for i in rs.size() - 1:
		assert_lt(float(rs[i]["radius"]), float(rs[i + 1]["radius"]), "smallest first")
	for w in v.weapons:
		var found: bool = false
		for r: Dictionary in rs:
			if (r["kinds"] as Array).has(str(w["kind"])):
				found = float(r["radius"]) >= float(w["range"])
		assert_true(found, "%s ring reaches its range" % w["kind"])


func test_equal_reach_shares_a_ring() -> void:
	var v: SimVehicle = _rig({})
	v.weapons = [{"kind": "mg", "range": 200.0}, {"kind": "shotgun", "range": 201.0}, {"kind": "flamer", "range": 100.0}]
	var rs: Array[Dictionary] = RangeOverlay.rings(v)
	assert_eq(rs.size(), 2)
	assert_eq((rs[1]["kinds"] as Array).size(), 2)
	assert_eq(float(rs[1]["radius"]), 201.0)


func test_no_guns_no_rings() -> void:
	var v: SimVehicle = _rig({})
	v.weapons = []
	assert_eq(RangeOverlay.rings(v).size(), 0)


func test_label_stays_on_screen() -> void:
	var vs := Vector2(640, 360)
	var c := vs / 2.0
	for r: float in [95.0, 170.0, 260.0, 320.0]:
		var a: Vector2 = RangeOverlay.label_anchor(c, r, vs)
		assert_true(a != Vector2.INF, "a spot for r=%s" % r)
		assert_true(Rect2(Vector2.ZERO, vs).has_point(a), "on screen for r=%s" % r)
		assert_lt(absf(a.distance_to(c) - r), 0.5, "on the ring for r=%s" % r)
	assert_eq(RangeOverlay.label_anchor(c, 2000.0, vs), Vector2.INF)
