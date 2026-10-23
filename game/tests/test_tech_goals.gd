extends TestCase
## The TECH view's own goals (TechGuide, client-side): flags per match, ideas seeding them, the next step
## towards them, and the build's identity from where its scrap went.


func _rig(ids: Array) -> SimVehicle:
	var v := SimVehicle.new(1, 1, Vector2.ZERO)
	v.scrap = 99999
	for id: String in ids:
		for _i in 12:
			if v.tech.has(id):
				break
			assert_true(Tech.buy(v, Tech.next_step(v, id), 1), "buy " + id)
	return v


func test_toggle_and_built_goals_drop_off() -> void:
	var w := SimWorld.new(1)
	var v: SimVehicle = _rig([])
	assert_true(TechGuide.toggle_goal(w, "engineering_war_rig"))
	assert_true(TechGuide.toggle_goal(w, "salvage_hooks"))
	assert_eq(TechGuide.goals(w, v), ["engineering_war_rig", "salvage_hooks"] as Array[String])
	assert_false(TechGuide.toggle_goal(w, "engineering_war_rig"), "second toggle drops it")
	assert_true(Tech.buy(v, "salvage_hooks", 1))
	assert_eq(TechGuide.goals(w, v).size(), 0, "a built goal drops off")
	assert_false(TechGuide.is_goal(SimWorld.new(2), "salvage_hooks"), "goals are per match")


func test_next_step_follows_the_goals_in_order() -> void:
	var v: SimVehicle = _rig(["ballistics_ammo_bench"])
	var g: Array[String] = ["engineering_pickup", "ballistics_tables"]
	assert_eq(TechGuide.next_step(v, g), "engineering_frame", "first goal's first missing step")
	var path: Array[String] = TechGuide.goals_path(v, g)
	assert_eq(path[path.size() - 1], "ballistics_tables")
	assert_true(path.has("engineering_pickup"))
	assert_eq(TechGuide.next_step(v, [] as Array[String]), "", "no goals, no next")


func test_idea_goals_are_its_deepest_nodes_and_fusions() -> void:
	var ig: Array[String] = TechGuide.idea_goals(TechGuide.template_by_id("firebrand"))
	assert_eq(ig, ["ballistics_glowing", "propulsion_phantom", "fusion_burning_wake"] as Array[String])


func test_main_branches_and_idea_like() -> void:
	var v: SimVehicle = _rig([])
	assert_eq(TechGuide.main_branches(v).size(), 0)
	assert_true(TechGuide.idea_like(v).is_empty())
	v = _rig(["ballistics_tables", "propulsion_drift", "propulsion_tuned"])
	var mb: Array[String] = TechGuide.main_branches(v)
	assert_eq(mb[0], "ballistics", "tables path is the most scrap")
	assert_eq(mb[1], "propulsion")
	assert_eq(str(TechGuide.idea_like(v).get("id", "")), "firebrand")
