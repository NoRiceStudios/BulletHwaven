extends SceneTree
## Dev tool: times WorldView's per-frame update on a scenario (render work only, no GPU).
##   godot --headless --path game -s res://tools/bench_render.gd -- --scenario=horde --ticks=150


var _view: WorldView
var _world: SimWorld
var _scenario: String = "horde"
var _frame: int = 0


func _initialize() -> void:
	var args: Dictionary = {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	_scenario = args.get("scenario", "horde")
	_world = Scenarios.build(_scenario, int(args.get("seed", "1")))
	for i in int(args.get("ticks", "150")):
		Scenarios.step(_scenario, _world)
	_view = WorldView.new()
	root.add_child(_view)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let _ready run first
	_view.set_world(_world, 1)
	var frames: int = 120
	var t0: int = Time.get_ticks_usec()
	for i in frames:
		_view._process(1.0 / 60.0)
	var per: float = float(Time.get_ticks_usec() - t0) / frames / 1000.0
	print("BENCH %s: %d enemies, %d projectiles, %.2f ms per WorldView update" % [_scenario, _world.enemy_count, _world.proj_count, per])
	return true
