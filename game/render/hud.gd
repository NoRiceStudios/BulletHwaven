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
const ZONES_BANNER_TICKS := 100  ## CONTROL ZONES OPEN (after the PVP ON banner when both come at once)
const ZONE_PANEL_W := 74.0
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
## Boss bar damage chip: the shown fraction trails the real one (real time, 0 lag when frozen).
var _boss_lag: float = 0.0
var _boss_lag_hold: float = 0.0
const SCRAP_PULSE_S := 0.35
const GAIN_SHOW_S := 0.9

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null

## Behaviour picker (live doctrine control): a click on the dock's DRIVE / TARGET block opens a CRT strip above the
## dock to switch the base drive and target with one click (keys 1/2/3 and Q/W/E do the same without it).
## A change flashes the dock line. Screenshots set `pointer_override` and `picker_open` directly.
const DRIVE_KEY_LABELS := {"circle": "1", "kite": "2", "charge": "3", "zone": "4"}
const TARGET_KEY_LABELS := {"nearest": "Q", "strongest": "W", "players_first": "E"}
const PICKER_IDLE_S := 6.0  ## the strip closes itself after this long without the pointer on it
const FLASH_S := 0.6
var picker_open: bool = false
var pointer_override: Vector2 = Vector2(-1, -1)
var _picker_idle: float = 0.0
var _hits: Array = []  ## [Rect2, action, arg] drawn this frame (dock block and picker chips)
var _hover: Array = []  ## the hit under the pointer, from the previous frame's hits
var _doc_seen: Dictionary = {}  ## the base doctrine last drawn, to flash a change
var _flash: Dictionary = {"drive": 0.0, "target": 0.0}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(delta: float) -> void:
	_tick_juice(delta)
	_tick_picker(delta)
	_tick_boss_lag(delta, view == null or view.frozen)
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


## Spectator keys: Tab / Right next rig, Shift+Tab / Left previous, Home or A back to auto. Left clicks go to
## the behaviour picker.
func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and click_at(mb.position):
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT and mark_at(mb.position):
			get_viewport().set_input_as_handled()
		return
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
		if view != null and view.juice.surge_active(world.tick) and not _boss_intro():
			_surge_edge(vs)
		_draw_rival_tags()  # under the panels
		_draw_zone_tags(v)
		if me != null and me.alive and not spec:
			_draw_mark_reticle(me)
		_draw_top(vs)
		_draw_zone_panel(vs, v)
		_hover = _hover_hit()
		_hits.clear()
		_draw_dock(v, vs)
		var watching: bool = spec and not elim_recent
		if world.vehicles.size() > 1:
			_draw_standings(v)
		if view != null and view.rig_status != null and view.rig_status.visible_now():
			_panels.append(RigStatus.panel_rect(world, v))
		if watching:
			_draw_spectating(vs, v)
		elif me != null and not me.eliminated:
			_draw_drain_warning(me, vs)
		_draw_feed(vs)
		_draw_boss(vs, watching)
		_draw_grace(vs, watching)
		if v != null and (watching or not (me != null and me.eliminated)):
			_draw_rival_arrows(vs, v)
			_draw_zone_arrows(vs)
			if v.alive:
				_draw_combo(v)
		if view != null and view.juice.surge_active(world.tick) and not _boss_intro():
			_draw_surge(vs, watching)
		if me != null and me.eliminated and not watching:
			_draw_eliminated(vs)
		elif dead:
			_draw_respawn(me, vs)
		if _picker_usable(me):
			_draw_radio(me, vs)
		if picker_open and _picker_usable(me):
			_draw_picker(me, vs)
	var pv: int = world.tick - view.pvp_on_tick if view != null and view.pvp_on_tick >= 0 else -1
	if world.phase == SimWorld.PHASE_COMBAT and pv >= 0 and pv < PVP_BANNER_TICKS:
		_pvp_banner(vs, pv)
	var zo: int = _zones_banner_age()
	if world.phase == SimWorld.PHASE_COMBAT and zo >= 0 and zo < ZONES_BANNER_TICKS:
		_zones_banner(vs, zo)
	if view != null and world.phase == SimWorld.PHASE_COMBAT and view.juice.evo_age(world.tick) >= 0:
		_draw_evolved(vs)
	var el: int = phase_elapsed(world)
	if el >= 0 and el < BANNER_TICKS:
		if world.phase == SimWorld.PHASE_COMBAT:
			_banner(vs, "ROUND %d" % world.round, "THE HIVE STIRS" if world.round > 1 else "HOLD THE LINE", el, 64.0)
		elif world.phase == SimWorld.PHASE_WORKSHOP:
			var bv: BossView = view.boss_view() if view != null else null
			var sub: String = "MAKE CAMP - %s ON THE CLOCK" % UiKit.clock(world.workshop_duration())
			if bv != null and not bv.end_kill and bv.end_round == world.round and bv.end_tick >= 0 and bv.end_kind >= 0:
				sub = "THE %s BURROWS AWAY - %s WILL BE BACK" % [Bosses.boss_name(bv.end_kind), "SHE" if bv.end_kind == SimWorld.BOSS_A else "IT"]
			_banner(vs, "HIVE RETREATS", sub, el, 112.0)


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
	var own: bool = v.peer_id == local_peer and not v.eliminated
	if own:
		_note_doctrine(v)
		var blk := Rect2(r.position.x + 3, r.position.y + 3, 85, r.size.y - 6)
		var hov: bool = _is_hover("picker")
		if hov or picker_open:
			draw_rect(blk, Color(Gfx.CRT_TEXT, 0.16 if hov else 0.1))
			UiKit.outline_rect(self, blk, Color(Gfx.CRT_TEXT, 0.7 if hov else 0.45))
		_caret(Vector2(blk.end.x - 6, blk.position.y + 3), picker_open)
		_hits.append([blk, "picker", null])
	UiFont.draw_small(self, "DRIVE", Vector2(dx, y1 + 1), Gfx.UI_DIM)
	var drive: String = _effective(v, "drive")
	UiFont.draw(self, drive.to_upper(), Vector2(lx, y1), _doc_col(v, "drive", drive), Gfx.UI_SHADOW)
	UiFont.draw_small(self, "TARGET", Vector2(dx, y2 + 1), Gfx.UI_DIM)
	var tgt: String = _effective(v, "target")
	if Orders.active(world, v):
		UiFont.draw(self, "MARKED", Vector2(lx, y2), Gfx.FIRE[5], Gfx.UI_SHADOW)
	else:
		UiFont.draw(self, str(WorkshopUi.TARGET_LABELS.get(tgt, tgt.to_upper())), Vector2(lx, y2), _doc_col(v, "target", tgt), Gfx.UI_SHADOW)
	_rule_lamps(v, Vector2(r.position.x + 91.0, y1 + 1.0))
	var pr := Rect2(r.position.x + 89.0, y2 - 1, UiFont.width_small("P RULES") + 4.0, 9)
	var phov: bool = own and _is_hover("rules")
	UiFont.draw_small(self, "P RULES", Vector2(r.position.x + 91.0, y2 + 1), Gfx.CRT_HI if phov else Gfx.UI_DIM)
	if own:
		_hits.append([pr, "rules", null])
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
	var y: float = dock.position.y - 18.0
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
	x = _draw_mark_chip(v, Vector2(x, y)) + 10.0
	_draw_toggle_chips(Vector2(x, y))


# ---------------------------------------------------------------- radio

const RADIO_LABELS := {"fall_back": "FALL BACK", "all_in": "ALL IN", "hold": "HOLD", "boss": "BOSS FOCUS"}
const RADIO_KEYS: PackedStringArray = ["Z", "X", "C", "V"]
const RADIO_W := 138.0


