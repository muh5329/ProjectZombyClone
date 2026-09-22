class_name Door
extends WallFixture
## Hinged door. The body itself is the hinge: it sits at the hinge post and
## the leaf (mesh + collision) is offset along local +X, so rotating the
## body swings the door and the collision follows for free.
##
## States: closed / open. Actions come from interaction_actions(); the
## player never knows this is a door. Emits EventBus.door_state_changed.
## A swing is refused ("Blocked") when a character stands where the leaf
## would end up, and toggles are rate-limited by WallFixture.toggle_cooldown.

const STATE_CLOSED := &"closed"
const STATE_OPEN := &"open"
const ACTION_OPEN := &"open"
const ACTION_CLOSE := &"close"
## Layers checked before swinging: 2 player + 3 zombies.
const BLOCK_MASK := (1 << 1) | (1 << 2)

@export var width: float = 0.9
@export var height: float = 2.1
@export var thickness: float = 0.08
@export var color: Color = Color(0.5, 0.33, 0.2)
@export var swing_seconds: float = 0.4
## Locked doors cannot be opened (keys/lockpicking in a later round).
@export var locked: bool = false

var state: StringName = STATE_CLOSED
## Signed swing angle of the last opening (radians), 0 when closed.
var _swing: float = 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _init() -> void:
	fixture_group = &"door"


func _build_visual() -> void:
	_mesh = _box(visual, Vector3(width, height, thickness), Vector3(width * 0.5, height * 0.5, 0.0), color)
	_mesh.name = "Leaf"
	# A small knob so open/closed reads at a glance in the blockout.
	_box(visual, Vector3(0.08, 0.08, 0.16), Vector3(width - 0.12, 1.0, 0.0), Color(0.85, 0.8, 0.5))
	_shape = _add_shape(_leaf_size(), _leaf_offset())


func _leaf_size() -> Vector3:
	return Vector3(width, height, maxf(thickness, 0.12))


func _leaf_offset() -> Vector3:
	return Vector3(width * 0.5, height * 0.5, 0.0)


func is_open() -> bool:
	return state == STATE_OPEN


# --- Interactable provider API --------------------------------------------

func interaction_display_name() -> String:
	return "Door"


func interaction_prompt_position() -> Vector3:
	return _mesh.global_position if _mesh else global_position


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var busy := on_cooldown()
	if state == STATE_CLOSED:
		if locked:
			out.append(Interactable.action(ACTION_OPEN, "Open door", false, "Locked"))
		elif busy:
			out.append(Interactable.action(ACTION_OPEN, "Open door", false, "Busy"))
		elif _blocked_at(_swing_for(actor)):
			out.append(Interactable.action(ACTION_OPEN, "Open door", false, "Blocked"))
		else:
			out.append(Interactable.action(ACTION_OPEN, "Open door"))
	else:
		if busy:
			out.append(Interactable.action(ACTION_CLOSE, "Close door", false, "Busy"))
		elif _blocked_at(0.0):
			out.append(Interactable.action(ACTION_CLOSE, "Close door", false, "Blocked"))
		else:
			out.append(Interactable.action(ACTION_CLOSE, "Close door"))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	match action_id:
		ACTION_OPEN:
			return open_door(actor)
		ACTION_CLOSE:
			return close_door()
	return {"ok": false, "reason": "Unknown action"}


# --- State ------------------------------------------------------------------

## Swing angle that moves the leaf away from [actor] (+90° for an actor at
## local +Z).
func _swing_for(actor: Node) -> float:
	var side := 1.0
	if actor is Node3D:
		side = 1.0 if to_local((actor as Node3D).global_position).z >= 0.0 else -1.0
	return side * PI * 0.5


## Would the leaf, rotated to [angle] about the hinge, overlap a character?
func _blocked_at(angle: float) -> bool:
	# The query is expressed in this node's (currently rotated) space, so
	# only the difference between the target and current swing matters.
	var b := Basis(Vector3.UP, angle - rotation.y)
	return _box_blocked(_leaf_size(), b * _leaf_offset(), b, BLOCK_MASK)


## Opens away from [actor] (if given). Result {ok, reason}.
func open_door(actor: Node = null) -> Dictionary:
	if state == STATE_OPEN:
		return {"ok": false, "reason": "Already open"}
	if locked:
		return {"ok": false, "reason": "Locked"}
	if on_cooldown():
		return {"ok": false, "reason": "Busy"}
	var angle := _swing_for(actor)
	if _blocked_at(angle):
		return {"ok": false, "reason": "Blocked"}
	_swing = angle
	state = STATE_OPEN
	_mark_toggled()
	_animate_to(_swing)
	EventBus.door_state_changed.emit(self, state)
	return {"ok": true}


func close_door() -> Dictionary:
	if state == STATE_CLOSED:
		return {"ok": false, "reason": "Already closed"}
	if on_cooldown():
		return {"ok": false, "reason": "Busy"}
	if _blocked_at(0.0):
		return {"ok": false, "reason": "Blocked"}
	state = STATE_CLOSED
	_swing = 0.0
	_mark_toggled()
	_animate_to(0.0)
	EventBus.door_state_changed.emit(self, state)
	return {"ok": true}


func _animate_to(angle: float) -> void:
	if not is_inside_tree():
		_kill_tween()
		rotation.y = angle
		return
	_new_tween().tween_property(self, "rotation:y", angle, swing_seconds)
