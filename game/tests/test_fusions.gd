extends TestCase
## Tech tree v2.3 stage 3, the eleven fusions: Thermite Ram, Spotter, Hot Rod, Barbed Wire, Lucky Strike, Fortified Relay,
## Burning Wake, War Machine, Scrap Storm, Junkyard Drone and Thunderclap (effects, caps, throttles), respec dormancy,
## snapshot and determinism.


## Buys `ids` in order, each with the nodes it needs first (Tech.next_step).
func _own(v: SimVehicle, ids: Array) -> void:
	v.scrap = 99999
	for id: String in ids:
		for _i in 12:
			if v.tech.has(id):
				break
			var step: String = Tech.next_step(v, id)
			assert_true(Tech.buy(v, step, 1), "buy " + step)
		assert_true(v.tech.has(id), "owns " + id)
	assert_true(Tech.active(v, ids[ids.size() - 1]))


## A one-rig world (round 1, no spawner) whose rig owns `ids` (and what they need); it is tough and stands still.
func _world(ids: Array, p_seed: int = 7) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	w.fast_rounds = true
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	_own(v, ids)
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	v.invuln_ticks = 0
	v.scrap = 0
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


func _enemy(w: SimWorld, kind: int, dx: float, hp: float, dy: float = 0.0) -> int:
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(kind, v.pos + Vector2(dx, dy))
	var i: int = w.enemy_count - 1
	w.enemy_hp[i] = hp
	w.rebuild_derived()
	return i


