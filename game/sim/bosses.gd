class_name Bosses
extends RefCounted
## Boss rounds (design doc 7f / 7j): every 4th round (4, 8, ...) the first surge brings a boss. Two bosses, the
## match seed picks which comes first and they alternate; from round 12 they are enraged. Bosses are ordinary
## entries of the enemy arrays (kinds SimWorld.BOSS_A / BOSS_B / BOSS_SHARD) so targeting, shots, splash, burn
## and ramming work unchanged; everything boss specific (phases, attacks, telegraph markers, rewards) lives here
## and in the `boss_*` fields of SimWorld. Pure sim: all randomness comes from `world.rng`.
##
## Tripod Queen (BOSS_A): slow artillery walker. Shells land after a telegraph (marker MARK_SHELL), phase 2 adds
## mite broods, phase 3 volleys of 3 shells and a faster walk.
## Shard Colossus (BOSS_B): brute. Radial ring of slow crystal shards after a glow telegraph (MARK_RING), phase 2
## adds telegraphed charges (MARK_CHARGE), phase 3 splits it into three BOSS_SHARD minibosses.

const FIRST_ROUND := 4
const EVERY := 4
const ENRAGE_ROUND := 12  ## from this round the boss is enraged
const WARN_TICKS := 90  ## "boss" warning event this long before the spawn (3 s)

## SimWorld.boss_state
const ST_NONE := 0  ## nothing happened yet this round (or no boss round)
const ST_WARNED := 1
const ST_ACTIVE := 2
const ST_KILLED := 3
const ST_RETREATED := 4

## Telegraph marker kinds (SimWorld.boss_marks[i]["k"])
const MARK_SHELL := 0  ## circle at pos, radius r: a shell lands when `left` reaches 0
const MARK_RING := 1  ## glow around pos (the boss), radius r: a ring of shards is released when `left` reaches 0
const MARK_CHARGE := 2  ## line from pos to pos2, width r: the boss charges along it when `left` reaches 0

const NAMES: Dictionary = {3: "TRIPOD QUEEN", 4: "SHARD COLOSSUS", 5: "CRYSTAL SHARD"}

# --- balance
const HP_BASE := 450.0  ## x (1 + HP_PER_ROUND per boss round index) x (1 + HP_PER_EXTRA_VEHICLE per extra alive vehicle)
const HP_PER_ROUND := 0.1  ## per round after round 4 (rigs grow faster than the hive's hp curve, so bosses scale gently)
const HP_PER_EXTRA_VEHICLE := 0.8
const PHASE2_FRAC := 0.66
const PHASE3_FRAC := 0.33
const SPLIT_COUNT := 3
const SPLIT_HP_FRAC := 1.0 / 6.0  ## each shard has this share of the boss's full hp
const ENRAGE_SPEED := 1.25
const ENRAGE_COOLDOWN := 0.7
const BOSS_SPAWN_FACTOR := 0.5  ## regular spawns while a boss is warned / active
const EMP_SLOW_MAX := 45  ## ticks: bosses only get slowed by an EMP

const RAM_DAMAGE_FACTOR := 0.3  ## a ram does this share of its damage to a boss ...
const RAM_RECOIL := 1.2  ## ... and costs the rammer this much extra per tick of contact (x enemy_damage_mult)

const BOUNTY_BASE := 25
const BOUNTY_PER_ROUND := 6
const BOUNTY_KILLER_MULT := 2.0
const BOUNTY_MIN_SHARE := 0.10  ## a vehicle needs this share of the boss's hp dealt to earn a bounty

