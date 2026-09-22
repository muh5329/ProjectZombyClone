class_name WorldItem
extends StaticBody3D
## An item lying in the world: a blockout box (ItemData.color /
## world_size) on physics layer 4 (interactables) with an Interactable
## "Pick up <name>". Picking up hands an ItemInstance to the actor's
## duck-typed pick_up_item(item) -> {ok, reason?} and frees this node.
## Group "world_item".

const LAYER_INTERACTABLES := 1 << 3

@export var item_data: ItemData
## Starting condition (-1 = the data's max).
@export var condition: int = -1

var item: ItemInstance


func _ready() -> void:
	add_to_group(&"world_item")
	collision_layer = LAYER_INTERACTABLES
	collision_mask = 0
	if item == null:
		item = ItemInstance.new(item_data, condition)
	var size := item_data.world_size if item_data else Vector3(0.3, 0.1, 0.3)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item_data.color if item_data else Color.GRAY
	box.material = mat
	mesh.mesh = box
	mesh.position = Vector3(0, size.y * 0.5 + 0.04, 0)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	# A little taller than the mesh so the interaction query finds it easily.
	bs.size = Vector3(maxf(size.x, 0.3), 0.3, maxf(size.z, 0.3))
	shape.shape = bs
	shape.position = Vector3(0, 0.15, 0)
	add_child(shape)
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)


## Build a WorldItem for an existing instance (drops, tests).
static func for_instance(inst: ItemInstance) -> WorldItem:
	var w := WorldItem.new()
	w.item_data = inst.data
	w.item = inst
	return w


func interaction_display_name() -> String:
	return item.display_name() if item else "Item"


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3.UP * 0.2


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var can := actor != null and actor.has_method(&"pick_up_item")
	out.append(Interactable.action(&"pick_up", "Pick up %s" % interaction_display_name(), can, "" if can else "Can't carry"))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	if action_id != &"pick_up" or actor == null or not actor.has_method(&"pick_up_item"):
		return {"ok": false, "reason": "Can't carry"}
	var r: Dictionary = actor.call(&"pick_up_item", item)
	if r.get("ok", false):
		collision_layer = 0
		queue_free()
	return r
