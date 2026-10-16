class_name RigArt
extends RefCounted
## Which baked strips make up a rig (playtest round 1 #6: "the rig visibly grows").
## The strips come from tools/artgen/rig.py (export_assets.export_rig): every hull-fixed layer is a
## 32-direction RotSprite strip on the same 80x80 frame centred on the sim position, so stacking
## sprites that show the same frame lines them up. Rows select the variant (footprint, level).
## Guns and the trailer turn on their own and sit on the anchors below (mirrors rig.RIG_ANCHORS).
##
## Footprint 0 = "A" buggy (chassis 1), 1 = "B" six-wheel truck (chassis 3 truck, 4 war rig tractor),
## 2 = "P" pickup (chassis 2). Chassis 4 (war rig) adds an articulated trailer with two gun rings.
## Tech bolt-ons (rig_tech.png: dozer blade, roll cage, sidecar, jerrycans, scrap hoard) are hull layers too;
## other tech reuses card layers (spike skirts -> spikes, reactive plates -> plates, welder / crane -> kit).

const FRAME := 80
const TRAILER_FRAME := 64
const GUN_FRAME := 40
const FLAME_FRAME := 32

const TEX_GEAR := preload("res://assets/rig_gear.png")  ## rows: A wheels/offroad/tracks, B wheels/offroad/tracks
const TEX_BODY := preload("res://assets/rig_body.png")  ## rows: BODY_* (rig.BODY_STYLES); paint keyed
const TEX_TECH := preload("res://assets/rig_tech.png")  ## rows: footprint x TECH_KIT; the sidecar is paint keyed
const TEX_DRONE := preload("res://assets/rig_drone.png")  ## 16 directions x 2 rotor frames, 20x20
const TEX_SHADOW := preload("res://assets/rig_shadow.png")  ## rows as rig_gear (gear + body silhouette)
## Rows of rig_body.png.
const BODY_BUGGY := 0
const BODY_BUGGY_FRAME := 1
const BODY_TRUCK := 2
const BODY_PICKUP := 3
const BODY_WAR_RIG := 4
const FOOT_BUGGY := 0
const FOOT_TRUCK := 1
const FOOT_PICKUP := 2
## Tech bolt-on rows of rig_tech.png (per footprint): [tech_fx key, row].
const TECH_KIT: Array = [["dozer", 0], ["roll_cage", 1], ["sidecar", 2], ["jerry_blast", 3], ["hoarder", 4]]
const TECH_KIT_ROWS := 5
const TEX_KIT := preload("res://assets/rig_kit.png")  ## rows: A then B x KIT_CARDS
const TEX_TRAILER := preload("res://assets/rig_trailer.png")  ## paint keyed
const TEX_FLAME := preload("res://assets/nitro_flame.png")  ## rows: level 1..3 x flicker a/b
const TEX_FLAME_GLOW := preload("res://assets/nitro_flame_glow.png")
const TEX_RAMPS := preload("res://assets/paint_ramps.png")
const PAINT_SHADER := preload("res://render/paint.gdshader")

## Card -> strip with rows A L1..3, B L1..3, drawn bottom to top in this order.
const LEVEL_LAYERS: Array = [
	["steel_plates", preload("res://assets/rig_plates.png")],
	["reinforced_hull", preload("res://assets/rig_reinforced.png")],
	["ablative_scrap", preload("res://assets/rig_ablative.png")],
	["spiked_plating", preload("res://assets/rig_spikes.png")],
	["v8_engine", preload("res://assets/rig_v8.png")],
	["nitro", preload("res://assets/rig_nitro.png")],
]
const KIT_CARDS: PackedStringArray = ["scrap_magnet", "berserker", "vulture", "regenerator"]
const GUN_TEX := {
	"mg": preload("res://assets/gun_mg.png"), "shotgun": preload("res://assets/gun_shotgun.png"),
	"cannon": preload("res://assets/gun_cannon.png"), "flamer": preload("res://assets/gun_flamer.png"),
}
## Evolved guns (rig.gun_evo, design doc 5a): rows kind (Cards.WEAPON_KINDS order) x phase 0/1, 56x56 frames.
const GUN_EVO_TEX := preload("res://assets/gun_evo.png")
const GUN_EVO_FRAME := 56
const BARREL_EVO := {"mg": 21, "shotgun": 15, "cannon": 29, "flamer": 18}  ## as rig.BARREL_EVO
## Barrel length per gun kind and level (muzzle flash position), as rig.BARREL.
const BARREL := {"mg": [14, 15, 15], "shotgun": [10, 11, 11], "cannon": [16, 18, 20], "flamer": [10, 10, 11]}

