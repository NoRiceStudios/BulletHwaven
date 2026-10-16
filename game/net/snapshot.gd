class_name Snapshot
extends RefCounted
## Compact binary world snapshot (host -> clients). See docs/architecture.md ("Net contract").
##
## Layout (little endian):
##   header   37 B  version, flags, tick, next_enemy_id, counts, enemy id base,
##                   phase, round, phase_ticks_left, winner_peer, leader_peer, pvp_grace_ticks, fuel_drain
##   vehicles variable (about 160 B each: doctrine strings, weapons, doctrine rules, fuel / flags,
##                   offers, cards, tech (+ purchase rounds, dormant fusions, respecs), player name and colour index). Rules are binary: u8 count,
##                   per rule u8 action (Doctrine.ACTIONS index), u8 conditions, per condition
##                   u8 id (Doctrine.COND_IDS), u8 op (Doctrine.OPS), u16 value
##   events   7 B each  type, owner, kind, pos (u16 x2, 1/16 px, offset by POS_ORIGIN); the type byte's
##                      top bit (EVENT_EXTRA_BIT) adds 2 signed bytes: kill = victim, weapon;
##                      vehicle_destroyed = cause (SimWorld.SRC_*), killer
##   enemies  8 B each  id offset u16, x u16, y u16 (1/16 px), packed u16:
##                      kind 2 bits | hp 4 bits (1..15 of max) | speed 3 bits (0..7 of kind speed) | heading 7 bits
##   projs   13 B each  x u16, y u16 (1/16 px, offset), vx i16, vy i16 (px/s), owner i8, ttl u8 (1/100 s), damage u8 (1/4)
##
## Positions are quantized to 1/16 px (max error POS_ERROR). Enemy velocity is quantized to
## 1/7 of the kind's speed and 128 headings; enemy hp to 1/15 of the kind's max hp (for the
## current round, SimWorld.enemy_max_hp). Card and tech ids are table indices (Cards.DEFS / Tech.DEFS).
## Projectile pierce / splash are not sent: the client world is passive.

const VERSION := 8  # 8: tech v2.3 (dormant fusions, respecs, purchase rounds); 7: doctrine rules (rig + per weapon); 6: positions at 1/16 px (2560x1440 arena); 5: pvp_grace_ticks, fuel_drain, invuln_ticks, round/match stats, event extras
const FLAG_WIDE_IDS := 1  ## enemy ids spread over more than 65535: ids are sent as u32 deltas from 0
const FLAG_STATS := 2  ## vehicles carry round_stats and match_stats (sent outside combat only)
const EVENT_EXTRA_BIT := 0x80
const EVENT_EXTRAS := {"kill": ["victim", "weapon"], "vehicle_destroyed": ["cause", "killer"]}
const MAX_DEATHS := 16
const MAX_ROUND_PLAYERS := 16

const POS_SCALE := 16.0  ## u16 / 16 covers 4096 px: the arena plus POS_ORIGIN must stay below that
const POS_ORIGIN := 64.0  ## added to projectile/event coordinates (they may leave the arena slightly)
const POS_ERROR := 1.0 / 32.0

const HEADER_BYTES := 37
const ENEMY_BYTES := 8
const WIDE_ENEMY_BYTES := 10
const PROJ_BYTES := 13
const EVENT_BYTES := 7

const MAX_VEHICLES := 64  ## vehicle ids travel as u8 / i8 owners, keep well below 127
const EVENT_TYPES: PackedStringArray = ["fire", "hit", "kill", "vehicle_destroyed", "retreat", "respawn", "spit", "pvp_on", "bounty", "drain"]
const MAX_ROUND := 65535
const SPEED_STEPS := 7
const HEADING_STEPS := 128
const HP_STEPS := 15
const TTL_SCALE := 100.0  # u8: up to 2.55 s (acid lives about 1.8 s)
const DAMAGE_SCALE := 4.0


