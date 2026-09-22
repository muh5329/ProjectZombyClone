class_name ZombieStateLostTarget
extends ZombieState
## Transition state: forget the target, announce it, then search around
## the last known position (walking there first if not already close).


func enter(_from: StringName) -> void:
	EventBus.zombie_lost_target.emit(zombie)
	ai.release_attack_slot()
	zombie.target = null
	ai.memory_left = 0.0
	ai.investigate_position = ai.last_known_position


func update(_delta: float) -> StringName:
	if ai.distance_to(ai.investigate_position) <= profile().lost_near_distance:
		return ZombieAI.S_SEARCH
	return ZombieAI.S_INVESTIGATE
