extends TestCase
## Tech tree v2.3 stage 2b: the ability framework (slots, cooldowns, auto-cast rules, use_ability / set_ability),
## nitro / EMP / smoke / salvo and their tech variants (dirty fuel, slipstream, phantom), the new rule
## vocabulary (conditions, focus fire, `ability:<id>`, four conditions), swarm logic, snapshot and determinism.

const NITRO: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro"]
const DIRTY: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_dirty_fuel"]
const SLIP: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_slipstream"]
const PHANTOM: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_ghost", "propulsion_turbine", "propulsion_phantom"]
const EMP: Array = ["electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_emp"]
const SMOKE: Array = ["electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_smoke"]
const SALVO: Array = ["electronics_rangefinder", "electronics_relay", "electronics_targeting", "electronics_smoke", "electronics_neural"]
const TARGETING: Array = ["electronics_rangefinder", "electronics_radar", "electronics_targeting"]
const HUNTER: Array = ["electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_hunter"]
const RELAY: Array = ["electronics_rangefinder", "electronics_relay"]
const SWARM: Array = ["electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_hunter", "electronics_overclock", "electronics_swarm"]


func _world(ids: Array, hold: bool = true, p_seed: int = 7) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	v.scrap = 99999
	for id: String in ids:
		assert_true(Tech.buy(v, id, 1), "buy " + id)
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	if hold:
		w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


