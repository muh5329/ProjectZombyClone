class_name Saveable
extends RefCounted
## The save contract (Round 10) + small JSON helpers.
##
## A STATIC persistent object (placed by the map or generated
## deterministically by a building: containers, doors, windows,
## furniture) joins group [GROUP], exposes a stable, unique
## `persist_id` (String) and implements
##     save_state() -> Dictionary       (JSON-safe: no Vector3, no INF)
##     load_state(d: Dictionary) -> void (silent: no sounds, no events that
##                                        start gameplay reactions)
## Optional: `remove_for_load()` — called when the object exists in the
## fresh scene but not in the save (it was destroyed: furniture taken
## apart / smashed). Objects without it keep their default state.
##
## DYNAMIC objects (dropped items, zombies, corpses) are not in the group:
## WorldSnapshot records them as spawn records and re-creates them.
## Ids must be deterministic across runs: map-placed nodes use an exported
## id, generated ones derive it from the building id + build order.

const GROUP := &"saveable"


## Every saveable under [root] (or the whole tree when null), with an id.
static func collect(tree: SceneTree, root: Node = null) -> Array[Node]:
	var out: Array[Node] = []
	for n in tree.get_nodes_in_group(GROUP):
		if root != null and not root.is_ancestor_of(n):
			continue
		if n.is_queued_for_deletion() or not n.has_method(&"save_state"):
			continue
		if String(n.get(&"persist_id")) == "":
			continue
		out.append(n)
	return out


# --- JSON-safe conversions ---------------------------------------------------------

static func vec3(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func to_vec3(a: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	if a is Vector3:
		return a
	return fallback


## Transform as 12 floats (basis columns x, y, z + origin).
static func xform(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func to_xform(a: Variant) -> Transform3D:
	if not a is Array or (a as Array).size() < 12:
		return Transform3D.IDENTITY
	var f: Array = a
	return Transform3D(Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8])),
		Vector3(f[9], f[10], f[11]))


## INF / NAN are not JSON: -1 stands for "infinite" in saved timers.
static func finite_or(v: float, fallback: float = -1.0) -> float:
	return v if is_finite(v) else fallback
