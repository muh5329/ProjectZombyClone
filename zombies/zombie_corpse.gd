class_name ZombieCorpse
extends StaticBody3D
## What a dead zombie leaves behind: a static body on layer 4
## (interactables) only — it blocks nobody and is walked over — with the
## collapsed ZombieVisual and an Interactable provider offering
## "Search corpse" (disabled until inventory, Round 5).
## Group "corpse".

const LAYER_INTERACTABLES := 1 << 3

var killer: Node = null


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
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)


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


# --- Interactable provider API --------------------------------------------

func interaction_display_name() -> String:
	return "Zombie corpse"


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3.UP * 0.4


func interaction_actions(_actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(Interactable.action(&"search", "Search corpse", false, "No inventory yet"))
	return out


func interaction_perform(_action_id: StringName, _actor: Node) -> Dictionary:
	return {"ok": false, "reason": "No inventory yet"}
