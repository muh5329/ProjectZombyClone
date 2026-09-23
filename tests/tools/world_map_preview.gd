extends SceneTree
## Dev / evidence tool (Round 11): generates the world layout for three
## seeds and renders them side by side to tests/output/37_world_map.png
## (plus one PNG per seed). Headless:
##   godot --headless --path . -s tests/tools/world_map_preview.gd -- [seed1 seed2 seed3] [--mpp=1.5]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var seeds: Array[int] = []
	var mpp := 1.5
	var crop := Rect2()
	var wsize := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			wsize = float(a.trim_prefix("--size="))
		if a.begins_with("--crop="):
			var c := a.trim_prefix("--crop=").split(",")
			crop = Rect2(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
		elif a.begins_with("--mpp="):
			mpp = float(a.trim_prefix("--mpp="))
		elif a.is_valid_int():
			seeds.append(int(a))
	if seeds.is_empty():
		seeds = [1337, 7, 99]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/output"))
	var gen: GDScript = load("res://worldgen/world_generator.gd")
	var ren: GDScript = load("res://worldgen/world_map_renderer.gd")
	var images: Array = []
	for s in seeds:
		var t0 := Time.get_ticks_msec()
		var prm = gen.default_params().duplicate()
		if wsize > 0.0:
			prm.world_size = Vector2(wsize, wsize)
		var layout = gen.generate(s, prm)
		var t1 := Time.get_ticks_msec()
		var img: Image = ren.render(layout, mpp)
		var t2 := Time.get_ticks_msec()
		if crop.size != Vector2.ZERO:
			var ci := Rect2i(int(crop.position.x / mpp), int(crop.position.y / mpp), int(crop.size.x / mpp), int(crop.size.y / mpp))
			img.get_region(ci).save_png("res://tests/output/world_map_crop_%d.png" % s)
			images.append(img)
			continue
		img.save_png("res://tests/output/world_map_seed_%d.png" % s)
		images.append(img)
		var kinds := {}
		for b in layout.buildings:
			kinds[String(b.kind)] = int(kinds.get(String(b.kind), 0)) + 1
		print("seed %d: layout %d ms (%s), render %d ms, buildings %d %s, lots %d, roads %d, trees %d, fields %d, fences %d, vehicles %d, zombies %d, spawn %s" % [
			s, t1 - t0, str(layout.stats), t2 - t1, layout.buildings.size(), str(kinds), layout.lots.size(), layout.roads.size(),
			layout.tree_count(), layout.fields.size(), layout.fences.size(), layout.vehicles.size(), layout.zombies.size(),
			layout.spawn_building])
		print("  zones %s  hash %s" % [str(layout.zone_ratios()), layout.layout_hash().substr(0, 16)])
	if crop.size != Vector2.ZERO:
		quit(0)
		return
	var out: Image = ren.side_by_side(images)
	out.save_png("res://tests/output/37_world_map.png")
	print("saved res://tests/output/37_world_map.png")
	quit(0)
