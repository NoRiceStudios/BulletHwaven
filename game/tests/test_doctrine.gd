extends TestCase
## Programmable behaviour: IF-THEN rules for the rig and per weapon (Doctrine).


func _world(players: int = 1) -> SimWorld:
	var w := SimWorld.new(31)
	w.spawning_enabled = false
	for i in players:
		w.add_vehicle(i + 1, Vector2(400.0 + 400.0 * float(i), 400.0))
	return w


func _rules(w: SimWorld, scope: String, text: String, peer: int = 1) -> void:
	w.apply_command(peer, {"type": "set_rules", "scope": scope, "value": text})


func test_parse_and_encode_roundtrip() -> void:
	var text := "hp<30|drive:flee;swarm>20&t_dist<120|drive:charge;t_player=1|target:players_first;|drive:kite"
	var r: Variant = Doctrine.parse(text, Doctrine.SCOPE_RIG)
	assert_true(r != null, "valid rig rules parse")
	assert_eq((r as Array).size(), 4)
	assert_eq(Doctrine.encode(r), text, "canonical text survives a roundtrip")
	assert_eq(((r as Array)[3]["if"] as Array).size(), 0, "no condition = always")
	var wr: Variant = Doctrine.parse("t_boulder=1|fire:hold;t_hp<40|target:weakest", "cannon")
	assert_true(wr != null, "valid weapon rules parse")
	assert_eq(Doctrine.parse("", "mg"), [], "empty list")
	for bad in [
		"hp<30|drive:fly",  # unknown action
		"hp<30|fire:hold",  # weapon action on the rig
		"mana<3|drive:kite",  # unknown condition
		"hp<300|drive:kite",  # out of range
		"t_player=2|drive:kite",  # flag must be 0 / 1
		"hp=30|drive:kite",  # numeric needs < or >
		"hp<30&hp<20&hp<10&hp<5&hp<1|drive:kite",  # too many conditions
		"hp<30drive:kite",  # no separator
		"|drive:kite;|drive:kite;|drive:kite;|drive:kite;|drive:kite;|drive:kite;|drive:kite",  # > MAX_SLOTS
	]:
		assert_eq(Doctrine.parse(bad, Doctrine.SCOPE_RIG), null, "rejects %s" % bad)
	assert_eq(Doctrine.parse("|drive:kite", "mg"), null, "drive action on a weapon")
	assert_eq(Doctrine.parse("|target:follow", Doctrine.SCOPE_RIG), null, "follow is weapon-only")


func test_validate_commands() -> void:
	var ok: Dictionary = NetSession.validate_command({"type": "set_rules", "scope": "rig", "value": " hp<30 | drive:flee "})
	assert_eq(ok, {"type": "set_rules", "scope": "rig", "value": "hp<30|drive:flee"}, "canonicalised")
	assert_eq(NetSession.validate_command({"type": "set_rules", "scope": "laser", "value": ""}), {}, "unknown scope")
	assert_eq(NetSession.validate_command({"type": "set_rules", "scope": "rig", "value": "x"}), {}, "garbage")
	assert_eq(NetSession.validate_command({"type": "set_rules", "scope": "rig", "value": 3}), {}, "not a string")
	assert_eq(NetSession.validate_command({"type": "set_weapon_target", "scope": "mg", "value": "boulders"}),
		{"type": "set_weapon_target", "scope": "mg", "value": "boulders"})
	assert_eq(NetSession.validate_command({"type": "set_weapon_target", "scope": "rig", "value": "boulders"}), {}, "rig has no weapon target")
	assert_eq(NetSession.validate_command({"type": "set_target", "value": "weakest"}), {"type": "set_target", "value": "weakest"}, "new base target modes")


func test_rig_rule_overrides_drive_and_reports_live() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_rules(w, "rig", "hp<30|drive:flee;|target:weakest")
	assert_eq(v.rules.size(), 2)
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(120, 0))
	w.step()
	assert_eq(v.eff_drive, "circle", "healthy: base drive")
	assert_eq(v.eff_target, "weakest", "unconditional rule always applies")
	assert_eq(v.rule_live, 2, "only rule 2 matched")
	v.hp = v.max_hp * 0.2
	w.step()
	assert_eq(v.eff_drive, "flee", "low hp: flee")
	assert_eq(v.rule_live, 3)
	for i in 45:
		w.step()
	var away: Vector2 = (v.pos - w.enemy_pos[0]).normalized()
	assert_gt(v.vel.normalized().dot(away), 0.3, "fleeing drives away from the target")


