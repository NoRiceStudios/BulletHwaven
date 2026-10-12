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
var weapons: Array[Dictionary] = []

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
	weapons.append({"kind": "mg", "damage": 4.0, "range": 240.0, "cooldown_ticks": 3, "cooldown": 0, "aim": 0.0})


func max_range() -> float:
	var r: float = 0.0
	for w in weapons:
		r = maxf(r, float(w["range"]))
	return r