func _find(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1


func _count(w: SimWorld, n: int, type: String) -> int:
	var c: int = 0
	for t in n:
		w.step()
		for e in w.events:
			if e["type"] == type:
				c += 1
	return c


func _has_event(w: SimWorld, type: String) -> bool:
	for e in w.events:
		if e["type"] == type:
			return true
	return false


## Makes enemy `i` the rig's focus target (focus-fire kill conditions).
func _focus(w: SimWorld, i: int) -> void:
	var v: SimVehicle = w.vehicles[0]
	v.focus = true
	v.target_kind = 1
	v.target_index = i
	v.target_id = w.enemy_id[i]


# ---------------------------------------------------------------- thermite ram

func test_thermite_sparks_reach_45px_ignite_and_throw_shrapnel() -> void:
	var w: SimWorld = _world(["fusion_thermite"])
	var v: SimVehicle = w.vehicles[0]
	assert_true(Tech.active(v, "fusion_thermite"))
	v.weapons.clear()
	var rammed: int = _enemy(w, SimWorld.MITE, 24.0, 1.0e6)
	var near: int = _enemy(w, SimWorld.MITE, 24.0, 1.0e6, 40.0)  # 40 px from the rammed one: outside plain sparks (30)
	var weak: int = _enemy(w, SimWorld.MITE, 24.0, 10.0, -42.0)
	var near_id: int = w.enemy_id[near]
	var weak_id: int = w.enemy_id[weak]
	v.momentum = 10.0
	w.events.clear()
	Mobility.ram_hit(w, v, rammed)
	var hp: float = w.enemy_hp[_find(w, near_id)]
	assert_true(hp <= 1.0e6 - Mobility.SPARKS_DAMAGE + 0.5, "the 45 px burst hurt the neighbour: %f" % hp)
	assert_true(w.enemy_burn_ticks[_find(w, near_id)] > 0, "and set it on fire")
	assert_true(w.enemy_hp[_find(w, weak_id)] <= 0.0, "15 damage kills the weak one")
	assert_true(_has_event(w, "shrapnel"), "its death throws shrapnel")
	assert_eq(w._pending_proj.size(), 3, "three shards queued")
	# plain bumper: 30 px, no fire
	var w2: SimWorld = _world(["propulsion_bumper"])
	w2.vehicles[0].weapons.clear()
	var r2: int = _enemy(w2, SimWorld.MITE, 24.0, 1.0e6)
	var n2: int = _enemy(w2, SimWorld.MITE, 24.0, 1.0e6, 40.0)
	Mobility.ram_hit(w2, w2.vehicles[0], r2)
	assert_eq(w2.enemy_hp[n2], 1.0e6, "plain sparks stop at 30 px")
	assert_eq(w2.enemy_burn_ticks[n2], 0)


# ---------------------------------------------------------------- spotter

func test_spotter_cannon_never_misses_spitters_and_hits_harder() -> void:
	var losses: Array[float] = []
	for ids: Array in [["fusion_spotter"], ["electronics_radar", "ballistics_heavy_shells"]]:
		var w: SimWorld = _world(ids)
		var v: SimVehicle = w.vehicles[0]
		v.cards = {"cannon": 1}
		Cards.recompute(v)
		var s: int = _enemy(w, SimWorld.SPITTER, 150.0, 1.0e6)
		var sid: int = w.enemy_id[s]
		var shot: bool = false
		for t in 60:
			var j: int = _find(w, sid)
			w.stun_enemy(j, 200)  # stands still, so a plain shell hits too and the damage is comparable
			w.step()
			if _has_event(w, "fire") and not shot:
				shot = true
				if ids.size() == 1:
					assert_true(w.proj_pos[0].distance_to(w.enemy_pos[_find(w, sid)]) < 20.0, "the shell is born on the spitter")
			if shot and w.proj_count == 0:
				break
		assert_true(shot)
		losses.append(1.0e6 - w.enemy_hp[_find(w, sid)])
	assert_true(losses[1] > 0.0)
	assert_true(absf(losses[0] / losses[1] - 1.5) < 0.05, "+50 %% vs spitters: %f vs %f" % [losses[0], losses[1]])
	# other aliens are not boosted
	var w3: SimWorld = _world(["fusion_spotter"])
	var v3: SimVehicle = w3.vehicles[0]
	v3.cards = {"cannon": 1}
	Cards.recompute(v3)
	var m: int = _enemy(w3, SimWorld.MITE, 150.0, 1.0e6)
	for t in 40:
		w3.stun_enemy(m, 200)
		w3.step()
		if w3.proj_count == 0 and w3.enemy_hp[m] < 1.0e6:
			break
	var expect: float = float(v3.weapons[0]["damage"])
	var took: float = 1.0e6 - w3.enemy_hp[m]  # the fire ammo adds a little burn on top
	assert_true(took >= expect - 0.5 and took < expect * 1.25, "mite takes the plain damage: %f vs %f" % [took, expect])


# ---------------------------------------------------------------- hot rod

func test_hot_rod_repairs_while_drifting() -> void:
	var w: SimWorld = _world(["fusion_hot_rod"])
	var v: SimVehicle = w.vehicles[0]
	v.max_hp = 1000.0
	v.hp = 500.0
	v.regen = 0.0
	v.drifting = true
	for t in 30:
		Fusions.tick(w, v)
	assert_true(absf(v.hp - 510.0) < 0.01, "10 hp/s for 1 s: %f" % v.hp)
	v.drifting = false
	for t in 30:
		Fusions.tick(w, v)
	assert_true(absf(v.hp - 510.0) < 0.01, "nothing while straight")
	# the drift flag follows hard turns at speed
	var w2: SimWorld = _world(["propulsion_drift"])
	var v2: SimVehicle = w2.vehicles[0]
	v2.turn_diff = 0.6
	v2.vel = Vector2(90.0, 0.0)
	Mobility.update(w2, v2)
	assert_true(v2.drifting)
	v2.turn_diff = 0.1
	Mobility.update(w2, v2)
	assert_false(v2.drifting)
	v2.turn_diff = 0.6
	v2.vel = Vector2(10.0, 0.0)
	Mobility.update(w2, v2)
	assert_false(v2.drifting, "too slow to drift")


# ---------------------------------------------------------------- barbed wire

func test_barbed_wire_contact_kills_pay_scrap_up_to_the_cap() -> void:
	var w: SimWorld = _world(["fusion_barbed"])
	var v: SimVehicle = w.vehicles[0]
	v.scrap_mult = 1.0
	for k in 20:
		var i: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
		w._hit_enemy(i, 10.0, v.id, true)
	assert_eq(v.barbed_scrap, 45, "capped at 45 per round")
	assert_eq(v.scrap, 20 + 45, "20 mites + 15 x 3 barbed scrap")
	# a shot kill pays no barbed scrap
	var j: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
	var s0: int = v.scrap
	w._hit_enemy(j, 10.0, v.id)
	assert_eq(v.scrap, s0 + 1)
	assert_eq(v.barbed_scrap, 45)
	# the cap resets every round
	w.phase_ticks_left = 1
	w.step()
	w.phase_ticks_left = 1
	w.apply_command(1, {"type": "ready"})
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_COMBAT)
	assert_eq(v.barbed_scrap, 0)


