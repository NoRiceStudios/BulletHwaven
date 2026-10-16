extends SceneTree
## Playtest harness driver (headless). Used by scripts/playtest.sh, see docs/architecture.md, "Dev scripts".
##
## A playtest session is a seed + config + the ordered log of the human player's commands, keyed by
## decision point (= the workshop that opens after round N). Every call replays the game from tick 0
## through tools/scenarios.gd (replay_*), so no live process is needed and results are deterministic.
##
##   godot --headless --path game -s res://tools/playtest.gd -- --op=new --dir=<dir> --seed=N
##         --mode=solo|ffa [--opponents=a,b,c] [--name=NAME] [--color=0..7]
##         [--doctrine-drive=circle] [--doctrine-target=nearest] [--fast]
##   godot --headless --path game -s res://tools/playtest.gd -- --op=advance --dir=<dir>
##         [--commands='[{"type":"pick_card","value":1},...]'] [--stay]
##
## It writes <dir>/session.json and <dir>/step_NN/{state.json,summary.txt,frames.json}. frames.json lists
## the screenshots to take; the shell script renders them with main.gd (--scenario=replay).

const KIND_NAMES: PackedStringArray = ["mite", "boulder", "spitter"]
const FX_PCT: PackedStringArray = ["speed", "turn", "scrap", "ram", "vulture", "dmg", "range", "rate", "creduce", "thorns", "luck"]
const FX_LABELS := {
	"hp": "max hp", "armor": "armor", "speed": "speed", "turn": "turn rate", "scrap": "scrap income",
	"regen": "hp/s regen", "contact": "contact dmg/tick", "ram": "ram dmg", "vulture": "dmg vs weak targets",
	"dmg": "weapon dmg", "range": "weapon range", "rate": "fire rate", "slots": "weapon slot",
	"interest": "interest cap", "creduce": "alien contact dmg ignored", "thorns": "thorns", "pierce": "pierce (all weapons)",
	"reroll": "scrap off each reroll", "luck": "rare+ card offer weight", "fuel": "fuel (once)",
}
const SAMPLE_TICKS := 300  ## hp / enemy timeline resolution (10 s)
const FRAME_FRACTIONS: Array = [0.2, 0.5, 0.85]
const FRAME_NAMES: Array = ["combat_early", "combat_mid", "combat_late"]
const SCREEN_SAFE_TICKS := 6  ## frames avoid the last ticks of a combat (the field is cleared there)

var args: Dictionary = {}

# per-tick scratch of the combat collector
var _prev_hp: PackedFloat32Array = PackedFloat32Array()
var _prev_alive: Array = []
var _prev_fuel: PackedInt32Array = PackedInt32Array()
var _prev_kills: PackedInt32Array = PackedInt32Array()
var _prev_scrap: int = 0
var _buf: PackedInt32Array = PackedInt32Array()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	var code: int = _main()
	quit(code)


func _fail(msg: String) -> int:
	printerr("PLAYTEST_ERROR " + msg)
	return 2


func _main() -> int:
	var dir: String = str(args.get("dir", ""))
	if dir == "":
		return _fail("missing --dir")
	var op: String = str(args.get("op", ""))
	var session: Dictionary = {}
	var stay: bool = false
	if op == "new":
		var mode: String = str(args.get("mode", "solo"))
		if mode != "solo" and mode != "ffa":
			return _fail("--mode must be solo or ffa")
		var opps: Array = []
		if mode == "ffa":
			var raw: String = str(args.get("opponents", ",".join(Scenarios.REPLAY_DEFAULT_OPPONENTS)))
			for p in raw.split(",", false):
				var pn: String = p.strip_edges()
				if not BotPolicy.has(pn):
					return _fail("unknown bot policy '%s' (known: %s)" % [pn, ", ".join(BotPolicy.names())])
				opps.append(pn)
			if opps.is_empty() or opps.size() > 7:
				return _fail("ffa needs 1..7 opponents")
		var color: int = int(str(args.get("color", "0")))
		if color < 0 or color >= SimVehicle.COLOR_COUNT:
			return _fail("--color must be 0..7")
		var drive: String = str(args.get("doctrine-drive", "circle"))
		var target: String = str(args.get("doctrine-target", "nearest"))
		if not drive in ["circle", "kite", "charge"]:
			return _fail("--doctrine-drive must be circle|kite|charge")
		if not target in ["nearest", "strongest", "players_first"]:
			return _fail("--doctrine-target must be nearest|strongest|players_first")
		if FileAccess.file_exists(dir.path_join("session.json")):
			return _fail("%s already holds a session (pick another directory)" % dir)
		session = {
			"version": 1, "seed": int(str(args.get("seed", "1"))), "mode": mode,
			"name": SimVehicle.sanitize_name(str(args.get("name", "DRIVER"))), "color": color,
			"opponents": opps, "fast": args.has("fast"),
			"doctrine": {"drive": drive, "target": target},
			"decisions": [], "pending": [], "over": false, "code_hash": _code_hash(), "code_notes": [],
		}
	elif op == "advance":
		var loaded: Variant = _read_json(dir.path_join("session.json"))
		if not (loaded is Dictionary):
			return _fail("no valid session.json in %s" % dir)
		session = loaded
		_normalise(session)
		var hash_now: String = _code_hash()
		if str(session.get("code_hash", "")) != hash_now and not bool(session.get("over", false)):
			var note: String = "step %02d: sim/bot code changed since the session started or last advanced; earlier steps may not match this replay" % ((session["decisions"] as Array).size() + 1)
			(session["code_notes"] as Array).append(note)
			session["code_hash"] = hash_now
			printerr("PLAYTEST_WARNING " + note)
		if bool(session.get("over", false)):
			print("PLAYTEST_GAME_OVER already over; see %s" % _latest_summary_path(dir))
			return 0
		var cmds: Array = []
		if args.has("commands"):
			var parsed: Variant = JSON.parse_string(str(args["commands"]))
			if not (parsed is Array):
				return _fail("--commands must be a JSON array of command objects")
			for c: Variant in parsed:
				var err: String = _check_command(c)
				if err != "":
					return _fail(err)
				cmds.append(c)
		stay = args.has("stay")
		if stay:
			(session["pending"] as Array).append_array(cmds)
		else:
			var all: Array = (session["pending"] as Array).duplicate()
			all.append_array(cmds)
			(session["decisions"] as Array).append(all)
			session["pending"] = []
	else:
		return _fail("--op must be new or advance")

	var t0: int = Time.get_ticks_msec()
	var res: Dictionary = _play(session)
	var sim_ms: int = Time.get_ticks_msec() - t0
	var w: SimWorld = res["w"]
	var over: bool = w.phase == SimWorld.PHASE_GAME_OVER
	session["over"] = over
	var step: int = (session["decisions"] as Array).size() + 1
	var step_dir: String = dir.path_join("step_%02d" % step)
	DirAccess.make_dir_recursive_absolute(step_dir)
	var frames: Array = _frames(res, step_dir, stay, over)
	var state: Dictionary = _state(session, res, step, over)
	state["frames"] = frames
	state["sim_replay_ms"] = sim_ms
	_write(step_dir.path_join("state.json"), JSON.stringify(state, "  "))
	_write(step_dir.path_join("summary.txt"), _summary(session, res, state, step, over, stay))
	_write(step_dir.path_join("frames.json"), JSON.stringify({"session": dir, "frames": frames}))
	_write(dir.path_join("session.json"), JSON.stringify(session, "  "))
	print("PLAYTEST_OK step=%d dir=%s over=%d sim_ms=%d ticks=%d" % [step, step_dir, 1 if over else 0, sim_ms, w.tick])
	return 0


