class_name Equipment
extends Node
## What a character wears / holds (child "Equipment" of the Player; generic
## for NPCs). Slots:
##
## - primary_hand   — weapons / tools (MeleeCombat swings what is here)
## - secondary_hand — a second one-handed item; a TWO-HANDED weapon in the
##                    primary hand occupies both (secondary() returns it)
## - back           — a bag (ContainerItemData); its contents are carried
##                    storage with the bag's weight reduction
## - hotbar 1-3     — a Hotbar (inventory/hotbar.gd) of references to
##                    items for quick equip (keys 1-3); not storage.
##
## Every slot is an unlimited ItemContainer tagged with its slot id, so an
## equipped item is OUT of the inventory (its weight counts once, via
## Encumbrance) and every generic transfer (ItemContainer.transfer_to,
## the loot window) works on equipped items too; slot changes from
## anywhere are noticed through the slot containers' `changed`.
##
## Rules (all refusals return {ok: false, reason}):
## - bags only on the back ("Bags go on the back"), only bags there
##   ("Only bags go on the back"); hands take weapons, tools and items
##   tagged &"hand" ("Can't hold that");
## - equipping displaces what is in the way (a two-hander clears both
##   hands) into the main inventory, else the worn bag — refused as a
##   whole ("No room in inventory") when it does not fit;
## - unequip goes to the main inventory, else the worn bag, else refused;
## - the owner's can_release_item() guards anything leaving a slot
##   (the swung weapon mid-swing: "Mid-swing").
##
## Signals: equipped_changed(slot, item) locally (MeleeCombat, visuals),
## EventBus.equipment_changed / hotbar_changed; contents_changed when any
## slot or the worn bag's contents change (Encumbrance, UI).
## to_dict()/from_dict() store the slots (bags with nested contents) and
## the hotbar as references into the character's containers.

signal equipped_changed(slot: StringName, item: ItemInstance)
signal contents_changed
signal hotbar_changed

const PRIMARY := &"primary_hand"
const SECONDARY := &"secondary_hand"
const BACK := &"back"
const SLOTS: Array[StringName] = [PRIMARY, SECONDARY, BACK]
const HAND_SLOTS: Array[StringName] = [PRIMARY, SECONDARY]
const HOTBAR_SIZE := Hotbar.SIZE
const SLOT_LABELS := {PRIMARY: "Primary hand", SECONDARY: "Secondary hand", BACK: "Back"}

const REASON_NO_ROOM := "No room in inventory"
const REASON_BAG_BACK := "Bags go on the back"
const REASON_ONLY_BAGS := "Only bags go on the back"
const REASON_CANT_HOLD := "Can't hold that"
const REASON_NOT_CARRIED := "Not carried"

## The character (anything exposing `inventory: ItemContainer`; optional
## can_release_item(item)). Defaults to the parent.
var character: Node
## slot id -> ItemContainer (unlimited, equipment_slot = id).
var slots: Dictionary = {}
## Quick-equip references (keys 1-3).
var hotbar := Hotbar.new()

var _last: Dictionary = {}
var _last_hotbar: Array = []


func _init() -> void:
	for s in SLOTS:
		var c := ItemContainer.new(-1.0)
		c.equipment_slot = s
		slots[s] = c
		_last[s] = null
		c.changed.connect(_on_slot_changed.bind(s))
	hotbar.changed.connect(_emit_hotbar_if_changed)


func _ready() -> void:
	if character == null:
		character = get_parent()
	var inv := main_inventory()
	if inv != null and not inv.changed.is_connected(_on_storage_changed):
		inv.changed.connect(_on_storage_changed)


# --- Queries -------------------------------------------------------------------

func main_inventory() -> ItemContainer:
	return ContainerAccess.inventory_of(character)


func item_in(slot: StringName) -> ItemInstance:
	var c: ItemContainer = slots.get(slot)
	return c.items[0] if c != null and not c.items.is_empty() else null


func primary() -> ItemInstance:
	return item_in(PRIMARY)


## The secondary-hand item; a two-handed primary occupies it too.
func secondary() -> ItemInstance:
	var p := primary()
	if p != null and p.is_two_handed():
		return p
	return item_in(SECONDARY)


func back_bag() -> ItemInstance:
	return item_in(BACK)


## The worn bag's contents (carried storage), or null.
func bag_contents() -> ItemContainer:
	var b := back_bag()
	return b.contents if b != null else null


## Distinct items in the hands (a two-hander once).
func hand_items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for s in HAND_SLOTS:
		var it := item_in(s)
		if it != null and not out.has(it):
			out.append(it)
	return out


