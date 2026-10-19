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
const GLASS := 3  ## Glass Wings, a flyer (see species.gd)
const BROOD := 4  ## Brood Carrier: bursts into mites
const SHRIEKER := 5  ## Shrieker: heals and hastens nearby aliens
const BOSS_A := 6  ## Tripod Queen (see bosses.gd); all boss kinds are >= BOSS_A
const BOSS_B := 7  ## Shard Colossus
const BOSS_SHARD := 8  ## a Colossus split-off (phase 3)
# Per enemy kind: mite, boulder, spitter, glass wings, brood carrier, shrieker, then the bosses.
const ENEMY_RADIUS: PackedFloat32Array = [6.0, 14.0, 8.0, 7.0, 17.0, 10.0, 36.0, 34.0, 22.0]
const ENEMY_SPEED: PackedFloat32Array = [74.0, 35.0, 55.0, 190.0, 28.0, 50.0, 34.0, 48.0, 70.0]  # px/s (glass: dive speed; bosses: base speed, Bosses.speed_of() adds phase / enrage)
const ENEMY_HP: PackedFloat32Array = [4.0, 80.0, 20.0, 7.0, 70.0, 14.0, 1.0, 1.0, 1.0]  # bosses: hp is set by Bosses (see enemy_max_hp_of)
const ENEMY_CONTACT_DAMAGE: PackedFloat32Array = [0.15, 1.5, 0.6, 1.0, 0.8, 0.3, 2.5, 3.0, 1.6]  # per tick while touching (glass: only while diving)
const ENEMY_SCRAP: PackedInt32Array = [1, 5, 2, 2, 4, 3, 0, 0, 3]
const MAX_ENEMY_RADIUS := 36.0

# Damage sources (stats, "vehicle_destroyed" cause). 0..2 equal the enemy kind (contact damage).
const SRC_MITE := 0
const SRC_BOULDER := 1
const SRC_SPITTER := 2  # spitter body contact
const SRC_ACID := 3
const SRC_RAM := 4  # a rival's ram / spikes
const SRC_PLAYER := 5  # a rival's shots
const SRC_BOSS := 6  # a boss: contact, shells, charges
const SRC_GLASS := 7  # glass wings diving into a rig
const SRC_BROOD := 8  # brood carrier body contact
const SRC_SHRIEKER := 9  # shrieker body contact
const SRC_NAMES: PackedStringArray = ["mite", "boulder", "spitter", "acid", "ram", "player", "boss", "glass", "brood", "shrieker"]
const CONTACT_KINDS := 6  # enemy kinds that deal contact damage as a "regular" alien (bookkeeping in _update_enemies)
const CONTACT_SRC: PackedInt32Array = [SRC_MITE, SRC_BOULDER, SRC_SPITTER, SRC_GLASS, SRC_BROOD, SRC_SHRIEKER]
const WEAPON_RAM := 4  # "weapon" of a player kill by ramming (Cards.WEAPON_KINDS holds 0..3)

# Ballistics ammo and weapon heat (tech tree v2.3, section 4.1). Ammo ids, bits and scaling: Ammo.
const BURN_TICKS := 60  # 2 s
const BURN_FRACTION := 0.25  # fire ammo: this fraction of the hit as damage over BURN_TICKS
const BURN_SPREAD_PERIOD := 15  # napalm: a burning enemy ignites its neighbours every 0.5 s
const BURN_SPREAD_DECAY := 0.85  # burn dps multiplier per jump
const SHARD_COUNT := 3
const SHARD_DAMAGE := 0.4  # of the killing hit
const SHARD_SPEED := 260.0
const SHARD_TTL := 0.18
const SCATTER_EVERY := 4  # scatter packing: every 4th shot of a non-shotgun
const SCATTER_PELLETS := 3
const SCATTER_DAMAGE := 0.4
const SCATTER_SPREAD := 0.3
const JAM_FIRE_TICKS := 120  # hot loads: 4 s of continuous fire ...
const JAM_PAUSE_TICKS := 24  # ... then 0.8 s of stutter
const OVERHEAT_FIRE_TICKS := 180  # glowing barrels: 6 s ... 
const OVERHEAT_PAUSE_TICKS := 30  # ... then 1 s
const HEAT_COOL := 2  # heat ticks lost per tick without fire intent
const EMBER_RADIUS := 14.0
const EMBER_TICKS := 60  # 2 s
const EMBER_DPS := 20.0
const EMBER_BURN_DPS := 5.0  # the burn an ember zone starts
# Ground zones (zone_* arrays). Later tech stages reuse them for oil, smoke and fire.
const ZONE_EMBER := 0
const ZONE_OIL := 1
const ZONE_SMOKE := 2
const ZONE_FIRE := 3
const EVO_FIRE_EVERY := 5  # Inferno Spout: one fire zone per this many shots (6 per second at the base rate)
const EVO_FIRE_RADIUS := 16.0
const EVO_FIRE_TICKS := 45  # 1.5 s
const EVO_BURN_MULT := 2.0  # Inferno Spout burn dps = hit damage x this
const EVO_FLAMER_IDX := 3  # Cards.weapon_kind_index("flamer")
const MAX_ZONES := 64

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
const FUEL_DRAIN_START_ROUND := 7  # PVP_START_ROUND + 3: multiplayer only, from the workshop after this round
const FUEL_DRAIN_BASE := 6
const FUEL_DRAIN_LETHAL_ROUND := 18  # from the workshop after this round the drain can eliminate every rig except the one with the most fuel
const FUEL_DRAIN_ROUNDS_PER_STEP := 3  # the drain grows by 1 every this many rounds past the start
const PVP_PROTECT_TICKS := 60  # 2 s of third-party protection after a player kill
const PVP_PROTECT_FACTOR := 0.5  # damage multiplier while protected
const RETALIATE_TICKS := 60  # return fire: a vehicle shoots back at a player that hurt it for 2 s (any doctrine)

const SPAWN_RATE_START := 3.0  # base enemies / s (round 1), multiplied by the wave curve and spawn_rate_mult(r)
# Wave curve (fractions of the combat length, the lull is absolute): build-up, surge, lull, final surge.
const WAVE_SURGE_START := 0.35
const WAVE_SURGE_END := 0.5
const WAVE_LULL_TICKS := 180  # 6 s
const WAVE_BUILD_FROM := 0.8  # multiplier at the start of the round, rising to 1.0 at the first surge
const WAVE_SURGE := 2.2
const WAVE_LULL := 0.3
const WAVE_FINAL_FROM := 2.0  # final surge ramps from this to WAVE_FINAL_TO until the round ends
const WAVE_FINAL_TO := 2.8
const SURGE_WARN_TICKS := 60  # a "surge" event this long before each surge starts
const PACK_START := 3.0  # mites spawn in packs: 3 in round 1 ...
const PACK_PER_ROUND := 0.6
const PACK_MAX := 8  # ... up to 8
const PACK_RADIUS := 24.0  # a pack clusters within this of one edge point
const MITE_SCRAP_START := 0.19  # scrap per mite kill (fractional, carried): many more mites must not inflate the economy
const MITE_SCRAP_PER_ROUND := 0.009
const MITE_SCRAP_MIN := 0.06
const BOULDER_CHANCE := 0.02  # round 1 (per spawned alien; the horde spawns ~2-3x as fast as before, so this is lower)
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
const SPIT_WARN_TICKS := 30  # radar array: a spitter is flagged this long before it spits

# Armour shedding (scrap armour) and dodge.
const SHED_HP_FRACTION := 0.15  # a hit of more than this share of max hp tears off a plate
const PLATE_DAMAGE := 20.0
const PLATE_SPEED := 300.0
const PLATE_TTL := 0.5

# Round loop (docs/architecture.md, "Round loop contract").
const PHASE_COMBAT := 0
const PHASE_WORKSHOP := 1
const PHASE_GAME_OVER := 2
const PHASE_DEPLOY := 3  # pre-match doctrine setup (begin_deploy); ends in round 1 combat

const COMBAT_TICKS := 2100  # 70 s
const COMBAT_TICKS_EARLY := 1350  # 45 s, rounds 1 and 2
const EARLY_ROUNDS := 2
const WORKSHOP_TICKS := 1350  # 45 s
const DEPLOY_TICKS := 900  # 30 s
const FAST_DEPLOY_TICKS := 60
const FAST_COMBAT_TICKS := 120  # world.fast_rounds (tests, screenshots)
const FAST_WORKSHOP_TICKS := 81  # scaled with the workshop: 45 * 45 / 25

const START_FUEL := 100
const FUEL_LOSS := 20  # destroyed by aliens
const FUEL_LOSS_PVP := 30  # destroyed by another player
const RESPAWN_TICKS := 90  # 3 s
const INTEREST_PER := 10  # +1 scrap per this much scrap held at the end of a round (10%)
const INTEREST_CAP_PER_ROUND := 2  # interest cap = Vehicle.interest_cap (5 + salvage tech) + this x round
const REROLL_COST_START := 6
const RETREAT_EVENT_CAP := 150  # at most this many "retreat" events per round end

