extends TestCase
## Playtest round 1 fixes (balance iteration 3): flat spawn curve and alive caps, round and match stats,
## kill feed events, anti-passive FFA rules (fuel steal and drain), newbie protection, draft rules,
## interest cap scaling and the ramming changes. See docs/architecture.md.


func _world(players: int, round_n: int = 4, fast: bool = true) -> SimWorld:
	var w := SimWorld.new(31)
	w.fast_rounds = fast
	w.spawning_enabled = false
	w.round = round_n
	for i in players:
		var v := w.add_vehicle(i + 1, Vector2(200.0 + 400.0 * float(i), 360.0))
		v.weapons.clear()
		v.speed = 0.0
	return w


func _count_events(w: SimWorld, type: String) -> int:
	var n: int = 0
	for e in w.events:
		if e["type"] == type:
			n += 1
	return n


func _find_event(w: SimWorld, type: String) -> Dictionary:
	for e in w.events:
		if e["type"] == type:
			return e
	return {}


# ---------------------------------------------------------------- 1: spawn curve and caps

func test_spawn_rate_is_flat_in_the_last_15_seconds() -> void:
	var w := SimWorld.new(1)
	for r in [1, 3, 5, 9]:
		var dur: int = w.combat_duration(r)
		var flat_from: int = dur - int(SimWorld.SPAWN_RAMP_END_BEFORE * float(SimWorld.TICK_RATE))
		var at_flat: float = w.spawn_rate_at(r, flat_from)
		for t in range(flat_from, dur, 15):
			assert_eq(w.spawn_rate_at(r, t), at_flat, "round %d flat at tick %d" % [r, t])
		assert_gt(at_flat, w.spawn_rate_at(r, 0), "round %d still ramps earlier" % r)
	# The full-length round ramps 1.5 -> 3.5 per second (x round scaling) and stops at 45 s.
	assert_eq(w.spawn_rate_at(3, 0), SimWorld.SPAWN_RATE_START * SimWorld.spawn_rate_mult(3))
	assert_eq(w.spawn_rate_at(3, 1799), (SimWorld.SPAWN_RATE_START + 4.0 * SimWorld.SPAWN_RATE_RAMP) * SimWorld.spawn_rate_mult(3))


func test_boulder_and_spitter_alive_caps() -> void:
	# No vehicle: enemies pile up where they spawn, so the counts are the pure spawner output.
	var w := SimWorld.new(77)
	w.round = 12
	w.phase_ticks_left = 1800
	var spit_ticks: Array[int] = []
	var spit_sides: Array[int] = []
	for i in 1700:  # stop before the round ends (the retreat clears the field)
		var before: int = w.enemy_count
		w.step()
		for k in range(before, w.enemy_count):
			if w.enemy_kind[k] == SimWorld.SPITTER:
				spit_ticks.append(w.tick)
				var p: Vector2 = w.enemy_pos[k]
				spit_sides.append(0 if p.y < 20.0 else (1 if p.y > SimWorld.ARENA.end.y - 20.0 else (2 if p.x < 20.0 else 3)))
	var nb: int = 0
	var ns: int = 0
	for k in w.enemy_count:
		if w.enemy_kind[k] == SimWorld.BOULDER:
			nb += 1
		elif w.enemy_kind[k] == SimWorld.SPITTER:
			ns += 1
	assert_eq(nb, SimWorld.boulder_cap(12), "boulders stop at the cap")
	assert_eq(ns, SimWorld.spitter_cap(12), "spitters stop at the cap")
	assert_eq(SimWorld.boulder_cap(1), SimWorld.BOULDER_CAP_BASE + SimWorld.BOULDER_CAP_PER_ROUND)
	assert_eq(SimWorld.boulder_cap(99), SimWorld.BOULDER_CAP_MAX)
	assert_eq(SimWorld.spitter_cap(3), SimWorld.SPITTER_CAP_BASE + 1)
	assert_eq(SimWorld.spitter_cap(99), SimWorld.SPITTER_CAP_MAX)
	assert_gt(float(w.enemy_count), 100.0, "mites keep coming")
	for k in range(1, spit_ticks.size()):
		assert_true(spit_ticks[k] - spit_ticks[k - 1] >= SimWorld.SPITTER_SPAWN_GAP, "spitters are spread out in time")
		assert_ne(spit_sides[k], spit_sides[k - 1], "and never from the same edge twice in a row")


# ---------------------------------------------------------------- 2: stats