## Bottom left: the radio set. Four calls (key, name) that override every rule for a few seconds, the charges
## left this round as lamps, the running call lit with a bar for its time left.
func _draw_radio(v: SimVehicle, vs: Vector2) -> void:
	var r := Rect2(4, vs.y - 4.0 - 40.0, RADIO_W, 40)
	_panels.append(r)
	UiKit.panel(self, r)
	var x0: float = r.position.x + 6.0
	var y: float = r.position.y + 4.0
	UiFont.draw_small(self, "RADIO", Vector2(x0, y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var charges: int = v.radio_charges
	for i in Orders.RADIO_CHARGES:
		var p := Vector2(x0 + 30.0 + i * 7.0, y + 1.0)
		draw_rect(Rect2(p - Vector2.ONE, Vector2(6, 6)), Gfx.OUTLINE)
		draw_rect(Rect2(p, Vector2(4, 4)), Gfx.FIRE[4] if i < charges else Gfx.UI_PLATE_DARK)
	var cur: String = Orders.radio_id(v)
	var note: String = "OVERRIDES RULES 5 S" if cur == "" else "%s %d" % [RADIO_LABELS.get(cur, ""), ceili(float(v.radio_ticks) / float(SimWorld.TICK_RATE))]
	UiFont.draw_small(self, note, Vector2(r.end.x - 6.0 - UiFont.width_small(note), y), Gfx.FIRE[5] if cur != "" else Gfx.UI_DIM, Gfx.UI_SHADOW)
	var bw: float = floorf((r.size.x - 12.0 - 3.0) / 2.0)
	for i in Orders.RADIO_IDS.size():
		var id: String = Orders.RADIO_IDS[i]
		var br := Rect2(x0 + (i % 2) * (bw + 3.0), y + 10.0 + (i / 2) * 12.0, bw, 10)
		var on: bool = cur == id
		var can: bool = charges > 0 and v.alive and v.radio_lock <= 0
		var hov: bool = can and _is_hover("radio", id)
		draw_rect(br, Gfx.FIRE[4] if on else (Color(Gfx.FIRE[4], 0.22) if hov else Gfx.UI_PLATE_DARK))
		UiKit.outline_rect(self, br, Gfx.FIRE[5] if on or hov else (Gfx.UI_DIM if can else Color(Gfx.UI_DIM, 0.4)))
		var tc: Color = Gfx.OUTLINE if on else (Gfx.UI_TEXT if can else Gfx.UI_DIM)
		var kx: float = UiFont.draw_small(self, RADIO_KEYS[i], br.position + Vector2(3, 2), Gfx.OUTLINE if on else Gfx.FIRE[4])
		UiFont.draw_small(self, RADIO_LABELS[id], Vector2(kx + 3.0, br.position.y + 2), tc)
		if on:
			var f: float = float(v.radio_ticks) / float(Orders.RADIO_TICKS)
			draw_rect(Rect2(br.position.x + 1, br.end.y - 2, floorf((br.size.x - 2) * f), 1), Gfx.OUTLINE)
		_hits.append([br, "radio", id])


## The target mark order: "RMB MARK" when ready, the seconds left while it runs, the cooldown after.
func _draw_mark_chip(v: SimVehicle, p: Vector2) -> float:
	var label: String
	var col: Color
	if Orders.active(world, v):
		label = "MARKED %d" % ceili(float(v.mark_order_ticks) / float(SimWorld.TICK_RATE))
		col = Gfx.FIRE[5] if (world.tick / 4) % 2 == 0 else Gfx.FIRE[4]
	elif v.mark_order_cd > 0:
		label = "RMB MARK %d" % ceili(float(v.mark_order_cd) / float(SimWorld.TICK_RATE))
		col = Gfx.UI_DIM
	else:
		label = "RMB MARK"
		col = Gfx.FIRE[5]
	return UiFont.draw_small(self, label, p, col, Gfx.UI_SHADOW)


## The view toggles next to the mark chip, lit while on: R range rings, T target marks.
func _draw_toggle_chips(p: Vector2) -> void:
	if view == null or view.ranges == null or view.targets == null:
		return
	var x: float = p.x
	for t: Array in [["R RANGE", view.ranges.shown], ["T TARGETS", view.targets.shown]]:
		x = UiFont.draw_small(self, str(t[0]), Vector2(x, p.y), Gfx.FIRE[5] if bool(t[1]) else Gfx.UI_DIM, Gfx.UI_SHADOW) + 10.0


## Reticle over the local rig's marked target: four warm corner brackets that snap in on the cast and a bar
## for the time left. Screen space, so it stays crisp.
func _draw_mark_reticle(v: SimVehicle) -> void:
	if view == null or not Orders.active(world, v):
		return
	var c: Vector2 = view.to_screen(Orders.target_pos(world, v))
	var age: int = Orders.MARK_TICKS - v.mark_order_ticks
	var snap: float = clampf(1.0 - float(age) / 8.0, 0.0, 1.0)
	var r: float = floorf(10.0 + 14.0 * snap * snap)
	var col: Color = Gfx.FIRE[5] if snap > 0.0 or (world.tick / 6) % 2 == 0 else UiKit.bar_color(v.color_index)
	var arms: Array[Rect2] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var k := c + Vector2(sx * r, sy * r)
			arms.append(Rect2(k.x - (4.0 if sx > 0.0 else 0.0), k.y, 5, 1))
			arms.append(Rect2(k.x, k.y - (4.0 if sy > 0.0 else 0.0), 1, 5))
	for a in arms:
		draw_rect(a.grow(1), Gfx.OUTLINE)
	for a in arms:
		draw_rect(a, col)
	var f: float = float(v.mark_order_ticks) / float(Orders.MARK_TICKS)
	draw_rect(Rect2(c.x - r - 1, c.y + r + 3, 2.0 * r + 2, 3), Gfx.OUTLINE)
	draw_rect(Rect2(c.x - r, c.y + r + 4, floorf(2.0 * r * f), 1), Gfx.FIRE[4])


# ---------------------------------------------------------------- behaviour picker

func _tick_picker(delta: float) -> void:
	for k: String in _flash:
		_flash[k] = maxf(0.0, float(_flash[k]) - delta / FLASH_S)
	if not picker_open:
		return
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer) if world != null else null
	if not _picker_usable(me):
		picker_open = false
		return
	if pointer_override.x >= 0.0:
		return  # screenshots: keep it open
	_picker_idle = 0.0 if not _hover.is_empty() else _picker_idle + delta
	if _picker_idle > PICKER_IDLE_S:
		picker_open = false


## The local rig can be steered from the dock: combat, still in the match, not watching someone else, rule editor shut.
func _picker_usable(me: SimVehicle) -> bool:
	return world != null and me != null and not me.eliminated and world.phase == SimWorld.PHASE_COMBAT \
		and view != null and not view.spectating() and not (view.rules != null and view.rules.is_open)


func _pointer() -> Vector2:
	return pointer_override if pointer_override.x >= 0.0 else get_local_mouse_position()


func _hover_hit() -> Array:
	var p: Vector2 = _pointer()
	for i in range(_hits.size() - 1, -1, -1):
		if (_hits[i][0] as Rect2).has_point(p):
			return _hits[i]
	return []


func _is_hover(action: String, arg: Variant = null) -> bool:
	return not _hover.is_empty() and _hover[1] == action and (arg == null or _hover[2] == arg)


## Clicks at `p` (viewport px); true if it hit the dock block or the picker. Also used by screenshot scenarios.
func click_at(p: Vector2) -> bool:
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer) if world != null else null
	if not _picker_usable(me):
		return false
	for i in range(_hits.size() - 1, -1, -1):
		var h: Array = _hits[i]
		if not (h[0] as Rect2).has_point(p):
			continue
		_picker_idle = 0.0
		match str(h[1]):
			"picker":
				picker_open = not picker_open
			"rules":
				picker_open = false
				view.rules.open()
			"drive":
				_send({"type": "set_drive", "value": h[2]})
			"target":
				_send({"type": "set_target", "value": h[2]})
			"radio":
				radio(str(h[2]))
		return true
	if picker_open:
		picker_open = false  # a click anywhere else closes it
	return false


## Calls radio command `id` (Orders.RADIO_IDS) for the local rig; the sim refuses it without charges.
func radio(id: String) -> void:
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer) if world != null else null
	if _picker_usable(me) and me.alive:
		_send({"type": "radio", "value": id})