# Per-round enemy scaling (round 1 = x1).
const HP_SCALE_PER_ROUND := 0.09
const HP_SCALE_QUAD := 0.005  # late-game term: the hive outgrows a linear power curve
const SPAWN_SCALE_PER_ROUND := 0.35
const BOULDER_CHANCE_PER_ROUND := 0.013
const BOULDER_CHANCE_MAX := 0.2
const DAMAGE_SCALE_PER_ROUND := 0.06
# Early-round easing (playtest: the first waves were too strong). Spawn rate and enemy damage start at this
# share in round 1 and rise linearly to full strength in round EASE_END_ROUND; later rounds are unchanged.
const EASE_END_ROUND := 7
const SPAWN_EASE_START := 1.0  # no spawn easing: early rounds are already mass, not hp
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
		if tick == 0 and round == 1:
			if phase == PHASE_COMBAT:
				phase_ticks_left = combat_duration(1)
			elif phase == PHASE_DEPLOY:
				phase_ticks_left = deploy_duration()

var enemy_count: int = 0
var enemy_id: PackedInt32Array = PackedInt32Array()
var enemy_kind: PackedByteArray = PackedByteArray()
var enemy_pos: PackedVector2Array = PackedVector2Array()
var enemy_vel: PackedVector2Array = PackedVector2Array()  # px/s
var enemy_hp: PackedFloat32Array = PackedFloat32Array()
## Burning (fire ammo, napalm, ember zones): ticks left (> 0 = burning), damage per second, owner vehicle id.
var enemy_burn_ticks: PackedInt32Array = PackedInt32Array()
var enemy_burn_dps: PackedFloat32Array = PackedFloat32Array()
var enemy_burn_owner: PackedInt32Array = PackedInt32Array()
## Alien status effects, packed per enemy: bits 0..7 stun ticks (EMP), 8..15 slow ticks (oil), 16..23 blind
## ticks (smoke: the alien lost its target). See stun_enemy().
var enemy_status: PackedInt32Array = PackedInt32Array()
## Tick of the last ram effect on each enemy (throttle: Mobility.RAM_FX_TICKS). Host-side only.
var enemy_ram_tick: PackedInt32Array = PackedInt32Array()

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
var proj_ammo: PackedByteArray = PackedByteArray()  # Ammo bit mask loaded when fired (0 = plain)

## Ground zones, capped at MAX_ZONES: centre, radius px, ZONE_* kind, ticks left, owner vehicle id.
var zone_count: int = 0
var zone_pos: PackedVector2Array = PackedVector2Array()
var zone_radius: PackedFloat32Array = PackedFloat32Array()
var zone_kind: PackedByteArray = PackedByteArray()
var zone_ttl: PackedInt32Array = PackedInt32Array()
var zone_owner: PackedInt32Array = PackedInt32Array()

var events: Array[Dictionary] = []

# Boss rounds (see bosses.gd). boss_first is derived from the seed at construction; the rest is per round.
var boss_forced: bool = false  ## tests / scenarios: bosses come even with spawning_enabled = false
var boss_first: int = 0  ## which boss opens the schedule (0 = BOSS_A, 1 = BOSS_B); they alternate every boss round
var boss_round: int = 0  ## round the boss fields below belong to (reset lazily by Bosses.tick)
var boss_kind: int = -1  ## this round's boss kind (BOSS_A / BOSS_B), -1 = not a boss round
var boss_state: int = 0  ## Bosses.ST_*
var boss_phase: int = 0  ## 0 = not spawned, 1..3
var boss_enraged: bool = false
var boss_max_hp: float = 0.0  ## full hp of the boss (shared pool; a Colossus shard has 1/6 of it)
var boss_hp_frac: float = 0.0  ## remaining hp of all boss bodies / boss_max_hp
var boss_warn_left: int = 0  ## ticks until the spawn while warned
var boss_spawn_pos: Vector2 = Vector2.ZERO
var boss_marks: Array[Dictionary] = []  ## telegraph markers {k, pos, pos2, r, left, total} (Bosses.MARK_*)
var boss_ents: Dictionary = {}  ## host only: enemy id -> attack state of a boss body
var boss_dealt: Dictionary = {}  ## host only: vehicle id -> damage dealt to the boss this round
var boss_dmg_taken: float = 0.0  ## host only: damage the boss's attacks did to vehicles this round
var boss_ticks: int = 0  ## host only: ticks since the spawn
var boss_log: Array[Dictionary] = []  ## host only, diagnostics for the bot league

## Set false to stop the timed enemy spawner (tests, scenarios).
# Hive signature (see species.gd): first round of Glass Wings / Brood Carrier / Shrieker in this match (0 = not in it).
# Derived from the seed at construction, synced in the snapshot header.
var hive_first: PackedInt32Array = PackedInt32Array([0, 0, 0])
var brood_pending: Array = []  ## host only: [release tick, pos, mites] of burst brood carriers

var spawning_enabled: bool = true
var next_enemy_id: int = 0

## Shared scratch buffer for VehicleAI queries.
var ai_buf: PackedInt32Array = PackedInt32Array()

var _hash: SpatialHash
var _spawn_accum: float = 0.0
var _hit_weapon: int = -1  # weapon kind index of the projectile being resolved (kill feed)
var _hit_ammo: int = 0  # Ammo mask of the projectile being resolved (shrapnel on kill)
var _hit_dmg: float = 0.0  # its damage
var _hit_scale: float = 1.0  # its ammo effect scale
var _in_splash: bool = false  # inside _splash_damage (scrap storm counts splash kills)
var _burning: bool = false  # some enemy may be burning (skips the burn loop otherwise)
var _pending_proj: Array = []  # projectiles to add once the projectile loop is done: [pos, vel, ttl, dmg, owner, weapon, ammo mask]
var _spitter_gap: int = 0
var _fire_dmg: bool = false  # the damage being applied comes from fire (ember / fire zones): a brood carrier killed by it dies childless
var _last_spitter_side: int = -1
var _query_buf: PackedInt32Array = PackedInt32Array()
var _splash_buf: PackedInt32Array = PackedInt32Array()
var _av_pos: PackedVector2Array = PackedVector2Array()  # alive vehicle positions (enemy phase)
var _av_idx: PackedInt32Array = PackedInt32Array()
var _ch_pos: PackedVector2Array = PackedVector2Array()  # what aliens chase: vehicles outside smoke, plus decoys
var _ch_idx: PackedInt32Array = PackedInt32Array()  # vehicle index; a decoy is -1 - vehicle index
var _jam_pos: PackedVector2Array = PackedVector2Array()  # alive jammer rigs (aliens near them slow down)
var _jam_r2: float = 0.0
var _boss_contact: PackedFloat32Array = PackedFloat32Array()  # per vehicle, boss contact damage this tick
var _contact: PackedFloat32Array = PackedFloat32Array()  # per vehicle x 3 enemy kinds, damage this tick


func _init(p_seed: int) -> void:
	seed = p_seed
	rng.seed = p_seed
	_hash = SpatialHash.new(ARENA, HASH_CELL)
	phase_ticks_left = combat_duration(1)
	boss_first = Bosses.first_for_seed(p_seed)
	hive_first = Species.signature(p_seed)


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


## Applies a (pre-validated) command from `peer_id`. Card / tech / ready / set_ability / accept_contract / reserve_card / scrap_card
## commands only work in the workshop, use_ability only in combat; set_drive, set_target, set_rules, set_ammo and set_weapon_target work in every phase. Unknown or illegal commands are ignored.
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
			if value2 in Doctrine.RIG_TARGETS:
				v.doctrine["target"] = value2
		"set_rules":  # {"scope": "rig" | weapon kind, "value": Doctrine text form}
			var scope: String = str(cmd.get("scope", ""))
			if scope == Doctrine.SCOPE_RIG or Doctrine.is_weapon_scope(scope):
				var parsed: Variant = Doctrine.parse(str(cmd.get("value", "")), scope)
				if parsed != null and Doctrine.rules_allowed(v, parsed):
					Doctrine.set_rules(v, scope, parsed)
		"set_ammo":  # {"scope": weapon kind, "value": ammo id}; needs the ammo unlocked, any phase
			Ammo.select(v, str(cmd.get("scope", "")), str(cmd.get("value", "")))
		"use_ability":  # {"value": ability id}; combat only, casts now if equipped and ready
			if phase == PHASE_COMBAT and v.alive and not v.eliminated:
				Abilities.cast(self, v, str(cmd.get("value", "")))
		"set_ability":  # {"slot": 0..1, "value": ability id}; workshop only, needs the ability unlocked
			if _can_shop(v):
				Abilities.set_slot(v, _integral(cmd.get("slot")), str(cmd.get("value", "")))
		"set_weapon_target":  # {"scope": weapon kind, "value": Doctrine.WEAPON_TARGETS}
			Doctrine.set_weapon_target(v, str(cmd.get("scope", "")), str(cmd.get("value", "")))
		"pick_card":
			if _can_shop(v) and not v.picked:
				var idx: int = _integral(cmd.get("value"))
				if idx >= 0 and idx < v.offers.size() and Cards.grant(v, v.offers[idx]):
					if v.reserved_card == v.offers[idx]:
						v.reserved_card = ""
					v.picked = true
					v.offers = []
		"reroll":
			if _can_shop(v) and not v.picked and v.scrap >= v.reroll_cost:
				v.scrap -= v.reroll_cost
				v.reroll_cost += 1
				v.offers = Cards.roll_offers(rng, v, maxi(Cards.OFFER_COUNT, v.offers.size()), round, v.offers)
		"buy_tech":
			if _can_shop(v):
				Tech.buy(v, str(cmd.get("value", "")), round)
		"respec_tech":  # {"from": owned choice id, "value": unowned choice of the same branch and tier}
			if _can_shop(v):
				Tech.respec(v, str(cmd.get("from", "")), str(cmd.get("value", "")), round)
		"accept_contract":  # {"value": offer index}; workshop only, needs offers (Salvage.accept)
			if _can_shop(v):
				Salvage.accept(v, _integral(cmd.get("value")))
		"reserve_card":  # {"value": offer index}; haggler, workshop only (Salvage.reserve)
			if _can_shop(v):
				Salvage.reserve(v, _integral(cmd.get("value")))
		"scrap_card":  # {"value": card id}; scrap press, workshop only (Salvage.scrap_card)
			if _can_shop(v):
				Salvage.scrap_card(v, str(cmd.get("value", "")))
		"ready":
			if _can_shop(v) or (phase == PHASE_DEPLOY and not v.eliminated):
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
## FUEL_DRAIN_START_ROUND): 6, growing by 1 every 3 rounds (7..9: 6, 10..12: 7, ...).
static func fuel_drain_for_round(r: int) -> int:
	if r < FUEL_DRAIN_START_ROUND:
		return 0
	return FUEL_DRAIN_BASE + (r - FUEL_DRAIN_START_ROUND) / FUEL_DRAIN_ROUNDS_PER_STEP


