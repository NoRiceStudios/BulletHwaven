class_name RigArt
extends RefCounted
## Which baked strips make up a rig (playtest round 1 #6: "the rig visibly grows").
## The strips come from tools/artgen/rig.py (export_assets.export_rig): every hull-fixed layer is a
## 32-direction RotSprite strip on the same 80x80 frame centred on the sim position, so stacking
## sprites that show the same frame lines them up. Rows select the variant (footprint, level).
## Guns and the trailer turn on their own and sit on the anchors below (mirrors rig.RIG_ANCHORS).
##
## Footprint 0 = "A" buggy (engineering tier 0-1), 1 = "B" six-wheel truck (engineering 2+);
## engineering 3 adds an articulated trailer that carries the third gun mount.

const FRAME := 80
const TRAILER_FRAME := 64
const GUN_FRAME := 40
const FLAME_FRAME := 32

const TEX_GEAR := preload("res://assets/rig_gear.png")  ## rows: A wheels/offroad/tracks, B wheels/offroad/tracks
const TEX_BODY := preload("res://assets/rig_body.png")  ## rows: tier 0, 1 (A), 2+ (B); paint keyed
const TEX_SHADOW := preload("res://assets/rig_shadow.png")  ## rows as rig_gear (gear + body silhouette)
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
## Barrel length per gun kind and level (muzzle flash position), as rig.BARREL.
const BARREL := {"mg": [14, 15, 15], "shotgun": [10, 11, 11], "cannon": [16, 18, 20], "flamer": [10, 10, 11]}

## Anchors per footprint, rig facing north, relative to the sim position (px).
## Gun sprite centres for mounts 0 and 1 (the third gun rides the trailer).
const MOUNTS: Array = [[Vector2(0, -4), Vector2(0, -15)], [Vector2(0, -10), Vector2(0, 10)]]
const EXHAUSTS: Array = [[Vector2(-9, 26), Vector2(8, 26)], [Vector2(-9, 32), Vector2(8, 32)]]
const REAR_WHEELS: Array = [[Vector2(-12, 14), Vector2(12, 14)], [Vector2(-12, 23), Vector2(12, 23)]]
const HITCH: Array = [Vector2(0, 26), Vector2(0, 32)]
const TRAILER_TONGUE := 26.0  ## hitch -> trailer centre
const TRAILER_MOUNT := Vector2(0, 0)  ## gun on the trailer, from the trailer centre
## Rough radius of the rig for rings and markers.
const RADIUS: PackedFloat32Array = [27.0, 33.0]


static func engineering(v: SimVehicle) -> int:
	return Tech.branch_tier(v, "engineering")


static func footprint(v: SimVehicle) -> int:
	return 1 if engineering(v) >= 2 else 0


static func has_trailer(v: SimVehicle) -> bool:
	return engineering(v) >= 3


static func uses_tracks(v: SimVehicle) -> bool:
	return v.cards.has("caterpillar_tracks")


static func card_level(v: SimVehicle, id: String) -> int:
	return clampi(int(v.cards.get(id, 0)), 0, 3)


## Changes whenever the look of the rig changes (cheap cache key for the sprite stack).
static func signature(v: SimVehicle) -> String:
	var parts: PackedStringArray = [str(engineering(v)), str(v.color_index)]
	for id: String in v.cards:
		parts.append("%s%d" % [id, int(v.cards[id])])
	for w in v.weapons:
		parts.append(str(w.get("kind", "")))
	return ",".join(parts)


## Hull-fixed layers bottom to top: [[texture, row], ...] (all FRAME-sized, VEHICLE_DIRS columns).
static func hull_layers(v: SimVehicle) -> Array:
	var f: int = footprint(v)
	var out: Array = [[TEX_GEAR, f * 3 + gear_index(v)], [TEX_BODY, mini(engineering(v), 2)]]
	for l: Array in LEVEL_LAYERS:
		var lv: int = card_level(v, l[0])
		if lv > 0:
			out.append([l[1], f * 3 + lv - 1])
	for i in KIT_CARDS.size():
		if card_level(v, KIT_CARDS[i]) > 0:
			out.append([TEX_KIT, f * KIT_CARDS.size() + i])
	return out


static func gear_index(v: SimVehicle) -> int:
	if uses_tracks(v):
		return 2
	return 1 if v.cards.has("off_road_tyres") else 0


static func shadow_row(v: SimVehicle) -> int:
	return footprint(v) * 3 + gear_index(v)


## Guns in weapon order: [[kind, level], ...].
static func guns(v: SimVehicle) -> Array:
	var out: Array = []
	for w in v.weapons:
		var kind: String = str(w.get("kind", "mg"))
		if not GUN_TEX.has(kind):
			kind = "mg"
		out.append([kind, clampi(int(v.cards.get(kind, 1)), 1, 3)])
	return out


## One material per rig: resolves paint keys with the owner's paint job.
static func paint_material(color_index: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PAINT_SHADER
	m.set_shader_parameter("ramps", TEX_RAMPS)
	m.set_shader_parameter("paint_row", Gfx.color_slot(color_index))
	return m
