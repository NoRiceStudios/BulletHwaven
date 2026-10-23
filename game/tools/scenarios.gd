class_name Scenarios
extends RefCounted
## Named, deterministic SimWorld setups for screenshots (main.gd --shot=...) and manual checks.
## build(name, seed) + step(name, world) N times always gives the same state.
##
## Round-loop scenarios use fast_rounds (4 s combat) and auto-ready through early workshops:
## - "workshop"     (about 400 ticks): the workshop after round 3, red with scrap, cards and tech,
##                  magenta already picked and ready.
## - "tech_tree"    (about 400 ticks): the same workshop later in a match: red owns 14 tech nodes
##                  (both ballistics forks taken, a fusion) and 640 scrap, with the TECH view
##                  open (all five branches, no goals yet: the three ideas); --hover a node.
## - "tech_mid"     (about 400 ticks) TECH view later in a match (tech tree v2.3 UI): FIREBRAND goals, a
##                  built fusion (Hot Rod), a dormant one (Thermite Ram after swapping the bumper away),
##                  an idle keystone (War Rig after Truck -> Roll Cage), an active keystone in its swap
##                  window (Glowing Barrels), three fusions ready, mixed belts and three abilities.
## - "tech_swap"    tech_mid with the swap confirmation open (click on the struck-out Ram Bumper).
## - "workshop_mid" tech_mid's rig (Tungsten Stock instead of Mixed Belts, so one ammo type per gun and a
##                  chip for the other) in the PARTS view: ammo per gun, ability slots, compact tech column.
## - "tech_goals"   (about 400 ticks) the round 3 workshop with the player's own goals across three
##                  branches (War Rig, Thunderclap, Scrap Baron): flags, the framed way, NEXT.
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
## - "ranges"       (about 60 ticks) the weapon range rings (R) around a rig with all four guns in a
##                  horde: flamer, scatter gun and machine gun rings, the cannon's reaching off screen.
## - "pvp_on"       (about 380 ticks) fast rounds up to the start of round 4: the PVP ON banner.
## - "rig_kill"     (about 60 ticks) a rival rig blowing up next to yours (explosion and debris).
##
## Information UI review scenarios (playtest round 1 #2, #5, #10, #11), five named rigs (LAN_NIGHT):
## - "recap"        (about 160 ticks) workshop after round 8: wrecked by boulders and acid, zone king, KITE hint,
##                  interest x/cap, UNDERDOG badge, the fuel-drain notice.
## - "recap_pvp"    (about 160 ticks) the same, but DUNE RAT hunted you down with its cannon.
## - "scouting"     = recap; use --hover / --click on a convoy row for the dossier.
## - "combat_feed"  (about 160 ticks) round 6: kill feed lines and off-screen rival arrows.
## - "pvp_grace"    (about 90 ticks) start of round 4: the PvP grace countdown.
## - "spectator"    (about 120 ticks) you are eliminated: the camera follows the nearest fight.
## - "spectator_ws" (about 160 ticks) the workshop seen by an eliminated player.
## - "awards"       (about 120 ticks) game over with LAN-night awards.
##
## Combat visuals of the tech tree (tech tree v2.3 "Sichtbar als"; CombatFx, EffectsLayer, rig layers):
## - "fx_firebrand" (about 150 ticks) a FIREBRAND buggy (napalm, mixed belts, glowing barrels, nitro with
##                  dirty fuel and slipstream, burning wake) drifting through a horde: burning aliens, fire
##                  trail, oil, soot, two-tone tracers, hot barrels; a rival on hot loads with a jammed barrel.
## - "fx_fortress"  (about 95 ticks) a FORTRESS war rig with trailer (four guns, repair / junkyard drone,
##                  swarm logic lasers, salvo, EMP) in a horde.
## - "fx_scrapper"  (about 95 ticks)  a SCRAPPER buggy (scrap baron chain on 700 scrap, jerrycans, crane,
##                  armour piercing and one shot one kill) with a boulder contract: banners over boulders,
##                  saw blades, KILL pops.
## - "fx_chassis"   parked line-up (any ticks): buggy, framed buggy, pickup with dozer and spike skirts,
##                  truck, pickup with roll cage, war rig with trailer and drone, a sidecar buggy, jerrycans.
## - "fx_ram"       (about 60 ticks)  ramming builds: full momentum sparks, nitro jet, war machine
##                  shockwaves and thunderclap chains, a juggernaut glow, a phantom decoy, a dodge.
##
## Combat juice (KillFx, JuiceState, HUD combo / scrap / surge; docs/architecture.md "Combat visuals"):
## - "juice"        (about 150 ticks) a cannon / scattergun / MG pickup mowing through a dense mite horde
##                  with boulders and spitters: kill bursts, scrap sparkles, cannon impacts, the kill combo.
## - "juice_surge"  the same with a faked "surge" warning at tick JUICE_SURGE_TICK (appended to that tick's
##                  events like a scenario cue): SWARM INCOMING; shoot about 20 ticks later.
##
## Weapon evolutions (design doc 5a; RigView, WorldView, CombatFx, the HUD's EVOLVED banner, the legendary card):
## - "evo_combat"   (about 120 ticks) four rigs, one per evolved gun, holding a firing line in a horde: the local
##                  Gatling Hell (casings, tracer stream), a Meat Grinder, an Earthshaker (blasts, scorch) and an
##                  Inferno Spout.
## - "evo_flip"     evo_combat, but the local rig's machine gun evolves at tick EVO_FLIP_TICK (a scenario cue):
##                  the flash on the rig and the EVOLVED: GATLING HELL banner; shoot about 6 to 20 ticks later.
## - "evo_workshop" (about 380 ticks) the round 3 workshop with a Gatling Hell offer (machine gun L3 + V8).
## - "evo_moment"   evo_workshop, the evolution picked EVO_PICK_DELAY ticks after the workshop opens: the card
##                  stamped EVOLVED, the rig bursting and the banner over the panels; the pick lands at about tick 392, shoot
##                  about 4 to 30 ticks later.
##
## UI scenarios (main.gd also builds the menu from ui_state()):
## - "menu"     the attract battlefield (eight rigs, one per paint) behind the main menu.
## - "join"     the join screen with two fake discovered hosts (one in a match).
## - "lobby"    the host's lobby: four drivers, mixed ready.
## - "pause"    skirmish with the pause / menu overlay (LAN wording: the fight goes on).
## - "rematch"  gameover_mp seen by the host: REMATCH and LEAVE TO MENU.
## - "waiting"  gameover_mp seen by the loser (a client): waiting for the host's rematch.
## - "picker"   the programmed rig of "rules" in combat with the dock's behaviour picker open (--hover a chip).
## - "mark"     skirmish where MAD MAREK right-clicks an alien at tick MARK_CAST_TICK (target mark order;
##              about 215 ticks shows the reticle snapping in, 300 the order running).
## - "rules_logic" / "rules_logic_weapon" the rule editor on a rig with Radar and Targeting Computer: an ANY rule
##              with a hold time, a switched-off rule, a rule shadowed by an ALWAYS rule above it, an edited
##              priority list (the cannon has its own). Combat overlay, rig tab / cannon tab.
## - "workshop_rules" the "workshop" scenario in its RULES view.
## - "rules_live" the programmed rig of "rules" in combat with the live rule monitor (no overlay).
## - "radio"    skirmish where MAD MAREK calls ALL IN on the radio at tick MARK_CAST_TICK (about 260 ticks).
## - "deploy"   the deploy screen before round 1 (three rigs, one ready; --click a preset). Under 900 ticks.
##
## PvP control zones (docs/architecture.md "Control zones"; ZoneView, the HUD's zone panel and tags):
## - "zones"        (about 120 ticks) round 6, five rigs pinned in a horde around three zones: A (bottom
##                  centre) held by MAD MAREK, who stands in it and scores; B (right) LIMEADE's, DUNE RAT
##                  rolls in at ZONE_ENTER_TICK and takes it at about tick 156 (60 % at 120); C (left) SANDY's,
##                  contested by NIGHTCRAWLER. A capture of A is faked at ZONE_FLASH_TICK for the feed line and
##                  the burst (shoot 95 to 110 to see the burst).
## - "zones_locked" the same field at the start of round 4 with a short grace (ZONE_GRACE_TICKS): the zones
##                  locked (about 30), PVP ON (about 70), CONTROL ZONES OPEN after it (about 190).