## Interest cap at the current round: the vehicle's own cap (5 + salvage tech) + 2 per round (hoarder: +10 and 6 per round).
func interest_cap_for(v: SimVehicle) -> int:
	if Salvage.is_hoarder(v):
		return v.interest_cap + Salvage.HOARDER_CAP_BONUS + Salvage.HOARDER_CAP_PER_ROUND * round
	return v.interest_cap + INTEREST_CAP_PER_ROUND * round


## Interest a vehicle would earn now: 10% of held scrap (INTEREST_PER; 12% for the hoarder), capped at interest_cap_for().
func interest_for(v: SimVehicle) -> int:
	if Salvage.is_hoarder(v):
		return mini(v.scrap * Salvage.HOARDER_PCT / 100, interest_cap_for(v))
	return mini(v.scrap / INTEREST_PER, interest_cap_for(v))


## Fresh per-round stats (see docs/architecture.md, "Stats").
static func new_round_stats(r: int) -> Dictionary:
	return {
		"round": r,
		"taken": {"mite": 0.0, "boulder": 0.0, "spitter": 0.0, "acid": 0.0, "rival": 0.0, "glass": 0.0, "brood": 0.0, "shrieker": 0.0},
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


## Full hp of enemy index `j` (a boss shares one pool: Bosses.max_hp_for, a Colossus shard has a sixth of it).
func enemy_max_hp_of(j: int) -> float:
	var k: int = enemy_kind[j]
	if k < BOSS_A:
		return enemy_max_hp(k, round)
	return boss_max_hp * (Bosses.SPLIT_HP_FRAC if k == BOSS_SHARD else 1.0)


## True in the 30 ticks before the spitter with stable id `id` spits (every SPIT_PERIOD ticks, staggered by id).
## Pure in (tick, id), so clients with the radar array flag spitters from the synced tick alone.
static func spit_warning(t: int, id: int) -> bool:
	return (t + id * 7) % SPIT_PERIOD >= SPIT_PERIOD - SPIT_WARN_TICKS


## Stuns enemy index `j` for `ticks` (EMP): it neither moves nor attacks. Keeps the longer of two stuns.
func stun_enemy(j: int, ticks: int) -> void:
	if enemy_kind[j] >= BOSS_A:  # bosses only slow down
		_status_enemy(j, 8, Bosses.stun_to_slow(ticks))
		return
	var st: int = enemy_status[j]
	if (st & 255) < ticks:
		enemy_status[j] = (st & ~255) | clampi(ticks, 0, 255)


## Slows (oil, shift 8) or blinds (smoke, shift 16) enemy index `j`; keeps the longer effect.
func _status_enemy(j: int, shift: int, ticks: int) -> void:
	var st: int = enemy_status[j]
	if ((st >> shift) & 255) < ticks:
		enemy_status[j] = (st & ~(255 << shift)) | (ticks << shift)


func combat_duration(r: int) -> int:
	if fast_rounds:
		return FAST_COMBAT_TICKS
	return COMBAT_TICKS_EARLY if r <= EARLY_ROUNDS else COMBAT_TICKS


func deploy_duration() -> int:
	return FAST_DEPLOY_TICKS if fast_rounds else DEPLOY_TICKS


## Starts the pre-match deploy phase (doctrine setup, ends in round 1 combat). Only valid at tick 0 of
## round 1, before anything stepped. `ticks` < 0 = the default duration. A plain SimWorld starts in combat.
func begin_deploy(ticks: int = -1) -> void:
	if tick != 0 or round != 1:
		return
	phase = PHASE_DEPLOY
	phase_ticks_left = ticks if ticks >= 0 else deploy_duration()
	for v in vehicles:
		v.ready = false


func workshop_duration() -> int:
	return FAST_WORKSHOP_TICKS if fast_rounds else WORKSHOP_TICKS


## Wave multiplier `ticks_in` ticks into a combat of `dur` ticks: build-up (0.8 -> 1.0), surge, a ~6 s lull
## and a final surge that runs until the end-of-round retreat.
static func wave_mult(ticks_in: int, dur: int) -> float:
	var s1: int = int(WAVE_SURGE_START * float(dur))
	var e1: int = int(WAVE_SURGE_END * float(dur))
	var lull_end: int = e1 + WAVE_LULL_TICKS
	if ticks_in < s1:
		return lerpf(WAVE_BUILD_FROM, 1.0, float(ticks_in) / float(maxi(s1, 1)))
	if ticks_in < e1:
		return WAVE_SURGE
	if ticks_in < lull_end:
		return WAVE_LULL
	return lerpf(WAVE_FINAL_FROM, WAVE_FINAL_TO, clampf(float(ticks_in - lull_end) / float(maxi(dur - lull_end, 1)), 0.0, 1.0))


## Ticks (into the combat) at which the first and the final surge start.
static func surge_starts(dur: int) -> PackedInt32Array:
	return PackedInt32Array([int(WAVE_SURGE_START * float(dur)), int(WAVE_SURGE_END * float(dur)) + WAVE_LULL_TICKS])


## Enemies per second `ticks_in` ticks into a combat of round `r`.
func spawn_rate_at(r: int, ticks_in: int) -> float:
	return SPAWN_RATE_START * wave_mult(ticks_in, combat_duration(r)) * spawn_rate_mult(r)


## Mites per pack in round `r`.
static func pack_size(r: int) -> int:
	return clampi(int(PACK_START + PACK_PER_ROUND * float(maxi(r - 1, 0))), 1, PACK_MAX)


## Scrap per mite kill in round `r` (a fraction; see ENEMY_SCRAP for the others).
static func mite_scrap(r: int) -> float:
	return maxf(MITE_SCRAP_START + MITE_SCRAP_PER_ROUND * float(maxi(r - 1, 0)), MITE_SCRAP_MIN)


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
	enemy_burn_ticks.append(0)
	enemy_burn_dps.append(0.0)
	enemy_burn_owner.append(-1)
	enemy_status.append(0)
	enemy_ram_tick.append(-1000)
	enemy_count += 1
	return id


func spawn_projectile(pos: Vector2, vel: Vector2, ttl: float, damage: float, owner: int, pierce: int = 0, splash: float = 0.0, weapon: int = 255, ammo: int = 0) -> void:
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
	proj_ammo.append(ammo & 255)
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
		PHASE_DEPLOY:
			_step_deploy()
	tick += 1


func _step_combat() -> void:
	if pvp_grace_ticks > 0:
		pvp_grace_ticks -= 1
		if pvp_grace_ticks == 0:
			_emit("pvp_on", ARENA.get_center(), -1, -1)
	update_leader()
	_update_respawns()
	Bosses.tick(self)
	Species.tick(self)
	_update_enemies()
	_update_vehicles()
	_update_projectiles()
	_update_burn()
	_update_zones()
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


## Deploy -> round 1 combat (same state as a world that started in combat; no "round" change, no events).
func _step_deploy() -> void:
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
		phase = PHASE_COMBAT
		phase_ticks_left = combat_duration(1)
		for v in vehicles:
			v.ready = false


func checksum() -> int:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var head := PackedInt64Array([tick, enemy_count, proj_count, vehicles.size(), phase, round, phase_ticks_left, winner_peer, next_enemy_id, leader_peer, pvp_grace_ticks, fuel_drain,
		boss_first, boss_kind, boss_state, boss_phase, int(boss_enraged), roundi(boss_max_hp), boss_marks.size(),
		hive_first[0], hive_first[1], hive_first[2]])
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
		vf.append(float(Doctrine.fingerprint(v).hash()))
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
			vf.append(float(v.tech_round.get(tid, 0)))
		vf.append(float(v.tech_dormant.size()))
		for tid in v.tech_dormant:
			vf.append(float(Tech.index_of(tid)))
		vf.append(float(v.respecs))
		vf.append(float(v.chassis))
		vf.append(v.momentum)
		vf.append(float(v.ab_cd[0]))
		vf.append(float(v.ab_cd[1]))
		vf.append(float(v.abilities[0].hash()))
		vf.append(float(v.abilities[1].hash()))
		vf.append(float(v.nitro_ticks))
		vf.append(float(v.sputter_ticks))
		vf.append(float(v.salvo_ticks))
		vf.append(float(v.smoke_ticks))
		vf.append(float(v.decoy_ticks))
		vf.append(v.decoy_pos.x)
		vf.append(v.decoy_pos.y)
		vf.append(float(v.rules_off_ticks))
		vf.append(float(v.nitro_count))
		vf.append(float(v.boom_cd))
		vf.append(float(v.jammed_by))
		vf.append(float(v.shed))
		vf.append(float(v.mark_id))
		vf.append(float(v.contract_kind))
		vf.append(float(v.contract_need))
		vf.append(float(v.contract_reward))
		vf.append(v.contract_prog)
		vf.append(float(v.contract_offers.size()))
		for co in v.contract_offers:
			vf.append(float(co.x * 1000000 + co.y * 1000 + co.z))
		vf.append(float(v.loan_debt))
		vf.append(float(v.loan_left))
		vf.append(float(v.reserved_card.hash()))
		vf.append(float(v.bonus_offers))
		vf.append(float(v.lucky_round))
		vf.append(float(v.saws))
		vf.append(v.raid_acc)
		vf.append(float(v.barbed_scrap))
		vf.append(float(v.storm_count))
		vf.append(v.fort_regen)
		vf.append(float(v.fort_ticks))
		vf.append(float(v.clap_cd))
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
			vf.append(float(wp.get("heat", 0)))
			vf.append(float(wp.get("jam", 0)))
			vf.append(float(wp.get("sw", 0)))
			vf.append(float(wp.get("shots", 0)))
		var ammo_kinds: Array = v.ammo.keys()
		ammo_kinds.sort()
		for ak: String in ammo_kinds:
			vf.append(float(ak.hash()))
			for aid: String in v.ammo[ak]:
				vf.append(float(aid.hash()))
		for aid2 in v.ammo_known:
			vf.append(float(aid2.hash()))
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
		proj_ammo,
		enemy_burn_ticks.to_byte_array(),
		enemy_burn_dps.to_byte_array(),
		enemy_burn_owner.to_byte_array(),
		enemy_status.to_byte_array(),
		zone_pos.to_byte_array(),
		zone_radius.to_byte_array(),
		zone_kind,
		zone_ttl.to_byte_array(),
		zone_owner.to_byte_array(),
	]:
		if part.size() > 0:  # HashingContext rejects empty updates
			ctx.update(part)
	return ctx.finish().decode_s64(0)


