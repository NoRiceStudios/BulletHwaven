extends SceneTree
## Headless bot league: plays many full matches between BotPolicy bots (real round timings, just
## ticks) and aggregates balance statistics. Two stages, usually driven by scripts/bot-league.sh:
##
##   run     godot --headless --path game -s res://tools/bot_league.gd -- --stage=run --mode=solo|ffa|all
##               [--seeds=20] [--matches=200] [--rounds=20] [--shard=0/4] [--out=<dir>] [--policies=a,b]
##               [--random-extra=40] [--seed-base=1000]
##           Writes one JSON line per match to <out>/raw_<mode>_<shard>.jsonl.
##   report  ... -- --stage=report --in=<dir> --out=<dir> [--extra=<markdown file>]
##           Reads every raw_*.jsonl in <in> and writes report.md plus CSVs to <out>.
##
## solo: every policy x N seeds (same seeds for every policy: paired comparison). ffa: 4 players,
## random policy mixes. A match ends at game over or when --rounds full rounds were played (capped).
## Landmark: a player's build "at the start of round 5" is stored, and card / tech lift compares the
## later outcome of players that own an item then against those that do not (controls for the
## survivorship bias of comparing final builds).

const LANDMARK := 5
const FFA_POS: Array = [Vector2(-240, -100), Vector2(240, -100), Vector2(240, 100), Vector2(-240, 100)]  ## offsets from the arena centre
const KIND_NAMES: PackedStringArray = ["mite", "boulder", "spitter", "glass", "brood", "shrieker", "boss", "boss", "boss"]
const FUEL_COLS: Array = [2, 4, 6, 8, 10, 12, 15, 20]

var args: Dictionary = {}
var max_rounds: int = 20


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "true"
	max_rounds = int(args.get("rounds", "20"))
	var stage: String = str(args.get("stage", "run"))
	if stage == "report":
		_report()
	else:
		_run()
	quit(0)


# ======================================================================== run stage

func _run() -> void:
	var mode: String = str(args.get("mode", "all"))
	var seeds: int = int(args.get("seeds", "20"))
	var matches: int = int(args.get("matches", "200"))
	var extra_rand: int = int(args.get("random-extra", "40"))
	var seed_base: int = int(args.get("seed-base", "1000"))
	var shard_parts: PackedStringArray = str(args.get("shard", "0/1")).split("/")
	var shard_i: int = int(shard_parts[0])
	var shard_n: int = maxi(int(shard_parts[1]) if shard_parts.size() > 1 else 1, 1)
	var out_dir: String = _out_dir()
	var pols: PackedStringArray = BotPolicy.names()
	if args.has("policies"):
		pols = str(args["policies"]).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)

	var jobs: Array[Dictionary] = []
	if mode == "solo" or mode == "all":
		for p in pols:
			var n: int = seeds + (extra_rand if p == "random" else 0)
			for s in n:
				jobs.append({"kind": "solo", "seed": seed_base + s, "policies": [p]})
	if mode == "ffa" or mode == "all":
		var mix := RandomNumberGenerator.new()
		mix.seed = 777
		for m in matches:
			var pick: Array = []
			for _k in 4:
				pick.append(pols[mix.randi() % pols.size()])
			jobs.append({"kind": "ffa", "seed": 50000 + m, "policies": pick})

	# Heavy jobs first would balance better, but order must stay deterministic; round-robin is fine.
	var mine: Array[Dictionary] = []
	for i in jobs.size():
		if i % shard_n == shard_i:
			mine.append(jobs[i])
	var path: String = "%s/raw_%s_%d.jsonl" % [out_dir, mode, shard_i]
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return
	var t0: int = Time.get_ticks_msec()
	for k in mine.size():
		var job: Dictionary = mine[k]
		var rec: Dictionary = _play(str(job["kind"]), int(job["seed"]), job["policies"])
		f.store_line(JSON.stringify(rec))
		f.flush()
		if (k + 1) % 5 == 0 or k + 1 == mine.size():
			print("[shard %d/%d] %d/%d matches, %.0fs" % [shard_i, shard_n, k + 1, mine.size(), (Time.get_ticks_msec() - t0) / 1000.0])
	f.close()


func _out_dir() -> String:
	if args.has("out"):
		return str(args["out"])
	return ProjectSettings.globalize_path("res://").path_join("../docs/balance").simplify_path()


