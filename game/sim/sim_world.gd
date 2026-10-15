class_name SimWorld
extends RefCounted
## Deterministic simulation core. See docs/architecture.md ("Sim contract").
## No Node / scene tree / Input / OS / Time / global randf: all randomness is `rng`.

const TICK_RATE := 30
const DT := 1.0 / 30.0
const ARENA := Rect2(0, 0, 2560, 1440)
## Start / respawn slots: 8 points on this ellipse around the arena centre (NetSession uses it too).
const SPAWN_ELLIPSE := Vector2(720.0, 400.0)
## Aliens spawn on the edge of the vehicles' bounding box grown by this much (clipped to the arena),
## so they always arrive from off-screen at the same distance, however big the arena is.
const SPAWN_REACH := Vector2(640.0, 360.0)

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

# Damage sources (stats, "vehicle_destroyed" cause). 0..2 equal the enemy kind (contact damage).
const SRC_MITE := 0
const SRC_BOULDER := 1
const SRC_SPITTER := 2  # spitter body contact
const SRC_ACID := 3
const SRC_RAM := 4  # a rival's ram / spikes
const SRC_PLAYER := 5  # a rival's shots
const SRC_NAMES: PackedStringArray = ["mite", "boulder", "spitter", "acid", "ram", "player"]
const WEAPON_RAM := 4  # "weapon" of a player kill by ramming (Cards.WEAPON_KINDS holds 0..3)

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
const PVP_GRACE_TICKS := 300  # 10 s at the start of round PVP_START_ROUND during which PvP is still off
const INVULN_TICKS := 90  # 3 s of invulnerability after a respawn and at the start of every combat from round 2
const UNDERDOG_FUEL_FACTOR := 0.7  # the lowest-fuel player loses 30% less fuel per death
const FUEL_STEAL := 10  # a player kill moves this much of the victim's fuel loss to the killer
const LEADER_FUEL_BONUS := 10  # extra fuel for destroying the marked leader
const REPEAT_KILL_FACTORS: Array[float] = [1.0, 0.5, 0.0]  # reward share for the 1st, 2nd, 3rd+ kill of the same victim in a round
const FUEL_DRAIN_START_ROUND := 8  # PVP_START_ROUND + 4: multiplayer only, from the workshop after this round
const FUEL_DRAIN_BASE := 5
const FUEL_DRAIN_ROUNDS_PER_STEP := 3  # the drain grows by 1 every this many rounds past the start
const PVP_PROTECT_TICKS := 60  # 2 s of third-party protection after a player kill
const PVP_PROTECT_FACTOR := 0.5  # damage multiplier while protected
const RETALIATE_TICKS := 60  # return fire: a vehicle shoots back at a player that hurt it for 2 s (any doctrine)

const SPAWN_RATE_START := 1.5  # enemies / s
const SPAWN_RATE_RAMP := 0.5  # added every SPAWN_RAMP_INTERVAL seconds of the combat phase
const SPAWN_RAMP_INTERVAL := 10.0
const SPAWN_RAMP_END_BEFORE := 15.0  # the in-round ramp stops this many seconds before the round ends (flat finish)
const BOULDER_CHANCE := 0.04  # round 1; reaches the old 0.4 cap in the same round (13) as before
const SPAWN_INSET := 8.0
# Alive caps: a spawn that would exceed the cap becomes a mite, so the field never snowballs.
const BOULDER_CAP_BASE := 8
const BOULDER_CAP_PER_ROUND := 3
const BOULDER_CAP_MAX := 48
const SPITTER_CAP_BASE := 3
const SPITTER_CAP_MAX := 12
const SPITTER_SPAWN_GAP := 75  # ticks (2.5 s) between spitter spawns, on a different edge than the last

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
const WORKSHOP_TICKS := 2700  # 90 s (90 * TICK_RATE)
const FAST_COMBAT_TICKS := 120  # world.fast_rounds (tests, screenshots)
const FAST_WORKSHOP_TICKS := 162  # scaled with the workshop: 45 * 90 / 25

