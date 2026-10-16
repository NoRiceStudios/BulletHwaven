class_name TechTreeView
extends RefCounted
## The workshop's TECH view (design doc section 5b, tech tree v2.3 sections 2, 5, 7 and 8), opened with T
## or its tab. Drawn into the WorkshopUi canvas; clicks are registered as its hits.
##
## Layout (640x360 units, top to bottom inside the body):
## - a tool row: BUILD PLAN chips (FIREBRAND / FORTRESS / SCRAPPER, "tpl"), the BEGINNER VIEW toggle
##   ("beginner") and the built count;
## - one column per branch: icon, name and stage pips, the branch's one-sentence pitch, then six stage
##   rows (choices side by side, the prototype clamped to the stage 3 core, keystones with brass
##   corners). The beginner view expands only the plan's two branches; the others shrink to narrow
##   columns of state chips under MORE (header click "expand" opens one). Everything stays buyable;
## - two fusion rows (small, large), each node tagged with its two requirements;
## - the detail panel for the hovered node: effects, what you see, who it is for, the net preview on
##   your own rig, fusion partners, swap price and what a swap greys out. With nothing hovered it shows
##   the plan's cheat sheet and the legend. It stays on the last node while the pointer is on it, so
##   the underlined glossary words ("gloss") can be hovered for their explanation.
## Hovering a fusion dims everything except the fusion and the two nodes it needs; hovering a locked node
## frames the path to it. The next node of the plan pulses amber. Clicking a node builds it; clicking
## one locked by its sibling opens the swap confirmation (WorkshopUi.confirm, drawn by draw_confirm()).

const TOOL_H := 14.0
const HEAD_H := 12.0
const PITCH_H := 15.0
const ROW_H := 21.0
const NODE_H := 18.0
const FUS_LABEL_H := 9.0
const FUS_H := 19.0
const GUTTER := 9.0
const COL_GAP := 4.0
const COLLAPSED_W := 46.0
const DETAIL_H := 83.0
const DIM_WASH := Color(0.06, 0.04, 0.035, 0.68)

## Node states (also used for the TECH tab badge). INACTIVE = owned but a requirement is gone (no
## effect); EXCLUDED = a sibling choice is owned (click to swap).
enum State { OWNED, BUYABLE, POOR, LOCKED, EXCLUDED, INACTIVE }

static var _focus: Dictionary = {}  ## ids framed for the hovered node (its path, a fusion's parts)
static var _partner: Dictionary = {}  ## fusions (and their other parts) of the hovered choice
static var _dim: bool = false  ## a fusion is hovered: wash out everything outside _focus
static var _sticky: String = ""  ## node the detail panel keeps while the pointer is on the panel
static var _next: String = ""  ## next node of the build plan
static var _tpl: Dictionary = {}
static var _rects: Dictionary = {}  ## tech id -> Rect2 drawn this frame


static func state(v: SimVehicle, id: String) -> State:
	if v.tech.has(id):
		return State.OWNED if Tech.active(v, id) else State.INACTIVE
	if Tech.blocked_by(v, id) != "":
		return State.EXCLUDED
	if Tech.missing(v, id) != "":
		return State.LOCKED
	return State.BUYABLE if v.scrap >= Tech.price(v, id) else State.POOR


## Fusions `v` could build now (both parts active, not owned), cheapest first.
static func fusions_ready(v: SimVehicle) -> Array[String]:
	var out: Array[String] = []
	for f in Tech.fusions():
		if Tech.unlocked(v, f):
			out.append(f)
	return out


## Draws the tree into `r` and returns the hovered tech id ("" = none).
static func draw(ui: WorkshopUi, v: SimVehicle, r: Rect2) -> String:
	UiKit.panel(ui, r)
	ui.add_hit(r, "none", null)
	_rects.clear()
	var x0: float = r.position.x + 4.0
	var w: float = r.size.x - 8.0
	var y: float = r.position.y + 4.0
	_tpl = TechGuide.template_for(ui.world, v)
	_next = TechGuide.next_on_path(v, _tpl)
	var det := Rect2(x0, r.end.y - DETAIL_H - 4.0, w, DETAIL_H)
	var hov_arg: Variant = ui.hover_arg("tech")
	var hov_id: String = str(hov_arg) if hov_arg != null else ""
	if hov_id != "":
		_sticky = hov_id
	elif not det.has_point(ui.pointer()) or not ui.confirm.is_empty():
		_sticky = ""
	_set_focus(v, hov_id)

	_tool_row(ui, v, Vector2(x0, y), w)
	y += TOOL_H
	_tree(ui, v, Rect2(x0, y, w, HEAD_H + PITCH_H + ROW_H * Tech.MAX_TIER))
	y += HEAD_H + PITCH_H + ROW_H * Tech.MAX_TIER
	_fusion_rows(ui, v, Rect2(x0 + GUTTER, y, w - GUTTER, FUS_LABEL_H + 2.0 * (FUS_H + 1.0)))

	var tpl_hov: Variant = ui.hover_arg("tpl")
	_detail(ui, v, _sticky, str(tpl_hov) if tpl_hov != null else "", det)
	return hov_id


static func _set_focus(v: SimVehicle, id: String) -> void:
	_focus.clear()
	_partner.clear()
	_dim = false
	if id == "":
		return
	if Tech.is_fusion(id):
		_dim = true
		_focus[id] = true
		for rq in Tech.requirements(id):
			_focus[str(rq)] = true
			for p in TechGuide.build_path(v, str(rq), _tpl.get("path", [])):
				_focus[p] = true
		return
	for p in TechGuide.build_path(v, id, _tpl.get("path", [])):
		_focus[p] = true
	for f in Tech.fusion_partners(id):
		_partner[f] = true
		for rq in Tech.requirements(f):
			if str(rq) != id:
				_partner[str(rq)] = true


# ---------------------------------------------------------------- tool row

