class_name ZombieStateKnockedDown
extends ZombieState
## On the ground (weapon knockdown roll or a shove): the visual lies flat,
## no attacks, damage taken ×profile.knockdown_damage_multiplier (see
## Zombie.take_damage). After profile.knockdown_seconds it gets up and
## resumes the chase (target remembered) or idles.


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	ai.release_attack_slot()
	zombie.visual.lunge = 0.0
	zombie.visual.set_knocked_down(true)


func exit(_to: StringName) -> void:
	zombie.visual.set_knocked_down(false)
	if not zombie.dead:
		EventBus.zombie_got_up.emit(zombie)


func update(_delta: float) -> StringName:
	if time_in_state < ai.down_seconds:
		return &""
	if ai.target_valid() and ai.memory_left > 0.0:
		return ZombieAI.S_CHASE
	return ZombieAI.S_IDLE