func test_first_matching_rule_wins_per_group() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_rules(w, "rig", "hp>50|drive:kite;|drive:charge")
	w.step()
	assert_eq(v.eff_drive, "kite", "top rule wins")
	v.hp = v.max_hp * 0.4
	w.step()
	assert_eq(v.eff_drive, "charge", "falls through to the next rule")


func test_rule_slots_follow_electronics() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	assert_eq(Doctrine.slots(v), Doctrine.BASE_SLOTS)
	_rules(w, "rig", "|target:nearest;|target:nearest;|drive:kite")
	assert_eq(v.rules.size(), 3, "stored beyond the slots")
	w.step()
	assert_eq(v.eff_drive, "circle", "third rule is locked")
	v.tech.append("electronics_rangefinder")
	Cards.recompute(v)
	assert_eq(Doctrine.slots(v), Doctrine.BASE_SLOTS + 1)
	w.step()
	assert_eq(v.eff_drive, "kite", "unlocked by Electronics")


func test_weapon_hold_fire() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(150, 0))
	_rules(w, "mg", "t_boulder=1|fire:hold")
	for i in 30:
		w.step()
	assert_eq(w.proj_count, 0, "mg holds fire at boulders")
	assert_eq(int(v.weapons[0]["live"]), 1, "weapon rule reported live")
	_rules(w, "mg", "t_boulder=0|fire:hold")
	for i in 30:
		w.step()
	assert_gt(float(w.proj_count), 0.0, "fires once the rule no longer matches")


func test_weapons_pick_their_own_targets() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	Cards.grant(v, "cannon")
	assert_eq(v.weapons.size(), 2)
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(80, 0))
	w.spawn_enemy(SimWorld.SPITTER, v.pos + Vector2(-200, 0))
	w.apply_command(1, {"type": "set_weapon_target", "scope": "cannon", "value": "spitters"})
	assert_eq(Doctrine.weapon_doc(v, "cannon")["target"], "spitters")
	w.step()
	w.step()  # the spatial hash holds new aliens from the next tick on
	var mg: Dictionary = v.weapons[0]
	var cannon: Dictionary = v.weapons[1]
	assert_eq(v.target_kind, 1)
	assert_eq(w.enemy_kind[v.target_index], SimWorld.BOULDER, "rig targets the nearest alien")
	assert_eq(int(mg.get("tk", 0)), 0, "mg follows the rig")
	assert_eq(int(cannon["tk"]), 1, "cannon has its own target")
	assert_eq(w.enemy_kind[int(cannon["ti"])], SimWorld.SPITTER, "cannon aims at the spitter")
	assert_gt(absf(angle_difference(float(mg["aim"]), float(cannon["aim"]))), 2.0, "turrets point different ways")
	# A rule can send it back to the rig's target.
	_rules(w, "cannon", "|target:follow")
	w.step()
	assert_eq(int(cannon["tk"]), 0, "rule: follow")


func test_weapon_falls_back_when_nothing_matches() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(100, 0))
	w.apply_command(1, {"type": "set_weapon_target", "scope": "mg", "value": "spitters"})
	var guard: int = 0
	while w.proj_count == 0 and guard < 20:
		w.step()
		guard += 1
	assert_gt(float(w.proj_count), 0.0, "no spitter around: shoots the nearest alien instead of idling")


func test_doctrine_survives_card_changes_and_snapshots() -> void:
	var host := _world(2)
	var v: SimVehicle = host.vehicles[0]
	_rules(host, "rig", "hp<40&swarm>10|drive:flee")
	_rules(host, "mg", "t_hp<30|target:weakest;t_player=1|fire:hold")
	host.apply_command(1, {"type": "set_weapon_target", "scope": "mg", "value": "strongest"})
	Cards.grant(v, "shotgun")
	Cards.grant(v, "mg")
	assert_eq(Doctrine.encode(Doctrine.weapon_doc(v, "mg")["rules"]), "t_hp<30|target:weakest;t_player=1|fire:hold", "rules kept across recompute")
	host.spawn_enemy(SimWorld.MITE, v.pos + Vector2(80, 0))
	for i in 5:
		host.step()
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)), "snapshot applies")
	var c: SimVehicle = client.vehicles[0]
	assert_eq(Doctrine.fingerprint(c), Doctrine.fingerprint(v), "rules and weapon doctrine synced")
	assert_eq(c.rule_live, v.rule_live)
	assert_eq(int(c.weapons[0]["live"]), int(v.weapons[0]["live"]))
	assert_eq(Doctrine.fingerprint(client.vehicles[1]), "", "other rig: nothing programmed")


