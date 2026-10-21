class_name TechGuide
extends RefCounted
## Client-side guidance for the tech tree (tech tree v2.3, section 8; design doc section 5b): the one-line
## pitch per branch, a "you see" and a "good if you ..." line per node, the player's own goals (nodes
## marked in the TECH view; the tree lights the way to them), the three build ideas that can seed those
## goals, the build's identity from where its scrap went, glossary terms, and the net preview of a node on
## your own rig. Render only: the preview runs on a scratch copy of the vehicle and never touches the real one.

## The branch's signature mechanic in one sentence (shown under the branch name).
const PITCH := {
	"ballistics": "LOAD DIFFERENT AMMO FOR DIFFERENT FOES",
	"engineering": "YOUR RIG GROWS: MORE GUNS AND HP, BUT HEAVIER",
	"propulsion": "SPEED BUILDS MOMENTUM, MOMENTUM FEEDS RAMS AND NITRO",
	"electronics": "YOUR RIG LEARNS NEW RULES AND ABILITIES",
	"salvage": "MORE SCRAP, CONTRACTS, AND SCRAP AS A WEAPON",
}

## What the node looks like in the fight ("Sichtbar als").
const SEEN := {
	"ballistics_ammo_bench": "BURNING TARGETS", "ballistics_belt_feed": "SHRAPNEL SPARKS",
	"ballistics_heavy_shells": "RECOIL AND HIT FLASHES", "ballistics_tables": "INSTANT AMMO SWAPS",
	"ballistics_hot_loads": "STUTTERING, SMOKING BARRELS", "ballistics_scatter": "PELLET BURSTS",
	"ballistics_napalm": "FIRE JUMPING THROUGH THE PACK", "ballistics_he": "EXPLOSIONS",
	"ballistics_tungsten": "GLOWING EMBER TRAILS", "ballistics_mixed_belts": "TWO-COLOUR MUZZLE FLASH",
	"ballistics_glowing": "RED-HOT BARRELS", "ballistics_one_shot": "KILL NUMBERS, CAMERA KICK",
	"engineering_frame": "WELD SEAMS", "engineering_spikes": "SPIKES ON THE SKIRTS",
	"engineering_welder": "WELDING SPARKS", "engineering_pickup": "A BIGGER RIG",
	"engineering_scrap_armour": "PLATES FLYING OFF", "engineering_reactive": "FLASHING PLATES",
	"engineering_drone": "A DRONE FLYING ALONG", "engineering_dozer": "A BLADE ON THE FRONT",
	"engineering_truck": "A TRUCK", "engineering_roll_cage": "A ROLL CAGE",
	"engineering_war_rig": "A TRAILER", "engineering_featherweight": "QUICK SIDE-HOPS",
	"propulsion_tuned": "THE MOMENTUM BAR", "propulsion_bumper": "SPARKS ON EVERY RAM",
	"propulsion_drift": "DUST PLUMES IN CURVES", "propulsion_nitro": "AN EXHAUST FLAME",
	"propulsion_dirty_fuel": "SMOKE AND BACKFIRES", "propulsion_battering": "ENEMIES FLYING",
	"propulsion_ghost": "AFTERIMAGES", "propulsion_slipstream": "OIL SLICKS",
	"propulsion_turbine": "BOOST RINGS", "propulsion_sidecar": "A SIDECAR GUNNER",
	"propulsion_juggernaut": "A GLOWING FRONT", "propulsion_phantom": "A GHOST DECOY",
	"electronics_rangefinder": "A LASER DOT ON THE TARGET", "electronics_radar": "WARNING MARKERS",
	"electronics_relay": "A TARGET RING", "electronics_targeting": "MORE ROOM IN THE RULE EDITOR",
	"electronics_aux_mount": "A MAKESHIFT GUN MOUNT", "electronics_emp": "A SHOCK RING",
	"electronics_smoke": "A SMOKE CLOUD", "electronics_hunter": "SKULLS OVER THE WOUNDED",
	"electronics_neural": "A STORM OF MUZZLE FLASH", "electronics_overclock": "A SPARKING ANTENNA",
	"electronics_swarm": "RED LASERS ON ONE TARGET", "electronics_jammer": "A FLICKERING JAM FIELD",
	"salvage_hooks": "A CONTRACT BANNER", "salvage_haggler": "A CLAMPED CARD",
	"salvage_lucky": "A GOLDEN SHIMMER", "salvage_loan": "A DEBT LINE",
	"salvage_black_market": "TWO CONTRACT OFFERS", "salvage_insurance": "SCRAP RAINING FROM YOUR WRECK",
	"salvage_jerrycans": "JERRYCANS, THEN A BIG BANG", "salvage_press": "SAW BLADES",
	"salvage_hoarder": "A SCRAP PILE ON THE ROOF", "salvage_crane": "A MAGNET CRANE",
	"salvage_bounty": "BOUNTIES OVER THE LEADER", "salvage_baron": "A GROWING GOLD CHAIN",
	"salvage_raider": "SCRAP SPRAYING FROM RIVALS",
	"fusion_thermite": "BIGGER, BURNING SPARK BLASTS", "fusion_spotter": "SHELLS SNAPPING ONTO SPITTERS",
	"fusion_hot_rod": "REPAIR SPARKS IN DRIFTS", "fusion_barbed": "SCRAP FROM SPIKE KILLS",
	"fusion_lucky_strike": "A FOURTH CARD NOW AND THEN", "fusion_fortified": "REPAIR GLOW AFTER FOCUS KILLS",
	"fusion_burning_wake": "A BURNING TRAIL", "fusion_war_machine": "SHOCKWAVE RINGS ON RAMS",
	"fusion_scrap_storm": "SCRAP SHRAPNEL BURSTS", "fusion_junkyard": "THE DRONE DIVES AT ENEMIES",
	"fusion_thunderclap": "CHAIN LIGHTNING ON CONTACT KILLS",
}