## Plays one match and returns its record (see the run stage notes).
func _play(kind: String, p_seed: int, pols: Array) -> Dictionary:
	var w := SimWorld.new(p_seed)
	w.fast_rounds = false
	var n: int = pols.size()
	var bots: Array[BotPolicy] = []
	var stats: Array[Dictionary] = []
	var last_scrap: Array[int] = []
	var last_fuel: Array[int] = []
	for i in n:
		var pos: Vector2 = SimWorld.ARENA.get_center() + (Vector2.ZERO if n == 1 else (FFA_POS[i] as Vector2))
		var v: SimVehicle = w.add_vehicle(i + 1, pos)
		var bot: BotPolicy = BotPolicy.create(str(pols[i]), p_seed * 31 + i)
		bots.append(bot)
		for cmd in bot.doctrine_commands(w, v):
			w.apply_command(v.peer_id, cmd)
		stats.append({
			"policy": str(pols[i]), "income": 0, "spent": 0, "fuel_hist": [], "deaths": [], "picks": [],
			"shown": [], "rerolls": 0, "tech_buys": [], "b5": null, "elim_round": 0, "elim_tick": 0,
		})
		last_scrap.append(v.scrap)
		last_fuel.append(v.fuel)

	var elim_order: Array[int] = []
	var handled_round: int = 0
	var capped: bool = false
	var max_ticks: int = (max_rounds + 2) * (SimWorld.COMBAT_TICKS + SimWorld.WORKSHOP_TICKS)
	while w.phase != SimWorld.PHASE_GAME_OVER and w.tick < max_ticks:
		if w.phase == SimWorld.PHASE_WORKSHOP and handled_round != w.round:
			if w.round >= max_rounds:
				capped = true
				break
			handled_round = w.round
			for i in n:
				var v: SimVehicle = w.vehicles[i]
				if v.eliminated:
					continue
				_do_workshop(w, v, bots[i], stats[i])
				last_scrap[i] = v.scrap
				if w.round == LANDMARK - 1:
					stats[i]["b5"] = {"cards": v.cards.duplicate(), "tech": v.tech.duplicate()}
		w.step()
		for i in n:
			var v2: SimVehicle = w.vehicles[i]
			var d: int = v2.scrap - last_scrap[i]
			if d > 0:
				stats[i]["income"] = int(stats[i]["income"]) + d
			last_scrap[i] = v2.scrap
			if v2.eliminated and not elim_order.has(i):
				elim_order.append(i)
				stats[i]["elim_round"] = w.round
				stats[i]["elim_tick"] = w.tick
		for e in w.events:
			if str(e["type"]) == "vehicle_destroyed":
				var vi: int = int(e["owner"])
				var vd: SimVehicle = w.vehicles[vi]
				var src: int = int(e.get("cause", -1))  # SimWorld.SRC_*: 0 mite, 1 boulder, 2 spitter, 3 acid, 4 ram, 5 shots
				var cause: String = _cause(w, vd) if src < 0 else ["mite", "boulder", "spitter", "acid", "pvp", "pvp", "boss", "glass", "brood", "shrieker"][mini(src, 9)]
				(stats[vi]["deaths"] as Array).append([w.tick, w.round, cause])
		for i in n:
			last_fuel[i] = w.vehicles[i].fuel

	if w.boss_state == Bosses.ST_ACTIVE:  # the match ended with a boss on the field
		w.boss_log.append({"round": w.round, "kind": w.boss_kind, "what": "lost", "tick": w.boss_ticks, "hp": w.boss_hp_frac, "killer": -1,
			"taken": w.boss_dmg_taken, "dealt": {}, "alive": 0, "phase": w.boss_phase})
	# placements: survivors by fuel then kills, then eliminated in reverse elimination order
	var survivors: Array[int] = []
	for i in n:
		if not elim_order.has(i):
			survivors.append(i)
	survivors.sort_custom(func(a: int, b: int) -> bool:
		var va: SimVehicle = w.vehicles[a]
		var vb: SimVehicle = w.vehicles[b]
		if va.fuel != vb.fuel:
			return va.fuel > vb.fuel
		return va.kills > vb.kills)
	var order: Array[int] = survivors.duplicate()
	for j in range(elim_order.size() - 1, -1, -1):
		order.append(elim_order[j])
	var players: Array = []
	for i in n:
		var v3: SimVehicle = w.vehicles[i]
		var s: Dictionary = stats[i]
		var er: int = int(s["elim_round"])
		s["reached"] = er if er > 0 else mini(w.round, max_rounds)
		s["survived"] = er == 0
		s["kills"] = v3.kills
		s["fuel"] = v3.fuel
		s["scrap_end"] = v3.scrap
		s["cards"] = v3.cards.duplicate()
		s["tech"] = v3.tech.duplicate()
		s["placement"] = order.find(i) + 1
		s["won"] = w.phase == SimWorld.PHASE_GAME_OVER and w.winner_peer == v3.peer_id
		players.append(s)
	return {
		"kind": kind, "seed": p_seed, "ticks": w.tick, "rounds": w.round, "capped": capped,
		"gameover": w.phase == SimWorld.PHASE_GAME_OVER, "players": players, "bosses": w.boss_log,
	}


## One bot's whole workshop, applied command by command so the harness can log what was shown.
func _do_workshop(w: SimWorld, v: SimVehicle, bot: BotPolicy, st: Dictionary) -> void:
	(st["fuel_hist"] as Array).append(v.fuel)
	for cmd in bot.doctrine_commands(w, v):
		w.apply_command(v.peer_id, cmd)
	var before: int = v.scrap
	for _k in 40:
		var c: Dictionary = bot.next_command(w, v)
		if c.is_empty():
			break
		var t: String = str(c["type"])
		if t == "pick_card":
			var shown: Array = v.offers.duplicate()
			(st["shown"] as Array).append(shown)
			(st["picks"] as Array).append(str(shown[int(c["value"])]))
		elif t == "reroll":
			st["rerolls"] = int(st["rerolls"]) + 1
		elif t == "buy_tech":
			(st["tech_buys"] as Array).append([str(c["value"]), w.round])
		w.apply_command(v.peer_id, c)
		if t == "ready":
			break
	st["spent"] = int(st["spent"]) + (before - v.scrap)


func _cause(w: SimWorld, v: SimVehicle) -> String:
	var weight: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for j in w.enemy_count:
		if w.enemy_pos[j].distance_squared_to(v.pos) < 40.0 * 40.0:
			var k: int = w.enemy_kind[j]
			weight[k] += SimWorld.ENEMY_CONTACT_DAMAGE[k]
	var bi: int = 0
	if weight[1] > weight[bi]:
		bi = 1
	for bk in range(2, 9):
		if weight[bk] > weight[bi]:
			bi = bk
	if weight[bi] > 0.0:
		return KIND_NAMES[bi]
	for p in w.proj_count:
		if w.proj_owner[p] < 0 and w.proj_pos[p].distance_squared_to(v.pos) < 40.0 * 40.0:
			return "acid"
	return "other"


# ======================================================================== report stage

