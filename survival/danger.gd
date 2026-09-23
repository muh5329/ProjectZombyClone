class_name Danger
extends RefCounted
## Static "is [target] in danger?" queries used by time fast-forward and
## sleep (Round 7). Zombies are found through the `zombie` group and
## duck-typed (`target`, `hostile`, `is_dead()`), so this imports no
## zombie types.


## Zombies currently chasing / attacking [target] (hostile with it as
## their target).
static func chasers(tree: SceneTree, target: Node) -> Array[Node]:
	var out: Array[Node] = []
	if tree == null or target == null:
		return out
	for z in tree.get_nodes_in_group(&"zombie"):
		if _alive(z) and bool(z.get("hostile")) and z.get("target") == target:
			out.append(z)
	return out


static func is_chased(tree: SceneTree, target: Node) -> bool:
	return not chasers(tree, target).is_empty()


## Flat distance to the nearest living zombie (INF when none).
static func nearest_zombie_distance(tree: SceneTree, at: Vector3) -> float:
	var best := INF
	if tree == null:
		return best
	for z in tree.get_nodes_in_group(&"zombie"):
		if not _alive(z) or not z is Node3D:
			continue
		var d := (z as Node3D).global_position - at
		d.y = 0.0
		best = minf(best, d.length())
	return best


## Player-facing reason [target] cannot relax (sleep / fast-forward) or ""
## when it is safe: chased by anything, or a zombie within [radius] m
## (radius ≤ 0 = only chasers count).
static func threat_reason(tree: SceneTree, target: Node3D, radius: float) -> String:
	if target == null:
		return ""
	if is_chased(tree, target):
		return "danger"
	if radius > 0.0 and nearest_zombie_distance(tree, target.global_position) <= radius:
		return "danger nearby"
	return ""


static func _alive(z: Node) -> bool:
	if z == null or not is_instance_valid(z) or not z.is_inside_tree():
		return false
	return not (z.has_method(&"is_dead") and bool(z.call(&"is_dead")))
