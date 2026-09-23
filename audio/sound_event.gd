class_name SoundEvent
extends RefCounted
## One gameplay sound (not audio playback): where, how far, how loud, what
## kind, who made it. Created by SoundManager.emit_sound(); short-lived
## (duration seconds of physics time) and dispatched to nearby listeners
## once, when emitted.

var id: int = 0
var category: StringName = &""
var position: Vector3 = Vector3.ZERO
## Base radius in metres (before walls, hearing sensitivity, masking).
var radius: float = 5.0
## 0..1.
var intensity: float = 0.5
## Seconds the event stays alive (debug rings).
var duration: float = 1.0
## Game minute (TimeManager.now()) at emission.
var created_minute: float = 0.0
## Physics seconds at emission (expiry).
var created_time: float = 0.0
## Extra payload: &"lure" (Vector3: where a zombie moan points), &"hops".
var extras: Dictionary = {}
var _source: WeakRef = null


func _init(p_category: StringName = &"", p_position: Vector3 = Vector3.ZERO, p_radius: float = 5.0,
		p_intensity: float = 0.5, p_source: Object = null) -> void:
	category = p_category
	position = p_position
	radius = p_radius
	intensity = p_intensity
	set_source(p_source)


func set_source(s: Object) -> void:
	_source = weakref(s) if s != null else null


## The emitter, or null when none / already freed.
func source() -> Object:
	if _source == null:
		return null
	var o: Variant = _source.get_ref()
	return o if o != null and is_instance_valid(o) else null


func is_from(o: Object) -> bool:
	return o != null and source() == o


## Seconds left at physics time [now] (<= 0: expired).
func time_left(now: float) -> float:
	return duration - (now - created_time)


## 1 → 0 over the event's life (debug fade).
func life_fraction(now: float) -> float:
	return clampf(time_left(now) / maxf(duration, 0.001), 0.0, 1.0)
