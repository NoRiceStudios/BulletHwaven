extends TestCase
## Minimap geometry: fits any arena size inside MAX_INNER, keeps the aspect, maps corners to corners.


func test_inner_size_fits_any_arena() -> void:
	for a: Rect2 in [Rect2(0, 0, 1280, 720), Rect2(0, 0, 3840, 2160), Rect2(0, 0, 4000, 4000), Rect2(-500, -200, 6000, 1500)]:
		var s: Vector2 = Minimap.inner_size(a)
		assert_true(s.x <= Minimap.MAX_INNER.x and s.y <= Minimap.MAX_INNER.y, "fits for %s" % a)
		assert_true(absf(s.x / s.y - a.size.x / a.size.y) < 0.1, "aspect kept for %s" % a)
		assert_true(s.x == Minimap.MAX_INNER.x or s.y == Minimap.MAX_INNER.y, "uses the space for %s" % a)


func test_corners_map_to_corners() -> void:
	var a := Rect2(-500, -200, 6000, 1500)
	var inner := Rect2(Vector2(10, 20), Minimap.inner_size(a))
	assert_eq(Minimap.to_map(a.position, a, inner), inner.position)
	assert_eq(Minimap.to_map(a.end, a, inner), inner.end - Vector2.ONE)
	assert_eq(Minimap.to_map(a.end + Vector2(999, 999), a, inner), inner.end - Vector2.ONE)


func test_frame_in_bottom_right_corner() -> void:
	var vs := Vector2(640, 360)
	var r: Rect2 = Minimap.frame_rect(vs)
	assert_eq(r.end, vs - Vector2(Minimap.MARGIN, Minimap.MARGIN))
	assert_true(Rect2(Vector2.ZERO, vs).encloses(r))


func test_from_map_inverts_to_map() -> void:
	var a := Rect2(0, 0, 3840, 2160)
	var inner := Rect2(Vector2(500, 280), Minimap.inner_size(a))
	for p: Vector2 in [Vector2(10, 10), Vector2(1900, 1000), Vector2(3800, 2100)]:
		var back: Vector2 = Minimap.from_map(Minimap.to_map(p, a, inner), a, inner)
		assert_lt(back.distance_to(p), a.size.x / inner.size.x * 2.0, "round trip of %s" % p)
