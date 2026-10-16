extends TestCase
## Tech tree v2.3 stage 2a: Ballistics ammo and weapon effects (burn, shrapnel, armour piercing, napalm,
## burn bonus, scatter, ember trail, jam / overheat, execute, mixed belts), the fractional fire rate,
## set_ammo, the `ammo:<id>` rule action, snapshot and determinism.

const BENCH: Array = ["ballistics_ammo_bench"]
const BELT: Array = ["ballistics_ammo_bench", "ballistics_belt_feed"]
const HEAVY: Array = ["ballistics_ammo_bench", "ballistics_heavy_shells"]
const TABLES: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables"]
const HOT: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_hot_loads"]
const SCATTER: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_scatter"]
const NAPALM: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm"]
const HE: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_he"]
const TUNGSTEN: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm", "ballistics_tungsten"]
const MIXED: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm", "ballistics_mixed_belts"]
const GLOWING: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm", "ballistics_tungsten", "ballistics_glowing"]
const ONE_SHOT: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm", "ballistics_tungsten", "ballistics_one_shot"]


## A one-rig world (round 1, no spawner) with the tech `ids` bought and `cards` as the weapon cards.
## The rig is tough and holds position.
func _world(ids: Array, cards: Dictionary = {"mg": 1}, p_seed: int = 7) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	var v: SimVehicle = w.add_vehicle(1, Vector2(1000.0, 700.0))
	v.scrap = 99999
	v.cards = cards.duplicate()
	Cards.recompute(v)
	for id: String in ids:
		assert_true(Tech.buy(v, id, 1), "buy " + id)
	v.max_hp = 1.0e6
	v.hp = 1.0e6
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "hp>0|drive:hold"})
	return w


## Spawns an enemy `dist` px in front of the rig with `hp` and returns its index.
func _enemy(w: SimWorld, kind: int, dist: float, hp: float, dy: float = 0.0) -> int:
	var v: SimVehicle = w.vehicles[0]
	w.spawn_enemy(kind, v.pos + Vector2(dist, dy))
	var i: int = w.enemy_count - 1
	w.enemy_hp[i] = hp
	w.rebuild_derived()
	return i


## Steps `n` ticks and counts the events of `type` (and, for `owner >= 0`, of that owner).
func _count(w: SimWorld, n: int, type: String, kind: int = -999) -> int:
	var c: int = 0
	for t in n:
		w.step()
		for e in w.events:
			if e["type"] == type and (kind == -999 or int(e["kind"]) == kind):
				c += 1
	return c