## Every equipped item (hands + back), slot order.
func equipped_items() -> Array[ItemInstance]:
	var out := hand_items()
	if back_bag() != null:
		out.append(back_bag())
	return out


## The slot holding [item] (&"" when not equipped).
func slot_of(item: ItemInstance) -> StringName:
	if item == null:
		return &""
	for s in SLOTS:
		if item_in(s) == item:
			return s
	return &""


func is_equipped(item: ItemInstance) -> bool:
	return slot_of(item) != &""


## Storage the character carries items in: main inventory, worn bag.
func storage() -> Array[ItemContainer]:
	var out: Array[ItemContainer] = []
	var m := main_inventory()
	if m != null:
		out.append(m)
	var b := bag_contents()
	if b != null:
		out.append(b)
	return out


## True for the main inventory, the worn bag's contents and slot containers.
func owns_container(c: ItemContainer) -> bool:
	if c == null:
		return false
	return storage().has(c) or slots.values().has(c)


## True when [item] is equipped or stored in carried storage.
func carries(item: ItemInstance) -> bool:
	return item != null and item.stack > 0 and owns_container(item.owner_container())


## Default slot for [item]: bags → back, everything else → primary hand.
static func default_slot(item: ItemInstance) -> StringName:
	return BACK if item != null and item.is_bag() else PRIMARY


## Pure slot rule: "" when [item] may go into [slot].
static func slot_rule(item: ItemInstance, slot: StringName) -> String:
	if item == null or item.data == null:
		return "Nothing there"
	if not SLOTS.has(slot):
		return "No such slot"
	if slot == BACK:
		return "" if item.is_bag() else REASON_ONLY_BAGS
	if item.is_bag():
		return REASON_BAG_BACK
	return "" if can_hold(item.data) else REASON_CANT_HOLD


## Items that go in the hands: weapons, tools, anything tagged &"hand".
static func can_hold(d: ItemData) -> bool:
	return d != null and (d.category == ItemData.Category.WEAPON or d.category == ItemData.Category.TOOL or d.has_tag(&"hand"))


## True when [item] can be equipped somewhere (UI: show "Equip").
static func is_equippable(item: ItemInstance) -> bool:
	return item != null and slot_rule(item, default_slot(item)) == ""


# --- Equip / unequip -------------------------------------------------------------

## Put [item] (carried, or a free instance) into [slot] (&"" = default).
## One item of a stack is taken. Whatever is in the way goes back into
## storage — or nothing happens ("No room in inventory").
func equip(item: ItemInstance, slot: StringName = &"") -> Dictionary:
	if slot == &"":
		slot = default_slot(item)
	var why := slot_rule(item, slot)
	if why != "":
		return _no(why)
	if slot == SECONDARY and item.is_two_handed():
		slot = PRIMARY
	if item_in(slot) == item or (slot == SECONDARY and secondary() == item):
		return {"ok": true, "slot": slot}
	var src := item.owner_container()
	if src != null and not owns_container(src):
		return _no(REASON_NOT_CARRIED)
	if src != null and src.equipment_slot != &"":
		var rel0 := _release_check(item)
		if rel0 != "":
			return _no(rel0)
	# What has to make room.
	var displaced: Array[ItemInstance] = []
	match slot:
		PRIMARY:
			_add_unique(displaced, item_in(PRIMARY))
			if item.is_two_handed():
				_add_unique(displaced, item_in(SECONDARY))
		SECONDARY:
			_add_unique(displaced, item_in(SECONDARY))
			var p := primary()
			if p != null and p.is_two_handed():
				_add_unique(displaced, p)
		BACK:
			_add_unique(displaced, back_bag())
	displaced.erase(item)
	for d in displaced:
		var rel := _release_check(d)
		if rel != "":
			return _no(rel)
	var plan := _plan_stow(displaced, item, src, slot == BACK)
	if plan.is_empty() and not displaced.is_empty():
		return _no(REASON_NO_ROOM)
	# Commit: take the item, stow the displaced, fill the slot.
	var taking := item
	if src != null:
		taking = src.remove(item, 1)
	elif item.stack > 1:
		taking = item.split(1)
	for i in displaced.size():
		var d := displaced[i]
		var from := d.owner_container()
		if from != null:
			from.remove(d)
		var r: Dictionary = (plan[i] as ItemContainer).add(d)
		if not r.ok:
			push_warning("Equipment.equip: stow of %s failed (%s)" % [d.id(), r.get("reason", "?")])
	var put: Dictionary = (slots[slot] as ItemContainer).add(taking)
	if not put.ok:
		push_warning("Equipment.equip: slot %s refused %s" % [slot, taking.id()])
		return _no(String(put.get("reason", "Can't equip")))
	return {"ok": true, "slot": slot, "item": taking}