func test_rules_are_deterministic() -> void:
	var sums: Array[int] = []
	for run in 2:
		var w := SimWorld.new(77)
		w.add_vehicle(1, Vector2(400, 400))
		w.add_vehicle(2, Vector2(800, 400))
		Cards.grant(w.vehicles[0], "cannon")
		_rules(w, "rig", "swarm>8|drive:kite;hp<50|drive:flee;|target:strongest")
		_rules(w, "cannon", "t_dist<100|fire:hold;|target:weakest")
		_rules(w, "rig", "t_dist>150|drive:charge", 2)
		for i in 600:
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1], "same seed, same rules, same world")


func test_editor_edits_through_commands() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	Cards.grant(v, "cannon")
	var ed := DoctrineEditor.new()
	ed.world = w
	ed.local_peer = 1
	ed.send_command = func(cmd: Dictionary) -> void: w.apply_command(1, NetSession.validate_command(cmd))
	ed.open("rig")
	ed.activate("template", "swarm>20|drive:kite")
	ed.activate("add_rule", null)
	assert_eq(Doctrine.encode(v.rules), "swarm>20|drive:kite;hp<30|drive:flee")
	ed.activate("up", 1)
	ed.activate("inc", [0, 0])
	ed.activate("op", [0, 0])
	assert_eq(Doctrine.encode(v.rules), "hp>40|drive:flee;swarm>20|drive:kite", "reorder, step, flip")
	ed.activate("add_rule", null)
	assert_eq(v.rules.size(), 2, "slots full: nothing added")
	ed.activate("action", 1)
	ed.activate("menu_pick", "target:weakest")
	ed.activate("add_cond", 1)
	ed.activate("menu_pick", "t_player")
	assert_eq(Doctrine.encode(v.rules), "hp>40|drive:flee;swarm>20&t_player=1|target:weakest")
	ed.activate("cond", [1, 0])
	ed.activate("menu_pick", "")
	ed.activate("delete", 0)
	assert_eq(Doctrine.encode(v.rules), "t_player=1|target:weakest", "remove condition, delete rule")
	ed.activate("tab", "cannon")
	assert_eq(ed.scope, "cannon")
	ed.activate("weapon_target", "boulders")
	ed.activate("template", "t_boulder=1|fire:hold")
	assert_eq(Doctrine.fingerprint(v), "t_player=1|target:weakest#cannon:boulders:t_boulder=1|fire:hold")
	ed.activate("tab", "flamer")
	assert_eq(ed.scope, "rig", "a gun the rig does not own falls back to the rig tab")
	assert_eq(DoctrineEditor.sentence(Doctrine.parse("hp<30&t_player=0|drive:flee", "rig")[0], "rig"),
		"IF OWN HP IS BELOW 30% AND THE TARGET IS NOT A RIVAL: THE RIG FLEES.")
	ed.free()


func test_condition_masks_rig_weapon_snapshot() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_rules(w, "rig", "hp<50&swarm>3|drive:flee;swarm>0|target:weakest")
	_rules(w, "mg", "t_boulder=0&t_player=1|fire:hold;t_boulder=0|target:weakest")
	v.hp = v.max_hp * 0.4
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(60, 0))
	w.step()
	w.step()
	var m: int = Doctrine.MAX_CONDS
	assert_eq(v.rule_conds & 15, 1, "rule 0: hp<50 holds, swarm>3 not")
	assert_eq((v.rule_conds >> m) & 15, 1, "rule 1: swarm>0 holds")
	assert_eq(v.rule_live, 2, "rule 0 not live, rule 1 live")
	var wp: Dictionary = v.weapons[0]
	assert_eq(int(wp["clive"]) & 15, 1, "weapon rule 0: only t_boulder=0")
	assert_eq((int(wp["clive"]) >> m) & 15, 1, "weapon rule 1")
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(w)))
	assert_eq(client.vehicles[0].rule_conds, v.rule_conds, "rule_conds synced")
	assert_eq(int(client.vehicles[0].weapons[0]["clive"]), int(wp["clive"]), "clive synced")
	v.rules_off_ticks = 30
	w.step()
	assert_eq(v.rule_conds, 0, "EMP: no bits")
	assert_eq(v.rule_live, 0)
	assert_eq(int(v.weapons[0]["clive"]), 0, "EMP: weapon rules off too")