# Tripod
const SHELL_TICKS := 36  ## 1.2 s telegraph
const SHELL_RADIUS := 56.0
const SHELL_DAMAGE := 26.0  ## x enemy_damage_mult
const SHELL_RANGE := 900.0
const SHELL_JITTER := 36.0
const VOLLEY_TICKS := 160
const VOLLEY_TICKS_P3 := 110
const BROOD_TICKS := 130
const BROOD_PACK := 4
const BROOD_MAX_MITES := 120
const TRIPOD_STANDOFF_MIN := 170.0
const TRIPOD_STANDOFF_MAX := 290.0
const TRIPOD_ENTRY_DIST := 480.0
const TRIPOD_HP_MULT := 0.8  ## relative to HP_BASE (she is the harder one to reach)
const COLOSSUS_HP_MULT := 1.1
const TRIPOD_ENTRY_SPEED := 2.4
const TRIPOD_P3_SPEED := 1.4

# Colossus
const RING_WINDUP := 30  ## 1 s glow
const RING_WINDUP_SHARD := 20
const RING_TICKS := 140
const RING_TICKS_SHARD := 170
const RING_COUNT := 14
const RING_COUNT_P2 := 18
const RING_COUNT_SHARD := 7
const RING_SPEED := 95.0
const RING_TTL := 4.5
const RING_DAMAGE := 9.0  ## x enemy_damage_mult
const CHARGE_WINDUP := 30
const CHARGE_TICKS := 22
const CHARGE_SPEED := 380.0
const CHARGE_RECOVER := 24
const CHARGE_CD := 210
const CHARGE_RANGE := 620.0
const CHARGE_IMPACT := 30.0  ## x enemy_damage_mult, once per charge
const COLOSSUS_P2_SPEED := 1.2

const M_WALK := 0
const M_RING := 1
const M_WINDUP := 2
const M_CHARGE := 3
const M_RECOVER := 4


# ---------------------------------------------------------------- schedule (pure)

static func first_for_seed(seed_value: int) -> int:
	var h: int = posmod(seed_value * 1103515245 + 12345, 2147483648)
	return (h >> 16) & 1


static func is_boss_round(r: int) -> bool:
	return r >= FIRST_ROUND and r % EVERY == 0


## Enemy kind of the boss of round `r` (BOSS_A / BOSS_B), -1 when it is not a boss round.
static func kind_for_round(first: int, r: int) -> int:
	if not is_boss_round(r):
		return -1
	return SimWorld.BOSS_A + ((first + r / EVERY - 1) % 2)


static func enraged_in(r: int) -> bool:
	return r >= ENRAGE_ROUND


static func boss_name(kind: int) -> String:
	return str(NAMES.get(kind, "BOSS"))


## The next boss the players will meet: {"round", "kind", "enraged", "name"}. In a workshop (or any phase but
## combat) the round about to start counts; during combat only later rounds do. The workshop shows
## "NEXT BOSS IN ROUND n: name" from this.
static func next_boss(w: SimWorld) -> Dictionary:
	var r: int = w.round if w.phase != SimWorld.PHASE_WORKSHOP else w.round + 1
	if w.phase == SimWorld.PHASE_COMBAT:
		r = w.round + 1
	while not is_boss_round(r):
		r += 1
	var k: int = kind_for_round(w.boss_first, r)
	return {"round": r, "kind": k, "enraged": enraged_in(r), "name": boss_name(k)}


static func max_hp_for(r: int, vehicles_alive: int, kind: int = -1) -> float:
	var km: float = TRIPOD_HP_MULT if kind == SimWorld.BOSS_A else (COLOSSUS_HP_MULT if kind == SimWorld.BOSS_B else 1.0)
	return HP_BASE * km * (1.0 + HP_PER_ROUND * float(maxi(r - FIRST_ROUND, 0))) * (1.0 + HP_PER_EXTRA_VEHICLE * float(maxi(vehicles_alive - 1, 0)))


static func speed_of(w: SimWorld, kind: int, phase: int) -> float:
	var s: float = SimWorld.ENEMY_SPEED[kind]
	if kind == SimWorld.BOSS_A and phase >= 3:
		s *= TRIPOD_P3_SPEED
	elif kind != SimWorld.BOSS_A and phase >= 2:
		s *= COLOSSUS_P2_SPEED
	if w.boss_enraged:
		s *= ENRAGE_SPEED
	return s


