extends "res://tests/test_case.gd"

const MovementScript = preload("res://characters/movement_component.gd")


var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()


func _mc() -> MovementComponent:
	var m: MovementComponent = MovementScript.new()
	_nodes.append(m)
	return m


func test_speeds_are_human_scale() -> void:
	var m := _mc()
	check_lt(m.speed_sneak, m.speed_walk, "sneak < walk")
	check_lt(m.speed_walk, m.speed_jog, "walk < jog")
	check_lt(m.speed_jog, m.speed_sprint, "jog < sprint")
	check_lt(m.speed_sprint, 7.0, "sprint slower than a superhero")


func test_accelerates_to_target_and_stops() -> void:
	var m := _mc()
	m.mode = MovementComponent.Mode.JOG
	var v := Vector3.ZERO
	for i in 60:
		v = m.compute_velocity(Vector3.FORWARD, v, 1.0 / 60.0)
	check_near(v.length(), m.speed_jog, 0.05, "reaches jog speed after 1s")
	check_near(v.y, 0.0, 0.0001, "y untouched")
	for i in 60:
		v = m.compute_velocity(Vector3.ZERO, v, 1.0 / 60.0)
	check_near(v.length(), 0.0, 0.001, "decelerates to rest")


func test_first_frame_is_not_full_speed() -> void:
	var m := _mc()
	var v := m.compute_velocity(Vector3.RIGHT, Vector3.ZERO, 1.0 / 60.0)
	check_lt(v.length(), m.speed_jog * 0.5, "no instant acceleration")


func test_modifiers_multiply() -> void:
	var m := _mc()
	m.set_modifier(&"encumbrance", 0.5)
	m.set_modifier(&"injury", 0.5)
	check_near(m.total_modifier(), 0.25, 0.0001, "modifiers multiply")
	check_near(m.target_speed(MovementComponent.Mode.JOG), m.speed_jog * 0.25, 0.0001, "target speed uses modifier")
	m.clear_modifier(&"injury")
	check_near(m.total_modifier(), 0.5, 0.0001, "cleared")
	m.set_modifier(&"encumbrance", 1.0)
	check(m.speed_modifiers.is_empty(), "1.0 modifier removes entry")


func test_diagonal_input_not_faster() -> void:
	var m := _mc()
	var v := Vector3.ZERO
	for i in 120:
		v = m.compute_velocity(Vector3(1, 0, 1), v, 1.0 / 60.0)
	check_near(v.length(), m.speed_jog, 0.05, "diagonal normalised")


func test_preserves_vertical_velocity() -> void:
	var m := _mc()
	var v := m.compute_velocity(Vector3.FORWARD, Vector3(0, -3.0, 0), 0.1)
	check_near(v.y, -3.0, 0.0001, "gravity component preserved")


func test_facing_follows_direction() -> void:
	var m := _mc()
	m.compute_velocity(Vector3.FORWARD, Vector3.ZERO, 0.016)
	check_near(m.facing, 0.0, 0.001, "facing -Z is yaw 0")
	m.compute_velocity(Vector3.LEFT, Vector3.ZERO, 0.016)
	check_near(m.facing, PI / 2.0, 0.001, "facing -X is yaw +90°")
	var yaw := 0.0
	for i in 60:
		yaw = m.step_facing(yaw, 1.0 / 60.0)
	check_near(yaw, PI / 2.0, 0.05, "visual yaw converges")
