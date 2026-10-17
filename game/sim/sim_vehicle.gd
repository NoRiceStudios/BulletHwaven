class_name SimVehicle
extends RefCounted
## One auto-driving armoured vehicle. Plain data plus a few AI scratch fields.

const RADIUS := 14.0
const MAX_HP := 300.0

# Player identity (lobby). Colour indices: 0 red, 1 magenta (the current art), 2..7 reserved for more paints.
const COLOR_COUNT := 8
const MAX_NAME_LEN := 16
const DEFAULT_NAME := "DRIVER"

var id: int = 0
var peer_id: int = 0
var player_name: String = DEFAULT_NAME  ## sanitised, 1..MAX_NAME_LEN printable ASCII chars
var color_index: int = 0  ## 0..COLOR_COUNT-1 paint colour; defaults to id % COLOR_COUNT
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO  ## px/s
var heading: float = 0.0  ## radians, 0 = +X. Sprites face north: render rotation = heading + PI / 2.
var hp: float = MAX_HP
var max_hp: float = MAX_HP
var alive: bool = true
var scrap: int = 0
var kills: int = 0
var doctrine: Dictionary = {"drive": "circle", "target": "nearest"}
## Programmable behaviour (Doctrine, design doc section 6 layer 2): the rig's IF-THEN rules and, per
## weapon kind, {"target": base target mode ("follow" = the rig's target), "rules": Array}. Kept
## across card changes; rules beyond Doctrine.slots() are stored but not run.
var rules: Array = []
var weapon_doctrine: Dictionary = {}
## Each: {"kind", "damage", "range", "cooldown_ticks" (float, ticks per shot), "cooldown" (float ticks left,
## in (-1, 0] it carries the fractional rest into the next shot), "aim", "pellets", "spread",
## "pierce", "splash", "speed", "heat", "jam", "sw", "shots"} (see Cards.WEAPONS), plus host-side scratch from the weapon's own
## doctrine (VehicleAI.update_weapon_target: "tk", "ti", "tid", "tp", "tv", "tmode") and "live", the
## mask of its matching rules (synced). Rebuilt from the weapon cards by Cards.recompute().
var weapons: Array[Dictionary] = []

## Loaded ammo per weapon kind (Ammo): kind -> Array of ammo ids (index 0 = primary, 2 entries with mixed
## belts). Per-weapon heat / jam / switch state lives in the weapon dicts ("heat", "jam", "sw", "shots").
var ammo: Dictionary = {}
var ammo_known: Array[String] = []  ## host-side: ammo types unlocked at the last Ammo.sync (decides what auto-loads)

# Round loop state (docs/architecture.md, "Round loop contract").
var fuel: int = 100
var respawn_ticks: int = 0  ## > 0 while destroyed and waiting to respawn
var eliminated: bool = false
var ready: bool = false  ## workshop: done shopping
var offers: Array[String] = []  ## 3 card ids to pick from, empty once picked
var picked: bool = false
var reroll_cost: int = SimWorld.REROLL_COST_START
var cards: Dictionary = {"mg": 1}  ## card id -> level 1..3 (insertion order = acquisition order)
var tech: Array[String] = []  ## owned tech ids (acquisition order); only ACTIVE ones apply (Tech.active)
var tech_dormant: Array[String] = []  ## fusions that lost a requirement through a respec (re-buy at half price)
var tech_round: Dictionary = {}  ## tech id -> round it was bought in (keystone respec window)
var respecs: int = 0  ## respecs done this match (the first one is free)