func test_contact_damage_is_attributed_by_enemy_kind() -> void:
	var w := _world(1, 1)
	var v: SimVehicle = w.vehicles[0]
	v.invuln_ticks = 0
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(20, 0))
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(-18, 0))
	w.rebuild_derived()
	for i in 10:
		w.step()
	var tk: Dictionary = v.round_stats["taken"]
	assert_gt(float(tk["boulder"]), float(tk["mite"]), "boulder hits harder")
	assert_gt(float(tk["mite"]), 0.0)
	assert_eq(float(tk["acid"]), 0.0)
	var total: float = float(tk["boulder"]) + float(tk["mite"]) + float(tk["spitter"])
	assert_lt(absf(total - (v.max_hp - v.hp)), 0.01, "the split adds up to the hp lost")


func test_death_record_and_acid_source() -> void:
	var w := _world(1, 3)
	var v: SimVehicle = w.vehicles[0]
	v.invuln_ticks = 0
	w.spawn_projectile(v.pos + Vector2(-30, 0), Vector2(170, 0), 1.0, 1.0e6, -1)
	for i in 20:
		w.step()
	assert_false(v.alive)
	var deaths: Array = v.round_stats["deaths"]
	assert_eq(deaths.size(), 1)
	assert_eq(deaths[0]["cause"], "acid")
	assert_eq(deaths[0]["killer"], -1)
	assert_eq(deaths[0]["killer_kind"], SimWorld.SPITTER)
	assert_gt(float(v.round_stats["taken"]["acid"]), 0.0)
	assert_eq(v.match_stats["deaths"], 1)
	assert_eq(v.round_stats["fuel_lost"], SimWorld.FUEL_LOSS)
	var ev: Dictionary = {}
	for e in w.events:
		if e["type"] == "vehicle_destroyed":
			ev = e
	# (the event is emitted on the tick of the hit; look through the stats if it already passed)
	if not ev.is_empty():
		assert_eq(ev["cause"], SimWorld.SRC_ACID)
		assert_eq(ev["killer"], -1)


func test_player_kill_event_stats_and_nemesis() -> void:
	var w := _world(3, 5)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.invuln_ticks = 0
	b.invuln_ticks = 0
	w.spawn_projectile(a.pos + Vector2(300, 0), Vector2.ZERO, 5.0, 1.0e6, a.id, 0, 0.0, 2)  # a cannon shell, parked on b
	w.proj_pos[0] = b.pos
	w.step()
	var kill: Dictionary = _find_event(w, "kill")
	assert_false(kill.is_empty(), "player kill event")
	assert_eq(kill["owner"], a.id, "killer")
	assert_eq(kill["victim"], b.id, "victim")
	assert_eq(kill["weapon"], 2, "weapon kind index (cannon)")
	assert_eq(kill["kind"], -1)
	var vd: Dictionary = _find_event(w, "vehicle_destroyed")
	assert_eq(vd["owner"], b.id)
	assert_eq(vd["cause"], SimWorld.SRC_PLAYER)
	assert_eq(vd["killer"], a.id)
	assert_eq(a.match_stats["player_kills"], 1)
	assert_eq(a.round_stats["kills_players"], 1)
	assert_eq(a.match_stats["top_victim"], b.id)
	assert_eq(b.match_stats["nemesis"], a.id)
	assert_eq(b.match_stats["deaths"], 1)
	assert_gt(float(a.round_stats["dealt_players"]), 0.0)
	assert_gt(float(b.round_stats["taken"]["rival"]), 0.0)
	assert_true(b.round_stats["taken_players"].has(a.id), "damage taken by attacker id")
	assert_eq(b.round_stats["deaths"][0]["killer"], a.id)
	assert_eq(b.round_stats["deaths"][0]["cause"], "player")
	# A ram kill is flagged.
	var c: SimVehicle = w.vehicles[2]
	c.invuln_ticks = 0
	w._damage_vehicle(c, 1.0e6, a.id, true, SimWorld.SRC_RAM)
	assert_eq(a.match_stats["ram_kills"], 1)
	var last_kill: Dictionary = {}
	for e in w.events:
		if e["type"] == "kill":
			last_kill = e
	assert_eq(last_kill["weapon"], SimWorld.WEAPON_RAM)