# ---------------------------------------------------------------- lucky strike

func test_lucky_strike_bonus_offer_rate_limit() -> void:
	var w: SimWorld = _world(["fusion_lucky_strike"])
	var v: SimVehicle = w.vehicles[0]
	var kills: int = 0
	while v.bonus_offers == 0 and kills < 3000:
		var i: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
		_focus(w, i)
		w._hit_enemy(i, 10.0, v.id)
		kills += 1
	assert_eq(v.bonus_offers, 1, "a bonus offer after some focus kills (took %d)" % kills)
	assert_true(kills > 3, "a 2 %% chance, not a sure thing")
	assert_eq(v.lucky_round, 1)
	# at most one per 2 rounds: no second one now (still banked or not), nor next round
	var banked: int = v.bonus_offers
	for k in 400:
		var i2: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
		_focus(w, i2)
		w._hit_enemy(i2, 10.0, v.id)
	assert_eq(v.bonus_offers, banked, "one at a time")
	v.bonus_offers = 0
	w.round = 2
	for k in 600:
		var i3: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
		_focus(w, i3)
		w._hit_enemy(i3, 10.0, v.id)
	assert_eq(v.bonus_offers, 0, "not in the very next round")
	w.round = 3
	kills = 0
	while v.bonus_offers == 0 and kills < 3000:
		var i4: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
		_focus(w, i4)
		w._hit_enemy(i4, 10.0, v.id)
		kills += 1
	assert_eq(v.bonus_offers, 1, "two rounds later it can happen again")
	# kills that are not focus fire never roll
	var w2: SimWorld = _world(["fusion_lucky_strike"])
	for k in 800:
		var j: int = _enemy(w2, SimWorld.MITE, 50.0, 1.0)
		w2.vehicles[0].focus = false
		w2._hit_enemy(j, 10.0, 0)
	assert_eq(w2.vehicles[0].bonus_offers, 0)


func test_bonus_offer_gives_a_fourth_card() -> void:
	var w: SimWorld = _world(["fusion_lucky_strike"])
	var v: SimVehicle = w.vehicles[0]
	v.bonus_offers = 1
	w.phase_ticks_left = 1
	w.step()
	assert_eq(w.phase, SimWorld.PHASE_WORKSHOP)
	assert_eq(v.offers.size(), 4, "three cards and the bonus one")
	assert_eq(v.bonus_offers, 0)
	w.apply_command(1, {"type": "pick_card", "value": 3})
	assert_true(v.picked, "the fourth card can be picked")
	w.apply_command(1, {"type": "ready"})
	w.step()
	w.phase_ticks_left = 1
	w.step()
	assert_eq(v.offers.size(), 3, "back to three")


# ---------------------------------------------------------------- fortified relay