static func _cd(w: SimWorld, ticks: int) -> int:
	return roundi(float(ticks) * (ENRAGE_COOLDOWN if w.boss_enraged else 1.0))


static func is_boss_kind(kind: int) -> bool:
	return kind >= SimWorld.BOSS_A


## True while a boss is warned or fighting (regular spawns thin out, workshop / HUD show the bar).
static func engaged(w: SimWorld) -> bool:
	return w.boss_state == ST_WARNED or w.boss_state == ST_ACTIVE


# ---------------------------------------------------------------- per-tick update

## Called once per combat tick, before the enemies move.
static func tick(w: SimWorld) -> void:
	if w.boss_round != w.round:
		_reset_round(w)
	if w.boss_kind < 0 or not (w.spawning_enabled or w.boss_forced):
		return
	var dur: int = w.combat_duration(w.round)
	var ticks_in: int = dur - w.phase_ticks_left
	var start: int = SimWorld.surge_starts(dur)[0]
	match w.boss_state:
		ST_NONE:
			if ticks_in >= start - WARN_TICKS:
				w.boss_state = ST_WARNED
				w.boss_spawn_pos = _spawn_point(w)
				w._emit("boss", w.boss_spawn_pos, -1, w.boss_kind, {"in_ticks": maxi(start - ticks_in, 0), "enraged": 1 if w.boss_enraged else 0})
		ST_WARNED:
			if ticks_in >= start:
				_spawn(w)
		ST_ACTIVE:
			_update_active(w)
	if w.boss_state != ST_ACTIVE and w.boss_state != ST_WARNED:
		w.boss_warn_left = 0
	elif w.boss_state == ST_WARNED:
		w.boss_warn_left = maxi(start - ticks_in, 0)
	else:
		w.boss_warn_left = 0


static func _reset_round(w: SimWorld) -> void:
	w.boss_round = w.round
	w.boss_kind = kind_for_round(w.boss_first, w.round)
	w.boss_enraged = enraged_in(w.round) and w.boss_kind >= 0
	w.boss_state = ST_NONE
	w.boss_phase = 0
	w.boss_max_hp = 0.0
	w.boss_hp_frac = 0.0
	w.boss_warn_left = 0
	w.boss_dealt.clear()
	w.boss_ents.clear()
	w.boss_marks.clear()
	w.boss_dmg_taken = 0.0
	w.boss_ticks = 0


## Clears the transient fight state (the field was cleared: marks and entity states are meaningless).
static func clear_field(w: SimWorld) -> void:
	w.boss_marks.clear()
	w.boss_ents.clear()


## The round ends with the boss alive: it retreats (no penalty). Called before the field is cleared.
static func end_round(w: SimWorld) -> void:
	if w.boss_state == ST_ACTIVE or w.boss_state == ST_WARNED:
		var at: Vector2 = w.boss_spawn_pos
		for i in w.enemy_count:
			if w.enemy_kind[i] >= SimWorld.BOSS_A and w.enemy_hp[i] > 0.0:
				at = w.enemy_pos[i]
				break
		if w.boss_state == ST_ACTIVE:
			_log(w, "retreat", -1)
			w._emit("boss_retreat", at, -1, w.boss_kind)
		w.boss_state = ST_RETREATED
	w.boss_marks.clear()
	w.boss_ents.clear()


static func _spawn_point(w: SimWorld) -> Vector2:
	var sum := Vector2.ZERO
	var n: int = 0
	for v in w.vehicles:
		if v.alive:
			sum += v.pos
			n += 1
	var c: Vector2 = sum / float(n) if n > 0 else SimWorld.ARENA.get_center()
	var a: Rect2 = SimWorld.ARENA
	var inset: float = 44.0
	var dists: Array[float] = [c.y - a.position.y, a.end.y - c.y, c.x - a.position.x, a.end.x - c.x]  # top, bottom, left, right
	var side: int = 0
	for k in range(1, 4):
		if dists[k] < dists[side]:
			side = k
	var along_x: float = clampf(c.x, a.position.x + 140.0, a.end.x - 140.0)
	var along_y: float = clampf(c.y, a.position.y + 140.0, a.end.y - 140.0)
	match side:
		0:
			return Vector2(along_x, a.position.y + inset)
		1:
			return Vector2(along_x, a.end.y - inset)
		2:
			return Vector2(a.position.x + inset, along_y)
	return Vector2(a.end.x - inset, along_y)


