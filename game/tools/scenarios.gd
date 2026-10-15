class_name Scenarios
extends RefCounted
## Named, deterministic SimWorld setups for screenshots (main.gd --shot=...) and manual checks.
## build(name, seed) + step(name, world) N times always gives the same state.
##
## Round-loop scenarios use fast_rounds (4 s combat) and auto-ready through early workshops:
## - "workshop"     (about 400 ticks): the workshop after round 3, red with scrap, cards and tech,
##                  magenta already picked and ready.
## - "gameover"     (about 300 ticks): solo, the last fuel burns in round 2, YOUR CONVOY IS LOST.
## - "gameover_mp"  (about 200 ticks): magenta runs dry, red is the last rig standing.
## - "eliminated"   (about 220 ticks): three rigs; red runs dry and spectates (ELIMINATED).
##
## Spitters scattered into skirmish / horde spit real acid (the sim's own attack, any round).
##
## Visual review scenarios (playtest round 1 #6, #11, #12):
## - "rig_growth"   eight parked rigs, one per paint, from the starter buggy to a tier-3 rig with a
##                  trailer: every card's bolt-on (guns per level, plates, spikes, nitro, tracks...).
##                  The world is not stepped (any ticks), so the line-up stays put.
## - "late_round"   (about 240 ticks) round 8: a dense hive of boulders and spitters, corpses piling
##                  up, the local rig at low hp (red vignette), rivals with builds and a bounty leader.
## - "pvp_on"       (about 380 ticks) fast rounds up to the start of round 4: the PVP ON banner.
## - "rig_kill"     (about 60 ticks) a rival rig blowing up next to yours (explosion and debris).
##
## Information UI review scenarios (playtest round 1 #2, #5, #10, #11), five named rigs (LAN_NIGHT):
## - "recap"        (about 160 ticks) workshop after round 8: wrecked by boulders and acid, KITE hint,
##                  interest x/cap, UNDERDOG badge, the fuel-drain notice.
## - "recap_pvp"    (about 160 ticks) the same, but DUNE RAT hunted you down with its cannon.
## - "scouting"     = recap; use --hover / --click on a convoy row for the dossier.
## - "combat_feed"  (about 160 ticks) round 6: kill feed lines and off-screen rival arrows.
## - "pvp_grace"    (about 90 ticks) start of round 4: the PvP grace countdown.
## - "spectator"    (about 120 ticks) you are eliminated: the camera follows the nearest fight.
## - "spectator_ws" (about 160 ticks) the workshop seen by an eliminated player.
## - "awards"       (about 120 ticks) game over with LAN-night awards.
##
## UI scenarios (main.gd also builds the menu from ui_state()):
## - "menu"     the attract battlefield (eight rigs, one per paint) behind the main menu.
## - "join"     the join screen with two fake discovered hosts (one in a match).
## - "lobby"    the host's lobby: four drivers, mixed ready.
## - "pause"    skirmish with the pause / menu overlay (LAN wording: the fight goes on).
## - "rematch"  gameover_mp seen by the host: REMATCH and LEAVE TO MENU.
## - "waiting"  gameover_mp seen by the loser (a client): waiting for the host's rematch.

const NAMES: PackedStringArray = ["skirmish", "horde", "workshop", "gameover", "gameover_mp", "eliminated",
	"menu", "join", "lobby", "pause", "rematch", "waiting", "rig_growth", "late_round", "pvp_on", "rig_kill",
	"recap", "recap_pvp", "scouting", "combat_feed", "pvp_grace", "spectator", "spectator_ws", "awards"]
