class_name DoctrinePresets
extends RefCounted
## Starting doctrines offered in the deploy phase before round 1 (design doc section 6): a base drive, a base
## target and up to two rig rules each, using only what a fresh rig has unlocked. Picking one sends the usual
## `set_drive` / `set_target` / `set_rules` commands, so the sim knows nothing about presets.

const LIST: Array[Dictionary] = [
	{"id": "orbiter", "name": "ORBITER", "drive": "circle", "target": "nearest", "rules": "hp<30|drive:flee;swarm>25|drive:kite",
		"lines": ["CIRCLES THE PACK, GUNS OUT", "FLEES BELOW 30% HP", "KITES WHEN 25+ ALIENS CLOSE IN"], "tag": "ALL-ROUNDER"},
	{"id": "sniper", "name": "LONG GUN", "drive": "kite", "target": "strongest", "rules": "t_dist<80|drive:flee;boss_active=1|target:boss",
		"lines": ["KEEPS AT WEAPON RANGE", "HUNTS THE TOUGHEST ALIEN", "BACKS OFF WHEN IT GETS CLOSE"], "tag": "SAFE, SLOWER KILLS"},
	{"id": "brawler", "name": "BRAWLER", "drive": "charge", "target": "nearest", "rules": "hp<25|drive:kite;swarm>30|drive:circle",
		"lines": ["DRIVES STRAIGHT IN AND RAMS", "CIRCLES WHEN 30+ ALIENS SWARM", "KITES BELOW 25% HP"], "tag": "FAST SCRAP, RISKY"},
	{"id": "hunter", "name": "HEADHUNTER", "drive": "circle", "target": "nearest", "rules": "pvp=1&rivals>0|target:players_first;hp<30|drive:flee",
		"lines": ["CLEARS ALIENS UNTIL PVP IS ON", "THEN GOES FOR NEARBY RIVALS", "FLEES BELOW 30% HP"], "tag": "PVP FROM ROUND 4"},
	{"id": "zone_holder", "name": "ZONE HOLDER", "drive": "circle", "target": "nearest", "rules": "pvp=1&hp>35|drive:zone;in_zone=1|target:intruders",
		"lines": ["CLEARS ALIENS UNTIL ZONES OPEN", "THEN TAKES AND HOLDS A ZONE", "SHOOTS RIVALS INSIDE IT"], "tag": "SCRAP FROM ROUND 4"},
]


## The commands that turn `v`'s rig doctrine into preset `p` (rules the rig cannot run yet are dropped by the sim).
static func commands(p: Dictionary) -> Array[Dictionary]:
	return [
		{"type": "set_drive", "value": p["drive"]},
		{"type": "set_target", "value": p["target"]},
		{"type": "set_rules", "scope": Doctrine.SCOPE_RIG, "value": p["rules"]},
	]


## The preset `v`'s rig doctrine matches exactly, else "" (edited by hand: CUSTOM).
static func current(v: SimVehicle) -> String:
	for p in LIST:
		if str(v.doctrine["drive"]) == p["drive"] and str(v.doctrine["target"]) == p["target"] \
				and Doctrine.encode(v.rules) == Doctrine.encode(Doctrine.parse(p["rules"], Doctrine.SCOPE_RIG)):
			return p["id"]
	return ""


static func by_id(id: String) -> Dictionary:
	for p in LIST:
		if p["id"] == id:
			return p
	return {}
