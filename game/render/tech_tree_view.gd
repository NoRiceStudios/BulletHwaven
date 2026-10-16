class_name TechTreeView
extends RefCounted
## The workshop's TECH view (design doc section 5b), opened with T or its tab. Five branch columns
## with one row per stage 1..6 (choices side by side, the prototype next to the stage 3 core), two
## fusion rows (small, large) and an info strip for the hovered node. Clicking a choice that is
## locked by its sibling swaps them (respec). Interim stage layout; a redesign follows. Hovering a node also marks the
## nodes still missing on the way to it. Drawn into the WorkshopUi canvas; clicks are registered as
## its hits ("tech", id).

const TITLE_H := 12.0
const HEAD_H := 13.0
const ROW_H := 23.0
const NODE_H := 18.0
const FUSION_H := 19.0

## Node states (also used for the TECH tab badge). INACTIVE = owned but a requirement is gone
## (no effect); EXCLUDED = a sibling choice is owned (click to swap).
enum State { OWNED, BUYABLE, POOR, LOCKED, EXCLUDED, INACTIVE }

static var _path: Dictionary = {}  ## tech ids still missing on the way to the hovered node


static func state(v: SimVehicle, id: String) -> State:
	if v.tech.has(id):
		return State.OWNED if Tech.active(v, id) else State.INACTIVE
	if Tech.blocked_by(v, id) != "":
		return State.EXCLUDED
	if Tech.missing(v, id) != "":
		return State.LOCKED
	return State.BUYABLE if v.scrap >= Tech.price(v, id) else State.POOR


