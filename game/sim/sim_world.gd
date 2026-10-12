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
const SPLASH_FRACTION := 0.5  # splash damage as a fraction of the direct hit
const PVP_KILL_SCRAP := 15  # bounty for destroying another player's vehicle

# PvP rules (design doc 7j and 8): grace period and anti-snowball.
const PVP_START_ROUND := 4  # before this round vehicles never target, shoot or ram each other
const LEADER_BOUNTY_MULT := 3  # killing the leader pays PVP_KILL_SCRAP x this
const LEADER_SCRAP_DIVISOR := 10  # leader score = kills + scrap / this
const PVP_PROTECT_TICKS := 60  # 2 s of third-party protection after a player kill
const PVP_PROTECT_FACTOR := 0.5  # damage multiplier while protected
const RETALIATE_TICKS := 60  # return fire: a vehicle shoots back at a player that hurt it for 2 s (any doctrine)

const SPAWN_RATE_START := 1.5  # enemies / s
const SPAWN_RATE_RAMP := 0.5  # added every SPAWN_RAMP_INTERVAL seconds of the combat phase
const SPAWN_RAMP_INTERVAL := 10.0
const BOULDER_CHANCE := 0.1
const SPAWN_INSET := 8.0

# Spitters (ranged aliens that keep their distance and lob slow acid at vehicles).
const SPITTER_MIN_ROUND := 3
const SPITTER_CHANCE_START := 0.08  # of spawns in round SPITTER_MIN_ROUND (after the boulder roll)
const SPITTER_CHANCE_PER_ROUND := 0.03
const SPITTER_CHANCE_MAX := 0.25
const SPITTER_KEEP_MIN := 180.0  # backs away from its target closer than this
const SPITTER_KEEP_MAX := 230.0  # closes in on its target farther than this
const SPIT_PERIOD := 60  # ticks between shots per spitter (2 s), staggered by enemy id
const SPIT_RANGE := 260.0  # only fires at a vehicle within this distance
const SPIT_SPEED := 170.0  # px/s, slow enough to see coming
const SPIT_DAMAGE := 8.0  # x enemy_damage_mult(round), reduced by armour like any hit
const SPIT_INACCURACY := 0.08  # radians, uniform +-

# Round loop (docs/architecture.md, "Round loop contract").
const PHASE_COMBAT := 0
const PHASE_WORKSHOP := 1
const PHASE_GAME_OVER := 2

const COMBAT_TICKS := 1800  # 60 s
const COMBAT_TICKS_EARLY := 1200  # 40 s, rounds 1 and 2
const EARLY_ROUNDS := 2
const WORKSHOP_TICKS := 750  # 25 s
const FAST_COMBAT_TICKS := 120  # world.fast_rounds (tests, screenshots)
const FAST_WORKSHOP_TICKS := 45

const START_FUEL := 100
const FUEL_LOSS := 20  # destroyed by aliens
const FUEL_LOSS_PVP := 30  # destroyed by another player
const RESPAWN_TICKS := 90  # 3 s
const INTEREST_PER := 10  # +1 scrap per this much scrap held at the end of a round
const REROLL_COST_START := 6
const RETREAT_EVENT_CAP := 150  # at most this many "retreat" events per round end

# Per-round enemy scaling (round 1 = x1).
const HP_SCALE_PER_ROUND := 0.15
const SPAWN_SCALE_PER_ROUND := 0.11
const BOULDER_CHANCE_PER_ROUND := 0.025
const BOULDER_CHANCE_MAX := 0.4
const DAMAGE_SCALE_PER_ROUND := 0.03

# Armour: flat reduction per hit with a floor; per touching enemy per tick it counts for much less.
const ARMOR_MIN_FRACTION := 0.25
const CONTACT_ARMOR_FACTOR := 0.08

const SPAWN_SPOT_CLEARANCE := 90.0  # no vehicle closer than this to a respawn spot
const SPAWN_SPOT_ENEMY_CLEARANCE := 70.0

const HASH_CELL := 32.0
const STALE_MARGIN := 10.0  # enemies move < this per tick, hash is one move old
const MAX_SEPARATION_NEIGHBORS := 6

var tick: int = 0
var seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var vehicles: Array[SimVehicle] = []

