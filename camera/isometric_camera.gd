class_name IsometricCamera
extends Node3D
## Fixed dimetric camera rig in the Project Zomboid style.
##
## Hierarchy: [this pivot] -> Arm (pitched) -> Camera3D.
## - Orthographic by default (2:1 dimetric look: 30° elevation, 45° yaw
##   steps). Zoom levels are then the vertical view size in world units.
##   With [orthographic] off the old perspective rig is used and zoom levels
##   are camera distances ([perspective_zoom_levels]).
## - Follows [target] smoothly on the ground plane.
## - Yaw snaps in 45° steps (Q/R) with smooth interpolation.
## - Exposes [camera] so the OcclusionManager can cast from it. Use
##   [method view_direction] for "towards the camera" queries: in
##   orthographic mode the eye is at infinity, so the camera position is
##   meaningless for that.

@export var target_path: NodePath
@export var follow_speed: float = 8.0
@export var yaw_step_degrees: float = 45.0
@export var initial_yaw_degrees: float = 45.0
@export var yaw_lerp_speed: float = 7.0
## Elevation angle. 30° gives the classic 2:1 dimetric projection.
@export var pitch_degrees: float = 30.0
## Orthographic (dimetric) projection. Perspective is kept as a fallback.
## Can be toggled at runtime: the projection and zoom list are re-applied.
@export var orthographic: bool = true:
	set(v):
		orthographic = v
		if _camera != null:
			_apply_projection()
			zoom_index = clampi(zoom_index, 0, _levels().size() - 1)
			_current_zoom = _levels()[zoom_index]
			_apply_zoom()
## Zoom levels. Orthographic: vertical view size in world units.
@export var zoom_levels: Array[float] = [10.0, 14.0, 20.0, 28.0]
## Zoom levels used when [orthographic] is false: camera distance in metres.
@export var perspective_zoom_levels: Array[float] = [12.0, 18.0, 26.0, 38.0]
@export var initial_zoom_index: int = 1
@export var zoom_lerp_speed: float = 8.0
@export var fov: float = 35.0
## How far back along the arm the orthographic camera sits. Only affects
## clipping/shadow ranges, never the framing.
@export var orthographic_distance: float = 45.0
## Extra height added to the follow point so the character's centre is framed.
@export var target_height_offset: float = 0.9

var target: Node3D
var yaw_index: int = 0
var zoom_index: int = 1

var _arm: Node3D
var _camera: Camera3D
var _current_yaw: float = 0.0
var _current_zoom: float = 10.0

var camera: Camera3D:
	get: return _camera


func _ready() -> void:
	if zoom_levels.is_empty():
		push_warning("IsometricCamera: zoom_levels empty, using default")
		zoom_levels = [20.0]
	if perspective_zoom_levels.is_empty():
		perspective_zoom_levels = [26.0]
	if yaw_step_degrees <= 0.0:
		push_warning("IsometricCamera: yaw_step_degrees must be > 0, using 45")
		yaw_step_degrees = 45.0
	add_to_group(&"isometric_camera")
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
	_apply_projection()

	yaw_index = int(round(initial_yaw_degrees / yaw_step_degrees))
	zoom_index = clampi(initial_zoom_index, 0, _levels().size() - 1)
	_current_yaw = deg_to_rad(yaw_index * yaw_step_degrees)
	_current_zoom = _levels()[zoom_index]
	rotation.y = _current_yaw
	_apply_zoom()

	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path)
	if is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position + Vector3.UP * target_height_offset
	_camera.make_current()


func _apply_projection() -> void:
	if orthographic:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.keep_aspect = Camera3D.KEEP_HEIGHT
		_camera.position.z = orthographic_distance
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov


func _levels() -> Array[float]:
	return zoom_levels if orthographic else perspective_zoom_levels


func _apply_zoom() -> void:
	if orthographic:
		_camera.size = _current_zoom
	else:
		_camera.position.z = _current_zoom


func set_target(node: Node3D) -> void:
	target = node


func rotate_step(steps: int) -> void:
	var count := int(round(360.0 / yaw_step_degrees))
	yaw_index = posmod(yaw_index + steps, count)
	EventBus.camera_rotated.emit(target_yaw_degrees())


func zoom_step(delta_index: int) -> void:
	var new_index := clampi(zoom_index + delta_index, 0, _levels().size() - 1)
	if new_index != zoom_index:
		zoom_index = new_index
		EventBus.camera_zoomed.emit(zoom_index)


func target_yaw_degrees() -> float:
	return yaw_index * yaw_step_degrees


## Current zoom value (ortho size or perspective distance) as interpolated.
func current_zoom() -> float:
	return _current_zoom


## Unit vector pointing from the scene towards the eye, flattened onto the
## ground plane. Works for both projections.
func view_direction_flat() -> Vector3:
	var z := _camera.global_basis.z
	var flat := Vector3(z.x, 0.0, z.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.BACK


## A point far behind the camera plane through [point], suitable as a ray
## origin "from the eye" for both projections.
func eye_position_for(point: Vector3, distance: float = 80.0) -> Vector3:
	if orthographic:
		return point + _camera.global_basis.z * distance
	return _camera.global_position


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

	var levels := _levels()
	zoom_index = clampi(zoom_index, 0, levels.size() - 1)
	_current_zoom = lerpf(_current_zoom, levels[zoom_index], clampf(zoom_lerp_speed * delta, 0.0, 1.0))
	_apply_zoom()


# --- Save (Round 10) ------------------------------------------------------------------

func view_state() -> Dictionary:
	return {"yaw_index": yaw_index, "zoom_index": zoom_index}


## Snap to a saved heading / zoom and onto the target (no easing), so a
## loaded game opens on the view it was saved with.
func restore_view(d: Dictionary) -> void:
	var count := int(round(360.0 / yaw_step_degrees))
	yaw_index = posmod(int(d.get("yaw_index", yaw_index)), count)
	zoom_index = clampi(int(d.get("zoom_index", zoom_index)), 0, _levels().size() - 1)
	_current_yaw = wrapf(deg_to_rad(target_yaw_degrees()), -PI, PI)
	rotation.y = _current_yaw
	_current_zoom = _levels()[zoom_index]
	_apply_zoom()
	if is_instance_valid(target) and target.is_inside_tree():
		global_position = target.global_position + Vector3.UP * target_height_offset