# ---------------------------------------------------------------- rule options, new conditions, priority lists

func _unlock_logic(v: SimVehicle) -> void:
	v.tech_fx["logic_any"] = 1.0
	v.tech_fx["logic_hold"] = 1.0
	v.tech_fx["prio_weapon"] = 1.0
	v.tech_fx["cond_under_fire"] = 1.0
	v.tech_fx["cond_round_time"] = 1.0
	v.tech_fx["max_conds"] = 1.0


func test_rule_options_text_roundtrip() -> void:
	var text := "-hp<30/swarm>20|drive:flee@2;hp<30&swarm>20|drive:kite;|target:priority;-|drive:hold@5"
	var r: Variant = Doctrine.parse(text, Doctrine.SCOPE_RIG)
	assert_true(r != null, "option syntax parses")
	var rules: Array = r
	assert_true(Doctrine.rule_off(rules[0]) and Doctrine.rule_any(rules[0]) and Doctrine.rule_hold(rules[0]) == 2)
	assert_false(Doctrine.rule_any(rules[1]) or Doctrine.rule_off(rules[1]))
	assert_eq(Doctrine.rule_hold(rules[1]), 0)
	assert_eq(Doctrine.encode(rules), text, "round trip")
	assert_eq(Doctrine.encode(Doctrine.parse("hp<30|drive:flee@0", "rig")), "hp<30|drive:flee", "@0 is dropped")
	assert_false(Doctrine.rule_any(Doctrine.parse("hp<30|drive:flee", "rig")[0]), "any needs >= 2 conditions")
	for bad in ["hp<30&swarm>2/t_dist<5|drive:flee", "hp<30|drive:flee@6", "hp<30|drive:flee@x", "hp<30|drive:flee@1@2",
			"hp<30/|drive:flee", "hp<30|drive:flee@-1"]:
		assert_eq(Doctrine.parse(bad, "rig"), null, "rejects %s" % bad)
	assert_true(Doctrine.parse("under_fire=1|target:mites;mites>10|target:flyers;|target:broods;|target:priority", "rig") != null, "new items parse")


func test_rule_matches_mask() -> void:
	var all: Dictionary = Doctrine.make_rule([["hp", "<", 5], ["hp", "<", 6]], "drive:kite")
	var any: Dictionary = Doctrine.make_rule([["hp", "<", 5], ["hp", "<", 6]], "drive:kite", true)
	assert_false(Doctrine.rule_matches_mask(all, 1))
	assert_true(Doctrine.rule_matches_mask(all, 3))
	assert_true(Doctrine.rule_matches_mask(any, 2))
	assert_false(Doctrine.rule_matches_mask(any, 0))
	assert_true(Doctrine.rule_matches_mask(Doctrine.make_rule([], "drive:kite"), 0), "no conditions = always")


func test_any_off_hold_evaluation() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_unlock_logic(v)
	_rules(w, "rig", "hp<30/swarm>5|drive:flee")
	w.step()
	assert_eq(v.eff_drive, "circle", "neither holds")
	v.hp = v.max_hp * 0.2
	w.step()
	assert_eq(v.eff_drive, "flee", "one condition is enough")
	assert_eq(v.rule_live, 1)
	assert_eq(v.rule_conds & 15, 1, "clive stays the raw mask")
	v.hp = v.max_hp
	_rules(w, "rig", "-hp>0|drive:flee")
	w.step()
	assert_eq(v.eff_drive, "circle", "off rule never runs")
	assert_eq(v.rule_live, 0, "and is never lit")
	# hold
	_rules(w, "rig", "hp<30|drive:flee@1")
	v.hp = v.max_hp * 0.2
	w.step()
	assert_eq(v.rule_live, 1)
	v.hp = v.max_hp
	var lit: int = 0
	for i in 60:
		w.step()
		if v.rule_live == 1:
			lit += 1
	assert_eq(lit, 30, "held for 1 s = 30 ticks")
	assert_eq(v.eff_drive, "circle", "then released")
	v.hp = v.max_hp * 0.2
	w.step()
	_rules(w, "rig", "hp<30|drive:flee@1")
	assert_true(v.rule_hold.is_empty(), "set_rules clears the hold scratch")
	v.hp = v.max_hp
	w.step()
	assert_eq(v.rule_live, 0)