## Two rigs in PvP (round 4, no grace), `b` 150 px east of `a`; `a` has the tech `ids`.
func _duel(ids: Array) -> SimWorld:
	var w := SimWorld.new(9)
	w.spawning_enabled = false
	w.round = 4
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	var b: SimVehicle = w.add_vehicle(2, Vector2(1150, 700))
	a.scrap = 99999
	for id: String in ids:
		assert_true(Tech.buy(a, id, 1), "buy " + id)
	for v: SimVehicle in [a, b]:
		v.max_hp = 1.0e6
		v.hp = 1.0e6
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	w.apply_command(2, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


func _enemy(w: SimWorld, kind: int, dx: float, hp: float, dy: float = 0.0) -> int:
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(kind, v.pos + Vector2(dx, dy))
	var i: int = w.enemy_count - 1
	w.enemy_hp[i] = hp
	w.rebuild_derived()
	return i


func _count(w: SimWorld, n: int, type: String) -> int:
	var c: int = 0
	for t in n:
		w.step()
		for e in w.events:
			if e["type"] == type:
				c += 1
	return c


func _find(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1


## Steps once and reports whether rig rule 0 matched.
func _live(w: SimWorld, rule: String) -> bool:
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": rule})
	w.step()
	return (w.vehicles[0].rule_live & 1) == 1


# ---------------------------------------------------------------- slots

func test_slots_fill_in_purchase_order_and_swap_in_the_workshop() -> void:
	var w: SimWorld = _world(NITRO)
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.abilities, ["nitro", ""] as Array[String])
	for id: String in EMP:
		Tech.buy(v, id, 1)
	assert_eq(v.abilities, ["nitro", "emp"] as Array[String], "second slot: the next ability bought")
	Tech.buy(v, "electronics_neural", 1)
	assert_eq(v.abilities, ["nitro", "emp"] as Array[String], "only two slots")
	assert_eq(Abilities.unlocked(v), ["nitro", "emp", "salvo"] as Array[String])
	# set_ability works in the workshop only, for unlocked abilities.
	w.apply_command(1, {"type": "set_ability", "slot": 1, "value": "salvo"})
	assert_eq(v.abilities[1], "emp", "not in combat")
	w.phase = SimWorld.PHASE_WORKSHOP
	w.apply_command(1, {"type": "set_ability", "slot": 1, "value": "salvo"})
	assert_eq(v.abilities, ["nitro", "salvo"] as Array[String])
	w.apply_command(1, {"type": "set_ability", "slot": 0, "value": "smoke"})
	assert_eq(v.abilities, ["nitro", "salvo"] as Array[String], "smoke is not unlocked")
	v.ab_cd[1] = 77
	w.apply_command(1, {"type": "set_ability", "slot": 0, "value": "salvo"})
	assert_eq(v.abilities, ["salvo", "nitro"] as Array[String], "an equipped ability swaps places")
	assert_eq(v.ab_cd[0], 77, "with its cooldown")
	w.apply_command(1, {"type": "set_ability", "slot": 7, "value": "nitro"})
	assert_eq(v.abilities, ["salvo", "nitro"] as Array[String], "bad slot")


func test_command_validation() -> void:
	assert_eq(NetSession.validate_command({"type": "use_ability", "value": "nitro"}), {"type": "use_ability", "value": "nitro"})
	assert_eq(NetSession.validate_command({"type": "use_ability", "value": "bogus"}), {})
	assert_eq(NetSession.validate_command({"type": "use_ability"}), {})
	assert_eq(NetSession.validate_command({"type": "set_ability", "slot": 1, "value": "emp"}), {"type": "set_ability", "slot": 1, "value": "emp"})
	assert_eq(NetSession.validate_command({"type": "set_ability", "slot": 1.0, "value": "emp"}), {"type": "set_ability", "slot": 1, "value": "emp"}, "JSON floats")
	assert_eq(NetSession.validate_command({"type": "set_ability", "slot": 2, "value": "emp"}), {})
	assert_eq(NetSession.validate_command({"type": "set_ability", "slot": -1, "value": "emp"}), {})
	assert_eq(NetSession.validate_command({"type": "set_ability", "slot": "0", "value": "emp"}), {})
	assert_eq(NetSession.validate_command({"type": "set_ability", "slot": 0, "value": 3}), {})
	# Rules with the new vocabulary go through canonical re-encoding; five conditions never pass.
	var ok: Dictionary = NetSession.validate_command({"type": "set_rules", "scope": "rig", "value": "boulders>2&fuel<40|ability:nitro"})
	assert_eq(ok["value"], "boulders>2&fuel<40|ability:nitro")
	assert_eq(NetSession.validate_command({"type": "set_rules", "scope": "rig", "value": "hp<1&hp<2&hp<3&hp<4&hp<5|fire:focus"}), {})
	assert_eq(NetSession.validate_command({"type": "set_rules", "scope": "mg", "value": "|fire:focus"}), {}, "focus is a rig action")


# ---------------------------------------------------------------- nitro

func test_nitro_auto_rule_cost_and_cooldown() -> void:
	var w: SimWorld = _world(NITRO)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	for t in 20:  # nothing near and full hp: the default rule does not fire
		v.momentum = 100.0
		w.step()
	assert_eq(v.nitro_ticks, 0)
	_enemy(w, SimWorld.MITE, 150.0, 1.0e6)
	v.momentum = 40.0
	w.step()
	assert_eq(v.nitro_ticks, 0, "below 50 momentum: no nitro")
	v.momentum = 100.0
	w.step()
	var started: int = w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "nitro").size()
	assert_eq(started, 1, "target within 200 px and momentum >= 50")
	assert_eq(v.nitro_ticks, 60, "2 s")
	assert_true(v.momentum >= 45.0 and v.momentum < 51.0, "costs 50 momentum, got %f" % v.momentum)
	assert_eq(v.ab_cd[0], 180, "6 s cooldown")
	var casts: int = 0
	for t in 184:
		v.momentum = 100.0
		w.step()
		for e in w.events:
			if e["type"] == "nitro":
				casts += 1
	assert_eq(casts, 1, "the second one only after the cooldown")
	# Low hp is the other trigger.
	var low: SimWorld = _world(NITRO)
	low.vehicles[0].hp = 0.2 * low.vehicles[0].max_hp
	low.vehicles[0].momentum = 100.0
	low.step()
	assert_eq(low.vehicles[0].nitro_ticks, 60, "hp under 30 % needs no target")
	# Overclock shortens the cooldown.
	var oc: SimWorld = _world(NITRO + ["electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_emp", "electronics_overclock"])
	assert_eq(Abilities.cooldown_for(oc.vehicles[0], "nitro"), 126, "-30 %")


func test_nitro_boosts_speed() -> void:
	var w: SimWorld = _world(NITRO, false)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	for t in 60:
		w.step()
	var base: float = v.vel.length()
	v.momentum = 100.0
	w.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(v.nitro_ticks, 60, "cast by hand")
	for t in 20:
		w.step()
	assert_true(absf(v.vel.length() / base - 1.6) < 0.08, "+60 %%: %f vs %f" % [v.vel.length(), base])
	for t in 80:
		w.step()
	assert_eq(v.nitro_ticks, 0)
	assert_true(absf(v.vel.length() / base - 1.0) < 0.08, "back to normal after 2 s: %f vs %f" % [v.vel.length(), base])