func test_alien_kills_and_scrap_in_stats() -> void:
	var w := _world(1, 1)
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(SimWorld.MITE, Vector2(10, 10))
	w.rebuild_derived()
	w._hit_enemy(0, 100.0, v.id)
	assert_eq(v.round_stats["kills"], 1)
	assert_eq(v.match_stats["kills"], 1)
	assert_eq(v.round_stats["scrap_earned"], v.scrap)
	assert_eq(v.match_stats["scrap_earned"], v.scrap)
	assert_gt(float(v.round_stats["dealt"]), 0.0)
	# A new combat starts fresh round stats; match stats persist.
	w._begin_workshop()
	var before: int = int(v.match_stats["kills"])
	w._begin_combat()
	assert_eq(v.round_stats["kills"], 0)
	assert_eq(v.round_stats["round"], w.round)
	assert_eq(v.match_stats["kills"], before)


func test_stats_snapshot_only_outside_combat() -> void:
	var host := _world(2, 5)
	var a: SimVehicle = host.vehicles[0]
	var b: SimVehicle = host.vehicles[1]
	a.invuln_ticks = 0
	b.invuln_ticks = 0
	host._damage_vehicle(b, 1.0e6, a.id)
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	assert_true((client.vehicles[1].round_stats["deaths"] as Array).is_empty(), "combat snapshots carry no stats")
	host._begin_workshop()
	var bytes: PackedByteArray = Snapshot.encode(host)
	assert_true(Snapshot.apply(client, bytes))
	var ca: SimVehicle = client.vehicles[0]
	var cb: SimVehicle = client.vehicles[1]
	assert_eq(ca.match_stats["player_kills"], 1)
	assert_eq(ca.match_stats["top_victim"], b.id)
	assert_eq(cb.match_stats["nemesis"], a.id)
	assert_eq(cb.round_stats["deaths"].size(), 1)
	assert_eq(cb.round_stats["deaths"][0]["cause"], "player")
	assert_eq(cb.round_stats["deaths"][0]["killer"], a.id)
	assert_eq(cb.round_stats["fuel_lost"], b.round_stats["fuel_lost"])
	assert_eq(ca.round_stats["fuel_gained"], a.round_stats["fuel_gained"])
	assert_lt(absf(float(ca.round_stats["dealt_players"]) - float(a.round_stats["dealt_players"])), 1.0)
	# Truncated stats are rejected, the world stays as it was.
	var cut: PackedByteArray = bytes.slice(0, bytes.size() - 1)
	assert_false(Snapshot.apply(client, cut))


func test_kill_and_destroyed_event_extras_over_the_snapshot() -> void:
	var host := _world(2, 5)
	var evs: Array[Dictionary] = [
		{"type": "kill", "pos": Vector2(100, 200), "owner": 1, "kind": -1, "victim": 0, "weapon": 3},
		{"type": "kill", "pos": Vector2(110, 200), "owner": 1, "kind": 2},
		{"type": "vehicle_destroyed", "pos": Vector2(5, 5), "owner": 0, "kind": -1, "cause": 5, "killer": 1},
		{"type": "pvp_on", "pos": Vector2(640, 360), "owner": -1, "kind": -1},
		{"type": "bounty", "pos": Vector2(300, 300), "owner": 1, "kind": -1},
		{"type": "drain", "pos": Vector2(300, 300), "owner": 0, "kind": 5},
	]
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host, evs)))
	assert_eq(client.events.size(), 6)
	assert_eq(client.events[0]["victim"], 0)
	assert_eq(client.events[0]["weapon"], 3)
	assert_false(client.events[1].has("victim"), "alien kills stay 7 bytes")
	assert_eq(client.events[1]["kind"], 2)
	assert_eq(client.events[2]["cause"], 5)
	assert_eq(client.events[2]["killer"], 1)
	assert_eq(client.events[3]["type"], "pvp_on")
	assert_eq(client.events[4]["type"], "bounty")
	assert_eq(client.events[5]["type"], "drain")
	assert_eq(client.events[5]["kind"], 5)


func test_bounty_event_when_the_leader_changes() -> void:
	var w := _world(3, 5)
	w.vehicles[2].kills = 20
	w.step()
	var e: Dictionary = _find_event(w, "bounty")
	assert_false(e.is_empty(), "new leader announced")
	assert_eq(e["owner"], 2, "owner = new leader's vehicle id")
	assert_eq(e["kind"], -1, "kind = previous leader (none)")
	w.step()
	assert_eq(_count_events(w, "bounty"), 0, "only on a change")
	w.vehicles[0].kills = 30
	w.step()
	e = _find_event(w, "bounty")
	assert_eq(e["owner"], 0)
	assert_eq(e["kind"], 2, "previous leader")
	w.vehicles[0].eliminated = true
	w.vehicles[2].eliminated = true
	w.step()
	assert_eq(w.leader_peer, -1)
	assert_eq(_find_event(w, "bounty")["owner"], -1, "no leader any more")