const START_FUEL := 100
const FUEL_LOSS := 20  # destroyed by aliens
const FUEL_LOSS_PVP := 30  # destroyed by another player
const RESPAWN_TICKS := 90  # 3 s
const INTEREST_PER := 10  # +1 scrap per this much scrap held at the end of a round (10%)
const INTEREST_CAP_PER_ROUND := 2  # interest cap = Vehicle.interest_cap (5 + salvage tech) + this x round
const REROLL_COST_START := 6
const RETREAT_EVENT_CAP := 150  # at most this many "retreat" events per round end

# Per-round enemy scaling (round 1 = x1).
const HP_SCALE_PER_ROUND := 0.20
const HP_SCALE_QUAD := 0.0125  # late-game term: the hive outgrows a linear power curve
const SPAWN_SCALE_PER_ROUND := 0.15
const BOULDER_CHANCE_PER_ROUND := 0.03
const BOULDER_CHANCE_MAX := 0.4
const DAMAGE_SCALE_PER_ROUND := 0.03
# Early-round easing (playtest: the first waves were too strong). Spawn rate and enemy damage start at this
# share in round 1 and rise linearly to full strength in round EASE_END_ROUND; later rounds are unchanged.
const EASE_END_ROUND := 7
const SPAWN_EASE_START := 0.55
const DAMAGE_EASE_START := 0.65

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
## Ticks of PvP grace left at the start of round PVP_START_ROUND (0 = none / over). See pvp_enabled().
var pvp_grace_ticks: int = 0
## Fuel every player loses at the coming workshop (0 = no drain yet / solo). See fuel_drain_for_round().
var fuel_drain: int = 0
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
var proj_weapon: PackedByteArray = PackedByteArray()  # weapon kind index of the shooter's gun (kill feed), 255 = alien

var events: Array[Dictionary] = []

## Set false to stop the timed enemy spawner (tests, scenarios).
var spawning_enabled: bool = true
var next_enemy_id: int = 0

## Shared scratch buffer for VehicleAI queries.
var ai_buf: PackedInt32Array = PackedInt32Array()

var _hash: SpatialHash
var _spawn_accum: float = 0.0
var _hit_weapon: int = -1  # weapon kind index of the projectile being resolved (kill feed)
var _spitter_gap: int = 0
var _last_spitter_side: int = -1
var _query_buf: PackedInt32Array = PackedInt32Array()
var _splash_buf: PackedInt32Array = PackedInt32Array()
var _av_pos: PackedVector2Array = PackedVector2Array()  # alive vehicle positions (enemy phase)
var _av_idx: PackedInt32Array = PackedInt32Array()
var _contact: PackedFloat32Array = PackedFloat32Array()  # per vehicle x 3 enemy kinds, damage this tick


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
		v.offers = Cards.roll_offers(rng, v, Cards.OFFER_COUNT, round)


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
				v.offers = Cards.roll_offers(rng, v, Cards.OFFER_COUNT, round, v.offers)
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

## False during the grace rounds (< PVP_START_ROUND) and during the first PVP_GRACE_TICKS (10 s) of round
## PVP_START_ROUND (`pvp_grace_ticks` > 0): vehicles do not target players, player projectiles pass
## through other vehicles and ramming does no damage. Alien hits are unaffected. A "pvp_on" event is
## emitted on the tick PvP switches on.
func pvp_enabled() -> bool:
	return round >= PVP_START_ROUND and pvp_grace_ticks <= 0


## True when `v` has strictly the least fuel of all non-eliminated players (and there is another one):
## it loses UNDERDOG_FUEL_FACTOR x the usual fuel per death.
func is_underdog(v: SimVehicle) -> bool:
	if v.eliminated:
		return false
	var others: int = 0
	for o in vehicles:
		if o == v or o.eliminated:
			continue
		others += 1
		if o.fuel <= v.fuel:
			return false
	return others > 0


## Fuel every player loses at the workshop after round `r` (multiplayer only, 0 before
## FUEL_DRAIN_START_ROUND): 5, growing by 1 every 3 rounds (8..10: 5, 11..13: 6, ...).
static func fuel_drain_for_round(r: int) -> int:
	if r < FUEL_DRAIN_START_ROUND:
		return 0
	return FUEL_DRAIN_BASE + (r - FUEL_DRAIN_START_ROUND) / FUEL_DRAIN_ROUNDS_PER_STEP


