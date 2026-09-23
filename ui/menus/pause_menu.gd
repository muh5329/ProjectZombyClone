class_name PauseMenu
extends CanvasLayer
## Esc pause menu (Round 10): Resume / Save / Load / Quit to menu. Pauses
## the tree (this layer keeps processing: PROCESS_MODE_ALWAYS) and puts
## the previous pause state (F5 time pause) back on resume. Save / Load
## open the named-slot browser (SlotBrowser); Quit asks when progress
## would be lost (SaveManager.request_quit_to_menu).
##
## Esc reaches it only when nothing else wanted it (it sits early in the
## map, so the loot window / a running timed action consume Esc first).

## Slot of the quick "Save" of older callers / tests.
const SAVE_SLOT := "manual"

var root: Control
var main_box: VBoxContainer
var browser: SlotBrowser
var status: Label
var _was_paused: bool = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"pause_menu")
	_build()
	root.visible = false


func is_open() -> bool:
	return root.visible


func _build() -> void:
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := MenuStyle.panel(Vector2(360, 0))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 10)
	panel.add_child(col)
	col.add_child(MenuStyle.title("Paused"))
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override(&"separation", 8)
	col.add_child(main_box)
	main_box.add_child(MenuStyle.button("Resume", close))
	main_box.add_child(MenuStyle.button("Save", show_save))
	main_box.add_child(MenuStyle.button("Load", show_slots))
	main_box.add_child(MenuStyle.button("Quit to menu", quit_to_menu))
	browser = SlotBrowser.new()
	browser.name = "Slots"
	browser.visible = false
	browser.closed.connect(_back)
	col.add_child(browser)
	status = MenuStyle.label("F9 quick-save · F10 quick-load")
	col.add_child(status)


func open() -> void:
	if root.visible:
		return
	_was_paused = get_tree().paused
	get_tree().paused = true
	_back()
	status.text = "F9 quick-save · F10 quick-load"
	root.visible = true


func close() -> void:
	if not root.visible:
		return
	root.visible = false
	if is_inside_tree():
		get_tree().paused = _was_paused


func toggle() -> void:
	if root.visible:
		close()
	else:
		open()


## Quick save into [SAVE_SLOT] (no dialog).
func save() -> Dictionary:
	var r := SaveManager.save_game(SAVE_SLOT, SaveManager.current_map())
	status.text = "Game saved (%s)" % SAVE_SLOT if r.ok else String(r.error)
	return r


func show_save() -> void:
	main_box.visible = false
	browser.open(&"save")
	status.text = "Name a new save, or overwrite one"


func show_slots() -> void:
	main_box.visible = false
	browser.open(&"load")
	status.text = "Pick a save"


func _back() -> void:
	browser.visible = false
	main_box.visible = true


func load_slot(slot: String) -> void:
	browser.load_slot(slot)
	if browser.status.text != "":
		status.text = browser.status.text


func quit_to_menu() -> void:
	SaveManager.request_quit_to_menu()


func _unhandled_input(event: InputEvent) -> void:
	if SaveManager.is_confirming():
		return
	if event.is_action_pressed(&"ui_cancel"):
		if root.visible and browser.visible:
			_back()
		else:
			toggle()
		get_viewport().set_input_as_handled()
