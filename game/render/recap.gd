class_name Recap
extends RefCounted
## "Last round" recap for the workshop (playtest round 1 #2): what wrecked a rig, damage taken by
## source, earnings, fuel, and a doctrine hint when one source dominates. Reads `round_stats` (in the
## snapshot outside combat) and the WorldView logs (the killer's weapon comes from the kill feed).

const DOMINANT := 0.45  ## share of the damage taken that makes a source "dominant"
const HINT_MIN_HP := 0.35  ## ...if at least this fraction of max hp was lost (or the rig was wrecked)


static func total_taken(v: SimVehicle) -> float:
	var taken: Dictionary = v.round_stats.get("taken", {})
	var t: float = 0.0
	for k: String in taken:
		t += float(taken[k])
	return t


## Damage taken as bar segments, biggest first: {key, label, short, hp, frac, color, paint (-1 =
## alien)}. Rival damage is split per attacker (paint colour), the rest of "rival" is "RIVALS".
static func segments(w: SimWorld, v: SimVehicle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var taken: Dictionary = v.round_stats.get("taken", {})
	var total: float = total_taken(v)
	if total <= 0.0:
		return out
	for k: String in UiKit.TAKEN_KEYS:
		var hp: float = float(taken.get(k, 0.0))
		if hp > 0.0:
			out.append({"key": k, "label": UiKit.TAKEN_LABELS[k], "short": UiKit.TAKEN_SHORT[k], "hp": hp,
				"frac": hp / total, "color": UiKit.TAKEN_COLORS[k], "paint": -1, "id": -1})
	var rival: float = float(taken.get("rival", 0.0))
	var tp: Dictionary = v.round_stats.get("taken_players", {})
	for id: Variant in tp:
		var hp: float = minf(float(tp[id]), rival)
		var av: SimVehicle = UiKit.vehicle_by_id(w, int(id))
		if hp <= 0.0 or av == null:
			continue
		rival -= hp
		out.append({"key": "rival", "label": UiKit.player_name(av), "short": UiKit.player_name(av), "hp": hp,
			"frac": hp / total, "color": UiKit.bar_color(av.color_index), "paint": av.color_index, "id": av.id})
	if rival > 0.5:
		out.append({"key": "rival", "label": "RIVALS", "short": "RIVALS", "hp": rival, "frac": rival / total,
			"color": Gfx.UI_BAD, "paint": -1, "id": -1})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["hp"]) > float(b["hp"]))
	return out


## Share of the damage per source group (boulder, mite, spit = spitter + acid, rival).
static func groups(v: SimVehicle) -> Dictionary:
	var taken: Dictionary = v.round_stats.get("taken", {})
	var total: float = maxf(total_taken(v), 0.001)
	return {
		"boulder": float(taken.get("boulder", 0.0)) / total,
		"mite": float(taken.get("mite", 0.0)) / total,
		"spit": (float(taken.get("spitter", 0.0)) + float(taken.get("acid", 0.0))) / total,
		"rival": float(taken.get("rival", 0.0)) / total,
	}


static func deaths(v: SimVehicle) -> Array:
	return v.round_stats.get("deaths", [])


## The rig that dealt `v` the most damage this round (-1 = none).
static func top_attacker(v: SimVehicle) -> int:
	var tp: Dictionary = v.round_stats.get("taken_players", {})
	var best: int = -1
	var best_hp: float = 0.0
	for id: Variant in tp:
		if float(tp[id]) > best_hp:
			best_hp = float(tp[id])
			best = int(id)
	return best


## Weapon index of the latest kill of `victim` by `killer` in round `rnd` (from the kill feed; -1 = unknown).
static func killer_weapon(view: WorldView, victim: int, killer: int, rnd: int) -> int:
	if view == null:
		return -1
	for i in range(view.kill_log.size() - 1, -1, -1):
		var e: Dictionary = view.kill_log[i]
		if int(e["victim"]) == victim and int(e["killer"]) == killer and int(e["round"]) == rnd:
			return int(e["weapon"])
	return -1


## Doctrine hint for the dominant damage source: {group, text, options: [{label, cmd}]} or {}.
## Options are doctrine commands (sent through the workshop's send_command); none = advice only.
static func hint(w: SimWorld, v: SimVehicle) -> Dictionary:
	if v.round_stats.is_empty() or v.eliminated:
		return {}
	var total: float = total_taken(v)
	if deaths(v).is_empty() and total < v.max_hp * HINT_MIN_HP:
		return {}
	var g: Dictionary = groups(v)
	var top: String = ""
	for k: String in g:
		if float(g[k]) >= DOMINANT and (top == "" or float(g[k]) > float(g[top])):
			top = k
	if top == "":
		return {}
	var drive: String = str(v.doctrine["drive"])
	var target: String = str(v.doctrine["target"])
	var kite := {"label": "SET KITE", "cmd": {"type": "set_drive", "value": "kite"}}
	var share: String = UiKit.pct(float(g[top]))
	match top:
		"boulder":
			if drive != "kite":
				return {"group": top, "text": "BOULDERS %s - TRY KITE, KEEP YOUR DISTANCE" % share, "options": [kite]}
			return {"group": top, "text": "BOULDERS %s EVEN ON KITE - BOLT ON ARMOUR" % share, "options": []}
		"mite":
			if drive == "charge":
				return {"group": top, "text": "MITES %s - A CHARGER GETS SWARMED, TRY CIRCLE" % share,
					"options": [{"label": "SET CIRCLE", "cmd": {"type": "set_drive", "value": "circle"}}]}
			if target != "nearest":
				return {"group": top, "text": "MITES %s - SHOOT WHAT IS CLOSEST" % share,
					"options": [{"label": "TARGET NEAREST", "cmd": {"type": "set_target", "value": "nearest"}}]}
			return {"group": top, "text": "MITES %s - SPIKES AND ARMOUR SHRUG THEM OFF" % share, "options": []}
		"spit":
			if drive != "charge":
				return {"group": top, "text": "ACID %s - TRY CHARGE, CLOSE IN ON SPITTERS" % share,
					"options": [{"label": "SET CHARGE", "cmd": {"type": "set_drive", "value": "charge"}}]}
			return {"group": top, "text": "ACID %s - ARMOUR SOAKS EVERY GLOB" % share, "options": []}
		"rival":
			var av: SimVehicle = UiKit.vehicle_by_id(w, top_attacker(v))
			var who: String = UiKit.player_name(av) if av != null else "RIVALS"
			var opts: Array = []
			if target != "players_first":
				opts.append({"label": "TARGET PLAYERS 1ST", "cmd": {"type": "set_target", "value": "players_first"}})
			if drive != "kite":
				opts.append(kite)
			var text: String = "%s HUNTS YOU - FIGHT BACK OR KITE AWAY" % who if not opts.is_empty() \
				else "%s HUNTS YOU - ARMOUR UP" % who
			return {"group": top, "text": text, "options": opts, "rival": av.id if av != null else -1}
	return {}


## True when every option of `h` is already the vehicle's doctrine (the hint was applied).
static func applied(v: SimVehicle, opt: Dictionary) -> bool:
	var cmd: Dictionary = opt["cmd"]
	var key: String = "drive" if cmd["type"] == "set_drive" else "target"
	return str(v.doctrine[key]) == str(cmd["value"])