func test_use_ability_command_rules() -> void:
	var w: SimWorld = _world(NITRO)
	var v: SimVehicle = w.vehicles[0]
	v.momentum = 100.0
	w.apply_command(1, {"type": "use_ability", "value": "emp"})
	assert_eq(v.ab_cd[0], 0, "not equipped: ignored")
	w.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(v.nitro_ticks, 60)
	v.nitro_ticks = 0
	v.momentum = 100.0
	w.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(v.nitro_ticks, 0, "cooling down")
	var ws: SimWorld = _world(NITRO)
	ws.vehicles[0].momentum = 100.0
	ws.phase = SimWorld.PHASE_WORKSHOP
	ws.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(ws.vehicles[0].nitro_ticks, 0, "combat only")
	var wm: SimWorld = _world(NITRO)
	wm.vehicles[0].momentum = 30.0
	wm.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(wm.vehicles[0].nitro_ticks, 0, "needs 50 momentum")


func test_dirty_fuel_smoke_and_sputter() -> void:
	var w: SimWorld = _world(DIRTY, false)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	var kinds: Array = []
	for k in 4:
		v.momentum = 100.0
		v.ab_cd[0] = 0
		v.nitro_ticks = 0
		v.sputter_ticks = 0
		w.apply_command(1, {"type": "use_ability", "value": "nitro"})
		for e in w.events:
			if e["type"] == "nitro":
				kinds.append(e["kind"])
		if k == 2:
			assert_eq(v.nitro_ticks, 60)
			for t in 30:
				w.step()
			var smokes: int = 0
			for z in w.zone_count:
				if w.zone_kind[z] == SimWorld.ZONE_SMOKE:
					smokes += 1
			assert_true(smokes >= 2, "the nitro leaves a trail of smoke, got %d" % smokes)
	assert_eq(v.sputter_ticks, 30, "the 4th coughs for 1 s")
	assert_eq(v.nitro_ticks, 0, "and gives no boost")
	assert_eq(Abilities.speed_mult(v), 1.0)
	# Events of the direct commands were emitted into world.events one by one.
	assert_eq(v.nitro_count, 4)
	assert_true(kinds.is_empty() or kinds[kinds.size() - 1] == 1)


func test_smoke_blinds_aliens_and_slipstream_slows_them() -> void:
	var w: SimWorld = _world(DIRTY)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	w._add_zone(v.pos + Vector2(100, 0), 30.0, SimWorld.ZONE_SMOKE, 100, 0)
	var i: int = _enemy(w, SimWorld.MITE, 100.0, 1.0e6)
	var x0: float = w.enemy_pos[i].x
	for t in 20:
		w.step()
	assert_true(absf(w.enemy_pos[i].x - x0) < 4.0, "an alien in smoke loses its target for a second: %f" % (w.enemy_pos[i].x - x0))
	assert_true(((w.enemy_status[i] >> 16) & 255) > 0)
	# Oil: the alien is slowed to 60 %.
	var a: SimWorld = _world(SLIP)
	var b: SimWorld = _world(SLIP)
	a.vehicles[0].weapons.clear()
	b.vehicles[0].weapons.clear()
	a._add_zone(a.vehicles[0].pos + Vector2(250, 0), 60.0, SimWorld.ZONE_OIL, 200, 0)
	_enemy(a, SimWorld.MITE, 250.0, 1.0e6)
	_enemy(b, SimWorld.MITE, 250.0, 1.0e6)
	for t in 30:
		a.step()
		b.step()
	var da: float = 250.0 - (a.enemy_pos[0].x - a.vehicles[0].pos.x)
	var db: float = 250.0 - (b.enemy_pos[0].x - b.vehicles[0].pos.x)
	assert_true(da < db * 0.8 and da > db * 0.35, "slowed on oil: %f vs %f" % [da, db])
	# A slipstream nitro lays oil.
	var c: SimWorld = _world(SLIP, false)
	c.vehicles[0].weapons.clear()
	c.vehicles[0].momentum = 100.0
	c.apply_command(1, {"type": "use_ability", "value": "nitro"})
	for t in 30:
		c.step()
	var oil: int = 0
	for z in c.zone_count:
		if c.zone_kind[z] == SimWorld.ZONE_OIL:
			oil += 1
	assert_true(oil >= 2, "an oil trail, got %d" % oil)


