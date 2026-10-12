class_name SimWorld
extends RefCounted
## Deterministic simulation core. See docs/architecture.md ("Sim contract").
## No Node / scene tree / Input / OS / Time / global randf: all randomness is `rng`.

const TICK_RATE := 30
const DT := 1.0 / 30.0
const ARENA := Rect2(0, 0, 1280, 720)

const MITE := 0
const BOULDER := 1
const SPITTER := 2

# Per-kind stats, indexed by enemy kind.
const ENEMY_RADIUS: PackedFloat32Array = [6.0, 14.0, 8.0]
const ENEMY_SPEED: PackedFloat32Array = [90.0, 35.0, 55.0]  # px/s
const ENEMY_HP: PackedFloat32Array = [6.0, 80.0, 20.0]
const ENEMY_CONTACT_DAMAGE: PackedFloat32Array = [0.35, 1.5, 0.6]  # per tick while touching
const ENEMY_SCRAP: PackedInt32Array = [1, 5, 2]
const MAX_ENEMY_RADIUS := 14.0

const MAX_ENEMIES := 2500
const MAX_PROJECTILES := 2000
const MAX_EVENTS := 1024

const PROJECTILE_SPEED := 400.0  # px/s
const PROJECTILE_RADIUS := 2.0
const MUZZLE_OFFSET := 16.0
const SPREAD := 0.04  # radians, uniform +-
const PVP_KILL_SCRAP := 10

const SPAWN_RATE_START := 1.5  # enemies / s
const SPAWN_RATE_RAMP := 0.5  # added every SPAWN_RAMP_INTERVAL seconds
const SPAWN_RAMP_INTERVAL := 10.0
const BOULDER_CHANCE := 0.1
const SPAWN_INSET := 8.0

const HASH_CELL := 32.0
const STALE_MARGIN := 10.0  # enemies move < this per tick, hash is one move old
const MAX_SEPARATION_NEIGHBORS := 6

var tick: int = 0
var seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var vehicles: Array[SimVehicle] = []

var enemy_count: int = 0
var enemy_id: PackedInt32Array = PackedInt32Array()
var enemy_kind: PackedByteArray = PackedByteArray()
var enemy_pos: PackedVector2Array = PackedVector2Array()
var enemy_vel: PackedVector2Array = PackedVector2Array()  # px/s
var enemy_hp: PackedFloat32Array = PackedFloat32Array()

var proj_count: int = 0
var proj_pos: PackedVector2Array = PackedVector2Array()
var proj_vel: PackedVector2Array = PackedVector2Array()  # px/s
var proj_ttl: PackedFloat32Array = PackedFloat32Array()  # seconds
var proj_damage: PackedFloat32Array = PackedFloat32Array()
var proj_owner: PackedInt32Array = PackedInt32Array()  # vehicle id, -1 = alien

var events: Array[Dictionary] = []

## Set false to stop the timed enemy spawner (tests, scenarios).
var spawning_enabled: bool = true
var next_enemy_id: int = 0

## Shared scratch buffer for VehicleAI queries.
var ai_buf: PackedInt32Array = PackedInt32Array()

var _hash: SpatialHash
var _spawn_accum: float = 0.0
var _query_buf: PackedInt32Array = PackedInt32Array()
var _av_pos: PackedVector2Array = PackedVector2Array()  # alive vehicle positions (enemy phase)
var _av_idx: PackedInt32Array = PackedInt32Array()
var _contact: PackedFloat32Array = PackedFloat32Array()


func _init(p_seed: int) -> void:
	seed = p_seed
	rng.seed = p_seed
	_hash = SpatialHash.new(ARENA, HASH_CELL)


# ---------------------------------------------------------------- public API

func add_vehicle(peer_id: int, pos: Vector2) -> SimVehicle:
	var v := SimVehicle.new(vehicles.size(), peer_id, pos)
	v.heading = (ARENA.get_center() - pos).angle()
	vehicles.append(v)
	return v


func get_vehicle_for_peer(peer_id: int) -> SimVehicle:
	for v in vehicles:
		if v.peer_id == peer_id:
			return v
	return null


func apply_command(peer_id: int, cmd: Dictionary) -> void:
	var v: SimVehicle = get_vehicle_for_peer(peer_id)
	if v == null:
		return
	var value: String = str(cmd.get("value", ""))
	match str(cmd.get("type", "")):
		"set_drive":
			if value in ["circle", "kite", "charge"]:
				v.doctrine["drive"] = value
		"set_target":
			if value in ["nearest", "strongest", "players_first"]:
				v.doctrine["target"] = value


