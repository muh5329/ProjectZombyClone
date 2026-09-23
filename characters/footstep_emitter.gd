class_name FootstepEmitter
extends Node
## Footstep sounds (SoundManager) for the parent Character at [rate_hz]
## while it moves. The category follows the effective movement mode —
## footstep_sneak / _walk / _jog / _sprint (2 / 4 / 8 / 14 m in
## data/audio/sound_categories.tres) — and the radius is scaled by
## [radius_multipliers] (encumbrance: heavy loads clank).

@export var rate_hz: float = 1.0

const CATEGORIES := {
	MovementComponent.Mode.SNEAK: &"footstep_sneak",
	MovementComponent.Mode.WALK: &"footstep_walk",
	MovementComponent.Mode.JOG: &"footstep_jog",
	MovementComponent.Mode.SPRINT: &"footstep_sprint",
}

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


static func category_for(mode: MovementComponent.Mode) -> StringName:
	return CATEGORIES.get(mode, &"footstep_jog")


## Footstep radius for [mode], including the multipliers.
func radius_for(mode: MovementComponent.Mode) -> float:
	return SoundManager.category_radius(category_for(mode)) * multiplier()


func _physics_process(delta: float) -> void:
	if _character == null or _character.is_busy or not _character.is_moving():
		_accum = 0.0
		return
	_accum += delta
	var period := 1.0 / maxf(rate_hz, 0.01)
	if _accum < period:
		return
	_accum -= period
	var mode := _character.effective_mode
	SoundManager.emit_sound(category_for(mode), _character.global_position, _character, {"radius": radius_for(mode)})
