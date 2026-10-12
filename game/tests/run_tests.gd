extends SceneTree
## Headless test runner: godot --headless --path game -s res://tests/run_tests.gd
## Discovers res://tests/test_*.gd (except test_case.gd), runs every `test_*` method and
## exits with code 1 if anything failed.

const TESTS_DIR := "res://tests"


func _init() -> void:
	var files: PackedStringArray = []
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		printerr("cannot open %s" % TESTS_DIR)
		quit(1)
		return
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
	files.sort()

	var total: int = 0
	var failed: int = 0
	var asserts: int = 0
	for f in files:
		var script: GDScript = load("%s/%s" % [TESTS_DIR, f])
		if script == null:
			printerr("FAIL  %s: failed to load" % f)
			failed += 1
			total += 1
			continue
		var names: Array[String] = []
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_"):
				names.append(mname)
		names.sort()
		for mname in names:
			var t: TestCase = script.new()
			t.current_test = "%s::%s" % [f, mname]
			var t0: int = Time.get_ticks_usec()
			t.call(mname)
			var ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
			total += 1
			asserts += t.assertion_count
			if t.failures.is_empty():
				print("PASS  %s::%s (%.0f ms)" % [f, mname, ms])
			else:
				failed += 1
				print("FAIL  %s::%s" % [f, mname])
				for msg in t.failures:
					print("      " + msg)
	print("---- %d tests, %d assertions, %d failed" % [total, asserts, failed])
	quit(1 if failed > 0 else 0)
