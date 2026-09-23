extends SceneTree
## Dev tool (Round 11): loads maps/world.tscn headless and reports load
## timings, node counts, nav bake, zombies and where the player starts.
##   godot --headless --path . -s tests/tools/world_probe.gd -- [seed]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var s := int(a[0]) if a.size() > 0 else 1337
	var sm = root.get_node("SaveManager")
	var t0 := Time.get_ticks_msec()
	var map: Node = sm.instantiate_new_game("res://maps/world.tscn", s)
	root.add_child(map)
	var t1 := Time.get_ticks_msec()
	print("add_child (generate + build) %d ms" % (t1 - t0))
	var nav = map.get_node("NavRegion")
	var frames := 0
	while not nav.baked and frames < 3000:
		await physics_frame
		frames += 1
	var t2 := Time.get_ticks_msec()
	print("nav baked after %d ms (%d frames), regions %d, bake_ms %.0f" % [t2 - t1, frames, nav.regions.size(), nav.bake_ms])
	for i in 30:
		await physics_frame
	var sp = map.get_node("Zombies")
	var player: Node3D = map.get_node("Player")
	var loc = load("res://buildings/building.gd").locate(self, player.global_position)
	print("zombies %d, player at %s in %s / %s" % [sp.zombies.size(), player.global_position,
		loc.building.name if loc.building else "-", loc.room.room_name if loc.room else "-"])
	var total := 0
	var q := [root]
	while not q.is_empty():
		var n: Node = q.pop_back()
		total += 1
		q.append_array(n.get_children())
	print("total nodes %d" % total)
	var r: Dictionary = sm.save_game("world probe", map)
	print("save %.0f ms, %d bytes" % [r.get("ms", -1.0), r.get("bytes", 0)])
	var t3 := Time.get_ticks_msec()
	var lr: Dictionary = await sm.load_game("world probe", map)
	print("load ok=%s %.0f ms (wall %d ms)" % [str(lr.ok), lr.get("ms", -1.0), Time.get_ticks_msec() - t3])
	sm.delete_slot("world probe")
	quit(0)