func test_fortified_focus_kills_repair_in_stacks() -> void:
	var w: SimWorld = _world(["fusion_fortified"])
	var v: SimVehicle = w.vehicles[0]
	v.max_hp = 1000.0
	v.hp = 100.0
	v.regen = 0.0
	var seen: Array[float] = []
	for k in 4:
		var i: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
		_focus(w, i)
		w._hit_enemy(i, 10.0, v.id)
		seen.append(v.fort_regen)
	assert_eq(seen, [2.0, 4.0, 6.0, 6.0] as Array[float], "+2 per kill, max +6 hp/s")
	for t in 90:
		Fusions.tick(w, v)
	assert_true(absf(v.hp - (100.0 + 6.0 * 3.0)) < 0.05, "6 hp/s for 3 s: %f" % v.hp)
	assert_eq(v.fort_regen, 0.0, "worn off after 3 s")
	var h: float = v.hp
	for t in 30:
		Fusions.tick(w, v)
	assert_eq(v.hp, h)
	# a non-focus kill does nothing
	var j: int = _enemy(w, SimWorld.MITE, 50.0, 1.0)
	v.focus = false
	w._hit_enemy(j, 10.0, v.id)
	assert_eq(v.fort_regen, 0.0)


# ---------------------------------------------------------------- burning wake

func test_burning_wake_leaves_fire_zones_when_drifting_or_on_nitro() -> void:
	var w: SimWorld = _world(["fusion_burning_wake"])
	var v: SimVehicle = w.vehicles[0]
	var fires := func() -> int:
		var n: int = 0
		for z in w.zone_count:
			if w.zone_kind[z] == SimWorld.ZONE_FIRE:
				n += 1
		return n
	v.drifting = false
	for t in 30:
		w.tick += 1
		Fusions.tick(w, v)
	assert_eq(fires.call(), 0, "no drift, no fire")
	v.drifting = true
	for t in 30:
		w.tick += 1
		v.pos += Vector2(6.0, 0.0)
		Fusions.tick(w, v)
	assert_true(int(fires.call()) >= 3, "a trail while drifting: %d" % int(fires.call()))
	# nitro also lays fire
	var w2: SimWorld = _world(["fusion_burning_wake"])
	var v2: SimVehicle = w2.vehicles[0]
	v2.nitro_ticks = 60
	for t in 30:
		w2.tick += 1
		v2.pos += Vector2(6.0, 0.0)
		Fusions.tick(w2, v2)
	assert_true(w2.zone_count >= 3)
	# the fire burns aliens that stand in it
	var e: int = _enemy(w, SimWorld.MITE, 0.0, 100.0)
	w.enemy_pos[e] = w.zone_pos[0]
	w.rebuild_derived()
	var hp0: float = w.enemy_hp[e]
	w.step()
	assert_true(w.enemy_hp[e] < hp0)
	assert_true(w.enemy_burn_ticks[e] > 0)
	# without the fusion: nothing
	var w3: SimWorld = _world(["propulsion_drift"])
	w3.vehicles[0].drifting = true
	for t in 30:
		w3.tick += 1
		Fusions.tick(w3, w3.vehicles[0])
	assert_eq(w3.zone_count, 0)


# ---------------------------------------------------------------- war machine

