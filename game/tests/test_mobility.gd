extends TestCase
## Tech tree v2.3 stage 2b: momentum and the movement / chassis nodes (ram effects, knockback, dozer, dodge,
## ghost, juggernaut, turbine boom, scrap armour, reactive plates), the jammer, spit warning, snapshot and
## determinism.

const TUNED: Array = ["propulsion_tuned"]
const BUMPER: Array = ["propulsion_tuned", "propulsion_bumper"]
const DRIFT: Array = ["propulsion_tuned", "propulsion_drift"]
const NITRO: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro"]
const DIRTY: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_dirty_fuel"]
const BATTER: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_battering"]
const GHOST: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_ghost"]
const TURBINE: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_battering", "propulsion_turbine"]
const JUGG: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_battering", "propulsion_turbine", "propulsion_juggernaut"]
const DOZER: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_dozer"]
const REACTIVE: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_reactive"]
const SCRAP_ARMOUR: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_scrap_armour"]
const CAGE: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_drone", "engineering_roll_cage"]
const FEATHER: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_drone", "engineering_roll_cage", "engineering_featherweight"]
const JAMMER: Array = ["electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_emp", "electronics_overclock", "electronics_jammer"]


## A one-rig world (round 1, no spawner) with the tech `ids` bought. The rig is tough; `hold` makes it stand still.
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


# ---------------------------------------------------------------- momentum

func test_momentum_builds_while_driving() -> void:
	var w: SimWorld = _world(TUNED, false)
	var v: SimVehicle = w.vehicles[0]
	w.vehicles[0].weapons.clear()
	for t in 60:
		w.step()
	assert_true(v.momentum > 38.0 and v.momentum < 42.0, "+20/s: about 40 after 2 s, got %f" % v.momentum)
	for t in 200:
		w.step()
	assert_eq(v.momentum, 100.0, "capped at 100")
	# No Tuned Engine: no momentum at all.
	var w0: SimWorld = _world([], false)
	for t in 90:
		w0.step()
	assert_eq(w0.vehicles[0].momentum, 0.0, "momentum comes with the Tuned Engine")


func test_momentum_decays_when_stopped_and_turbine_halves() -> void:
	var w: SimWorld = _world(TUNED)
	var v: SimVehicle = w.vehicles[0]
	_enemy(w, SimWorld.MITE, 600.0, 1.0e6)  # a target: without one the rig patrols instead of holding
	v.momentum = 80.0
	for t in 30:
		w.step()
	assert_true(absf(v.momentum - 50.0) < 1.0, "-30/s while stopped, got %f" % v.momentum)
	var wt: SimWorld = _world(TURBINE)
	_enemy(wt, SimWorld.MITE, 600.0, 1.0e6)
	wt.vehicles[0].momentum = 80.0
	for t in 30:
		wt.step()
	assert_true(absf(wt.vehicles[0].momentum - 65.0) < 1.0, "the turbine halves the decay, got %f" % wt.vehicles[0].momentum)


func test_momentum_hit_loss_and_dirty_fuel() -> void:
	var w: SimWorld = _world(TUNED)
	var v: SimVehicle = w.vehicles[0]
	v.momentum = 60.0
	w._damage_vehicle(v, 8.0, -1)
	assert_eq(v.momentum, 60.0, "a small hit costs nothing")
	w._damage_vehicle(v, 12.0, -1)
	assert_eq(v.momentum, 50.0, "-10 per hit over 10 damage")
	# Dirty fuel doubles the gain.
	var a: SimWorld = _world(NITRO, false)
	var b: SimWorld = _world(DIRTY, false)
	a.vehicles[0].weapons.clear()
	b.vehicles[0].weapons.clear()
	for t in 30:
		a.step()
		b.step()
	assert_true(b.vehicles[0].momentum > a.vehicles[0].momentum * 1.8, "x2: %f vs %f" % [b.vehicles[0].momentum, a.vehicles[0].momentum])


func test_momentum_ram_bonus_at_full_bar() -> void:
	var w: SimWorld = _world(TUNED, false)
	var v: SimVehicle = w.vehicles[0]
	w.apply_command(1, {"type": "set_drive", "value": "charge"})
	_enemy(w, SimWorld.MITE, 300.0, 1.0e6)
	v.momentum = 50.0
	w.step()
	var normal: float = v.ram_damage
	v.momentum = 100.0
	w.step()
	assert_true(absf(v.ram_damage - normal * 1.5 / 1.0) < 0.001 or v.ram_damage > normal * 1.4, "+50 %% ram at 100 momentum: %f vs %f" % [v.ram_damage, normal])
	assert_true(v.ramming)


