class_name SlotBrowser
extends VBoxContainer
## Named save slots (Round 10) for the pause menu and the title screen:
## one row per slot (name, day / clock, health, real date) with
## Overwrite + Delete (save mode) or Load + Delete (load mode), and in
## save mode a name field + "Save as new". Overwriting and deleting ask
## for confirmation (SaveManager.confirm); loading goes through
## SaveManager.request_load (asks when unsaved progress would be lost).

signal closed
signal saved(slot: String)

var mode: StringName = &"load"
var list_box: VBoxContainer
var name_edit: LineEdit
var status: Label


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override(&"separation", 4)
	add_child(list_box)
	var new_row := HBoxContainer.new()
	new_row.name = "NewRow"
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "New save name"
	name_edit.max_length = SaveFile.MAX_SLOT_LENGTH
	name_edit.custom_minimum_size = Vector2(220, 34)
	name_edit.text_submitted.connect(func(_t): save_new())
	new_row.add_child(name_edit)
	var b := MenuStyle.button("Save as new", save_new)
	b.custom_minimum_size = Vector2(140, 34)
	new_row.add_child(b)
	add_child(new_row)
	status = MenuStyle.label("", 13)
	add_child(status)
	add_child(MenuStyle.button("Back", func(): closed.emit()))


func open(p_mode: StringName) -> void:
	mode = p_mode
	(get_node("NewRow") as Control).visible = mode == &"save"
	status.text = ""
	refresh()
	visible = true


func refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var slots := SaveManager.list_slots()
	if slots.is_empty():
		list_box.add_child(MenuStyle.label("No saved games", 14))
	for e in slots:
		var slot := String(e.slot)
		var row := HBoxContainer.new()
		row.name = "Slot_" + SaveFile.encode_slot(slot)
		var l := MenuStyle.label(MenuStyle.slot_text(e), 13, Color(0.9, 0.9, 0.88))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size = Vector2(380, 0)
		row.add_child(l)
		if mode == &"save":
			row.add_child(_small("Overwrite", ask_overwrite.bind(slot)))
		else:
			row.add_child(_small("Load", load_slot.bind(slot)))
		row.add_child(_small("Delete", ask_delete.bind(slot)))
		list_box.add_child(row)


func _small(text: String, cb: Callable) -> Button:
	var b := MenuStyle.button(text, cb)
	b.custom_minimum_size = Vector2(96, 30)
	b.add_theme_font_size_override(&"font_size", 14)
	return b


func save_new() -> void:
	var slot := name_edit.text.strip_edges()
	if not SaveFile.is_valid_slot(slot):
		status.text = "Type a name for the save"
		return
	if SaveManager.has_slot(slot):
		ask_overwrite(slot)
		return
	_save(slot)


func ask_overwrite(slot: String) -> void:
	SaveManager.confirm("Overwrite the save '%s'?" % slot, _save.bind(slot))


func _save(slot: String) -> void:
	var r := SaveManager.save_game(slot, SaveManager.current_map())
	status.text = "Saved '%s'" % slot if r.ok else String(r.error)
	if r.ok:
		name_edit.text = ""
		saved.emit(slot)
	refresh()


func ask_delete(slot: String) -> void:
	SaveManager.confirm("Delete the save '%s'?" % slot, _delete.bind(slot))


func _delete(slot: String) -> void:
	status.text = "Deleted '%s'" % slot if SaveManager.delete_slot(slot) else "Could not delete '%s'" % slot
	refresh()


func load_slot(slot: String) -> void:
	# Checked first (a bad save leaves everything as it is); the load runs
	# in the SaveManager, which replaces this menu.
	var r := SaveManager.read_slot(slot)
	if not r.ok:
		status.text = String(r.error)
		return
	SaveManager.request_load(slot)
