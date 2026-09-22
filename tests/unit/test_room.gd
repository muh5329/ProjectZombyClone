extends "res://tests/test_case.gd"

const RoomScript = preload("res://buildings/room.gd")

var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()


func _room(pos: Vector3, size: Vector3) -> Room:
	var r: Room = RoomScript.new()
	r.position = pos
	r.size = size
	tree.root.add_child(r)
	_nodes.append(r)
	return r


func test_contains_point_inside_and_outside() -> void:
	var r := _room(Vector3(5, 0, 3), Vector3(4, 2.7, 2))
	check(r.contains_point(Vector3(5, 0.5, 3)), "centre inside")
	check(r.contains_point(Vector3(6.9, 0.0, 3.9)), "near corner inside")
	check(not r.contains_point(Vector3(7.5, 0.5, 3)), "outside in x")
	check(not r.contains_point(Vector3(5, 0.5, 4.5)), "outside in z")
	check(not r.contains_point(Vector3(5, 3.5, 3)), "above ceiling")
	check(r.contains_point(Vector3(5, -0.2, 3)), "slightly below floor still counts (feet on ground)")


func test_contains_point_respects_parent_transform() -> void:
	var parent := Node3D.new()
	parent.position = Vector3(-14, 0, -10)
	tree.root.add_child(parent)
	_nodes.append(parent)
	var r: Room = RoomScript.new()
	r.position = Vector3(5, 0, 6)
	r.size = Vector3(10, 2.7, 4)
	parent.add_child(r)
	check(r.contains_point(Vector3(-9, 0.5, -4)), "world point inside after parent offset")
	check(not r.contains_point(Vector3(5, 0.5, 6)), "local coords are not world coords")


func test_margin_edges() -> void:
	var r := _room(Vector3.ZERO, Vector3(2, 2, 2))
	check(r.contains_point(Vector3(1.04, 0, 0)), "within margin")
	check(not r.contains_point(Vector3(1.1, 0, 0)), "beyond margin")
