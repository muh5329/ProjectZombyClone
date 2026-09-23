class_name ItemActions
extends RefCounted
## The per-item verbs of the inventory screen (right-click context menu,
## hotkeys), kept out of the UI so they are testable: for_item() lists
## {id, label, enabled, reason} for one carried item, perform() runs one
## through the actor's verbs (Player.equip_item / unequip_item /
## use_item / drop_item / split_item / Equipment.assign_hotbar).
## Pure presentation-free logic; the actor is duck-typed.

const EQUIP := &"equip"
const EQUIP_SECONDARY := &"equip_secondary"
const UNEQUIP := &"unequip"
const USE := &"use"
const DROP := &"drop"
const DROP_ONE := &"drop_one"
const SPLIT := &"split"
## Round 7: eat / drink the whole item, or half of it.
const CONSUME := &"consume"
const CONSUME_HALF := &"consume_half"
const HOTBAR_PREFIX := "hotbar_"
## Round 9: boxes (ItemData.unpack_item): "Open box".
const OPEN_BOX := &"open_box"


## Why [d] has no Use verb ("" when it has one / is not special).
static func use_block_reason(d: ItemData) -> String:
	if d == null:
		return "Nothing there"
	return ""


## True when [d] has a "Bandage" Use verb (dressings). Food / drink get
## Eat / Drink entries from the actor's ConsumeAction instead (Round 7).
static func has_use(d: ItemData) -> bool:
	return d is MedicalData and (d as MedicalData).bandage_quality > 0.0


static func _a(id: StringName, label: String, enabled: bool = true, reason: String = "") -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "reason": reason}


static func is_box(d: ItemData) -> bool:
	return d != null and d.unpack_item != &"" and d.unpack_count > 0 and ItemDB.has_item(d.unpack_item)


## Open one box of [item]: it is used up and its contents go to the actor
## (overflow dropped at the feet). Returns {ok, reason?, added, dropped}.
static func open_box(actor: Node, item: ItemInstance) -> Dictionary:
	if actor == null or item == null or not is_box(item.data):
		return {"ok": false, "reason": "Not a box"}
	var from := item.owner_container()
	if from == null or (actor.has_method(&"carries") and not bool(actor.call(&"carries", item))):
		return {"ok": false, "reason": "Not here"}
	if from.remove(item, 1) == null:
		return {"ok": false, "reason": "Nothing there"}
	var r := CarriedItems.give(actor, item.data.unpack_item, item.data.unpack_count)
	EventBus.inventory_changed.emit(actor)
	return {"ok": true, "added": r.added, "dropped": r.dropped}


## Actions for [item] carried by [actor] (a Player-like node with an
## `equipment`).
static func for_item(actor: Node, item: ItemInstance) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if actor == null or item == null or item.data == null:
		return out
	var eq: Equipment = actor.get("equipment") as Equipment
	var slot := eq.slot_of(item) if eq else &""
	if slot != &"":
		out.append(_a(UNEQUIP, "Take off" if slot == Equipment.BACK else "Unequip"))
	elif eq and Equipment.is_equippable(item):
		if item.is_bag():
			out.append(_a(EQUIP, "Wear on back"))
		else:
			out.append(_a(EQUIP, "Equip (both hands)" if item.is_two_handed() else "Equip"))
			if not item.is_two_handed():
				out.append(_a(EQUIP_SECONDARY, "Equip in secondary hand"))
	if has_use(item.data):
		out.append(_a(USE, "Bandage"))
	if is_box(item.data):
		out.append(_a(OPEN_BOX, "Open box (%d %s)" % [item.data.unpack_count,
			ItemDB.get_item(item.data.unpack_item).display_name.to_lower()]))
	var consume: Variant = actor.get("consume")
	if item.data is FoodData and consume is ConsumeAction:
		for o in (consume as ConsumeAction).options_for(item):
			out.append(_a(o.id, o.label, o.enabled, o.reason))
	if item.stack > 1:
		out.append(_a(SPLIT, "Split stack"))
		out.append(_a(DROP_ONE, "Drop one"))
		out.append(_a(DROP, "Drop all"))
	else:
		out.append(_a(DROP, "Drop"))
	if eq and (Equipment.is_equippable(item) or Equipment.is_consumable(item)):
		for i in Equipment.HOTBAR_SIZE:
			var cur := eq.hotbar_item(i)
			out.append(_a(StringName(HOTBAR_PREFIX + str(i)), "Assign to hotbar %d%s" % [i + 1, "" if cur == null or cur == item else " (replace %s)" % cur.display_name()]))
	return out


## Run action [id] on [item]. Returns the verb's {ok, reason?}.
static func perform(actor: Node, item: ItemInstance, id: StringName) -> Dictionary:
	if actor == null or item == null:
		return {"ok": false, "reason": "Nothing there"}
	match id:
		EQUIP:
			return actor.call(&"equip_item", item, &"")
		EQUIP_SECONDARY:
			return actor.call(&"equip_item", item, Equipment.SECONDARY)
		UNEQUIP:
			return actor.call(&"unequip_item", item)
		USE:
			return actor.call(&"use_item", item)
		CONSUME:
			return actor.call(&"consume_item", item, 1.0)
		CONSUME_HALF:
			return actor.call(&"consume_item", item, 0.5)
		DROP:
			return actor.call(&"drop_item", item, -1)
		DROP_ONE:
			return actor.call(&"drop_item", item, 1)
		SPLIT:
			return actor.call(&"split_item", item)
		OPEN_BOX:
			return open_box(actor, item)
	var s := String(id)
	if s.begins_with(HOTBAR_PREFIX):
		var eq: Equipment = actor.get("equipment") as Equipment
		if eq == null:
			return {"ok": false, "reason": "No hotbar"}
		var r := eq.assign_hotbar(int(s.substr(HOTBAR_PREFIX.length())), item)
		if not r.ok:
			EventBus.interaction_refused.emit(actor, null, String(r.reason))
		return r
	return {"ok": false, "reason": "No such action"}
