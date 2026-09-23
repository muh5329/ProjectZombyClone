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

## A busy action ended WITHOUT finishing: overridden by a new
## begin_busy(), cancelled through cancel_busy(), or cut by death.
## [context] is the cancelled action's busy context (&"eat", &"bandage",
## &"search", &"sleep", &"rest"…); its owner restores its state (return
## the item, refund the dressing…). Round 7.
signal busy_cancelled(context: StringName)

const STAMINA := StatsComponent.STAMINA
const STATE_EXHAUSTED := &"exhausted"
## Intent directions shorter than this count as "not moving".
const INTENT_DEADZONE := BodyHelpers.INTENT_DEADZONE

@export var profile: CharacterStatsProfile

@onready var movement: MovementComponent = $Movement
@onready var stats: StatsComponent = $Stats
## Optional HealthComponent child named "Health" (player, survivors).
@onready var health: HealthComponent = get_node_or_null("Health")
## Optional InjuryComponent child named "Injuries" (Round 4).
@onready var injuries: InjuryComponent = get_node_or_null("Injuries")
## Optional NeedsComponent child named "Needs" (Round 7: hunger, thirst,
## fatigue, sickness).
@onready var needs: NeedsComponent = get_node_or_null("Needs")
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
## True while an action owns the body (climbing, vaulting…). Intent is
## ignored and the body is not moved by physics; whoever set it moves the
## character (e.g. a Tween) and must clear it.
var is_busy: bool = false
## Stats context charged while busy (e.g. &"climb"). Set by begin_busy().
var busy_context: StringName = &"idle"
## Tween that currently moves this body while busy (owned by this node so
## it survives the thing that started it). May be null.
var busy_tween: Tween = null
## When non-zero the body faces this (XZ) direction instead of its travel
## direction (aiming, swinging). Set by combat; ZERO = travel facing.
var facing_override: Vector3 = Vector3.ZERO
## Reasons sprinting is impossible regardless of stamina, keyed by source
## ({&"encumbrance": "Too heavy"}). Systems set / clear their own key.
var sprint_locks: Dictionary = {}
## Max stamina = (profile max − Σ penalties) × Π multipliers, keyed by
## source (&"injury" penalty from wounds, &"needs" multiplier from hunger /
## thirst). Systems set their own key via set_stamina_max_*().
var _stamina_max_penalties: Dictionary = {}
var _stamina_max_multipliers: Dictionary = {}
## Melee swing time multipliers keyed by source (&"needs": fatigue).
var swing_time_multipliers: Dictionary = {}
## Seconds of winded time remaining (physics time).
var _winded_left: float = 0.0
var _last_emitted_mode: MovementComponent.Mode = MovementComponent.Mode.JOG


func _ready() -> void:
	if profile == null:
		profile = CharacterStatsProfile.new()
	stats.character = self
	stats.threshold.connect(_on_stat_threshold)
	stats.add_stat(STAMINA, profile.stamina_max, profile.stamina_rates(), profile.stamina_thresholds())
	if health:
		health.character = self
		health.set_max(profile.health_max)
		health.died.connect(_on_died)
	if injuries:
		injuries.setup(self)
	if needs:
		needs.setup(self)


func set_intent(direction: Vector3, mode: MovementComponent.Mode) -> void:
	intent_direction = direction
	intent_mode = mode


func has_move_intent() -> bool:
	return BodyHelpers.has_move_intent(intent_direction)


func is_moving() -> bool:
	return BodyHelpers.is_moving(velocity)


func speed() -> float:
	return BodyHelpers.flat_speed(velocity)


func can_sprint() -> bool:
	return not exhausted and sprint_locks.is_empty()


## Block (reason != "") or allow sprinting for [source].
func set_sprint_lock(source: StringName, reason: String) -> void:
	if reason == "":
		sprint_locks.erase(source)
	else:
		sprint_locks[source] = reason


## Player-facing reason a sprint is refused right now ("" when it is not).
func sprint_denied_reason() -> String:
	if not sprint_locks.is_empty():
		return String(sprint_locks.values()[0])
	if exhausted:
		return "Too winded to sprint"
	return ""


## Lower max stamina by [amount] points for [source] (0 clears).
func set_stamina_max_penalty(source: StringName, amount: float) -> void:
	if amount <= 0.0:
		_stamina_max_penalties.erase(source)
	else:
		_stamina_max_penalties[source] = amount
	_refresh_stamina_max()


