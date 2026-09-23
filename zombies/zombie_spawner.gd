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
	var near := clampi(near_count, 0, count)
	for i in count:
		var p := pick_spawn_point() if i < count - near else pick_spawn_point(near_center, near_radius, near_min_player_distance)
		if p == Vector3.INF:
			push_warning("ZombieSpawner: no valid spawn point for zombie %d" % i)
			continue
		out.append(spawn_at(p))
	spawned.emit(out)
	return out


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
	return {"spawn_counter": spawn_counter, "rng_state": str(rng.state)}


func load_state(d: Dictionary) -> void:
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
