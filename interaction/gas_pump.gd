class_name GasPump
extends StaticBody3D
## A gas-station fuel pump (Round 11): a blockout prop on layers 1 + 4
## that offers "Siphon fuel" — disabled ("No power") until fuel items and
## electricity exist. Built by WorldBuilder from layout props of kind pump.

const SIZE := Vector3(0.9, 1.7, 0.6)

@export var display_name: String = "Gas pump"
@export var persist_id: String = ""


func _ready() -> void:
	collision_layer = 1 | (1 << 3)
	collision_mask = 0
	add_to_group(&"gas_pump")
	var visual := Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_box(visual, Vector3(0, SIZE.y * 0.5, 0), SIZE, Color(0.82, 0.18, 0.14))
	_box(visual, Vector3(0, SIZE.y * 0.72, SIZE.z * 0.5 + 0.01), Vector3(0.55, 0.35, 0.02), Color(0.12, 0.14, 0.16))
	_box(visual, Vector3(SIZE.x * 0.5 + 0.06, 0.9, 0.0), Vector3(0.06, 0.8, 0.06), Color(0.1, 0.1, 0.1))
	_box(visual, Vector3(0, 0.08, 0), Vector3(SIZE.x + 0.5, 0.16, SIZE.z + 0.6), Color(0.62, 0.62, 0.6))
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	shape.shape = bs
	shape.position = Vector3(0, SIZE.y * 0.5, 0)
	add_child(shape)
	var it := Interactable.new()
	it.name = "Interactable"
	add_child(it)


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


func interaction_display_name() -> String:
	return display_name


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3(0, 1.3, 0)


func interaction_actions(_actor: Node) -> Array[Dictionary]:
	return [{"id": &"siphon", "label": "Siphon fuel", "enabled": false, "reason": "No power"}]


func interaction_perform(action_id: StringName, _actor: Node) -> Dictionary:
	if action_id == &"siphon":
		return {"ok": false, "reason": "No power"}
	return {"ok": false, "reason": "Unknown action"}