func test_pvp_on_event_and_grace_at_round_four() -> void:
	var w := SimWorld.new(5)
	w.spawning_enabled = false
	for i in 2:
		w.add_vehicle(i + 1, Vector2(300.0 + 500.0 * float(i), 360.0)).weapons.clear()
	w.round = SimWorld.PVP_START_ROUND - 1
	w._begin_workshop()
	w._begin_combat()
	assert_eq(w.round, SimWorld.PVP_START_ROUND)
	assert_eq(w.pvp_grace_ticks, SimWorld.PVP_GRACE_TICKS, "10 s grace")
	assert_eq(SimWorld.PVP_GRACE_TICKS, 300)
	assert_false(w.pvp_enabled())
	var on_tick: int = -1
	var n_on: int = 0
	for i in SimWorld.PVP_GRACE_TICKS + 30:
		w.step()
		if _count_events(w, "pvp_on") > 0:
			n_on += 1
			on_tick = i
		if i < SimWorld.PVP_GRACE_TICKS - 1:
			assert_false(w.pvp_enabled(), "off during the grace")
	assert_eq(n_on, 1, "exactly one pvp_on event")
	assert_eq(on_tick, SimWorld.PVP_GRACE_TICKS - 1, "on the tick the grace ends")
	assert_true(w.pvp_enabled())
	# Round 5 has no grace; fast rounds skip it (and announce pvp_on at once).
	w._begin_workshop()
	w._begin_combat()
	assert_eq(w.pvp_grace_ticks, 0)
	var f := SimWorld.new(5)
	f.fast_rounds = true
	f.add_vehicle(1, Vector2(300, 300))
	f.add_vehicle(2, Vector2(900, 300))
	f.round = 3
	f._begin_workshop()
	f._begin_combat()
	assert_true(f.pvp_enabled())
	assert_eq(_count_events(f, "pvp_on"), 1)


func test_pvp_grace_survives_snapshot() -> void:
	var w := _world(2, 4)
	w.pvp_grace_ticks = 123
	w.fuel_drain = 6
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(w)))
	assert_eq(client.pvp_grace_ticks, 123)
	assert_eq(client.fuel_drain, 6)
	assert_false(client.pvp_enabled())
	assert_ne(w.checksum(), SimWorld.new(0).checksum())


# ---------------------------------------------------------------- 3: anti-passive

func test_kill_steals_fuel() -> void:
	var w := _world(3, 5)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	for v in w.vehicles:
		v.invuln_ticks = 0
	a.fuel = 60
	w._damage_vehicle(b, 1.0e6, a.id)
	assert_eq(b.fuel, 100 - SimWorld.FUEL_LOSS_PVP, "victim loses the usual 30")
	assert_eq(a.fuel, 60 + SimWorld.FUEL_STEAL, "killer takes 10 of it")
	assert_eq(a.round_stats["fuel_gained"], SimWorld.FUEL_STEAL)
	# Capped at 100.
	var c: SimVehicle = w.vehicles[2]
	a.fuel = 95
	w._damage_vehicle(c, 1.0e6, a.id)
	assert_eq(a.fuel, 100)
	# Alien kills never refuel.
	b.alive = true
	b.hp = b.max_hp
	b.fuel = 50
	a.fuel = 50
	w._damage_vehicle(b, 1.0e6, -1)
	assert_eq(a.fuel, 50)


func test_leader_kill_pays_extra_fuel() -> void:
	var w := _world(3, 5)
	for v in w.vehicles:
		v.invuln_ticks = 0
	var a: SimVehicle = w.vehicles[0]
	w.vehicles[2].kills = 40
	w.step()
	assert_eq(w.leader_peer, 3)
	a.fuel = 50
	w._damage_vehicle(w.vehicles[2], 1.0e6, a.id)
	assert_eq(a.fuel, 50 + SimWorld.FUEL_STEAL + SimWorld.LEADER_FUEL_BONUS, "steal plus bounty fuel")