## Info-UI line-up: [name, paint, GROWTH_BUILDS index, drive, target, extra tech].
const LAN_NIGHT: Array = [
	["MAD MAREK", 0, 6, "circle", "nearest", ["ballistics_1"]],
	["DUNE RAT", 2, 3, "kite", "players_first", ["ballistics_1", "ballistics_2", "electronics_1", "salvage_1"]],
	["SANDY", 3, 2, "charge", "nearest", ["propulsion_1"]],
	["NIGHTCRAWLER", 7, 7, "circle", "strongest", []],
	["LIMEADE", 6, 1, "kite", "nearest", ["salvage_1"]],
]
## rig_growth line-up: [engineering tier, {card: level}] per paint (weapon cards in mount order).
const GROWTH_BUILDS: Array = [
	[0, {}],
	[1, {"mg": 2, "shotgun": 1, "steel_plates": 2, "v8_engine": 1}],
	[2, {"shotgun": 3, "flamer": 2, "spiked_plating": 3, "nitro": 2, "berserker": 1, "caterpillar_tracks": 1}],
	[3, {"cannon": 3, "mg": 3, "flamer": 3, "reinforced_hull": 3, "ablative_scrap": 2, "off_road_tyres": 1, "scrap_magnet": 1}],
	[2, {"cannon": 1, "steel_plates": 3, "ablative_scrap": 3, "vulture": 1, "regenerator": 1, "v8_engine": 3}],
	[0, {"flamer": 1, "spiked_plating": 1, "nitro": 1}],
	[1, {"mg": 3, "cannon": 2, "reinforced_hull": 1, "steel_plates": 1}],
	[2, {"shotgun": 2, "spiked_plating": 2, "steel_plates": 1, "v8_engine": 2, "off_road_tyres": 1}],
]
const WORKSHOP_ROUND := 3
const ATTRACT_NAMES: PackedStringArray = ["RUSTBUCKET", "DUNE RAT", "MAD MAREK", "SANDY", "OLD SMOKEY",
	"NOMAD", "LIMEADE", "NIGHTCRAWLER"]


static func build(name: String, p_seed: int) -> SimWorld:
	match name:
		"skirmish":
			return _skirmish(p_seed)
		"horde":
			return _horde(p_seed)
		"workshop":
			var w: SimWorld = _skirmish(p_seed)
			w.fast_rounds = true
			return w
		"gameover":
			var w1 := SimWorld.new(p_seed)
			w1.fast_rounds = true
			w1.add_vehicle(1, SimWorld.ARENA.get_center(), "MAD MAREK")
			w1.vehicles[0].fuel = 15
			_scatter(w1, 500, 0.08, 0.04, 120.0, 700.0)
			return w1
		"gameover_mp":
			var w2: SimWorld = _skirmish(p_seed)
			w2.fast_rounds = true
			w2.vehicles[1].fuel = 15
			return w2
		"eliminated":
			var w3: SimWorld = _skirmish(p_seed)
			w3.fast_rounds = true
			w3.add_vehicle(3, _old_arena(Vector2(640, 600)), "NIGHTCRAWLER", 7)
			w3.vehicles[0].fuel = 15
			return w3
		"menu", "join", "lobby":
			return attract(p_seed)
		"pause":
			return _skirmish(p_seed)
		"rematch", "waiting":
			return build("gameover_mp", p_seed)
		"rig_growth":
			return _rig_growth(p_seed)
		"late_round":
			return _late_round(p_seed)
		"pvp_on":
			var w4: SimWorld = attract(p_seed)
			w4.fast_rounds = true
			return w4
		"rig_kill":
			return _rig_kill(p_seed)
		"recap", "recap_pvp", "scouting":
			var c: Vector2 = SimWorld.ARENA.get_center()
			var w5: SimWorld = _lan_night(p_seed, [c, c + Vector2(260, -150), c + Vector2(-300, 160), c + Vector2(330, 200), c + Vector2(-380, -170)])
			w5.fast_rounds = true
			w5.round = 8
			_scatter(w5, 120, 0.12, 0.08, 120.0, 600.0)
			return w5
		"combat_feed", "pvp_grace", "spectator", "spectator_ws", "awards":
			var c2: Vector2 = SimWorld.ARENA.get_center()
			var spots: Array = [c2, _old_arena(Vector2(140, 110)), _old_arena(Vector2(1170, 640)), _old_arena(Vector2(1200, 320)), c2 + Vector2(120, -80)]
			if name == "spectator" or name == "spectator_ws":
				spots = [c2 + Vector2(-380, 150), c2 + Vector2(40, -20), c2 + Vector2(170, 40), _old_arena(Vector2(170, 130)), _old_arena(Vector2(1130, 610))]
			var w6: SimWorld = _lan_night(p_seed, spots)
			w6.round = 4 if name == "pvp_grace" else (11 if name == "awards" else 6)
			w6.fast_rounds = name == "spectator_ws"
			w6.phase_ticks_left = w6.combat_duration(w6.round)
			if name == "pvp_grace":
				w6.pvp_grace_ticks = SimWorld.PVP_GRACE_TICKS
			if name == "spectator" or name == "spectator_ws":
				_knock_out(w6.vehicles[0])
			_scatter(w6, 300, 0.12, 0.07, 110.0, 700.0)
			return w6
	return null


