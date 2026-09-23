class_name EntryPlanner
extends RefCounted
## How a zombie gets into a building (Round 9): one place that scores
## entry points, used by
## - HouseWindow.nav_cost() → the window's NavigationLink3D enter cost
##   (the navmesh then prefers cheap windows on its own), and
## - ZombieAI.consider_detour() → at a barricaded door / window, walk to
##   a clearly better opening of the same building instead.
##
## Scores are "metres of extra path": planks cost BarricadeData
## .nav_cost_per_plank (8) each, a closed window +CLOSED_WINDOW_COST (it
## must be smashed: 2 hits), a closed door +CLOSED_DOOR_COST (300 hp), a
## full set of attacker slots +QUEUE_COST (the crowd waits there).
##
## The exterior openings of a building are cached per building (group
## scans only once, freed fixtures pruned) — no node scans per call.

const CLOSED_WINDOW_COST := 2.0
const CLOSED_DOOR_COST := 10.0
const QUEUE_COST := 6.0
## Base link cost of an open / smashed window (a climb is slower than a
## doorway).
const OPEN_WINDOW_COST := 1.0
## Link cost of a closed window without planks (navmesh level: zombies
## still prefer a doorway unless the detour is long).
const CLOSED_WINDOW_LINK_COST := 10.0

## building instance id → Array[WeakRef] of its exterior doors / windows.
static var _cache: Dictionary = {}


## Pure: score of one entry (lower is better).
static func score(distance: float, planks: int, per_plank: float, closed_window: bool = false,
		closed_door: bool = false, slots_full: bool = false) -> float:
	return distance + planks * per_plank + (CLOSED_WINDOW_COST if closed_window else 0.0) \
		+ (CLOSED_DOOR_COST if closed_door else 0.0) + (QUEUE_COST if slots_full else 0.0)


## Pure: navigation-link cost of a window.
static func window_link_cost(closed: bool, planks: int, per_plank: float) -> float:
	return (CLOSED_WINDOW_LINK_COST if closed else OPEN_WINDOW_COST) + planks * per_plank


## The building a fixture belongs to (nearest ancestor in group "building").
static func building_of(n: Node) -> Node:
	var p := n.get_parent() if n != null else null
	while p != null:
		if p.is_in_group(&"building"):
			return p
		p = p.get_parent()
	return null


## Exterior doors / windows of [building] (cached).
static func openings(building: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if building == null or not building.is_inside_tree():
		return out
	var id := building.get_instance_id()
	if not _cache.has(id):
		var refs: Array = []
		for group: StringName in [&"door", &"window"]:
			for f in building.get_tree().get_nodes_in_group(group):
				if building.is_ancestor_of(f) and f.has_method(&"barricade_planks"):
					var o: Vector3 = f.get(&"outward")
					if o.length_squared() > 0.5:
						refs.append(weakref(f))
		_cache[id] = refs
	for r: WeakRef in _cache[id]:
		var f: Variant = r.get_ref()
		if f != null and is_instance_valid(f) and (f as Node).is_inside_tree():
			out.append(f)
	return out


## Forget a building (tests / rebuilt buildings).
static func invalidate(building: Node = null) -> void:
	if building == null:
		_cache.clear()
	else:
		_cache.erase(building.get_instance_id())


## Score of [fixture] seen from [from] (flat distance to its approach point).
static func entry_score_of(fixture: Node3D, from: Vector3, per_plank: float) -> Dictionary:
	var p: Vector3
	if fixture.has_method(&"approach_point"):
		p = fixture.call(&"approach_point", from)
	else:
		p = fixture.call(&"sound_opening_center")
		var n: Vector3 = fixture.call(&"wall_normal")
		p += n * (0.75 if (from - p).dot(n) >= 0.0 else -0.75)
	var d := Vector2(p.x - from.x, p.z - from.z).length()
	var is_window := fixture.has_method(&"approach_point")
	var state := StringName(fixture.get(&"state"))
	var b := BarricadeComponent.of(fixture)
	var full := b != null and b.plank_count() > 0 and b.attacker_count() >= b.data.max_attackers
	var sc := score(d, int(fixture.call(&"barricade_planks")), per_plank,
		is_window and state == &"closed", not is_window and state == &"closed", full)
	return {"fixture": fixture, "point": p, "score": sc, "distance": d}


## The best other entry of [current]'s building within [radius] of [from]
## that beats [current] (scored from [from], where the zombie stands) by
## at least [margin]. {} when none.
static func better_entry(current: Node3D, from: Vector3, per_plank: float, radius: float, margin: float) -> Dictionary:
	var building := building_of(current)
	if building == null:
		return {}
	var here := entry_score_of(current, from, per_plank)
	var best := {}
	for f in openings(building):
		if f == current:
			continue
		var e := entry_score_of(f, from, per_plank)
		if float(e.distance) > radius:
			continue
		if best.is_empty() or float(e.score) < float(best.score):
			best = e
	if best.is_empty() or float(best.score) > float(here.score) - margin:
		return {}
	return best
