class_name NoiseMeter
extends HBoxContainer
## HUD "Noise" meter: the radius of the player's last sound (EventBus
## .sound_emitted with the player as source) on a 0..[max_radius] m bar
## with a tick at [loud_radius] — past it the bar turns red and reads
## "LOUD". Holds for [hold_seconds], then drains at [decay_per_second] m/s.
## Pure presentation.

@export var max_radius: float = 20.0
## The "zombies across the street hear this" line (m): from the sound data
## (SoundCategoryTable.player_loud_radius), shared with the noise rings.
var loud_radius: float = 10.0
@export var hold_seconds: float = 0.8
@export var decay_per_second: float = 8.0

const COL_QUIET := Color(0.55, 0.8, 0.9)
const COL_LOUD := Color(1.0, 0.35, 0.25)

## Radius of the last player sound (m) and the category.
var last_radius: float = 0.0
var last_category: StringName = &""
## What the bar shows now (m).
var shown: float = 0.0
var _hold: float = 0.0
var _bar: Control
var _value_label: Label


func _ready() -> void:
	name = "NoiseMeter"
	loud_radius = NoiseRings.loud_radius()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 6)
	var l := Label.new()
	l.text = "Noise"
	l.custom_minimum_size = Vector2(46, 0)
	l.add_theme_font_size_override(&"font_size", 13)
	add_child(l)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(120, 12)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_value_label = Label.new()
	_value_label.add_theme_font_size_override(&"font_size", 13)
	_value_label.custom_minimum_size = Vector2(90, 0)
	add_child(_value_label)
	EventBus.sound_emitted.connect(_on_sound_emitted)
	_refresh()


func _on_sound_emitted(_position: Vector3, radius: float, _intensity: float, category: StringName, source: Node) -> void:
	var p := GameManager.player
	if p == null or source != p:
		return
	if p.has_method(&"is_dead") and p.is_dead():
		return
	last_radius = radius
	last_category = category
	# A quiet footstep right after a loud smash does not hide the smash.
	# Held for the category's duration at least: hammering repeats every
	# 1.5 s while working, so the meter keeps reading 18 m (not a decay).
	if radius >= shown:
		shown = radius
		var hold := hold_seconds
		var cat: Variant = SoundManager.category(category)
		if cat != null:
			hold = maxf(hold, float(cat.duration) + 0.1)
		_hold = hold
	_refresh()


func is_loud() -> bool:
	return shown >= loud_radius


## "8 m", "14 m LOUD", "" when silent.
static func format_value(r: float, loud_at: float) -> String:
	if r < 0.5:
		return ""
	return "%d m%s" % [int(round(r)), "  LOUD" if r >= loud_at else ""]


func _process(delta: float) -> void:
	if shown <= 0.0:
		return
	if _hold > 0.0:
		_hold -= delta
		return
	shown = maxf(0.0, shown - decay_per_second * delta)
	_refresh()


func _refresh() -> void:
	if _value_label == null:
		return
	_value_label.text = format_value(shown, loud_radius)
	_value_label.add_theme_color_override(&"font_color", COL_LOUD if is_loud() else Color(0.9, 0.92, 0.95))
	_bar.queue_redraw()


func _draw_bar() -> void:
	var s := _bar.size
	_bar.draw_rect(Rect2(Vector2.ZERO, s), Color(0.05, 0.05, 0.07, 0.75))
	var f := clampf(shown / maxf(max_radius, 0.1), 0.0, 1.0)
	if f > 0.0:
		_bar.draw_rect(Rect2(Vector2(1, 1), Vector2((s.x - 2) * f, s.y - 2)), COL_LOUD if is_loud() else COL_QUIET)
	var tx := s.x * clampf(loud_radius / maxf(max_radius, 0.1), 0.0, 1.0)
	_bar.draw_line(Vector2(tx, -2), Vector2(tx, s.y + 2), Color(1, 1, 1, 0.85), 2.0)
