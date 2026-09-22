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
## Navmesh points higher than this are prop tops (car roofs) — rejected.
@export var max_spawn_height: float = 0.75

## Stable id prefix of this spawner's zombies ("" → the node path relative
## to the scene owner, e.g. "Zombies"). Zombies get
## spawn_id = "<spawner_id>/<n>" with a monotonically increasing n, so
## corpse loot ids never collide (even for two spawners on one seed).
@export var spawner_id: String = ""

var zombies: Array[Zombie] = []
## Zombies ever spawned by this spawner (never decreases).
var spawn_counter: int = 0
var rng := RandomNumberGenerator.new()
var _nav: NavBaker


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
	if _nav != null and not _nav.baked:
		await _nav.navigation_ready
	if not auto_spawn or not is_inside_tree():
		return
	spawn_initial()


func spawn_initial() -> Array[Zombie]:
	var out: Array[Zombie] = []
	for i in count:
		var p := pick_spawn_point()
		if p == Vector3.INF:
			push_warning("ZombieSpawner: no valid spawn point for zombie %d" % i)
			continue
		out.append(spawn_at(p))
	spawned.emit(out)
	return out


## A valid spawn point, or Vector3.INF when none was found in 60 tries.
func pick_spawn_point() -> Vector3:
	var map := get_world_3d().navigation_map
	var player := GameManager.player as Node3D
	for attempt in 60:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * spawn_radius
		var p := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q.distance_to(p) > 1.5 or q.y > max_spawn_height:
			continue
		if player != null and is_instance_valid(player):
			var d := q - player.global_position
			d.y = 0.0
			if d.length() < min_player_distance:
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
	z.ai_seed = rng.randi() | 1
	spawn_counter += 1
	z.spawn_id = "%s/%d" % [stable_id(), spawn_counter]
	z.name = "Zombie%d" % (zombies.size() + 1)
	z.position = to_local(Vector3(p.x, p.y + 0.05, p.z))
	add_child(z)
	zombies.append(z)
	return z


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