## Anchors per footprint, rig facing north, relative to the sim position (px).
## Gun sprite centres for mounts 0 and 1 (the third gun rides the trailer).
## Hull gun rings in fill order (cockpit / cab, deck or bed, then the extras); guns 3+ ride the trailer
## first (war rig), the last gun rides the sidecar when there is one.
const MOUNTS: Array = [[Vector2(0, -4), Vector2(0, -15), Vector2(0, 16), Vector2(0, 5)],
	[Vector2(0, -10), Vector2(0, 10), Vector2(0, -22), Vector2(0, 23)],
	[Vector2(0, -6), Vector2(0, 11), Vector2(0, 21), Vector2(0, -20)]]
const SIDECAR_MOUNT: Array = [Vector2(27, 1), Vector2(27, -5), Vector2(27, 0)]
const EXHAUSTS: Array = [[Vector2(-9, 26), Vector2(8, 26)], [Vector2(-9, 32), Vector2(8, 32)], [Vector2(-9, 29), Vector2(8, 29)]]
const REAR_WHEELS: Array = [[Vector2(-12, 14), Vector2(12, 14)], [Vector2(-12, 23), Vector2(12, 23)], [Vector2(-12, 18), Vector2(12, 18)]]
const HITCH: Array = [Vector2(0, 26), Vector2(0, 32), Vector2(0, 30)]
const TRAILER_TONGUE := 26.0  ## hitch -> trailer centre
const TRAILER_MOUNTS: Array = [Vector2(0, 0), Vector2(0, 13)]  ## guns on the trailer, from the trailer centre
## Rough radius of the rig for rings and markers.
const RADIUS: PackedFloat32Array = [27.0, 33.0, 30.0]
## Front of the hull (bumper) from the rig centre, facing north (dozer glow, juggernaut).
const FRONT: PackedFloat32Array = [-26.0, -32.0, -29.0]


## Chassis size 1..4 (`SimVehicle.chassis`, from the chassis tech); rows of the body strip follow it.
static func engineering(v: SimVehicle) -> int:
	return v.chassis


static func footprint(v: SimVehicle) -> int:
	match engineering(v):
		1:
			return FOOT_BUGGY
		2:
			return FOOT_PICKUP
	return FOOT_TRUCK


## Row of rig_body.png: bare buggy, buggy with the welded frame, pickup, truck, war rig tractor.
static func body_row(v: SimVehicle) -> int:
	match engineering(v):
		1:
			return BODY_BUGGY_FRAME if Tech.active(v, "engineering_frame") else BODY_BUGGY
		2:
			return BODY_PICKUP
		3:
			return BODY_TRUCK
	return BODY_WAR_RIG


static func has_trailer(v: SimVehicle) -> bool:
	return engineering(v) >= 4


static func fx(v: SimVehicle, key: String) -> bool:
	return float(v.tech_fx.get(key, 0.0)) > 0.0


static func has_sidecar(v: SimVehicle) -> bool:
	return fx(v, "sidecar")


static func uses_tracks(v: SimVehicle) -> bool:
	return v.cards.has("caterpillar_tracks")


static func card_level(v: SimVehicle, id: String) -> int:
	return clampi(int(v.cards.get(id, 0)), 0, 3)


