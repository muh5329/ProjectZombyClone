extends "res://tests/test_case.gd"
## Runs the actual test_ground scene headless and drives the player through
## the PlayerController's scripted mode. Physics runs for real here.
## Timings below assume data/characters/player_stats.tres defaults.

var scene: Node
var player: Character
var ctrl: PlayerController
var cam: IsometricCamera


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	scene.get_node("Zombies").auto_spawn = false  # zombies have their own tests
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	cam = scene.get_node("IsometricCamera")
	ctrl.scripted = true
	# Let the player settle on the floor.
	await physics_frames(10)


func teardown() -> void:
	await despawn(scene)


func _drive(dir: Vector3, mode: MovementComponent.Mode, frames_n: int) -> void:
	ctrl.scripted_direction = dir
	ctrl.scripted_mode = mode
	await physics_frames(frames_n)


func _stamina() -> float:
	return player.stats.get_value(Character.STAMINA)


func test_player_registers_and_lands_on_floor() -> void:
	check_eq(GameManager.player, player, "registered with GameManager")
	check(player.is_on_floor(), "on floor after settling")
	check_near(player.global_position.y, 0.0, 0.05, "resting at ground level")
	check(player.profile != null, "stats profile assigned")
	check_eq(player.stats.get_max(Character.STAMINA), player.profile.stamina_max, "stamina max from profile")


func test_player_reparent_keeps_registration() -> void:
	var holder := Node3D.new()
	scene.add_child(holder)
	player.reparent(holder)
	await physics_frames(2)
	check_eq(GameManager.player, player, "still registered after reparent")
	player.reparent(scene)
	await physics_frames(2)
	check_eq(GameManager.player, player, "still registered after second reparent")
	holder.queue_free()


func test_jog_moves_expected_distance() -> void:
	var start := player.global_position
	await _drive(Vector3.FORWARD, MovementComponent.Mode.JOG, 120)  # 2 s
	var moved := (player.global_position - start).length()
	# ~0.25 s to accelerate, so a bit less than 2 * jog speed.
	check_gt(moved, player.movement.speed_jog * 1.6, "moved a jog's worth")
	check_lt(moved, player.movement.speed_jog * 2.05, "not faster than jog")
	check_eq(player.effective_mode, MovementComponent.Mode.JOG, "mode jog")


func test_jog_is_not_free() -> void:
	var st0 := _stamina()
	await _drive(Vector3.FORWARD, MovementComponent.Mode.JOG, 120)
	check_lt(_stamina(), st0 - 1.5, "jogging 2 s costs stamina")


func test_walk_mode_speed_and_recovery() -> void:
	player.stats.set_value(Character.STAMINA, 60.0)
	var start := player.global_position
	await _drive(Vector3.RIGHT, MovementComponent.Mode.WALK, 60)
	var moved := (player.global_position - start).length()
	check_lt(moved, player.movement.speed_walk * 1.05, "walk speed respected")
	check_gt(moved, player.movement.speed_sneak * 1.0, "faster than sneak")
	check_eq(player.effective_mode, MovementComponent.Mode.WALK, "mode walk")
	check_gt(_stamina(), 60.0, "walking recovers a little")


func test_sprint_is_faster_and_drains_stamina() -> void:
	var st0 := _stamina()
	var start := player.global_position
	await _drive(Vector3.RIGHT, MovementComponent.Mode.SPRINT, 60)
	var moved := (player.global_position - start).length()
	check_gt(moved, player.movement.speed_jog * 1.0, "sprint covers more than jog would")
	check_lt(_stamina(), st0 - 10.0, "stamina drained hard")
	check_eq(player.effective_mode, MovementComponent.Mode.SPRINT, "mode sprint")


func test_exhaustion_blocks_sprint_and_recovers() -> void:
	var got := [false, false]  # array: lambdas capture locals by value
	var cb := func(c, stat, state):
		if c == player and stat == Character.STAMINA and state == &"exhausted":
			got[0] = true
	var denied_cb := func(c):
		if c == player:
			got[1] = true
	EventBus.stat_threshold.connect(cb)
	EventBus.sprint_denied.connect(denied_cb)
	# 100 stamina / 18 per s ≈ 5.6 s. Drive 7 s.
	await _drive(Vector3.BACK, MovementComponent.Mode.SPRINT, 60 * 7)
	check(player.exhausted, "exhausted flag set")
	check(got[0], "EventBus threshold event fired")
	check(got[1], "sprint_denied event fired while holding sprint")
	check(player.sprint_denied, "sprint_denied flag while holding sprint")
	check_eq(player.stats.get_state(Character.STAMINA), &"exhausted", "stat state agrees with flag")
	check_eq(player.effective_mode, MovementComponent.Mode.JOG, "sprint request downgraded to jog")
	check_lt(player.speed(), player.movement.speed_jog * 0.7, "exhausted penalty applied")
	EventBus.stat_threshold.disconnect(cb)
	EventBus.sprint_denied.disconnect(denied_cb)
	# Rest 4 s: idle regen 3.5/s -> ~14 %, still below 40 % exit.
	await _drive(Vector3.ZERO, MovementComponent.Mode.JOG, 60 * 4)
	check(player.exhausted, "still exhausted after only 4 s rest")
	# Rest to ~ 45 %.
	await _drive(Vector3.ZERO, MovementComponent.Mode.JOG, 60 * 9)
	check(not player.exhausted, "recovered after real rest")
	check(not player.movement.speed_modifiers.has(&"exhaustion"), "penalty cleared")
	check_eq(player.stats.get_state(Character.STAMINA), &"normal", "stat state normal")


