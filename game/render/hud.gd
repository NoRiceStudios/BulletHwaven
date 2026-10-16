class_name Hud
extends Control
## Combat HUD (layout from the UI revamp, see the constants below): round, clock and hive top centre;
## doctrine, hp, fuel, scrap and kills in one dock at the bottom centre; round-start / workshop-start banners; the
## respawn countdown (with what wrecked you) and the ELIMINATED state. Information UI from playtest
## round 1 (#2, #5): a kill feed of player kills under the hive plate, off-screen rival arrows at the
## screen edge, the PvP grace countdown, a fuel-drain warning before camp, and spectator mode once
## the local rig is eliminated (Tab / Left / Right cycle the watched rig, live standings). Reads sim
## state and the WorldView logs only, so it works the same for host, client and solo. Workshop and
## game over have their own overlays. Combat juice (WorldView.juice): the watched rig's kill combo next
## to it with milestone words, the scrap counter ticking up with a pulse, and the SWARM INCOMING banner
## with a cyan edge pulse while a hive surge is announced. When the watched rig's weapon evolves (a
## workshop pick; WorldView detects it), the brass EVOLVED: <NAME> banner slams in (WorkshopUi shows it too).

const BANNER_TICKS := 75  ## how long a phase-start banner stays up (sim ticks)
const PVP_BANNER_TICKS := 105  ## the full-width PVP ON banner (#11)
const LOW_HP := 0.3  ## below this hp fraction the screen edges pulse red (#12)
const FEED_TICKS := 210  ## a kill feed line stays this long (7 s)
const FEED_MAX := 4
const DRAIN_WARN_TICKS := 12 * SimWorld.TICK_RATE  ## warn about the camp fuel drain this long before it
const FEED_BG := Color(0.1, 0.07, 0.07, 0.78)

var _panels: Array[Rect2] = []  ## HUD rects drawn this frame (rival arrows stay clear of them)
## Scrap counter of the watched rig: the shown value ticks up to the real one; a gain pulses it and
## floats "+N" over it. Real time, never in screenshot mode (frozen).
var _scrap_id: int = -1
var _scrap_seen: int = 0
var _scrap_shown: float = 0.0
var _scrap_pulse: float = 0.0  ## 1 -> 0
var _gain: int = 0
var _gain_t: float = 9.0  ## s since the last gain
## Kill combo pop: 1 on every chained kill, decays fast (real time, 0 when frozen).
var _combo_seen: int = 0
var _combo_pop: float = 0.0
var _combo_left: bool = false  ## the counter sits left of the rig (a rival is on its right)
const SCRAP_PULSE_S := 0.35
const GAIN_SHOW_S := 0.9

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(delta: float) -> void:
	_tick_juice(delta)
	queue_redraw()


func _tick_juice(delta: float) -> void:
	var v: SimVehicle = view.focus_vehicle() if view != null and world != null else null
	var frozen: bool = view == null or view.frozen
	if v == null:
		_scrap_id = -1
		return
	if v.id != _scrap_id or frozen or v.scrap < _scrap_seen:
		_scrap_id = v.id
		_scrap_shown = float(v.scrap)
		_scrap_pulse = 0.0
		_gain_t = 9.0
	elif v.scrap > _scrap_seen:
		var got: int = v.scrap - _scrap_seen
		_gain = (_gain + got) if _gain_t < GAIN_SHOW_S * 0.6 else got
		_gain_t = 0.0
		_scrap_pulse = 1.0
	_scrap_seen = v.scrap
	if not frozen:
		var gap: float = float(v.scrap) - _scrap_shown
		_scrap_shown = minf(float(v.scrap), _scrap_shown + maxf(24.0, gap * 9.0) * delta)
		_scrap_pulse = maxf(0.0, _scrap_pulse - delta / SCRAP_PULSE_S)
		_gain_t += delta
	var n: int = view.juice.combo
	if frozen:
		_combo_pop = 0.0
	elif n > _combo_seen:
		_combo_pop = 1.0
	else:
		_combo_pop = maxf(0.0, _combo_pop - delta * 7.0)
	_combo_seen = n


## Spectator keys: Tab / Right next rig, Shift+Tab / Left previous, Home or A back to auto.
func _unhandled_input(event: InputEvent) -> void:
	if view == null or not view.spectating() or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_TAB:
			view.cycle_spectate(-1 if k.shift_pressed else 1)
		KEY_RIGHT:
			view.cycle_spectate(1)
		KEY_LEFT:
			view.cycle_spectate(-1)
		KEY_HOME, KEY_A:
			view.spectate_auto()
		_:
			return
	get_viewport().set_input_as_handled()


## Ticks since the current phase started (from the sim's own timers, so it also works after a
## snapshot or in screenshot mode).
static func phase_elapsed(w: SimWorld) -> int:
	match w.phase:
		SimWorld.PHASE_COMBAT:
			return w.combat_duration(w.round) - w.phase_ticks_left
		SimWorld.PHASE_WORKSHOP:
			return w.workshop_duration() - w.phase_ticks_left
	return 0


func _draw() -> void:
	if world == null:
		return
	_panels.clear()
	var vs: Vector2 = get_viewport_rect().size
	if view != null and view.minimap != null and view.minimap.visible_now():
		_panels.append(Minimap.frame_rect(vs))
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	var spec: bool = view != null and view.spectating()
	var elim_recent: bool = me != null and me.eliminated and not spec
	var v: SimVehicle = view.focus_vehicle() if spec else me
	if world.phase == SimWorld.PHASE_COMBAT:
		var dead: bool = me != null and not me.alive and not me.eliminated
		if me != null and me.eliminated and (elim_recent or not spec):
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.05, 0.06, 0.45))
		elif dead:
			_dim(vs, view.local_screen_pos() if view else vs / 2.0)
		elif me != null and me.alive and me.hp / me.max_hp < LOW_HP:
			_low_hp(vs, me.hp / me.max_hp)
		if view != null and view.juice.surge_active(world.tick):
			_surge_edge(vs)
		_draw_rival_tags()  # under the panels
		_draw_top(vs)
		_draw_dock(v, vs)
		var watching: bool = spec and not elim_recent
		if world.vehicles.size() > 1:
			_draw_standings(v)
		if watching:
			_draw_spectating(vs, v)
		elif me != null and not me.eliminated:
			_draw_drain_warning(me, vs)
		_draw_feed(vs)
		_draw_grace(vs, watching)
		if v != null and (watching or not (me != null and me.eliminated)):
			_draw_rival_arrows(vs, v)
			if v.alive:
				_draw_combo(v)
		if view != null and view.juice.surge_active(world.tick):
			_draw_surge(vs, watching)
		if me != null and me.eliminated and not watching:
			_draw_eliminated(vs)
		elif dead:
			_draw_respawn(me, vs)
	var pv: int = world.tick - view.pvp_on_tick if view != null and view.pvp_on_tick >= 0 else -1
	if world.phase == SimWorld.PHASE_COMBAT and pv >= 0 and pv < PVP_BANNER_TICKS:
		_pvp_banner(vs, pv)
	if view != null and world.phase == SimWorld.PHASE_COMBAT and view.juice.evo_age(world.tick) >= 0:
		_draw_evolved(vs)
	var el: int = phase_elapsed(world)
	if el >= 0 and el < BANNER_TICKS:
		if world.phase == SimWorld.PHASE_COMBAT:
			_banner(vs, "ROUND %d" % world.round, "THE HIVE STIRS" if world.round > 1 else "HOLD THE LINE", el, 64.0)
		elif world.phase == SimWorld.PHASE_WORKSHOP:
			_banner(vs, "HIVE RETREATS", "MAKE CAMP - %s ON THE CLOCK" % UiKit.clock(world.workshop_duration()), el, 112.0)


