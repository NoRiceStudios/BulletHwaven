class_name Species
extends RefCounted
## The three "hive signature" species (design doc 7a / 7c, architecture "Species and the hive signature"):
## Glass Wings (flyers), Brood Carriers (burst into mites) and Shriekers (buff pulse). Static and pure: the
## state lives in the SimWorld enemy arrays (kinds SimWorld.GLASS / BROOD / SHRIEKER) plus `hive_first` and
## the host-only `brood_pending`. Hooks in SimWorld: spawn (`roll` / `spawn_event`), movement (`glass_desire`,
## `shrieker_desire`), contact rules (`glass_diving`), death (`on_brood_death`), `tick` (brood mites, shriek
## pulses). Glass Wings and Shriekers keep no per-enemy state: their cycle is a pure function of (tick, id).

const COUNT := 3
const NAMES: PackedStringArray = ["GLASS WINGS", "BROOD CARRIER", "SHRIEKER"]
const SHORT: PackedStringArray = ["FLYERS", "MITE BURSTS", "BUFF PULSE"]

## Hive signature: how many of the three are active in a match, and the window of their first round.
const ACTIVE_COUNT := 2
const FIRST_MIN := 3
const FIRST_MAX := 7

# --- Glass Wings
const GLASS_PERIOD := 150  ## ticks per flight cycle (5 s)
const GLASS_DIVE_START := 100  ## cycle tick the dive starts at (before it: loose circling, after the dive: pull away)
const GLASS_DIVE_END := 132
const GLASS_FLOCK := 4  ## ids per flock (they share a cycle phase, offset a few ticks)
const GLASS_RING := 135.0  ## circling radius around the target
const GLASS_CIRCLE_SPEED := 105.0
const GLASS_AWAY_SPEED := 165.0
const GLASS_FLOCK_MIN := 3
const GLASS_FLOCK_MAX := 5

# --- Brood Carrier
const BROOD_MITES_MIN := 6
const BROOD_MITES_MAX := 8
const BROOD_DELAY := 6  ## ticks between the burst frame and the mites (render shows the burst)
const BROOD_SPREAD := 16.0

# --- Shrieker
const SHRIEK_PERIOD := 150  ## ticks between pulses (5 s), staggered by id
const SHRIEK_RADIUS := 90.0
const SHRIEK_HEAL := 0.2  ## of max hp
const SHRIEK_HASTE_TICKS := 90  ## status bits 24..30 of enemy_status
const HASTE_SHIFT := 24
const HASTE_MULT := 1.35
const SHRIEK_WINDUP := 14  ## ticks before the pulse the pipes light up
const SHRIEKER_KEEP_MIN := 250.0
const SHRIEKER_KEEP_MAX := 320.0
const SHRIEKER_NEAR := 360.0  ## doctrine condition "shrieker near": a living shrieker within this of the rig


# ---------------------------------------------------------------- hive signature

## First round of each species in a match of `seed` (index = kind - SimWorld.GLASS; 0 = not in this match).
## Exactly ACTIVE_COUNT of the three are drawn, each with its own first round in FIRST_MIN..FIRST_MAX. Pure in
## `seed` and uses its own generator, so world.rng is untouched.
static func signature(seed: int) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed * 6364136223846793005 + 1442695040888963407) & 0x7fffffffffffffff
	var out := PackedInt32Array([0, 0, 0])
	var skip: int = rng.randi() % COUNT
	for i in COUNT:
		var first: int = rng.randi_range(FIRST_MIN, FIRST_MAX)
		if i != skip:
			out[i] = first
	return out


static func is_active(w: SimWorld, kind: int, r: int) -> bool:
	var i: int = kind - SimWorld.GLASS
	return i >= 0 and i < COUNT and w.hive_first[i] > 0 and r >= w.hive_first[i]


static func any_active(w: SimWorld, r: int) -> bool:
	for i in COUNT:
		if w.hive_first[i] > 0 and r >= w.hive_first[i]:
			return true
	return false


## The signature as a list of {"kind", "name", "first"} for the species in this match, earliest first.
static func list(w: SimWorld) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in COUNT:
		if w.hive_first[i] > 0:
			out.append({"kind": SimWorld.GLASS + i, "name": NAMES[i], "short": SHORT[i], "first": w.hive_first[i]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["first"]) < int(b["first"]))
	return out


# ---------------------------------------------------------------- spawning

