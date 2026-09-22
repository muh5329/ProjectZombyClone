class_name ZombieState
extends AIState
## Base for zombie states: keeps the AI / zombie handles.

var ai: ZombieAI
var zombie: Zombie


func _init(p_id: StringName, p_ai: ZombieAI) -> void:
	super(p_id)
	ai = p_ai
	zombie = p_ai.zombie


func profile() -> ZombieProfile:
	return zombie.profile