# ======================================================================== helpers (io, validation)

## Fingerprint of the sim and bot code: a session only replays identically against the same code.
static func _code_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var files: PackedStringArray = []
	for d in ["res://sim", "res://tools"]:
		var da: DirAccess = DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			if f.ends_with(".gd") and (d == "res://sim" or f == "bots.gd" or f == "scenarios.gd"):
				files.append(d.path_join(f))
	files.sort()
	for f in files:
		ctx.update((f + FileAccess.get_file_as_string(f)).to_utf8_buffer())
	return ctx.finish().hex_encode().left(12)


static func _read_json(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return
	f.store_string(text)
	f.close()


## JSON gives floats; make seeds / colours ints again.
static func _normalise(session: Dictionary) -> void:
	session["seed"] = int(session.get("seed", 1))
	session["color"] = int(session.get("color", 0))
	if not session.has("decisions"):
		session["decisions"] = []
	if not session.has("pending"):
		session["pending"] = []
	if not session.has("code_notes"):
		session["code_notes"] = []


static func _check_command(c: Variant) -> String:
	if not (c is Dictionary):
		return "each command must be a JSON object, got %s" % str(c)
	var d: Dictionary = c
	var t: String = str(d.get("type", ""))
	if not t in Scenarios.REPLAY_COMMANDS:
		return "unknown command type '%s' (valid: %s)" % [t, ", ".join(Scenarios.REPLAY_COMMANDS)]
	if t == "pick_card" and not (d.get("value") is float or d.get("value") is int):
		return "pick_card needs a numeric value 0..2"
	if t == "buy_tech" and not Tech.has(str(d.get("value", ""))):
		return "buy_tech needs a known tech id, got '%s'" % str(d.get("value", ""))
	if t == "respec_tech" and NetSession.validate_command(d).is_empty():
		return "respec_tech needs known tech ids in \"from\" (owned choice) and \"value\" (unowned choice of the same branch and stage)"
	if t == "set_drive" and not str(d.get("value", "")) in ["circle", "kite", "charge"]:
		return "set_drive value must be circle|kite|charge"
	if t == "set_target" and not str(d.get("value", "")) in Doctrine.RIG_TARGETS:
		return "set_target value must be %s" % "|".join(Doctrine.RIG_TARGETS)
	if (t == "set_rules" or t == "set_weapon_target") and NetSession.validate_command(d).is_empty():
		return "%s needs a scope (rig or a weapon kind) and a valid value (rules like \"hp<30|drive:flee\", see sim/doctrine.gd)" % t
	return ""


static func _step_dirs(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var da: DirAccess = DirAccess.open(dir)
	if da != null:
		for d in da.get_directories():
			if d.begins_with("step_"):
				out.append(d)
	out.sort()
	return out


static func _latest_summary_path(dir: String) -> String:
	var s: PackedStringArray = _step_dirs(dir)
	return dir.path_join(s[s.size() - 1] if s.size() > 0 else "step_01").path_join("summary.txt")


# ======================================================================== replay + collector

## Replays the session to its decision point (or game over) and collects the stats of the last combat.
func _play(session: Dictionary) -> Dictionary:
	var run: Dictionary = Scenarios.replay_new(session)
	var w: SimWorld = run["w"]
	var target: int = int(run["target"])
	var st: Dictionary = {}
	var seen: Dictionary = {}  # enemy kind -> [round, tick] first seen
	var elim: Dictionary = {}  # vehicle id -> [round, tick]
	var guard: int = 0
	while not Scenarios.replay_done(run):
		guard += 1
		if guard > 3000000:
			break
		var collecting: bool = w.phase == SimWorld.PHASE_COMBAT and w.round == target
		if collecting:
			if st.is_empty():
				_init_stats(st, w)
			_pre(w)
		Scenarios.replay_advance(run)
		if collecting:
			_post(st, w)
		if w.tick % 30 == 0 and w.phase == SimWorld.PHASE_COMBAT:
			for k in [SimWorld.BOULDER, SimWorld.SPITTER]:
				if not seen.has(k) and w.enemy_kind.has(k):
					seen[k] = [w.round, w.tick]
		for v in w.vehicles:
			if v.eliminated and not elim.has(v.id):
				elim[v.id] = [w.round, w.tick]
	return {"w": w, "run": run, "st": st, "seen": seen, "elim": elim, "target": target}


func _init_stats(st: Dictionary, w: SimWorld) -> void:
	var me: SimVehicle = w.vehicles[0]
	st["round"] = w.round
	st["t0"] = w.tick
	st["t1"] = w.tick
	st["scrap0"] = me.scrap
	st["kills0"] = me.kills
	st["fuel0"] = me.fuel
	st["hp0"] = me.hp
	st["max_hp"] = me.max_hp
	st["kills"] = {}
	st["pvp_kills"] = []
	st["deaths"] = []
	st["respawns"] = 0
	st["dmg"] = {}
	st["dmg_total"] = 0.0
	st["hits_dealt"] = 0
	st["hits_taken"] = 0
	st["enemy_peak"] = 0
	st["enemy_peak_tick"] = w.tick
	st["spits"] = 0
	st["min_hp_frac"] = 1.0
	st["min_hp_tick"] = w.tick
	st["hp_series"] = []
	st["enemy_series"] = []
	st["alive_ticks"] = PackedInt32Array()
	st["opp_deaths"] = {}
	st["interest"] = 0
	st["scrap_pre_interest"] = me.scrap
	st["kinds_seen"] = {}
	st["ended_by"] = ""
	st["spectating"] = me.eliminated


func _pre(w: SimWorld) -> void:
	var n: int = w.vehicles.size()
	_prev_hp.resize(n)
	_prev_fuel.resize(n)
	_prev_kills.resize(n)
	_prev_alive.resize(n)
	for i in n:
		var v: SimVehicle = w.vehicles[i]
		_prev_hp[i] = v.hp
		_prev_fuel[i] = v.fuel
		_prev_kills[i] = v.kills
		_prev_alive[i] = v.alive
	_prev_scrap = w.vehicles[0].scrap


func _post(st: Dictionary, w: SimWorld) -> void:
	var me: SimVehicle = w.vehicles[0]
	var t_s: float = float(w.tick - int(st["t0"])) / float(SimWorld.TICK_RATE)
	var flipped: bool = w.phase == SimWorld.PHASE_WORKSHOP
	st["t1"] = w.tick
	var hits_veh: Array = []
	var own_alien_kills: int = 0
	var destroyed: Array = []
	var kills: Dictionary = st["kills"]
	for e: Dictionary in w.events:
		match str(e["type"]):
			"kill":
				if int(e["owner"]) == 0:
					var kn: String = _kind_name(int(e["kind"]))
					kills[kn] = int(kills.get(kn, 0)) + 1
					own_alien_kills += 1
			"hit":
				if int(e["kind"]) == -1:
					hits_veh.append(e)
					if int(e["owner"]) == 0:
						st["hits_dealt"] = int(st["hits_dealt"]) + 1
			"spit":
				st["spits"] = int(st["spits"]) + 1
			"vehicle_destroyed":
				destroyed.append(int(e["owner"]))
			"respawn":
				if int(e["owner"]) == 0:
					st["respawns"] = int(st["respawns"]) + 1

	for e2: Dictionary in hits_veh:
		var ow: int = int(e2["owner"])
		if ow > 0 and (e2["pos"] as Vector2).distance_to(me.pos) <= SimVehicle.RADIUS + 14.0:
			st["hits_taken"] = int(st["hits_taken"]) + 1

	# damage the human rig took this tick, split by (approximate) source
	var top_cause: String = "unknown"
	if _prev_alive[0]:
		var d: float = _prev_hp[0] - me.hp
		if d > 0.01 and not flipped:
			var weights: Dictionary = _damage_weights(w, me, hits_veh)
			var total_w: float = 0.0
			for k: String in weights:
				total_w += float(weights[k])
			if total_w <= 0.0:
				weights = {"other": 1.0}
				total_w = 1.0
			var best: float = -1.0
			var dmg: Dictionary = st["dmg"]
			for k2: String in weights:
				var share: float = d * float(weights[k2]) / total_w
				dmg[k2] = float(dmg.get(k2, 0.0)) + share
				if float(weights[k2]) > best:
					best = float(weights[k2])
					top_cause = k2
			st["dmg_total"] = float(st["dmg_total"]) + d
	if me.alive:
		(st["alive_ticks"] as PackedInt32Array).append(w.tick)
		var frac: float = me.hp / maxf(me.max_hp, 1.0)
		if frac < float(st["min_hp_frac"]):
			st["min_hp_frac"] = frac
			st["min_hp_tick"] = w.tick
	# destroyed vehicles (tick of the destroy event; fuel already updated)
	for vid in destroyed:
		var vv: SimVehicle = w.vehicles[vid]
		var cause: String = top_cause
		if vid != 0:
			cause = _top_key(_damage_weights(w, vv, hits_veh))
		var by_pvp: bool = cause.begins_with("shots from") or cause.begins_with("ram by") or _prev_fuel[vid] - vv.fuel >= SimWorld.FUEL_LOSS_PVP
		if vid == 0:
			(st["deaths"] as Array).append({"t": snappedf(t_s, 0.1), "cause": cause, "pvp": by_pvp,
				"fuel_before": _prev_fuel[0], "fuel_after": me.fuel, "eliminated": me.eliminated})
		else:
			var od: Dictionary = st["opp_deaths"]
			if not od.has(vid):
				od[vid] = []
			(od[vid] as Array).append({"t": snappedf(t_s, 0.1), "cause": cause, "fuel_after": vv.fuel, "pvp": by_pvp, "eliminated": vv.eliminated})
	# player kills (bounties)
	var pk: int = me.kills - _prev_kills[0] - own_alien_kills
	if pk > 0:
		for vid2 in destroyed:
			if vid2 != 0:
				(st["pvp_kills"] as Array).append({"t": snappedf(t_s, 0.1), "victim": w.vehicles[vid2].player_name})

	# enemies
	if w.enemy_count > int(st["enemy_peak"]):
		st["enemy_peak"] = w.enemy_count
		st["enemy_peak_tick"] = w.tick
	var rel: int = w.tick - int(st["t0"])
	if rel % SAMPLE_TICKS == 0:
		(st["hp_series"] as Array).append([int(rel / SimWorld.TICK_RATE), roundi(100.0 * me.hp / maxf(me.max_hp, 1.0)) if me.alive else 0])
		(st["enemy_series"] as Array).append([int(rel / SimWorld.TICK_RATE), w.enemy_count])
		var ks: Dictionary = st["kinds_seen"]
		for k3 in [SimWorld.MITE, SimWorld.BOULDER, SimWorld.SPITTER]:
			if not ks.has(k3) and w.enemy_kind.has(k3):
				ks[k3] = rel
	if flipped:
		# the final step also paid interest: solve interest = min((scrap_after - interest) / PER, cap)
		var cap: int = w.interest_cap_for(me)
		var interest: int = 0
		for i in range(0, cap + 1):
			if mini((me.scrap - i) / SimWorld.INTEREST_PER, cap) == i and not me.eliminated:
				interest = i
		st["interest"] = interest
		st["scrap_pre_interest"] = me.scrap - interest
		st["ended_by"] = "timer"
	else:
		st["scrap_pre_interest"] = me.scrap
		if w.phase == SimWorld.PHASE_GAME_OVER:
			st["ended_by"] = "game over"


## Relative weights of the damage sources hurting vehicle `me` this tick (contact enemies by kind, acid, rival shots, rams).
func _damage_weights(w: SimWorld, me: SimVehicle, hits_veh: Array) -> Dictionary:
	var out: Dictionary = {}
	var mult: float = SimWorld.enemy_damage_mult(w.round)
	_buf.resize(maxi(_buf.size(), 256))
	var n: int = w.query_enemies(me.pos, SimVehicle.RADIUS + SimWorld.MAX_ENEMY_RADIUS + 4.0, _buf)
	for q in n:
		var j: int = _buf[q]
		var kind: int = w.enemy_kind[j]
		if w.enemy_pos[j].distance_to(me.pos) <= SimVehicle.RADIUS + SimWorld.ENEMY_RADIUS[kind] + 2.0:
			var key: String = "%s contact" % _kind_name(kind)
			out[key] = float(out.get(key, 0.0)) + SimWorld.ENEMY_CONTACT_DAMAGE[kind] * mult
	for e: Dictionary in hits_veh:
		var pos: Vector2 = e["pos"]
		if pos.distance_to(me.pos) > SimVehicle.RADIUS + 14.0:
			continue
		var owner: int = int(e["owner"])
		if owner < 0:
			out["acid"] = float(out.get("acid", 0.0)) + SimWorld.SPIT_DAMAGE * mult
		elif owner != me.id and owner < w.vehicles.size():
			var key2: String = "shots from %s" % w.vehicles[owner].player_name
			var ov: SimVehicle = w.vehicles[owner]
			var avg: float = 4.0
			if not ov.weapons.is_empty():
				avg = 0.0
				for wp in ov.weapons:
					avg += float(wp["damage"])
				avg /= float(ov.weapons.size())
			out[key2] = float(out.get(key2, 0.0)) + avg
	for o in w.vehicles:
		if o.id != me.id and o.alive and o.ram_damage > 0.0 and o.pos.distance_to(me.pos) < 2.0 * SimVehicle.RADIUS + 6.0:
			var key3: String = "ram by %s" % o.player_name
			out[key3] = float(out.get(key3, 0.0)) + o.ram_damage
	return out


static func _top_key(weights: Dictionary) -> String:
	var best: String = "unknown"
	var bw: float = 0.0
	for k: String in weights:
		if float(weights[k]) > bw:
			bw = float(weights[k])
			best = k
	return best


static func _kind_name(k: int) -> String:
	return KIND_NAMES[k] if k >= 0 and k < KIND_NAMES.size() else "kind%d" % k


# ======================================================================== frames

func _frames(res: Dictionary, step_dir: String, stay: bool, over: bool) -> Array:
	var w: SimWorld = res["w"]
	var st: Dictionary = res["st"]
	var out: Array = []
	var combat_done: bool = true
	for nm: String in FRAME_NAMES:
		if not FileAccess.file_exists(step_dir.path_join(nm + ".png")):
			combat_done = false
	var skip_combat: bool = stay and combat_done
	if not st.is_empty():
		var t0: int = int(st["t0"])
		var t1: int = int(st["t1"]) - SCREEN_SAFE_TICKS
		var alive: PackedInt32Array = st["alive_ticks"]
		for i in FRAME_NAMES.size():
			var want: int = t0 + roundi(float(FRAME_FRACTIONS[i]) * float(t1 - t0))
			var best: int = want
			var best_d: int = 1 << 30
			for t in alive:
				if t > t1 or t <= t0:
					continue
				var dd: int = absi(t - want)
				if dd < best_d:
					best_d = dd
					best = t
			out.append({"name": FRAME_NAMES[i], "tick": best, "png": step_dir.path_join(FRAME_NAMES[i] + ".png"),
				"render": not skip_combat})
	var end_name: String = "gameover" if over else "workshop"
	out.append({"name": end_name, "tick": w.tick, "png": step_dir.path_join(end_name + ".png"), "render": true,
		"game_over": over})
	return out


# ======================================================================== state.json

func _state(session: Dictionary, res: Dictionary, step: int, over: bool) -> Dictionary:
	var w: SimWorld = res["w"]
	var me: SimVehicle = w.vehicles[0]
	var run: Dictionary = res["run"]
	var st: Dictionary = res["st"]
	var s: Dictionary = {
		"step": step, "seed": int(session["seed"]), "mode": session["mode"], "round": w.round,
		"phase": ["combat", "workshop", "game_over"][w.phase], "tick": w.tick,
		"game_over": over, "winner": _winner_name(w) if over else "",
		"workshop_seconds_left": snappedf(float(w.phase_ticks_left) / 30.0, 0.1) if w.phase == SimWorld.PHASE_WORKSHOP else 0.0,
		"pvp_enabled": w.pvp_enabled(),
	}
	s["you"] = _vehicle_dict(w, me, true)
	var opps: Array = []
	for i in range(1, w.vehicles.size()):
		opps.append(_vehicle_dict(w, w.vehicles[i], false))
	s["opponents"] = opps
	# offers
	var offers: Array = []
	for i in me.offers.size():
		offers.append(_offer_dict(me, i, me.offers[i]))
	s["offers"] = offers
	s["picked_this_workshop"] = me.picked
	s["reroll_cost"] = me.reroll_cost
	s["tech"] = _tech_list(me)
	s["orders_applied"] = _orders(run, session, w)
	s["last_combat"] = _combat_dict(res, w) if not st.is_empty() else {}
	if over:
		s["standings"] = _standings(w, res["elim"])
	s["pending_orders_recorded"] = (session["pending"] as Array).size()
	return s


func _winner_name(w: SimWorld) -> String:
	if w.winner_peer < 0:
		return ""
	var v: SimVehicle = w.get_vehicle_for_peer(w.winner_peer)
	return v.player_name if v != null else ""


func _vehicle_dict(w: SimWorld, v: SimVehicle, full: bool) -> Dictionary:
	var d: Dictionary = {
		"name": v.player_name, "color_index": v.color_index, "hp": roundi(v.hp), "max_hp": roundi(v.max_hp),
		"fuel": v.fuel, "kills": v.kills, "alive": v.alive, "eliminated": v.eliminated,
		"weapons": _weapon_list(v), "doctrine": v.doctrine.duplicate(), "rules": Doctrine.fingerprint(v),
	}
	if "leader_peer" in w:
		d["is_leader"] = int(w.get("leader_peer")) == v.peer_id
	if full:
		d["scrap"] = v.scrap
		d["cards"] = v.cards.duplicate()
		d["tech_owned"] = v.tech.duplicate()
		d["armor"] = snappedf(v.armor, 0.01)
		d["speed_mult"] = snappedf(v.speed, 0.01)
		d["turn_mult"] = snappedf(v.turn_rate, 0.01)
		d["scrap_mult"] = snappedf(v.scrap_mult, 0.01)
		d["regen"] = snappedf(v.regen, 0.01)
		d["weapon_slots"] = v.weapon_slots
		d["interest_cap"] = w.interest_cap_for(v)
		d["invulnerable"] = v.invuln_ticks > 0
		d["ready"] = v.ready
	return d


static func _weapon_list(v: SimVehicle) -> Array:
	var out: Array = []
	for wp in v.weapons:
		out.append({"kind": wp["kind"], "level": int(v.cards.get(wp["kind"], 1)), "damage": snappedf(float(wp["damage"]), 0.1),
			"pellets": int(wp.get("pellets", 1)), "shots_per_s": snappedf(30.0 / maxf(float(wp["cooldown_ticks"]), 1.0), 0.1),
			"range": roundi(float(wp["range"])), "pierce": int(wp.get("pierce", 0)), "splash": roundi(float(wp.get("splash", 0.0)))})
	return out


func _offer_dict(me: SimVehicle, index: int, id: String) -> Dictionary:
	var d: Dictionary = Cards.def(id)
	var lvl: int = int(me.cards.get(id, 0))
	return {"index": index, "id": id, "name": d.get("name", id), "category": d.get("category", "?"),
		"rarity": d.get("rarity", "?"), "owned_level": lvl, "becomes_level": lvl + 1, "effect": _card_effect(id, lvl + 1)}


static func _card_effect(id: String, level: int) -> String:
	if Cards.WEAPONS.has(id):
		var b: Dictionary = Cards.WEAPONS[id]
		var li: int = clampi(level, 1, 3) - 1
		var s: String = "%s L%d: dmg %s" % [id, level, _num(float((b["damage"] as Array)[li]))]
		var pel: int = int((b["pellets"] as Array)[li])
		if pel > 1:
			s += " x%d pellets" % pel
		s += ", %s shots/s, range %d" % [_num(30.0 / float((b["cooldown"] as Array)[li])), roundi(float((b["range"] as Array)[li]))]
		var pierce: int = int((b["pierce"] as Array)[li])
		if pierce > 0:
			s += ", pierce %d" % pierce
		var splash: float = float((b["splash"] as Array)[li])
		if splash > 0.0:
			s += ", splash %d" % roundi(splash)
		return s + " (before tech)"
	if Cards.is_evolution(id):
		return str(Cards.def(id).get("text", ""))
	return _fx_text(Cards.def(id).get("fx", {}), true)


static func _fx_text(fx: Dictionary, per_level: bool) -> String:
	var parts: PackedStringArray = []
	for k: String in fx:
		var amt: float = float(fx[k])
		var base: String = k.get_slice("_", 0)
		var kind: String = k.get_slice("_", 1)  # per-weapon keys: dmg_mg, pellets_shotgun, ...
		var pct: bool = k in FX_PCT or (kind != "" and base in ["dmg", "rate", "range"])
		var shown: String = ("%+d%%" % roundi(amt * 100.0)) if pct else ("+" if amt >= 0.0 else "") + _num(amt)
		var label: String = FX_LABELS.get(k, "%s %s" % [kind, base] if kind != "" else k)
		parts.append("%s %s" % [shown, label])
	return ", ".join(parts) + (" per level" if per_level else "")


static func _num(x: float) -> String:
	if absf(x - roundf(x)) < 0.05:
		return str(roundi(x))
	return "%.1f" % x


func _tech_list(me: SimVehicle) -> Array:
	var out: Array = []
	for i in Tech.count():
		var id: String = Tech.id_at(i)
		var d: Dictionary = Tech.def(id)
		var status: String
		if me.tech.has(id):
			status = "owned" if Tech.active(me, id) else "owned but inactive (needs %s)" % Tech.missing(me, id)
		elif Tech.blocked_by(me, id) != "":
			status = "excluded (took %s; respec_tech swaps)" % Tech.blocked_by(me, id)
		elif Tech.missing(me, id) != "":
			status = "locked (needs %s)" % Tech.missing(me, id)
		else:
			status = "affordable" if me.scrap >= Tech.price(me, id) else "need %d more scrap" % (Tech.price(me, id) - me.scrap)
			if me.tech_dormant.has(id):
				status += " (dormant fusion, half price)"
		out.append({"id": id, "name": d["name"], "branch": d["branch"], "tier": d["tier"], "kind": d["kind"],
			"cost": Tech.price(me, id), "status": status, "effect": _fx_text(d["fx"], false)})
	return out


func _orders(run: Dictionary, session: Dictionary, w: SimWorld) -> Dictionary:
	# what happened to the commands applied at the previous workshop and (stay mode) at this one
	var log: Dictionary = run["cmd_log"]
	var out: Dictionary = {}
	for r in log:
		if int(r) == w.round or int(r) == w.round - 1:
			out[str(r)] = log[r]
	return out


func _combat_dict(res: Dictionary, w: SimWorld) -> Dictionary:
	var st: Dictionary = res["st"]
	var t0: int = int(st["t0"])
	var secs: float = float(int(st["t1"]) - t0) / float(SimWorld.TICK_RATE)
	var me: SimVehicle = w.vehicles[0]
	var kills: Dictionary = st["kills"]
	var kill_total: int = 0
	for k: String in kills:
		kill_total += int(kills[k])
	var dmg: Dictionary = {}
	for k2: String in st["dmg"]:
		dmg[k2] = snappedf(float(st["dmg"][k2]), 0.1)
	var seen: Dictionary = res["seen"]
	var firsts: Array = []
	for kk: Variant in seen:
		var rr: Array = seen[kk]
		if int(rr[0]) == int(st["round"]):
			firsts.append({"kind": _kind_name(int(kk)), "first_seen_t": snappedf(float(int(rr[1]) - t0) / 30.0, 0.1)})
	return {
		"round": st["round"], "seconds": snappedf(secs, 0.1), "ended_by": st["ended_by"],
		"alien_kills": kill_total, "kills_by_kind": kills, "pvp_kills": st["pvp_kills"],
		"kills_total_now": me.kills,
		"damage_taken": snappedf(float(st["dmg_total"]), 0.1), "damage_by_source": dmg,
		"lowest_hp_percent": roundi(100.0 * float(st["min_hp_frac"])), "lowest_hp_t": snappedf(float(int(st["min_hp_tick"]) - t0) / 30.0, 0.1),
		"hp_series": st["hp_series"], "enemy_series": st["enemy_series"],
		"enemy_peak": st["enemy_peak"], "enemy_peak_t": snappedf(float(int(st["enemy_peak_tick"]) - t0) / 30.0, 0.1),
		"spitter_shots_fired": st["spits"],
		"sim_stats": _sim_stats(w, me),
		"deaths": st["deaths"], "respawns": st["respawns"],
		"fuel_start": st["fuel0"], "fuel_end": me.fuel,
		"scrap_start": st["scrap0"], "scrap_earned": int(st["scrap_pre_interest"]) - int(st["scrap0"]),
		"interest": st["interest"], "scrap_end": me.scrap,
		"pvp_hits_dealt": st["hits_dealt"], "pvp_hits_taken": st["hits_taken"],
		"new_threats": firsts,
		"opponent_deaths": _opp_deaths(w, st), "spectating": st["spectating"],
	}


## The sim's own exact round and match stats of the human rig (`round_stats` / `match_stats`), JSON friendly.
func _sim_stats(w: SimWorld, me: SimVehicle) -> Dictionary:
	var rs: Dictionary = me.round_stats.duplicate(true)
	var tp: Dictionary = {}
	for pid: Variant in (rs["taken_players"] as Dictionary):
		var nm: String = w.vehicles[int(pid)].player_name if int(pid) < w.vehicles.size() else str(pid)
		tp[nm] = snappedf(float((rs["taken_players"] as Dictionary)[pid]), 0.1)
	rs["taken_players"] = tp
	for k: String in rs["taken"]:
		rs["taken"][k] = snappedf(float(rs["taken"][k]), 0.1)
	rs["dealt"] = snappedf(float(rs["dealt"]), 0.1)
	rs["dealt_players"] = snappedf(float(rs["dealt_players"]), 0.1)
	for d: Dictionary in rs["deaths"]:
		d["t"] = snappedf(float(d["t"]) / 30.0, 0.1)
		d["killer_name"] = w.vehicles[int(d["killer"])].player_name if int(d["killer"]) >= 0 else ""
	var ms: Dictionary = me.match_stats.duplicate(true)
	ms["dmg_dealt"] = snappedf(float(ms["dmg_dealt"]), 0.1)
	ms["top_victim_name"] = w.vehicles[int(ms["top_victim"])].player_name if int(ms["top_victim"]) >= 0 else ""
	ms["nemesis_name"] = w.vehicles[int(ms["nemesis"])].player_name if int(ms["nemesis"]) >= 0 else ""
	return {"round_stats": rs, "match_stats": ms, "fuel_drain_per_round": w.fuel_drain, "underdog": w.is_underdog(me),
		"pvp_grace_ticks": w.pvp_grace_ticks}


func _opp_deaths(w: SimWorld, st: Dictionary) -> Array:
	var out: Array = []
	var od: Dictionary = st["opp_deaths"]
	for vid: Variant in od:
		for d: Dictionary in od[vid]:
			var e: Dictionary = d.duplicate()
			e["name"] = w.vehicles[int(vid)].player_name
			out.append(e)
	return out


func _standings(w: SimWorld, elim: Dictionary) -> Array:
	var survivors: Array = []
	var gone: Array = []
	for v in w.vehicles:
		if v.eliminated:
			gone.append(v)
		else:
			survivors.append(v)
	survivors.sort_custom(func(a: SimVehicle, b: SimVehicle) -> bool:
		if a.fuel != b.fuel:
			return a.fuel > b.fuel
		return a.kills > b.kills)
	gone.sort_custom(func(a: SimVehicle, b: SimVehicle) -> bool:
		var ea: Array = elim.get(a.id, [0, 0])
		var eb: Array = elim.get(b.id, [0, 0])
		if ea[1] != eb[1]:
			return int(ea[1]) > int(eb[1])
		return a.id < b.id)
	var out: Array = []
	var place: int = 1
	for v: SimVehicle in survivors + gone:
		var e: Array = elim.get(v.id, [])
		out.append({"place": place, "name": v.player_name, "you": v.id == 0, "kills": v.kills, "fuel": v.fuel,
			"eliminated_round": int(e[0]) if not e.is_empty() else 0})
		place += 1
	return out


# ======================================================================== summary.txt

func _summary(session: Dictionary, res: Dictionary, state: Dictionary, step: int, over: bool, stay: bool) -> String:
	var w: SimWorld = res["w"]
	var me: SimVehicle = w.vehicles[0]
	var L: PackedStringArray = []
	var you: Dictionary = state["you"]
	var head: String = "BULLETHWAVEN PLAYTEST  step %02d  seed %d  %s" % [step, int(session["seed"]), str(session["mode"]).to_upper()]
	L.append(head)
	var notes: Array = session.get("code_notes", [])
	if not notes.is_empty() and str(notes[-1]).begins_with("step %02d:" % step):
		L.append("WARNING: " + str(notes[-1]))
	if over:
		L.append("GAME OVER in round %d (tick %d)  %s" % [w.round, w.tick, _over_line(w, state)])
	else:
		L.append("DECISION POINT %d: workshop after round %d, next is round %d. %.0f s on the clock (replay stops when it opens). PvP %s." % [
			step, w.round, w.round + 1, float(state["workshop_seconds_left"]),
			"ON" if bool(state["pvp_enabled"]) else "off until round %d (plus a %d s grace at its start)" % [SimWorld.PVP_START_ROUND, SimWorld.PVP_GRACE_TICKS / SimWorld.TICK_RATE]])
	var flags: String = ""
	if bool(you.get("is_leader", false)):
		flags += "  [LEADER: bounty on you]"
	L.append("YOU %s (colour %d): hp %d/%d  fuel %d  scrap %d  kills %d%s" % [me.player_name, me.color_index, you["hp"], you["max_hp"], me.fuel, me.scrap, me.kills, flags])
	L.append("DOCTRINE: drive=%s target=%s" % [me.doctrine["drive"], me.doctrine["target"]])
	if Doctrine.fingerprint(me) != "":
		L.append("RULES (%d slots per list): %s" % [Doctrine.slots(me), Doctrine.fingerprint(me)])
	var cards: PackedStringArray = []
	for id: String in me.cards:
		cards.append("%s L%d [%s]" % [Cards.def(id).get("name", id), int(me.cards[id]), Cards.def(id).get("category", "?")])
	L.append("CARDS: " + ", ".join(cards))
	var wl: PackedStringArray = []
	for wp: Dictionary in you["weapons"]:
		var px: String = (" x%d" % int(wp["pellets"])) if int(wp["pellets"]) > 1 else ""
		wl.append("%s L%d dmg %s%s %s/s rng %d" % [wp["kind"], wp["level"], _num(float(wp["damage"])), px, _num(float(wp["shots_per_s"])), wp["range"]])
	L.append("WEAPONS (%d/%d slots): %s" % [wl.size(), me.weapon_slots, "; ".join(wl)])
	var stats: PackedStringArray = []
	if me.armor > 0.0:
		stats.append("armor %s" % _num(me.armor))
	if absf(me.speed - 1.0) > 0.005:
		stats.append("speed x%.2f" % me.speed)
	if absf(me.turn_rate - 1.0) > 0.005:
		stats.append("turn x%.2f" % me.turn_rate)
	if absf(me.scrap_mult - 1.0) > 0.005:
		stats.append("scrap x%.2f" % me.scrap_mult)
	if me.regen > 0.0:
		stats.append("regen %s hp/s" % _num(me.regen))
	stats.append("interest 10%% of held scrap, capped at %d now (+%d per round)" % [w.interest_cap_for(me), SimWorld.INTEREST_CAP_PER_ROUND])
	if w.fuel_drain > 0:
		stats.append("FUEL DRAIN %d per round (only rig kills refuel you)" % w.fuel_drain)
	L.append("STATS: " + ", ".join(stats))
	L.append("TECH OWNED: " + (", ".join(me.tech) if not me.tech.is_empty() else "none"))

	if not over:
		L.append("")
		if me.eliminated:
			L.append("YOU ARE ELIMINATED: spectating, nothing to decide (advance with no commands).")
		else:
			if me.picked:
				L.append("OFFERS: card already picked this workshop.")
			else:
				L.append("OFFERS (command {\"type\":\"pick_card\",\"value\":i}); reroll costs %d scrap (have %d), +1 each reroll:" % [me.reroll_cost, me.scrap])
				for o: Dictionary in state["offers"]:
					var tag: String = "NEW" if int(o["owned_level"]) == 0 else "L%d->L%d" % [o["owned_level"], o["becomes_level"]]
					L.append("  [%d] %s (%s, %s) %s: %s" % [o["index"], o["name"], o["category"], o["rarity"], tag, o["effect"]])
			L.append("TECH (command {\"type\":\"buy_tech\",\"value\":id}); buyable now (spec nodes of one fork exclude each other; locked and excluded nodes hidden):")
			for t: Dictionary in state["tech"]:
				if t["status"] == "owned" or str(t["status"]).begins_with("locked") or str(t["status"]).begins_with("excluded"):
					continue
				L.append("  %s \"%s\" cost %d: %s  [%s]" % [t["id"], t["name"], t["cost"], t["effect"], t["status"]])
			L.append("(ready is optional: the next round starts when the timer ends anyway. Doctrine: set_drive circle|kite|charge, set_target nearest|strongest|weakest|players_first|boulders|spitters, set_rules {scope: rig|<gun>, value: \"hp<30|drive:flee;...\"}, set_weapon_target {scope: <gun>, value: follow|nearest|...}.)")

	var orders: Dictionary = state["orders_applied"]
	if not orders.is_empty():
		L.append("")
		var keys: Array = orders.keys()
		keys.sort()
		for k: String in keys:
			var lines: Array = orders[k]
			if lines.is_empty():
				continue
			L.append("ORDERS at workshop %s:%s" % [k, " (this workshop, applied)" if int(k) == w.round and not over else ""])
			for ln: String in lines:
				L.append("  " + ln)

	if w.vehicles.size() > 1:
		L.append("")
		L.append("OPPONENTS:")
		for o2: Dictionary in state["opponents"]:
			var ws: PackedStringArray = []
			for wp2: Dictionary in o2["weapons"]:
				ws.append("%s L%d" % [wp2["kind"], wp2["level"]])
			var stt: String = "ELIMINATED" if o2["eliminated"] else ("hp %d/%d" % [o2["hp"], o2["max_hp"]] if o2["alive"] else "wrecked")
			L.append("  %s: %s, fuel %d, kills %d, %s%s" % [o2["name"], stt, o2["fuel"], o2["kills"], ", ".join(ws),
				"  [LEADER]" if bool(o2.get("is_leader", false)) else ""])

	if over:
		L.append("")
		L.append("FINAL STANDINGS:")
		for e: Dictionary in state["standings"]:
			L.append("  %d. %s%s  kills %d, fuel %d%s" % [e["place"], e["name"], " (you)" if e["you"] else "", e["kills"], e["fuel"],
				", eliminated in round %d" % int(e["eliminated_round"]) if int(e["eliminated_round"]) > 0 else ", survived"])

	var lc: Dictionary = state["last_combat"]
	if not lc.is_empty():
		L.append("")
		L.append_array(_combat_lines(lc, w, stay))

	var shots: PackedStringArray = []
	for f: Dictionary in state["frames"]:
		shots.append("%s (tick %d)" % [f["name"], int(f["tick"])])
	L.append("")
	L.append("SCREENSHOTS in step_%02d/: %s (+ _1080p variants)" % [step, ", ".join(shots)])
	return "\n".join(L) + "\n"


func _over_line(w: SimWorld, state: Dictionary) -> String:
	if str(state["mode"]) == "solo":
		return "YOUR CONVOY IS LOST."
	if w.winner_peer == 1:
		return "YOU WIN: last rig standing."
	var wn: String = str(state["winner"])
	return ("%s wins." % wn) if wn != "" else "nobody survives."


func _combat_lines(lc: Dictionary, w: SimWorld, stay: bool) -> PackedStringArray:
	var L: PackedStringArray = []
	L.append("LAST COMBAT (round %d, %.0f s, ended by %s):" % [lc["round"], lc["seconds"], lc["ended_by"]])
	if bool(lc["spectating"]):
		L.append("  you were eliminated, spectating. aliens peak %d at %.0fs" % [lc["enemy_peak"], lc["enemy_peak_t"]])
		_rival_lines(L, lc, w)
		return L
	var kb: PackedStringArray = []
	for k: String in lc["kills_by_kind"]:
		kb.append("%s %d" % [k, lc["kills_by_kind"][k]])
	var pk: Array = lc["pvp_kills"]
	var pks: String = ""
	if not pk.is_empty():
		var vs: PackedStringArray = []
		for p: Dictionary in pk:
			vs.append("%s at %.0fs" % [p["victim"], p["t"]])
		pks = "; DESTROYED RIVALS: " + ", ".join(vs)
	L.append("  kills: %d aliens (%s)%s" % [lc["alien_kills"], ", ".join(kb) if not kb.is_empty() else "none", pks])
	var srcs: Dictionary = lc["damage_by_source"]
	var parts: Array = []
	for k2: String in srcs:
		parts.append([k2, float(srcs[k2])])
	parts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var ds: PackedStringArray = []
	for p2: Array in parts:
		ds.append("%s %s" % [p2[0], _num(float(p2[1]))])
	L.append("  damage taken: %s hp (approx. split: %s)" % [_num(float(lc["damage_taken"])), ", ".join(ds) if not ds.is_empty() else "none"])
	L.append_array(_sim_stat_lines(lc["sim_stats"], w))
	var hp: PackedStringArray = []
	for e: Array in lc["hp_series"]:
		hp.append("%ds:%d%%" % [e[0], e[1]])
	L.append("  hp %% timeline: %s ; lowest %d%% at %.0fs" % [" ".join(hp), lc["lowest_hp_percent"], lc["lowest_hp_t"]])
	var en: PackedStringArray = []
	for e2: Array in lc["enemy_series"]:
		en.append("%ds:%d" % [e2[0], e2[1]])
	L.append("  aliens alive: %s ; peak %d at %.0fs" % [" ".join(en), lc["enemy_peak"], lc["enemy_peak_t"]])
	var deaths: Array = lc["deaths"]
	if deaths.is_empty():
		L.append("  deaths: none")
	else:
		var dl: PackedStringArray = []
		for d: Dictionary in deaths:
			dl.append("%.0fs (%s%s) fuel %d->%d%s" % [d["t"], d["cause"], ", PvP" if d["pvp"] else "", d["fuel_before"], d["fuel_after"],
				" ELIMINATED" if d["eliminated"] else ""])
		L.append("  deaths: %d: %s; respawns %d" % [deaths.size(), "; ".join(dl), lc["respawns"]])
	L.append("  fuel %d -> %d" % [lc["fuel_start"], lc["fuel_end"]])
	L.append("  scrap: %d at start, +%d earned (kills/bounties), +%d interest -> %d" % [lc["scrap_start"], lc["scrap_earned"], lc["interest"], lc["scrap_end"]])
	if w.vehicles.size() > 1:
		L.append("  PvP: %d of your shots hit rigs, %d rival shots hit you" % [lc["pvp_hits_dealt"], lc["pvp_hits_taken"]])
	_rival_lines(L, lc, w)
	var notes: PackedStringArray = []
	for f: Dictionary in lc["new_threats"]:
		notes.append("first %s seen at %.0fs (new this round)" % [f["kind"], f["first_seen_t"]])
	if int(lc["spitter_shots_fired"]) > 0:
		notes.append("%d acid shots fired" % int(lc["spitter_shots_fired"]))
	if not notes.is_empty():
		L.append("  notable: " + "; ".join(notes))
	return L


func _sim_stat_lines(ss: Dictionary, w: SimWorld) -> PackedStringArray:
	var L: PackedStringArray = []
	var rs: Dictionary = ss["round_stats"]
	var tk: Dictionary = rs["taken"]
	var tps: PackedStringArray = []
	for nm: String in rs["taken_players"]:
		tps.append("%s %s" % [nm, _num(float(rs["taken_players"][nm]))])
	L.append("  EXACT damage taken (sim): mite %s, boulder %s, spitter contact %s, acid %s, rival rigs %s%s" % [
		_num(float(tk["mite"])), _num(float(tk["boulder"])), _num(float(tk["spitter"])), _num(float(tk["acid"])), _num(float(tk["rival"])),
		(" (" + ", ".join(tps) + ")") if not tps.is_empty() else ""])
	L.append("  EXACT dealt %s hp (%s to rigs); kills %d aliens, %d rigs; fuel lost %d, stolen/gained %d, drained %d%s" % [
		_num(float(rs["dealt"])), _num(float(rs["dealt_players"])), rs["kills"], rs["kills_players"], rs["fuel_lost"], rs["fuel_gained"],
		rs["fuel_drained"], "; UNDERDOG (lowest fuel: loses 30% less per death)" if bool(ss["underdog"]) else ""])
	var ds: PackedStringArray = []
	for d: Dictionary in rs["deaths"]:
		ds.append("%.0fs by %s%s" % [d["t"], d["cause"], (" " + str(d["killer_name"])) if str(d["killer_name"]) != "" else ""])
	if not ds.is_empty():
		L.append("  EXACT deaths: " + "; ".join(ds))
	var ms: Dictionary = ss["match_stats"]
	L.append("  MATCH so far: %d aliens, %d rigs (%d by ram), %d deaths, %s hp dealt, %d scrap earned; top victim %s, nemesis %s" % [
		ms["kills"], ms["player_kills"], ms["ram_kills"], ms["deaths"], _num(float(ms["dmg_dealt"])), ms["scrap_earned"],
		str(ms["top_victim_name"]) if str(ms["top_victim_name"]) != "" else "-", str(ms["nemesis_name"]) if str(ms["nemesis_name"]) != "" else "-"])
	return L


func _rival_lines(L: PackedStringArray, lc: Dictionary, w: SimWorld) -> void:
	if w.vehicles.size() > 1:
		var ods: Array = lc["opponent_deaths"]
		for oi in mini(ods.size(), 8):
			var od: Dictionary = ods[oi]
			L.append("  %s destroyed at %.0fs (%s) fuel %d%s" % [od["name"], od["t"], od["cause"], od["fuel_after"],
				", ELIMINATED" if od["eliminated"] else ""])
		if ods.size() > 8:
			L.append("  (+%d more rival deaths, see state.json)" % (ods.size() - 8))