## Rebuilds derived structures (spatial hash, counts) after external code (e.g. a network
## snapshot) rewrote the enemy/projectile arrays.
func rebuild_derived() -> void:
	enemy_count = enemy_id.size()
	proj_count = proj_pos.size()
	var nb: int = enemy_burn_ticks.size()
	if nb != enemy_count:
		enemy_burn_ticks.resize(enemy_count)
		for i in range(nb, enemy_count):
			enemy_burn_ticks[i] = 0
	nb = enemy_burn_dps.size()
	if nb != enemy_count:
		enemy_burn_dps.resize(enemy_count)
		for i in range(nb, enemy_count):
			enemy_burn_dps[i] = 0.0
	nb = enemy_burn_owner.size()
	if nb != enemy_count:
		enemy_burn_owner.resize(enemy_count)
		for i in range(nb, enemy_count):
			enemy_burn_owner[i] = -1
	if proj_ammo.size() != proj_count:
		proj_ammo.resize(proj_count)
	if enemy_status.size() != enemy_count:
		enemy_status.resize(enemy_count)
	nb = enemy_ram_tick.size()
	if nb != enemy_count:
		enemy_ram_tick.resize(enemy_count)
		for i in range(nb, enemy_count):
			enemy_ram_tick[i] = -1000
	zone_count = zone_pos.size()
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
	Abilities.clear_effects(v)
	v.momentum = 0.0
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
	Bosses.end_round(self)
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
	var drain_keeper: SimVehicle = null  # lethal drain: this rig (most fuel, first on ties) keeps its last point
	if fuel_drain > 0 and round >= FUEL_DRAIN_LETHAL_ROUND:
		for v in vehicles:
			if not v.eliminated and (drain_keeper == null or v.fuel > drain_keeper.fuel):
				drain_keeper = v
	for v in vehicles:
		v.vel = Vector2.ZERO
		v.target_kind = 0
		v.ram_damage = 0.0
		v.ready = false
		v.picked = false
		v.protect_ticks = 0
		v.invuln_ticks = 0
		v.retaliate_ticks = 0
		v.reroll_cost = maxi(1, REROLL_COST_START - v.reroll_discount)
		v.offers = []
		Abilities.clear_effects(v)
		v.momentum = 0.0
		v.mark_id = -1
		if v.shed > 0:  # the workshop refits shed scrap plates
			v.shed = 0
			Cards.recompute(v, false, false)
		if v.eliminated:
			continue
		if not v.alive:
			_respawn(v)
			v.invuln_ticks = 0
		Salvage.settle(self, v)
		var interest: int = interest_for(v)
		v.scrap += interest
		_note_scrap(v, interest)
		v.round_stats["interest"] = interest
		Salvage.repay(self, v)
		if fuel_drain > 0:
			var floor_fuel: int = 1 if (drain_keeper == null or v == drain_keeper) else 0
			var d: int = mini(fuel_drain, maxi(v.fuel - floor_fuel, 0))
			v.fuel -= d
			v.round_stats["fuel_drained"] = d
			_emit("drain", v.pos, v.id, d)
			if v.fuel <= 0:
				v.eliminated = true
				v.respawn_ticks = 0
				continue
		v.offers = Cards.roll_offers(rng, v, Cards.OFFER_COUNT + v.bonus_offers, round, [], v.boss_rare)
		v.bonus_offers = 0
		v.boss_rare = false
		Salvage.apply_reserve(v)
		Salvage.roll(self, v)


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
		Abilities.reset_round(v)
		v.ram_fx.clear()
		v.contract_offers = []
		v.barbed_scrap = 0
		v.storm_count = 0
		v.fort_regen = 0.0
		v.fort_ticks = 0
		v.clap_cd = 0
		v.raid_acc = 0.0
		if v.alive and not v.eliminated:
			Salvage.launch_saws(self, v)
		else:
			v.saws = 0
		for w in v.weapons:
			w["cooldown"] = 0.0
			w["heat"] = 0
			w["jam"] = 0
			w["sw"] = 0


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
	enemy_burn_ticks.resize(0)
	enemy_burn_dps.resize(0)
	enemy_burn_owner.resize(0)
	enemy_status.resize(0)
	enemy_ram_tick.resize(0)
	_burning = false
	Bosses.clear_field(self)
	brood_pending.clear()
	_pending_proj.clear()
	zone_pos.resize(0)
	zone_radius.resize(0)
	zone_kind.resize(0)
	zone_ttl.resize(0)
	zone_owner.resize(0)
	zone_count = 0
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
	proj_ammo.resize(0)
	proj_count = 0
	_hash.rebuild(enemy_pos, 0)


# ---------------------------------------------------------------- enemies

