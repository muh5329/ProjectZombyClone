class_name ZombieStateStunned
extends ZombieState
## Hit hard (or shoved): freeze for ai.stun_seconds, then resume chasing
## (target remembered) or stand idle.


func enter(_from: StringName) -> void:
	ai.stop()
	zombie.visual.lunge = 0.0


func update(_delta: float) -> StringName:
	if time_in_state < ai.stun_seconds:
		return &""
	if ai.target_valid() and ai.memory_left > 0.0:
		return ZombieAI.S_CHASE
	return ZombieAI.S_IDLE
