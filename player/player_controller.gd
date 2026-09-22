class_name PlayerController
extends Node
## Translates raw input into movement intent for the parent Character.
##
## Movement is camera-relative: "forward" is away from the camera on the
## ground plane, so WASD stays intuitive as the isometric camera rotates.
## Interaction/combat input is added by separate nodes in later rounds; this
## node only concerns itself with locomotion.

## When true, input is ignored and [scripted_direction]/[scripted_mode] are
## used instead (test harness / cutscenes).
var scripted: bool = false
var scripted_direction: Vector3 = Vector3.ZERO
var scripted_mode: MovementComponent.Mode = MovementComponent.Mode.JOG

@onready var character: Character = get_parent() as Character


func _physics_process(_delta: float) -> void:
	if character == null:
		return
	if scripted:
		character.set_intent(scripted_direction, scripted_mode)
		return
	character.set_intent(_read_direction(), _read_mode())


func _read_mode() -> MovementComponent.Mode:
	if Input.is_action_pressed(&"sneak"):
		return MovementComponent.Mode.SNEAK
	if Input.is_action_pressed(&"sprint"):
		return MovementComponent.Mode.SPRINT
	if Input.is_action_pressed(&"walk"):
		return MovementComponent.Mode.WALK
	return MovementComponent.Mode.JOG


func _read_direction() -> Vector3:
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	return camera_relative(input, get_viewport().get_camera_3d())


## Convert a 2D input vector (x = right, y = down/back) into a world-space
## direction on the XZ plane relative to [camera]'s yaw. Static so it can be
## unit-tested with a dummy camera.
static func camera_relative(input: Vector2, camera: Camera3D) -> Vector3:
	var forward := Vector3.FORWARD
	var right := Vector3.RIGHT
	if camera:
		var b := camera.global_basis
		forward = Vector3(-b.z.x, 0.0, -b.z.z)
		right = Vector3(b.x.x, 0.0, b.x.z)
		if forward.length_squared() < 0.0001:
			# Camera looking straight down: fall back to its "up" as forward.
			forward = Vector3(b.y.x, 0.0, b.y.z)
		forward = forward.normalized()
		right = right.normalized()
	var dir := right * input.x + forward * -input.y
	return dir.normalized() if dir.length_squared() > 1.0 else dir
