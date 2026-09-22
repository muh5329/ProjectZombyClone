class_name ZombieStateWander
extends ZombieState
## Shamble to a random outdoor navmesh point within wander_radius of home.
## Back to idle on arrival, timeout, when stuck, or when a breakable
## (closed door) is in the way — wanderers do not bang on doors.


func enter(_from: StringName) -> void:
	ai.set_destination(ai.random_point_near(zombie.home_position, profile().wander_radius, true))


func update(_delta: float) -> StringName:
	if ai.move_along_path(MovementComponent.Mode.WALK):
		return ZombieAI.S_IDLE
	if time_in_state >= profile().wander_timeout or ai.stuck_time >= profile().wander_stuck_seconds:
		return ZombieAI.S_IDLE
	if ai.repath_due() and ai.breakable_ahead() != null:
		return ZombieAI.S_IDLE
	return &""