static func _spawn(w: SimWorld) -> void:
	var alive: int = 0
	for v in w.vehicles:
		if v.alive and not v.eliminated:
			alive += 1
	w.boss_max_hp = max_hp_for(w.round, maxi(alive, 1), w.boss_kind)
	var id: int = w.spawn_enemy(w.boss_kind, w.boss_spawn_pos)
	if id < 0:
		return
	var idx: int = w.enemy_count - 1
	w.enemy_hp[idx] = w.boss_max_hp
	w.boss_ents[id] = _new_ent(w, w.boss_kind, 1)
	w.boss_state = ST_ACTIVE
	w.boss_phase = 1
	w.boss_hp_frac = 1.0
	w.boss_ticks = 0
	_log(w, "spawn", -1)
	w._emit("boss_spawn", w.boss_spawn_pos, -1, w.boss_kind, {})


static func _new_ent(w: SimWorld, kind: int, phase: int) -> Dictionary:
	var e := {"mode": M_WALK, "t": 0, "cd": 60, "cd2": 90, "dir": Vector2.ZERO, "brood": BROOD_TICKS, "ring": 0, "hit": false}
	if kind == SimWorld.BOSS_B or kind == SimWorld.BOSS_SHARD:
		e["cd"] = _cd(w, RING_TICKS) + (w.rng.randi() % 40 if kind == SimWorld.BOSS_SHARD else 0)
		e["cd2"] = 90
	if kind == SimWorld.BOSS_A:
		e["cd"] = 90
	return e


static func _update_active(w: SimWorld) -> void:
	w.boss_ticks += 1
	# index every living boss entity, drop states of dead ones
	var idx_of: Dictionary = {}
	var total: float = 0.0
	var main_hp: float = -1.0
	for i in w.enemy_count:
		var k: int = w.enemy_kind[i]
		if k >= SimWorld.BOSS_A and w.enemy_hp[i] > 0.0:
			idx_of[w.enemy_id[i]] = i
			total += w.enemy_hp[i]
			if k != SimWorld.BOSS_SHARD:
				main_hp = w.enemy_hp[i]
	for id in w.boss_ents.keys():
		if not idx_of.has(id):
			w.boss_ents.erase(id)
	w.boss_hp_frac = clampf(total / maxf(w.boss_max_hp, 1.0), 0.0, 1.0)
	if idx_of.is_empty():
		return  # killed (handled in on_death) or cleared
	# phases follow the main body's hp (after a Colossus split there is no main body: phase 3 stays)
	if main_hp >= 0.0:
		var f: float = main_hp / maxf(w.boss_max_hp, 1.0)
		var want: int = 1
		if f <= PHASE3_FRAC:
			want = 3
		elif f <= PHASE2_FRAC:
			want = 2
		if want > w.boss_phase:
			w.boss_phase = want
			var mi: int = _main_index(w)
			w._emit("boss_phase", w.enemy_pos[mi] if mi >= 0 else w.boss_spawn_pos, -1, want, {})
			_log(w, "phase%d" % want, -1)
			if want == 3 and w.boss_kind == SimWorld.BOSS_B and mi >= 0:
				_split(w, mi)
				return
	# alive targets, nearest first per boss entity
	var ids: Array = idx_of.keys()
	ids.sort()
	for id in ids:
		var i2: int = int(idx_of[id])
		if w.enemy_hp[i2] <= 0.0:
			continue
		var st: Dictionary = w.boss_ents.get(id, {})
		if st.is_empty():
			st = _new_ent(w, w.enemy_kind[i2], w.boss_phase)
			w.boss_ents[id] = st
		match w.enemy_kind[i2]:
			SimWorld.BOSS_A:
				_tripod(w, i2, st)
			_:
				_colossus(w, i2, st)
	_update_marks(w)


