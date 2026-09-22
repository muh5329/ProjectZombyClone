class_name ZombieStateStunned
extends ZombieState
## Hit hard: freeze for profile.stun_seconds, then resume chasing (target
## remembered) or stand idle. Round 4 adds knock-downs on top.


func enter(_from: StringName) -> void:
	ai.stop()
	zombie.visual.lunge = 0.0


func update(_delta: float) -> StringName:
	if time_in_state < profile().stun_seconds:
		return &""
	if ai.target_valid() and ai.memory_left > 0.0:
		return ZombieAI.S_CHASE
	return ZombieAI.S_IDLE