## Encodes the world. `p_events` overrides `world.events` when non-empty (the host passes the
## events accumulated since the last snapshot, since snapshots go out every 2 ticks).
static func encode(world: SimWorld, p_events: Array[Dictionary] = []) -> PackedByteArray:
	var evs: Array[Dictionary] = p_events if not p_events.is_empty() else world.events
	var n_enemy: int = mini(world.enemy_count, world.enemy_id.size())
	var n_proj: int = mini(world.proj_count, world.proj_pos.size())
	var n_veh: int = mini(world.vehicles.size(), MAX_VEHICLES)
	var n_evt: int = mini(evs.size(), SimWorld.MAX_EVENTS)

	var id_min: int = 0
	var id_max: int = 0
	if n_enemy > 0:
		id_min = world.enemy_id[0]
		id_max = id_min
		for i in n_enemy:
			var eid: int = world.enemy_id[i]
			if eid < id_min:
				id_min = eid
			elif eid > id_max:
				id_max = eid
	var wide: bool = (id_max - id_min) > 65535
	var flags: int = FLAG_WIDE_IDS if wide else 0
	var with_stats: bool = world.phase != SimWorld.PHASE_COMBAT
	if with_stats:
		flags |= FLAG_STATS
	if wide:
		id_min = 0

	var sp := StreamPeerBuffer.new()
	sp.put_u8(VERSION)
	sp.put_u8(flags)
	sp.put_u32(world.tick)
	sp.put_u32(world.next_enemy_id)
	sp.put_u8(n_veh)
	sp.put_u16(n_evt)
	sp.put_u16(n_enemy)
	sp.put_u16(n_proj)
	sp.put_u32(id_min)
	sp.put_u8(clampi(world.phase, 0, SimWorld.PHASE_GAME_OVER))
	sp.put_u16(clampi(world.round, 1, MAX_ROUND))
	sp.put_u16(clampi(world.phase_ticks_left, 0, 65535))
	sp.put_32(world.winner_peer)
	sp.put_32(world.leader_peer)
	sp.put_u16(clampi(world.pvp_grace_ticks, 0, 65535))
	sp.put_u8(clampi(world.fuel_drain, 0, 255))

	for vi in n_veh:
		_put_vehicle(sp, world.vehicles[vi], with_stats)

	for ei in n_evt:
		var e: Dictionary = evs[ei]
		var tix: int = EVENT_TYPES.find(str(e.get("type", "")))
		var epos: Vector2 = e.get("pos", Vector2.ZERO)
		var etype: String = str(e.get("type", ""))
		var keys: Array = EVENT_EXTRAS.get(etype, [])
		var has_extra: bool = not keys.is_empty() and e.has(keys[0])
		sp.put_u8(maxi(tix, 0) | (EVENT_EXTRA_BIT if has_extra else 0))
		sp.put_8(clampi(int(e.get("owner", -1)), -1, 127))
		sp.put_8(clampi(int(e.get("kind", -1)), -1, 127))
		sp.put_u16(_q_off(epos.x))
		sp.put_u16(_q_off(epos.y))
		if has_extra:
			sp.put_8(clampi(int(e.get(keys[0], -1)), -1, 127))
			sp.put_8(clampi(int(e.get(keys[1], -1)), -1, 127))

	var out: PackedByteArray = sp.data_array

	var estride: int = WIDE_ENEMY_BYTES if wide else ENEMY_BYTES
	var head_size: int = out.size()
	out.resize(head_size + n_enemy * estride + n_proj * PROJ_BYTES)
	var o: int = head_size
	for i in n_enemy:
		var kind: int = world.enemy_kind[i]
		var p: Vector2 = world.enemy_pos[i]
		var vel: Vector2 = world.enemy_vel[i]
		var max_speed: float = SimWorld.ENEMY_SPEED[kind]
		var spd: int = clampi(roundi(vel.length() / max_speed * SPEED_STEPS), 0, SPEED_STEPS)
		var ang: int = 0
		if spd > 0:
			ang = roundi(vel.angle() / TAU * HEADING_STEPS) & (HEADING_STEPS - 1)
		var hpl: int = clampi(ceili(world.enemy_hp[i] / SimWorld.enemy_max_hp(kind, world.round) * HP_STEPS), 1, HP_STEPS)
		var packed: int = (kind & 3) | (hpl << 2) | (spd << 6) | (ang << 9)
		if wide:
			out.encode_u32(o, world.enemy_id[i])
			o += 4
		else:
			out.encode_u16(o, world.enemy_id[i] - id_min)
			o += 2
		out.encode_u16(o, _q(p.x))
		out.encode_u16(o + 2, _q(p.y))
		out.encode_u16(o + 4, packed)
		o += 6
	for i in n_proj:
		var pp: Vector2 = world.proj_pos[i]
		var pv: Vector2 = world.proj_vel[i]
		out.encode_u16(o, _q_off(pp.x))
		out.encode_u16(o + 2, _q_off(pp.y))
		out.encode_s16(o + 4, clampi(roundi(pv.x), -32768, 32767))
		out.encode_s16(o + 6, clampi(roundi(pv.y), -32768, 32767))
		out.encode_s8(o + 8, clampi(world.proj_owner[i], -1, 127))
		out.encode_u8(o + 9, clampi(roundi(world.proj_ttl[i] * TTL_SCALE), 0, 255))
		out.encode_u8(o + 10, clampi(roundi(world.proj_damage[i] * DAMAGE_SCALE), 0, 255))
		o += PROJ_BYTES
	return out


