class_name HotbarWidget
extends HBoxContainer
## Bottom-centre quick-equip bar (reference 4): three slots showing the
## items assigned to the player's Equipment hotbar (keys 1-3). Equipped
## slot: gold border; an assigned item no longer carried is dimmed.
## Presentation only: listens to EventBus.hotbar_changed.

const SLOT := Vector2(68, 58)
const COL_BG := Color(0.07, 0.07, 0.08, 0.82)
const COL_BORDER := Color(0.35, 0.35, 0.38, 0.9)
const COL_EQUIPPED := Color(1.0, 0.8, 0.35, 1.0)

var slots: Array[Panel] = []
var _styles: Array[StyleBoxFlat] = []
## Last summary received (tests).
var summary: Array = []


func _ready() -> void:
	name = "Hotbar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 4)
	_styles = [_style(COL_BORDER, 1), _style(COL_EQUIPPED, 2)]
	for i in Equipment.HOTBAR_SIZE:
		slots.append(_make_slot(i))
	EventBus.hotbar_changed.connect(_on_hotbar_changed)
	var p := GameManager.player
	var eq := p.get_node_or_null("Equipment") as Equipment if p else null
	show_summary(eq.hotbar_summary() if eq else [])


func _style(border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_BG
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(2)
	return s


func _make_slot(i: int) -> Panel:
	var p := Panel.new()
	p.name = "Slot%d" % (i + 1)
	p.custom_minimum_size = SLOT
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override(&"panel", _styles[0])
	add_child(p)
	var n := Label.new()
	n.text = str(i + 1)
	n.position = Vector2(4, 1)
	n.add_theme_font_size_override(&"font_size", 11)
	n.add_theme_color_override(&"font_color", Color(0.8, 0.8, 0.78))
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(n)
	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.position = Vector2(22, 12)
	icon.size = Vector2(24, 24)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	var nm := Label.new()
	nm.name = "Name"
	nm.position = Vector2(2, 38)
	nm.size = Vector2(SLOT.x - 4, 18)
	nm.clip_text = true
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override(&"font_size", 9)
	nm.add_theme_color_override(&"font_color", Color(0.92, 0.92, 0.88))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(nm)
	return p


func _on_hotbar_changed(c: Node, s: Array) -> void:
	if c == GameManager.player:
		show_summary(s)


func show_summary(s: Array) -> void:
	summary = s
	for i in slots.size():
		var d: Dictionary = s[i] if i < s.size() else {}
		var p := slots[i]
		var icon: ColorRect = p.get_node("Icon")
		var nm: Label = p.get_node("Name")
		var has := d.has("id")
		icon.visible = has
		nm.text = String(d.get("name", "")) if has else ""
		if has:
			icon.color = d.get("color", Color.GRAY)
		var eq := bool(d.get("equipped", false))
		p.add_theme_stylebox_override(&"panel", _styles[1 if eq else 0])
		p.modulate = Color(1, 1, 1, 1.0 if not has or bool(d.get("carried", true)) else 0.45)
		p.tooltip_text = "%d: %s%s" % [i + 1, nm.text, " (equipped)" if eq else ""] if has else "%d: empty — right-click an item → Assign to hotbar" % (i + 1)


## Name shown in slot [i] ("" when empty).
func slot_name(i: int) -> String:
	return (slots[i].get_node("Name") as Label).text if i >= 0 and i < slots.size() else ""


func slot_equipped(i: int) -> bool:
	return i >= 0 and i < summary.size() and bool((summary[i] as Dictionary).get("equipped", false))
