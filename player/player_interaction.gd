class_name PlayerInteraction
extends Node3D
## Finds the best Interactable near the player and performs actions on it.
##
## Detection: a sphere shape query ([range_m]) on physics layer 4. Candidates
## are scored by distance and by how much they are in front of the
## character's facing; something directly behind the player is ignored
## unless it is very close (so "stand next to it and press E" still works).
## A line-of-sight ray from the eye to the candidate's prompt position on
## layer 1 (world) rejects objects behind a wall.
##
## Input: `interact` (E) performs the first enabled action; `action_1..4`
## pick an alternative from the current action list. All object-specific
## behaviour lives in the objects (see Interactable); nothing here knows
## what a door is. Input is ignored while the character is busy.

## Detection radius in metres.
@export var range_m: float = 1.6
## Candidates behind the player (facing dot < this) are ignored beyond
## [close_range_m].
@export var min_facing_dot: float = -0.2
@export var close_range_m: float = 1.0
## Layers that block line of sight (1 = world).
@export_flags_3d_physics var los_mask: int = 1

var current_target: Interactable = null
var current_actions: Array[Dictionary] = []
## Result of the last perform() call (for tests / UI feedback).
var last_result: Dictionary = {}
## When true, input is ignored (tests drive perform_action() directly).
var scripted: bool = false

var _shape: SphereShape3D
var _query: PhysicsShapeQueryParameters3D
var _los_query: PhysicsRayQueryParameters3D
var _character: Character


func _ready() -> void:
	_character = get_parent() as Character
	_shape = SphereShape3D.new()
	_shape.radius = range_m
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _shape
	_query.collision_mask = 1 << 3  # layer 4: interactables
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_los_query = PhysicsRayQueryParameters3D.new()
	_los_query.collision_mask = los_mask
	_los_query.collide_with_areas = false
	if _character:
		_query.exclude = [_character.get_rid()]
		_los_query.exclude = [_character.get_rid()]


func _physics_process(_delta: float) -> void:
	_refresh_target()


func _unhandled_input(event: InputEvent) -> void:
	if scripted or _character == null or _character.is_busy:
		return
	if event.is_action_pressed(&"interact"):
		interact()
	else:
		for i in 4:
			if event.is_action_pressed(StringName("action_%d" % (i + 1))):
				perform_index(i)
				return


## Perform the first enabled action on the current target.
func interact() -> Dictionary:
	for a in current_actions:
		if a.enabled:
			return perform_action(a.id)
	if current_target != null and not current_actions.is_empty():
		# Everything disabled: surface the primary reason.
		return perform_action(current_actions[0].id)
	last_result = {"ok": false, "reason": "Nothing to do"}
	return last_result


## Perform the [index]-th action (0-based) of the current list, if enabled.
func perform_index(index: int) -> Dictionary:
	if index < 0 or index >= current_actions.size():
		last_result = {"ok": false, "reason": "No such action"}
		return last_result
	return perform_action(current_actions[index].id)


func perform_action(action_id: StringName) -> Dictionary:
	if current_target == null:
		last_result = {"ok": false, "reason": "No target"}
		return last_result
	if _character and _character.is_busy:
		last_result = {"ok": false, "reason": "Busy"}
		EventBus.interaction_refused.emit(_character, current_target, "Busy")
		return last_result
	last_result = current_target.perform(action_id, _character)
	_refresh_target(true)
	return last_result


func _eye() -> Vector3:
	return _character.global_position + Vector3.UP * _character.eye_height()


func _facing_vector() -> Vector3:
	if _character == null:
		return Vector3.FORWARD
	var f := _character.movement.facing
	return Vector3(-sin(f), 0.0, -cos(f))


func _refresh_target(force_emit: bool = false) -> void:
	var best: Interactable = null
	var best_score := INF
	if _character != null and _character.is_inside_tree() and not _character.is_busy:
		var origin := _character.global_position
		var eye := _eye()
		var facing := _facing_vector()
		for body in _candidates(eye):
			var it := Interactable.of(body)
			if it == null:
				continue
			var prompt := it.get_prompt_position()
			var to := prompt - origin
			to.y = 0.0
			var dist := to.length()
			var dot := to.normalized().dot(facing) if dist > 0.001 else 1.0
			if dot < min_facing_dot and dist > close_range_m:
				continue
			var score := dist + (1.0 - dot) * 0.6
			if score >= best_score:
				continue
			if not _has_line_of_sight(eye, prompt, body):
				continue
			best_score = score
			best = it
	var actions: Array[Dictionary] = []
	if best != null:
		actions = best.get_actions(_character)
	var changed := best != current_target or not _same_actions(actions, current_actions)
	current_target = best
	current_actions = actions
	if changed or force_emit:
		EventBus.interaction_target_changed.emit(_character, current_target, current_actions)


## True when the ray from [eye] to [point] hits nothing, or hits [body]
## itself (or one of its ancestors / descendants).
func _has_line_of_sight(eye: Vector3, point: Vector3, body: Node) -> bool:
	var space := _character.get_world_3d().direct_space_state
	if space == null:
		return true
	_los_query.from = eye
	_los_query.to = point
	var hit := space.intersect_ray(_los_query)
	if hit.is_empty():
		return true
	var col: Node = hit.get("collider")
	if col == null or col == body:
		return true
	return col.is_ancestor_of(body) or body.is_ancestor_of(col)


func _candidates(centre: Vector3) -> Array[Node]:
	var out: Array[Node] = []
	var space := _character.get_world_3d().direct_space_state
	if space == null:
		return out
	_query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit in space.intersect_shape(_query, 16):
		var col: Node = hit.get("collider")
		if col != null and not out.has(col):
			out.append(col)
	return out


## Structural comparison of two action lists (id, label, enabled, reason).
static func _same_actions(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var x := a[i]
		var y := b[i]
		if x.id != y.id or x.enabled != y.enabled or x.label != y.label or x.reason != y.reason:
			return false
	return true