## Rewrites `world` from `bytes` and calls `world.rebuild_derived()`. Returns false (leaving the
## world untouched) if the data is malformed or from another snapshot version.
static func apply(world: SimWorld, bytes: PackedByteArray) -> bool:
	var r := _Reader.new(bytes)
	if r.u8() != VERSION:
		return false
	var flags: int = r.u8()
	var tick: int = r.u32()
	var next_id: int = r.u32()
	var n_veh: int = r.u8()
	var n_evt: int = r.u16()
	var n_enemy: int = r.u16()
	var n_proj: int = r.u16()
	var id_base: int = r.u32()
	var phase: int = r.u8()
	var round_n: int = r.u16()
	var phase_left: int = r.u16()
	var winner: int = r.s32()
	var leader: int = r.s32()
	var grace: int = r.u16()
	var drain: int = r.u8()
	var with_stats: bool = (flags & FLAG_STATS) != 0
	if not r.ok or n_veh > MAX_VEHICLES or phase > SimWorld.PHASE_GAME_OVER or round_n < 1:
		return false
	var wide: bool = (flags & FLAG_WIDE_IDS) != 0

	var vehicles: Array[SimVehicle] = []
	for vi in n_veh:
		var v: SimVehicle = _get_vehicle(r, with_stats)
		if not r.ok:
			return false
		vehicles.append(v)

	var events: Array[Dictionary] = []
	for ei in n_evt:
		var tbyte: int = r.u8()
		var tix: int = tbyte & (EVENT_EXTRA_BIT - 1)
		var owner: int = r.s8()
		var kind: int = r.s8()
		var ex: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
		var ey: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
		var ev := {}
		if not r.ok or tix >= EVENT_TYPES.size():
			return false
		ev = {"type": EVENT_TYPES[tix], "pos": Vector2(ex, ey), "owner": owner, "kind": kind}
		if (tbyte & EVENT_EXTRA_BIT) != 0:
			var keys: Array = EVENT_EXTRAS.get(EVENT_TYPES[tix], [])
			if keys.is_empty():
				return false
			ev[keys[0]] = r.s8()
			ev[keys[1]] = r.s8()
			if not r.ok:
				return false
		events.append(ev)

	var estride: int = WIDE_ENEMY_BYTES if wide else ENEMY_BYTES
	if not r.has(n_enemy * estride + n_proj * PROJ_BYTES):
		return false
	var data: PackedByteArray = bytes
	var o: int = r.pos

	var e_id := PackedInt32Array()
	var e_kind := PackedByteArray()
	var e_pos := PackedVector2Array()
	var e_vel := PackedVector2Array()
	var e_hp := PackedFloat32Array()
	e_id.resize(n_enemy)
	e_kind.resize(n_enemy)
	e_pos.resize(n_enemy)
	e_vel.resize(n_enemy)
	e_hp.resize(n_enemy)
	for i in n_enemy:
		if wide:
			e_id[i] = data.decode_u32(o)
			o += 4
		else:
			e_id[i] = id_base + data.decode_u16(o)
			o += 2
		var px: float = float(data.decode_u16(o)) / POS_SCALE
		var py: float = float(data.decode_u16(o + 2)) / POS_SCALE
		var packed: int = data.decode_u16(o + 4)
		o += 6
		var kind: int = packed & 3
		if kind > SimWorld.SPITTER:
			return false
		var hpl: int = (packed >> 2) & 15
		var spd: int = (packed >> 6) & 7
		var ang: int = (packed >> 9) & 127
		e_kind[i] = kind
		e_pos[i] = Vector2(px, py)
		if spd > 0:
			var speed: float = SimWorld.ENEMY_SPEED[kind] * float(spd) / SPEED_STEPS
			e_vel[i] = Vector2.from_angle(float(ang) * TAU / HEADING_STEPS) * speed
		e_hp[i] = SimWorld.enemy_max_hp(kind, round_n) * float(hpl) / HP_STEPS

	var p_pos := PackedVector2Array()
	var p_vel := PackedVector2Array()
	var p_ttl := PackedFloat32Array()
	var p_dmg := PackedFloat32Array()
	var p_owner := PackedInt32Array()
	p_pos.resize(n_proj)
	p_vel.resize(n_proj)
	p_ttl.resize(n_proj)
	p_dmg.resize(n_proj)
	p_owner.resize(n_proj)
	var p_pierce := PackedByteArray()
	var p_splash := PackedFloat32Array()
	var p_last := PackedInt32Array()
	p_pierce.resize(n_proj)
	p_splash.resize(n_proj)
	p_last.resize(n_proj)
	p_last.fill(-1)
	for i in n_proj:
		p_pos[i] = Vector2(
			float(data.decode_u16(o)) / POS_SCALE - POS_ORIGIN,
			float(data.decode_u16(o + 2)) / POS_SCALE - POS_ORIGIN)
		p_vel[i] = Vector2(float(data.decode_s16(o + 4)), float(data.decode_s16(o + 6)))
		p_owner[i] = data.decode_s8(o + 8)
		p_ttl[i] = float(data.decode_u8(o + 9)) / TTL_SCALE
		p_dmg[i] = float(data.decode_u8(o + 10)) / DAMAGE_SCALE
		o += PROJ_BYTES

	# Commit.
	world.tick = tick
	world.next_enemy_id = next_id
	world.phase = phase
	world.round = round_n
	world.phase_ticks_left = phase_left
	world.winner_peer = winner
	world.leader_peer = leader
	world.pvp_grace_ticks = grace
	world.fuel_drain = drain
	_commit_vehicles(world, vehicles)
	world.events = events
	world.enemy_id = e_id
	world.enemy_kind = e_kind
	world.enemy_pos = e_pos
	world.enemy_vel = e_vel
	world.enemy_hp = e_hp
	world.proj_pos = p_pos
	world.proj_vel = p_vel
	world.proj_ttl = p_ttl
	world.proj_damage = p_dmg
	world.proj_owner = p_owner
	world.proj_pierce = p_pierce
	world.proj_splash = p_splash
	world.proj_last = p_last
	world.rebuild_derived()
	return true