## "GOOD IF YOU ..." (who should take it).
const GOOD_IF := {
	"ballistics_ammo_bench": "WANT EVERY GUN TO SET ALIENS ON FIRE", "ballistics_belt_feed": "RUN MACHINE GUNS OR FLAMERS",
	"ballistics_heavy_shells": "RUN CANNONS OR SCATTER GUNS", "ballistics_tables": "SWAP AMMO OR STACK AMMO EFFECTS",
	"ballistics_hot_loads": "FIGHT IN SHORT BURSTS", "ballistics_scatter": "SHOOT INTO DENSE SWARMS",
	"ballistics_napalm": "FACE BIG PACKS OF MITES", "ballistics_he": "RUN A CANNON AND BURN THINGS FIRST",
	"ballistics_tungsten": "SHOOT DOWN LINES OF ENEMIES", "ballistics_mixed_belts": "WANT TWO AMMO EFFECTS AT ONCE",
	"ballistics_glowing": "FACE ENDLESS SWARMS", "ballistics_one_shot": "HUNT BOULDERS AND ELITES",
	"engineering_frame": "TAKE A LOT OF HITS EARLY", "engineering_spikes": "DRIVE INTO THE PACK",
	"engineering_welder": "WANT TO OUTLAST LONG FIGHTS", "engineering_pickup": "WANT A THIRD GUN",
	"engineering_scrap_armour": "TAKE MANY SMALL HITS", "engineering_reactive": "FACE SPITTERS AND THEIR ACID",
	"engineering_drone": "PLAY SAFE AND OUTLAST", "engineering_dozer": "CHARGE THROUGH MITES",
	"engineering_truck": "WANT THE BIGGEST HP POOL", "engineering_roll_cage": "WANT ARMOUR WITHOUT THE WEIGHT",
	"engineering_war_rig": "WANT A FOURTH GUN AND A WALL OF HP", "engineering_featherweight": "TRUST SPEED AND DODGES OVER HP",
	"propulsion_tuned": "KEEP MOVING FAST", "propulsion_bumper": "RAM A LOT",
	"propulsion_drift": "CIRCLE OR KITE", "propulsion_nitro": "WANT BURSTS OF SPEED",
	"propulsion_dirty_fuel": "RAM AND NITRO ALL THE TIME", "propulsion_battering": "RAM YOUR WAY OUT OF SWARMS",
	"propulsion_ghost": "STAY FAST UNDER FIRE", "propulsion_slipstream": "KITE SWARMS BEHIND YOU",
	"propulsion_turbine": "KEEP MOMENTUM FULL", "propulsion_sidecar": "WANT ONE MORE GUN WITHOUT WEIGHT",
	"propulsion_juggernaut": "CHARGE AND NEVER BACK OFF", "propulsion_phantom": "NITRO OUT OF TROUBLE OFTEN",
	"electronics_rangefinder": "WANT ONE MORE RULE", "electronics_radar": "FIGHT RIVALS OR SPITTERS",
	"electronics_relay": "WANT EVERY GUN ON ONE TARGET", "electronics_targeting": "WRITE DETAILED RULES",
	"electronics_aux_mount": "WANT A GUN SLOT EARLY", "electronics_emp": "GET SWARMED OR FIGHT RIVALS UP CLOSE",
	"electronics_smoke": "OFTEN DROP TO LOW HP", "electronics_hunter": "FINISH OFF WOUNDED RIGS",
	"electronics_neural": "WANT A FIRE-RATE BURST ON BIG WAVES", "electronics_overclock": "LEAN ON ABILITIES",
	"electronics_swarm": "RUN MANY GUNS", "electronics_jammer": "FIGHT RIVALS UP CLOSE",
	"salvage_hooks": "LIKE SIDE JOBS FOR SCRAP", "salvage_haggler": "REROLL A LOT FOR ONE CARD",
	"salvage_lucky": "WANT RARE CARDS AND BIGGER CONTRACTS", "salvage_loan": "NEED SCRAP NOW AND CAN PAY LATER",
	"salvage_black_market": "SAVE SCRAP FOR INTEREST", "salvage_insurance": "GET WRECKED A LOT ANYWAY",
	"salvage_jerrycans": "RUN LOW ON FUEL", "salvage_press": "HAVE CARDS YOU NO LONGER NEED",
	"salvage_hoarder": "SIT ON A BIG PILE OF SCRAP", "salvage_crane": "WANT THE MOST SCRAP PER KILL",
	"salvage_bounty": "HUNT THE LEADER", "salvage_baron": "HOLD LOTS OF SCRAP AND RARELY DIE",
	"salvage_raider": "TRADE SHOTS WITH RIVALS",
	"fusion_thermite": "RAM WITH A BELT-FED GUN", "fusion_spotter": "SHOOT SPITTERS WITH CANNONS",
	"fusion_hot_rod": "DRIFT IN CIRCLES", "fusion_barbed": "KILL WITH SPIKES",
	"fusion_lucky_strike": "FOCUS FIRE", "fusion_fortified": "FOCUS FIRE AND TANK",
	"fusion_burning_wake": "DRIFT THROUGH PACKS", "fusion_war_machine": "RAM WITH SPIKES",
	"fusion_scrap_storm": "KILL WITH SPLASH DAMAGE", "fusion_junkyard": "FOCUS FIRE WITH A DRONE",
	"fusion_thunderclap": "KILL BY CONTACT",
}