# Round loop state.
var phase: int = PHASE_COMBAT
@warning_ignore("shadowed_global_identifier")
var round: int = 1
var phase_ticks_left: int = COMBAT_TICKS_EARLY
var winner_peer: int = -1  ## peer id of the winner once phase == PHASE_GAME_OVER (-1 = none / solo loss)
## Peer id of the marked leader (bounty target), -1 = nobody. See update_leader().
var leader_peer: int = -1
## Shortens combat and workshop (tests, screenshots). Set it right after construction: at tick 0 it
## also resets the running combat timer.
var fast_rounds: bool = false:
	set(value):
		fast_rounds = value
		if tick == 0 and phase == PHASE_COMBAT and round == 1:
			phase_ticks_left = combat_duration(1)

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
var proj_pierce: PackedByteArray = PackedByteArray()  # extra enemies the projectile may pass through
var proj_splash: PackedFloat32Array = PackedFloat32Array()  # splash radius on enemy hit, 0 = none
var proj_last: PackedInt32Array = PackedInt32Array()  # id of the last enemy pierced (not hit twice), -1 = none

var events: Array[Dictionary] = []

## Set false to stop the timed enemy spawner (tests, scenarios).
var spawning_enabled: bool = true
var next_enemy_id: int = 0

## Shared scratch buffer for VehicleAI queries.
var ai_buf: PackedInt32Array = PackedInt32Array()

var _hash: SpatialHash
var _spawn_accum: float = 0.0
var _query_buf: PackedInt32Array = PackedInt32Array()
var _splash_buf: PackedInt32Array = PackedInt32Array()
var _av_pos: PackedVector2Array = PackedVector2Array()  # alive vehicle positions (enemy phase)
var _av_idx: PackedInt32Array = PackedInt32Array()
var _contact: PackedFloat32Array = PackedFloat32Array()


func _init(p_seed: int) -> void:
	seed = p_seed
	rng.seed = p_seed
	_hash = SpatialHash.new(ARENA, HASH_CELL)
	phase_ticks_left = combat_duration(1)


# ---------------------------------------------------------------- public API

## `p_name` is sanitised; `p_color` < 0 keeps the default (vehicle id % 8).
func add_vehicle(peer_id: int, pos: Vector2, p_name: String = SimVehicle.DEFAULT_NAME, p_color: int = -1) -> SimVehicle:
	var v := SimVehicle.new(vehicles.size(), peer_id, pos)
	v.player_name = SimVehicle.sanitize_name(p_name)
	if p_color >= 0:
		v.color_index = p_color % SimVehicle.COLOR_COUNT
	v.heading = (ARENA.get_center() - pos).angle()
	vehicles.append(v)
	prepare_vehicle(v)
	return v


## Initialises a vehicle that joined (or took over a departed slot) mid-game: fuel and, during the
## workshop, a fresh set of card offers. NetSession calls this after replacing a slot.
func prepare_vehicle(v: SimVehicle) -> void:
	v.fuel = START_FUEL
	if phase == PHASE_WORKSHOP:
		v.offers = Cards.roll_offers(rng, v)


func get_vehicle_for_peer(peer_id: int) -> SimVehicle:
	for v in vehicles:
		if v.peer_id == peer_id:
			return v
	return null


## Applies a (pre-validated) command from `peer_id`. Card / tech / ready commands only work in the
## workshop; set_drive and set_target work in every phase. Unknown or illegal commands are ignored.
func apply_command(peer_id: int, cmd: Dictionary) -> void:
	var v: SimVehicle = get_vehicle_for_peer(peer_id)
	if v == null:
		return
	var type: String = str(cmd.get("type", ""))
	match type:
		"set_drive":
			var value: String = str(cmd.get("value", ""))
			if value in ["circle", "kite", "charge"]:
				v.doctrine["drive"] = value
		"set_target":
			var value2: String = str(cmd.get("value", ""))
			if value2 in ["nearest", "strongest", "players_first"]:
				v.doctrine["target"] = value2
		"pick_card":
			if _can_shop(v) and not v.picked:
				var idx: int = _integral(cmd.get("value"))
				if idx >= 0 and idx < v.offers.size() and Cards.grant(v, v.offers[idx]):
					v.picked = true
					v.offers = []
		"reroll":
			if _can_shop(v) and not v.picked and v.scrap >= v.reroll_cost:
				v.scrap -= v.reroll_cost
				v.reroll_cost += 1
				v.offers = Cards.roll_offers(rng, v)
		"buy_tech":
			if _can_shop(v):
				Tech.buy(v, str(cmd.get("value", "")))
		"ready":
			if _can_shop(v):
				v.ready = true