func test_ram_costs_momentum_unless_ram_free() -> void:
	var free: SimWorld = _world(BUMPER, false)
	var costly: SimWorld = _world(DRIFT, false)
	for w: SimWorld in [free, costly]:
		w.vehicles[0].weapons.clear()
		w.apply_command(1, {"type": "set_drive", "value": "charge"})
		for k in 5:
			_enemy(w, SimWorld.MITE, 40.0 + 18.0 * float(k), 1.0e6, float(k % 2) * 6.0)
		w.vehicles[0].momentum = 60.0
		for t in 20:
			w.step()
	assert_true(free.vehicles[0].momentum >= 60.0, "ram bumper: ramming is free, got %f" % free.vehicles[0].momentum)
	assert_true(costly.vehicles[0].momentum < free.vehicles[0].momentum - 8.0, "without it each ram hit costs, got %f vs %f" % [costly.vehicles[0].momentum, free.vehicles[0].momentum])


# ---------------------------------------------------------------- ram effects

func test_sparks_burst_with_throttle() -> void:
	var w: SimWorld = _world(BUMPER, false)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	w.apply_command(1, {"type": "set_drive", "value": "charge"})
	var big: int = _enemy(w, SimWorld.MITE, 24.0, 1.0e6)
	var side: int = _enemy(w, SimWorld.MITE, 24.0, 1.0e6, 22.0)
	var side_id: int = w.enemy_id[side]
	var sparks: int = _count(w, 60, "sparks")
	assert_true(sparks >= 3 and sparks <= 8, "a burst every 15 ticks per target, got %d" % sparks)
	var hp_side: float = w.enemy_hp[_find(w, side_id)]
	assert_true(hp_side < 1.0e6 - 15.0, "the burst hurt the neighbour: %f" % hp_side)
	assert_ne(big, -1)
	# Without the bumper no sparks.
	var w2: SimWorld = _world(DRIFT, false)
	w2.vehicles[0].weapons.clear()
	w2.apply_command(1, {"type": "set_drive", "value": "charge"})
	_enemy(w2, SimWorld.MITE, 24.0, 1.0e6)
	assert_eq(_count(w2, 60, "sparks"), 0)


func test_battering_ram_throws_enemies() -> void:
	var far: Array = []
	for ids: Array in [BATTER, BUMPER]:
		var w: SimWorld = _world(ids, false)
		w.vehicles[0].weapons.clear()
		w.apply_command(1, {"type": "set_drive", "value": "charge"})
		var i: int = _enemy(w, SimWorld.MITE, 24.0, 1.0e6)
		var id: int = w.enemy_id[i]
		var best: float = 0.0
		for t in 12:
			w.step()
			var j: int = _find(w, id)
			best = maxf(best, w.enemy_pos[j].distance_to(w.vehicles[0].pos))
		far.append(best)
	assert_true(float(far[0]) > float(far[1]) + 12.0, "knocked back: %f vs %f" % [far[0], far[1]])


func test_knock_immune_rivals_are_not_shoved() -> void:
	var w := SimWorld.new(3)
	w.spawning_enabled = false
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	var b: SimVehicle = w.add_vehicle(2, Vector2(1030, 700))
	var c: SimVehicle = w.add_vehicle(3, Vector2(1000, 760))
	a.scrap = 99999
	b.scrap = 99999
	c.scrap = 99999
	for id: String in BATTER:
		Tech.buy(a, id, 1)
	for id: String in CAGE:
		Tech.buy(b, id, 1)
	c.pos = Vector2(1030, 760)
	var b0: Vector2 = b.pos
	Mobility.ram_hit_vehicle(w, a, b)
	assert_eq(b.pos, b0, "roll cage: no knock-back")
	var c0: Vector2 = c.pos
	Mobility.ram_hit_vehicle(w, a, c)
	assert_true(c.pos.distance_to(c0) > 15.0, "a plain rig is shoved")
	c0 = c.pos
	Mobility.ram_hit_vehicle(w, a, c)
	assert_eq(c.pos, c0, "throttled: not again within 15 ticks")


func test_dozer_keeps_mites_off_the_hull() -> void:
	var lost: Array = []
	for ids: Array in [DOZER, ["engineering_frame", "engineering_welder", "engineering_pickup"]]:
		var w: SimWorld = _world(ids)
		var v: SimVehicle = w.vehicles[0]
		v.weapons.clear()
		w.round = 7  # full contact damage (mites are weak since the horde pass)
		v.heading = 0.0
		v.max_hp = 5000.0
		v.hp = 5000.0
		for k in 4:
			_enemy(w, SimWorld.MITE, 60.0 + 4.0 * float(k), 1.0e6, float(k) * 5.0 - 7.0)
		for t in 60:
			w.step()
		lost.append(5000.0 - v.hp)
	assert_true(float(lost[0]) < float(lost[1]) * 0.35, "the blade shoves mites aside: %f vs %f" % [lost[0], lost[1]])


