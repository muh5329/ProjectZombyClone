class_name AIState
extends RefCounted
## One state of a StateMachine. Subclass and override enter/exit/update.
## States are plain RefCounted objects so machines can be unit-tested
## without a scene tree; the owner (a zombie, an NPC) is whatever the
## machine's `owner_node` is.

var id: StringName = &""
## Owning machine (weak: the machine holds the states, so a strong
## back-reference would be a RefCounted cycle that never frees).
var machine: StateMachine:
	get:
		return _machine_ref.get_ref() as StateMachine if _machine_ref else null
	set(v):
		_machine_ref = weakref(v) if v != null else null
var _machine_ref: WeakRef = null
## Seconds spent in this state since enter() (physics time).
var time_in_state: float = 0.0


func _init(p_id: StringName = &"") -> void:
	id = p_id


## Called after the machine switched to this state. [from] may be &"".
func enter(_from: StringName) -> void:
	pass


## Called before the machine switches away. [to] is the next state id.
func exit(_to: StringName) -> void:
	pass


## Called every tick while active. Return a state id to request a
## transition, or &"" to stay.
func update(_delta: float) -> StringName:
	return &""


## Convenience: the machine's owner (Node or anything).
func owner_node() -> Object:
	return machine.owner_node if machine else null