func test_war_machine_shockwave_costs_momentum_and_throttles_per_target() -> void:
	var w: SimWorld = _world(["fusion_war_machine"])
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	var a: int = _enemy(w, SimWorld.MITE, 20.0, 1.0e6)
	var b: int = _enemy(w, SimWorld.MITE, 30.0, 1.0e6, 10.0)
	var c: int = _enemy(w, SimWorld.MITE, 100.0, 1.0e6)  # outside 60 px
	var b_id: int = w.enemy_id[b]
	var c_id: int = w.enemy_id[c]
	v.momentum = 100.0
	var pre_b: Vector2 = w.enemy_pos[b]
	w.events.clear()
	Mobility.ram_hit(w, v, a)
	assert_true(_has_event(w, "shockwave"))
	assert_eq(v.momentum, 60.0, "costs 40 momentum (the bumper rams for free)")
	assert_true(w.enemy_hp[_find(w, b_id)] <= 1.0e6 - 30.0 + 0.5, "30 damage inside 60 px")
	assert_eq(w.enemy_hp[_find(w, c_id)], 1.0e6, "nothing outside")
	assert_true(w.enemy_pos[_find(w, b_id)].distance_to(pre_b) > 15.0, "knocked back")
	# the same targets are immune for 30 ticks
	var hp_b: float = w.enemy_hp[_find(w, b_id)]
	w.tick += 20
	w.enemy_ram_tick[a] = -1000  # the ram effect throttle itself (15 ticks) is separate
	Mobility.ram_hit(w, v, a)
	assert_eq(w.enemy_hp[_find(w, b_id)], hp_b - Mobility.SPARKS_DAMAGE, "1 s per target: only the bumper's sparks hit again")
	assert_eq(v.momentum, 60.0, "and no wave, no cost")
	w.tick += 15
	w.enemy_ram_tick[a] = -1000
	Mobility.ram_hit(w, v, a)
	assert_true(w.enemy_hp[_find(w, b_id)] <= hp_b - Mobility.SPARKS_DAMAGE * 2.0 - Fusions.WAR_DAMAGE + 0.5, "after a second the wave hits again")
	assert_eq(v.momentum, 20.0)
	# too little momentum: no wave
	v.momentum = 39.0
	w.tick += 40
	w.enemy_ram_tick[a] = -1000
	hp_b = w.enemy_hp[_find(w, b_id)]
	Mobility.ram_hit(w, v, a)
	assert_eq(w.enemy_hp[_find(w, b_id)], hp_b - Mobility.SPARKS_DAMAGE, "sparks only")
	assert_eq(v.momentum, 39.0)


func test_war_machine_shockwave_hits_rivals() -> void:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	w.round = 4
	var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
	var b: SimVehicle = w.add_vehicle(2, Vector2(1040, 700))
	_own(a, ["fusion_war_machine"])
	a.invuln_ticks = 0
	b.invuln_ticks = 0
	a.momentum = 100.0
	var hp: float = b.hp
	Fusions.war_machine(w, a)
	assert_true(b.hp < hp, "30 damage to the rival (armour aside)")
	assert_eq(a.momentum, 60.0)


# ---------------------------------------------------------------- scrap storm

func test_scrap_storm_splash_kills_throw_shards_and_scrap() -> void:
	var w: SimWorld = _world(["fusion_scrap_storm"])
	var v: SimVehicle = w.vehicles[0]
	v.scrap_mult = 1.0
	var a: int = _enemy(w, SimWorld.MITE, 60.0, 5.0)
	var burning: int = _enemy(w, SimWorld.MITE, 70.0, 5.0)
	w._ignite(burning, 5.0, v.id)
	w._pending_proj.clear()
	w.events.clear()
	w._splash_damage(v.pos + Vector2(65.0, 0.0), 30.0, 50.0, v.id, -1)
	assert_eq(v.storm_count, 2)
	assert_eq(v.scrap, 2 + 2, "two kills (1 each) plus 1 scrap per burst")
	assert_eq(w._pending_proj.size(), 6, "3 shards per burst")
	var burn_shards: int = 0
	for e: Array in w._pending_proj:
		assert_eq(e[3], 25.0, "25 damage")
		assert_true((int(e[6]) & Ammo.SHARD_BIT) != 0, "a shard never shatters again")
		if (int(e[6]) & Ammo.FIRE_BIT) != 0:
			burn_shards += 1
	assert_eq(burn_shards, 3, "only the burning victim's shards burn")
	assert_ne(a, -1)
	# direct (non-splash) kills do not storm
	var d: int = _enemy(w, SimWorld.MITE, 60.0, 5.0)
	w._pending_proj.clear()
	w._hit_enemy(d, 10.0, v.id)
	assert_eq(w._pending_proj.size(), 0)
	# cap 40 bursts per round
	for k in 60:
		_enemy(w, SimWorld.MITE, 60.0, 5.0)
	w._pending_proj.clear()
	w._splash_damage(v.pos + Vector2(60.0, 0.0), 30.0, 50.0, v.id, -1)
	assert_eq(v.storm_count, 40, "capped")
	# the shards are real projectiles once the loop flushes them
	var before: int = w.proj_count
	w._flush_pending()
	assert_true(w.proj_count > before)
	var shards: int = 0
	for p in w.proj_count:
		if (w.proj_ammo[p] & Ammo.SHARD_BIT) != 0 and is_equal_approx(w.proj_damage[p], 25.0):
			shards += 1
	assert_true(shards >= 3)