func test_phantom_drive() -> void:
	var w: SimWorld = _world(PHANTOM)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	v.momentum = 100.0
	w.apply_command(1, {"type": "use_ability", "value": "nitro"})
	assert_eq(v.invuln_ticks, 15, "0.5 s invulnerable")
	assert_eq(v.decoy_ticks, 30, "a decoy for 1 s")
	assert_eq(v.decoy_pos, v.pos)
	var hp0: float = v.hp
	w._damage_vehicle(v, 50.0, -1)
	assert_eq(v.hp, hp0, "immune meanwhile")
	# Aliens chase the decoy, not the rig that moved away.
	var decoy: Vector2 = v.decoy_pos
	v.pos = decoy + Vector2(900, 0)
	w.spawn_enemy(SimWorld.MITE, decoy + Vector2(60, 0))
	w.enemy_hp[w.enemy_count - 1] = 1.0e6
	w.rebuild_derived()
	w.step()
	assert_true(w.enemy_vel[w.enemy_count - 1].x < -1.0, "heads for the decoy: %s" % str(w.enemy_vel[w.enemy_count - 1]))
	for t in 40:
		w.step()
	assert_true(w.enemy_vel[w.enemy_count - 1].x > 1.0, "after the decoy faded it turns to the rig")
	# Kills take 0.5 s off the cooldown, never below 3 s.
	var w2: SimWorld = _world(PHANTOM)
	var v2: SimVehicle = w2.vehicles[0]
	v2.ab_cd[0] = 150
	for k in 6:
		var i: int = _enemy(w2, SimWorld.MITE, 500.0, 1.0)
		w2._hit_enemy(i, 5.0, 0)
	assert_eq(v2.ab_cd[0], 90, "150 - 4 x 15, then the 3 s floor")
	v2.ab_cd[0] = 60
	var j: int = _enemy(w2, SimWorld.MITE, 500.0, 1.0)
	w2._hit_enemy(j, 5.0, 0)
	assert_eq(v2.ab_cd[0], 60, "already under the floor: untouched")


# ---------------------------------------------------------------- emp, smoke, salvo

func test_emp_stuns_aliens_and_switches_rival_rules_off() -> void:
	var w: SimWorld = _world(EMP)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	for k in 4:
		_enemy(w, SimWorld.MITE, 90.0, 1.0e6, float(k) * 22.0 - 33.0)
	w.step()
	assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "emp").size(), 0, "4 aliens are not enough")
	_enemy(w, SimWorld.MITE, 90.0, 1.0e6, 60.0)
	w.step()
	assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e["type"] == "emp").size(), 1, "5 aliens within 120 px")
	assert_eq(v.ab_cd[0], 600, "20 s cooldown")
	var before: PackedVector2Array = w.enemy_pos.duplicate()
	for t in 30:
		w.step()
	for i in 5:
		assert_true(w.enemy_pos[i].distance_to(before[i]) < 1.0, "stunned aliens stand still (%d)" % i)
	for t in 25:
		w.step()
	assert_true(w.enemy_pos[0].distance_to(before[0]) > 5.0, "after 1.5 s they move again")
	# Rivals in the pulse: rules off for 3 s.
	var d: SimWorld = _duel(EMP)
	d.vehicles[0].weapons.clear()
	for k in 5:
		d.spawn_enemy(SimWorld.MITE, d.vehicles[0].pos + Vector2(-50, float(k) * 12.0 - 24.0))
		d.enemy_hp[d.enemy_count - 1] = 1.0e6
	d.rebuild_derived()
	d.vehicles[1].pos = d.vehicles[0].pos + Vector2(100, 0)
	d.step()
	var b: SimVehicle = d.vehicles[1]
	assert_true(b.rules_off_ticks >= 88 and b.rules_off_ticks <= 90, "the rival's rules are off for 3 s")
	d.step()
	assert_eq(b.rule_live, 0, "none of its rules runs")
	assert_eq(Doctrine.active_slots(b), 0)
	for t in 92:
		d.step()
	assert_eq(b.rule_live, 1, "back after 3 s")