## Build ideas: two branches, an ordered node path (requirements always come first) and a cheat sheet.
## Picking one only seeds the player's goals (idea_goals); the tree itself never narrows to it.
const TEMPLATES: Array = [
	{"id": "firebrand", "name": "FIREBRAND", "branches": ["ballistics", "propulsion"],
		"blurb": "BURN EVERYTHING, DRIFT THROUGH THE FIRE",
		"path": ["ballistics_ammo_bench", "propulsion_tuned", "ballistics_belt_feed", "propulsion_drift",
			"ballistics_tables", "ballistics_napalm", "fusion_burning_wake", "propulsion_nitro", "ballistics_tungsten",
			"propulsion_slipstream", "propulsion_turbine", "ballistics_glowing", "propulsion_phantom"],
		"cheat": ["WORKSHOP 1: BUY AMMO BENCH + TUNED ENGINE", "WORKSHOP 2: BUY BELT FEED, THEN DRIFT TUNING",
			"WORKSHOP 3+: TABLES > NAPALM MIX > BURNING WAKE"]},
	{"id": "fortress", "name": "FORTRESS", "branches": ["engineering", "electronics"],
		"blurb": "A BIG, SELF-REPAIRING RIG WITH SMART GUNS",
		"path": ["engineering_frame", "electronics_rangefinder", "engineering_welder", "electronics_relay",
			"fusion_fortified", "engineering_pickup", "electronics_targeting", "engineering_drone", "fusion_junkyard",
			"engineering_truck", "electronics_neural", "engineering_war_rig", "electronics_swarm"],
		"cheat": ["WORKSHOP 1: BUY WELDED FRAME + RANGEFINDER", "WORKSHOP 2: BUY FIELD WELDER + RELAY",
			"WORKSHOP 3+: FORTIFIED RELAY > PICKUP > DRONE"]},
	{"id": "scrapper", "name": "SCRAPPER", "branches": ["salvage", "ballistics"],
		"blurb": "CONTRACTS AND INTEREST, THEN SCRAP AS AMMO",
		"path": ["salvage_hooks", "ballistics_ammo_bench", "salvage_lucky", "ballistics_heavy_shells",
			"salvage_black_market", "salvage_press", "fusion_scrap_storm", "ballistics_tables", "ballistics_he",
			"salvage_crane", "ballistics_tungsten", "salvage_baron"],
		"cheat": ["WORKSHOP 1: BUY SCRAP HOOKS, TAKE A CONTRACT", "WORKSHOP 2: BUY AMMO BENCH + LUCKY CHARM",
			"WORKSHOP 3+: HEAVY SHELLS > BLACK MARKET > PRESS"]},
]

