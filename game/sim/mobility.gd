class_name Mobility
extends RefCounted
## Propulsion and chassis mechanics (tech tree v2.3, sections 4.2 and 4.3): momentum, ram effects (sparks,
## knockback, momentum cost), turbine boom, dozer blade, dodge, juggernaut armour and the jammer field.
## Pure static code over SimWorld / SimVehicle; deterministic (randomness only through `world.rng`).

const MOMENTUM_MAX := 100.0
const TOP_SPEED := 120.0  ## px/s reference for momentum: rigs that cannot drive this fast build none
const GAIN_FRACTION := 0.8  ## momentum builds while the drive style asks for more than this share of TOP_SPEED
const GAIN_PER_TICK := 20.0 * SimWorld.DT  ## +20 / s
const DRIFT_DIFF := 0.35  ## rad of heading error that counts as turning hard (drift tuning doubles the gain)
const STOP_FRACTION := 0.2  ## "nearly stopped": below this share of TOP_SPEED
const DECAY_PER_TICK := 30.0 * SimWorld.DT  ## -30 / s when nearly stopped (halved by the turbine)
const HIT_LOSS := 10.0  ## per hit of more than HIT_LOSS_MIN_DAMAGE
const HIT_LOSS_MIN_DAMAGE := 10.0
const RAM_COST := 10.0  ## per ram hit without ram_free ...
const RAM_COST_TICKS := 10  ## ... at most this often (a charge into a swarm is many hits per tick)
const RAM_FX_TICKS := 15  ## ram effects (sparks, momentum, knockback) per target at most this often
const FULL_MOMENTUM := 100.0  ## momentum_ram applies from here

const SPARKS_RADIUS := 30.0
const SPARKS_DAMAGE := 15.0
const KNOCK_PUSH := 28.0  ## battering ram: px an enemy is thrown (boulders less)
const KNOCK_PUSH_BOULDER := 10.0
const KNOCK_PUSH_VEHICLE := 22.0

const DOZER_REACH := 34.0  ## mites this close in front of the blade are shoved aside
const DOZER_PUSH := 7.0

const BOOM_RADIUS := 40.0
const BOOM_DAMAGE := 30.0
const BOOM_COOLDOWN := 300  ## 10 s

const GHOST_MOMENTUM := 70.0  ## ghost runner dodges above this momentum
const JUGGERNAUT_ARMOR_DIV := 20.0  ## armour = momentum / 20 (up to +5)
const DODGE_MAX := 0.6
const OIL_SLOW := 0.6  ## speed factor of an enemy on oil (-40 %)
const JAM_SLOW := 0.8  ## aliens inside a jammer field (-20 %)


static func has_momentum(v: SimVehicle) -> bool:
	return float(v.tech_fx.get("momentum", 0.0)) > 0.0


## Extra ram multiplier from a full momentum bar (momentum_ram), added to the sum of the ram bonuses.
static func ram_bonus(v: SimVehicle) -> float:
	if v.momentum >= FULL_MOMENTUM:
		return float(v.tech_fx.get("momentum_ram", 0.0))
	return 0.0


## Chance to dodge a hit (featherweight, ghost runner above 70 momentum).
static func dodge_chance(v: SimVehicle) -> float:
	var fx: Dictionary = v.tech_fx
	if fx.is_empty():
		return 0.0
	var c: float = float(fx.get("dodge", 0.0))
	if v.momentum > GHOST_MOMENTUM:
		c += float(fx.get("ghost", 0.0))
	return minf(c, DODGE_MAX)


static func is_juggernaut(v: SimVehicle) -> bool:
	return float(v.tech_fx.get("juggernaut", 0.0)) > 0.0


## Per tick after steering: momentum, juggernaut armour, turbine boom, dozer blade.
static func update(w: SimWorld, v: SimVehicle) -> void:
	v.eff_armor = v.armor
	var fx: Dictionary = v.tech_fx
	if fx.is_empty():
		return
	if v.boom_cd > 0:
		v.boom_cd -= 1
	elif v.momentum >= FULL_MOMENTUM and float(fx.get("turbine_boom", 0.0)) > 0.0:
		_boom(w, v)
	if float(fx.get("momentum", 0.0)) > 0.0:
		if v.drive_speed > GAIN_FRACTION * TOP_SPEED:
			var mult: float = 1.0
			if v.turn_diff > DRIFT_DIFF and float(fx.get("drift_momentum", 0.0)) > 0.0:
				mult *= 2.0
			if float(fx.get("dirty_fuel", 0.0)) > 0.0:
				mult *= 2.0
			v.momentum = minf(v.momentum + GAIN_PER_TICK * mult, MOMENTUM_MAX)
		elif v.vel.length_squared() < STOP_FRACTION * TOP_SPEED * STOP_FRACTION * TOP_SPEED:
			var decay: float = DECAY_PER_TICK
			if float(fx.get("momentum_decay_half", 0.0)) > 0.0:
				decay *= 0.5
			v.momentum = maxf(v.momentum - decay, 0.0)
	if float(fx.get("juggernaut", 0.0)) > 0.0:
		v.eff_armor += v.momentum / JUGGERNAUT_ARMOR_DIV
	if float(fx.get("dozer", 0.0)) > 0.0:
		_dozer(w, v)


