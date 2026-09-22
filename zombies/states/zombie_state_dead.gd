class_name ZombieStateDead
extends ZombieState
## Terminal. Zombie.die() handles the corpse, visuals and events.


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
