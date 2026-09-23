class_name WallFixture
extends StaticBody3D
## Base for things set into a wall opening (Door, HouseWindow).
##
## Provides the shared contract the rest of the game relies on:
## - physics layers 1 (world) + 4 (interactables) + 6 (occluders),
## - groups "wall", "occluder" and an extra [fixture_group],
## - metadata "outward" / "wall_height" for the occlusion cutaway,
## - a "Visual" child with its origin at floor level (occlusion scales it),
## - an auto-attached Interactable component,
## - small helpers: _box() mesh builder and a tween-kill helper.
## Subclasses implement _build_visual() and the Interactable provider API.

## Height of the wall this fixture sits in (occlusion stub scaling).
@export var wall_height: float = 2.7
## Outward normal of the wall (ZERO for interior walls) for the cutaway.
@export var outward: Vector3 = Vector3.ZERO
## Sounds start this far from the opening, on the actor's side.
const SOUND_SIDE_OFFSET := 0.3

## Seconds between two state changes (spam-safe, not arcade).
@export var toggle_cooldown: float = 0.5

var visual: Node3D
## Physics-time timestamp (seconds) of the last state change.
var _last_toggle_time: float = -1000.0
var _tween: Tween

## Group name added by the subclass ("door", "window").
var fixture_group: StringName = &""


func _ready() -> void:
	collision_layer = (1 << 0) | (1 << 3) | (1 << 5)
	collision_mask = 0
	add_to_group(&"wall")
	add_to_group(&"occluder")
	if fixture_group != &"":
		add_to_group(fixture_group)
	set_meta(&"outward", outward)
	set_meta(&"wall_height", wall_height)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_build_visual()
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)


func _build_visual() -> void:
	pass


## Seconds of physics time since the scene started.
static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 if Engine.is_editor_hint() else Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


# --- Sound propagation (Round 8, SoundManager) -----------------------------------

## True when sound passes freely through this opening (open / broken).
func sound_passes() -> bool:
	return false


## Centre of the opening at floor level (sound escaping through it).
func sound_opening_center() -> Vector3:
	return global_position


## Horizontal normal of the wall this fixture sits in (either side).
func wall_normal() -> Vector3:
	var n := global_basis.z
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.BACK


## Where a sound made by / at this fixture starts: [SOUND_SIDE_OFFSET] m
## off the opening centre, on [actor]'s side (outward when no actor), at
## floor level — never inside the leaf / wall, so the fixture itself
## muffles it for the other side.
func sound_position(actor: Node = null) -> Vector3:
	var c := sound_opening_center()
	var n := wall_normal()
	var side := 1.0
	if actor is Node3D and is_instance_valid(actor):
		side = 1.0 if ((actor as Node3D).global_position - c).dot(n) >= 0.0 else -1.0
	elif outward.length_squared() > 0.5:
		side = 1.0 if outward.dot(n) >= 0.0 else -1.0
	var p := c + n * side * SOUND_SIDE_OFFSET
	p.y = global_position.y
	return p


## How much this fixture muffles a sound ray that hits it (SoundMath kind).
func sound_obstacle_kind() -> StringName:
	return SoundMath.WALL


# --- Barricades (Round 9, BarricadeComponent) ------------------------------------

## Planks nailed across this opening (0 when none).
func barricade_planks() -> int:
	return BarricadeComponent.planks_on(self)


func is_barricaded() -> bool:
	return barricade_planks() > 0


## Extra sound multiplier through this opening: ×0.8 per plank.
func sound_barricade_factor() -> float:
	var b := BarricadeComponent.of(self)
	return b.data.sound_factor(b.plank_count()) if b != null and b.data != null else 1.0


## The breakable a zombie must beat to get through: the barricade while it
## has planks, else the fixture itself.
func breakable_target() -> Node:
	var b := BarricadeComponent.of(self)
	if b != null and b.blocks_path():
		return b
	return self


## "" when planks may be nailed here now (subclasses: door must be closed…).
func barricade_block_reason(_actor: Node) -> String:
	return ""


## Called by BarricadeComponent after the plank count changed.
func on_barricade_changed(_planks: int) -> void:
	pass


func on_cooldown() -> bool:
	return _now() - _last_toggle_time < toggle_cooldown


func _mark_toggled() -> void:
	_last_toggle_time = _now()


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func _new_tween() -> Tween:
	_kill_tween()
	_tween = create_tween()
	_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return _tween


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, transparent: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = mat
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_shape(size: Vector3, pos: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = pos
	add_child(shape)
	return shape


## True if a body on [mask] overlaps a box of [size] at [local_pos] under
## [local_basis] (both in this node's local space).
func _box_blocked(size: Vector3, local_pos: Vector3, local_basis: Basis, mask: int) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	q.shape = bs
	q.collision_mask = mask
	q.collide_with_areas = false
	q.exclude = [get_rid()]
	q.transform = global_transform * Transform3D(local_basis, local_pos)
	return not space.intersect_shape(q, 1).is_empty()
