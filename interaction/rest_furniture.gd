class_name RestFurniture
extends StaticBody3D
## A bed or a seat (sofa) the character can use (Round 7). Built by
## HouseBlockout for furniture whose catalog entry has interaction &"bed"
## (Sleep + Rest) or &"seat" (Rest). Layers 1 + 4 (+ 6 when tall); the
## blockout mesh / collision come from HouseBlockout._furnish().
## Actions go through the actor's RestComponent (child "Rest", duck-typed):
## Sleep is listed disabled with its reason ("Not tired", "Can't sleep:
## danger nearby").

const KIND_BED := &"bed"
const KIND_SEAT := &"seat"
const SLEEP := &"sleep"
const REST := &"rest"

@export var kind: StringName = KIND_BED
@export var display_name: String = "Bed"
## Furniture size (prompt position / occlusion); set by the builder.
@export var size: Vector3 = Vector3(1.4, 0.5, 2.0)


func _ready() -> void:
	collision_layer |= 1 << 3
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)


static func rest_of(actor: Node) -> Node:
	return actor.get_node_or_null("Rest") if actor != null else null


func interaction_display_name() -> String:
	return display_name


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3.UP * (size.y + 0.1)


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rest := rest_of(actor)
	if rest == null:
		return out
	if kind == KIND_BED:
		var why := String(rest.call(&"sleep_block_reason"))
		out.append(Interactable.action(SLEEP, "Sleep", why == "", why))
	var rwhy := String(rest.call(&"rest_block_reason"))
	out.append(Interactable.action(REST, "Rest", rwhy == "", rwhy))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	var rest := rest_of(actor)
	if rest == null:
		return {"ok": false, "reason": "Can't"}
	match action_id:
		SLEEP:
			return rest.call(&"sleep", self)
		REST:
			return rest.call(&"rest", self)
	return {"ok": false, "reason": "No such action"}
