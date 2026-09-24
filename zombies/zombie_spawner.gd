class_name ZombieSpawner
extends Node3D
## Spawns zombies on the navmesh at map load: [count] of them at random
## navmesh points within [spawn_radius] of this node, at least
## [min_player_distance] from the player and never inside a building
## (WorldQuery + a margin). Deterministic through [seed] so tests and
## screenshot runs repeat; each zombie gets its own derived ai_seed.
## spawn_at() places one zombie anywhere (tests, later the population sim).

signal spawned(zombies: Array)

@export var zombie_scene: PackedScene = preload("res://zombies/zombie.tscn")
@export var profile: ZombieProfile
@export var count: int = 10
@export var seed: int = 1337
@export var min_player_distance: float = 15.0
@export var spawn_radius: float = 35.0
## Points closer than this to a building room are rejected.
@export var building_margin: float = 1.5
## Spawn automatically once the NavBaker reports the mesh (tests set false).
@export var auto_spawn: bool = true
## The region to wait for; defaults to the first NavBaker in the parent.
@export var nav_path: NodePath
## Round 10: how many of [count] start in a "near" zone (the street by
## House A, so a smashed window is heard) instead of anywhere in the
## spawn radius; they keep [near_min_player_distance] from the player.
@export var near_count: int = 0
@export var near_center: Vector3 = Vector3.ZERO
@export var near_radius: float = 4.0
@export var near_min_player_distance: float = 8.0
## Navmesh points higher than this are prop tops (car roofs) — rejected.
@export var max_spawn_height: float = 0.75
## Round 11: explicit start positions (feet, world space; the generated
## world's population from WorldLayout.zombies). When set, spawn_initial()
## spawns one zombie per point (snapped to the navmesh; an unusable point
## is re-picked within 6 m) instead of [count] random picks.
@export var spawn_points: PackedVector3Array = PackedVector3Array()

## Stable id prefix of this spawner's zombies ("" → the node path relative
## to the scene owner, e.g. "Zombies"). Zombies get
## spawn_id = "<spawner_id>/<n>" with a monotonically increasing n, so
## corpse loot ids never collide (even for two spawners on one seed).
@export var spawner_id: String = ""

## Round 11: rural groups ({id, chunk: Vector2i, points: PackedVector2Array}
## from WorldLayout.zombie_groups), spawned once when their chunk's
## navmesh is live (WorldNav.chunk_ready). Spawned ids are saved.
var groups: Array = []
var groups_spawned: Dictionary = {}

var zombies: Array[Zombie] = []
## Zombies ever spawned by this spawner (never decreases).
var spawn_counter: int = 0
var rng := RandomNumberGenerator.new()
var _nav: NavBaker
## Start points that were not usable yet (navmesh lagging): retried.
var _retry: Array[Vector3] = []
var _retry_rounds: int = 0
var _tick: float = 0.0
var _started: bool = false


func _ready() -> void:
	rng.seed = seed
	_nav = _find_nav()
	if auto_spawn:
		_spawn_when_ready()


func _find_nav() -> NavBaker:
	if not nav_path.is_empty():
		return get_node_or_null(nav_path) as NavBaker
	var parent := get_parent()
	if parent:
		for c in parent.get_children():
			if c is NavBaker:
				return c
	return null


func _spawn_when_ready() -> void:
	# A one-shot signal connection, not a coroutine: nothing is left
	# suspended when the map is freed before the navmesh is ready.
	if _nav != null and not _nav.baked:
		if not _nav.navigation_ready.is_connected(_on_nav_ready):
			_nav.navigation_ready.connect(_on_nav_ready, CONNECT_ONE_SHOT)
		return
	_on_nav_ready()


func _on_nav_ready() -> void:
	if not auto_spawn or not is_inside_tree():
		return
	spawn_initial()


func spawn_initial() -> Array[Zombie]:
	var out: Array[Zombie] = []
	_started = true
	if not spawn_points.is_empty():
		for i in spawn_points.size():
			var p := _point_near(spawn_points[i])
			if p == Vector3.INF:
				# The navmesh may still lag behind (heavy load): retry later
				# instead of warning per point.
				_retry.append(spawn_points[i])
				continue
			out.append(spawn_at(p))
		spawned.emit(out)
		return out
	var near := clampi(near_count, 0, count)
	for i in count:
		var p := pick_spawn_point() if i < count - near else pick_spawn_point(near_center, near_radius, near_min_player_distance)
		if p == Vector3.INF:
			push_warning("ZombieSpawner: no valid spawn point for zombie %d" % i)
			continue
		out.append(spawn_at(p))
	spawned.emit(out)
	return out


## A usable point at [p] or re-picked within 6 m (INF when none).
func _point_near(p: Vector3) -> Vector3:
	var q := _usable_point(p)
	if q == Vector3.INF:
		q = pick_spawn_point(p, 6.0, min_player_distance)
	return q


func _physics_process(delta: float) -> void:
	if _retry.is_empty() and (groups.is_empty() or groups_spawned.size() >= groups.size()):
		return
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	if not _retry.is_empty():
		_retry_rounds += 1
		var left: Array[Vector3] = []
		var got: Array = []
		for q in _retry:
			var p := _point_near(q)
			if p == Vector3.INF:
				left.append(q)
			else:
				got.append(spawn_at(p))
		_retry = left
		if not got.is_empty():
			spawned.emit(got)
		if not _retry.is_empty() and _retry_rounds >= 20:
			push_warning("ZombieSpawner: %d start points had no valid spawn spot" % _retry.size())
			_retry.clear()
	_spawn_groups()


