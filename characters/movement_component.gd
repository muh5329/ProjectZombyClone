class_name MovementComponent
extends Node
## Pure movement model for humans: converts an intent (direction + mode) into
## a horizontal velocity, applying acceleration and modifiers.
##
## This node does NOT move anything; the owning CharacterBody3D applies the
## returned velocity. That keeps it unit-testable without a physics world.
##
## Speeds are deliberately "vulnerable human" — no action-RPG dashing.

enum Mode { SNEAK, WALK, JOG, SPRINT }

const MODE_NAMES := {
	Mode.SNEAK: &"sneak",
	Mode.WALK: &"walk",
	Mode.JOG: &"jog",
	Mode.SPRINT: &"sprint",
}

## Base speeds in metres/second.
@export var speed_sneak: float = 1.3
@export var speed_walk: float = 2.0
@export var speed_jog: float = 3.4
@export var speed_sprint: float = 5.6

## How quickly velocity approaches target (m/s²). Humans do not turn on a dime.
@export var acceleration: float = 14.0
@export var deceleration: float = 16.0
## Turning rate for the visual facing (rad/s).
@export var turn_speed: float = 12.0

## Multipliers applied to speed from external systems. Keyed by source
## (e.g. &"encumbrance", &"injury", &"exhaustion"). Product of all values.
var speed_modifiers: Dictionary = {}

var mode: Mode = Mode.JOG
var facing: float = 0.0  # yaw radians the body should face


func set_modifier(source: StringName, multiplier: float) -> void:
	if is_equal_approx(multiplier, 1.0):
		speed_modifiers.erase(source)
	else:
		speed_modifiers[source] = multiplier


func clear_modifier(source: StringName) -> void:
	speed_modifiers.erase(source)


func total_modifier() -> float:
	var m := 1.0
	for v: float in speed_modifiers.values():
		m *= v
	return maxf(m, 0.0)


func base_speed_for(p_mode: Mode) -> float:
	match p_mode:
		Mode.SNEAK: return speed_sneak
		Mode.WALK: return speed_walk
		Mode.JOG: return speed_jog
		Mode.SPRINT: return speed_sprint
	return speed_jog


func target_speed(p_mode: Mode = mode) -> float:
	return base_speed_for(p_mode) * total_modifier()


## Compute the new horizontal velocity.
## [direction] is a world-space unit vector on the XZ plane (or ZERO).
## [current] is the body's current velocity (Y is preserved untouched).
func compute_velocity(direction: Vector3, current: Vector3, delta: float) -> Vector3:
	var flat_dir := Vector3(direction.x, 0.0, direction.z)
	if flat_dir.length_squared() > 1.0:
		flat_dir = flat_dir.normalized()
	var target := flat_dir * target_speed()
	var horiz := Vector3(current.x, 0.0, current.z)
	var rate := acceleration if flat_dir != Vector3.ZERO else deceleration
	horiz = horiz.move_toward(target, rate * delta)
	if flat_dir != Vector3.ZERO:
		facing = atan2(-flat_dir.x, -flat_dir.z)
	return Vector3(horiz.x, current.y, horiz.z)


## Smoothly rotate [current_yaw] toward [facing]; returns the new yaw.
func step_facing(current_yaw: float, delta: float) -> float:
	return lerp_angle(current_yaw, facing, clampf(turn_speed * delta, 0.0, 1.0))


static func mode_name(p_mode: Mode) -> StringName:
	return MODE_NAMES.get(p_mode, &"jog")