## Interest cap at the current round: the vehicle's own cap (5 + salvage tech) + 2 per round.
func interest_cap_for(v: SimVehicle) -> int:
	return v.interest_cap + INTEREST_CAP_PER_ROUND * round


## Interest a vehicle would earn now: 10% of held scrap (INTEREST_PER), capped at interest_cap_for().
func interest_for(v: SimVehicle) -> int:
	return mini(v.scrap / INTEREST_PER, interest_cap_for(v))


## Fresh per-round stats (see docs/architecture.md, "Stats").
static func new_round_stats(r: int) -> Dictionary:
	return {
		"round": r,
		"taken": {"mite": 0.0, "boulder": 0.0, "spitter": 0.0, "acid": 0.0, "rival": 0.0},
		"taken_players": {},  # attacker vehicle id -> hp (rival shots and rams)
		"dealt": 0.0, "dealt_players": 0.0,
		"kills": 0, "kills_players": 0,
		"deaths": [],  # {"t": ticks into combat, "cause": SRC_NAMES entry, "src": int, "killer": vehicle id or -1, "killer_kind": enemy kind or -1}
		"fuel_lost": 0, "fuel_gained": 0, "fuel_drained": 0,
		"scrap_earned": 0, "interest": 0,
	}


static func new_match_stats() -> Dictionary:
	return {
		"kills": 0, "player_kills": 0, "ram_kills": 0, "deaths": 0, "dmg_dealt": 0.0, "scrap_earned": 0,
		"top_victim": -1, "top_victim_n": 0, "nemesis": -1, "nemesis_n": 0,
	}


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
	var old_peer: int = leader_peer
	if alive_n < 2 or best <= 0:
		leader_peer = -1
	elif not tied:
		leader_peer = best_peer
	elif not incumbent_in_top:
		leader_peer = -1
	if leader_peer != old_peer:
		var nv: SimVehicle = get_vehicle_for_peer(leader_peer) if leader_peer >= 0 else null
		var ov: SimVehicle = get_vehicle_for_peer(old_peer) if old_peer >= 0 else null
		_emit("bounty", nv.pos if nv != null else (ov.pos if ov != null else Vector2.ZERO),
			nv.id if nv != null else -1, ov.id if ov != null else -1)


# ---------------------------------------------------------------- round scaling

static func enemy_hp_mult(r: int) -> float:
	var n: float = float(maxi(r - 1, 0))
	return 1.0 + HP_SCALE_PER_ROUND * n + HP_SCALE_QUAD * n * n


static func spawn_rate_mult(r: int) -> float:
	return (1.0 + SPAWN_SCALE_PER_ROUND * float(maxi(r - 1, 0))) * early_ease(r, SPAWN_EASE_START)


## `start` in round 1, rising linearly to 1.0 in round EASE_END_ROUND and after.
static func early_ease(r: int, start: float) -> float:
	var t: float = clampf(float(maxi(r, 1) - 1) / float(EASE_END_ROUND - 1), 0.0, 1.0)
	return lerpf(start, 1.0, t)


static func boulder_chance(r: int) -> float:
	return minf(BOULDER_CHANCE + BOULDER_CHANCE_PER_ROUND * float(maxi(r - 1, 0)), BOULDER_CHANCE_MAX)


## Share of spawns that are spitters in round `r` (0 before SPITTER_MIN_ROUND).
static func spitter_chance(r: int) -> float:
	if r < SPITTER_MIN_ROUND:
		return 0.0
	return minf(SPITTER_CHANCE_START + SPITTER_CHANCE_PER_ROUND * float(r - SPITTER_MIN_ROUND), SPITTER_CHANCE_MAX)


## Most boulders alive at once in round `r`: 6 + 2 per round, at most 32.
static func boulder_cap(r: int) -> int:
	return mini(BOULDER_CAP_BASE + BOULDER_CAP_PER_ROUND * maxi(r, 1), BOULDER_CAP_MAX)


## Most spitters alive at once in round `r`: 2 + r / 2, at most 8.
static func spitter_cap(r: int) -> int:
	return mini(SPITTER_CAP_BASE + maxi(r, 0) / 2, SPITTER_CAP_MAX)


static func enemy_damage_mult(r: int) -> float:
	return (1.0 + DAMAGE_SCALE_PER_ROUND * float(maxi(r - 1, 0))) * early_ease(r, DAMAGE_EASE_START)