static func _main_index(w: SimWorld) -> int:
	for i in w.enemy_count:
		var k: int = w.enemy_kind[i]
		if k >= SimWorld.BOSS_A and k != SimWorld.BOSS_SHARD and w.enemy_hp[i] > 0.0:
			return i
	return -1


## Nearest living vehicle to `p` (index into w.vehicles), -1 when none.
static func nearest_vehicle(w: SimWorld, p: Vector2) -> int:
	var best: int = -1
	var best_d2: float = INF
	for vi in w.vehicles.size():
		var v: SimVehicle = w.vehicles[vi]
		if not v.alive:
			continue
		var d2: float = p.distance_squared_to(v.pos)
		if d2 < best_d2:
			best_d2 = d2
			best = vi
	return best


# ---------------------------------------------------------------- Tripod Queen

static func _tripod(w: SimWorld, i: int, st: Dictionary) -> void:
	var p: Vector2 = w.enemy_pos[i]
	var phase: int = w.boss_phase
	st["cd"] = int(st["cd"]) - 1
	if int(st["cd"]) <= 0:
		var near: int = nearest_vehicle(w, p)
		if near >= 0 and p.distance_to(w.vehicles[near].pos) <= SHELL_RANGE:
			_volley(w, p, 3 if phase >= 3 else 1)
			st["cd"] = _cd(w, VOLLEY_TICKS_P3 if phase >= 3 else VOLLEY_TICKS)
		else:
			st["cd"] = 20
	if phase >= 2:
		st["brood"] = int(st["brood"]) - 1
		if int(st["brood"]) <= 0:
			st["brood"] = _cd(w, BROOD_TICKS)
			_brood(w, p)


## Lobs `n` shells at the predicted positions of the nearest vehicles (cycling when there are fewer).
static func _volley(w: SimWorld, from: Vector2, n: int) -> void:
	var order: Array[int] = []
	for vi in w.vehicles.size():
		if w.vehicles[vi].alive:
			order.append(vi)
	if order.is_empty():
		return
	order.sort_custom(func(a: int, b: int) -> bool:
		return from.distance_squared_to(w.vehicles[a].pos) < from.distance_squared_to(w.vehicles[b].pos))
	var lead: float = float(SHELL_TICKS) * SimWorld.DT
	for k in n:
		var v: SimVehicle = w.vehicles[order[k % order.size()]]
		var at: Vector2 = v.pos + v.vel * lead
		if k > 0:  # follow-up shells scatter so a lone rig is bracketed, not hit three times
			var ang: float = w.rng.randf() * TAU
			at += Vector2.from_angle(ang) * (SHELL_JITTER + w.rng.randf() * SHELL_JITTER * 1.5)
		else:
			at += Vector2.from_angle(w.rng.randf() * TAU) * w.rng.randf() * SHELL_JITTER
		at = Vector2(clampf(at.x, 4.0, SimWorld.ARENA.end.x - 4.0), clampf(at.y, 4.0, SimWorld.ARENA.end.y - 4.0))
		w.boss_marks.append({"k": MARK_SHELL, "pos": at, "pos2": Vector2.ZERO, "r": SHELL_RADIUS, "left": SHELL_TICKS, "total": SHELL_TICKS})
	w._emit("boss_shell", from, -1, n)


static func _brood(w: SimWorld, p: Vector2) -> void:
	var mites: int = 0
	for j in w.enemy_count:
		if w.enemy_kind[j] == SimWorld.MITE:
			mites += 1
	if mites >= BROOD_MAX_MITES:
		return
	for k in BROOD_PACK + (w.round / 8):
		var ang: float = w.rng.randf() * TAU
		var q: Vector2 = p + Vector2.from_angle(ang) * (SimWorld.ENEMY_RADIUS[SimWorld.BOSS_A] + 6.0 + w.rng.randf() * 10.0)
		w.spawn_enemy(SimWorld.MITE, Vector2(clampf(q.x, 8.0, SimWorld.ARENA.end.x - 8.0), clampf(q.y, 8.0, SimWorld.ARENA.end.y - 8.0)))
	w._emit("boss_brood", p, -1, SimWorld.BOSS_A)