func _update_enemies() -> void:
	var n: int = enemy_count
	if n == 0:
		return
	# Snapshot alive vehicles (contact), and what the aliens chase: vehicles outside smoke and phantom decoys.
	_av_pos.clear()
	_av_idx.clear()
	_ch_pos.clear()
	_ch_idx.clear()
	for vi in vehicles.size():
		var sv: SimVehicle = vehicles[vi]
		if sv.alive:
			_av_pos.append(sv.pos)
			_av_idx.append(vi)
			if sv.smoke_ticks <= 0:
				_ch_pos.append(sv.pos)
				_ch_idx.append(vi)
			if sv.decoy_ticks > 0:
				_ch_pos.append(sv.decoy_pos)
				_ch_idx.append(-1 - vi)
	var nv: int = _av_pos.size()
	var nch: int = _ch_pos.size()
	var njam: int = _jam_pos.size()
	_contact.resize(vehicles.size() * CONTACT_KINDS)
	_contact.fill(0.0)
	_boss_contact.resize(vehicles.size())
	_boss_contact.fill(0.0)

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

		# Chase the nearest target (not a rig hidden in smoke; a phantom decoy counts). Status effects: a stunned
		# alien stands still, a blinded one lost its target, oil slows it, so does a jammer field.
		var st: int = enemy_status[i]
		var stunned: bool = false
		var blind: bool = false
		var slowed: bool = false
		var hasted: bool = false
		if st != 0:
			var s_stun: int = st & 255
			var s_slow: int = (st >> 8) & 255
			var s_blind: int = (st >> 16) & 255
			stunned = s_stun > 0
			slowed = s_slow > 0
			blind = s_blind > 0
			var s_haste: int = Species.haste_of(st)
			hasted = s_haste > 0
			enemy_status[i] = maxi(s_stun - 1, 0) | (maxi(s_slow - 1, 0) << 8) | (maxi(s_blind - 1, 0) << 16) | (maxi(s_haste - 1, 0) << Species.HASTE_SHIFT)
		var best_d2: float = INF
		var bk: int = -1
		if not stunned and not blind:
			for k in nch:
				var d2: float = p.distance_squared_to(_ch_pos[k])
				if d2 < best_d2:
					best_d2 = d2
					bk = k
		var desired: Vector2 = Vector2.ZERO
		if bk >= 0:
			var dir: Vector2 = _ch_pos[bk] - p
			var dl: float = dir.length()
			if dl > 0.001:
				if kind == SPITTER:
					desired = _spitter_desire(dir / dl, dl, enemy_id[i])
				elif kind == GLASS:
					desired = Species.glass_desire(tick, enemy_id[i], p, _ch_pos[bk])
				elif kind == SHRIEKER:
					desired = Species.shrieker_desire(dir / dl, dl, enemy_id[i])
				elif kind >= BOSS_A:
					desired = Bosses.move_desire(self, i, kind, p, _ch_pos[bk])
				else:
					desired = dir * (ENEMY_SPEED[kind] / dl)
			if hasted:
				desired *= Species.HASTE_MULT
			if slowed:
				desired *= Mobility.OIL_SLOW
			for jk in njam:
				if p.distance_squared_to(_jam_pos[jk]) <= _jam_r2:
					desired *= Mobility.JAM_SLOW
					break
		var vel: Vector2 = Vector2.ZERO if stunned else enemy_vel[i].lerp(desired, 0.25)
		var is_boss: bool = kind >= BOSS_A
		if is_boss:
			var cvel: Vector2 = Bosses.charge_velocity(self, enemy_id[i])
			if cvel != Vector2.ZERO:
				vel = cvel
		var np: Vector2 = p + vel * DT

		# Mild separation from neighbours (3x3 cells, capped).
		var cx: int = clampi(int((p.x - ox) * inv), 0, cols - 1)
		var cy: int = clampi(int((p.y - oy) * inv), 0, rows - 1)
		var sep: Vector2 = Vector2.ZERO
		var seen: int = 0
		if is_boss:
			seen = MAX_SEPARATION_NEIGHBORS  # bosses are not shoved around by the swarm
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
		var flying: bool = kind == GLASS and not Species.glass_diving(tick, enemy_id[i])  # a glass wing only touches a rig in its dive
		for k in nv:
			if flying:
				break
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
				if is_boss:
					_boss_contact[vidx] += _contact_hit(kind, cv.eff_armor, cv.contact_reduction)
					Bosses.on_contact(self, i, vidx)
				elif not stunned:
					_contact[vidx * CONTACT_KINDS + kind] += _contact_hit(kind, cv.eff_armor, cv.contact_reduction)
				var ram: float = cv.ram_damage
				if kind == GLASS:
					ram = 0.0  # rams and thorns do not reach a flyer
				elif cv.thorns > 0.0:
					ram += cv.thorns * ENEMY_CONTACT_DAMAGE[kind] * enemy_damage_mult(round)
				if is_boss:  # ramming a boss: reduced damage dealt, and the rammer pays for it
					ram *= Bosses.RAM_DAMAGE_FACTOR
					if cv.ramming:
						_boss_contact[vidx] += Bosses.RAM_RECOIL * enemy_damage_mult(round)
				if ram > 0.0 and not killed:
					_hit_enemy(i, ram, vidx, true)
					killed = enemy_hp[i] <= 0.0
					if cv.ramming and not is_boss:
						var kb: Vector2 = Mobility.ram_hit(self, cv, i)
						if kb != Vector2.ZERO:
							np += kb
							vel = kb * (0.5 / DT)

		np.x = clampf(np.x, a_min.x, a_max.x)
		np.y = clampf(np.y, a_min.y, a_max.y)
		enemy_pos[i] = np
		enemy_vel[i] = vel

		if kind == SPITTER and bk >= 0 and enemy_hp[i] > 0.0 and (tick + enemy_id[i] * 7) % SPIT_PERIOD == 0:
			var ci: int = _ch_idx[bk]
			if ci >= 0:
				_spit(np, vehicles[ci].pos, vehicles[ci].vel)
			else:
				_spit(np, vehicles[-1 - ci].decoy_pos, Vector2.ZERO)

	for vidx in vehicles.size():
		var ctot: float = 0.0
		var dom_k: int = 0
		var dom_v: float = -1.0
		var split := PackedFloat32Array()
		for ck in CONTACT_KINDS:
			var cval: float = _contact[vidx * CONTACT_KINDS + ck]
			split.append(cval)
			ctot += cval
			if cval > dom_v:
				dom_v = cval
				dom_k = ck
		if ctot > 0.0:
			_damage_vehicle(vehicles[vidx], ctot, -1, false, CONTACT_SRC[dom_k], split)
		if _boss_contact[vidx] > 0.0:
			boss_dmg_taken += _boss_contact[vidx]
			_damage_vehicle(vehicles[vidx], _boss_contact[vidx], -1, false, SRC_BOSS)


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


## A spitter at `from` lobs one acid glob at a target at `tpos` moving with `tvel` (leading its movement;
## a rig or a phantom decoy). Emits a "spit" event.
func _spit(from: Vector2, tpos: Vector2, tvel: Vector2) -> void:
	var dist: float = from.distance_to(tpos)
	if dist > SPIT_RANGE or dist < 1.0:
		return
	var aim: Vector2 = tpos + tvel * (dist / SPIT_SPEED)
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
	var kind0: int = enemy_kind[j]
	if kind0 >= BOSS_A:
		if kind0 == BOSS_B and boss_phase < 3:  # the Colossus does not die before it splits (Bosses._split)
			dmg = minf(dmg, enemy_hp[j] - 1.0)
			if dmg <= 0.0:
				return
		Bosses.on_damage(self, killer, minf(dmg, enemy_hp[j]))
	var applied: float = minf(dmg, enemy_hp[j])
	enemy_hp[j] -= dmg
	var kv: SimVehicle = vehicles[killer] if (killer >= 0 and killer < vehicles.size()) else null
	if kv != null:
		kv.round_stats["dealt"] = float(kv.round_stats["dealt"]) + applied
		kv.match_stats["dmg_dealt"] = float(kv.match_stats["dmg_dealt"]) + applied
		if by_ram and kv.contract_kind == Salvage.K_RAM:
			kv.contract_prog += applied
	if enemy_hp[j] > 0.0:
		return
	var kind: int = enemy_kind[j]
	_emit("kill", enemy_pos[j], killer, kind)
	if kind >= BOSS_A:
		Bosses.on_death(self, j, killer)
	elif kind == BROOD:  # fire, burn or splash kills the brood with it
		Species.on_brood_death(self, j, killer, _fire_dmg or _in_splash or enemy_burn_ticks[j] > 0 \
				or (_hit_ammo & Ammo.FIRE_BIT) != 0 or _hit_weapon == EVO_FLAMER_IDX)
	if (_hit_ammo & Ammo.SHRAPNEL_BIT) != 0 and (_hit_ammo & Ammo.SHARD_BIT) == 0:
		_queue_shards(enemy_pos[j], killer, kind)
	if kv != null:
		Abilities.on_kill(kv)
		kv.scrap_frac += (mite_scrap(round) if kind == MITE else float(ENEMY_SCRAP[kind])) * kv.scrap_mult
		var whole: int = int(kv.scrap_frac)
		kv.scrap += whole
		kv.scrap_frac -= float(whole)
		kv.kills += 1
		_note_scrap(kv, whole)
		kv.round_stats["kills"] = int(kv.round_stats["kills"]) + 1
		kv.match_stats["kills"] = int(kv.match_stats["kills"]) + 1
		if by_ram:
			kv.match_stats["ram_kills"] = int(kv.match_stats["ram_kills"]) + 1
		if kv.contract_kind >= 0:
			Salvage.on_kill(kv, kind)
		if not kv.tech_fx.is_empty():
			Fusions.on_kill(self, kv, j, by_ram, _in_splash)


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
			enemy_burn_ticks[i] = enemy_burn_ticks[n]
			enemy_burn_dps[i] = enemy_burn_dps[n]
			enemy_burn_owner[i] = enemy_burn_owner[n]
			enemy_status[i] = enemy_status[n]
			enemy_ram_tick[i] = enemy_ram_tick[n]
		i -= 1
	if n != enemy_count:
		enemy_id.resize(n)
		enemy_kind.resize(n)
		enemy_pos.resize(n)
		enemy_vel.resize(n)
		enemy_hp.resize(n)
		enemy_burn_ticks.resize(n)
		enemy_burn_dps.resize(n)
		enemy_burn_owner.resize(n)
		enemy_status.resize(n)
		enemy_ram_tick.resize(n)
		enemy_count = n


