class_name Zones
extends RefCounted
## PvP control zones (design doc section 8, "Contested objectives"). From round SimWorld.PVP_START_ROUND on,
## every multiplayer combat places 1..3 circular zones between the rig spawn ring and the arena centre. A rig
## that stands alone in a zone for CAPTURE_TICKS takes it; while it owns the zone and stands inside it scores
## scrap. Zones are visible but locked until PvP is on (the round-4 grace). Pure and deterministic: the only
## randomness is `world.rng` at placement. State lives on SimWorld (`zones`, `zones_active`) and SimVehicle
## (`zone_ticks`); stats in round_stats / match_stats "zone_points".

const MAX_ZONES := 3
const ZONE_RADIUS := 110.0  ## px
const CAPTURE_TICKS := 90  ## 3 s alone inside to take a zone
const ZONE_SCRAP_PER_SEC := 1  ## scrap per full second held inside (flat, not scrap_mult)
const ZONE_FUEL_BONUS := 5  ## fuel for the best holder at the end of the round
const ZONE_FUEL_MIN_POINTS := 10  ## zone_points needed (this round) for the fuel bonus
const ZONE_MIN_SPACING := 320.0  ## px between zone centres
const ZONE_CENTRE_REACH := Vector2(560.0, 300.0)  ## zones lie inside this ellipse around the arena centre
const PLACE_ATTEMPTS := 40
const INTRUDER_MARGIN := 60.0  ## target:intruders also takes rivals this far outside a zone


## Fresh zone record.
static func make_zone(pos: Vector2) -> Dictionary:
	return {"pos": pos, "owner": -1, "cap_id": -1, "cap_ticks": 0, "contested": false}


## Combat start: clears the old zones and, in a multiplayer game from PVP_START_ROUND, places new ones with
## `world.rng`. Resets every rig's zone_ticks. Zones start locked (`zones_active` false); tick() unlocks them.
static func setup(w: SimWorld) -> void:
	w.zones = []
	w.zones_active = false
	for v in w.vehicles:
		v.zone_ticks = 0
	if w.round < SimWorld.PVP_START_ROUND or w.vehicles.size() < 2:
		return
	var rigs: int = 0
	for v in w.vehicles:
		if not v.eliminated:
			rigs += 1
	var n: int = clampi(rigs - 1, 1, MAX_ZONES)
	var c: Vector2 = SimWorld.ARENA.get_center()
	for i in n:
		var spot: Vector2 = Vector2.ZERO
		var found: bool = false
		for _a in PLACE_ATTEMPTS:
			var ang: float = w.rng.randf() * TAU
			var rad: float = sqrt(w.rng.randf())
			var p: Vector2 = c + Vector2(cos(ang) * ZONE_CENTRE_REACH.x, sin(ang) * ZONE_CENTRE_REACH.y) * rad
			if _spaced(w, p):
				spot = p
				found = true
				break
		if not found:  # deterministic fallback: spread on a ring
			var fa: float = TAU * (float(i) / float(n)) + 0.5
			spot = c + Vector2(cos(fa) * ZONE_CENTRE_REACH.x, sin(fa) * ZONE_CENTRE_REACH.y) * 0.6
		w.zones.append(make_zone(spot))
	if w.pvp_enabled():  # fast rounds / later rounds: no grace, the zones are live at once
		w.zones_active = true
		w._emit("zones_open", c, -1, w.zones.size())


static func _spaced(w: SimWorld, p: Vector2) -> bool:
	for z: Dictionary in w.zones:
		if (z["pos"] as Vector2).distance_to(p) < ZONE_MIN_SPACING:
			return false
	return true


## One combat tick (after the vehicles moved): unlocks the zones with PvP, then captures and scores.
static func tick(w: SimWorld) -> void:
	if w.zones.is_empty():
		return
	if not w.zones_active:
		if not w.pvp_enabled():
			return
		w.zones_active = true
		w._emit("zones_open", SimWorld.ARENA.get_center(), -1, w.zones.size())
	for zi in w.zones.size():
		var z: Dictionary = w.zones[zi]
		var zp: Vector2 = z["pos"]
		var occ: int = 0
		var who: SimVehicle = null
		for v in w.vehicles:
			if v.alive and not v.eliminated and v.pos.distance_squared_to(zp) <= ZONE_RADIUS * ZONE_RADIUS:
				occ += 1
				who = v
		if occ == 0:
			z["contested"] = false
			if int(z["cap_ticks"]) > 0:
				z["cap_ticks"] = int(z["cap_ticks"]) - 1
				if int(z["cap_ticks"]) == 0:
					z["cap_id"] = -1
			continue
		if occ >= 2:
			z["contested"] = true
			continue
		z["contested"] = false
		if who.id == int(z["owner"]):
			z["cap_id"] = -1  # the owner standing in it breaks any capture attempt
			z["cap_ticks"] = 0
			_score(w, who)
		elif int(z["cap_id"]) == who.id:
			z["cap_ticks"] = int(z["cap_ticks"]) + 1
			if int(z["cap_ticks"]) >= CAPTURE_TICKS:
				var prev: int = int(z["owner"])
				z["owner"] = who.id
				z["cap_id"] = -1
				z["cap_ticks"] = 0
				w._emit("zone_captured", zp, who.id, zi, {"prev": prev, "count": held_by(w, who)})
		else:
			z["cap_id"] = who.id
			z["cap_ticks"] = 1


