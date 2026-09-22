class_name ZombieStateSearch
extends ZombieState
## Look around for search_time_min..max seconds: turn to random headings,
## occasionally shuffle a couple of metres. Then wander.

var _total: float = 5.0
var _next_action: float = 0.0
var _walking: bool = false


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	_total = ai.random_range(profile().search_time_min, profile().search_time_max)
	_next_action = 0.3
	_walking = false


func update(_delta: float) -> StringName:
	if time_in_state >= _total:
		return ZombieAI.S_WANDER
	if _walking:
		if ai.move_along_path(MovementComponent.Mode.WALK) or ai.stuck_time > profile().search_stuck_seconds:
			_walking = false
			ai.stop()
	if time_in_state >= _next_action:
		_next_action = time_in_state + ai.random_range(profile().search_turn_period_min, profile().search_turn_period_max)
		if not _walking and ai.rng.randf() < profile().search_walk_chance:
			ai.set_destination(ai.random_point_near(zombie.global_position, profile().search_walk_radius))
			_walking = true
		else:
			zombie.face_yaw(ai.rng.randf() * TAU)
	return &""