## Adds an enemy and returns its stable id (or -1 if the cap is reached).
func spawn_enemy(kind: int, pos: Vector2) -> int:
	if enemy_count >= MAX_ENEMIES:
		return -1
	var id: int = next_enemy_id
	next_enemy_id += 1
	enemy_id.append(id)
	enemy_kind.append(kind)
	enemy_pos.append(pos)
	enemy_vel.append(Vector2.ZERO)
	enemy_hp.append(ENEMY_HP[kind])
	enemy_count += 1
	return id


func spawn_projectile(pos: Vector2, vel: Vector2, ttl: float, damage: float, owner: int) -> void:
	if proj_count >= MAX_PROJECTILES:
		return
	proj_pos.append(pos)
	proj_vel.append(vel)
	proj_ttl.append(ttl)
	proj_damage.append(damage)
	proj_owner.append(owner)
	proj_count += 1


## Enemy indices within `radius` of `center` (as of the end of the previous tick's hash,
## filtered by current positions). Results are written to out[0..n).
func query_enemies(center: Vector2, radius: float, out: PackedInt32Array) -> int:
	return _hash.query_circle(center, radius, enemy_pos, out, STALE_MARGIN)


func step() -> void:
	events.clear()
	_update_enemies()
	_update_vehicles()
	_update_projectiles()
	_compact_enemies()
	_spawn_tick()
	_hash.rebuild(enemy_pos, enemy_count)
	tick += 1


func checksum() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var head := PackedInt64Array([tick, enemy_count, proj_count, vehicles.size()])
	ctx.update(head.to_byte_array())
	var vf := PackedFloat64Array()
	for v in vehicles:
		vf.append(float(v.id))
		vf.append(float(v.peer_id))
		vf.append(v.pos.x)
		vf.append(v.pos.y)
		vf.append(v.vel.x)
		vf.append(v.vel.y)
		vf.append(v.heading)
		vf.append(v.hp)
		vf.append(v.max_hp)
		vf.append(1.0 if v.alive else 0.0)
		vf.append(float(v.scrap))
		vf.append(float(v.kills))
		vf.append(float(str(v.doctrine.get("drive", "")).hash()))
		vf.append(float(str(v.doctrine.get("target", "")).hash()))
		for wp in v.weapons:
			vf.append(float(wp["damage"]))
			vf.append(float(wp["range"]))
			vf.append(float(wp["cooldown"]))
			vf.append(float(wp["aim"]))
	for part: PackedByteArray in [
		vf.to_byte_array(),
		enemy_id.to_byte_array(),
		enemy_kind,
		enemy_pos.to_byte_array(),
		enemy_vel.to_byte_array(),
		enemy_hp.to_byte_array(),
		proj_pos.to_byte_array(),
		proj_vel.to_byte_array(),
		proj_ttl.to_byte_array(),
		proj_damage.to_byte_array(),
		proj_owner.to_byte_array(),
	]:
		if part.size() > 0:  # HashingContext rejects empty updates
			ctx.update(part)
	return ctx.finish().decode_s64(0)


## Rebuilds derived structures (spatial hash, counts) after external code (e.g. a network
## snapshot) rewrote the enemy/projectile arrays.
func rebuild_derived() -> void:
	enemy_count = enemy_id.size()
	proj_count = proj_pos.size()
	_hash.rebuild(enemy_pos, enemy_count)


# ---------------------------------------------------------------- events

func _emit(type: String, pos: Vector2, owner: int, kind: int) -> void:
	if events.size() >= MAX_EVENTS:
		return
	events.append({"type": type, "pos": pos, "owner": owner, "kind": kind})


# ---------------------------------------------------------------- enemies

