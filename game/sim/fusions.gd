class_name Fusions
extends RefCounted
## The eleven fusion effects (tech tree v2.3, section 5). Thermite Ram, Burning Wake, War Machine, Scrap Storm,
## Junkyard Drone, Thunderclap, Barbed Wire, Lucky Strike, Fortified Relay and Hot Rod are triggered from the
## sim (kills, rams, the per-tick update); Spotter lives in SimWorld._fire_weapons / the projectile hit.
## Pure static code over SimWorld / SimVehicle; deterministic (randomness only through `world.rng`).

const THERMITE_RADIUS := 45.0  ## the bumper's sparks grow from 30 px
const THERMITE_BURN_DPS := 5.0

const WAKE_RADIUS := 16.0
const WAKE_TICKS := 60
const WAKE_PERIOD := 6  ## ticks between fire puddles while drifting or on nitro

const WAR_RADIUS := 60.0
const WAR_DAMAGE := 30.0
const WAR_PUSH := 22.0
const WAR_MOMENTUM := 40.0
const WAR_THROTTLE := 30  ## ticks per target (1 s)
const WAR_KEY_BASE := 1000  ## Vehicle.ram_fx key = base + target id (alien ids or rival ids)
const WAR_PRUNE := 160

const BARBED_CAP := 45  ## scrap per round

const LUCKY_EVERY_ROUNDS := 2

const FORT_TICKS := 90  ## 3 s
const FORT_MAX := 6.0

const STORM_SHARDS := 3
const STORM_DAMAGE := 25.0
const STORM_CAP := 40  ## bursts (and +1 scrap each) per round
const STORM_MASK_BURN := Ammo.SHARD_BIT | Ammo.FIRE_BIT

const DRONE_PERIOD := 30  ## about one hit per second
const DRONE_DAMAGE := 15.0
const DRONE_REACH := 220.0

const CLAP_COOLDOWN := 180  ## 6 s
const CLAP_RADIUS := 50.0
const CLAP_STUN_TICKS := 30  ## 1 s
const CLAP_CHAIN_TARGETS := 2
const CLAP_CHAIN_REACH := 150.0
const CLAP_CHAIN_DAMAGE := 10.0


static func _on(v: SimVehicle, key: String) -> bool:
	return float(v.tech_fx.get(key, 0.0)) > 0.0


## Per tick for a live rig, after Mobility.update (so `v.drifting` is current): fortified and hot rod repair,
## the burning wake and the junkyard drone.
static func tick(w: SimWorld, v: SimVehicle) -> void:
	if v.clap_cd > 0:
		v.clap_cd -= 1
	if v.fort_ticks > 0:
		v.hp = minf(v.hp + v.fort_regen * SimWorld.DT, v.max_hp)
		v.fort_ticks -= 1
		if v.fort_ticks == 0:
			v.fort_regen = 0.0
	var fx: Dictionary = v.tech_fx
	if fx.is_empty():
		return
	if v.drifting:
		var heal: float = float(fx.get("drift_regen", 0.0))
		if heal > 0.0 and v.hp < v.max_hp:
			v.hp = minf(v.hp + heal * SimWorld.DT, v.max_hp)
	if float(fx.get("burning_wake", 0.0)) > 0.0 and (v.drifting or v.nitro_ticks > 0) and (w.tick + v.id) % WAKE_PERIOD == 0:
		w._add_zone(v.pos, WAKE_RADIUS, SimWorld.ZONE_FIRE, WAKE_TICKS, v.id)
	if float(fx.get("junkyard", 0.0)) > 0.0 and (w.tick + v.id) % DRONE_PERIOD == 0:
		_drone(w, v)


