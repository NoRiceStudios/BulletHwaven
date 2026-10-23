class_name RulesLive
extends Control
## Live rule monitor (combat, playtest feedback "show me which rule is active and which of my conditions hold"):
## a CRT panel on the right edge listing the watched rig's rules and every gun's rules. Each rule shows its
## conditions lit while they hold (from the synced `rule_conds` / weapon `clive` masks), its action, and whether
## it WINS (the first match of its kind, so it is what the rig does now), merely MATCHES (a higher rule of the
## same kind wins), or is LOCKED (beyond the rig's slots) / OFFLINE (EMP, jammer). Radio calls and the target mark sit on top as banners,
## because they beat every rule. L toggles it (kept in user://profile.cfg [ui] rules_live). Reads sim state only.

const PROFILE_PATH := "user://profile.cfg"
const W := 168.0
const TOP := 64.0
const ROW_H := 20.0

var view: WorldView = null
var shown: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		shown = bool(cfg.get_value("ui", "rules_live", true))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active() or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_L:
		shown = not shown
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_PATH)  # keep the other sections
		cfg.set_value("ui", "rules_live", shown)
		cfg.save(PROFILE_PATH)
		get_viewport().set_input_as_handled()


func active() -> bool:
	return view != null and view.world != null and not view.attract and view.world.phase == SimWorld.PHASE_COMBAT \
		and not (view.rules != null and view.rules.is_open)


func _draw() -> void:
	if not active():
		return
	var w: SimWorld = view.world
	var v: SimVehicle = view.focus_vehicle()
	if v == null or v.eliminated:
		return
	var vs: Vector2 = get_viewport_rect().size
	var x0: float = vs.x - 4.0 - W
	if not shown:
		var tag := "L  LIVE RULES"
		var tr := Rect2(vs.x - 4.0 - UiFont.width_small(tag) - 10.0, TOP, UiFont.width_small(tag) + 10.0, 11)
		_plate(tr)
		UiFont.draw_small(self, tag, tr.position + Vector2(5, 2), Gfx.CRT_DIM)
		return
	var bottom: float = (Minimap.frame_rect(vs).position.y - 6.0) if view.minimap != null and view.minimap.visible_now() else vs.y - 40.0
	var blocks: Array = _blocks(w, v)
	var h: float = 16.0
	for b: Dictionary in blocks:
		h += 11.0 + maxf(1.0, (b["rules"] as Array).size()) * ROW_H
	var banners: PackedStringArray = _banners(w, v)
	h += banners.size() * 11.0
	h = minf(h, bottom - TOP)
	var r := Rect2(x0, TOP, W, h)
	_plate(r)
	var y: float = r.position.y + 4.0
	UiFont.draw(self, "LIVE RULES", Vector2(x0 + 5, y), Gfx.CRT_HI)
	var hint := "L HIDE"
	UiFont.draw_small(self, hint, Vector2(r.end.x - 5.0 - UiFont.width_small(hint), y + 1), Gfx.CRT_DIM)
	y += 12.0
	for t in banners:
		draw_rect(Rect2(x0 + 3, y - 1, W - 6, 10), Gfx.CRT_TEXT)
		UiFont.draw_small(self, t, Vector2(x0 + 6, y + 1), Gfx.CRT_BG)
		y += 11.0
	for b: Dictionary in blocks:
		if y + 11.0 > r.end.y:
			break
		draw_rect(Rect2(x0 + 4, y + 4, W - 8, 1), Gfx.CRT_DIM)
		var title: String = b["title"]
		draw_rect(Rect2(x0 + 6, y, UiFont.width_small(title) + 6, 9), Gfx.CRT_BG)
		UiFont.draw_small(self, title, Vector2(x0 + 8, y + 1), Gfx.CRT_TEXT)
		y += 11.0
		var rules: Array = b["rules"]
		if rules.is_empty():
			UiFont.draw_small(self, "NO RULES: BASE %s" % b["base"], Vector2(x0 + 8, y + 1), Gfx.CRT_DIM)
			y += ROW_H
			continue
		for i in rules.size():
			if y + ROW_H > r.end.y + 2.0:
				break
			_row(rules[i], i, b, Vector2(x0 + 5, y))
			y += ROW_H


func _plate(r: Rect2) -> void:
	draw_rect(r.grow(1), Gfx.OUTLINE)
	draw_rect(r, Color(Gfx.CRT_BG, 0.9))
	UiKit.outline_rect(self, r.grow(-1), Gfx.CRT_DIM)


## Radio call and target mark: they beat every rule, so they head the list while they run.
func _banners(w: SimWorld, v: SimVehicle) -> PackedStringArray:
	var out := PackedStringArray()
	var rid: String = Orders.radio_id(v)
	if rid != "":
		out.append("RADIO %s OVERRIDES ALL  %ds" % [str(Hud.RADIO_LABELS.get(rid, rid.to_upper())), ceili(float(v.radio_ticks) / float(SimWorld.TICK_RATE))])
	if Orders.active(w, v):
		out.append("MARK: ALL GUNS ON IT  %ds" % ceili(float(v.mark_order_ticks) / float(SimWorld.TICK_RATE)))
	return out


