class_name ItemContextMenu
extends PopupMenu
## Right-click menu of the inventory screen: shows the {id, label,
## enabled, reason} entries it is given (ItemActions / container Take)
## and emits action_chosen(side, item, id). Disabled entries show their
## reason in brackets ("Eat (Round 7)").

signal action_chosen(side: StringName, item: ItemInstance, id: StringName)

var item: ItemInstance = null
var side: StringName = &""
var _ids: Array[StringName] = []


func _ready() -> void:
	name = "ContextMenu"
	id_pressed.connect(_on_id)


func open_for(p_side: StringName, p_item: ItemInstance, actions: Array, screen_pos: Vector2) -> void:
	item = p_item
	side = p_side
	_ids.clear()
	clear()
	for i in actions.size():
		var a: Dictionary = actions[i]
		var label := String(a.label)
		if not bool(a.enabled) and String(a.reason) != "":
			label += " (%s)" % a.reason
		add_item(label, i)
		set_item_disabled(i, not bool(a.enabled))
		_ids.append(a.id)
	reset_size()
	position = Vector2i(screen_pos)
	popup()


func _on_id(idx: int) -> void:
	if idx < 0 or idx >= _ids.size() or item == null:
		return
	action_chosen.emit(side, item, _ids[idx])
