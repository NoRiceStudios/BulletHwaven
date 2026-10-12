class_name Hud
extends Control
## Minimal pixel HUD in the mock-up style: riveted plates, 3x5 font, player-colour hp bar.

var world: SimWorld = null
var local_peer: int = 1
var _plate: StyleBoxTexture


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate = StyleBoxTexture.new()
	_plate.texture = Gfx.TEX_UI_PLATE
	_plate.set_texture_margin_all(4)
	_plate.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	_plate.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var vs: Vector2 = get_viewport_rect().size
	var w: float = vs.x
	var h: float = vs.y
	var v: SimVehicle = world.get_vehicle_for_peer(local_peer)
	var secs: int = world.tick / SimWorld.TICK_RATE
	var clock := "%d:%02d" % [secs / 60, secs % 60]

	# top left: own rig
	draw_style_box(_plate, Rect2(6, 6, 104, 34))
	PixelFont.draw(self, "SCRAP %d" % (v.scrap if v else 0), Vector2(12, 11), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	PixelFont.draw(self, clock, Vector2(104 - PixelFont.width(clock), 11), Gfx.FIRE[4], Gfx.UI_SHADOW)
	PixelFont.draw(self, "HP", Vector2(12, 20), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	draw_rect(Rect2(24, 20, 80, 5), Gfx.OUTLINE)
	if v != null:
		var frac: float = clampf(v.hp / v.max_hp, 0.0, 1.0) if v.alive else 0.0
		var col: Color = Gfx.PLAYER_COLORS[Gfx.player_index(v)]
		var fill: float = floorf(78.0 * frac)
		if fill > 0.0:
			draw_rect(Rect2(25, 21, fill, 3), col)
			draw_rect(Rect2(25, 21, fill, 1), col.lightened(0.25))
	PixelFont.draw(self, "KILLS %d" % (v.kills if v else 0), Vector2(12, 29), Gfx.UI_TEXT, Gfx.UI_SHADOW)
	if v != null and not v.alive:
		var msg := "RIG DESTROYED"
		PixelFont.draw(self, msg, Vector2(floorf((w - PixelFont.width(msg)) / 2.0), floorf(h / 2.0) - 30), Gfx.FIRE[4], Gfx.OUTLINE)

	# top right: the hive
	var l1 := "HIVE: %d ALIVE" % world.enemy_count
	var l2 := "TICK %d" % world.tick
	var pw: float = maxf(PixelFont.width(l1), PixelFont.width(l2)) + 14.0
	draw_style_box(_plate, Rect2(w - pw - 6, 6, pw, 25))
	PixelFont.draw(self, l1, Vector2(w - pw + 1, 11), Gfx.GLOW[3], Gfx.UI_SHADOW)
	PixelFont.draw(self, l2, Vector2(w - pw + 1, 20), Gfx.UI_TEXT, Gfx.UI_SHADOW)

	# bottom left: doctrine
	if v != null:
		var doc := "DOCTRINE: %s  /  TARGET: %s" % [str(v.doctrine["drive"]), str(v.doctrine["target"]).replace("_", " ")]
		var dw: float = PixelFont.width(doc) + 14.0
		draw_style_box(_plate, Rect2(6, h - 22, dw, 16))
		PixelFont.draw(self, doc, Vector2(13, h - 16), Gfx.UI_TEXT, Gfx.UI_SHADOW)
