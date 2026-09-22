@tool
class_name BlockoutBox
extends StaticBody3D
## Placeholder solid box (Phase 1 asset pipeline). Builds its own mesh and
## collision from [size] so blockout maps stay tiny and editable.
## Will be replaced by real building/prop scenes; do not add gameplay here.

@export var size: Vector3 = Vector3(1, 1, 1):
	set(v):
		size = v
		_rebuild()
@export var color: Color = Color(0.6, 0.6, 0.65):
	set(v):
		color = v
		_rebuild()

var _mesh: MeshInstance3D
var _shape: CollisionShape3D


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.name = "Mesh"
		add_child(_mesh)
	if _shape == null:
		_shape = CollisionShape3D.new()
		_shape.name = "Shape"
		add_child(_shape)
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	_mesh.mesh = box
	_mesh.position = Vector3(0, size.y * 0.5, 0)
	var bs := BoxShape3D.new()
	bs.size = size
	_shape.shape = bs
	_shape.position = Vector3(0, size.y * 0.5, 0)