func _can_shop(v: SimVehicle) -> bool:
	return phase == PHASE_WORKSHOP and not v.eliminated


## `x` as an int if it is an int or an integral float, else -1.
static func _integral(x: Variant) -> int:
	if typeof(x) == TYPE_INT:
		return x
	if typeof(x) == TYPE_FLOAT:
		var f: float = x
		if is_finite(f) and f == floorf(f) and absf(f) < 1.0e9:
			return int(f)
	return -1


# ---------------------------------------------------------------- PvP rules

## False during the grace rounds (< PVP_START_ROUND): vehicles do not target players, player
## projectiles pass through other vehicles and ramming does no damage. Alien hits are unaffected.
func pvp_enabled() -> bool:
	return round >= PVP_START_ROUND


## Leader score: kills (aliens and players) plus a tenth of the scrap in hand.
func leader_score(v: SimVehicle) -> int:
	return v.kills + v.scrap / LEADER_SCRAP_DIVISOR


## Recomputes `leader_peer`: the non-eliminated vehicle with the strictly highest leader_score, or -1
## while PvP is off, fewer than two vehicles are still in the game, or the top score is tied (a tied
## incumbent keeps the mark). Deterministic, no rng.
func update_leader() -> void:
	var best: int = -1
	var best_peer: int = -1
	var tied: bool = false
	var incumbent_in_top: bool = false
	var alive_n: int = 0
	if pvp_enabled():
		for v in vehicles:
			if v.eliminated:
				continue
			alive_n += 1
			var s: int = leader_score(v)
			if s > best:
				best = s
				best_peer = v.peer_id
				tied = false
				incumbent_in_top = v.peer_id == leader_peer
			elif s == best:
				tied = true
				incumbent_in_top = incumbent_in_top or v.peer_id == leader_peer
	if alive_n < 2 or best <= 0:
		leader_peer = -1
	elif not tied:
		leader_peer = best_peer
	elif not incumbent_in_top:
		leader_peer = -1


# ---------------------------------------------------------------- round scaling

static func enemy_hp_mult(r: int) -> float:
	return 1.0 + HP_SCALE_PER_ROUND * float(maxi(r - 1, 0))


static func spawn_rate_mult(r: int) -> float:
	return 1.0 + SPAWN_SCALE_PER_ROUND * float(maxi(r - 1, 0))


static func boulder_chance(r: int) -> float:
	return minf(BOULDER_CHANCE + BOULDER_CHANCE_PER_ROUND * float(maxi(r - 1, 0)), BOULDER_CHANCE_MAX)


## Share of spawns that are spitters in round `r` (0 before SPITTER_MIN_ROUND).
static func spitter_chance(r: int) -> float:
	if r < SPITTER_MIN_ROUND:
		return 0.0
	return minf(SPITTER_CHANCE_START + SPITTER_CHANCE_PER_ROUND * float(r - SPITTER_MIN_ROUND), SPITTER_CHANCE_MAX)


static func enemy_damage_mult(r: int) -> float:
	return 1.0 + DAMAGE_SCALE_PER_ROUND * float(maxi(r - 1, 0))


## Full hp of an enemy of `kind` spawned in round `r` (snapshots encode hp relative to this).
static func enemy_max_hp(kind: int, r: int) -> float:
	return ENEMY_HP[kind] * enemy_hp_mult(r)


func combat_duration(r: int) -> int:
	if fast_rounds:
		return FAST_COMBAT_TICKS
	return COMBAT_TICKS_EARLY if r <= EARLY_ROUNDS else COMBAT_TICKS


func workshop_duration() -> int:
	return FAST_WORKSHOP_TICKS if fast_rounds else WORKSHOP_TICKS


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
	enemy_hp.append(enemy_max_hp(kind, round))
	enemy_count += 1
	return id


