class_name Orders
extends RefCounted
## Live orders (design doc section 6): the "target mark". The player right-clicks an alien or a rival rig
## during combat; for MARK_TICKS every gun of the rig and the rig's targeting focus it, then the order
## is on cooldown (counted from the cast). Pure and deterministic, no rng. Fields live on SimVehicle
## (`mark_order_*`, not to be confused with the swarm-logic `mark_id`).

const MARK_TICKS := 180  ## 6 s of focus fire
const MARK_COOLDOWN := 450  ## 15 s from the cast
const MARK_PICK_RADIUS := 40.0  ## px from the clicked point to the target (bosses add their body radius)
const MARK_MAX_DIST := 640.0  ## px from the rig to the target

const RADIO_IDS: PackedStringArray = ["fall_back", "all_in", "hold", "boss"]  ## index = wire value, append only
const RADIO_TICKS := 150  ## 5 s
const RADIO_CHARGES := 3  ## per combat round
const RADIO_LOCK_TICKS := 30  ## minimum gap between two calls

const KIND_NONE := 0
const KIND_ALIEN := 1
const KIND_RIVAL := 2


## Tries to mark the target nearest to `p`. False (nothing changes) on a miss, out of reach or on cooldown.
static func cast_mark(w: SimWorld, v: SimVehicle, p: Vector2) -> bool:
	if v.mark_order_cd > 0 or not v.alive or v.eliminated:
		return false
	var best_kind: int = KIND_NONE
	var best_id: int = -1
	var best_d: float = INF
	var near: int = w.query_enemies(p, MARK_PICK_RADIUS + SimWorld.MAX_ENEMY_RADIUS, w.ai_buf)
	for q in near:
		var e: int = w.ai_buf[q]
		if w.enemy_hp[e] <= 0.0:
			continue
		var k: int = w.enemy_kind[e]
		var reach: float = MARK_PICK_RADIUS + (SimWorld.ENEMY_RADIUS[k] if k >= SimWorld.BOSS_A else 0.0)
		var d: float = p.distance_to(w.enemy_pos[e])
		if d > reach or w.enemy_pos[e].distance_to(v.pos) > MARK_MAX_DIST:
			continue
		if d < best_d or (d == best_d and w.enemy_id[e] < best_id):
			best_d = d
			best_kind = KIND_ALIEN
			best_id = w.enemy_id[e]
	if best_kind == KIND_NONE and w.pvp_enabled():
		for o in w.vehicles:
			if o.id == v.id or not _rival_ok(o):
				continue
			var d2: float = p.distance_to(o.pos)
			if d2 <= MARK_PICK_RADIUS and o.pos.distance_to(v.pos) <= MARK_MAX_DIST and d2 < best_d:
				best_d = d2
				best_kind = KIND_RIVAL
				best_id = o.id
	if best_kind == KIND_NONE:
		return false
	v.mark_order_kind = best_kind
	v.mark_order_id = best_id
	v.mark_order_ticks = MARK_TICKS
	v.mark_order_cd = MARK_COOLDOWN
	var ekind: int = -1
	var at: Vector2 = Vector2.ZERO
	if best_kind == KIND_ALIEN:
		var ei: int = _enemy_index(w, best_id)
		ekind = w.enemy_kind[ei]
		at = w.enemy_pos[ei]
	else:
		at = w.vehicles[best_id].pos
	w._emit("mark", at, v.id, ekind)
	return true


## Combat tick, after the normal targeting: counts the cooldown down and, while the mark is active,
## forces the rig target onto it and makes every gun follow. Ends the order at once if the target is gone.
static func tick(w: SimWorld, v: SimVehicle) -> void:
	if v.mark_order_cd > 0:
		v.mark_order_cd -= 1
	if v.mark_order_ticks <= 0:
		return
	if not active(w, v):
		v.mark_order_ticks = 0
		return
	v.mark_order_ticks -= 1
	v.focus = true
	if v.mark_order_kind == KIND_ALIEN:
		var ei: int = _enemy_index(w, v.mark_order_id)
		v.target_kind = KIND_ALIEN
		v.target_index = ei
		v.target_id = v.mark_order_id
		v.target_pos = w.enemy_pos[ei]
		v.target_vel = w.enemy_vel[ei]
	else:
		var t: SimVehicle = w.vehicles[v.mark_order_id]
		v.target_kind = KIND_RIVAL
		v.target_index = t.id
		v.target_id = t.id
		v.target_pos = t.pos
		v.target_vel = t.vel


