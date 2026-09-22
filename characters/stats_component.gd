class_name StatsComponent
extends Node
## Generic numeric stat container for any character (player, zombie, NPC).
##
## Stats are registered by name with a max value, per-context rates and named
## threshold states. Systems (movement, combat, survival) read and modify
## them through this component so they never touch each other's internals.
##
## Threshold states support hysteresis: a state is entered at or below its
## `enter` fraction and only left once the stat climbs to `exit`. This is the
## single source of truth for "exhausted", "starving", etc. — other systems
## must react to the [signal threshold] signal, not re-derive it.
##
## Round 1 registers only STAMINA. Later rounds add hunger, thirst, fatigue…
## via add_stat() — no changes to this class required.

const STAMINA := &"stamina"

## Emitted locally (in addition to EventBus) so tightly-bound UI can subscribe.
signal changed(stat: StringName, value: float, max_value: float)
signal threshold(stat: StringName, state: StringName)

class Threshold:
	var enter: float
	var exit: float
	func _init(p_enter: float, p_exit: float) -> void:
		enter = p_enter
		exit = maxf(p_exit, p_enter)

class Stat:
	var value: float
	var max_value: float
	## Per-second change by context name (e.g. {&"idle": 3.5, &"sprint": -18}).
	## Contexts missing from the dictionary apply 0. See tick().
	var rates: Dictionary = {}
	## state name -> Threshold, checked lowest `enter` first.
	var thresholds: Dictionary = {}
	var current_state: StringName = &"normal"

	func _init(p_max: float, p_value: float = -1.0) -> void:
		max_value = maxf(p_max, 0.0)
		value = max_value if p_value < 0.0 else clampf(p_value, 0.0, max_value)

	func fraction() -> float:
		return 0.0 if max_value <= 0.0 else clampf(value / max_value, 0.0, 1.0)


var _stats: Dictionary = {}
## Owner character (the node whose stats these are), used for EventBus payloads.
var character: Node = null


func _ready() -> void:
	if character == null:
		character = get_parent()


## [thresholds] values may be a float (enter == exit) or a Dictionary
## {"enter": f, "exit": f}.
func add_stat(id: StringName, max_value: float, rates: Dictionary = {}, thresholds: Dictionary = {}) -> Stat:
	var s := Stat.new(max_value)
	s.rates = rates.duplicate()
	for state: StringName in thresholds:
		var spec: Variant = thresholds[state]
		if spec is Dictionary:
			s.thresholds[state] = Threshold.new(float(spec.get("enter", 0.0)), float(spec.get("exit", spec.get("enter", 0.0))))
		else:
			s.thresholds[state] = Threshold.new(float(spec), float(spec))
	_stats[id] = s
	_evaluate_thresholds(id, s)
	return s


func has_stat(id: StringName) -> bool:
	return _stats.has(id)


func get_stat(id: StringName) -> Stat:
	return _stats.get(id)


func get_value(id: StringName) -> float:
	var s: Stat = _stats.get(id)
	return s.value if s else 0.0


func get_max(id: StringName) -> float:
	var s: Stat = _stats.get(id)
	return s.max_value if s else 0.0


func get_fraction(id: StringName) -> float:
	var s: Stat = _stats.get(id)
	return s.fraction() if s else 0.0


func get_state(id: StringName) -> StringName:
	var s: Stat = _stats.get(id)
	return s.current_state if s else &"normal"


func is_in_state(id: StringName, state: StringName) -> bool:
	return get_state(id) == state


func set_value(id: StringName, v: float) -> void:
	var s: Stat = _stats.get(id)
	if s == null:
		push_warning("StatsComponent: unknown stat %s" % id)
		return
	var new_v := clampf(v, 0.0, s.max_value)
	if new_v == s.value:  # exact: tiny per-tick drains must accumulate
		return
	s.value = new_v
	changed.emit(id, s.value, s.max_value)
	EventBus.stat_changed.emit(character, id, s.value, s.max_value)
	_evaluate_thresholds(id, s)


## Change a stat's maximum (injuries lower max stamina). The value is
## clamped into the new range; `changed` fires when anything moved.
func set_max(id: StringName, max_value: float) -> void:
	var s: Stat = _stats.get(id)
	if s == null:
		return
	var m := maxf(max_value, 0.0)
	if m == s.max_value:
		return
	s.max_value = m
	s.value = minf(s.value, m)
	changed.emit(id, s.value, s.max_value)
	EventBus.stat_changed.emit(character, id, s.value, s.max_value)
	_evaluate_thresholds(id, s)


func modify(id: StringName, delta: float) -> void:
	set_value(id, get_value(id) + delta)


## Apply the per-second rate for [context] to every stat. Call once per
## physics tick with the character's current activity context
## (e.g. &"idle", &"walk", &"jog", &"sprint"). [scale] lets callers apply
## effort (0..1) so partial input does not pay full price.
func tick(delta: float, context: StringName, scale: float = 1.0) -> void:
	for id: StringName in _stats:
		var s: Stat = _stats[id]
		var rate: float = s.rates.get(context, 0.0)
		if rate != 0.0:
			modify(id, rate * delta * scale)


func _evaluate_thresholds(id: StringName, s: Stat) -> void:
	if s.thresholds.is_empty():
		return
	var frac := s.fraction()
	var new_state: StringName = &"normal"
	# Hysteresis: stay in the current state until we climb past its exit.
	if s.current_state != &"normal":
		var cur: Threshold = s.thresholds[s.current_state]
		if frac < cur.exit:
			new_state = s.current_state
	# Lowest matching `enter` wins (more severe state first), and a more
	# severe state may still be entered while holding a milder one.
	var best := 2.0
	for state: StringName in s.thresholds:
		var t: Threshold = s.thresholds[state]
		if frac <= t.enter and t.enter < best:
			best = t.enter
			if new_state == &"normal" or _severity(s, state) > _severity(s, new_state):
				new_state = state
	if new_state != s.current_state:
		s.current_state = new_state
		threshold.emit(id, new_state)
		EventBus.stat_threshold.emit(character, id, new_state)


## Lower enter fraction = more severe.
func _severity(s: Stat, state: StringName) -> float:
	if state == &"normal":
		return -1.0
	return 1.0 - (s.thresholds[state] as Threshold).enter


## Serialisable snapshot (used by the save system in a later round).
func to_dict() -> Dictionary:
	var d := {}
	for id: StringName in _stats:
		d[String(id)] = _stats[id].value
	return d


func from_dict(d: Dictionary) -> void:
	for k: String in d:
		if _stats.has(StringName(k)):
			set_value(StringName(k), float(d[k]))