func test_fuel_drain_from_round_eight_multiplayer_only() -> void:
	assert_eq(SimWorld.FUEL_DRAIN_START_ROUND, SimWorld.PVP_START_ROUND + 4)
	assert_eq(SimWorld.fuel_drain_for_round(7), 0)
	assert_eq(SimWorld.fuel_drain_for_round(8), 5)
	assert_eq(SimWorld.fuel_drain_for_round(10), 5)
	assert_eq(SimWorld.fuel_drain_for_round(11), 6)
	assert_eq(SimWorld.fuel_drain_for_round(20), 9)
	var w := _world(2, 7)
	w._begin_workshop()
	assert_eq(w.vehicles[0].fuel, 100, "round 7: no drain yet")
	assert_eq(w.fuel_drain, 0)
	var w2 := _world(2, 8)
	w2.vehicles[1].fuel = 3
	w2._begin_workshop()
	assert_eq(w2.vehicles[0].fuel, 95)
	assert_eq(w2.fuel_drain, 5)
	assert_eq(w2.vehicles[1].fuel, 1, "the drain alone never eliminates")
	assert_false(w2.vehicles[1].eliminated)
	assert_eq(w2.vehicles[0].round_stats["fuel_drained"], 5)
	assert_eq(_count_events(w2, "drain"), 2)
	var solo := _world(1, 12)
	solo._begin_workshop()
	assert_eq(solo.vehicles[0].fuel, 100, "solo has no drain")
	assert_eq(solo.fuel_drain, 0)


# ---------------------------------------------------------------- 4: newbie protection

func test_respawn_and_combat_start_invulnerability() -> void:
	var w := _world(2, 2, false)
	var a: SimVehicle = w.vehicles[0]
	a.invuln_ticks = 0
	w._damage_vehicle(a, 1.0e6, -1)
	assert_false(a.alive)
	for i in SimWorld.RESPAWN_TICKS + 2:
		w.step()
	assert_true(a.alive)
	assert_gt(float(a.invuln_ticks), 0.0, "respawned vehicles are invulnerable")
	var hp: float = a.hp
	w._damage_vehicle(a, 50.0, -1)
	assert_eq(a.hp, hp, "immune")
	w.spawn_enemy(SimWorld.BOULDER, a.pos)
	w.rebuild_derived()
	for i in 20:
		w.step()
	assert_eq(a.hp, hp, "aliens cannot hurt it either")
	for i in SimWorld.INVULN_TICKS:
		w.step()
	assert_eq(a.invuln_ticks, 0)
	w._damage_vehicle(a, 50.0, -1)
	assert_lt(a.hp, hp, "protection wears off after 3 s")
	# Combat start (from round 2).
	var w2 := _world(1, 1)
	w2._begin_workshop()
	w2._begin_combat()
	assert_eq(w2.vehicles[0].invuln_ticks, SimWorld.INVULN_TICKS)
	w2._begin_workshop()
	assert_eq(w2.vehicles[0].invuln_ticks, 0, "none in the workshop")


func test_invulnerable_rigs_cannot_be_targeted_and_shots_pass_through() -> void:
	var w := _world(2, 6)
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.invuln_ticks = 0
	b.pos = a.pos + Vector2(100, 0)
	b.invuln_ticks = 60
	w.apply_command(1, {"type": "set_target", "value": "players_first"})
	a.weapons = [{"kind": "mg", "damage": 4.0, "range": 240.0, "cooldown_ticks": 3, "cooldown": 0, "aim": 0.0}]
	w.step()
	assert_eq(a.target_kind, 0, "a protected rival is not a target")
	w.spawn_projectile(a.pos + Vector2(20, 0), Vector2(400, 0), 1.0, 50.0, a.id)
	for i in 10:
		w.step()
	assert_eq(b.hp, b.max_hp, "shots pass through")
	assert_gt(float(w.proj_count) + 1.0, 0.0)
	b.invuln_ticks = 0
	for i in 3:
		w.step()
	assert_eq(a.target_kind, 2, "targeted once the protection is gone")