## Jargon: [term, one-line explanation]. A word matches a term word it starts with (BURNING -> BURN).
const GLOSSARY: Array = [
	["INTEREST CAP", "THE MOST INTEREST YOUR HELD SCRAP CAN EARN AFTER A ROUND"],
	["RULE SLOT", "ROOM FOR ONE IF-THEN RULE IN YOUR RIG'S DOCTRINE (RULES VIEW)"],
	["MOMENTUM", "A 0-100 BAR: FILLS AT TOP SPEED, DRAINS WHEN YOU STOP OR GET HIT"],
	["KITE", "DRIVE STYLE: KEEP YOUR DISTANCE AND SHOOT WHILE BACKING OFF"],
	["PIERCE", "A SHOT FLIES ON THROUGH THIS MANY MORE ENEMIES"],
	["SPITTER", "ALIEN THAT KEEPS ITS DISTANCE AND LOBS ACID"],
	["LEADER", "THE RIG WITH THE TOP SCORE: MARKED WITH A SKULL, WORTH A BOUNTY"],
	["AMMO", "WHAT EACH GUN FIRES; SWITCH IT PER GUN IN PARTS OR BY A RULE"],
	["CONTRACT", "A JOB OFFERED IN THE WORKSHOP, PAID WHEN THE NEXT ROUND ENDS"],
	["BURN", "DAMAGE OVER TIME: A QUARTER OF THE HIT AGAIN OVER 2 S"],
]

