class_name BotPolicy
extends RefCounted
## Deterministic workshop bots: decision policies that shop for one vehicle (card pick, rerolls,
## tech purchases, ready) and choose its doctrine. Used by the bot league (tools/bot_league.gd) for
## balance work, and meant to later drive AI opponents and an agent playtest harness.
##
## One BotPolicy instance drives ONE vehicle (it keeps a little per-workshop state). It reads
## `SimWorld` / `SimVehicle` and never mutates them: it only returns commands in the same format the
## network layer uses (see docs/architecture.md, "Round loop contract").
##
## Typical use (offline, sim only):
##   var bot := BotPolicy.create("balanced", match_seed + vehicle.id)
##   for cmd in bot.doctrine_commands(world, v): world.apply_command(v.peer_id, cmd)   # any phase
##   # once per workshop (world.phase == PHASE_WORKSHOP):
##   bot.workshop_commands(world, v)          # applies pick / reroll / buy_tech / ready itself
##
## Typical use (networked bot or agent): call `next_command(world, v)` and send the result through
## `NetSession.send_command`; call it again after the next snapshot until it returns {} (nothing
## more to do). It is stateless between calls except for reroll bookkeeping, so it is safe to call
## once per tick. It returns `{"type": "ready"}` last.
##
## Randomness comes from a policy-local RandomNumberGenerator seeded in `create()`, never from the
## world rng, so adding a bot never perturbs the sim's own random stream.
##
## Registry: `BotPolicy.names()` lists the policies, `BotPolicy.create(name, seed)` builds one,
## `BotPolicy.describe(name)` gives a one-line description.

const NEVER := -99.0  ## card score meaning "never take this"

# Card score presets (higher = better; unlisted ids get cfg["default_card"]).
const CARDS_BALANCED := {
	"mg": 5.0, "shotgun": 6.0, "cannon": 7.0, "flamer": 5.0,
	"steel_plates": 6.0, "spiked_plating": 4.0, "reinforced_hull": 6.0, "ablative_scrap": 5.0,
	"v8_engine": 4.0, "off_road_tyres": 3.0, "nitro": 3.0, "caterpillar_tracks": 4.0,
	"scrap_magnet": 5.0, "berserker": 3.0, "vulture": 3.0, "regenerator": 5.0,
}
const CARDS_DAMAGE := {
	"mg": 7.0, "shotgun": 8.0, "cannon": 9.0, "flamer": 7.0,
	"berserker": 4.0, "vulture": 4.0, "steel_plates": 2.0, "reinforced_hull": 2.0,
}
const CARDS_TANK := {
	"steel_plates": 9.0, "reinforced_hull": 9.0, "ablative_scrap": 8.0, "caterpillar_tracks": 7.0,
	"regenerator": 8.0, "spiked_plating": 6.0, "mg": 5.5, "shotgun": 6.0, "cannon": 6.5, "flamer": 5.0,
}
const CARDS_SPEED := {
	"v8_engine": 9.0, "nitro": 9.0, "off_road_tyres": 8.0, "steel_plates": 3.0,
	"reinforced_hull": 3.0, "mg": 5.5, "shotgun": 6.0, "cannon": 6.5, "flamer": 5.0,
}
const CARDS_HUNTER := {
	"mg": 7.0, "shotgun": 8.0, "cannon": 8.0, "flamer": 6.0, "vulture": 8.0, "berserker": 8.0,
	"spiked_plating": 7.0, "nitro": 5.0, "v8_engine": 5.0, "steel_plates": 4.0, "reinforced_hull": 4.0,
}

