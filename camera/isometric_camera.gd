class_name IsometricCamera
extends Node3D
## Elevated isometric-style camera rig.
##
## Hierarchy: [this pivot] -> Arm (pitched) -> Camera3D.
## - Follows [target] smoothly on the ground plane.
## - Yaw snaps in 45° steps (Q/R) with smooth interpolation.
## - Discrete zoom levels (wheel / +/-).
## - Occlusion handling (roof/wall fading) is added in Round 2 when buildings
##   exist; the rig exposes [camera] so that system can raycast from it.

@export var target_path: NodePath
@export var follow_speed: float = 8.0
@export var yaw_step_degrees: float = 45.0
@export var initial_yaw_degrees: float = 45.0
@export var yaw_lerp_speed: float = 7.0
@export var pitch_degrees: float = 52.0
@export var zoom_levels: Array[float] = [12.0, 18.0, 26.0, 38.0]
@export var initial_zoom_index: int = 2
@export var zoom_lerp_speed: float = 8.0
@export var fov: float = 35.0
## Extra height added to the follow point so the character's centre is framed.
@export var target_height_offset: float = 0.9

var target: Node3D
var yaw_index: int = 0
var zoom_index: int = 1

var _arm: Node3D
var _camera: Camera3D
var _current_yaw: float = 0.0
var _current_distance: float = 10.0

var camera: Camera3D:
	get: return _camera


func _ready() -> void:
	if zoom_levels.is_empty():
		push_warning("IsometricCamera: zoom_levels empty, using default")
		zoom_levels = [26.0]
	if yaw_step_degrees <= 0.0:
		push_warning("IsometricCamera: yaw_step_degrees must be > 0, using 45")
		yaw_step_degrees = 45.0
	_arm = Node3D.new()
	_arm.name = "Arm"
	add_child(_arm)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = fov
	_camera.near = 0.2
	_camera.far = 400.0
	_arm.add_child(_camera)
	_arm.rotation_degrees.x = -pitch_degrees

	yaw_index = int(round(initial_yaw_degrees / yaw_step_degrees))
	zoom_index = clampi(initial_zoom_index, 0, zoom_levels.size() - 1)
	_current_yaw = deg_to_rad(yaw_index * yaw_step_degrees)
	_current_distance = zoom_levels[zoom_index]
	rotation.y = _current_yaw
	_camera.position.z = _current_distance

	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path)
	if is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position + Vector3.UP * target_height_offset
	_camera.make_current()


func set_target(node: Node3D) -> void:
	target = node


func rotate_step(steps: int) -> void:
	var count := int(round(360.0 / yaw_step_degrees))
	yaw_index = posmod(yaw_index + steps, count)
	EventBus.camera_rotated.emit(target_yaw_degrees())


func zoom_step(delta_index: int) -> void:
	var new_index := clampi(zoom_index + delta_index, 0, zoom_levels.size() - 1)
	if new_index != zoom_index:
		zoom_index = new_index
		EventBus.camera_zoomed.emit(zoom_index)


func target_yaw_degrees() -> float:
	return yaw_index * yaw_step_degrees


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_rotate_left"):
		rotate_step(1)
	elif event.is_action_pressed(&"camera_rotate_right"):
		rotate_step(-1)
	elif event.is_action_pressed(&"camera_zoom_in"):
		zoom_step(-1)
	elif event.is_action_pressed(&"camera_zoom_out"):
		zoom_step(1)


func _process(delta: float) -> void:
	if is_instance_valid(target) and target.is_inside_tree():
		var goal := target.global_position + Vector3.UP * target_height_offset
		global_position = global_position.lerp(goal, clampf(follow_speed * delta, 0.0, 1.0))

	var goal_yaw := deg_to_rad(target_yaw_degrees())
	_current_yaw = wrapf(lerp_angle(_current_yaw, goal_yaw, clampf(yaw_lerp_speed * delta, 0.0, 1.0)), -PI, PI)
	rotation.y = _current_yaw

	_current_distance = lerpf(_current_distance, zoom_levels[zoom_index], clampf(zoom_lerp_speed * delta, 0.0, 1.0))
	_camera.position.z = _current_distance
