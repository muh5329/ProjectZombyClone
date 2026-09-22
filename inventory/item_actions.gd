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
const HOTBAR_PREFIX := "hotbar_"


## Why [d] cannot be used yet ("" when it can / is not a consumable).
static func use_block_reason(d: ItemData) -> String:
	if d == null:
		return "Nothing there"
	match d.category:
		ItemData.Category.FOOD:
			return "Eating comes in Round 7"
		ItemData.Category.DRINK:
			return "Drinking comes in Round 7"
	return ""


## True when [d] has a Use verb (dressings; food / drink as stubs).
static func has_use(d: ItemData) -> bool:
	if d is MedicalData and (d as MedicalData).bandage_quality > 0.0:
		return true
	return d != null and (d.category == ItemData.Category.FOOD or d.category == ItemData.Category.DRINK)


static func _a(id: StringName, label: String, enabled: bool = true, reason: String = "") -> Dictionary:
	return {"id": id, "label": label, "enabled": enabled, "reason": reason}


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
		var why := use_block_reason(item.data)
		var label := "Bandage" if why == "" else ("Eat" if item.data.category == ItemData.Category.FOOD else "Drink")
		out.append(_a(USE, label, why == "", "Round 7" if why != "" else ""))
	if item.stack > 1:
		out.append(_a(SPLIT, "Split stack"))
		out.append(_a(DROP_ONE, "Drop one"))
		out.append(_a(DROP, "Drop all"))
	else:
		out.append(_a(DROP, "Drop"))
	if eq and Equipment.is_equippable(item):
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
		DROP:
			return actor.call(&"drop_item", item, -1)
		DROP_ONE:
			return actor.call(&"drop_item", item, 1)
		SPLIT:
			return actor.call(&"split_item", item)
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