## Changes whenever the look of the rig changes (cheap cache key for the sprite stack).
static func signature(v: SimVehicle) -> String:
	var parts: PackedStringArray = [str(engineering(v)), str(body_row(v)), str(v.color_index)]
	for id: String in v.tech:
		parts.append(id)
	for id: String in v.cards:
		parts.append("%s%d" % [id, int(v.cards[id])])
	for w in v.weapons:
		parts.append(str(w.get("kind", "")))
	return ",".join(parts)


## Hull-fixed layers bottom to top: [[texture, row], ...] (all FRAME-sized, VEHICLE_DIRS columns).
static func hull_layers(v: SimVehicle) -> Array:
	var f: int = footprint(v)
	var out: Array = [[TEX_GEAR, f * 3 + gear_index(v)], [TEX_BODY, body_row(v)]]
	for l: Array in LEVEL_LAYERS:
		var lv: int = maxi(card_level(v, l[0]), _tech_level(v, l[0]))
		if lv > 0:
			out.append([l[1], f * 3 + lv - 1])
	for i in KIT_CARDS.size():
		if card_level(v, KIT_CARDS[i]) > 0 or _tech_kit_card(v, KIT_CARDS[i]):
			out.append([TEX_KIT, f * KIT_CARDS.size() + i])
	for t: Array in TECH_KIT:
		if fx(v, t[0]):
			out.append([TEX_TECH, f * TECH_KIT_ROWS + int(t[1])])
	return out


## Tech that shows as a card layer: spike skirts (spikes 2), reactive plates (plates 2), scrap armour (ablative 2).
static func _tech_level(v: SimVehicle, card: String) -> int:
	match card:
		"spiked_plating":
			return 2 if Tech.active(v, "engineering_spikes") else 0
		"steel_plates":
			return 2 if fx(v, "blast_resist") else 0
		"ablative_scrap":
			return 2 if fx(v, "armor_shed") else 0
	return 0


## Field welder -> the welding kit, salvage crane -> the magnet boom.
static func _tech_kit_card(v: SimVehicle, card: String) -> bool:
	match card:
		"regenerator":
			return Tech.active(v, "engineering_welder")
		"scrap_magnet":
			return Tech.active(v, "salvage_crane")
	return false


static func gear_index(v: SimVehicle) -> int:
	if uses_tracks(v):
		return 2
	return 1 if v.cards.has("off_road_tyres") else 0


static func shadow_row(v: SimVehicle) -> int:
	return footprint(v) * 3 + gear_index(v)


## Guns in weapon order: [[kind, level, evolved], ...].
static func guns(v: SimVehicle) -> Array:
	var out: Array = []
	for w in v.weapons:
		var kind: String = str(w.get("kind", "mg"))
		if not GUN_TEX.has(kind):
			kind = "mg"
		out.append([kind, clampi(int(v.cards.get(kind, 1)), 1, 3), bool(w.get("evo", false))])
	return out


## Bit per evolved weapon kind (1 << Cards.weapon_kind_index), from the weapons' "evo" flags.
static func evo_mask(v: SimVehicle) -> int:
	var m: int = 0
	for w in v.weapons:
		if bool(w.get("evo", false)):
			m |= 1 << Cards.weapon_kind_index(str(w.get("kind", "")))
	return m


## The evolution card that evolves weapon `kind` ("" if none).
static func evolution_card(kind: String) -> String:
	for d: Dictionary in Cards.DEFS:
		if str(d["category"]) == "evolution" and str(d.get("weapon", "")) == kind:
			return str(d["id"])
	return ""


## Barrel length of a gun entry ([kind, level, evolved]).
static func barrel_length(g: Array) -> float:
	if g.size() > 2 and bool(g[2]):
		return float(BARREL_EVO.get(str(g[0]), 20))
	return float((BARREL[str(g[0])] as Array)[int(g[1]) - 1])


## One material per rig: resolves paint keys with the owner's paint job.
static func paint_material(color_index: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("ramps", TEX_RAMPS)
	m.set_shader_parameter("paint_row", Gfx.color_slot(color_index))
	return m