## Right click: orders the target mark on whatever is under `p` (the sim picks the alien or rival there; a miss
## costs nothing). Screenshot scenarios call it too.
func mark_at(p: Vector2) -> bool:
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer) if world != null else null
	if not _picker_usable(me) or not me.alive:
		return false
	var wp: Vector2 = view.world_at(p)
	_send({"type": "mark", "x": wp.x, "y": wp.y})
	return true


func _send(cmd: Dictionary) -> void:
	if view != null and view.workshop != null and view.workshop.send_command.is_valid():
		view.workshop.send_command.call(cmd)


## Flashes the dock line when the base doctrine changes (by key, picker or rule editor).
func _note_doctrine(v: SimVehicle) -> void:
	for k in ["drive", "target"]:
		var cur: String = str(v.doctrine[k])
		if _doc_seen.has(k) and _doc_seen[k] != cur and int(_doc_seen.get("id", -1)) == v.id:
			_flash[k] = 1.0
		_doc_seen[k] = cur
	_doc_seen["id"] = v.id


## Dock colour of the drive / target line: bright while a rule overrides the base, white while flashing.
func _doc_col(v: SimVehicle, group: String, eff: String) -> Color:
	var base: Color = Gfx.CRT_HI if eff != str(v.doctrine[group]) else Gfx.CRT_TEXT
	return base.lerp(Gfx.UI_TEXT, float(_flash.get(group, 0.0)))


## Small up / down caret (open state of the picker).
func _caret(p: Vector2, up: bool) -> void:
	var c: Color = Gfx.CRT_TEXT
	for i in 3:
		var w: float = 5.0 - 2.0 * i
		var y: float = p.y + (2 - i if up else i)
		draw_rect(Rect2(p.x + i, y, w, 1), c)


## The strip above the dock: base drive and base target as chips with their keys, the rule that overrides
## each right now, and the way into the full rule editor.
func _draw_picker(v: SimVehicle, vs: Vector2) -> void:
	var dock: Rect2 = _dock_rect(vs)
	var rows: Array = [["DRIVE", "drive", Doctrine.BASE_DRIVES, DRIVE_KEY_LABELS], ["TARGET", "target", Doctrine.RIG_TARGETS, TARGET_KEY_LABELS]]
	var label_w: float = 34.0
	var widths: Array[float] = []
	for row: Array in rows:
		var w: float = label_w
		for id: String in row[2]:
			w += _pick_chip_w(id, row) + 3.0
		widths.append(w)
	var inner_w: float = maxf(widths.max(), 220.0)
	var r := Rect2(floorf(vs.x / 2.0 - (inner_w + 12.0) / 2.0), 0, inner_w + 12.0, 52)
	r.position.y = dock.position.y - 22.0 - r.size.y
	if view != null and view.minimap != null and view.minimap.visible_now():  # wide (many targets): clear the minimap
		var mm: Rect2 = Minimap.frame_rect(vs)
		if r.end.x > mm.position.x:
			r.position.y = minf(r.position.y, mm.position.y - 4.0 - r.size.y)
	_panels.append(r)
	draw_rect(r.grow(1), Gfx.OUTLINE)
	draw_rect(r, Color(Gfx.CRT_BG, 0.94))
	UiKit.outline_rect(self, r.grow(-1), Gfx.CRT_DIM)
	var x0: float = r.position.x + 6.0
	var y: float = r.position.y + 5.0
	UiFont.draw(self, "BEHAVIOUR", Vector2(x0, y), Gfx.CRT_HI)
	var hint := "CHANGES THE BASE SETTING - RULES STILL WIN WHEN THEY MATCH"
	UiFont.draw_small(self, hint, Vector2(r.end.x - 6.0 - UiFont.width_small(hint), y + 1), Gfx.CRT_DIM)
	y += 13.0
	for row: Array in rows:
		var grp: String = row[1]
		UiFont.draw_small(self, row[0], Vector2(x0, y + 1), Gfx.CRT_DIM)
		var x: float = x0 + label_w
		var base: String = str(v.doctrine[grp])
		var eff: String = _effective(v, grp)
		for id: String in row[2]:
			x = _pick_chip(id, row, Vector2(x, y), base == id, eff == id and eff != base) + 3.0
		y += 13.0
	var ov: String = _override_text(v)
	var foot: String = ov if ov != "" else "NO RULE OVERRIDES RIGHT NOW"
	var rmb := "RIGHT-CLICK AN ALIEN: ALL GUNS ON IT"
	UiFont.draw_small(self, rmb, Vector2(r.end.x - 6.0 - UiFont.width_small(rmb), r.end.y - 9.0), Gfx.CRT_DIM)
	UiFont.draw_small(self, foot, Vector2(x0, r.end.y - 9.0), Gfx.CRT_HI if ov != "" else Gfx.CRT_DIM)


func _pick_label(id: String, row: Array) -> String:
	var name: String = str(DoctrineEditor.ACTION_LABELS.get("%s:%s" % [row[1], id], id.to_upper())).trim_prefix("TGT ")
	var key: String = str((row[3] as Dictionary).get(id, ""))
	return name if key == "" else "%s %s" % [key, name]


func _pick_chip_w(id: String, row: Array) -> float:
	return UiFont.width(_pick_label(id, row)) + 6.0


func _pick_chip(id: String, row: Array, pos: Vector2, on: bool, ruled: bool) -> float:
	var text: String = _pick_label(id, row)
	var r := Rect2(pos - Vector2(2, 2), Vector2(_pick_chip_w(id, row), 10))
	var hov: bool = _is_hover(row[1], id)
	if on:
		draw_rect(r, Gfx.CRT_TEXT)
	elif hov:
		draw_rect(r, Color(Gfx.CRT_TEXT, 0.22))
	UiKit.outline_rect(self, r, Gfx.CRT_HI if ruled else (Gfx.CRT_TEXT if on or hov else Gfx.CRT_DIM))
	var tc: Color = Gfx.CRT_BG if on else (Gfx.CRT_HI if hov or ruled else Gfx.CRT_TEXT)
	UiFont.draw(self, text, pos + Vector2(1, 0), tc)
	_hits.append([r, row[1], id])
	return r.end.x


## "RULE 2 OVERRIDES: KITE" for the lit rig rules that set drive or target (empty when none does).
func _override_text(v: SimVehicle) -> String:
	var parts: PackedStringArray = []
	var seen: Dictionary = {}
	for i in mini(v.rules.size(), Doctrine.slots(v)):
		if (v.rule_live >> i) & 1 == 0:
			continue
		var a: String = str(v.rules[i]["do"])
		var g: String = Doctrine.action_group(a)
		if (g == "drive" or g == "target") and not seen.has(g):
			seen[g] = true
			parts.append("RULE %d: %s" % [i + 1, str(DoctrineEditor.ACTION_LABELS.get(a, a.to_upper()))])
	return ("NOW OVERRIDDEN BY " + "  ".join(parts)) if not parts.is_empty() else ""


## What the rig does right now in action group `group` ("drive" / "target"): the first lit rule of
## that group, else the base doctrine. Built from the synced rules and lamps, so clients agree.
static func _effective(v: SimVehicle, group: String) -> String:
	var radio: String = Orders.radio_id(v)  # a radio call beats every rule (Orders)
	if radio != "":
		if group == "drive":
			match radio:
				"fall_back":
					return "flee" if Doctrine.action_unlocked(v, "drive:flee") else "hold"
				"all_in":
					return "charge"
				"hold":
					return "hold"
		elif radio == "boss":
			return "boss"
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