func test_scrap_storm_with_the_cannon_splash() -> void:
	var w: SimWorld = _world(["fusion_scrap_storm"])
	var v: SimVehicle = w.vehicles[0]
	v.cards = {"cannon": 3}
	Cards.recompute(v)
	assert_true(float(v.weapons[0]["splash"]) > 0.0, "heavy shells + cannon splash")
	for k in 6:
		_enemy(w, SimWorld.MITE, 120.0 + float(k % 3) * 6.0, 4.0, float(k) * 5.0)
	for t in 90:
		w.step()
	assert_true(v.storm_count > 0, "cannon splash kills set it off")


# ---------------------------------------------------------------- junkyard drone

func test_junkyard_drone_hits_about_once_a_second() -> void:
	var w: SimWorld = _world(["fusion_junkyard"])
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	var near: int = _enemy(w, SimWorld.MITE, 60.0, 1.0e6)
	var far: int = _enemy(w, SimWorld.MITE, 300.0, 1.0e6)
	var spitter: int = _enemy(w, SimWorld.SPITTER, 40.0, 1.0e6)
	var ids: Array[int] = [w.enemy_id[near], w.enemy_id[far], w.enemy_id[spitter]]
	for i in 3:  # stand still, so the distances stay as set
		w.enemy_status[_find(w, ids[i])] = 255
	var hits: int = _count(w, 90, "hit")
	assert_true(hits >= 2 and hits <= 4, "about one hit a second, got %d" % hits)
	var lost: float = 1.0e6 - w.enemy_hp[_find(w, ids[0])]
	assert_true(lost >= 29.9 and lost <= 60.1, "15 per hit on the nearest mite: %f" % lost)
	assert_eq(w.enemy_hp[_find(w, ids[1])], 1.0e6, "out of reach")
	assert_eq(w.enemy_hp[_find(w, ids[2])], 1.0e6, "only mites when nothing is focused")
	# a focus target takes the hits instead
	var w2: SimWorld = _world(["fusion_junkyard"])
	var v2: SimVehicle = w2.vehicles[0]
	v2.weapons.clear()
	var m: int = _enemy(w2, SimWorld.MITE, 60.0, 1.0e6)
	var t2: int = _enemy(w2, SimWorld.BOULDER, 100.0, 1.0e6)
	var tid: int = w2.enemy_id[t2]
	var mid: int = w2.enemy_id[m]
	for i in [m, t2]:
		w2.enemy_status[i] = 255
	for t in 40:
		_focus(w2, _find(w2, tid))
		v2.focus = true
		Fusions.tick(w2, v2)
		w2.tick += 1
	assert_true(w2.enemy_hp[_find(w2, tid)] < 1.0e6, "the focus target is hit")
	assert_eq(w2.enemy_hp[_find(w2, mid)], 1.0e6)
	# drone kills pay scrap like any kill
	var w3: SimWorld = _world(["fusion_junkyard"])
	w3.vehicles[0].weapons.clear()
	var k: int = _enemy(w3, SimWorld.MITE, 50.0, 10.0)
	assert_ne(k, -1)
	for t in 40:
		w3.step()
	assert_true(w3.vehicles[0].scrap >= 1 and w3.vehicles[0].kills >= 1)


