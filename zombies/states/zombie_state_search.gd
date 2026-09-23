class_name ZombieStateSearch
extends ZombieState
## Look around for search_time_min..max seconds: turn to random headings,
## occasionally shuffle a couple of metres. Then wander.
## Round 8: after investigating a deliberate lure (profile
## lure_search_categories — the player's shout) the search lasts
## lure_search_time_min..max (8–12 s) and its shuffles widen up to
## lure_search_extra_radius further: shouting pins zombies down for a while.

var _total: float = 5.0
## True while this search follows a lure (tests / debug).
var lure: bool = false
var _next_action: float = 0.0
var _walking: bool = false


func enter(from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	lure = from == ZombieAI.S_INVESTIGATE and profile().lure_search_categories.has(ai.investigate_category)
	if lure:
		_total = ai.random_range(profile().lure_search_time_min, profile().lure_search_time_max)
	else:
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
			ai.set_destination(ai.random_point_near(zombie.global_position, walk_radius()))
			_walking = true
		else:
			zombie.face_yaw(ai.rng.randf() * TAU)
	return &""


## Shuffle radius now (widens over a lure search).
func walk_radius() -> float:
	if not lure:
		return profile().search_walk_radius
	return profile().search_walk_radius + profile().lure_search_extra_radius * clampf(time_in_state / maxf(_total, 0.1), 0.0, 1.0)


func total_seconds() -> float:
	return _total
