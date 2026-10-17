class_name HivePanel
extends RefCounted
## The hive signature panel of the workshop (design doc 7c): the two species this match has drawn, the round
## each one arrives in, and the next boss (Bosses.next_boss). Drawn in the PARTS view with the usual UiKit
## panel; the first workshop (round 1) adds a one-line counter-tip per species, later ones keep it compact.
## Reads the world only (hive_first and boss_first are synced in the snapshot).

const HINTS: PackedStringArray = [
	"FLYERS: DIVE, THEN PULL AWAY. NO RAMS, NO FLAMER, GUNS ONLY.",
	"BURSTS INTO 6-8 MITES. BURN OR BLAST IT TO KILL THE BROOD TOO.",
	"HEALS AND SPEEDS UP THE HORDE. KILL IT FIRST.",
]
const ROW := 9.0
const PAD := 6.0


static func full(world: SimWorld) -> bool:
	return world.round <= 1


## Height of the panel for `world` (so the workshop can stack it above the convoy).
static func height(world: SimWorld, w: float) -> float:
	var h: float = 16.0  # padding and the section title
	var species: Array[Dictionary] = Species.list(world)
	for e in species:
		h += ROW
		if full(world):
			h += UiFont.wrap_small(HINTS[int(e["kind"]) - SimWorld.GLASS], int(w - PAD * 2.0)).size() * 7.0 + 2.0
	h += 23.0  # next boss: a section line, the name row and padding
	return h


static func draw(ci: CanvasItem, world: SimWorld, r: Rect2) -> void:
	UiKit.panel(ci, r)
	var x0: float = r.position.x + PAD
	var w: float = r.size.x - PAD * 2.0
	var y: float = r.position.y + 5.0
	UiKit.section(ci, "HIVE SIGNATURE", Vector2(x0, y), w, "THIS MATCH")
	y += 11.0
	var next_round: int = world.round + 1
	for e in Species.list(world):
		var first: int = int(e["first"])
		var tag: String
		var tag_col: Color
		if first <= world.round:
			tag = "ACTIVE"
			tag_col = Gfx.UI_TEXT
		elif first == next_round:
			tag = "NEXT ROUND"
			tag_col = Gfx.HAZARD
		else:
			tag = "ROUND %d" % first
			tag_col = Gfx.UI_DIM
		UiFont.draw(ci, str(e["name"]), Vector2(x0, y), Gfx.UI_TEXT)
		UiFont.draw_small(ci, tag, Vector2(x0 + w - UiFont.width_small(tag), y + 1.0), tag_col)
		y += ROW
		if full(world):
			for line in UiFont.wrap_small(HINTS[int(e["kind"]) - SimWorld.GLASS], int(w)):
				UiFont.draw_small(ci, line, Vector2(x0, y), Gfx.UI_DIM)
				y += 7.0
			y += 2.0
	var nb: Dictionary = Bosses.next_boss(world)
	var when: String = "ROUND %d" % int(nb["round"])
	UiKit.section(ci, "NEXT BOSS", Vector2(x0, y + 1.0), w, when, Gfx.HAZARD if int(nb["round"]) == next_round else Gfx.UI_DIM)
	y += 11.0
	UiFont.draw(ci, str(nb["name"]), Vector2(x0, y - 1.0), Gfx.UI_BAD)
	if bool(nb["enraged"]):
		var en: String = "ENRAGED"
		UiFont.draw_small(ci, en, Vector2(x0 + w - UiFont.width_small(en), y), Gfx.UI_BAD)
