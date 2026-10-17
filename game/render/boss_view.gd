class_name BossView
extends Node2D
## PLACEHOLDER boss visuals (simple polygons) plus the telegraph markers. A later art pass replaces `_draw_body`;
## the markers (`_draw_marks`) are the real read of the telegraphs and can be restyled in place.
## Reads the world only: boss bodies are enemies of kind >= SimWorld.BOSS_A (positions come from the WorldView's
## smoothed enemy positions), markers are `world.boss_marks` (Bosses.MARK_*).

var view: WorldView
var world: SimWorld


func _ready() -> void:
	z_index = Gfx.Z_ENEMIES + 1


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if view == null or view.world == null:
		return
	world = view.world
	_draw_marks()
	for i in world.enemy_count:
		var kind: int = world.enemy_kind[i]
		if kind < SimWorld.BOSS_A or world.enemy_hp[i] <= 0.0:
			continue
		var pos: Vector2 = Vector2(world.enemy_pos[i])
		var disp: Variant = view._enemy_disp.get(world.enemy_id[i])
		if disp != null:
			pos = Vector2((disp as Vector3).x, (disp as Vector3).y)
		pos = Gfx.snap(pos)
		var frac: float = world.enemy_hp[i] / maxf(world.enemy_max_hp_of(i), 1.0)
		var mode: int = _mode_of(world.enemy_id[i])
		_draw_body(kind, pos, frac, mode)


## Host only: the attack state of the body (Bosses.M_*); clients see 0.
func _mode_of(id: int) -> int:
	var st: Dictionary = world.boss_ents.get(id, {})
	return int(st.get("mode", 0))


func _draw_body(kind: int, p: Vector2, frac: float, mode: int) -> void:
	var r: float = SimWorld.ENEMY_RADIUS[kind]
	var t: float = float(world.tick)
	var rim: Color = Gfx.OUTLINE
	var flash: float = 0.5 + 0.5 * sin(t * 0.35)
	draw_circle(p + Vector2(4, 6), r, Color(0.18, 0.165, 0.24, 0.45))  # shadow
	if kind == SimWorld.BOSS_A:
		# Tripod Queen: three splayed legs, a domed body, a glowing core that brightens as she is hurt
		for k in 3:
			var a: float = TAU * float(k) / 3.0 + 0.5 + sin(t * 0.07 + float(k)) * 0.06
			var knee: Vector2 = p + Vector2.from_angle(a) * r * 1.1
			var foot: Vector2 = p + Vector2.from_angle(a + 0.25) * r * 1.55
			draw_line(p, knee, rim, 7.0)
			draw_line(knee, foot, rim, 7.0)
			draw_line(p, knee, Gfx.SAND[1], 5.0)
			draw_line(knee, foot, Gfx.SAND[1], 5.0)
		draw_circle(p, r * 0.82, rim)
		draw_circle(p, r * 0.74, Gfx.SAND[2])
		draw_circle(p + Vector2(-5, -6), r * 0.5, Gfx.SAND[3])
		var core: Color = Gfx.GLOW[3].lerp(Gfx.GLOW[5], flash * (1.0 - frac))
		draw_circle(p, r * 0.26, rim)
		draw_circle(p, r * 0.2, core)
		return
	# Shard Colossus and its shards: a faceted crystal brute
	var pts := PackedVector2Array()
	var n: int = 9
	for k in n:
		var a2: float = TAU * float(k) / float(n)
		var rr: float = r * (1.0 if k % 2 == 0 else 0.72) + (3.0 if k % 3 == 0 else 0.0)
		pts.append(p + Vector2.from_angle(a2) * rr)
	var fill: Color = Gfx.SAND[2].lerp(Gfx.GLOW[2], 0.25)
	draw_colored_polygon(pts, fill)
	var closed := PackedVector2Array(pts)
	closed.append(pts[0])
	draw_polyline(closed, rim, 2.0)
	for k in n:
		if k % 2 == 0:
			draw_line(p, pts[k], Color(Gfx.SAND[4], 0.55), 1.0)
	var glow: Color = Gfx.GLOW[3 if mode != 1 else 5]
	if kind == SimWorld.BOSS_B:
		draw_circle(p, r * 0.3, rim)
		draw_circle(p, r * 0.24, glow.lerp(Gfx.GLOW[5], flash * (1.0 - frac)))
	else:
		draw_circle(p, r * 0.3, glow)


func _draw_marks() -> void:
	for m: Dictionary in world.boss_marks:
		var total: float = maxf(float(m["total"]), 1.0)
		var done: float = 1.0 - float(m["left"]) / total
		var pos: Vector2 = m["pos"]
		var r: float = float(m["r"])
		var pulse: float = 0.5 + 0.5 * sin(float(world.tick) * 0.6)
		match int(m["k"]):
			Bosses.MARK_SHELL:  # impact circle: outline, fill grows toward the edge
				draw_circle(pos, r, Color(Gfx.GLOW[2], 0.10 + 0.10 * pulse))
				draw_circle(pos, r * done, Color(Gfx.GLOW[3], 0.22))
				draw_arc(pos, r, 0.0, TAU, 40, Color(Gfx.GLOW[4], 0.55 + 0.35 * pulse), 1.5)
				draw_line(pos + Vector2(-4, 0), pos + Vector2(4, 0), Gfx.GLOW[5], 1.0)
				draw_line(pos + Vector2(0, -4), pos + Vector2(0, 4), Gfx.GLOW[5], 1.0)
			Bosses.MARK_RING:  # the boss glows before it fires a ring of shards
				draw_circle(pos, r + 6.0 * done, Color(Gfx.GLOW[4], 0.15 + 0.35 * done))
				draw_arc(pos, r + 10.0 * done, 0.0, TAU, 32, Color(Gfx.GLOW[5], 0.4 + 0.5 * pulse), 2.0)
			Bosses.MARK_CHARGE:  # lane the boss will charge along
				var p2: Vector2 = m["pos2"]
				var dir: Vector2 = (p2 - pos).normalized()
				var side := Vector2(-dir.y, dir.x) * r
				var quad := PackedVector2Array([pos + side, p2 + side, p2 - side, pos - side])
				draw_colored_polygon(quad, Color(Gfx.GLOW[2], 0.14 + 0.16 * done))
				draw_polyline(PackedVector2Array([pos + side, p2 + side, p2 - side, pos - side, pos + side]), Color(Gfx.GLOW[4], 0.4 + 0.4 * pulse), 1.5)