# Tech purchase orders (strict: the bot saves for the first unowned entry).
const TECH_BALANCED: Array = [
	"ballistics_ammo_bench", "engineering_frame", "electronics_rangefinder", "ballistics_heavy_shells",
	"engineering_welder", "salvage_hooks", "electronics_relay", "propulsion_tuned", "fusion_fortified",
	"ballistics_tables", "engineering_pickup", "electronics_targeting", "propulsion_bumper",
	"ballistics_he", "engineering_drone", "fusion_junkyard", "ballistics_tungsten", "engineering_truck",
	"electronics_neural", "ballistics_glowing",
]
const TECH_DAMAGE: Array = [
	"ballistics_ammo_bench", "electronics_rangefinder", "ballistics_belt_feed", "electronics_relay",
	"ballistics_tables", "engineering_frame", "engineering_welder", "engineering_pickup",
	"electronics_targeting", "ballistics_he", "electronics_hunter", "ballistics_tungsten",
	"electronics_overclock", "ballistics_glowing", "electronics_swarm",
]
const TECH_TANK: Array = [
	"engineering_frame", "engineering_welder", "engineering_pickup", "ballistics_ammo_bench",
	"propulsion_tuned", "ballistics_heavy_shells", "salvage_hooks", "electronics_rangefinder",
	"engineering_reactive", "engineering_truck", "engineering_war_rig",
]
const TECH_SPEED: Array = [
	"propulsion_tuned", "propulsion_drift", "propulsion_nitro", "engineering_frame", "ballistics_ammo_bench",
	"electronics_rangefinder", "engineering_welder", "fusion_hot_rod", "propulsion_ghost",
	"propulsion_turbine", "propulsion_phantom",
]
const TECH_RUSH: Array = [
	"ballistics_ammo_bench", "engineering_frame", "propulsion_tuned", "electronics_rangefinder", "salvage_hooks",
	"ballistics_belt_feed", "propulsion_bumper", "engineering_spikes", "salvage_haggler",
	"fusion_thermite", "fusion_barbed", "ballistics_tables", "engineering_pickup", "propulsion_nitro",
	"electronics_targeting", "salvage_black_market", "ballistics_napalm", "propulsion_battering",
	"fusion_war_machine",
]
const TECH_SAVER: Array = [
	"salvage_hooks", "salvage_haggler", "salvage_black_market", "ballistics_ammo_bench", "engineering_frame",
	"electronics_rangefinder", "salvage_hoarder", "salvage_crane", "salvage_baron",
]
const TECH_HUNTER: Array = [
	"ballistics_ammo_bench", "electronics_rangefinder", "engineering_frame", "ballistics_heavy_shells",
	"propulsion_tuned", "electronics_radar", "fusion_spotter", "ballistics_tables", "electronics_targeting",
	"electronics_hunter", "ballistics_he", "electronics_overclock",
]

var policy_name: String = ""
var cfg: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Per-workshop bookkeeping (keyed on the world round so the bot can be called every tick).
var _shop_round: int = -1
var _rerolls: int = 0
var _pick_done: bool = false


# ---------------------------------------------------------------- registry

## All policy names, in a stable order.
static func names() -> PackedStringArray:
	return PackedStringArray(_table().keys())


static func has(policy_name_: String) -> bool:
	return _table().has(policy_name_)


## One-line description of a policy ("" if unknown).
static func describe(policy_name_: String) -> String:
	var t: Dictionary = _table().get(policy_name_, {})
	return str(t.get("desc", ""))


## Builds the policy `policy_name_` with its own rng seeded from `p_seed` (use match seed + vehicle id).
## Returns null for an unknown name.
static func create(policy_name_: String, p_seed: int = 0) -> BotPolicy:
	var t: Dictionary = _table()
	if not t.has(policy_name_):
		return null
	var b := BotPolicy.new()
	b.policy_name = policy_name_
	b.cfg = (t[policy_name_] as Dictionary).duplicate(true)
	b.rng.seed = hash([policy_name_, p_seed])
	return b