## Player kills under the hive plate, newest on top: KILLER > VICTIM WEAPON (rams in fire colour), and zone
## captures: NAME TOOK [B] (FROM NAME). Lines with the watched / local rig get a hazard edge. Alien kills are
## never listed.
func _draw_feed(vs: Vector2) -> void:
	if view == null:
		return
	var me: SimVehicle = view.focus_vehicle()
	var lines: Array[Dictionary] = []
	for log: Array[Dictionary] in [view.kill_log, view.zone_log]:
		for i in range(log.size() - 1, -1, -1):
			var e: Dictionary = log[i]
			var age: int = world.tick - int(e["tick"])
			if age >= FEED_TICKS or int(e["round"]) != world.round:
				break
			if age >= 0 and (not e.has("type") or str(e["type"]) == "captured"):
				lines.append(e)
	lines.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tick"]) > int(b["tick"]))
	var y: float = 6.0
	var shown: int = 0
	for e: Dictionary in lines:
		var age: int = world.tick - int(e["tick"])
		var zone: bool = e.has("type")
		var kv: SimVehicle = UiKit.vehicle_by_id(world, int(e["owner"] if zone else e["killer"]))
		var vv: SimVehicle = UiKit.vehicle_by_id(world, int(e["prev"] if zone else e["victim"]))
		if kv == null or (vv == null and not zone):
			continue
		if age > FEED_TICKS - 15 and (age / 3) % 2 == 0:
			y += 13.0
			shown += 1
			continue
		var kn: String = UiKit.player_name(kv)
		var vn: String = UiKit.player_name(vv) if vv != null else ""
		var w: float
		var wt: String = ""
		var weapon: int = -1
		if zone:
			w = UiFont.width(kn) + 4.0 + UiFont.width("TOOK") + 4.0 + 11.0 + 6.0
			if vv != null:
				w += UiFont.width("FROM") + 4.0 + UiFont.width(vn) + 6.0
		else:
			weapon = int(e["weapon"])
			wt = "RAMMED" if weapon == SimWorld.WEAPON_RAM else UiKit.weapon_short(weapon)
			w = UiFont.width(kn) + 5.0 + 6.0 + 5.0 + UiFont.width(vn) + 6.0 + UiFont.width(wt) + 12.0
		var r := Rect2(vs.x - 6.0 - w, y, w, 12)
		var mine: bool = me != null and (kv == me or vv == me)
		draw_rect(r, Gfx.OUTLINE)
		draw_rect(r.grow(-1.0), FEED_BG if not mine else Color(0.22, 0.13, 0.08, 0.9))
		draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(2, r.size.y - 2)), UiKit.bar_color(kv.color_index))
		if mine:
			UiKit.outline_rect(self, r, Gfx.HAZARD)
		var x: float = r.position.x + 6.0
		x = UiKit.paint_text(self, kn, Vector2(x, y + 3), kv.color_index) + 4.0
		if zone:
			x = UiFont.draw(self, "TOOK", Vector2(x, y + 3), Gfx.UI_DIM, Gfx.UI_SHADOW) + 4.0
			var zi: int = int(e["zone"])
			if zi >= 0 and zi < world.zones.size():
				_zone_badge(Rect2(x, y + 1, 11, 10), zi)
			else:
				UiFont.draw(self, ZoneView.letter(zi), Vector2(x + 3, y + 3), Gfx.UI_TEXT, Gfx.UI_SHADOW)
			x += 15.0
			if vv != null:
				x = UiFont.draw(self, "FROM", Vector2(x, y + 3), Gfx.UI_DIM, Gfx.UI_SHADOW) + 4.0
				UiKit.paint_text(self, vn, Vector2(x, y + 3), vv.color_index)
		else:
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


# ---------------------------------------------------------------- boss rounds (BossView keeps the moment ticks)

const BOSS_BAR_W := 300.0
const BOSS_BAR_H := 30.0
const BOSS_INTRO_HOLD := 30  ## the APPROACHES plate stays this long after the spawn ("EMERGES")
const BOSS_PLATE_TICKS := 70  ## phase / split plates
const BOSS_KILL_TICKS := 165  ## the DOWN banner
const BOSS_PLATE_Y := 82.0
const BOSS_PHASE_SUB := {3: ["", "BROOD SACS OPEN", "TRIPLE VOLLEYS"], 4: ["", "IT CHARGES - WATCH THE LANES", "IT SHATTERS"]}


## Height the boss bar takes under the top plate (other top banners move down by it).
func _boss_offset() -> float:
	if world.boss_state == Bosses.ST_ACTIVE or world.boss_state == Bosses.ST_WARNED:
		return BOSS_BAR_H + 4.0
	return 0.0


## The wide boss bar under the clock plate and the boss moments' plates. Driven by world.boss_* and the
## BossView moment ticks only, so host, clients and screenshots agree.
func _draw_boss(vs: Vector2, watching: bool) -> void:
	if world.phase != SimWorld.PHASE_COMBAT or view == null:
		return
	var bv: BossView = view.boss_view()
	var cx: float = floorf(vs.x / 2.0)
	if world.boss_state == Bosses.ST_WARNED:
		_boss_edge(vs)
		_boss_pointer(vs, world.boss_spawn_pos, true)
	elif world.boss_state == Bosses.ST_ACTIVE:
		_boss_pointer(vs, _boss_main_pos(), false)
	if _boss_offset() > 0.0:
		_boss_bar(Rect2(cx - BOSS_BAR_W / 2.0, 37.0 + (29.0 if watching else 0.0), BOSS_BAR_W, BOSS_BAR_H))
	# centre plates: approach (until just after the spawn), phase / split, kill
	var since_spawn: int = world.tick - bv.spawn_tick
	var split_now: bool = bv.split_tick >= bv.spawn_tick and world.tick >= bv.split_tick  # a split outranks the intro
	if world.boss_state == Bosses.ST_WARNED or (world.boss_state == Bosses.ST_ACTIVE and since_spawn >= 0 and since_spawn < BOSS_INTRO_HOLD and not split_now):
		_boss_approach(vs, since_spawn if world.boss_state == Bosses.ST_ACTIVE else -1)
		return
	var ek: int = world.tick - bv.end_tick
	if bv.end_kill and ek >= 0 and ek < BOSS_KILL_TICKS and bv.end_round == world.round:
		_boss_down(vs, ek, bv)
		return
	var ps: int = world.tick - bv.phase_tick
	var sp: int = world.tick - bv.split_tick
	if world.boss_state == Bosses.ST_ACTIVE and sp >= 0 and sp < BOSS_PLATE_TICKS:
		_boss_plate(vs, "SHATTERED", "%d SHARDS - BREAK THEM ALL" % Bosses.SPLIT_COUNT, sp, false)
	elif world.boss_state == Bosses.ST_ACTIVE and ps >= 0 and ps < BOSS_PLATE_TICKS and bv.phase_n >= 2:
		var subs: Array = BOSS_PHASE_SUB.get(world.boss_kind, ["", "", ""])
		_boss_plate(vs, "PHASE %d" % bv.phase_n, str(subs[clampi(bv.phase_n - 1, 0, 2)]), ps, false)


## True while the boss is announced or just surfacing: its plate replaces the SWARM INCOMING plate (the boss
## comes with the first surge, so the two would say the same thing on top of each other).
func _boss_intro() -> bool:
	if world.boss_state == Bosses.ST_WARNED:
		return true
	return view != null and world.boss_state == Bosses.ST_ACTIVE and world.tick - view.boss_view().spawn_tick < BOSS_INTRO_HOLD


## Position of the main boss body (the first shard after a split), Vector2.INF when none.
func _boss_main_pos() -> Vector2:
	var best := Vector2.INF
	for i in world.enemy_count:
		if world.enemy_kind[i] >= SimWorld.BOSS_A and world.enemy_hp[i] > 0.0:
			if world.enemy_kind[i] != SimWorld.BOSS_SHARD:
				return world.enemy_pos[i]
			if best == Vector2.INF:
				best = world.enemy_pos[i]
	return best


