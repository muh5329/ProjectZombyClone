extends SceneTree
## Dev tool (Round 11): runs WorldLayoutValidator on N seeds and prints
## problems grouped by kind.
##   godot --headless --path . -s tests/tools/world_validate.gd -- [first_seed] [count] [--plans] [--size=768]
## (scripts/worldgen_sweep.sh runs it on 200 seeds; exit 1 on any problem.)

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var first := int(a[0]) if a.size() > 0 else 1
	var n := int(a[1]) if a.size() > 1 else 10
	var gen: GDScript = load("res://worldgen/world_generator.gd")
	var prm: WorldGenParams = gen.default_params().duplicate()
	for arg in a:
		if arg.begins_with("--size="):
			var sz := float(arg.trim_prefix("--size="))
			prm.world_size = Vector2(sz, sz)
	var val: GDScript = load("res://worldgen/world_layout_validator.gd")
	var total := 0
	var full := OS.get_cmdline_user_args().has("--plans")
	var t_all := Time.get_ticks_msec()
	var worst := 0.0
	for s in range(first, first + n):
		var layout = gen.generate_fresh(s, prm)
		var t1 := Time.get_ticks_msec()
		var probs: Array = val.all_problems(layout) if full else val.layout_problems(layout)
		total += probs.size()
		worst = maxf(worst, layout.stats.total_ms)
		if probs.size() > 0 or not a.has("--quiet"):
			print("seed %d: %d problems (gen %.0f ms, validate %d ms)" % [s, probs.size(), layout.stats.total_ms, Time.get_ticks_msec() - t1])
		for i in mini(probs.size(), 12):
			print("   ", probs[i])
	print("TOTAL %d problems on %d seeds (%.1f s, slowest layout %.0f ms)" % [total, n, (Time.get_ticks_msec() - t_all) / 1000.0, worst])
	quit(1 if total > 0 else 0)