func spawn_projectile(pos: Vector2, vel: Vector2, ttl: float, damage: float, owner: int, pierce: int = 0, splash: float = 0.0) -> void:
	if proj_count >= MAX_PROJECTILES:
		return
	proj_pos.append(pos)
	proj_vel.append(vel)
	proj_ttl.append(ttl)
	proj_damage.append(damage)
	proj_owner.append(owner)
	proj_pierce.append(clampi(pierce, 0, 255))
	proj_splash.append(splash)
	proj_last.append(-1)
	proj_count += 1


## Enemy indices within `radius` of `center` (as of the end of the previous tick's hash,
## filtered by current positions). Results are written to out[0..n).
func query_enemies(center: Vector2, radius: float, out: PackedInt32Array) -> int:
	return _hash.query_circle(center, radius, enemy_pos, out, STALE_MARGIN)


func step() -> void:
	events.clear()
	match phase:
		PHASE_COMBAT:
			_step_combat()
		PHASE_WORKSHOP:
			_step_workshop()
	tick += 1


func _step_combat() -> void:
	update_leader()
	_update_respawns()
	_update_enemies()
	_update_vehicles()
	_update_projectiles()
	_compact_enemies()
	_spawn_tick()
	_hash.rebuild(enemy_pos, enemy_count)
	if _check_game_over():
		return
	phase_ticks_left -= 1
	if phase_ticks_left <= 0:
		_begin_workshop()


func _step_workshop() -> void:
	if _check_game_over():
		return
	phase_ticks_left -= 1
	var need: int = 0
	var ready_n: int = 0
	for v in vehicles:
		if v.eliminated:
			continue
		need += 1
		if v.ready:
			ready_n += 1
	if phase_ticks_left <= 0 or (need > 0 and ready_n == need):
		_begin_combat()


func checksum() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var head := PackedInt64Array([tick, enemy_count, proj_count, vehicles.size(), phase, round, phase_ticks_left, winner_peer, next_enemy_id, leader_peer])
	ctx.update(head.to_byte_array())
	var vf := PackedFloat64Array()
	for v in vehicles:
		vf.append(float(v.id))
		vf.append(float(v.peer_id))
		vf.append(float(v.color_index))
		vf.append(float(v.player_name.hash()))
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
		vf.append(float(v.fuel))
		vf.append(float(v.respawn_ticks))
		vf.append(1.0 if v.eliminated else 0.0)
		vf.append(1.0 if v.ready else 0.0)
		vf.append(1.0 if v.picked else 0.0)
		vf.append(float(v.reroll_cost))
		vf.append(v.scrap_frac)
		vf.append(v.armor)
		vf.append(v.speed)
		vf.append(v.turn_rate)
		vf.append(v.scrap_mult)
		vf.append(v.regen)
		vf.append(v.contact_damage)
		vf.append(v.ram_mult)
		vf.append(v.vulture)
		vf.append(float(v.weapon_slots))
		vf.append(float(v.interest_cap))
		vf.append(float(v.protect_ticks))
		vf.append(float(v.offers.size()))
		for oid in v.offers:
			vf.append(float(Cards.index_of(oid)))
		vf.append(float(v.cards.size()))
		for cid: String in v.cards:
			vf.append(float(Cards.index_of(cid)))
			vf.append(float(v.cards[cid]))
		vf.append(float(v.tech.size()))
		for tid in v.tech:
			vf.append(float(Tech.index_of(tid)))
		for wp in v.weapons:
			vf.append(float(str(wp["kind"]).hash()))
			vf.append(float(wp["damage"]))
			vf.append(float(wp["range"]))
			vf.append(float(wp["cooldown"]))
			vf.append(float(wp["cooldown_ticks"]))
			vf.append(float(wp["aim"]))
			vf.append(float(wp.get("pellets", 1)))
			vf.append(float(wp.get("spread", 0.0)))
			vf.append(float(wp.get("pierce", 0)))
			vf.append(float(wp.get("splash", 0.0)))
			vf.append(float(wp.get("speed", 0.0)))
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
		proj_pierce,
		proj_splash.to_byte_array(),
		proj_last.to_byte_array(),
	]:
		if part.size() > 0:  # HashingContext rejects empty updates
			ctx.update(part)
	return ctx.finish().decode_s64(0)


