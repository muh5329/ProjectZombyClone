class_name Hotbar
extends RefCounted
## The quick-equip bar (keys 1-3): [SIZE] references to ItemInstances,
## owned by an Equipment. Pure bookkeeping — which item sits in which
## slot, one slot per item. References are kept by identity even while
## the item is not carried (dropped, stored): the Equipment reports such
## a slot as "not carried" (greyed on the HUD) and it works again as soon
## as that same item is picked back up. Validation (carried? equippable?)
## lives in Equipment.assign_hotbar.

signal changed

const SIZE := 3

var _items: Array = []


func _init() -> void:
	_items.resize(SIZE)


## The item referenced by slot [index] (carried or not), or null.
func item_at(index: int) -> ItemInstance:
	return _items[index] if index >= 0 and index < SIZE else null


## Slot of [item] (-1 when not on the bar).
func index_of(item: ItemInstance) -> int:
	return -1 if item == null else _items.find(item)


## Put [item] in [index] (null clears); it leaves any other slot.
func assign(index: int, item: ItemInstance) -> bool:
	if index < 0 or index >= SIZE:
		return false
	for i in SIZE:
		if _items[i] == item:
			_items[i] = null
	_items[index] = item
	changed.emit()
	return true


func clear() -> void:
	for i in SIZE:
		_items[i] = null
	changed.emit()