func _report() -> void:
	var in_dir: String = str(args.get("in", _out_dir()))
	var out_dir: String = _out_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var recs: Array[Dictionary] = []
	var da: DirAccess = DirAccess.open(in_dir)
	if da == null:
		push_error("cannot open " + in_dir)
		return
	var files: PackedStringArray = da.get_files()
	files.sort()
	for fn in files:
		if not (fn.begins_with("raw_") and fn.ends_with(".jsonl")):
			continue
		var f: FileAccess = FileAccess.open(in_dir.path_join(fn), FileAccess.READ)
		while f != null and not f.eof_reached():
			var line: String = f.get_line()
			if line.strip_edges() == "":
				continue
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				recs.append(parsed)
	var solo: Array[Dictionary] = []  # flattened player rows
	var ffa: Array[Dictionary] = []
	var ffa_matches: Array[Dictionary] = []
	for r in recs:
		var kind: String = str(r["kind"])
		for p: Dictionary in r["players"]:
			p["kind"] = kind
			p["match_ticks"] = r["ticks"]
			# score = rounds reached; a survivor of the cap also gets its remaining fuel as a fraction
			# of a round, so capped runs still rank by how healthy they ended.
			p["score"] = float(p["reached"]) + (float(p["fuel"]) / 100.0 if bool(p["survived"]) else 0.0)
			if kind == "solo":
				solo.append(p)
			else:
				ffa.append(p)
		if kind == "ffa":
			ffa_matches.append(r)
	print("report: %d matches (%d solo rows, %d ffa rows)" % [recs.size(), solo.size(), ffa.size()])
	if recs.is_empty():
		return

	var md: PackedStringArray = PackedStringArray()
	var finds: PackedStringArray = PackedStringArray()
	var cap: int = 0
	for r in recs:
		cap = maxi(cap, int(r["rounds"]))
	md.append("# Bot league balance report")
	md.append("")
	md.append("Generated by `scripts/bot-league.sh` (`game/tools/bot_league.gd`, policies in `game/tools/bots.gd`).")
	md.append("%d matches: %d solo rows, %d ffa matches. Round cap per match: %d (real timings, `fast_rounds = false`)." % [
		recs.size(), solo.size(), ffa_matches.size(), int(args.get("rounds", str(max_rounds)))])
	md.append("")
	md.append("Caveats: bots are heuristic (see `bots.gd`), doctrine is static per policy, bots never react to rivals except `players_first`, results are for the sim as checked out when the run was made, and ffa win rates depend on the policy mix. Card/tech lift compares players that own an item at the start of round %d against those that do not, and is only comparable within a column. `se` = standard error; |lift| > 2 se is flagged `*`." % LANDMARK)
	md.append("")

	var pol_names: PackedStringArray = BotPolicy.names()
	for sp: Dictionary in solo:  # node probes (probe_<id>, base_<branch>) are not in the registry
		if not pol_names.has(str(sp["policy"])):
			pol_names.append(str(sp["policy"]))
	# ---- solo policies
	var solo_rows: Array = []
	var solo_csv: PackedStringArray = PackedStringArray(["policy,n,mean_reached,median_reached,p25,p75,capped_pct,mean_kills,mean_income,mean_first_death_s,mean_deaths"])
	var solo_stat: Dictionary = {}
	for pn in pol_names:
		var rows: Array = solo.filter(func(p: Dictionary) -> bool: return str(p["policy"]) == pn)
		if rows.is_empty():
			continue
		var reached: Array = rows.map(func(p: Dictionary) -> float: return float(p["score"]))
		var capped_pct: float = 100.0 * float(rows.filter(func(p: Dictionary) -> bool: return bool(p["survived"])).size()) / rows.size()
		var kills: Array = rows.map(func(p: Dictionary) -> float: return float(p["kills"]))
		var income: Array = rows.map(func(p: Dictionary) -> float: return float(p["income"]))
		var fd: Array = []
		var nd: Array = []
		for p: Dictionary in rows:
			var dl: Array = p["deaths"]
			nd.append(float(dl.size()))
			if not dl.is_empty():
				fd.append(float((dl[0] as Array)[0]) / 30.0)
		var st := {"n": rows.size(), "mean": _mean(reached), "median": _pct(reached, 0.5), "p25": _pct(reached, 0.25),
			"p75": _pct(reached, 0.75), "capped": capped_pct, "kills": _mean(kills), "income": _mean(income)}
		solo_stat[pn] = st
		solo_rows.append([pn, rows.size(), _f(st["mean"], 1), _f(st["median"], 1), "%s-%s" % [_f(st["p25"], 0), _f(st["p75"], 0)],
			_f(capped_pct, 0) + "%", _f(st["kills"], 0), _f(st["income"], 0), _f(_mean(fd), 0) if not fd.is_empty() else "-", _f(_mean(nd), 1)])
		solo_csv.append("%s,%d,%.2f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.2f" % [pn, rows.size(), st["mean"], st["median"], st["p25"], st["p75"],
			capped_pct, st["kills"], st["income"], _mean(fd) if not fd.is_empty() else 0.0, _mean(nd)])
	if not solo_rows.is_empty():
		solo_rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
		md.append("## Solo: rounds survived per policy")
		md.append("")
		md.append("`score` = round in which the rig ran out of fuel, or for rigs that survived to the round cap: cap + remaining fuel / 100 (so capped runs still rank by health). `capped%` = survived to the cap. Time to first death in game seconds.")
		md.append("")
		md.append_array(_table(["policy", "n", "score (mean)", "median", "p25-p75", "capped%", "kills", "scrap earned", "1st death (s)", "deaths"], solo_rows))
		md.append("")
		_save_lines(out_dir.path_join("solo_policies.csv"), solo_csv)

		# keystone timing: round of the first tier 6 purchase (and the first tier 5 one), per policy
		var key_rows: Array = []
		for pn in pol_names:
			var k6: Array = []
			var k5: Array = []
			var nrows: int = 0
			for p: Dictionary in solo:
				if str(p["policy"]) != pn:
					continue
				nrows += 1
				for tb: Array in p["tech_buys"]:
					var td: Dictionary = Tech.def(str(tb[0]))
					if td.is_empty() or td["kind"] == "proto":
						continue
					if int(td["tier"]) == 6:
						k6.append(float(tb[1]))
						break
				for tb2: Array in p["tech_buys"]:
					var td2: Dictionary = Tech.def(str(tb2[0]))
					if not td2.is_empty() and td2["kind"] != "proto" and int(td2["tier"]) == 5:
						k5.append(float(tb2[1]))
						break
			if nrows > 0 and not str(pn).begins_with("never"):
				key_rows.append([pn, nrows, "%d%%" % int(100.0 * k5.size() / nrows), _f(_mean(k5), 1) if not k5.is_empty() else "-",
					"%d%%" % int(100.0 * k6.size() / nrows), _f(_mean(k6), 1) if not k6.is_empty() else "-"])
		md.append("## Keystone timing (solo)")
		md.append("")
		md.append("Workshop round of the first tier 5 / tier 6 purchase (round 1 = first workshop after round 0). Design target: a focused good player reaches a keystone around round 9-10.")
		md.append("")
		md.append_array(_table(["policy", "n", "reached t5", "t5 round (mean)", "reached t6", "t6 round (mean)"], key_rows))
		md.append("")

		# fuel by round + cause of death
		var fuel_rows: Array = []
		var fuel_csv: PackedStringArray = PackedStringArray(["policy," + ",".join(FUEL_COLS.map(func(c: int) -> String: return "r%d" % c))])
		var cause_rows: Array = []
		for pn in pol_names:
			var rows2: Array = solo.filter(func(p: Dictionary) -> bool: return str(p["policy"]) == pn)
			if rows2.is_empty():
				continue
			var line: Array = [pn]
			var csvl: Array = [pn]
			for c: int in FUEL_COLS:
				var vals: Array = []
				for p: Dictionary in rows2:
					var fh: Array = p["fuel_hist"]
					# fuel at the end of round c; 0 once eliminated earlier; ignore capped runs shorter than c
					if fh.size() >= c:
						vals.append(float(fh[c - 1]))
					elif not bool(p["survived"]):
						vals.append(0.0)
				line.append(_f(_mean(vals), 0) if not vals.is_empty() else "-")
				csvl.append(_f(_mean(vals), 1) if not vals.is_empty() else "")
			fuel_rows.append(line)
			fuel_csv.append(",".join(PackedStringArray(csvl.map(func(x: Variant) -> String: return str(x)))))
			var causes: Dictionary = {}
			var total: int = 0
			for p: Dictionary in rows2:
				for d: Array in p["deaths"]:
					var cs: String = str(d[2])
					causes[cs] = int(causes.get(cs, 0)) + 1
					total += 1
			var cl: Array = [pn, total]
			for cs2 in ["mite", "boulder", "spitter", "acid", "pvp", "other"]:
				cl.append(_f(100.0 * float(causes.get(cs2, 0)) / maxf(total, 1), 0) + "%")
			cause_rows.append(cl)
		md.append("### Fuel at the end of round N (mean, 0 once eliminated)")
		md.append("")
		md.append_array(_table(["policy"] + FUEL_COLS.map(func(c: int) -> String: return "r%d" % c), fuel_rows))
		md.append("")
		md.append("### Cause of death (share of vehicle losses, nearest damaging enemy kind)")
		md.append("")
		md.append_array(_table(["policy", "losses", "mite", "boulder", "spitter", "acid", "pvp", "other"], cause_rows))
		md.append("")
		_save_lines(out_dir.path_join("solo_fuel_by_round.csv"), fuel_csv)

		# distributions
		var dist_csv: PackedStringArray = PackedStringArray(["round,first_death_count,reached_count"])
		var first_death: Dictionary = {}
		var reach: Dictionary = {}
		var firsts: Array = []
		for p: Dictionary in solo:
			var dl2: Array = p["deaths"]
			var fr: int = int((dl2[0] as Array)[1]) if not dl2.is_empty() else 0
			first_death[fr] = int(first_death.get(fr, 0)) + 1
			var rr: int = int(p["reached"])
			reach[rr] = int(reach.get(rr, 0)) + 1
			if fr > 0:
				firsts.append(float(fr))
		var drows: Array = []
		for rd in range(0, max_rounds + 1):
			var a: int = int(first_death.get(rd, 0))
			var b: int = int(reach.get(rd, 0))
			if rd > 0 or a > 0:
				dist_csv.append("%d,%d,%d" % [rd, a, b])
			if a > 0 or b > 0:
				drows.append(["never" if rd == 0 else str(rd), a, _bar(a, solo.size()), b, _bar(b, solo.size())])
		md.append("### Distributions (all solo rows)")
		md.append("")
		md.append("Round of the first vehicle loss (0 = never lost a vehicle) and the round reached (round of elimination; cap = survived).")
		md.append("")
		md.append_array(_table(["round", "first loss", "", "reached", ""], drows))
		md.append("")
		_save_lines(out_dir.path_join("solo_distributions.csv"), dist_csv)

	# ---- ffa policies
	var ffa_stat: Dictionary = {}
	if not ffa.is_empty():
		var frows: Array = []
		var fcsv: PackedStringArray = PackedStringArray(["policy,appearances,wins,win_rate,avg_placement,mean_reached,mean_kills"])
		for pn in pol_names:
			var rows3: Array = ffa.filter(func(p: Dictionary) -> bool: return str(p["policy"]) == pn)
			if rows3.is_empty():
				continue
			var wins: int = rows3.filter(func(p: Dictionary) -> bool: return bool(p["won"])).size()
			var placement: Array = rows3.map(func(p: Dictionary) -> float: return float(p["placement"]))
			var reached3: Array = rows3.map(func(p: Dictionary) -> float: return float(p["reached"]))
			var kills3: Array = rows3.map(func(p: Dictionary) -> float: return float(p["kills"]))
			var wr: float = float(wins) / rows3.size()
			ffa_stat[pn] = {"n": rows3.size(), "wr": wr, "place": _mean(placement)}
			frows.append([pn, rows3.size(), wins, _f(100.0 * wr, 1) + "%", _f(_mean(placement), 2), _f(_mean(reached3), 1), _f(_mean(kills3), 0)])
			fcsv.append("%s,%d,%d,%.4f,%.3f,%.2f,%.1f" % [pn, rows3.size(), wins, wr, _mean(placement), _mean(reached3), _mean(kills3)])
		frows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[4]) < float(b[4]))
		md.append("## FFA: 4 players, random policy mixes")
		md.append("")
		var decisive: int = ffa_matches.filter(func(m: Dictionary) -> bool: return bool(m["gameover"])).size()
		var lens: Array = ffa_matches.map(func(m: Dictionary) -> float: return float(m["rounds"]))
		var mins: Array = ffa_matches.map(func(m: Dictionary) -> float: return float(m["ticks"]) / 30.0 / 60.0)
		md.append("%d matches, %d decided before the cap (%s%%). Game length: mean %s rounds, median %s, p90 %s; mean %s min of bot play time (workshops skipped as soon as every bot is ready; add up to 90 s per round for human shopping). Fair win rate is 25%%." % [
			ffa_matches.size(), decisive, _f(100.0 * decisive / maxf(ffa_matches.size(), 1), 0), _f(_mean(lens), 1), _f(_pct(lens, 0.5), 0),
			_f(_pct(lens, 0.9), 0), _f(_mean(mins), 1)])
		md.append("")
		md.append_array(_table(["policy", "appearances", "wins", "win rate", "avg place (1 = best)", "mean round out", "kills"], frows))
		md.append("")
		_save_lines(out_dir.path_join("ffa_policies.csv"), fcsv)

		# placement histogram of game length
		var lhist: Dictionary = {}
		for m: Dictionary in ffa_matches:
			var rr2: int = int(m["rounds"])
			lhist[rr2] = int(lhist.get(rr2, 0)) + 1
		var lrows: Array = []
		for rd2 in range(1, max_rounds + 1):
			if lhist.has(rd2):
				lrows.append([rd2, lhist[rd2], _bar(int(lhist[rd2]), ffa_matches.size())])
		md.append("Game length distribution (round the game ended):")
		md.append("")
		md.append_array(_table(["round", "matches", ""], lrows))
		md.append("")

	# ---- cards and tech
	var all_rows: Array[Dictionary] = []
	all_rows.append_array(solo)
	all_rows.append_array(ffa)
	var card_ids: Array[String] = []
	for i in Cards.count():
		card_ids.append(Cards.id_at(i))
	var tech_ids: Array[String] = []
	for i in Tech.count():
		tech_ids.append(Tech.id_at(i))

	var offered: Dictionary = {}
	var picked: Dictionary = {}
	for p: Dictionary in all_rows:
		for sh: Array in p["shown"]:
			for cid in sh:
				offered[str(cid)] = int(offered.get(str(cid), 0)) + 1
		for pk in p["picks"]:
			picked[str(pk)] = int(picked.get(str(pk), 0)) + 1
	var card_rows: Array = []
	var card_csv: PackedStringArray = PackedStringArray(["card,offered,picked,pick_rate,lvl3_share_end,solo_lift,solo_se,solo_n_own,solo_random_lift,solo_random_se,solo_random_n_own,ffa_win_lift,ffa_se,ffa_n_own"])
	var card_info: Dictionary = {}
	for cid in card_ids:
		var own_fn: Callable = func(p: Dictionary) -> bool:
			var b5: Dictionary = p["b5"]
			return int((b5["cards"] as Dictionary).get(cid, 0)) >= (2 if cid == "mg" else 1)
		var l_solo: Dictionary = _lift(solo, own_fn, "score")
		var l_rand: Dictionary = _lift(solo.filter(func(p: Dictionary) -> bool: return str(p["policy"]) == "random"), own_fn, "score")
		var l_ffa: Dictionary = _lift(ffa, own_fn, "won")
		var off: int = int(offered.get(cid, 0))
		var pk2: int = int(picked.get(cid, 0))
		var l3: int = all_rows.filter(func(p: Dictionary) -> bool: return int((p["cards"] as Dictionary).get(cid, 0)) >= 3).size()
		var pr: float = float(pk2) / maxf(off, 1)
		card_info[cid] = {"pick_rate": pr, "solo": l_solo, "rand": l_rand, "ffa": l_ffa, "offered": off, "lvl3": float(l3) / maxf(all_rows.size(), 1)}
		card_rows.append([cid, off, pk2, _f(100.0 * pr, 0) + "%", _lf(l_solo, 2), _lf(l_rand, 2), _lf(l_ffa, 1, 100.0, "pp"), _f(100.0 * l3 / maxf(all_rows.size(), 1), 0) + "%"])
		card_csv.append("%s,%d,%d,%.4f,%.4f,%s,%s,%s" % [cid, off, pk2, pr, float(l3) / maxf(all_rows.size(), 1), _lc(l_solo), _lc(l_rand), _lc(l_ffa)])
	md.append("## Cards")
	md.append("")
	md.append("`offered` / `picked`: times shown at pick time / chosen (policy driven, so pick rate says more about the bots' scoring than about power). `solo lift`: extra rounds reached by rigs that own the card at the start of round %d vs those that do not (mg: level 2+). `random lift`: same, only the `random` policy (the cleanest signal: its picks are unbiased). `ffa lift`: win-rate difference in percentage points. `lvl3`: share of all players with the card at level 3 at the end." % LANDMARK)
	md.append("")
	md.append_array(_table(["card", "offered", "picked", "pick rate", "solo lift (rounds)", "random lift (rounds)", "ffa lift", "lvl3"], card_rows))
	md.append("")
	_save_lines(out_dir.path_join("cards.csv"), card_csv)

	var tech_rows: Array = []
	var tech_csv: PackedStringArray = PackedStringArray(["tech,cost,owned_end_share,owned_r5_share,solo_lift,solo_se,solo_n_own,solo_random_lift,solo_random_se,solo_random_n_own,ffa_win_lift,ffa_se,ffa_n_own"])
	var tech_info: Dictionary = {}
	for tid in tech_ids:
		var own_fn2: Callable = func(p: Dictionary) -> bool:
			var b5: Dictionary = p["b5"]
			return (b5["tech"] as Array).has(tid)
		var t_solo: Dictionary = _lift(solo, own_fn2, "score")
		var t_rand: Dictionary = _lift(solo.filter(func(p: Dictionary) -> bool: return str(p["policy"]) == "random"), own_fn2, "score")
		var t_ffa: Dictionary = _lift(ffa, own_fn2, "won")
		var end_n: int = all_rows.filter(func(p: Dictionary) -> bool: return (p["tech"] as Array).has(tid)).size()
		var with_b5: Array = all_rows.filter(func(p: Dictionary) -> bool: return p["b5"] != null)
		var r5_n: int = with_b5.filter(func(p: Dictionary) -> bool: return ((p["b5"] as Dictionary)["tech"] as Array).has(tid)).size()
		tech_info[tid] = {"solo": t_solo, "rand": t_rand, "ffa": t_ffa, "end": float(end_n) / maxf(all_rows.size(), 1)}
		tech_rows.append([tid, Tech.cost(tid), _f(100.0 * end_n / maxf(all_rows.size(), 1), 0) + "%", _f(100.0 * r5_n / maxf(with_b5.size(), 1), 0) + "%",
			_lf(t_solo, 2), _lf(t_rand, 2), _lf(t_ffa, 1, 100.0, "pp")])
		tech_csv.append("%s,%d,%.4f,%.4f,%s,%s,%s" % [tid, Tech.cost(tid), float(end_n) / maxf(all_rows.size(), 1), float(r5_n) / maxf(with_b5.size(), 1), _lc(t_solo), _lc(t_rand), _lc(t_ffa)])
	md.append("## Tech")
	md.append("")
	md.append("`owned end`: share of all players owning it at the end of their game. `owned r%d`: share of players alive at round %d that already had it. Lifts as for cards. Tech purchases are policy-driven (random buys uniformly), so read the random column first." % [LANDMARK, LANDMARK])
	md.append("")
	md.append_array(_table(["tech", "cost", "owned end", "owned r%d" % LANDMARK, "solo lift (rounds)", "random lift (rounds)", "ffa lift"], tech_rows))
	md.append("")
	_save_lines(out_dir.path_join("tech.csv"), tech_csv)

	# ---- economy
	var econ_rows: Array = []
	for pn in pol_names:
		var rows4: Array = all_rows.filter(func(p: Dictionary) -> bool: return str(p["policy"]) == pn)
		if rows4.is_empty():
			continue
		var inc: Array = rows4.map(func(p: Dictionary) -> float: return float(p["income"]) / maxf(float(p["reached"]), 1.0))
		var spn: Array = rows4.map(func(p: Dictionary) -> float: return float(p["spent"]) / maxf(float(p["reached"]), 1.0))
		var rer: Array = rows4.map(func(p: Dictionary) -> float: return float(p["rerolls"]) / maxf(float(p["reached"]), 1.0))
		var end_s: Array = rows4.map(func(p: Dictionary) -> float: return float(p["scrap_end"]))
		econ_rows.append([pn, _f(_mean(inc), 1), _f(_mean(spn), 1), _f(_mean(rer), 2), _f(_mean(end_s), 0)])
	md.append("## Economy (per round played)")
	md.append("")
	md.append_array(_table(["policy", "scrap income / round", "scrap spent / round", "rerolls / round", "unspent at end"], econ_rows))
	md.append("")

	md.append_array(_boss_section(recs))

	# ---- findings
	finds.append_array(_findings(solo_stat, ffa_stat, card_info, tech_info, solo, ffa, ffa_matches))
	md.insert(7, "## Findings")
	md.insert(8, "")
	for i in finds.size():
		md.insert(9 + i, finds[i])
	md.insert(9 + finds.size(), "")

	var extra: String = str(args.get("extra", ""))
	if extra != "" and FileAccess.file_exists(extra):
		md.append(FileAccess.get_file_as_string(extra))
	var rf: FileAccess = FileAccess.open(out_dir.path_join("report.md"), FileAccess.WRITE)
	rf.store_string("\n".join(md) + "\n")
	rf.close()
	var ff: FileAccess = FileAccess.open(out_dir.path_join("findings.txt"), FileAccess.WRITE)
	ff.store_string("\n".join(finds) + "\n")
	ff.close()
	print("report written to " + out_dir.path_join("report.md"))


