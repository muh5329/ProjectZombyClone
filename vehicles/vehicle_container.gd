class_name VehicleContainer
extends LootContainer
## A searchable part of a Vehicle (trunk / truck bed, glovebox): a small
## layer-4 (interactables only) body next to the car so the player can
## target it from outside; the car body itself blocks movement. Loot comes
## from the data/loot/vehicle_trunk / vehicle_glovebox tables through the
## usual LootContainer fallback chain (container_type).

## Local offset of the prompt from this node (outside the car body).
var prompt_offset: Vector3 = Vector3(0, 1.0, 0)
var shape_size: Vector3 = Vector3(1.0, 0.8, 0.4)


func _init() -> void:
	super._init()
	search_noise_radius = 4.0
	room_type = &""
	building_type = &""


func _ready() -> void:
	collision_layer = LAYER_INTERACTABLES
	collision_mask = 0
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = shape_size
		shape.shape = box
		shape.position = Vector3(0, shape_size.y * 0.5, 0)
		add_child(shape)
	super._ready()


func interaction_prompt_position() -> Vector3:
	return global_transform * prompt_offset
