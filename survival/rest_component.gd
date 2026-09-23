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
##   noise within [wake_noise_radius] m or a zombie within
##   [wake_zombie_radius] (10) m ("Woken by noise!"), or after the real-time cap.
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
## A sound this close (from anything but the sleeper) wakes you.
@export var wake_noise_radius: float = 8.0
## A zombie this close wakes you (10 m: one shambling at the front door
## of a small house wakes a sleeper in any room — an investigating zombie
## stops ~1 m short of the point it heard).
@export var wake_zombie_radius: float = 10.0

var character: Character
var sleeping: bool = false
var resting: bool = false
## The bed / sofa in use.
var furniture: Node = null
var last_wake_reason: String = ""
var _check_accum: float = 0.0


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
	if not EventBus.sound_emitted.is_connected(_on_sound):
		EventBus.sound_emitted.connect(_on_sound)
	if not EventBus.character_damaged.is_connected(_on_damaged):
		EventBus.character_damaged.connect(_on_damaged)
	if not EventBus.health_drained.is_connected(_on_drained):
		EventBus.health_drained.connect(_on_drained)


func _disconnect() -> void:
	if sleeping or resting:
		return
	if EventBus.time_advanced.is_connected(_on_time_advanced):
		EventBus.time_advanced.disconnect(_on_time_advanced)
	if EventBus.sound_emitted.is_connected(_on_sound):
		EventBus.sound_emitted.disconnect(_on_sound)
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


func _on_sound(position: Vector3, radius: float, _intensity: float, _category: StringName, source: Variant) -> void:
	if not sleeping or character == null:
		return
	if source is Object and is_instance_valid(source) and source == character:
		return
	var d := position - character.global_position
	d.y = 0.0
	# Anything audible that close wakes you (a sound whose own radius does
	# not even reach the sleeper does not).
	if d.length() <= minf(wake_noise_radius, maxf(radius, 0.0)):
		wake(WOKEN_NOISE)


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
	if Danger.is_chased(get_tree(), character) \
			or Danger.nearest_zombie_distance(get_tree(), character.global_position) <= wake_zombie_radius:
		wake(WOKEN_NOISE)


func _refuse(reason: String) -> Dictionary:
	EventBus.interaction_refused.emit(character, null, reason)
	return {"ok": false, "reason": reason}
