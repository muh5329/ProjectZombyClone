extends SceneTree
## Dev tool: renders a lineup of procedural people / zombies / vehicles to
## tests/output/preview_*.png (not part of the suite).
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/tools/model_preview.gd -- [zoom] [anim]

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var zoom := float(args[0]) if args.size() > 0 else 6.0
	var clip := StringName(args[1]) if args.size() > 1 else &""
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.52, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.environment.ambient_light_energy = 0.35
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.55, 0.35)
	pm.material = gm
	ground.mesh = pm
	world.add_child(ground)
	await process_frame
	var assets = root.get_node("CharacterAssets") if root.has_node("CharacterAssets") else null
	var outfits: Array = load("res://characters/models/character_assets.gd").of(self).outfits
	var i := 0
	for o in outfits:
		var m = load("res://characters/models/character_model.gd").new()
		world.add_child(m)
		var a = load("res://characters/models/appearance.gd").random(i * 31 + 5, [o], false)
		m.setup(a)
		m.position = Vector3((i % 7) * 0.9 - 2.7, 0, -float(i / 7) * 1.4)
		m.play(clip if clip != &"" else &"idle", 0.0)
		m.advance(0.4)
		i += 1
	for k in 7:
		var m = load("res://characters/models/character_model.gd").new()
		world.add_child(m)
		m.setup(load("res://characters/models/character_assets.gd").of(self).zombie_appearance(k * 5 + 1))
		m.position = Vector3(k * 0.9 - 2.7, 0, 1.6)
		m.play(&"z_walk" if clip == &"" else clip, 0.0)
		m.advance(0.3 + k * 0.2)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom
	var pivot := Node3D.new()
	world.add_child(pivot)
	pivot.rotation_degrees = Vector3(0, 45 if args.size() < 3 else float(args[2]), 0)
	var arm := Node3D.new()
	pivot.add_child(arm)
	arm.rotation_degrees = Vector3(-30, 0, 0)
	arm.add_child(cam)
	cam.position = Vector3(0, 0, 45)
	cam.far = 200
	pivot.position = Vector3(0, 0.8, 0)
	cam.current = true
	for f in 10:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://tests/output/preview_models.png")
	print("saved")
	quit(0)