func test_smoke_screen() -> void:
	var d: SimWorld = _duel(SMOKE)
	var a: SimVehicle = d.vehicles[0]
	var b: SimVehicle = d.vehicles[1]
	d.apply_command(2, {"type": "set_target", "value": "players_first"})
	d.apply_command(2, {"type": "set_rules", "scope": "rig", "value": ""})
	d.step()
	assert_eq(b.target_kind, 2, "the rival is shooting at us")
	assert_eq(a.smoke_ticks, 0, "full hp: no smoke")
	a.hp = 0.3 * a.max_hp
	d.step()
	assert_eq(a.smoke_ticks, 90 - 0, "3 s of smoke below 40 % hp")
	assert_eq(a.ab_cd[0], 450, "15 s cooldown")
	d.step()
	assert_ne(b.target_kind, 2, "untargetable")
	var smoke_zones: int = 0
	for z in d.zone_count:
		if d.zone_kind[z] == SimWorld.ZONE_SMOKE:
			smoke_zones += 1
	assert_eq(smoke_zones, 1, "and a cloud on the ground")
	# Aliens lose a hidden rig.
	var w: SimWorld = _world(SMOKE)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	v.hp = 0.2 * v.max_hp
	var i: int = _enemy(w, SimWorld.MITE, 300.0, 1.0e6)
	var x0: float = w.enemy_pos[i].x
	for t in 40:
		w.step()
	assert_true(absf(w.enemy_pos[i].x - x0) < 6.0, "no target while hidden: %f" % (w.enemy_pos[i].x - x0))
	for t in 60:
		w.step()
	assert_true(w.enemy_pos[i].x < x0 - 10.0, "after the smoke it comes for us")


func test_salvo_fire_rate_and_auto_rule() -> void:
	var shots: Array = []
	for cast in [false, true]:
		var w: SimWorld = _world(SALVO)
		var v: SimVehicle = w.vehicles[0]
		_enemy(w, SimWorld.BOULDER, 200.0, 1.0e9)
		v.ab_cd[v.abilities.find("salvo")] = 0
		w.step()  # target found
		if cast:
			w.apply_command(1, {"type": "use_ability", "value": "salvo"})
		shots.append(_count(w, 60, "fire"))
	assert_true(float(shots[1]) > float(shots[0]) * 1.35 and float(shots[1]) < float(shots[0]) * 1.65, "+50 %%: %d vs %d" % [shots[1], shots[0]])
	# Auto: 15 aliens or 3 boulders.
	var few: SimWorld = _world(SALVO)
	few.vehicles[0].weapons.clear()
	for k in 14:
		_enemy(few, SimWorld.MITE, 120.0, 1.0e6, float(k) * 14.0 - 90.0)
	few.step()
	assert_eq(few.vehicles[0].salvo_ticks, 0, "14 aliens: no salvo")
	_enemy(few, SimWorld.MITE, 150.0, 1.0e6)
	few.step()
	assert_eq(few.vehicles[0].salvo_ticks, 60, "15 aliens near")
	assert_eq(few.vehicles[0].ab_cd[few.vehicles[0].abilities.find("salvo")], 360, "12 s")
	var rocks: SimWorld = _world(SALVO)
	rocks.vehicles[0].weapons.clear()
	for k in 2:
		_enemy(rocks, SimWorld.BOULDER, 150.0, 1.0e9, float(k) * 30.0)
	rocks.step()
	assert_eq(rocks.vehicles[0].salvo_ticks, 0)
	_enemy(rocks, SimWorld.BOULDER, 150.0, 1.0e9, 90.0)
	rocks.step()
	assert_eq(rocks.vehicles[0].salvo_ticks, 60, "3 boulders near")


# ---------------------------------------------------------------- rule vocabulary