func test_players_first_prefers_the_leader_over_the_weakest() -> void:
	var w := _world(3, 6)
	for v in w.vehicles:
		v.invuln_ticks = 0
	var hunter: SimVehicle = w.vehicles[0]
	hunter.weapons = [{"kind": "mg", "damage": 4.0, "range": 600.0, "cooldown_ticks": 3, "cooldown": 0, "aim": 0.0}]
	w.apply_command(1, {"type": "set_target", "value": "players_first"})
	var near: SimVehicle = w.vehicles[1]
	var far: SimVehicle = w.vehicles[2]
	near.pos = hunter.pos + Vector2(80, 0)
	far.pos = hunter.pos + Vector2(400, 0)
	near.hp = 10.0  # the weakest and nearest
	far.kills = 25  # the leader
	w.step()
	assert_eq(w.leader_peer, far.peer_id)
	assert_eq(hunter.target_kind, 2)
	assert_eq(hunter.target_id, far.id, "the bounty target, not the weak neighbour")
	# Without a bounty it prefers the higher score, not the weaker rig.
	far.kills = 0
	near.kills = 3
	w.leader_peer = -1
	hunter.target_kind = 0
	hunter.target_id = -1
	w.vehicles[1].hp = w.vehicles[1].max_hp
	w.step()
	assert_eq(hunter.target_id, near.id, "still prefers the stronger score; nearest on equal score")


func test_underdog_loses_less_fuel() -> void:
	var w := _world(3, 5)
	for v in w.vehicles:
		v.invuln_ticks = 0
	var low: SimVehicle = w.vehicles[0]
	low.fuel = 40
	assert_true(w.is_underdog(low))
	assert_false(w.is_underdog(w.vehicles[1]))
	w._damage_vehicle(low, 1.0e6, -1)
	assert_eq(low.fuel, 40 - roundi(float(SimWorld.FUEL_LOSS) * SimWorld.UNDERDOG_FUEL_FACTOR), "20 -> 14 for the underdog")
	# Not when tied for the lowest, and never in solo.
	w.vehicles[1].fuel = low.fuel
	assert_false(w.is_underdog(low))
	var solo := _world(1, 5)
	assert_false(solo.is_underdog(solo.vehicles[0]))
	# A player kill of the underdog costs it 30 * 0.7 = 21.
	var w2 := _world(2, 5)
	for v2 in w2.vehicles:
		v2.invuln_ticks = 0
	w2.vehicles[1].fuel = 50
	w2._damage_vehicle(w2.vehicles[1], 1.0e6, 0)
	assert_eq(w2.vehicles[1].fuel, 50 - 21)
	assert_eq(w2.vehicles[0].fuel, 100, "killer already at the cap")


func test_repeat_kills_of_the_same_victim_pay_less() -> void:
	var w := _world(3, 5)
	for v in w.vehicles:
		v.invuln_ticks = 0
	var a: SimVehicle = w.vehicles[0]
	var b: SimVehicle = w.vehicles[1]
	a.fuel = 50
	var s0: int = a.scrap
	w._damage_vehicle(b, 1.0e6, a.id)
	assert_eq(a.scrap - s0, SimWorld.PVP_KILL_SCRAP, "1st kill: full")
	assert_eq(a.fuel, 60)
	b.alive = true
	b.hp = b.max_hp
	b.fuel = 100
	s0 = a.scrap
	w._damage_vehicle(b, 1.0e6, a.id)
	assert_eq(a.scrap - s0, roundi(SimWorld.PVP_KILL_SCRAP * 0.5), "2nd kill: half")
	assert_eq(a.fuel, 65)
	b.alive = true
	b.hp = b.max_hp
	b.fuel = 100
	s0 = a.scrap
	w._damage_vehicle(b, 1.0e6, a.id)
	assert_eq(a.scrap - s0, 0, "3rd kill: nothing")
	assert_eq(a.fuel, 65)
	assert_eq(a.kills, 3, "still counts as a kill")
	assert_eq(a.match_stats["top_victim_n"], 3)
	# Another victim pays in full, and a new round resets the count.
	var s1: int = a.scrap
	w._damage_vehicle(w.vehicles[2], 1.0e6, a.id)
	assert_eq(a.scrap - s1, SimWorld.PVP_KILL_SCRAP)
	w._begin_workshop()
	w._begin_combat()
	assert_true(a.kill_counts.is_empty())


# ---------------------------------------------------------------- 7: drafts

func _stock_vehicle(cards: Dictionary) -> SimVehicle:
	var v := SimVehicle.new(0, 1, Vector2.ZERO)
	v.cards = cards
	Cards.recompute(v)
	return v