func _update_enemies() -> void:
	var n: int = enemy_count
	if n == 0:
		return
	# Snapshot alive vehicles.
	_av_pos.clear()
	_av_idx.clear()
	for vi in vehicles.size():
		if vehicles[vi].alive:
			_av_pos.append(vehicles[vi].pos)
			_av_idx.append(vi)
	var nv: int = _av_pos.size()
	_contact.resize(vehicles.size())
	_contact.fill(0.0)

	var cols: int = _hash.cols
	var rows: int = _hash.rows
	var inv: float = _hash.inv_cell
	var ox: float = _hash.origin.x
	var oy: float = _hash.origin.y
	var cell_start: PackedInt32Array = _hash.cell_start
	var items: PackedInt32Array = _hash.items
	var a_min := ARENA.position
	var a_max := ARENA.end
	var vr: float = SimVehicle.RADIUS

	for i in n:
		if enemy_hp[i] <= 0.0:
			continue
		var kind: int = enemy_kind[i]
		var r: float = ENEMY_RADIUS[kind]
		var p: Vector2 = enemy_pos[i]

		# Chase the nearest alive vehicle.
		var best_d2: float = INF
		var bk: int = -1
		for k in nv:
			var d2: float = p.distance_squared_to(_av_pos[k])
			if d2 < best_d2:
				best_d2 = d2
				bk = k
		var desired: Vector2 = Vector2.ZERO
		if bk >= 0:
			var dir: Vector2 = _av_pos[bk] - p
			var dl: float = dir.length()
			if dl > 0.001:
				desired = dir * (ENEMY_SPEED[kind] / dl)
		var vel: Vector2 = enemy_vel[i].lerp(desired, 0.25)
		var np: Vector2 = p + vel * DT

		# Mild separation from neighbours (3x3 cells, capped).
		var cx: int = clampi(int((p.x - ox) * inv), 0, cols - 1)
		var cy: int = clampi(int((p.y - oy) * inv), 0, rows - 1)
		var sep: Vector2 = Vector2.ZERO
		var seen: int = 0
		for gy in range(maxi(cy - 1, 0), mini(cy + 2, rows)):
			if seen >= MAX_SEPARATION_NEIGHBORS:
				break
			for gx in range(maxi(cx - 1, 0), mini(cx + 2, cols)):
				var c: int = gy * cols + gx
				for s in range(cell_start[c], cell_start[c + 1]):
					var j: int = items[s]
					if j == i:
						continue
					var dv: Vector2 = np - enemy_pos[j]
					var rr: float = r + ENEMY_RADIUS[enemy_kind[j]]
					var d2: float = dv.length_squared()
					if d2 < rr * rr:
						if d2 < 0.0001:
							dv = Vector2.from_angle(float(i) * 2.399963)
							d2 = 1.0
						var dl2: float = sqrt(d2)
						sep += dv * ((rr - dl2) * 0.5 / dl2)
						seen += 1
						if seen >= MAX_SEPARATION_NEIGHBORS:
							break
				if seen >= MAX_SEPARATION_NEIGHBORS:
					break
		np += sep

		# Contact with vehicles: stop at the hull, deal damage, take ram damage.
		var killed: bool = false
		for k in nv:
			var vp: Vector2 = _av_pos[k]
			var dv2: Vector2 = np - vp
			var rr2: float = vr + r
			var dd2: float = dv2.length_squared()
			if dd2 < rr2 * rr2:
				var dl3: float = sqrt(dd2)
				if dl3 < 0.001:
					dv2 = Vector2.from_angle(float(i) * 2.399963)
					dl3 = 1.0
				np = vp + dv2 * (rr2 / dl3)
				vel = Vector2.ZERO
				var vidx: int = _av_idx[k]
				_contact[vidx] += ENEMY_CONTACT_DAMAGE[kind]
				var ram: float = vehicles[vidx].ram_damage
				if ram > 0.0 and not killed:
					_hit_enemy(i, ram, vidx)
					killed = enemy_hp[i] <= 0.0

		np.x = clampf(np.x, a_min.x, a_max.x)
		np.y = clampf(np.y, a_min.y, a_max.y)
		enemy_pos[i] = np
		enemy_vel[i] = vel

	for vidx in vehicles.size():
		if _contact[vidx] > 0.0:
			_damage_vehicle(vehicles[vidx], _contact[vidx], -1)


## Applies damage to an enemy; credits the kill (event, scrap, kills) on death.
## The enemy stays in the arrays until _compact_enemies().
func _hit_enemy(j: int, dmg: float, killer: int) -> void:
	if enemy_hp[j] <= 0.0:
		return
	enemy_hp[j] -= dmg
	if enemy_hp[j] > 0.0:
		return
	var kind: int = enemy_kind[j]
	_emit("kill", enemy_pos[j], killer, kind)
	if killer >= 0 and killer < vehicles.size():
		var kv: SimVehicle = vehicles[killer]
		kv.scrap += ENEMY_SCRAP[kind]
		kv.kills += 1