## Share of spawn events that bring this species in round `r` (`first` = its first round).
static func chance(i: int, r: int, first: int) -> float:
	var n: float = float(maxi(r - first, 0))
	match i:
		0:
			return minf(0.07 + 0.015 * n, 0.17)
		1:
			return minf(0.05 + 0.012 * n, 0.12)
	return minf(0.05 + 0.01 * n, 0.10)


## Most of the species alive at once.
static func cap(i: int, r: int, first: int) -> int:
	var n: int = maxi(r - first, 0)
	match i:
		0:
			return mini(4 + 2 * n, 14)
		1:
			return mini(2 + n, 8)
	return mini(2 + n / 2, 5)


static func flock_size(r: int) -> int:
	return clampi(GLASS_FLOCK_MIN + r / 6, GLASS_FLOCK_MIN, GLASS_FLOCK_MAX)


## Living enemies of the three kinds.
static func count_alive(w: SimWorld) -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0])
	for j in w.enemy_count:
		var k: int = w.enemy_kind[j] - SimWorld.GLASS
		if k >= 0 and k < COUNT and w.enemy_hp[j] > 0.0:
			out[k] += 1
	return out


## One roll per mite spawn event: returns the species kind to spawn instead of the pack, or -1. Draws from
## world.rng only for species that are active and below their cap. `counts` is updated by spawn_event().
static func roll(w: SimWorld, counts: PackedInt32Array) -> int:
	var r: int = w.round
	for i in COUNT:
		var first: int = w.hive_first[i]
		if first <= 0 or r < first or counts[i] >= cap(i, r, first):
			continue
		if w.rng.randf() < chance(i, r, first):
			return SimWorld.GLASS + i
	return -1


## Spawns the species `kind` at edge point `at` (a glass flock clusters around it, clamped to lo..hi).
static func spawn_event(w: SimWorld, kind: int, at: Vector2, lo: Vector2, hi: Vector2, counts: PackedInt32Array) -> void:
	if kind == SimWorld.GLASS:
		var n: int = flock_size(w.round)
		for k in n:
			var ang: float = w.rng.randf() * TAU
			var rad: float = sqrt(w.rng.randf()) * 30.0
			var p: Vector2 = at + Vector2(cos(ang), sin(ang)) * rad
			w.spawn_enemy(kind, Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y)))
		counts[0] += n
	else:
		w.spawn_enemy(kind, at)
		counts[kind - SimWorld.GLASS] += 1


# ---------------------------------------------------------------- Glass Wings

## Cycle tick of glass wing `id` at `t`: flocks share a phase, members are a few ticks apart.
static func glass_phase(t: int, id: int) -> int:
	return (t + (id / GLASS_FLOCK) * 41 + (id % GLASS_FLOCK) * 5) % GLASS_PERIOD


## Is wing `id` diving at tick `t`? Only then does it touch (and hurt) a rig; the render uses it for the pose.
static func glass_diving(t: int, id: int) -> bool:
	var ph: int = glass_phase(t, id)
	return ph >= GLASS_DIVE_START and ph < GLASS_DIVE_END


## Desired velocity of a glass wing at `p` toward the target at `tp`: circle loosely around it, dive straight
## in, pull away.
static func glass_desire(t: int, id: int, p: Vector2, tp: Vector2) -> Vector2:
	var to: Vector2 = tp - p
	var d: float = maxf(to.length(), 0.001)
	var u: Vector2 = to / d
	var ph: int = glass_phase(t, id)
	if ph >= GLASS_DIVE_START and ph < GLASS_DIVE_END:
		return u * SimWorld.ENEMY_SPEED[SimWorld.GLASS]
	if ph >= GLASS_DIVE_END:
		var side: float = 1.0 if id % 2 == 0 else -1.0
		return (-u + Vector2(-u.y, u.x) * side * 0.5).normalized() * GLASS_AWAY_SPEED
	var tang: Vector2 = Vector2(-u.y, u.x) * (1.0 if id % 2 == 0 else -1.0)
	var k: float = clampf((d - GLASS_RING) / GLASS_RING * 2.0, -1.0, 1.0)
	return (tang * 0.8 + u * k).normalized() * GLASS_CIRCLE_SPEED


# ---------------------------------------------------------------- Shrieker

