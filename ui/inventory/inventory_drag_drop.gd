class_name InventoryDragDrop
extends RefCounted
## Drag-and-drop rules of the inventory screen (owned by LootWindow).
## Payload = {kind, side, item}. Targets: &"player" (the active player
## tab), &"container" (the open container), &"tab_<i>" (a player tab).
## Container rows are taken through the container, player rows are put
## into the container or moved between the player's own containers
## (Player.move_item — out of a slot unequips).

const KIND := "zomb_item"
const SIDE_PLAYER := &"player"
const SIDE_CONTAINER := &"container"

var window: LootWindow


func _init(w: LootWindow) -> void:
	window = w


func payload(side: StringName, item: ItemInstance) -> Dictionary:
	return {"kind": KIND, "side": side, "item": item}


## The ItemContainer a drop on [target] would fill (null: nowhere).
func destination(target: StringName) -> ItemContainer:
	if target == SIDE_CONTAINER:
		return window.container.inventory if window.container != null else null
	if target == SIDE_PLAYER:
		return window.active_player_container()
	var s := String(target)
	if s.begins_with("tab_"):
		var tabs := window.player_tabs()
		var i := int(s.substr(4))
		return tabs[i].container if i >= 0 and i < tabs.size() else null
	return null


static func _valid(data: Variant) -> bool:
	return data is Dictionary and String((data as Dictionary).get("kind", "")) == KIND


func can_drop(target: StringName, data: Variant) -> bool:
	if not _valid(data):
		return false
	var item: ItemInstance = data.get("item")
	var to := destination(target)
	if item == null or to == null or item.owner_container() == to:
		return false
	if data.get("side", &"") == SIDE_CONTAINER and target == SIDE_CONTAINER:
		return false
	return LootWindow.move_block_reason(item, to) == ""


func drop(target: StringName, data: Variant) -> Dictionary:
	if not _valid(data):
		return {"ok": false, "reason": "Nothing dragged"}
	var item: ItemInstance = data.get("item")
	var to := destination(target)
	var p := window._player()
	var c: Node = window.container
	if item == null or to == null or p == null:
		return {"ok": false, "reason": "Nowhere to put it"}
	if data.get("side", &"") == SIDE_CONTAINER:
		if c == null or target == SIDE_CONTAINER:
			return {"ok": false, "reason": "Already there"}
		return c.take(p, item, -1, to)
	if target == SIDE_CONTAINER:
		if c == null:
			return {"ok": false, "reason": "Nothing open"}
		return c.put(p, item, -1)
	return p.call(&"move_item", item, to, -1)
