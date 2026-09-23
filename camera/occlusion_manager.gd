class_name OcclusionManager
extends Node
## Project-Zomboid-style cutaway. Runs at [update_hz] in physics time.
##
## Inside a Building (Room.contains_point, with hysteresis so thresholds
## never flicker):
##   - the building's roofs (group "roof") are hidden,
##   - wall segments (group "wall", incl. doors/windows) whose outward normal
##     faces the eye are reduced to a [stub_height] stub; interior walls of
##     the current room lying between the player and the eye are stubbed
##     too. Only the "Visual" child is scaled — collision stays full height.
## Outside (and additionally inside): anything on physics layer 6
## ("occluders", group "occluder") hit by a ray from the eye to the player
## is faded to [fade_alpha] with a per-instance `material_override` (a
## duplicate of the mesh's material; `MeshInstance3D.transparency` is a
## no-op in the Compatibility renderer). Shared materials are never touched.
##
## All transitions tween over [tween_seconds]; a node's state only changes
## when its desired state changes, so nothing thrashes. Everything is found
## through groups and metadata — no type checks against buildings. Wall /
## roof lists are cached per building while the player is inside.

const STATE_FULL := &"full"
const STATE_STUB := &"stub"
const STATE_FADED := &"faded"
const STATE_HIDDEN := &"hidden"

@export var update_hz: float = 10.0
@export var stub_height: float = 0.35
@export var fade_alpha: float = 0.15
@export var tween_seconds: float = 0.2
## Exterior wall is cut when dot(outward, towards-eye) exceeds this.
@export var facing_threshold: float = 0.3
## Interior wall is cut when it lies at least this far (m) on the eye's
## side of the player.
@export var interior_side_distance: float = 0.3
## Room hysteresis: keep the current room while within this distance (m).
@export var room_exit_margin: float = 0.35
@export var max_ray_hits: int = 8
## Optional explicit camera rig; otherwise the first node in group
## "isometric_camera" is used.
@export var camera_path: NodePath

var current_building: Node = null
var current_room: Node = null
## Node -> current state.
var states: Dictionary = {}

var _accum: float = 0.0
var _tweens: Dictionary = {}
var _meshes: Dictionary = {}  # node -> Array[MeshInstance3D]
var _rig: Node = null
var _cached_walls: Array[Node] = []
var _cached_roofs: Array[Node] = []
var _cache_building: Node = null
var _ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []


func _ready() -> void:
	add_to_group(&"occlusion_manager")
	_ray_query.collision_mask = 1 << 5
	_ray_query.collide_with_areas = false


func _rig_node() -> Node:
	if is_instance_valid(_rig):
		return _rig
	if not camera_path.is_empty():
		_rig = get_node_or_null(camera_path)
	if _rig == null:
		var list := get_tree().get_nodes_in_group(&"isometric_camera")
		_rig = list[0] if not list.is_empty() else null
	return _rig


func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < 1.0 / maxf(update_hz, 0.01):
		return
	_accum = 0.0
	update_now()


func state_of(node: Node) -> StringName:
	return states.get(node, STATE_FULL)


func _eye_height(player: Node) -> float:
	if player.has_method(&"eye_height"):
		return player.eye_height()
	return 0.9


## Recompute desired states and start transitions. Safe to call from tests.
func update_now() -> void:
	var player := GameManager.player as Node3D
	var rig := _rig_node()
	if player == null or rig == null or not player.is_inside_tree():
		_apply({})
		_set_location(null, null)
		return
	var ppos := player.global_position
	var loc := Building.locate(get_tree(), ppos + Vector3.UP * 0.5, current_room, room_exit_margin)
	_set_location(loc.building, loc.room)

	var desired: Dictionary = {}
	var eye_dir: Vector3 = rig.view_direction_flat()
	if loc.building != null:
		for r in _roofs_of(loc.building):
			desired[r] = STATE_HIDDEN
		for w in _walls_of(loc.building):
			if _wall_should_cut(w, ppos, eye_dir, loc.room):
				desired[w] = STATE_STUB

	var focus := ppos + Vector3.UP * _eye_height(player)
	var origin: Vector3 = rig.eye_position_for(focus)
	for hit in _ray_hits(origin, focus, player):
		if not desired.has(hit) and hit.is_in_group(&"occluder"):
			desired[hit] = STATE_FADED
	_apply(desired)