const NAMES: PackedStringArray = ["skirmish", "horde", "workshop", "tech_tree", "gameover", "gameover_mp", "eliminated",
	"menu", "join", "lobby", "pause", "rematch", "waiting", "rig_growth", "late_round", "pvp_on", "rig_kill",
	"recap", "recap_pvp", "scouting", "combat_feed", "pvp_grace", "spectator", "spectator_ws", "awards",
	"tech_mid", "tech_swap", "workshop_mid", "tech_goals", "fx_firebrand", "fx_fortress", "fx_scrapper",
	"fx_chassis", "fx_ram", "juice", "juice_surge", "evo_combat", "evo_flip", "evo_workshop", "evo_moment", "boss_tripod", "boss_colossus", "boss_shards",
	"boss_warning", "boss_enraged", "boss_spawn", "boss_phase", "boss_kill", "boss_kill_colossus", "boss_retreat", "species", "hive", "picker", "deploy", "mark", "radio", "rules_live", "zones", "zones_locked", "rules_logic", "rules_logic_weapon", "workshop_rules", "ranges"]
const EVO_FLIP_TICK := 90
const MARK_CAST_TICK := 200
const EVO_PICK_DELAY := 30
const JUICE_SURGE_TICK := 100
const ZONE_ENTER_TICK := 66
const ZONE_FLASH_TICK := 90
const ZONE_GRACE_TICKS := 60
## Info-UI line-up: [name, paint, GROWTH_BUILDS index, drive, target, extra tech].
const LAN_NIGHT: Array = [
	["MAD MAREK", 0, 6, "circle", "nearest", ["ballistics_ammo_bench"]],
	["DUNE RAT", 2, 3, "kite", "players_first", ["ballistics_ammo_bench", "ballistics_belt_feed", "electronics_rangefinder", "salvage_hooks"]],
	["SANDY", 3, 2, "charge", "nearest", ["propulsion_tuned"]],
	["NIGHTCRAWLER", 7, 7, "circle", "strongest", []],
	["LIMEADE", 6, 1, "kite", "nearest", ["salvage_hooks"]],
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
		"workshop", "tech_tree", "tech_mid", "tech_swap", "workshop_mid", "tech_goals", "workshop_rules":
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
		"rules", "rules_weapon", "picker", "rules_live":
			return _programmed(p_seed)
		"rules_logic", "rules_logic_weapon":
			return _programmed_logic(p_seed)
		"deploy":
			return _deploy(p_seed)
		"mark", "radio":
			return _skirmish(p_seed)
		"rig_growth":
			return _rig_growth(p_seed)
		"late_round":
			return _late_round(p_seed)
		"ranges":
			var wr: SimWorld = _horde(p_seed)
			_outfit(wr.vehicles[0], 3, {"flamer": 2, "shotgun": 1, "cannon": 2, "mg": 3})
			return wr
		"pvp_on":
			var w4: SimWorld = attract(p_seed)
			w4.fast_rounds = true
			return w4
		"rig_kill":
			return _rig_kill(p_seed)
		"fx_firebrand", "fx_fortress", "fx_scrapper", "fx_chassis", "fx_ram":
			return _fx_world(name, p_seed)
		"juice", "juice_surge":
			return _juice_world(p_seed)
		"evo_combat", "evo_flip":
			return _evo_world(name, p_seed)
		"boss_tripod", "boss_colossus", "boss_shards", "boss_warning", "boss_enraged", "boss_spawn", "boss_phase", "boss_kill", \
				"boss_kill_colossus", "boss_retreat":
			return _boss_world(name, p_seed)
		"species":
			return _species_world(p_seed)
		"zones", "zones_locked":
			return _zones_world(name, p_seed)
		"hive":
			var wh: SimWorld = _skirmish(p_seed)
			wh.fast_rounds = true
			return wh
		"evo_workshop", "evo_moment":
			var we: SimWorld = _skirmish(p_seed)
			we.fast_rounds = true
			return we
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
		"ranges":
			return {"ranges": true}
		"tech_tree":
			return {"workshop_tab": "tech"}
		"tech_mid":
			return {"workshop_tab": "tech", "workshop_actions": [["idea", "firebrand"]]}
		"tech_swap":
			return {"workshop_tab": "tech", "workshop_actions": [["idea", "firebrand"], ["tech", "propulsion_bumper"]]}
		"workshop_mid":
			return {"workshop_actions": [["idea", "firebrand"]]}
		"tech_goals":
			return {"workshop_tab": "tech", "workshop_actions": [["goal", "engineering_war_rig"], ["goal", "fusion_thunderclap"], ["goal", "salvage_baron"]]}
		"rules":
			return {"rules": "rig"}
		"rules_weapon":
			return {"rules": "cannon"}
		"rules_logic":
			return {"rules": "rig"}
		"rules_logic_weapon":
			return {"rules": "cannon"}
		"workshop_rules":
			return {"workshop_tab": "rules"}
		"picker":
			return {"picker": true}
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
	if name.begins_with("boss_"):
		_boss_step(name, w)
		return
	if name == "species":
		_species_step(w)
		return
	if name == "zones" or name == "zones_locked":
		_zones_step(name, w)
		return
	if name == "radio":
		if w.tick == MARK_CAST_TICK:
			w.apply_command(1, {"type": "radio", "value": "all_in"})
		w.step()
		return
	if name == "mark":
		if w.tick == MARK_CAST_TICK:  # the alien nearest a point 120 px ahead of the rig, like a player's right click
			var me: SimVehicle = w.vehicles[0]
			var aim: Vector2 = me.pos + Vector2.from_angle(me.heading) * 120.0
			var best: int = -1
			for i in w.enemy_count:
				if best < 0 or w.enemy_pos[i].distance_squared_to(aim) < w.enemy_pos[best].distance_squared_to(aim):
					best = i
			if best >= 0:
				w.apply_command(1, {"type": "mark", "x": w.enemy_pos[best].x, "y": w.enemy_pos[best].y})
		w.step()
		return
	if name == "hive":  # the first workshop, held (round 1 is over: the panel lists this match's species and the next boss)
		if w.phase == SimWorld.PHASE_COMBAT:
			w.step()
		else:
			w.tick += 1
		return
	if name == "rig_growth" or name == "fx_chassis":
		w.tick += 1  # parked: only the clock runs (nitro flicker, ring)
		return
	if name.begins_with("fx_"):
		_fx_step(name, w)
		return
	if name.begins_with("juice"):
		_juice_step(name, w)
		return
	if name == "evo_combat" or name == "evo_flip":
		_evo_step(name, w)
		return
	if name == "evo_workshop" or name == "evo_moment":
		_evo_workshop_step(name, w)
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
		"workshop", "tech_tree", "tech_mid", "tech_swap", "workshop_mid", "tech_goals", "workshop_rules":
			if w.phase == SimWorld.PHASE_WORKSHOP:
				if w.round < WORKSHOP_ROUND:
					_ready_all(w)
				elif not w.has_meta("staged"):
					_stage_workshop(w)
					if name == "tech_tree":
						_stage_tech_tree(w.vehicles[0])
						_stage_salvage(w, w.vehicles[0])
					elif name in ["tech_mid", "tech_swap", "workshop_mid"]:
						_stage_tech_mid(w, w.vehicles[0], name != "workshop_mid")
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


## Later in a match: a ballistics line to stage 4 (napalm), engineering to the pickup, electronics to
## stage 3, drift, the Burning Wake fusion, and scrap for the next big node.
static func _stage_tech_tree(red: SimVehicle) -> void:
	red.scrap = 99999
	for id: String in ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm",
			"engineering_frame", "engineering_welder", "engineering_pickup", "electronics_rangefinder",
			"electronics_radar", "electronics_targeting", "propulsion_tuned", "propulsion_drift",
			"fusion_burning_wake", "salvage_hooks"]:
		Tech.buy(red, id)
	red.scrap = 640


