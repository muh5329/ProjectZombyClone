extends SceneTree
## Headless test runner.
##
##   godot --headless --path . -s tests/test_runner.gd            # all tests
##   godot --headless --path . -s tests/test_runner.gd -- unit    # one dir
##   godot --headless --path . -s tests/test_runner.gd -- --filter=stamina
##
## Discovers tests/<dir>/test_*.gd, runs every `test_*` method, prints a
## report and exits 0 on success / 1 on failure. Also writes
## tests/output/report.txt so results can be captured as evidence.
##
## scripts/test.sh additionally fails the run if any "SCRIPT ERROR" line
## appears in the engine output (the runner itself cannot observe those).
## A global watchdog aborts the run after WATCHDOG_SECONDS.

const DIRS := ["unit", "integration"]
const WATCHDOG_SECONDS := 900.0

var _total := 0
var _failed := 0
var _report: PackedStringArray = []


func _init() -> void:
	# Autoloads are registered by the engine before scripts run in -s mode?
	# No: with -s the main loop is this SceneTree and autoloads ARE loaded
	# (ProjectSettings autoload list is honoured). We still guard below.
	call_deferred("_run")


func _run() -> void:
	await process_frame
	create_timer(WATCHDOG_SECONDS).timeout.connect(func():
		printerr("TEST WATCHDOG: run exceeded %d s, aborting" % int(WATCHDOG_SECONDS))
		quit(2))
	if not root.has_node("EventBus"):
		_log("WARNING: autoloads not present; tests needing EventBus will fail")

	var args := OS.get_cmdline_user_args()
	var dirs: Array[String] = []
	var filter := ""
	for a in args:
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
		elif DIRS.has(a):
			dirs.append(a)
	if dirs.is_empty():
		dirs.assign(DIRS)

	var start := Time.get_ticks_msec()
	for d in dirs:
		var dir_path := "res://tests/%s" % d
		var da := DirAccess.open(dir_path)
		if da == null:
			continue
		var files := da.get_files()
		files.sort()
		for f in files:
			if f.begins_with("test_") and f.ends_with(".gd"):
				await _run_script("%s/%s" % [dir_path, f], filter)

	var elapsed := (Time.get_ticks_msec() - start) / 1000.0
	var summary := "\n%d tests, %d failed (%.2fs)" % [_total, _failed, elapsed]
	_log(summary)
	_log("RESULT: %s" % ("PASS" if _failed == 0 else "FAIL"))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var fa := FileAccess.open("res://tests/output/report.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(_report))
		fa.close()
	quit(1 if _failed > 0 else 0)


func _run_script(path: String, filter: String) -> void:
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		_log("LOAD FAIL %s (parse/compile error)" % path)
		_failed += 1
		_total += 1
		return
	var methods: Array[String] = []
	for m in script.get_script_method_list():
		if m.name.begins_with("test_") and (filter == "" or m.name.contains(filter) or path.contains(filter)):
			methods.append(m.name)
	if methods.is_empty():
		return
	_log("== %s" % path.get_file())
	for m in methods:
		var tc = script.new()
		tc.tree = self
		_total += 1
		await tc.setup()
		await tc.call(m)
		await tc.teardown()
		if tc._failures.is_empty():
			_log("  ok   %s (%d checks)" % [m, tc._checks])
		else:
			_failed += 1
			_log("  FAIL %s" % m)
			for f in tc._failures:
				_log("       - %s" % f)


func _log(s: String) -> void:
	print(s)
	_report.append(s)