static func _tool_row(ui: WorkshopUi, v: SimVehicle, p: Vector2, w: float) -> void:
	var x: float = UiFont.draw_small(ui, "BUILD PLAN", Vector2(p.x + 2, p.y + 3), Gfx.UI_DIM) + 5.0
	var picked: bool = TechGuide.is_picked(ui.world)
	for t: Dictionary in TechGuide.TEMPLATES:
		var on: bool = t["id"] == _tpl["id"]
		var label: String = str(t["name"])
		var sub: String = "%s+%s" % [str(t["branches"][0]).left(3).to_upper(), str(t["branches"][1]).left(3).to_upper()]
		var cw: float = UiFont.width(label) + UiFont.width_small(sub) + 14.0
		var cr := Rect2(x, p.y, cw, 11)
		var hov: bool = ui.is_hover("tpl", t["id"])
		ui.draw_rect(cr, Gfx.OUTLINE)
		if on:
			ui.draw_rect(cr.grow(-1.0), Gfx.FIRE[4] if picked else Gfx.BRASS[2])
			ui.draw_rect(Rect2(cr.position + Vector2.ONE, Vector2(cr.size.x - 2, 1)), Gfx.FIRE[5] if picked else Gfx.BRASS[3])
		else:
			ui.draw_rect(cr.grow(-1.0), Color(0.18, 0.13, 0.1) if hov else Color(0.11, 0.08, 0.07))
			UiKit.outline_rect(ui, cr.grow(-1.0), Gfx.FIRE[3] if hov else UiKit.PANEL_EDGE)
		var tx: float = UiFont.draw(ui, label, Vector2(cr.position.x + 4, p.y + 3), Gfx.INK if on else (Gfx.FIRE[5] if hov else Gfx.UI_TEXT))
		UiFont.draw_small(ui, sub, Vector2(tx + 4, p.y + 3), Color(Gfx.INK, 0.7) if on else Gfx.UI_DIM)
		ui.add_hit(cr, "tpl", t["id"])
		x = cr.end.x + 3.0
	if not picked:
		UiFont.draw_small(ui, "(SUGGESTED - CLICK ONE TO FOLLOW IT)", Vector2(x + 2, p.y + 3), Gfx.UI_DIM)
	# right: built count, then the beginner toggle
	var beg: bool = TechGuide.beginner()
	var bl: String = "BEGINNER VIEW: %s" % ("ON" if beg else "OFF")
	var bw: float = UiFont.width_small(bl) + 10.0
	var br := Rect2(p.x + w - bw, p.y, bw, 11)
	var bh: bool = ui.is_hover("beginner")
	ui.draw_rect(br, Gfx.OUTLINE)
	ui.draw_rect(br.grow(-1.0), Color(0.18, 0.13, 0.1) if bh else Color(0.11, 0.08, 0.07))
	UiKit.outline_rect(ui, br.grow(-1.0), Gfx.FIRE[3] if bh else UiKit.PANEL_EDGE)
	var lx: float = UiFont.draw_small(ui, "BEGINNER VIEW: ", Vector2(br.position.x + 5, p.y + 3), Gfx.UI_DIM)
	UiFont.draw_small(ui, "ON" if beg else "OFF", Vector2(lx, p.y + 3), Gfx.FIRE[4] if beg else Gfx.UI_TEXT)
	ui.add_hit(br, "beginner", not beg)
	var cnt: String = "%d / %d BUILT" % [v.tech.size(), Tech.count()]
	UiFont.draw_small(ui, cnt, Vector2(br.position.x - 8 - UiFont.width_small(cnt), p.y + 3), Gfx.UI_DIM)


# ---------------------------------------------------------------- branch columns

static func _tree(ui: WorkshopUi, v: SimVehicle, r: Rect2) -> void:
	var beg: bool = TechGuide.beginner()
	var order: Array[String] = []
	var open: Dictionary = {}
	if beg:
		for b: String in _tpl["branches"]:
			order.append(b)
			open[b] = true
		for b in Tech.BRANCHES:
			if not order.has(b):
				order.append(b)
				if TechGuide.is_opened(b):
					open[b] = true
	else:
		for b in Tech.BRANCHES:
			order.append(b)
			open[b] = true
	var n_open: int = open.size()
	var n_closed: int = order.size() - n_open
	var avail: float = r.size.x - GUTTER - COL_GAP * float(order.size() - 1) - (4.0 if n_closed > 0 else 0.0)
	var open_w: float = floorf((avail - COLLAPSED_W * n_closed) / float(n_open))
	# stage numbers in the gutter
	var ry0: float = r.position.y + HEAD_H + PITCH_H
	for tier in range(1, Tech.MAX_TIER + 1):
		var gy: float = ry0 + (tier - 1) * ROW_H + 6.0
		UiFont.draw_small(ui, str(tier), Vector2(r.position.x + 2, gy), Gfx.BRASS[3] if tier == Tech.MAX_TIER else Gfx.UI_DIM)
	var x: float = r.position.x + GUTTER
	var closed_x: float = -1.0
	# MORE first gets its group title, so the open plan columns come first and the rest after a gap
	var sorted: Array[String] = []
	for b in order:
		if open.has(b):
			sorted.append(b)
	for b in order:
		if not open.has(b):
			sorted.append(b)
	for b in sorted:
		if open.has(b):
			_column(ui, v, b, Rect2(x, r.position.y, open_w, r.size.y), beg and not (_tpl["branches"] as Array).has(b))
			x += open_w + COL_GAP
		else:
			if closed_x < 0.0:
				x += 4.0
				closed_x = x
			_collapsed(ui, v, b, Rect2(x, r.position.y, COLLAPSED_W, r.size.y))
			x += COLLAPSED_W + COL_GAP
	if closed_x >= 0.0:
		UiKit.section(ui, "MORE", Vector2(closed_x, r.position.y + 2), x - COL_GAP - closed_x)
		ui.draw_rect(Rect2(closed_x - 5.0, r.position.y + 2, 1, r.size.y - 4), Color(UiKit.PANEL_EDGE, 0.8))