# ---------------------------------------------------------------- helpers

static func _q(v: float) -> int:
	return clampi(roundi(v * POS_SCALE), 0, 65535)


static func _q_off(v: float) -> int:
	return clampi(roundi((v + POS_ORIGIN) * POS_SCALE), 0, 65535)


static func _put_str(sp: StreamPeerBuffer, s: String) -> void:
	var b: PackedByteArray = s.to_utf8_buffer()
	if b.size() > 255:
		b = b.slice(0, 255)
	sp.put_u8(b.size())
	if b.size() > 0:
		sp.put_data(b)


static func _put_vehicle(sp: StreamPeerBuffer, v: SimVehicle, with_stats: bool = false) -> void:
	sp.put_u8(v.id)
	sp.put_32(v.peer_id)
	_put_str(sp, v.player_name)
	sp.put_u8(clampi(v.color_index, 0, SimVehicle.COLOR_COUNT - 1))
	sp.put_float(v.pos.x)
	sp.put_float(v.pos.y)
	sp.put_float(v.vel.x)
	sp.put_float(v.vel.y)
	sp.put_float(v.heading)
	sp.put_float(v.hp)
	sp.put_float(v.max_hp)
	sp.put_u8(1 if v.alive else 0)
	sp.put_u32(v.scrap)
	sp.put_u32(v.kills)
	sp.put_float(v.ram_damage)
	sp.put_u8(v.target_kind)
	sp.put_32(v.target_id)
	sp.put_float(v.target_pos.x)
	sp.put_float(v.target_pos.y)
	sp.put_u8(mini(v.doctrine.size(), 255))
	var written: int = 0
	for k: Variant in v.doctrine:
		if written >= 255:
			break
		_put_str(sp, str(k))
		_put_str(sp, str(v.doctrine[k]))
		written += 1
	sp.put_u8(mini(v.weapons.size(), 255))
	var wn: int = 0
	for w in v.weapons:
		if wn >= 255:
			break
		_put_str(sp, str(w.get("kind", "mg")))
		sp.put_float(float(w.get("damage", 0.0)))
		sp.put_float(float(w.get("range", 0.0)))
		sp.put_u16(int(w.get("cooldown_ticks", 0)))
		sp.put_u16(int(w.get("cooldown", 0)))
		sp.put_float(float(w.get("aim", 0.0)))
		sp.put_u8(clampi(int(w.get("pellets", 1)), 0, 255))
		sp.put_float(float(w.get("spread", 0.0)))
		sp.put_u8(clampi(int(w.get("pierce", 0)), 0, 255))
		sp.put_float(float(w.get("splash", 0.0)))
		sp.put_float(float(w.get("speed", 0.0)))
		sp.put_u8(clampi(int(w.get("live", 0)), 0, 255))
		wn += 1
	sp.put_u8(clampi(v.rule_live, 0, 255))
	_put_rules(sp, v.rules)
	var kinds: Array = []
	for k: String in v.weapon_doctrine:
		if Doctrine.is_weapon_scope(k) and kinds.size() < 255:
			kinds.append(k)
	sp.put_u8(kinds.size())
	for k: String in kinds:
		var wd: Dictionary = v.weapon_doctrine[k]
		_put_str(sp, k)
		sp.put_u8(maxi(Doctrine.WEAPON_TARGETS.find(str(wd["target"])), 0))
		_put_rules(sp, wd["rules"])
	sp.put_u16(clampi(v.fuel, 0, 65535))
	sp.put_u16(clampi(v.respawn_ticks, 0, 65535))
	sp.put_u8((1 if v.eliminated else 0) | (2 if v.ready else 0) | (4 if v.picked else 0))
	sp.put_u16(clampi(v.reroll_cost, 0, 65535))
	sp.put_float(v.scrap_frac)
	var offer_ix: Array[int] = []
	for oid in v.offers:
		var oi: int = Cards.index_of(oid)
		if oi >= 0 and offer_ix.size() < 255:
			offer_ix.append(oi)
	sp.put_u8(offer_ix.size())
	for oi in offer_ix:
		sp.put_u8(oi)
	var card_ix: Array[int] = []
	var card_lv: Array[int] = []
	for cid: String in v.cards:
		var ci: int = Cards.index_of(cid)
		if ci >= 0 and card_ix.size() < 255:
			card_ix.append(ci)
			card_lv.append(clampi(int(v.cards[cid]), 1, Cards.MAX_LEVEL))
	sp.put_u8(card_ix.size())
	for k in card_ix.size():
		sp.put_u8(card_ix[k])
		sp.put_u8(card_lv[k])
	var tech_ix: Array[int] = []
	var tech_rd: Array[int] = []
	for tid in v.tech:
		var ti: int = Tech.index_of(tid)
		if ti >= 0 and tech_ix.size() < 255:
			tech_ix.append(ti)
			tech_rd.append(clampi(int(v.tech_round.get(tid, 0)), 0, 255))
	sp.put_u8(tech_ix.size())
	for k in tech_ix.size():
		sp.put_u8(tech_ix[k])
		sp.put_u8(tech_rd[k])  # purchase round (keystone respec window)
	var dormant_ix: Array[int] = []
	for tid in v.tech_dormant:
		var di: int = Tech.index_of(tid)
		if di >= 0 and dormant_ix.size() < 255:
			dormant_ix.append(di)
	sp.put_u8(dormant_ix.size())
	for di in dormant_ix:
		sp.put_u8(di)
	sp.put_u8(clampi(v.respecs, 0, 255))
	sp.put_u8(clampi(v.protect_ticks, 0, 255))
	sp.put_u8(clampi(v.invuln_ticks, 0, 255))
	if with_stats:
		_put_stats(sp, v)


