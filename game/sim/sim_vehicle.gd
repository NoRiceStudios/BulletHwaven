class_name SimVehicle
extends RefCounted
## One auto-driving armoured vehicle. Plain data plus a few AI scratch fields.

const RADIUS := 14.0
const MAX_HP := 300.0

var id: int = 0
var peer_id: int = 0
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO  ## px/s
var heading: float = 0.0  ## radians, 0 = +X. Sprites face north: render rotation = heading + PI / 2.
var hp: float = MAX_HP
var max_hp: float = MAX_HP
var alive: bool = true
var scrap: int = 0
var kills: int = 0
var doctrine: Dictionary = {"drive": "circle", "target": "nearest"}
## Each: {"kind", "damage", "range", "cooldown_ticks", "cooldown", "aim", "pellets", "spread",
## "pierce", "splash", "speed"} (see Cards.WEAPONS). Rebuilt from the weapon cards by Cards.recompute().
var weapons: Array[Dictionary] = []

# Round loop state (docs/architecture.md, "Round loop contract").
var fuel: int = 100
var respawn_ticks: int = 0  ## > 0 while destroyed and waiting to respawn
var eliminated: bool = false
var ready: bool = false  ## workshop: done shopping
var offers: Array[String] = []  ## 3 card ids to pick from, empty once picked
var picked: bool = false
var reroll_cost: int = 2
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

# AI scratch state (derived each tick; not part of the checksum).
var target_kind: int = 0  ## 0 = none, 1 = enemy, 2 = vehicle
var target_index: int = -1  ## enemy array index (kind 1) or vehicle id (kind 2)
var target_id: int = -1  ## stable enemy id (kind 1) or vehicle id (kind 2)
var target_pos: Vector2 = Vector2.ZERO
var target_vel: Vector2 = Vector2.ZERO  ## px/s
var orbit_dir: float = 1.0
var ram_damage: float = 0.0  ## per-tick damage dealt to touching enemies/vehicles ("charge")


func _init(p_id: int, p_peer_id: int, p_pos: Vector2) -> void:
	id = p_id
	peer_id = p_peer_id
	pos = p_pos
	orbit_dir = 1.0 if p_id % 2 == 0 else -1.0
	Cards.recompute(self, true, false)
	hp = max_hp


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
