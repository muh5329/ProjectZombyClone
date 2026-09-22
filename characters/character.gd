class_name Character
extends CharacterBody3D
## Base class for humans (player, survivors). Zombies get their own base.
##
## Owns a MovementComponent and a StatsComponent and applies "intent"
## (direction + desired mode) each physics tick. Who sets the intent is not
## this class's business: the PlayerController does it from input, an AI
## will do it from a behaviour tree.
##
## Exhaustion is owned by StatsComponent's threshold state; this class only
## reacts to it (speed penalty, sprint denial, winded timer).

const STAMINA := StatsComponent.STAMINA
const STATE_EXHAUSTED := &"exhausted"
## Intent directions shorter than this count as "not moving".
const INTENT_DEADZONE := 0.1

@export var profile: CharacterStatsProfile

@onready var movement: MovementComponent = $Movement
@onready var stats: StatsComponent = $Stats
## Visual root that is rotated to face the movement direction.
@onready var visual: Node3D = get_node_or_null("Visual")

var intent_direction: Vector3 = Vector3.ZERO
var intent_mode: MovementComponent.Mode = MovementComponent.Mode.JOG
## The mode actually in effect after stamina/injury rules.
var effective_mode: MovementComponent.Mode = MovementComponent.Mode.JOG
## True while the stamina "exhausted" state is active or the winded timer runs.
var exhausted: bool = false
## True this tick if sprint was requested but denied (for UI feedback).
var sprint_denied: bool = false
## Seconds of winded time remaining (physics time).
var _winded_left: float = 0.0
var _last_emitted_mode: MovementComponent.Mode = MovementComponent.Mode.JOG


func _ready() -> void:
	if profile == null:
		profile = CharacterStatsProfile.new()
	stats.character = self
	stats.threshold.connect(_on_stat_threshold)
	stats.add_stat(STAMINA, profile.stamina_max, profile.stamina_rates(), profile.stamina_thresholds())


func set_intent(direction: Vector3, mode: MovementComponent.Mode) -> void:
	intent_direction = direction
	intent_mode = mode


func has_move_intent() -> bool:
	return intent_direction.length_squared() > INTENT_DEADZONE * INTENT_DEADZONE


func is_moving() -> bool:
	return Vector2(velocity.x, velocity.z).length_squared() > 0.01


func speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func can_sprint() -> bool:
	return not exhausted


func _physics_process(delta: float) -> void:
	if _winded_left > 0.0:
		_winded_left = maxf(0.0, _winded_left - delta)
		if _winded_left == 0.0 and not stats.is_in_state(STAMINA, STATE_EXHAUSTED):
			_set_exhausted(false)
	_resolve_mode()
	movement.mode = effective_mode

	if not is_on_floor():
		velocity.y -= 9.8 * delta
	else:
		velocity.y = 0.0

	velocity = movement.compute_velocity(intent_direction, velocity, delta)
	move_and_slide()

	# Stamina is charged AFTER moving so effort reflects what actually
	# happened: sprinting into a wall (speed 0) costs like standing still.
	_tick_stats(delta)

	if visual:
		visual.rotation.y = movement.step_facing(visual.rotation.y, delta)

	if effective_mode != _last_emitted_mode:
		_last_emitted_mode = effective_mode
		EventBus.movement_mode_changed.emit(self, MovementComponent.mode_name(effective_mode))


func _resolve_mode() -> void:
	effective_mode = intent_mode
	var denied := false
	if effective_mode == MovementComponent.Mode.SPRINT:
		if not has_move_intent():
			effective_mode = MovementComponent.Mode.JOG
		elif not can_sprint():
			effective_mode = MovementComponent.Mode.JOG
			denied = true
	if denied and not sprint_denied:
		EventBus.sprint_denied.emit(self)
	sprint_denied = denied


func _tick_stats(delta: float) -> void:
	var context: StringName = &"idle"
	var effort := 1.0
	if has_move_intent() and is_moving():
		context = MovementComponent.mode_name(effective_mode)
		# Effort = how much of the mode's speed we actually achieved (0..1).
		var target := movement.target_speed(effective_mode)
		effort = clampf(speed() / target, 0.0, 1.0) if target > 0.0 else 0.0
		if effort < 0.05:
			context = &"idle"
			effort = 1.0
	stats.tick(delta, context, effort)


func _on_stat_threshold(stat: StringName, state: StringName) -> void:
	if stat != STAMINA:
		return
	if state == STATE_EXHAUSTED:
		_winded_left = profile.winded_min_seconds
		_set_exhausted(true)
	elif exhausted and _winded_left <= 0.0:
		_set_exhausted(false)


func _set_exhausted(v: bool) -> void:
	if exhausted == v:
		return
	exhausted = v
	if v:
		movement.set_modifier(&"exhaustion", profile.exhausted_speed_multiplier)
	else:
		movement.clear_modifier(&"exhaustion")
