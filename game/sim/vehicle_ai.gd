class_name VehicleAI
extends RefCounted
## Doctrine-driven target selection and steering (the rules in Doctrine pick drive / target modes). Stateless: scratch lives on SimVehicle.

const RETARGET_TICKS := 6
const NEAR_QUERY := 450.0
const TURN_RATE := 3.2  ## rad/s
const WALL_MARGIN := 100.0
const SPEED_CIRCLE := 95.0
const SPEED_KITE := 96.0
const SPEED_CHARGE := 125.0
const SPEED_FLEE := 110.0
const CHARGE_RAM_DAMAGE := 2.0


static func update_target(w: SimWorld, v: SimVehicle) -> void:
	if _target_valid(w, v) and (w.tick + v.id) % RETARGET_TICKS != 0 and v.acquired_mode == v.eff_target:
		_refresh_target(w, v)
	else:
		v.acquired_mode = v.eff_target
		_acquire(w, v)


static func _target_valid(w: SimWorld, v: SimVehicle) -> bool:
	if v.target_kind == 1:
		var i: int = v.target_index
		return i >= 0 and i < w.enemy_count and w.enemy_id[i] == v.target_id and w.enemy_hp[i] > 0.0
	if v.target_kind == 2:
		var t: SimVehicle = w.vehicles[v.target_id]
		return t.alive and t.invuln_ticks <= 0  # a rival that just respawned / combat start cannot be targeted
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
	var mode: String = v.eff_target
	if v.retaliate_ticks > 0 and mode != "players_first" and w.pvp_enabled():
		# Return fire: shoot back at the player that hurt us, if it is in range.
		var attacker: SimVehicle = w.vehicles[v.retaliate_id]
		if attacker.alive and attacker.invuln_ticks <= 0 and v.pos.distance_squared_to(attacker.pos) <= rng_range * rng_range:
			v.target_kind = 2
			v.target_index = attacker.id
			v.target_id = attacker.id
			_refresh_target(w, v)
			return
	var t: Vector3i = find_target(w, v, mode, 0.0)
	if t.x != 0:
		v.target_kind = t.x
		v.target_index = t.y
		v.target_id = t.z
		_refresh_target(w, v)


## Picks a target for target mode `mode` (Doctrine.RIG_TARGETS / WEAPON_TARGETS). Returns
## Vector3i(kind, index, id) with kind 0 = nothing. `reach` > 0 (a weapon) limits every candidate to
## that distance; 0 (the rig) takes aliens anywhere and rivals within the longest weapon range.
## Modes that find nothing fall back to the nearest alien.
static func find_target(w: SimWorld, v: SimVehicle, mode: String, reach: float) -> Vector3i:
	var r: float = reach if reach > 0.0 else v.max_range()
	if mode == "players_first" and w.pvp_enabled():
		# Prefer the marked leader (bounty), then the highest leader score in range (never the weakest rig),
		# nearest among equals. Rivals under respawn / round-start protection cannot be targeted.
		var best: SimVehicle = null
		var best_d2: float = r * r
		var best_score: int = -1
		for o in w.vehicles:
			if o.id == v.id or not o.alive or o.invuln_ticks > 0:
				continue
			var d2: float = v.pos.distance_squared_to(o.pos)
			if d2 > r * r:
				continue
			var sc: int = w.leader_score(o) + (1000000 if o.peer_id == w.leader_peer else 0)
			if sc > best_score or (sc == best_score and d2 < best_d2):
				best_score = sc
				best_d2 = d2
				best = o
		if best != null:
			return Vector3i(2, best.id, best.id)
	var idx: int = -1
	match mode:
		"strongest":
			idx = _extreme_in_range(w, v.pos, r, true)
		"weakest":
			idx = _extreme_in_range(w, v.pos, r, false)
		"boulders":
			idx = _nearest_enemy(w, v.pos, -1, SimWorld.BOULDER, reach)
		"spitters":
			idx = _nearest_enemy(w, v.pos, -1, SimWorld.SPITTER, reach)
	if idx < 0:
		# Charge without berserker does not ram boulders: prefer anything else if it is around.
		var skip: int = SimWorld.BOULDER if reach <= 0.0 and _avoids_boulders(v) else -1
		idx = _nearest_enemy(w, v.pos, skip, -1, reach)
		if idx < 0 and skip >= 0:
			idx = _nearest_enemy(w, v.pos, -1, -1, reach)
	if idx >= 0:
		return Vector3i(1, idx, w.enemy_id[idx])
	return Vector3i.ZERO