## One open branch: header, pitch, six stage rows. `closable`: opened from MORE (header click closes it).
static func _column(ui: WorkshopUi, v: SimVehicle, b: String, r: Rect2, closable: bool) -> void:
	var cx: float = r.position.x
	var y: float = r.position.y
	var plan: bool = (_tpl["branches"] as Array).has(b)
	UiKit.icon(ui, b, Vector2(cx, y - 3))
	UiFont.draw(ui, b.to_upper(), Vector2(cx + 18, y + 1), Gfx.FIRE[4] if plan else Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiKit.pips(ui, Vector2(r.end.x - 31, y + 1), Tech.branch_tier(v, b), Tech.MAX_TIER, Gfx.BRASS[3])
	if closable:
		var hr := Rect2(cx, y - 2, r.size.x, HEAD_H)
		var hov: bool = ui.is_hover("expand", b)
		UiFont.draw_small(ui, "CLOSE", Vector2(r.end.x - 31 - 6 - UiFont.width_small("CLOSE"), y + 2), Gfx.FIRE[5] if hov else Gfx.UI_DIM)
		ui.add_hit(hr, "expand", b)
	y += HEAD_H
	var pitch: PackedStringArray = UiFont.wrap_small(str(TechGuide.PITCH.get(b, "")), int(r.size.x) - 2)
	for k in mini(pitch.size(), 2):
		_gloss_line(ui, pitch[k], Vector2(cx + 1, y + k * 7.0), Gfx.UI_DIM, true)
	y += PITCH_H
	for tier in range(1, Tech.MAX_TIER + 1):
		var row: Array[String] = _row_ids(b, tier)
		if tier == 3 and row.size() == 2:
			var cw: float = floorf((r.size.x - 5.0) * 0.56)
			var core_r := Rect2(cx, y, cw, NODE_H)
			var proto_r := Rect2(cx + cw + 5.0, y, r.size.x - cw - 5.0, NODE_H)
			# the clamp that bolts the prototype to the core
			ui.draw_rect(Rect2(core_r.end.x - 1, y + 5, 7, 7), Gfx.OUTLINE)
			ui.draw_rect(Rect2(core_r.end.x, y + 6, 5, 5), Gfx.STEEL[3])
			ui.draw_rect(Rect2(core_r.end.x + 2, y + 8, 1, 1), Gfx.OUTLINE)
			_node(ui, v, row[0], core_r)
			_node(ui, v, row[1], proto_r)
		else:
			var gap: float = 2.0
			var nw: float = floorf((r.size.x - gap * (row.size() - 1)) / float(row.size()))
			for k in row.size():
				var last: bool = k == row.size() - 1
				var nr := Rect2(cx + k * (nw + gap), y, (r.end.x - (cx + k * (nw + gap))) if last else nw, NODE_H)
				_node(ui, v, row[k], nr)
		y += ROW_H


## A branch folded under MORE: short name and pips (click to open), then a chip per node.
static func _collapsed(ui: WorkshopUi, v: SimVehicle, b: String, r: Rect2) -> void:
	var hr := Rect2(r.position.x, r.position.y + HEAD_H - 1, r.size.x, PITCH_H)
	var hov: bool = ui.is_hover("expand", b)
	if hov:
		ui.draw_rect(hr, UiKit.HOVER_WASH)
	UiFont.draw_small(ui, b.left(4).to_upper() + " +", Vector2(r.position.x + 1, hr.position.y + 1), Gfx.FIRE[5] if hov else Gfx.UI_TEXT)
	UiKit.pips(ui, Vector2(r.position.x, hr.position.y + 8), Tech.branch_tier(v, b), Tech.MAX_TIER, Gfx.BRASS[3])
	ui.add_hit(hr, "expand", b)
	var y: float = r.position.y + HEAD_H + PITCH_H
	for tier in range(1, Tech.MAX_TIER + 1):
		var row: Array[String] = _row_ids(b, tier)
		var gap: float = 2.0
		var nw: float = floorf((r.size.x - gap * (row.size() - 1)) / float(row.size()))
		for k in row.size():
			var last: bool = k == row.size() - 1
			var x: float = r.position.x + k * (nw + gap)
			_chip(ui, v, row[k], Rect2(x, y + 3, (r.end.x - x) if last else nw, NODE_H - 6))
		y += ROW_H


## The nodes of `branch` at `tier` in table order: core / choices first, the prototype last.
static func _row_ids(branch: String, tier: int) -> Array[String]:
	var out: Array[String] = []
	for id in Tech.ids(branch):
		if int(Tech.def(id)["tier"]) == tier:
			out.append(id)
	return out


# ---------------------------------------------------------------- nodes

## Frames around a node: hover path / fusion parts (light), fusion partners (brass), next plan node
## (pulsing amber).
static func _halo(ui: WorkshopUi, id: String, nr: Rect2, hov: bool) -> void:
	if hov:
		return
	if _focus.has(id):
		UiKit.outline_rect(ui, nr.grow(1.0), Gfx.FIRE[5] if _dim else Gfx.UI_TEXT)
	elif _partner.has(id):
		UiKit.outline_rect(ui, nr.grow(1.0), Gfx.BRASS[2])
	elif id == _next:
		UiKit.outline_rect(ui, nr.grow(1.0), Gfx.FIRE[4] if fmod(ui.blink(), 1.0) < 0.6 else Gfx.FIRE[2])


static func _node(ui: WorkshopUi, v: SimVehicle, id: String, nr: Rect2) -> void:
	_rects[id] = nr
	var st: State = state(v, id)
	var d: Dictionary = Tech.def(id)
	var kind: String = str(d["kind"])
	var tier: int = int(d["tier"])
	var hov: bool = ui.is_hover("tech", id)
	_halo(ui, id, nr, hov)
	ui.add_hit(nr, "tech", id)
	var glyph: bool = kind == "choice" and (tier == 2 or tier == 4) and not Tech.fusion_partners(id).is_empty()
	var price: int = Tech.price(v, id)
	var name_col: Color
	var right: String = ""
	var right_col: Color = Gfx.UI_TEXT
	var pip: bool = false
	match st:
		State.OWNED:
			ui.draw_rect(nr, Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.BRASS[2])
			ui.draw_rect(Rect2(nr.position + Vector2.ONE, Vector2(nr.size.x - 2, 1)), Gfx.BRASS[3])
			name_col = Gfx.INK
			right = "BUILT"
			right_col = Gfx.BRASS[0]
		State.INACTIVE:
			ui.draw_rect(nr, Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Color(0.29, 0.22, 0.13))
			_dashed(ui, nr.grow(-1.0), Gfx.BRASS[2])
			name_col = Gfx.STEEL[4]
			right = "IDLE"
			right_col = Gfx.UI_BAD
		State.LOCKED, State.EXCLUDED:
			ui.draw_rect(nr, Gfx.UI_DIM if hov else Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.STEEL[1])
			name_col = Gfx.STEEL[3] if st == State.EXCLUDED else Gfx.STEEL[4]
			if st == State.EXCLUDED:
				right = "SWAP"
				right_col = Gfx.STEEL[4] if not hov else Gfx.HAZARD
			else:
				right = str(price)
				right_col = Gfx.STEEL[3]
				pip = true
		_:
			var afford: bool = st == State.BUYABLE
			UiKit.steel(ui, nr, Color.WHITE if afford else Color(0.75, 0.7, 0.7))
			if afford:
				UiKit.outline_rect(ui, nr, Gfx.HAZARD if (hov or fmod(ui.blink(), 1.2) < 0.9) else Gfx.OUTLINE)
			elif hov:
				UiKit.outline_rect(ui, nr, Gfx.UI_BAD)
			name_col = Gfx.UI_TEXT
			right = str(price)
			right_col = Gfx.UI_TEXT if afford else Gfx.UI_BAD
			pip = true
	if v.tech_dormant.has(id) and st != State.OWNED:
		_dashed(ui, nr, Gfx.BRASS[3])
	if tier == Tech.MAX_TIER:
		_keystone_corners(ui, nr)
	if kind == "proto":
		ui.draw_rect(Rect2(nr.position.x + 1, nr.end.y - 3, nr.size.x - 2, 2), Color(Gfx.INK_RED, 0.85))
	if hov and st != State.LOCKED and st != State.EXCLUDED:
		UiKit.outline_rect(ui, nr, Gfx.UI_TEXT)
	# name: full where it fits, else the short label, else the short label in fine print
	var avail: float = nr.size.x - 6.0
	var full: String = UiKit.tech_name(id)
	var short: String = str(d["short"])
	var label: String = full if UiFont.width(full) <= avail else short
	var lx: float = nr.position.x + 3.0
	var ly: float = nr.position.y + 3.0
	var shadow: Color = Gfx.OUTLINE if name_col == Gfx.UI_TEXT else Color(0, 0, 0, 0)
	if UiFont.width(label) <= avail:
		UiFont.draw(ui, label, Vector2(lx, ly), name_col, shadow)
	else:
		UiFont.draw_small(ui, _fit_small(label, avail), Vector2(lx, ly + 1), name_col, shadow)
	if st == State.EXCLUDED:
		var sw: float = minf(UiFont.width(label), avail)
		ui.draw_rect(Rect2(lx - 1, ly + 3, sw + 2, 1), Gfx.INK_RED)
	# lower line: tag (wide nodes) or the fusion glyph on the left, state / price on the right
	var by: float = nr.position.y + 10.0
	var rw: float = UiFont.width_small(right) + (9.0 if pip else 0.0)
	var rx: float = nr.end.x - 4.0 - rw
	if pip:
		ui.scrap_pip(Vector2(rx, by))
		UiFont.draw_small(ui, right, Vector2(rx + 9, by), right_col, Gfx.OUTLINE if st == State.BUYABLE or st == State.POOR else Color(0, 0, 0, 0))
	else:
		UiFont.draw_small(ui, right, Vector2(rx, by), right_col)
	var tag: String = _tag(v, id, st)
	var tx: float = lx
	if glyph:
		_link_glyph(ui, Vector2(tx, by), _glyph_col(v, id, st))
		tx += 9.0
	if tag != "" and tx + UiFont.width_small(tag) < rx - 3.0:
		var tcol: Color = Gfx.FIRE[4] if tag == "NEXT" else (Gfx.BRASS[0] if st == State.OWNED else Gfx.STEEL[4])
		if tag == "NEXT" and st == State.OWNED:
			tcol = Gfx.INK
		UiFont.draw_small(ui, tag, Vector2(tx, by), tcol)
	if _dim and not _focus.has(id):
		ui.draw_rect(nr, DIM_WASH)


## Left tag on the lower line: NEXT on the plan, KEYSTONE, PROTOTYPE, DORMANT (only where it fits).
static func _tag(v: SimVehicle, id: String, st: State) -> String:
	if id == _next and st != State.OWNED:
		return "NEXT"
	var d: Dictionary = Tech.def(id)
	if v.tech_dormant.has(id):
		return "DORMANT"
	if str(d["kind"]) == "proto":
		return "PROTOTYPE"
	if int(d["tier"]) == Tech.MAX_TIER:
		return "KEYSTONE"
	if int(d["tier"]) == 1:
		return "ENTRY"
	if str(d["kind"]) == "core":
		return "CORE"
	return ""


## Colour of the fusion glyph: lit when a fusion with this choice is built or one step away.
static func _glyph_col(v: SimVehicle, id: String, st: State) -> Color:
	for f in Tech.fusion_partners(id):
		if v.tech.has(f) and Tech.active(v, f):
			return Gfx.INK if st == State.OWNED else Gfx.BRASS[3]
	for f in Tech.fusion_partners(id):
		for rq in Tech.requirements(f):
			if str(rq) != id and Tech.active(v, str(rq)):
				return Gfx.FIRE[4] if st != State.OWNED else Gfx.INK_RED
	return Gfx.BRASS[0] if st == State.OWNED else Gfx.STEEL[3]


## Two linked rings (7x5): "this choice fuses with another branch".
static func _link_glyph(ui: WorkshopUi, p: Vector2, col: Color) -> void:
	var q: Vector2 = p.floor()
	for o: Vector2 in [Vector2(0, 0), Vector2(3, 0)]:
		ui.draw_rect(Rect2(q + o + Vector2(1, 0), Vector2(2, 1)), col)
		ui.draw_rect(Rect2(q + o + Vector2(1, 4), Vector2(2, 1)), col)
		ui.draw_rect(Rect2(q + o + Vector2(0, 1), Vector2(1, 3)), col)
		ui.draw_rect(Rect2(q + o + Vector2(3, 1), Vector2(1, 3)), col)


## Brass corner brackets: the stage 6 keystones.
static func _keystone_corners(ui: WorkshopUi, nr: Rect2) -> void:
	var c: Color = Gfx.BRASS[3]
	var p: Vector2 = nr.position
	var e: Vector2 = nr.end
	for pt: Vector2 in [p, Vector2(e.x - 4, p.y), Vector2(p.x, e.y - 1), Vector2(e.x - 4, e.y - 1)]:
		ui.draw_rect(Rect2(pt, Vector2(4, 1)), c)
	for pt2: Vector2 in [p, Vector2(e.x - 1, p.y), Vector2(p.x, e.y - 4), Vector2(e.x - 1, e.y - 4)]:
		ui.draw_rect(Rect2(pt2, Vector2(1, 4)), c)


## Dashed 1px outline (dormant fusions, idle nodes).
static func _dashed(ui: WorkshopUi, r: Rect2, col: Color) -> void:
	var x: float = r.position.x
	while x < r.end.x:
		var len: float = minf(3.0, r.end.x - x)
		ui.draw_rect(Rect2(x, r.position.y, len, 1), col)
		ui.draw_rect(Rect2(x, r.end.y - 1, len, 1), col)
		x += 5.0
	var y: float = r.position.y
	while y < r.end.y:
		var len2: float = minf(3.0, r.end.y - y)
		ui.draw_rect(Rect2(r.position.x, y, 1, len2), col)
		ui.draw_rect(Rect2(r.end.x - 1, y, 1, len2), col)
		y += 5.0


static func _fit_small(text: String, w: float) -> String:
	var t: String = text
	while UiFont.width_small(t) > w and t.length() > 1:
		t = t.left(t.length() - 1)
	return t


## A node of a folded branch: a state-coloured chip without text (hover for details, click to build).
static func _chip(ui: WorkshopUi, v: SimVehicle, id: String, nr: Rect2) -> void:
	_rects[id] = nr
	var st: State = state(v, id)
	var hov: bool = ui.is_hover("tech", id)
	_halo(ui, id, nr, hov)
	ui.add_hit(nr.grow_individual(0, 3, 0, 3), "tech", id)
	ui.draw_rect(nr, Gfx.OUTLINE)
	var fill: Color
	match st:
		State.OWNED: fill = Gfx.BRASS[2]
		State.INACTIVE: fill = Color(0.29, 0.22, 0.13)
		State.BUYABLE: fill = Gfx.STEEL[3]
		State.POOR: fill = Gfx.STEEL[2]
		_: fill = Gfx.STEEL[1]
	ui.draw_rect(nr.grow(-1.0), fill)
	if st == State.BUYABLE:
		UiKit.outline_rect(ui, nr, Gfx.HAZARD)
	elif st == State.EXCLUDED:
		ui.draw_rect(Rect2(nr.position.x + 2, nr.get_center().y, nr.size.x - 4, 1), Gfx.INK_RED)
	if int(Tech.def(id)["tier"]) == Tech.MAX_TIER:
		_keystone_corners(ui, nr)
	if hov:
		UiKit.outline_rect(ui, nr.grow(1.0), Gfx.UI_TEXT)
	if _dim and not _focus.has(id):
		ui.draw_rect(nr, DIM_WASH)


# ---------------------------------------------------------------- fusions

static func _fusion_rows(ui: WorkshopUi, v: SimVehicle, r: Rect2) -> void:
	UiKit.section(ui, "FUSIONS: A CHOICE FROM EACH OF TWO BRANCHES", Vector2(r.position.x, r.position.y + 1), r.size.x,
		"SMALL %d  -  LARGE %d  -  DORMANT AFTER A SWAP: RE-BUY AT 50%%" % [Tech.SMALL_FUSION_COST, Tech.LARGE_FUSION_COST])
	var y: float = r.position.y + FUS_LABEL_H
	for kind in ["fusion_s", "fusion_l"]:
		var fus: Array[String] = Tech.ids("", kind)
		var gap: float = 3.0
		var fw: float = floorf((r.size.x - gap * (fus.size() - 1)) / float(fus.size()))
		for k in fus.size():
			var x: float = r.position.x + k * (fw + gap)
			var last: bool = k == fus.size() - 1
			_fusion(ui, v, fus[k], Rect2(x, y, (r.end.x - x) if last else fw, FUS_H))
		y += FUS_H + 1.0


## A fusion: name and price (or BUILT / RE-BUY) on top, its two parts below in their state colours.
static func _fusion(ui: WorkshopUi, v: SimVehicle, id: String, nr: Rect2) -> void:
	_rects[id] = nr
	var st: State = state(v, id)
	var hov: bool = ui.is_hover("tech", id)
	var dormant: bool = v.tech_dormant.has(id)
	_halo(ui, id, nr, hov)
	ui.add_hit(nr, "tech", id)
	var name_col: Color = Gfx.UI_TEXT
	match st:
		State.OWNED:
			ui.draw_rect(nr, Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.BRASS[2])
			ui.draw_rect(Rect2(nr.position + Vector2.ONE, Vector2(nr.size.x - 2, 1)), Gfx.BRASS[3])
			name_col = Gfx.INK
		State.BUYABLE, State.POOR:
			UiKit.steel(ui, nr, Color.WHITE if st == State.BUYABLE else Color(0.75, 0.7, 0.7))
			if st == State.BUYABLE:
				UiKit.outline_rect(ui, nr, Gfx.HAZARD if (hov or fmod(ui.blink(), 1.2) < 0.9) else Gfx.OUTLINE)
		_:
			ui.draw_rect(nr, Gfx.UI_DIM if hov else Gfx.OUTLINE)
			ui.draw_rect(nr.grow(-1.0), Gfx.STEEL[1])
			name_col = Gfx.STEEL[4]
	if dormant and st != State.OWNED:
		_dashed(ui, nr, Gfx.BRASS[3])
	if str(Tech.def(id)["kind"]) == "fusion_l":
		ui.draw_rect(Rect2(nr.position.x + 1, nr.position.y + 1, 2, nr.size.y - 2), Gfx.BRASS[2] if st != State.OWNED else Gfx.BRASS[0])
	if hov:
		UiKit.outline_rect(ui, nr, Gfx.UI_TEXT)
	var lx: float = nr.position.x + 5.0
	# price / state at the top right
	var right: String
	var rcol: Color
	var pip: bool = false
	match st:
		State.OWNED:
			right = "BUILT"
			rcol = Gfx.BRASS[0]
		State.BUYABLE, State.POOR:
			right = str(Tech.price(v, id))
			rcol = Gfx.UI_TEXT if st == State.BUYABLE else Gfx.UI_BAD
			pip = true
		_:
			right = str(Tech.price(v, id))
			rcol = Gfx.STEEL[3]
			pip = true
	var rx: float = nr.end.x - 4.0 - UiFont.width_small(right)
	UiFont.draw_small(ui, right, Vector2(rx, nr.position.y + 3), rcol)
	if pip:
		ui.scrap_pip(Vector2(rx - 9, nr.position.y + 3))
	var name_end: float = rx - (10.0 if pip else 0.0) - 4.0
	if dormant and st != State.OWNED:
		var dl: String = "RE-BUY"
		name_end = rx - 12 - UiFont.width_small(dl) - 4.0
		UiFont.draw_small(ui, dl, Vector2(name_end + 4.0, nr.position.y + 3), Gfx.BRASS[3])
	var nm: String = UiKit.tech_name(id)
	if lx + UiFont.width(nm) > name_end:
		nm = str(Tech.def(id)["short"])
	UiFont.draw(ui, nm, Vector2(lx, nr.position.y + 3), name_col, Gfx.OUTLINE if name_col == Gfx.UI_TEXT else Color(0, 0, 0, 0))
	# the two parts
	var px: float = lx
	var req: Array = Tech.requirements(id)
	for i in req.size():
		var rq: String = str(req[i])
		var t: String = str(Tech.def(rq)["short"])
		var col: Color
		if Tech.active(v, rq):
			col = Gfx.BRASS[0] if st == State.OWNED else Gfx.BRASS[3]
		elif Tech.blocked_by(v, rq) != "":
			col = Gfx.UI_BAD
		else:
			col = Gfx.STEEL[3] if st != State.OWNED else Gfx.INK
		if i > 0:
			px = UiFont.draw_small(ui, " + ", Vector2(px, nr.position.y + 10), Gfx.STEEL[3] if st != State.OWNED else Gfx.BRASS[0])
		px = UiFont.draw_small(ui, t, Vector2(px, nr.position.y + 10), col)
	if _dim and not _focus.has(id):
		ui.draw_rect(nr, DIM_WASH)


# ---------------------------------------------------------------- detail panel

## Body or fine-print text with glossary words underlined (dotted) and hoverable ("gloss", index).
## Returns the x after the text.
static func _gloss_line(ui: WorkshopUi, text: String, pos: Vector2, col: Color, small: bool = false) -> float:
	var end: float = UiFont.draw_small(ui, text, pos, col) if small else UiFont.draw(ui, text, pos, col)
	var t: String = text.to_upper()
	for sp: Array in TechGuide.gloss_spans(t):
		var pre: String = t.substr(0, int(sp[0]))
		var word: String = t.substr(int(sp[0]), int(sp[1]))
		var wx: float = pos.x + float(UiFont.width_small(pre) if small else UiFont.width(pre))
		var ww: float = float(UiFont.width_small(word) if small else UiFont.width(word))
		var uy: float = pos.y + (6.0 if small else 7.0)
		var hov: bool = ui.is_hover("gloss", int(sp[2]))
		var x: float = floorf(wx)
		while x < wx + ww - 1.0:
			ui.draw_rect(Rect2(x, uy, 1, 1), Gfx.FIRE[5] if hov else Color(col, 0.75))
			x += 2.0
		ui.add_hit(Rect2(wx - 1, pos.y - 2, ww + 2, 10), "gloss", int(sp[2]))
	return end


## Wrapped glossary text; returns the y below it.
static func _gloss_par(ui: WorkshopUi, text: String, pos: Vector2, w: float, col: Color, small: bool, lh: float, max_y: float) -> float:
	var y: float = pos.y
	var lines: PackedStringArray = UiFont.wrap_small(text, int(w)) if small else UiFont.wrap(text, int(w))
	for ln in lines:
		if y > max_y:
			break
		_gloss_line(ui, ln, Vector2(pos.x, y), col, small)
		y += lh
	return y


static func _where(id: String) -> String:
	var d: Dictionary = Tech.def(id)
	var b: String = str(d["branch"]).to_upper()
	var tier: int = int(d["tier"])
	match str(d["kind"]):
		"fusion_s":
			return "SMALL FUSION"
		"fusion_l":
			return "LARGE FUSION"
		"proto":
			return "%s - STAGE 3 PROTOTYPE: AN EXTRA WITH A DRAWBACK" % b
		"choice":
			var n: int = Tech.choices(str(d["branch"]), tier).size()
			if tier == Tech.MAX_TIER:
				return "%s - KEYSTONE - PICK 1 OF %d" % [b, n]
			return "%s - STAGE %d - PICK 1 OF %d" % [b, tier, n]
	if tier == 1:
		return "%s - STAGE 1 ENTRY" % b
	return "%s - STAGE %d CORE" % [b, tier]


static func _detail(ui: WorkshopUi, v: SimVehicle, id: String, tpl_hover: String, r: Rect2) -> void:
	ui.draw_rect(r, Color(0.08, 0.05, 0.06, 0.6))
	UiKit.outline_rect(ui, r, Gfx.OUTLINE)
	ui.add_hit(r, "none", null)
	if id == "":
		_overview(ui, v, tpl_hover, r)
		return
	var st: State = state(v, id)
	var max_y: float = r.end.y - 8.0
	# A: what it is
	var ax: float = r.position.x + 6.0
	var aw: float = 206.0
	var y: float = r.position.y + 4.0
	UiFont.draw_small(ui, _where(id), Vector2(ax, y), Gfx.UI_DIM)
	y += 8.0
	UiFont.draw_big(ui, UiKit.tech_name(id), Vector2(ax, y), Gfx.UI_TEXT, Gfx.OUTLINE)
	y += 11.0
	for ln in UiKit.tech_lines(id):
		y = _gloss_par(ui, ln, Vector2(ax, y), aw, Gfx.FIRE[4], false, 8.0, max_y - 16.0)
	y += 2.0
	var seen: String = str(TechGuide.SEEN.get(id, ""))
	if seen != "" and y <= max_y:
		var sx: float = UiFont.draw_small(ui, "YOU SEE ", Vector2(ax, y), Gfx.UI_DIM)
		_gloss_line(ui, seen, Vector2(sx, y), Gfx.UI_TEXT, true)
		y += 8.0
	var good: String = str(TechGuide.GOOD_IF.get(id, ""))
	if good != "" and y <= max_y:
		_gloss_par(ui, "GOOD IF YOU " + good, Vector2(ax, y), aw, Gfx.BRASS[3], true, 7.0, max_y)
	ui.draw_rect(Rect2(r.position.x + 216, r.position.y + 4, 1, r.size.y - 8), Color(UiKit.PANEL_EDGE, 0.7))
	# B: net preview on your own rig
	var bx: float = r.position.x + 222.0
	var bw: float = 168.0
	var pv: Dictionary = TechGuide.preview(v, id)
	var by: float = r.position.y + 4.0
	UiKit.section(ui, str(pv["head"]), Vector2(bx, by), bw)
	by += 10.0
	var rows: Array = pv["rows"]
	var shown: int = 0
	for row: Array in rows:
		if by > max_y:
			UiFont.draw_small(ui, "+%d MORE" % (rows.size() - shown), Vector2(bx, by - 1), Gfx.UI_DIM)
			break
		UiFont.draw(ui, str(row[0]), Vector2(bx, by), Gfx.UI_DIM)
		var a1: String = str(row[2])
		var col: Color = Gfx.FIRE[4] if bool(row[3]) else Gfx.UI_BAD
		var rx: float = bx + bw - UiFont.width(a1)
		UiFont.draw(ui, a1, Vector2(rx, by), col, Gfx.UI_SHADOW)
		var ax2: float = UiKit.arrow_glyph(ui, Vector2(rx - 9, by + 1), Gfx.UI_DIM)
		UiFont.draw(ui, str(row[1]), Vector2(ax2 - 9 - UiFont.width(str(row[1])) - 1, by), Gfx.UI_TEXT)
		by += 8.0
		shown += 1
	if str(pv["note"]) != "":
		for ln in UiFont.wrap_small(str(pv["note"]), int(bw)):
			UiFont.draw_small(ui, ln, Vector2(bx, by), Gfx.UI_DIM)
			by += 7.0
	ui.draw_rect(Rect2(r.position.x + 396, r.position.y + 4, 1, r.size.y - 8), Color(UiKit.PANEL_EDGE, 0.7))
	# C: what it takes, what it joins, what a swap costs
	var cx: float = r.position.x + 402.0
	var cw: float = r.end.x - cx - 5.0
	var cy: float = r.position.y + 4.0
	for item: Array in _status_lines(ui, v, id, st):
		if cy > max_y + 1.0:
			break
		var small: bool = item.size() > 2 and bool(item[2])
		var lines: PackedStringArray = UiFont.wrap_small(str(item[0]), int(cw)) if small else UiFont.wrap(str(item[0]), int(cw))
		for ln in lines:
			if cy > max_y + 1.0:
				break
			if small:
				UiFont.draw_small(ui, ln, Vector2(cx, cy), item[1])
			else:
				UiFont.draw(ui, ln, Vector2(cx, cy), item[1])
			cy += 7.0 if small else 8.0
		cy += 1.0


## Right column of the detail panel: [text, colour, small] lines in priority order.
static func _status_lines(ui: WorkshopUi, v: SimVehicle, id: String, st: State) -> Array:
	var out: Array = []
	var d: Dictionary = Tech.def(id)
	var tier: int = int(d["tier"])
	var rnd: int = ui.world.round
	match st:
		State.OWNED:
			out.append(["BUILT IN ROUND %d - ACTIVE" % int(v.tech_round.get(id, 0)), Gfx.BRASS[3]])
		State.INACTIVE:
			out.append(["IDLE - NO EFFECT: NEEDS %s" % UiKit.tech_name(Tech.missing(v, id)), Gfx.UI_BAD])
			out.append(["WORKS AGAIN FOR FREE ONCE IT IS BACK", Gfx.UI_DIM, true])
		State.EXCLUDED:
			var from: String = Tech.blocked_by(v, id)
			if Tech.can_respec(v, from, id, rnd):
				var fee: int = Tech.respec_cost(v, id)
				out.append(["CLICK TO SWAP OUT %s" % UiKit.tech_name(from), Gfx.HAZARD])
				out.append(["FIRST SWAP FREE" if fee == 0 else "SWAP FOR %d SCRAP" % fee, Gfx.HAZARD])
				if tier == Tech.MAX_TIER:
					out.append(["KEYSTONE: SWAP OPEN UNTIL THE WORKSHOP AFTER ROUND %d" % (int(v.tech_round.get(from, 0)) + Tech.KEYSTONE_RESPEC_ROUNDS), Gfx.FIRE[4], true])
			elif tier == Tech.MAX_TIER and rnd > int(v.tech_round.get(from, 0)) + Tech.KEYSTONE_RESPEC_ROUNDS:
				out.append(["KEYSTONE %s IS LOCKED IN" % UiKit.tech_name(from), Gfx.UI_BAD])
			elif Tech.missing(v, id) != "":
				out.append(["SWAP NEEDS %s" % UiKit.tech_name(Tech.missing(v, id)), Gfx.UI_BAD])
			else:
				out.append(["SWAP COSTS %d - %d MORE SCRAP" % [Tech.respec_cost(v, id), Tech.respec_cost(v, id) - v.scrap], Gfx.UI_BAD])
			var gone: Array[String] = TechGuide.greys_out(v, from, id)
			if not gone.is_empty():
				out.append(["GREYS OUT: " + _names(gone), Gfx.UI_BAD])
			else:
				out.append(["NOTHING GREYS OUT, FOLLOW-UPS STAY BUILT", Gfx.UI_DIM, true])
		State.LOCKED:
			var path: Array[String] = TechGuide.build_path(v, id, _tpl.get("path", []))
			out.append(["BUILD %s FIRST" % UiKit.tech_name(path[0] if not path.is_empty() else Tech.next_step(v, id)), Gfx.UI_BAD])
			if path.size() > 1:
				out.append(["PATH: %d NODES, %d SCRAP IN ALL" % [path.size(), TechGuide.path_cost(v, path)], Gfx.UI_TEXT, true])
			for p in path:
				if Tech.blocked_by(v, p) != "":
					out.append(["NEEDS A SWAP: %s OUT, %s IN" % [UiKit.tech_name(Tech.blocked_by(v, p)), UiKit.tech_name(p)], Gfx.UI_BAD, true])
		State.POOR:
			out.append(["%d SCRAP - NEED %d MORE" % [Tech.price(v, id), Tech.price(v, id) - v.scrap], Gfx.UI_BAD])
		_:
			if v.tech_dormant.has(id):
				out.append(["CLICK: RE-BUY AT HALF PRICE - %d SCRAP" % Tech.price(v, id), Gfx.HAZARD])
			else:
				out.append(["CLICK TO BUILD - %d SCRAP" % Tech.price(v, id), Gfx.HAZARD])
	# what it needs (fusions always, nodes while not active)
	var req: Array = Tech.requirements(id)
	if Tech.is_fusion(id):
		out.append(["NEEDS: %s + %s" % [UiKit.tech_name(str(req[0])), UiKit.tech_name(str(req[1]))], Gfx.UI_TEXT if st == State.OWNED else Gfx.FIRE[5]])
	elif not req.is_empty() and st != State.OWNED:
		var names: PackedStringArray = []
		for rq in req:
			names.append(str(Tech.def(str(rq))["short"]))
		var one: bool = (d["requires"] as Array).is_empty() and req.size() > 1
		out.append([("NEEDS ONE OF: " if one else "NEEDS: ") + " / ".join(names), Gfx.UI_DIM, true])
	# fusion partners
	var fus: Array[String] = Tech.fusion_partners(id)
	if not fus.is_empty():
		var parts: PackedStringArray = []
		for f in fus:
			var other: String = ""
			for rq in Tech.requirements(f):
				if str(rq) != id:
					other = str(rq)
			var mark: String = ""
			if v.tech.has(f):
				mark = " (BUILT)" if Tech.active(v, f) else " (DORMANT)"
			elif Tech.active(v, other):
				mark = " (READY)"
			parts.append("%s = %s%s" % [str(Tech.def(other)["short"]), str(Tech.def(f)["short"]), mark])
		out.append(["FUSION WITH: " + ", ".join(parts), Gfx.BRASS[3], true])
	# swapping: price, keystone window, what an owned choice would grey out
	if str(d["kind"]) == "choice":
		if tier == Tech.MAX_TIER:
			if v.tech.has(id):
				var until: int = int(v.tech_round.get(id, 0)) + Tech.KEYSTONE_RESPEC_ROUNDS
				if rnd <= until:
					out.append(["KEYSTONE: SWAPPABLE UNTIL THE WORKSHOP AFTER ROUND %d" % until, Gfx.FIRE[4], true])
				else:
					out.append(["KEYSTONE: LOCKED IN SINCE ROUND %d" % until, Gfx.UI_DIM, true])
			elif st != State.EXCLUDED:
				out.append(["KEYSTONE: SWAPPABLE ONLY UNTIL THE NEXT WORKSHOP", Gfx.UI_DIM, true])
		if v.tech.has(id):
			var sib: String = ""
			for c in Tech.choices(str(d["branch"]), tier):
				if c != id:
					sib = c
					break
			var price_t: String = "FIRST SWAP FREE" if v.respecs == 0 else "SWAP FOR %d SCRAP" % Tech.respec_cost(v, id)
			out.append(["SWAP: CLICK A SIBLING - " + price_t, Gfx.UI_DIM, true])
			if sib != "":
				var gone2: Array[String] = TechGuide.greys_out(v, id, sib)
				if not gone2.is_empty():
					out.append(["SWAPPING IT OUT GREYS OUT: " + _names(gone2), Gfx.UI_BAD, true])
		elif st != State.EXCLUDED:
			out.append(["PICK ONE PER STAGE - " + ("FIRST SWAP FREE" if v.respecs == 0 else "SWAPS COST +50%"), Gfx.UI_DIM, true])
	return out


static func _names(ids: Array[String]) -> String:
	var n: PackedStringArray = []
	for t in ids:
		n.append(UiKit.tech_name(t))
	return ", ".join(n)


## Nothing hovered: the plan's cheat sheet, the legend and the house rules.
static func _overview(ui: WorkshopUi, v: SimVehicle, tpl_hover: String, r: Rect2) -> void:
	var t: Dictionary = TechGuide.template_by_id(tpl_hover) if tpl_hover != "" else _tpl
	var ax: float = r.position.x + 6.0
	var y: float = r.position.y + 4.0
	var picked: bool = TechGuide.is_picked(ui.world) and t["id"] == _tpl["id"]
	var head: String = "BUILD PLAN" if picked else ("CLICK TO FOLLOW THIS PLAN" if tpl_hover != "" else "SUGGESTED PLAN")
	UiFont.draw_small(ui, head, Vector2(ax, y), Gfx.FIRE[4] if tpl_hover != "" and not picked else Gfx.UI_DIM)
	y += 8.0
	var nx: float = UiFont.draw_big(ui, str(t["name"]), Vector2(ax, y), Gfx.UI_TEXT, Gfx.OUTLINE)
	UiFont.draw_small(ui, "%s + %s" % [str(t["branches"][0]).to_upper(), str(t["branches"][1]).to_upper()], Vector2(nx + 6, y + 2), Gfx.UI_DIM)
	y += 10.0
	UiFont.draw_small(ui, str(t["blurb"]), Vector2(ax, y), Gfx.BRASS[3])
	y += 9.0
	for ln: String in t["cheat"]:
		UiFont.draw(ui, ln, Vector2(ax, y), Gfx.UI_TEXT)
		y += 8.0
	var pp: Vector2i = TechGuide.path_progress(v, t)
	var nxt: String = TechGuide.next_on_path(v, t)
	var nt: String = "PATH %d/%d BUILT" % [pp.x, pp.y]
	if nxt != "":
		nt += " - NEXT: %s (%d)" % [UiKit.tech_name(nxt), Tech.price(v, nxt)]
	UiFont.draw_small(ui, nt, Vector2(ax, y + 1), Gfx.FIRE[4])
	ui.draw_rect(Rect2(r.position.x + 216, r.position.y + 4, 1, r.size.y - 8), Color(UiKit.PANEL_EDGE, 0.7))
	# legend: one swatch per state
	var bx: float = r.position.x + 222.0
	var by: float = r.position.y + 4.0
	UiKit.section(ui, "HOW TO READ IT", Vector2(bx, by), 168.0)
	by += 10.0
	var items: Array = [["BUILT", "brass"], ["BUILD NOW", "buy"], ["NEED SCRAP", "poor"], ["LOCKED", "lock"],
		["SWAP (SIBLING)", "swap"], ["IDLE / DORMANT", "idle"], ["NEXT ON YOUR PLAN", "next"], ["KEYSTONE", "key"]]
	for i in items.size():
		var lx: float = bx + (i % 2) * 86.0
		var ly: float = by + (i / 2) * 10.0
		_legend_chip(ui, Rect2(lx, ly - 1, 11, 7), str(items[i][1]))
		UiFont.draw_small(ui, str(items[i][0]), Vector2(lx + 15, ly), Gfx.UI_TEXT)
	by += 42.0
	_link_glyph(ui, Vector2(bx + 2, by), Gfx.BRASS[3])
	UiFont.draw_small(ui, "THIS CHOICE CAN FUSE WITH ANOTHER BRANCH", Vector2(bx + 15, by), Gfx.UI_TEXT)
	by += 9.0
	ui.draw_rect(Rect2(bx + 1, by + 2, 10, 2), Color(Gfx.INK_RED, 0.85))
	UiFont.draw_small(ui, "PROTOTYPE: AN EXTRA WITH A DRAWBACK", Vector2(bx + 15, by), Gfx.UI_TEXT)
	ui.draw_rect(Rect2(r.position.x + 396, r.position.y + 4, 1, r.size.y - 8), Color(UiKit.PANEL_EDGE, 0.7))
	# house rules
	var cx: float = r.position.x + 402.0
	var cw: float = r.end.x - cx - 5.0
	var cy: float = r.position.y + 4.0
	UiKit.section(ui, "RULES OF THE TREE", Vector2(cx, cy), cw)
	cy += 10.0
	for txt: String in ["A STAGE NEEDS A NODE OF THE ONE BEFORE. ONE CHOICE PER STAGE.",
			"CLICK A STRUCK-OUT CHOICE TO SWAP: FIRST SWAP FREE, THEN +50%.",
			"FUSIONS JOIN TWO BRANCHES. SWAP A PART AWAY AND THEY SLEEP.",
			"HELD SCRAP EARNS INTEREST UP TO YOUR INTEREST CAP."]:
		cy = _gloss_par(ui, txt, Vector2(cx, cy), cw, Gfx.UI_DIM, true, 7.0, r.end.y - 6.0) + 2.0


static func _legend_chip(ui: WorkshopUi, r: Rect2, kind: String) -> void:
	ui.draw_rect(r, Gfx.OUTLINE)
	var inner: Rect2 = r.grow(-1.0)
	match kind:
		"brass":
			ui.draw_rect(inner, Gfx.BRASS[2])
		"buy":
			ui.draw_rect(inner, Gfx.STEEL[3])
			UiKit.outline_rect(ui, r, Gfx.HAZARD)
		"poor":
			ui.draw_rect(inner, Gfx.STEEL[2])
			ui.draw_rect(Rect2(inner.end.x - 4, inner.position.y + 1, 3, 3), Gfx.UI_BAD)
		"lock":
			ui.draw_rect(inner, Gfx.STEEL[1])
		"swap":
			ui.draw_rect(inner, Gfx.STEEL[1])
			ui.draw_rect(Rect2(inner.position.x, inner.get_center().y, inner.size.x, 1), Gfx.INK_RED)
		"idle":
			ui.draw_rect(inner, Color(0.29, 0.22, 0.13))
			_dashed(ui, r, Gfx.BRASS[3])
		"next":
			ui.draw_rect(inner, Gfx.STEEL[2])
			UiKit.outline_rect(ui, r.grow(1.0), Gfx.FIRE[4])
		"key":
			ui.draw_rect(inner, Gfx.STEEL[1])
			_keystone_corners(ui, r)


# ---------------------------------------------------------------- overlays (drawn after everything)

## The glossary explanation of the hovered word, as a small dark box over the pointer.
static func draw_gloss(ui: WorkshopUi) -> void:
	var g: Variant = ui.hover_arg("gloss")
	if g == null:
		return
	var e: Array = TechGuide.GLOSSARY[int(g)]
	var head: String = str(e[0]) + ": "
	var text: String = str(e[1])
	var w: float = UiFont.width(head) + UiFont.width(text) + 10.0
	var p: Vector2 = ui.pointer()
	var r := Rect2(clampf(p.x - w / 2.0, 4.0, 636.0 - w), p.y - 18.0, w, 12)
	ui.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(0.05, 0.03, 0.03, 0.5))
	ui.draw_rect(r, Gfx.OUTLINE)
	ui.draw_rect(r.grow(-1.0), Color(0.16, 0.11, 0.08))
	UiKit.outline_rect(ui, r.grow(-1.0), Gfx.FIRE[3])
	var x: float = UiFont.draw(ui, head, r.position + Vector2(5, 3), Gfx.FIRE[4])
	UiFont.draw(ui, text, Vector2(x, r.position.y + 3), Gfx.UI_TEXT)