## Round and match stats of one vehicle (see SimWorld.new_round_stats / new_match_stats).
static func _put_stats(sp: StreamPeerBuffer, v: SimVehicle) -> void:
	var rs: Dictionary = v.round_stats
	var tk: Dictionary = rs.get("taken", {})
	sp.put_u16(clampi(int(rs.get("round", 0)), 0, 65535))
	for key in ["mite", "boulder", "spitter", "acid", "rival"]:
		sp.put_u16(clampi(roundi(float(tk.get(key, 0.0))), 0, 65535))
	var tp: Dictionary = rs.get("taken_players", {})
	var tp_ids: Array = tp.keys()
	tp_ids.sort()
	if tp_ids.size() > MAX_ROUND_PLAYERS:
		tp_ids.resize(MAX_ROUND_PLAYERS)
	sp.put_u8(tp_ids.size())
	for pid: int in tp_ids:
		sp.put_u8(clampi(pid, 0, 255))
		sp.put_u16(clampi(roundi(float(tp[pid])), 0, 65535))
	sp.put_u32(clampi(roundi(float(rs.get("dealt", 0.0))), 0, 0x7fffffff))
	sp.put_u32(clampi(roundi(float(rs.get("dealt_players", 0.0))), 0, 0x7fffffff))
	sp.put_u16(clampi(int(rs.get("kills", 0)), 0, 65535))
	sp.put_u16(clampi(int(rs.get("kills_players", 0)), 0, 65535))
	var deaths: Array = rs.get("deaths", [])
	var nd: int = mini(deaths.size(), MAX_DEATHS)
	sp.put_u8(nd)
	for i in nd:
		var d: Dictionary = deaths[i]
		sp.put_u16(clampi(int(d.get("t", 0)), 0, 65535))
		sp.put_u8(clampi(int(d.get("src", 0)), 0, 255))
		sp.put_8(clampi(int(d.get("killer", -1)), -1, 127))
		sp.put_8(clampi(int(d.get("killer_kind", -1)), -1, 127))
	sp.put_u16(clampi(int(rs.get("fuel_lost", 0)), 0, 65535))
	sp.put_u16(clampi(int(rs.get("fuel_gained", 0)), 0, 65535))
	sp.put_u16(clampi(int(rs.get("fuel_drained", 0)), 0, 65535))
	sp.put_u32(clampi(int(rs.get("scrap_earned", 0)), 0, 0x7fffffff))
	sp.put_u16(clampi(int(rs.get("interest", 0)), 0, 65535))
	var ms: Dictionary = v.match_stats
	sp.put_u32(clampi(int(ms.get("kills", 0)), 0, 0x7fffffff))
	sp.put_u16(clampi(int(ms.get("player_kills", 0)), 0, 65535))
	sp.put_u16(clampi(int(ms.get("ram_kills", 0)), 0, 65535))
	sp.put_u16(clampi(int(ms.get("deaths", 0)), 0, 65535))
	sp.put_u32(clampi(roundi(float(ms.get("dmg_dealt", 0.0))), 0, 0x7fffffff))
	sp.put_u32(clampi(int(ms.get("scrap_earned", 0)), 0, 0x7fffffff))
	sp.put_8(clampi(int(ms.get("top_victim", -1)), -1, 127))
	sp.put_u16(clampi(int(ms.get("top_victim_n", 0)), 0, 65535))
	sp.put_8(clampi(int(ms.get("nemesis", -1)), -1, 127))
	sp.put_u16(clampi(int(ms.get("nemesis_n", 0)), 0, 65535))


