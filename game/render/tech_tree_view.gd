class_name TechTreeView
extends RefCounted
## Full tech tree panel of the workshop (design doc section 5b), opened with T or the TECH TREE
## button. Five branch columns (core spine of 6 tiers with a pick-one fork after tiers 2 and 4),
## a fusion row (nodes that need tier 3 in two branches) and an info strip for the hovered node.
## Drawn into the WorkshopUi canvas; clicks are registered as its hits ("tech", id).

const TITLE_H := 16.0
const HEAD_H := 13.0
const ROW_H := 20.0
const NODE_H := 17.0
const FUSION_H := 18.0
## Layout rows of a branch column: [kind, core tier].
const ROWS: Array = [["core", 1], ["core", 2], ["spec", 2], ["core", 3], ["core", 4], ["spec", 4], ["core", 5], ["core", 6]]

## Node states, also used by the compact column.
enum State { OWNED, BUYABLE, POOR, LOCKED, EXCLUDED }


static func state(v: SimVehicle, id: String) -> State:
	if v.tech.has(id):
		return State.OWNED
	if Tech.blocked_by(v, id) != "":
		return State.EXCLUDED
	if Tech.missing(v, id) != "":
		return State.LOCKED
	return State.BUYABLE if v.scrap >= Tech.cost(id) else State.POOR