# ---------------------------------------------------------------- dodge, ghost, juggernaut, turbine

func test_dodge_chance_and_determinism() -> void:
	var w: SimWorld = _world(FEATHER)
	var v: SimVehicle = w.vehicles[0]
	assert_true(absf(Mobility.dodge_chance(v) - 0.10) < 0.001, "featherweight: 10 %")
	var dodges: int = 0
	var hits: int = 0
	for k in 3000:
		var hp0: float = v.hp
		w.events.clear()
		w._damage_vehicle(v, 5.0, -1, false, SimWorld.SRC_ACID)
		if v.hp == hp0:
			dodges += 1
			assert_eq(w.events.size(), 1)
			assert_eq(w.events[0]["type"], "dodge")
		else:
			hits += 1
	assert_true(dodges > 230 and dodges < 370, "about 10 %% of 3000, got %d" % dodges)
	# Same seed, same dodges.
	var w2: SimWorld = _world(FEATHER)
	var seq_a: String = ""
	var seq_b: String = ""
	var wb: SimWorld = _world(FEATHER)
	for k in 200:
		var h1: float = w2.vehicles[0].hp
		w2._damage_vehicle(w2.vehicles[0], 5.0, -1, false, SimWorld.SRC_ACID)
		seq_a += "d" if w2.vehicles[0].hp == h1 else "h"
		var h2: float = wb.vehicles[0].hp
		wb._damage_vehicle(wb.vehicles[0], 5.0, -1, false, SimWorld.SRC_ACID)
		seq_b += "d" if wb.vehicles[0].hp == h2 else "h"
	assert_eq(seq_a, seq_b, "dodging is deterministic")
	# Contact damage is never dodged (it is not a discrete hit).
	var hp1: float = v.hp
	for k in 100:
		w._damage_vehicle(v, 1.0, -1, false, SimWorld.SRC_MITE)
	assert_eq(hp1 - v.hp, 100.0)
	assert_eq(hits + dodges, 3000)


func test_ghost_runner_dodges_above_70_momentum() -> void:
	var w: SimWorld = _world(GHOST)
	var v: SimVehicle = w.vehicles[0]
	v.momentum = 60.0
	assert_eq(Mobility.dodge_chance(v), 0.0)
	v.momentum = 71.0
	assert_true(absf(Mobility.dodge_chance(v) - 0.20) < 0.001)
	var dodges: int = 0
	for k in 1000:
		var hp0: float = v.hp
		w._damage_vehicle(v, 5.0, -1, false, SimWorld.SRC_ACID)
		v.momentum = 80.0
		if v.hp == hp0:
			dodges += 1
	assert_true(dodges > 150 and dodges < 250, "about 20 %%, got %d" % dodges)


func test_juggernaut_armour_and_doctrine_fallback() -> void:
	var w: SimWorld = _world(JUGG, false)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	v.momentum = 100.0
	w.step()
	assert_true(absf(v.eff_armor - (v.armor + 5.0)) < 0.2, "armour + momentum / 20, got %f vs %f" % [v.eff_armor, v.armor])
	v.momentum = 0.0
	v.vel = Vector2.ZERO
	# Backing away is out: kite becomes circle, flee rules are refused.
	w.apply_command(1, {"type": "set_drive", "value": "kite"})
	_enemy(w, SimWorld.MITE, 200.0, 1.0e6)
	w.step()
	assert_eq(v.eff_drive, "circle", "kite falls back to circle")
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp<90|drive:flee"})
	assert_true(v.rules.is_empty() or encode_ok(v), "flee is not available")
	assert_false(Doctrine.actions_for("rig", v).has("drive:flee"))
	assert_false(Doctrine.actions_for("rig", v).has("drive:kite"))
	assert_true(Doctrine.actions_for("rig", v).has("drive:charge"))
	# The sim also guards a rule that slipped in before the keystone was bought.
	v.rules = Doctrine.parse("hp>0|drive:flee", "rig")
	w.step()
	assert_ne(v.eff_drive, "flee")
	# A plain rig keeps both.
	var plain: SimWorld = _world([])
	assert_true(Doctrine.actions_for("rig", plain.vehicles[0]).has("drive:flee"))


