extends SceneTree
## Dev probe: steps a boss scenario headless and prints, per tick, the boss state and markers (to pick screenshot
## ticks). godot --headless --path game -s res://tools/boss_probe.gd -- --scenario=boss_colossus --ticks=300


func _init() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var name: String = args.get("scenario", "boss_tripod")
	var w: SimWorld = Scenarios.build(name, int(args.get("seed", "1")))
	for t in int(args.get("ticks", "300")):
		Scenarios.step(name, w)
		var marks: Array = []
		for m in w.boss_marks:
			marks.append("%d:%d/%d" % [m["k"], m["left"], m["total"]])
		var evs: Array = []
		for e in w.events:
			if str(e["type"]).begins_with("boss"):
				evs.append(e["type"])
		if not marks.is_empty() or not evs.is_empty():
			print("t%d st%d ph%d hp%.2f marks %s ev %s" % [w.tick, w.boss_state, w.boss_phase, w.boss_hp_frac, marks, evs])
	quit()