func test_winded_timer_blocks_sprint_even_if_stamina_restored() -> void:
	await _drive(Vector3.BACK, MovementComponent.Mode.SPRINT, 60 * 7)
	check(player.exhausted, "exhausted")
	player.stats.set_value(Character.STAMINA, 100.0)  # e.g. future item
	await physics_frames(2)
	check(player.exhausted, "winded timer still holds after instant refill")
	check_eq(player.stats.get_state(Character.STAMINA), &"normal", "stat itself is normal")
	await physics_frames(int(player.profile.winded_min_seconds * 60) + 5)
	check(not player.exhausted, "winded timer expired -> can sprint again")


func test_sprint_while_standing_still_does_not_drain() -> void:
	var st0 := _stamina()
	await _drive(Vector3.ZERO, MovementComponent.Mode.SPRINT, 60)
	check(_stamina() >= st0 - 0.001, "no drain when not moving")
	check_eq(player.effective_mode, MovementComponent.Mode.JOG, "not 'sprinting' in place")
	check(not player.sprint_denied, "standing still is not a 'denied' sprint")


func test_sprint_into_wall_costs_little() -> void:
	# Wall at (-6, 0, 2), 8 m wide along X, 0.3 thick along Z. Stand touching it.
	player.global_position = Vector3(-6, 0.1, 2.5)
	await physics_frames(5)
	var st0 := _stamina()
	await _drive(Vector3.FORWARD, MovementComponent.Mode.SPRINT, 120)
	check_gt(player.global_position.z, 2.3, "blocked by wall")
	check_gt(_stamina(), st0 - 8.0, "pinned against a wall does not drain like a real sprint (2 s of sprint = 36)")


func test_partial_input_costs_partial_stamina() -> void:
	var st0 := _stamina()
	await _drive(Vector3.FORWARD * 0.3, MovementComponent.Mode.SPRINT, 60)
	var partial := st0 - _stamina()
	player.stats.set_value(Character.STAMINA, st0)
	await _drive(Vector3.FORWARD, MovementComponent.Mode.SPRINT, 60)
	var full := st0 - _stamina()
	check_lt(partial, full * 0.5, "30 % stick costs well under half a full sprint")
	check_gt(partial, 0.0, "but is not free")


func test_tiny_input_is_deadzone() -> void:
	var start := player.global_position
	await _drive(Vector3.FORWARD * 0.05, MovementComponent.Mode.SPRINT, 60)
	check_eq(player.effective_mode, MovementComponent.Mode.JOG, "no sprint from deadzone input")
	check_lt((player.global_position - start).length(), 0.3, "barely moves")


func test_sneak_is_slow() -> void:
	var start := player.global_position
	await _drive(Vector3.LEFT, MovementComponent.Mode.SNEAK, 60)
	var moved := (player.global_position - start).length()
	check_lt(moved, player.movement.speed_sneak * 1.05, "sneak speed respected")
	check_gt(moved, 0.5, "but did move")


func test_rapid_mode_toggling_is_stable() -> void:
	var modes := [MovementComponent.Mode.SPRINT, MovementComponent.Mode.SNEAK, MovementComponent.Mode.JOG, MovementComponent.Mode.WALK]
	for i in 120:
		ctrl.scripted_direction = Vector3.FORWARD if i % 3 else Vector3.ZERO
		ctrl.scripted_mode = modes[i % 4]
		await tree.physics_frame
	check(player.is_on_floor(), "still grounded")
	check_lt(player.speed(), player.movement.speed_sprint + 0.01, "never exceeded sprint speed")
	check(_stamina() >= 0.0 and _stamina() <= 100.0, "stamina in range")


func test_wall_blocks_player() -> void:
	player.global_position = Vector3(-6, 0.1, 4.0)
	await physics_frames(5)
	await _drive(Vector3.FORWARD, MovementComponent.Mode.SPRINT, 120)
	check_gt(player.global_position.z, 2.3, "stopped in front of wall (z stays > wall face)")
	check_near(player.global_position.y, 0.0, 0.1, "did not climb wall")


func _cam_ground_distance() -> float:
	return (Vector3(cam.global_position.x, 0, cam.global_position.z)
		- Vector3(player.global_position.x, 0, player.global_position.z)).length()


