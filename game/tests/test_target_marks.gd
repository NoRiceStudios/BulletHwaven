extends TestCase
## Target marks: every gun records what it is on (after the fallback to the rig's target), the
## snapshot carries it, and render/target_marks.gd groups the guns by target.


## A rig with an mg (follows the rig: nearest) and a cannon on the strongest, a mite close by and a
## boulder farther out.
func _world() -> SimWorld:
	var w := SimWorld.new(7)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1280, 720))
	Cards.grant(v, "cannon")
	Cards.recompute(v)
	w.apply_command(1, {"type": "set_drive", "value": "circle"})
	w.apply_command(1, {"type": "set_weapon_target", "scope": "cannon", "value": "strongest"})
	w.spawn_enemy(SimWorld.MITE, Vector2(1340, 720))
	w.spawn_enemy(SimWorld.BOULDER, Vector2(1280, 800))
	return w


func _gun(v: SimVehicle, kind: String) -> Dictionary:
	for wp in v.weapons:
		if str(wp["kind"]) == kind:
			return wp
	return {}


func test_each_gun_records_its_target() -> void:
	var w: SimWorld = _world()
	var v: SimVehicle = w.vehicles[0]
	w.step()  # two ticks: the mite still lives
	w.step()
	assert_eq(v.target_kind, 1, "the rig is on an alien")
	var mg: Dictionary = _gun(v, "mg")
	var cannon: Dictionary = _gun(v, "cannon")
	assert_eq(int(mg["ak"]), 1)
	assert_eq(int(mg["aid"]), v.target_id, "the mg follows the rig's target")
	assert_eq(int(w.enemy_kind[_index(w, int(mg["aid"]))]), SimWorld.MITE)
	assert_eq(int(cannon["ak"]), 1)
	assert_eq(int(w.enemy_kind[_index(w, int(cannon["aid"]))]), SimWorld.BOULDER, "the cannon is on the strongest")
	assert_true((cannon["ap"] as Vector2).distance_to(Vector2(1280, 800)) < 20.0, "position recorded")


func test_no_target_clears_the_mark() -> void:
	var w := SimWorld.new(3)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1280, 720))
	for t in 3:
		w.step()
	assert_eq(int(v.weapons[0].get("ak", -1)), 0)
	assert_true(TargetMarks.groups(v).is_empty())


func test_snapshot_carries_gun_targets() -> void:
	var w: SimWorld = _world()
	for t in 3:
		w.step()
	var c := SimWorld.new(1)
	c.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c, Snapshot.encode(w)), "applies")
	var v: SimVehicle = w.vehicles[0]
	var cv: SimVehicle = c.vehicles[0]
	for i in v.weapons.size():
		assert_eq(int(cv.weapons[i]["ak"]), int(v.weapons[i]["ak"]))
		assert_eq(int(cv.weapons[i]["aid"]), int(v.weapons[i]["aid"]))
		assert_true((cv.weapons[i]["ap"] as Vector2).distance_to(v.weapons[i]["ap"]) < 0.01)


func test_groups_share_targets_and_flag_reach() -> void:
	var v := SimVehicle.new(0, 1, Vector2.ZERO)
	v.weapons = [
		{"kind": "mg", "range": 200.0, "ak": 1, "aid": 5, "ap": Vector2(100, 0)},
		{"kind": "cannon", "range": 300.0, "ak": 1, "aid": 9, "ap": Vector2(0, 250)},
		{"kind": "shotgun", "range": 80.0, "ak": 1, "aid": 5, "ap": Vector2(100, 0)},
		{"kind": "flamer", "range": 60.0, "ak": 0, "aid": -1, "ap": Vector2.ZERO},
	]
	var g: Array[Dictionary] = TargetMarks.groups(v)
	assert_eq(g.size(), 2, "two targets, the idle flamer left out")
	assert_eq(g[0]["guns"], [0, 2], "mg and shotgun share the mite")
	assert_eq(g[0]["reach"], [true, false], "the shotgun is out of reach")
	assert_eq(g[1]["guns"], [1])
	assert_eq(g[1]["reach"], [true])


func _index(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1
