class_name ClockWidget
extends PanelContainer
## Top-right digital clock (reference 4): big cyan "08:10", a line with
## the outdoor temperature and the date ("71.6°F 07/12"), and the speed
## steps (|| > >> >>>) with the current one lit. Presentation only: reads
## the TimeManager when the minute / speed changes (EventBus
## time_speed_changed; the minute is compared each frame — cheap).

const COL_LCD := Color(0.35, 0.88, 0.97)
const COL_DIM := Color(0.3, 0.42, 0.46)
const STEP_TEXT: Array[String] = ["||", ">", ">>", ">>>"]

var time_label: Label
var info_label: Label
var speed_labels: Array[Label] = []
var _shown_minute: int = -1
var _shown_step: int = -1


func _ready() -> void:
	name = "Clock"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.025, 0.03, 0.88)
	sb.border_color = Color(0.2, 0.28, 0.3, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 4
	add_theme_stylebox_override(&"panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	time_label = _label(40, COL_LCD)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(time_label)
	info_label = _label(15, COL_LCD)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(info_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override(&"separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	for t in STEP_TEXT:
		var l := _label(20, COL_DIM)
		l.text = t
		row.add_child(l)
		speed_labels.append(l)
	EventBus.time_speed_changed.connect(func(_s: int, _x: float) -> void: refresh(true))
	refresh(true)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", col)
	return l


func _process(_delta: float) -> void:
	refresh()


## Redraw when the game minute or the speed step changed ([force]: always).
func refresh(force: bool = false) -> void:
	var m := int(floor(TimeManager.now()))
	var step := TimeManager.speed_step
	if not force and m == _shown_minute and step == _shown_step:
		return
	_shown_minute = m
	_shown_step = step
	time_label.text = TimeManager.clock_text()
	info_label.text = format_info(TimeManager.temperature_f(), TimeManager.date_text())
	for i in speed_labels.size():
		var lit := i == step
		speed_labels[i].add_theme_color_override(&"font_color", COL_LCD if lit else COL_DIM)


## Pure: "71.6°F 07/12".
static func format_info(temp_f: float, date: String) -> String:
	return "%.1f°F %s" % [temp_f, date]


func shown_time() -> String:
	return time_label.text
