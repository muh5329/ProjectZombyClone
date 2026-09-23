class_name ConsumeAction
extends Node
## Eating and drinking for a Character (child node "Consume", Round 7).
##
## start(item, portion): a timed busy action ("Eating Canned Beans…",
## FoodData.eat_seconds × portion) owned by the character. The item (one
## of its stack) is taken out of its container when eating starts and put
## back if the action is interrupted — by damage (EventBus
## character_damaged) or by the player walking off (move intent). On
## completion NeedsMath.consume_effect(food, portion, spoil state) goes to
## the NeedsComponent; a half portion leaves a half-eaten item behind, a
## finished drink with an empty_item_id leaves that (empty bottle).
##
## Tools (resolve_tool, pure): FoodData.requires_tool is an item tag that
## must be carried (tin opener); otherwise a carried item tagged
## fallback_tool_tag (a knife: &"blade") opens it, with
## fallback_injury_chance of a hand scratch; neither → "Need a can opener".
##
## Water sources (Sink): drink_water(amount, seconds) and
## fill_containers(seconds) (every carried item with ItemData.fill_item_id:
## empty bottle → water bottle).

const CONTEXT := &"eat"
const ACTION_EAT := &"eat"
const ACTION_DRINK := &"drink"
const ACTION_FILL := &"fill"
const REASON_NO_OPENER := "Need a can opener"

var character: Character
var rng := RandomNumberGenerator.new()
## What is being done right now ({} when idle): {action, item, portion,
## from (WeakRef container), seconds, water, fill}.
var current: Dictionary = {}
## Last result of an opening with the fallback tool (tests): {tool, cut}.
var last_open: Dictionary = {}


func _ready() -> void:
	character = get_parent() as Character
	rng.randomize()
	if character:
		character.busy_cancelled.connect(_on_busy_cancelled)


func is_consuming() -> bool:
	return not current.is_empty() and character != null and character.is_busy and character.busy_context == CONTEXT


# --- Pure helpers ----------------------------------------------------------------

## Pure: which carried item opens [food]? Returns {ok, reason?, tool:
## ItemInstance|null, kind: &"none" | &"tool" | &"fallback"}. [storages]:
## the containers to search (main inventory, worn bag, hand slots).
static func resolve_tool(food: FoodData, storages: Array) -> Dictionary:
	if food == null or food.requires_tool == &"":
		return {"ok": true, "tool": null, "kind": &"none"}
	var fallback: ItemInstance = null
	for c in storages:
		if c == null:
			continue
		for it: ItemInstance in (c as ItemContainer).items:
			if it.data == null or it.is_broken():
				continue
			if it.data.has_tag(food.requires_tool):
				return {"ok": true, "tool": it, "kind": &"tool"}
			if fallback == null and food.fallback_tool_tag != &"" and it.data.has_tag(food.fallback_tool_tag):
				fallback = it
	if fallback != null:
		return {"ok": true, "tool": fallback, "kind": &"fallback"}
	return {"ok": false, "reason": REASON_NO_OPENER, "tool": null, "kind": &"none"}


## "Eating Canned Beans…" / "Drinking Water Bottle…" (+ " (half)").
static func action_label(food: FoodData, half: bool) -> String:
	var verb := "Drinking" if food != null and food.is_drink() else "Eating"
	return "%s %s%s…" % [verb, food.display_name if food else "?", " (half)" if half else ""]


