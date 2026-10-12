class_name VehicleAI
extends RefCounted
## Doctrine-driven target selection and steering. Stateless: scratch lives on SimVehicle.

const RETARGET_TICKS := 6
const NEAR_QUERY := 450.0
const TURN_RATE := 3.2  ## rad/s
const WALL_MARGIN := 100.0
const SPEED_CIRCLE := 95.0
const SPEED_KITE := 105.0
const SPEED_CHARGE := 125.0
const CHARGE_RAM_DAMAGE := 2.0


static func update_target(w: SimWorld, v: SimVehicle) -> void:
	if _target_valid(w, v) and (w.tick + v.id) % RETARGET_TICKS != 0:
		_refresh_target(w, v)
	else:
		_acquire(w, v)


static func _target_valid(w: SimWorld, v: SimVehicle) -> bool:
	if v.target_kind == 1:
		var i: int = v.target_index
		return i >= 0 and i < w.enemy_count and w.enemy_id[i] == v.target_id and w.enemy_hp[i] > 0.0
	if v.target_kind == 2:
		return w.vehicles[v.target_id].alive
	return false


static func _refresh_target(w: SimWorld, v: SimVehicle) -> void:
	if v.target_kind == 1:
		v.target_pos = w.enemy_pos[v.target_index]
		v.target_vel = w.enemy_vel[v.target_index]
	else:
		var t: SimVehicle = w.vehicles[v.target_id]
		v.target_pos = t.pos
		v.target_vel = t.vel


static func _acquire(w: SimWorld, v: SimVehicle) -> void:
	v.target_kind = 0
	v.target_index = -1
	v.target_id = -1
	var rng_range: float = v.max_range()
	var mode: String = v.doctrine.get("target", "nearest")
	if v.retaliate_ticks > 0 and mode != "players_first" and w.pvp_enabled():
		# Return fire: shoot back at the player that hurt us, if it is in range.
		var attacker: SimVehicle = w.vehicles[v.retaliate_id]
		if attacker.alive and v.pos.distance_squared_to(attacker.pos) <= rng_range * rng_range:
			v.target_kind = 2
			v.target_index = attacker.id
			v.target_id = attacker.id
			_refresh_target(w, v)
			return
	if mode == "players_first" and w.pvp_enabled():
		var best: SimVehicle = null
		var best_d2: float = rng_range * rng_range
		for o in w.vehicles:
			if o.id == v.id or not o.alive:
				continue
			var d2: float = v.pos.distance_squared_to(o.pos)
			if d2 <= best_d2:
				best_d2 = d2
				best = o
		if best != null:
			v.target_kind = 2
			v.target_index = best.id
			v.target_id = best.id
			_refresh_target(w, v)
			return
	var idx: int = -1
	if mode == "strongest":
		idx = _strongest_in_range(w, v.pos, rng_range)
	if idx < 0:
		idx = _nearest_enemy(w, v.pos)
	if idx >= 0:
		v.target_kind = 1
		v.target_index = idx
		v.target_id = w.enemy_id[idx]
		_refresh_target(w, v)


static func _strongest_in_range(w: SimWorld, p: Vector2, r: float) -> int:
	var n: int = w.query_enemies(p, r, w.ai_buf)
	var best: int = -1
	var best_hp: float = 0.0
	for q in n:
		var j: int = w.ai_buf[q]
		var hp: float = w.enemy_hp[j]
		if hp > best_hp:
			best_hp = hp
			best = j
	return best


static func _nearest_enemy(w: SimWorld, p: Vector2) -> int:
	var n: int = w.query_enemies(p, NEAR_QUERY, w.ai_buf)
	var best: int = -1
	var best_d2: float = INF
	if n > 0:
		for q in n:
			var j: int = w.ai_buf[q]
			if w.enemy_hp[j] <= 0.0:
				continue
			var d2: float = p.distance_squared_to(w.enemy_pos[j])
			if d2 < best_d2:
				best_d2 = d2
				best = j
		if best >= 0:
			return best
	# Nothing nearby: linear fallback (cheap when the field is sparse).
	for j in w.enemy_count:
		if w.enemy_hp[j] <= 0.0:
			continue
		var d2: float = p.distance_squared_to(w.enemy_pos[j])
		if d2 < best_d2:
			best_d2 = d2
			best = j
	return best


## Turns the heading toward the doctrine's desired direction (rate limited) and sets vel.
static func steer(w: SimWorld, v: SimVehicle) -> void:
	var drive: String = v.doctrine.get("drive", "circle")
	var rng_range: float = maxf(v.engage_range(), 40.0)
	var desired: Vector2 = Vector2.ZERO
	var speed: float = SPEED_CIRCLE
	v.ram_damage = 0.0
	if v.target_kind != 0:
		var to_t: Vector2 = v.target_pos - v.pos
		var d: float = to_t.length()
		var u: Vector2 = to_t / maxf(d, 0.001)
		var tang: Vector2 = Vector2(-u.y, u.x) * v.orbit_dir
		if drive == "charge":
			desired = u
			speed = SPEED_CHARGE
			v.ram_damage = CHARGE_RAM_DAMAGE * v.ram_mult
		elif drive == "kite":
			var want: float = rng_range * 0.9
			var k: float = clampf((d - want) / (rng_range * 0.4), -1.0, 1.0)
			desired = u * k + tang * 0.6
			speed = SPEED_KITE
		else:
			var r0: float = rng_range * 0.75
			var k2: float = clampf((d - r0) / r0 * 2.0, -1.2, 1.2)
			desired = tang + u * k2
			speed = SPEED_CIRCLE
	else:
		# Idle: patrol around the arena centre.
		var c: Vector2 = SimWorld.ARENA.get_center()
		var to_c: Vector2 = c - v.pos
		var dc: float = to_c.length()
		var uc: Vector2 = to_c / maxf(dc, 0.001)
		desired = Vector2(-uc.y, uc.x) * v.orbit_dir + uc * clampf((dc - 200.0) / 200.0, -1.0, 1.0)
	if desired.length_squared() > 0.000001:
		desired = desired.normalized()
	else:
		desired = Vector2.from_angle(v.heading)
	desired += _wall_push(v.pos) * 2.5
	var diff: float = angle_difference(v.heading, desired.angle())
	v.ram_damage += v.contact_damage
	var max_turn: float = TURN_RATE * v.turn_rate * SimWorld.DT
	v.heading = wrapf(v.heading + clampf(diff, -max_turn, max_turn), -PI, PI)
	var slow: float = 1.0 - 0.35 * minf(absf(diff) / 0.6, 1.0)
	v.vel = Vector2.from_angle(v.heading) * speed * v.speed * slow


## 0 in the open field, pointing inward (magnitude up to ~1 per axis) near walls.
static func _wall_push(p: Vector2) -> Vector2:
	var a: Rect2 = SimWorld.ARENA
	var push: Vector2 = Vector2.ZERO
	var m: float = WALL_MARGIN
	var l: float = p.x - a.position.x
	var r: float = a.end.x - p.x
	var t: float = p.y - a.position.y
	var b: float = a.end.y - p.y
	if l < m:
		push.x += (m - l) / m
	if r < m:
		push.x -= (m - r) / m
	if t < m:
		push.y += (m - t) / m
	if b < m:
		push.y -= (m - b) / m
	return push
