class_name RestComponent
extends Node
## Sleeping and resting for a Character (child node "Rest", Round 7).
##
## - sleep(bed): refused "Not tired" below the profile's sleep fatigue level
##   and "Can't sleep: danger nearby" while chased or with a zombie within
##   [danger_radius] m. Asleep: the character is busy (&"sleep"),
##   NeedsComponent.sleeping (fatigue falls, hunger / thirst slow down),
##   TimeManager.begin_sleep() (Engine.time_scale up so zombies keep
##   simulating, plus a game-time skip: 8 h ≈ 8 real s). Wakes up when
##   fatigue reaches 0 ("" reason), on damage ("Woken: under attack!"), a
##   sound whose propagated strength at the ear reaches the needs
##   profile's wake_sound_strength (Round 8: the sleeper is a SoundManager
##   listener, so walls and closed doors muffle) or a zombie within
##   [wake_zombie_radius] (10) m with a clear line of sight ("Woken by
##   noise!"), or after the real-time cap.
##   Refused while bleeding. Wounds get the skipped game time too (heal
##   over the night).
## - rest(furniture): sit / lie awake (&"rest": stamina regen ×3 via the
##   stats profile, fatigue slowly down) until the player moves, gets hurt
##   or is fully rested.
## EventBus: sleep_started / sleep_ended(character, reason), rest_started /
## rest_ended.

const SLEEP_CONTEXT := &"sleep"
const REST_CONTEXT := &"rest"
const REASON_NOT_TIRED := "Not tired"
const REASON_DANGER := "Can't sleep: danger nearby"
const REASON_BLEEDING := "Can't sleep: bleeding"
const REASON_TOO_THIRSTY := "Too thirsty to sleep"
const REASON_TOO_HUNGRY := "Too hungry to sleep"
const WOKEN_NOISE := "Woken by noise!"
const WOKEN_ATTACK := "Woken: under attack!"

## No sleeping with a zombie this close (or while chased).
@export var danger_radius: float = 15.0
## A zombie this close AND in sight (eye to eye on layers 1+7+8) wakes you.
@export var wake_zombie_radius: float = 10.0
## Used when the character has no needs profile.
const DEFAULT_WAKE_STRENGTH := 0.1
const SIGHT_MASK := (1 << 0) | (1 << 6) | (1 << 7)

var character: Character
var sleeping: bool = false
var resting: bool = false
## The bed / sofa in use.
var furniture: Node = null
var last_wake_reason: String = ""
var _check_accum: float = 0.0
var _sight_ray: PhysicsRayQueryParameters3D
## The last sound that reached the sleeper: {category, strength} (tests).
var last_sound: Dictionary = {}


func _ready() -> void:
	character = get_parent() as Character
	if character:
		character.busy_cancelled.connect(_on_busy_cancelled)


func _exit_tree() -> void:
	if sleeping:
		sleeping = false
		TimeManager.end_sleep()
	_disconnect()


func _needs() -> NeedsComponent:
	return character.needs if character else null


# --- Sleep ---------------------------------------------------------------------------

## Why the character cannot sleep right now ("" when it can).
func sleep_block_reason() -> String:
	if character == null or character.is_dead():
		return "Can't sleep now"
	if sleeping:
		return "Already asleep"
	if character.is_busy:
		return "Busy"
	var n := _needs()
	if n == null:
		return "Can't sleep"
	if not n.can_sleep():
		return REASON_NOT_TIRED
	if character.injuries and character.injuries.bleeding_count() > 0:
		return REASON_BLEEDING
	match NeedsMath.sleep_risk(n.to_dict(), n.profile):
		NeedsMath.THIRST:
			return REASON_TOO_THIRSTY
		NeedsMath.HUNGER:
			return REASON_TOO_HUNGRY
	if Danger.threat_reason(get_tree(), character, danger_radius) != "":
		return REASON_DANGER
	return ""