func test_logic_options_need_tech() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_rules(w, "rig", "hp<30/swarm>5|drive:flee")
	assert_eq(v.rules.size(), 0, "any rejected without logic_any")
	_rules(w, "rig", "hp<30|drive:flee@2")
	assert_eq(v.rules.size(), 0, "hold rejected without logic_hold")
	_rules(w, "rig", "-hp<30|drive:flee")
	assert_eq(v.rules.size(), 1, "off is free")
	_rules(w, "rig", "under_fire=1|drive:flee")
	assert_eq(Doctrine.encode(v.rules), "-hp<30|drive:flee", "previous list kept: under_fire locked")
	v.tech_fx["logic_hold"] = 1.0
	v.tech_fx["logic_any"] = 1.0
	_rules(w, "rig", "hp<30/swarm>5|drive:flee@2")
	assert_eq(v.rules.size(), 1)
	# after a respec the tech is gone: hold is ignored, any rule is skipped
	v.tech_fx.erase("logic_hold")
	v.hp = v.max_hp * 0.2
	w.step()
	assert_eq(v.eff_drive, "flee")
	v.hp = v.max_hp
	w.step()
	assert_eq(v.eff_drive, "circle", "hold ignored without tech")
	v.tech_fx.erase("logic_any")
	v.hp = v.max_hp * 0.2
	w.step()
	assert_eq(v.eff_drive, "circle", "any rule skipped without tech")


func test_new_conditions() -> void:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	_unlock_logic(v)
	for i in 3:
		w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(60 + 10 * i, 0))
	w.spawn_enemy(SimWorld.SPITTER, v.pos + Vector2(0, 250))
	w.spawn_enemy(SimWorld.GLASS, v.pos + Vector2(0, -250))
	w.spawn_enemy(SimWorld.GLASS, v.pos + Vector2(0, -280))
	w.spawn_enemy(SimWorld.GLASS, v.pos + Vector2(0, -900))
	w.rebuild_derived()
	var ctx := {}
	var none := Vector2.ZERO
	assert_eq(Doctrine._value(w, v, "mites", 0, -1, -1, none, ctx), 3.0)
	assert_eq(Doctrine._value(w, v, "spitters", 0, -1, -1, none, ctx), 1.0)
	assert_eq(Doctrine._value(w, v, "flyers", 0, -1, -1, none, ctx), 2.0, "the far one is out of range")
	v.momentum = 40.0
	assert_eq(Doctrine._value(w, v, "momentum", 0, -1, -1, none, ctx), 40.0)
	assert_eq(Doctrine._value(w, v, "under_fire", 0, -1, -1, none, ctx), 0.0)
	v.hurt_ticks = Doctrine.UNDER_FIRE_TICKS
	assert_eq(Doctrine._value(w, v, "under_fire", 0, -1, -1, none, ctx), 1.0)
	w.spawning_enabled = false
	var t0: float = Doctrine._value(w, v, "round_time", 0, -1, -1, none, ctx)
	for i in 60:
		w.step()
	assert_eq(Doctrine._value(w, v, "round_time", 0, -1, -1, none, ctx), t0 + 2.0, "seconds into the combat")
	assert_eq(v.hurt_ticks, 0, "under_fire expires after 60 ticks")
	for pair in [["t_mite", 0, 1.0], ["t_glass", 3, 1.0], ["t_brood", 4, 1.0], ["t_shrieker", 5, 1.0], ["t_boss", SimWorld.BOSS_A, 1.0], ["t_boss", 0, 0.0], ["t_mite", 2, 0.0]]:
		var e: int = w.spawn_enemy(int(pair[1]), v.pos + Vector2(100, 100))
		assert_eq(Doctrine._value(w, v, str(pair[0]), 1, e, w.enemy_id[e], none, ctx), float(pair[2]), "%s on kind %d" % [pair[0], pair[1]])
	var locked: SimVehicle = _world().vehicles[0]
	assert_false(Doctrine.cond_unlocked(locked, "under_fire"))
	assert_false(Doctrine.cond_unlocked(locked, "round_time"))
	assert_true(Doctrine.cond_unlocked(locked, "mites"))