static func _focus(weapon: String, desc: String) -> Dictionary:
	var cards: Dictionary = {"steel_plates": 3.0, "reinforced_hull": 3.0, "regenerator": 2.0, "scrap_magnet": 2.0}
	for w: String in Cards.WEAPON_KINDS:
		cards[w] = 10.0 if w == weapon else NEVER
	if weapon != "mg":
		cards["mg"] = NEVER  # keep the starter mg at level 1, never upgrade it
	return {
		"desc": desc, "cards": cards, "default_card": 1.0, "upgrade_bonus": 0.0,
		"tech_mode": "order", "tech": TECH_DAMAGE, "tech_reserve": 0,
		"reroll_below": 8.0, "max_rerolls": 4, "reroll_reserve": 10,
		"drive": "circle", "target": "nearest",
	}


static func _table() -> Dictionary:
	return {
		"never_upgrade": {
			"desc": "Never picks, rerolls or buys: the starter mg all game (baseline).",
			"cards": {}, "default_card": NEVER, "tech_mode": "none",
			"drive": "circle", "target": "nearest",
		},
		"random": {
			"desc": "Random pick, random tech and rerolls, random doctrine every workshop.",
			"mode": "random", "cards": {}, "default_card": 1.0, "tech_mode": "random",
			"drive": "circle", "target": "nearest",
		},
		"greedy_damage": {
			"desc": "Weapons and damage cards first, ballistics/electronics tech.",
			"cards": CARDS_DAMAGE, "default_card": 1.0, "upgrade_bonus": 2.0,
			"tech_mode": "order", "tech": TECH_DAMAGE, "tech_reserve": 0,
			"reroll_below": 7.0, "max_rerolls": 4, "reroll_reserve": 10,
			"drive": "circle", "target": "nearest",
		},
		"tank": {
			"desc": "Armour, hp and regen cards, engineering tech.",
			"cards": CARDS_TANK, "default_card": 1.0, "upgrade_bonus": 0.0, "new_weapon_bonus": 4.0,
			"tech_mode": "order", "tech": TECH_TANK, "tech_reserve": 0,
			"reroll_below": 7.0, "max_rerolls": 3, "reroll_reserve": 10,
			"drive": "circle", "target": "nearest",
		},
		"speedster": {
			"desc": "Mobility cards and propulsion tech, kites.",
			"cards": CARDS_SPEED, "default_card": 1.0, "upgrade_bonus": 0.0, "new_weapon_bonus": 4.0,
			"tech_mode": "order", "tech": TECH_SPEED, "tech_reserve": 0,
			"reroll_below": 7.0, "max_rerolls": 3, "reroll_reserve": 10,
			"drive": "kite", "target": "nearest",
		},
		"turtle": {
			"desc": "Passive FFA play: tank build, kites, never targets players (nearest alien only; the sim's return fire still applies).",
			"cards": CARDS_TANK, "default_card": 1.0, "upgrade_bonus": 0.0, "new_weapon_bonus": 4.0,
			"tech_mode": "order", "tech": TECH_TANK, "tech_reserve": 0,
			"reroll_below": 7.0, "max_rerolls": 3, "reroll_reserve": 10,
			"drive": "kite", "target": "nearest",
		},
		"focus_mg": _focus("mg", "Only ever upgrades the machine gun."),
		"focus_shotgun": _focus("shotgun", "Takes the scatter gun and levels it; ignores other weapons."),
		"focus_cannon": _focus("cannon", "Takes the siege cannon and levels it; ignores other weapons."),
		"focus_flamer": _focus("flamer", "Takes the flamethrower and levels it; ignores other weapons."),
		"tech_rush": {
			"desc": "Spends every scrap on tech, tier by tier across all branches.",
			"cards": CARDS_BALANCED, "default_card": 1.0, "upgrade_bonus": 1.0,
			"tech_mode": "order", "tech": TECH_RUSH, "tech_reserve": 0,
			"reroll_below": 0.0, "max_rerolls": 0, "reroll_reserve": 0,
			"drive": "circle", "target": "nearest",
		},
		"saver": {
			"desc": "Interest maximiser: keeps scrap at the interest cap, spends only the surplus.",
			"cards": CARDS_BALANCED, "default_card": 1.0, "upgrade_bonus": 1.0,
			"tech_mode": "saver", "tech": TECH_SAVER, "tech_reserve": 0,
			"reroll_below": 0.0, "max_rerolls": 0, "reroll_reserve": 0,
			"drive": "circle", "target": "nearest",
		},
		"balanced": {
			"desc": "Sensible human-like mix: weapons first, then hp/armour, balanced tech, light rerolling.",
			"cards": CARDS_BALANCED, "default_card": 1.0, "upgrade_bonus": 1.0, "lvl_decay": 0.08,
			"tech_mode": "order", "tech": TECH_BALANCED, "tech_reserve": 0,
			"reroll_below": 5.5, "max_rerolls": 3, "reroll_reserve": 15,
			"drive": "circle", "target": "nearest",
		},
		"balanced_kite": {
			"desc": "As balanced, but the kite driving doctrine.",
			"cards": CARDS_BALANCED, "default_card": 1.0, "upgrade_bonus": 1.0, "lvl_decay": 0.08,
			"tech_mode": "order", "tech": TECH_BALANCED, "tech_reserve": 0,
			"reroll_below": 5.5, "max_rerolls": 3, "reroll_reserve": 15,
			"drive": "kite", "target": "nearest",
		},
		"balanced_charge": {
			"desc": "As balanced, but the charge (ram) driving doctrine.",
			"cards": CARDS_BALANCED, "default_card": 1.0, "upgrade_bonus": 1.0, "lvl_decay": 0.08,
			"tech_mode": "order", "tech": TECH_BALANCED, "tech_reserve": 0,
			"reroll_below": 5.5, "max_rerolls": 3, "reroll_reserve": 15,
			"drive": "charge", "target": "nearest",
		},
		"pvp_hunter": {
			"desc": "players_first + charge, damage cards, hunts rivals.",
			"cards": CARDS_HUNTER, "default_card": 1.0, "upgrade_bonus": 1.5,
			"tech_mode": "order", "tech": TECH_HUNTER, "tech_reserve": 0,
			"reroll_below": 7.0, "max_rerolls": 3, "reroll_reserve": 10,
			"drive": "charge", "target": "players_first",
		},
	}