func sleep(bed: Node = null) -> Dictionary:
	var why := sleep_block_reason()
	if why != "":
		return _refuse(why)
	sleeping = true
	furniture = bed
	last_wake_reason = ""
	_check_accum = 0.0
	_needs().sleeping = true
	TimeManager.begin_sleep()
	var tw := character.begin_busy(SLEEP_CONTEXT)
	# The busy tween runs in scaled physics time: cap × scale = real cap.
	tw.tween_interval(TimeManager.config.sleep_max_real_seconds * TimeManager.config.sleep_engine_time_scale)
	tw.tween_callback(wake.bind("Can't sleep any longer"))
	_connect()
	EventBus.sleep_started.emit(character, bed)
	return {"ok": true}


## End the sleep with [reason] ("" = woke up rested).
func wake(reason: String = "") -> void:
	if not sleeping:
		return
	_end_sleep(reason)
	character.cancel_busy(SLEEP_CONTEXT)


func _end_sleep(reason: String) -> void:
	sleeping = false
	last_wake_reason = reason
	furniture = null
	var n := _needs()
	if n:
		n.sleeping = false
	TimeManager.end_sleep()
	_disconnect()
	EventBus.sleep_ended.emit(character, reason)


## The sleep / rest busy action was cut from outside (overridden, death).
func _on_busy_cancelled(context: StringName) -> void:
	if context == SLEEP_CONTEXT and sleeping:
		_end_sleep("")
	elif context == REST_CONTEXT and resting:
		_end_rest("")


# --- Rest ------------------------------------------------------------------------------

func rest_block_reason() -> String:
	if character == null or character.is_dead():
		return "Can't rest now"
	if resting or sleeping:
		return "Already resting"
	if character.is_busy:
		return "Busy"
	return ""


func rest(seat: Node = null) -> Dictionary:
	var why := rest_block_reason()
	if why != "":
		return _refuse(why)
	resting = true
	furniture = seat
	var n := _needs()
	if n:
		n.resting = true
	var tw := character.begin_busy(REST_CONTEXT)
	tw.tween_interval(3600.0)
	tw.tween_callback(stop_rest.bind("Got up"))
	_connect()
	EventBus.rest_started.emit(character, seat)
	return {"ok": true}


func stop_rest(reason: String = "Got up") -> void:
	if not resting:
		return
	_end_rest(reason)
	character.cancel_busy(REST_CONTEXT)


func _end_rest(reason: String) -> void:
	resting = false
	furniture = null
	var n := _needs()
	if n:
		n.resting = false
	_disconnect()
	EventBus.rest_ended.emit(character, reason)


# --- Watching for trouble ---------------------------------------------------------------

func _connect() -> void:
	if not EventBus.time_advanced.is_connected(_on_time_advanced):
		EventBus.time_advanced.connect(_on_time_advanced)
	if sleeping and not SoundManager.is_listening(self):
		SoundManager.register_listener(self)
	if not EventBus.character_damaged.is_connected(_on_damaged):
		EventBus.character_damaged.connect(_on_damaged)
	if not EventBus.health_drained.is_connected(_on_drained):
		EventBus.health_drained.connect(_on_drained)


func _disconnect() -> void:
	if not sleeping:
		SoundManager.unregister_listener(self)
	if sleeping or resting:
		return
	if EventBus.time_advanced.is_connected(_on_time_advanced):
		EventBus.time_advanced.disconnect(_on_time_advanced)
	if EventBus.character_damaged.is_connected(_on_damaged):
		EventBus.character_damaged.disconnect(_on_damaged)
	if EventBus.health_drained.is_connected(_on_drained):
		EventBus.health_drained.disconnect(_on_drained)


## Wounds tick on physics time, which a sleep only speeds up ×engine
## scale; give them the rest of the skipped game time so a night's sleep
## heals like a night (1 game minute = 1 injury second at 1×).
func _on_time_advanced(from_minute: float, to_minute: float) -> void:
	if not sleeping or character == null or character.injuries == null:
		return
	var cfg := TimeManager.config
	var per_scaled_second := cfg.sleep_minutes_per_second / maxf(cfg.sleep_engine_time_scale, 0.01)
	if per_scaled_second <= cfg.minutes_per_second:
		return
	var equivalent := (to_minute - from_minute) / maxf(cfg.minutes_per_second, 0.001)
	character.injuries.tick(equivalent * (1.0 - cfg.minutes_per_second / per_scaled_second))


