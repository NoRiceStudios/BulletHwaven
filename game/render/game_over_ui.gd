class_name GameOverUi
extends Control
## Game over screen (phase == PHASE_GAME_OVER): the frozen field behind a dark vignette, the
## winner (or "YOUR CONVOY IS LOST" in solo, with the round reached), per-rig standings and the
## buttons. Restart and quit are callables set by main.gd: the host (and solo) gets a rematch /
## restart (NetSession.rematch()), clients see `waiting_text`; everyone can leave to the menu.

var world: SimWorld = null
var local_peer: int = 1
var view: WorldView = null
var restart: Callable = Callable()  ## invalid = no restart offered (clients wait for the host)
var restart_label: String = "REMATCH"
var quit: Callable = Callable()
var quit_label: String = "LEAVE TO MENU"
var waiting_text: String = "WAITING FOR THE HOST TO CALL A REMATCH"

var _hits: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false


func _process(_delta: float) -> void:
	visible = world != null and world.phase == SimWorld.PHASE_GAME_OVER
	if visible:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		for h: Array in _hits:
			if (h[0] as Rect2).has_point((event as InputEventMouseButton).position):
				_activate(h[1])
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_SPACE:
			_activate("restart")
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			_activate("quit")
			get_viewport().set_input_as_handled()


func _activate(action: String) -> void:
	if action == "restart" and restart.is_valid():
		restart.call()
	elif action == "quit" and quit.is_valid():
		quit.call()


func _draw() -> void:
	_hits.clear()
	var vs: Vector2 = get_viewport_rect().size
	var c: Vector2 = view.local_screen_pos() if view else vs / 2.0
	var vig := Vector2(Gfx.TEX_VIGNETTE.get_size())
	draw_texture(Gfx.TEX_VIGNETTE, (c - vig / 2.0).floor())
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.08, 0.05, 0.06, 0.5))
	var me: SimVehicle = world.get_vehicle_for_peer(local_peer)
	var solo: bool = world.vehicles.size() < 2
	var cx: float = floorf(vs.x / 2.0)
	var n: int = world.vehicles.size()
	var r := Rect2(cx - 130, 22, 260, 112 + n * 9)
	UiKit.plate(self, r)
	UiKit.hazard_band(self, Rect2(r.position.x + 5, r.position.y + 5, r.size.x - 10, 5))

	var title: String
	var sub: String
	var col: Color
	if solo:
		title = "YOUR CONVOY IS LOST"
		sub = "RAN DRY IN ROUND %d" % world.round
		col = Gfx.UI_BAD
	elif world.winner_peer == local_peer:
		title = "LAST RIG STANDING"
		sub = "YOUR CONVOY RULES THE DUNES - ROUND %d" % world.round
		col = Gfx.FIRE[4]
	elif world.winner_peer >= 0:
		var wv: SimVehicle = world.get_vehicle_for_peer(world.winner_peer)
		title = "%s WINS" % (UiKit.player_name(wv) if wv else "NOBODY")
		sub = "YOUR CONVOY IS LOST - ROUND %d" % world.round
		col = UiKit.bar_color(wv.color_index) if wv else Gfx.UI_TEXT
	else:
		title = "NO SURVIVORS"
		sub = "THE HIVE TAKES IT ALL - ROUND %d" % world.round
		col = Gfx.UI_BAD
	var scale: int = 2 if PixelFont.width_big(title, 2) <= r.size.x - 16 else 1
	UiKit.center_big(self, title, cx, r.position.y + 18, col, Gfx.OUTLINE, scale)
	UiKit.center_text(self, sub, cx, r.position.y + 40, Gfx.UI_TEXT, Gfx.UI_SHADOW)

	# standings
	var y: float = r.position.y + 54.0
	var cols: Array[float] = [r.position.x + 14, r.position.x + 120, r.position.x + 160, r.position.x + 200]
	for i in 4:
		PixelFont.draw(self, ["RIG", "FUEL", "KILLS", "TECH"][i], Vector2(cols[i], y), Gfx.UI_DIM, Gfx.UI_SHADOW)
	y += 9.0
	draw_rect(Rect2(r.position.x + 12, y - 3, r.size.x - 24, 1), Gfx.OUTLINE)
	for v in world.vehicles:
		UiKit.swatch(self, Rect2(cols[0] - 1, y - 1, 7, 7), v.color_index)
		var nx: float = UiKit.paint_text(self, UiKit.player_name(v), Vector2(cols[0] + 9, y), v.color_index)
		var tag: String = "WINNER" if v.peer_id == world.winner_peer else ("(YOU)" if v.peer_id == local_peer else "")
		if tag != "":
			PixelFont.draw(self, tag, Vector2(nx + 3, y), Gfx.FIRE[4] if v.peer_id == world.winner_peer else Gfx.UI_TEXT, Gfx.UI_SHADOW)
		PixelFont.draw(self, "OUT" if v.eliminated else str(v.fuel), Vector2(cols[1], y), Gfx.UI_DIM if v.eliminated else Gfx.FIRE[3], Gfx.UI_SHADOW)
		PixelFont.draw(self, str(v.kills), Vector2(cols[2], y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		PixelFont.draw(self, "%d/%d" % [v.tech.size(), Tech.count()], Vector2(cols[3], y), Gfx.UI_TEXT, Gfx.UI_SHADOW)
		y += 9.0
	if me != null:
		var best: String = ""
		var best_l: int = 0
		for id: String in me.cards:
			if int(me.cards[id]) > best_l:
				best_l = int(me.cards[id])
				best = id
		if best != "":
			UiKit.center_text(self, "FAVOURITE PART: %s LV %d" % [UiKit.card_name(best), best_l], cx, y + 4, Gfx.UI_DIM, Gfx.UI_SHADOW)

	# buttons
	var by: float = r.end.y - 24.0
	var has_restart: bool = restart.is_valid()
	var bw: float = 104.0
	var bx: float = cx - (bw + 4.0 if has_restart else bw / 2.0)
	var mouse: Vector2 = get_local_mouse_position()
	if has_restart:
		var rb := Rect2(bx, by, bw, 17)
		var hov: bool = rb.has_point(mouse)
		UiKit.steel(self, rb)
		UiKit.hazard_frame(self, rb, 2.0, Color.WHITE if hov else Color(0.8, 0.8, 0.8))
		UiKit.center_text(self, "ENTER - %s" % restart_label, rb.get_center().x, rb.position.y + 6, Gfx.FIRE[5] if hov else Gfx.UI_TEXT, Gfx.OUTLINE)
		_hits.append([rb, "restart"])
		bx += bw + 8.0
	var qb := Rect2(bx, by, bw, 17)
	UiKit.steel(self, qb)
	UiKit.center_text(self, "ESC - %s" % quit_label, qb.get_center().x, qb.position.y + 6, Gfx.FIRE[5] if qb.has_point(mouse) else Gfx.UI_TEXT, Gfx.OUTLINE)
	_hits.append([qb, "quit"])
	if not has_restart and waiting_text != "":
		var dots: String = ".".repeat(int(Time.get_ticks_msec() / 400) % 4)
		var t: String = waiting_text + dots
		var tw: float = PixelFont.width(waiting_text + "...") + 12.0
		var tr := Rect2(floorf(cx - tw / 2.0), r.end.y + 4, tw, 9)
		UiKit.tape(self, tr, Color("#e8dcc4"))
		PixelFont.draw(self, t, Vector2(tr.position.x + 6, tr.position.y + 2), Gfx.INK)