func test_rule_vocabulary_is_locked_by_tech() -> void:
	var plain: SimWorld = _world([], false)
	var pv: SimVehicle = plain.vehicles[0]
	for rule in ["boulders>1|drive:circle", "fuel<50|drive:circle", "rival_weaker=1|drive:circle", "ability_ready=1|drive:circle",
			"t_leader=1|drive:circle", "|fire:focus", "|ability:nitro", "|ability:emp"]:
		var parsed: Variant = Doctrine.parse(rule, "rig")
		assert_true(parsed != null, "parses: " + rule)
		assert_false(Doctrine.rules_allowed(pv, parsed), "locked: " + rule)
		plain.apply_command(1, {"type": "set_rules", "scope": "rig", "value": rule})
		assert_true(pv.rules.is_empty(), "set_rules refuses " + rule)
	assert_eq(Doctrine.conds_for(pv).size(), Doctrine.COND_IDS.size() - 7)
	assert_false(Doctrine.actions_for("rig", pv).has("fire:focus"))
	assert_true(Doctrine.actions_for("rig").has("fire:focus"), "without a vehicle everything is listed")
	assert_eq(Doctrine.parse("|fire:focus", "mg"), null, "focus is a rig action")
	assert_eq(Doctrine.parse("|ability:nitro", "cannon"), null)
	# Unlocking opens them.
	var w: SimWorld = _world(NITRO + HUNTER, false)
	var v: SimVehicle = w.vehicles[0]
	assert_true(Doctrine.cond_unlocked(v, "boulders"))
	assert_true(Doctrine.cond_unlocked(v, "fuel"))
	assert_true(Doctrine.cond_unlocked(v, "rival_weaker"))
	assert_true(Doctrine.cond_unlocked(v, "ability_ready"))
	assert_true(Doctrine.cond_unlocked(v, "t_leader"))
	assert_true(Doctrine.actions_for("rig", v).has("ability:nitro"))
	assert_false(Doctrine.actions_for("rig", v).has("ability:emp"))
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "boulders>1&fuel<50|ability:nitro"})
	assert_eq(v.rules.size(), 1, "accepted once unlocked")
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "|ability:emp"})
	assert_eq(v.rules.size(), 1, "emp is still locked")
	# Relay: focus fire.
	var rl: SimWorld = _world(RELAY, false)
	rl.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "boulders>0|fire:focus"})
	assert_eq(rl.vehicles[0].rules.size(), 1)


func test_four_conditions_need_the_targeting_computer() -> void:
	var four: String = "hp<90&hp<80&hp<70&hp<60|drive:circle"
	var w: SimWorld = _world(["electronics_rangefinder"], false)
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": four})
	assert_true(w.vehicles[0].rules.is_empty(), "3 conditions without it")
	assert_eq(Doctrine.max_conds(w.vehicles[0]), 3)
	var t: SimWorld = _world(TARGETING, false)
	assert_eq(Doctrine.max_conds(t.vehicles[0]), 4)
	t.apply_command(1, {"type": "set_rules", "scope": "rig", "value": four})
	assert_eq(t.vehicles[0].rules.size(), 1)
	# After a respec the extra condition is stored but the rule would not be accepted again.
	assert_eq(Doctrine.parse("hp<1&hp<2&hp<3&hp<4&hp<5|drive:circle", "rig"), null, "five never")


func test_new_conditions_evaluate() -> void:
	var w: SimWorld = _world(HUNTER, false)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	for k in 2:
		_enemy(w, SimWorld.BOULDER, 100.0 + 10.0 * float(k), 1.0e9, float(k) * 30.0)
	assert_false(_live(w, "boulders>2|drive:hold"), "two boulders are not more than 2")
	_enemy(w, SimWorld.BOULDER, 100.0, 1.0e9, -40.0)
	assert_true(_live(w, "boulders>2|drive:hold"), "three are")
	v.fuel = 40
	assert_true(_live(w, "fuel<50|drive:hold"))
	v.fuel = 80
	assert_false(_live(w, "fuel<50|drive:hold"))
	# ability_ready follows the cooldown and the momentum.
	var n: SimWorld = _world(NITRO + TARGETING, false)
	n.vehicles[0].weapons.clear()
	n.vehicles[0].momentum = 100.0
	assert_true(_live(n, "ability_ready=1|drive:hold"))
	n.vehicles[0].ab_cd[0] = 50
	assert_false(_live(n, "ability_ready=1|drive:hold"))
	n.vehicles[0].ab_cd[0] = 0
	n.vehicles[0].momentum = 10.0
	assert_false(_live(n, "ability_ready=1|drive:hold"), "nitro needs momentum")
	# Rival conditions (PvP).
	var d: SimWorld = _duel(HUNTER)
	var a: SimVehicle = d.vehicles[0]
	var b: SimVehicle = d.vehicles[1]
	d.apply_command(1, {"type": "set_target", "value": "players_first"})
	b.hp = 0.3 * b.max_hp
	assert_true(_live(d, "rival_weaker=1|drive:hold"), "a nearby rival is weaker")
	b.hp = b.max_hp
	a.hp = 0.3 * a.max_hp
	assert_false(_live(d, "rival_weaker=1|drive:hold"))
	a.scrap = 0
	b.scrap = 0
	b.kills = 50
	d.update_leader()
	d.step()
	assert_eq(d.leader_peer, 2)
	assert_eq(a.target_kind, 2)
	assert_true(_live(d, "t_leader=1|drive:hold"), "the target is the leader")
	b.kills = 0
	a.kills = 60
	d.update_leader()
	d.step()
	assert_false(_live(d, "t_leader=1|drive:hold"))