## Draws the tree into `r` and returns the hovered tech id ("" = none).
static func draw(ui: WorkshopUi, v: SimVehicle, r: Rect2) -> String:
	UiKit.panel(ui, r)
	ui.add_hit(r, "none", null)
	var x0: float = r.position.x + 4.0
	var y: float = r.position.y + 5.0
	var lx: float = _legend(ui, Vector2(r.end.x - 8.0, y))
	UiKit.section(ui, "%d / %d BUILT    CHOICES: PICK ONE PER STAGE, CLICK ANOTHER TO SWAP" % [v.tech.size(), Tech.count()],
		Vector2(x0 + 2, y), lx - x0 - 10.0)
	y += TITLE_H
	_path = _missing_path(v, str(ui.hover_arg("tech")) if ui.hover_arg("tech") != null else "")

	var hover_id: String = ""
	var col_w: float = floorf((r.size.x - 8.0) / float(Tech.BRANCHES.size()))
	var node_w: float = col_w - 6.0
	for bi in Tech.BRANCHES.size():
		var b: String = Tech.BRANCHES[bi]
		var cx: float = x0 + bi * col_w + 3.0
		# branch header
		UiKit.icon(ui, b, Vector2(cx, y - 3))
		UiFont.draw(ui, b.to_upper(), Vector2(cx + 18, y + 1), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiKit.pips(ui, Vector2(cx + node_w - 31, y + 1), Tech.branch_tier(v, b), Tech.MAX_TIER, Gfx.BRASS[3])
		var ry: float = y + HEAD_H
		for tier in range(1, Tech.MAX_TIER + 1):
			var row: Array[String] = _row_ids(b, tier)
			var gap: float = 2.0
			var nw: float = floorf((node_w - gap * (row.size() - 1)) / float(row.size()))
			for k in row.size():
				var nr := Rect2(cx + k * (nw + gap), ry, nw, NODE_H)
				var single: bool = row.size() == 1
				_node(ui, v, row[k], nr, UiKit.tech_name(row[k]) if single else str(Tech.def(row[k])["short"]),
					"STAGE %d" % tier if single else ("PROTOTYPE" if Tech.def(row[k])["kind"] == "proto" else ""))
				if ui.is_hover("tech", row[k]):
					hover_id = row[k]
			ry += ROW_H
	y += HEAD_H + ROW_H * Tech.MAX_TIER

	# fusions: small row, large row
	UiFont.draw(ui, "FUSIONS - NEED A CHOICE FROM TWO BRANCHES, GO DORMANT IF YOU SWAP ONE AWAY", Vector2(x0 + 3, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 8.0
	for kind in ["fusion_s", "fusion_l"]:
		var fus: Array[String] = Tech.ids("", kind)
		var fw: float = floorf((r.size.x - 8.0) / float(fus.size()))
		for k in fus.size():
			var id2: String = fus[k]
			var req: Array = Tech.requirements(id2)
			var tag := "%s+%s" % [str(Tech.def(str(req[0]))["branch"]).left(3).to_upper(), str(Tech.def(str(req[1]))["branch"]).left(3).to_upper()]
			var fr := Rect2(x0 + k * fw + 3.0, y, fw - 6.0, FUSION_H - 1)
			_node(ui, v, id2, fr, UiKit.tech_name(id2), tag)
			if ui.is_hover("tech", id2):
				hover_id = id2
		y += FUSION_H + 1.0
	y += 2.0

	_info(ui, v, hover_id, Rect2(x0, y, r.size.x - 8.0, r.end.y - y - 4.0))
	return hover_id


## The nodes of `branch` at `tier` in table order: core / choices first, the prototype last.
static func _row_ids(branch: String, tier: int) -> Array[String]:
	var out: Array[String] = []
	for id in Tech.ids(branch):
		if int(Tech.def(id)["tier"]) == tier:
			out.append(id)
	return out


## Every inactive node the hovered node still needs, itself included ({} = no hover).
static func _missing_path(v: SimVehicle, id: String) -> Dictionary:
	var out: Dictionary = {}
	if id == "" or Tech.active(v, id):
		return out
	var todo: Array = [id]
	while not todo.is_empty():
		var cur: String = str(todo.pop_back())
		if out.has(cur) or Tech.active(v, cur):
			continue
		out[cur] = true
		var d: Dictionary = Tech.def(cur)
		for rq in d["requires"]:
			todo.append(str(rq))
		if Tech.missing(v, cur) != "" and not (d["any"] as Array).is_empty():
			todo.append(str(Tech.missing(v, cur)))
	return out


## Colour key (built, can build now, too expensive, locked) ending at `right`; returns its left x.
static func _legend(ui: WorkshopUi, right: Vector2) -> float:
	var items: Array = [["BUILT", Gfx.BRASS[2]], ["BUILD NOW", Gfx.HAZARD], ["NEED SCRAP", Gfx.UI_BAD], ["LOCKED", Gfx.STEEL[2]]]
	var x: float = right.x
	for i in range(items.size() - 1, -1, -1):
		var w: float = UiFont.width_small(items[i][0])
		x -= w
		UiFont.draw_small(ui, items[i][0], Vector2(x, right.y), Gfx.UI_DIM)
		x -= 7.0
		ui.draw_rect(Rect2(x, right.y, 5, 5), Gfx.OUTLINE)
		ui.draw_rect(Rect2(x + 1, right.y + 1, 3, 3), items[i][1])
		x -= 8.0
	return x


## One node: name on top, cost (or state) below. `tag` replaces the tier label on the left.
static func _node(ui: WorkshopUi, v: SimVehicle, id: String, nr: Rect2, label: String, tag: String) -> void:
	var st: State = state(v, id)
	var hov: bool = ui.is_hover("tech", id)
	if _path.has(id) and not hov:
		# on the way to the hovered node: a lit frame around it
		UiKit.outline_rect(ui, nr.grow(1.0), Gfx.UI_TEXT)
	ui.add_hit(nr, "tech", id)
	var cost: int = Tech.price(v, id)
	var lx: float = nr.position.x + 3.0
	var fit: String = label
	while UiFont.width(fit) > nr.size.x - 5.0 and fit.length() > 1:
		fit = fit.left(fit.length() - 1)
	match st:
		State.OWNED:
			ui.draw_rect(nr, Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.BRASS[2])
			ui.draw_rect(Rect2(nr.position + Vector2.ONE, Vector2(nr.size.x - 2, 1)), Gfx.BRASS[3])
			UiFont.draw(ui, fit, Vector2(lx, nr.position.y + 3), Gfx.INK)
			_lower(ui, nr, tag, "BUILT", Gfx.BRASS[0], Gfx.BRASS[0])
			if hov:
				UiKit.outline_rect(ui, nr, Gfx.UI_TEXT)
		State.LOCKED, State.EXCLUDED, State.INACTIVE:
			ui.draw_rect(nr, Gfx.UI_DIM if hov else Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.STEEL[1])
			UiFont.draw(ui, fit, Vector2(lx, nr.position.y + 3), Gfx.STEEL[3])
			if st == State.EXCLUDED:
				# struck through: a sibling was taken, click to swap
				ui.draw_rect(Rect2(nr.position.x + 2, nr.position.y + 5, nr.size.x - 4, 1), Gfx.INK_RED)
				_lower(ui, nr, tag, "SWAP", Gfx.STEEL[3], Gfx.STEEL[4])
			elif st == State.INACTIVE:
				_lower(ui, nr, tag, "IDLE", Gfx.STEEL[3], Gfx.INK_RED)
			else:
				_lower(ui, nr, tag, str(cost), Gfx.STEEL[3], Gfx.STEEL[3])
		_:
			var afford: bool = st == State.BUYABLE
			UiKit.steel(ui, nr, Color.WHITE if afford else Color(0.75, 0.7, 0.7))
			if afford:
				UiKit.outline_rect(ui, nr, Gfx.HAZARD if (hov or fmod(ui.blink(), 1.2) < 0.9) else Gfx.OUTLINE)
			elif hov:
				UiKit.outline_rect(ui, nr, Gfx.UI_BAD)
			UiFont.draw(ui, fit, Vector2(lx, nr.position.y + 3), Gfx.UI_TEXT, Gfx.OUTLINE)
			var txt := str(cost)
			var px: float = nr.end.x - 4.0 - UiFont.width(txt) - 9.0
			if tag != "" and nr.size.x > 60.0:
				UiFont.draw(ui, tag, Vector2(lx, nr.position.y + 10), Gfx.STEEL[4] if afford else Gfx.STEEL[3])
			ui.scrap_pip(Vector2(px, nr.position.y + 10))
			UiFont.draw(ui, txt, Vector2(px + 9, nr.position.y + 10), Gfx.UI_TEXT if afford else Gfx.UI_BAD, Gfx.OUTLINE)


## Lower line of a node: `tag` on the left (wide nodes only), `right` on the right.
static func _lower(ui: WorkshopUi, nr: Rect2, tag: String, right: String, tag_col: Color, col: Color) -> void:
	if tag != "" and nr.size.x > 60.0:
		UiFont.draw(ui, tag, Vector2(nr.position.x + 3, nr.position.y + 10), tag_col)
	UiFont.draw(ui, right, Vector2(nr.end.x - 4.0 - UiFont.width(right), nr.position.y + 10), col)


## Info strip: the hovered node, else a hint.
static func _info(ui: WorkshopUi, v: SimVehicle, id: String, r: Rect2) -> void:
	ui.draw_rect(r, Color(0.08, 0.05, 0.06, 0.6))
	UiKit.outline_rect(ui, r, Gfx.OUTLINE)
	var p: Vector2 = r.position + Vector2(5, 4)
	if id == "":
		UiFont.draw(ui, "HOVER A NODE FOR DETAILS, CLICK TO BUILD", p, Gfx.UI_DIM)
		UiFont.draw(ui, "STAGES BUILD ON EACH OTHER. PICK ONE CHOICE PER STAGE; CLICK A LOCKED ONE TO SWAP.", p + Vector2(0, 10), Gfx.UI_DIM)
		UiFont.draw(ui, "THE FIRST SWAP IS FREE. FUSIONS JOIN TWO BRANCHES AND SLEEP IF YOU SWAP A PART AWAY.", p + Vector2(0, 18), Gfx.UI_DIM)
		UiFont.draw(ui, "SCRAP YOU HOLD EARNS INTEREST, SO SAVING FOR A BIG NODE IS A PLAN TOO.", p + Vector2(0, 28), Gfx.UI_DIM)
		return
	var d: Dictionary = Tech.def(id)
	var kind: String = str(d["kind"])
	var where: String
	match kind:
		"choice": where = "%s - STAGE %d CHOICE" % [str(d["branch"]).to_upper(), int(d["tier"])]
		"proto": where = "%s - STAGE %d PROTOTYPE" % [str(d["branch"]).to_upper(), int(d["tier"])]
		"fusion_s": where = "SMALL FUSION"
		"fusion_l": where = "LARGE FUSION"
		_: where = "%s - STAGE %d" % [str(d["branch"]).to_upper(), int(d["tier"])]
	UiFont.draw(ui, where, p, Gfx.UI_DIM)
	UiFont.draw_big(ui, UiKit.tech_name(id), p + Vector2(0, 8), Gfx.UI_TEXT, Gfx.OUTLINE)
	# effects in the middle
	var ex: float = r.position.x + 200.0
	var ly: float = r.position.y + 4.0
	UiFont.draw(ui, "EFFECT", Vector2(ex, ly), Gfx.UI_DIM)
	ly += 8.0
	for ln in UiKit.tech_lines(id):
		UiFont.draw(ui, ln, Vector2(ex, ly), Gfx.FIRE[4])
		ly += 7.0
	# requirements and status on the right
	var sx: float = r.position.x + 370.0
	var sy: float = r.position.y + 4.0
	UiFont.draw(ui, "NEEDS", Vector2(sx, sy), Gfx.UI_DIM)
	sy += 8.0
	var req: Array = Tech.requirements(id)
	if req.is_empty():
		UiFont.draw(ui, "NOTHING", Vector2(sx, sy), Gfx.UI_DIM)
		sy += 7.0
	if req.size() > 1 and (d["requires"] as Array).is_empty():
		UiFont.draw(ui, "ONE OF", Vector2(sx, sy), Gfx.UI_DIM)
		sy += 7.0
	for rq in req:
		var have: bool = Tech.active(v, str(rq))
		UiFont.draw(ui, ("+ " if have else "- ") + UiKit.tech_name(str(rq)), Vector2(sx, sy), Gfx.UI_TEXT if have else Gfx.UI_BAD)
		sy += 7.0
	var status: String
	var scol: Color = Gfx.UI_DIM
	match state(v, id):
		State.OWNED:
			status = "BUILT"
		State.INACTIVE:
			status = "NO EFFECT: NEEDS %s" % UiKit.tech_name(Tech.missing(v, id))
			scol = Gfx.UI_BAD
		State.EXCLUDED:
			var sw: String = Tech.blocked_by(v, id)
			if Tech.can_respec(v, sw, id, ui.world.round):
				status = "CLICK TO SWAP FOR %s - %d SCRAP" % [UiKit.tech_name(sw), Tech.respec_cost(v, id)]
				scol = Gfx.HAZARD
			else:
				status = "SWAP FROM %s NOT POSSIBLE NOW" % UiKit.tech_name(sw)
				scol = Gfx.UI_BAD
		State.LOCKED:
			status = "BUILD %s FIRST" % UiKit.tech_name(Tech.next_step(v, id))
			scol = Gfx.UI_BAD
		State.POOR:
			status = "%d MORE SCRAP" % (Tech.price(v, id) - v.scrap)
			scol = Gfx.UI_BAD
		_:
			status = "CLICK TO BUILD - %d SCRAP" % Tech.price(v, id)
			scol = Gfx.HAZARD
	if _path.size() > 1:
		var total: int = 0
		for pid: String in _path:
			total += Tech.price(v, pid)
		UiFont.draw(ui, "PATH: %d NODES, %d SCRAP IN ALL" % [_path.size(), total], Vector2(sx, sy + 2), Gfx.UI_TEXT)
		sy += 9.0
	if Tech.blocked_by(v, id) == "" and str(d["group"]) != "" and not v.tech.has(id):
		UiFont.draw(ui, "PICK ONE PER STAGE", Vector2(sx, sy + 2), Gfx.STEEL[4])
		sy += 7.0
	for ln in UiFont.wrap(status, int(r.end.x - sx - 4.0)):
		UiFont.draw(ui, ln, Vector2(sx, sy + 3), scol)
		sy += 7.0