static func _get_stats(r: _Reader, v: SimVehicle) -> void:
	var rs := SimWorld.new_round_stats(r.u16())
	var tk: Dictionary = rs["taken"]
	for key in ["mite", "boulder", "spitter", "acid", "rival"]:
		tk[key] = float(r.u16())
	var ntp: int = r.u8()
	if ntp > MAX_ROUND_PLAYERS:
		r.fail()
		return
	var tp: Dictionary = rs["taken_players"]
	for i in ntp:
		var pid: int = r.u8()
		tp[pid] = float(r.u16())
	rs["dealt"] = float(r.u32())
	rs["dealt_players"] = float(r.u32())
	rs["kills"] = r.u16()
	rs["kills_players"] = r.u16()
	var nd: int = r.u8()
	if nd > MAX_DEATHS:
		r.fail()
		return
	var deaths: Array = rs["deaths"]
	for i in nd:
		var t: int = r.u16()
		var src: int = r.u8()
		var killer: int = r.s8()
		var kk: int = r.s8()
		if src >= SimWorld.SRC_NAMES.size():
			r.fail()
			return
		deaths.append({"t": t, "cause": SimWorld.SRC_NAMES[src], "src": src, "killer": killer, "killer_kind": kk})
	rs["fuel_lost"] = r.u16()
	rs["fuel_gained"] = r.u16()
	rs["fuel_drained"] = r.u16()
	rs["scrap_earned"] = r.u32()
	rs["interest"] = r.u16()
	var ms := SimWorld.new_match_stats()
	ms["kills"] = r.u32()
	ms["player_kills"] = r.u16()
	ms["ram_kills"] = r.u16()
	ms["deaths"] = r.u16()
	ms["dmg_dealt"] = float(r.u32())
	ms["scrap_earned"] = r.u32()
	ms["top_victim"] = r.s8()
	ms["top_victim_n"] = r.u16()
	ms["nemesis"] = r.s8()
	ms["nemesis_n"] = r.u16()
	v.round_stats = rs
	v.match_stats = ms


