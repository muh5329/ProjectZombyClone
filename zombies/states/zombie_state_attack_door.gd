class_name ZombieStateAttackDoor
extends ZombieState
## Bang on the breakable in the path (ai.blocking_obstacle: a closed
## door…) until it no longer blocks, then resume (chase if the target is
## remembered, else investigate). Same windup / cooldown rhythm and lunge
## tell as a normal attack. The obstacle announces its own bangs.

enum Phase { WINDUP, COOLDOWN }

var phase: Phase = Phase.WINDUP
var timer: float = 0.0
var hits: int = 0


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	hits = 0
	phase = Phase.WINDUP
	timer = profile().attack_windup
	if _obstacle_ok():
		zombie.face_toward(_obstacle_position())


func exit(_to: StringName) -> void:
	zombie.visual.lunge = 0.0


func _obstacle_ok() -> bool:
	var o := ai.blocking_obstacle
	return o != null and is_instance_valid(o) and o.is_inside_tree() and o.blocks_path()


func _obstacle_position() -> Vector3:
	var o := ai.blocking_obstacle
	if o.has_method(&"interaction_prompt_position"):
		return o.call(&"interaction_prompt_position")
	return o.global_position


func update(delta: float) -> StringName:
	if not _obstacle_ok():
		ai.blocking_obstacle = null
		return ai.after_obstacle_state()
	var at := _obstacle_position()
	if ai.distance_to(at) > profile().door_max_distance:
		ai.blocking_obstacle = null
		return ai.after_obstacle_state()
	zombie.face_toward(at)
	if ai.target_valid() and zombie.senses.visible_target != zombie.target:
		ai.memory_left -= delta
	timer -= delta
	match phase:
		Phase.WINDUP:
			var windup := profile().attack_windup
			zombie.visual.lunge = profile().lunge_distance * clampf(1.0 - timer / windup, 0.0, 1.0) if windup > 0.0 else 0.0
			if timer <= 0.0:
				zombie.visual.lunge = 0.0
				zombie.visual.flash(profile().swing_flash_seconds)
				ai.blocking_obstacle.call(&"take_damage", profile().door_damage, zombie)
				hits += 1
				EventBus.zombie_attacked.emit(zombie, ai.blocking_obstacle, true)
				phase = Phase.COOLDOWN
				timer = profile().attack_cooldown
		Phase.COOLDOWN:
			if timer <= 0.0:
				phase = Phase.WINDUP
				timer = profile().attack_windup
	return &""