## Move whatever is in [what] (a slot id or an equipped ItemInstance) back
## into storage: main inventory first, else the worn bag.
func unequip(what: Variant) -> Dictionary:
	var item: ItemInstance = what as ItemInstance if what is ItemInstance else item_in(StringName(what))
	var slot := slot_of(item)
	if item == null or slot == &"":
		return _no("Not equipped")
	var rel := _release_check(item)
	if rel != "":
		return _no(rel)
	var dest := _stow_target(item, 0.0, [])
	if dest == null:
		return _no(REASON_NO_ROOM)
	var r := (slots[slot] as ItemContainer).transfer_to(dest, item)
	if not r.ok:
		return _no(String(r.get("reason", REASON_NO_ROOM)))
	return {"ok": true, "slot": slot, "to": dest}


## Remove [item] from its slot for good (a weapon that broke).
func destroy(item: ItemInstance) -> bool:
	var slot := slot_of(item)
	if slot == &"":
		return false
	(slots[slot] as ItemContainer).remove(item)
	var hi := hotbar.index_of(item)
	if hi >= 0:
		hotbar.assign(hi, null)  # a broken weapon is gone for good
	return true


## Remove everything (tests, from_dict).
func clear() -> void:
	for s in SLOTS:
		(slots[s] as ItemContainer).clear()
	hotbar.clear()


func _release_check(item: ItemInstance) -> String:
	if character != null and character.has_method(&"can_release_item"):
		var r: Dictionary = character.call(&"can_release_item", item)
		if not r.get("ok", true):
			return String(r.get("reason", "Can't let go"))
	return ""


## Where each displaced item would go (parallel array), [] when one of
## them does not fit. [taking] leaves [src] first (frees its weight);
## a new back bag's contents are not a stow target.
func _plan_stow(displaced: Array[ItemInstance], taking: ItemInstance, src: ItemContainer, replacing_back: bool) -> Array:
	var out: Array = []
	var freed := {}
	if src != null:
		freed[src] = taking.unit_weight()
	var used := {}
	for d in displaced:
		var skip: Array = []
		if replacing_back and bag_contents() != null:
			skip.append(bag_contents())  # the old bag is the one leaving
		if d.contents != null:
			skip.append(d.contents)
		var dest: ItemContainer = null
		for c in storage():
			if skip.has(c):
				continue
			if c.accept_reason(d) != "":
				continue
			var free := c.free_weight() + float(freed.get(c, 0.0)) - float(used.get(c, 0.0))
			var w := d.total_weight()
			if src != null and d.contents == src:
				w -= taking.unit_weight()  # the new item came out of this bag
			if w <= free + ItemContainer.EPS:
				dest = c
				used[c] = float(used.get(c, 0.0)) + w
				break
		if dest == null:
			return []
		out.append(dest)
	return out


## First storage container that takes [item] whole (not its own contents).
func _stow_target(item: ItemInstance, _extra: float, _skip: Array) -> ItemContainer:
	for c in storage():
		if c == item.contents:
			continue
		if c.fit_item(item) >= item.stack:
			return c
	return null


func _add_unique(list: Array[ItemInstance], it: ItemInstance) -> void:
	if it != null and not list.has(it):
		list.append(it)


func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


# --- Hotbar -----------------------------------------------------------------------

## Assign [item] to hotbar slot [index] (null clears). An item sits in at
## most one hotbar slot. Only carried / equipped equippable items.
func assign_hotbar(index: int, item: ItemInstance) -> Dictionary:
	if index < 0 or index >= HOTBAR_SIZE:
		return _no("No such hotbar slot")
	if item != null and not carries(item):
		return _no(REASON_NOT_CARRIED)
	if item != null and not is_equippable(item):
		return _no(REASON_CANT_HOLD)
	hotbar.assign(index, item)
	return {"ok": true}


## The item assigned to [index] while the character carries it (null
## otherwise — the reference is kept, so picking that item back up
## restores the slot).
func hotbar_item(index: int) -> ItemInstance:
	var it := hotbar.item_at(index)
	return it if it != null and carries(it) else null


## Key 1-3: equip the assigned item (unequip it when already held).
func use_hotbar(index: int) -> Dictionary:
	var item := hotbar.item_at(index)
	if item == null:
		return _no("Hotbar slot %d is empty" % (index + 1))
	if not carries(item):
		return _no(REASON_NOT_CARRIED)
	if is_equipped(item):
		return unequip(item)
	return equip(item)