func test_camera_follows_and_rotates() -> void:
	check_lt(_cam_ground_distance(), 0.5, "camera starts on player")
	await _drive(Vector3.RIGHT, MovementComponent.Mode.JOG, 90)
	ctrl.scripted_direction = Vector3.ZERO
	var caught := await wait_until(func(): return _cam_ground_distance() < 0.3, 300)
	check(caught, "camera caught up with player")

	var yaw0 := cam.target_yaw_degrees()
	cam.rotate_step(1)
	check_near(cam.target_yaw_degrees(), fmod(yaw0 + 45.0, 360.0), 0.001, "rotated one step")
	var mid_seen := [false]
	var settled := await wait_until(func():
		var y := rad_to_deg(cam.rotation.y)
		if absf(y - yaw0) > 5.0 and absf(y - cam.target_yaw_degrees()) > 5.0:
			mid_seen[0] = true
		return absf(angle_difference(deg_to_rad(y), deg_to_rad(cam.target_yaw_degrees()))) < deg_to_rad(0.5), 400)
	check(settled, "rotation reached target")
	check(mid_seen[0], "rotation was interpolated, not snapped")
	for i in 8:
		cam.rotate_step(-1)
	check_near(cam.target_yaw_degrees(), fmod(yaw0 + 45.0, 360.0), 0.001, "full circle wraps")
	await frames(5)
	check(absf(cam.rotation.y) <= PI + 0.001, "rotation.y stays wrapped")


func test_camera_zoom_levels_clamp() -> void:
	var z0 := cam.zoom_index
	for i in 20:
		cam.zoom_step(1)
	check_eq(cam.zoom_index, cam.zoom_levels.size() - 1, "clamped at max")
	for i in 20:
		cam.zoom_step(-1)
	check_eq(cam.zoom_index, 0, "clamped at min")
	var ok: bool
	if cam.orthographic:
		check_eq(cam.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "orthographic projection active")
		ok = await wait_until(func(): return absf(cam.camera.size - cam.zoom_levels[0]) < 0.1, 400)
		check(ok, "orthographic size follows level")
		check_gt(cam.camera.position.z, 10.0, "ortho camera sits far back along the arm")
	else:
		ok = await wait_until(func(): return absf(cam.camera.position.z - cam.perspective_zoom_levels[0]) < 0.1, 400)
		check(ok, "camera distance follows level")
	cam.zoom_index = z0


func test_camera_pitch_and_perspective_fallback() -> void:
	check_near(cam.pitch_degrees, 30.0, 0.001, "default elevation is 30° (2:1 dimetric)")
	var c2 := IsometricCamera.new()
	c2.orthographic = false
	scene.add_child(c2)
	await frames(2)
	check_eq(c2.camera.projection, Camera3D.PROJECTION_PERSPECTIVE, "perspective path still works")
	check_near(c2.camera.position.z, c2.perspective_zoom_levels[c2.zoom_index], 0.01, "perspective uses distances")
	c2.queue_free()
	cam.camera.make_current()


func test_camera_survives_bad_config_and_lost_target() -> void:
	var c2 := IsometricCamera.new()
	c2.zoom_levels = []
	c2.yaw_step_degrees = 0.0
	scene.add_child(c2)
	await frames(2)
	check_eq(c2.zoom_levels.size(), 1, "empty zoom levels defaulted")
	check_gt(c2.yaw_step_degrees, 0.0, "zero yaw step defaulted")
	c2.rotate_step(1)  # must not divide by zero
	var t := Node3D.new()
	scene.add_child(t)
	c2.set_target(t)
	await frames(2)
	t.free()  # target gone: camera must not error
	await frames(2)
	c2.set_target(null)
	await frames(2)
	check(true, "no errors with freed / null target")
	c2.queue_free()
	cam.camera.make_current()


func test_movement_is_camera_relative() -> void:
	# With camera yaw 45°, pressing "forward" in the real controller must move
	# the player along (-1,0,-1)/√2. Use the static helper with the live camera.
	var d := PlayerController.camera_relative(Vector2(0, -1), cam.camera)
	check_near(d.x, -0.7071, 0.02, "x")
	check_near(d.z, -0.7071, 0.02, "z")


func test_camera_projection_toggle_at_runtime() -> void:
	cam.orthographic = false
	await frames(60)
	check_eq(cam.camera.projection, Camera3D.PROJECTION_PERSPECTIVE, "perspective after toggle")
	check_near(cam.camera.position.z, cam.perspective_zoom_levels[cam.zoom_index], 0.2, "distance from perspective list")
	cam.orthographic = true
	await frames(60)
	check_eq(cam.camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "orthographic again")
	check_near(cam.camera.size, cam.zoom_levels[cam.zoom_index], 0.2, "size from ortho list")
	check_near(cam.camera.position.z, cam.orthographic_distance, 0.01, "ortho camera back on the arm")
