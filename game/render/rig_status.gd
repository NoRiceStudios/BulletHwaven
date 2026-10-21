class_name RigStatus
extends Control
## Combat "RIG" panel on the left edge under the standings (playtest: "I want to see which effects are
## active, how much I heal per second"): the watched rig's guns (icon, name, level, damage per second, a
## lamp while it fires, heat and jams) and every effect that is on right now with its number: running
## ability timers (nitro, salvo, smoke, shields, EMP'd) with a draining bar, then the standing effects of
## cards and tech (repair hp/s, armour, contact resist, thorns, spikes, dodge, ram, execute, speed, scrap).
## I toggles it (kept in user://profile.cfg [ui] rig_status). Reads sim state and the WorldView only, and
## every number comes from synced fields, so host, clients and screenshots agree.

const W := 140.0
const MARGIN := 6.0
const GAP := 4.0  ## under the standings plate
const GUN_H := 18.0
const ROW_H := 9.0
const MAX_ROWS := 9  ## effect rows; the rest collapse into "+N MORE"
const FIRE_LAMP_TICKS := 4
const PROFILE_PATH := "user://profile.cfg"

const GOOD := Color("#9fcb2c")  ## repair (LIME paint step: warm-leaning green, never cyan)

var view: WorldView = null
var shown: bool = true


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) == OK:
		shown = bool(cfg.get_value("ui", "rig_status", true))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active() or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).keycode == KEY_I:
		shown = not shown
		var cfg := ConfigFile.new()
		cfg.load(PROFILE_PATH)  # keep the other sections
		cfg.set_value("ui", "rig_status", shown)
		if cfg.save(PROFILE_PATH) != OK:
			push_warning("rig_status: cannot save %s" % PROFILE_PATH)
		get_viewport().set_input_as_handled()


func active() -> bool:
	return view != null and view.world != null and not view.attract and view.world.phase == SimWorld.PHASE_COMBAT


## Screenshot mode always shows it, whatever the player's preference.
func visible_now() -> bool:
	return (shown or view.frozen) and active() and _rig() != null


func _rig() -> SimVehicle:
	var v: SimVehicle = view.focus_vehicle()
	return v if v != null and v.alive else null


# ---------------------------------------------------------------- numbers (pure, tested)

## Damage per second of weapon dict `w` on `v` right now (pellets, fire rate, a running salvo).
static func weapon_dps(v: SimVehicle, w: Dictionary) -> float:
	var cd: float = maxf(float(w.get("cooldown_ticks", 1.0)), 1.0)
	var rate: float = 1.0 + Abilities.SALVO_RATE if v.salvo_ticks > 0 else 1.0
	return float(w.get("damage", 0.0)) * float(maxi(int(w.get("pellets", 1)), 1)) * float(SimWorld.TICK_RATE) * rate / cd


## Display name of weapon kind `kind` on `v` (the evolution's name once evolved).
static func weapon_name(v: SimVehicle, kind: String) -> String:
	if Cards.is_evolved(v, kind):
		var evo: String = RigArt.evolution_card(kind)
		if evo != "":
			return UiKit.card_name(evo)
	return UiKit.card_name(kind)