const ABILITY_NAMES := {"nitro": "NITRO", "emp": "EMP", "smoke": "SMOKE", "salvo": "SALVO"}
## The fixed auto-cast rule of each ability (Abilities.auto_wanted), for its tooltip.
const ABILITY_AUTO := {
	"nitro": "AUTO: 50 MOMENTUM AND A TARGET NEAR, OR LOW HP",
	"emp": "AUTO: 5 ALIENS WITHIN 120 PX",
	"smoke": "AUTO: HP BELOW 40%",
	"salvo": "AUTO: 15 ALIENS OR 3 BOULDERS NEAR",
}
const AMMO_NAMES := {"fire": "FIRE", "shrapnel": "SHRAPNEL", "ap": "AP"}
const AMMO_SHORT := {"fire": "FIRE", "shrapnel": "SHRAP", "ap": "AP"}

static var _goals: Dictionary = {}  ## world instance id -> Array[String]: goals marked this match
static var _pv_key: String = ""
static var _pv: Dictionary = {}


# ---------------------------------------------------------------- ideas and goals

static func template_by_id(id: String) -> Dictionary:
	for t: Dictionary in TEMPLATES:
		if t["id"] == id:
			return t
	return {}


## The goals an idea seeds: the deepest node of each of its branches on its path, then its fusions.
static func idea_goals(t: Dictionary) -> Array[String]:
	var deepest := {}
	var fus: Array[String] = []
	for id: String in t.get("path", []):
		if Tech.is_fusion(id):
			fus.append(id)
			continue
		var b: String = str(Tech.def(id)["branch"])
		if not deepest.has(b) or int(Tech.def(id)["tier"]) > int(Tech.def(str(deepest[b]))["tier"]):
			deepest[b] = id
	var out: Array[String] = []
	for b: String in t.get("branches", []):
		if deepest.has(b):
			out.append(str(deepest[b]))
	out.append_array(fus)
	return out


## The goals marked on `v` this match, built ones left out (they drop off once owned).
static func goals(w: SimWorld, v: SimVehicle) -> Array[String]:
	var out: Array[String] = []
	if w == null:
		return out
	var key: int = w.get_instance_id()
	var kept: Array[String] = []
	for id: String in _goals.get(key, []):
		if not v.tech.has(id):
			kept.append(id)
	_goals[key] = kept
	out.append_array(kept)
	return out


static func is_goal(w: SimWorld, id: String) -> bool:
	return w != null and (_goals.get(w.get_instance_id(), []) as Array).has(id)


## Marks or unmarks `id` as a goal; returns true when it is a goal now.
static func toggle_goal(w: SimWorld, id: String) -> bool:
	if w == null or Tech.def(id).is_empty():
		return false
	var key: int = w.get_instance_id()
	var g: Array[String] = []
	g.append_array(_goals.get(key, []))
	var on: bool = not g.has(id)
	if on:
		g.append(id)
	else:
		g.erase(id)
	_goals[key] = g
	return on


static func set_goals(w: SimWorld, ids: Array[String]) -> void:
	if w != null:
		var g: Array[String] = []
		g.append_array(ids)
		_goals[w.get_instance_id()] = g


## The node to buy next towards the goals ("" = no goal reachable without a swap): the first step of the
## first goal whose path needs no sibling swap.
static func next_step(v: SimVehicle, goal_ids: Array[String]) -> String:
	for id in goal_ids:
		if v.tech.has(id) or Tech.blocked_by(v, id) != "":
			continue
		var steps: Array[String] = build_path(v, id, goal_ids)
		if steps.is_empty():
			continue
		var ok: bool = true
		for s in steps:
			if Tech.blocked_by(v, s) != "":
				ok = false
		if ok:
			return steps[0]
	return ""


