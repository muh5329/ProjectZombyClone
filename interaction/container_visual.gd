class_name ContainerVisual
extends Node3D
## Blockout look of a LootContainer (child "Visual"): a box body plus a
## lid — &"front": a door hinged on the left front edge that swings out
## towards +Z; &"top": a lid hinged at the back that lifts; &"none": a
## lighter top plate. set_open() tweens the lid (0.25 s). Pure
## presentation: no gameplay state lives here.

var size: Vector3 = Vector3.ONE
var color: Color = Color(0.55, 0.4, 0.25)
var lid_style: StringName = &"front"
var lid: Node3D
var _tween: Tween


func build(p_size: Vector3, p_color: Color, p_lid_style: StringName) -> void:
	size = p_size
	color = p_color
	lid_style = p_lid_style
	for ch in get_children():
		ch.queue_free()
	lid = null
	var body_size := size
	if lid_style == &"top":
		body_size.y = size.y - 0.06
	add_child(_box("Mesh", body_size, Vector3(0, body_size.y * 0.5, 0), color))
	if lid_style == &"front":
		lid = Node3D.new()
		lid.name = "Lid"
		lid.position = Vector3(-size.x * 0.5, 0.0, size.z * 0.5 + 0.02)
		add_child(lid)
		var ph := size.y * 0.86
		lid.add_child(_box("Door", Vector3(size.x - 0.04, ph, 0.03), Vector3(size.x * 0.5, size.y * 0.07 + ph * 0.5, 0), color.lightened(0.12)))
		lid.add_child(_box("Handle", Vector3(0.04, minf(0.18, ph * 0.3), 0.04), Vector3(size.x - 0.1, minf(size.y * 0.75, 1.1), 0.03), color.darkened(0.6)))
	elif lid_style == &"top":
		lid = Node3D.new()
		lid.name = "Lid"
		lid.position = Vector3(0.0, body_size.y, -size.z * 0.5)
		add_child(lid)
		lid.add_child(_box("LidPlate", Vector3(size.x + 0.02, 0.06, size.z + 0.02), Vector3(0, 0.03, size.z * 0.5), color.lightened(0.15)))
	else:
		add_child(_box("Top", Vector3(size.x + 0.02, 0.03, size.z + 0.02), Vector3(0, size.y + 0.015, 0), color.lightened(0.25)))


## Swing the door / lift the lid (open) or shut it.
func set_open(open_it: bool) -> void:
	if lid == null:
		return
	if _tween and _tween.is_valid():
		_tween.kill()
	var prop := "rotation:y" if lid_style == &"front" else "rotation:x"
	var target := 0.0
	if open_it:
		target = deg_to_rad(-100.0) if lid_style == &"front" else deg_to_rad(-105.0)
	_tween = create_tween()
	_tween.tween_property(lid, prop, target, 0.25)


## 0 closed … 1 fully open (-1 when there is no lid).
func open_fraction() -> float:
	if lid == null:
		return -1.0
	var a := absf(lid.rotation.y if lid_style == &"front" else lid.rotation.x)
	return clampf(a / deg_to_rad(100.0), 0.0, 1.0)


func _box(nm: String, s: Vector3, at: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var box := BoxMesh.new()
	box.size = s
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	box.material = mat
	mi.mesh = box
	mi.position = at
	return mi
