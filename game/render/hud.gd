class_name Hud
extends Control
## Combat HUD in the mock-up style (riveted plates, 3x5 font, stencil headings): round, phase
## timer, hp and fuel, scrap; the hive; doctrine; round-start / workshop-start banners; the
## respawn countdown (with what wrecked you) and the ELIMINATED state. Information UI from playtest
## round 1 (#2, #5): a kill feed of player kills under the hive plate, off-screen rival arrows at the
## screen edge, the PvP grace countdown, a fuel-drain warning before camp, and spectator mode once
## the local rig is eliminated (Tab / Left / Right cycle the watched rig, live standings). Reads sim
## state and the WorldView logs only, so it works the same for host, client and solo. Workshop and
## game over have their own overlays.

const BANNER_TICKS := 75  ## how long a phase-start banner stays up (sim ticks)
const PVP_BANNER_TICKS := 105  ## the full-width PVP ON banner (#11)
const LOW_HP := 0.3  ## below this hp fraction the screen edges pulse red (#12)
const FEED_TICKS := 210  ## a kill feed line stays this long (7 s)
const FEED_MAX := 4
const DRAIN_WARN_TICKS := 12 * SimWorld.TICK_RATE  ## warn about the camp fuel drain this long before it
const FEED_BG := Color(0.1, 0.07, 0.07, 0.78)

var _panels: Array[Rect2] = []  ## HUD rects drawn this frame (rival arrows stay clear of them)

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(_delta: float) -> void:
	queue_redraw()


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
		_draw_status(v)
		_draw_hive(vs)
		_draw_doctrine(v, vs)
		var watching: bool = spec and not elim_recent
		if watching:
			_draw_spectating(vs, v)
			_draw_standings(v)
		elif me != null and not me.eliminated:
			_draw_drain_warning(me)
		_draw_feed(vs)
		_draw_grace(vs, watching)
		_draw_rival_tags()
		if v != null and (watching or not (me != null and me.eliminated)):
			_draw_rival_arrows(vs, v)
		if me != null and me.eliminated and not watching:
			_draw_eliminated(vs)
		elif dead:
			_draw_respawn(me, vs)
	var pv: int = world.tick - view.pvp_on_tick if view != null and view.pvp_on_tick >= 0 else -1
	if world.phase == SimWorld.PHASE_COMBAT and pv >= 0 and pv < PVP_BANNER_TICKS:
		_pvp_banner(vs, pv)
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

