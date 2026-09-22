extends "res://tests/test_case.gd"

const StatsScript = preload("res://characters/stats_component.gd")

var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()


func _stats() -> StatsComponent:
	var s: StatsComponent = StatsScript.new()
	var dummy := Node.new()
	_nodes.append(dummy)
	_nodes.append(s)
	s.character = dummy
	return s


func test_add_get_set_clamped() -> void:
	var s := _stats()
	s.add_stat(&"stamina", 100.0)
	check_eq(s.get_value(&"stamina"), 100.0, "starts full")
	s.modify(&"stamina", -30.0)
	check_eq(s.get_value(&"stamina"), 70.0, "modify")
	s.modify(&"stamina", -500.0)
	check_eq(s.get_value(&"stamina"), 0.0, "clamped low")
	s.set_value(&"stamina", 999.0)
	check_eq(s.get_value(&"stamina"), 100.0, "clamped high")
	check_near(s.get_fraction(&"stamina"), 1.0, 0.0001, "fraction")
	check_eq(s.get_max(&"stamina"), 100.0, "max")


func test_unknown_stat_is_safe() -> void:
	var s := _stats()
	check_eq(s.get_value(&"nope"), 0.0, "unknown value")
	check_eq(s.get_fraction(&"nope"), 0.0, "unknown fraction")
	check_eq(s.get_state(&"nope"), &"normal", "unknown state")
	# modify() on an unknown stat warns but must not crash.
	s.modify(&"nope", 5.0)
	check(true, "no crash")


func test_tiny_drains_accumulate() -> void:
	# Regression: is_equal_approx swallowed sub-epsilon changes.
	var s := _stats()
	s.add_stat(&"hunger", 100.0)
	for i in 1000:
		s.modify(&"hunger", -0.0005)
	check_near(s.get_value(&"hunger"), 99.5, 0.001, "1000 x 0.0005 accumulated")


func test_max_zero_stat_is_safe() -> void:
	var s := _stats()
	s.add_stat(&"weird", 0.0, {}, {&"low": 0.5})
	check_eq(s.get_fraction(&"weird"), 0.0, "fraction 0")
	s.modify(&"weird", 10.0)
	check_eq(s.get_value(&"weird"), 0.0, "clamped to 0 max")


func test_thresholds_emit_once_per_transition() -> void:
	var s := _stats()
	s.add_stat(&"stamina", 100.0, {}, {&"low": 0.25, &"exhausted": 0.02})
	var events: Array = []
	s.threshold.connect(func(id, state): events.append([id, state]))
	s.set_value(&"stamina", 50.0)
	check_eq(events.size(), 0, "no event above thresholds")
	s.set_value(&"stamina", 20.0)
	check_eq(events.size(), 1, "low emitted")
	check_eq(events[0][1], &"low", "state low")
	s.set_value(&"stamina", 15.0)
	check_eq(events.size(), 1, "still low, no repeat")
	s.set_value(&"stamina", 1.0)
	check_eq(events[1][1], &"exhausted", "exhausted (most severe wins)")
	s.set_value(&"stamina", 80.0)
	check_eq(events[2][1], &"normal", "back to normal")


func test_threshold_hysteresis() -> void:
	var s := _stats()
	s.add_stat(&"stamina", 100.0, {}, {
		&"low": 0.25,
		&"exhausted": {"enter": 0.02, "exit": 0.40},
	})
	s.set_value(&"stamina", 1.0)
	check_eq(s.get_state(&"stamina"), &"exhausted", "entered exhausted")
	s.set_value(&"stamina", 30.0)
	check_eq(s.get_state(&"stamina"), &"exhausted", "30% still exhausted (exit is 40%)")
	s.set_value(&"stamina", 39.9)
	check_eq(s.get_state(&"stamina"), &"exhausted", "just below exit still exhausted")
	s.set_value(&"stamina", 40.0)
	check_eq(s.get_state(&"stamina"), &"normal", "at exit -> normal (above low)")
	s.set_value(&"stamina", 20.0)
	check_eq(s.get_state(&"stamina"), &"low", "low re-entered normally")
	s.set_value(&"stamina", 1.5)
	check_eq(s.get_state(&"stamina"), &"exhausted", "escalates low -> exhausted")
	s.set_value(&"stamina", 25.0)
	check_eq(s.get_state(&"stamina"), &"exhausted", "does not drop back to 'low' while held")


func test_tick_uses_context_rates_and_scale() -> void:
	var s := _stats()
	s.add_stat(&"stamina", 100.0, {&"idle": 10.0, &"sprint": -20.0})
	s.set_value(&"stamina", 50.0)
	s.tick(1.0, &"idle")
	check_near(s.get_value(&"stamina"), 60.0, 0.0001, "idle +10/s")
	s.tick(1.0, &"sprint")
	check_near(s.get_value(&"stamina"), 40.0, 0.0001, "sprint -20/s")
	s.tick(1.0, &"sprint", 0.5)
	check_near(s.get_value(&"stamina"), 30.0, 0.0001, "scaled by effort")
	s.tick(1.0, &"unknown_context")
	check_near(s.get_value(&"stamina"), 30.0, 0.0001, "unknown context = 0 rate")


func test_serialisation_roundtrip() -> void:
	var s := _stats()
	s.add_stat(&"stamina", 100.0)
	s.add_stat(&"hunger", 100.0)
	s.set_value(&"stamina", 33.0)
	s.set_value(&"hunger", 77.0)
	var d := s.to_dict()
	var s2 := _stats()
	s2.add_stat(&"stamina", 100.0)
	s2.add_stat(&"hunger", 100.0)
	s2.from_dict(d)
	check_eq(s2.get_value(&"stamina"), 33.0, "stamina restored")
	check_eq(s2.get_value(&"hunger"), 77.0, "hunger restored")
	s2.from_dict({"ghost": 5.0, "stamina": 10.0})
	check_eq(s2.get_value(&"stamina"), 10.0, "known key applied")
	check(not s2.has_stat(&"ghost"), "unknown key ignored")