## Junkyard drone: hits the rig's focus target, else the nearest mite in reach, for 15 damage.
static func _drone(w: SimWorld, v: SimVehicle) -> void:
	var j: int = -1
	if v.focus and v.target_kind == 1 and v.target_index >= 0 and v.target_index < w.enemy_count \
			and w.enemy_id[v.target_index] == v.target_id and w.enemy_hp[v.target_index] > 0.0 \
			and w.enemy_pos[v.target_index].distance_squared_to(v.pos) <= DRONE_REACH * DRONE_REACH:
		j = v.target_index
	else:
		j = VehicleAI._nearest_enemy(w, v.pos, -1, SimWorld.MITE, DRONE_REACH)
	if j < 0 or j >= w.enemy_count or w.enemy_hp[j] <= 0.0:
		return
	w._emit("hit", w.enemy_pos[j], v.id, w.enemy_kind[j])
	w._hit_enemy(j, DRONE_DAMAGE, v.id)


# ---------------------------------------------------------------- rams

## Thermite Ram: the bumper's sparks reach 45 px, ignite what they hit and a kill throws shrapnel.
static func thermite(w: SimWorld, v: SimVehicle, at: Vector2, skip: int) -> void:
	w._hit_ammo = Ammo.SHRAPNEL_BIT
	w._hit_dmg = Mobility.SPARKS_DAMAGE
	w._hit_scale = 1.0
	w._hit_weapon = -1
	w._splash_damage(at, THERMITE_RADIUS, Mobility.SPARKS_DAMAGE, v.id, skip)
	w._hit_ammo = 0
	var cnt: int = w.query_enemies(at, THERMITE_RADIUS, w._splash_buf)
	for q in cnt:
		var j: int = w._splash_buf[q]
		if j != skip and w.enemy_hp[j] > 0.0:
			w._ignite(j, THERMITE_BURN_DPS, v.id)


## War Machine: a ram hit sends a shockwave (60 px, 30 damage, knockback) around the rig. It costs 40 momentum
## (no wave below that) and hits each target at most once per second.
static func war_machine(w: SimWorld, v: SimVehicle) -> void:
	if v.momentum < WAR_MOMENTUM:
		return
	var cnt: int = w.query_enemies(v.pos, WAR_RADIUS, w.ai_buf)
	var targets: Array[int] = []
	for q in cnt:
		var j: int = w.ai_buf[q]
		if w.enemy_hp[j] <= 0.0:
			continue
		var key: int = WAR_KEY_BASE + w.enemy_id[j]
		if w.tick - int(v.ram_fx.get(key, -1000)) < WAR_THROTTLE:
			continue
		targets.append(j)
	var rivals: Array[SimVehicle] = []
	if w.pvp_enabled():
		var reach: float = WAR_RADIUS + SimVehicle.RADIUS
		for o in w.vehicles:
			if o != v and o.alive and o.invuln_ticks <= 0 and v.pos.distance_squared_to(o.pos) <= reach * reach \
					and w.tick - int(v.ram_fx.get(WAR_KEY_BASE + o.id, -1000)) >= WAR_THROTTLE:
				rivals.append(o)
	if targets.is_empty() and rivals.is_empty():
		return
	if v.ram_fx.size() > WAR_PRUNE:
		_prune(w, v)
	v.momentum = maxf(v.momentum - WAR_MOMENTUM, 0.0)
	for j in targets:
		v.ram_fx[WAR_KEY_BASE + w.enemy_id[j]] = w.tick
		var away: Vector2 = w.enemy_pos[j] - v.pos
		var dl: float = away.length()
		w._hit_enemy(j, WAR_DAMAGE, v.id)
		if dl > 0.001 and w.enemy_hp[j] > 0.0:
			w.enemy_pos[j] += away * (WAR_PUSH / dl)
	for o in rivals:
		v.ram_fx[WAR_KEY_BASE + o.id] = w.tick
		w._damage_vehicle(o, WAR_DAMAGE, v.id, true, SimWorld.SRC_RAM)
		if float(o.tech_fx.get("knock_immune", 0.0)) <= 0.0:
			var away2: Vector2 = o.pos - v.pos
			var dl2: float = away2.length()
			if dl2 > 0.001:
				o.pos += away2 * (WAR_PUSH / dl2)
	w._emit("shockwave", v.pos, v.id, 0)


static func _prune(w: SimWorld, v: SimVehicle) -> void:
	for k: int in v.ram_fx.keys():
		if k >= WAR_KEY_BASE and w.tick - int(v.ram_fx[k]) >= WAR_THROTTLE:
			v.ram_fx.erase(k)


