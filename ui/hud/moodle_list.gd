class_name MoodleList
extends VBoxContainer
## PZ-style "moodles" on the right edge under the clock (Round 7): one row
## per need above fine — a label ("Hungry") and a small square coloured by
## severity (yellow → orange → red) with the need's initial. Presentation
## only: EventBus.moodles_changed for the player; the tooltip carries the
## level ("Hunger: level 2 / 4").

const SQUARE := Vector2(26, 26)
const INITIALS := {&"hunger": "H", &"thirst": "T", &"fatigue": "F", &"sickness": "S"}

## Last list received ([{id, label, level, max_level}]).
var moodles: Array = []
## Last need pulsed (tests).
var pulsing: StringName = &""


func _ready() -> void:
	name = "Moodles"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 4)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	EventBus.moodles_changed.connect(_on_moodles_changed)
	var p := GameManager.player
	var needs := p.get_node_or_null("Needs") as NeedsComponent if p else null
	show_moodles(needs.moodles() if needs else [])


func _on_moodles_changed(c: Node, list: Array) -> void:
	if c != null and c == GameManager.player:
		show_moodles(list)


## Pure: severity colour for [level] of [max_level].
static func severity_color(level: int, max_level: int) -> Color:
	var f := clampf(float(level) / float(maxi(max_level, 1)), 0.0, 1.0)
	if f >= 0.99:
		return Color(0.9, 0.15, 0.12)
	if f >= 0.66:
		return Color(0.95, 0.4, 0.15)
	if f >= 0.4:
		return Color(0.95, 0.65, 0.2)
	return Color(0.9, 0.85, 0.4)


func show_moodles(list: Array) -> void:
	moodles = list
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for m: Dictionary in list:
		add_child(_row(m))


func _row(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Moodle_%s" % String(m.id)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = "%s: level %d / %d" % [String(m.id).capitalize(), int(m.level), int(m.max_level)]
	var col := severity_color(int(m.level), int(m.max_level))
	var l := Label.new()
	l.text = String(m.label)
	l.add_theme_font_size_override(&"font_size", 15)
	l.add_theme_color_override(&"font_color", col.lightened(0.2))
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override(&"outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	var sq := Panel.new()
	sq.custom_minimum_size = SQUARE
	sq.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0.05, 0.05, 0.05, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(13)
	sq.add_theme_stylebox_override(&"panel", sb)
	var ini := Label.new()
	ini.text = String(INITIALS.get(StringName(m.id), "?"))
	ini.add_theme_font_size_override(&"font_size", 13)
	ini.add_theme_color_override(&"font_color", Color(0.08, 0.06, 0.05))
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ini.set_anchors_preset(Control.PRESET_FULL_RECT)
	ini.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sq.add_child(ini)
	row.add_child(sq)
	return row


## Flash the row of [need] a few times (a need reached a dangerous level).
## Returns false when that moodle is not shown.
func pulse(need: StringName) -> bool:
	var row := get_node_or_null("Moodle_%s" % String(need)) as Control
	if row == null:
		return false
	pulsing = need
	var tw := row.create_tween()
	tw.set_loops(4)
	tw.tween_property(row, ^"modulate", Color(1.8, 1.8, 1.8, 1.0), 0.25)
	tw.tween_property(row, ^"modulate", Color.WHITE, 0.25)
	return true


## Labels currently shown (tests).
func labels() -> PackedStringArray:
	var out: PackedStringArray = []
	for m: Dictionary in moodles:
		out.append(String(m.label))
	return out