func _spawn_tick() -> void:
	if not spawning_enabled:
		return
	var dur: int = combat_duration(round)
	var ticks_in: int = dur - phase_ticks_left
	var pack: int = pack_size(round)
	var starts: PackedInt32Array = surge_starts(dur)
	for si in starts.size():  # warn SURGE_WARN_TICKS before each surge
		if ticks_in == starts[si] - SURGE_WARN_TICKS and ticks_in >= 0:
			_emit("surge", _swarm_center(), -1, si, {"in_ticks": SURGE_WARN_TICKS, "index": si})
	# the accumulator counts spawn events: a mite event is a pack, boulders and spitters are single
	var boss_mult: float = Bosses.BOSS_SPAWN_FACTOR if Bosses.engaged(self) else 1.0
	_spawn_accum += spawn_rate_at(round, ticks_in) * boss_mult * DT / float(pack)
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
	var species_on: bool = Species.any_active(self, round)
	var species_n: PackedInt32Array = Species.count_alive(self) if species_on else PackedInt32Array([0, 0, 0])
	var p_boulder: float = minf(boulder_chance(round) * float(pack), 0.5)  # per event, so packs do not dilute them
	var p_spitter: float = minf(spitter_chance(round) * float(pack), 0.3) if round >= SPITTER_MIN_ROUND else 0.0
	while _spawn_accum >= 1.0:
		_spawn_accum -= 1.0
		var side: int = rng.randi() % 4
		var t: float = rng.randf()
		var kind: int = MITE
		if rng.randf() < p_boulder:
			kind = BOULDER
		elif round >= SPITTER_MIN_ROUND and rng.randf() < p_spitter:
			kind = SPITTER
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
		var at: Vector2 = _edge_pos(area, side, t)
		var lo: Vector2 = area.position + Vector2(SPAWN_INSET, SPAWN_INSET)
		var hi: Vector2 = area.end - Vector2(SPAWN_INSET, SPAWN_INSET)
		if kind == MITE and species_on:  # hive signature: a mite event may become one of this match's species
			var sk: int = Species.roll(self, species_n)
			if sk >= 0:
				Species.spawn_event(self, sk, at, lo, hi, species_n)
				continue
		if kind == MITE:
			for k in pack:
				var ang: float = rng.randf() * TAU
				var rad: float = sqrt(rng.randf()) * PACK_RADIUS
				var mp: Vector2 = at + Vector2(cos(ang), sin(ang)) * rad
				spawn_enemy(MITE, Vector2(clampf(mp.x, lo.x, hi.x), clampf(mp.y, lo.y, hi.y)))
		else:
			spawn_enemy(kind, at)


## Centre of the alive vehicles (where the "surge" warning points), the arena centre when none is alive.
func _swarm_center() -> Vector2:
	var sum := Vector2.ZERO
	var n: int = 0
	for v in vehicles:
		if v.alive:
			sum += v.pos
			n += 1
	return sum / float(n) if n > 0 else ARENA.get_center()


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
	Mobility.update_jam(self)
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
		Abilities.tick(self, v)
		Doctrine.apply_rig(self, v)
		VehicleAI.update_target(self, v)
		_update_mark(v)
		Abilities.auto_cast(self, v)
		VehicleAI.steer(self, v)
		Mobility.update(self, v)
		Fusions.tick(self, v)
		v.pos += v.vel * DT
		v.pos.x = clampf(v.pos.x, lo.x, hi.x)
		v.pos.y = clampf(v.pos.y, lo.y, hi.y)
	_resolve_vehicle_contacts()
	for v in vehicles:
		if v.alive:
			_fire_weapons(v)


## Swarm logic: the marked target is the rig's own target (it jumps on to the next one when that dies).
func _update_mark(v: SimVehicle) -> void:
	if float(v.tech_fx.get("swarm_logic", 0.0)) <= 0.0:
		v.mark_id = -1
		return
	if v.target_kind == 1 and v.target_index >= 0 and v.target_index < enemy_count:
		v.mark_id = v.target_id
		v.mark_pos = v.target_pos
	else:
		v.mark_id = -1


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
				if va.ramming:
					Mobility.ram_hit_vehicle(self, va, vb)
			if vb.ram_damage > 0.0:
				_damage_vehicle(va, vb.ram_damage, vb.id, true, SRC_RAM)
				if vb.ramming:
					Mobility.ram_hit_vehicle(self, vb, va)


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
	if src == SRC_ACID or src == SRC_PLAYER:  # dodge: discrete hits only, not the per-tick contact damage
		var dodge: float = Mobility.dodge_chance(v)
		if dodge > 0.0 and rng.randf() < dodge:
			_emit("dodge", v.pos, v.id, 0)
			return
	if src == SRC_ACID:
		dmg *= 1.0 - clampf(float(v.tech_fx.get("blast_resist", 0.0)), 0.0, 0.9)
	if use_armor and v.eff_armor > 0.0:
		dmg = maxf(dmg - v.eff_armor, dmg * ARMOR_MIN_FRACTION)
	if v.protect_ticks > 0:
		dmg *= PVP_PROTECT_FACTOR
	var av: SimVehicle = vehicles[attacker] if by_player else null
	if av != null and _aims_at(av, v.id):  # deliberate attack, not a stray shot
		v.retaliate_id = attacker
		v.retaliate_ticks = RETALIATE_TICKS
	var applied: float = minf(dmg, v.hp)
	v.hp -= dmg
	if dmg > Mobility.HIT_LOSS_MIN_DAMAGE and v.momentum > 0.0:
		v.momentum = maxf(v.momentum - Mobility.HIT_LOSS, 0.0)
	if dmg > SHED_HP_FRACTION * v.max_hp and v.hp > 0.0:
		_shed_plate(v)
	_note_taken(v, applied, src, attacker if by_player else -1, split)
	if av != null:
		av.round_stats["dealt"] = float(av.round_stats["dealt"]) + applied
		av.round_stats["dealt_players"] = float(av.round_stats["dealt_players"]) + applied
		av.match_stats["dmg_dealt"] = float(av.match_stats["dmg_dealt"]) + applied
		if av.contract_kind >= 0:
			if src == SRC_PLAYER and av.contract_kind == Salvage.K_LEADER and v.peer_id == leader_peer:
				av.contract_prog += 1.0
			elif src == SRC_RAM and av.contract_kind == Salvage.K_RAM:
				av.contract_prog += applied
		if not av.tech_fx.is_empty():
			Salvage.raid(self, av, v, applied)
	if v.hp > 0.0:
		return
	v.hp = 0.0
	v.alive = false
	Salvage.on_destroyed(v)
	Abilities.clear_effects(v)
	v.momentum = 0.0
	v.vel = Vector2.ZERO
	v.target_kind = 0
	v.ram_damage = 0.0
	var killer_id: int = attacker if by_player else -1
	var killer_kind: int = -1
	if src <= SRC_SPITTER:
		killer_kind = src
	elif src >= SRC_GLASS:
		killer_kind = GLASS + (src - SRC_GLASS)
	elif src == SRC_ACID:
		killer_kind = SPITTER
	elif src == SRC_BOSS:
		killer_kind = maxi(boss_kind, BOSS_A)
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
	Salvage.on_death(self, v)
	if by_player:
		_reward_player_kill(av, v, src, lost)


## Scrap armour: a big hit tears off one armour plate until the next workshop; the plate flies off as a
## projectile (toward the rig's target, else a random way).
func _shed_plate(v: SimVehicle) -> void:
	if float(v.tech_fx.get("armor_shed", 0.0)) <= 0.0 or v.armor < 1.0:
		return
	v.armor -= 1.0
	v.eff_armor = maxf(v.eff_armor - 1.0, 0.0)
	v.shed += 1
	var dir: Vector2 = Vector2.from_angle(rng.randf() * TAU)
	if v.target_kind != 0 and v.target_pos.distance_squared_to(v.pos) > 1.0:
		dir = (v.target_pos - v.pos).normalized()
	_pending_proj.append([v.pos + dir * MUZZLE_OFFSET, dir * PLATE_SPEED, PLATE_TTL, PLATE_DAMAGE, v.id, 0, 0])
	_emit("shed", v.pos, v.id, 0)