func test_priority_text() -> void:
	var p: Dictionary = Doctrine.default_priority()
	assert_eq(Doctrine.encode_priority(p), Doctrine.DEFAULT_PRIO)
	assert_eq(p["order"].size(), Doctrine.PRIO_TYPES.size())
	var t := "boss,-rival,spitter,shrieker,brood,glass,mite,-boulder:weakest"
	var q: Variant = Doctrine.parse_priority(t)
	assert_true(q != null)
	assert_eq(Doctrine.encode_priority(q), t)
	assert_eq(q["off"], ["rival", "boulder"] as Array[String])
	assert_eq(q["pick"], "weakest")
	assert_eq((Doctrine.parse_priority("boss,shrieker,spitter,brood,glass,mite,boulder,rival") as Dictionary)["pick"], "nearest", "pick defaults")
	for bad in ["", "boss:nearest", "boss,boss,spitter,brood,glass,mite,boulder,rival:nearest",
			"boss,shrieker,spitter,brood,glass,mite,boulder,rival,mite:nearest", "boss,shrieker,spitter,brood,glass,mite,boulder,ghost:nearest",
			"boss,shrieker,spitter,brood,glass,mite,boulder,rival:fastest", "boss,shrieker,spitter,brood,glass,mite,boulder,rival:nearest:x"]:
		assert_eq(Doctrine.parse_priority(bad), null, "rejects %s" % bad)


func _prio_world() -> SimWorld:
	var w := _world()
	var v: SimVehicle = w.vehicles[0]
	v.tech_fx["prio_weapon"] = 1.0
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(40, 0))
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(0, 80))
	w.spawn_enemy(SimWorld.SPITTER, v.pos + Vector2(-150, 0))
	w.spawn_enemy(SimWorld.SPITTER, v.pos + Vector2(-100, 0))
	w.spawn_enemy(SimWorld.GLASS, v.pos + Vector2(0, -120))
	w.rebuild_derived()
	return w


func _prio_kind(w: SimWorld, t: Vector3i) -> int:
	return w.enemy_kind[t.y] if t.x == 1 else -1


func test_priority_targeting() -> void:
	var w := _prio_world()
	var v: SimVehicle = w.vehicles[0]
	var t: Vector3i = VehicleAI.find_target(w, v, "priority", 0.0)
	assert_eq(_prio_kind(w, t), SimWorld.SPITTER, "default list: spitter before glass, boulder, mite")
	assert_eq(t.y, 3, "nearest spitter")
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "boss,shrieker,spitter,brood,glass,mite,boulder,rival:weakest"})
	w.enemy_hp[2] = 100.0
	w.enemy_hp[3] = 5.0
	assert_eq(VehicleAI.find_target(w, v, "priority", 0.0).y, 3, "weakest spitter")
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "boss,shrieker,spitter,brood,glass,mite,boulder,rival:strongest"})
	assert_eq(VehicleAI.find_target(w, v, "priority", 0.0).y, 2, "strongest spitter")
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "boulder,mite,spitter,brood,glass,boss,shrieker,rival:nearest"})
	assert_eq(_prio_kind(w, VehicleAI.find_target(w, v, "priority", 0.0)), SimWorld.BOULDER, "order respected")
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "-boulder,-mite,-spitter,-brood,glass,boss,shrieker,rival:nearest"})
	assert_eq(_prio_kind(w, VehicleAI.find_target(w, v, "priority", 0.0)), SimWorld.GLASS, "off types skipped")
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "-boulder,-mite,-spitter,-brood,-glass,boss,shrieker,rival:nearest"})
	assert_eq(VehicleAI.find_target(w, v, "priority", 0.0), Vector3i.ZERO, "everything left is off: nothing")
	# out of range: the rig falls back to the nearest alien that is not off, a weapon returns nothing
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "boss,shrieker,-spitter,brood,glass,mite,boulder,rival:nearest"})
	w.enemy_pos[0] = v.pos + Vector2(3000, 0)
	w.enemy_pos[1] = v.pos + Vector2(3000, 90)
	w.enemy_pos[4] = v.pos + Vector2(3000, 180)
	w.rebuild_derived()
	var far: Vector3i = VehicleAI.find_target(w, v, "priority", 0.0)
	assert_eq(far.x, 1)
	assert_eq(w.enemy_kind[far.y], SimWorld.MITE, "nothing in range: nearest alien not off")
	assert_eq(VehicleAI.find_target(w, v, "priority", 40.0, "mg"), Vector3i.ZERO, "weapon: nothing in reach")