## Rural groups whose chunk navmesh is live now (WorldNav only).
func _spawn_groups() -> void:
	if not _started or _nav == null or not _nav.baked or not _nav.has_method(&"chunk_ready"):
		return
	for g in groups:
		var gid := String(g.id)
		if groups_spawned.has(gid) or not bool(_nav.call(&"chunk_ready", g.chunk)):
			continue
		groups_spawned[gid] = true
		var got: Array = []
		for q2 in (g.points as PackedVector2Array):
			var p := _point_near(Vector3(q2.x, 0.0, q2.y))
			if p != Vector3.INF:
				got.append(spawn_at(p))
		if not got.is_empty():
			spawned.emit(got)


## Round 12 (population director): a usable spot at [p] or within
## [radius] m, at most [tries] navmesh queries (the population instantiates
## many zombies; pick_spawn_point's 60 tries cost tens of ms when a spot is
## blocked). INF when none.
func find_spot(p: Vector3, radius: float = 4.0, tries: int = 5) -> Vector3:
	var q := _usable_point(p)
	if q != Vector3.INF:
		return q
	for i in tries:
		var a := rng.randf() * TAU
		var r := radius * sqrt(rng.randf())
		q = _usable_point(p + Vector3(cos(a) * r, 0.0, sin(a) * r))
		if q != Vector3.INF:
			return q
	return Vector3.INF


## [p] snapped to the navmesh when it is a valid spawn spot (INF otherwise).
func _usable_point(p: Vector3) -> Vector3:
	var q := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)
	if q.distance_to(p) > 1.5 or q.y > max_spawn_height:
		return Vector3.INF
	if WorldQuery.is_inside_building(get_tree(), q, building_margin):
		return Vector3.INF
	return Vector3(q.x, 0.0, q.z)


## A valid spawn point, or Vector3.INF when none was found in 60 tries.
## Default: anywhere within spawn_radius of this node; [center] / [radius]
## / [min_dist] (when radius > 0) pick in a zone instead.
func pick_spawn_point(center: Vector3 = Vector3.INF, radius: float = -1.0, min_dist: float = -1.0) -> Vector3:
	var map := get_world_3d().navigation_map
	var player := GameManager.player as Node3D
	var c := global_position if center == Vector3.INF else center
	var rad := spawn_radius if radius <= 0.0 else radius
	var keep := min_player_distance if min_dist < 0.0 else min_dist
	for attempt in 60:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * rad
		var p := c + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q.distance_to(p) > 1.5 or q.y > max_spawn_height:
			continue
		if player != null and is_instance_valid(player):
			var d := q - player.global_position
			d.y = 0.0
			if d.length() < keep:
				continue
		if WorldQuery.is_inside_building(get_tree(), q, building_margin):
			continue
		return Vector3(q.x, 0.0, q.z)
	return Vector3.INF


## Spawn one zombie at [p] (feet position). Returns it after it is in the tree.
func spawn_at(p: Vector3, p_profile: ZombieProfile = null) -> Zombie:
	var z: Zombie = zombie_scene.instantiate()
	if p_profile != null:
		z.profile = p_profile
	elif profile != null:
		z.profile = profile
	z.ai_seed = next_seed(rng)
	spawn_counter += 1
	z.spawn_id = "%s/%d" % [stable_id(), spawn_counter]
	z.name = "Zombie%d" % (zombies.size() + 1)
	z.position = to_local(Vector3(p.x, p.y + 0.05, p.z))
	add_child(z)
	zombies.append(z)
	return z


## The per-zombie seed drawn from the spawner's rng (never 0). Static so
## tests can reproduce real spawn seeds.
static func next_seed(r: RandomNumberGenerator) -> int:
	return r.randi() | 1


func stable_id() -> String:
	if spawner_id != "":
		return spawner_id
	if owner != null and owner != self:
		return String(owner.get_path_to(self))
	return String(name)


func alive_count() -> int:
	var n := 0
	for z in zombies:
		if is_instance_valid(z) and not z.dead:
			n += 1
	return n


# --- Save (Round 10) ------------------------------------------------------------------

## Spawner bookkeeping: the spawn counter (ids stay unique after a load)
## and the rng state (64-bit → a String: JSON numbers are doubles).
func save_state() -> Dictionary:
	var gs: Array = groups_spawned.keys()
	gs.sort()
	return {"spawn_counter": spawn_counter, "rng_state": str(rng.state), "groups_spawned": gs}


func load_state(d: Dictionary) -> void:
	_started = true
	for gid in (d.get("groups_spawned", []) as Array):
		groups_spawned[String(gid)] = true
	spawn_counter = maxi(int(d.get("spawn_counter", spawn_counter)), spawn_counter)
	var st := String(d.get("rng_state", ""))
	if st.is_valid_int():
		rng.state = st.to_int()


## Re-create a living zombie from Zombie.save_record() (never re-rolls
## anything: same id, same look, same place).
func restore_zombie(d: Dictionary) -> Zombie:
	var z: Zombie = zombie_scene.instantiate()
	var by_id := ZombieProfile.by_id(String(d.get("profile", "")))
	if by_id != null:
		z.profile = by_id
	elif profile != null:
		z.profile = profile
	z.ai_seed = int(d.get("seed", 0))
	if z.ai_seed == 0:
		z.ai_seed = next_seed(rng)
	z.spawn_id = String(d.get("spawn_id", ""))
	z.name = "Zombie%d" % (zombies.size() + 1)
	z.position = to_local(Saveable.to_vec3(d.get("position")))
	add_child(z)
	zombies.append(z)
	z.apply_record(d)
	return z