## Boss bar: the name in the stencil face, phase pips and the ENRAGED tag; a segmented cyan hp bar with
## notches at the phase thresholds and a pale chip that trails the damage. While warned the bar charges up
## ("EMERGES IN 3"); after the Colossus splits it shows one segment per shard ("SHARDS 2/3").
func _boss_bar(r: Rect2) -> void:
	_panels.append(r)
	UiKit.panel(self, r)
	draw_rect(Rect2(r.position.x + 2, r.end.y - 3, r.size.x - 4, 1), Color(Gfx.GLOW[1], 0.8))
	var name_s: String = Bosses.boss_name(world.boss_kind)
	var x0: float = r.position.x + 7.0
	var xr: float = r.end.x - 7.0
	var hot: bool = (world.tick / 8) % 2 == 0
	var nx: float = UiFont.draw_title(self, name_s, Vector2(x0, r.position.y + 5), Gfx.BONE_LIGHT, 11, Gfx.OUTLINE)
	if world.boss_enraged:
		var tr := Rect2(nx + 6.0, r.position.y + 4, UiFont.width_small("ENRAGED") + 8.0, 9)
		draw_rect(tr, Gfx.OUTLINE)
		draw_rect(tr.grow(-1.0), Gfx.UI_BAD if hot else Color("#8a2a1c"))
		UiFont.draw_small(self, "ENRAGED", tr.position + Vector2(4, 2), Gfx.BONE_LIGHT)
	var bar := Rect2(x0, r.position.y + 17.0, r.size.x - 14.0, 8.0)
	var shards: Array[float] = _shard_fracs()
	if world.boss_state == Bosses.ST_WARNED:
		var secs: int = ceili(float(world.boss_warn_left) / float(SimWorld.TICK_RATE))
		var t := "EMERGES IN %d" % secs
		UiFont.draw(self, t, Vector2(xr - UiFont.width(t), r.position.y + 6), Gfx.UI_BAD if hot else Gfx.FIRE[4], Gfx.UI_SHADOW)
		var fill: float = 1.0 - float(world.boss_warn_left) / float(Bosses.WARN_TICKS)
		_boss_hp(bar, [fill], fill, true)
		return
	if not shards.is_empty():
		var alive: int = 0
		for f in shards:
			alive += 1 if f > 0.0 else 0
		var st := "SHARDS %d/%d" % [alive, Bosses.SPLIT_COUNT]
		UiFont.draw(self, st, Vector2(xr - UiFont.width(st), r.position.y + 6), Gfx.GLOW[4], Gfx.UI_SHADOW)
		var tot: float = 0.0
		for f in shards:
			tot += f
		_boss_hp(bar, shards, tot / float(shards.size()), false)
		return
	var left_s: int = ceili(float(world.phase_ticks_left) / float(SimWorld.TICK_RATE))
	if left_s <= 6:  # the round is about to end: it will slink off
		var rt := "RETREATS IN %d" % left_s
		UiFont.draw(self, rt, Vector2(xr - UiFont.width(rt), r.position.y + 6), Gfx.UI_DIM if hot else Gfx.UI_TEXT, Gfx.UI_SHADOW)
	else:  # phase pips: the current one lit
		var px: float = xr - 3.0 * 9.0 + 2.0
		UiFont.draw_small(self, "PHASE", Vector2(px - UiFont.width_small("PHASE") - 4.0, r.position.y + 6), Gfx.UI_DIM)
		for k in 3:
			var on: bool = k < world.boss_phase
			var pr := Rect2(px + float(k) * 9.0, r.position.y + 5, 7, 7)
			draw_rect(pr, Gfx.OUTLINE)
			draw_rect(pr.grow(-1.0), (Gfx.GLOW[4] if k == world.boss_phase - 1 else Gfx.GLOW[2]) if on else Gfx.UI_PLATE_DARK)
	_boss_hp(bar, [world.boss_hp_frac], world.boss_hp_frac, false)
	for tfrac: float in [Bosses.PHASE2_FRAC, Bosses.PHASE3_FRAC]:  # phase notches, dim once passed
		var nx2: float = bar.position.x + 1.0 + floorf((bar.size.x - 2.0) * tfrac)
		var passed: bool = world.boss_hp_frac <= tfrac
		draw_rect(Rect2(nx2, bar.position.y - 2.0, 1, bar.size.y + 4.0), Gfx.OUTLINE)
		draw_rect(Rect2(nx2 - 1.0, bar.position.y - 3.0, 3, 2), Gfx.UI_DIM if passed else Gfx.BONE_LIGHT)


## Hp fill of the boss bar: `segs` equal segments (one per body after a split) each 0..1 full; `total` is
## what the trailing chip follows. `charging`: the intro fill (running stripes).
func _boss_hp(bar: Rect2, segs: Array, total: float, charging: bool) -> void:
	draw_rect(bar, Gfx.OUTLINE)
	var inner: Rect2 = bar.grow(-1.0)
	draw_rect(inner, Color("#10191a"))
	var n: int = segs.size()
	var sw: float = floorf((inner.size.x - float(n - 1)) / float(n))
	for k in n:
		var f: float = clampf(float(segs[k]), 0.0, 1.0)
		var sx: float = inner.position.x + float(k) * (sw + 1.0)
		var w: float = (inner.end.x - sx) if k == n - 1 else sw
		if k < n - 1:
			draw_rect(Rect2(sx + w, inner.position.y, 1, inner.size.y), Gfx.OUTLINE)
		var fw: float = floorf(w * f)
		if fw <= 0.0:
			continue
		var col: Color = Gfx.GLOW[2] if charging else (Gfx.GLOW[3] if world.boss_phase < 3 else Gfx.GLOW[4])
		draw_rect(Rect2(sx, inner.position.y, fw, inner.size.y), col)
		draw_rect(Rect2(sx, inner.position.y, fw, 1), Gfx.GLOW[3] if charging else Gfx.GLOW[5])
		draw_rect(Rect2(sx, inner.end.y - 1, fw, 1), Gfx.GLOW[1])
		if charging:  # running stripes while it charges in
			var x: float = sx - 6.0 + float((world.tick / 2) % 6)
			while x < sx + fw - 1.0:
				if x >= sx:
					draw_rect(Rect2(x, inner.position.y + 1, 2, inner.size.y - 2), Gfx.GLOW[3])
				x += 6.0
	# damage chip: a pale stretch that trails the real hp for a moment (real time; not in screenshots)
	if not charging and n == 1 and _boss_lag > total:
		var lx: float = inner.position.x + floorf(inner.size.x * total)
		var lw: float = floorf(inner.size.x * (_boss_lag - total))
		if lw > 0.0:
			draw_rect(Rect2(lx, inner.position.y, lw, inner.size.y), Color(Gfx.BONE_LIGHT, 0.75))


## Trailing damage chip of the boss bar (real time; follows instantly when frozen or rising).
func _tick_boss_lag(delta: float, frozen: bool) -> void:
	if world == null:
		return
	var f: float = world.boss_hp_frac
	if frozen or f >= _boss_lag or world.boss_state != Bosses.ST_ACTIVE:
		_boss_lag = f
		_boss_lag_hold = 0.0
		return
	_boss_lag_hold += delta
	if _boss_lag_hold > 0.35:
		_boss_lag = maxf(f, _boss_lag - delta * 0.25)


## After the Colossus split: each shard's hp fraction (0 = broken), in a stable order; empty before.
func _shard_fracs() -> Array[float]:
	var out: Array[float] = []
	if world.boss_kind != SimWorld.BOSS_B or world.boss_state != Bosses.ST_ACTIVE:
		return out
	var ids: Array = []
	var hp: Dictionary = {}
	for i in world.enemy_count:
		var k: int = world.enemy_kind[i]
		if k == SimWorld.BOSS_B and world.enemy_hp[i] > 0.0:
			return out  # the body is still whole
		if k == SimWorld.BOSS_SHARD and world.enemy_hp[i] > 0.0:
			ids.append(world.enemy_id[i])
			hp[world.enemy_id[i]] = world.enemy_hp[i] / maxf(world.enemy_max_hp_of(i), 1.0)
	if ids.is_empty():
		return out
	ids.sort()
	for id in ids:
		out.append(clampf(float(hp[id]), 0.0, 1.0))
	while out.size() < Bosses.SPLIT_COUNT:
		out.append(0.0)
	return out


## The big stencil plate before the spawn: "TRIPOD QUEEN" / "APPROACHES" (ENRAGED variant in hot red) with a
## WARNING tape over it; it slams in, and flips to "EMERGES" as the boss breaks the surface.
func _boss_approach(vs: Vector2, since_spawn: int) -> void:
	var el: int = world.tick - view.boss_view().warn_tick
	if since_spawn > BOSS_INTRO_HOLD - 8 and (since_spawn / 2) % 2 == 0:
		return
	var name_s: String = Bosses.boss_name(world.boss_kind)
	var sub: String = "EMERGES" if since_spawn >= 0 else "APPROACHES"
	var enraged: bool = world.boss_enraged
	_boss_plate_raw(vs, name_s, sub, el, "ENRAGED" if enraged else "WARNING", true, enraged or since_spawn >= 0)