func test_priority_rival_only_with_pvp() -> void:
	var w := _world(2)
	var v: SimVehicle = w.vehicles[0]
	var o: SimVehicle = w.vehicles[1]
	v.invuln_ticks = 0
	o.invuln_ticks = 0
	o.pos = v.pos + Vector2(100, 0)
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(0, 150))
	w.rebuild_derived()
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "rival,boss,shrieker,spitter,brood,glass,mite,boulder:nearest"})
	assert_eq(w.pvp_enabled(), false)
	assert_eq(VehicleAI.find_target(w, v, "priority", 0.0).x, 1, "no pvp: the alien")
	w.round = SimWorld.PVP_START_ROUND
	w.pvp_grace_ticks = 0
	var t: Vector3i = VehicleAI.find_target(w, v, "priority", 0.0)
	assert_eq(t, Vector3i(2, o.id, o.id), "pvp on: the rival")
	o.smoke_ticks = 10
	assert_eq(VehicleAI.find_target(w, v, "priority", 0.0).x, 1, "smoked rival skipped")
	o.smoke_ticks = 0
	w.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "-rival,boss,shrieker,spitter,brood,glass,mite,boulder:nearest"})
	assert_eq(VehicleAI.find_target(w, v, "priority", 0.0).x, 1, "rival off")


func test_weapon_priority_follow_or_own() -> void:
	var w := _prio_world()
	var v: SimVehicle = w.vehicles[0]
	assert_false(Doctrine.weapon_has_own_priority(v, "mg"))
	assert_eq(Doctrine.priority_of(v, "mg"), v.target_prio, "follows the rig")
	w.apply_command(1, {"type": "set_priority", "scope": "mg", "value": "mite,boss,shrieker,spitter,brood,glass,boulder,rival:nearest"})
	assert_true(Doctrine.weapon_has_own_priority(v, "mg"))
	assert_eq(_prio_kind(w, VehicleAI.find_target(w, v, "priority", 400.0, "mg")), SimWorld.MITE, "own list")
	assert_eq(_prio_kind(w, VehicleAI.find_target(w, v, "priority", 0.0)), SimWorld.SPITTER, "rig list unchanged")
	assert_true(Doctrine.fingerprint(v).contains("!mite,"), "fingerprint carries it")
	v.tech_fx.erase("prio_weapon")
	assert_eq(Doctrine.priority_of(v, "mg"), v.target_prio, "locked: the rig's list")
	v.tech_fx["prio_weapon"] = 1.0
	w.apply_command(1, {"type": "set_priority", "scope": "mg", "value": ""})
	assert_false(Doctrine.weapon_has_own_priority(v, "mg"), "empty = follow the rig")
	assert_eq(Doctrine.priority_of(v, "mg"), v.target_prio)
	var w2 := _world()
	w2.apply_command(1, {"type": "set_priority", "scope": "mg", "value": Doctrine.DEFAULT_PRIO})
	assert_false(Doctrine.weapon_has_own_priority(w2.vehicles[0], "mg"), "own list needs the tech")
	# a weapon in mode priority picks through VehicleAI.update_weapon_target
	w.apply_command(1, {"type": "set_weapon_target", "scope": "mg", "value": "priority"})
	w.apply_command(1, {"type": "set_priority", "scope": "mg", "value": "mite,boss,shrieker,spitter,brood,glass,boulder,rival:nearest"})
	var wp: Dictionary = v.weapons[0]
	VehicleAI.update_weapon_target(w, v, wp, 0, "priority")
	assert_eq(int(wp["tk"]), 1)
	assert_eq(w.enemy_kind[int(wp["ti"])], SimWorld.MITE)


