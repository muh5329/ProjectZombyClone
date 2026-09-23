class_name TimedWork
extends RefCounted
## One timed "busy" action of an actor (nailing a plank, prying one off,
## taking furniture apart, pushing a dresser, eating / drinking /
## filling — ConsumeAction uses it too): the actor owns the busy tween
## (Character.begin_busy(context)). The ONE cancel implementation:
## - a hit on the actor (EventBus.character_damaged) → "Interrupted",
## - move intent while working (walking off) → "Stopped",
## - the player's cancel key / pressing an action again
##   (PlayerInteraction → cancel_for(actor)) → "Stopped",
## - any other busy_cancelled (another busy action, death) → silent.
## Emits timed_action_started / timed_action_finished (HUD bar + label)
## with [action_id] (defaults to the context).
##
## on_done(actor) runs only when the full time elapsed; on_cancel(actor)
## runs when it was cut short (nothing consumed / nothing changed). An
## optional [noise] category (+ radius override) is emitted at the start
## and every [noise_period] seconds while working — hammering is loud for
## its whole duration, not just once.

var actor: Node = null
var context: StringName = &""
var seconds: float = 0.0
var running: bool = false
var completed: bool = false
var _on_done: Callable
var _on_cancel: Callable
var _noise: StringName = &""
var _noise_at: Node3D = null
var _noise_period: float = 0.0
## Id used in the timed_action_* events (defaults to the context).
var action_id: StringName = &""
## Reason shown when the work is cancelled ("" = silent).
var _cancel_reason: String = ""
var _tree: SceneTree = null

## actor instance id → WeakRef(TimedWork) while running.
static var _running: Dictionary = {}


## The TimedWork [actor] is doing now (or null).
static func running_for(actor: Node) -> TimedWork:
	if actor == null:
		return null
	var r: WeakRef = _running.get(actor.get_instance_id())
	var w: Variant = r.get_ref() if r != null else null
	if w is TimedWork and (w as TimedWork).running:
		return w
	return null


## Cancel whatever timed work [actor] is doing. True when something stopped.
static func cancel_for(actor: Node, reason: String = "Stopped") -> bool:
	var w := running_for(actor)
	if w == null:
		return false
	w.cancel(reason)
	return true


## True while [a] is doing a busy action (duck-typed `is_busy`).
static func is_busy(a: Node) -> bool:
	return a != null and "is_busy" in a and bool(a.get("is_busy"))


## Start. Returns {ok, reason?, seconds}. [actor] needs begin_busy();
## actors without it (tests, scripts) complete instantly.
func start(p_actor: Node, p_context: StringName, label: String, p_seconds: float,
		on_done: Callable, on_cancel: Callable = Callable(), noise: StringName = &"",
		noise_at: Node3D = null, noise_period: float = 1.5) -> Dictionary:
	if p_actor == null:
		return {"ok": false, "reason": "Nobody"}
	if is_busy(p_actor):
		return {"ok": false, "reason": "Busy"}
	if p_actor.has_method(&"is_dead") and p_actor.is_dead():
		return {"ok": false, "reason": "Dead"}
	actor = p_actor
	context = p_context
	if action_id == &"":
		action_id = context
	seconds = maxf(p_seconds, 0.0)
	_on_done = on_done
	_on_cancel = on_cancel
	_noise = noise
	_noise_at = noise_at
	_noise_period = noise_period
	if not p_actor.has_method(&"begin_busy"):
		_complete()
		return {"ok": true, "seconds": 0.0}
	running = true
	_running[p_actor.get_instance_id()] = weakref(self)
	if p_actor.has_signal(&"busy_cancelled"):
		p_actor.connect(&"busy_cancelled", _on_busy_cancelled)
	EventBus.character_damaged.connect(_on_character_damaged)
	if p_actor.is_inside_tree() and p_actor.has_method(&"has_move_intent"):
		_tree = p_actor.get_tree()
		_tree.physics_frame.connect(_on_physics_frame)
	var tw: Tween = p_actor.call(&"begin_busy", context)
	if _noise != &"" and _noise_period > 0.0:
		var t := 0.0
		_make_noise()
		while t + _noise_period < seconds - 0.05:
			tw.tween_interval(_noise_period)
			tw.tween_callback(_make_noise)
			t += _noise_period
		tw.tween_interval(maxf(seconds - t, 0.0))
	else:
		tw.tween_interval(seconds)
	tw.tween_callback(_complete)
	EventBus.timed_action_started.emit(p_actor, action_id, label, seconds)
	return {"ok": true, "busy": true, "seconds": seconds}


## Stop early; [reason] is shown to the player ("" = silent).
func cancel(reason: String = "Interrupted") -> void:
	if not running:
		return
	_cancel_reason = reason
	if actor != null and is_instance_valid(actor) and actor.has_method(&"cancel_busy") \
			and bool(actor.call(&"cancel_busy", context)):
		return  # busy_cancelled → _on_busy_cancelled
	_on_busy_cancelled(context)


func _make_noise() -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var at: Vector3
	if _noise_at != null and is_instance_valid(_noise_at):
		at = _noise_at.global_position
	elif actor is Node3D:
		at = (actor as Node3D).global_position
	else:
		return
	SoundManager.emit_sound(_noise, at, actor)


func _complete() -> void:
	var a := actor
	_stop()
	completed = true
	if _on_done.is_valid():
		_on_done.call(a)
	if a != null and is_instance_valid(a):
		EventBus.timed_action_finished.emit(a, action_id, true)


func _on_busy_cancelled(ctx: StringName) -> void:
	if ctx != context or not running:
		return
	var a := actor
	_stop()
	if _on_cancel.is_valid():
		_on_cancel.call(a)
	var reason := _cancel_reason
	_cancel_reason = ""
	if a != null and is_instance_valid(a):
		EventBus.timed_action_finished.emit(a, action_id, false)
		if reason != "":
			EventBus.interaction_refused.emit(a, null, reason)


func _on_character_damaged(character: Node, _amount: float, _source: Node, _info: Dictionary) -> void:
	if running and character == actor:
		cancel("Interrupted")


## Walking off stops the work (intent is still set while busy).
func _on_physics_frame() -> void:
	if running and actor != null and is_instance_valid(actor) and bool(actor.call(&"has_move_intent")):
		cancel("Stopped")


func _stop() -> void:
	running = false
	if _tree != null and _tree.physics_frame.is_connected(_on_physics_frame):
		_tree.physics_frame.disconnect(_on_physics_frame)
	_tree = null
	if actor != null and is_instance_valid(actor):
		var r: WeakRef = _running.get(actor.get_instance_id())
		if r != null and r.get_ref() == self:
			_running.erase(actor.get_instance_id())
	if EventBus.character_damaged.is_connected(_on_character_damaged):
		EventBus.character_damaged.disconnect(_on_character_damaged)
	if actor != null and is_instance_valid(actor) and actor.has_signal(&"busy_cancelled") \
			and actor.is_connected(&"busy_cancelled", _on_busy_cancelled):
		actor.disconnect(&"busy_cancelled", _on_busy_cancelled)
