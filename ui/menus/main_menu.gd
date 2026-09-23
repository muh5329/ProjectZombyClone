class_name MainMenu
extends Control
## Title screen (Round 10, the project's main scene): New game, Continue
## (the newest save), Load (slot list), Quit. Round 11: New game generates
## a fresh county (maps/world.tscn) from a random seed, or from the number
## typed in the seed field; the seed is shown (and on the M map).

const NEW_GAME_SCENE := "res://maps/world.tscn"

var main_box: VBoxContainer
var seed_edit: LineEdit
## Seed of the last New game (the typed one, else a random one).
var last_seed: int = -1
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
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override(&"separation", 8)
	seed_row.add_child(MenuStyle.label("World seed", 14))
	seed_edit = LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.placeholder_text = "random"
	seed_edit.max_length = 9
	seed_edit.custom_minimum_size = Vector2(160, 0)
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(seed_edit)
	main_box.add_child(seed_row)
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


## The seed for a new game: the typed number, else a random one.
func chosen_seed() -> int:
	var t := seed_edit.text.strip_edges() if seed_edit != null else ""
	if t.is_valid_int() and int(t) >= 0:
		return int(t)
	return randi() % 1000000


func new_game() -> void:
	last_seed = chosen_seed()
	status.text = "Generating world (seed %d)…" % last_seed
	SaveManager.new_game(NEW_GAME_SCENE, last_seed)


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
