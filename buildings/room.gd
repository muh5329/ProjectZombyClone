class_name Room
extends Node3D
## Axis-aligned box volume inside a Building. [position] is the centre of
## the floor rectangle; [size] is the full extent (x, height, z).
## Used for "is the player inside?" queries (occlusion, HUD, later AI).

@export var room_name: String = "Room"
@export var size: Vector3 = Vector3(4, 2.7, 4)
## Tolerance beyond the walls so a character standing in a doorway still
## counts.
@export var margin: float = 0.05
## How far below the floor a point may be (feet on a slightly lower ground).
@export var floor_tolerance: float = 0.5


func _ready() -> void:
	add_to_group(&"room")


func contains_point(p: Vector3, extra_margin: float = 0.0) -> bool:
	var l := to_local(p)
	var m := margin + extra_margin
	return (absf(l.x) <= size.x * 0.5 + m
		and absf(l.z) <= size.z * 0.5 + m
		and l.y >= -margin - floor_tolerance and l.y <= size.y + margin)


## Convenience for tests / generators: rect on the XZ plane in local space.
func floor_rect_local() -> Rect2:
	return Rect2(-size.x * 0.5, -size.z * 0.5, size.x, size.z)
