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


func _collect_rooms() -> void:
	rooms.clear()
	for c in get_children():
		if c is Room:
			rooms.append(c)


func add_room(room: Room) -> void:
	add_child(room)
	if not rooms.has(room):
		rooms.append(room)


## The Room containing [p] (with [extra_margin] added to each room's
## tolerance; negative = must be that deep inside), or null.
func room_at(p: Vector3, extra_margin: float = 0.0) -> Room:
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