static func _get_vehicle(r: _Reader, with_stats: bool = false) -> SimVehicle:
	var id: int = r.u8()
	var peer: int = r.s32()
	var v := SimVehicle.new(id, peer, Vector2.ZERO)
	v.player_name = SimVehicle.sanitize_name(r.string())
	var pcolor: int = r.u8()
	if pcolor >= SimVehicle.COLOR_COUNT:
		r.fail()
	v.color_index = pcolor
	v.weapons.clear()
	v.pos = Vector2(r.f32(), r.f32())
	v.vel = Vector2(r.f32(), r.f32())
	v.heading = r.f32()
	v.hp = r.f32()
	v.max_hp = r.f32()
	v.alive = r.u8() != 0
	v.scrap = r.u32()
	v.kills = r.u32()
	v.ram_damage = r.f32()
	v.target_kind = r.u8()
	v.target_id = r.s32()
	v.target_pos = Vector2(r.f32(), r.f32())
	var doc := {}
	var nd: int = r.u8()
	for i in nd:
		var k: String = r.string()
		doc[k] = r.string()
		if not r.ok:
			return v
	v.doctrine = doc
	var nw: int = r.u8()
	for i in nw:
		var kind: String = r.string()
		var dmg: float = r.f32()
		var rng: float = r.f32()
		var cdt: int = r.u16()
		var cd: int = r.u16()
		var aim: float = r.f32()
		var pellets: int = r.u8()
		var spread: float = r.f32()
		var pierce: int = r.u8()
		var splash: float = r.f32()
		var wspeed: float = r.f32()
		var wlive: int = r.u8()
		if not r.ok:
			return v
		v.weapons.append({
			"kind": kind, "damage": dmg, "range": rng, "cooldown_ticks": cdt, "cooldown": cd, "aim": aim,
			"pellets": pellets, "spread": spread, "pierce": pierce, "splash": splash, "speed": wspeed,
			"live": wlive,
		})
	v.rule_live = r.u8()
	v.rules = _get_rules(r, Doctrine.SCOPE_RIG)
	v.weapon_doctrine = {}
	var nwd: int = r.u8()
	for i in nwd:
		var wk: String = r.string()
		var ti: int = r.u8()
		var wrules: Array = _get_rules(r, wk)
		if not r.ok:
			return v
		if Doctrine.is_weapon_scope(wk) and ti < Doctrine.WEAPON_TARGETS.size():
			v.weapon_doctrine[wk] = {"target": Doctrine.WEAPON_TARGETS[ti], "rules": wrules}
	v.fuel = r.u16()
	v.respawn_ticks = r.u16()
	var bits: int = r.u8()
	v.eliminated = (bits & 1) != 0
	v.ready = (bits & 2) != 0
	v.picked = (bits & 4) != 0
	v.reroll_cost = r.u16()
	v.scrap_frac = r.f32()
	var offers: Array[String] = []
	var no: int = r.u8()
	for i in no:
		var oid: String = Cards.id_at(r.u8())
		if oid == "":
			r.fail()
		offers.append(oid)
	v.offers = offers
	var cards := {}
	var nc: int = r.u8()
	for i in nc:
		var cid: String = Cards.id_at(r.u8())
		var lvl: int = r.u8()
		if cid == "" or lvl < 1 or lvl > Cards.MAX_LEVEL:
			r.fail()
		cards[cid] = lvl
	v.cards = cards
	var tech: Array[String] = []
	var tech_round := {}
	var nt: int = r.u8()
	for i in nt:
		var tid: String = Tech.id_at(r.u8())
		var trd: int = r.u8()
		if tid == "":
			r.fail()
		tech.append(tid)
		tech_round[tid] = trd
	v.tech = tech
	v.tech_round = tech_round
	var dormant: Array[String] = []
	var ndorm: int = r.u8()
	for i in ndorm:
		var did: String = Tech.id_at(r.u8())
		if did == "":
			r.fail()
		dormant.append(did)
	v.tech_dormant = dormant
	v.respecs = r.u8()
	v.protect_ticks = r.u8()
	v.invuln_ticks = r.u8()
	if with_stats:
		_get_stats(r, v)
	else:
		v.round_stats = {}  # not sent during combat: _commit_vehicles keeps the receiver's copy
		v.match_stats = {}
	if r.ok:
		# Derived stats follow from cards + tech; weapons and hp are exactly as sent.
		Cards.recompute(v, false, false)
	return v


## Updates existing SimVehicle objects in place when ids line up (so render keeps references).
static func _commit_vehicles(world: SimWorld, fresh: Array[SimVehicle]) -> void:
	var cur: Array[SimVehicle] = world.vehicles
	for i in fresh.size():
		var src: SimVehicle = fresh[i]
		if i < cur.size() and cur[i].id == src.id:
			var dst: SimVehicle = cur[i]
			dst.peer_id = src.peer_id
			dst.player_name = src.player_name
			dst.color_index = src.color_index
			dst.pos = src.pos
			dst.vel = src.vel
			dst.heading = src.heading
			dst.hp = src.hp
			dst.max_hp = src.max_hp
			dst.alive = src.alive
			dst.scrap = src.scrap
			dst.kills = src.kills
			dst.doctrine = src.doctrine
			dst.rules = src.rules
			dst.weapon_doctrine = src.weapon_doctrine
			dst.rule_live = src.rule_live
			dst.weapons = src.weapons
			dst.target_kind = src.target_kind
			dst.target_id = src.target_id
			dst.target_pos = src.target_pos
			dst.ram_damage = src.ram_damage
			dst.fuel = src.fuel
			dst.respawn_ticks = src.respawn_ticks
			dst.eliminated = src.eliminated
			dst.ready = src.ready
			dst.picked = src.picked
			dst.reroll_cost = src.reroll_cost
			dst.scrap_frac = src.scrap_frac
			dst.offers = src.offers
			dst.cards = src.cards
			dst.tech = src.tech
			dst.tech_dormant = src.tech_dormant
			dst.tech_round = src.tech_round
			dst.respecs = src.respecs
			dst.tech_fx = src.tech_fx
			dst.chassis = src.chassis
			dst.armor = src.armor
			dst.speed = src.speed
			dst.turn_rate = src.turn_rate
			dst.scrap_mult = src.scrap_mult
			dst.regen = src.regen
			dst.contact_damage = src.contact_damage
			dst.ram_mult = src.ram_mult
			dst.vulture = src.vulture
			dst.weapon_slots = src.weapon_slots
			dst.interest_cap = src.interest_cap
			dst.protect_ticks = src.protect_ticks
			dst.invuln_ticks = src.invuln_ticks
			dst.contact_reduction = src.contact_reduction
			dst.thorns = src.thorns
			if not src.round_stats.is_empty():
				dst.round_stats = src.round_stats
				dst.match_stats = src.match_stats
		else:
			if src.round_stats.is_empty():
				src.round_stats = SimWorld.new_round_stats(1)
				src.match_stats = SimWorld.new_match_stats()
			if i < cur.size():
				cur[i] = src
			else:
				cur.append(src)
	while cur.size() > fresh.size():
		cur.pop_back()