func _boss_plate(vs: Vector2, title: String, sub: String, el: int, hot: bool) -> void:
	if el > BOSS_PLATE_TICKS - 10 and (el / 2) % 2 == 0:
		return
	_boss_plate_raw(vs, title, sub, el, "", false, hot)


## A dark plate with a hazard (warning) or cyan (hive) frame, the title slamming in in the stencil face, an
## optional tape label over it and a line under it.
func _boss_plate_raw(vs: Vector2, title: String, sub: String, el: int, tape: String, hazard: bool, hot: bool) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var slam: float = clampf(1.0 - float(el) / 5.0, 0.0, 1.0)
	var base: int = 20
	var size: int = base + int(round(slam * 10.0))
	var tw: float = float(UiFont.width_big_px(title, base, true))
	var w: float = maxf(tw, float(UiFont.width_big_px(sub, 11, true))) + 70.0
	var h: float = 42.0
	var r := Rect2(cx - floorf(w / 2.0), BOSS_PLATE_Y + _boss_offset() - 34.0, w, h)
	draw_rect(r.grow(1.0), Gfx.OUTLINE)
	draw_rect(r, Color("#1b1414"))
	if hazard:
		UiKit.hazard_frame(self, r, 3.0)
	else:
		UiKit.outline_rect(self, r.grow(-1.0), Gfx.GLOW[3] if (el / 3) % 2 == 0 else Gfx.GLOW[2])
		UiKit.outline_rect(self, r.grow(-3.0), Color(Gfx.GLOW[1], 0.8))
	draw_rect(Rect2(r.position.x + 4, r.position.y + 4, r.size.x - 8, 1), Color(1.0, 0.85, 0.6, 0.06))
	var col: Color
	if el < 3:
		col = Gfx.FIRE[6] if hazard else Gfx.GLOW[5]
	elif hazard:
		col = (Gfx.UI_BAD if (el / 4) % 2 == 0 else Gfx.FIRE[4]) if hot else Gfx.FIRE[4]
	else:
		col = Gfx.GLOW[4]
	var stw: float = float(UiFont.width_big_px(title, size, true))
	UiFont.draw_big_rim(self, title, Vector2(floorf(cx - stw / 2.0), r.position.y + 7.0 - roundf(slam * 4.0)), col, Gfx.OUTLINE, size, true)
	var sub_col: Color = Gfx.BONE_LIGHT if hazard else Gfx.UI_TEXT
	var sw: float = float(UiFont.width_big_px(sub, 11, true))
	UiFont.draw_big_rim(self, sub, Vector2(floorf(cx - sw / 2.0), r.end.y - 13.0), sub_col, Gfx.OUTLINE, 11, true)
	if tape != "":
		var tr: Rect2 = UiKit.tape_label(self, tape, cx, r.position.y - 6.0, Color("#f08a6a") if tape == "ENRAGED" else Color("#e8dcc4"))
		_panels.append(tr)
	if hazard:  # alien pips on the flanks, beating with the footsteps
		var beat: bool = world.boss_state == Bosses.ST_WARNED and world.boss_warn_left % 18 < 5
		for sx: float in [r.position.x + 10.0, r.end.x - 17.0]:
			draw_rect(Rect2(sx - 1, r.get_center().y - 4, 9, 9), Gfx.OUTLINE)
			draw_rect(Rect2(sx, r.get_center().y - 3, 7, 7), Gfx.GLOW[5] if beat else Gfx.GLOW[2])
	_panels.append(r)


## The boss is down: a warm brass plate (the players' moment) with the name, the bounty and who struck last.
func _boss_down(vs: Vector2, el: int, bv: BossView) -> void:
	if el > BOSS_KILL_TICKS - 12 and (el / 2) % 2 == 0:
		return
	var cx: float = floorf(vs.x / 2.0)
	var title: String = Bosses.boss_name(bv.end_kind) + " DOWN"
	var slam: float = clampf(1.0 - float(el) / 6.0, 0.0, 1.0)
	var base: int = 22
	var size: int = base + int(round(slam * 12.0))
	var tw: float = float(UiFont.width_big_px(title, base, true))
	var w: float = tw + 90.0
	var h: float = 50.0
	var r := Rect2(cx - floorf(w / 2.0), BOSS_PLATE_Y - 34.0, w, h)
	draw_rect(r.grow(1.0), Gfx.OUTLINE)
	draw_rect(r, Gfx.BRASS[2])
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), Gfx.BRASS[3])
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Gfx.BRASS[0])
	var inner: Rect2 = r.grow(-3.0)
	draw_rect(inner.grow(1.0), Gfx.BRASS[0])
	draw_rect(inner, Color("#221c1d"))
	if el < 14:  # a glint sweeps across
		var gx: float = floorf(inner.position.x + (inner.size.x + 20.0) * float(el) / 13.0 - 10.0)
		for row in int(inner.size.y):
			var x: float = gx - float(row) * 0.5
			if x > inner.position.x and x + 3.0 < inner.end.x:
				draw_rect(Rect2(x, inner.position.y + float(row), 3, 1), Color(Gfx.FIRE[6], 0.22))
	var col: Color = Gfx.FIRE[6] if el < 3 else (Gfx.FIRE[5] if (el / 5) % 2 == 0 or el > 30 else Gfx.FIRE[4])
	var stw: float = float(UiFont.width_big_px(title, size, true))
	UiFont.draw_big_rim(self, title, Vector2(floorf(cx - stw / 2.0), r.position.y + 7.0 - roundf(slam * 4.0)), col, Gfx.OUTLINE, size, true)
	var killer: SimVehicle = UiKit.vehicle_by_id(world, bv.end_killer)
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	var bounty: int = Bosses.BOUNTY_BASE + Bosses.BOUNTY_PER_ROUND * world.round
	var mine: int = 0
	if me != null and int(me.round_stats.get("round", -1)) == world.round:
		mine = int(me.round_stats.get("boss_bounty", 0))
	var line: String = ("BOUNTY +%d SCRAP" % mine) if mine > 0 else ("BOUNTY %d SCRAP - x2 FOR THE KILL" % bounty)
	var y2: float = r.position.y + 34.0
	if killer != null:
		var kt: String = "KILLING BLOW "
		var kn: String = UiKit.player_name(killer)
		var kw: float = UiFont.width(kt) + UiFont.width(kn) + 14.0 + UiFont.width(line)
		var x: float = floorf(cx - kw / 2.0)
		x = UiFont.draw(self, kt, Vector2(x, y2), Gfx.UI_DIM, Gfx.OUTLINE)
		x = UiKit.paint_text(self, kn, Vector2(x, y2), killer.color_index) + 14.0
		UiFont.draw(self, line, Vector2(x, y2), Gfx.FIRE[5], Gfx.OUTLINE)
	else:
		UiKit.center_text(self, line, cx, y2, Gfx.FIRE[5], Gfx.OUTLINE)
	var s := Vector2(Gfx.TEX_SKULL.get_size())
	for sx: float in [r.position.x - s.x - 6.0, r.end.x + 6.0]:
		draw_texture(Gfx.TEX_SKULL, Vector2(floorf(sx), floorf(r.get_center().y - s.y / 2.0)))
	_panels.append(r)


