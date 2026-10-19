class_name Snapshot
extends RefCounted
## Compact binary world snapshot (host -> clients). See docs/architecture.md ("Net contract").
##
## Layout (little endian):
##   header   38 B  version, flags, tick, next_enemy_id, counts, enemy id base,
##                   phase, round, phase_ticks_left, winner_peer, leader_peer, pvp_grace_ticks, fuel_drain, zone count
##   (header ends with u8 boss_first, u16 hive signature: 3 bits first round per species, Glass Wings lowest)
##   zones    u8 count, per zone 9 B: x, y u16 (1/16 px, offset), radius u8 (px), kind u8, ttl u16, owner i8
##   vehicles variable (about 160 B each: doctrine strings, weapons (with heat, jam, switch pause, loaded ammo), doctrine rules, fuel / flags,
##                   offers, cards, tech (+ purchase rounds, dormant fusions, respecs), player name and colour index). Rules are binary: u8 count,
##                   per rule u8 action (Doctrine.ACTIONS index), u8 conditions, per condition
##                   u8 id (Doctrine.COND_IDS), u8 op (Doctrine.OPS), u16 value
##   events   7 B each  type, owner, kind, pos (u16 x2, 1/16 px, offset by POS_ORIGIN); the type byte's
##                      top bit (EVENT_EXTRA_BIT) adds 2 signed bytes: kill = victim, weapon;
##                      vehicle_destroyed = cause (SimWorld.SRC_*), killer
##   enemies  8 B each  id offset u16, x u16, y u16 (1/16 px), packed u16:
##                      kind 3 bits (0..5 = SimWorld kinds, 6 = a boss body) | hp 4 bits (1..15 of max) | speed 3 bits (0..7 of kind speed) | heading 6 bits
##   projs   13 B each  x u16, y u16 (1/16 px, offset), vx i16, vy i16 (px/s), owner i8, ttl u8 (1/100 s), damage u8 (1/4)
##   burning ceil(enemies / 8) B (only with FLAG_BURNING): bit i set = enemy i burns (burn dps and owner are host-side)
##   stunned ceil(enemies / 8) B (only with FLAG_STUNNED): bit i set = enemy i is EMP-stunned
##   boss     (only with FLAG_BOSS) u8 kind, u8 state, u8 phase, u8 flags (bit 0 enraged), u32 max hp, u16 hp fraction (1/1000), u16 warn ticks,
##            u16 x, y spawn point (1/16 px, offset), u8 bodies: per body u16 enemy index, u8 real kind (the enemy table sends 6 for every
##            boss kind), u32 hp; u8 markers: per marker u8 kind (Bosses.MARK_*), u16 x, y, x2, y2 (1/16 px, offset), u8 radius, u8 ticks left, u8 total
##
## Vehicle extras since version 10 (right after scrap_frac): a flags byte and the groups it names, see _put_extras() (bit 64: salvage, version 11).
##
## Positions are quantized to 1/16 px (max error POS_ERROR). Enemy velocity is quantized to
## 1/7 of the kind's speed and 128 headings; enemy hp to 1/15 of the kind's max hp (for the
## current round, SimWorld.enemy_max_hp). Card and tech ids are table indices (Cards.DEFS / Tech.DEFS).
## Projectile pierce / splash are not sent: the client world is passive.

const VERSION := 15  # 15: live order "target mark" (vehicle extras flag 128: mark_order ticks / cooldown / kind / id), event mark; 14: hive signature (header u16), species kinds 3..5 (enemy kind 3 bits, heading 6 bits), taken stats glass / brood / shrieker, events shriek / brood; 13: boss rounds (header boss_first, FLAG_BOSS tail block, boss enemy kinds, boss events); 12: event surge; 11: salvage (contract offers and progress, loan debt, reserved card, bonus offers), events contract_done / saw / shockwave / chain / jerry_blast; 10: momentum, abilities (slots, cooldowns, effect timers, decoy), swarm mark, jam flags, stunned bitset; 9: ammo / heat per weapon, ground zones, burning bitset, float cooldowns; 8: tech v2.3 (dormant fusions, respecs, purchase rounds); 7: doctrine rules (rig + per weapon); 6: positions at 1/16 px (2560x1440 arena); 5: pvp_grace_ticks, fuel_drain, invuln_ticks, round/match stats, event extras
const FLAG_WIDE_IDS := 1  ## enemy ids spread over more than 65535: ids are sent as u32 deltas from 0
const FLAG_STATS := 2  ## vehicles carry round_stats and match_stats (sent outside combat only)
const FLAG_BURNING := 4  ## a burning bitset follows the projectiles (only sent while something burns)
const FLAG_BOSS := 16  ## a boss block follows the stunned bitset (while Bosses state != NONE)
const FLAG_STUNNED := 8  ## a stunned bitset follows the burning one (only sent while an EMP holds something)
const EVENT_EXTRA_BIT := 0x80
const EVENT_EXTRAS := {"kill": ["victim", "weapon"], "vehicle_destroyed": ["cause", "killer"], "surge": ["in_ticks", "index"], "boss": ["in_ticks", "enraged"]}
const TAKEN_KEYS: PackedStringArray = ["mite", "boulder", "spitter", "acid", "rival", "glass", "brood", "shrieker"]
const MAX_DEATHS := 16
const MAX_ROUND_PLAYERS := 16