## Scale max stamina by [mult] for [source] (1 clears).
func set_stamina_max_multiplier(source: StringName, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		_stamina_max_multipliers.erase(source)
	else:
		_stamina_max_multipliers[source] = maxf(mult, 0.0)
	_refresh_stamina_max()


## Pure: (base − Σ penalties) × Π multipliers, never below 0.
static func combined_max(base: float, penalties: Dictionary, multipliers: Dictionary) -> float:
	var m := base
	for p: float in penalties.values():
		m -= p
	for k: float in multipliers.values():
		m *= k
	return maxf(m, 0.0)


func _refresh_stamina_max() -> void:
	var base := profile.stamina_max if profile else 100.0
	stats.set_max(STAMINA, combined_max(base, _stamina_max_penalties, _stamina_max_multipliers))


## Set (1 = clear) a melee swing time multiplier for [source].
func set_swing_time_multiplier(source: StringName, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		swing_time_multipliers.erase(source)
	else:
		swing_time_multipliers[source] = mult


## Product of the swing time multipliers (MeleeCombat applies it).
func swing_time_multiplier() -> float:
	var m := 1.0
	for v: float in swing_time_multipliers.values():
		m *= v
	return m


func is_dead() -> bool:
	return health != null and health.dead


## Damage entry point used by zombies / hazards. Duck-typed: anything with
## take_damage(amount, source, info) can be attacked. Returns the
## HealthComponent result, or {ok: false} when this character has no health.
func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> Dictionary:
	if health == null:
		return {"ok": false, "reason": "No health"}
	return health.take_damage(amount, source, info)


## Death: the body stays as a busy (input-ignoring) character. Round 4
## replaces this with a proper death sequence.
func _on_died(_source: Node) -> void:
	var cut := busy_context if is_busy and busy_tween != null and busy_tween.is_valid() else &""
	if busy_tween and busy_tween.is_valid():
		busy_tween.kill()
	busy_tween = null
	is_busy = true
	busy_context = &"dead"
	if cut != &"":
		busy_cancelled.emit(cut)
	intent_direction = Vector3.ZERO
	velocity = Vector3.ZERO


## Height of the eyes / interaction focus above the feet (from the profile).
func eye_height() -> float:
	return profile.eye_height if profile else 0.9


## Take control of the body away from locomotion. Returns a fresh Tween
## owned by this node that the caller fills with the movement; end_busy()
## is connected to its `finished` so the lock always clears, even if the
## caller (a window, a car…) is freed mid-way.
func begin_busy(context: StringName = &"idle") -> Tween:
	if busy_tween and busy_tween.is_valid():
		var old := busy_context
		busy_tween.kill()
		busy_tween = null
		busy_cancelled.emit(old)
	is_busy = true
	busy_context = context
	velocity = Vector3.ZERO
	busy_tween = create_tween()
	busy_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	busy_tween.finished.connect(end_busy)
	return busy_tween


func end_busy() -> void:
	is_busy = false
	busy_context = &"idle"
	busy_tween = null


## Stop the running busy action (only when it is [context], or any when
## &""): kill its tween, free the body (the dead stay busy) and emit
## busy_cancelled. Returns true when something was cancelled. The one
## place that ends a busy action early (eat, bandage, search, sleep, rest).
func cancel_busy(context: StringName = &"") -> bool:
	if not is_busy or busy_context == &"dead":
		return false
	if context != &"" and busy_context != context:
		return false
	var ctx := busy_context
	if busy_tween and busy_tween.is_valid():
		busy_tween.kill()
	end_busy()
	busy_cancelled.emit(ctx)
	return true


## Legacy toggle (tests / simple callers).
func set_busy(v: bool) -> void:
	if v:
		is_busy = true
		velocity = Vector3.ZERO
	else:
		end_busy()


func _physics_process(delta: float) -> void:
	if is_busy:
		# Somebody else is moving us (climb tween). Charge the busy context.
		velocity = Vector3.ZERO
		stats.tick(delta, busy_context, 1.0)
		return
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
	if facing_override.x != 0.0 or facing_override.z != 0.0:
		movement.facing = BodyHelpers.yaw_for(facing_override)
	move_and_slide()

	# Stamina is charged AFTER moving so effort reflects what actually
	# happened: sprinting into a wall (speed 0) costs like standing still.
	_tick_stats(delta)

	if visual:
		visual.rotation.y = movement.step_facing(visual.rotation.y, delta)

	if effective_mode != _last_emitted_mode:
		_last_emitted_mode = effective_mode
		EventBus.movement_mode_changed.emit(self, MovementComponent.mode_name(effective_mode))


## Direction the body faces (logical, XZ unit vector).
func facing_vector() -> Vector3:
	return BodyHelpers.facing_vector(movement.facing)


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