## One block per rule list: the rig, then every mounted gun that has rules or a base target of its own.
func _blocks(_w: SimWorld, v: SimVehicle) -> Array:
	var out: Array = []
	var active_n: int = Doctrine.active_slots(v)
	var slots: int = Doctrine.slots(v)
	out.append({"title": "RIG", "rules": v.rules, "live": v.rule_live, "conds": v.rule_conds,
		"slots": slots, "active": active_n, "base": "%s / %s" % [str(v.doctrine["drive"]).to_upper(), str(v.doctrine["target"]).to_upper()]})
	for wp: Dictionary in v.weapons:
		var kind: String = str(wp["kind"])
		var doc: Dictionary = Doctrine.weapon_doc(v, kind)
		if (doc["rules"] as Array).is_empty():
			continue
		out.append({"title": UiKit.card_name(kind), "rules": doc["rules"], "live": int(wp.get("live", 0)), "conds": int(wp.get("clive", 0)),
			"slots": slots, "active": active_n, "base": str(doc["target"]).to_upper()})
	return out


func _row(rule: Dictionary, i: int, b: Dictionary, p: Vector2) -> void:
	var off: bool = i >= int(b["active"])
	var lit: bool = not off and (int(b["live"]) >> i) & 1 == 1
	var act: String = str(rule["do"])
	var state: String = ("LOCKED" if i >= int(b["slots"]) else "OFFLINE") if off else ""
	if lit:
		state = "WINS" if _wins(b, i) else "MATCH"
	var x: float = p.x
	draw_rect(Rect2(x, p.y + 1, 5, 5), Gfx.OUTLINE)
	draw_rect(Rect2(x + 1, p.y + 2, 3, 3), Gfx.CRT_HI if lit else (Gfx.CRT_DIM if not off else Gfx.CRT_BG))
	x += 8.0
	x = UiFont.draw_small(self, "%d" % (i + 1), Vector2(x, p.y), Gfx.CRT_DIM) + 4.0
	UiFont.draw_small(self, str(DoctrineEditor.ACTION_LABELS.get(act, act.to_upper())), Vector2(x, p.y), Gfx.CRT_HI if state == "WINS" else (Gfx.CRT_TEXT if not off else Gfx.CRT_DIM))
	if state != "":
		var sw: float = UiFont.width_small(state) + 4.0
		var sr := Rect2(p.x + W - 10.0 - sw, p.y - 1, sw, 8)
		if state == "WINS":
			draw_rect(sr, Gfx.CRT_HI)
		else:
			UiKit.outline_rect(self, sr, Gfx.CRT_DIM)
		UiFont.draw_small(self, state, sr.position + Vector2(2, 1), Gfx.CRT_BG if state == "WINS" else Gfx.CRT_DIM)
	# the conditions, lit while they hold
	var conds: Array = rule["if"]
	var cx: float = p.x + 8.0
	var cy: float = p.y + 9.0
	if conds.is_empty():
		UiFont.draw_small(self, "ALWAYS", Vector2(cx, cy), Gfx.CRT_TEXT if not off else Gfx.CRT_DIM)
		return
	for j in conds.size():
		var t: String = cond_text(conds[j])
		var holds: bool = not off and (int(b["conds"]) >> (i * Doctrine.MAX_CONDS + j)) & 1 == 1
		var tw: float = UiFont.width_small(t) + 4.0
		if cx + tw > p.x + W - 8.0:
			UiFont.draw_small(self, "+", Vector2(cx, cy), Gfx.CRT_DIM)
			break
		var cr := Rect2(cx, cy - 1, tw, 9)
		if holds:
			draw_rect(cr, Color(Gfx.CRT_TEXT, 0.85))
		else:
			UiKit.outline_rect(self, cr, Color(Gfx.CRT_DIM, 0.7))
		UiFont.draw_small(self, t, Vector2(cx + 2, cy), Gfx.CRT_BG if holds else Gfx.CRT_DIM)
		cx += tw + 3.0


## True if rule i is the first lit rule of its action group (what the rig / gun does now).
static func _wins(b: Dictionary, i: int) -> bool:
	var rules: Array = b["rules"]
	var grp: String = Doctrine.action_group(str(rules[i]["do"]))
	for k in i:
		if (int(b["live"]) >> k) & 1 == 1 and Doctrine.action_group(str(rules[k]["do"])) == grp:
			return false
	return true


## "HP<30%", "ALIENS NEAR>15", "BOSS ACTIVE", "NOT PVP ON".
static func cond_text(c: Array) -> String:
	var id: String = str(c[0])
	var label: String = str(DoctrineEditor.COND_LABELS.get(id, id.to_upper()))
	var meta: Dictionary = Doctrine.CONDS.get(id, {})
	if bool(meta.get("flag", false)):
		return label if int(c[2]) == 1 else "NOT " + label
	return "%s%s%d%s" % [label.trim_prefix("OWN "), str(c[1]), int(c[2]), str(meta.get("unit", ""))]