## Every node still to build for all goals, each once, in buy order.
static func goals_path(v: SimVehicle, goal_ids: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for id in goal_ids:
		for p in build_path(v, id, goal_ids):
			if not out.has(p):
				out.append(p)
	return out


## Base scrap built into each branch (a fusion counts half for each of its two branches).
static func invested(v: SimVehicle) -> Dictionary:
	var out := {}
	for b in Tech.BRANCHES:
		out[b] = 0
	for id in v.tech:
		if Tech.is_fusion(id):
			for rq in Tech.requirements(id):
				var rb: String = str(Tech.def(str(rq))["branch"])
				out[rb] = int(out[rb]) + Tech.cost(id) / 2
		else:
			var b2: String = str(Tech.def(id)["branch"])
			out[b2] = int(out[b2]) + Tech.cost(id)
	return out


## The build's two main branches by scrap built in, biggest first ([] = nothing built; one entry when
## only one branch has scrap in it).
static func main_branches(v: SimVehicle) -> Array[String]:
	var inv: Dictionary = invested(v)
	var order: Array[String] = []
	for b in Tech.BRANCHES:
		if int(inv[b]) > 0:
			order.append(b)
	order.sort_custom(func(x: String, y: String) -> bool: return int(inv[x]) > int(inv[y]))
	if order.size() > 2:
		order.resize(2)
	return order


## The idea whose two branches are the build's two main ones ({} = none).
static func idea_like(v: SimVehicle) -> Dictionary:
	var mb: Array[String] = main_branches(v)
	if mb.size() < 2:
		return {}
	for t: Dictionary in TEMPLATES:
		if (t["branches"] as Array).has(mb[0]) and (t["branches"] as Array).has(mb[1]):
			return t
	return {}


# ---------------------------------------------------------------- paths and previews

## The nodes `v` still has to build to own `id`, in buy order (`id` last; [] = owned). For an any-of
## requirement an active candidate counts, else an owned one, else one not locked out by a sibling.
static func build_path(v: SimVehicle, id: String, prefer: Array = []) -> Array[String]:
	var out: Array[String] = []
	_walk(v, id, out, 0, prefer)
	return out


static func _walk(v: SimVehicle, id: String, out: Array[String], depth: int, prefer: Array) -> void:
	if depth > 12 or out.has(id) or Tech.active(v, id):
		return
	var d: Dictionary = Tech.def(id)
	if d.is_empty():
		return
	for r in d["requires"]:
		_walk(v, str(r), out, depth + 1, prefer)
	var any: Array = d["any"]
	if not any.is_empty():
		var pick: String = ""
		for a in any:
			if Tech.active(v, str(a)):
				pick = "-"
				break
		if pick == "":
			for a in any:
				if v.tech.has(str(a)) or out.has(str(a)):
					pick = str(a)
					break
		if pick == "":
			for a in any:
				if Tech.blocked_by(v, str(a)) == "" and prefer.has(str(a)):
					pick = str(a)
					break
		if pick == "":
			for a in any:
				if Tech.blocked_by(v, str(a)) == "":
					pick = str(a)
					break
		if pick == "":
			pick = str(any[0])
		if pick != "-":
			_walk(v, pick, out, depth + 1, prefer)
	if not v.tech.has(id):
		out.append(id)


## Scrap the build path costs in all.
static func path_cost(v: SimVehicle, path: Array[String]) -> int:
	var total: int = 0
	for id in path:
		total += Tech.price(v, id)
	return total


## A scratch copy of `v` with the state the tech and stat code reads (cards, tech, ammo, abilities).
static func scratch(v: SimVehicle) -> SimVehicle:
	var s := SimVehicle.new(v.id, v.peer_id, Vector2.ZERO)
	s.cards = v.cards.duplicate()
	s.tech = v.tech.duplicate()
	s.tech_dormant = v.tech_dormant.duplicate()
	s.tech_round = v.tech_round.duplicate()
	s.respecs = v.respecs
	s.shed = v.shed
	s.ammo = v.ammo.duplicate(true)
	s.ammo_known = v.ammo_known.duplicate()
	s.abilities = v.abilities.duplicate()
	s.scrap = v.scrap
	Cards.recompute(s)
	return s


## Ids that are active on `v` but no longer on `s` (greyed out or gone dormant by a change).
static func lost(v: SimVehicle, s: SimVehicle) -> Array[String]:
	var out: Array[String] = []
	for id in v.tech:
		if Tech.active(v, id) and not Tech.active(s, id):
			out.append(id)
	return out


## What swapping `from` for `to` would grey out (nodes left without a requirement, fusions going dormant).
static func greys_out(v: SimVehicle, from: String, to: String) -> Array[String]:
	var s: SimVehicle = scratch(v)
	s.scrap = 1 << 30
	if not Tech.respec(s, from, to, int(v.tech_round.get(from, 0))):
		return []
	var out: Array[String] = lost(v, s)
	out.erase(from)
	return out


## The comparable numbers of a rig: key -> [label, value, format ("int", "num", "pct", "x")].
static func stats(v: SimVehicle) -> Dictionary:
	var out := {}
	var up: float = 1.0
	if float(v.tech_fx.get("overheat", 0.0)) > 0.0:
		up = float(SimWorld.OVERHEAT_FIRE_TICKS) / float(SimWorld.OVERHEAT_FIRE_TICKS + SimWorld.OVERHEAT_PAUSE_TICKS)
	elif float(v.tech_fx.get("jam", 0.0)) > 0.0:
		up = float(SimWorld.JAM_FIRE_TICKS) / float(SimWorld.JAM_FIRE_TICKS + SimWorld.JAM_PAUSE_TICKS)
	var scatter: bool = float(v.tech_fx.get("scatter", 0.0)) > 0.0
	for w: Dictionary in v.weapons:
		var kind: String = str(w["kind"])
		var dps: float = float(w["damage"]) * float(w["pellets"]) * float(SimWorld.TICK_RATE) / maxf(float(w["cooldown_ticks"]), 1.0) * up
		if scatter and kind != "shotgun":
			dps *= 1.0 + float(SimWorld.SCATTER_PELLETS) * SimWorld.SCATTER_DAMAGE / float(SimWorld.SCATTER_EVERY)
		var ki: int = Cards.weapon_kind_index(kind)
		out["dps_" + kind] = ["%s DPS" % UiKit.weapon_short(ki), dps, "int"]
	out["hp"] = ["MAX HP", v.max_hp, "int"]
	out["armor"] = ["ARMOUR", v.armor, "num"]
	out["speed"] = ["SPEED", v.speed, "pct"]
	out["turn"] = ["TURNING", v.turn_rate, "pct"]
	out["regen"] = ["REPAIR HP/S", v.regen, "num"]
	out["range"] = ["RANGE", v.max_range(), "int"]
	out["slots"] = ["GUN SLOTS", float(v.weapon_slots), "int"]
	out["rules"] = ["RULE SLOTS", float(Doctrine.slots(v)), "int"]
	var ab: int = 0
	for a in v.abilities:
		ab += 1 if a != "" else 0
	out["abilities"] = ["ABILITIES", float(maxi(ab, Abilities.unlocked(v).size())), "int"]
	out["ram"] = ["RAM", v.ram_mult, "x"]
	out["contact"] = ["SPIKE DMG/TICK", v.contact_damage, "num"]
	out["scrap"] = ["SCRAP GAIN", v.scrap_mult, "x"]
	out["interest"] = ["INTEREST CAP", float(v.interest_cap), "int"]
	out["dodge"] = ["DODGE", float(v.tech_fx.get("dodge", 0.0)), "pct0"]
	return out


static func fmt(value: float, kind: String) -> String:
	match kind:
		"int":
			return str(roundi(value))
		"pct":
			return UiKit.pct(value)
		"pct0":
			return UiKit.pct(value)
		"x":
			return "X" + UiKit.num(snappedf(value, 0.01))
	return UiKit.num(snappedf(value, 0.1))


## Net preview of `id` on `v`: {"head": String, "rows": [[label, before, after, better: bool]], "note": String}.
## Buildable or locked nodes are bought on a scratch copy (with their missing path), a node locked by a
## sibling is swapped in, an owned one is compared against the rig without it.
static func preview(v: SimVehicle, id: String) -> Dictionary:
	var key: String = "%s|%s|%s|%s|%d|%s" % [id, str(v.tech), str(v.cards), str(v.tech_dormant), v.respecs, str(v.abilities)]
	if key == _pv_key:
		return _pv
	_pv_key = key
	var before: SimVehicle = scratch(v)
	var after: SimVehicle = scratch(v)
	after.scrap = 1 << 30
	var head: String = "IF YOU BUILD IT"
	var note: String = ""
	if v.tech.has(id):
		if not Tech.active(v, id):
			_pv = {"head": "ON YOUR RIG", "rows": [], "note": "NO EFFECT UNTIL %s IS BACK" % UiKit.tech_name(Tech.missing(v, id))}
			return _pv
		head = "WHAT IT GIVES YOUR RIG"
		before.tech.erase(id)
		Cards.recompute(before)
		after = scratch(v)
	elif Tech.blocked_by(v, id) != "":
		var from: String = Tech.blocked_by(v, id)
		head = "AFTER SWAPPING %s OUT" % str(Tech.def(from)["short"])
		if not Tech.respec(after, from, id, int(v.tech_round.get(from, 0))):
			_pv = {"head": head, "rows": [], "note": "SWAP NOT POSSIBLE: NEEDS %s" % UiKit.tech_name(Tech.missing(v, id))}
			return _pv
	else:
		var path: Array[String] = build_path(v, id)
		if path.size() > 1:
			head = "WITH ITS PATH (%d NODES)" % path.size()
		for p in path:
			var sib: String = Tech.blocked_by(after, p)
			if sib != "":  # the path runs through a choice locked by its sibling: swap it in
				if not Tech.respec(after, sib, p, int(v.tech_round.get(sib, 0))):
					note = "PATH NEEDS A SWAP THAT IS NOT POSSIBLE"
					break
				note = "INCLUDES SWAPPING %s OUT" % str(Tech.def(sib)["short"])
			elif not Tech.buy(after, p):
				note = "PATH BLOCKED"
				break
	var a: Dictionary = stats(before)
	var b: Dictionary = stats(after)
	var rows: Array = []
	for k: String in b:
		var nb: float = float((b[k] as Array)[1])
		var na: float = float((a[k] as Array)[1]) if a.has(k) else 0.0
		if absf(nb - na) < 0.004:
			continue
		var f: String = str((b[k] as Array)[2])
		var t0: String = fmt(na, f) if a.has(k) else "-"
		var t1: String = fmt(nb, f)
		if t0 == t1:
			continue
		rows.append([str((b[k] as Array)[0]), t0, t1, nb > na])
	if rows.is_empty() and note == "":
		note = "NO STAT CHANGE: IT ADDS A MECHANIC"
	_pv = {"head": head, "rows": rows, "note": note}
	return _pv


# ---------------------------------------------------------------- glossary

## Glossary hits in `text`: [[start char, length, glossary index]].
static func gloss_spans(text: String) -> Array:
	var out: Array = []
	var t: String = text.to_upper()
	var words: Array = []  # [start, word]
	var i: int = 0
	while i < t.length():
		while i < t.length() and not _letter(t.unicode_at(i)):
			i += 1
		var s: int = i
		while i < t.length() and (_letter(t.unicode_at(i)) or t[i] == "-"):
			i += 1
		if i > s:
			words.append([s, t.substr(s, i - s)])
	var k: int = 0
	while k < words.size():
		var hit: bool = false
		for gi in GLOSSARY.size():
			var parts: PackedStringArray = str(GLOSSARY[gi][0]).split(" ")
			if k + parts.size() > words.size():
				continue
			var ok: bool = true
			for p in parts.size():
				var wd: String = str(words[k + p][1])
				if not wd.begins_with(parts[p]) or wd.length() > parts[p].length() + 3:
					ok = false
					break
			if ok:
				var st: int = int(words[k][0])
				var last: Array = words[k + parts.size() - 1]
				out.append([st, int(last[0]) + str(last[1]).length() - st, gi])
				k += parts.size()
				hit = true
				break
		if not hit:
			k += 1
	return out


static func _letter(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
