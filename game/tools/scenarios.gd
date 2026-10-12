class_name Scenarios
extends RefCounted
## Named, deterministic SimWorld setups for screenshots (main.gd --shot=...) and manual checks.
## build(name, seed) + step(name, world) N times always gives the same state.
##
## Round-loop scenarios use fast_rounds (4 s combat) and auto-ready through early workshops:
## - "workshop"     (about 400 ticks): the workshop after round 3, red with scrap, cards and tech,
##                  magenta already picked and ready.
## - "gameover"     (about 300 ticks): solo, the last fuel burns in round 2, YOUR CONVOY IS LOST.
## - "gameover_mp"  (about 200 ticks): magenta runs dry, red is the last rig standing.
## - "eliminated"   (about 220 ticks): three rigs; red runs dry and spectates (ELIMINATED).
##
## The sim does not give spitters an attack yet; step() lets them lob acid (owner -1 projectiles,
## which the sim already handles) on a fixed cadence so alien projectiles show up in shots.

const NAMES: PackedStringArray = ["skirmish", "horde", "workshop", "gameover", "gameover_mp", "eliminated"]
const WORKSHOP_ROUND := 3
const SPIT_PERIOD := 45  ## ticks
const SPIT_RANGE := 230.0
const SPIT_SPEED := 170.0
const SPIT_DAMAGE := 6.0


static func build(name: String, p_seed: int) -> SimWorld:
	match name:
		"skirmish":
			return _skirmish(p_seed)
		"horde":
			return _horde(p_seed)
		"workshop":
			var w: SimWorld = _skirmish(p_seed)
			w.fast_rounds = true
			return w
		"gameover":
			var w1 := SimWorld.new(p_seed)
			w1.fast_rounds = true
			w1.add_vehicle(1, SimWorld.ARENA.get_center())
			w1.vehicles[0].fuel = 15
			_scatter(w1, 500, 0.08, 0.04, 120.0, 700.0)
			return w1
		"gameover_mp":
			var w2: SimWorld = _skirmish(p_seed)
			w2.fast_rounds = true
			w2.vehicles[1].fuel = 15
			return w2
		"eliminated":
			var w3: SimWorld = _skirmish(p_seed)
			w3.fast_rounds = true
			w3.add_vehicle(3, Vector2(640, 600))
			w3.vehicles[0].fuel = 15
			return w3
	return null


static func step(name: String, w: SimWorld) -> void:
	w.step()
	_spit(w)
	match name:
		"workshop":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				if w.round < WORKSHOP_ROUND:
					_ready_all(w)
				elif not w.has_meta("staged"):
					_stage_workshop(w)
		"gameover":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
			elif w.phase == SimWorld.PHASE_COMBAT and w.round >= 2:
				_swarm(w, w.vehicles[0])
		"gameover_mp":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
			elif w.phase == SimWorld.PHASE_COMBAT and w.round >= 2:
				_swarm(w, w.vehicles[1])
		"eliminated":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
			elif w.phase == SimWorld.PHASE_COMBAT and w.round >= 2:
				_swarm(w, w.vehicles[0])


## The hive closes in on `v` (low hp, mites dropping in around it) until its last fuel burns.
static func _swarm(w: SimWorld, v: SimVehicle) -> void:
	if not v.alive or v.eliminated:
		return
	v.hp = minf(v.hp, 1.0)
	var a: float = w.rng.randf() * TAU
	var p: Vector2 = v.pos + Vector2.from_angle(a) * (40.0 + w.rng.randf() * 60.0)
	if SimWorld.ARENA.grow(-12.0).has_point(p):
		w.spawn_enemy(SimWorld.MITE if w.rng.randf() < 0.85 else SimWorld.SPITTER, p)


static func _ready_all(w: SimWorld) -> void:
	for v in w.vehicles:
		w.apply_command(v.peer_id, {"type": "ready"})


## A mid-game workshop: some scrap, a few cards and tech, 19 s on the clock, rival ready.
static func _stage_workshop(w: SimWorld) -> void:
	w.set_meta("staged", true)
	w.phase_ticks_left = 19 * SimWorld.TICK_RATE + 12
	var red: SimVehicle = w.vehicles[0]
	for id: String in ["shotgun", "steel_plates", "steel_plates", "v8_engine"]:
		Cards.grant(red, id)
	red.offers = Cards.roll_offers(w.rng, red)  # re-deal for the new loadout (slots are full now)
	red.scrap = 107
	for id: String in ["ballistics_1", "engineering_1", "ballistics_2"]:
		w.apply_command(red.peer_id, {"type": "buy_tech", "value": id})
	red.fuel = 60
	var mag: SimVehicle = w.vehicles[1]
	w.apply_command(mag.peer_id, {"type": "pick_card", "value": 0})
	w.apply_command(mag.peer_id, {"type": "ready"})


## Two rigs (red: circle / nearest, magenta: kite / players_first) in a running horde.
static func _skirmish(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, Vector2(420, 420))
	w.add_vehicle(2, Vector2(900, 300))
	w.apply_command(1, {"type": "set_drive", "value": "circle"})
	w.apply_command(1, {"type": "set_target", "value": "nearest"})
	w.apply_command(2, {"type": "set_drive", "value": "kite"})
	w.apply_command(2, {"type": "set_target", "value": "players_first"})
	_scatter(w, 170, 0.06, 0.05, 140.0, 640.0)
	return w


## One rig in the middle of ~800 aliens.
static func _horde(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, SimWorld.ARENA.get_center())
	_scatter(w, 800, 0.06, 0.03, 170.0, 760.0)
	return w


## Places `n` enemies around the vehicles (ring min_d..max_d from the arena centre), using world.rng.
static func _scatter(w: SimWorld, n: int, boulder_p: float, spitter_p: float, min_d: float, max_d: float) -> void:
	var c: Vector2 = SimWorld.ARENA.get_center()
	var area: Rect2 = SimWorld.ARENA.grow(-12.0)
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < n * 20:
		tries += 1
		var a: float = w.rng.randf() * TAU
		var d: float = lerpf(min_d, max_d, sqrt(w.rng.randf()))
		var p: Vector2 = c + Vector2(cos(a) * d, sin(a) * d * 0.62)
		if not area.has_point(p):
			continue
		var near: bool = false
		for v in w.vehicles:
			if v.pos.distance_to(p) < min_d:
				near = true
		if near:
			continue
		var r: float = w.rng.randf()
		var kind: int = SimWorld.BOULDER if r < boulder_p else (SimWorld.SPITTER if r < boulder_p + spitter_p else SimWorld.MITE)
		w.spawn_enemy(kind, p)
		placed += 1


static func _spit(w: SimWorld) -> void:
	for i in w.enemy_count:
		if w.enemy_kind[i] != SimWorld.SPITTER or (w.tick + w.enemy_id[i] * 11) % SPIT_PERIOD != 0:
			continue
		var from: Vector2 = w.enemy_pos[i]
		var best: SimVehicle = null
		var best_d: float = SPIT_RANGE
		for v in w.vehicles:
			var d: float = v.pos.distance_to(from)
			if v.alive and d < best_d:
				best = v
				best_d = d
		if best == null:
			continue
		var dir: Vector2 = from.direction_to(best.pos + best.vel * (best_d / SPIT_SPEED))
		w.spawn_projectile(from + dir * 10.0, dir * SPIT_SPEED, SPIT_RANGE / SPIT_SPEED + 0.2, SPIT_DAMAGE, -1)
