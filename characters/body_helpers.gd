class_name BodyHelpers
extends RefCounted
## Tiny pure helpers shared by every body (Character, Zombie, later NPCs):
## flat (XZ) distances, speeds and yaw <-> direction conversions.

## Intent directions shorter than this count as "not moving".
const INTENT_DEADZONE := 0.1


static func has_move_intent(direction: Vector3) -> bool:
	return direction.length_squared() > INTENT_DEADZONE * INTENT_DEADZONE


static func is_moving(velocity: Vector3) -> bool:
	return velocity.x * velocity.x + velocity.z * velocity.z > 0.01


static func flat_speed(velocity: Vector3) -> float:
	return Vector2(velocity.x, velocity.z).length()


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## World direction for a yaw (radians) in the MovementComponent convention
## (yaw 0 faces -Z).
static func facing_vector(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## Yaw (radians) that faces along [direction] (XZ).
static func yaw_for(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)