# ---------------------------------------------------------------- kills

## Called for every alien kill credited to `kv` (enemy index `j`, still in the arrays). `by_ram`: a contact kill
## (charge ram, spikes); `splash`: killed by splash damage.
static func on_kill(w: SimWorld, kv: SimVehicle, j: int, by_ram: bool, splash: bool) -> void:
	var fx: Dictionary = kv.tech_fx
	if by_ram:
		var barbed: int = int(fx.get("barbed", 0.0))
		if barbed > 0 and kv.barbed_scrap < BARBED_CAP:
			var gain: int = mini(barbed, BARBED_CAP - kv.barbed_scrap)
			kv.barbed_scrap += gain
			kv.scrap += gain
			w._note_scrap(kv, gain)
		if float(fx.get("thunderclap", 0.0)) > 0.0:
			thunderclap(w, kv, w.enemy_pos[j], j)
	if splash and float(fx.get("scrap_storm", 0.0)) > 0.0 and kv.storm_count < STORM_CAP:
		kv.storm_count += 1
		kv.scrap += 1
		w._note_scrap(kv, 1)
		var mask: int = STORM_MASK_BURN if w.enemy_burn_ticks[j] > 0 else Ammo.SHARD_BIT
		var a0: float = w.rng.randf() * TAU
		for k in STORM_SHARDS:
			var dir: Vector2 = Vector2.from_angle(a0 + TAU * float(k) / float(STORM_SHARDS))
			w._pending_proj.append([w.enemy_pos[j], dir * SimWorld.SHARD_SPEED, SimWorld.SHARD_TTL, STORM_DAMAGE, kv.id, -1, mask])
	if kv.focus and kv.target_kind == 1 and w.enemy_id[j] == kv.target_id:
		var lucky: float = float(fx.get("lucky_strike", 0.0))
		if lucky > 0.0 and kv.bonus_offers == 0 and w.round - kv.lucky_round >= LUCKY_EVERY_ROUNDS \
				and w.rng.randf() < lucky:
			kv.bonus_offers = 1
			kv.lucky_round = w.round
		var fort: float = float(fx.get("fortified", 0.0))
		if fort > 0.0:
			kv.fort_regen = minf(kv.fort_regen + fort, FORT_MAX)
			kv.fort_ticks = FORT_TICKS


## Thunderclap: a contact kill at `at` sets off a mini EMP (stuns aliens within 50 px for 1 s) and a chain to the
## two nearest other aliens in reach (stun and a little damage). 6 s cooldown.
static func thunderclap(w: SimWorld, v: SimVehicle, at: Vector2, dead: int) -> void:
	if v.clap_cd > 0:
		return
	v.clap_cd = CLAP_COOLDOWN
	w._emit("chain", at, v.id, 0)
	var cnt: int = w.query_enemies(at, CLAP_RADIUS, w.ai_buf)
	for q in cnt:
		var j: int = w.ai_buf[q]
		if j != dead and w.enemy_hp[j] > 0.0:
			w.stun_enemy(j, CLAP_STUN_TICKS)
	var reach: int = w.query_enemies(at, CLAP_CHAIN_REACH, w.ai_buf)
	var picked: Array[int] = []
	for _n in CLAP_CHAIN_TARGETS:
		var best: int = -1
		var best_d2: float = INF
		for q in reach:
			var j2: int = w.ai_buf[q]
			if j2 == dead or w.enemy_hp[j2] <= 0.0 or picked.has(j2):
				continue
			var d2: float = at.distance_squared_to(w.enemy_pos[j2])
			if d2 > CLAP_RADIUS * CLAP_RADIUS and d2 < best_d2:  # the EMP ring itself is handled above
				best_d2 = d2
				best = j2
		if best < 0:
			break
		picked.append(best)
	for j3 in picked:
		w.stun_enemy(j3, CLAP_STUN_TICKS)
		w._emit("chain", w.enemy_pos[j3], v.id, 1)
		w._hit_enemy(j3, CLAP_CHAIN_DAMAGE, v.id)