const CD_SCALE := 16.0  ## weapon cooldown / cooldown_ticks travel in 1/16 ticks (u16)
const POS_SCALE := 16.0  ## u16 / 16 covers 4096 px: the arena plus POS_ORIGIN must stay below that
const POS_ORIGIN := 64.0  ## added to projectile/event coordinates (they may leave the arena slightly)
const POS_ERROR := 1.0 / 32.0

const HEADER_BYTES := 41  # includes the zone count; the zone entries follow it
const ENEMY_BYTES := 8
const WIDE_ENEMY_BYTES := 10
const PROJ_BYTES := 13
const EVENT_BYTES := 7

const MAX_VEHICLES := 64  ## vehicle ids travel as u8 / i8 owners, keep well below 127
const EVENT_TYPES: PackedStringArray = ["fire", "hit", "kill", "vehicle_destroyed", "retreat", "respawn", "spit", "pvp_on", "bounty", "drain", "shrapnel", "jam", "overheat", "execute", "nitro", "emp", "smoke", "salvo", "dodge", "sparks", "boom", "shed", "contract_done", "saw", "shockwave", "chain", "jerry_blast", "surge", "boss", "boss_spawn", "boss_phase", "boss_kill", "boss_retreat", "boss_shell", "boss_blast", "boss_ring", "boss_charge", "boss_brood", "boss_split", "shriek", "brood", "mark"]
const MAX_ROUND := 65535
const SPEED_STEPS := 7
const HEADING_STEPS := 64
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
	var any_burn: bool = false
	for bi in mini(n_enemy, world.enemy_burn_ticks.size()):
		if world.enemy_burn_ticks[bi] > 0:
			any_burn = true
			break
	if any_burn:
		flags |= FLAG_BURNING
	var any_stun: bool = false
	for si in mini(n_enemy, world.enemy_status.size()):
		if (world.enemy_status[si] & 255) > 0:
			any_stun = true
			break
	if any_stun:
		flags |= FLAG_STUNNED
	var with_boss: bool = world.boss_state != Bosses.ST_NONE
	if with_boss:
		flags |= FLAG_BOSS

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
	sp.put_u8(clampi(world.phase, 0, SimWorld.PHASE_DEPLOY))
	sp.put_u16(clampi(world.round, 1, MAX_ROUND))
	sp.put_u16(clampi(world.phase_ticks_left, 0, 65535))
	sp.put_32(world.winner_peer)
	sp.put_32(world.leader_peer)
	sp.put_u16(clampi(world.pvp_grace_ticks, 0, 65535))
	sp.put_u8(clampi(world.fuel_drain, 0, 255))
	sp.put_u8(world.boss_first & 1)
	sp.put_u16((world.hive_first[0] & 7) | ((world.hive_first[1] & 7) << 3) | ((world.hive_first[2] & 7) << 6))

	var n_zone: int = mini(world.zone_count, mini(world.zone_pos.size(), SimWorld.MAX_ZONES))
	sp.put_u8(n_zone)
	for zi in n_zone:
		sp.put_u16(_q_off(world.zone_pos[zi].x))
		sp.put_u16(_q_off(world.zone_pos[zi].y))
		sp.put_u8(clampi(roundi(world.zone_radius[zi]), 0, 255))
		sp.put_u8(world.zone_kind[zi])
		sp.put_u16(clampi(world.zone_ttl[zi], 0, 65535))
		sp.put_8(clampi(world.zone_owner[zi], -1, 127))

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
	var burn_bytes: int = (n_enemy + 7) / 8 if any_burn else 0
	var stun_bytes: int = (n_enemy + 7) / 8 if any_stun else 0
	out.resize(head_size + n_enemy * estride + n_proj * PROJ_BYTES + burn_bytes + stun_bytes)
	var o: int = head_size
	for i in n_enemy:
		var kind: int = world.enemy_kind[i]
		var p: Vector2 = world.enemy_pos[i]
		var vel: Vector2 = world.enemy_vel[i]
		var max_speed: float = SimWorld.ENEMY_SPEED[mini(kind, SimWorld.BOSS_A)]
		var spd: int = clampi(roundi(vel.length() / max_speed * SPEED_STEPS), 0, SPEED_STEPS)
		var ang: int = 0
		if spd > 0:
			ang = roundi(vel.angle() / TAU * HEADING_STEPS) & (HEADING_STEPS - 1)
		var hpl: int = clampi(ceili(world.enemy_hp[i] / maxf(world.enemy_max_hp_of(i), 1.0) * HP_STEPS), 1, HP_STEPS)
		var packed: int = (mini(kind, SimWorld.BOSS_A) & 7) | (hpl << 3) | (spd << 7) | (ang << 10)
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
	for i in burn_bytes:  # resize() zero-fills
		out[o + i] = 0
	for i in mini(n_enemy, world.enemy_burn_ticks.size()) if any_burn else 0:
		if world.enemy_burn_ticks[i] > 0:
			out[o + (i >> 3)] |= 1 << (i & 7)
	o += burn_bytes
	for i in mini(n_enemy, world.enemy_status.size()) if any_stun else 0:
		if (world.enemy_status[i] & 255) > 0:
			out[o + (i >> 3)] |= 1 << (i & 7)
	if with_boss:
		out.append_array(_put_boss(world, n_enemy))
	return out