## Full hp of an enemy of `kind` spawned in round `r` (snapshots encode hp relative to this).
static func enemy_max_hp(kind: int, r: int) -> float:
	return ENEMY_HP[kind] * enemy_hp_mult(r)


func combat_duration(r: int) -> int:
	if fast_rounds:
		return FAST_COMBAT_TICKS
	return COMBAT_TICKS_EARLY if r <= EARLY_ROUNDS else COMBAT_TICKS


func workshop_duration() -> int:
	return FAST_WORKSHOP_TICKS if fast_rounds else WORKSHOP_TICKS


## Enemies per second `ticks_in` ticks into a combat of round `r`. The in-round ramp (+0.5/s per 10 s) stops
## SPAWN_RAMP_END_BEFORE seconds before the round ends, so the last 15 s are flat (no end-of-round snowball).
func spawn_rate_at(r: int, ticks_in: int) -> float:
	var total_secs: float = float(combat_duration(r)) * DT
	var ramp_secs: float = minf(float(ticks_in) * DT, maxf(total_secs - SPAWN_RAMP_END_BEFORE, 0.0))
	return (SPAWN_RATE_START + SPAWN_RATE_RAMP * floorf(ramp_secs / SPAWN_RAMP_INTERVAL)) * spawn_rate_mult(r)


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


func spawn_projectile(pos: Vector2, vel: Vector2, ttl: float, damage: float, owner: int, pierce: int = 0, splash: float = 0.0, weapon: int = 255) -> void:
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
	proj_weapon.append(clampi(weapon, 0, 255))
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
	if pvp_grace_ticks > 0:
		pvp_grace_ticks -= 1
		if pvp_grace_ticks == 0:
			_emit("pvp_on", ARENA.get_center(), -1, -1)
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
	var head := PackedInt64Array([tick, enemy_count, proj_count, vehicles.size(), phase, round, phase_ticks_left, winner_peer, next_enemy_id, leader_peer, pvp_grace_ticks, fuel_drain])
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
		vf.append(float(v.invuln_ticks))
		vf.append(v.contact_reduction)
		vf.append(v.thorns)
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
	if proj_weapon.size() != proj_count:
		var oldw: int = proj_weapon.size()
		proj_weapon.resize(proj_count)
		for i in range(oldw, proj_count):
			proj_weapon[i] = 255
	if proj_last.size() != proj_count:
		var old: int = proj_last.size()
		proj_last.resize(proj_count)
		for i in range(old, proj_count):
			proj_last[i] = -1
	_hash.rebuild(enemy_pos, enemy_count)


# ---------------------------------------------------------------- events

func _emit(type: String, pos: Vector2, owner: int, kind: int, extra: Dictionary = {}) -> void:
	if events.size() >= MAX_EVENTS:
		return
	var e := {"type": type, "pos": pos, "owner": owner, "kind": kind}
	e.merge(extra)
	events.append(e)


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
	v.invuln_ticks = INVULN_TICKS
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
		var p: Vector2 = c + Vector2(cos(a) * SPAWN_ELLIPSE.x, sin(a) * SPAWN_ELLIPSE.y)
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
	pvp_grace_ticks = 0
	# Multiplayer fuel drain from round FUEL_DRAIN_START_ROUND: only kills (fuel steal) refill it. Never
	# eliminates by itself (floor 1). Solo has no drain: there is nobody to take fuel from.
	fuel_drain = fuel_drain_for_round(round) if vehicles.size() >= 2 else 0
	for v in vehicles:
		v.vel = Vector2.ZERO
		v.target_kind = 0
		v.ram_damage = 0.0
		v.ready = false
		v.picked = false
		v.protect_ticks = 0
		v.invuln_ticks = 0
		v.retaliate_ticks = 0
		v.reroll_cost = REROLL_COST_START
		v.offers = []
		if v.eliminated:
			continue
		if not v.alive:
			_respawn(v)
			v.invuln_ticks = 0
		var interest: int = interest_for(v)
		v.scrap += interest
		_note_scrap(v, interest)
		v.round_stats["interest"] = interest
		if fuel_drain > 0:
			var d: int = mini(fuel_drain, maxi(v.fuel - 1, 0))
			v.fuel -= d
			v.round_stats["fuel_drained"] = d
			_emit("drain", v.pos, v.id, d)
		v.offers = Cards.roll_offers(rng, v, Cards.OFFER_COUNT, round)