## Rebuilds derived structures (spatial hash, counts) after external code (e.g. a network
## snapshot) rewrote the enemy/projectile arrays.
func rebuild_derived() -> void:
	enemy_count = enemy_id.size()
	proj_count = proj_pos.size()
	if proj_pierce.size() != proj_count:
		proj_pierce.resize(proj_count)
	if proj_splash.size() != proj_count:
		proj_splash.resize(proj_count)
	if proj_last.size() != proj_count:
		var old: int = proj_last.size()
		proj_last.resize(proj_count)
		for i in range(old, proj_count):
			proj_last[i] = -1
	_hash.rebuild(enemy_pos, enemy_count)


# ---------------------------------------------------------------- events

func _emit(type: String, pos: Vector2, owner: int, kind: int) -> void:
	if events.size() >= MAX_EVENTS:
		return
	events.append({"type": type, "pos": pos, "owner": owner, "kind": kind})


# ---------------------------------------------------------------- round loop

## Counts down respawn timers of destroyed (not eliminated) vehicles.
func _update_respawns() -> void:
	for v in vehicles:
		if v.alive or v.eliminated:
			continue
		if v.respawn_ticks > 0:
			v.respawn_ticks -= 1
		if v.respawn_ticks <= 0:
			_respawn(v)


func _respawn(v: SimVehicle) -> void:
	v.pos = _find_spawn_spot(v)
	v.vel = Vector2.ZERO
	v.hp = v.max_hp
	v.alive = true
	v.respawn_ticks = 0
	v.protect_ticks = 0
	v.retaliate_ticks = 0
	v.target_kind = 0
	v.heading = (ARENA.get_center() - v.pos).angle()
	_emit("respawn", v.pos, v.id, -1)


## First of the 8 ellipse slots (starting at the vehicle's own) that is clear of vehicles and
## enemies; if none is, the slot farthest from the other vehicles. No rng, fully deterministic.
func _find_spawn_spot(v: SimVehicle) -> Vector2:
	var c: Vector2 = ARENA.get_center()
	var best: Vector2 = c
	var best_d: float = -1.0
	for k in 8:
		var a: float = float((v.id + k) % 8) * TAU / 8.0
		var p: Vector2 = c + Vector2(cos(a) * 480.0, sin(a) * 240.0)
		var nearest: float = INF
		for o in vehicles:
			if o != v and o.alive:
				nearest = minf(nearest, o.pos.distance_to(p))
		var clear: bool = nearest >= SPAWN_SPOT_CLEARANCE
		if clear and enemy_count > 0:
			clear = query_enemies(p, SPAWN_SPOT_ENEMY_CLEARANCE, ai_buf) == 0
		if clear:
			return p
		if nearest > best_d:
			best_d = nearest
			best = p
	return best


## Combat -> workshop: aliens retreat (one "retreat" event per enemy, thinned to at most
## RETREAT_EVENT_CAP, with the enemy's kind), projectiles vanish, vehicles stop, interest is paid
## and every player gets fresh card offers. Destroyed vehicles respawn at once.
func _begin_workshop() -> void:
	_compact_enemies()
	var stride: int = maxi(1, ceili(float(enemy_count) / float(RETREAT_EVENT_CAP)))
	for i in range(0, enemy_count, stride):
		_emit("retreat", enemy_pos[i], -1, enemy_kind[i])
	_clear_field()
	phase = PHASE_WORKSHOP
	phase_ticks_left = workshop_duration()
	for v in vehicles:
		v.vel = Vector2.ZERO
		v.target_kind = 0
		v.ram_damage = 0.0
		v.ready = false
		v.picked = false
		v.protect_ticks = 0
		v.retaliate_ticks = 0
		v.reroll_cost = REROLL_COST_START
		v.offers = []
		if v.eliminated:
			continue
		if not v.alive:
			_respawn(v)
		v.scrap += mini(v.scrap / INTEREST_PER, v.interest_cap)
		v.offers = Cards.roll_offers(rng, v)


## Workshop -> combat: the next round starts, vehicles are repaired, unused offers are dropped.
func _begin_combat() -> void:
	round += 1
	phase = PHASE_COMBAT
	phase_ticks_left = combat_duration(round)
	_spawn_accum = 0.0
	for v in vehicles:
		v.offers = []
		v.ready = false
		v.picked = false
		if v.alive and not v.eliminated:
			v.hp = v.max_hp
		for w in v.weapons:
			w["cooldown"] = 0