func _draw_status(v: SimVehicle) -> void:
	var r := Rect2(6, 6, 158, 53)
	_panels.append(r)
	UiKit.plate(self, r)
	var x0: float = r.position.x + 7.0
	var xr: float = r.end.x - 7.0
	UiFont.draw_big(self, "ROUND %d" % world.round, Vector2(x0, 11), Gfx.UI_TEXT, Gfx.OUTLINE)
	var t: String = UiKit.clock(world.phase_ticks_left)
	UiFont.draw_big(self, t, Vector2(xr - UiFont.width_big(t), 11), Gfx.FIRE[4], Gfx.OUTLINE)
	UiFont.draw_small(self, "HP", Vector2(x0, 23), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw_small(self, "FUEL", Vector2(x0, 32), Gfx.UI_DIM, Gfx.UI_SHADOW)
	var bx: float = x0 + 20.0
	var hp_frac: float = 0.0
	var fuel: int = 0
	if v != null:
		hp_frac = clampf(v.hp / v.max_hp, 0.0, 1.0) if v.alive else 0.0
		fuel = maxi(v.fuel, 0)
	var hp_txt: String = "%d/%d" % [ceili(maxf(v.hp, 0.0)) if v.alive else 0, roundi(v.max_hp)] if v else "0"
	var low: bool = v != null and v.alive and hp_frac < LOW_HP
	var hp_col: Color = Gfx.UI_BAD if low else Gfx.UI_TEXT
	var num_w: float = 42.0  # right column for the numbers, so both bars line up
	UiKit.bar(self, Rect2(bx, 23, xr - num_w - bx, 6), hp_frac, UiKit.bar_color(v.color_index) if v else Gfx.UI_DIM)
	UiFont.draw(self, hp_txt, Vector2(xr - UiFont.width(hp_txt), 23), hp_col, Gfx.UI_SHADOW)
	var fuel_col: Color = Gfx.FIRE[3] if fuel > 40 else Gfx.UI_BAD
	UiKit.bar(self, Rect2(bx, 32, xr - num_w - bx, 6), float(fuel) / float(SimWorld.START_FUEL), fuel_col)
	var ft := str(fuel)
	UiFont.draw(self, ft, Vector2(xr - UiFont.width(ft), 32), fuel_col, Gfx.UI_SHADOW)
	draw_rect(Rect2(x0 - 1, 42, xr - x0 + 2, 1), Color(Gfx.OUTLINE, 0.8))
	var sx: float = UiFont.draw_small(self, "SCRAP ", Vector2(x0, 46), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw(self, str(v.scrap if v else 0), Vector2(sx, 46), Gfx.FIRE[4], Gfx.UI_SHADOW)
	var k := str(v.kills if v else 0)
	var kx: float = xr - UiFont.width(k)
	UiFont.draw(self, k, Vector2(kx, 46), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiFont.draw_small(self, "KILLS ", Vector2(kx - UiFont.width_small("KILLS "), 46), Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_hive(vs: Vector2) -> void:
	var l1 := "HIVE: %d ALIVE" % world.enemy_count
	var boost: float = SimWorld.enemy_hp_mult(world.round) - 1.0
	var l2 := ("HIVE HP +%s" % UiKit.pct(boost)) if boost > 0.001 else "HIVE HP BASE"
	var pw: float = maxf(UiFont.width(l1), UiFont.width(l2)) + 16.0
	UiKit.plate(self, Rect2(vs.x - pw - 6, 6, pw, 28))
	_panels.append(Rect2(vs.x - pw - 6, 6, pw, 28))
	UiFont.draw(self, l1, Vector2(vs.x - pw + 2, 12), Gfx.GLOW[3], Gfx.UI_SHADOW)
	UiFont.draw(self, l2, Vector2(vs.x - pw + 2, 22), Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_doctrine(v: SimVehicle, vs: Vector2) -> void:
	if v == null:
		return
	var drive: String = str(v.doctrine["drive"]).to_upper()
	var target: String = str(v.doctrine["target"]).replace("_", " ").to_upper()
	var live := PackedStringArray()
	for i in Doctrine.MAX_SLOTS:
		if (v.rule_live >> i) & 1 == 1:
			live.append(str(i + 1))
	var rules: String = " ".join(live) if not live.is_empty() else "-"
	var dw: float = UiFont.width_small("DRIVE ") + UiFont.width(drive) + UiFont.width_small("    TARGET ") + UiFont.width(target) \
		+ UiFont.width_small("    RULE ") + UiFont.width(rules) + UiFont.width_small("    P: PROGRAM") + 16.0
	var r := Rect2(6, vs.y - 23, dw, 17)
	UiKit.plate(self, r)
	_panels.append(r)
	var x: float = UiFont.draw_small(self, "DRIVE ", Vector2(14, vs.y - 17), Gfx.UI_DIM, Gfx.UI_SHADOW)
	x = UiFont.draw(self, drive, Vector2(x, vs.y - 17), Gfx.CRT_TEXT, Gfx.UI_SHADOW)
	x = UiFont.draw_small(self, "    TARGET ", Vector2(x, vs.y - 17), Gfx.UI_DIM, Gfx.UI_SHADOW)
	x = UiFont.draw(self, target, Vector2(x, vs.y - 17), Gfx.CRT_TEXT, Gfx.UI_SHADOW)
	x = UiFont.draw_small(self, "    RULE ", Vector2(x, vs.y - 17), Gfx.UI_DIM, Gfx.UI_SHADOW)
	x = UiFont.draw(self, rules, Vector2(x, vs.y - 17), Gfx.CRT_HI if not live.is_empty() else Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw_small(self, "    P: PROGRAM", Vector2(x, vs.y - 17), Gfx.UI_DIM, Gfx.UI_SHADOW)


# ---------------------------------------------------------------- overlays

func _dim(vs: Vector2, center: Vector2) -> void:
	var s := Vector2(Gfx.TEX_VIGNETTE.get_size())
	draw_texture(Gfx.TEX_VIGNETTE, (center - s / 2.0).floor())
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.05, 0.06, 0.25))


func _draw_respawn(v: SimVehicle, vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var r := Rect2(cx - 84, 92, 168, 57)
	UiKit.plate(self, r)
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
	UiKit.plate(self, r)
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
	var y: float = 38.0
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
	var r := Rect2(cx - 60, 40.0 if below else 6.0, 120, 27)
	UiKit.plate(self, r)
	UiKit.hazard_frame(self, r.grow(-2.0), 2.0)
	var hot: bool = secs <= 3 and (world.tick / 5) % 2 == 0
	UiKit.center_big(self, title, cx, r.position.y + 6, Gfx.UI_BAD if hot else Gfx.FIRE[4], Gfx.OUTLINE)
	UiKit.center_text(self, "RIVALS HOLD FIRE - FOR NOW", cx, r.position.y + 16, Gfx.UI_DIM, Gfx.UI_SHADOW)
	_panels.append(r)


## Late rounds of a multiplayer game: a tape under the status plate before camp drains fuel.
func _draw_drain_warning(v: SimVehicle) -> void:
	if world.vehicles.size() < 2 or v.eliminated:
		return
	var drain: int = SimWorld.fuel_drain_for_round(world.round)
	if drain <= 0 or world.phase_ticks_left > DRAIN_WARN_TICKS:
		return
	var text := "CAMP DRAINS %d FUEL - KILLS REFUEL" % drain
	var r := Rect2(6, 63, UiFont.width(text) + 10.0, 10)
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
	var r := Rect2(cx - floorf(w / 2.0), 6, w, 27)
	UiKit.plate(self, r)
	var x0: float = cx - floorf((UiFont.width("SPECTATING") + 6.0 + UiFont.width_big(nm)) / 2.0)
	var x: float = UiFont.draw(self, "SPECTATING", Vector2(x0, r.position.y + 7), Gfx.UI_DIM, Gfx.UI_SHADOW) + 6.0
	UiKit.paint_big(self, nm, Vector2(x, r.position.y + 6), v.color_index)
	var auto: bool = view.spectate_id < 0
	var keys: String = ("AUTO CAM - " if auto else "") + "TAB  < >  SWITCH RIG"
	UiKit.center_text(self, keys, cx, r.position.y + 17, Gfx.UI_DIM, Gfx.UI_SHADOW)
	_panels.append(r)


## Live standings under the status plate while spectating (fuel, kills; the watched rig marked).
func _draw_standings(watched: SimVehicle) -> void:
	var rows: Array[SimVehicle] = UiKit.standings(world)
	var r := Rect2(6, 63, 158, 18 + rows.size() * 10)
	UiKit.plate(self, r)
	_panels.append(r)
	UiFont.draw(self, "STANDINGS", r.position + Vector2(6, 5), Gfx.UI_DIM, Gfx.UI_SHADOW)
	UiFont.draw(self, "FUEL  KILLS", Vector2(r.end.x - 6 - UiFont.width("FUEL  KILLS"), r.position.y + 5), Gfx.UI_DIM, Gfx.UI_SHADOW)
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