## True while the order has ticks left and its target is still valid.
static func active(w: SimWorld, v: SimVehicle) -> bool:
	if v.mark_order_ticks <= 0:
		return false
	if v.mark_order_kind == KIND_ALIEN:
		var ei: int = _enemy_index(w, v.mark_order_id)
		return ei >= 0 and w.enemy_hp[ei] > 0.0
	if v.mark_order_kind == KIND_RIVAL:
		return v.mark_order_id >= 0 and v.mark_order_id < w.vehicles.size() and v.mark_order_id != v.id \
				and _rival_ok(w.vehicles[v.mark_order_id])
	return false


## Where the marked target is now (Vector2.ZERO when there is none).
static func target_pos(w: SimWorld, v: SimVehicle) -> Vector2:
	if v.mark_order_kind == KIND_ALIEN:
		var ei: int = _enemy_index(w, v.mark_order_id)
		return w.enemy_pos[ei] if ei >= 0 else Vector2.ZERO
	if v.mark_order_kind == KIND_RIVAL and v.mark_order_id >= 0 and v.mark_order_id < w.vehicles.size():
		return w.vehicles[v.mark_order_id].pos
	return Vector2.ZERO


## Radio command: overrides the rig's rules and base setting for RADIO_TICKS. False (nothing changes) when
## not in combat, dead, out of charges, locked or on an unknown id. Replaces a running command (costs a charge).
static func cast_radio(w: SimWorld, v: SimVehicle, id: String) -> bool:
	var idx: int = RADIO_IDS.find(id)
	if idx < 0 or w.phase != SimWorld.PHASE_COMBAT or not v.alive or v.eliminated:
		return false
	if v.radio_charges <= 0 or v.radio_lock > 0:
		return false
	v.radio_charges -= 1
	v.radio_ticks = RADIO_TICKS
	v.radio_cmd = idx
	v.radio_lock = RADIO_LOCK_TICKS
	w._emit("radio", v.pos, v.id, idx)
	return true


static func radio_active(v: SimVehicle) -> bool:
	return v.radio_ticks > 0 and v.radio_cmd >= 0 and v.radio_cmd < RADIO_IDS.size()


## "" when no command runs.
static func radio_id(v: SimVehicle) -> String:
	return RADIO_IDS[v.radio_cmd] if radio_active(v) else ""


## Combat tick, right after Doctrine.apply_rig and before targeting: counts the lock and the command down
## and, while it runs, overrides the effective drive / target / focus (beats every rule).
static func radio_tick(v: SimVehicle) -> void:
	if v.radio_lock > 0:
		v.radio_lock -= 1
	if v.radio_ticks <= 0:
		return
	v.radio_ticks -= 1
	match RADIO_IDS[v.radio_cmd] if v.radio_cmd >= 0 and v.radio_cmd < RADIO_IDS.size() else "":
		"fall_back":
			v.eff_drive = "hold" if not Doctrine.action_unlocked(v, "drive:flee") else "flee"
		"all_in":
			v.eff_drive = "charge"
			v.focus = true
		"hold":
			v.eff_drive = "hold"
		"boss":
			v.eff_target = "boss"
			v.focus = true


## Round start / respawn: the radio command ends (charges are refilled only at the round start).
static func reset_radio(v: SimVehicle, refill: bool) -> void:
	v.radio_ticks = 0
	v.radio_cmd = -1
	v.radio_lock = 0
	if refill:
		v.radio_charges = RADIO_CHARGES


## Clears the running order and its cooldown (round start, respawn).
static func reset(v: SimVehicle) -> void:
	v.mark_order_ticks = 0
	v.mark_order_cd = 0
	v.mark_order_kind = 0
	v.mark_order_id = -1


static func _rival_ok(o: SimVehicle) -> bool:
	return o.alive and not o.eliminated and o.invuln_ticks <= 0 and o.smoke_ticks <= 0


static func _enemy_index(w: SimWorld, id: int) -> int:
	for i in w.enemy_count:
		if w.enemy_id[i] == id:
			return i
	return -1