func test_new_target_modes() -> void:
	var w := _prio_world()
	var v: SimVehicle = w.vehicles[0]
	for m in ["priority", "mites", "flyers", "broods"]:
		assert_true(Doctrine.RIG_TARGETS.has(m) and Doctrine.WEAPON_TARGETS.has(m), m)
		assert_true(Doctrine.ACTIONS.has("target:" + m), m)
	assert_eq(w.enemy_kind[VehicleAI.find_target(w, v, "mites", 0.0).y], SimWorld.MITE)
	assert_eq(w.enemy_kind[VehicleAI.find_target(w, v, "flyers", 0.0).y], SimWorld.GLASS)
	assert_eq(VehicleAI.find_target(w, v, "broods", 0.0), VehicleAI.find_target(w, v, "nearest", 0.0), "no brood: nearest alien")
	w.apply_command(1, {"type": "set_target", "value": "priority"})
	assert_eq(v.doctrine["target"], "priority")
	w.apply_command(1, {"type": "set_weapon_target", "scope": "mg", "value": "flyers"})
	assert_eq(Doctrine.weapon_doc(v, "mg")["target"], "flyers")


func test_set_priority_validation() -> void:
	var good := "boss,-rival,spitter,shrieker,brood,glass,mite,boulder:weakest"
	assert_eq(NetSession.validate_command({"type": "set_priority", "scope": "rig", "value": " boss , -rival,spitter,shrieker,brood,glass,mite,boulder : weakest "}),
		{"type": "set_priority", "scope": "rig", "value": good}, "canonical")
	assert_eq(NetSession.validate_command({"type": "set_priority", "scope": "mg", "value": ""}), {"type": "set_priority", "scope": "mg", "value": ""}, "weapon: follow")
	assert_eq(NetSession.validate_command({"type": "set_priority", "scope": "rig", "value": ""}), {}, "rig needs a list")
	assert_eq(NetSession.validate_command({"type": "set_priority", "scope": "laser", "value": good}), {}, "unknown scope")
	assert_eq(NetSession.validate_command({"type": "set_priority", "scope": "rig", "value": "boss:nearest"}), {}, "missing types")
	assert_eq(NetSession.validate_command({"type": "set_priority", "scope": "rig", "value": 3}), {}, "not a string")
	assert_eq(NetSession.validate_command({"type": "set_priority", "value": good}), {}, "no scope")
	var w := _world()
	w.phase = SimWorld.PHASE_WORKSHOP
	w.apply_command(1, NetSession.validate_command({"type": "set_priority", "scope": "rig", "value": good}))
	assert_eq(Doctrine.encode_priority(w.vehicles[0].target_prio), good, "valid in the workshop too")


func test_priority_and_options_snapshot_roundtrip() -> void:
	var host := _world(2)
	var v: SimVehicle = host.vehicles[0]
	Cards.grant(v, "cannon")
	_unlock_logic(v)
	_rules(host, "rig", "-hp<30/swarm>20|drive:flee@2;mites>5|target:priority;under_fire=1&t_boss=0|drive:kite@5")
	_rules(host, "cannon", "spitters>1/flyers>1|target:flyers@3")
	host.apply_command(1, {"type": "set_priority", "scope": "rig", "value": "-boss,shrieker,spitter,-brood,glass,mite,boulder,rival:strongest"})
	host.apply_command(1, {"type": "set_priority", "scope": "cannon", "value": "mite,boss,shrieker,spitter,brood,glass,boulder,-rival:weakest"})
	host.apply_command(1, {"type": "set_weapon_target", "scope": "cannon", "value": "priority"})
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	var c: SimVehicle = client.vehicles[0]
	assert_eq(Doctrine.fingerprint(c), Doctrine.fingerprint(v), "rules with options and both priorities synced")
	assert_eq(c.rules, v.rules, "rule dicts identical")
	assert_eq(c.target_prio, v.target_prio)
	assert_true(Doctrine.weapon_has_own_priority(c, "cannon"))
	assert_eq(c.weapon_doctrine["cannon"]["prio"], v.weapon_doctrine["cannon"]["prio"])
	assert_false(Doctrine.weapon_has_own_priority(c, "mg"))
	assert_eq(Doctrine.encode_priority(client.vehicles[1].target_prio), Doctrine.DEFAULT_PRIO, "default list on the other rig")
	assert_eq(Snapshot.VERSION, 19)