func encode_ok(v: SimVehicle) -> bool:
	return Doctrine.encode(v.rules).find("flee") < 0


func test_turbine_boom() -> void:
	var w: SimWorld = _world(TURBINE)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	v.ab_cd[0] = 99999  # keep the auto nitro from spending the momentum
	var i: int = _enemy(w, SimWorld.MITE, 30.0, 1.0e6)
	var id: int = w.enemy_id[i]
	var far: int = _enemy(w, SimWorld.MITE, 120.0, 1.0e6)
	var far_id: int = w.enemy_id[far]
	v.momentum = 100.0
	w.step()
	var hp: float = w.enemy_hp[_find(w, id)]
	assert_true(absf(1.0e6 - hp - 30.0) < 0.5, "30 damage, got %f" % (1.0e6 - hp))
	assert_eq(w.enemy_hp[_find(w, far_id)], 1.0e6, "outside 40 px: untouched")
	var booms: int = 1
	for t in 320:
		v.momentum = 100.0
		w.step()
		for e in w.events:
			if e["type"] == "boom":
				booms += 1
	assert_eq(booms, 2, "one boom per 10 s while the bar is full")
	# Below full momentum nothing happens.
	var w2: SimWorld = _world(TURBINE)
	w2.vehicles[0].weapons.clear()
	_enemy(w2, SimWorld.MITE, 30.0, 100.0)
	w2.vehicles[0].momentum = 90.0
	assert_eq(_count(w2, 5, "boom"), 0)


# ---------------------------------------------------------------- chassis armour

func test_scrap_armour_sheds_plates_until_the_workshop() -> void:
	var w: SimWorld = _world(SCRAP_ARMOUR)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	v.max_hp = 400.0
	v.hp = 400.0
	var a0: float = v.armor
	assert_true(a0 >= 4.0, "frame 1 + scrap armour 3")
	w._damage_vehicle(v, 30.0, -1, true, SimWorld.SRC_PLAYER)
	assert_eq(v.armor, a0, "30 is under 15 % of 400: nothing shed")
	w._damage_vehicle(v, 90.0, -1, true, SimWorld.SRC_ACID)
	assert_eq(v.armor, a0 - 1.0, "a hit over 15 % of max hp tears off a plate")
	assert_eq(v.shed, 1)
	w.step()
	var plates: int = 0
	for k in w.proj_count:
		if w.proj_owner[k] == 0 and absf(w.proj_damage[k] - 20.0) < 0.5:
			plates += 1
	assert_eq(plates, 1, "the plate flies off as a 20 damage projectile")
	# Recomputing (buying something) keeps it off; the workshop refits it.
	Cards.recompute(v)
	assert_eq(v.armor, a0 - 1.0)
	w._begin_workshop()
	assert_eq(v.shed, 0)
	assert_eq(v.armor, a0)


func test_reactive_plates_cut_acid() -> void:
	var react: SimWorld = _world(REACTIVE)
	var plain: SimWorld = _world(["engineering_frame", "engineering_welder", "engineering_pickup"])
	var rv: SimVehicle = react.vehicles[0]
	var pv: SimVehicle = plain.vehicles[0]
	rv.armor = 0.0
	rv.eff_armor = 0.0
	pv.armor = 0.0
	pv.eff_armor = 0.0
	react._damage_vehicle(rv, 10.0, -1, true, SimWorld.SRC_ACID)
	plain._damage_vehicle(pv, 10.0, -1, true, SimWorld.SRC_ACID)
	assert_true(absf((1.0e6 - rv.hp) - 7.0) < 0.01, "acid -30 %%: %f" % (1.0e6 - rv.hp))
	assert_true(absf((1.0e6 - pv.hp) - 10.0) < 0.01)
	react._damage_vehicle(rv, 10.0, -1, true, SimWorld.SRC_MITE)
	assert_true(absf((1.0e6 - rv.hp) - 17.0) < 0.01, "other sources are unchanged")


# ---------------------------------------------------------------- jammer and spit warning

