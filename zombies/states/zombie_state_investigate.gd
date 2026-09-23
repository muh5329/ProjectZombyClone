class_name ZombieStateInvestigate
extends ZombieState
## Walk to the position of a heard sound (or the last known target
## position), then search there. A breakable in the way gets banged on.
## Round 8: a faint sound first makes the zombie stand and turn toward it
## for profile.faint_turn_seconds; a loud one is investigated at chase
## speed. While investigating the zombie moans (ai.maybe_moan) so its
## neighbours follow.


func enter(_from: StringName) -> void:
	if ai.investigate_pause:
		ai.stop()
		zombie.face_toward(ai.investigate_position)
	ai.set_destination(ai.investigate_position)


func _mode() -> MovementComponent.Mode:
	return MovementComponent.Mode.JOG if ai.investigate_loud else MovementComponent.Mode.WALK


func update(_delta: float) -> StringName:
	ai.maybe_moan()
	if ai.investigate_pause:
		if time_in_state < profile().faint_turn_seconds:
			ai.stop()
			return &""
		ai.investigate_pause = false
	if ai.distance_to(ai.investigate_position) <= profile().investigate_arrive_distance:
		return ZombieAI.S_SEARCH
	var arrived := ai.move_along_path(_mode())
	if ai.repath_due():
		ai.set_destination(ai.investigate_position)
		var obstacle := ai.breakable_ahead()
		if obstacle != null:
			ai.blocking_obstacle = obstacle
			return ZombieAI.S_ATTACK_DOOR
	if arrived or time_in_state >= profile().investigate_timeout or ai.stuck_time >= profile().investigate_stuck_seconds:
		return ZombieAI.S_SEARCH
	return &""