## Context-menu entries for [item]: [{id, label, enabled, reason, portion}]
## (ids &"consume" and &"consume_half").
func options_for(item: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var food := item.data as FoodData if item != null else null
	if food == null:
		return out
	var verb := "Drink" if food.is_drink() else "Eat"
	var why := block_reason(item)
	out.append({"id": &"consume", "label": verb, "enabled": why == "", "reason": why, "portion": 1.0})
	if food.can_eat_half and not item.is_partial():
		out.append({"id": &"consume_half", "label": "%s half" % verb, "enabled": why == "", "reason": why, "portion": 0.5})
	return out


## Why [item] cannot be consumed right now ("" when it can).
func block_reason(item: ItemInstance) -> String:
	var food := item.data as FoodData if item != null else null
	if food == null:
		return "Can't eat that"
	if character == null or character.needs == null:
		return "Can't eat"
	var t := resolve_tool(food, _tool_storages())
	return "" if t.ok else String(t.reason)


func _storages() -> Array:
	if character != null and character.has_method(&"carried_storage"):
		return character.call(&"carried_storage")
	var inv: Variant = character.get("inventory") if character else null
	return [inv] if inv is ItemContainer else []


## Storage + hands: a knife in the hand opens cans too.
func _tool_storages() -> Array:
	var out: Array = _storages().duplicate()
	var eq: Variant = character.get("equipment") if character else null
	if eq is Equipment:
		for slot in Equipment.SLOTS:
			out.append((eq as Equipment).slots[slot])
	return out


# --- Eating ------------------------------------------------------------------------

## Eat / drink [portion] (1 = what is left of the item, 0.5 = half of a
## whole one). Returns {ok, reason?, seconds}.
func start(item: ItemInstance, portion: float = 1.0) -> Dictionary:
	if character == null or character.is_dead():
		return _refuse("Can't eat now")
	if _paused():
		return _refuse("Paused")
	if character.is_busy:
		return _refuse("Busy")
	var food := item.data as FoodData if item != null else null
	if food == null:
		return _refuse("Can't eat that")
	if character.has_method(&"carries") and not bool(character.call(&"carries", item)):
		return _refuse("Not here")
	if character.needs == null:
		return _refuse("Can't eat")
	var tool := resolve_tool(food, _tool_storages())
	if not tool.ok:
		return _refuse(String(tool.reason))
	var from := item.owner_container()
	if from == null:
		return _refuse("Not here")
	if from.equipment_slot != &"" and character.has_method(&"can_release_item"):
		var rel: Dictionary = character.call(&"can_release_item", item)
		if not rel.get("ok", true):
			return _refuse(String(rel.get("reason", "Busy")))
	var half := portion < 0.999 and not item.is_partial()
	var eat_portion := item.portion * (0.5 if half else 1.0)
	var taken := from.remove(item, 1)
	if taken == null:
		return _refuse("Nothing there")
	last_open = {}
	if tool.kind == &"fallback":
		var cut := rng.randf() < food.fallback_injury_chance
		last_open = {"tool": (tool.tool as ItemInstance).id(), "cut": cut}
		if cut:
			var hand := &"left_hand" if rng.randf() < 0.5 else &"right_hand"
			character.take_damage(character.needs.profile.fallback_cut_damage, null, {"region": hand, "type": &"scratch"})
			EventBus.interaction_refused.emit(character, null, "Cut yourself opening it!")
			if character.is_dead():
				_return_item(taken, from)
				return {"ok": false, "reason": "Dead"}
	var seconds := maxf(food.eat_seconds * eat_portion, 0.1)
	current = {"action": ACTION_DRINK if food.is_drink() else ACTION_EAT, "item": taken,
		"portion": eat_portion, "from": weakref(from), "seconds": seconds}
	_begin(seconds, action_label(food, half))
	return {"ok": true, "seconds": seconds, "portion": eat_portion, "tool": tool.kind}


func _begin(seconds: float, label: String) -> void:
	if not EventBus.character_damaged.is_connected(_on_damaged):
		EventBus.character_damaged.connect(_on_damaged)
	var tw := character.begin_busy(CONTEXT)
	tw.tween_interval(seconds)
	tw.tween_callback(_finish)
	EventBus.timed_action_started.emit(character, StringName(current.action), label, seconds)


func _physics_process(_delta: float) -> void:
	# Walking off stops eating (intent is still set while busy).
	if not current.is_empty() and is_consuming() and character.has_move_intent():
		interrupt("Stopped")


func _on_damaged(c: Node, _amount: float, _source: Node, _info: Dictionary) -> void:
	if c == character and is_consuming():
		interrupt("Interrupted")


## Stop the running action: nothing is consumed, the item goes back.
func interrupt(reason: String = "Interrupted") -> void:
	if current.is_empty():
		return
	if not character.cancel_busy(CONTEXT):
		_on_busy_cancelled(CONTEXT)  # not busy any more: restore anyway
	EventBus.interaction_refused.emit(character, null, reason)


## The eat / drink / fill action was cut (interrupt, overridden, death):
## the item goes back where it came from, nothing is consumed.
func _on_busy_cancelled(context: StringName) -> void:
	if context != CONTEXT or current.is_empty():
		return
	var cur := current
	current = {}
	_stop_listening()
	var it: ItemInstance = cur.get("item")
	if it != null:
		_return_item(it, (cur.from as WeakRef).get_ref() as ItemContainer)
	EventBus.timed_action_finished.emit(character, StringName(cur.action), false)


func _stop_listening() -> void:
	if EventBus.character_damaged.is_connected(_on_damaged):
		EventBus.character_damaged.disconnect(_on_damaged)


func _finish() -> void:
	var cur := current
	current = {}
	_stop_listening()
	if cur.is_empty() or character == null or character.is_dead():
		return
	match StringName(cur.action):
		ACTION_FILL:
			_finish_fill()
		&"water":
			character.needs.consume({"thirst": float(cur.water)})
			EventBus.item_consumed.emit(character, {"id": &"tap_water", "name": "Water", "portion": 1.0,
				"hunger": 0.0, "thirst": float(cur.water), "sickness": 0.0, "spoil_state": &"fresh"})
		_:
			_finish_food(cur)
	EventBus.timed_action_finished.emit(character, StringName(cur.action), true)


func _finish_food(cur: Dictionary) -> void:
	var it: ItemInstance = cur.item
	var food := it.data as FoodData
	var portion := float(cur.portion)
	var state := it.spoil_state()
	var eff := NeedsMath.consume_effect(food, portion, state, character.needs.profile)
	character.needs.consume(eff)
	var from := (cur.from as WeakRef).get_ref() as ItemContainer
	it.portion = maxf(it.portion - portion, 0.0)
	if it.portion > 0.01:
		_return_item(it, from)
	elif food.empty_item_id != &"" and ItemDB.has_item(food.empty_item_id):
		_return_item(ItemInstance.new(ItemDB.get_item(food.empty_item_id)), from)
	EventBus.item_consumed.emit(character, {"id": food.id, "name": food.display_name, "portion": portion,
		"hunger": eff.hunger, "thirst": eff.thirst, "sickness": eff.sickness,
		"spoil_state": FoodData.SPOIL_IDS[state]})


## Put [it] back where it came from (if still carried), else the main
## inventory / worn bag, else drop it at the feet.
func _return_item(it: ItemInstance, from: ItemContainer) -> void:
	if it == null or it.stack <= 0:
		return
	var storages := _storages()
	if from != null and from.equipment_slot == &"" and storages.has(from) and from.add(it).get("ok", false):
		return
	for c in storages:
		if c != from and (c as ItemContainer).add(it).get("ok", false):
			return
	if character.get_parent() != null:
		WorldItem.drop(it, character)


# --- Water sources (Sink) ------------------------------------------------------------

## Drink from a tap: [amount] thirst removed after [seconds].
func drink_water(amount: float, seconds: float) -> Dictionary:
	if character == null or character.is_dead():
		return _refuse("Can't drink now")
	if _paused():
		return _refuse("Paused")
	if character.is_busy:
		return _refuse("Busy")
	if character.needs == null:
		return _refuse("Can't drink")
	current = {"action": &"water", "water": amount, "seconds": seconds}
	_begin(seconds, "Drinking water…")
	return {"ok": true, "seconds": seconds}


## Carried items that can be filled with water (ItemData.fill_item_id).
func fillable_items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for c in _storages():
		for it: ItemInstance in (c as ItemContainer).items:
			if it.data != null and it.data.fill_item_id != &"" and ItemDB.has_item(it.data.fill_item_id):
				out.append(it)
	return out


## Why nothing can be filled right now ("" when at least one bottle can):
## "No empty bottles", or "No room for the water" when the water would
## not fit in the bottle's container.
func fill_block_reason() -> String:
	var items := fillable_items()
	if items.is_empty():
		return "No empty bottles"
	for it in items:
		var c := it.owner_container()
		var filled := ItemDB.get_item(it.data.fill_item_id)
		if c == null or c.capacity < 0.0 or c.free_weight() + 0.0001 >= filled.weight - it.data.weight:
			return ""
	return "No room for the water"


func _paused() -> bool:
	return is_inside_tree() and get_tree().paused


## Fill every carried empty container after [seconds].
func fill_containers(seconds: float) -> Dictionary:
	if character == null or character.is_dead():
		return _refuse("Can't do that now")
	if _paused():
		return _refuse("Paused")
	if character.is_busy:
		return _refuse("Busy")
	var why := fill_block_reason()
	if why != "":
		return _refuse(why)
	current = {"action": ACTION_FILL, "seconds": seconds}
	_begin(seconds, "Filling bottles…")
	return {"ok": true, "seconds": seconds}


func _finish_fill() -> void:
	var n := 0
	for it in fillable_items():
		var c := it.owner_container()
		var filled := ItemDB.get_item(it.data.fill_item_id)
		var count := it.stack
		var extra := (filled.weight - it.data.weight) * count
		# The water weighs something: only what still fits is filled.
		if c.capacity >= 0.0 and extra > c.free_weight() + 0.0001:
			count = clampi(int(floor(c.free_weight() / maxf(filled.weight - it.data.weight, 0.001))), 0, count)
		if count <= 0:
			continue
		c.remove(it, count)
		c.add(ItemInstance.new(filled, -1, count))
		n += count
	EventBus.interaction_refused.emit(character, null, "Filled %d bottle%s" % [n, "" if n == 1 else "s"] if n > 0 else "No room for the water")


func _refuse(reason: String) -> Dictionary:
	EventBus.interaction_refused.emit(character, null, reason)
	return {"ok": false, "reason": reason}