## Books `hp` of damage taken from `src` / `attacker` in the round stats of `v`. `split` (contact damage
## per enemy kind) spreads one contact total over mite / boulder / spitter.
func _note_taken(v: SimVehicle, hp: float, src: int, attacker: int, split: PackedFloat32Array) -> void:
	if hp <= 0.0:
		return
	var taken: Dictionary = v.round_stats["taken"]
	if split.size() == CONTACT_KINDS:
		var tot: float = 0.0
		for sv in split:
			tot += sv
		if tot > 0.0:
			for ck in CONTACT_KINDS:
				var key: String = SRC_NAMES[CONTACT_SRC[ck]]
				taken[key] = float(taken[key]) + hp * split[ck] / tot
		return
	match src:
		SRC_MITE:
			taken["mite"] = float(taken["mite"]) + hp
		SRC_BOULDER:
			taken["boulder"] = float(taken["boulder"]) + hp
		SRC_SPITTER:
			taken["spitter"] = float(taken["spitter"]) + hp
		SRC_GLASS, SRC_BROOD, SRC_SHRIEKER:
			taken[SRC_NAMES[src]] = float(taken[SRC_NAMES[src]]) + hp
		SRC_ACID, SRC_BOSS:
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
	if float(av.tech_fx.get("bounty_office", 0.0)) > 0.0:
		bounty *= Salvage.BOUNTY_MULT
	Salvage.loot_baron(self, av, v)
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
	var fx: Dictionary = v.tech_fx
	var scatter: bool = float(fx.get("scatter", 0.0)) > 0.0
	var heat_limit: int = 0
	var heat_pause: int = 0
	if float(fx.get("overheat", 0.0)) > 0.0:
		heat_limit = OVERHEAT_FIRE_TICKS
		heat_pause = OVERHEAT_PAUSE_TICKS
	elif float(fx.get("jam", 0.0)) > 0.0:
		heat_limit = JAM_FIRE_TICKS
		heat_pause = JAM_PAUSE_TICKS
	var cd_step: float = 1.0 + Abilities.SALVO_RATE if v.salvo_ticks > 0 else 1.0
	for slot in v.weapons.size():
		var w: Dictionary = v.weapons[slot]
		# Fire rate is an accumulator in (fractional) ticks: a shot adds cooldown_ticks, so the
		# overshoot of one tick carries into the next shot instead of being rounded away. A salvo winds it faster.
		var cd: float = float(w["cooldown"])
		if cd > 0.0:
			cd -= cd_step
			w["cooldown"] = cd
		var jam: int = int(w.get("jam", 0))
		if jam > 0:
			jam -= 1
			w["jam"] = jam
		var sw: int = int(w.get("sw", 0))
		if sw > 0:
			sw -= 1
			w["sw"] = sw
		# Per-weapon doctrine: its rules pick a target mode, may hold fire and may load another ammo.
		var dec: Array = Doctrine.apply_weapon(self, v, w)
		if str(dec[2]) != "":
			if Ammo.select(v, str(w["kind"]), str(dec[2])):
				sw = int(w.get("sw", 0))
		VehicleAI.update_weapon_target(self, v, w, slot, "follow" if v.focus else str(dec[0]))
		var tk: int = int(w.get("tk", 0))
		var tpos: Vector2 = w.get("tp", Vector2.ZERO)
		var tvel: Vector2 = w.get("tv", Vector2.ZERO)
		var ti: int = int(w.get("ti", -1))
		var tid: int = int(w.get("tid", -1))
		if tk == 0:
			tk = v.target_kind
			tpos = v.target_pos
			tvel = v.target_vel
			ti = v.target_index
			tid = v.target_id
		if tk == 0:
			_cool_heat(w)
			continue
		var speed: float = float(w.get("speed", PROJECTILE_SPEED))
		var dist: float = v.pos.distance_to(tpos)
		var lead: Vector2 = tpos + tvel * (dist / speed)
		var to: Vector2 = lead - v.pos
		var ang: float = to.angle()
		w["aim"] = ang
		var intends: bool = not bool(dec[1]) and dist <= float(w["range"])
		if not intends:
			_cool_heat(w)
			continue
		var kind_name: String = str(w["kind"])
		var widx: int = Cards.weapon_kind_index(kind_name)
		# Jam / overheat: continuous fire intent heats the barrel; at the limit it pauses.
		if heat_limit > 0 and jam <= 0:
			var heat: int = int(w.get("heat", 0)) + 1
			if heat >= heat_limit:
				w["heat"] = 0
				w["jam"] = heat_pause
				_emit("overheat" if heat_limit == OVERHEAT_FIRE_TICKS else "jam", v.pos + Vector2.from_angle(ang) * MUZZLE_OFFSET, v.id, widx)
				continue
			w["heat"] = heat
		elif heat_limit <= 0:
			w["heat"] = 0
		if cd > 0.0 or jam > 0 or sw > 0 or proj_count >= MAX_PROJECTILES:
			continue
		var spread: float = float(w.get("spread", SPREAD))
		var pellets: int = int(w.get("pellets", 1))
		var pierce: int = int(w.get("pierce", 0))
		var splash: float = float(w.get("splash", 0.0))
		var dmg: float = float(w["damage"]) * Salvage.baron_mult(v)
		if v.vulture > 0.0 and _is_weak(tk, ti, tid):
			dmg *= 1.0 + v.vulture
		var amask: int = Ammo.mask(v, kind_name)
		if (amask & Ammo.AP_BIT) != 0:
			pierce += 1
		var evo: bool = bool(w.get("evo", false))
		if evo:
			amask |= Ammo.EVO_BIT
		var ttl: float = float(w["range"]) / speed + 0.05
		var muzzle: Vector2 = v.pos + Vector2.from_angle(ang) * MUZZLE_OFFSET
		var spot: bool = kind_name == "cannon" and tk == 1 and ti >= 0 and ti < enemy_count and enemy_kind[ti] == SPITTER \
				and enemy_id[ti] == tid and float(fx.get("spotter", 0.0)) > 0.0
		for p in pellets:
			var dir: Vector2 = Vector2.from_angle(ang + rng.randf_range(-spread, spread))
			if spot:  # spotter: the shell is born on the spitter, so it cannot miss
				spawn_projectile(enemy_pos[ti], Vector2.from_angle(ang) * speed, ttl, dmg, v.id, pierce, splash, widx, amask)
			else:
				spawn_projectile(muzzle, dir * speed, ttl, dmg, v.id, pierce, splash, widx, amask)
		if scatter and kind_name != "shotgun":
			var shots: int = int(w.get("shots", 0)) + 1
			w["shots"] = shots
			if shots % SCATTER_EVERY == 0:
				for p in SCATTER_PELLETS:
					var sdir: Vector2 = Vector2.from_angle(ang + rng.randf_range(-SCATTER_SPREAD, SCATTER_SPREAD))
					spawn_projectile(muzzle, sdir * speed, ttl, dmg * SCATTER_DAMAGE, v.id, 0, 0.0, widx, amask)
		if evo and kind_name == "flamer":  # Inferno Spout: a short fire zone along the stream every EVO_FIRE_EVERY shots
			var fshots: int = int(w.get("zn", 0)) + 1
			w["zn"] = fshots
			if fshots % EVO_FIRE_EVERY == 0:
				var reach: float = float(w["range"]) * (0.45 + 0.2 * float((fshots / EVO_FIRE_EVERY) % 3))
				_add_zone(v.pos + Vector2.from_angle(ang) * reach, EVO_FIRE_RADIUS, ZONE_FIRE, EVO_FIRE_TICKS, v.id)
		w["cooldown"] = cd + float(w["cooldown_ticks"])
		_emit("fire", muzzle, v.id, widx)


## A weapon without fire intent cools down.
func _cool_heat(w: Dictionary) -> void:
	var heat: int = int(w.get("heat", 0))
	if heat > 0:
		w["heat"] = maxi(heat - HEAT_COOL, 0)


## Vulture: is the target under 30% hp?
func _is_weak(kind: int, index: int, id: int) -> bool:
	if kind == 1:
		if index < 0 or index >= enemy_count:
			return false
		return enemy_hp[index] < Cards.VULTURE_HP_FRACTION * enemy_max_hp_of(index)
	if kind == 2 and id >= 0 and id < vehicles.size():
		var t: SimVehicle = vehicles[id]
		return t.alive and t.hp < Cards.VULTURE_HP_FRACTION * t.max_hp
	return false


