class_name Interactable
extends Node3D
## Interaction component. Attach as a child of any physics body on layer 4
## ("interactables"); the body (the [provider], parent by default) supplies
## the actions by implementing:
##
##   func interaction_actions(actor: Node) -> Array[Dictionary]
##   func interaction_perform(action_id: StringName, actor: Node) -> Dictionary
##   func interaction_display_name() -> String          (optional)
##   func interaction_prompt_position() -> Vector3       (optional)
##
## Each action is {id: StringName, label: String, enabled: bool, reason: String}.
## The player never switches on object types: it only talks to this API.
## Signals for other systems go through the EventBus.

## Children of the provider in this group add their own actions.
const GROUP_EXTENSION := &"interaction_extension"

## Node that implements the interaction callbacks (defaults to the parent).
@export var provider: Node


func _ready() -> void:
	if provider == null:
		provider = get_parent()
	add_to_group(&"interactable")


## The physics body this component belongs to (the provider if it is a
## CollisionObject3D, else the nearest CollisionObject3D ancestor).
func body() -> Node:
	if provider is CollisionObject3D:
		return provider
	var n: Node = get_parent()
	while n != null and not n is CollisionObject3D:
		n = n.get_parent()
	return n


## Resolve the Interactable for a node found by physics (the body itself or
## a component child). Returns null when the node offers no interactions.
static func of(node: Node) -> Interactable:
	if node == null:
		return null
	if node is Interactable:
		return node
	for c in node.get_children():
		if c is Interactable:
			return c
	return null


func get_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for src in _sources():
		var raw: Variant = src.call(&"interaction_actions", actor)
		for a in raw:
			out.append(normalise_action(a))
	return out


## The provider, then its extensions: children of the provider in group
## [GROUP_EXTENSION] that implement the same two callbacks (Round 9: a
## FurnitureWork adds "Move in front of door" / "Disassemble" to a
## container or a sofa without the container knowing).
func _sources() -> Array[Node]:
	var out: Array[Node] = []
	if provider != null and provider.has_method(&"interaction_actions"):
		out.append(provider)
	if provider != null:
		for c in provider.get_children():
			if c.is_in_group(GROUP_EXTENSION) and c.has_method(&"interaction_actions") and c.has_method(&"interaction_perform"):
				out.append(c)
	return out


## Perform [action_id]; returns a result Dictionary ({ok: bool, ...}).
func perform(action_id: StringName, actor: Node) -> Dictionary:
	for src in _sources():
		for raw in src.call(&"interaction_actions", actor):
			var a := normalise_action(raw)
			if a.id != action_id:
				continue
			if not a.enabled:
				var reason := String(a.reason) if a.reason != "" else "Unavailable"
				EventBus.interaction_refused.emit(actor, self, reason)
				return {"ok": false, "reason": reason}
			var result: Variant = src.call(&"interaction_perform", action_id, actor)
			var d: Dictionary = result if result is Dictionary else {}
			if not d.has("ok"):
				d["ok"] = true
			if d.ok:
				EventBus.interaction_performed.emit(actor, self, action_id)
			else:
				EventBus.interaction_refused.emit(actor, self, String(d.get("reason", "Unavailable")))
			return d
	EventBus.interaction_refused.emit(actor, self, "No such action")
	return {"ok": false, "reason": "No such action"}


func get_prompt_position() -> Vector3:
	if provider != null and provider.has_method(&"interaction_prompt_position"):
		return provider.call(&"interaction_prompt_position")
	return global_position + Vector3.UP * 1.2


func display_name() -> String:
	if provider != null and provider.has_method(&"interaction_display_name"):
		return provider.call(&"interaction_display_name")
	return String(provider.name) if provider else name


## Helper for providers: build a well-formed action dictionary.
## [explicit] actions are never the E (default) action: they need their
## number key (Round 9: "Remove barricade" must not happen by accident).
static func action(id: StringName, label: String, enabled: bool = true, reason: String = "", explicit: bool = false) -> Dictionary:
	var a := {"id": id, "label": label, "enabled": enabled, "reason": reason}
	if explicit:
		a["explicit"] = true
	return a


static func normalise_action(a: Dictionary) -> Dictionary:
	var out := {
		"id": StringName(a.get("id", &"")),
		"label": String(a.get("label", String(a.get("id", "")))),
		"enabled": bool(a.get("enabled", true)),
		"reason": String(a.get("reason", "")),
	}
	if bool(a.get("explicit", false)):
		out["explicit"] = true
	return out


## True when [a] may be the default (E) action.
static func is_default_candidate(a: Dictionary) -> bool:
	return bool(a.get("enabled", true)) and not bool(a.get("explicit", false))