## The boss tail block (see the layout notes at the top).
static func _put_boss(world: SimWorld, n_enemy: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(clampi(world.boss_kind, 0, 255))
	b.put_u8(clampi(world.boss_state, 0, 255))
	b.put_u8(clampi(world.boss_phase, 0, 255))
	b.put_u8(1 if world.boss_enraged else 0)
	b.put_u32(roundi(world.boss_max_hp))
	b.put_u16(clampi(roundi(world.boss_hp_frac * 1000.0), 0, 1000))
	b.put_u16(clampi(world.boss_warn_left, 0, 65535))
	b.put_u16(_q_off(world.boss_spawn_pos.x))
	b.put_u16(_q_off(world.boss_spawn_pos.y))
	var bodies: Array[int] = []
	for i in n_enemy:
		if world.enemy_kind[i] >= SimWorld.BOSS_A and world.enemy_hp[i] > 0.0:
			bodies.append(i)
	b.put_u8(mini(bodies.size(), 255))
	for k in mini(bodies.size(), 255):
		var i2: int = bodies[k]
		b.put_u16(i2)
		b.put_u8(world.enemy_kind[i2])
		b.put_u32(maxi(1, roundi(world.enemy_hp[i2])))
	var n_mark: int = mini(world.boss_marks.size(), 255)
	b.put_u8(n_mark)
	for k in n_mark:
		var m: Dictionary = world.boss_marks[k]
		var p1: Vector2 = m["pos"]
		var p2: Vector2 = m["pos2"]
		b.put_u8(int(m["k"]))
		b.put_u16(_q_off(p1.x))
		b.put_u16(_q_off(p1.y))
		b.put_u16(_q_off(p2.x))
		b.put_u16(_q_off(p2.y))
		b.put_u8(clampi(roundi(float(m["r"])), 0, 255))
		b.put_u8(clampi(int(m["left"]), 0, 255))
		b.put_u8(clampi(int(m["total"]), 0, 255))
	return b.data_array


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
	var boss_first: int = r.u8() & 1
	var hive_bits: int = r.u16()
	var with_stats: bool = (flags & FLAG_STATS) != 0
	if not r.ok or n_veh > MAX_VEHICLES or phase > SimWorld.PHASE_DEPLOY or round_n < 1:
		return false
	var wide: bool = (flags & FLAG_WIDE_IDS) != 0

	var n_zone: int = r.u8()
	var z_pos := PackedVector2Array()
	var z_radius := PackedFloat32Array()
	var z_kind := PackedByteArray()
	var z_ttl := PackedInt32Array()
	var z_owner := PackedInt32Array()
	for zi in n_zone:
		var zx: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
		var zy: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
		z_pos.append(Vector2(zx, zy))
		z_radius.append(float(r.u8()))
		z_kind.append(r.u8())
		z_ttl.append(r.u16())
		z_owner.append(r.s8())
	if not r.ok or n_zone > SimWorld.MAX_ZONES:
		return false

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
	var burn_bytes: int = (n_enemy + 7) / 8 if (flags & FLAG_BURNING) != 0 else 0
	var stun_bytes: int = (n_enemy + 7) / 8 if (flags & FLAG_STUNNED) != 0 else 0
	if not r.has(n_enemy * estride + n_proj * PROJ_BYTES + burn_bytes + stun_bytes):
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
		var kind: int = packed & 7
		if kind > SimWorld.BOSS_A:
			return false
		var hpl: int = (packed >> 3) & 15
		var spd: int = (packed >> 7) & 7
		var ang: int = (packed >> 10) & 63
		e_kind[i] = kind
		e_pos[i] = Vector2(px, py)
		if spd > 0:
			var speed: float = SimWorld.ENEMY_SPEED[kind] * float(spd) / SPEED_STEPS
			e_vel[i] = Vector2.from_angle(float(ang) * TAU / HEADING_STEPS) * speed
		e_hp[i] = SimWorld.enemy_max_hp(kind, round_n) * float(hpl) / HP_STEPS if kind < SimWorld.BOSS_A else 1.0  # boss bodies: patched by the boss block

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
	var e_burn := PackedInt32Array()
	e_burn.resize(n_enemy)
	if burn_bytes > 0:
		for i in n_enemy:
			if (data[o + (i >> 3)] & (1 << (i & 7))) != 0:
				e_burn[i] = SimWorld.BURN_TICKS  # the client only needs "burning"
	var e_status := PackedInt32Array()
	e_status.resize(n_enemy)
	if stun_bytes > 0:
		var so: int = o + burn_bytes
		for i in n_enemy:
			if (data[so + (i >> 3)] & (1 << (i & 7))) != 0:
				e_status[i] = Abilities.EMP_STUN_TICKS  # the client only needs "stunned"

	var boss_ok: bool = true
	var b_kind: int = -1
	var b_state: int = 0
	var b_phase: int = 0
	var b_enraged: bool = false
	var b_max: float = 0.0
	var b_frac: float = 0.0
	var b_warn: int = 0
	var b_spawn := Vector2.ZERO
	var b_marks: Array[Dictionary] = []
	if (flags & FLAG_BOSS) != 0:
		r.pos += n_enemy * estride + n_proj * PROJ_BYTES + burn_bytes + stun_bytes
		b_kind = r.u8()
		b_state = r.u8()
		b_phase = r.u8()
		b_enraged = (r.u8() & 1) != 0
		b_max = float(r.u32())
		b_frac = float(r.u16()) / 1000.0
		b_warn = r.u16()
		b_spawn = Vector2(float(r.u16()) / POS_SCALE - POS_ORIGIN, float(r.u16()) / POS_SCALE - POS_ORIGIN)
		var n_body: int = r.u8()
		for k in n_body:
			var bi: int = r.u16()
			var bk: int = r.u8()
			var bhp: float = float(r.u32())
			if not r.ok or bi >= n_enemy or bk < SimWorld.BOSS_A or bk > SimWorld.BOSS_SHARD:
				return false
			e_kind[bi] = bk
			e_hp[bi] = bhp
		var n_mark: int = r.u8()
		for k in n_mark:
			var mk: int = r.u8()
			var mx: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
			var my: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
			var mx2: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
			var my2: float = float(r.u16()) / POS_SCALE - POS_ORIGIN
			var mr: int = r.u8()
			var ml: int = r.u8()
			var mt: int = r.u8()
			b_marks.append({"k": mk, "pos": Vector2(mx, my), "pos2": Vector2(mx2, my2), "r": float(mr), "left": ml, "total": mt})
		if not r.ok:
			return false
	for bj in n_enemy:  # a kind-3 body that the block did not name is malformed
		if e_kind[bj] == SimWorld.BOSS_A and e_hp[bj] == 1.0 and (flags & FLAG_BOSS) == 0:
			return false

	# Commit.
	world.boss_first = boss_first
	world.hive_first = PackedInt32Array([hive_bits & 7, (hive_bits >> 3) & 7, (hive_bits >> 6) & 7])
	world.boss_round = round_n
	world.boss_kind = b_kind
	world.boss_state = b_state
	world.boss_phase = b_phase
	world.boss_enraged = b_enraged
	world.boss_max_hp = b_max
	world.boss_hp_frac = b_frac
	world.boss_warn_left = b_warn
	world.boss_spawn_pos = b_spawn
	world.boss_marks = b_marks
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
	world.enemy_burn_ticks = e_burn
	world.enemy_burn_dps = PackedFloat32Array()
	world.enemy_burn_owner = PackedInt32Array()
	world.enemy_status = e_status
	world.enemy_ram_tick = PackedInt32Array()
	world.zone_pos = z_pos
	world.zone_radius = z_radius
	world.zone_kind = z_kind
	world.zone_ttl = z_ttl
	world.zone_owner = z_owner
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
		sp.put_u16(clampi(roundi(float(w.get("cooldown_ticks", 0.0)) * CD_SCALE), 0, 65535))
		sp.put_u16(clampi(roundi(float(w.get("cooldown", 0.0)) * CD_SCALE), 0, 65535))
		sp.put_float(float(w.get("aim", 0.0)))
		sp.put_u8(clampi(int(w.get("pellets", 1)), 0, 255))
		sp.put_float(float(w.get("spread", 0.0)))
		sp.put_u8(clampi(int(w.get("pierce", 0)), 0, 255))
		sp.put_float(float(w.get("splash", 0.0)))
		sp.put_float(float(w.get("speed", 0.0)))
		sp.put_u8(clampi(int(w.get("live", 0)), 0, 255))
		sp.put_u8(clampi(int(w.get("heat", 0)), 0, 255))
		sp.put_u8(clampi(int(w.get("jam", 0)), 0, 255))
		sp.put_u8(clampi(int(w.get("sw", 0)), 0, 255))
		var wammo: Array = v.ammo.get(str(w.get("kind", "")), [])
		for ai in 2:
			sp.put_u8(Ammo.IDS.find(str(wammo[ai])) if ai < wammo.size() else 255)
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
	_put_extras(sp, v)
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


## Momentum, abilities and electronics state (version 10). A flags byte says which groups follow, so a rig
## without that tech pays one byte: 1 momentum f32; 2 ability slots (u8 index or 255, u16 cooldown) x2; 4 timers
## (nitro, sputter, salvo, smoke, decoy, rules-off: u8 each; nitro count u8; boom cooldown u16); 8 decoy
## position 2 x f32; 16 jammed-by s8 and shed plates u8; 32 swarm mark s32 and position 2 x f32.
static func _put_extras(sp: StreamPeerBuffer, v: SimVehicle) -> void:
	var ext: int = 0
	if v.momentum != 0.0:
		ext |= 1
	if v.abilities[0] != "" or v.abilities[1] != "" or v.ab_cd[0] != 0 or v.ab_cd[1] != 0:
		ext |= 2
	if v.nitro_ticks != 0 or v.sputter_ticks != 0 or v.salvo_ticks != 0 or v.smoke_ticks != 0 or v.decoy_ticks != 0 \
			or v.rules_off_ticks != 0 or v.nitro_count != 0 or v.boom_cd != 0:
		ext |= 4
	if v.decoy_ticks > 0:
		ext |= 8
	if v.jammed_by >= 0 or v.shed != 0:
		ext |= 16
	if v.mark_id >= 0:
		ext |= 32
	if not v.contract_offers.is_empty() or v.contract_kind >= 0 or v.loan_debt > 0 or v.reserved_card != "" or v.bonus_offers > 0:
		ext |= 64
	if v.mark_order_ticks > 0 or v.mark_order_cd > 0:
		ext |= 128
	sp.put_u8(ext)
	if (ext & 1) != 0:
		sp.put_float(v.momentum)
	if (ext & 2) != 0:
		for s in Abilities.SLOTS:
			sp.put_u8(Abilities.IDS.find(v.abilities[s]) if v.abilities[s] != "" else 255)
			sp.put_u16(clampi(v.ab_cd[s], 0, 65535))
	if (ext & 4) != 0:
		sp.put_u8(clampi(v.nitro_ticks, 0, 255))
		sp.put_u8(clampi(v.sputter_ticks, 0, 255))
		sp.put_u8(clampi(v.salvo_ticks, 0, 255))
		sp.put_u8(clampi(v.smoke_ticks, 0, 255))
		sp.put_u8(clampi(v.decoy_ticks, 0, 255))
		sp.put_u8(clampi(v.rules_off_ticks, 0, 255))
		sp.put_u8(v.nitro_count & 255)
		sp.put_u16(clampi(v.boom_cd, 0, 65535))
	if (ext & 8) != 0:
		sp.put_float(v.decoy_pos.x)
		sp.put_float(v.decoy_pos.y)
	if (ext & 16) != 0:
		sp.put_8(clampi(v.jammed_by, -1, 127))
		sp.put_u8(clampi(v.shed, 0, 255))
	if (ext & 32) != 0:
		sp.put_32(v.mark_id)
		sp.put_float(v.mark_pos.x)
		sp.put_float(v.mark_pos.y)
	if (ext & 64) != 0:
		var offers: Array[Vector3i] = v.contract_offers
		var no: int = mini(offers.size(), Salvage.MAX_OFFERS)
		sp.put_u8(no)
		for i in no:
			sp.put_u8(clampi(offers[i].x, 0, 255))
			sp.put_u16(clampi(offers[i].y, 0, 65535))
			sp.put_u16(clampi(offers[i].z, 0, 65535))
		sp.put_8(clampi(v.contract_kind, -1, 127))
		if v.contract_kind >= 0:
			sp.put_u16(clampi(v.contract_need, 0, 65535))
			sp.put_u16(clampi(v.contract_reward, 0, 65535))
			sp.put_16(clampi(int(v.contract_prog), -1, 32767))
		sp.put_u16(clampi(v.loan_debt, 0, 65535))
		sp.put_u8(clampi(v.loan_left, 0, 255))
		sp.put_u8(Cards.index_of(v.reserved_card) if v.reserved_card != "" else 255)
		sp.put_u8(clampi(v.bonus_offers, 0, 255))
	if (ext & 128) != 0:
		sp.put_u8(clampi(v.mark_order_ticks, 0, 255))
		sp.put_u16(clampi(v.mark_order_cd, 0, 65535))
		sp.put_u8(clampi(v.mark_order_kind, 0, 2))
		sp.put_32(v.mark_order_id)


static func _get_extras(r: _Reader, v: SimVehicle, slot_ids: Array[String], slot_cd: PackedInt32Array) -> void:
	var ext: int = r.u8()
	if (ext & 1) != 0:
		v.momentum = r.f32()
	if (ext & 2) != 0:
		for s in Abilities.SLOTS:
			var aix: int = r.u8()
			if aix < Abilities.IDS.size():
				slot_ids[s] = Abilities.IDS[aix]
			elif aix != 255:
				r.fail()
			slot_cd[s] = r.u16()
	if (ext & 4) != 0:
		v.nitro_ticks = r.u8()
		v.sputter_ticks = r.u8()
		v.salvo_ticks = r.u8()
		v.smoke_ticks = r.u8()
		v.decoy_ticks = r.u8()
		v.rules_off_ticks = r.u8()
		v.nitro_count = r.u8()
		v.boom_cd = r.u16()
	if (ext & 8) != 0:
		v.decoy_pos = Vector2(r.f32(), r.f32())
	if (ext & 16) != 0:
		v.jammed_by = r.s8()
		v.shed = r.u8()
	if (ext & 32) != 0:
		v.mark_id = r.s32()
		v.mark_pos = Vector2(r.f32(), r.f32())
	if (ext & 64) != 0:
		var no: int = r.u8()
		if no > Salvage.MAX_OFFERS:
			r.fail()
			return
		var offers: Array[Vector3i] = []
		for i in no:
			var ok: int = r.u8()
			var on: int = r.u16()
			var orw: int = r.u16()
			if ok >= Salvage.K_COUNT:
				r.fail()
				return
			offers.append(Vector3i(ok, on, orw))
		v.contract_offers = offers
		var ck: int = r.s8()
		if ck >= Salvage.K_COUNT:
			r.fail()
			return
		v.contract_kind = ck
		if ck >= 0:
			v.contract_need = r.u16()
			v.contract_reward = r.u16()
			v.contract_prog = float(r.s16())
		v.loan_debt = r.u16()
		v.loan_left = r.u8()
		var rix: int = r.u8()
		if rix != 255:
			v.reserved_card = Cards.id_at(rix)
			if v.reserved_card == "":
				r.fail()
		v.bonus_offers = r.u8()
	if (ext & 128) != 0:
		v.mark_order_ticks = r.u8()
		v.mark_order_cd = r.u16()
		v.mark_order_kind = r.u8()
		v.mark_order_id = r.s32()
		if v.mark_order_kind > 2:
			r.fail()


## Round and match stats of one vehicle (see SimWorld.new_round_stats / new_match_stats).
static func _put_stats(sp: StreamPeerBuffer, v: SimVehicle) -> void:
	var rs: Dictionary = v.round_stats
	var tk: Dictionary = rs.get("taken", {})
	sp.put_u16(clampi(int(rs.get("round", 0)), 0, 65535))
	for key in TAKEN_KEYS:
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
	for key in TAKEN_KEYS:
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
	v.ammo = {}
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
		var cdt: float = float(r.u16()) / CD_SCALE
		var cd: float = float(r.u16()) / CD_SCALE
		var aim: float = r.f32()
		var pellets: int = r.u8()
		var spread: float = r.f32()
		var pierce: int = r.u8()
		var splash: float = r.f32()
		var wspeed: float = r.f32()
		var wlive: int = r.u8()
		var wheat: int = r.u8()
		var wjam: int = r.u8()
		var wsw: int = r.u8()
		var wammo: Array[String] = []
		for ai in 2:
			var aix: int = r.u8()
			if aix < Ammo.IDS.size():
				wammo.append(Ammo.IDS[aix])
		if not r.ok:
			return v
		v.ammo[kind] = wammo
		v.weapons.append({
			"kind": kind, "damage": dmg, "range": rng, "cooldown_ticks": cdt, "cooldown": cd, "aim": aim,
			"pellets": pellets, "spread": spread, "pierce": pierce, "splash": splash, "speed": wspeed,
			"live": wlive, "heat": wheat, "jam": wjam, "sw": wsw, "shots": 0,
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
	var slot_ids: Array[String] = ["", ""]
	var slot_cd := PackedInt32Array([0, 0])
	_get_extras(r, v, slot_ids, slot_cd)
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
	for w in v.weapons:  # the evolved flag follows from the cards (not sent per weapon)
		w["evo"] = Cards.is_evolved(v, str(w["kind"]))
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
		v.abilities = slot_ids  # as sent (recompute would fill free slots by itself)
		v.ab_cd = slot_cd
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
			dst.ammo = src.ammo
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
			dst.eff_armor = src.eff_armor
			dst.momentum = src.momentum
			dst.abilities = src.abilities
			dst.ab_cd = src.ab_cd
			dst.nitro_ticks = src.nitro_ticks
			dst.sputter_ticks = src.sputter_ticks
			dst.salvo_ticks = src.salvo_ticks
			dst.smoke_ticks = src.smoke_ticks
			dst.decoy_ticks = src.decoy_ticks
			dst.decoy_pos = src.decoy_pos
			dst.rules_off_ticks = src.rules_off_ticks
			dst.nitro_count = src.nitro_count
			dst.boom_cd = src.boom_cd
			dst.jammed_by = src.jammed_by
			dst.shed = src.shed
			dst.mark_id = src.mark_id
			dst.mark_pos = src.mark_pos
			dst.mark_order_ticks = src.mark_order_ticks
			dst.mark_order_cd = src.mark_order_cd
			dst.mark_order_kind = src.mark_order_kind
			dst.mark_order_id = src.mark_order_id
			dst.contract_offers = src.contract_offers
			dst.contract_kind = src.contract_kind
			dst.contract_need = src.contract_need
			dst.contract_reward = src.contract_reward
			dst.contract_prog = src.contract_prog
			dst.loan_debt = src.loan_debt
			dst.loan_left = src.loan_left
			dst.reserved_card = src.reserved_card
			dst.bonus_offers = src.bonus_offers
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

	func s16() -> int:
		if not _take(2):
			return 0
		pos += 2
		return bytes.decode_s16(pos - 2)

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
