class_name WorldQuery
extends RefCounted
## Static world lookups for AI code that must not depend on building or
## navigation node types: "is this point indoors?", "random reachable point".
## Everything goes through groups / the NavigationServer.


## True when [p] lies inside any building room ([margin] metres of
## tolerance around each room).
static func is_inside_building(tree: SceneTree, p: Vector3, margin: float = 0.0) -> bool:
	for b in tree.get_nodes_in_group(&"building"):
		if b.has_method(&"room_at") and b.room_at(p, margin) != null:
			return true
	return false


## Closest navmesh point to [p] on [map] (p itself when the map is invalid).
static func closest_nav_point(map: RID, p: Vector3) -> Vector3:
	if not map.is_valid():
		return p
	return NavigationServer3D.map_get_closest_point(map, p)


## Random navmesh point within [radius] of [center], Y set to [ground_y].
## With [avoid_buildings] indoor points are re-rolled up to [tries] times.
static func random_nav_point(map: RID, rng: RandomNumberGenerator, center: Vector3, radius: float,
		ground_y: float, avoid_buildings: bool = false, tree: SceneTree = null, tries: int = 4) -> Vector3:
	var q := center
	for attempt in (tries if avoid_buildings else 1):
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		q = closest_nav_point(map, center + Vector3(cos(a) * r, 0.0, sin(a) * r))
		q.y = ground_y
		if not avoid_buildings or tree == null or not is_inside_building(tree, q):
			return q
	return q