# ---------------------------------------------------------------- doctrine

## Commands that move the vehicle's doctrine to this policy's choice (empty if already there).
## Valid in every phase.
func doctrine_commands(_world: SimWorld, v: SimVehicle) -> Array[Dictionary]:
	var drive: String = str(cfg.get("drive", "circle"))
	var target: String = str(cfg.get("target", "nearest"))
	if str(cfg.get("mode", "")) == "random":
		drive = ["circle", "kite", "charge"][rng.randi() % 3]
		target = ["nearest", "strongest", "players_first"][rng.randi() % 3]
	var out: Array[Dictionary] = []
	if str(v.doctrine.get("drive", "")) != drive:
		out.append({"type": "set_drive", "value": drive})
	if str(v.doctrine.get("target", "")) != target:
		out.append({"type": "set_target", "value": target})
	return out


# ---------------------------------------------------------------- workshop

## Runs the whole workshop for `v`: calls next_command() and applies each command with
## world.apply_command() until the policy is done (it ends with "ready"). Returns the commands issued.
func workshop_commands(world: SimWorld, v: SimVehicle) -> Array[Dictionary]:
	var issued: Array[Dictionary] = []
	for cmd in doctrine_commands(world, v):
		world.apply_command(v.peer_id, cmd)
		issued.append(cmd)
	for _i in 40:  # guard: a workshop needs far fewer commands
		var c: Dictionary = next_command(world, v)
		if c.is_empty():
			break
		world.apply_command(v.peer_id, c)
		issued.append(c)
		if c["type"] == "ready":
			break
	return issued