## Swap-removes dead enemies (hp <= 0), then shrinks all arrays once.
func _compact_enemies() -> void:
	var n: int = enemy_count
	var i: int = n - 1
	while i >= 0:
		if enemy_hp[i] <= 0.0:
			n -= 1
			enemy_id[i] = enemy_id[n]
			enemy_kind[i] = enemy_kind[n]
			enemy_pos[i] = enemy_pos[n]
			enemy_vel[i] = enemy_vel[n]
			enemy_hp[i] = enemy_hp[n]
		i -= 1
	if n != enemy_count:
		enemy_id.resize(n)
		enemy_kind.resize(n)
		enemy_pos.resize(n)
		enemy_vel.resize(n)
		enemy_hp.resize(n)
		enemy_count = n


func _spawn_tick() -> void:
	if not spawning_enabled:
		return
	var secs: float = float(tick) * DT
	var rate: float = SPAWN_RATE_START + SPAWN_RATE_RAMP * floorf(secs / SPAWN_RAMP_INTERVAL)
	_spawn_accum += rate * DT
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		var side: int = rng.randi() % 4
		var t: float = rng.randf()
		var pos: Vector2
		match side:
			0:
				pos = Vector2(ARENA.position.x + t * ARENA.size.x, ARENA.position.y + SPAWN_INSET)
			1:
				pos = Vector2(ARENA.position.x + t * ARENA.size.x, ARENA.end.y - SPAWN_INSET)
			2:
				pos = Vector2(ARENA.position.x + SPAWN_INSET, ARENA.position.y + t * ARENA.size.y)
			_:
				pos = Vector2(ARENA.end.x - SPAWN_INSET, ARENA.position.y + t * ARENA.size.y)
		var kind: int = BOULDER if rng.randf() < BOULDER_CHANCE else MITE
		spawn_enemy(kind, pos)


# ---------------------------------------------------------------- vehicles

func _update_vehicles() -> void:
	var lo := ARENA.position + Vector2(SimVehicle.RADIUS, SimVehicle.RADIUS)
	var hi := ARENA.end - Vector2(SimVehicle.RADIUS, SimVehicle.RADIUS)
	for v in vehicles:
		if not v.alive:
			continue
		VehicleAI.update_target(self, v)
		VehicleAI.steer(self, v)
		v.pos += v.vel * DT
		v.pos.x = clampf(v.pos.x, lo.x, hi.x)
		v.pos.y = clampf(v.pos.y, lo.y, hi.y)
	_resolve_vehicle_contacts()
	for v in vehicles:
		if v.alive:
			_fire_weapons(v)


func _resolve_vehicle_contacts() -> void:
	var nv: int = vehicles.size()
	var min_d: float = SimVehicle.RADIUS * 2.0
	for a in nv:
		var va: SimVehicle = vehicles[a]
		if not va.alive:
			continue
		for b in range(a + 1, nv):
			var vb: SimVehicle = vehicles[b]
			if not vb.alive:
				continue
			var dv: Vector2 = vb.pos - va.pos
			var d2: float = dv.length_squared()
			if d2 >= min_d * min_d:
				continue
			var d: float = sqrt(d2)
			if d < 0.001:
				dv = Vector2.from_angle(float(a) + 0.5)
				d = 1.0
			var push: Vector2 = dv * ((min_d - d) * 0.5 / d)
			va.pos -= push
			vb.pos += push
			if va.ram_damage > 0.0:
				_damage_vehicle(vb, va.ram_damage, va.id)
			if vb.ram_damage > 0.0:
				_damage_vehicle(va, vb.ram_damage, vb.id)


func _damage_vehicle(v: SimVehicle, dmg: float, attacker: int) -> void:
	if not v.alive:
		return
	v.hp -= dmg
	if v.hp > 0.0:
		return
	v.hp = 0.0
	v.alive = false
	v.vel = Vector2.ZERO
	v.target_kind = 0
	_emit("vehicle_destroyed", v.pos, v.id, -1)
	if attacker >= 0 and attacker != v.id and attacker < vehicles.size():
		var av: SimVehicle = vehicles[attacker]
		av.kills += 1
		av.scrap += PVP_KILL_SCRAP


