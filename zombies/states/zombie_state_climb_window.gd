class_name ZombieStateClimbWindow
extends ZombieState
## Climb through ai.climb_window (open or smashed, no planks): the body
## goes up onto the sill, over, and down on the far side in
## profile.window_climb_seconds (Zombie.start_climb moves it every physics
## tick; no collision meanwhile). Damage / shoves do not interrupt a climb
## (like the player's). If the window gets closed or barricaded before the
## zombie is halfway, it drops back and bangs on it instead. Then resume
## (chase if the target is remembered, else investigate) from a fresh path.

var window: Node3D = null


func enter(_from: StringName) -> void:
	window = ai.climb_window
	ai.climb_window = null
	ai.stop()
	ai.clear_destination()
	if window == null or not is_instance_valid(window):
		return
	var from := zombie.global_position
	var to: Vector3 = window.call(&"landing_point", from)
	var sill: float = float(window.get(&"sill_height"))
	var over := Vector3(window.global_position.x, from.y + sill + 0.05, window.global_position.z)
	zombie.face_toward(to)
	zombie.start_climb(from, over, to, profile().window_climb_seconds)


func exit(_to: StringName) -> void:
	if zombie.is_climbing():
		zombie.stop_climb(false)
	window = null


func update(_delta: float) -> StringName:
	if window == null or not is_instance_valid(window):
		zombie.stop_climb(false)
		ai.reset_path()
		return ai.after_obstacle_state()
	if zombie.climb_progress() < 0.5 and window.has_method(&"blocks_path") and window.call(&"blocks_path"):
		# Shut / boarded in our face: drop back and bang on it.
		zombie.stop_climb(true)
		var b := ZombieAI.resolve_breakable(window)
		if b != null:
			ai.blocking_obstacle = b
			return ZombieAI.S_ATTACK_DOOR
		return ai.after_obstacle_state()
	if zombie.is_climbing():
		return &""
	ai.reset_path()
	EventBus.window_climbed.emit(zombie, window, false)
	return ai.after_obstacle_state()