## The next command to send in the current workshop, or {} when there is nothing (more) to do
## (outside the workshop, eliminated, or already ready). Order: card pick (with rerolls), tech
## purchases (one per call), then "ready". Call again after the previous command has been applied.
func next_command(world: SimWorld, v: SimVehicle) -> Dictionary:
	if world.phase != SimWorld.PHASE_WORKSHOP or v.eliminated or v.ready:
		return {}
	if _shop_round != world.round:
		_shop_round = world.round
		_rerolls = 0
		_pick_done = false
	var random_mode: bool = str(cfg.get("mode", "")) == "random"

	# 1. card
	if not v.picked and not _pick_done and not v.offers.is_empty():
		if random_mode:
			if v.scrap >= v.reroll_cost and _rerolls < 2 and rng.randf() < 0.15:
				_rerolls += 1
				return {"type": "reroll"}
			_pick_done = true
			return {"type": "pick_card", "value": rng.randi() % v.offers.size()}
		var best_i: int = -1
		var best_s: float = -1.0e9
		for i in v.offers.size():
			var s: float = card_score(v, v.offers[i])
			if s > best_s:
				best_s = s
				best_i = i
		var rr: int = int(cfg.get("reroll_reserve", 0))
		if (best_s < float(cfg.get("reroll_below", 0.0)) and _rerolls < int(cfg.get("max_rerolls", 0))
				and v.scrap - v.reroll_cost >= rr):
			_rerolls += 1
			return {"type": "reroll"}
		_pick_done = true
		if best_s >= 0.0:
			return {"type": "pick_card", "value": best_i}

	# 2. tech
	var tid: String = _next_tech(world, v)
	if tid != "":
		return {"type": "buy_tech", "value": tid}

	# 3. done
	return {"type": "ready"}


## Score of card `id` for vehicle `v` under this policy (higher = better; <= NEVER/2 = refuse).
func card_score(v: SimVehicle, id: String) -> float:
	var table: Dictionary = cfg.get("cards", {})
	var s: float = float(table.get(id, cfg.get("default_card", 1.0)))
	if s <= NEVER / 2.0:
		return s
	var lvl: int = int(v.cards.get(id, 0))
	if lvl > 0:
		if Cards.is_weapon(id):
			s += float(cfg.get("upgrade_bonus", 0.0))
		s *= 1.0 - float(cfg.get("lvl_decay", 0.0)) * float(lvl)
	elif Cards.is_weapon(id):
		s += float(cfg.get("new_weapon_bonus", 0.0))  # first copy of a weapon (fills a free slot)
	return s


## The tech id this policy wants to buy right now (affordable and allowed), or "".
func _next_tech(world: SimWorld, v: SimVehicle) -> String:
	var mode: String = str(cfg.get("tech_mode", "none"))
	if mode == "none":
		return ""
	if mode == "random":
		var ok: Array[String] = []
		for i in Tech.count():
			var id: String = Tech.id_at(i)
			if Tech.can_buy(v, id):
				ok.append(id)
		if ok.is_empty() or rng.randf() > 0.6:
			return ""
		return ok[rng.randi() % ok.size()]
	var reserve: int = int(cfg.get("tech_reserve", 0))
	if mode == "saver":
		reserve = world.interest_cap_for(v) * SimWorld.INTEREST_PER
	for entry in cfg.get("tech", []):
		var id2: String = str(entry)
		if v.tech.has(id2):
			continue
		# strict order: the first unowned entry is the goal; save for it.
		if Tech.blocked_by(v, id2) != "":
			continue  # an exclusive sibling was bought first: skip this entry
		var goal: String = Tech.next_step(v, id2)
		if Tech.blocked_by(v, goal) != "":
			continue  # the way there runs through a node a sibling choice already locked
		if Tech.can_buy(v, goal) and v.scrap - Tech.price(v, goal) >= reserve:
			return goal
		return ""
	return ""
