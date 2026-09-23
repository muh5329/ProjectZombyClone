class_name Sink
extends StaticBody3D
## Kitchen / bathroom sink (Round 7): "Drink" (removes up to
## [thirst_per_drink] thirst in [drink_seconds]) and "Fill bottle" (every
## carried empty bottle → water bottle in [fill_seconds]). Not a loot
## container. The water runs until WorldConfig.water_shutoff_day (default
## day 14) → "The water is off" (PZ scarcity); [has_water] false = dry.
## Actions go through the actor's ConsumeAction (child "Consume") and
## NeedsComponent (duck-typed via the Character's `needs`).

const DRINK := &"drink"
const FILL := &"fill"
const REASON_NO_WATER := "The water is off"

@export var display_name: String = "Sink"
@export var has_water: bool = true
@export var thirst_per_drink: float = 60.0
@export var drink_seconds: float = 4.0
@export var fill_seconds: float = 2.5
@export var size: Vector3 = Vector3(0.8, 0.9, 0.55)


func _ready() -> void:
	collision_layer |= 1 << 3
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)


## Water runs while [has_water] and the world's water_shutoff_day
## (WorldConfig; outbreak day + days played) has not come (Round 7).
func water_on() -> bool:
	if not has_water:
		return false
	var cfg := WorldConfig.find(get_tree()) if is_inside_tree() else null
	if cfg == null:
		return true
	return WorldConfig.water_on_for(cfg.water_shutoff_day, cfg.world_age_days + TimeManager.day_index())


func interaction_display_name() -> String:
	return display_name


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3.UP * (size.y + 0.1)


static func consume_of(actor: Node) -> Node:
	return actor.get_node_or_null("Consume") if actor != null else null


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := consume_of(actor)
	if c == null:
		return out
	var needs: Variant = actor.get("needs")
	var drink_why := ""
	if not water_on():
		drink_why = REASON_NO_WATER
	elif needs == null:
		drink_why = "Can't drink"
	elif float(needs.call(&"value", &"thirst")) < 1.0:
		drink_why = "Not thirsty"
	out.append(Interactable.action(DRINK, "Drink", drink_why == "", drink_why))
	var fill_why := ""
	if not water_on():
		fill_why = REASON_NO_WATER
	else:
		fill_why = String(c.call(&"fill_block_reason"))
	out.append(Interactable.action(FILL, "Fill bottle", fill_why == "", fill_why))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	var c := consume_of(actor)
	if c == null:
		return {"ok": false, "reason": "Can't"}
	match action_id:
		DRINK:
			if not water_on():
				return {"ok": false, "reason": REASON_NO_WATER}
			return c.call(&"drink_water", thirst_per_drink, drink_seconds)
		FILL:
			if not water_on():
				return {"ok": false, "reason": REASON_NO_WATER}
			return c.call(&"fill_containers", fill_seconds)
	return {"ok": false, "reason": "No such action"}