## Boss encounters: one row per (match, boss round) from the sim's boss_log.
func _boss_section(recs: Array[Dictionary]) -> PackedStringArray:
	var enc: Array[Dictionary] = []
	var boss_deaths: Dictionary = {}  # round -> deaths caused by a boss
	for r in recs:
		var logs: Array = r.get("bosses", [])
		var by: Dictionary = {}
		for row: Dictionary in logs:
			var rk: int = int(row["round"])
			if not by.has(rk):
				by[rk] = []
			(by[rk] as Array).append(row)
		for rk2 in by.keys():
			var rows: Array = by[rk2]
			var outcome: String = "lost"
			var ticks: int = 0
			var hp_left: float = 1.0
			var taken: float = 0.0
			var spawned: bool = false
			var kind: int = 3
			var alive: int = 0
			for row2: Dictionary in rows:
				var what: String = str(row2["what"])
				kind = int(row2["kind"])
				if what == "spawn":
					spawned = true
					alive = int(row2["alive"])
				taken = float(row2["taken"])
				if what == "kill":
					outcome = "killed"
					ticks = int(row2["tick"])
					hp_left = 0.0
				elif what == "retreat" and outcome != "killed":
					outcome = "retreated"
					hp_left = float(row2["hp"])
					ticks = int(row2["tick"])
				elif what == "lost" and outcome != "killed":
					hp_left = float(row2["hp"])
					ticks = int(row2["tick"])
			if not spawned:
				continue
			var pol: String = str((r["players"] as Array)[0]["policy"]) if str(r["kind"]) == "solo" else "ffa"
			enc.append({"policy": pol, "round": int(rk2), "kind": kind, "outcome": outcome, "ticks": ticks, "hp_left": hp_left, "taken": taken, "alive": alive, "mode": str(r["kind"])})
		for p: Dictionary in r["players"]:
			for d: Array in p["deaths"]:
				if str(d[2]) == "boss":
					boss_deaths[int(d[1])] = int(boss_deaths.get(int(d[1]), 0)) + 1
	var out := PackedStringArray()
	out.append("## Bosses")
	out.append("")
	if enc.is_empty():
		out.append("No boss encounters in this run.")
		out.append("")
		return out
	out.append("One row per boss spawn. `kill%` = boss dead before the round ended, `retreat%` = round timer ended with the boss alive, `lost%` = the match ended with it on the field. `taken` = damage the boss's own attacks did to rigs (shells, charges, shards, contact).")
	out.append("")
	var heads: Array = ["", "n", "kill%", "retreat%", "lost%", "mean kill time s", "hp left (not killed)", "taken / enc", "rigs/spawn", "boss deaths"]
	for mode in ["solo", "ffa"]:
		var rows3: Array = []
		for rk3 in range(4, 41, 4):
			var es: Array = enc.filter(func(e: Dictionary) -> bool: return int(e["round"]) == rk3 and str(e["mode"]) == mode)
			if es.is_empty():
				continue
			rows3.append(_boss_row("R%d" % rk3, es, int(boss_deaths.get(rk3, 0))))
		if not rows3.is_empty():
			out.append("### %s, by round" % mode)
			out.append("")
			heads[0] = "round"
			out.append_array(_table(heads, rows3))
			out.append("")
	var pols: Array = []
	for e in enc:
		if str(e["mode"]) == "solo" and not pols.has(str(e["policy"])):
			pols.append(str(e["policy"]))
	pols.sort()
	var prow: Array = []
	for pn in pols:
		var es2: Array = enc.filter(func(e: Dictionary) -> bool: return str(e["policy"]) == pn and str(e["mode"]) == "solo")
		prow.append(_boss_row(str(pn), es2, 0))
	if not prow.is_empty():
		out.append("### solo, by policy (all boss rounds)")
		out.append("")
		heads[0] = "policy"
		out.append_array(_table(heads, prow))
		out.append("")
	var kinds: Array = []
	for kk in [SimWorld.BOSS_A, SimWorld.BOSS_B]:
		var es3: Array = enc.filter(func(e: Dictionary) -> bool: return int(e["kind"]) == kk)
		if not es3.is_empty():
			kinds.append(_boss_row(Bosses.boss_name(kk), es3, 0))
	if not kinds.is_empty():
		out.append("### by boss")
		out.append("")
		heads[0] = "boss"
		out.append_array(_table(heads, kinds))
		out.append("")
	return out