## While the boss is announced: the hive's cyan pulses on the screen edges, strongest on the side it will come
## from, beating with the footsteps under the sand.
func _boss_edge(vs: Vector2) -> void:
	var sp: Vector2 = view.get_viewport().get_canvas_transform() * world.boss_spawn_pos
	var dir: Vector2 = (sp - vs / 2.0).normalized()
	var p: float = 1.0 - float(world.boss_warn_left) / float(Bosses.WARN_TICKS)
	var beat: float = 1.0 - float(world.boss_warn_left % 18) / 18.0
	var k: float = (0.35 + 0.65 * beat * beat) * (0.5 + 0.5 * p)
	var bands: PackedFloat32Array = [0.42, 0.26, 0.14, 0.06]
	var sides: Array[float] = [maxf(0.0, -dir.y), maxf(0.0, dir.y), maxf(0.0, -dir.x), maxf(0.0, dir.x)]  # top, bottom, left, right
	for i in bands.size():
		var bw: float = 5.0
		var o: float = float(i) * bw
		var a: float = bands[i] * k
		var col: Color = Gfx.GLOW[2] if i > 0 else Gfx.GLOW[3]
		draw_rect(Rect2(0, o, vs.x, bw), Color(col, a * (0.2 + 0.8 * sides[0])))
		draw_rect(Rect2(0, vs.y - o - bw, vs.x, bw), Color(col, a * (0.2 + 0.8 * sides[1])))
		draw_rect(Rect2(o, 0, bw, vs.y), Color(col, a * (0.2 + 0.8 * sides[2])))
		draw_rect(Rect2(vs.x - o - bw, 0, bw, vs.y), Color(col, a * (0.2 + 0.8 * sides[3])))


## An arrow on the screen edge toward the boss (or where it will surface) while it is off screen.
func _boss_pointer(vs: Vector2, wp: Vector2, coming: bool) -> void:
	if wp == Vector2.INF:
		return
	var sp: Vector2 = view.get_viewport().get_canvas_transform() * wp
	if Rect2(Vector2.ZERO, vs).grow(-8.0).has_point(sp):
		return
	var inset := Rect2(Vector2(14, 14), vs - Vector2(28, 28))
	var c: Vector2 = vs / 2.0
	var dir: Vector2 = (sp - c).normalized()
	var t: float = INF
	if absf(dir.x) > 0.001:
		t = minf(t, ((inset.end.x if dir.x > 0.0 else inset.position.x) - c.x) / dir.x)
	if absf(dir.y) > 0.001:
		t = minf(t, ((inset.end.y if dir.y > 0.0 else inset.position.y) - c.y) / dir.y)
	var p: Vector2 = _clear_of_panels(c + dir * t, inset).floor()
	var on: bool = not coming or (world.tick / 4) % 2 == 0
	UiKit.pointer(self, p, dir, 12.0, Gfx.GLOW[4] if on else Gfx.GLOW[2])
	var label: String = "BOSS"
	var lp: Vector2 = (p - dir * 24.0).floor()
	var lw: float = UiFont.width_small(label)
	draw_rect(Rect2(lp.x - lw / 2.0 - 3.0, lp.y - 5.0, lw + 6.0, 10), Color(Gfx.OUTLINE, 0.8))
	UiFont.draw_small(self, label, Vector2(floorf(lp.x - lw / 2.0), lp.y - 3.0), Gfx.GLOW[4])