func _fire_weapons(v: SimVehicle) -> void:
	var has_target: bool = v.target_kind != 0
	for w in v.weapons:
		var cd: int = w["cooldown"]
		if cd > 0:
			cd -= 1
			w["cooldown"] = cd
		if not has_target:
			continue
		var dist: float = v.pos.distance_to(v.target_pos)
		var lead: Vector2 = v.target_pos + v.target_vel * (dist / PROJECTILE_SPEED)
		var to: Vector2 = lead - v.pos
		var ang: float = to.angle()
		w["aim"] = ang
		if cd > 0 or dist > float(w["range"]) or proj_count >= MAX_PROJECTILES:
			continue
		var fire_ang: float = ang + rng.randf_range(-SPREAD, SPREAD)
		var dir: Vector2 = Vector2.from_angle(fire_ang)
		var muzzle: Vector2 = v.pos + dir * MUZZLE_OFFSET
		var ttl: float = float(w["range"]) / PROJECTILE_SPEED + 0.05
		spawn_projectile(muzzle, dir * PROJECTILE_SPEED, ttl, float(w["damage"]), v.id)
		w["cooldown"] = int(w["cooldown_ticks"])
		_emit("fire", muzzle, v.id, 0)


# ---------------------------------------------------------------- projectiles

## Earliest t in [0, 1] where the segment p0 + d * t touches the circle (c, r), or -1.
static func _segment_circle_t(p0: Vector2, d: Vector2, c: Vector2, r: float) -> float:
	var f: Vector2 = p0 - c
	var cc: float = f.length_squared() - r * r
	if cc <= 0.0:
		return 0.0
	var a: float = d.length_squared()
	if a < 0.000001:
		return -1.0
	var b: float = f.dot(d)
	var disc: float = b * b - a * cc
	if disc < 0.0:
		return -1.0
	var t: float = (-b - sqrt(disc)) / a
	if t < 0.0 or t > 1.0:
		return -1.0
	return t


func _update_projectiles() -> void:
	var n: int = proj_count
	var i: int = n - 1
	var nveh: int = vehicles.size()
	var a_lo := ARENA.position - Vector2(40, 40)
	var a_hi := ARENA.end + Vector2(40, 40)
	while i >= 0:
		var p0: Vector2 = proj_pos[i]
		var step_v: Vector2 = proj_vel[i] * DT
		var p1: Vector2 = p0 + step_v
		var ttl: float = proj_ttl[i] - DT
		var owner: int = proj_owner[i]
		var dmg: float = proj_damage[i]
		var best_t: float = 2.0
		var hit_enemy: int = -1
		var hit_vehicle: int = -1

		if owner >= 0:
			var reach: float = step_v.length() * 0.5 + MAX_ENEMY_RADIUS + PROJECTILE_RADIUS
			var cnt: int = _hash.query_circle(p0 + step_v * 0.5, reach, enemy_pos, _query_buf, STALE_MARGIN)
			for q in cnt:
				var j: int = _query_buf[q]
				if enemy_hp[j] <= 0.0:
					continue
				var t: float = _segment_circle_t(p0, step_v, enemy_pos[j], ENEMY_RADIUS[enemy_kind[j]] + PROJECTILE_RADIUS)
				if t >= 0.0 and t < best_t:
					best_t = t
					hit_enemy = j
		for vi in nveh:
			var v: SimVehicle = vehicles[vi]
			if not v.alive or v.id == owner:
				continue
			var tv: float = _segment_circle_t(p0, step_v, v.pos, SimVehicle.RADIUS + PROJECTILE_RADIUS)
			if tv >= 0.0 and tv < best_t:
				best_t = tv
				hit_vehicle = vi
				hit_enemy = -1

		var remove: bool = false
		if hit_vehicle >= 0:
			var hv: SimVehicle = vehicles[hit_vehicle]
			_emit("hit", p0 + step_v * best_t, owner, -1)
			_damage_vehicle(hv, dmg, owner)
			remove = true
		elif hit_enemy >= 0:
			_emit("hit", p0 + step_v * best_t, owner, enemy_kind[hit_enemy])
			_hit_enemy(hit_enemy, dmg, owner)
			remove = true
		elif ttl <= 0.0 or p1.x < a_lo.x or p1.y < a_lo.y or p1.x > a_hi.x or p1.y > a_hi.y:
			remove = true

		if remove:
			n -= 1
			proj_pos[i] = proj_pos[n]
			proj_vel[i] = proj_vel[n]
			proj_ttl[i] = proj_ttl[n]
			proj_damage[i] = proj_damage[n]
			proj_owner[i] = proj_owner[n]
		else:
			proj_pos[i] = p1
			proj_ttl[i] = ttl
		i -= 1
	if n != proj_count:
		proj_pos.resize(n)
		proj_vel.resize(n)
		proj_ttl.resize(n)
		proj_damage.resize(n)
		proj_owner.resize(n)
		proj_count = n