static func _score(w: SimWorld, v: SimVehicle) -> void:
	v.zone_ticks += 1
	if v.zone_ticks % SimWorld.TICK_RATE != 0:
		return
	var n: int = ZONE_SCRAP_PER_SEC
	v.scrap += n
	w._note_scrap(v, n)
	v.round_stats["zone_points"] = int(v.round_stats.get("zone_points", 0)) + n
	v.match_stats["zone_points"] = int(v.match_stats.get("zone_points", 0)) + n


## Combat end (before the field is cleared): the strictly best holder this round (>= ZONE_FUEL_MIN_POINTS) gets
## ZONE_FUEL_BONUS fuel and a "zone_bonus" event (owner = vehicle id, kind = fuel gained, only when > 0). Clears the zones.
static func finish(w: SimWorld) -> void:
	if not w.zones.is_empty():
		var best: SimVehicle = null
		var best_pts: int = 0
		var tied: bool = false
		for v in w.vehicles:
			if v.eliminated:
				continue
			var pts: int = int(v.round_stats.get("zone_points", 0))
			if pts > best_pts:
				best_pts = pts
				best = v
				tied = false
			elif pts == best_pts and pts > 0:
				tied = true
		if best != null and not tied and best_pts >= ZONE_FUEL_MIN_POINTS:
			var gain: int = clampi(ZONE_FUEL_BONUS, 0, maxi(SimWorld.START_FUEL - best.fuel, 0))
			if gain > 0:
				best.fuel += gain
				best.round_stats["fuel_gained"] = int(best.round_stats["fuel_gained"]) + gain
				w._emit("zone_bonus", best.pos, best.id, gain)
	w.zones = []
	w.zones_active = false


# ---------------------------------------------------------------- helpers (AI, doctrine, render)

## Index of the zone containing `pos`, or -1.
static func zone_at(w: SimWorld, pos: Vector2) -> int:
	for i in w.zones.size():
		if (w.zones[i]["pos"] as Vector2).distance_squared_to(pos) <= ZONE_RADIUS * ZONE_RADIUS:
			return i
	return -1


## Zone `v` should head for: the nearest active zone it does not own, else the nearest it owns, else -1.
static func goal_zone(w: SimWorld, v: SimVehicle) -> int:
	if not w.zones_active:
		return -1
	var best: int = -1
	var best_d: float = INF
	var own: int = -1
	var own_d: float = INF
	for i in w.zones.size():
		var d: float = v.pos.distance_to(w.zones[i]["pos"])
		if int(w.zones[i]["owner"]) == v.id:
			if d < own_d:
				own_d = d
				own = i
		elif d < best_d:
			best_d = d
			best = i
	return best if best >= 0 else own


## Zones owned by `v`.
static func held_by(w: SimWorld, v: SimVehicle) -> int:
	var n: int = 0
	for z: Dictionary in w.zones:
		if int(z["owner"]) == v.id:
			n += 1
	return n


## Distance to the centre of the nearest active zone `v` does not own, -1 if there is none.
static func nearest_unheld_dist(w: SimWorld, v: SimVehicle) -> float:
	if not w.zones_active:
		return -1.0
	var best: float = -1.0
	for z: Dictionary in w.zones:
		if int(z["owner"]) == v.id:
			continue
		var d: float = v.pos.distance_to(z["pos"])
		if best < 0.0 or d < best:
			best = d
	return best


## Is a rival rig (alive, not eliminated) inside zone `zone_index`?
static func intruder_in(w: SimWorld, v: SimVehicle, zone_index: int) -> bool:
	if zone_index < 0 or zone_index >= w.zones.size():
		return false
	var zp: Vector2 = w.zones[zone_index]["pos"]
	for o in w.vehicles:
		if o.id != v.id and o.alive and not o.eliminated and o.pos.distance_squared_to(zp) <= ZONE_RADIUS * ZONE_RADIUS:
			return true
	return false


## The zone `v` stands in also holds a rival, or a rival is capturing it.
static func contested_for(w: SimWorld, v: SimVehicle) -> bool:
	if not w.zones_active:
		return false
	var zi: int = zone_at(w, v.pos)
	if zi < 0:
		return false
	var cid: int = int(w.zones[zi]["cap_id"])
	return intruder_in(w, v, zi) or (cid >= 0 and cid != v.id and int(w.zones[zi]["cap_ticks"]) > 0)


## Capture progress 0..1 of a zone record (0 when nobody is capturing it).
static func progress(zone: Dictionary) -> float:
	if int(zone["cap_id"]) < 0:
		return 0.0
	return clampf(float(int(zone["cap_ticks"])) / float(CAPTURE_TICKS), 0.0, 1.0)


## Nearest rival rig (vehicle) in range `r` of `v` that stands in (or within INTRUDER_MARGIN of) a zone `v`
## is in or owns; null if none. Used by target:intruders. Rivals under protection / smoke are skipped.
static func nearest_intruder(w: SimWorld, v: SimVehicle, r: float) -> SimVehicle:
	if not w.zones_active:
		return null
	var best: SimVehicle = null
	var best_d2: float = r * r
	var reach: float = ZONE_RADIUS + INTRUDER_MARGIN
	for zi in w.zones.size():
		var zp: Vector2 = w.zones[zi]["pos"]
		if int(w.zones[zi]["owner"]) != v.id and zp.distance_squared_to(v.pos) > ZONE_RADIUS * ZONE_RADIUS:
			continue
		for o in w.vehicles:
			if o.id == v.id or not o.alive or o.eliminated or o.invuln_ticks > 0 or o.smoke_ticks > 0:
				continue
			if o.pos.distance_squared_to(zp) > reach * reach:
				continue
			var d2: float = v.pos.distance_squared_to(o.pos)
			if d2 < best_d2 or (d2 == best_d2 and best != null and o.id < best.id):
				best_d2 = d2
				best = o
	return best