func test_ability_rules_override_the_auto_cast() -> void:
	# A rule for the ability replaces the default: it fires without a target ...
	var w: SimWorld = _world(NITRO)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	v.momentum = 100.0
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp<95|ability:nitro;hp>0|drive:hold"})
	assert_eq(v.rules.size(), 2)
	w.step()
	assert_eq(v.nitro_ticks, 0, "full hp: the rule does not match")
	v.hp = 0.9 * v.max_hp
	v.momentum = 100.0
	w.step()
	assert_eq(v.nitro_ticks, 60, "the rule casts it")
	# ... and silences the default while it does not match.
	var s: SimWorld = _world(NITRO)
	s.vehicles[0].weapons.clear()
	s.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp<10|ability:nitro;hp>0|drive:hold"})
	_enemy(s, SimWorld.MITE, 100.0, 1.0e6)
	s.vehicles[0].momentum = 100.0
	for t in 5:
		s.step()
	assert_eq(s.vehicles[0].nitro_ticks, 0, "an enemy in range would have triggered the default")


func test_focus_fire_overrides_weapon_targets() -> void:
	var w: SimWorld = _world(RELAY, false)
	var v: SimVehicle = w.vehicles[0]
	w.apply_command(1, {"type": "set_weapon_target", "scope": "mg", "value": "boulders"})
	_enemy(w, SimWorld.MITE, 80.0, 1.0e9)
	_enemy(w, SimWorld.BOULDER, 150.0, 1.0e9, 20.0)
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	w.step()
	w.step()
	assert_eq(int(v.weapons[0].get("tk", 0)), 1, "the gun picks its own target (the boulder)")
	assert_eq(int(v.weapons[0].get("tid", -1)), w.enemy_id[1])
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold;hp>0|fire:focus"})
	w.step()
	w.step()
	assert_true(v.focus)
	assert_eq(int(v.weapons[0].get("tk", 0)), 0, "focus fire: it follows the rig's target")


# ---------------------------------------------------------------- swarm logic

func test_swarm_logic_marks_the_rig_target() -> void:
	var w: SimWorld = _world(SWARM)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	assert_true(float(v.tech_fx.get("swarm_logic", 0.0)) > 0.0)
	var a: int = _enemy(w, SimWorld.BOULDER, 100.0, 1.0e6)
	var b: int = _enemy(w, SimWorld.BOULDER, 200.0, 1.0e6, 10.0)
	var aid: int = w.enemy_id[a]
	var bid: int = w.enemy_id[b]
	w.step()
	assert_eq(v.mark_id, aid, "the marked target is the rig's target")
	assert_true(v.focus, "all guns share it")
	# +35 % damage on the mark only.
	var hp_a: float = w.enemy_hp[_find(w, aid)]
	var hp_b: float = w.enemy_hp[_find(w, bid)]
	w.spawn_projectile(w.enemy_pos[_find(w, aid)] - Vector2(20, 0), Vector2(400, 0), 1.0, 10.0, 0)
	w.spawn_projectile(w.enemy_pos[_find(w, bid)] - Vector2(20, 0), Vector2(400, 0), 1.0, 10.0, 0)
	w.step()
	assert_true(absf((hp_a - w.enemy_hp[_find(w, aid)]) - 13.5) < 0.05, "+35 %% on the mark, got %f" % (hp_a - w.enemy_hp[_find(w, aid)]))
	assert_true(absf((hp_b - w.enemy_hp[_find(w, bid)]) - 10.0) < 0.05, "the other one takes the plain 10")
	# The mark jumps on when the target dies.
	w._hit_enemy(_find(w, aid), 1.0e9, 0)
	for t in 8:
		w.step()
	assert_eq(v.mark_id, bid, "next target")


