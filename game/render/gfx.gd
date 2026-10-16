class_name Gfx
extends RefCounted
## Shared render constants: textures exported by tools/artgen (--export-game-assets), palette
## colours (tools/artgen/palette.py), draw order and sheet helpers.
##
## Directional sprites are pre-rendered strips (frame k = rotated k * 360 / N degrees clockwise
## from north), so nothing is rotated on the GPU and pixels stay crisp at 640x360.

const VEHICLE_DIRS := 32
const ENEMY_DIRS := 16
const FX_DIRS := 16

const TEX_GROUND := preload("res://assets/ground_dune_sea.png")
## Hull strips per paint job, indexed by SimVehicle.color_index (tools/artgen/palette.py PLAYERS order).
const TEX_BUGGY: Array[Texture2D] = [preload("res://assets/buggy_red.png"), preload("res://assets/buggy_magenta.png"),
	preload("res://assets/buggy_blue.png"), preload("res://assets/buggy_green.png"), preload("res://assets/buggy_white.png"),
	preload("res://assets/buggy_purple.png"), preload("res://assets/buggy_lime.png"), preload("res://assets/buggy_black.png")]
const TEX_TURRET := preload("res://assets/turret_mg.png")
const TEX_MITE := preload("res://assets/mite.png")
const TEX_MITE_GLOW := preload("res://assets/mite_glow.png")
const TEX_BOULDER := preload("res://assets/boulder.png")
const TEX_BOULDER_GLOW := preload("res://assets/boulder_glow.png")
const TEX_SPITTER := preload("res://assets/spitter.png")
const TEX_SPITTER_GLOW := preload("res://assets/spitter_glow.png")
const TEX_TRACER := preload("res://assets/tracer.png")  ## rows: TRACER_* (plain, fire, shrapnel, AP, shard, saw)
const TEX_TRACER_GLOW := preload("res://assets/tracer_glow.png")
const TEX_ACID := preload("res://assets/acid.png")
const TEX_ACID_GLOW := preload("res://assets/acid_glow.png")
const TEX_MUZZLE := preload("res://assets/muzzle.png")  ## rows: plain, fire, shrapnel, AP (TRACER_* 0..3)
const TEX_MUZZLE_GLOW := preload("res://assets/muzzle_glow.png")
const TEX_EXPLOSION := preload("res://assets/explosion.png")
const TEX_EXPLOSION_GLOW := preload("res://assets/explosion_glow.png")
const TEX_EXPLOSION_BIG := preload("res://assets/explosion_big.png")  ## 10 frames, a rig going up
const TEX_EXPLOSION_BIG_GLOW := preload("res://assets/explosion_big_glow.png")
const TEX_WRECK := preload("res://assets/decal_wreck.png")  ## 4 cells of thrown scrap
const TEX_SKULL := preload("res://assets/ui_skull.png")  ## bounty mark over the leader
## Combat effects (tools/artgen/fx.py).
const TEX_FLAME := preload("res://assets/fx_flame.png")  ## 8 flicker frames x 3 sizes, 16x24 cells
const TEX_FLAME_GLOW := preload("res://assets/fx_flame_glow.png")
const TEX_SMOKE := preload("res://assets/fx_smoke.png")  ## 8 life frames x (grey, soot), 24x24
const TEX_OIL := preload("res://assets/fx_oil.png")  ## 3 puddles, 48x40
const TEX_BURN := preload("res://assets/decal_burn.png")  ## 4 scorch marks, 24x24
const TEX_KILL := preload("res://assets/fx_kill.png")  ## "KILL": flash, settled (32x12)
const TEX_KILL_GLOW := preload("res://assets/fx_kill_glow.png")
const TEX_BANNER := preload("res://assets/fx_banner.png")  ## contract pennant, 2 wave frames (14x18)
const FLAME_BASE_Y := 9.0  ## px from a flame cell's centre down to the flame's foot
const TRACER_PLAIN := 0
const TRACER_FIRE := 1
const TRACER_SHRAPNEL := 2
const TRACER_AP := 3
const TRACER_SHARD := 4
const TRACER_SAW := 5
const TRACER_ROWS := 6
## Shots of evolved weapons (Ammo.EVO_BIT; tools/artgen/fx.py tracer_evo): 16 directions x rows, 24x24 cells.
const TEX_TRACER_EVO := preload("res://assets/tracer_evo.png")
const TEX_TRACER_EVO_GLOW := preload("res://assets/tracer_evo_glow.png")
const EVO_GATLING := 0
const EVO_GRINDER := 1
const EVO_SHELL := 2
const EVO_TRACER_ROWS := 3
const TEX_HALO_CYAN := preload("res://assets/halo_cyan.png")
const TEX_HALO_WARM := preload("res://assets/halo_warm.png")
const TEX_HALO_WARM_BIG := preload("res://assets/halo_warm_big.png")
const TEX_GOO := preload("res://assets/decal_goo.png")
const TEX_GOO_BIG := preload("res://assets/decal_goo_big.png")
const TEX_CARCASS := preload("res://assets/decal_carcass.png")
const TEX_SCORCH := preload("res://assets/decal_scorch.png")
const TEX_FONT := preload("res://assets/font_3x5.png")
const TEX_UI_PLATE := preload("res://assets/ui_plate.png")
const TEX_STENCIL := preload("res://assets/font_stencil.png")
const TEX_ICONS := preload("res://assets/ui_icons.png")
const TEX_CARD := preload("res://assets/ui_card.png")
const TEX_CARD_EVO := preload("res://assets/ui_card_evo.png")  ## evolution (legendary) card: gunmetal in a brass frame
const TEX_TAPE := preload("res://assets/ui_tape.png")
const TEX_HAZARD := preload("res://assets/ui_hazard.png")
const TEX_STEEL := preload("res://assets/ui_steel.png")
const TEX_VIGNETTE := preload("res://assets/ui_vignette.png")
const TEX_LOGO := preload("res://assets/ui_logo_plate.png")  ## title plate; the words are set by MenuUi
const TEX_SPLAT := preload("res://assets/ui_splat.png")
## Cells of ui_icons.png (16x16 each), as in tools/artgen/ui.py ICON_NAMES.
const ICON_NAMES: PackedStringArray = ["mg", "shotgun", "cannon", "flamer", "armor", "mobility", "behavior",
	"ballistics", "engineering", "propulsion", "electronics", "salvage", "scrap", "fuel"]
