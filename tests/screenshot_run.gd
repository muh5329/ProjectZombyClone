extends SceneTree
## Plays the main scene with REAL input actions (Input.action_press) and saves
## screenshots to tests/output/. Needs a display (use xvfb-run on CI).
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/screenshot_run.gd
##
## Exit code 1 if anything looks wrong (player didn't move, etc.).

const OUT := "res://tests/output/"

var _problems: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scene: PackedScene = load("res://maps/test_ground.tscn")
	if scene == null:
		printerr("SCREENSHOT_RUN: failed to load main scene")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	await _frames(20)
	var player: Node3D = inst.get_node("Player")
	var cam: Node3D = inst.get_node("IsometricCamera")

	await _shot("01_spawn")

	# Jog forward (W) for 1.5 s using the real action.
	var p0 := player.global_position
	_press(&"move_forward")
	await _frames(90)
	_release(&"move_forward")
	await _frames(10)
	if (player.global_position - p0).length() < 2.0:
		_problems.append("player did not jog forward via input map")
	await _shot("02_after_jog")

	# Rotate the camera twice (Q) and move "forward" again: should be a
	# different world direction (camera-relative).
	var yaw_before: float = cam.target_yaw_degrees()
	await _tap(&"camera_rotate_left")
	await _frames(5)
	await _tap(&"camera_rotate_left")
	await _frames(60)
	if is_equal_approx(cam.target_yaw_degrees(), yaw_before):
		_problems.append("camera did not rotate via input map")
	var p1 := player.global_position
	_press(&"move_forward")
	await _frames(60)
	_release(&"move_forward")
	await _frames(5)
	var d_new := (player.global_position - p1).normalized()
	var d_old := (player.global_position - p0).normalized()
	if d_new.dot(d_old) > 0.7:
		_problems.append("movement not camera-relative after rotation")
	await _shot("03_rotated_camera")

	# Zoom out twice.
	await _tap(&"camera_zoom_out")
	await _frames(5)
	await _tap(&"camera_zoom_out")
	await _frames(60)
	await _shot("04_zoomed_out")

	# Sprint until exhausted (Shift + A; left = away from the house).
	_press(&"sprint")
	_press(&"move_left")
	await _frames(60 * 7)
	if not player.exhausted:
		_problems.append("player did not become exhausted after 7 s sprint")
	await _shot("05_exhausted")
	_release(&"sprint")
	_release(&"move_left")

	# Sneak
	_press(&"sneak")
	_press(&"move_back")
	await _frames(45)
	await _shot("06_sneak")
	_release(&"sneak")
	_release(&"move_back")

	# --- Round 2: house, door, cutaway, window climb -----------------------
	# House A occupies x -14..-4, z -10..-2; front door centre world (-11, -2).
	var occl: Node = inst.get_node("OcclusionManager")
	var house: Node = inst.get_node("Buildings/HouseA")
	# Back to the default heading (45°) and zoom so the framing is canonical.
	await _tap(&"camera_rotate_right")
	await _frames(5)
	await _tap(&"camera_rotate_right")
	await _tap(&"camera_zoom_in")
	await _frames(5)
	await _tap(&"camera_zoom_in")
	player.global_position = Vector3(-11, 0.1, -0.6)
	await _frames(60)
	if not is_equal_approx(cam.target_yaw_degrees(), 45.0):
		_problems.append("camera not back at 45° (got %.0f)" % cam.target_yaw_degrees())
	var interaction: Node = player.get_node("Interaction")
	if interaction.current_target == null:
		_problems.append("no interaction target in front of the front door")
	await _shot("07_door_prompt")
	await _tap(&"interact")
	await _frames(30)
	var front_door: Node = null
	for d in house.doors:
		if (d.global_position - Vector3(-11.45, 0, -2)).length() < 0.2:
			front_door = d
	if front_door == null or not front_door.is_open():
		_problems.append("front door did not open via E")
	# W + D at camera yaw 45° is straight north (-Z): through the doorway.
	_press(&"move_forward")
	_press(&"move_right")
	await _frames(55)
	_release(&"move_forward")
	_release(&"move_right")
	await _frames(30)
	if occl.current_room == null:
		_problems.append("player not detected inside a room after walking through the door (pos %s)" % str(player.global_position))
	var roof_hidden := false
	for r in house.get_roofs():
		roof_hidden = roof_hidden or occl.state_of(r) == &"hidden"
	if not roof_hidden:
		_problems.append("roof not hidden while inside")
	await _shot("08_inside_cutaway")

	# West window of the living room: world (-14, -4). Stand 0.7 m inside.
	player.global_position = Vector3(-13.3, 0.1, -4)
	await _frames(20)
	await _tap(&"interact")  # Open window
	await _frames(25)
	await _shot("09_window_open")
	await _tap(&"interact")  # Climb through
	await _frames(70)
	if player.global_position.x > -14.3:
		_problems.append("player did not end up outside after climbing (x=%.2f)" % player.global_position.x)
	if occl.current_room != null:
		_problems.append("still 'inside' after climbing out")
	await _frames(20)
	await _shot("10_after_climb")

	if _problems.is_empty():
		print("SCREENSHOT_RUN: OK")
		quit(0)
	else:
		for p in _problems:
			printerr("SCREENSHOT_RUN PROBLEM: " + p)
		quit(1)


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _release(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


func _tap(action: StringName) -> void:
	_press(action)
	await process_frame
	_release(action)


## Waits n PHYSICS frames (= n/60 s of game time regardless of render fps).
func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := OUT + name + ".png"
	img.save_png(path)
	print("saved ", path)
