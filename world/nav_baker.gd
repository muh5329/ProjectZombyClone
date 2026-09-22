class_name NavBaker
extends NavigationRegion3D
## Bakes the walkable navigation mesh at runtime from the static colliders
## on physics layer 1 (world: ground, walls, windows, props). Door leaves
## live on layer 7 so doorways bake as passable; a zombie facing a closed
## door attacks it instead of re-pathing (see ZombieAI).
##
## Baking runs on a thread after [wait_frames] physics frames so generated
## buildings (HouseBlockout) exist and their shapes are in the tree.
## Listeners await [signal navigation_ready] / check [baked].

signal navigation_ready

## Physics frames to wait before baking (buildings generate in _ready).
@export var wait_frames: int = 2
## Only geometry inside this box (world space) is baked. Keeps the bake
## fast on the 200 m test ground; streaming (later) bakes per chunk.
@export var bake_aabb: AABB = AABB(Vector3(-50, -2, -50), Vector3(100, 8, 100))
## Multiples of cell_size / cell_height bake exactly (no rounding warnings).
@export var agent_radius: float = 0.3
@export var agent_height: float = 1.5
@export var cell_size: float = 0.15
@export var cell_height: float = 0.1
## Physics layers parsed as obstacles (1 = world).
@export_flags_3d_physics var geometry_mask: int = 1
## Set false to bake manually (tests / editors).
@export var bake_on_ready: bool = true

var baked: bool = false
var bake_ms: float = 0.0
var _bake_started_at: int = 0


func _ready() -> void:
	if navigation_mesh == null:
		navigation_mesh = NavigationMesh.new()
	var nm := navigation_mesh
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = geometry_mask
	# Parse the whole map (the parent and everything under it), not only
	# this region's children.
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = &"navigation_mesh_source_group"
	var source := get_parent()
	if source != null:
		source.add_to_group(nm.geometry_source_group_name)
	nm.agent_radius = agent_radius
	nm.agent_height = agent_height
	nm.agent_max_climb = 0.3
	nm.cell_size = cell_size
	nm.cell_height = cell_height
	nm.filter_baking_aabb = bake_aabb
	nm.filter_baking_aabb_offset = Vector3.ZERO
	bake_finished.connect(_on_bake_finished)
	if bake_on_ready:
		_bake_later()


func _bake_later() -> void:
	for i in maxi(wait_frames, 0):
		await get_tree().physics_frame
	if not is_inside_tree():
		return
	bake_now()


## Start (re)baking. Async: wait for [signal navigation_ready].
func bake_now() -> void:
	if is_baking():
		return
	baked = false
	_bake_started_at = Time.get_ticks_msec()
	bake_navigation_mesh(true)


func _on_bake_finished() -> void:
	bake_ms = float(Time.get_ticks_msec() - _bake_started_at)
	# The NavigationServer syncs the new mesh into the map on a later
	# physics step; queries before that return nothing. Wait for the map
	# iteration to advance (bounded).
	var map := get_navigation_map()
	var it0 := NavigationServer3D.map_get_iteration_id(map)
	for i in 60:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) != it0 and navigation_mesh.get_polygon_count() > 0:
			break
	await get_tree().physics_frame
	baked = true
	navigation_ready.emit()


## Closest point on the baked mesh to [p].
func closest_point(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_navigation_map(), p)


## Distance from [p] to the navmesh (0 when on it).
func distance_to_mesh(p: Vector3) -> float:
	return closest_point(p).distance_to(p)