# ---------------------------------------------------------------- thunderclap

func test_thunderclap_contact_kill_stuns_and_chains() -> void:
	var w: SimWorld = _world(["fusion_thunderclap"])
	var v: SimVehicle = w.vehicles[0]
	var dead: int = _enemy(w, SimWorld.MITE, 40.0, 1.0)
	var ring: int = _enemy(w, SimWorld.MITE, 40.0, 1.0e6, 20.0)  # inside the 50 px mini EMP
	var chain1: int = _enemy(w, SimWorld.MITE, 40.0, 1.0e6, 90.0)  # chain range
	var chain2: int = _enemy(w, SimWorld.MITE, 40.0, 1.0e6, -100.0)
	var chain3: int = _enemy(w, SimWorld.MITE, 40.0, 1.0e6, 140.0)  # a third one: not reached
	var far: int = _enemy(w, SimWorld.MITE, 40.0, 1.0e6, 400.0)
	var ids: Array[int] = []
	for i in [ring, chain1, chain2, chain3, far]:
		ids.append(w.enemy_id[i])
	w.events.clear()
	w._hit_enemy(dead, 10.0, v.id, true)
	var stunned: Array[bool] = []
	for id in ids:
		stunned.append((w.enemy_status[_find(w, id)] & 255) > 0)
	assert_eq(stunned, [true, true, true, false, false] as Array[bool], "EMP ring + 2 chain targets, nobody else")
	assert_eq(w.enemy_hp[_find(w, ids[1])], 1.0e6 - Fusions.CLAP_CHAIN_DAMAGE, "chain damage")
	assert_eq(w.enemy_hp[_find(w, ids[0])], 1.0e6, "the ring is only stunned")
	var chains: int = 0
	for e in w.events:
		if e["type"] == "chain":
			chains += 1
	assert_eq(chains, 3, "origin + 2 chain bolts")
	assert_eq(v.clap_cd, Fusions.CLAP_COOLDOWN)
	# 1 s stun
	assert_true((w.enemy_status[_find(w, ids[0])] & 255) <= 30)
	# cooldown: the next contact kill does nothing
	var dead2: int = _enemy(w, SimWorld.MITE, 40.0, 1.0)
	var calm: int = _enemy(w, SimWorld.MITE, 40.0, 1.0e6, 10.0)
	var calm_id: int = w.enemy_id[calm]
	w._hit_enemy(dead2, 10.0, v.id, true)
	assert_eq((w.enemy_status[_find(w, calm_id)] & 255), 0, "6 s cooldown")
	for t in Fusions.CLAP_COOLDOWN:
		Fusions.tick(w, v)
	assert_eq(v.clap_cd, 0)
	var dead3: int = _enemy(w, SimWorld.MITE, 40.0, 1.0)
	w._hit_enemy(dead3, 10.0, v.id, true)
	assert_true((w.enemy_status[_find(w, calm_id)] & 255) > 0, "ready again")
	# a plain shot kill does not trigger it
	var w2: SimWorld = _world(["fusion_thunderclap"])
	var d: int = _enemy(w2, SimWorld.MITE, 40.0, 1.0)
	var o: int = _enemy(w2, SimWorld.MITE, 40.0, 1.0e6, 10.0)
	var oid: int = w2.enemy_id[o]
	w2._hit_enemy(d, 10.0, 0)
	assert_eq((w2.enemy_status[_find(w2, oid)] & 255), 0)
	assert_eq(w2.vehicles[0].clap_cd, 0)


func test_thunderclap_by_spikes_in_a_real_fight() -> void:
	var w: SimWorld = _world(["fusion_thunderclap"])
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	for k in 8:
		_enemy(w, SimWorld.MITE, 22.0 + float(k) * 6.0, 1.0, float(k % 3) * 8.0 - 8.0)
	var claps: int = _count(w, 60, "chain")
	assert_true(claps >= 1, "spikes killed a mite and set it off")


