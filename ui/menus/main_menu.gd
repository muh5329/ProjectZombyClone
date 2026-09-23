class_name MainMenu
extends Control
## Title screen (Round 10, the project's main scene): New game (a fresh
## test_ground), Continue (the newest save), Load (slot list), Quit.

const NEW_GAME_SCENE := "res://maps/test_ground.tscn"

var main_box: VBoxContainer
var browser: SlotBrowser
var status: Label
var continue_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = false
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := MenuStyle.panel(Vector2(460, 0))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	panel.add_child(col)
	col.add_child(MenuStyle.title("PROJECT ZOMB", 40))
	col.add_child(MenuStyle.label("This is how you died.", 15))
	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override(&"separation", 8)
	col.add_child(main_box)
	main_box.add_child(MenuStyle.button("New game", new_game))
	continue_button = MenuStyle.button("Continue", continue_game)
	main_box.add_child(continue_button)
	main_box.add_child(MenuStyle.button("Load", show_slots))
	main_box.add_child(MenuStyle.button("Quit", quit))
	browser = SlotBrowser.new()
	browser.name = "Slots"
	browser.visible = false
	browser.closed.connect(_back)
	col.add_child(browser)
	status = MenuStyle.label("")
	col.add_child(status)
	var slots := SaveManager.list_slots()
	continue_button.disabled = slots.is_empty()
	if not slots.is_empty():
		continue_button.tooltip_text = MenuStyle.slot_text(slots[0])
		status.text = "Last save: " + MenuStyle.slot_text(slots[0])


func new_game() -> void:
	SaveManager.new_game(NEW_GAME_SCENE)


func continue_game() -> void:
	var slots := SaveManager.list_slots()
	if slots.is_empty():
		status.text = "No saved games"
		return
	load_slot(String(slots[0].slot))


func show_slots() -> void:
	main_box.visible = false
	browser.open(&"load")


func _back() -> void:
	browser.visible = false
	main_box.visible = true


func load_slot(slot: String) -> void:
	browser.load_slot(slot)
	if browser.status.text != "":
		status.text = browser.status.text
	else:
		status.text = "Loading…"


func quit() -> void:
	get_tree().quit()