## Effects running out: [{label, value, left (ticks), total (ticks), bad}], most urgent first.
static func timers(v: SimVehicle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v.rules_off_ticks > 0:
		out.append({"label": "EMP'D", "value": "RULES OFF", "left": v.rules_off_ticks, "total": Abilities.EMP_RULES_OFF_TICKS, "bad": true})
	if v.jammed_by >= 0:
		out.append({"label": "JAMMED", "value": "LAST RULE OFF", "left": 0, "total": 0, "bad": true})
	if v.sputter_ticks > 0:
		out.append({"label": "NITRO", "value": "SPUTTERS", "left": v.sputter_ticks, "total": Abilities.SPUTTER_TICKS, "bad": true})
	elif v.nitro_ticks > 0:
		out.append({"label": "NITRO", "value": "+%s SPEED" % UiKit.pct(Abilities.NITRO_SPEED), "left": v.nitro_ticks, "total": Abilities.NITRO_TICKS, "bad": false})
	if v.salvo_ticks > 0:
		out.append({"label": "SALVO", "value": "+%s FIRE RATE" % UiKit.pct(Abilities.SALVO_RATE), "left": v.salvo_ticks, "total": Abilities.SALVO_TICKS, "bad": false})
	if v.smoke_ticks > 0:
		out.append({"label": "SMOKE", "value": "UNTARGETABLE", "left": v.smoke_ticks, "total": Abilities.SMOKE_TICKS, "bad": false})
	if v.decoy_ticks > 0:
		out.append({"label": "DECOY", "value": "PHANTOM OUT", "left": v.decoy_ticks, "total": Abilities.DECOY_TICKS, "bad": false})
	if v.invuln_ticks > 0:
		out.append({"label": "SHIELD", "value": "INVULNERABLE", "left": v.invuln_ticks, "total": SimWorld.INVULN_TICKS, "bad": false})
	if v.protect_ticks > 0:
		out.append({"label": "COVER", "value": "-%s DAMAGE" % UiKit.pct(1.0 - SimWorld.PVP_PROTECT_FACTOR), "left": v.protect_ticks, "total": SimWorld.PVP_PROTECT_TICKS, "bad": false})
	return out


## Standing effects of cards and tech: [{label, value, good}] (only the ones that are on).
static func effects(v: SimVehicle) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v.regen > 0.0:
		out.append({"label": "REPAIR", "value": "+%s HP/S" % _n(v.regen), "heal": true})
	var drift: float = float(v.tech_fx.get("drift_regen", 0.0))
	if drift > 0.0:
		out.append({"label": "DRIFT REPAIR", "value": "+%s HP/S" % _n(drift), "heal": true})
	if v.eff_armor > 0.0:
		out.append({"label": "ARMOUR", "value": "-%s / HIT" % _n(v.eff_armor)})
	if v.contact_reduction > 0.0:
		out.append({"label": "BITE RESIST", "value": "-%s" % UiKit.pct(v.contact_reduction)})
	if v.thorns > 0.0:
		out.append({"label": "THORNS", "value": "%s BACK" % UiKit.pct(v.thorns)})
	if v.contact_damage > 0.0:
		out.append({"label": "SPIKES", "value": "%s DPS" % _n(v.contact_damage * float(SimWorld.TICK_RATE))})
	var dodge: float = Mobility.dodge_chance(v)
	if dodge > 0.0:
		out.append({"label": "DODGE", "value": UiKit.pct(dodge)})
	if v.ram_mult > 1.0:
		out.append({"label": "RAM", "value": "x%s" % _n(v.ram_mult)})
	if v.vulture > 0.0:
		out.append({"label": "EXECUTE", "value": "+%s <%s HP" % [UiKit.pct(v.vulture), UiKit.pct(Cards.VULTURE_HP_FRACTION)]})
	if absf(v.speed - 1.0) > 0.005:
		out.append({"label": "SPEED", "value": "%s%s" % ["+" if v.speed > 1.0 else "-", UiKit.pct(absf(v.speed - 1.0))], "bad": v.speed < 1.0})
	if v.scrap_mult > 1.0:
		out.append({"label": "SCRAP", "value": "+%s" % UiKit.pct(v.scrap_mult - 1.0)})
	return out


## "2.5", "3", "12".
static func _n(x: float) -> String:
	var r: float = roundf(x * 10.0) / 10.0
	return str(int(r)) if is_equal_approx(r, roundf(r)) else "%.1f" % r


# ---------------------------------------------------------------- layout

## Top of the panel: under the standings plate (Hud._draw_standings), or the corner when solo.
static func top_y(w: SimWorld) -> float:
	if w.vehicles.size() > 1:
		return MARGIN + 18.0 + float(UiKit.standings(w).size()) * 10.0 + GAP
	return MARGIN


## The panel's rect for rig `v` (the HUD keeps rival arrows clear of it).
static func panel_rect(w: SimWorld, v: SimVehicle) -> Rect2:
	var n_fx: int = mini(timers(v).size() + effects(v).size(), MAX_ROWS + 1)
	var h: float = 16.0 + float(v.weapons.size()) * GUN_H
	if n_fx > 0:
		h += 12.0 + float(n_fx) * ROW_H
	return Rect2(MARGIN, top_y(w), W, h + 2.0)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not visible_now():
		return
	var w: SimWorld = view.world
	var v: SimVehicle = _rig()
	var r: Rect2 = panel_rect(w, v)
	UiKit.panel(self, r)
	UiKit.section(self, "GUNS", r.position + Vector2(6, 5), r.size.x - 12, "I HIDE")
	var y: float = r.position.y + 15.0
	var rv: RigView = view.rig_view(v.id)
	for w_i in v.weapons.size():
		_gun_row(v, v.weapons[w_i], rv, Vector2(r.position.x + 5, y), r.size.x - 10)
		y += GUN_H
	var tm: Array[Dictionary] = timers(v)
	var fx: Array[Dictionary] = effects(v)
	if tm.is_empty() and fx.is_empty():
		return
	y += 2.0
	UiKit.section(self, "EFFECTS", Vector2(r.position.x + 6, y), r.size.x - 12)
	y += 11.0
	var x0: float = r.position.x + 7.0
	var xr: float = r.end.x - 7.0
	var shown_rows: int = 0
	var total: int = tm.size() + fx.size()
	for t in tm:
		if shown_rows >= MAX_ROWS and total > MAX_ROWS + 1:
			break
		_timer_row(t, x0, xr, y)
		y += ROW_H
		shown_rows += 1
	for e in fx:
		if shown_rows >= MAX_ROWS and total > MAX_ROWS + 1:
			break
		var col: Color = Gfx.UI_BAD if bool(e.get("bad", false)) else Gfx.UI_TEXT
		if bool(e.get("heal", false)):
			col = GOOD if v.hp < v.max_hp and (view.frozen or (w.tick / 8) % 4 != 0) else Color(GOOD, 0.75)
		UiFont.draw_small(self, str(e["label"]), Vector2(x0, y + 1), Gfx.UI_DIM, Gfx.UI_SHADOW)
		var val: String = str(e["value"])
		UiFont.draw(self, val, Vector2(xr - UiFont.width(val), y), col, Gfx.UI_SHADOW)
		y += ROW_H
		shown_rows += 1
	if shown_rows < total:
		UiFont.draw_small(self, "+%d MORE" % (total - shown_rows), Vector2(x0, y + 1), Gfx.UI_DIM, Gfx.UI_SHADOW)


## One gun: kind icon, name (brass once evolved) and level pips; under it dps, range and the lamp / heat / jam.
func _gun_row(v: SimVehicle, w: Dictionary, rv: RigView, p: Vector2, width: float) -> void:
	var kind: String = str(w.get("kind", ""))
	var ki: int = Cards.weapon_kind_index(kind)
	var evo: bool = bool(w.get("evo", Cards.is_evolved(v, kind)))
	var since: int = view.world.tick - rv.last_fire(ki) if rv != null else 9999
	var firing: bool = since >= 0 and since < FIRE_LAMP_TICKS
	var jammed: bool = int(w.get("jam", 0)) > 0
	# icon on a dark well; it lights warm while the gun fires
	var well := Rect2(p, Vector2(16, 16))
	draw_rect(well, Gfx.OUTLINE)
	draw_rect(well.grow(-1.0), Color(Gfx.FIRE[3], 0.35) if firing else Gfx.UI_PLATE_DARK)
	UiKit.icon(self, kind, p)
	var tx: float = p.x + 20.0
	UiFont.draw(self, weapon_name(v, kind).to_upper(), Vector2(tx, p.y + 1), Gfx.BRASS[3] if evo else Gfx.UI_TEXT, Gfx.UI_SHADOW)
	if evo:
		UiFont.draw_small(self, "EVO", Vector2(p.x + width - UiFont.width_small("EVO"), p.y + 2), Gfx.BRASS[3], Gfx.UI_SHADOW)
	else:
		UiKit.pips(self, Vector2(p.x + width - 16.0, p.y + 2), int(v.cards.get(kind, 1)), Cards.MAX_LEVEL, Gfx.FIRE[4])
	var y2: float = p.y + 10.0
	var x: float = UiFont.draw_small(self, "DPS", Vector2(tx, y2), Gfx.UI_DIM, Gfx.UI_SHADOW) + 3.0
	x = UiFont.draw_small(self, str(roundi(weapon_dps(v, w))), Vector2(x, y2), Gfx.FIRE[5] if v.salvo_ticks > 0 else Gfx.FIRE[4], Gfx.UI_SHADOW) + 6.0
	x = UiFont.draw_small(self, "RANGE", Vector2(x, y2), Gfx.UI_DIM, Gfx.UI_SHADOW) + 3.0
	x = UiFont.draw_small(self, str(roundi(float(w.get("range", 0.0)))), Vector2(x, y2), Gfx.UI_TEXT, Gfx.UI_SHADOW) + 6.0
	if jammed:
		var jt: String = "OVERHEAT" if float(v.tech_fx.get("overheat", 0.0)) > 0.0 else "JAMMED"
		UiFont.draw_small(self, jt, Vector2(p.x + width - UiFont.width_small(jt), y2), Gfx.UI_BAD if (view.world.tick / 4) % 2 == 0 or view.frozen else Gfx.FIRE[5], Gfx.UI_SHADOW)
	elif int(w.get("heat", 0)) > 0 and (float(v.tech_fx.get("jam", 0.0)) > 0.0 or float(v.tech_fx.get("overheat", 0.0)) > 0.0):
		var limit: float = float(SimWorld.OVERHEAT_FIRE_TICKS if float(v.tech_fx.get("overheat", 0.0)) > 0.0 else SimWorld.JAM_FIRE_TICKS)
		var hf: float = clampf(float(w.get("heat", 0)) / limit, 0.0, 1.0)
		UiKit.bar(self, Rect2(p.x + width - 24.0, y2, 24, 5), hf, Gfx.UI_BAD if hf > 0.75 else Gfx.FIRE[3])


func _timer_row(t: Dictionary, x0: float, xr: float, y: float) -> void:
	var bad: bool = bool(t["bad"])
	var col: Color = Gfx.UI_BAD if bad else Gfx.FIRE[5]
	UiFont.draw_small(self, str(t["label"]), Vector2(x0, y + 1), col, Gfx.UI_SHADOW)
	var val: String = str(t["value"])
	var left: int = int(t["left"])
	if left > 0:
		val += " %ss" % _n(float(left) / float(SimWorld.TICK_RATE))
	UiFont.draw(self, val, Vector2(xr - UiFont.width(val), y), col, Gfx.UI_SHADOW)
	if int(t["total"]) > 0:
		var f: float = clampf(float(left) / float(t["total"]), 0.0, 1.0)
		draw_rect(Rect2(x0, y + 7, floorf((xr - x0) * f), 1), Color(col, 0.6))