# ---------------------------------------------------------------- Shard Colossus (and its shards)

static func _colossus(w: SimWorld, i: int, st: Dictionary) -> void:
	var p: Vector2 = w.enemy_pos[i]
	var kind: int = w.enemy_kind[i]
	var mini_boss: bool = kind == SimWorld.BOSS_SHARD
	var phase: int = w.boss_phase
	var mode: int = int(st["mode"])
	var t: int = int(st["t"])
	var near: int = nearest_vehicle(w, p)
	match mode:
		M_WALK:
			st["cd"] = int(st["cd"]) - 1
			st["cd2"] = int(st["cd2"]) - 1
			if int(st["cd"]) <= 0 and near >= 0:
				st["mode"] = M_RING
				st["t"] = RING_WINDUP_SHARD if mini_boss else RING_WINDUP
				var rr: float = SimWorld.ENEMY_RADIUS[kind] + 8.0
				w.boss_marks.append({"k": MARK_RING, "pos": p, "pos2": Vector2.ZERO, "r": rr, "left": int(st["t"]), "total": int(st["t"]), "id": w.enemy_id[i]})
			elif phase >= 2 and not mini_boss and int(st["cd2"]) <= 0 and near >= 0 and p.distance_to(w.vehicles[near].pos) <= CHARGE_RANGE:
				var dir: Vector2 = (w.vehicles[near].pos - p).normalized()
				st["mode"] = M_WINDUP
				st["t"] = CHARGE_WINDUP
				st["dir"] = dir
				st["hit"] = false
				var end: Vector2 = p + dir * (CHARGE_SPEED * float(CHARGE_TICKS) * SimWorld.DT)
				w.boss_marks.append({"k": MARK_CHARGE, "pos": p, "pos2": end, "r": SimWorld.ENEMY_RADIUS[kind], "left": CHARGE_WINDUP, "total": CHARGE_WINDUP, "id": w.enemy_id[i]})
				w._emit("boss_charge", p, -1, kind)
		M_RING:
			st["t"] = t - 1
			if t - 1 <= 0:
				_release_ring(w, i, st)
				st["mode"] = M_WALK
				st["cd"] = _cd(w, RING_TICKS_SHARD if mini_boss else RING_TICKS)
		M_WINDUP:
			st["t"] = t - 1
			if t - 1 <= 0:
				st["mode"] = M_CHARGE
				st["t"] = CHARGE_TICKS
		M_CHARGE:
			st["t"] = t - 1
			if t - 1 <= 0:
				_end_charge(w, st)
		M_RECOVER:
			st["t"] = t - 1
			if t - 1 <= 0:
				st["mode"] = M_WALK


static func _end_charge(w: SimWorld, st: Dictionary) -> void:
	st["mode"] = M_RECOVER
	st["t"] = CHARGE_RECOVER
	st["cd2"] = _cd(w, CHARGE_CD)


static func _release_ring(w: SimWorld, i: int, st: Dictionary) -> void:
	var kind: int = w.enemy_kind[i]
	var n: int = RING_COUNT_SHARD if kind == SimWorld.BOSS_SHARD else (RING_COUNT_P2 if w.boss_phase >= 2 else RING_COUNT)
	var p: Vector2 = w.enemy_pos[i]
	st["ring"] = int(st["ring"]) + 1
	var a0: float = TAU * 0.5 / float(n) * float(int(st["ring"]) % 2)  # alternate rings offset by half a gap
	var dmg: float = RING_DAMAGE * SimWorld.enemy_damage_mult(w.round)
	for k in n:
		var dir: Vector2 = Vector2.from_angle(a0 + TAU * float(k) / float(n))
		w.spawn_projectile(p + dir * (SimWorld.ENEMY_RADIUS[kind] + 4.0), dir * RING_SPEED, RING_TTL, dmg, -1)
	w._emit("boss_ring", p, -1, n)