## Draws the tree into `r` and returns the hovered tech id ("" = none).
static func draw(ui: WorkshopUi, v: SimVehicle, r: Rect2) -> String:
	UiKit.plate(ui, r)
	var x0: float = r.position.x + 4.0
	var y: float = r.position.y + 4.0
	PixelFont.draw_big(ui, "TECH TREE", Vector2(x0 + 2, y + 1), Gfx.UI_TEXT, Gfx.OUTLINE)
	var sub := "%d / %d BUILT   FORKS: PICK ONE, THE OTHERS LOCK" % [v.tech.size(), Tech.count()]
	PixelFont.draw(ui, sub, Vector2(x0 + 66, y + 2), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var close := Rect2(r.end.x - 70, y - 1, 66, 12)
	UiKit.steel(ui, close)
	if ui.is_hover("tree", false):
		UiKit.outline_rect(ui, close, Gfx.HAZARD)
	UiKit.center_text(ui, "CLOSE  T", close.get_center().x, close.position.y + 4, Gfx.UI_TEXT, Gfx.OUTLINE)
	ui.add_hit(close, "tree", false)
	y += TITLE_H

	var hover_id: String = ""
	var col_w: float = floorf((r.size.x - 8.0) / float(Tech.BRANCHES.size()))
	var node_w: float = col_w - 6.0
	for bi in Tech.BRANCHES.size():
		var b: String = Tech.BRANCHES[bi]
		var cx: float = x0 + bi * col_w + 3.0
		# branch header
		UiKit.icon(ui, b, Vector2(cx, y - 3))
		PixelFont.draw(ui, b.to_upper(), Vector2(cx + 18, y + 1), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiKit.pips(ui, Vector2(cx + node_w - 31, y + 1), Tech.branch_tier(v, b), Tech.MAX_TIER, Gfx.BRASS[3])
		var ry: float = y + HEAD_H
		# spine rail behind the nodes
		var rail_x: float = floorf(cx + node_w / 2.0)
		ui.draw_rect(Rect2(rail_x - 1, ry + NODE_H, 3, ROW_H * (ROWS.size() - 1) - NODE_H + 1), Gfx.OUTLINE)
		ui.draw_rect(Rect2(rail_x, ry + NODE_H, 1, ROW_H * (ROWS.size() - 1) - NODE_H + 1),
			Gfx.BRASS[2] if Tech.branch_tier(v, b) >= Tech.MAX_TIER else Gfx.STEEL[2])
		for row: Array in ROWS:
			var tier: int = int(row[1])
			if row[0] == "core":
				var id: String = "%s_%d" % [b, tier]
				var nr := Rect2(cx, ry, node_w, NODE_H)
				_node(ui, v, id, nr, UiKit.tech_name(id), "%s %d" % ["TIER", tier])
				if ui.is_hover("tech", id):
					hover_id = id
			else:
				var sp: Array[String] = Tech.specs(b, tier)
				var gap: float = 2.0
				var sw: float = floorf((node_w - gap * (sp.size() - 1)) / float(sp.size()))
				# fork bracket hanging off the core node above
				ui.draw_rect(Rect2(cx + floorf(sw / 2.0), ry - 2, node_w - sw + 1, 1), Gfx.OUTLINE)
				for k in sp.size():
					var nr2 := Rect2(cx + k * (sw + gap), ry, sw, NODE_H)
					_node(ui, v, sp[k], nr2, str(Tech.def(sp[k])["short"]), "")
					if ui.is_hover("tech", sp[k]):
						hover_id = sp[k]
			ry += ROW_H
	y += HEAD_H + ROW_H * ROWS.size()

	# fusions
	PixelFont.draw(ui, "FUSIONS - NEED TIER %d IN BOTH BRANCHES" % Tech.FUSION_TIER, Vector2(x0 + 3, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 8.0
	var fus: Array[String] = Tech.ids("", "fusion")
	for k in fus.size():
		var id2: String = fus[k]
		var req: Array = Tech.requirements(id2)
		var tag := "%s+%s" % [str(Tech.def(str(req[0]))["branch"]).left(3).to_upper(), str(Tech.def(str(req[1]))["branch"]).left(3).to_upper()]
		var fr := Rect2(x0 + k * col_w + 3.0, y, node_w, FUSION_H - 1)
		_node(ui, v, id2, fr, UiKit.tech_name(id2), tag)
		if ui.is_hover("tech", id2):
			hover_id = id2
	y += FUSION_H + 3.0

	_info(ui, v, hover_id, Rect2(x0, y, r.size.x - 8.0, r.end.y - y - 4.0))
	return hover_id


## One node: name on top, cost (or state) below. `tag` replaces the tier label on the left.
static func _node(ui: WorkshopUi, v: SimVehicle, id: String, nr: Rect2, label: String, tag: String) -> void:
	var st: State = state(v, id)
	var hov: bool = ui.is_hover("tech", id)
	ui.add_hit(nr, "tech", id)
	var cost: int = Tech.cost(id)
	var lx: float = nr.position.x + 3.0
	var fit: String = label
	while PixelFont.width(fit) > nr.size.x - 5.0 and fit.length() > 1:
		fit = fit.left(fit.length() - 1)
	match st:
		State.OWNED:
			ui.draw_rect(nr, Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.BRASS[2])
			ui.draw_rect(Rect2(nr.position + Vector2.ONE, Vector2(nr.size.x - 2, 1)), Gfx.BRASS[3])
			PixelFont.draw(ui, fit, Vector2(lx, nr.position.y + 3), Gfx.INK)
			_lower(ui, nr, tag, "BUILT", Gfx.BRASS[0], Gfx.BRASS[0])
			if hov:
				UiKit.outline_rect(ui, nr, Gfx.UI_TEXT)
		State.LOCKED, State.EXCLUDED:
			ui.draw_rect(nr, Gfx.UI_DIM if hov else Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.STEEL[1])
			PixelFont.draw(ui, fit, Vector2(lx, nr.position.y + 3), Gfx.STEEL[3])
			if st == State.EXCLUDED:
				# struck through: the other fork was taken
				ui.draw_rect(Rect2(nr.position.x + 2, nr.position.y + 5, nr.size.x - 4, 1), Gfx.INK_RED)
				_lower(ui, nr, tag, "LOCKED", Gfx.STEEL[3], Gfx.INK_RED)
			else:
				_lower(ui, nr, tag, str(cost), Gfx.STEEL[3], Gfx.STEEL[3])
		_:
			var afford: bool = st == State.BUYABLE
			UiKit.steel(ui, nr, Color.WHITE if afford else Color(0.75, 0.7, 0.7))
			if afford:
				UiKit.outline_rect(ui, nr, Gfx.HAZARD if (hov or fmod(ui.blink(), 1.2) < 0.9) else Gfx.OUTLINE)
			elif hov:
				UiKit.outline_rect(ui, nr, Gfx.UI_BAD)
			PixelFont.draw(ui, fit, Vector2(lx, nr.position.y + 3), Gfx.UI_TEXT, Gfx.OUTLINE)
			var txt := str(cost)
			var px: float = nr.end.x - 4.0 - PixelFont.width(txt) - 9.0
			if tag != "" and nr.size.x > 60.0:
				PixelFont.draw(ui, tag, Vector2(lx, nr.position.y + 10), Gfx.STEEL[4] if afford else Gfx.STEEL[3])
			ui.scrap_pip(Vector2(px, nr.position.y + 10))
			PixelFont.draw(ui, txt, Vector2(px + 9, nr.position.y + 10), Gfx.UI_TEXT if afford else Gfx.UI_BAD, Gfx.OUTLINE)


## Lower line of a node: `tag` on the left (wide nodes only), `right` on the right.
static func _lower(ui: WorkshopUi, nr: Rect2, tag: String, right: String, tag_col: Color, col: Color) -> void:
	if tag != "" and nr.size.x > 60.0:
		PixelFont.draw(ui, tag, Vector2(nr.position.x + 3, nr.position.y + 10), tag_col)
	PixelFont.draw(ui, right, Vector2(nr.end.x - 4.0 - PixelFont.width(right), nr.position.y + 10), col)


## Info strip: the hovered node, else a hint.
static func _info(ui: WorkshopUi, v: SimVehicle, id: String, r: Rect2) -> void:
	ui.draw_rect(r, Color(0.08, 0.05, 0.06, 0.6))
	UiKit.outline_rect(ui, r, Gfx.OUTLINE)
	var p: Vector2 = r.position + Vector2(5, 4)
	if id == "":
		PixelFont.draw(ui, "HOVER A NODE FOR DETAILS, CLICK TO BUILD", p, Gfx.UI_DIM)
		PixelFont.draw(ui, "CORE TIERS BUILD ON EACH OTHER. AFTER TIER 2 AND TIER 4 EVERY BRANCH FORKS:", p + Vector2(0, 10), Gfx.UI_DIM)
		PixelFont.draw(ui, "PICK ONE SPECIALISATION, THE OTHERS LOCK FOR THE MATCH. FUSIONS JOIN TWO BRANCHES.", p + Vector2(0, 18), Gfx.UI_DIM)
		PixelFont.draw(ui, "SCRAP YOU HOLD EARNS INTEREST, SO SAVING FOR A BIG NODE IS A PLAN TOO.", p + Vector2(0, 28), Gfx.UI_DIM)
		return
	var d: Dictionary = Tech.def(id)
	var kind: String = str(d["kind"])
	var where: String
	match kind:
		"spec": where = "%s - FORK AFTER TIER %d" % [str(d["branch"]).to_upper(), int(d["tier"])]
		"fusion": where = "FUSION"
		_: where = "%s - TIER %d" % [str(d["branch"]).to_upper(), int(d["tier"])]
	PixelFont.draw(ui, where, p, Gfx.UI_DIM)
	PixelFont.draw_big(ui, UiKit.tech_name(id), p + Vector2(0, 8), Gfx.UI_TEXT, Gfx.OUTLINE)
	# effects in the middle
	var ex: float = r.position.x + 200.0
	var ly: float = r.position.y + 4.0
	PixelFont.draw(ui, "EFFECT", Vector2(ex, ly), Gfx.UI_DIM)
	ly += 8.0
	for ln in UiKit.tech_lines(id):
		PixelFont.draw(ui, ln, Vector2(ex, ly), Gfx.FIRE[4])
		ly += 7.0
	# requirements and status on the right
	var sx: float = r.position.x + 370.0
	var sy: float = r.position.y + 4.0
	PixelFont.draw(ui, "NEEDS", Vector2(sx, sy), Gfx.UI_DIM)
	sy += 8.0
	var req: Array = Tech.requirements(id)
	if req.is_empty():
		PixelFont.draw(ui, "NOTHING", Vector2(sx, sy), Gfx.UI_DIM)
		sy += 7.0
	for rq in req:
		var have: bool = v.tech.has(str(rq))
		PixelFont.draw(ui, ("+ " if have else "- ") + UiKit.tech_name(str(rq)), Vector2(sx, sy), Gfx.UI_TEXT if have else Gfx.UI_BAD)
		sy += 7.0
	var status: String
	var scol: Color = Gfx.UI_DIM
	match state(v, id):
		State.OWNED:
			status = "BUILT"
		State.EXCLUDED:
			status = "LOCKED: YOU TOOK %s" % UiKit.tech_name(Tech.blocked_by(v, id))
			scol = Gfx.UI_BAD
		State.LOCKED:
			status = "BUILD %s FIRST" % UiKit.tech_name(Tech.next_step(v, id))
			scol = Gfx.UI_BAD
		State.POOR:
			status = "%d MORE SCRAP" % (Tech.cost(id) - v.scrap)
			scol = Gfx.UI_BAD
		_:
			status = "CLICK TO BUILD - %d SCRAP" % Tech.cost(id)
			scol = Gfx.HAZARD
	if Tech.blocked_by(v, id) == "" and str(d["group"]) != "" and not v.tech.has(id):
		PixelFont.draw(ui, "LOCKS THE OTHER FORK NODES", Vector2(sx, sy + 2), Gfx.STEEL[4])
		sy += 7.0
	for ln in PixelFont.wrap(status, int(r.end.x - sx - 4.0)):
		PixelFont.draw(ui, ln, Vector2(sx, sy + 3), scol)
		sy += 7.0