func _walls_of(building: Node) -> Array[Node]:
	_ensure_cache(building)
	_prune(_cached_walls)
	return _cached_walls


func _roofs_of(building: Node) -> Array[Node]:
	_ensure_cache(building)
	_prune(_cached_roofs)
	return _cached_roofs


## Drop nodes freed since the cache was built (e.g. a smashed-out window).
static func _prune(list: Array[Node]) -> void:
	for i in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]) or not list[i].is_inside_tree():
			list.remove_at(i)


func _ensure_cache(building: Node) -> void:
	if building == _cache_building:
		return
	_invalidate_cache()
	_cache_building = building
	if building.has_method(&"get_walls"):
		_cached_walls = building.get_walls()
	if building.has_method(&"get_roofs"):
		_cached_roofs = building.get_roofs()
	if not building.tree_exiting.is_connected(_invalidate_cache):
		building.tree_exiting.connect(_invalidate_cache)


func _invalidate_cache() -> void:
	if is_instance_valid(_cache_building) and _cache_building.tree_exiting.is_connected(_invalidate_cache):
		_cache_building.tree_exiting.disconnect(_invalidate_cache)
	_cache_building = null
	_cached_walls = []
	_cached_roofs = []


func _wall_should_cut(wall: Node, ppos: Vector3, eye_dir: Vector3, room: Node = null) -> bool:
	if not wall is Node3D:
		return false
	var w := wall as Node3D
	var outward: Vector3 = wall.get_meta(&"outward", Vector3.ZERO)
	if outward.length_squared() > 0.5:
		return outward.normalized().dot(eye_dir) > facing_threshold
	# Interior: only walls bounding the current room, whose normal faces the
	# eye and which lie on the eye's side of the player. Other rooms keep
	# their partitions so the floor plan stays readable.
	if room != null and room.has_method(&"contains_point"):
		var wp := w.global_position
		if not room.contains_point(Vector3(wp.x, ppos.y + 0.5, wp.z)):
			return false
	var n := w.global_basis.z
	n.y = 0.0
	if n.length_squared() < 0.0001:
		return false
	n = n.normalized()
	var facing := n.dot(eye_dir)
	if absf(facing) < facing_threshold:
		return false
	var d := w.global_position - ppos
	d.y = 0.0
	var s := d.dot(n)  # signed distance from player to wall plane
	return s * facing > interior_side_distance


func _ray_hits(from: Vector3, to: Vector3, player: Node3D) -> Array[Node]:
	var out: Array[Node] = []
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return out
	_exclude.clear()
	if player is CollisionObject3D:
		_exclude.append((player as CollisionObject3D).get_rid())
	_ray_query.from = from
	_ray_query.to = to
	for i in max_ray_hits:
		_ray_query.exclude = _exclude
		var hit := space.intersect_ray(_ray_query)
		if hit.is_empty():
			break
		var col: Node = hit.get("collider")
		if col == null:
			break
		out.append(col)
		_exclude.append(hit["rid"])
	return out


func _set_location(building: Node, room: Node) -> void:
	if building == current_building and room == current_room:
		return
	current_building = building
	current_room = room
	if building == null:
		_invalidate_cache()
	EventBus.player_room_changed.emit(room, building)


func _apply(desired: Dictionary) -> void:
	var all: Dictionary = {}
	for n in states:
		all[n] = true
	for n in desired:
		all[n] = true
	for n in all:
		if not is_instance_valid(n):
			states.erase(n)
			_tweens.erase(n)
			_meshes.erase(n)
			continue
		var target: StringName = desired.get(n, STATE_FULL)
		if state_of(n) == target:
			continue
		_transition(n, target)