const ICON_SIZE := 16

const SHEET_SHADER := preload("res://render/sheet.gdshader")
const SHEET_ADD_SHADER := preload("res://render/sheet_add.gdshader")
const SILHOUETTE_SHADER := preload("res://render/silhouette.gdshader")

## Turret pivot relative to the hull centre, buggy facing north (px).
const TURRET_PIVOT := Vector2(0, -4)
const BARREL_LENGTH := 15.0

# Draw order (z_index, all relative to the WorldView).
const Z_GROUND := -20
const Z_DECALS := -19
const Z_RING := -18  ## own-rig ground ring
const Z_SHADOWS := -10
const Z_ENEMIES := 0
const Z_FIRE := 1  ## flames: over burning aliens, under the rigs
const Z_VEHICLES := 2
const Z_RIG_DECO := 3  ## on the hull, under the guns (scrap baron chain)
const Z_TURRETS := 4
const Z_PROJECTILES := 5
const Z_EFFECTS := 6
const Z_GLOW := 8
const Z_LABELS := 9

# Palette (tools/artgen/palette.py).
const OUTLINE := Color("#1c1416")
const SHADOW := Color("#2f2a3d")
const SAND: Array[Color] = [Color("#6e4a36"), Color("#8e6145"), Color("#ad7d55"), Color("#c99c6b"), Color("#e0bd8c"), Color("#f0d9b0")]
const GLOW: Array[Color] = [Color("#0f3a40"), Color("#16646a"), Color("#1fa3a3"), Color("#4fe0d4"), Color("#a8fff2"), Color("#effffc")]
const FIRE: Array[Color] = [Color("#3a1a14"), Color("#7a2a14"), Color("#c4481c"), Color("#ef7d22"), Color("#ffb53d"), Color("#ffe48a"), Color("#fffbe0")]
const STEEL: Array[Color] = [Color("#1f1e24"), Color("#34343c"), Color("#4c4e58"), Color("#6c707a"), Color("#959aa3"), Color("#c3c7cc")]
const UI_TEXT := Color("#f0d9b0")
const UI_SHADOW := Color("#2a2224")
const UI_DIM := Color("#ad9b80")
const UI_BAD := Color("#e0623a")  ## warm warning red-orange (never cyan: cold = alien)
const UI_PLATE_DARK := Color("#3d3233")
const BONE_LIGHT := Color("#f2ead8")
const INK := Color("#2a1c18")  ## dark ink on paper tags
const INK_RED := Color("#a8341f")
const HAZARD := Color("#c9a227")
const BRASS: Array[Color] = [Color("#4a3414"), Color("#7a5a24"), Color("#a8823a"), Color("#d2ad5c")]
## Salvaged CRT terminal (doctrine): amber monochrome, a warm contrast to the desert (section 11f).
const CRT_BG := Color("#1d1209")
const CRT_DIM := Color("#8a5418")
const CRT_TEXT := Color("#ffb53d")
const CRT_HI := Color("#ffe48a")
## Card category tape colours (warm / neutral; GLOW stays reserved for aliens).
const CATEGORY_COLORS := {
	"weapon": Color("#d8673e"), "armor": Color("#a3a8b0"), "mobility": Color("#d6ad30"), "behavior": Color("#a9a66a"),
	"evolution": Color("#d2ad5c"),  # BRASS[3]: legendary evolution cards (their own brass-framed card, ui_card_evo.png)
}
## Player paint (PLAYERS ramp, step 3), indexed by SimVehicle.color_index (0..7). Eight distinct
## paints: never cyan/teal (alien GLOW) and never yellow/orange (FIRE tracers); design doc 11c.
const PLAYER_COLORS: Array[Color] = [Color("#d9473a"), Color("#c84aae"), Color("#3f6ae4"), Color("#3fa449"),
	Color("#e4e1da"), Color("#8549d0"), Color("#9fcb2c"), Color("#27262c")]