func test_draft_guarantees_a_weapon_while_a_slot_is_free() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var v := _stock_vehicle({"mg": 1})
	assert_true(Cards.weapon_cards_owned(v) < v.weapon_slots)
	for i in 400:
		var offers: Array[String] = Cards.roll_offers(rng, v, 3, 5)
		var new_weapon: bool = false
		for id in offers:
			if Cards.is_weapon(id) and not v.cards.has(id):
				new_weapon = true
		assert_true(new_weapon, "a new weapon is on offer: %s" % str(offers))
	# With the slots full there is no such guarantee (weapon upgrades still come up).
	var full := _stock_vehicle({"mg": 1, "shotgun": 1})
	var saw_none: bool = false
	for i in 200:
		var offers2: Array[String] = Cards.roll_offers(rng, full, 3, 5)
		var any_weapon: bool = false
		for id2 in offers2:
			any_weapon = any_weapon or Cards.is_weapon(id2)
			assert_false(Cards.is_weapon(id2) and not full.cards.has(id2), "no unowned weapon without a slot")
		saw_none = saw_none or not any_weapon
	assert_true(saw_none, "slots full: weapon cards are not forced")


func test_draft_never_three_of_one_category_and_all_distinct() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for cards in [{"mg": 1}, {"mg": 1, "cannon": 2}, {"mg": 3, "cannon": 3, "steel_plates": 3}]:
		var v := _stock_vehicle(cards)
		for i in 500:
			var offers: Array[String] = Cards.roll_offers(rng, v, 3, 1 + i % 8)
			assert_eq(offers.size(), 3)
			var cats := {}
			var uniq := {}
			for id in offers:
				cats[Cards.def(id)["category"]] = true
				uniq[id] = true
				assert_true(Cards.is_offerable(v, id))
			assert_gt(float(cats.size()), 1.0, "not all of one category: %s" % str(offers))
			assert_eq(uniq.size(), 3)


func test_reroll_never_repeats_a_card_of_the_previous_offer() -> void:
	var w := SimWorld.new(8)
	w.fast_rounds = true
	var v := w.add_vehicle(1, Vector2(300, 300))
	w._begin_workshop()
	v.scrap = 10000
	for i in 40:
		var prev: Array[String] = v.offers.duplicate()
		w.apply_command(1, {"type": "reroll"})
		assert_eq(v.offers.size(), 3)
		for id in v.offers:
			assert_false(prev.has(id), "%s repeated after a reroll of %s" % [id, str(prev)])


func test_early_rounds_favour_weapon_variety() -> void:
	var v := _stock_vehicle({"mg": 3})  # one free slot, mg maxed
	var early: int = 0
	var late: int = 0
	for s in 200:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		for id in Cards.roll_offers(rng, v, 3, 2):
			early += 1 if Cards.is_weapon(id) else 0
		rng.seed = s
		for id2 in Cards.roll_offers(rng, v, 3, 9):
			late += 1 if Cards.is_weapon(id2) else 0
	assert_true(early >= late, "early rounds show at least as many weapons (%d vs %d)" % [early, late])
	# Filler commons weigh less than before.
	assert_true(int(Cards.def("v8_engine")["weight"]) < 10)
	assert_true(int(Cards.def("scrap_magnet")["weight"]) < 8)


# ---------------------------------------------------------------- 8: economy

func test_interest_cap_scales_with_the_round() -> void:
	var w := _world(1, 1)
	var v: SimVehicle = w.vehicles[0]
	assert_eq(w.interest_cap_for(v), 5 + 2 * 1)
	w.round = 10
	assert_eq(w.interest_cap_for(v), 25)
	v.scrap = 300
	assert_eq(w.interest_for(v), 25, "10% of 300 = 30, capped at 25")
	v.scrap = 120
	assert_eq(w.interest_for(v), 12, "10% of held scrap")
	v.tech = ["salvage_hooks", "salvage_haggler", "salvage_black_market"]
	Cards.recompute(v)
	assert_eq(w.interest_cap_for(v), 25 + 4, "salvage tech raises the cap")
	v.scrap = 120
	w._begin_workshop()
	assert_eq(v.scrap, 132)
	assert_eq(v.round_stats["interest"], 12)


# ---------------------------------------------------------------- 9: ramming

