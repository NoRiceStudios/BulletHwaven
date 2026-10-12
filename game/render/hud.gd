class_name Hud
extends Control
## Combat HUD in the mock-up style (riveted plates, 3x5 font, stencil headings): round, phase
## timer, hp and fuel, scrap; the hive; doctrine; round-start / workshop-start banners; the
## respawn countdown and the ELIMINATED state. Reads the local player's vehicle only, so it works
## the same for host, client and solo. Workshop and game over have their own overlays.

const BANNER_TICKS := 75  ## how long a phase-start banner stays up (sim ticks)
const PVP_BANNER_TICKS := 105  ## the full-width PVP ON banner (#11)
const LOW_HP := 0.3  ## below this hp fraction the screen edges pulse red (#12)

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _process(_delta: float) -> void:
	queue_redraw()


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
	var vs: Vector2 = get_viewport_rect().size
	var v: SimVehicle = world.get_vehicle_for_peer(local_peer)
	if world.phase == SimWorld.PHASE_COMBAT:
		var dead: bool = v != null and not v.alive and not v.eliminated
		if v != null and v.eliminated:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.05, 0.06, 0.45))
		elif dead:
			_dim(vs, view.local_screen_pos() if view else vs / 2.0)
		elif v != null and v.alive and v.hp / v.max_hp < LOW_HP:
			_low_hp(vs, v.hp / v.max_hp)
		_draw_status(v)
		_draw_hive(vs)
		_draw_doctrine(v, vs)
		if v != null and v.eliminated:
			_draw_eliminated(vs)
		elif dead:
			_draw_respawn(v, vs)
	var pv: int = world.tick - view.pvp_on_tick if view != null and view.pvp_on_tick >= 0 else -1
	if world.phase == SimWorld.PHASE_COMBAT and pv >= 0 and pv < PVP_BANNER_TICKS:
		_pvp_banner(vs, pv)
	var el: int = phase_elapsed(world)
	if el >= 0 and el < BANNER_TICKS:
		if world.phase == SimWorld.PHASE_COMBAT:
			_banner(vs, "ROUND %d" % world.round, "THE HIVE STIRS" if world.round > 1 else "HOLD THE LINE", el, 64.0)
		elif world.phase == SimWorld.PHASE_WORKSHOP:
			_banner(vs, "HIVE RETREATS", "MAKE CAMP - %s ON THE CLOCK" % UiKit.clock(world.workshop_duration()), el, 112.0)


# ---------------------------------------------------------------- combat panels