## Workshop -> combat: the next round starts, vehicles are repaired, unused offers are dropped.
func _begin_combat() -> void:
	round += 1
	phase = PHASE_COMBAT
	phase_ticks_left = combat_duration(round)
	_spawn_accum = 0.0
	_spitter_gap = 0
	_last_spitter_side = -1
	pvp_grace_ticks = 0
	if round == PVP_START_ROUND:
		if fast_rounds:
			_emit("pvp_on", ARENA.get_center(), -1, -1)  # fast rounds (tests, screenshots) skip the grace
		else:
			pvp_grace_ticks = PVP_GRACE_TICKS
	for v in vehicles:
		v.offers = []
		v.ready = false
		v.picked = false
		v.round_stats = new_round_stats(round)
		v.kill_counts = {}
		v.last_hit_attacker = -1
		if v.alive and not v.eliminated:
			v.hp = v.max_hp
			v.invuln_ticks = INVULN_TICKS
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
	proj_weapon.resize(0)
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
	_contact.resize(vehicles.size() * 3)
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
				var cv: SimVehicle = vehicles[vidx]
				_contact[vidx * 3 + kind] += _contact_hit(kind, cv.armor, cv.contact_reduction)
				var ram: float = cv.ram_damage
				if cv.thorns > 0.0:
					ram += cv.thorns * ENEMY_CONTACT_DAMAGE[kind] * enemy_damage_mult(round)
				if ram > 0.0 and not killed:
					_hit_enemy(i, ram, vidx, true)
					killed = enemy_hp[i] <= 0.0

		np.x = clampf(np.x, a_min.x, a_max.x)
		np.y = clampf(np.y, a_min.y, a_max.y)
		enemy_pos[i] = np
		enemy_vel[i] = vel

		if kind == SPITTER and bk >= 0 and enemy_hp[i] > 0.0 and (tick + enemy_id[i] * 7) % SPIT_PERIOD == 0:
			_spit(np, vehicles[_av_idx[bk]])

	for vidx in vehicles.size():
		var c0: float = _contact[vidx * 3]
		var c1: float = _contact[vidx * 3 + 1]
		var c2: float = _contact[vidx * 3 + 2]
		var ctot: float = c0 + c1 + c2
		if ctot > 0.0:
			var dom: int = SRC_MITE
			if c1 > c0 and c1 >= c2:
				dom = SRC_BOULDER
			elif c2 > c0 and c2 > c1:
				dom = SRC_SPITTER
			_damage_vehicle(vehicles[vidx], ctot, -1, false, dom, PackedFloat32Array([c0, c1, c2]))


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
func _contact_hit(kind: int, armor: float, reduction: float = 0.0) -> float:
	var d: float = ENEMY_CONTACT_DAMAGE[kind] * enemy_damage_mult(round)
	return maxf(d - armor * CONTACT_ARMOR_FACTOR, d * ARMOR_MIN_FRACTION) * (1.0 - reduction)


## Applies damage to an enemy; credits the kill (event, scrap, kills) on death.
## The enemy stays in the arrays until _compact_enemies().
func _hit_enemy(j: int, dmg: float, killer: int, by_ram: bool = false) -> void:
	if enemy_hp[j] <= 0.0:
		return
	var applied: float = minf(dmg, enemy_hp[j])
	enemy_hp[j] -= dmg
	var kv: SimVehicle = vehicles[killer] if (killer >= 0 and killer < vehicles.size()) else null
	if kv != null:
		kv.round_stats["dealt"] = float(kv.round_stats["dealt"]) + applied
		kv.match_stats["dmg_dealt"] = float(kv.match_stats["dmg_dealt"]) + applied
	if enemy_hp[j] > 0.0:
		return
	var kind: int = enemy_kind[j]
	_emit("kill", enemy_pos[j], killer, kind)
	if kv != null:
		kv.scrap_frac += float(ENEMY_SCRAP[kind]) * kv.scrap_mult
		var whole: int = int(kv.scrap_frac)
		kv.scrap += whole
		kv.scrap_frac -= float(whole)
		kv.kills += 1
		_note_scrap(kv, whole)
		kv.round_stats["kills"] = int(kv.round_stats["kills"]) + 1
		kv.match_stats["kills"] = int(kv.match_stats["kills"]) + 1
		if by_ram:
			kv.match_stats["ram_kills"] = int(kv.match_stats["ram_kills"]) + 1