## Ends the game when at most one player is left in a multiplayer game (winner = the survivor),
## or when the only player is eliminated in solo. Returns true if the game is over.
func _check_game_over() -> bool:
	var total: int = vehicles.size()
	if total == 0:
		return false
	var remaining: int = 0
	var last: SimVehicle = null
	for v in vehicles:
		if not v.eliminated:
			remaining += 1
			last = v
	var over: bool = (total >= 2 and remaining <= 1) or (total == 1 and remaining == 0)
	if not over:
		return false
	phase = PHASE_GAME_OVER
	phase_ticks_left = 0
	winner_peer = last.peer_id if (total >= 2 and remaining == 1) else -1
	for v in vehicles:
		v.vel = Vector2.ZERO
		v.offers = []
	return true


func _clear_field() -> void:
	enemy_id.resize(0)
	enemy_kind.resize(0)
	enemy_pos.resize(0)
	enemy_vel.resize(0)
	enemy_hp.resize(0)
	enemy_count = 0
	proj_pos.resize(0)
	proj_vel.resize(0)
	proj_ttl.resize(0)
	proj_damage.resize(0)
	proj_owner.resize(0)
	proj_pierce.resize(0)
	proj_splash.resize(0)
	proj_last.resize(0)
	proj_count = 0
	_hash.rebuild(enemy_pos, 0)


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
				if kind == SPITTER:
					desired = _spitter_desire(dir / dl, dl, enemy_id[i])
				else:
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
				_contact[vidx] += _contact_hit(kind, vehicles[vidx].armor)
				var ram: float = vehicles[vidx].ram_damage
				if ram > 0.0 and not killed:
					_hit_enemy(i, ram, vidx)
					killed = enemy_hp[i] <= 0.0

		np.x = clampf(np.x, a_min.x, a_max.x)
		np.y = clampf(np.y, a_min.y, a_max.y)
		enemy_pos[i] = np
		enemy_vel[i] = vel

		if kind == SPITTER and bk >= 0 and enemy_hp[i] > 0.0 and (tick + enemy_id[i] * 7) % SPIT_PERIOD == 0:
			_spit(np, vehicles[_av_idx[bk]])

	for vidx in vehicles.size():
		if _contact[vidx] > 0.0:
			_damage_vehicle(vehicles[vidx], _contact[vidx], -1, false)


## Spitter movement: hold SPITTER_KEEP_MIN..SPITTER_KEEP_MAX px from the target (`u` = unit vector to
## it, `d` = distance), backing away (with a sideways drift, so it does not corner itself) when too
## close, closing in when too far, and strafing slowly in between.
static func _spitter_desire(u: Vector2, d: float, id: int) -> Vector2:
	var side: float = 1.0 if id % 2 == 0 else -1.0
	var tang: Vector2 = Vector2(-u.y, u.x) * side
	var spd: float = ENEMY_SPEED[SPITTER]
	if d > SPITTER_KEEP_MAX:
		return u * spd
	if d < SPITTER_KEEP_MIN:
		return (-u + tang * 0.6).normalized() * spd
	return tang * (spd * 0.4)


## A spitter at `from` lobs one acid glob at `target` (leading its movement). Emits a "spit" event.
func _spit(from: Vector2, target: SimVehicle) -> void:
	var dist: float = from.distance_to(target.pos)
	if dist > SPIT_RANGE or dist < 1.0:
		return
	var aim: Vector2 = target.pos + target.vel * (dist / SPIT_SPEED)
	var ang: float = (aim - from).angle() + rng.randf_range(-SPIT_INACCURACY, SPIT_INACCURACY)
	var dir: Vector2 = Vector2.from_angle(ang)
	var muzzle: Vector2 = from + dir * 10.0
	spawn_projectile(muzzle, dir * SPIT_SPEED, SPIT_RANGE / SPIT_SPEED + 0.3, SPIT_DAMAGE * enemy_damage_mult(round), -1)
	_emit("spit", muzzle, -1, SPITTER)