func _visual_of(n: Node) -> Node3D:
	var v := n.get_node_or_null("Visual")
	if v is Node3D:
		return v
	# BlockoutBox-style nodes: no Visual child. Fall back to the node itself.
	return n as Node3D


## All MeshInstance3D under [n] (cached per node; instances, not materials).
func _meshes_of(n: Node) -> Array:
	if _meshes.has(n):
		return _meshes[n]
	var out: Array = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			out.append(cur)
		for c in cur.get_children():
			stack.append(c)
	_meshes[n] = out
	return out


func _transition(n: Node, target: StringName) -> void:
	states[n] = target
	if _tweens.has(n):
		var old: Tween = _tweens[n]
		if old and old.is_valid():
			old.kill()
	var visual := _visual_of(n)
	var meshes := _meshes_of(n)
	var wall_h := float(n.get_meta(&"wall_height", 2.7))
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_parallel(true)
	_tweens[n] = tw
	match target:
		STATE_FULL:
			if visual:
				visual.visible = true
				tw.tween_property(visual, "scale:y", 1.0, tween_seconds)
			_fade_to(meshes, tw, 1.0)
			var holder := [n, meshes]
			tw.finished.connect(func():
				if state_of(holder[0]) == STATE_FULL:
					# Untyped: a cached mesh may have been freed meanwhile.
					for mv: Variant in holder[1]:
						if is_instance_valid(mv) and (mv as MeshInstance3D).has_meta(&"occl_base_alpha"):
							(mv as MeshInstance3D).material_override = null
							(mv as MeshInstance3D).remove_meta(&"occl_base_alpha"))
		STATE_STUB:
			if visual:
				visual.visible = true
				tw.tween_property(visual, "scale:y", clampf(stub_height / maxf(wall_h, 0.01), 0.02, 1.0), tween_seconds)
			_fade_to(meshes, tw, 1.0)
		STATE_FADED:
			if visual:
				visual.visible = true
				tw.tween_property(visual, "scale:y", 1.0, tween_seconds)
			_fade_to(meshes, tw, fade_alpha)
		STATE_HIDDEN:
			_fade_to(meshes, tw, 0.0)
			var holder := [n, visual]
			tw.finished.connect(func():
				if is_instance_valid(holder[1]) and state_of(holder[0]) == STATE_HIDDEN:
					holder[1].visible = false)


## Tween each mesh instance's alpha towards base_alpha * [alpha_scale]
## through a per-instance material override.
func _fade_to(meshes: Array, tw: Tween, alpha_scale: float) -> void:
	for mv: Variant in meshes:
		if not is_instance_valid(mv):
			continue
		var mi := mv as MeshInstance3D
		var m := _fade_material(mi)
		if m == null:
			continue
		var target_a: float = float(mi.get_meta(&"occl_base_alpha", 1.0)) * alpha_scale
		if alpha_scale > 0.0:
			# Some meshes (vehicles) never fade below their floor (R8.5).
			target_a = maxf(target_a, float(mi.get_meta(&"occl_min_alpha", 0.0)))
		tw.tween_property(m, "albedo_color:a", target_a, tween_seconds)


## The per-instance override used for fading (created on first use from a
## duplicate of the active material, so the shared one is never mutated).
func _fade_material(mi: MeshInstance3D) -> StandardMaterial3D:
	if mi.has_meta(&"occl_base_alpha") and mi.material_override is StandardMaterial3D:
		return mi.material_override
	var base := mi.get_active_material(0)
	var m: StandardMaterial3D
	if base is StandardMaterial3D:
		m = (base as StandardMaterial3D).duplicate()
	else:
		m = StandardMaterial3D.new()
	mi.set_meta(&"occl_base_alpha", m.albedo_color.a)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if mi.get_meta(&"occl_depth_always", false):
		# Keep writing depth while faded: the mesh's own inner faces are
		# hidden (no x-ray through a car), what is behind still shows.
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mi.material_override = m
	return m