## Turbine boom: a shockwave when the bar is full, every 10 s, only if something stands in it.
static func _boom(w: SimWorld, v: SimVehicle) -> void:
	var hit: bool = w.query_enemies(v.pos, BOOM_RADIUS, w.ai_buf) > 0
	var rivals: Array[SimVehicle] = []
	if w.pvp_enabled():
		var reach: float = BOOM_RADIUS + SimVehicle.RADIUS
		for o in w.vehicles:
			if o != v and o.alive and o.invuln_ticks <= 0 and v.pos.distance_squared_to(o.pos) <= reach * reach:
				rivals.append(o)
	if not hit and rivals.is_empty():
		return
	v.boom_cd = BOOM_COOLDOWN
	w._splash_damage(v.pos, BOOM_RADIUS, BOOM_DAMAGE, v.id, -1)
	for o in rivals:
		w._damage_vehicle(o, BOOM_DAMAGE, v.id, true, SimWorld.SRC_RAM)
	w._emit("boom", v.pos, v.id, 0)


## Dozer blade: mites right in front of the nose are pushed outward, so they never touch the hull.
static func _dozer(w: SimWorld, v: SimVehicle) -> void:
	var n: int = w.query_enemies(v.pos, DOZER_REACH, w.ai_buf)
	if n == 0:
		return
	var fwd: Vector2 = Vector2.from_angle(v.heading)
	for q in n:
		var j: int = w.ai_buf[q]
		if w.enemy_kind[j] != SimWorld.MITE or w.enemy_hp[j] <= 0.0:
			continue
		var d: Vector2 = w.enemy_pos[j] - v.pos
		var dl: float = d.length()
		if dl < 0.001 or dl > DOZER_REACH or d.dot(fwd) < 0.5 * dl:
			continue
		w.enemy_pos[j] += d * (DOZER_PUSH / dl)


# ---------------------------------------------------------------- ram hits

## A charge ram hit enemy `i`. Applies the ram effects at most every RAM_FX_TICKS per target: momentum cost
## (none with ram_free), the bumper's sparks. Returns the knockback (px, away from the rig) for the caller to
## add to the enemy position; zero when there is none.
static func ram_hit(w: SimWorld, v: SimVehicle, i: int) -> Vector2:
	if w.tick - w.enemy_ram_tick[i] < RAM_FX_TICKS:
		return Vector2.ZERO
	w.enemy_ram_tick[i] = w.tick
	_ram_common(w, v, w.enemy_pos[i], i)
	if float(v.tech_fx.get("knockback", 0.0)) > 0.0 and w.enemy_hp[i] > 0.0:
		var away: Vector2 = w.enemy_pos[i] - v.pos
		var dl: float = away.length()
		if dl > 0.001:
			var push: float = KNOCK_PUSH_BOULDER if w.enemy_kind[i] == SimWorld.BOULDER else KNOCK_PUSH
			return away * (push / dl)
	return Vector2.ZERO


## A charge ram hit rival `o` (PvP). Same effects; the rival is shoved unless it has a roll cage.
static func ram_hit_vehicle(w: SimWorld, v: SimVehicle, o: SimVehicle) -> void:
	if w.tick - int(v.ram_fx.get(o.id, -1000)) < RAM_FX_TICKS:
		return
	v.ram_fx[o.id] = w.tick
	_ram_common(w, v, (v.pos + o.pos) * 0.5, -1)
	if float(v.tech_fx.get("knockback", 0.0)) > 0.0 and float(o.tech_fx.get("knock_immune", 0.0)) <= 0.0:
		var away: Vector2 = o.pos - v.pos
		var dl: float = away.length()
		if dl > 0.001:
			o.pos += away * (KNOCK_PUSH_VEHICLE / dl)


static func _ram_common(w: SimWorld, v: SimVehicle, at: Vector2, skip: int) -> void:
	var fx: Dictionary = v.tech_fx
	if float(fx.get("momentum", 0.0)) > 0.0 and float(fx.get("ram_free", 0.0)) <= 0.0 \
			and w.tick - int(v.ram_fx.get(-1, -1000)) >= RAM_COST_TICKS:
		v.ram_fx[-1] = w.tick
		v.momentum = maxf(v.momentum - RAM_COST, 0.0)
	if float(fx.get("sparks", 0.0)) > 0.0:
		w._splash_damage(at, SPARKS_RADIUS, SPARKS_DAMAGE, v.id, skip)
		w._emit("sparks", at, v.id, 0)


# ---------------------------------------------------------------- jammer

## Marks the rigs inside a rival's jammer field (their last rule slot is off) and lists the jammers for the
## alien slow-down. Run once per tick before the rules.
static func update_jam(w: SimWorld) -> void:
	w._jam_pos.clear()
	w._jam_r2 = 0.0
	for v in w.vehicles:
		v.jammed_by = -1
	var pvp: bool = w.pvp_enabled()
	for j in w.vehicles:
		if not j.alive:
			continue
		var r: float = float(j.tech_fx.get("jammer", 0.0))
		if r <= 0.0:
			continue
		w._jam_pos.append(j.pos)
		w._jam_r2 = maxf(w._jam_r2, r * r)
		if not pvp:
			continue
		for o in w.vehicles:
			if o != j and o.alive and o.jammed_by < 0 and j.pos.distance_squared_to(o.pos) <= r * r:
				o.jammed_by = j.id