## The swap confirmation (WorkshopUi.confirm = {"from", "to"}): price, what greys out, SWAP / CANCEL.
static func draw_confirm(ui: WorkshopUi, v: SimVehicle, body: Rect2) -> void:
	var from: String = str(ui.confirm.get("from", ""))
	var to: String = str(ui.confirm.get("to", ""))
	ui.draw_rect(body, Color(0.03, 0.02, 0.02, 0.55))
	ui.add_hit(body, "swap_cancel", null)
	var gone: Array[String] = TechGuide.greys_out(v, from, to)
	var fee: int = Tech.respec_cost(v, to)
	var can: bool = Tech.can_respec(v, from, to, ui.world.round)
	var w: float = 300.0
	var lines: Array = []  # [text, colour]
	lines.append(["REFUND %d FOR %s, PAY %d FOR %s" % [Tech.cost(from), UiKit.tech_name(from), Tech.cost(to), UiKit.tech_name(to)], Gfx.UI_DIM])
	lines.append(["FIRST SWAP OF THE MATCH: FREE" if fee == 0 else "SWAP FEE: %d SCRAP (+50%% OF THE NEW NODE)" % fee, Gfx.FIRE[4]])
	if gone.is_empty():
		lines.append(["NOTHING GREYS OUT. NODES AFTER IT STAY BUILT.", Gfx.UI_DIM])
	else:
		lines.append(["GREYS OUT: " + _names(gone), Gfx.UI_BAD])
		var has_fusion: bool = false
		for gid in gone:
			has_fusion = has_fusion or Tech.is_fusion(gid)
		lines.append(["FUSIONS GO DORMANT: RE-BUY AT 50%. OTHERS WAKE UP AGAIN FOR FREE." if has_fusion else "THEY WAKE UP AGAIN FOR FREE WHEN IT IS BACK.", Gfx.UI_DIM])
	if int(Tech.def(to)["tier"]) == Tech.MAX_TIER:
		lines.append(["KEYSTONE: THIS SWAP IS ONLY OPEN UNTIL THE NEXT WORKSHOP", Gfx.UI_DIM])
	var wrapped: Array = []
	for item: Array in lines:
		for ln in UiFont.wrap(str(item[0]), int(w) - 16):
			wrapped.append([ln, item[1]])
	var h: float = 22.0 + wrapped.size() * 9.0 + 22.0
	var r := Rect2(floorf(body.get_center().x - w / 2.0), floorf(body.position.y + 70.0), w, h)
	UiKit.panel(ui, r)
	ui.add_hit(r, "none", null)
	UiKit.hazard_band(ui, Rect2(r.position.x + 1, r.position.y + 1, r.size.x - 2, 3))
	var y: float = r.position.y + 8.0
	var title: String = "%s INSTEAD OF %s?" % [UiKit.tech_name(to), UiKit.tech_name(from)]
	if UiFont.width_big(title) > w - 16.0:
		title = "%s INSTEAD OF %s?" % [str(Tech.def(to)["short"]), str(Tech.def(from)["short"])]
	UiFont.draw_big(ui, title, Vector2(r.position.x + 8, y), Gfx.UI_TEXT, Gfx.OUTLINE)
	y += 14.0
	for item: Array in wrapped:
		UiFont.draw(ui, str(item[0]), Vector2(r.position.x + 8, y), item[1])
		y += 9.0
	y += 3.0
	var sr := Rect2(r.position.x + 8, y, 130, 14)
	var label: String = ("SWAP - FREE" if fee == 0 else "SWAP - %d SCRAP" % fee) if can else "CANNOT SWAP NOW"
	UiKit.button(ui, sr, label + ("   ENTER" if can else ""), ui.is_hover("swap_ok"), can)
	if can:
		UiKit.outline_rect(ui, sr.grow(1.0), Gfx.HAZARD)
		ui.add_hit(sr, "swap_ok", null)
	var cr := Rect2(r.end.x - 8 - 90, y, 90, 14)
	UiKit.button(ui, cr, "CANCEL   ESC", ui.is_hover("swap_cancel"))
	ui.add_hit(cr, "swap_cancel", null)