## PvP grace (round PVP_START_ROUND): a hazard-framed countdown at the top until rivals may shoot.
func _draw_grace(vs: Vector2, below: bool) -> void:
	if world.phase != SimWorld.PHASE_COMBAT or world.pvp_grace_ticks <= 0:
		return
	var cx: float = floorf(vs.x / 2.0)
	var secs: int = ceili(float(world.pvp_grace_ticks) / float(SimWorld.TICK_RATE))
	var title := "PVP IN %d" % secs
	var r := Rect2(cx - 60, (66.0 if below else 37.0) + _boss_offset(), 120, 27)
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
## watched / local rig is marked. With control zones on the field a ZONE column shows each rig's zone points
## this round.
func _draw_standings(watched: SimVehicle) -> void:
	var rows: Array[SimVehicle] = UiKit.standings(world)
	var zones: bool = not world.zones.is_empty()
	var r := Rect2(6, 6, 140 + (24.0 if zones else 0.0), 18 + rows.size() * 10)
	UiKit.panel(self, r)
	_panels.append(r)
	var cols: Array = [["FUEL", 34.0], ["KILLS", 6.0]]  # [header, right edge inset]
	if zones:
		cols = [["FUEL", 58.0], ["KILLS", 30.0], ["ZONE", 6.0]]
	var head_x: float = r.end.x - float(cols[0][1]) - UiFont.width_small(cols[0][0]) - 4.0
	UiKit.section(self, "STANDINGS", r.position + Vector2(6, 5), head_x - r.position.x - 6.0)
	for col: Array in cols:
		var hw: float = UiFont.width_small(col[0])
		UiFont.draw_small(self, col[0], Vector2(r.end.x - float(col[1]) - hw, r.position.y + 5), Gfx.UI_DIM)
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
		UiFont.draw(self, ft, Vector2(r.end.x - float(cols[0][1]) - UiFont.width(ft), y), Gfx.UI_DIM if out else Gfx.FIRE[3], Gfx.UI_SHADOW)
		var kt := str(o.kills)
		UiFont.draw(self, kt, Vector2(r.end.x - float(cols[1][1]) - UiFont.width(kt), y), Gfx.UI_DIM if out else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		if zones:
			var zp: int = int(o.round_stats.get("zone_points", 0))
			var held: int = Zones.held_by(world, o)
			var zt := str(zp)
			var zx: float = r.end.x - 6.0 - UiFont.width(zt)
			UiFont.draw(self, zt, Vector2(zx, y), Gfx.FIRE[4] if zp > 0 and not out else Gfx.UI_DIM, Gfx.UI_SHADOW)
			for k in held:  # a flag pip per zone it holds right now
				var fp := Vector2(zx - 5.0 - 4.0 * k, y)
				draw_rect(Rect2(fp, Vector2(3, 6)), Gfx.OUTLINE)
				draw_rect(Rect2(fp + Vector2(1, 1), Vector2(2, 2)), UiKit.bar_color(o.color_index))
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



# ---------------------------------------------------------------- control zones (sim/zones.gd, ZoneView)

## Fill and text colour of zone badge `i`: the owner's paint, plate grey when nobody holds it.
func _zone_badge(r: Rect2, i: int, big: bool = false) -> void:
	var z: Dictionary = world.zones[i]
	var owner: SimVehicle = UiKit.vehicle_by_id(world, int(z["owner"]))
	var live: bool = world.zones_active
	var hot: bool = live and bool(z["contested"])
	draw_rect(r, Gfx.OUTLINE)
	var inner: Rect2 = r.grow(-1.0)
	if owner != null:
		var pc: Color = UiKit.bar_color(owner.color_index)
		draw_rect(inner, pc if live else pc.darkened(0.45))
		draw_rect(Rect2(inner.position, Vector2(inner.size.x, 1)), (pc if live else pc.darkened(0.45)).lightened(0.3))
	else:
		draw_rect(inner, Gfx.UI_PLATE_DARK)
	var prog: float = Zones.progress(z) if live else 0.0
	if prog > 0.0 and not hot:
		var cap: SimVehicle = UiKit.vehicle_by_id(world, int(z["cap_id"]))
		if cap != null:
			draw_rect(Rect2(inner.position.x, inner.end.y - 2, floorf(inner.size.x * prog), 2), UiKit.bar_color(cap.color_index))
	if hot and (world.tick / 5) % 2 == 0:
		UiKit.outline_rect(self, r.grow(1.0), Gfx.HAZARD)
	var dark_text: bool = owner != null and live and Gfx.color_slot(owner.color_index) != Gfx.DARK_PAINT
	var tc: Color = Gfx.INK if dark_text else (Gfx.UI_TEXT if live else Gfx.UI_DIM)
	var l: String = ZoneView.letter(i)
	if big:
		UiKit.center_big(self, l, r.get_center().x, r.position.y + floorf((r.size.y - 8.0) / 2.0), tc)
	else:
		UiKit.center_text(self, l, r.get_center().x + 1.0, r.position.y + floorf((r.size.y - 6.0) / 2.0), tc)


## Left of the clock plate: one badge per zone in its owner's paint (capture bar, contested blink), how many
## the watched rig holds and its zone points this round.
func _draw_zone_panel(vs: Vector2, v: SimVehicle) -> void:
	if world.zones.is_empty():
		return
	var top: Rect2 = _top_rect(vs)
	var r := Rect2(top.position.x - 4.0 - ZONE_PANEL_W, top.position.y, ZONE_PANEL_W, top.size.y)
	_panels.append(r)
	UiKit.panel(self, r)
	var x0: float = r.position.x + 6.0
	var y: float = r.position.y + 5.0
	var status: String
	var scol: Color = Gfx.UI_DIM
	if not world.zones_active:
		status = "LOCKED"
	elif v != null:
		var held: int = Zones.held_by(world, v)
		status = "HELD %d/%d" % [held, world.zones.size()]
		scol = Gfx.FIRE[4] if held > 0 else Gfx.UI_DIM
	UiKit.section(self, "ZONES", Vector2(x0, y), r.size.x - 12.0, status, scol)
	var bx: float = x0
	for i in world.zones.size():
		_zone_badge(Rect2(bx, r.position.y + 13.0, 12, 11), i)
		bx += 14.0
	if v != null:
		var pts: int = int(v.round_stats.get("zone_points", 0))
		var pt: String = "+%d" % pts
		var px: float = r.end.x - 6.0 - UiFont.width_big(pt)
		UiFont.draw_big(self, pt, Vector2(px, r.position.y + 15.0), Gfx.FIRE[4] if pts > 0 else Gfx.UI_DIM, Gfx.OUTLINE)


## Over each zone beacon on screen (screen space, crisp): its letter in the owner's paint and what is going
## on there: LOCKED, FREE, the holder, TAKING n% in the capturer's paint, CONTESTED, YOURS +1/S.
func _draw_zone_tags(focus: SimVehicle) -> void:
	if view == null or view.attract or world.zones.is_empty():
		return
	var vs: Vector2 = get_viewport_rect().size
	for i in world.zones.size():
		var z: Dictionary = world.zones[i]
		var foot: Vector2 = view.to_screen(z["pos"])
		var tag := Vector2(foot.x - 7.0, foot.y - ZoneView.BEACON_FOOT.y - 14.0)
		if not Rect2(Vector2(-60, -20), vs + Vector2(120, 40)).has_point(tag):
			continue
		var b := Rect2(tag.floor(), Vector2(13, 12))
		_zone_badge(b, i, true)
		var owner: SimVehicle = UiKit.vehicle_by_id(world, int(z["owner"]))
		var cap: SimVehicle = UiKit.vehicle_by_id(world, int(z["cap_id"]))
		var prog: float = Zones.progress(z)
		# [name in paint (or ""), its paint, plain text, its colour, rim]
		var who: String = ""
		var who_paint: int = 0
		var text: String
		var col: Color = Gfx.UI_TEXT
		var rim: Color = Gfx.UI_SHADOW
		var capturing: bool = false
		if not world.zones_active:
			var secs: int = ceili(float(world.pvp_grace_ticks) / float(SimWorld.TICK_RATE))
			text = "LOCKED" if secs <= 0 else "OPENS IN %d" % secs
			col = Gfx.UI_DIM
		elif bool(z["contested"]):
			text = "CONTESTED"
			col = Gfx.UI_BAD if (world.tick / 5) % 2 == 0 else Gfx.HAZARD
			rim = Gfx.OUTLINE
		elif cap != null and prog > 0.0:
			who = UiKit.player_name(cap) if cap != focus else "YOU"
			who_paint = cap.color_index
			text = " TAKING %d%%" % floori(prog * 100.0)
			capturing = true
		elif owner != null and owner == focus:
			var inside: bool = Zones.zone_at(world, focus.pos) == i and focus.alive
			text = "YOURS +%d/S" % Zones.ZONE_SCRAP_PER_SEC if inside else "YOURS"
			col = Gfx.FIRE[5]
			rim = Gfx.OUTLINE
		elif owner != null:
			who = UiKit.player_name(owner)
			who_paint = owner.color_index
			text = ""
		else:
			text = "FREE ZONE"
			col = Gfx.BONE_LIGHT
			rim = Gfx.OUTLINE
		var tw: float = UiFont.width(who) + UiFont.width(text)
		var tx: float = b.end.x + 4.0
		if tx + tw > vs.x - 4.0:  # near the right edge: the words go left of the badge
			tx = b.position.x - 4.0 - tw
		var ty: float = b.position.y + 3.0
		var x: float = tx
		if who != "":
			x = UiKit.paint_text(self, who, Vector2(x, ty), who_paint)
		if text != "":
			x = UiFont.draw(self, text, Vector2(x, ty), col, rim)
		if capturing:
			UiKit.bar(self, Rect2(tx, ty + 8.0, x - tx, 3), prog, UiKit.bar_color(cap.color_index))


## A small badge at the screen edge for every zone off screen (its letter in the owner's paint and a pointer),
## kept clear of the HUD plates like the rival arrows.
func _draw_zone_arrows(vs: Vector2) -> void:
	if view == null or world.zones.is_empty():
		return
	var inset := Rect2(Vector2(12, 12), vs - Vector2(24, 24))
	var c: Vector2 = vs / 2.0
	for i in world.zones.size():
		var sp: Vector2 = view.to_screen(world.zones[i]["pos"])
		if Rect2(Vector2.ZERO, vs).grow(-8.0).has_point(sp):
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
		var p: Vector2 = _clear_of_panels(c + dir * t, inset).floor()
		var owner: SimVehicle = UiKit.vehicle_by_id(world, int(world.zones[i]["owner"]))
		var col: Color = UiKit.bar_color(owner.color_index) if owner != null and world.zones_active else Gfx.BONE_LIGHT
		UiKit.pointer(self, p + Vector2(0.5, 0.5) + dir * 3.0, dir, 5.0, col)
		_zone_badge(Rect2(p - dir * 7.0 - Vector2(5, 5), Vector2(11, 11)), i)


## Ticks since the CONTROL ZONES OPEN banner started (-1 = none): with the zones, but after the PVP ON banner
## when PvP and the zones switch on together (round 4).
func _zones_banner_age() -> int:
	if view == null or view.zones_open_tick < 0 or world.zones.is_empty():
		return -1
	var start: int = view.zones_open_tick
	if view.pvp_on_tick >= 0 and absi(view.pvp_on_tick - start) <= 2:
		start = view.pvp_on_tick + PVP_BANNER_TICKS
	var age: int = world.tick - start
	return age if age >= 0 else -1


## The zones go live: a hazard banner in the PVP ON style with the zone badges and the deal.
func _zones_banner(vs: Vector2, el: int) -> void:
	var slide: float = clampf(1.0 - float(el) / 6.0, 0.0, 1.0)
	if el > ZONES_BANNER_TICKS - 12 and (el / 2) % 2 == 0:
		return
	var y: float = 94.0
	var h: float = 40.0
	var x: float = floorf(slide * vs.x)  # from the right (PVP ON comes from the left)
	draw_rect(Rect2(x, y - 1, vs.x, h + 2), Gfx.OUTLINE)
	UiKit.hazard_frame(self, Rect2(x, y, vs.x, h), 4.0)
	draw_rect(Rect2(x, y + 5, vs.x, h - 10), Color("#2a1c18"))
	draw_rect(Rect2(x, y + 5, vs.x, 1), Color("#5e2f1e"))
	var cx: float = floorf(x + vs.x / 2.0)
	var flick: Color = Gfx.FIRE[5] if (el / 4) % 2 == 0 or el > 24 else Gfx.UI_TEXT
	var title := "CONTROL ZONES OPEN"
	UiKit.center_big(self, title, cx, y + 9, flick, Gfx.OUTLINE, 2)
	UiKit.center_text(self, "STAND ALONE IN A ZONE %d S TO TAKE IT - HOLD IT FOR SCRAP" % (Zones.CAPTURE_TICKS / SimWorld.TICK_RATE), cx, y + 27, Gfx.UI_TEXT, Gfx.UI_SHADOW)
	var tw: float = UiFont.width_big(title) * 2.0
	for side in 2:
		for i in world.zones.size():
			var bx: float = cx - tw / 2.0 - 16.0 - 15.0 * float(world.zones.size() - i) if side == 0 else cx + tw / 2.0 + 6.0 + 15.0 * float(i)
			_zone_badge(Rect2(floorf(bx), y + 10, 13, 13), i, true)


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
	var y: float = 37.0 + (29.0 if below else 0.0) + (31.0 if world.pvp_grace_ticks > 0 else 0.0) + _boss_offset()
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
