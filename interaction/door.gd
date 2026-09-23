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
##
## Physics: the leaf is on layer 7 ("doors") + 4 + 6, NOT layer 1, so the
## navigation mesh bakes doorways as passable; characters still collide
## with it through their masks. Zombies bang on closed doors through the
## "breakable" contract (group "breakable", take_damage(), blocks_path()):
## take_damage() lowers [health]; at 0 the door is "broken" — the leaf is
## gone (the body stays on layer 4 only so "Close door (Door is broken)"
## remains readable), the doorway is permanently open. Every bang emits
## door_banged + a 12 m door_bang sound so more zombies come. Sounds go
## through SoundManager (categories door_open / door_close / door_bang /
## door_break); a closed door muffles sounds passing through it (×0.6),
## an open or broken one lets them out (sound_passes()).

const STATE_CLOSED := &"closed"
const STATE_OPEN := &"open"
const STATE_BROKEN := &"broken"
## Physics layer index (0-based) of the "doors" layer.
const DOOR_LAYER_BIT := 6
## SoundManager categories (radii live in data/audio/sound_categories.tres).
const SOUND_OPEN := &"door_open"
const SOUND_CLOSE := &"door_close"
const SOUND_BANG := &"door_bang"
const SOUND_BREAK := &"door_break"
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
## Hit points before the door breaks. With a zombie's 8 damage every 2 s a
## single zombie needs ~75 s; a group of four ~20 s (axes later).
@export var health_max: float = 300.0

var state: StringName = STATE_CLOSED
var health: float = 300.0
var _block_query: PhysicsShapeQueryParameters3D
var _block_shape: BoxShape3D
## Signed swing angle of the last opening (radians), 0 when closed.
var _swing: float = 0.0
var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _init() -> void:
	fixture_group = &"door"


func _ready() -> void:
	super._ready()
	# Leaf on the doors layer (7), never on world (1): see class doc.
	collision_layer = (1 << DOOR_LAYER_BIT) | (1 << 3) | (1 << 5)
	health = health_max
	add_to_group(&"breakable")
	_block_shape = BoxShape3D.new()
	_block_shape.size = _leaf_size()
	_block_query = PhysicsShapeQueryParameters3D.new()
	_block_query.shape = _block_shape
	_block_query.collision_mask = BLOCK_MASK
	_block_query.collide_with_areas = false
	_block_query.exclude = [get_rid()]


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


## True when the doorway can be walked through (open or broken).
func is_open() -> bool:
	return state != STATE_CLOSED


func is_broken() -> bool:
	return state == STATE_BROKEN


## Breakable contract: a closed door is in the way.
func blocks_path() -> bool:
	return state == STATE_CLOSED


# --- Interactable provider API --------------------------------------------

func interaction_display_name() -> String:
	return "Door"


func interaction_prompt_position() -> Vector3:
	return _mesh.global_position if _mesh else global_position


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var busy := on_cooldown()
	if state == STATE_BROKEN:
		out.append(Interactable.action(ACTION_CLOSE, "Close door", false, "Door is broken"))
	elif state == STATE_CLOSED:
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
			return close_door(actor)
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
## Runs every physics tick while the door is targeted, so the query and
## shape are created once.
func _blocked_at(angle: float) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	# The query is expressed in this node's (currently rotated) space, so
	# only the difference between the target and current swing matters.
	var b := Basis(Vector3.UP, angle - rotation.y)
	_block_query.transform = global_transform * Transform3D(b, b * _leaf_offset())
	return not space.intersect_shape(_block_query, 1).is_empty()


## Opens away from [actor] (if given). Result {ok, reason}.
func open_door(actor: Node = null) -> Dictionary:
	if state == STATE_BROKEN:
		return {"ok": false, "reason": "Door is broken"}
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
	_emit_sound(SOUND_OPEN, actor)
	return {"ok": true}


func close_door(actor: Node = null) -> Dictionary:
	if state == STATE_BROKEN:
		return {"ok": false, "reason": "Door is broken"}
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
	# The slam is heard when the leaf is shut (so the leaf muffles it for
	# the far side).
	if _tween and _tween.is_valid():
		_tween.tween_callback(_emit_close.bind(weakref(actor) if actor != null else null))
	else:
		_emit_sound(SOUND_CLOSE, actor)
	return {"ok": true}


## Damage the door (zombie banging, later axes/sledgehammers). Returns
## {ok, broken, health}. A broken door is passable forever: the leaf and
## its collision are removed and door_state_changed(door, "broken") fires.
func take_damage(amount: float, source: Node = null, _info: Dictionary = {}) -> Dictionary:
	if state == STATE_BROKEN:
		return {"ok": false, "broken": true, "health": 0.0}
	if amount <= 0.0:
		return {"ok": false, "broken": false, "health": health}
	health = maxf(0.0, health - amount)
	EventBus.door_banged.emit(self, source)
	if health <= 0.0:
		_break(source)
		return {"ok": true, "broken": true, "health": 0.0}
	_emit_sound(SOUND_BANG, source)
	# Small shudder so banging reads visually (does not change collision).
	if _mesh and is_inside_tree():
		_new_tween().tween_property(_mesh, "position:x", _leaf_offset().x, 0.15).from(_leaf_offset().x + 0.04)
	return {"ok": true, "broken": false, "health": health}


func _break(source: Node) -> void:
	_kill_tween()
	state = STATE_BROKEN
	_swing = 0.0
	health = 0.0
	# Keep a collision shape so the broken door can still be targeted
	# (layer 4 only: nothing collides with it, the doorway is free).
	collision_layer = 1 << 3
	if visual:
		visual.visible = false
	_mark_toggled()
	EventBus.door_state_changed.emit(self, state)
	_emit_sound(SOUND_BREAK, source)


func _emit_close(actor_ref: WeakRef) -> void:
	var a: Variant = actor_ref.get_ref() if actor_ref != null else null
	_emit_sound(SOUND_CLOSE, a if a != null and is_instance_valid(a) else null)


## Sound 0.3 m off the doorway on [source]'s side (outward without one),
## floor level: a closed leaf muffles it for the other side.
func _emit_sound(category: StringName, source: Node) -> void:
	if not is_inside_tree():
		return
	SoundManager.emit_sound(category, sound_position(source), source)


# --- Sound propagation --------------------------------------------------------------

func sound_passes() -> bool:
	return is_open()


## Middle of the doorway: the mount sits at the hinge, the doorway runs
## along its local +X (the door body itself rotates when open).
func sound_opening_center() -> Vector3:
	var mount := get_parent() as Node3D
	if mount == null:
		return global_position
	return mount.global_transform * Vector3(width * 0.5, 0.0, 0.0)


## The doorway's wall normal (the mount's; the leaf itself swings).
func wall_normal() -> Vector3:
	var mount := get_parent() as Node3D
	var n := mount.global_basis.z if mount else global_basis.z
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.BACK


## A ray that hits a closed leaf is muffled ×0.6; one that clips an open
## leaf only a little.
func sound_obstacle_kind() -> StringName:
	return SoundMath.DOOR_CLOSED if state == STATE_CLOSED else SoundMath.PROP


func _animate_to(angle: float) -> void:
	if not is_inside_tree():
		_kill_tween()
		rotation.y = angle
		return
	_new_tween().tween_property(self, "rotation:y", angle, swing_seconds)