## Tech tree v2.3 UI check: a mixed rig with a built, a dormant and three ready fusions, an idle keystone
## (War Rig after Truck -> Roll Cage, the free first swap), an active keystone in its swap window, mixed
## belts (two ammo types per gun), three guns and three abilities for two slots.
static func _stage_tech_mid(w: SimWorld, red: SimVehicle, mixed: bool = true) -> void:
	red.scrap = 99999
	for id: String in ["ballistics_ammo_bench", "ballistics_belt_feed", "engineering_frame", "ballistics_tables", "ballistics_napalm",
			"ballistics_mixed_belts" if mixed else "ballistics_tungsten", "ballistics_glowing",
			"engineering_welder", "engineering_pickup", "engineering_drone", "engineering_truck", "engineering_war_rig",
			"propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "fusion_thermite", "electronics_rangefinder",
			"electronics_relay", "electronics_targeting", "electronics_emp", "electronics_neural"]:
		Tech.buy(red, id, w.round)
	Cards.grant(red, "cannon")
	Tech.respec(red, "engineering_truck", "engineering_roll_cage", w.round)
	Tech.respec(red, "propulsion_bumper", "propulsion_drift", w.round)
	Tech.buy(red, "fusion_hot_rod", w.round)
	red.scrap = 640


## Salvage UI check: haggler, black market (two contract offers), scrap press, a lucky-strike fourth card and a loan debt.
static func _stage_salvage(w: SimWorld, red: SimVehicle) -> void:
	red.scrap = 99999
	for id: String in ["salvage_haggler", "salvage_black_market", "salvage_press"]:
		Tech.buy(red, id)
	red.scrap = 640
	red.loan_debt = 220
	red.loan_left = 2
	red.offers = Cards.roll_offers(w.rng, red, Cards.OFFER_COUNT + 1, w.round)
	red.reserved_card = red.offers[1]
	Salvage.roll(w, red)


## A mid-game workshop: some scrap, a few cards and tech, 19 s on the clock, rival ready.
static func _stage_workshop(w: SimWorld) -> void:
	w.set_meta("staged", true)
	w.phase_ticks_left = 19 * SimWorld.TICK_RATE + 12
	var red: SimVehicle = w.vehicles[0]
	for id: String in ["shotgun", "steel_plates", "steel_plates", "v8_engine"]:
		Cards.grant(red, id)
	red.offers = Cards.roll_offers(w.rng, red)  # re-deal for the new loadout (slots are full now)
	red.scrap = 107
	for id: String in ["ballistics_ammo_bench", "engineering_frame", "ballistics_belt_feed"]:
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
	# Engineering "tier" -> the chassis chain: 1 frame, 2 pickup (chassis 2), 3 truck (chassis 3).
	var chain: PackedStringArray = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_drone", "engineering_truck"]
	for t in [0, 1, 3, 5][clampi(tier, 0, 3)]:
		v.tech.append(chain[t])
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