func test_jammer_disables_the_last_rule_slot_and_slows_aliens() -> void:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	w.round = 4
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	var b: SimVehicle = w.add_vehicle(2, Vector2(1150, 700))
	a.scrap = 99999
	for id: String in JAMMER:
		assert_true(Tech.buy(a, id, 1), id)
	assert_true(float(a.tech_fx.get("jammer", 0.0)) >= 200.0)
	b.max_hp = 1.0e6
	b.hp = 1.0e6
	a.max_hp = 1.0e6
	a.hp = 1.0e6
	w.apply_command(2, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold;hp>0|target:weakest"})
	assert_eq(Doctrine.slots(b), 2)
	w.step()
	assert_eq(b.jammed_by, a.id, "inside the 200 px field")
	assert_eq(Doctrine.active_slots(b), 1, "the last slot is off")
	assert_eq(b.rule_live, 1, "only the first rule runs")
	assert_eq(a.jammed_by, -1)
	b.pos = Vector2(1400, 700)
	w.step()
	assert_eq(b.jammed_by, -1, "out of range: slots are back")
	assert_eq(b.rule_live, 3)
	# Aliens near the jammer crawl: -20 % speed.
	var near: SimWorld = _world(JAMMER)
	var base: SimWorld = _world(["electronics_rangefinder"])
	var dist: Array = []
	for ww: SimWorld in [near, base]:
		ww.vehicles[0].weapons.clear()
		_enemy(ww, SimWorld.MITE, 190.0, 1.0e6)
		ww.vehicles[0].max_hp = 1.0e9
		var x0: float = ww.enemy_pos[0].x
		for t in 20:
			ww.step()
		dist.append(x0 - ww.enemy_pos[0].x)
	assert_true(float(dist[0]) < float(dist[1]) * 0.9 and float(dist[0]) > float(dist[1]) * 0.7, "-20 %%: %f vs %f" % [dist[0], dist[1]])


func test_spit_warning_covers_the_second_before_a_spit() -> void:
	var w: SimWorld = _world(["electronics_rangefinder", "electronics_radar"])
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	assert_true(float(v.tech_fx.get("spit_warn", 0.0)) > 0.0)
	var i: int = _enemy(w, SimWorld.SPITTER, 200.0, 1.0e6)
	var id: int = w.enemy_id[i]
	var warned: int = 0
	var spits: int = 0
	w.step()
	for t in 180:
		var tick_before: int = w.tick
		w.step()
		for e in w.events:
			if e["type"] == "spit":
				spits += 1
				assert_true(SimWorld.spit_warning(tick_before - 1, id), "warned the tick before")
				assert_false(SimWorld.spit_warning(tick_before, id), "the flag is down at the shot")
		if SimWorld.spit_warning(tick_before, id):
			warned += 1
	assert_true(spits >= 2, "the spitter spat")
	assert_eq(warned, 90, "half of every 2 s period is flagged (the last second)")


# ---------------------------------------------------------------- snapshot and determinism

func test_snapshot_carries_mobility_state() -> void:
	var w: SimWorld = _world(JUGG)
	var v: SimVehicle = w.vehicles[0]
	v.momentum = 73.5
	v.boom_cd = 120
	v.shed = 2
	v.jammed_by = 3
	v.mark_id = 17
	v.mark_pos = Vector2(1100, 720)
	v.decoy_ticks = 12
	v.decoy_pos = Vector2(900, 650)
	v.nitro_count = 5
	var c := SimWorld.new(1)
	c.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c, Snapshot.encode(w)))
	var cv: SimVehicle = c.vehicles[0]
	assert_true(absf(cv.momentum - 73.5) < 0.001)
	assert_eq(cv.boom_cd, 120)
	assert_eq(cv.jammed_by, 3)
	assert_eq(cv.mark_id, 17)
	assert_eq(cv.mark_pos, Vector2(1100, 720))
	assert_eq(cv.decoy_ticks, 12)
	assert_eq(cv.decoy_pos, Vector2(900, 650))
	assert_eq(cv.nitro_count, 5)
	assert_eq(cv.shed, 2)
	assert_true(Mobility.is_juggernaut(cv), "tech fx follow from the tech list")
	assert_eq(Snapshot.VERSION, 13)
	# A rig with none of it pays one byte for the whole block.
	var plain: SimWorld = _world([])
	var with_state: PackedByteArray = Snapshot.encode(w)
	assert_gt(float(with_state.size()), float(Snapshot.encode(plain).size()))


func test_determinism_with_mobility() -> void:
	var sums: Array = []
	for run in 2:
		var w: SimWorld = _world(TURBINE, false, 11)
		w.spawning_enabled = true
		w.vehicles[0].max_hp = 400.0
		w.vehicles[0].hp = 400.0
		w.apply_command(1, {"type": "set_drive", "value": "charge"})
		for t in 600:
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1], "same seed, same world")
	var w2: SimWorld = _world(TURBINE, false, 11)
	var base: int = w2.checksum()
	w2.vehicles[0].momentum = 40.0
	assert_ne(w2.checksum(), base, "momentum is part of the checksum")
