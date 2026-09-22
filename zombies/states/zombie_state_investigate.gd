class_name ZombieStateInvestigate
extends ZombieState
## Walk to the position of a heard sound (or the last known target
## position), then search there. A breakable in the way gets banged on.


func enter(_from: StringName) -> void:
	ai.set_destination(ai.investigate_position)


func update(_delta: float) -> StringName:
	if ai.distance_to(ai.investigate_position) <= profile().investigate_arrive_distance:
		return ZombieAI.S_SEARCH
	var arrived := ai.move_along_path(MovementComponent.Mode.WALK)
	if ai.repath_due():
		ai.set_destination(ai.investigate_position)
		var obstacle := ai.breakable_ahead()
		if obstacle != null:
			ai.blocking_obstacle = obstacle
			return ZombieAI.S_ATTACK_DOOR
	if arrived or time_in_state >= profile().investigate_timeout or ai.stuck_time >= profile().investigate_stuck_seconds:
		return ZombieAI.S_SEARCH
	return &""