func _find(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1


# ---------------------------------------------------------------- fire rate

func test_fractional_fire_rate() -> void:
	# Flamer: 2 ticks per shot. Belt feed gives it +30%: 2 / 1.3 = 1.54 ticks. The old rounding made that 2 again.
	var base: SimWorld = _world([], {"flamer": 1})
	_enemy(base, SimWorld.BOULDER, 60.0, 1.0e7)
	var fast: SimWorld = _world(BELT, {"flamer": 1})
	_enemy(fast, SimWorld.BOULDER, 60.0, 1.0e7)
	var wf: Dictionary = fast.vehicles[0].weapons[0]
	assert_gt(float(wf["cooldown_ticks"]), 1.5)
	assert_lt(float(wf["cooldown_ticks"]), 1.6)
	var n_base: int = _count(base, 300, "fire")
	var n_fast: int = _count(fast, 300, "fire")
	assert_true(n_base >= 140 and n_base <= 151, "base flamer: ~150 shots in 10 s, got %d" % n_base)
	assert_true(n_fast >= 190 and n_fast <= 196, "belt-fed flamer fires ~30%% faster, got %d" % n_fast)


# ---------------------------------------------------------------- burn

func test_burn_ticks_and_kill_credit() -> void:
	var w: SimWorld = _world(BENCH)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	var i: int = _enemy(w, SimWorld.BOULDER, 400.0, 80.0)
	var eid: int = w.enemy_id[i]
	var ex: Vector2 = w.enemy_pos[i]
	w.spawn_projectile(ex - Vector2(22, 0), Vector2(400, 0), 1.0, 8.0, 0, 0, 0.0, 0, Ammo.FIRE_BIT)
	w.step()
	var j: int = _find(w, eid)
	assert_true(w.enemy_burn_ticks[j] > 50, "ignited by the hit")
	assert_eq(w.enemy_burn_owner[j], 0)
	assert_true(absf(w.enemy_burn_dps[j] - 1.0) < 0.001, "25% of 8 over 2 s = 1 dps")
	var hp_after_hit: float = w.enemy_hp[j]
	for t in 70:
		w.step()
	j = _find(w, eid)
	assert_eq(w.enemy_burn_ticks[j], 0, "burn ran out after 2 s")
	var lost: float = hp_after_hit - w.enemy_hp[j]
	assert_true(lost > 1.7 and lost < 2.2, "about 2 damage over time, got %f" % lost)
	# Kill credit: the burn finishes the enemy and the scrap goes to the igniting rig.
	var k: int = _enemy(w, SimWorld.MITE, 500.0, 0.5, 40.0)
	var scrap0: int = v.scrap
	var kills0: int = v.kills
	var dealt0: float = float(v.round_stats["dealt"])
	w._ignite(k, 30.0, 0)
	var kill_events: int = _count(w, 5, "kill")
	assert_eq(kill_events, 1, "the burn killed it")
	assert_eq(v.kills, kills0 + 1, "kill credited to the owner")
	assert_true(v.scrap > scrap0, "scrap credited")
	assert_true(float(v.round_stats["dealt"]) > dealt0, "burn damage counts as dealt")


func test_napalm_spreads() -> void:
	var w: SimWorld = _world(NAPALM)
	w.vehicles[0].weapons.clear()
	var first: int = -1
	for k in 6:
		var i: int = _enemy(w, SimWorld.BOULDER, 400.0, 1.0e6, float(k) * 22.0)
		if k == 0:
			first = w.enemy_id[i]
	w._ignite(_find(w, first), 4.0, 0)
	for t in 90:
		w.step()
	var burning: int = 0
	for i in w.enemy_count:
		if w.enemy_burn_ticks[i] > 0:
			burning += 1
	assert_true(burning >= 4, "fire jumps along the line, burning: %d" % burning)
	# Without napalm it stays put.
	var w2: SimWorld = _world(BENCH)
	w2.vehicles[0].weapons.clear()
	for k in 6:
		_enemy(w2, SimWorld.BOULDER, 400.0, 1.0e6, float(k) * 22.0)
	w2._ignite(0, 4.0, 0)
	for t in 30:
		w2.step()
	var b2: int = 0
	for i in w2.enemy_count:
		if w2.enemy_burn_ticks[i] > 0:
			b2 += 1
	assert_eq(b2, 1, "no napalm, no spreading")


func test_burn_bonus_he() -> void:
	var dmg: Array[float] = []
	for burning in [false, true]:
		var w: SimWorld = _world(HE)
		w.vehicles[0].weapons.clear()
		var i: int = _enemy(w, SimWorld.BOULDER, 400.0, 80.0)
		var eid: int = w.enemy_id[i]
		if burning:
			w._ignite(i, 0.001, 0)
		w.spawn_projectile(w.enemy_pos[i] - Vector2(22, 0), Vector2(400, 0), 1.0, 10.0, 0, 0, 0.0, 0)  # mg
		w.step()
		dmg.append(80.0 - w.enemy_hp[_find(w, eid)])
	assert_true(absf(dmg[0] - 10.0) < 0.1, "plain hit")
	assert_true(absf(dmg[1] - 11.5) < 0.1, "+15%% vs a burning target, got %f" % dmg[1])
	# The cannon (weapon index 2) gets no bonus.
	var w3: SimWorld = _world(HE)
	w3.vehicles[0].weapons.clear()
	var c: int = _enemy(w3, SimWorld.BOULDER, 400.0, 80.0)
	w3._ignite(c, 0.001, 0)
	w3.spawn_projectile(w3.enemy_pos[c] - Vector2(22, 0), Vector2(400, 0), 1.0, 10.0, 0, 0, 0.0, 2)
	w3.step()
	assert_true(absf((80.0 - w3.enemy_hp[0]) - 10.0) < 0.1, "no bonus for the cannon")


# ---------------------------------------------------------------- shrapnel and armour piercing

func test_shrapnel_on_kill_does_not_chain() -> void:
	var w: SimWorld = _world(BELT)
	w.vehicles[0].weapons.clear()
	var a: int = _enemy(w, SimWorld.MITE, 400.0, 6.0)
	var centre: Vector2 = w.enemy_pos[a]
	for ring in [26.0, 36.0]:
		for k in 14:
			w.spawn_enemy(SimWorld.MITE, centre + Vector2.from_angle(TAU * float(k) / 14.0) * ring)
			w.enemy_hp[w.enemy_count - 1] = 1.0
	w.rebuild_derived()
	w.spawn_projectile(centre - Vector2(14, 0), Vector2(400, 0), 1.0, 20.0, 0, 0, 0.0, 0, Ammo.SHRAPNEL_BIT)
	var shrapnel: int = 0
	var kills: int = 0
	for t in 12:
		w.step()
		for e in w.events:
			if e["type"] == "shrapnel":
				shrapnel += 1
			elif e["type"] == "kill":
				kills += 1
	assert_eq(shrapnel, 1, "only the bullet's kill shatters, not the shards' kills")
	assert_true(kills >= 3, "the shards killed neighbours, kills: %d" % kills)
	# Shards carry the shard bit, so they never shatter and never execute.
	assert_eq(Ammo.bit("shrapnel"), Ammo.SHRAPNEL_BIT)


func test_ap_vs_boulder_and_extra_pierce() -> void:
	var dmg: Array[float] = []
	for mask in [0, Ammo.AP_BIT]:
		var w: SimWorld = _world(HEAVY)
		w.vehicles[0].weapons.clear()
		var i: int = _enemy(w, SimWorld.BOULDER, 400.0, 80.0)
		var eid: int = w.enemy_id[i]
		w.spawn_projectile(w.enemy_pos[i] - Vector2(22, 0), Vector2(400, 0), 1.0, 10.0, 0, 0, 0.0, 0, mask)
		w.step()
		dmg.append(80.0 - w.enemy_hp[_find(w, eid)])
	assert_true(absf(dmg[0] - 10.0) < 0.1)
	assert_true(absf(dmg[1] - 15.0) < 0.1, "AP does +50%% to boulders, got %f" % dmg[1])
	# Tables scale the effect by +25%.
	var wt: SimWorld = _world(["ballistics_ammo_bench", "ballistics_heavy_shells", "ballistics_tables"])
	wt.vehicles[0].weapons.clear()
	var t: int = _enemy(wt, SimWorld.BOULDER, 400.0, 80.0)
	wt.spawn_projectile(wt.enemy_pos[t] - Vector2(22, 0), Vector2(400, 0), 1.0, 10.0, 0, 0, 0.0, 0, Ammo.AP_BIT)
	wt.step()
	assert_true(absf((80.0 - wt.enemy_hp[0]) - 10.0 * (1.0 + 0.5 * 1.25)) < 0.1, "ammo_fx scales the AP bonus")
	# Plain mites get no bonus; a loaded gun fires with +1 pierce.
	var wm: SimWorld = _world(HEAVY)
	var m: int = _enemy(wm, SimWorld.BOULDER, 150.0, 1.0e7)
	assert_eq(m, 0)
	var plain_pierce: int = int(wm.vehicles[0].weapons[0]["pierce"])
	var guard: int = 0
	while wm.proj_count == 0 and guard < 30:
		wm.step()
		guard += 1
	assert_true(wm.proj_count > 0 and (wm.proj_ammo[0] & Ammo.AP_BIT) != 0, "AP loaded in the mg (last weapon gets the later ammo)")
	assert_eq(int(wm.proj_pierce[0]), plain_pierce + 1, "AP: +1 pierce")


# ---------------------------------------------------------------- loading and switching

func test_autoload_and_mixed_belts() -> void:
	var v: SimVehicle = SimVehicle.new(0, 1, Vector2.ZERO)
	v.scrap = 99999
	v.cards = {"mg": 1, "shotgun": 1}
	Cards.recompute(v)
	assert_true(v.ammo.get("mg", []).is_empty(), "no ammo before the bench")
	Tech.buy(v, "ballistics_ammo_bench", 1)
	assert_eq(v.ammo["mg"], ["fire"] as Array[String], "the bench loads fire everywhere")
	assert_eq(v.ammo["shotgun"], ["fire"] as Array[String])
	Tech.buy(v, "ballistics_belt_feed", 1)
	assert_eq(v.ammo["mg"], ["fire"] as Array[String], "a later type goes into the last ceil(n/2) weapons")
	assert_eq(v.ammo["shotgun"], ["shrapnel"] as Array[String])
	# Mixed belts: two types per weapon, every effect at 70%.
	for id in ["ballistics_tables", "ballistics_napalm", "ballistics_mixed_belts"]:
		assert_true(Tech.buy(v, id, 1), id)
	assert_eq(v.ammo["mg"].size(), 2)
	assert_eq(v.ammo["shotgun"].size(), 2)
	assert_eq(Ammo.mask(v, "mg"), Ammo.FIRE_BIT | Ammo.SHRAPNEL_BIT)
	assert_true(absf(Ammo.effect_scale(v, Ammo.FIRE_BIT | Ammo.SHRAPNEL_BIT) - 1.25 * 0.7) < 0.0001)
	assert_true(absf(Ammo.effect_scale(v, Ammo.FIRE_BIT) - 1.25) < 0.0001)
	# Swapping the tier-2 choice away drops what is no longer unlocked.
	var w := SimWorld.new(3)
	var rv: SimVehicle = w.add_vehicle(1, Vector2(100, 100))
	rv.scrap = 99999
	rv.cards = {"mg": 1, "shotgun": 1}
	Cards.recompute(rv)
	Tech.buy(rv, "ballistics_ammo_bench", 1)
	Tech.buy(rv, "ballistics_belt_feed", 1)
	assert_true(Tech.respec(rv, "ballistics_belt_feed", "ballistics_heavy_shells", 1))
	assert_eq(rv.ammo["shotgun"], ["ap"] as Array[String], "AP replaced shrapnel")
	assert_false(Ammo.is_unlocked(rv, "shrapnel"))


func test_set_ammo_validation_and_delay() -> void:
	var w: SimWorld = _world(BELT, {"mg": 1, "shotgun": 1})
	var v: SimVehicle = w.vehicles[0]
	assert_eq(v.ammo["mg"], ["fire"] as Array[String])
	w.apply_command(1, {"type": "set_ammo", "scope": "mg", "value": "ap"})
	assert_eq(v.ammo["mg"], ["fire"] as Array[String], "ap is not unlocked")
	w.apply_command(1, {"type": "set_ammo", "scope": "cannon", "value": "shrapnel"})
	assert_eq(v.ammo["shotgun"], ["shrapnel"] as Array[String], "the later type went into the last weapon")
	assert_false(v.ammo.has("cannon"), "no such weapon")
	w.apply_command(1, {"type": "set_ammo", "scope": "mg", "value": "fire"})
	assert_eq(int(v.weapons[0]["sw"]), 0, "already loaded: no switch")
	w.apply_command(1, {"type": "set_ammo", "scope": "mg", "value": "shrapnel"})
	assert_eq(v.ammo["mg"], ["shrapnel"] as Array[String])
	assert_eq(int(v.weapons[0]["sw"]), Ammo.SWITCH_TICKS, "30 ticks of silence")
	_enemy(w, SimWorld.BOULDER, 150.0, 1.0e7)
	var shots_early: int = _count(w, Ammo.SWITCH_TICKS - 1, "fire", 0)
	assert_eq(shots_early, 0, "the weapon is silent while it switches")
	var shots_late: int = _count(w, 10, "fire", 0)
	assert_true(shots_late > 0, "then it shoots again")
	# Ballistic tables: instant.
	var w2: SimWorld = _world(TABLES, {"mg": 1, "shotgun": 1})
	w2.apply_command(1, {"type": "set_ammo", "scope": "mg", "value": "shrapnel"})
	assert_eq(w2.vehicles[0].ammo["mg"], ["shrapnel"] as Array[String])
	assert_eq(int(w2.vehicles[0].weapons[0]["sw"]), 0, "no delay with ballistic tables")
	# Works in the workshop too.
	var w3: SimWorld = _world(BELT, {"mg": 1, "shotgun": 1})
	w3.fast_rounds = true
	var guard: int = 0
	while w3.phase == SimWorld.PHASE_COMBAT and guard < 5000:
		w3.step()
		guard += 1
	w3.apply_command(1, {"type": "set_ammo", "scope": "mg", "value": "shrapnel"})
	assert_eq(w3.vehicles[0].ammo["mg"], ["shrapnel"] as Array[String], "workshop")
	# Net validation.
	var ok: Dictionary = NetSession.validate_command({"type": "set_ammo", "scope": "mg", "value": "fire"})
	assert_eq(ok, {"type": "set_ammo", "scope": "mg", "value": "fire"})
	assert_true(NetSession.validate_command({"type": "set_ammo", "scope": "rig", "value": "fire"}).is_empty())
	assert_true(NetSession.validate_command({"type": "set_ammo", "scope": "mg", "value": "plasma"}).is_empty())
	assert_true(NetSession.validate_command({"type": "set_ammo", "scope": "mg"}).is_empty())
	assert_true(NetSession.validate_command({"type": "set_ammo", "scope": 3, "value": "fire"}).is_empty())


func test_ammo_rule_action() -> void:
	var w: SimWorld = _world(BELT, {"mg": 1, "shotgun": 1})
	var v: SimVehicle = w.vehicles[0]
	w.apply_command(1, {"type": "set_rules", "scope": "mg", "value": "|ammo:ap"})
	assert_true(Doctrine.weapon_doc(v, "mg")["rules"].is_empty(), "ap is locked: rule refused")
	w.apply_command(1, {"type": "set_rules", "scope": "mg", "value": "t_dist>100|ammo:shrapnel"})
	assert_eq(Doctrine.weapon_doc(v, "mg")["rules"].size(), 1)
	assert_true(Doctrine.parse("|ammo:fire", "rig") == null, "rig rules cannot load ammo")
	assert_true(Doctrine.actions_for("mg", v).has("ammo:shrapnel"))
	assert_false(Doctrine.actions_for("mg", v).has("ammo:ap"), "editor lists unlocked ammo only")
	_enemy(w, SimWorld.BOULDER, 150.0, 1.0e7)
	w.step()
	w.step()
	assert_eq(v.ammo["mg"], ["shrapnel"] as Array[String], "the rule loaded shrapnel")
	# Index tables only grew: the old action ids keep their position.
	assert_eq(Doctrine.ACTIONS.find("fire:free"), 13)
	assert_eq(Doctrine.ACTIONS.find("ammo:fire"), 14)


# ---------------------------------------------------------------- scatter, embers

func test_scatter_every_fourth_shot() -> void:
	var w: SimWorld = _world(SCATTER)
	var v: SimVehicle = w.vehicles[0]
	var base: float = float(v.weapons[0]["damage"])
	_enemy(w, SimWorld.BOULDER, 200.0, 1.0e7)
	var fires: int = 0
	var seen: Array[int] = []
	for t in 60:
		w.step()
		for e in w.events:
			if e["type"] == "fire":
				fires += 1
				var extra: int = 0
				for p in w.proj_count:
					if absf(w.proj_damage[p] - base * 0.4) < 0.001:
						extra += 1
				seen.append(extra)
	assert_true(fires >= 8, "fired enough: %d" % fires)
	var rounds_with_pellets: int = 0
	for e in seen:
		if e >= 3:
			rounds_with_pellets += 1
	assert_true(rounds_with_pellets >= 2, "every 4th shot throws 3 extra pellets")
	# A shotgun does not get the mini volley (it already gets +2 pellets).
	var ws: SimWorld = _world(SCATTER, {"shotgun": 1})
	_enemy(ws, SimWorld.BOULDER, 120.0, 1.0e7)
	assert_eq(int(ws.vehicles[0].weapons[0]["pellets"]), 7, "shotgun +2 pellets")
	for t in 40:
		ws.step()
		for p in ws.proj_count:
			assert_true(absf(ws.proj_damage[p] - float(ws.vehicles[0].weapons[0]["damage"]) * 0.4) > 0.001, "no mini volley for shotguns")


func test_ember_trail_from_pierced_hits() -> void:
	var w: SimWorld = _world(TUNGSTEN)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	var a: int = _enemy(w, SimWorld.BOULDER, 400.0, 1.0e6)
	var b: int = _enemy(w, SimWorld.BOULDER, 430.0, 1.0e6)
	var bid: int = w.enemy_id[b]
	var pos: Vector2 = w.enemy_pos[a]
	w.spawn_projectile(pos - Vector2(22, 0), Vector2(400, 0), 1.0, 5.0, 0, 1, 0.0, 0)
	w.step()
	assert_eq(w.zone_count, 1, "the pierced hit left an ember zone")
	assert_eq(w.zone_kind[0], SimWorld.ZONE_EMBER)
	assert_eq(w.zone_owner[0], 0)
	# A second pierce at the same spot refreshes instead of stacking.
	w._add_zone(w.zone_pos[0] + Vector2(2, 0), SimWorld.EMBER_RADIUS, SimWorld.ZONE_EMBER, SimWorld.EMBER_TICKS, 0)
	assert_eq(w.zone_count, 1)
	# Standing in it burns (20 dps) and ignites; the zone expires after ~2 s.
	var ei: int = _find(w, bid)
	var hp0: float = w.enemy_hp[_find(w, w.enemy_id[0])]
	for t in 12:
		w.step()
	assert_true(w.enemy_hp[_find(w, w.enemy_id[0])] < hp0 - 4.0, "the zone damages")
	var burning: bool = false
	for i in w.enemy_count:
		burning = burning or w.enemy_burn_ticks[i] > 0
	assert_true(burning, "the zone ignites")
	assert_true(ei >= 0)
	for t in 80:
		w.step()
	assert_eq(w.zone_count, 0, "embers die out")
	assert_eq(w.zone_pos.size(), 0)
	# The zone array is capped.
	for k in SimWorld.MAX_ZONES + 10:
		w._add_zone(Vector2(100.0 + 50.0 * float(k), 100.0), 10.0, SimWorld.ZONE_OIL, 30, 0)
	assert_eq(w.zone_count, SimWorld.MAX_ZONES)
	# No tungsten, no embers.
	var w2: SimWorld = _world(BENCH)
	w2.vehicles[0].weapons.clear()
	var c: int = _enemy(w2, SimWorld.BOULDER, 400.0, 1.0e6)
	w2.spawn_projectile(w2.enemy_pos[c] - Vector2(22, 0), Vector2(400, 0), 1.0, 5.0, 0, 1, 0.0, 0)
	w2.step()
	assert_eq(w2.zone_count, 0)


# ---------------------------------------------------------------- jam, overheat, execute

func _shots_in(ids: Array, erase_fx: Array, ticks: int) -> Array[int]:
	var w: SimWorld = _world(ids)
	for k: String in erase_fx:
		w.vehicles[0].tech_fx.erase(k)
	_enemy(w, SimWorld.BOULDER, 100.0, 1.0e9)
	var fires: int = 0
	var pauses: int = 0
	for t in ticks:
		w.step()
		for e in w.events:
			if e["type"] == "fire":
				fires += 1
			elif e["type"] == "jam" or e["type"] == "overheat":
				pauses += 1
	return [fires, pauses]


func test_jam_duty_cycle() -> void:
	var jam: Array[int] = _shots_in(HOT, [], 720)
	var free: Array[int] = _shots_in(HOT, ["jam"], 720)
	assert_eq(free[1], 0, "no jam without the flag")
	assert_true(jam[1] >= 4 and jam[1] <= 6, "about one jam per 4.8 s, got %d" % jam[1])
	var ratio: float = float(jam[0]) / float(free[0])
	assert_true(ratio > 0.78 and ratio < 0.88, "4 s on, 0.8 s off: ~83%% duty, got %f" % ratio)


func test_overheat_duty_cycle_replaces_jam() -> void:
	var hot: Array[int] = _shots_in(GLOWING, [], 840)
	var free: Array[int] = _shots_in(GLOWING, ["overheat"], 840)
	assert_eq(free[1], 0, "overheat replaces the jam: without it nothing stutters")
	assert_true(hot[1] >= 3 and hot[1] <= 5, "one pause per 7 s, got %d" % hot[1])
	var ratio: float = float(hot[0]) / float(free[0])
	assert_true(ratio > 0.82 and ratio < 0.9, "6 s on, 1 s off: ~86%% duty, got %f" % ratio)
	# Overheat wins over hot loads when both are active.
	var w: SimWorld = _world(GLOWING)
	assert_true(float(w.vehicles[0].tech_fx.get("overheat", 0.0)) > 0.0)
	var kinds: Dictionary = {}
	_enemy(w, SimWorld.BOULDER, 100.0, 1.0e9)
	for t in 400:
		w.step()
		for e in w.events:
			if e["type"] == "jam" or e["type"] == "overheat":
				kinds[e["type"]] = true
	assert_true(kinds.has("overheat") and not kinds.has("jam"))


func test_heat_cools_down_without_target() -> void:
	var w: SimWorld = _world(HOT)
	var e: int = _enemy(w, SimWorld.BOULDER, 100.0, 1.0e9)
	for t in 60:
		w.step()
	assert_true(int(w.vehicles[0].weapons[0]["heat"]) > 50)
	w.enemy_hp[e] = 0.0  # gone
	for t in 40:
		w.step()
	assert_true(int(w.vehicles[0].weapons[0]["heat"]) < 10, "the barrel cools down")


func test_execute_kills_weak_aliens_never_rivals() -> void:
	var w: SimWorld = _world(ONE_SHOT)
	var v: SimVehicle = w.vehicles[0]
	v.weapons.clear()
	assert_true(float(v.tech_fx.get("execute", 0.0)) > 0.0)
	var max_hp: float = SimWorld.enemy_max_hp(SimWorld.BOULDER, w.round)
	var weak: int = _enemy(w, SimWorld.BOULDER, 400.0, max_hp * 0.25)
	var strong: int = _enemy(w, SimWorld.BOULDER, 400.0, max_hp * 0.6, 60.0)
	var weak_id: int = w.enemy_id[weak]
	var strong_id: int = w.enemy_id[strong]
	w.spawn_projectile(w.enemy_pos[weak] - Vector2(22, 0), Vector2(400, 0), 1.0, 0.5, 0, 0, 0.0, 0)
	w.spawn_projectile(w.enemy_pos[strong] - Vector2(22, 0), Vector2(400, 0), 1.0, 0.5, 0, 0, 0.0, 0)
	var executes: int = 0
	for t in 2:
		w.step()
		for e in w.events:
			if e["type"] == "execute":
				executes += 1
	assert_eq(executes, 1)
	assert_eq(_find(w, weak_id), -1, "a hit on an alien under 30% hp kills it")
	assert_true(_find(w, strong_id) >= 0, "a healthier alien survives a weak hit")
	# Rival rigs: no execution.
	var w2 := SimWorld.new(9)
	w2.spawning_enabled = false
	var a: SimVehicle = w2.add_vehicle(1, Vector2(500, 500))
	var r: SimVehicle = w2.add_vehicle(2, Vector2(900, 500))
	a.scrap = 99999
	for id: String in ONE_SHOT:
		Tech.buy(a, id, 1)
	a.weapons.clear()
	w2.round = 4
	w2.pvp_grace_ticks = 0
	r.invuln_ticks = 0
	r.hp = r.max_hp * 0.2
	var hp0: float = r.hp
	w2.spawn_projectile(r.pos - Vector2(22, 0), Vector2(400, 0), 1.0, 1.0, 0, 0, 0.0, 0)
	w2.step()
	assert_true(r.alive and r.hp > hp0 - 3.0 and r.hp < hp0, "a rig under 30%% takes normal damage, hp %f of %f" % [r.hp, hp0])


# ---------------------------------------------------------------- snapshot, determinism

func test_snapshot_round_trip() -> void:
	var w: SimWorld = _world(MIXED, {"mg": 1, "shotgun": 1})
	var v: SimVehicle = w.vehicles[0]
	for k in 8:
		_enemy(w, SimWorld.BOULDER, 150.0 + 25.0 * float(k), 1.0e6, float(k) * 9.0)
	w._ignite(1, 3.0, 0)
	w._ignite(4, 3.0, 0)
	w._add_zone(Vector2(1200, 700), 14.0, SimWorld.ZONE_EMBER, 50, 0)
	for t in 20:
		w.step()
	w.apply_command(1, {"type": "set_ammo", "scope": "mg", "value": "shrapnel"})
	v.weapons[0]["heat"] = 42
	v.weapons[0]["jam"] = 7
	var bytes: PackedByteArray = Snapshot.encode(w)
	var c := SimWorld.new(1)
	c.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c, bytes), "applies")
	var cv: SimVehicle = c.vehicles[0]
	assert_eq(cv.ammo["mg"], v.ammo["mg"], "loaded ammo (order = primary first)")
	assert_eq(cv.ammo["shotgun"], v.ammo["shotgun"])
	assert_eq(int(cv.weapons[0]["heat"]), 42)
	assert_eq(int(cv.weapons[0]["jam"]), 7)
	assert_eq(int(cv.weapons[0]["sw"]), int(v.weapons[0]["sw"]))
	assert_true(absf(float(cv.weapons[0]["cooldown_ticks"]) - float(v.weapons[0]["cooldown_ticks"])) < 0.07)
	assert_eq(c.zone_count, 1)
	assert_eq(c.zone_kind[0], SimWorld.ZONE_EMBER)
	assert_eq(c.zone_ttl[0], w.zone_ttl[0])
	assert_eq(c.enemy_count, w.enemy_count)
	assert_eq(c.enemy_burn_ticks.size(), c.enemy_count)
	for i in w.enemy_count:
		assert_eq(c.enemy_burn_ticks[i] > 0, w.enemy_burn_ticks[i] > 0, "burning flag of enemy %d" % i)
	assert_true(Ammo.is_unlocked(cv, "shrapnel"), "unlock flags follow from the tech")
	# Without any fire there is no bitset (flag cleared) and the client still sees nobody burning.
	var w2: SimWorld = _world(BENCH)
	_enemy(w2, SimWorld.BOULDER, 150.0, 80.0)
	var c2 := SimWorld.new(1)
	c2.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c2, Snapshot.encode(w2)))
	assert_eq(c2.enemy_burn_ticks[0], 0)
	# New event types travel.
	var evs: Array[Dictionary] = [{"type": "shrapnel", "pos": Vector2(10, 10), "owner": 0, "kind": 0},
		{"type": "jam", "pos": Vector2(10, 10), "owner": 0, "kind": 0},
		{"type": "overheat", "pos": Vector2(10, 10), "owner": 0, "kind": 0},
		{"type": "execute", "pos": Vector2(10, 10), "owner": 0, "kind": 1}]
	var c3 := SimWorld.new(1)
	c3.add_vehicle(1, Vector2(1, 1))
	assert_true(Snapshot.apply(c3, Snapshot.encode(w2, evs)))
	assert_eq(c3.events.size(), 4)
	assert_eq(str(c3.events[3]["type"]), "execute")


func _run(p_seed: int) -> SimWorld:
	var w: SimWorld = _world(MIXED, {"mg": 1, "shotgun": 1}, p_seed)
	w.spawning_enabled = true
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": ""})
	w.vehicles[0].max_hp = 300.0
	w.vehicles[0].hp = 300.0
	for t in 400:
		w.step()
		if t == 100:
			w.apply_command(1, {"type": "set_ammo", "scope": "shotgun", "value": "fire"})
	return w


func test_determinism() -> void:
	var a: SimWorld = _run(11)
	var b: SimWorld = _run(11)
	var c: SimWorld = _run(12)
	assert_eq(a.checksum(), b.checksum(), "same seed, same world")
	assert_ne(a.checksum(), c.checksum(), "different seed, different world")
	var burned: bool = false
	for i in a.enemy_count:
		burned = burned or a.enemy_burn_ticks[i] > 0
	assert_true(a.vehicles[0].kills > 0, "the run actually fought")
	assert_true(burned or a.vehicles[0].kills > 5, "fire ammo was in play")
	for i in a.enemy_burn_ticks.size():
		assert_eq(a.enemy_burn_ticks.size(), a.enemy_count)
		break