## Books `n` scrap as earned in the round and match stats (the scrap itself is already added).
func _note_scrap(v: SimVehicle, n: int) -> void:
	if n <= 0:
		return
	v.round_stats["scrap_earned"] = int(v.round_stats["scrap_earned"]) + n
	v.match_stats["scrap_earned"] = int(v.match_stats["scrap_earned"]) + n


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
	_spawn_accum += spawn_rate_at(round, combat_duration(round) - phase_ticks_left) * DT
	if _spitter_gap > 0:
		_spitter_gap -= 1
	if _spawn_accum < 1.0:
		return
	var area: Rect2 = spawn_area()
	var n_boulder: int = 0
	var n_spitter: int = 0
	for i in enemy_count:
		var ek: int = enemy_kind[i]
		if ek == BOULDER:
			n_boulder += 1
		elif ek == SPITTER:
			n_spitter += 1
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		var side: int = rng.randi() % 4
		var t: float = rng.randf()
		var kind: int = MITE
		if rng.randf() < boulder_chance(round):
			kind = BOULDER
		elif round >= SPITTER_MIN_ROUND and rng.randf() < spitter_chance(round):
			kind = SPITTER  # no extra rng draw before SPITTER_MIN_ROUND: early rounds are unchanged
		if kind == BOULDER:
			if n_boulder >= boulder_cap(round):
				kind = MITE
			else:
				n_boulder += 1
		elif kind == SPITTER:
			if _spitter_gap > 0 or n_spitter >= spitter_cap(round):
				kind = MITE
			else:
				n_spitter += 1
				_spitter_gap = SPITTER_SPAWN_GAP
				if side == _last_spitter_side:  # spread: never two spitters in a row from the same edge
					side = (side + 1 + rng.randi() % 3) % 4
				_last_spitter_side = side
		spawn_enemy(kind, _edge_pos(area, side, t))


## Where aliens spawn: the bounding box of the alive vehicles grown by SPAWN_REACH, clipped to the
## arena (the whole arena when no vehicle is alive).
func spawn_area() -> Rect2:
	var box := Rect2()
	var any: bool = false
	for v in vehicles:
		if not v.alive:
			continue
		if any:
			box = box.expand(v.pos)
		else:
			box = Rect2(v.pos, Vector2.ZERO)
			any = true
	if not any:
		return ARENA
	return box.grow_individual(SPAWN_REACH.x, SPAWN_REACH.y, SPAWN_REACH.x, SPAWN_REACH.y).intersection(ARENA)


## Point on edge `side` (0 top, 1 bottom, 2 left, 3 right) of `area` at fraction `t` along it.
static func _edge_pos(area: Rect2, side: int, t: float) -> Vector2:
	match side:
		0:
			return Vector2(area.position.x + t * area.size.x, area.position.y + SPAWN_INSET)
		1:
			return Vector2(area.position.x + t * area.size.x, area.end.y - SPAWN_INSET)
		2:
			return Vector2(area.position.x + SPAWN_INSET, area.position.y + t * area.size.y)
	return Vector2(area.end.x - SPAWN_INSET, area.position.y + t * area.size.y)


# ---------------------------------------------------------------- vehicles

func _update_vehicles() -> void:
	var lo := ARENA.position + Vector2(SimVehicle.RADIUS, SimVehicle.RADIUS)
	var hi := ARENA.end - Vector2(SimVehicle.RADIUS, SimVehicle.RADIUS)
	for v in vehicles:
		if not v.alive:
			continue
		if v.protect_ticks > 0:
			v.protect_ticks -= 1
		if v.invuln_ticks > 0:
			v.invuln_ticks -= 1
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
				_damage_vehicle(vb, va.ram_damage, va.id, true, SRC_RAM)
			if vb.ram_damage > 0.0:
				_damage_vehicle(va, vb.ram_damage, vb.id, true, SRC_RAM)


