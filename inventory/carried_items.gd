class_name CarriedItems
extends RefCounted
## Static queries over what an actor carries (hands + main inventory +
## worn bag), duck-typed: an `equipment` (Equipment) child / property and
## `carried_storage()` / `inventory`. Used by carpentry (tools, planks,
## nails) and anything else that needs "do I have X" without knowing the
## Player type.


## Every carried container, hands first (equipment slots), then storage.
static func containers(actor: Node) -> Array[ItemContainer]:
	var out: Array[ItemContainer] = []
	if actor == null:
		return out
	var eq: Variant = actor.get("equipment") if "equipment" in actor else null
	if eq is Equipment:
		for slot in Equipment.SLOTS:
			var c: ItemContainer = (eq as Equipment).slots.get(slot)
			if c != null and not out.has(c):
				out.append(c)
	if actor.has_method(&"carried_storage"):
		for c: ItemContainer in actor.call(&"carried_storage"):
			if not out.has(c):
				out.append(c)
	elif "inventory" in actor and actor.get("inventory") is ItemContainer:
		out.append(actor.get("inventory"))
	return out


## First carried, unbroken item with one of [tags] (hands first, then the
## tags' order). Null when none.
static func find_tool(actor: Node, tags: Array) -> ItemInstance:
	var cs := containers(actor)
	for tag: StringName in tags:
		for c in cs:
			for it in c.items:
				if it != null and it.data != null and it.stack > 0 and it.data.has_tag(tag) and not it.is_broken():
					return it
	return null


## Total count of [id] across carried containers.
static func count(actor: Node, id: StringName) -> int:
	var n := 0
	for c in containers(actor):
		n += c.count_of(id)
	return n


## Remove [n] of [id] (storage first, never the hands). Returns how many
## were removed (all or nothing: nothing when fewer than [n] are carried).
static func consume(actor: Node, id: StringName, n: int) -> int:
	if n <= 0:
		return 0
	if count(actor, id) < n:
		return 0
	var left := n
	var cs := containers(actor)
	cs.reverse()  # storage before hands
	for c in cs:
		if left <= 0:
			break
		left -= c.remove_id(id, left)
	return n - left


## Give [n] of [id] to the actor (main storage first; what does not fit is
## dropped at its feet). Returns {added, dropped}.
static func give(actor: Node, id: StringName, n: int) -> Dictionary:
	var added := 0
	var dropped := 0
	if n <= 0 or actor == null:
		return {"added": 0, "dropped": 0}
	var data := ItemDB.get_item(id)
	if data == null:
		return {"added": 0, "dropped": 0}
	var left := n
	var storage: Array[ItemContainer] = []
	if actor.has_method(&"carried_storage"):
		storage.assign(actor.call(&"carried_storage"))
	elif "inventory" in actor and actor.get("inventory") is ItemContainer:
		storage.append(actor.get("inventory"))
	for c in storage:
		if left <= 0:
			break
		var fit := c.fit_count(data, left)
		if fit > 0 and bool(c.add_new(data, fit).get("ok", false)):
			left -= fit
			added += fit
	if left > 0 and actor is Node3D:
		WorldItem.drop(ItemInstance.new(data, -1, left), actor)
		dropped = left
	return {"added": added, "dropped": dropped}