## Markers count down; shells detonate.
static func _update_marks(w: SimWorld) -> void:
	var keep: Array[Dictionary] = []
	for m in w.boss_marks:
		m["left"] = int(m["left"]) - 1
		if m["k"] == MARK_RING or m["k"] == MARK_CHARGE:  # follow the boss while it winds up
			var id: int = int(m.get("id", -1))
			var found: bool = false
			for j in w.enemy_count:
				if w.enemy_id[j] == id and w.enemy_hp[j] > 0.0:
					found = true
					if m["k"] == MARK_RING:
						m["pos"] = w.enemy_pos[j]
					break
			if not found:
				continue
		if int(m["left"]) <= 0:
			if m["k"] == MARK_SHELL:
				_detonate(w, m)
			continue
		keep.append(m)
	w.boss_marks = keep


static func _detonate(w: SimWorld, m: Dictionary) -> void:
	var at: Vector2 = m["pos"]
	var r: float = float(m["r"])
	var dmg: float = SHELL_DAMAGE * SimWorld.enemy_damage_mult(w.round)
	for v in w.vehicles:
		if v.alive and v.pos.distance_to(at) <= r + SimVehicle.RADIUS * 0.5:
			w.boss_dmg_taken += minf(dmg, v.hp)
			w._damage_vehicle(v, dmg, -1, true, SimWorld.SRC_BOSS)
	w._emit("boss_blast", at, -1, roundi(r))


# ---------------------------------------------------------------- split (Colossus phase 3)

static func _split(w: SimWorld, mi: int) -> void:
	var at: Vector2 = w.enemy_pos[mi]
	w.enemy_hp[mi] = 0.0  # the body is gone silently (compacted at the end of the tick)
	var hp: float = w.boss_max_hp * SPLIT_HP_FRAC
	for k in SPLIT_COUNT:
		var ang: float = TAU * float(k) / float(SPLIT_COUNT) + w.rng.randf() * 0.5
		var q: Vector2 = at + Vector2.from_angle(ang) * 38.0
		q = Vector2(clampf(q.x, 24.0, SimWorld.ARENA.end.x - 24.0), clampf(q.y, 24.0, SimWorld.ARENA.end.y - 24.0))
		var id: int = w.spawn_enemy(SimWorld.BOSS_SHARD, q)
		if id < 0:
			continue
		w.enemy_hp[w.enemy_count - 1] = hp
		w.enemy_vel[w.enemy_count - 1] = Vector2.from_angle(ang) * 120.0
		w.boss_ents[id] = _new_ent(w, SimWorld.BOSS_SHARD, 3)
	w.boss_marks.clear()
	w._emit("boss_split", at, -1, SPLIT_COUNT)


# ---------------------------------------------------------------- movement hooks (called by SimWorld._update_enemies)

## Desired velocity of boss entity `i` (kind >= BOSS_A) at `p`, chasing `tp`.
static func move_desire(w: SimWorld, i: int, kind: int, p: Vector2, tp: Vector2) -> Vector2:
	var st: Dictionary = w.boss_ents.get(w.enemy_id[i], {})
	var to_t: Vector2 = tp - p
	var d: float = to_t.length()
	if d < 0.001:
		return Vector2.ZERO
	var u: Vector2 = to_t / d
	var spd: float = speed_of(w, kind, w.boss_phase)
	if kind == SimWorld.BOSS_A:
		var tang := Vector2(-u.y, u.x)
		if d > TRIPOD_ENTRY_DIST:
			return u * spd * TRIPOD_ENTRY_SPEED
		if d > TRIPOD_STANDOFF_MAX:
			return u * spd
		if d < TRIPOD_STANDOFF_MIN:
			return (-u + tang * 0.5).normalized() * spd * 0.8
		return tang * spd * 0.35
	var mode: int = int(st.get("mode", M_WALK))
	if mode != M_WALK:
		return Vector2.ZERO
	return u * spd