## Name tag and hp bar over every rival rig on screen (screen space, so the text stays crisp).
func _draw_rival_tags() -> void:
	if view == null or view.attract:
		return
	for r in world.vehicles:
		if not r.alive or r.peer_id == local_peer:
			continue
		var p: Vector2 = view.screen_pos(r)
		var top: float = p.y - view.rig_radius(r) - 11.0
		var tag: String = UiKit.player_name(r)
		UiKit.paint_text(self, tag, Vector2(p.x - floorf(UiFont.width(tag) / 2.0), top), r.color_index)
		var bw: float = 22.0
		draw_rect(Rect2(p.x - bw / 2.0 - 1.0, top + 8.0, bw + 2.0, 3.0), Gfx.OUTLINE)
		draw_rect(Rect2(p.x - bw / 2.0, top + 9.0, floorf(bw * clampf(r.hp / r.max_hp, 0.0, 1.0)), 1.0), UiKit.bar_color(r.color_index))


func _last_wreck(v: SimVehicle) -> Dictionary:
	if view == null:
		return {}
	for i in range(view.wreck_log.size() - 1, -1, -1):
		if int(view.wreck_log[i]["id"]) == v.id:
			return view.wreck_log[i]
	return {}


# ---------------------------------------------------------------- combat panels
# Layout (UI revamp): the round, clock and hive top centre; everything about the watched rig in
# one dock at the bottom centre, close to where the eye is; standings top left (multiplayer:
# fuel decides the match); the kill feed top right; the minimap bottom right.

const TOP_W := 136.0
const DOCK_W := 322.0
const DOCK_H := 28.0


func _top_rect(vs: Vector2) -> Rect2:
	return Rect2(floorf(vs.x / 2.0 - TOP_W / 2.0), 4, TOP_W, 29)


func _dock_rect(vs: Vector2) -> Rect2:
	return Rect2(floorf(vs.x / 2.0 - DOCK_W / 2.0), vs.y - DOCK_H - 4.0, DOCK_W, DOCK_H)


