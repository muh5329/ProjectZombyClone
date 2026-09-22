class_name ZombieCorpse
extends LootContainer
## What a dead zombie leaves behind: a static body on layer 4
## (interactables) only — it blocks nobody and is walked over — with the
## collapsed ZombieVisual. Round 5: it is a LootContainer of type
## &"zombie_corpse": "Search corpse" rolls the pockets lazily from the
## data/loot/zombie_corpse table (seeded by the world seed + the zombie's
## persist id "corpse/<ai_seed>"). Group "corpse".


var killer: Node = null


func _init() -> void:
	super._init()
	container_type = &"zombie_corpse"
	display_name = "Zombie corpse"
	capacity = 25.0
	prompt_height = 0.4
	search_label = "Search corpse"
	search_noise_radius = 0.0
	room_type = &""
	building_type = &""


func _ready() -> void:
	add_to_group(&"corpse")
	collision_layer = LAYER_INTERACTABLES
	collision_mask = 0
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = Vector3(0.6, 0.5, 1.7)
		shape.shape = box
		shape.position = Vector3(0, 0.25, -0.5)
		add_child(shape)
	super._ready()


## Adopt the zombie's visual node (re-parented) and collapse it.
func adopt_visual(v: ZombieVisual) -> void:
	if v.get_parent() != null:
		v.get_parent().remove_child(v)
	add_child(v)
	v.transform = Transform3D.IDENTITY
	v.rotation.y = 0.0
	v.collapse()


func take_damage(_amount: float, _source: Node = null, _info: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": "Already dead", "health": 0.0}


func is_dead() -> bool:
	return true
