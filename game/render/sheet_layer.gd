class_name SheetLayer
extends Node2D
## Draws many copies of one sprite sheet with a single MultiMesh: optional drop shadow pass,
## the sprites themselves and an optional additive glow pass all share the same instance data.
## Usage per frame: begin(), add(pos, frame, row) for every instance, finish(). `flash` (0..1) whitens
## one instance for a frame (aliens taking a hit; the shadow and glow passes ignore it).

var _mm: MultiMesh
var _count: int = 0
var _nodes: Array[MultiMeshInstance2D] = []


func setup(tex: Texture2D, cols: int, rows: int, z: int, glow_tex: Texture2D = null,
		shadow_offset: Vector2 = Vector2.ZERO, glow_intensity: float = 1.0, shadow_alpha: float = 0.45) -> void:
	var cell := Vector2(tex.get_width() / cols, tex.get_height() / rows)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_2D
	_mm.use_custom_data = true
	_mm.mesh = Gfx.quad_mesh(cell)
	_mm.instance_count = 64
	_mm.visible_instance_count = 0
	if shadow_offset != Vector2.ZERO:
		var sh := ShaderMaterial.new()
		sh.shader = Gfx.SHEET_SHADER
		sh.set_shader_parameter("frames", cols)
		sh.set_shader_parameter("rows", rows)
		sh.set_shader_parameter("shadow", true)
		sh.set_shader_parameter("shadow_color", Color(0.184, 0.165, 0.239, shadow_alpha))
		_add_node(tex, sh, Gfx.Z_SHADOWS, shadow_offset)
	var body := ShaderMaterial.new()
	body.shader = Gfx.SHEET_SHADER
	body.set_shader_parameter("frames", cols)
	body.set_shader_parameter("rows", rows)
	_add_node(tex, body, z, Vector2.ZERO)
	if glow_tex != null:
		var gl := ShaderMaterial.new()
		gl.shader = Gfx.SHEET_ADD_SHADER
		gl.set_shader_parameter("frames", cols)
		gl.set_shader_parameter("rows", rows)
		gl.set_shader_parameter("intensity", glow_intensity)
		_add_node(glow_tex, gl, Gfx.Z_GLOW, Vector2.ZERO)


func _add_node(tex: Texture2D, mat: ShaderMaterial, z: int, offset: Vector2) -> void:
	var n := MultiMeshInstance2D.new()
	n.multimesh = _mm
	n.texture = tex
	n.material = mat
	n.z_index = z
	n.position = offset
	add_child(n)
	_nodes.append(n)


## `expected` (optional) pre-sizes the buffer for this frame's instance count.
func begin(expected: int = 0) -> void:
	_count = 0
	if expected > _mm.instance_count:
		_mm.instance_count = nearest_po2(expected)


func add(pos: Vector2, frame: int, row: int = 0, flash: float = 0.0) -> void:
	if _count >= _mm.instance_count:
		_grow(_count * 2)
	_mm.set_instance_transform_2d(_count, Transform2D(0.0, Gfx.snap(pos)))
	_mm.set_instance_custom_data(_count, Color(float(frame), float(row), flash, 0.0))
	_count += 1


func finish() -> void:
	_mm.visible_instance_count = _count


func _grow(n: int) -> void:
	# Resizing clears the buffer, so keep what this frame already wrote.
	var keep: Array = []
	for i in _count:
		keep.append([_mm.get_instance_transform_2d(i), _mm.get_instance_custom_data(i)])
	_mm.instance_count = n
	for i in keep.size():
		_mm.set_instance_transform_2d(i, keep[i][0])
		_mm.set_instance_custom_data(i, keep[i][1])