## Applies damage to a vehicle (armour first unless `use_armor` is false). Invulnerable vehicles
## (`invuln_ticks` > 0) take nothing. `src` is the damage source (SRC_*; default: SRC_PLAYER for a rival
## attacker, else SRC_MITE) and `split` the contact damage per enemy kind (stats only). On destruction:
## fuel loss (the lowest-fuel player loses less), a respawn timer (or elimination at 0 fuel) and, for a
## player kill, kill count, scrap bounty, fuel steal and a "kill" event; always a "vehicle_destroyed" event.
func _damage_vehicle(v: SimVehicle, dmg: float, attacker: int, use_armor: bool = true, src: int = -1, split: PackedFloat32Array = PackedFloat32Array()) -> void:
	if not v.alive or v.invuln_ticks > 0:
		return
	var by_player: bool = attacker >= 0 and attacker != v.id and attacker < vehicles.size()
	if src < 0:
		src = SRC_PLAYER if by_player else SRC_MITE
	if use_armor and v.armor > 0.0:
		dmg = maxf(dmg - v.armor, dmg * ARMOR_MIN_FRACTION)
	if v.protect_ticks > 0:
		dmg *= PVP_PROTECT_FACTOR
	var av: SimVehicle = vehicles[attacker] if by_player else null
	if av != null and av.target_kind == 2 and av.target_id == v.id:  # deliberate attack, not a stray shot
		v.retaliate_id = attacker
		v.retaliate_ticks = RETALIATE_TICKS
	var applied: float = minf(dmg, v.hp)
	v.hp -= dmg
	_note_taken(v, applied, src, attacker if by_player else -1, split)
	if av != null:
		av.round_stats["dealt"] = float(av.round_stats["dealt"]) + applied
		av.round_stats["dealt_players"] = float(av.round_stats["dealt_players"]) + applied
		av.match_stats["dmg_dealt"] = float(av.match_stats["dmg_dealt"]) + applied
	if v.hp > 0.0:
		return
	v.hp = 0.0
	v.alive = false
	v.vel = Vector2.ZERO
	v.target_kind = 0
	v.ram_damage = 0.0
	var killer_id: int = attacker if by_player else -1
	var killer_kind: int = -1
	if src <= SRC_SPITTER:
		killer_kind = src
	elif src == SRC_ACID:
		killer_kind = SPITTER
	(v.round_stats["deaths"] as Array).append({
		"t": combat_duration(round) - phase_ticks_left, "cause": SRC_NAMES[clampi(src, 0, SRC_NAMES.size() - 1)],
		"src": src, "killer": killer_id, "killer_kind": killer_kind,
	})
	v.match_stats["deaths"] = int(v.match_stats["deaths"]) + 1
	_emit("vehicle_destroyed", v.pos, v.id, -1, {"cause": src, "killer": killer_id})
	var base_loss: int = FUEL_LOSS_PVP if by_player else FUEL_LOSS
	if is_underdog(v):
		base_loss = roundi(float(base_loss) * UNDERDOG_FUEL_FACTOR)
	var lost: int = mini(base_loss, v.fuel)
	v.fuel -= lost
	v.round_stats["fuel_lost"] = int(v.round_stats["fuel_lost"]) + lost
	if v.fuel <= 0:
		v.eliminated = true
		v.respawn_ticks = 0
	else:
		v.respawn_ticks = RESPAWN_TICKS
	if by_player:
		_reward_player_kill(av, v, src, lost)


## Books `hp` of damage taken from `src` / `attacker` in the round stats of `v`. `split` (contact damage
## per enemy kind) spreads one contact total over mite / boulder / spitter.
func _note_taken(v: SimVehicle, hp: float, src: int, attacker: int, split: PackedFloat32Array) -> void:
	if hp <= 0.0:
		return
	var taken: Dictionary = v.round_stats["taken"]
	if split.size() == 3:
		var tot: float = split[0] + split[1] + split[2]
		if tot > 0.0:
			taken["mite"] = float(taken["mite"]) + hp * split[0] / tot
			taken["boulder"] = float(taken["boulder"]) + hp * split[1] / tot
			taken["spitter"] = float(taken["spitter"]) + hp * split[2] / tot
		return
	match src:
		SRC_MITE:
			taken["mite"] = float(taken["mite"]) + hp
		SRC_BOULDER:
			taken["boulder"] = float(taken["boulder"]) + hp
		SRC_SPITTER:
			taken["spitter"] = float(taken["spitter"]) + hp
		SRC_ACID:
			taken["acid"] = float(taken["acid"]) + hp
		_:
			taken["rival"] = float(taken["rival"]) + hp
			if attacker >= 0:
				var tp: Dictionary = v.round_stats["taken_players"]
				tp[attacker] = float(tp.get(attacker, 0.0)) + hp


