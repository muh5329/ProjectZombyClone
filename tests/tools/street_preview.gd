extends SceneTree
## Dev tool: loads test_ground and captures the street (vehicles) to
## tests/output/preview_street.png.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/tools/street_preview.gd -- [x z zoom yaw hour]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var x := float(a[0]) if a.size() > 0 else 0.0
	var z := float(a[1]) if a.size() > 1 else 24.0
	var zoom := float(a[2]) if a.size() > 2 else 20.0
	var yaw := float(a[3]) if a.size() > 3 else 45.0
	var hour := float(a[4]) if a.size() > 4 else 11.0
	var inst: Node = load("res://maps/test_ground.tscn").instantiate()
	inst.get_node("Zombies").auto_spawn = false
	root.add_child(inst)
	root.get_node("TimeManager").set_time_of_day(hour)
	var player: Node3D = inst.get_node("Player")
	player.global_position = Vector3(x, 0.1, z)
	player.get_node("Controller").scripted = true
	var cam = inst.get_node("IsometricCamera")
	for i in 5:
		await process_frame
	var sp = inst.get_node("Zombies")
	for i in 6:
		sp.spawn_at(Vector3(x - 3 + i * 1.2, 0, z - 4 + (i % 2)))
	var zl: Array[float] = [zoom, zoom, zoom, zoom]
	cam.zoom_levels = zl
	cam.rotate_step(int(round((yaw - 45.0) / 45.0)))
	for i in 40:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("res://tests/output/preview_street.png")
	print("saved")
	quit(0)