## Shrieker movement: hold SHRIEKER_KEEP_MIN..MAX from the nearest rig (`u` = unit vector to it, `d` =
## distance), backing away when closer, creeping in when farther, otherwise drifting sideways.
static func shrieker_desire(u: Vector2, d: float, id: int) -> Vector2:
	var side: float = 1.0 if id % 2 == 0 else -1.0
	var tang: Vector2 = Vector2(-u.y, u.x) * side
	var spd: float = SimWorld.ENEMY_SPEED[SimWorld.SHRIEKER]
	if d > SHRIEKER_KEEP_MAX:
		return u * spd
	if d < SHRIEKER_KEEP_MIN:
		return (-u + tang * 0.5).normalized() * spd
	return tang * (spd * 0.3)


## Ticks into the pulse cycle of shrieker `id`; the pulse fires at 0.
static func shriek_phase(t: int, id: int) -> int:
	return (t + id * 11) % SHRIEK_PERIOD


## True while the pipes light up (the SHRIEK_WINDUP ticks before the pulse and a few after). Pure in (tick, id).
static func shriek_charging(t: int, id: int) -> bool:
	var ph: int = shriek_phase(t, id)
	return ph >= SHRIEK_PERIOD - SHRIEK_WINDUP or ph < 6


## Runs every combat tick: shriek pulses and the mites of burst brood carriers.
static func tick(w: SimWorld) -> void:
	if not w.brood_pending.is_empty():
		_release_brood(w)
	if w.enemy_count == 0 or not is_active(w, SimWorld.SHRIEKER, w.round):
		return
	for i in w.enemy_count:
		if w.enemy_kind[i] == SimWorld.SHRIEKER and w.enemy_hp[i] > 0.0 and shriek_phase(w.tick, w.enemy_id[i]) == 0:
			_shriek(w, i)


static func _shriek(w: SimWorld, i: int) -> void:
	var at: Vector2 = w.enemy_pos[i]
	w._emit("shriek", at, -1, SimWorld.SHRIEKER)
	var n: int = w.query_enemies(at, SHRIEK_RADIUS, w.ai_buf)
	for q in n:
		var j: int = w.ai_buf[q]
		if j == i or w.enemy_hp[j] <= 0.0 or w.enemy_kind[j] >= SimWorld.BOSS_A:
			continue  # bosses are not buffed
		var mx: float = w.enemy_max_hp_of(j)
		w.enemy_hp[j] = minf(w.enemy_hp[j] + SHRIEK_HEAL * mx, mx)
		w._status_enemy(j, HASTE_SHIFT, SHRIEK_HASTE_TICKS)


## Haste ticks left on an enemy status word.
static func haste_of(status: int) -> int:
	return (status >> HASTE_SHIFT) & 127


# ---------------------------------------------------------------- Brood Carrier

## A brood carrier index `j` just died. Killed by fire, burn or splash the brood dies with it (event kind 0);
## otherwise its mites hatch BROOD_DELAY ticks later (event kind 1).
static func on_brood_death(w: SimWorld, j: int, killer: int, brood_dies: bool) -> void:
	var pos: Vector2 = w.enemy_pos[j]
	w._emit("brood", pos, killer, 0 if brood_dies else 1)
	if not brood_dies:
		var n: int = BROOD_MITES_MIN + w.enemy_id[j] % (BROOD_MITES_MAX - BROOD_MITES_MIN + 1)
		w.brood_pending.append([w.tick + BROOD_DELAY, pos, n])


static func _release_brood(w: SimWorld) -> void:
	var keep: Array = []
	for e: Array in w.brood_pending:
		if int(e[0]) > w.tick:
			keep.append(e)
			continue
		var pos: Vector2 = e[1]
		for k in int(e[2]):
			var ang: float = w.rng.randf() * TAU
			var rad: float = sqrt(w.rng.randf()) * BROOD_SPREAD
			var p: Vector2 = pos + Vector2(cos(ang), sin(ang)) * rad
			w.spawn_enemy(SimWorld.MITE, Vector2(clampf(p.x, SimWorld.ARENA.position.x, SimWorld.ARENA.end.x), clampf(p.y, SimWorld.ARENA.position.y, SimWorld.ARENA.end.y)))
	w.brood_pending = keep


# ---------------------------------------------------------------- doctrine

## Doctrine condition "shrieker_near": a living shrieker within SHRIEKER_NEAR of the rig.
static func shrieker_near(w: SimWorld, v: SimVehicle) -> bool:
	var n: int = w.query_enemies(v.pos, SHRIEKER_NEAR, w.ai_buf)
	for q in n:
		var j: int = w.ai_buf[q]
		if w.enemy_kind[j] == SimWorld.SHRIEKER and w.enemy_hp[j] > 0.0:
			return true
	return false