## Menu backdrop: one rig per paint job, named, driving and fighting through a scattered hive.
static func attract(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	var c: Vector2 = SimWorld.ARENA.get_center()
	var drives: PackedStringArray = ["circle", "kite", "charge"]
	for i in SimVehicle.COLOR_COUNT:
		var a: float = TAU * float(i) / float(SimVehicle.COLOR_COUNT)
		w.add_vehicle(i + 1, c + Vector2(cos(a) * 420.0, sin(a) * 230.0), ATTRACT_NAMES[i], i)
		w.apply_command(i + 1, {"type": "set_drive", "value": drives[i % 3]})
	_scatter(w, 260, 0.07, 0.06, 90.0, 760.0)
	return w


## What main.gd shows on top of a UI scenario's world ({} = the plain game view).
static func ui_state(name: String) -> Dictionary:
	var lobby: Array[Dictionary] = [
		{"peer_id": 1, "name": "MAD MAREK", "color_index": 0, "ready": false, "is_host": true},
		{"peer_id": 2, "name": "DUNE RAT", "color_index": 2, "ready": true, "is_host": false},
		{"peer_id": 3, "name": "NIGHTCRAWLER", "color_index": 7, "ready": false, "is_host": false},
		{"peer_id": 4, "name": "LIMEADE", "color_index": 6, "ready": true, "is_host": false},
	]
	match name:
		"menu":
			return {"screen": "main", "profile": ["MAD MAREK", 0]}
		"join":
			return {"screen": "join", "profile": ["SANDY", 3], "ip": "192.168.1.",
				"hosts": [
					{"address": "192.168.1.20", "port": 24680, "name": "MAD MAREK", "players": 3, "state": "lobby"},
					{"address": "192.168.1.37", "port": 24680, "name": "OLD SMOKEY", "players": 5, "state": "match"},
				]}
		"lobby":
			return {"screen": "lobby", "profile": ["MAD MAREK", 0], "players": lobby, "is_host": true, "local_peer": 1,
				"info": "HOSTING ON PORT 24680 - FRIENDS FIND YOU UNDER JOIN LAN GAME"}
		"pause":
			return {"screen": "pause", "solo": false}
		"rematch", "awards":
			return {"game_over": "host"}
		"waiting":
			return {"game_over": "client", "local_peer": 2}
	return {}


static func step(name: String, w: SimWorld) -> void:
	if name == "rematch" or name == "waiting":
		name = "gameover_mp"
	if name in ["recap", "recap_pvp", "scouting", "combat_feed", "pvp_grace", "spectator", "spectator_ws", "awards"]:
		_step_info(name, w)
		return
	if name == "rig_growth":
		w.tick += 1  # parked: only the clock runs (nitro flicker, ring)
		return
	if name == "pvp_on" and w.round >= SimWorld.PVP_START_ROUND and w.phase == SimWorld.PHASE_COMBAT:
		w.step()
		return
	w.step()
	match name:
		"pvp_on":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
		"late_round":
			var me: SimVehicle = w.vehicles[0]
			if me.alive:
				me.hp = minf(me.hp, me.max_hp * 0.18)
		"rig_kill":
			if w.tick == 40:  # the rival in front of us takes a cannon shell too many
				var rv: SimVehicle = w.vehicles[1]
				rv.invuln_ticks = 0
				rv.protect_ticks = 0
				rv.hp = 1.0
				w.spawn_projectile(rv.pos + Vector2(-30, 0), Vector2(400, 0), 0.5, 500.0, 0)
		"menu", "join", "lobby":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
		"workshop":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				if w.round < WORKSHOP_ROUND:
					_ready_all(w)
				elif not w.has_meta("staged"):
					_stage_workshop(w)
		"gameover":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
			elif w.phase == SimWorld.PHASE_COMBAT and w.round >= 2:
				_swarm(w, w.vehicles[0])
		"gameover_mp":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
			elif w.phase == SimWorld.PHASE_COMBAT and w.round >= 2:
				_swarm(w, w.vehicles[1])
		"eliminated":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				_ready_all(w)
			elif w.phase == SimWorld.PHASE_COMBAT and w.round >= 2:
				_swarm(w, w.vehicles[0])


## The hive closes in on `v` (low hp, mites dropping in around it) until its last fuel burns.
static func _swarm(w: SimWorld, v: SimVehicle) -> void:
	if not v.alive or v.eliminated:
		return
	v.hp = minf(v.hp, 1.0)
	var a: float = w.rng.randf() * TAU
	var p: Vector2 = v.pos + Vector2.from_angle(a) * (40.0 + w.rng.randf() * 60.0)
	if SimWorld.ARENA.grow(-12.0).has_point(p):
		w.spawn_enemy(SimWorld.MITE if w.rng.randf() < 0.85 else SimWorld.SPITTER, p)


static func _ready_all(w: SimWorld) -> void:
	for v in w.vehicles:
		w.apply_command(v.peer_id, {"type": "ready"})


## A mid-game workshop: some scrap, a few cards and tech, 19 s on the clock, rival ready.
static func _stage_workshop(w: SimWorld) -> void:
	w.set_meta("staged", true)
	w.phase_ticks_left = 19 * SimWorld.TICK_RATE + 12
	var red: SimVehicle = w.vehicles[0]
	for id: String in ["shotgun", "steel_plates", "steel_plates", "v8_engine"]:
		Cards.grant(red, id)
	red.offers = Cards.roll_offers(w.rng, red)  # re-deal for the new loadout (slots are full now)
	red.scrap = 107
	for id: String in ["ballistics_1", "engineering_1", "ballistics_2"]:
		w.apply_command(red.peer_id, {"type": "buy_tech", "value": id})
	red.fuel = 60
	var mag: SimVehicle = w.vehicles[1]
	w.apply_command(mag.peer_id, {"type": "pick_card", "value": 0})
	w.apply_command(mag.peer_id, {"type": "ready"})


## Gives `v` an engineering tier and cards (levels), then recomputes its stats and weapons.
static func _outfit(v: SimVehicle, tier: int, cards: Dictionary) -> void:
	for id: String in cards:
		for i in int(cards[id]):
			Cards.grant(v, id)
	for t in range(1, tier + 1):
		v.tech.append("engineering_%d" % t)
	Cards.recompute(v)
	v.hp = v.max_hp


static func _rig_growth(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.spawning_enabled = false
	var c: Vector2 = SimWorld.ARENA.get_center()
	for i in SimVehicle.COLOR_COUNT:
		var col: int = i % 4
		var row: int = i / 4
		var pos: Vector2 = c + Vector2(-114.0 + 76.0 * col, -62.0 + 132.0 * row)
		var v: SimVehicle = w.add_vehicle(i + 1, pos, ATTRACT_NAMES[i], i)
		var b: Array = GROWTH_BUILDS[i]
		_outfit(v, b[0], b[1])
		v.heading = -PI / 2.0 + (0.0 if row == 0 else 0.4)
		v.vel = Vector2.from_angle(v.heading) * 60.0  # rolling: nitro jets burn
		for k in v.weapons.size():
			v.weapons[k]["aim"] = v.heading + 0.5 - 0.7 * k
	w.leader_peer = 4
	return w


static func _late_round(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = 8
	var c: Vector2 = SimWorld.ARENA.get_center()
	var builds: Array = [GROWTH_BUILDS[6], GROWTH_BUILDS[2], GROWTH_BUILDS[3], GROWTH_BUILDS[7]]
	var spots: Array = [c, c + Vector2(150, -70), c + Vector2(-170, 90), c + Vector2(230, 120)]
	for i in builds.size():
		var v: SimVehicle = w.add_vehicle(i + 1, spots[i], ATTRACT_NAMES[i * 2], [0, 2, 3, 7][i])
		_outfit(v, builds[i][0], builds[i][1])
		v.kills = 40 + i * 25
	w.apply_command(1, {"type": "set_drive", "value": "kite"})
	_scatter(w, 520, 0.22, 0.14, 70.0, 620.0)
	return w


static func _rig_kill(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = SimWorld.PVP_START_ROUND
	var c: Vector2 = SimWorld.ARENA.get_center()
	var me: SimVehicle = w.add_vehicle(1, c, "MAD MAREK", 0)
	_outfit(me, 1, {"cannon": 2, "steel_plates": 1})
	var rv: SimVehicle = w.add_vehicle(2, c + Vector2(90, 10), "DUNE RAT", 2)
	_outfit(rv, 2, {"shotgun": 2, "spiked_plating": 2})
	_scatter(w, 60, 0.1, 0.05, 160.0, 500.0)
	return w


## Two rigs (red: circle / nearest, magenta: kite / players_first) in a running horde.
static func _skirmish(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, _old_arena(Vector2(420, 420)), "MAD MAREK")
	w.add_vehicle(2, _old_arena(Vector2(900, 300)), "DUNE RAT")
	w.apply_command(1, {"type": "set_drive", "value": "circle"})
	w.apply_command(1, {"type": "set_target", "value": "nearest"})
	w.apply_command(2, {"type": "set_drive", "value": "kite"})
	w.apply_command(2, {"type": "set_target", "value": "players_first"})
	_scatter(w, 170, 0.06, 0.05, 140.0, 640.0)
	return w


## One rig in the middle of ~800 aliens.
static func _horde(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, SimWorld.ARENA.get_center(), "MAD MAREK")
	_scatter(w, 800, 0.06, 0.03, 170.0, 760.0)
	return w


## A spot written for the old 1280x720 arena, moved so it keeps its place relative to the centre.
static func _old_arena(p: Vector2) -> Vector2:
	return p + SimWorld.ARENA.get_center() - Vector2(640, 360)


## Places `n` enemies around the vehicles (ring min_d..max_d from the arena centre), using world.rng.
static func _scatter(w: SimWorld, n: int, boulder_p: float, spitter_p: float, min_d: float, max_d: float) -> void:
	var c: Vector2 = SimWorld.ARENA.get_center()
	var area: Rect2 = SimWorld.ARENA.grow(-12.0)
	var placed: int = 0
	var tries: int = 0
	while placed < n and tries < n * 20:
		tries += 1
		var a: float = w.rng.randf() * TAU
		var d: float = lerpf(min_d, max_d, sqrt(w.rng.randf()))
		var p: Vector2 = c + Vector2(cos(a) * d, sin(a) * d * 0.62)
		if not area.has_point(p):
			continue
		var near: bool = false
		for v in w.vehicles:
			if v.pos.distance_to(p) < min_d:
				near = true
		if near:
			continue
		var r: float = w.rng.randf()
		var kind: int = SimWorld.BOULDER if r < boulder_p else (SimWorld.SPITTER if r < boulder_p + spitter_p else SimWorld.MITE)
		w.spawn_enemy(kind, p)
		placed += 1



# ================================================================ playtest session replay
## "replay" is not a named scenario: it rebuilds the world of a playtest session
## (scripts/playtest.sh, tools/playtest.gd, main.gd --scenario=replay) from its session.json, so the
## headless summary and the screenshots come from one and the same deterministic replay.
##
## session = {"seed", "mode": "solo"|"ffa", "name", "color", "opponents": [policy names],
##   "fast": bool, "doctrine": {"drive", "target"},
##   "decisions": [[cmd, ...], ...]   # commands applied to the human rig at workshop 1, 2, ...
##   "pending": [cmd, ...]            # commands for the current decision point (the workshop of
##                                    # round decisions.size() + 1), applied there and then we stop
## }
## The human is peer 1 (vehicle 0), bots are peers 2.. with BotPolicy workshops. Commands are applied
## on the tick the workshop opens (human first, then the bots); the sim runs real round timings.
## Same ring positions as NetSession.spawn_position() (duplicated so tools never depend on net/).

const REPLAY_DEFAULT_OPPONENTS: PackedStringArray = ["balanced", "pvp_hunter", "random"]
const REPLAY_COMMANDS: PackedStringArray = ["pick_card", "reroll", "buy_tech", "ready", "set_drive", "set_target"]


static func replay_spawn_position(slot: int) -> Vector2:
	var a: float = float(slot % 8) * TAU / 8.0
	return SimWorld.ARENA.get_center() + Vector2(cos(a) * SimWorld.SPAWN_ELLIPSE.x, sin(a) * SimWorld.SPAWN_ELLIPSE.y)


## Builds the run state for `session`: {"w": SimWorld, "bots": Array (null for the human), "target":
## decision point (workshop round) to stop at, "handled": last workshop round already handled,
## "cmd_log": {round: [text]}, "session": session}.
static func replay_new(session: Dictionary) -> Dictionary:
	var w := SimWorld.new(int(session.get("seed", 1)))
	w.fast_rounds = bool(session.get("fast", false))
	var me: SimVehicle = w.add_vehicle(1, replay_spawn_position(0), str(session.get("name", "DRIVER")), int(session.get("color", 0)))
	var bots: Array = [null]
	if str(session.get("mode", "solo")) == "ffa":
		var used: Dictionary = {me.color_index: true}
		var names: Dictionary = {me.player_name: true}
		var opps: Array = session.get("opponents", [])
		for i in opps.size():
			var pol: String = str(opps[i])
			var color: int = 0
			while used.has(color):
				color += 1
			used[color] = true
			var base: String = pol.replace("_", " ").to_upper().left(13)
			var nm: String = base
			var n: int = 2
			while names.has(nm):
				nm = "%s %d" % [base, n]
				n += 1
			names[nm] = true
			var v: SimVehicle = w.add_vehicle(i + 2, replay_spawn_position(i + 1), nm, color)
			var bot: BotPolicy = BotPolicy.create(pol, int(session.get("seed", 1)) * 31 + i + 1)
			bots.append(bot)
			if bot != null:
				for cmd in bot.doctrine_commands(w, v):
					w.apply_command(v.peer_id, cmd)
	var doc: Dictionary = session.get("doctrine", {})
	if doc.has("drive"):
		w.apply_command(1, {"type": "set_drive", "value": doc["drive"]})
	if doc.has("target"):
		w.apply_command(1, {"type": "set_target", "value": doc["target"]})
	var decisions: Array = session.get("decisions", [])
	return {"w": w, "bots": bots, "target": decisions.size() + 1, "handled": 0, "cmd_log": {}, "session": session}


## True once the replay reached its decision point (that workshop's commands are applied) or the game ended.
static func replay_done(run: Dictionary) -> bool:
	var w: SimWorld = run["w"]
	if w.phase == SimWorld.PHASE_GAME_OVER:
		return true
	return w.phase == SimWorld.PHASE_WORKSHOP and int(run["handled"]) == w.round and w.round >= int(run["target"])


## One sim tick; when it opens a workshop, the human's commands for that decision point and then the
## bots' shopping are applied right away (so they happen "at the tick the workshop opens").
static func replay_advance(run: Dictionary) -> void:
	var w: SimWorld = run["w"]
	w.step()
	if w.phase == SimWorld.PHASE_WORKSHOP and int(run["handled"]) != w.round:
		run["handled"] = w.round
		_replay_workshop(run)


static func _replay_workshop(run: Dictionary) -> void:
	var w: SimWorld = run["w"]
	var session: Dictionary = run["session"]
	var decisions: Array = session.get("decisions", [])
	var cmds: Array = decisions[w.round - 1] if w.round <= decisions.size() else session.get("pending", [])
	var log: Array = []
	var me: SimVehicle = w.vehicles[0]
	for c: Variant in cmds:
		if c is Dictionary:
			log.append(replay_apply(w, me, c))
	(run["cmd_log"] as Dictionary)[w.round] = log
	var bots: Array = run["bots"]
	for i in range(1, bots.size()):
		var bot: BotPolicy = bots[i]
		var v: SimVehicle = w.vehicles[i]
		if bot != null and not v.eliminated:
			bot.workshop_commands(w, v)


## Applies one human command and returns a one-line account of what happened.
static func replay_apply(w: SimWorld, v: SimVehicle, cmd: Dictionary) -> String:
	var type: String = str(cmd.get("type", ""))
	var val: Variant = cmd.get("value")
	var label: String = type if val == null else "%s %s" % [type, str(int(val)) if (val is float and val == floorf(val)) else str(val)]
	var scrap: int = v.scrap
	var tech_n: int = v.tech.size()
	var was_picked: bool = v.picked
	var was_ready: bool = v.ready
	if v.eliminated and type in ["pick_card", "reroll", "buy_tech", "ready"]:
		return "%s -> IGNORED (you are eliminated)" % label
	var old_offers: Array[String] = v.offers.duplicate()
	var old_doc: Dictionary = v.doctrine.duplicate()
	w.apply_command(v.peer_id, cmd)
	match type:
		"pick_card":
			if v.picked and not was_picked:
				var idx: int = int(val)
				var id: String = old_offers[idx] if idx >= 0 and idx < old_offers.size() else "?"
				return "%s -> took %s, now L%d" % [label, str((Cards.def(id)).get("name", id)), int(v.cards.get(id, 0))]
			if was_picked:
				return "%s -> IGNORED (already picked this workshop)" % label
			return "%s -> IGNORED (bad index or not allowed)" % label
		"reroll":
			if v.scrap < scrap:
				return "%s -> new offers %s (-%d scrap)" % [label, ", ".join(v.offers), scrap - v.scrap]
			return "%s -> IGNORED (%s)" % [label, "already picked" if was_picked else "need %d scrap" % v.reroll_cost]
		"buy_tech":
			if v.tech.size() > tech_n:
				return "%s -> bought (-%d scrap)" % [label, scrap - v.scrap]
			var id2: String = str(val)
			if not Tech.has(id2):
				return "%s -> IGNORED (unknown tech id)" % label
			if v.tech.has(id2):
				return "%s -> IGNORED (already owned)" % label
			var pre: String = Tech.prerequisite(id2)
			if pre != "" and not v.tech.has(pre):
				return "%s -> IGNORED (needs %s first)" % [label, pre]
			return "%s -> IGNORED (costs %d, you have %d)" % [label, Tech.cost(id2), v.scrap]
		"ready":
			if v.ready and not was_ready:
				return "ready -> ok"
			return "ready -> %s" % ("already ready" if was_ready else "IGNORED")
		"set_drive", "set_target":
			var key: String = "drive" if type == "set_drive" else "target"
			if str(v.doctrine[key]) == str(val) and str(old_doc[key]) != str(val):
				return "%s -> ok" % label
			if str(v.doctrine[key]) == str(val):
				return "%s -> ok (unchanged)" % label
			return "%s -> IGNORED (invalid value)" % label
	return "%s -> IGNORED (unknown command)" % label


# ================================================================ information UI scenarios

## Five named rigs with builds, doctrines, some tech and kills (DUNE RAT leads).
static func _lan_night(p_seed: int, spots: Array) -> SimWorld:
	var w := SimWorld.new(p_seed)
	var kills: PackedInt32Array = [64, 96, 70, 55, 40]
	for i in LAN_NIGHT.size():
		var d: Array = LAN_NIGHT[i]
		var v: SimVehicle = w.add_vehicle(i + 1, spots[i], d[0], d[1])
		var b: Array = GROWTH_BUILDS[d[2]]
		for t: String in d[5]:
			v.tech.append(t)
		_outfit(v, b[0], b[1])
		w.apply_command(v.peer_id, {"type": "set_drive", "value": d[3]})
		w.apply_command(v.peer_id, {"type": "set_target", "value": d[4]})
		v.kills = kills[i]
		v.scrap = 40 + 23 * i
		v.fuel = [62, 78, 55, 47, 70][i]
	return w


static func _knock_out(v: SimVehicle) -> void:
	v.fuel = 0
	v.eliminated = true
	v.alive = false
	v.hp = 0.0
	v.respawn_ticks = 0


## A player kill line for the feed / recap (events only: the sim state is untouched).
static func _feed_kill(w: SimWorld, killer: int, victim: int, weapon: int) -> void:
	w.events.append({"type": "kill", "pos": w.vehicles[victim].pos, "owner": killer, "kind": -1, "victim": victim, "weapon": weapon})


static func _step_info(name: String, w: SimWorld) -> void:
	var was: int = w.phase
	w.step()
	match name:
		"recap", "recap_pvp", "scouting":
			if w.phase == SimWorld.PHASE_COMBAT and name == "recap_pvp" and w.phase_ticks_left == 60:
				_feed_kill(w, 1, 0, Cards.weapon_kind_index("cannon"))
			if w.phase == SimWorld.PHASE_WORKSHOP and was == SimWorld.PHASE_COMBAT:
				_stage_recap(w, name == "recap_pvp")
		"combat_feed", "spectator":
			var at: Dictionary = {30: [1, 2, 2], 80: [0, 4, SimWorld.WEAPON_RAM], 112: [3, 1, 1], 150: [4, 3, 0]}
			if name == "spectator":
				at = {40: [1, 0, 2], 95: [2, 4, SimWorld.WEAPON_RAM]}
			if at.has(w.tick):
				var k: Array = at[w.tick]
				_feed_kill(w, k[0], k[1], k[2])
		"spectator_ws":
			if w.tick == 60:
				_feed_kill(w, 1, 0, Cards.weapon_kind_index("cannon"))
			if w.phase == SimWorld.PHASE_WORKSHOP and was == SimWorld.PHASE_COMBAT:
				_stage_out(w)
		"awards":
			if w.tick == 100:
				_stage_awards(w)


## Workshop after round 8: the local rig was wrecked (boulders and acid, or DUNE RAT's cannon) and has
## the least fuel; the rivals have shopped and readied.
static func _stage_recap(w: SimWorld, pvp: bool) -> void:
	w.phase_ticks_left = 19 * SimWorld.TICK_RATE + 12
	var me: SimVehicle = w.vehicles[0]
	var rs: Dictionary = me.round_stats
	rs["round"] = w.round  # the scenario jumped straight to round 8
	if pvp:
		rs["taken"] = {"mite": 28.0, "boulder": 46.0, "spitter": 0.0, "acid": 17.0, "rival": 352.0}
		rs["taken_players"] = {1: 301.0, 3: 51.0}
		rs["deaths"] = [{"t": 830, "cause": "player", "src": SimWorld.SRC_PLAYER, "killer": 1, "killer_kind": -1},
			{"t": 1712, "cause": "player", "src": SimWorld.SRC_PLAYER, "killer": 1, "killer_kind": -1}]
		rs["kills"] = 38
		rs["kills_players"] = 1
		rs["fuel_lost"] = 51
		rs["fuel_gained"] = 10
		me.doctrine = {"drive": "circle", "target": "nearest"}
	else:
		rs["taken"] = {"mite": 26.0, "boulder": 268.0, "spitter": 0.0, "acid": 126.0, "rival": 0.0}
		rs["deaths"] = [{"t": 1712, "cause": "boulder", "src": SimWorld.SRC_BOULDER, "killer": -1, "killer_kind": SimWorld.BOULDER}]
		rs["kills"] = 47
		rs["fuel_lost"] = 20
	rs["scrap_earned"] = 61 + int(rs.get("interest", 0))
	me.fuel = 31
	for i in range(1, w.vehicles.size()):
		var o: SimVehicle = w.vehicles[i]
		if not o.picked and not o.offers.is_empty():
			w.apply_command(o.peer_id, {"type": "pick_card", "value": 0})
		if i % 2 == 1:
			w.apply_command(o.peer_id, {"type": "ready"})


## Spectator workshop: the local rig ran dry this round (its recap and match so far).
static func _stage_out(w: SimWorld) -> void:
	w.phase_ticks_left = 17 * SimWorld.TICK_RATE + 5
	var me: SimVehicle = w.vehicles[0]
	var rs: Dictionary = SimWorld.new_round_stats(w.round)
	rs["taken"] = {"mite": 61.0, "boulder": 84.0, "spitter": 12.0, "acid": 39.0, "rival": 236.0}
	rs["taken_players"] = {1: 236.0}
	rs["deaths"] = [{"t": 1188, "cause": "player", "src": SimWorld.SRC_PLAYER, "killer": 1, "killer_kind": -1}]
	rs["kills"] = 22
	rs["fuel_lost"] = 21
	rs["scrap_earned"] = 34
	me.round_stats = rs
	me.match_stats = {"kills": 287, "player_kills": 2, "ram_kills": 0, "deaths": 6, "dmg_dealt": 5400.0,
		"scrap_earned": 744, "top_victim": 4, "top_victim_n": 1, "nemesis": 1, "nemesis_n": 3}
	for i in range(1, w.vehicles.size()):
		var o: SimVehicle = w.vehicles[i]
		o.match_stats["player_kills"] = [0, 6, 2, 3, 1][i]
		if i % 2 == 0:
			w.apply_command(o.peer_id, {"type": "ready"})


## Round 11: DUNE RAT is the last rig standing; everyone's match stats for the awards.
static func _stage_awards(w: SimWorld) -> void:
	var stats: Array = [  # kills, player kills, ram kills, deaths, scrap, nemesis id, nemesis n
		[412, 3, 0, 7, 1180, 1, 3], [388, 9, 1, 2, 1420, -1, 0], [455, 2, 4, 5, 990, 3, 2],
		[301, 5, 0, 6, 1050, 1, 2], [270, 1, 0, 9, 860, 1, 4]]
	for i in w.vehicles.size():
		var v: SimVehicle = w.vehicles[i]
		var st: Array = stats[i]
		v.match_stats = {"kills": st[0], "player_kills": st[1], "ram_kills": st[2], "deaths": st[3], "dmg_dealt": 0.0,
			"scrap_earned": st[4], "top_victim": -1, "top_victim_n": 0, "nemesis": st[5], "nemesis_n": st[6]}
		v.kills = st[0] + st[1]
		if i != 1:
			_knock_out(v)
	w.phase = SimWorld.PHASE_GAME_OVER
	w.winner_peer = w.vehicles[1].peer_id