func test_spiked_plating_and_berserker_reduce_contact_damage() -> void:
	var w := SimWorld.new(1)
	var base: float = w._contact_hit(SimWorld.BOULDER, 0.0)
	var v := _stock_vehicle({"mg": 1, "spiked_plating": 2})
	assert_gt(v.contact_reduction, 0.15)
	assert_gt(v.thorns, 0.5)
	var spiked: float = w._contact_hit(SimWorld.BOULDER, v.armor, v.contact_reduction)
	var plain: float = w._contact_hit(SimWorld.BOULDER, v.armor)
	assert_lt(spiked, plain * 0.85, "less contact damage taken")
	var b := _stock_vehicle({"mg": 1, "berserker": 1})
	assert_gt(b.contact_reduction, 0.1)
	assert_eq(b.thorns, 0.0, "only spikes reflect")
	assert_lt(w._contact_hit(SimWorld.MITE, 0.0, b.contact_reduction), w._contact_hit(SimWorld.MITE, 0.0))
	assert_gt(base, 0.0)
	var both := _stock_vehicle({"mg": 1, "spiked_plating": 3, "berserker": 3})
	assert_true(both.contact_reduction <= Cards.MAX_CONTACT_REDUCTION + 0.0001, "capped")
	# Snapshot clients recompute the same values.
	var host := _world(1, 1)
	host.vehicles[0].cards["spiked_plating"] = 2
	Cards.recompute(host.vehicles[0])
	var client := SimWorld.new(0)
	assert_true(Snapshot.apply(client, Snapshot.encode(host)))
	assert_lt(absf(client.vehicles[0].contact_reduction - host.vehicles[0].contact_reduction), 0.0001)
	assert_lt(absf(client.vehicles[0].thorns - host.vehicles[0].thorns), 0.0001)


func test_thorns_reflect_damage_and_reduction_lowers_the_hit() -> void:
	var damage_taken: Array[float] = []
	var boulder_hp: Array[float] = []
	for cards in [{"mg": 1}, {"mg": 1, "spiked_plating": 3}]:
		var w := _world(1, 1)
		var v: SimVehicle = w.vehicles[0]
		v.invuln_ticks = 0
		v.cards = cards
		Cards.recompute(v)
		v.contact_damage = 0.0  # isolate the reflection from the spikes' own ram damage
		w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(20, 0))
		w.rebuild_derived()
		for i in 15:
			w.step()
		damage_taken.append(v.max_hp - v.hp)
		boulder_hp.append(w.enemy_hp[0])
	assert_lt(damage_taken[1], damage_taken[0], "spiked plating takes less contact damage")
	assert_lt(boulder_hp[1], boulder_hp[0], "and reflects some of it")


func _charger(cards: Dictionary) -> SimWorld:
	var w := _world(1, 1)
	var v: SimVehicle = w.vehicles[0]
	v.invuln_ticks = 0
	v.cards = cards
	Cards.recompute(v)
	v.weapons.clear()
	w.apply_command(1, {"type": "set_drive", "value": "charge"})
	w.spawn_enemy(SimWorld.BOULDER, v.pos + Vector2(60, 0))
	w.spawn_enemy(SimWorld.MITE, v.pos + Vector2(200, 0))
	w.rebuild_derived()
	return w


func test_charge_avoids_boulders_unless_berserk() -> void:
	var w := _charger({"mg": 1})
	w.step()
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.target_kind, 1)
	assert_eq(w.enemy_kind[v.target_index], SimWorld.MITE, "the farther mite, not the boulder next to it")
	var w2 := _charger({"mg": 1, "berserker": 1})
	w2.step()
	var v2: SimVehicle = w2.vehicles[0]
	assert_eq(w2.enemy_kind[v2.target_index], SimWorld.BOULDER, "berserkers ram the boulder")
	# Only boulders left: still engages them, but without ramming.
	var w3 := _charger({"mg": 1})
	w3.enemy_hp[1] = 0.0
	w3._compact_enemies()
	w3.rebuild_derived()
	w3.step()
	var v3: SimVehicle = w3.vehicles[0]
	assert_eq(v3.target_kind, 1)
	assert_eq(v3.ram_damage, 0.0, "no ramming of boulders without berserker")


# ---------------------------------------------------------------- determinism

func test_iteration3_determinism() -> void:
	var sums: Array[int] = []
	for run in 2:
		var w := SimWorld.new(2468)
		w.fast_rounds = true
		for i in 3:
			w.add_vehicle(i + 1, Vector2(300.0 + 300.0 * float(i), 360.0))
		w.round = 3
		for i in 900:
			if w.phase == SimWorld.PHASE_WORKSHOP and w.phase_ticks_left == w.workshop_duration() - 1:
				for v in w.vehicles:
					w.apply_command(v.peer_id, {"type": "reroll"})
					w.apply_command(v.peer_id, {"type": "pick_card", "value": 0})
			w.step()
		sums.append(w.checksum())
	assert_eq(sums[0], sums[1])