func _boss_row(label: String, es: Array, deaths: int) -> Array:
	var n: int = es.size()
	var k: int = 0
	var rt: int = 0
	var ls: int = 0
	var kt: Array = []
	var hl: Array = []
	var tk: Array = []
	var al: Array = []
	for e: Dictionary in es:
		match str(e["outcome"]):
			"killed":
				k += 1
				kt.append(float(e["ticks"]) / 30.0)
			"retreated":
				rt += 1
				hl.append(float(e["hp_left"]))
			_:
				ls += 1
				hl.append(float(e["hp_left"]))
		tk.append(float(e["taken"]))
		al.append(float(e["alive"]))
	return [label, n, _f(100.0 * k / n, 0), _f(100.0 * rt / n, 0), _f(100.0 * ls / n, 0), _f(_mean(kt), 1) if not kt.is_empty() else "-",
		_f(100.0 * _mean(hl), 0) + "%" if not hl.is_empty() else "-", _f(_mean(tk), 0), _f(_mean(al), 1), deaths if deaths > 0 else "-"]


func _findings(solo_stat: Dictionary, ffa_stat: Dictionary, card_info: Dictionary, tech_info: Dictionary,
		solo: Array[Dictionary], ffa: Array[Dictionary], ffa_matches: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	# ---- solo policies
	if solo_stat.has("never_upgrade") and solo_stat.has("balanced"):
		var base: float = float((solo_stat["never_upgrade"] as Dictionary)["mean"])
		var bal: float = float((solo_stat["balanced"] as Dictionary)["mean"])
		out.append("- **Upgrade value (solo):** `balanced` scores %s vs %s for `never_upgrade` (%+.1f rounds, x%.2f)." % [_f(bal, 1), _f(base, 1), bal - base, bal / maxf(base, 0.1)])
	var ranked: Array = solo_stat.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool: return float((solo_stat[a] as Dictionary)["mean"]) > float((solo_stat[b] as Dictionary)["mean"]))
	if ranked.size() >= 3:
		var top: PackedStringArray = PackedStringArray()
		for i in mini(4, ranked.size()):
			top.append("`%s` (%s)" % [ranked[i], _f((solo_stat[ranked[i]] as Dictionary)["mean"], 1)])
		var bot: PackedStringArray = PackedStringArray()
		for i in range(maxi(ranked.size() - 4, 4), ranked.size()):
			bot.append("`%s` (%s)" % [ranked[i], _f((solo_stat[ranked[i]] as Dictionary)["mean"], 1)])
		out.append("- **Solo policy ranking (score):** best %s; worst %s." % [", ".join(top), ", ".join(bot)])
		# dominant: clearly above `balanced`, the human-like reference
		if solo_stat.has("balanced"):
			var bal2: float = float((solo_stat["balanced"] as Dictionary)["mean"])
			var dom_s: PackedStringArray = PackedStringArray()
			var weak_s: PackedStringArray = PackedStringArray()
			for pn: String in solo_stat:
				var m: float = float((solo_stat[pn] as Dictionary)["mean"])
				if pn != "balanced" and m > bal2 + 1.5:
					dom_s.append("`%s` (%+.1f vs balanced)" % [pn, m - bal2])
				if pn not in ["never_upgrade", "random", "balanced"] and m < bal2 - 4.0:
					weak_s.append("`%s` (%+.1f)" % [pn, m - bal2])
			out.append("- **Dominant solo strategies (> balanced + 1.5 rounds):** %s." % (", ".join(dom_s) if not dom_s.is_empty() else "none"))
			out.append("- **Solo strategies far behind balanced (< -4 rounds, excluding baselines):** %s." % (", ".join(weak_s) if not weak_s.is_empty() else "none"))
	var capped_pols: PackedStringArray = PackedStringArray()
	for pn: String in solo_stat:
		if float((solo_stat[pn] as Dictionary)["capped"]) >= 50.0:
			capped_pols.append(pn)
	out.append("- **Pacing, solo:** %d of %d policies survive to the round cap in 50%%+ of runs (%s): the alien curve is too gentle for decent builds." % [capped_pols.size(), solo_stat.size(), ", ".join(capped_pols) if not capped_pols.is_empty() else "-"])
	var dead: Array = solo.filter(func(p: Dictionary) -> bool: return not bool(p["survived"]))
	if not dead.is_empty():
		var rd: Array = dead.map(func(p: Dictionary) -> float: return float(p["reached"]))
		out.append("- **Pacing, solo:** eliminated runs end at median round %s (p10 %s, p90 %s); a rig has 5 lives (20 fuel each), see the fuel table." % [_f(_pct(rd, 0.5), 0), _f(_pct(rd, 0.1), 0), _f(_pct(rd, 0.9), 0)])
	# weapons by focus policy
	var wl: PackedStringArray = PackedStringArray()
	for wk: String in Cards.WEAPON_KINDS:
		if solo_stat.has("focus_" + wk):
			wl.append("`%s` %s" % [wk, _f((solo_stat["focus_" + wk] as Dictionary)["mean"], 1)])
	if not wl.is_empty():
		out.append("- **Weapon strength (solo score of the single-weapon focus policies):** %s." % ", ".join(wl))
	# economy
	var unspent: Array = []
	for p: Dictionary in solo:
		if str(p["policy"]) == "balanced":
			unspent.append(float(p["scrap_end"]))
	if not unspent.is_empty():
		var tree_cost: int = 0
		for ti in Tech.count():
			tree_cost += Tech.cost(Tech.id_at(ti))
		var left: float = _mean(unspent)
		out.append("- **Economy:** a `balanced` rig ends with %s unspent scrap on average (all %d tech cost %d in total): %s" % [_f(left, 0), Tech.count(), tree_cost,
			"scrap is never a constraint, so tech prices, reroll costs and interest do not matter." if left > 3.0 * tree_cost else "scrap is a real (if mild) constraint."])
	# ---- ffa
	if not ffa_stat.is_empty():
		var dom: PackedStringArray = PackedStringArray()
		var weak: PackedStringArray = PackedStringArray()
		for pn: String in ffa_stat:
			var s: Dictionary = ffa_stat[pn]
			if int(s["n"]) < 20:
				continue
			var se: float = sqrt(0.25 * 0.75 / float(s["n"]))
			if float(s["wr"]) > 0.25 + 2.0 * se:
				dom.append("`%s` (%s%%, avg place %s)" % [pn, _f(100.0 * float(s["wr"]), 0), _f(s["place"], 2)])
			if float(s["wr"]) < 0.25 - 2.0 * se:
				weak.append("`%s` (%s%%, avg place %s)" % [pn, _f(100.0 * float(s["wr"]), 0), _f(s["place"], 2)])
		out.append("- **FFA policies winning significantly more than 25%%:** %s." % (", ".join(dom) if not dom.is_empty() else "none"))
		out.append("- **FFA policies winning significantly less than 25%%:** %s." % (", ".join(weak) if not weak.is_empty() else "none"))
		var decisive: int = ffa_matches.filter(func(m: Dictionary) -> bool: return bool(m["gameover"])).size()
		var lens: Array = ffa_matches.map(func(m: Dictionary) -> float: return float(m["rounds"]))
		out.append("- **Pacing, ffa:** %s%% of matches are decided before the round cap; median length %s rounds (p90 %s)." % [_f(100.0 * decisive / maxf(ffa_matches.size(), 1), 0), _f(_pct(lens, 0.5), 0), _f(_pct(lens, 0.9), 0)])
		var pvp_n: int = 0
		var loss_n: int = 0
		for p: Dictionary in ffa:
			for d: Array in p["deaths"]:
				loss_n += 1
				if str(d[2]) == "pvp":
					pvp_n += 1
		out.append("- **PvP share:** %s%% of ffa vehicle losses were caused by another player (bots only attack players when `players_first`)." % _f(100.0 * pvp_n / maxf(loss_n, 1), 0))
	# ---- cards / tech: only the `random` policy is an unbiased sample, so it decides
	var strong: PackedStringArray = PackedStringArray()
	var useless: PackedStringArray = PackedStringArray()
	var neverpick: PackedStringArray = PackedStringArray()
	for cid: String in card_info:
		var ci: Dictionary = card_info[cid]
		var lr: Dictionary = ci["rand"]
		if int(lr["n1"]) >= 10 and int(lr["n0"]) >= 10 and absf(float(lr["delta"])) > 2.0 * float(lr["se"]):
			if float(lr["delta"]) > 0.0:
				strong.append("`%s` (%+.1f rounds)" % [cid, float(lr["delta"])])
			else:
				useless.append("`%s` (%+.1f rounds)" % [cid, float(lr["delta"])])
		if int(ci["offered"]) >= 30 and float(ci["pick_rate"]) < 0.10:
			neverpick.append("`%s` (%s%%)" % [cid, _f(100.0 * float(ci["pick_rate"]), 0)])
	out.append("- **Cards that significantly raise survival (random-policy lift, owned at round %d):** %s." % [LANDMARK, ", ".join(strong) if not strong.is_empty() else "none detected"])
	out.append("- **Cards that significantly lower it:** %s." % (", ".join(useless) if not useless.is_empty() else "none detected"))
	out.append("- **Cards almost never picked by any scored policy (<10%% pick rate):** %s." % (", ".join(neverpick) if not neverpick.is_empty() else "none"))
	var cstrong: PackedStringArray = PackedStringArray()
	var cweak: PackedStringArray = PackedStringArray()
	for tid: String in tech_info:
		var lr2: Dictionary = (tech_info[tid] as Dictionary)["rand"]
		if int(lr2["n1"]) >= 10 and int(lr2["n0"]) >= 10:
			if absf(float(lr2["delta"])) > 2.0 * float(lr2["se"]):
				if float(lr2["delta"]) > 0.0:
					cstrong.append("`%s` (%+.1f rounds)" % [tid, float(lr2["delta"])])
				else:
					cweak.append("`%s` (%+.1f rounds)" % [tid, float(lr2["delta"])])
	out.append("- **Tech that significantly raises survival (random-policy lift):** %s." % (", ".join(cstrong) if not cstrong.is_empty() else "none detected"))
	out.append("- **Tech that significantly lowers it:** %s." % (", ".join(cweak) if not cweak.is_empty() else "none detected"))
	var low_end: PackedStringArray = PackedStringArray()
	for tid2: String in tech_info:
		if float((tech_info[tid2] as Dictionary)["end"]) < 0.25:
			low_end.append("`%s`" % tid2)
	if not low_end.is_empty():
		out.append("- **Tech owned by fewer than 25%% of players at the end:** %s." % ", ".join(low_end))
	return out


