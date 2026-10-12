class_name SpatialHash
extends RefCounted
## Uniform grid over point positions (counting-sort layout, no per-cell arrays).
## Rebuild once per tick; query candidates by circle. Indices refer to the position array
## passed to rebuild(), so the caller must not reorder it between rebuild and query
## (or must accept that indices are stale).

var cell_size: float
var inv_cell: float
var origin: Vector2
var cols: int
var rows: int
## cell_start[c] .. cell_start[c + 1] is the slice of `items` that belongs to cell c.
var cell_start: PackedInt32Array = PackedInt32Array()
var items: PackedInt32Array = PackedInt32Array()
var _item_cell: PackedInt32Array = PackedInt32Array()
var _fill: PackedInt32Array = PackedInt32Array()


func _init(p_bounds: Rect2, p_cell_size: float) -> void:
	cell_size = p_cell_size
	inv_cell = 1.0 / p_cell_size
	origin = p_bounds.position
	cols = maxi(1, ceili(p_bounds.size.x * inv_cell))
	rows = maxi(1, ceili(p_bounds.size.y * inv_cell))
	cell_start.resize(cols * rows + 1)
	_fill.resize(cols * rows)


func cell_index(p: Vector2) -> int:
	var cx: int = clampi(int((p.x - origin.x) * inv_cell), 0, cols - 1)
	var cy: int = clampi(int((p.y - origin.y) * inv_cell), 0, rows - 1)
	return cy * cols + cx


func rebuild(positions: PackedVector2Array, count: int) -> void:
	var ncell: int = cols * rows
	cell_start.fill(0)
	if _item_cell.size() < count:
		_item_cell.resize(count)
	if items.size() != count:
		items.resize(count)
	for i in count:
		var c: int = cell_index(positions[i])
		_item_cell[i] = c
		cell_start[c + 1] += 1
	for c in ncell:
		cell_start[c + 1] += cell_start[c]
	for c in ncell:
		_fill[c] = cell_start[c]
	for i in count:
		var c: int = _item_cell[i]
		items[_fill[c]] = i
		_fill[c] += 1


## Writes indices of points within `radius` of `center` (using the CURRENT `positions`)
## into out[0..n) and returns n. `margin` widens the cell coverage to tolerate points
## that moved since the last rebuild. `out` is grown if needed.
func query_circle(center: Vector2, radius: float, positions: PackedVector2Array, out: PackedInt32Array, margin: float = 0.0) -> int:
	if out.size() < items.size():
		out.resize(items.size())
	var reach: float = radius + margin
	var x0: int = clampi(int((center.x - reach - origin.x) * inv_cell), 0, cols - 1)
	var x1: int = clampi(int((center.x + reach - origin.x) * inv_cell), 0, cols - 1)
	var y0: int = clampi(int((center.y - reach - origin.y) * inv_cell), 0, rows - 1)
	var y1: int = clampi(int((center.y + reach - origin.y) * inv_cell), 0, rows - 1)
	var r2: float = radius * radius
	var n: int = 0
	for gy in range(y0, y1 + 1):
		var row: int = gy * cols
		for gx in range(x0, x1 + 1):
			var c: int = row + gx
			for s in range(cell_start[c], cell_start[c + 1]):
				var j: int = items[s]
				if center.distance_squared_to(positions[j]) <= r2:
					out[n] = j
					n += 1
	return n