# Derived stats (Cards.recompute): base values plus cards plus tech. speed / turn_rate are multipliers.
var armor: float = 0.0  ## flat reduction per hit (and, scaled, per touching enemy per tick)
var speed: float = 1.0
var chassis: int = 1  ## 1..4 from the chassis tech (render: rig size); 1 + the highest active "chassis" fx
var tech_fx: Dictionary = {}  ## every fx key of the ACTIVE tech summed (stage 2+ mechanics read e.g. tech_fx.get("momentum", 0.0))
var turn_rate: float = 1.0
var scrap_mult: float = 1.0
var regen: float = 0.0  ## hp / s
var contact_damage: float = 0.0  ## damage per tick to touching enemies (spikes, berserker)
var ram_mult: float = 1.0  ## multiplies the "charge" ram damage
var vulture: float = 0.0  ## extra damage fraction vs targets under 30% hp
var weapon_slots: int = 2
var interest_cap: int = 5
var reroll_discount: int = 0  ## scrap off every reroll (salvage tech), applied when the cost resets
var card_luck: float = 0.0  ## extra offer weight fraction for rare and better cards (salvage tech)
var scrap_frac: float = 0.0  ## fractional scrap carried by scrap_mult
var protect_ticks: int = 0  ## third-party protection: > 0 means damage taken is halved (set by a player kill)
var invuln_ticks: int = 0  ## newbie protection: > 0 means untargetable and immune (after respawn and at combat start)
var contact_reduction: float = 0.0  ## fraction of enemy contact damage ignored (spiked plating, berserker), 0..MAX
var thorns: float = 0.0  ## fraction of enemy contact damage dealt back to the touching enemy (spiked plating)

# Momentum, abilities and electronics state (tech tree v2.3 stage 2b; Mobility, Abilities). All of it is synced.
var momentum: float = 0.0  ## 0..100 (Mobility.MOMENTUM_MAX); only moves with the Tuned Engine
var abilities: Array[String] = ["", ""]  ## equipped ability ids (Abilities.IDS), one per slot, "" = empty; filled in purchase order
var ab_cd: PackedInt32Array = PackedInt32Array([0, 0])  ## cooldown ticks left per ability slot
var nitro_ticks: int = 0  ## nitro boost left (+60 % speed)
var sputter_ticks: int = 0  ## dirty fuel: a coughing nitro (no boost) left
var salvo_ticks: int = 0  ## salvo left (+50 % fire rate)
var smoke_ticks: int = 0  ## smoke screen left: untargetable
var decoy_ticks: int = 0  ## phantom decoy left; it stands at decoy_pos
var decoy_pos: Vector2 = Vector2.ZERO
var rules_off_ticks: int = 0  ## EMP'd by a rival: no rules run
var nitro_count: int = 0  ## nitros cast this match (every 4th sputters with dirty fuel)
var boom_cd: int = 0  ## turbine boom cooldown ticks
var jammed_by: int = -1  ## vehicle id of the jammer whose field this rig is in (its last rule slot is off), -1 = none
var shed: int = 0  ## armour plates shed this round (scrap armour)
var mark_id: int = -1  ## swarm logic: enemy id of the marked target, -1 = none
var mark_pos: Vector2 = Vector2.ZERO

# Salvage and fusion state (tech tree v2.3 stage 3; Salvage, Fusions). The contract / loan / reserve / bonus fields are synced.
var contract_offers: Array[Vector3i] = []  ## workshop: offered contracts as (kind, need, reward); empty once one is accepted
var contract_kind: int = -1  ## accepted contract (Salvage.K_*), -1 = none; paid when the combat ends
var contract_need: int = 0
var contract_reward: int = 0  ## base scrap, before contract_bonus
var contract_prog: float = 0.0  ## progress towards contract_need; -1 = failed (stirb nicht)
var loan_debt: int = 0  ## scrap still owed to the loan shark
var loan_left: int = 0  ## scheduled instalments left (the last one takes whatever is owed)
var reserved_card: String = ""  ## haggler: this card is added to the next workshop's offers
var boss_rare: bool = false  ## host only: the next draft has a guaranteed rare-or-better card (boss kill)
var bonus_offers: int = 0  ## lucky strike: extra card offers at the next workshop
var lucky_round: int = -10  ## round of the last lucky-strike bonus offer
var saws: int = 0  ## scrapped cards waiting to fly off as saw blades at the next combat start
var raid_acc: float = 0.0  ## host-only: raider damage not yet turned into stolen scrap
var barbed_scrap: int = 0  ## host-only: barbed wire scrap earned this round (cap)
var storm_count: int = 0  ## host-only: scrap storm bursts this round (cap)
var fort_regen: float = 0.0  ## host-only: fortified relay repair rate (hp/s) while fort_ticks run
var fort_ticks: int = 0
var clap_cd: int = 0  ## host-only: thunderclap cooldown ticks
var drifting: bool = false  ## host-only: hard turn at speed this tick (hot rod, burning wake)