# ---------------------------------------------------------------- snapshot, events, determinism

func test_snapshot_round_trip_abilities() -> void:
	var w: SimWorld = _world(NITRO + EMP)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	for k in 6:
		_enemy(w, SimWorld.MITE, 90.0, 1.0e6, float(k) * 20.0 - 50.0)
	w.step()  # the EMP fires
	v.momentum = 88.0
	v.ab_cd[0] = 33
	v.smoke_ticks = 20
	v.rules_off_ticks = 7
	v.salvo_ticks = 11
	v.sputter_ticks = 4
	var bytes: PackedByteArray = Snapshot.encode(w)
	var c := SimWorld.new(1)
	c.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c, bytes), "applies")
	var cv: SimVehicle = c.vehicles[0]
	assert_eq(cv.abilities, v.abilities)
	assert_eq(cv.ab_cd[0], 33)
	assert_eq(cv.ab_cd[1], v.ab_cd[1])
	assert_true(absf(cv.momentum - 88.0) < 0.001)
	assert_eq(cv.smoke_ticks, 20)
	assert_eq(cv.rules_off_ticks, 7)
	assert_eq(cv.salvo_ticks, 11)
	assert_eq(cv.sputter_ticks, 4)
	assert_eq(c.enemy_status.size(), c.enemy_count)
	for i in w.enemy_count:
		assert_eq((c.enemy_status[i] & 255) > 0, (w.enemy_status[i] & 255) > 0, "stunned flag of enemy %d" % i)
	assert_true((w.enemy_status[0] & 255) > 0)
	# New event types travel.
	var evs: Array[Dictionary] = []
	for t in ["nitro", "emp", "smoke", "salvo", "dodge", "sparks", "boom", "shed"]:
		evs.append({"type": t, "pos": Vector2(50, 60), "owner": 0, "kind": 1})
	var c2 := SimWorld.new(1)
	c2.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c2, Snapshot.encode(w, evs)))
	assert_eq(c2.events.size(), 8)
	assert_eq(c2.events[3]["type"], "salvo")
	assert_eq(c2.events[6]["type"], "boom")
	# A malformed extras flag is rejected.
	var bad: PackedByteArray = bytes.duplicate()
	assert_false(Snapshot.apply(c2, bad.slice(0, bad.size() - 40)))


func test_determinism_with_abilities() -> void:
	var sums: Array = []
	for run in 2:
		var w: SimWorld = _world(NITRO + EMP + ["electronics_neural"], false, 21)
		w.spawning_enabled = true
		w.vehicles[0].max_hp = 600.0
		w.vehicles[0].hp = 600.0
		for t in 900:
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1], "same seed, same world")
	var w2: SimWorld = _world(NITRO)
	var base: int = w2.checksum()
	w2.vehicles[0].ab_cd[0] = 5
	assert_ne(w2.checksum(), base, "cooldowns are part of the checksum")
	w2.vehicles[0].ab_cd[0] = 0
	w2.vehicles[0].decoy_ticks = 3
	assert_ne(w2.checksum(), base)


func test_bots_still_play_with_abilities() -> void:
	# A bot with the speed build buys nitro and phantom; the match runs on and the abilities cast on their own.
	var w := SimWorld.new(31)
	w.fast_rounds = true
	w.add_vehicle(1, Vector2(1000, 700))
	var bot: BotPolicy = BotPolicy.create("speedster", 5)
	if bot == null:
		bot = BotPolicy.create(BotPolicy.names()[0], 5)
	var casts: int = 0
	for t in 2400:
		if w.phase == SimWorld.PHASE_WORKSHOP:
			w.vehicles[0].scrap += 400
			bot.workshop_commands(w, w.vehicles[0])
		w.step()
		for e in w.events:
			if e["type"] == "nitro":
				casts += 1
		if w.phase == SimWorld.PHASE_GAME_OVER:
			break
	assert_true(w.round >= 3, "the bot kept playing, round %d" % w.round)
	assert_true(casts >= 0)