## Top centre: round and hive on the left, the clock big on the right.
func _draw_top(vs: Vector2) -> void:
	var r: Rect2 = _top_rect(vs)
	_panels.append(r)
	UiKit.panel(self, r)
	var x0: float = r.position.x + 7.0
	UiFont.draw_big(self, "ROUND %d" % world.round, Vector2(x0, r.position.y + 6), Gfx.UI_TEXT, Gfx.OUTLINE)
	var hx: float = UiFont.draw_small(self, "HIVE %d" % world.enemy_count, Vector2(x0, r.position.y + 19), Gfx.GLOW[3], Gfx.UI_SHADOW)
	var boost: float = SimWorld.enemy_hp_mult(world.round) - 1.0
	UiFont.draw_small(self, ("  HP +%s" % UiKit.pct(boost)) if boost > 0.001 else "  HP BASE", Vector2(hx, r.position.y + 19), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var t: String = UiKit.clock(world.phase_ticks_left)
	var low: bool = world.phase_ticks_left < 10 * SimWorld.TICK_RATE
	UiFont.draw_big(self, t, Vector2(r.end.x - 7 - UiFont.width_big(t, 2), r.position.y + 7), Gfx.UI_TEXT if low else Gfx.FIRE[4], Gfx.OUTLINE, 2)


## Bottom centre: doctrine | hp and fuel | scrap and kills of the watched rig.
func _draw_dock(v: SimVehicle, vs: Vector2) -> void:
	var r: Rect2 = _dock_rect(vs)
	_panels.append(r)
	UiKit.panel(self, r)
	if v == null:
		return
	var y1: float = r.position.y + 6.0
	var y2: float = r.position.y + 17.0
	# doctrine: what the rig is doing, and which rules fire right now
	var dx: float = r.position.x + 7.0
	var lx: float = dx + 30.0
	UiFont.draw_small(self, "DRIVE", Vector2(dx, y1 + 1), Gfx.UI_DIM)
	var drive: String = _effective(v, "drive")
	UiFont.draw(self, drive.to_upper(), Vector2(lx, y1), Gfx.CRT_HI if drive != str(v.doctrine["drive"]) else Gfx.CRT_TEXT, Gfx.UI_SHADOW)
	UiFont.draw_small(self, "TARGET", Vector2(dx, y2 + 1), Gfx.UI_DIM)
	var tgt: String = _effective(v, "target")
	UiFont.draw(self, str(WorkshopUi.TARGET_LABELS.get(tgt, tgt.to_upper())), Vector2(lx, y2),
		Gfx.CRT_HI if tgt != str(v.doctrine["target"]) else Gfx.CRT_TEXT, Gfx.UI_SHADOW)
	_rule_lamps(v, Vector2(r.position.x + 91.0, y1 + 1.0))
	UiFont.draw_small(self, "P RULES", Vector2(r.position.x + 91.0, y2 + 1), Gfx.UI_DIM)
	var s1: float = r.position.x + 122.0
	draw_rect(Rect2(s1, r.position.y + 4, 1, r.size.y - 8), Color(UiKit.PANEL_EDGE, 0.8))
	# hp and fuel
	var bx: float = s1 + 24.0
	var num_x: float = r.position.x + 252.0
	var hp_frac: float = clampf(v.hp / v.max_hp, 0.0, 1.0) if v.alive else 0.0
	var low: bool = v.alive and hp_frac < LOW_HP
	UiFont.draw_small(self, "HP", Vector2(s1 + 6, y1 + 1), Gfx.UI_DIM)
	var hp_col: Color = UiKit.bar_color(v.color_index)
	if low and (world.tick / 6) % 2 == 0:
		hp_col = Gfx.UI_BAD
	UiKit.bar(self, Rect2(bx, y1 - 1, num_x - bx - 4, 8), hp_frac, hp_col)
	var hp_txt: String = str(ceili(maxf(v.hp, 0.0)) if v.alive else 0)
	UiFont.draw(self, hp_txt, Vector2(num_x, y1), Gfx.UI_BAD if low else Gfx.UI_TEXT, Gfx.UI_SHADOW)
	var fuel: int = maxi(v.fuel, 0)
	var fuel_col: Color = Gfx.FIRE[3] if fuel > 40 else Gfx.UI_BAD
	UiFont.draw_small(self, "FUEL", Vector2(s1 + 6, y2 + 1), Gfx.UI_DIM)
	UiKit.bar(self, Rect2(bx, y2 + 1, num_x - bx - 4, 5), float(fuel) / float(SimWorld.START_FUEL), fuel_col)
	UiFont.draw(self, str(fuel), Vector2(num_x, y2), fuel_col, Gfx.UI_SHADOW)
	var s2: float = r.position.x + 272.0
	draw_rect(Rect2(s2, r.position.y + 4, 1, r.size.y - 8), Color(UiKit.PANEL_EDGE, 0.8))
	# scrap and kills, numbers right-aligned
	var xr: float = r.end.x - 7.0
	UiFont.draw_small(self, "SCRAP", Vector2(s2 + 6, y1 + 1), Gfx.UI_DIM)
	_draw_scrap(v, xr, y1)
	UiFont.draw_small(self, "KILLS", Vector2(s2 + 6, y2 + 1), Gfx.UI_DIM)
	var kt := str(v.kills)
	UiFont.draw(self, kt, Vector2(xr - UiFont.width(kt), y2), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	_draw_mobility(v, r)
	_draw_contract(v, r)


## The accepted contract on top of the dock: what it asks, a progress bar and the count.
func _draw_contract(v: SimVehicle, dock: Rect2) -> void:
	if v.contract_kind < 0:
		return
	var up: bool = Mobility.has_momentum(v) or v.abilities[0] != "" or v.abilities[1] != ""
	var y: float = dock.position.y - (18.0 if up else 9.0)
	var done: bool = Salvage.is_done(v)
	var failed: bool = v.contract_kind == Salvage.K_NO_DEATH and v.contract_prog < 0.0
	var col: Color = Gfx.UI_BAD if failed else (Gfx.FIRE[5] if done else Gfx.UI_DIM)
	var txt: String = "%s  %s" % [UiKit.contract_title(v.contract_kind, v.contract_need), UiKit.contract_progress(v)]
	var x: float = dock.position.x + 7.0
	UiFont.draw_small(self, "CONTRACT", Vector2(x, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	x += UiFont.width_small("CONTRACT") + 5.0
	if v.contract_kind != Salvage.K_NO_DEATH:
		var f: float = clampf(v.contract_prog / float(maxi(v.contract_need, 1)), 0.0, 1.0)
		UiKit.bar(self, Rect2(x, y, 40, 5), f, Gfx.FIRE[5] if done else Gfx.FIRE[3])
		x += 44.0
	UiFont.draw_small(self, txt, Vector2(x, y), col, Gfx.UI_SHADOW)
	UiFont.draw_small(self, UiKit.contract_reward_text(v, v.contract_reward), Vector2(x + UiFont.width_small(txt) + 6.0, y), Gfx.FIRE[4], Gfx.UI_SHADOW)


## Momentum bar (warm; sparks at full) and the two ability slots, on top of the dock. Only for rigs that have
## the Tuned Engine / an ability.
func _draw_mobility(v: SimVehicle, dock: Rect2) -> void:
	var has_mom: bool = Mobility.has_momentum(v)
	var has_ab: bool = v.abilities[0] != "" or v.abilities[1] != ""
	if not has_mom and not has_ab:
		return
	var x: float = dock.position.x + 7.0
	var y: float = dock.position.y - 9.0
	if has_mom:
		var f: float = clampf(v.momentum / Mobility.MOMENTUM_MAX, 0.0, 1.0)
		var full: bool = v.momentum >= Mobility.FULL_MOMENTUM
		draw_rect(Rect2(x - 1, y - 1, 62, 7), Gfx.OUTLINE)
		draw_rect(Rect2(x, y, 60, 5), Gfx.UI_PLATE_DARK)
		draw_rect(Rect2(x, y, floorf(60.0 * f), 5), Gfx.FIRE[5] if full and (world.tick / 3) % 2 == 0 else Gfx.FIRE[3])
		UiFont.draw_small(self, "MOMENTUM", Vector2(x + 64, y), Gfx.FIRE[5] if full else Gfx.UI_DIM, Gfx.UI_SHADOW)
		x += 118.0
	for s in Abilities.SLOTS:
		var id: String = v.abilities[s]
		if id == "":
			continue
		var cd: int = v.ab_cd[s]
		var ready: bool = Abilities.is_ready(v, id)
		var label: String = "%s %s" % [["F", "G"][s], id.to_upper()]
		var col: Color = Gfx.FIRE[5] if ready else Gfx.UI_DIM
		if cd > 0:
			label += " %d" % ceili(float(cd) / float(SimWorld.TICK_RATE))
		UiFont.draw_small(self, label, Vector2(x, y), col, Gfx.UI_SHADOW)
		x += UiFont.width_small(label) + 10.0


## What the rig does right now in action group `group` ("drive" / "target"): the first lit rule of
## that group, else the base doctrine. Built from the synced rules and lamps, so clients agree.
static func _effective(v: SimVehicle, group: String) -> String:
	var slots: int = Doctrine.slots(v)
	for i in mini(v.rules.size(), slots):
		if (v.rule_live >> i) & 1 == 1:
			var a: String = str(v.rules[i]["do"])
			if Doctrine.action_group(a) == group:
				return Doctrine.action_value(a)
	return str(v.doctrine[group])


## One lamp per rule slot: lit while the rule matches, dim when set, dark when empty.
func _rule_lamps(v: SimVehicle, pos: Vector2) -> void:
	var slots: int = Doctrine.slots(v)
	for i in slots:
		var p := Vector2(pos.x + i * 6.0, pos.y)
		var lit: bool = (v.rule_live >> i) & 1 == 1
		var used: bool = i < v.rules.size()
		draw_rect(Rect2(p - Vector2.ONE, Vector2(6, 6)), Gfx.OUTLINE)
		draw_rect(Rect2(p, Vector2(4, 4)), Gfx.CRT_HI if lit else (Gfx.CRT_DIM if used else Gfx.UI_PLATE_DARK))


# ---------------------------------------------------------------- overlays

func _dim(vs: Vector2, center: Vector2) -> void:
	var s := Vector2(Gfx.TEX_VIGNETTE.get_size())
	draw_texture(Gfx.TEX_VIGNETTE, (center - s / 2.0).floor())
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.05, 0.06, 0.25))


func _draw_respawn(v: SimVehicle, vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var r := Rect2(cx - 84, 92, 168, 57)
	UiKit.panel(self, r)
	UiKit.center_big(self, "RIG DESTROYED", cx, r.position.y + 6, Gfx.FIRE[4], Gfx.OUTLINE)
	_wreck_cause(v, cx, r.position.y + 17)
	var secs: float = float(maxi(v.respawn_ticks, 0)) / float(SimWorld.TICK_RATE)
	UiKit.center_text(self, "BACK ON THE ROAD IN %.1f" % secs, cx, r.position.y + 27, Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiKit.bar(self, Rect2(r.position.x + 10, r.position.y + 36, r.size.x - 20, 5),
		1.0 - float(v.respawn_ticks) / float(SimWorld.RESPAWN_TICKS), Gfx.FIRE[3])
	UiKit.center_text(self, "FUEL LEFT %d" % maxi(v.fuel, 0), cx, r.position.y + 45, Gfx.UI_BAD if v.fuel <= 40 else Gfx.UI_DIM, Gfx.UI_SHADOW)


## "WRECKED BY <cause>" centred at (cx, y): the rival's name in its paint and the weapon, or the alien.
func _wreck_cause(v: SimVehicle, cx: float, y: float) -> void:
	var e: Dictionary = _last_wreck(v)
	if e.is_empty():
		return
	var cause: int = int(e["cause"])
	var killer: SimVehicle = UiKit.vehicle_by_id(world, int(e["killer"]))
	if killer == null or cause < SimWorld.SRC_RAM:
		var what: String = UiKit.CAUSE_TEXT.get(SimWorld.SRC_NAMES[clampi(cause, 0, SimWorld.SRC_NAMES.size() - 1)], "THE HIVE") if cause >= 0 else "THE HIVE"
		UiKit.center_text(self, "WRECKED BY %s" % what, cx, y, Gfx.UI_BAD, Gfx.UI_SHADOW)
		return
	var weapon: String = UiKit.weapon_long(Recap.killer_weapon(view, v.id, killer.id, int(e["round"])))
	var pre := "WRECKED BY "
	var post: String = (" - %s" % weapon) if weapon != "" else ""
	var nm: String = UiKit.player_name(killer)
	var w: float = UiFont.width(pre) + UiFont.width(nm) + UiFont.width(post)
	var x: float = floorf(cx - w / 2.0)
	x = UiFont.draw(self, pre, Vector2(x, y), Gfx.UI_BAD, Gfx.UI_SHADOW)
	x = UiKit.paint_text(self, nm, Vector2(x, y), killer.color_index)
	UiFont.draw(self, post, Vector2(x, y), Gfx.FIRE[4] if weapon == "RAMMED" else Gfx.UI_TEXT, Gfx.UI_SHADOW)


func _draw_eliminated(vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	var cause: bool = me != null and not _last_wreck(me).is_empty()
	var r := Rect2(cx - 92, 92, 184, 54 if cause else 44)
	UiKit.panel(self, r)
	UiKit.hazard_frame(self, r.grow(-3.0), 2.0)
	UiKit.center_big(self, "ELIMINATED", cx, r.position.y + 9, Gfx.UI_BAD, Gfx.OUTLINE, 2)
	UiKit.center_text(self, "OUT OF FUEL - WATCHING THE OTHERS", cx, r.position.y + 30, Gfx.UI_TEXT, Gfx.UI_SHADOW)
	if cause:
		_wreck_cause(me, cx, r.position.y + 40)


# ---------------------------------------------------------------- kill feed, rivals, grace, drain

## Player kills under the hive plate, newest on top: KILLER > VICTIM WEAPON (rams in fire colour).
## Lines with the watched / local rig get a hazard edge. Alien kills are never listed.
func _draw_feed(vs: Vector2) -> void:
	if view == null:
		return
	var me: SimVehicle = view.focus_vehicle()
	var y: float = 6.0
	var shown: int = 0
	for i in range(view.kill_log.size() - 1, -1, -1):
		var e: Dictionary = view.kill_log[i]
		var age: int = world.tick - int(e["tick"])
		if age >= FEED_TICKS or int(e["round"]) != world.round:
			break
		if age < 0:
			continue
		var kv: SimVehicle = UiKit.vehicle_by_id(world, int(e["killer"]))
		var vv: SimVehicle = UiKit.vehicle_by_id(world, int(e["victim"]))
		if kv == null or vv == null:
			continue
		if age > FEED_TICKS - 15 and (age / 3) % 2 == 0:
			y += 13.0
			shown += 1
			continue
		var weapon: int = int(e["weapon"])
		var wt: String = "RAMMED" if weapon == SimWorld.WEAPON_RAM else UiKit.weapon_short(weapon)
		var kn: String = UiKit.player_name(kv)
		var vn: String = UiKit.player_name(vv)
		var w: float = UiFont.width(kn) + 5.0 + 6.0 + 5.0 + UiFont.width(vn) + 6.0 + UiFont.width(wt) + 12.0
		var r := Rect2(vs.x - 6.0 - w, y, w, 12)
		var mine: bool = me != null and (kv == me or vv == me)
		draw_rect(r, Gfx.OUTLINE)
		draw_rect(r.grow(-1.0), FEED_BG if not mine else Color(0.22, 0.13, 0.08, 0.9))
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(2, r.size.y - 2)), UiKit.bar_color(kv.color_index))
		if mine:
			UiKit.outline_rect(self, r, Gfx.HAZARD)
		var x: float = r.position.x + 6.0
		x = UiKit.paint_text(self, kn, Vector2(x, y + 3), kv.color_index) + 4.0
		x = UiKit.arrow_glyph(self, Vector2(x, y + 3.5), Gfx.UI_TEXT, Gfx.UI_SHADOW) + 5.0
		x = UiKit.paint_text(self, vn, Vector2(x, y + 3), vv.color_index) + 6.0
		UiFont.draw(self, wt, Vector2(x, y + 3), Gfx.FIRE[4] if weapon == SimWorld.WEAPON_RAM else Gfx.UI_DIM, Gfx.UI_SHADOW)
		_panels.append(r)
		y += 13.0
		shown += 1
		if shown >= FEED_MAX:
			break


## An arrow at the screen edge for every rival rig that is off-screen: paint colour, tiny hp and fuel
## pips behind it, smaller and fainter the farther away it is. Kept clear of the HUD plates.
func _draw_rival_arrows(vs: Vector2, focus: SimVehicle) -> void:
	if view == null or world.vehicles.size() < 2:
		return
	var screen := Rect2(Vector2.ZERO, vs)
	var inset := Rect2(Vector2(9, 9), vs - Vector2(18, 18))
	var c: Vector2 = vs / 2.0
	for r: SimVehicle in world.vehicles:
		if r == focus or r.eliminated or not r.alive or r.peer_id == local_peer:
			continue
		var sp: Vector2 = view.screen_pos(r)
		if screen.grow(-4.0).has_point(sp):
			continue
		var d: Vector2 = sp - c
		if d.length_squared() < 1.0:
			continue
		var dir: Vector2 = d.normalized()
		var t: float = INF
		if absf(dir.x) > 0.001:
			t = minf(t, ((inset.end.x if dir.x > 0.0 else inset.position.x) - c.x) / dir.x)
		if absf(dir.y) > 0.001:
			t = minf(t, ((inset.end.y if dir.y > 0.0 else inset.position.y) - c.y) / dir.y)
		var p: Vector2 = _clear_of_panels(c + dir * t, inset)
		var dist: float = focus.pos.distance_to(r.pos) if focus != null else 600.0
		var far: float = clampf((dist - 340.0) / 700.0, 0.0, 1.0)
		var size: float = roundf(lerpf(11.0, 7.0, far))
		var col: Color = UiKit.bar_color(r.color_index)
		var a: float = lerpf(1.0, 0.75, far)
		# hp / fuel gauge on a dark tag on the inward side of the arrow
		var pc: Vector2 = (p - dir * (size + 9.0)).floor()
		var pr := Rect2(pc - Vector2(9, 4), Vector2(18, 8))
		draw_rect(pr, Color(Gfx.OUTLINE, 0.85 * a))
		UiKit.outline_rect(self, pr, Color(col.darkened(0.3), a))
		draw_rect(Rect2(pr.position + Vector2(2, 2), Vector2(floorf(14.0 * clampf(r.hp / r.max_hp, 0.0, 1.0)), 2)), Color(col, a))
		draw_rect(Rect2(pr.position + Vector2(2, 5), Vector2(floorf(14.0 * clampf(float(r.fuel) / float(SimWorld.START_FUEL), 0.0, 1.0)), 1)), Color(Gfx.FIRE[3], a))
		UiKit.pointer(self, p.floor() + Vector2(0.5, 0.5), dir, size, Color(col, 1.0))
		if r.peer_id == world.leader_peer:
			var s := Vector2(Gfx.TEX_SKULL.get_size())
			var sp2: Vector2 = pc - Vector2(s.x / 2.0, s.y + 6.0) if pc.y > vs.y / 2.0 or pc.y > 30.0 else pc + Vector2(-s.x / 2.0, 6.0)
			draw_texture(Gfx.TEX_SKULL, sp2.floor(), Color(1, 1, 1, a))


## Moves an edge point out of any HUD plate (to the nearest free side, still inside `bounds`).
func _clear_of_panels(p: Vector2, bounds: Rect2) -> Vector2:
	for pass_i in 3:
		var hit: Rect2 = Rect2()
		var found: bool = false
		for r in _panels:
			if r.grow(12.0).has_point(p):
				hit = r.grow(12.0)
				found = true
				break
		if not found:
			return p
		var cands: Array[Vector2] = [Vector2(p.x, hit.end.y + 1.0), Vector2(p.x, hit.position.y - 1.0),
			Vector2(hit.end.x + 1.0, p.y), Vector2(hit.position.x - 1.0, p.y)]
		var best: Vector2 = p
		var best_d: float = INF
		for q in cands:
			if bounds.has_point(q) and q.distance_to(p) < best_d:
				best_d = q.distance_to(p)
				best = q
		p = best
	return p


## PvP grace (round PVP_START_ROUND): a hazard-framed countdown at the top until rivals may shoot.
func _draw_grace(vs: Vector2, below: bool) -> void:
	if world.phase != SimWorld.PHASE_COMBAT or world.pvp_grace_ticks <= 0:
		return
	var cx: float = floorf(vs.x / 2.0)
	var secs: int = ceili(float(world.pvp_grace_ticks) / float(SimWorld.TICK_RATE))
	var title := "PVP IN %d" % secs
	var r := Rect2(cx - 60, 66.0 if below else 37.0, 120, 27)
	UiKit.panel(self, r)
	UiKit.hazard_frame(self, r.grow(-2.0), 2.0)
	var hot: bool = secs <= 3 and (world.tick / 5) % 2 == 0
	UiKit.center_big(self, title, cx, r.position.y + 6, Gfx.UI_BAD if hot else Gfx.FIRE[4], Gfx.OUTLINE)
	UiKit.center_text(self, "RIVALS HOLD FIRE - FOR NOW", cx, r.position.y + 16, Gfx.UI_DIM, Gfx.UI_SHADOW)
	_panels.append(r)


## Late rounds of a multiplayer game: a tape under the status plate before camp drains fuel.
func _draw_drain_warning(v: SimVehicle, vs: Vector2) -> void:
	if world.vehicles.size() < 2 or v.eliminated:
		return
	var drain: int = SimWorld.fuel_drain_for_round(world.round)
	if drain <= 0 or world.phase_ticks_left > DRAIN_WARN_TICKS:
		return
	var text := "CAMP DRAINS %d FUEL - KILLS REFUEL" % drain
	var w: float = UiFont.width(text) + 10.0
	var r := Rect2(floorf(vs.x / 2.0 - w / 2.0), _dock_rect(vs).position.y - 14.0, w, 10)
	UiKit.tape(self, r, Color("#f0b090"))
	UiFont.draw(self, text, Vector2(r.position.x + 5, r.position.y + 2), Gfx.INK)
	_panels.append(r)


# ---------------------------------------------------------------- spectator

## Top centre: whom the camera follows, and the keys to switch.
func _draw_spectating(vs: Vector2, v: SimVehicle) -> void:
	if v == null:
		return
	var cx: float = floorf(vs.x / 2.0)
	var nm: String = UiKit.player_name(v)
	var w: float = maxf(UiFont.width_big(nm) + UiFont.width("SPECTATING") + 30.0, 150.0)
	var r := Rect2(cx - floorf(w / 2.0), 37, w, 27)
	UiKit.panel(self, r)
	var x0: float = cx - floorf((UiFont.width("SPECTATING") + 6.0 + UiFont.width_big(nm)) / 2.0)
	var x: float = UiFont.draw(self, "SPECTATING", Vector2(x0, r.position.y + 7), Gfx.UI_DIM, Gfx.UI_SHADOW) + 6.0
	UiKit.paint_big(self, nm, Vector2(x, r.position.y + 6), v.color_index)
	var auto: bool = view.spectate_id < 0
	var keys: String = ("AUTO CAM - " if auto else "") + "TAB  < >  SWITCH RIG"
	UiKit.center_text(self, keys, cx, r.position.y + 17, Gfx.UI_DIM, Gfx.UI_SHADOW)
	_panels.append(r)


## Live standings top left in every multiplayer combat (fuel decides the match, then kills); the
## watched / local rig is marked.
func _draw_standings(watched: SimVehicle) -> void:
	var rows: Array[SimVehicle] = UiKit.standings(world)
	var r := Rect2(6, 6, 140, 18 + rows.size() * 10)
	UiKit.panel(self, r)
	_panels.append(r)
	UiKit.section(self, "STANDINGS", r.position + Vector2(6, 5), r.size.x - 12, "FUEL   KILLS")
	var y: float = r.position.y + 16.0
	for i in rows.size():
		var o: SimVehicle = rows[i]
		var out: bool = o.eliminated
		if o == watched:
			draw_rect(Rect2(r.position.x + 3, y - 2, r.size.x - 6, 10), Color(1.0, 0.8, 0.5, 0.12))
			UiKit.arrow_glyph(self, Vector2(r.position.x + 4, y), Gfx.HAZARD)
		UiFont.draw(self, str(i + 1), Vector2(r.position.x + 12, y), Gfx.UI_DIM if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		UiKit.swatch(self, Rect2(r.position.x + 18, y - 1, 7, 7), o.color_index)
		if out:
			UiFont.draw(self, UiKit.player_name(o), Vector2(r.position.x + 28, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
		else:
			UiKit.paint_text(self, UiKit.player_name(o), Vector2(r.position.x + 28, y), o.color_index)
		var ft: String = "OUT" if out else str(maxi(o.fuel, 0))
		UiFont.draw(self, ft, Vector2(r.end.x - 34 - UiFont.width(ft), y), Gfx.UI_DIM if out else Gfx.FIRE[3], Gfx.UI_SHADOW)
		var kt := str(o.kills)
		UiFont.draw(self, kt, Vector2(r.end.x - 6 - UiFont.width(kt), y), Gfx.UI_DIM if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		y += 10.0


## Pulsing warm-red edge bands (banded, dithered pixel style) while the rig is nearly wrecked.
func _low_hp(vs: Vector2, frac: float) -> void:
	var pulse: float = 0.7 + 0.3 * sin(float(world.tick) * 0.42)
	var k: float = (0.6 + 0.4 * clampf(1.0 - frac / LOW_HP, 0.0, 1.0)) * pulse
	var col: Color = Color("#b02a28")
	var bands: PackedFloat32Array = [0.55, 0.4, 0.27, 0.16, 0.08]
	for i in bands.size():
		var w: float = 6.0
		var a: float = bands[i] * k
		var o: float = float(i) * w
		draw_rect(Rect2(o, o, vs.x - 2.0 * o, w), Color(col, a))
		draw_rect(Rect2(o, vs.y - o - w, vs.x - 2.0 * o, w), Color(col, a))
		draw_rect(Rect2(o, o + w, w, vs.y - 2.0 * o - 2.0 * w), Color(col, a))
		draw_rect(Rect2(vs.x - o - w, o + w, w, vs.y - 2.0 * o - 2.0 * w), Color(col, a))


## Full-width hazard banner when PvP switches on: rival rigs are fair game from now on (#11).
func _pvp_banner(vs: Vector2, el: int) -> void:
	var slide: float = clampf(1.0 - float(el) / 6.0, 0.0, 1.0)
	var fade_out: bool = el > PVP_BANNER_TICKS - 12
	var y: float = 94.0  # under the round banner, clear of the rig in the middle
	var h: float = 40.0
	var x: float = floorf(-slide * vs.x)
	if fade_out and (el / 2) % 2 == 0:
		return
	draw_rect(Rect2(x, y - 1, vs.x, h + 2), Gfx.OUTLINE)
	UiKit.hazard_frame(self, Rect2(x, y, vs.x, h), 4.0)
	draw_rect(Rect2(x, y + 5, vs.x, h - 10), Color("#2a1c18"))
	draw_rect(Rect2(x, y + 5, vs.x, 1), Color("#5e2f1e"))
	var cx: float = floorf(x + vs.x / 2.0)
	var flick: Color = Gfx.UI_BAD if (el / 4) % 2 == 0 or el > 24 else Gfx.FIRE[5]
	UiKit.center_big(self, "PVP ON", cx, y + 9, flick, Gfx.OUTLINE, 2)
	UiKit.center_text(self, "RIVAL RIGS ARE FAIR GAME - BOUNTY ON THE LEADER", cx, y + 27, Gfx.UI_TEXT, Gfx.UI_SHADOW)
	var s := Vector2(Gfx.TEX_SKULL.get_size())
	var tw: float = UiFont.width_big("PVP ON") * 2.0
	for sx: float in [cx - tw / 2.0 - 18.0 - s.x, cx + tw / 2.0 + 18.0]:
		draw_texture(Gfx.TEX_SKULL, Vector2(floorf(sx), y + 13))


## Tape banner that slides in and stays; `el` = ticks since the phase started.
func _banner(vs: Vector2, title: String, sub: String, el: int, y: float) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var tw: float = maxf(UiFont.width_big(title), UiFont.width(sub)) + 24.0
	var slide: float = clampf(1.0 - float(el) / 8.0, 0.0, 1.0)
	var r := Rect2(floorf(cx - tw / 2.0 - slide * 60.0), y, tw, 22)
	UiKit.tape(self, r, Color("#e8dcc4"))
	UiKit.center_big(self, title, r.get_center().x, y + 3, Gfx.INK)
	UiKit.center_text(self, sub, r.get_center().x, y + 13, Gfx.INK_RED)


# ---------------------------------------------------------------- combat juice

## The dock's scrap number: ticks up toward the real value; a gain lights it white-hot for a moment
## (a warm glow behind it) and floats "+N" above the dock.
func _draw_scrap(v: SimVehicle, xr: float, y: float) -> void:
	var shown: int = v.scrap if v.id != _scrap_id else mini(int(_scrap_shown), v.scrap)
	var st := str(shown)
	var w: float = UiFont.width(st)
	var p: float = _scrap_pulse
	if p > 0.0:
		draw_rect(Rect2(xr - w - 2.0, y - 2.0, w + 4.0, UiFont.HEIGHT + 4.0), Color(Gfx.FIRE[3], 0.35 * p))
	var col: Color = Gfx.FIRE[4].lerp(Gfx.FIRE[6], p)
	UiFont.draw(self, st, Vector2(xr - w, y - roundf(p * 2.0) / 2.0), col, Gfx.UI_SHADOW)
	if _gain > 0 and _gain_t < GAIN_SHOW_S:
		var f: float = _gain_t / GAIN_SHOW_S
		var gt: String = "+%d" % _gain
		var gy: float = y - 14.0 - f * 5.0
		var gc: Color = Color(Gfx.FIRE[5], 1.0 if f < 0.6 else (1.0 - f) / 0.4)
		UiFont.draw_big_rim(self, gt, Vector2(xr - UiFont.width_big_px(gt, 10), gy), gc, Color(Gfx.OUTLINE, gc.a), 10)


## The watched rig's kill chain next to it: "x24" growing and warming (pale gold to deep fire) with the
## combo, popping on every kill, and a stencil milestone word at 10 / 25 / 50 / 100 / 200.
func _draw_combo(v: SimVehicle) -> void:
	var j: JuiceState = view.juice
	var n: int = j.combo_shown(world.tick)
	if n <= 0:
		return
	var heat: float = JuiceState.heat(n)
	var live: bool = j.combo_live(world.tick)
	var a: float = 1.0
	if not live:
		a = clampf(1.0 - float(world.tick - j.combo_last - JuiceState.COMBO_WINDOW) / float(JuiceState.COMBO_FADE), 0.0, 1.0)
	var ramp: Array[Color] = [Gfx.FIRE[5], Gfx.FIRE[4], Gfx.FIRE[3], Gfx.FIRE[2]]
	var fi: float = heat * 3.0
	var col: Color = ramp[mini(int(fi), 2)].lerp(ramp[mini(int(fi) + 1, 3)], fi - floorf(fi))
	if _combo_pop > 0.6:
		col = Gfx.FIRE[6]
	col.a = a
	var size: int = 13 + int(round(heat * 13.0)) + int(round(_combo_pop * 4.0))
	var p: Vector2 = view.screen_pos(v)
	var r: float = view.rig_radius(v)
	var ma: int = j.milestone_age(world.tick) if live else -1
	var xw: int = UiFont.width_big_px("x", int(size * 0.7))
	var bw: float = float(xw + 1 + UiFont.width_big_px(str(n), size))
	if ma >= 0:
		bw = maxf(bw, float(UiFont.width_big_px(j.milestone_word, 11, true)))
	var bh: float = float(size) * UiFont.CAP + 16.0
	var y: float = p.y - r - 6.0 - float(size) * UiFont.CAP
	# right of the rig unless a rival rig or its tag is there (sticky, so it does not flip every frame)
	var right := Rect2(p.x + r + 8.0, y - 14.0, bw, bh)
	var left := Rect2(p.x - r - 8.0 - bw, y - 14.0, bw, bh)
	var cur: Rect2 = left if _combo_left else right
	var other: Rect2 = right if _combo_left else left
	if _rival_near(v, cur) and not _rival_near(v, other):
		_combo_left = not _combo_left
	var x: float = (left if _combo_left else right).position.x
	var rim := Color(Gfx.OUTLINE, a)
	var xe: float = UiFont.draw_big_rim(self, "x", Vector2(x, y + float(size) * 0.25), col, rim, int(size * 0.7))
	UiFont.draw_big_rim(self, str(n), Vector2(xe + 1.0, y), col, rim, size)
	if not live:
		return
	if ma < 0:
		UiFont.draw_big_rim(self, "KILL CHAIN", Vector2(x + 1.0, y - 8.0), Color(Gfx.UI_DIM, 0.9), rim, 7)
		return
	# milestone: slams in big, settles, blinks out
	var slam: float = clampf(1.0 - float(ma) / 5.0, 0.0, 1.0)
	if ma > JuiceState.MILESTONE_TICKS - 8 and (ma / 2) % 2 == 0:
		return
	var ms: int = 11 + int(round(slam * 8.0))
	var mc: Color = Gfx.FIRE[6] if ma < 3 else (Gfx.UI_BAD if (ma / 4) % 2 == 0 else Gfx.FIRE[4])
	UiFont.draw_big_rim(self, j.milestone_word, Vector2(x + 1.0, y - float(ms) * UiFont.TITLE_CAP - 4.0), mc, rim, ms, true)


## True when another live rig (with its name tag and hp bar) overlaps `r` on screen.
func _rival_near(v: SimVehicle, r: Rect2) -> bool:
	for o in world.vehicles:
		if o == v or not o.alive:
			continue
		var op: Vector2 = view.screen_pos(o)
		var orad: float = view.rig_radius(o)
		if r.intersects(Rect2(op.x - maxf(orad, 26.0), op.y - orad - 13.0, maxf(orad, 26.0) * 2.0, orad * 2.0 + 13.0)):
			return true
	return false


## Top centre while a hive surge is announced: SWARM INCOMING on a plate with a cyan (the hive) rim
## that flickers, the seconds to go, then HERE THEY COME as it hits. Dormant unless a "surge" arrives.
func _draw_surge(vs: Vector2, below: bool) -> void:
	var j: JuiceState = view.juice
	var el: int = world.tick - j.surge_tick
	var left: int = j.surge_left(world.tick)
	var cx: float = floorf(vs.x / 2.0)
	var y: float = 37.0 + (29.0 if below else 0.0) + (31.0 if world.pvp_grace_ticks > 0 else 0.0)
	y -= floorf(clampf(1.0 - float(el) / 5.0, 0.0, 1.0) * 30.0)  # drops in from under the top plate
	if left <= 0 and -left > JuiceState.SURGE_HOLD - 8 and (el / 2) % 2 == 0:
		return
	var title := "SWARM INCOMING"
	var w: float = UiFont.width_big(title, 1) + 46.0
	var r := Rect2(cx - floorf(w / 2.0), y, w, 26)
	UiKit.panel(self, r)
	var flick: bool = (el / 3) % 2 == 0
	UiKit.outline_rect(self, r.grow(-2.0), Gfx.GLOW[3] if flick else Gfx.GLOW[2])
	var glow: Color = Gfx.GLOW[4] if left <= 0 or flick else Gfx.GLOW[3]
	UiKit.center_big(self, title, cx, r.position.y + 5, glow, Gfx.OUTLINE)
	var sub: String = "HIVE SURGE IN %d" % ceili(float(left) / float(SimWorld.TICK_RATE)) if left > 0 else "HERE THEY COME"
	UiKit.center_small(self, sub, cx, r.position.y + 16, Gfx.UI_TEXT if left > 0 else Gfx.GLOW[4], Gfx.UI_SHADOW)
	for sx: float in [r.position.x + 8.0, r.end.x - 13.0]:  # bioluminescent pips, beating faster as it nears
		var on: bool = (el / maxi(2, mini(6, left / 10 + 2))) % 2 == 0
		draw_rect(Rect2(sx - 1, r.position.y + 9, 7, 7), Gfx.OUTLINE)
		draw_rect(Rect2(sx, r.position.y + 10, 5, 5), Gfx.GLOW[4] if on else Gfx.GLOW[1])
	_panels.append(r)


## A faint cyan pulse on the screen edges while the surge is announced (dithered bands like the low-hp
## warning, much weaker).
func _surge_edge(vs: Vector2) -> void:
	var j: JuiceState = view.juice
	var el: int = world.tick - j.surge_tick
	var fade: float = clampf(float(j.surge_in + JuiceState.SURGE_HOLD - el) / 12.0, 0.0, 1.0) * clampf(float(el) / 4.0, 0.0, 1.0)
	var k: float = (0.6 + 0.4 * sin(float(el) * 0.5)) * fade
	var col: Color = Gfx.GLOW[2]
	var bands: PackedFloat32Array = [0.26, 0.15, 0.07]
	for i in bands.size():
		var w: float = 4.0
		var a: float = bands[i] * k
		var o: float = float(i) * w
		draw_rect(Rect2(o, o, vs.x - 2.0 * o, w), Color(col, a))
		draw_rect(Rect2(o, vs.y - o - w, vs.x - 2.0 * o, w), Color(col, a))
		draw_rect(Rect2(o, o + w, w, vs.y - 2.0 * o - 2.0 * w), Color(col, a))
		draw_rect(Rect2(vs.x - o - w, o + w, w, vs.y - 2.0 * o - 2.0 * w), Color(col, a))


## The watched rig's weapon just evolved (combat: under the top plate; the workshop draws its own, over
## its panels).
func _draw_evolved(vs: Vector2) -> void:
	var y: float = 40.0 + (29.0 if view.spectating() else 0.0) + (31.0 if world.pvp_grace_ticks > 0 else 0.0)
	var r: Rect2 = draw_evolved_banner(self, view.juice, world.tick, floorf(vs.x / 2.0), y, false)
	if r.size.x > 0.0:
		_panels.append(r)


## The EVOLVED banner: a brass-framed gunmetal plate slams in with "EVOLVED: GATLING HELL" in the stencil
## face, white-hot first, then gold; the recipe under it, a glint sweeping across and (unless `compact`, for
## the workshop's narrow middle) the new gun on both flanks. Returns the plate (empty when hidden).
static func draw_evolved_banner(ci: CanvasItem, j: JuiceState, tick: int, cx: float, y: float, compact: bool) -> Rect2:
	var el: int = j.evo_age(tick)
	if el < 0 or (el > JuiceState.EVO_BANNER_TICKS - 12 and (el / 2) % 2 == 0):
		return Rect2()
	var title: String = "EVOLVED: " + j.evo_word
	var slam: float = clampf(1.0 - float(el) / 5.0, 0.0, 1.0)
	var base: int = 13 if compact else 17
	var size: int = base + int(round(slam * float(base) * 0.5))
	var tw: float = float(UiFont.width_big_px(title, size, true))
	var w: float = float(UiFont.width_big_px(title, base, true)) + (30.0 if compact else 64.0)
	var h: float = 30.0 if compact else 34.0
	var r := Rect2(cx - floorf(w / 2.0), y, w, h)
	# plate: dark gunmetal, a two-tone brass frame, rivets
	ci.draw_rect(r.grow(1.0), Gfx.OUTLINE)
	ci.draw_rect(r, Gfx.BRASS[2])
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Gfx.BRASS[3])
	ci.draw_rect(Rect2(r.position, Vector2(1, r.size.y)), Gfx.BRASS[3])
	ci.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Gfx.BRASS[0])
	ci.draw_rect(Rect2(r.end.x - 1, r.position.y, 1, r.size.y), Gfx.BRASS[0])
	var inner: Rect2 = r.grow(-3.0)
	ci.draw_rect(inner.grow(1.0), Gfx.BRASS[0])
	ci.draw_rect(inner, Color("#221c1d"))
	ci.draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), Color("#352c2b"))
	for p: Vector2 in [r.position + Vector2(1, 1), Vector2(r.end.x - 2, r.position.y + 1), Vector2(r.position.x + 1, r.end.y - 2), r.end - Vector2(2, 2)]:
		ci.draw_rect(Rect2(p, Vector2.ONE), Gfx.STEEL[5])
	if el < 12:  # a glint sweeping across the plate
		var gx: float = floorf(inner.position.x + (inner.size.x + 20.0) * float(el) / 11.0 - 10.0)
		for row in int(inner.size.y):
			var x: float = gx - float(row) * 0.5
			if x > inner.position.x and x + 3.0 < inner.end.x:
				ci.draw_rect(Rect2(x, inner.position.y + float(row), 3, 1), Color(Gfx.FIRE[6], 0.22))
	if not compact:  # the new gun on both flanks
		var ki: int = Cards.weapon_kind_index(j.evo_kind)
		var fs: float = float(RigArt.GUN_EVO_FRAME)
		for side in 2:
			var frame: int = 6 if side == 0 else 26
			var src := Rect2(float(frame) * fs, float(ki * 2 + (tick / 3) % 2) * fs, fs, fs)
			var gx: float = r.position.x - 30.0 if side == 0 else r.end.x - 26.0
			ci.draw_texture_rect_region(RigArt.GUN_EVO_TEX, Rect2(Vector2(floorf(gx), floorf(r.get_center().y - fs / 2.0)), Vector2(fs, fs)), src)
	# the words
	var col: Color = Gfx.FIRE[6] if el < 3 else (Gfx.FIRE[5] if (el / 5) % 2 == 0 or el > 30 else Gfx.FIRE[4])
	var ty: float = r.position.y + (5.0 if compact else 6.0) - roundf(slam * 3.0)
	UiFont.draw_big_rim(ci, title, Vector2(floorf(cx - tw / 2.0), ty), col, Gfx.OUTLINE, size, true)
	UiKit.center_small(ci, j.evo_sub, cx, r.end.y - 10.0, Gfx.BRASS[3], Gfx.OUTLINE)
	return r