# ======================================================================== helpers

## Outcome lift of "owns" vs "does not own" among rows with a landmark build. `metric` is a row key
## ("reached" or "won"). Returns {n1, n0, m1, m0, delta, se}.
func _lift(rows: Array, owns: Callable, metric: String) -> Dictionary:
	var a: Array = []
	var b: Array = []
	for p: Dictionary in rows:
		if p["b5"] == null:
			continue
		var y: float = (1.0 if bool(p["won"]) else 0.0) if metric == "won" else float(p[metric])
		if bool(owns.call(p)):
			a.append(y)
		else:
			b.append(y)
	var m1: float = _mean(a)
	var m0: float = _mean(b)
	var se: float = 0.0
	if a.size() > 1 and b.size() > 1:
		se = sqrt(_var(a) / a.size() + _var(b) / b.size())
	return {"n1": a.size(), "n0": b.size(), "m1": m1, "m0": m0, "delta": (m1 - m0) if (a.size() > 0 and b.size() > 0) else 0.0, "se": se}


func _lf(l: Dictionary, digits: int, scale: float = 1.0, unit: String = "") -> String:
	if int(l["n1"]) < 3 or int(l["n0"]) < 3:
		return "n/a (%d)" % int(l["n1"])
	var d: float = float(l["delta"]) * scale
	var flag: String = "*" if absf(float(l["delta"])) > 2.0 * float(l["se"]) else ""
	return "%s%s%s (n=%d)%s" % ["%+.*f" % [digits, d], unit, flag, int(l["n1"]), ""]


