class_name Building
extends Node3D
## A building: a container of Room volumes plus (generated or hand-placed)
## walls, doors, windows and a roof. Everything the occlusion system needs
## is discoverable through groups ("building", "room", "wall", "roof") and
## metadata, never through type checks on this class.

@export var display_name: String = "Building"

var rooms: Array[Room] = []


func _ready() -> void:
	add_to_group(&"building")
	_collect_rooms()
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_bound_r = -1.0


func _collect_rooms() -> void:
	_bound_r = -1.0
	rooms.clear()
	for c in get_children():
		if c is Room:
			rooms.append(c)


func add_room(room: Room) -> void:
	add_child(room)
	if not rooms.has(room):
		rooms.append(room)
	_bound_r = -1.0


## Round 12: a bounding circle (flat, world space) around every room,
## computed once (buildings do not move): room_at() skips far buildings
## without a transform per room — sound hearing and spawn checks ask
## every building for every listener / candidate point.
var _bound_c: Vector2 = Vector2.ZERO
var _bound_r: float = -1.0


func _bounds() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in rooms:
		var rr := r.size.length() * 0.5 + r.margin
		var g := r.global_position
		lo = Vector2(minf(lo.x, g.x - rr), minf(lo.y, g.z - rr))
		hi = Vector2(maxf(hi.x, g.x + rr), maxf(hi.y, g.z + rr))
	if rooms.is_empty():
		_bound_c = Vector2(global_position.x, global_position.z)
		_bound_r = 0.0
		return
	_bound_c = (lo + hi) * 0.5
	_bound_r = (hi - lo).length() * 0.5


## The Room containing [p] (with [extra_margin] added to each room's
## tolerance; negative = must be that deep inside), or null.
func room_at(p: Vector3, extra_margin: float = 0.0) -> Room:
	if is_inside_tree():
		if _bound_r < 0.0:
			_bounds()
		var lim := _bound_r + maxf(extra_margin, 0.0) + 1.0
		if Vector2(p.x, p.z).distance_squared_to(_bound_c) > lim * lim:
			return null
	for r in rooms:
		if r.contains_point(p, extra_margin):
			return r
	return null


func contains_point(p: Vector3) -> bool:
	return room_at(p) != null


## Nodes in group "wall" that belong to this building.
func get_walls() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"wall"):
		if is_ancestor_of(n):
			out.append(n)
	return out


func get_roofs() -> Array[Node]:
	var out: Array[Node] = []
	for n in get_tree().get_nodes_in_group(&"roof"):
		if is_ancestor_of(n):
			out.append(n)
	return out


## Find the (building, room) pair containing [p] among all buildings in
## [tree]. Returns {building: Building|null, room: Room|null}.
##
## With [current_room] given, the answer has hysteresis: the current room
## is kept while the point is within [exit_margin] of it, and another room
## only takes over once the point is [exit_margin] deep inside it. A door
## threshold therefore never flickers.
static func locate(tree: SceneTree, p: Vector3, current_room: Node = null, exit_margin: float = 0.35) -> Dictionary:
	if is_instance_valid(current_room) and current_room.is_inside_tree() \
			and current_room.has_method(&"contains_point") and current_room.contains_point(p, exit_margin):
		var cur_building: Node = current_room.get_parent()
		for b in tree.get_nodes_in_group(&"building"):
			if b.has_method(&"room_at"):
				var deep: Node = b.room_at(p, -exit_margin)
				if deep != null and deep != current_room:
					return {"building": b, "room": deep}
		return {"building": cur_building, "room": current_room}
	for b in tree.get_nodes_in_group(&"building"):
		if b.has_method(&"room_at"):
			var r: Node = b.room_at(p)
			if r != null:
				return {"building": b, "room": r}
	return {"building": null, "room": null}