## True if `av` (the rig or one of its weapons) deliberately aims at vehicle `id`.
func _aims_at(av: SimVehicle, id: int) -> bool:
	if av.target_kind == 2 and av.target_id == id:
		return true
	for w in av.weapons:
		if int(w.get("tk", 0)) == 2 and int(w.get("tid", -1)) == id:
			return true
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
				if enemy_kind[j] == GLASS and proj_weapon[i] == EVO_FLAMER_IDX:
					continue  # the flame stream is a ground weapon: it does not reach a flyer
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
		var amask: int = proj_ammo[i]
		var ov: SimVehicle = vehicles[owner] if (owner >= 0 and owner < nveh) else null
		if hit_vehicle >= 0:
			var hv: SimVehicle = vehicles[hit_vehicle]
			_emit("hit", p0 + step_v * best_t, owner, -1)
			if ov != null and (amask & Ammo.AP_BIT) != 0:
				dmg *= 1.0 + Ammo.AP_BONUS * Ammo.effect_scale(ov, amask)
			_hit_weapon = proj_weapon[i] if proj_weapon[i] != 255 else -1
			_damage_vehicle(hv, dmg, owner, true, SRC_ACID if owner < 0 else SRC_PLAYER)
			_hit_weapon = -1
			remove = true
		elif hit_enemy >= 0:
			var hit_pos: Vector2 = p0 + step_v * best_t
			var ekind: int = enemy_kind[hit_enemy]
			_emit("hit", hit_pos, owner, ekind)
			var ascale: float = 1.0
			if ov != null:
				var ofx: Dictionary = ov.tech_fx
				if amask != 0:
					ascale = Ammo.effect_scale(ov, amask)
					if (amask & Ammo.AP_BIT) != 0 and ekind == BOULDER:
						dmg *= 1.0 + Ammo.AP_BONUS * ascale
				if enemy_burn_ticks[hit_enemy] > 0 and proj_weapon[i] != 2:  # cannon is index 2
					var bb: float = float(ofx.get("burn_bonus", 0.0))
					if bb > 0.0:
						dmg *= 1.0 + bb
				if proj_weapon[i] == 2 and ekind == SPITTER:
					var spf: float = float(ofx.get("spotter", 0.0))
					if spf > 0.0:
						dmg *= 1.0 + spf
				var sw: float = float(ofx.get("swarm_logic", 0.0))
				if sw > 0.0 and enemy_id[hit_enemy] == ov.mark_id:
					dmg *= 1.0 + sw
				var ex: float = float(ofx.get("execute", 0.0))
				if ex > 0.0 and (amask & Ammo.SHARD_BIT) == 0 and enemy_hp[hit_enemy] > 0.0 \
						and ekind < BOSS_A and enemy_hp[hit_enemy] < ex * enemy_max_hp(ekind, round):
					dmg = maxf(dmg, enemy_hp[hit_enemy])
					_emit("execute", hit_pos, owner, ekind)
			_hit_weapon = proj_weapon[i] if proj_weapon[i] != 255 else -1
			_hit_ammo = amask
			_hit_dmg = dmg
			_hit_scale = ascale
			_hit_enemy(hit_enemy, dmg, owner)
			if proj_splash[i] > 0.0:
				_splash_damage(hit_pos, proj_splash[i], dmg * SPLASH_FRACTION, owner, hit_enemy)
			_hit_ammo = 0
			_hit_weapon = -1
			if (amask & Ammo.EVO_BIT) != 0 and proj_weapon[i] == EVO_FLAMER_IDX and enemy_hp[hit_enemy] > 0.0:
				_ignite(hit_enemy, dmg * EVO_BURN_MULT, owner)  # Inferno Spout burns hard (no ammo needed)
			if (amask & Ammo.FIRE_BIT) != 0 and enemy_hp[hit_enemy] > 0.0:
				_ignite(hit_enemy, dmg * BURN_FRACTION * ascale / (float(BURN_TICKS) * DT), owner)
			if proj_pierce[i] > 0:
				proj_pierce[i] -= 1
				proj_last[i] = enemy_id[hit_enemy]
				if ov != null and float(ov.tech_fx.get("ember", 0.0)) > 0.0:
					_add_zone(hit_pos, EMBER_RADIUS, ZONE_EMBER, EMBER_TICKS, owner)
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
			proj_ammo[i] = proj_ammo[n]
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
		proj_ammo.resize(n)
		proj_count = n
	_flush_pending()


## Damages every living enemy within `radius` of `center` except index `skip`.
func _splash_damage(center: Vector2, radius: float, dmg: float, owner: int, skip: int) -> void:
	var cnt: int = _hash.query_circle(center, radius, enemy_pos, _splash_buf, STALE_MARGIN)
	_in_splash = true
	for q in cnt:
		var j: int = _splash_buf[q]
		if j != skip and enemy_kind[j] != GLASS:  # a ground blast does not reach a flyer
			_hit_enemy(j, dmg, owner)
	_in_splash = false


# ---------------------------------------------------------------- burn, shards and zones

## Sets an enemy on fire for BURN_TICKS: `dps` damage per second credited to `owner`. A new fire only
## replaces a weaker running one (the stronger dps and its owner win), but always refreshes the timer.
func _ignite(j: int, dps: float, owner: int) -> void:
	if dps <= 0.0 or enemy_hp[j] <= 0.0:
		return
	if enemy_burn_ticks[j] <= 0 or dps >= enemy_burn_dps[j]:
		enemy_burn_dps[j] = dps
		enemy_burn_owner[j] = owner
	enemy_burn_ticks[j] = BURN_TICKS
	_burning = true


## Burn damage over time (credited to the igniting vehicle, kills included) and napalm spreading.
func _update_burn() -> void:
	if not _burning:
		return
	var any: bool = false
	for i in enemy_count:
		var bt: int = enemy_burn_ticks[i]
		if bt <= 0:
			continue
		if enemy_hp[i] <= 0.0:
			enemy_burn_ticks[i] = 0
			continue
		enemy_burn_ticks[i] = bt - 1
		any = true
		var owner: int = enemy_burn_owner[i]
		if (tick + enemy_id[i]) % BURN_SPREAD_PERIOD == 0 and owner >= 0 and owner < vehicles.size():
			var radius: float = float(vehicles[owner].tech_fx.get("napalm", 0.0))
			if radius > 0.0:
				var ndps: float = enemy_burn_dps[i] * BURN_SPREAD_DECAY
				var cnt: int = _hash.query_circle(enemy_pos[i], radius, enemy_pos, _splash_buf, STALE_MARGIN)
				for q in cnt:
					var k: int = _splash_buf[q]
					if k != i and enemy_burn_ticks[k] <= 0:
						_ignite(k, ndps, owner)
		_hit_enemy(i, enemy_burn_dps[i] * DT, owner)
	_burning = any
	_flush_pending()


## Queues SHARD_COUNT shards for a kill (added after the current projectile loop).
func _queue_shards(pos: Vector2, owner: int, ekind: int) -> void:
	_emit("shrapnel", pos, owner, ekind)
	var dmg: float = _hit_dmg * SHARD_DAMAGE * _hit_scale
	var a0: float = rng.randf() * TAU
	for k in SHARD_COUNT:
		var dir: Vector2 = Vector2.from_angle(a0 + TAU * float(k) / float(SHARD_COUNT))
		_pending_proj.append([pos, dir * SHARD_SPEED, SHARD_TTL, dmg, owner, _hit_weapon, Ammo.SHARD_BIT])


func _flush_pending() -> void:
	if _pending_proj.is_empty():
		return
	for e: Array in _pending_proj:
		spawn_projectile(e[0], e[1], e[2], e[3], e[4], 0, 0.0, maxi(int(e[5]), 0), int(e[6]))
	_pending_proj.clear()


## Adds a ground zone (skipped when full, or when the same kind and owner already covers the spot).
func _add_zone(pos: Vector2, radius: float, kind: int, ttl: int, owner: int) -> void:
	if zone_count >= MAX_ZONES:
		return
	var r2: float = radius * radius * 0.5
	for z in zone_count:
		if zone_kind[z] == kind and zone_owner[z] == owner and zone_pos[z].distance_squared_to(pos) < r2:
			zone_ttl[z] = maxi(zone_ttl[z], ttl)
			return
	zone_pos.append(pos)
	zone_radius.append(radius)
	zone_kind.append(kind)
	zone_ttl.append(ttl)
	zone_owner.append(owner)
	zone_count += 1


## Ticks the ground zones: embers burn (EMBER_DPS) and ignite what stands in them, oil slows, smoke blinds.
## Expired zones go.
func _update_zones() -> void:
	if zone_count == 0:
		return
	var z: int = zone_count - 1
	while z >= 0:
		if zone_kind[z] == ZONE_EMBER or zone_kind[z] == ZONE_FIRE:
			var owner: int = zone_owner[z]
			var cnt: int = _hash.query_circle(zone_pos[z], zone_radius[z], enemy_pos, _splash_buf, STALE_MARGIN)
			_fire_dmg = true
			for q in cnt:
				var j: int = _splash_buf[q]
				if enemy_hp[j] > 0.0 and enemy_kind[j] != GLASS:
					_hit_enemy(j, EMBER_DPS * DT, owner)
					_ignite(j, EMBER_BURN_DPS, owner)
			_fire_dmg = false
		elif zone_kind[z] == ZONE_OIL or zone_kind[z] == ZONE_SMOKE:
			# Oil slows what stands in it for 2 s; smoke makes aliens lose their target for 1 s.
			var oil: bool = zone_kind[z] == ZONE_OIL
			var cnt2: int = _hash.query_circle(zone_pos[z], zone_radius[z], enemy_pos, _splash_buf, STALE_MARGIN)
			for q in cnt2:
				var j2: int = _splash_buf[q]
				if enemy_kind[j2] == GLASS:
					continue
				if oil:
					_status_enemy(j2, 8, Abilities.OIL_SLOW_TICKS)
				else:
					_status_enemy(j2, 16, Abilities.BLIND_TICKS)
		zone_ttl[z] -= 1
		if zone_ttl[z] <= 0:
			var last: int = zone_count - 1
			zone_pos[z] = zone_pos[last]
			zone_radius[z] = zone_radius[last]
			zone_kind[z] = zone_kind[last]
			zone_ttl[z] = zone_ttl[last]
			zone_owner[z] = zone_owner[last]
			zone_pos.resize(last)
			zone_radius.resize(last)
			zone_kind.resize(last)
			zone_ttl.resize(last)
			zone_owner.resize(last)
			zone_count = last
		z -= 1