## Velocity to force while the boss entity with stable id `id` is charging (zero vector otherwise).
static func charge_velocity(w: SimWorld, id: int) -> Vector2:
	if w.boss_ents.is_empty():
		return Vector2.ZERO
	var st: Dictionary = w.boss_ents.get(id, {})
	if not st.is_empty() and int(st["mode"]) == M_CHARGE:
		return (st["dir"] as Vector2) * CHARGE_SPEED
	return Vector2.ZERO


## A boss entity touched vehicle `vidx`: a charge lands its impact once and ends.
static func on_contact(w: SimWorld, i: int, vidx: int) -> void:
	var st: Dictionary = w.boss_ents.get(w.enemy_id[i], {})
	if st.is_empty() or int(st["mode"]) != M_CHARGE or bool(st["hit"]):
		return
	st["hit"] = true
	var dmg: float = CHARGE_IMPACT * SimWorld.enemy_damage_mult(w.round)
	w.boss_dmg_taken += minf(dmg, w.vehicles[vidx].hp)
	w._damage_vehicle(w.vehicles[vidx], dmg, -1, true, SimWorld.SRC_BOSS)
	_end_charge(w, st)


## EMP and other stuns: a boss only slows (SimWorld.stun_enemy calls this for boss kinds).
static func stun_to_slow(ticks: int) -> int:
	return mini(ticks, EMP_SLOW_MAX)


# ---------------------------------------------------------------- damage and death hooks

## `applied` damage from vehicle `killer` hit boss entity `j`.
static func on_damage(w: SimWorld, killer: int, applied: float) -> void:
	if killer >= 0 and applied > 0.0:
		w.boss_dealt[killer] = float(w.boss_dealt.get(killer, 0.0)) + applied


## Boss entity `j` just reached 0 hp (killed by vehicle `killer`, -1 = burn / other). When it was the last one
## the boss is dead: bounties, event and the killer's guaranteed rare draft.
static func on_death(w: SimWorld, j: int, killer: int) -> void:
	if w.boss_state != ST_ACTIVE:
		return
	for i in w.enemy_count:
		if i != j and w.enemy_kind[i] >= SimWorld.BOSS_A and w.enemy_hp[i] > 0.0:
			return  # others left (Colossus shards)
	w.boss_state = ST_KILLED
	w.boss_hp_frac = 0.0
	w.boss_marks.clear()
	var bounty: int = BOUNTY_BASE + BOUNTY_PER_ROUND * w.round
	for vi in w.vehicles.size():
		var v: SimVehicle = w.vehicles[vi]
		var dealt: float = float(w.boss_dealt.get(vi, 0.0))
		var is_killer: bool = vi == killer
		if dealt < BOUNTY_MIN_SHARE * w.boss_max_hp and not is_killer:
			continue
		var pay: int = roundi(float(bounty) * (BOUNTY_KILLER_MULT if is_killer else 1.0) * v.scrap_mult)
		v.scrap += pay
		w._note_scrap(v, pay)
		v.round_stats["boss_bounty"] = int(v.round_stats.get("boss_bounty", 0)) + pay
		if is_killer:
			v.bonus_offers += 1
			v.boss_rare = true
	_log(w, "kill", killer)
	w._emit("boss_kill", w.enemy_pos[j], killer, w.boss_kind)


## Appends to the host-side diagnostic log (bot league report): one row per boss event.
static func _log(w: SimWorld, what: String, killer: int) -> void:
	w.boss_log.append({"round": w.round, "kind": w.boss_kind, "what": what, "tick": w.boss_ticks, "hp": w.boss_hp_frac, "killer": killer,
		"taken": w.boss_dmg_taken, "dealt": w.boss_dealt.duplicate(), "alive": _alive_count(w), "phase": w.boss_phase})


static func _alive_count(w: SimWorld) -> int:
	var n: int = 0
	for v in w.vehicles:
		if v.alive:
			n += 1
	return n