const PLAYER_NAMES: PackedStringArray = ["RED", "MAGENTA", "BLUE", "GREEN", "WHITE", "PURPLE", "LIME", "BLACK"]
## Paints too dark for the usual dark text shadow: their text gets a light rim instead.
const DARK_PAINT := 7


static func player_index(v: SimVehicle) -> int:
	return color_slot(v.color_index)


## A colour index clamped to the paint table (robust against junk from older snapshots).
static func color_slot(color_index: int) -> int:
	return clampi(color_index, 0, PLAYER_COLORS.size() - 1)


## Frame index for a world angle (radians, Godot convention 0 = east) in an N-frame strip.
static func frame_for_angle(angle: float, dirs: int) -> int:
	return posmod(roundi((angle + PI / 2.0) / (TAU / float(dirs))), dirs)


## The rotation a strip frame actually shows (clockwise from north), for placing attachments.
static func frame_rotation(frame: int, dirs: int) -> float:
	return float(frame) * TAU / float(dirs)


static func snap(p: Vector2) -> Vector2:
	return Vector2(floorf(p.x + 0.5), floorf(p.y + 0.5))


## Region of cell (col, row) in a sheet with square or rectangular cells.
static func cell_rect(tex: Texture2D, cols: int, rows: int, col: int, row: int) -> Rect2:
	var cw: float = float(tex.get_width()) / float(cols)
	var ch: float = float(tex.get_height()) / float(rows)
	return Rect2(col * cw, row * ch, cw, ch)


## Centred quad (2D vertices) for MultiMesh instances; even sizes keep texels on pixel centres.
static func quad_mesh(size: Vector2) -> ArrayMesh:
	var h := size / 2.0
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Cheap deterministic hash of a position + salt, for picking decal variants without an rng.
static func hash_pos(p: Vector2, salt: int) -> int:
	var h: int = int(p.x * 7.0) * 73856093 ^ int(p.y * 7.0) * 19349663 ^ salt * 83492791
	return absi(h)