# --- SoundManager listener (only while asleep) ---------------------------------

func sound_ear_position() -> Vector3:
	if character == null or not is_instance_valid(character):
		return Vector3(1e6, 0.0, 1e6)
	return character.global_position + Vector3.UP * character.eye_height()


func sound_sensitivity() -> float:
	return 1.0 if sleeping and character != null and not character.is_dead() else 0.0


func sound_owner() -> Object:
	return character


func wake_strength() -> float:
	var n := _needs()
	return n.profile.wake_sound_strength if n != null and n.profile != null else DEFAULT_WAKE_STRENGTH


func on_sound(event: SoundEvent, info: Dictionary) -> void:
	if not sleeping:
		return
	var st := float(info.get("strength", 0.0))
	last_sound = {"category": event.category, "strength": st}
	if st >= wake_strength():
		wake(WOKEN_NOISE)


## A living zombie within [wake_zombie_radius] with a clear eye-to-eye line.
func zombie_in_sight() -> bool:
	if character == null or not character.is_inside_tree():
		return false
	var space := character.get_world_3d().direct_space_state
	var eye := sound_ear_position()
	if _sight_ray == null:
		_sight_ray = PhysicsRayQueryParameters3D.new()
		_sight_ray.collision_mask = SIGHT_MASK
	for z in get_tree().get_nodes_in_group(&"zombie"):
		if not z is Node3D or not is_instance_valid(z) or (z.has_method(&"is_dead") and z.is_dead()):
			continue
		var zp := (z as Node3D).global_position
		if Vector2(zp.x - eye.x, zp.z - eye.z).length() > wake_zombie_radius:
			continue
		_sight_ray.from = zp + Vector3.UP * 1.5
		_sight_ray.to = eye
		if space == null or space.intersect_ray(_sight_ray).is_empty():
			return true
	return false


## Starving / dying of thirst / food poisoning hurts: you wake up
## ("Woken: dying of thirst") instead of dying in your sleep.
func _on_drained(c: Node, _amount: float, cause: StringName) -> void:
	if c != character or cause != &"needs":
		return
	var reason := "Woken: feeling awful"
	var n := _needs()
	if n:
		var worst := &""
		var worst_f := 0.0
		for need in [NeedsMath.THIRST, NeedsMath.HUNGER, NeedsMath.SICKNESS]:
			var mx := NeedsMath.thresholds_of(need, n.profile).size()
			var f := float(n.level(need)) / float(maxi(mx, 1))
			if f > worst_f:
				worst_f = f
				worst = need
		if worst != &"":
			reason = "Woken: %s" % n.label(worst).to_lower()
	if sleeping:
		wake(reason)
	elif resting:
		stop_rest(reason)


func _on_damaged(c: Node, _amount: float, _source: Node, _info: Dictionary) -> void:
	if c != character:
		return
	if sleeping:
		wake(WOKEN_ATTACK)
	elif resting:
		stop_rest("Interrupted")


func _physics_process(delta: float) -> void:
	if character == null or not (sleeping or resting):
		return
	if character.is_dead():
		if sleeping:
			wake("")
		stop_rest("")
		return
	var n := _needs()
	if resting:
		if character.has_move_intent():
			stop_rest("Got up")
		return
	if n != null and n.value(NeedsComponent.FATIGUE) <= 0.01:
		wake("")
		return
	_check_accum += delta
	if _check_accum < 0.25:
		return
	_check_accum = 0.0
	if Danger.is_chased(get_tree(), character) or zombie_in_sight():
		wake(WOKEN_NOISE)


func _refuse(reason: String) -> Dictionary:
	EventBus.interaction_refused.emit(character, null, reason)
	return {"ok": false, "reason": reason}
