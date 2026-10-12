class_name Scenarios
extends RefCounted
## Named, deterministic SimWorld setups for screenshots (main.gd --shot=...) and manual checks.
## build(name, seed) + step(name, world) N times always gives the same state.
##
## The sim does not give spitters an attack yet; step() lets them lob acid (owner -1 projectiles,
## which the sim already handles) on a fixed cadence so alien projectiles show up in shots.

const NAMES: PackedStringArray = ["skirmish", "horde"]
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
	return null


static func step(_name: String, w: SimWorld) -> void:
	w.step()
	_spit(w)


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
