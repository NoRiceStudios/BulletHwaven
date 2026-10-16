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