## Weapon targeting: "follow" shares the rig's target (tk = 0); any other mode keeps its own target
## in the weapon's scratch keys (tk / ti / tid / tp / tv / tmode), re-acquired every RETARGET_TICKS
## within the weapon's range. Finding nothing also falls back to the rig's target.
static func update_weapon_target(w: SimWorld, v: SimVehicle, wp: Dictionary, slot: int, mode: String) -> void:
	if mode == "follow":
		wp["tk"] = 0
		return
	var tk: int = int(wp.get("tk", 0))
	var ti: int = int(wp.get("ti", -1))
	var tid: int = int(wp.get("tid", -1))
	if tk != 0 and str(wp.get("tmode", "")) == mode and is_valid(w, tk, ti, tid) and (w.tick + v.id + slot + 1) % RETARGET_TICKS != 0:
		var p: Array = target_motion(w, tk, ti, tid)
		wp["tp"] = p[0]
		wp["tv"] = p[1]
		return
	var t: Vector3i = find_target(w, v, mode, float(wp["range"]))
	wp["tk"] = t.x
	wp["ti"] = t.y
	wp["tid"] = t.z
	wp["tmode"] = mode
	if t.x != 0:
		var q: Array = target_motion(w, t.x, t.y, t.z)
		wp["tp"] = q[0]
		wp["tv"] = q[1]


static func is_valid(w: SimWorld, kind: int, index: int, id: int) -> bool:
	if kind == 1:
		return index >= 0 and index < w.enemy_count and w.enemy_id[index] == id and w.enemy_hp[index] > 0.0
	if kind == 2:
		var t: SimVehicle = w.vehicles[id]
		return t.alive and t.invuln_ticks <= 0 and w.pvp_enabled()
	return false


## [position, velocity] of a (valid) target.
static func target_motion(w: SimWorld, kind: int, index: int, id: int) -> Array:
	if kind == 1:
		return [w.enemy_pos[index], w.enemy_vel[index]]
	var t: SimVehicle = w.vehicles[id]
	return [t.pos, t.vel]


## Index of the alien with the most (`most`) or least hp within r of p, or -1.
static func _extreme_in_range(w: SimWorld, p: Vector2, r: float, most: bool) -> int:
	var n: int = w.query_enemies(p, r, w.ai_buf)
	var best: int = -1
	var best_hp: float = 0.0
	for q in n:
		var j: int = w.ai_buf[q]
		var hp: float = w.enemy_hp[j]
		if hp <= 0.0:
			continue
		if best < 0 or (most and hp > best_hp) or (not most and hp < best_hp):
			best_hp = hp
			best = j
	return best


## The charge doctrine rams whatever it targets; boulders are only worth it with the berserker card.
static func _avoids_boulders(v: SimVehicle) -> bool:
	return v.eff_drive == "charge" and not v.cards.has("berserker")


## Nearest live alien to p: skipping kind `skip_kind`, only of kind `only_kind` (-1 = any). With
## max_r > 0 only within max_r; else nearby first, then anywhere.
static func _nearest_enemy(w: SimWorld, p: Vector2, skip_kind: int = -1, only_kind: int = -1, max_r: float = 0.0) -> int:
	var n: int = w.query_enemies(p, max_r if max_r > 0.0 else NEAR_QUERY, w.ai_buf)
	var best: int = -1
	var best_d2: float = INF
	if n > 0:
		for q in n:
			var j: int = w.ai_buf[q]
			if w.enemy_hp[j] <= 0.0 or w.enemy_kind[j] == skip_kind or (only_kind >= 0 and w.enemy_kind[j] != only_kind):
				continue
			var d2: float = p.distance_squared_to(w.enemy_pos[j])
			if d2 < best_d2:
				best_d2 = d2
				best = j
		if best >= 0 or max_r > 0.0:
			return best
	if max_r > 0.0:
		return -1
	# Nothing nearby: linear fallback (cheap when the field is sparse).
	for j in w.enemy_count:
		if w.enemy_hp[j] <= 0.0 or w.enemy_kind[j] == skip_kind or (only_kind >= 0 and w.enemy_kind[j] != only_kind):
			continue
		var d2: float = p.distance_squared_to(w.enemy_pos[j])
		if d2 < best_d2:
			best_d2 = d2
			best = j
	return best


## Turns the heading toward the doctrine's desired direction (rate limited) and sets vel.
static func steer(w: SimWorld, v: SimVehicle) -> void:
	var drive: String = v.eff_drive
	var rng_range: float = maxf(v.engage_range(), 40.0)
	var desired: Vector2 = Vector2.ZERO
	var speed: float = SPEED_CIRCLE
	v.ram_damage = 0.0
	if v.target_kind != 0:
		var to_t: Vector2 = v.target_pos - v.pos
		var d: float = to_t.length()
		var u: Vector2 = to_t / maxf(d, 0.001)
		var tang: Vector2 = Vector2(-u.y, u.x) * v.orbit_dir
		var ram_ok: bool = true
		if drive == "charge" and v.target_kind == 1 and w.enemy_kind[v.target_index] == SimWorld.BOULDER and _avoids_boulders(v):
			ram_ok = false  # only boulders left: shoot them from a circle instead of ramming
		if drive == "charge" and ram_ok:
			desired = u
			speed = SPEED_CHARGE
			v.ram_damage = CHARGE_RAM_DAMAGE * v.ram_mult
		elif drive == "flee":
			# Break away from the target, veering sideways so the rig does not run into a wall.
			desired = -u + tang * 0.5
			speed = SPEED_FLEE
		elif drive == "hold":
			# Stand and turn the nose toward the target.
			desired = u
			speed = 0.0
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
