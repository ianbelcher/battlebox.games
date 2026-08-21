extends SceneTree
## The unit test runner.
##
##   godot --headless --path game --script res://tests/run_tests.gd
##
## Discovers every tests/unit/*.gd, runs each method named `test_*`, and
## exits non-zero if any assertion failed — which is what makes it useful
## in CI. Pass a substring as WORLD_TEST_FILTER to run a subset while
## working on one thing.
##
## Tests get the real project: autoloads are NOT loaded (a --script run has
## no autoloads), so anything under test must be reachable as a class_name
## or a preload. That is a design constraint worth keeping — code that can
## only run with four singletons alive is code that cannot be tested.

const UNIT_DIR := "res://tests/unit"

func _init() -> void:
	var filter := OS.get_environment("WORLD_TEST_FILTER")
	var files := _discover(UNIT_DIR)
	if files.is_empty():
		push_error("No tests found under %s" % UNIT_DIR)
		quit(1)
		return
	var total_checks := 0
	var total_tests := 0
	var failed_tests := 0
	var report: Array[String] = []
	var started := Time.get_ticks_msec()

	for path: String in files:
		var script: GDScript = load(path)
		if script == null:
			report.append("  ✗ %s failed to load" % path)
			failed_tests += 1
			continue
		var suite := path.get_file().get_basename()
		for method: Dictionary in script.get_script_method_list():
			var name := str(method.name)
			if not name.begins_with("test_"):
				continue
			if not filter.is_empty() and not (suite + "." + name).contains(filter):
				continue
			total_tests += 1
			var case: TestCase = script.new()
			case.before_each()
			case.call(name)
			case.after_each()
			total_checks += case.checks
			if case.failures.is_empty():
				print("  ✓ %s.%s (%d checks)" % [suite, name, case.checks])
			else:
				failed_tests += 1
				print("  ✗ %s.%s" % [suite, name])
				for failure: String in case.failures:
					print("      %s" % failure)

	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	print("")
	if failed_tests == 0:
		print("%d tests, %d checks, all passing (%.1fs)"
			% [total_tests, total_checks, elapsed])
		quit(0)
	else:
		printerr("%d of %d tests FAILED (%d checks, %.1fs)"
			% [failed_tests, total_tests, total_checks, elapsed])
		quit(1)

func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		# Exported builds rename .gd to .gdc/.remap; accept both so this
		# runner is not quietly source-only.
		var name := file.replace(".remap", "")
		if name.ends_with(".gd"):
			found.append("%s/%s" % [dir_path, name])
	found.sort()
	return found