## Boss scenarios (round 4 boss fight): three tough rigs; the boss walks in and is moved next to them (see
## _boss_step). "boss_tripod": Tripod Queen at ~50% hp (phase 2: shells and mite broods; shoot about 90 to 200
## ticks), "boss_colossus": Shard Colossus at ~55% (phase 2: glow rings and charges; about 100 to 260 ticks),
## "boss_shards": the Colossus at 20% (it splits at once: the crystal burst at 3 to 30 ticks, the three shard
## minibosses later). Moments: "boss_warning" (the Queen announced: shoot 20 to 90, she surfaces at about 92),
## "boss_enraged" (the same for an enraged round-12 Colossus), "boss_spawn" (the convoy near the west edge: she
## erupts at about tick 21; shoot 22 to 50), "boss_phase" (phase 2 roar at BOSS_MOMENT_TICK; shoot +3 to +60),
## "boss_kill" / "boss_kill_colossus" (the boss dies at about BOSS_MOMENT_TICK + 1; shoot +5 to +150),
## "boss_retreat" (the round ends with the Queen alive at about tick 60: the workshop opens; shoot 62 to 120).
const BOSS_MOMENT_TICK := 60


static func _boss_world(name: String, p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = 12 if name == "boss_enraged" else 4
	var colossus: bool = name in ["boss_colossus", "boss_shards", "boss_enraged", "boss_kill_colossus"]
	# boss_first picks the opener; round 12 is the third boss round, the opener's own again
	w.boss_first = 1 if colossus else 0
	var c: Vector2 = SimWorld.ARENA.get_center()
	var spots: Array = [c, c + Vector2(-90, 70), c + Vector2(80, 110)]
	if name == "boss_spawn":  # the convoy by the west edge, so the eruption is in frame
		c = Vector2(250.0, c.y)
		spots = [c, c + Vector2(60, 90), c + Vector2(40, -100)]
	var builds: Array = [GROWTH_BUILDS[6], GROWTH_BUILDS[3], GROWTH_BUILDS[2]]
	for i in 3:
		var v: SimVehicle = w.add_vehicle(i + 1, spots[i], ATTRACT_NAMES[i * 2], [0, 2, 3][i])
		_outfit(v, builds[i][0], builds[i][1])
		v.max_hp *= 12.0
		v.hp = v.max_hp
		v.fuel = 100
		v.round_stats = SimWorld.new_round_stats(w.round)
	w.apply_command(1, {"type": "set_drive", "value": "circle"})
	w.apply_command(1, {"type": "set_target", "value": "boss"})
	_scatter(w, 50, 0.04, 0.02, 160.0, 600.0)
	var dur: int = w.combat_duration(w.round)
	var start: int = SimWorld.surge_starts(dur)[0]
	var lead: int = Bosses.WARN_TICKS + 2 if name == "boss_warning" or name == "boss_enraged" else 20
	w.phase_ticks_left = dur - (start - lead)
	return w


static func _boss_step(name: String, w: SimWorld) -> void:
	w.step()
	if w.boss_state != Bosses.ST_ACTIVE or name == "boss_spawn":
		return
	var first: bool = not w.has_meta("boss_placed")
	w.set_meta("boss_placed", true)
	var c: Vector2 = w.vehicles[0].pos
	var fracs: Dictionary = {"boss_tripod": 0.5, "boss_colossus": 0.55, "boss_shards": 0.2, "boss_phase": 0.69,
		"boss_kill": 0.2, "boss_kill_colossus": 0.2, "boss_retreat": 0.45}
	var moment: bool = w.tick == BOSS_MOMENT_TICK
	for i in w.enemy_count:
		var k: int = w.enemy_kind[i]
		if k < SimWorld.BOSS_A or w.enemy_hp[i] <= 0.0:
			continue
		var pinned: bool = name == "boss_tripod" or (k == SimWorld.BOSS_A and name in ["boss_phase", "boss_kill", "boss_retreat"])
		if first or pinned:  # pinned next to the camera rig so the shot frames it
			var off := Vector2(170, -30)
			if k == SimWorld.BOSS_A:
				off = Vector2(230, 40) if name == "boss_tripod" else Vector2(150, -20)
			w.enemy_pos[i] = c + off
		if first and k != SimWorld.BOSS_SHARD:
			if name == "boss_colossus" or name == "boss_tripod":  # a longer fight, so every attack shows
				w.boss_max_hp *= 4.0
			w.enemy_hp[i] = w.boss_max_hp * float(fracs.get(name, 1.0))
		if moment and name == "boss_phase":
			w.enemy_hp[i] = w.boss_max_hp * 0.64
		if name == "boss_kill_colossus" and k == SimWorld.BOSS_SHARD and w.tick > 20:
			if w.tick < BOSS_MOMENT_TICK:  # whittle the shards down: the first two die early, the last waits by the camera
				if w.enemy_id[i] % 3 != 0 and w.tick % 10 == 0:
					w.enemy_hp[i] = 0.5
				w.enemy_pos[i] = c + Vector2(110, -30)
		if moment and (name == "boss_kill" or name == "boss_kill_colossus"):
			w.enemy_hp[i] = 0.5  # the next shot kills
	if (name == "boss_kill" or name == "boss_kill_colossus") and w.tick >= BOSS_MOMENT_TICK - 4:
		if not w.has_meta("rig_pins"):  # the rigs hold still so the camera stays on the kill
			var pins: Array = []
			for v in w.vehicles:
				pins.append(v.pos)
			w.set_meta("rig_pins", pins)
		var pins2: Array = w.get_meta("rig_pins")
		for vi in w.vehicles.size():
			w.vehicles[vi].pos = pins2[vi]
			w.vehicles[vi].vel = Vector2.ZERO
	if name == "boss_retreat" and first:
		w.phase_ticks_left = mini(w.phase_ticks_left, 40)


## "species": round 6 with all three hive-signature species in one fight (the signature is forced to all three): a
## glass wing flock circling and diving, brood carriers (one bursts at SPECIES_BURST_TICK), two shriekers pulsing behind
## a mite horde. Two tough rigs; red targets shriekers first. About 120..220 ticks; the pulse rings and a dive show up at
## different ticks, so try a few.
static func _species_world(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = 6
	w.hive_first = PackedInt32Array([3, 3, 3])
	w.spawning_enabled = false
	var c: Vector2 = SimWorld.ARENA.get_center()
	var builds: Array = [GROWTH_BUILDS[6], GROWTH_BUILDS[3]]
	var spots: Array = [c, c + Vector2(-90, 60)]
	for i in 2:
		var v: SimVehicle = w.add_vehicle(i + 1, spots[i], ATTRACT_NAMES[i * 2], [0, 2][i])
		_outfit(v, builds[i][0], builds[i][1])
		v.max_hp *= 12.0
		v.hp = v.max_hp
		v.fuel = 100
	w.apply_command(1, {"type": "set_drive", "value": "circle"})
	w.apply_command(1, {"type": "set_target", "value": "shriekers"})
	w.phase_ticks_left = w.combat_duration(6) - 400
	_scatter(w, 70, 0.04, 0.03, 110.0, 460.0)
	for k in 5:
		w.spawn_enemy(SimWorld.GLASS, c + Vector2(190 + k * 9, -110 + k * 13))
	var broods: Array = [Vector2(-150, 40), Vector2(120, 100), Vector2(-40, -140)]
	for b: Vector2 in broods:
		w.spawn_enemy(SimWorld.BROOD, c + b)
	var shriekers: Array = [Vector2(260, 60), Vector2(-250, -70)]
	for s: Vector2 in shriekers:
		w.spawn_enemy(SimWorld.SHRIEKER, c + s)
		for k in 6:  # the horde around them
			var a: float = w.rng.randf() * TAU
			w.spawn_enemy(SimWorld.MITE, c + s + Vector2.from_angle(a) * (20.0 + w.rng.randf() * 60.0))
	return w


const SPECIES_BURST_TICK := 40


static func _species_step(w: SimWorld) -> void:
	w.step()
	var burst: int = -1
	var best: float = INF
	for i in w.enemy_count:
		var k: int = w.enemy_kind[i]
		if k >= SimWorld.GLASS and k <= SimWorld.SHRIEKER:
			w.enemy_hp[i] = w.enemy_max_hp_of(i)  # the show goes on: the guns cannot finish the specimens
			if k == SimWorld.BROOD and w.tick == SPECIES_BURST_TICK:
				var d: float = w.enemy_pos[i].distance_squared_to(w.vehicles[0].pos)
				if d < best:
					best = d
					burst = i
	if burst >= 0:  # the brood carrier nearest to the rig is shot dead: burst frame, then the mites
		w._hit_enemy(burst, 1000.0, 0)


## Two rigs (red: circle / nearest, magenta: kite / players_first) in a running horde.
## Three fresh rigs in the deploy phase before round 1; the second one is already ready.
static func _deploy(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.add_vehicle(1, _old_arena(Vector2(560, 380)), "MAD MAREK")
	w.add_vehicle(2, _old_arena(Vector2(760, 330)), "DUNE RAT", 2)
	w.add_vehicle(3, _old_arena(Vector2(700, 470)), "SANDY", 3)
	w.begin_deploy()
	w.apply_command(2, {"type": "ready"})
	return w


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



# ================================================================ combat visuals (tech tree v2.3)

## Buys `ids` in order (prerequisites first), grants `cards` (levels), refills hp.
static func _tech_up(w: SimWorld, v: SimVehicle, ids: Array, cards: Dictionary = {}) -> void:
	for id: String in cards:
		for i in int(cards[id]):
			Cards.grant(v, id)
	v.scrap = 99999
	for id: String in ids:
		if not Tech.buy(v, id, w.round):
			push_warning("scenarios: could not buy %s" % id)
	v.scrap = 0
	Cards.recompute(v)
	v.hp = v.max_hp


const FIREBRAND: Array = ["ballistics_ammo_bench", "ballistics_belt_feed", "ballistics_tables", "ballistics_napalm",
	"ballistics_mixed_belts", "ballistics_glowing", "propulsion_tuned", "propulsion_drift", "propulsion_nitro",
	"propulsion_dirty_fuel", "propulsion_slipstream", "fusion_burning_wake"]
const FORTRESS: Array = ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_drone",
	"engineering_truck", "engineering_war_rig", "electronics_rangefinder", "electronics_relay", "electronics_targeting",
	"electronics_emp", "electronics_neural", "electronics_swarm", "fusion_junkyard", "fusion_fortified"]
const SCRAPPER: Array = ["salvage_hooks", "salvage_haggler", "salvage_black_market", "salvage_jerrycans", "salvage_crane",
	"salvage_baron", "ballistics_ammo_bench", "ballistics_heavy_shells", "ballistics_tables", "ballistics_he",
	"ballistics_tungsten", "ballistics_one_shot"]
const RAMMER: Array = ["propulsion_tuned", "propulsion_bumper", "propulsion_nitro", "propulsion_battering",
	"propulsion_turbine", "propulsion_juggernaut", "engineering_frame", "engineering_spikes", "fusion_war_machine",
	"electronics_rangefinder", "electronics_radar", "electronics_targeting", "electronics_emp", "fusion_thunderclap"]
const PHANTOM: Array = ["propulsion_tuned", "propulsion_drift", "propulsion_nitro", "propulsion_ghost", "propulsion_sidecar",
	"propulsion_phantom", "engineering_frame", "engineering_welder", "engineering_pickup", "engineering_dozer",
	"engineering_roll_cage", "engineering_featherweight"]


static func _fx_world(name: String, p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = 6
	w.phase_ticks_left = 99999
	var c: Vector2 = SimWorld.ARENA.get_center()
	match name:
		"fx_firebrand":
			var me: SimVehicle = w.add_vehicle(1, c, "MAD MAREK", 0)
			_tech_up(w, me, FIREBRAND, {"flamer": 2, "mg": 2, "shotgun": 1})
			w.apply_command(1, {"type": "set_drive", "value": "circle"})
			var rv: SimVehicle = w.add_vehicle(2, c + Vector2(150, -60), "DUNE RAT", 2)
			_tech_up(w, rv, ["ballistics_ammo_bench", "ballistics_heavy_shells", "ballistics_hot_loads"], {"cannon": 2, "mg": 1})
			w.apply_command(2, {"type": "set_drive", "value": "kite"})
			_scatter(w, 240, 0.04, 0.04, 70.0, 460.0)
		"fx_fortress":
			var me2: SimVehicle = w.add_vehicle(1, c, "MAD MAREK", 3)
			_tech_up(w, me2, FORTRESS, {"cannon": 2, "mg": 2, "shotgun": 1})
			Cards.grant(me2, "flamer")
			Cards.recompute(me2)
			me2.hp = me2.max_hp * 0.7
			w.apply_command(1, {"type": "set_drive", "value": "kite"})
			w.apply_command(1, {"type": "set_target", "value": "boulders"})  # long swarm-logic lasers
			_scatter(w, 80, 0.1, 0.08, 190.0, 460.0)
		"fx_scrapper":
			var me3: SimVehicle = w.add_vehicle(1, c, "MAD MAREK", 6)
			_tech_up(w, me3, SCRAPPER, {"cannon": 2, "mg": 2})
			me3.scrap = 720
			me3.contract_kind = Salvage.K_BOULDERS
			me3.contract_need = 5
			me3.contract_prog = 2.0
			me3.contract_reward = 70
			w.apply_command(1, {"type": "set_drive", "value": "circle"})
			_scatter(w, 110, 0.14, 0.06, 170.0, 440.0)
		"fx_ram":
			var me4: SimVehicle = w.add_vehicle(1, c, "MAD MAREK", 0)
			_tech_up(w, me4, RAMMER, {"shotgun": 1})
			w.apply_command(1, {"type": "set_drive", "value": "charge"})
			var ph: SimVehicle = w.add_vehicle(2, c + Vector2(-70, 30), "SANDY", 5)
			_tech_up(w, ph, PHANTOM, {"mg": 2, "flamer": 1})
			w.apply_command(2, {"type": "set_drive", "value": "charge"})
			_scatter(w, 300, 0.04, 0.04, 80.0, 400.0)
		"fx_chassis":
			w.spawning_enabled = false
			# one row, the war rig (the local rig, so the camera centres on it) in the middle: [name, paint, tech, cards, x]
			var line: Array = [
				["WAR RIG", 5, FORTRESS.slice(0, 6), {"cannon": 3, "mg": 2, "flamer": 1}, 0.0],
				["BUGGY", 0, [], {}, -210.0],
				["FRAME", 1, ["engineering_frame", "engineering_spikes"], {"shotgun": 1}, -140.0],
				["PICKUP", 2, ["engineering_frame", "engineering_spikes", "engineering_pickup", "engineering_dozer"], {"mg": 1, "cannon": 1}, -70.0],
				["TRUCK", 3, ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_reactive", "engineering_truck"], {"cannon": 2, "mg": 1}, 70.0],
				["CAGE", 4, ["engineering_frame", "engineering_welder", "engineering_pickup", "engineering_dozer", "engineering_roll_cage"], {"shotgun": 2, "flamer": 1}, 140.0],
				["SIDECAR", 6, ["propulsion_tuned", "propulsion_drift", "propulsion_nitro", "propulsion_slipstream", "propulsion_sidecar"], {"mg": 2, "flamer": 1}, 210.0],
				["JERRYCANS", 7, ["salvage_hooks", "salvage_lucky", "salvage_black_market", "salvage_jerrycans", "salvage_hoarder"], {"mg": 1}, 280.0],
			]
			for i in line.size():
				var v: SimVehicle = w.add_vehicle(i + 1, c + Vector2(line[i][4], -20.0), line[i][0], line[i][1])
				_tech_up(w, v, line[i][2], line[i][3])
				v.heading = -PI / 2.0
				v.vel = Vector2.from_angle(v.heading) * 60.0
				v.hp = v.max_hp * (0.6 if i == 0 else 1.0)
				for k in v.weapons.size():
					v.weapons[k]["aim"] = v.heading + 0.5 - 0.6 * k
	for v in w.vehicles:
		v.invuln_ticks = 0
	return w


## Combat-visual scenarios: keep the fight going and trigger the abilities on cue.
static func _fx_step(name: String, w: SimWorld) -> void:
	w.step()
	w.phase_ticks_left = 99999
	var me: SimVehicle = w.vehicles[0]
	me.hp = maxf(me.hp, me.max_hp * 0.5)
	if w.enemy_count < (120 if name == "fx_firebrand" else 60):
		_scatter(w, 30, 0.05, 0.05, 200.0, 460.0)
	_fx_cues(name, w, me)  # after the step: the ability events join this tick's recorded events


static func _fx_cues(name: String, w: SimWorld, me: SimVehicle) -> void:
	match name:
		"fx_firebrand":
			me.momentum = 100.0
			if w.tick % 45 == 20 and me.ab_cd[0] <= 0:
				w.apply_command(1, {"type": "use_ability", "value": "nitro"})
		"fx_fortress":
			for cue: Array in [[88, "salvo"], [92, "emp"]]:  # fire on cue even if the auto-cast already used it
				var slot: int = me.abilities.find(cue[1])
				if w.tick == cue[0] and slot >= 0:
					me.ab_cd[slot] = 0
					w.apply_command(1, {"type": "use_ability", "value": cue[1]})
			me.hp = minf(me.hp, me.max_hp * 0.75)
		"fx_scrapper":
			if w.tick % 40 == 25:  # scrap-press saw blades (the sim launches them at combat start)
				for k in 2:
					var dir: Vector2 = Vector2.from_angle(float(w.tick) * 0.37 + float(k) * 2.6)
					w.spawn_projectile(me.pos + dir * SimWorld.MUZZLE_OFFSET, dir * Salvage.SAW_SPEED, Salvage.SAW_TTL,
							Salvage.SAW_DAMAGE, me.id, Salvage.SAW_PIERCE)
			me.contract_prog = minf(me.contract_prog, 3.0)
			me.scrap = maxi(me.scrap, 700)
		"fx_ram":
			me.momentum = 100.0
			w.vehicles[1].momentum = 100.0
			if w.tick % 50 == 10:
				w.apply_command(1, {"type": "use_ability", "value": "nitro"})
			if w.tick % 60 == 30:
				w.apply_command(2, {"type": "use_ability", "value": "nitro"})


# ================================================================ combat juice

static func _juice_world(p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = 5
	w.phase_ticks_left = 99999
	var c: Vector2 = SimWorld.ARENA.get_center()
	var me: SimVehicle = w.add_vehicle(1, c, "MAD MAREK", 0)
	_tech_up(w, me, ["engineering_frame", "engineering_welder", "engineering_pickup", "ballistics_ammo_bench"],
			{"cannon": 2, "shotgun": 3, "mg": 3})
	w.apply_command(1, {"type": "set_drive", "value": "circle"})
	var rv: SimVehicle = w.add_vehicle(2, c + Vector2(260, 120), "DUNE RAT", 2)
	_tech_up(w, rv, [], {"mg": 2})
	w.apply_command(2, {"type": "set_drive", "value": "kite"})
	_scatter(w, 300, 0.05, 0.04, 120.0, 460.0)
	for v in w.vehicles:
		v.invuln_ticks = 0
	return w


static func _juice_step(name: String, w: SimWorld) -> void:
	w.step()
	w.phase_ticks_left = 99999
	var me: SimVehicle = w.vehicles[0]
	me.hp = maxf(me.hp, me.max_hp * 0.6)
	if w.enemy_count < 240:
		_scatter(w, 30, 0.05, 0.04, 170.0, 380.0)
	if w.tick % 9 == 0:  # soften the nearest boulder and spitter so their kill bursts show up often
		for kind: int in [SimWorld.BOULDER, SimWorld.SPITTER]:
			var best: int = -1
			var best_d: float = 170.0 * 170.0
			for j in w.enemy_count:
				var d: float = w.enemy_pos[j].distance_squared_to(me.pos)
				if w.enemy_kind[j] == kind and d < best_d:
					best_d = d
					best = j
			if best >= 0:
				w.enemy_hp[best] = minf(w.enemy_hp[best], 2.0)
	if name == "juice_surge" and w.tick == JUICE_SURGE_TICK:  # faked: the sim's own surge warning lands later
		w.events.append({"type": "surge", "pos": me.pos, "owner": -1, "kind": -1, "in_ticks": 60})


# ================================================================ weapon evolutions

## [name, paint, chassis tier, cards (weapon card levels as grants: a weapon starts at 1 only for the mg),
## offset from the centre]. The evolution card comes last, after its weapon (L3) and its partner.
const EVO_LINE: Array = [
	["MAD MAREK", 0, 2, {"mg": 2, "v8_engine": 2, "steel_plates": 1, "evo_gatling": 1}, Vector2(0, 0)],
	["DUNE RAT", 2, 1, {"shotgun": 3, "spiked_plating": 2, "evo_grinder": 1}, Vector2(-150, -48)],
	["SANDY", 3, 3, {"cannon": 3, "caterpillar_tracks": 1, "reinforced_hull": 1, "evo_earthshaker": 1}, Vector2(150, -40)],
	["NIGHTCRAWLER", 5, 2, {"flamer": 3, "nitro": 2, "spiked_plating": 1, "evo_inferno": 1}, Vector2(-30, 82)],
]


static func _evo_world(name: String, p_seed: int) -> SimWorld:
	var w := SimWorld.new(p_seed)
	w.round = 3  # spitters, but no PvP: every gun works the horde
	w.phase_ticks_left = 99999
	var c: Vector2 = SimWorld.ARENA.get_center()
	for i in EVO_LINE.size():
		var e: Array = EVO_LINE[i]
		var v: SimVehicle = w.add_vehicle(i + 1, c + (e[4] as Vector2), e[0], e[1])
		var cards: Dictionary = (e[3] as Dictionary).duplicate()
		if name == "evo_flip" and i == 0:
			cards.erase("evo_gatling")  # granted on cue
		_outfit(v, e[2], cards)
		v.heading = -PI / 2.0 + 0.3 * float(i % 2) - 0.15
		v.invuln_ticks = 0
		w.set_meta("anchor_%d" % i, v.pos)
	_scatter(w, 300, 0.035, 0.04, 100.0, 380.0)
	return w


## The line holds (each rig pinned to its spot, turning as its AI likes), the horde is topped up, and in
## "evo_flip" the local machine gun evolves on cue (like the workshop pick would).
static func _evo_step(name: String, w: SimWorld) -> void:
	w.step()
	w.phase_ticks_left = 99999
	for i in w.vehicles.size():
		var v: SimVehicle = w.vehicles[i]
		v.pos = w.get_meta("anchor_%d" % i, v.pos)
		v.vel = Vector2.ZERO  # parked: casings and tracks stay where the rig is
		v.hp = maxf(v.hp, v.max_hp * 0.8)
	if w.enemy_count < 200:
		_scatter(w, 40, 0.035, 0.04, 200.0, 380.0)
	if name == "evo_flip" and w.tick == EVO_FLIP_TICK:
		Cards.grant(w.vehicles[0], "evo_gatling")


## Round-3 workshop staging with an evolution on offer; "evo_moment" picks it after EVO_PICK_DELAY ticks.
static func _evo_workshop_step(name: String, w: SimWorld) -> void:
	w.step()
	if w.phase != SimWorld.PHASE_WORKSHOP:
		return
	if w.round < WORKSHOP_ROUND:
		_ready_all(w)
		return
	var red: SimVehicle = w.vehicles[0]
	if not w.has_meta("staged"):
		w.set_meta("staged", w.tick)
		w.phase_ticks_left = 41 * SimWorld.TICK_RATE + 12
		for id: String in ["mg", "mg", "v8_engine", "shotgun", "shotgun", "steel_plates"]:
			Cards.grant(red, id)
		red.offers = Cards.roll_offers(w.rng, red, Cards.OFFER_COUNT, w.round)
		red.scrap = 132
		red.fuel = 72
		for id: String in ["ballistics_ammo_bench", "engineering_frame"]:
			w.apply_command(red.peer_id, {"type": "buy_tech", "value": id})
		var mag: SimVehicle = w.vehicles[1]
		w.apply_command(mag.peer_id, {"type": "pick_card", "value": 0})
		w.apply_command(mag.peer_id, {"type": "ready"})
	elif name == "evo_moment" and w.tick == int(w.get_meta("staged")) + EVO_PICK_DELAY:
		var at: int = red.offers.find("evo_gatling")
		w.apply_command(red.peer_id, {"type": "pick_card", "value": maxi(at, 0)})


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
const REPLAY_COMMANDS: PackedStringArray = ["pick_card", "reroll", "buy_tech", "respec_tech", "ready", "set_drive", "set_target", "set_rules", "set_weapon_target"]


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
	var respecs: int = v.respecs
	var was_picked: bool = v.picked
	var was_ready: bool = v.ready
	if v.eliminated and type in ["pick_card", "reroll", "buy_tech", "respec_tech", "ready"]:
		return "%s -> IGNORED (you are eliminated)" % label
	var old_offers: Array[String] = v.offers.duplicate()
	var old_doc: Dictionary = v.doctrine.duplicate()
	var old_prog: String = Doctrine.fingerprint(v)
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
			if Tech.blocked_by(v, id2) != "":
				return "%s -> IGNORED (excluded by %s)" % [label, Tech.blocked_by(v, id2)]
			var pre: String = Tech.missing(v, id2)
			if pre != "":
				return "%s -> IGNORED (needs %s first)" % [label, pre]
			return "%s -> IGNORED (costs %d, you have %d)" % [label, Tech.price(v, id2), v.scrap]
		"respec_tech":
			if v.respecs > respecs:
				return "%s -> swapped %s (%+d scrap)" % [label, str(cmd.get("from", "")), v.scrap - scrap]
			return "%s -> IGNORED (needs an owned choice and an unowned one of the same stage, scrap, and for stage 6 the round after buying)" % label
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
		"set_rules", "set_weapon_target":
			if Doctrine.fingerprint(v) != old_prog:
				return "%s -> ok" % label
			if NetSession.validate_command(cmd).is_empty():
				return "%s -> IGNORED (invalid scope or rule text)" % label
			return "%s -> ok (unchanged)" % label
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
		rs["zone_points"] = 14  # held a control zone for 14 s, and the most ground: zone king
		rs["fuel_gained"] = Zones.ZONE_FUEL_BONUS
		w.events.append({"type": "zone_bonus", "pos": me.pos, "owner": me.id, "kind": Zones.ZONE_FUEL_BONUS})
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


## The rule editor (render/doctrine_editor.gd) over a skirmish: a rig with three guns and rules in
## several lists, some of them matching (lit lamps).
static func _programmed(p_seed: int) -> SimWorld:
	var w: SimWorld = _skirmish(p_seed)
	var me: SimVehicle = w.vehicles[0]
	Cards.grant(me, "cannon")
	me.tech.append("electronics_rangefinder")
	Cards.recompute(me)
	for cmd: Dictionary in [
		{"type": "set_rules", "scope": "rig", "value": "hp<30|drive:flee;swarm>10&t_dist<150|drive:kite;pvp=1&rivals>0|target:players_first"},
		{"type": "set_weapon_target", "scope": "cannon", "value": "strongest"},
		{"type": "set_rules", "scope": "cannon", "value": "t_boulder=1&t_hp<20|fire:hold;has_target=1|target:spitters"},
		{"type": "set_rules", "scope": "mg", "value": "t_dist>200|fire:hold"},
	]:
		w.apply_command(me.peer_id, cmd)
	return w


static func _programmed_logic(p_seed: int) -> SimWorld:
	var w: SimWorld = _programmed(p_seed)
	var me: SimVehicle = w.vehicles[0]
	me.tech.append_array(["electronics_radar", "electronics_targeting"])
	Cards.recompute(me)
	for cmd: Dictionary in [
		{"type": "set_rules", "scope": "rig", "value": "hp<35/under_fire=1/swarm>25|drive:flee@2;-swarm>10&t_dist<150|drive:kite;flyers>1|target:priority;|target:nearest;pvp=1&rivals>0|target:players_first"},
		{"type": "set_target", "value": "priority"},
		{"type": "set_priority", "scope": "rig", "value": "boss,glass,spitter,shrieker,brood,mite,-boulder,rival:weakest"},
		{"type": "set_weapon_target", "scope": "cannon", "value": "priority"},
		{"type": "set_priority", "scope": "cannon", "value": "boss,boulder,brood,spitter,shrieker,glass,-mite,-rival:strongest"},
	]:
		w.apply_command(me.peer_id, cmd)
	return w


# ================================================================ PvP control zones

## Zone centres and rig anchors around the arena centre: [zone A, B, C], then per LAN_NIGHT rig its anchor
## (DUNE RAT has two: waiting outside B, then inside it from ZONE_ENTER_TICK).
const ZONE_SPOTS: Array = [Vector2(40, 72), Vector2(252, 6), Vector2(-262, 22)]
const ZONE_ANCHORS: Array = [Vector2(0, 0), Vector2(392, -120), Vector2(-236, 44), Vector2(-292, -4), Vector2(520, 330)]
const ZONE_RAT_IN := Vector2(222, 40)


static func _zones_world(name: String, p_seed: int) -> SimWorld:
	var c: Vector2 = SimWorld.ARENA.get_center()
	var spots: Array = []
	for a: Vector2 in ZONE_ANCHORS:
		spots.append(c + a)
	var w: SimWorld = _lan_night(p_seed, spots)
	w.round = SimWorld.PVP_START_ROUND if name == "zones_locked" else 6
	w.phase_ticks_left = w.combat_duration(w.round)
	if name == "zones_locked":
		w.pvp_grace_ticks = ZONE_GRACE_TICKS
	Zones.setup(w)
	for i in mini(w.zones.size(), ZONE_SPOTS.size()):
		w.zones[i]["pos"] = c + (ZONE_SPOTS[i] as Vector2)
	if name == "zones":
		w.zones[0]["owner"] = w.vehicles[0].id
		w.zones[1]["owner"] = w.vehicles[4].id
		w.zones[2]["owner"] = w.vehicles[2].id
		var me: SimVehicle = w.vehicles[0]
		me.round_stats["zone_points"] = 21
		me.match_stats["zone_points"] = 47
		me.zone_ticks = 21 * SimWorld.TICK_RATE
		w.vehicles[2].round_stats["zone_points"] = 9
		w.vehicles[4].round_stats["zone_points"] = 14
	for i in w.vehicles.size():
		var v: SimVehicle = w.vehicles[i]
		v.invuln_ticks = 0
		w.set_meta("anchor_%d" % i, v.pos)
	w.apply_command(1, {"type": "set_drive", "value": "zone"})
	w.apply_command(1, {"type": "set_rules", "scope": "rig", "value": "in_zone=1|target:intruders"})
	_scatter(w, 320, 0.08, 0.05, 90.0, 620.0)
	return w


## Every rig holds its anchor (turning and shooting as its AI likes), DUNE RAT rolls into zone B on cue,
## the horde is topped up, and in "zones" a capture of zone A is reported at ZONE_FLASH_TICK.
static func _zones_step(name: String, w: SimWorld) -> void:
	w.step()
	if w.tick == ZONE_ENTER_TICK:
		w.set_meta("anchor_1", SimWorld.ARENA.get_center() + ZONE_RAT_IN)
	for i in w.vehicles.size():
		var v: SimVehicle = w.vehicles[i]
		v.pos = w.get_meta("anchor_%d" % i, v.pos)
		v.vel = Vector2.ZERO
		v.hp = maxf(v.hp, v.max_hp * 0.7)
	if w.enemy_count < 260:
		_scatter(w, 40, 0.08, 0.05, 200.0, 620.0)
	if name == "zones" and w.tick == ZONE_FLASH_TICK:
		var z: Dictionary = w.zones[0]
		w.events.append({"type": "zone_captured", "pos": z["pos"], "owner": w.vehicles[0].id, "kind": 0,
			"prev": w.vehicles[4].id, "count": 1})