## Bounds-checked sequential reader; after a failed read `ok` is false and values are 0.
class _Reader:
	extends RefCounted
	var bytes: PackedByteArray
	var pos: int = 0
	var ok: bool = true

	func _init(p_bytes: PackedByteArray) -> void:
		bytes = p_bytes

	func fail() -> void:
		ok = false

	func has(n: int) -> bool:
		return ok and pos + n <= bytes.size()

	func _take(n: int) -> bool:
		if not has(n):
			ok = false
			return false
		return true

	func u8() -> int:
		if not _take(1):
			return 0
		pos += 1
		return bytes.decode_u8(pos - 1)

	func s8() -> int:
		if not _take(1):
			return 0
		pos += 1
		return bytes.decode_s8(pos - 1)

	func u16() -> int:
		if not _take(2):
			return 0
		pos += 2
		return bytes.decode_u16(pos - 2)

	func u32() -> int:
		if not _take(4):
			return 0
		pos += 4
		return bytes.decode_u32(pos - 4)

	func s32() -> int:
		if not _take(4):
			return 0
		pos += 4
		return bytes.decode_s32(pos - 4)

	func f32() -> float:
		if not _take(4):
			return 0.0
		pos += 4
		return bytes.decode_float(pos - 4)

	func string() -> String:
		var n: int = u8()
		if n == 0 or not _take(n):
			return ""
		pos += n
		return bytes.slice(pos - n, pos).get_string_from_utf8()


## Doctrine rules in the binary form (see the layout above). Unknown entries are skipped on read.
static func _put_rules(sp: StreamPeerBuffer, rules: Array) -> void:
	var n: int = mini(rules.size(), Doctrine.MAX_SLOTS)
	sp.put_u8(n)
	for i in n:
		var rule: Dictionary = rules[i]
		var conds: Array = rule["if"]
		var nc: int = mini(conds.size(), Doctrine.MAX_CONDS)
		sp.put_u8(maxi(Doctrine.ACTIONS.find(str(rule["do"])), 0))
		sp.put_u8(nc)
		for j in nc:
			var c: Array = conds[j]
			sp.put_u8(maxi(Doctrine.COND_IDS.find(str(c[0])), 0))
			sp.put_u8(maxi(Doctrine.OPS.find(str(c[1])), 0))
			sp.put_u16(clampi(int(c[2]), 0, 65535))


static func _get_rules(r: _Reader, scope: String) -> Array:
	var out: Array = []
	var allowed: PackedStringArray = Doctrine.actions_for(scope)
	var n: int = r.u8()
	if n > Doctrine.MAX_SLOTS:
		r.ok = false
		return out
	for i in n:
		var ai: int = r.u8()
		var nc: int = r.u8()
		if nc > Doctrine.MAX_CONDS:
			r.ok = false
			return out
		var conds: Array = []
		var good: bool = ai < Doctrine.ACTIONS.size() and allowed.has(Doctrine.ACTIONS[ai])
		for j in nc:
			var ci: int = r.u8()
			var oi: int = r.u8()
			var val: int = r.u16()
			if ci >= Doctrine.COND_IDS.size() or oi >= Doctrine.OPS.size():
				good = false
				continue
			var c: Variant = Doctrine.make_cond(Doctrine.COND_IDS[ci], Doctrine.OPS[oi], val)
			if c == null:
				good = false
			else:
				conds.append(c)
		if not r.ok:
			return out
		if good:
			out.append({"if": conds, "do": Doctrine.ACTIONS[ai]})
	return out