## Contact damage per tick of one touching enemy after the vehicle's armour.
func _contact_hit(kind: int, armor: float) -> float:
	var d: float = ENEMY_CONTACT_DAMAGE[kind] * enemy_damage_mult(round)
	return maxf(d - armor * CONTACT_ARMOR_FACTOR, d * ARMOR_MIN_FRACTION)


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
		kv.scrap_frac += float(ENEMY_SCRAP[kind]) * kv.scrap_mult
		var whole: int = int(kv.scrap_frac)
		kv.scrap += whole
		kv.scrap_frac -= float(whole)
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
	var secs: float = float(combat_duration(round) - phase_ticks_left) * DT  # seconds into this round
	var rate: float = (SPAWN_RATE_START + SPAWN_RATE_RAMP * floorf(secs / SPAWN_RAMP_INTERVAL)) * spawn_rate_mult(round)
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
		var kind: int = MITE
		if rng.randf() < boulder_chance(round):
			kind = BOULDER
		elif round >= SPITTER_MIN_ROUND and rng.randf() < spitter_chance(round):
			kind = SPITTER  # no extra rng draw before SPITTER_MIN_ROUND: early rounds are unchanged
		spawn_enemy(kind, pos)


# ---------------------------------------------------------------- vehicles

func _update_vehicles() -> void:
	var lo := ARENA.position + Vector2(SimVehicle.RADIUS, SimVehicle.RADIUS)
	var hi := ARENA.end - Vector2(SimVehicle.RADIUS, SimVehicle.RADIUS)
	for v in vehicles:
		if not v.alive:
			continue
		if v.protect_ticks > 0:
			v.protect_ticks -= 1
		if v.retaliate_ticks > 0:
			v.retaliate_ticks -= 1
		if v.regen > 0.0 and v.hp < v.max_hp:
			v.hp = minf(v.hp + v.regen * DT, v.max_hp)
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
			if not pvp_enabled():
				continue  # grace period: the vehicles only push each other
			if va.ram_damage > 0.0:
				_damage_vehicle(vb, va.ram_damage, va.id)
			if vb.ram_damage > 0.0:
				_damage_vehicle(va, vb.ram_damage, vb.id)


## Applies damage to a vehicle (armour first unless `use_armor` is false). On destruction: fuel
## loss, a respawn timer (or elimination at 0 fuel) and, for a player kill, kill count and bounty.
func _damage_vehicle(v: SimVehicle, dmg: float, attacker: int, use_armor: bool = true) -> void:
	if not v.alive:
		return
	if use_armor and v.armor > 0.0:
		dmg = maxf(dmg - v.armor, dmg * ARMOR_MIN_FRACTION)
	if v.protect_ticks > 0:
		dmg *= PVP_PROTECT_FACTOR
	if attacker >= 0 and attacker != v.id and attacker < vehicles.size():
		var av0: SimVehicle = vehicles[attacker]
		if av0.target_kind == 2 and av0.target_id == v.id:  # deliberate attack, not a stray shot
			v.retaliate_id = attacker
			v.retaliate_ticks = RETALIATE_TICKS
	v.hp -= dmg
	if v.hp > 0.0:
		return
	v.hp = 0.0
	v.alive = false
	v.vel = Vector2.ZERO
	v.target_kind = 0
	v.ram_damage = 0.0
	_emit("vehicle_destroyed", v.pos, v.id, -1)
	var by_player: bool = attacker >= 0 and attacker != v.id and attacker < vehicles.size()
	v.fuel = maxi(v.fuel - (FUEL_LOSS_PVP if by_player else FUEL_LOSS), 0)
	if v.fuel <= 0:
		v.eliminated = true
		v.respawn_ticks = 0
	else:
		v.respawn_ticks = RESPAWN_TICKS
	if by_player:
		var av: SimVehicle = vehicles[attacker]
		av.kills += 1
		av.scrap += PVP_KILL_SCRAP * (LEADER_BOUNTY_MULT if v.peer_id == leader_peer else 1)
		if av.alive:
			av.protect_ticks = PVP_PROTECT_TICKS