func _draw_status(v: SimVehicle) -> void:
	var r := Rect2(6, 6, 150, 46)
	UiKit.plate(self, r)
	var x0: float = r.position.x + 6.0
	PixelFont.draw(self, "ROUND %d" % world.round, Vector2(x0, 11), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	var t: String = UiKit.clock(world.phase_ticks_left)
	PixelFont.draw(self, t, Vector2(r.end.x - 6 - PixelFont.width(t), 11), Gfx.FIRE[4], Gfx.UI_SHADOW)
	PixelFont.draw(self, "HP", Vector2(x0, 19), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	PixelFont.draw(self, "FUEL", Vector2(x0, 27), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	var bx: float = x0 + 20.0
	var bw: float = r.end.x - 6.0 - bx
	var hp_frac: float = 0.0
	var fuel: int = 0
	if v != null:
		hp_frac = clampf(v.hp / v.max_hp, 0.0, 1.0) if v.alive else 0.0
		fuel = maxi(v.fuel, 0)
	var hp_txt: String = "%d/%d" % [ceili(maxf(v.hp, 0.0)) if v.alive else 0, roundi(v.max_hp)] if v else "0"
	var low: bool = v != null and v.alive and hp_frac < LOW_HP
	var hp_col: Color = Gfx.UI_BAD if low else Gfx.UI_TEXT
	UiKit.bar(self, Rect2(bx, 19, bw - PixelFont.width(hp_txt) - 4, 5), hp_frac, UiKit.bar_color(v.color_index) if v else Gfx.UI_DIM)
	PixelFont.draw(self, hp_txt, Vector2(r.end.x - 6 - PixelFont.width(hp_txt), 19), hp_col, Gfx.UI_SHADOW)
	var fuel_col: Color = Gfx.FIRE[3] if fuel > 40 else Gfx.UI_BAD
	UiKit.bar(self, Rect2(bx, 27, bw - 16, 5), float(fuel) / float(SimWorld.START_FUEL), fuel_col)
	var ft := str(fuel)
	PixelFont.draw(self, ft, Vector2(r.end.x - 6 - PixelFont.width(ft), 27), fuel_col, Gfx.UI_SHADOW)
	PixelFont.draw(self, "SCRAP %d" % (v.scrap if v else 0), Vector2(x0, 37), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	var k := "KILLS %d" % (v.kills if v else 0)
	PixelFont.draw(self, k, Vector2(r.end.x - 6 - PixelFont.width(k), 37), Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_hive(vs: Vector2) -> void:
	var l1 := "HIVE: %d ALIVE" % world.enemy_count
	var boost: float = SimWorld.enemy_hp_mult(world.round) - 1.0
	var l2 := ("HIVE HP +%s" % UiKit.pct(boost)) if boost > 0.001 else "HIVE HP BASE"
	var pw: float = maxf(PixelFont.width(l1), PixelFont.width(l2)) + 14.0
	UiKit.plate(self, Rect2(vs.x - pw - 6, 6, pw, 25))
	PixelFont.draw(self, l1, Vector2(vs.x - pw + 1, 11), Gfx.GLOW[3], Gfx.UI_SHADOW)
	PixelFont.draw(self, l2, Vector2(vs.x - pw + 1, 20), Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_doctrine(v: SimVehicle, vs: Vector2) -> void:
	if v == null:
		return
	var doc := "DOCTRINE: %s  /  TARGET: %s" % [str(v.doctrine["drive"]), str(v.doctrine["target"]).replace("_", " ")]
	var dw: float = PixelFont.width(doc) + 14.0
	UiKit.plate(self, Rect2(6, vs.y - 22, dw, 16))
	PixelFont.draw(self, doc, Vector2(13, vs.y - 16), Gfx.UI_TEXT, Gfx.UI_SHADOW)


# ---------------------------------------------------------------- overlays

func _dim(vs: Vector2, center: Vector2) -> void:
	var s := Vector2(Gfx.TEX_VIGNETTE.get_size())
	draw_texture(Gfx.TEX_VIGNETTE, (center - s / 2.0).floor())
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.05, 0.06, 0.25))


func _draw_respawn(v: SimVehicle, vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var r := Rect2(cx - 70, 92, 140, 48)
	UiKit.plate(self, r)
	UiKit.center_big(self, "RIG DESTROYED", cx, r.position.y + 6, Gfx.FIRE[4], Gfx.OUTLINE)
	var secs: float = float(maxi(v.respawn_ticks, 0)) / float(SimWorld.TICK_RATE)
	UiKit.center_text(self, "BACK ON THE ROAD IN %.1f" % secs, cx, r.position.y + 18, Gfx.UI_TEXT, Gfx.UI_SHADOW)
	UiKit.bar(self, Rect2(r.position.x + 10, r.position.y + 27, r.size.x - 20, 5),
		1.0 - float(v.respawn_ticks) / float(SimWorld.RESPAWN_TICKS), Gfx.FIRE[3])
	UiKit.center_text(self, "FUEL LEFT %d" % maxi(v.fuel, 0), cx, r.position.y + 36, Gfx.UI_BAD if v.fuel <= 40 else Gfx.UI_DIM, Gfx.UI_SHADOW)


func _draw_eliminated(vs: Vector2) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var r := Rect2(cx - 92, 92, 184, 44)
	UiKit.plate(self, r)
	UiKit.hazard_frame(self, r.grow(-3.0), 2.0)
	UiKit.center_big(self, "ELIMINATED", cx, r.position.y + 9, Gfx.UI_BAD, Gfx.OUTLINE, 2)
	UiKit.center_text(self, "OUT OF FUEL - WATCHING THE OTHERS", cx, r.position.y + 30, Gfx.UI_TEXT, Gfx.UI_SHADOW)


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
	var tw: float = PixelFont.width_big("PVP ON") * 2.0
	for sx: float in [cx - tw / 2.0 - 18.0 - s.x, cx + tw / 2.0 + 18.0]:
		draw_texture(Gfx.TEX_SKULL, Vector2(floorf(sx), y + 13))


## Tape banner that slides in and stays; `el` = ticks since the phase started.
func _banner(vs: Vector2, title: String, sub: String, el: int, y: float) -> void:
	var cx: float = floorf(vs.x / 2.0)
	var tw: float = maxf(PixelFont.width_big(title), PixelFont.width(sub)) + 24.0
	var slide: float = clampf(1.0 - float(el) / 8.0, 0.0, 1.0)
	var r := Rect2(floorf(cx - tw / 2.0 - slide * 60.0), y, tw, 22)
	UiKit.tape(self, r, Color("#e8dcc4"))
	UiKit.center_big(self, title, r.get_center().x, y + 3, Gfx.INK)
	UiKit.center_text(self, sub, r.get_center().x, y + 13, Gfx.INK_RED)
