class_name FootstepEmitter
extends Node
## Emits EventBus.sound_emitted footsteps for the parent Character at
## [rate_hz] while it moves. Radius depends on the effective movement mode
## (sneak 2 m, walk 4 m, jog 8 m, sprint 14 m). Round 8 turns these into
## real sound propagation; zombies already hear them (ZombieSenses).

@export var rate_hz: float = 1.0
@export var radius_sneak: float = 2.0
@export var radius_walk: float = 4.0
@export var radius_jog: float = 8.0
@export var radius_sprint: float = 14.0

## Radius multipliers keyed by source (&"encumbrance": heavy loads clank).
var radius_multipliers: Dictionary = {}
var _accum: float = 0.0
var _character: Character


func _ready() -> void:
	_character = get_parent() as Character


func set_multiplier(source: StringName, mult: float) -> void:
	if is_equal_approx(mult, 1.0):
		radius_multipliers.erase(source)
	else:
		radius_multipliers[source] = mult


func multiplier() -> float:
	var m := 1.0
	for v: float in radius_multipliers.values():
		m *= v
	return m


## Footstep radius for [mode], including the multipliers.
func radius_for(mode: MovementComponent.Mode) -> float:
	var r := radius_jog
	match mode:
		MovementComponent.Mode.SNEAK: r = radius_sneak
		MovementComponent.Mode.WALK: r = radius_walk
		MovementComponent.Mode.SPRINT: r = radius_sprint
	return r * multiplier()


func _physics_process(delta: float) -> void:
	if _character == null or _character.is_busy or not _character.is_moving():
		_accum = 0.0
		return
	_accum += delta
	var period := 1.0 / maxf(rate_hz, 0.01)
	if _accum < period:
		return
	_accum -= period
	var r := radius_for(_character.effective_mode)
	EventBus.sound_emitted.emit(_character.global_position, r, minf(r / radius_sprint, 1.0), &"footstep", _character)
