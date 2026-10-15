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
## Each: {"kind", "damage", "range", "cooldown_ticks", "cooldown", "aim", "pellets", "spread",
## "pierce", "splash", "speed"} (see Cards.WEAPONS), plus host-side scratch from the weapon's own
## doctrine (VehicleAI.update_weapon_target: "tk", "ti", "tid", "tp", "tv", "tmode") and "live", the
## mask of its matching rules (synced). Rebuilt from the weapon cards by Cards.recompute().
var weapons: Array[Dictionary] = []

# Round loop state (docs/architecture.md, "Round loop contract").
var fuel: int = 100
var respawn_ticks: int = 0  ## > 0 while destroyed and waiting to respawn
var eliminated: bool = false
var ready: bool = false  ## workshop: done shopping
var offers: Array[String] = []  ## 3 card ids to pick from, empty once picked
var picked: bool = false
var reroll_cost: int = SimWorld.REROLL_COST_START
var cards: Dictionary = {"mg": 1}  ## card id -> level 1..3 (insertion order = acquisition order)
var tech: Array[String] = []  ## owned tech ids

# Derived stats (Cards.recompute): base values plus cards plus tech. speed / turn_rate are multipliers.
var armor: float = 0.0  ## flat reduction per hit (and, scaled, per touching enemy per tick)
var speed: float = 1.0
var turn_rate: float = 1.0
var scrap_mult: float = 1.0
var regen: float = 0.0  ## hp / s
var contact_damage: float = 0.0  ## damage per tick to touching enemies (spikes, berserker)
var ram_mult: float = 1.0  ## multiplies the "charge" ram damage
var vulture: float = 0.0  ## extra damage fraction vs targets under 30% hp
var weapon_slots: int = 2
var interest_cap: int = 5
var scrap_frac: float = 0.0  ## fractional scrap carried by scrap_mult
var protect_ticks: int = 0  ## third-party protection: > 0 means damage taken is halved (set by a player kill)
var invuln_ticks: int = 0  ## newbie protection: > 0 means untargetable and immune (after respawn and at combat start)
var contact_reduction: float = 0.0  ## fraction of enemy contact damage ignored (spiked plating, berserker), 0..MAX
var thorns: float = 0.0  ## fraction of enemy contact damage dealt back to the touching enemy (spiked plating)

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
