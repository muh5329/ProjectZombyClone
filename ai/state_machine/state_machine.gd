class_name StateMachine
extends RefCounted
## Small explicit finite-state machine shared by zombies and (later) NPCs.
##
## - States are AIState objects keyed by id.
## - change_to(id) runs exit/enter and emits [signal state_changed].
## - update(delta) ticks the current state; a state may return the id of
##   the state to switch to. Transitions requested during enter() are
##   honoured in the same update (bounded to avoid infinite ping-pong).
## - previous_state lets transient states (LostTarget, Stunned) go back.
## Pure: no scene tree, no timers; delta comes from the caller.

signal state_changed(from: StringName, to: StringName)

## Whatever the states act on (a Node normally). Untyped on purpose.
var owner_node: Object = null
var states: Dictionary = {}
var current: AIState = null
var previous_state: StringName = &""
## Transition log (last [history_size] ids) for tests / debug overlay.
var history: Array[StringName] = []
var history_size: int = 16
var _transitions_this_update: int = 0
const MAX_CHAINED_TRANSITIONS := 4


func _init(p_owner: Object = null) -> void:
	owner_node = p_owner


func add_state(state: AIState) -> AIState:
	state.machine = self
	states[state.id] = state
	return state


func has_state(id: StringName) -> bool:
	return states.has(id)


func get_state(id: StringName) -> AIState:
	return states.get(id)


func current_id() -> StringName:
	return current.id if current else &""


func is_in(id: StringName) -> bool:
	return current != null and current.id == id


## Switch to [id]. Returns false when the id is unknown or already active
## (unless [force] re-enters it).
func change_to(id: StringName, force: bool = false) -> bool:
	var next: AIState = states.get(id)
	if next == null:
		push_warning("StateMachine: unknown state %s" % id)
		return false
	if current == next and not force:
		return false
	var from: StringName = current.id if current else &""
	if current:
		current.exit(id)
		previous_state = current.id
	current = next
	next.time_in_state = 0.0
	history.append(id)
	if history.size() > history_size:
		history.pop_front()
	next.enter(from)
	state_changed.emit(from, id)
	return true


func update(delta: float) -> void:
	if current == null:
		return
	_transitions_this_update = 0
	current.time_in_state += delta
	var next := current.update(delta)
	while next != &"" and next != current.id and _transitions_this_update < MAX_CHAINED_TRANSITIONS:
		_transitions_this_update += 1
		if not change_to(next):
			break
		# Let transient states (that decide in enter/update immediately)
		# resolve within the same tick.
		next = current.update(0.0)