func _lc(l: Dictionary) -> String:
	return "%.4f,%.4f,%d" % [float(l["delta"]), float(l["se"]), int(l["n1"])]


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: float = 0.0
	for x in a:
		s += float(x)
	return s / a.size()


static func _var(a: Array) -> float:
	if a.size() < 2:
		return 0.0
	var m: float = _mean(a)
	var s: float = 0.0
	for x in a:
		s += (float(x) - m) * (float(x) - m)
	return s / (a.size() - 1)


static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	var c: Array = a.duplicate()
	c.sort()
	var idx: float = q * (c.size() - 1)
	var lo: int = int(floor(idx))
	var hi: int = int(ceil(idx))
	return float(c[lo]) + (float(c[hi]) - float(c[lo])) * (idx - lo)


static func _f(x: Variant, digits: int) -> String:
	return "%.*f" % [digits, float(x)]


static func _bar(n: int, total: int) -> String:
	var k: int = roundi(40.0 * float(n) / maxf(total, 1))
	return "#".repeat(k)


static func _table(header: Array, rows: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	out.append("| " + " | ".join(PackedStringArray(header.map(func(x: Variant) -> String: return str(x)))) + " |")
	out.append("|" + "---|".repeat(header.size()))
	for r: Array in rows:
		out.append("| " + " | ".join(PackedStringArray(r.map(func(x: Variant) -> String: return str(x)))) + " |")
	return out


static func _save_lines(path: String, lines: PackedStringArray) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
