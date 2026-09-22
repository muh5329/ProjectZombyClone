extends "res://tests/test_case.gd"
## Pure StateMachine / AIState transitions (no scene tree).

const SMScript = preload("res://ai/state_machine/state_machine.gd")
const StateScript = preload("res://ai/state_machine/state.gd")


class Counting extends AIState:
	var entered := 0
	var exited := 0
	var next: StringName = &""
	var last_from: StringName = &""
	var last_to: StringName = &""
	func enter(from: StringName) -> void:
		entered += 1
		last_from = from
	func exit(to: StringName) -> void:
		exited += 1
		last_to = to
	func update(_delta: float) -> StringName:
		return next


class Bouncer extends AIState:
	## Immediately asks for another state (transient state).
	var target: StringName
	func _init(p_id: StringName, p_target: StringName) -> void:
		super(p_id)
		target = p_target
	func update(_delta: float) -> StringName:
		return target


func _machine() -> StateMachine:
	var m: StateMachine = SMScript.new()
	m.add_state(Counting.new(&"a"))
	m.add_state(Counting.new(&"b"))
	return m


func test_change_to_runs_exit_enter_and_emits() -> void:
	var m := _machine()
	var log := []
	m.state_changed.connect(func(f, t): log.append([f, t]))
	check(m.change_to(&"a"), "first change ok")
	check_eq(m.current_id(), &"a", "current a")
	check_eq((m.get_state(&"a") as Counting).entered, 1, "a entered")
	check_eq((m.get_state(&"a") as Counting).last_from, &"", "from empty on first enter")
	check(not m.change_to(&"a"), "same state is a no-op")
	check(m.change_to(&"b"), "a -> b")
	check_eq((m.get_state(&"a") as Counting).exited, 1, "a exited")
	check_eq((m.get_state(&"a") as Counting).last_to, &"b", "exit told where")
	check_eq((m.get_state(&"b") as Counting).last_from, &"a", "enter told from")
	check_eq(m.previous_state, &"a", "previous tracked")
	check_eq(log, [[&"", &"a"], [&"a", &"b"]], "signals")
	check(not m.change_to(&"zzz"), "unknown refused")
	check_eq(m.current_id(), &"b", "still b")
	check_eq(m.history, [&"a", &"b"], "history")


func test_update_follows_returned_transition_and_tracks_time() -> void:
	var m := _machine()
	m.change_to(&"a")
	m.update(0.5)
	m.update(0.25)
	check_near(m.current.time_in_state, 0.75, 0.0001, "time accumulates")
	(m.get_state(&"a") as Counting).next = &"b"
	m.update(0.1)
	check_eq(m.current_id(), &"b", "switched by update")
	check_near(m.current.time_in_state, 0.0, 0.0001, "time reset on enter")
	check(m.is_in(&"b"), "is_in")


func test_transient_states_resolve_in_one_update_and_are_bounded() -> void:
	var m: StateMachine = SMScript.new()
	m.add_state(Counting.new(&"idle"))
	m.add_state(Bouncer.new(&"lost", &"search"))
	m.add_state(Counting.new(&"search"))
	m.change_to(&"idle")
	(m.get_state(&"idle") as Counting).next = &"lost"
	m.update(0.016)
	check_eq(m.current_id(), &"search", "idle -> lost -> search in one tick")
	check_eq((m.get_state(&"search") as Counting).last_from, &"lost", "search entered from lost")
	# Ping-pong must not hang.
	var p: StateMachine = SMScript.new()
	p.add_state(Bouncer.new(&"x", &"y"))
	p.add_state(Bouncer.new(&"y", &"x"))
	p.change_to(&"x")
	p.update(0.016)
	check(p.current_id() == &"x" or p.current_id() == &"y", "bounded chained transitions")
	check_lt(float(p.history.size()), 8.0, "history bounded per tick")


func test_owner_and_force_reenter() -> void:
	var owner := RefCounted.new()
	var m: StateMachine = SMScript.new(owner)
	var a := Counting.new(&"a")
	m.add_state(a)
	m.change_to(&"a")
	check_eq(a.owner_node(), owner, "owner reachable from state")
	check(m.change_to(&"a", true), "force re-enter")
	check_eq(a.entered, 2, "entered twice")
	check_eq(a.exited, 1, "exited once")