# ---------------------------------------------------------------- dormancy, snapshot, determinism

func test_fusion_effects_follow_the_requirements() -> void:
	var w: SimWorld = _world(["fusion_thermite"])
	var v: SimVehicle = w.vehicles[0]
	assert_true(float(v.tech_fx.get("thermite", 0.0)) > 0.0)
	v.scrap = 5000
	assert_true(Tech.respec(v, "ballistics_belt_feed", "ballistics_heavy_shells", 1))
	assert_true(v.tech_dormant.has("fusion_thermite"), "the fusion went dormant")
	assert_eq(float(v.tech_fx.get("thermite", 0.0)), 0.0, "and its effect is off")
	var pre: int = v.scrap
	assert_true(Tech.respec(v, "ballistics_heavy_shells", "ballistics_belt_feed", 1))
	assert_true(Tech.buy(v, "fusion_thermite", 1))
	assert_eq(pre - v.scrap > 0, true)
	assert_true(float(v.tech_fx.get("thermite", 0.0)) > 0.0, "back after paying half")


func test_all_eleven_fusions_have_effects_in_the_table() -> void:
	var keys: Dictionary = {
		"fusion_thermite": "thermite", "fusion_spotter": "spotter", "fusion_hot_rod": "drift_regen", "fusion_barbed": "barbed",
		"fusion_lucky_strike": "lucky_strike", "fusion_fortified": "fortified", "fusion_burning_wake": "burning_wake",
		"fusion_war_machine": "war_machine", "fusion_scrap_storm": "scrap_storm", "fusion_junkyard": "junkyard",
		"fusion_thunderclap": "thunderclap",
	}
	assert_eq(Tech.fusions().size(), 11)
	for id: String in keys:
		var w: SimWorld = _world([id])
		assert_true(float(w.vehicles[0].tech_fx.get(keys[id], 0.0)) > 0.0, id)


func test_snapshot_round_trip_with_fusions() -> void:
	var w: SimWorld = _world(["fusion_burning_wake", "fusion_junkyard", "fusion_war_machine"])
	var v: SimVehicle = w.vehicles[0]
	for t in 30:
		w.step()
	var w2 := SimWorld.new(1)
	w2.add_vehicle(1, Vector2.ZERO)
	assert_true(Snapshot.apply(w2, Snapshot.encode(w)))
	var c: SimVehicle = w2.vehicles[0]
	assert_eq(c.tech, v.tech)
	assert_eq(c.tech_fx, v.tech_fx, "the fusion effects derive on the client too")
	assert_eq(w2.zone_count, w.zone_count)


func test_determinism_with_fusions_in_a_fight() -> void:
	var sums: Array[int] = []
	var kills: Array[int] = []
	for run in 2:
		var w := SimWorld.new(77)
		w.fast_rounds = true
		var a: SimVehicle = w.add_vehicle(1, Vector2(1000, 700))
		var b: SimVehicle = w.add_vehicle(2, Vector2(1200, 700))
		_own(a, ["fusion_lucky_strike", "fusion_scrap_storm", "fusion_thunderclap", "fusion_war_machine"])
		_own(b, ["fusion_junkyard", "fusion_burning_wake", "fusion_barbed"])
		a.cards = {"mg": 1, "cannon": 2}
		Cards.recompute(a)
		w.apply_command(1, {"type": "set_drive", "value": "charge"})
		w.apply_command(2, {"type": "set_drive", "value": "kite"})
		for t in 600:
			w.step()
		sums.append(w.checksum())
		kills.append(a.kills + b.kills)
	assert_eq(sums[0], sums[1], "same seed, same fusion world")
	assert_eq(kills[0], kills[1])
	assert_true(kills[0] > 0)