## Everything a player kill pays the killer: kill count, scrap bounty (x3 on the leader), fuel steal
## (+ a leader bonus) and third-party protection. Repeat kills of the same victim in a round pay
## REPEAT_KILL_FACTORS (100% / 50% / 0%). Also the "kill" feed event and the match stats.
func _reward_player_kill(av: SimVehicle, v: SimVehicle, src: int, fuel_lost: int) -> void:
	var n: int = int(av.kill_counts.get(v.id, 0))
	av.kill_counts[v.id] = n + 1
	var factor: float = REPEAT_KILL_FACTORS[mini(n, REPEAT_KILL_FACTORS.size() - 1)]
	var is_leader: bool = v.peer_id == leader_peer
	av.kills += 1
	av.round_stats["kills_players"] = int(av.round_stats["kills_players"]) + 1
	var ms: Dictionary = av.match_stats
	ms["player_kills"] = int(ms["player_kills"]) + 1
	if src == SRC_RAM:
		ms["ram_kills"] = int(ms["ram_kills"]) + 1
	var bounty: int = roundi(float(PVP_KILL_SCRAP * (LEADER_BOUNTY_MULT if is_leader else 1)) * factor)
	av.scrap += bounty
	_note_scrap(av, bounty)
	if not av.eliminated:
		var steal: int = roundi(float(mini(FUEL_STEAL, fuel_lost) + (LEADER_FUEL_BONUS if is_leader else 0)) * factor)
		var gain: int = clampi(steal, 0, maxi(START_FUEL - av.fuel, 0))
		av.fuel += gain
		av.round_stats["fuel_gained"] = int(av.round_stats["fuel_gained"]) + gain
	if av.alive:
		av.protect_ticks = PVP_PROTECT_TICKS
	# Top victim / nemesis (ties keep the earlier holder).
	av.victim_counts[v.id] = int(av.victim_counts.get(v.id, 0)) + 1
	if int(av.victim_counts[v.id]) > int(ms["top_victim_n"]):
		ms["top_victim"] = v.id
		ms["top_victim_n"] = av.victim_counts[v.id]
	v.killed_by_counts[av.id] = int(v.killed_by_counts.get(av.id, 0)) + 1
	if int(v.killed_by_counts[av.id]) > int(v.match_stats["nemesis_n"]):
		v.match_stats["nemesis"] = av.id
		v.match_stats["nemesis_n"] = v.killed_by_counts[av.id]
	_emit("kill", v.pos, av.id, -1, {"victim": v.id, "weapon": WEAPON_RAM if src == SRC_RAM else _hit_weapon})


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
			spawn_projectile(muzzle, dir * speed, ttl, dmg, v.id, pierce, splash, Cards.weapon_kind_index(str(w["kind"])))
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
			if not v.alive or v.id == owner or v.invuln_ticks > 0 or (owner >= 0 and not pvp):
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
			_hit_weapon = proj_weapon[i] if proj_weapon[i] != 255 else -1
			_damage_vehicle(hv, dmg, owner, true, SRC_ACID if owner < 0 else SRC_PLAYER)
			_hit_weapon = -1
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
			proj_weapon[i] = proj_weapon[n]
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
		proj_weapon.resize(n)
		proj_count = n


## Damages every living enemy within `radius` of `center` except index `skip`.
func _splash_damage(center: Vector2, radius: float, dmg: float, owner: int, skip: int) -> void:
	var cnt: int = _hash.query_circle(center, radius, enemy_pos, _splash_buf, STALE_MARGIN)
	for q in cnt:
		var j: int = _splash_buf[q]
		if j != skip:
			_hit_enemy(j, dmg, owner)
