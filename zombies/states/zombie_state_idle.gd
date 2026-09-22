class_name ZombieStateIdle
extends ZombieState
## Stand still for idle_time_min..max seconds, then wander.

var _wait: float = 3.0


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	_wait = ai.random_range(profile().idle_time_min, profile().idle_time_max)


func update(_delta: float) -> StringName:
	if time_in_state >= _wait:
		return ZombieAI.S_WANDER
	return &""