func _fire_weapons(v: SimVehicle) -> void:
	var has_target: bool = v.target_kind != 0
	var weak: bool = has_target and v.vulture > 0.0 and _target_is_weak(v)
	for w in v.weapons:
		var cd: int = w["cooldown"]
		if cd > 0:
			cd -= 1
			w["cooldown"] = cd
		if not has_target:
			continue
		var speed: float = float(w.get("speed", PROJECTILE_SPEED))
		var dist: float = v.pos.distance_to(v.target_pos)
		var lead: Vector2 = v.target_pos + v.target_vel * (dist / speed)
		var to: Vector2 = lead - v.pos
		var ang: float = to.angle()
		w["aim"] = ang
		if cd > 0 or dist > float(w["range"]) or proj_count >= MAX_PROJECTILES:
			continue
		var spread: float = float(w.get("spread", SPREAD))
		var pellets: int = int(w.get("pellets", 1))
		var pierce: int = int(w.get("pierce", 0))
		var splash: float = float(w.get("splash", 0.0))
		var dmg: float = float(w["damage"])
		if weak:
			dmg *= 1.0 + v.vulture
		var ttl: float = float(w["range"]) / speed + 0.05
		var muzzle: Vector2 = v.pos + Vector2.from_angle(ang) * MUZZLE_OFFSET
		for p in pellets:
			var dir: Vector2 = Vector2.from_angle(ang + rng.randf_range(-spread, spread))
			spawn_projectile(muzzle, dir * speed, ttl, dmg, v.id, pierce, splash)
		w["cooldown"] = int(w["cooldown_ticks"])
		_emit("fire", muzzle, v.id, Cards.weapon_kind_index(str(w["kind"])))


## Vulture: is the current target under 30% hp?
func _target_is_weak(v: SimVehicle) -> bool:
	if v.target_kind == 1:
		var i: int = v.target_index
		if i < 0 or i >= enemy_count:
			return false
		return enemy_hp[i] < Cards.VULTURE_HP_FRACTION * enemy_max_hp(enemy_kind[i], round)
	if v.target_kind == 2 and v.target_id >= 0 and v.target_id < vehicles.size():
		var t: SimVehicle = vehicles[v.target_id]
		return t.alive and t.hp < Cards.VULTURE_HP_FRACTION * t.max_hp
	return false


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
	var pvp: bool = pvp_enabled()
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
		var last_id: int = proj_last[i]

		if owner >= 0:
			var reach: float = step_v.length() * 0.5 + MAX_ENEMY_RADIUS + PROJECTILE_RADIUS
			var cnt: int = _hash.query_circle(p0 + step_v * 0.5, reach, enemy_pos, _query_buf, STALE_MARGIN)
			for q in cnt:
				var j: int = _query_buf[q]
				if enemy_hp[j] <= 0.0 or enemy_id[j] == last_id:
					continue
				var t: float = _segment_circle_t(p0, step_v, enemy_pos[j], ENEMY_RADIUS[enemy_kind[j]] + PROJECTILE_RADIUS)
				if t >= 0.0 and t < best_t:
					best_t = t
					hit_enemy = j
		for vi in nveh:
			var v: SimVehicle = vehicles[vi]
			if not v.alive or v.id == owner or (owner >= 0 and not pvp):
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
			var hit_pos: Vector2 = p0 + step_v * best_t
			_emit("hit", hit_pos, owner, enemy_kind[hit_enemy])
			_hit_enemy(hit_enemy, dmg, owner)
			if proj_splash[i] > 0.0:
				_splash_damage(hit_pos, proj_splash[i], dmg * SPLASH_FRACTION, owner, hit_enemy)
			if proj_pierce[i] > 0:
				proj_pierce[i] -= 1
				proj_last[i] = enemy_id[hit_enemy]
			else:
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
			proj_pierce[i] = proj_pierce[n]
			proj_splash[i] = proj_splash[n]
			proj_last[i] = proj_last[n]
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
		proj_pierce.resize(n)
		proj_splash.resize(n)
		proj_last.resize(n)
		proj_count = n


## Damages every living enemy within `radius` of `center` except index `skip`.
func _splash_damage(center: Vector2, radius: float, dmg: float, owner: int, skip: int) -> void:
	var cnt: int = _hash.query_circle(center, radius, enemy_pos, _splash_buf, STALE_MARGIN)
	for q in cnt:
		var j: int = _splash_buf[q]
		if j != skip:
			_hit_enemy(j, dmg, owner)
