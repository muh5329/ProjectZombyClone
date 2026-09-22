extends "res://tests/test_case.gd"

const ControllerScript = preload("res://player/player_controller.gd")


func _cam(yaw_deg: float) -> Camera3D:
	var c := Camera3D.new()
	c.rotation_degrees = Vector3(-52.0, yaw_deg, 0.0)
	# Camera3D needs a tree for global_basis; add under root temporarily.
	tree.root.add_child(c)
	return c


func test_forward_is_away_from_camera_yaw0() -> void:
	var c := _cam(0.0)
	var d := PlayerController.camera_relative(Vector2(0, -1), c)
	check_near(d.x, 0.0, 0.001, "x")
	check_near(d.z, -1.0, 0.001, "forward = -Z when camera yaw 0")
	c.free()


func test_forward_rotates_with_camera() -> void:
	var c := _cam(90.0)
	var d := PlayerController.camera_relative(Vector2(0, -1), c)
	check_near(d.x, -1.0, 0.001, "yaw 90 -> forward is -X")
	check_near(d.z, 0.0, 0.001, "z")
	var r := PlayerController.camera_relative(Vector2(1, 0), c)
	check_near(r.z, -1.0, 0.001, "right at yaw 90 is -Z")
	c.free()


func test_isometric_45_diagonal() -> void:
	var c := _cam(45.0)
	var d := PlayerController.camera_relative(Vector2(0, -1), c)
	check_near(d.length(), 1.0, 0.001, "unit")
	check_near(d.x, -0.7071, 0.01, "x")
	check_near(d.z, -0.7071, 0.01, "z")
	c.free()


func test_no_camera_falls_back() -> void:
	var d := PlayerController.camera_relative(Vector2(0, -1), null)
	check_near(d.z, -1.0, 0.001, "default forward")


func test_no_input_is_zero() -> void:
	var c := _cam(45.0)
	check_eq(PlayerController.camera_relative(Vector2.ZERO, c), Vector3.ZERO, "zero")
	c.free()
