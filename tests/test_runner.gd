extends SceneTree
## Headless test runner.
##
##   godot --headless --path . -s tests/test_runner.gd            # all tests
##   godot --headless --path . -s tests/test_runner.gd -- unit    # one dir
##   godot --headless --path . -s tests/test_runner.gd -- --filter=stamina
##   godot --headless --path . -s tests/test_runner.gd -- integration --shard=1/2
##
## --shard=K/N runs only the K-th of N balanced groups of test FILES
## (greedy by the approximate runtimes in FILE_SECONDS, unknown files
## count DEFAULT_FILE_SECONDS) so a long suite fits a per-call time cap;
## the N shards together run every file exactly once.
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
## Approximate runtimes (s) on the 2-core dev box, for --shard balancing.
const FILE_SECONDS := {
	"test_combat_scene.gd": 170.0, "test_survival_scene.gd": 88.0, "test_zombie_scene.gd": 72.0,
	"test_player_scene.gd": 58.0, "test_sound_scene.gd": 48.0, "test_inventory_scene.gd": 38.0,
	"test_loot_scene.gd": 36.0, "test_house_scene.gd": 32.0, "test_models_scene.gd": 18.0, "test_barricade_scene.gd": 105.0,
	"test_inventory_perf.gd": 3.0, "test_acceptance.gd": 75.0,
	"test_unstaged_1337.gd": 180.0, "test_unstaged_7.gd": 190.0, "test_unstaged_99.gd": 220.0, "test_save_scene.gd": 60.0,
}
const DEFAULT_FILE_SECONDS := 30.0

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
	var shard := 0
	var shards := 1
	for a in args:
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
		elif a.begins_with("--shard="):
			var parts := a.trim_prefix("--shard=").split("/")
			if parts.size() == 2:
				shard = int(parts[0]) - 1
				shards = maxi(int(parts[1]), 1)
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
		var files: Array[String] = []
		for f in da.get_files():
			if f.begins_with("test_") and f.ends_with(".gd"):
				files.append(f)
		files.sort()
		if shards > 1:
			files = shard_files(files, shard, shards)
			_log("== shard %d/%d: %s" % [shard + 1, shards, ", ".join(files)])
		for f in files:
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


## Pure: the files of shard [k] (0-based) of [n], greedy longest-first
## into the currently lightest shard; returned in name order.
static func shard_files(files: Array[String], k: int, n: int) -> Array[String]:
	var sorted := files.duplicate()
	sorted.sort_custom(func(a, b):
		var wa: float = FILE_SECONDS.get(a, DEFAULT_FILE_SECONDS)
		var wb: float = FILE_SECONDS.get(b, DEFAULT_FILE_SECONDS)
		return wa > wb if wa != wb else a < b)
	var load_s: Array[float] = []
	var groups: Array = []
	for i in n:
		load_s.append(0.0)
		groups.append([])
	for f in sorted:
		var best := 0
		for i in n:
			if load_s[i] < load_s[best]:
				best = i
		load_s[best] += float(FILE_SECONDS.get(f, DEFAULT_FILE_SECONDS))
		groups[best].append(f)
	var out: Array[String] = []
	if k >= 0 and k < n:
		out.assign(groups[k])
	out.sort()
	return out


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
