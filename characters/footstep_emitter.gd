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

var _accum: float = 0.0
var _character: Character


func _ready() -> void:
	_character = get_parent() as Character


func radius_for(mode: MovementComponent.Mode) -> float:
	match mode:
		MovementComponent.Mode.SNEAK: return radius_sneak
		MovementComponent.Mode.WALK: return radius_walk
		MovementComponent.Mode.SPRINT: return radius_sprint
	return radius_jog


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
	EventBus.sound_emitted.emit(_character.global_position, r, r / radius_sprint, &"footstep", _character)
