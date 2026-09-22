extends CanvasLayer
## Minimal survival HUD. Event-driven: listens to the EventBus for the
## registered player's stats and movement mode. Only the debug overlay
## polls (position/speed/fps are not events).
## Deliberately dumb: no gameplay logic, only presentation.

const COL_OK := Color(0.55, 0.8, 0.35)
const COL_LOW := Color(0.95, 0.65, 0.2)
const COL_EXHAUSTED := Color(0.9, 0.25, 0.2)

@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var stamina_label: Label = %StaminaLabel
@onready var mode_label: Label = %ModeLabel
@onready var debug_label: Label = %DebugLabel
@onready var hint_label: Label = %HintLabel
@onready var notice_label: Label = %NoticeLabel

var _flash_time: float = 0.0
var _notice_time: float = 0.0
var _stamina_state: StringName = &"normal"
var _mode: StringName = &"jog"
var _exhausted: bool = false
var _frac: float = 1.0


func _ready() -> void:
	EventBus.stat_changed.connect(_on_stat_changed)
	EventBus.stat_threshold.connect(_on_stat_threshold)
	EventBus.movement_mode_changed.connect(_on_mode_changed)
	EventBus.sprint_denied.connect(_on_sprint_denied)
	hint_label.text = "WASD move · Shift sprint · Ctrl sneak · Alt walk · Q/R rotate · Wheel zoom · F3 debug"
	notice_label.text = ""
	_sync_from_player()
	_refresh()


func _is_player(c: Node) -> bool:
	return c != null and c == GameManager.player


## Pull current values once (HUD may be created after the player).
func _sync_from_player() -> void:
	var p := GameManager.player as Character
	if p == null:
		return
	_frac = p.stats.get_fraction(Character.STAMINA)
	_stamina_state = p.stats.get_state(Character.STAMINA)
	_mode = MovementComponent.mode_name(p.effective_mode)
	_exhausted = p.exhausted


func _on_stat_changed(c: Node, stat: StringName, value: float, max_value: float) -> void:
	if stat == Character.STAMINA and _is_player(c):
		_frac = 0.0 if max_value <= 0.0 else value / max_value
		_refresh()


func _on_stat_threshold(c: Node, stat: StringName, state: StringName) -> void:
	if stat != Character.STAMINA or not _is_player(c):
		return
	_stamina_state = state
	_exhausted = (c as Character).exhausted
	if state == &"exhausted":
		_flash_time = 1.2
		_notice("Exhausted!", 2.0)
	_refresh()


func _on_mode_changed(c: Node, mode: StringName) -> void:
	if _is_player(c):
		_mode = mode
		_exhausted = (c as Character).exhausted
		_refresh()


func _on_sprint_denied(c: Node) -> void:
	if _is_player(c):
		_notice("Too winded to sprint", 1.5)


func _notice(text: String, seconds: float) -> void:
	notice_label.text = text
	_notice_time = seconds


func _refresh() -> void:
	stamina_bar.value = _frac * 100.0
	var suffix := ""
	if _stamina_state == &"low":
		suffix = "  (low)"
	stamina_label.text = "Stamina %d%%%s" % [int(round(_frac * 100.0)), suffix]
	var mode := String(_mode).capitalize()
	if _exhausted:
		mode += "  (EXHAUSTED)"
	mode_label.text = mode
	stamina_bar.modulate = COL_EXHAUSTED if _exhausted else (COL_LOW if _stamina_state == &"low" else COL_OK)


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		if fmod(_flash_time, 0.3) < 0.15:
			stamina_bar.modulate = Color.WHITE
		else:
			_refresh()
	if _notice_time > 0.0:
		_notice_time = maxf(0.0, _notice_time - delta)
		if _notice_time == 0.0:
			notice_label.text = ""
	# Exhausted flag can clear via the winded timer without a stat event.
	var p := GameManager.player as Character
	if p and p.exhausted != _exhausted:
		_exhausted = p.exhausted
		_refresh()

	debug_label.visible = GameManager.debug_overlay
	if debug_label.visible and p:
		debug_label.text = "pos %.1f, %.1f, %.1f\nspeed %.2f m/s\nfps %d" % [
			p.global_position.x, p.global_position.y, p.global_position.z,
			p.speed(), Engine.get_frames_per_second()]