## [{index, id, name, color, equipped, carried}] for the HUD ({index}
## when empty; carried false = assigned but not on the character).
func hotbar_summary() -> Array:
	var out: Array = []
	for i in HOTBAR_SIZE:
		var it := hotbar.item_at(i)
		if it == null or it.data == null:
			out.append({"index": i})
		else:
			out.append({"index": i, "id": it.id(), "name": it.display_name(), "color": it.data.color,
					"equipped": is_equipped(it), "carried": carries(it)})
	return out


## Emit hotbar_changed only when what the bar shows changed (assignment,
## equipped flag, carried flag) — not on every inventory change.
func _emit_hotbar_if_changed() -> void:
	var s := hotbar_summary()
	if s == _last_hotbar:
		return
	_last_hotbar = s
	hotbar_changed.emit()
	if character != null and is_inside_tree():
		EventBus.hotbar_changed.emit(character, s)


# --- Change tracking ------------------------------------------------------------------

func _on_slot_changed(slot: StringName) -> void:
	var now := item_in(slot)
	if now != _last[slot]:
		_last[slot] = now
		equipped_changed.emit(slot, now)
		if character != null and is_inside_tree():
			var info := {} if now == null else {"id": now.id(), "name": now.display_name()}
			EventBus.equipment_changed.emit(character, slot, info)
	_on_storage_changed()


func _on_storage_changed() -> void:
	_emit_hotbar_if_changed()
	contents_changed.emit()


# --- Save ------------------------------------------------------------------------------

## {slots: {slot: item dict}, hotbar: [ref | null]} — refs point into the
## slots ({where: "slot", slot}) or carried storage ({where: "main" /
## "bag", index}). Restore the main inventory BEFORE calling from_dict.
func to_dict() -> Dictionary:
	var sd := {}
	for s in SLOTS:
		var it := item_in(s)
		if it != null:
			sd[String(s)] = it.to_dict()
	var hb: Array = []
	for i in HOTBAR_SIZE:
		hb.append(_ref_of(hotbar_item(i)))
	return {"slots": sd, "hotbar": hb}


## Restore the slots through the same rules as equip(): unknown items,
## items not allowed in their slot, a two-hander outside the primary hand
## and a one-hander next to a two-hander are rejected with a warning.
func from_dict(d: Dictionary) -> void:
	for s in SLOTS:
		(slots[s] as ItemContainer).clear()
	var sd: Dictionary = d.get("slots", {})
	for k in sd:
		if not SLOTS.has(StringName(String(k))):
			push_warning("Equipment.from_dict: unknown slot '%s'" % k)
	# Back and primary first, so the secondary check sees a two-hander.
	for s in [BACK, PRIMARY, SECONDARY]:
		if not sd.has(String(s)):
			continue
		var inst := ItemInstance.from_dict(sd[String(s)])
		if inst == null:
			push_warning("Equipment.from_dict: unknown item in %s" % s)
			continue
		var why := slot_rule(inst, s)
		if why == "" and s == SECONDARY and inst.is_two_handed():
			why = "two-handed weapons go in the primary hand"
		if why == "" and s == SECONDARY and primary() != null and primary().is_two_handed():
			why = "both hands hold a two-handed weapon"
		if why != "":
			push_warning("Equipment.from_dict: %s rejected from %s (%s)" % [inst.id(), s, why])
			continue
		var r := equip(inst, s)
		if not r.ok:
			push_warning("Equipment.from_dict: %s not equipped (%s)" % [inst.id(), r.reason])
	var hb: Array = d.get("hotbar", [])
	for i in HOTBAR_SIZE:
		hotbar.assign(i, _resolve_ref(hb[i]) if i < hb.size() else null)


func _ref_of(item: ItemInstance) -> Variant:
	if item == null:
		return null
	var s := slot_of(item)
	if s != &"":
		return {"where": "slot", "slot": String(s)}
	var m := main_inventory()
	if m != null and m.has(item):
		return {"where": "main", "index": m.index_of(item)}
	var b := bag_contents()
	if b != null and b.has(item):
		return {"where": "bag", "index": b.index_of(item)}
	return null


func _resolve_ref(ref: Variant) -> ItemInstance:
	if not ref is Dictionary:
		return null
	var r: Dictionary = ref
	match String(r.get("where", "")):
		"slot":
			return item_in(StringName(String(r.get("slot", ""))))
		"main":
			var m := main_inventory()
			var i := int(r.get("index", -1))
			return m.items[i] if m != null and i >= 0 and i < m.items.size() else null
		"bag":
			var b := bag_contents()
			var j := int(r.get("index", -1))
			return b.items[j] if b != null and j >= 0 and j < b.items.size() else null
	return null