## Last combat round's numbers, for the workshop recap (see SimWorld.new_round_stats()). Reset at the
## start of every combat, filled while it runs. Snapshots carry it only outside combat.
var round_stats: Dictionary = {}
## Whole-match numbers (see SimWorld.new_match_stats()). Snapshots carry it only outside combat.
var match_stats: Dictionary = {}

# AI scratch state (derived each tick; not part of the checksum).
var target_kind: int = 0  ## 0 = none, 1 = enemy, 2 = vehicle
var target_index: int = -1  ## enemy array index (kind 1) or vehicle id (kind 2)
var target_id: int = -1  ## stable enemy id (kind 1) or vehicle id (kind 2)
var target_pos: Vector2 = Vector2.ZERO
var target_vel: Vector2 = Vector2.ZERO  ## px/s
var orbit_dir: float = 1.0
var eff_drive: String = "circle"  ## doctrine after the rules ran this tick (Doctrine.apply_rig)
var eff_target: String = "nearest"
var acquired_mode: String = ""  ## eff_target the current target was picked with (a rule switch retargets at once)
var rule_live: int = 0  ## bit i: rig rule i matched this tick (synced, for the rule editor)
var retaliate_id: int = -1  ## vehicle id of the last player that hurt this one (return fire), -1 = none
var retaliate_ticks: int = 0  ## ticks left for the return-fire memory
var ram_damage: float = 0.0  ## per-tick damage dealt to touching enemies/vehicles ("charge")
var kill_counts: Dictionary = {}  ## host-only: victim vehicle id -> player kills this round (diminishing rewards)
var victim_counts: Dictionary = {}  ## host-only: victim vehicle id -> player kills this match
var killed_by_counts: Dictionary = {}  ## host-only: killer vehicle id -> times it destroyed this vehicle (match)
var drive_speed: float = 0.0  ## px/s the drive style asked for this tick, before the turning slow-down (momentum gain)
var turn_diff: float = 0.0  ## |heading error| this tick (drift momentum)
var ramming: bool = false  ## charge ram active this tick (ram effects: sparks, momentum cost, knockback)
var eff_armor: float = 0.0  ## armor plus juggernaut's momentum armour, set every tick (used for all damage)
var focus: bool = false  ## all guns follow the rig's target this tick (fire:focus rule, swarm logic)
var ab_rule_any: int = 0  ## host-only: bit per Abilities.IDS index with an `ability:<id>` rule (overrides the auto-cast)
var ab_rule_hit: int = 0  ## ... and the ones whose rule matched this tick
var ram_fx: Dictionary = {}  ## host-only: rival vehicle id -> tick of the last ram effect on it (throttle)
var last_hit_src: int = 0  ## host-only: source (SimWorld.SRC_*) and attacker of the latest damage taken
var last_hit_attacker: int = -1


func _init(p_id: int, p_peer_id: int, p_pos: Vector2) -> void:
	id = p_id
	peer_id = p_peer_id
	color_index = p_id % COLOR_COUNT
	pos = p_pos
	orbit_dir = 1.0 if p_id % 2 == 0 else -1.0
	Cards.recompute(self, true, false)
	hp = max_hp
	round_stats = SimWorld.new_round_stats(1)
	match_stats = SimWorld.new_match_stats()


func max_range() -> float:
	var r: float = 0.0
	for w in weapons:
		r = maxf(r, float(w["range"]))
	return r


## Range the driving AI orients itself on: the mean weapon range, so a flamer in the mix pulls the
## vehicle closer. Equals max_range() with a single weapon kind.
func engage_range() -> float:
	if weapons.is_empty():
		return 0.0
	var r: float = 0.0
	for w in weapons:
		r += float(w["range"])
	return r / float(weapons.size())


## Cleans a player name: printable ASCII only (0x20..0x7E), runs of spaces collapsed, trimmed,
## at most MAX_NAME_LEN characters. Returns DEFAULT_NAME if nothing is left.
static func sanitize_name(raw: String) -> String:
	var out: String = ""
	var last_space: bool = true  # also trims leading spaces
	for i in mini(raw.length(), 128):
		var c: int = raw.unicode_at(i)
		if c < 0x20 or c > 0x7E:
			continue
		if c == 0x20:
			if last_space:
				continue
			last_space = true
		else:
			last_space = false
		out += char(c)
	out = out.strip_edges().left(MAX_NAME_LEN).strip_edges()
	return out if out != "" else DEFAULT_NAME
