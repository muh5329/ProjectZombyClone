extends "res://tests/test_case.gd"
## State machines of Door and HouseWindow through the Interactable API.
## Nodes are added to the tree because opening/closing creates tweens.

const DoorScript = preload("res://interaction/door.gd")
const WindowScript = preload("res://interaction/window.gd")

var _nodes: Array[Node] = []
var _actor: Node3D


func setup() -> void:
	_actor = Node3D.new()
	tree.root.add_child(_actor)
	_nodes.append(_actor)


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _door() -> Door:
	var d: Door = DoorScript.new()
	tree.root.add_child(d)
	_nodes.append(d)
	return d


func _window() -> HouseWindow:
	var w: HouseWindow = WindowScript.new()
	tree.root.add_child(w)
	_nodes.append(w)
	return w


func _ids(actions: Array[Dictionary], only_enabled: bool = false) -> Array:
	var out := []
	for a in actions:
		if not only_enabled or a.enabled:
			out.append(a.id)
	return out


func _find(actions: Array[Dictionary], id: StringName) -> Dictionary:
	for a in actions:
		if a.id == id:
			return a
	return {}


func test_door_actions_and_state() -> void:
	var d := _door()
	var it := Interactable.of(d)
	check(it != null, "door auto-attaches an Interactable component")
	check_eq(_ids(it.get_actions(_actor)), [&"open"], "closed door offers Open")
	check_eq(it.get_actions(_actor)[0].label, "Open door", "label")
	var r := it.perform(&"open", _actor)
	check(r.ok, "open ok")
	check_eq(d.state, &"open", "state open")
	check_eq(_ids(it.get_actions(_actor)), [&"close"], "open door offers Close")
	check(not it.perform(&"open", _actor).ok, "cannot open twice")
	var early := it.perform(&"close", _actor)
	check(not early.ok and early.reason == "Busy", "toggling within the cooldown is refused as Busy")
	check(not it.get_actions(_actor)[0].enabled, "close listed but disabled while on cooldown")
	await physics_frames(int(d.toggle_cooldown * 60) + 2)
	check(it.perform(&"close", _actor).ok, "close ok after cooldown")
	check_eq(d.state, &"closed", "closed again")
	check(not it.perform(&"bogus", _actor).ok, "unknown action refused")


func test_door_swings_away_from_actor_and_emits_event() -> void:
	var d := _door()
	var got := []
	var cb := func(door, state): got.append([door, state])
	EventBus.door_state_changed.connect(cb)
	_actor.global_position = Vector3(0.45, 0, 1.0)  # in front (+Z)
	d.open_door(_actor)
	await frames(2)
	check_gt(d._swing, 0.0, "actor at +Z -> swing positive (leaf goes to -Z)")
	await physics_frames(32)
	d.close_door()
	await physics_frames(32)
	_actor.global_position = Vector3(0.45, 0, -1.0)
	d.open_door(_actor)
	check_lt(d._swing, 0.0, "actor at -Z -> swing negative")
	EventBus.door_state_changed.disconnect(cb)
	check_eq(got.size(), 3, "three state events")
	check_eq(got[0][1], &"open", "first event open")
	check_eq(got[1][1], &"closed", "second closed")


func test_door_rotation_animates() -> void:
	var d := _door()
	d.open_door(_actor)
	await physics_frames(2)
	check_lt(absf(d.rotation.y), PI * 0.5 - 0.05, "not snapped instantly")
	var done := await wait_until(func(): return absf(absf(d.rotation.y) - PI * 0.5) < 0.01, 120)
	check(done, "reached 90° within the swing time")


func test_locked_door_has_disabled_action_with_reason() -> void:
	var d := _door()
	d.locked = true
	var it := Interactable.of(d)
	var a := it.get_actions(_actor)[0]
	check(not a.enabled, "open disabled")
	check_eq(a.reason, "Locked", "reason")
	var refused := []
	var cb := func(_a, _t, reason): refused.append(reason)
	EventBus.interaction_refused.connect(cb)
	var r := it.perform(&"open", _actor)
	EventBus.interaction_refused.disconnect(cb)
	check(not r.ok, "perform refused")
	check_eq(r.reason, "Locked", "refusal carries reason")
	check_eq(refused, ["Locked"], "interaction_refused event with reason")
	check_eq(d.state, &"closed", "still closed")


func test_fixture_shared_contract() -> void:
	var d := _door()
	var w := _window()
	for f in [d, w]:
		check(f is WallFixture, "%s extends WallFixture" % f.name)
		check(f.is_in_group(&"wall") and f.is_in_group(&"occluder"), "groups")
	check_eq(w.collision_layer, 41, "window layers 1+4+6")
	check_eq(d.collision_layer, 104, "door layers 4+6+7 (doors layer, not world: navmesh bakes through)")
	for f in [d, w]:
		check(f.has_meta(&"outward") and f.has_meta(&"wall_height"), "occlusion metadata")
		check(f.get_node_or_null("Visual") != null, "Visual child")
		check(Interactable.of(f) != null, "Interactable attached")
	check(d.is_in_group(&"door") and w.is_in_group(&"window"), "fixture groups")


func test_window_closed_actions() -> void:
	var w := _window()
	var it := Interactable.of(w)
	var acts := it.get_actions(_actor)
	check_eq(_ids(acts), [&"open", &"smash", &"climb"], "closed: open, smash, climb(disabled)")
	check_eq(_ids(acts, true), [&"open", &"smash"], "climb disabled while closed")
	check_eq(_find(acts, &"climb").reason, "Window is closed", "reason")
	var r := it.perform(&"climb", _actor)
	check(not r.ok, "climb refused while closed")
	check(not w.can_climb(), "can_climb false")


func test_window_open_and_close() -> void:
	var w := _window()
	var it := Interactable.of(w)
	var got := []
	var cb := func(win, state): got.append(state)
	EventBus.window_state_changed.connect(cb)
	check(it.perform(&"open", _actor).ok, "open")
	check_eq(w.state, &"open", "open state")
	var acts := it.get_actions(_actor)
	check_eq(_ids(acts), [&"climb", &"close", &"smash"], "open: climb first (E), then close, smash")
	check_eq(acts[0].label, "Climb through", "plain climb label")
	await physics_frames(32)
	check(it.perform(&"close", _actor).ok, "close")
	check_eq(w.state, &"closed", "closed again")
	EventBus.window_state_changed.disconnect(cb)
	check_eq(got, [&"open", &"closed"], "events")


func test_window_smashed_actions() -> void:
	var w := _window()
	var it := Interactable.of(w)
	check(it.perform(&"smash", _actor).ok, "smash")
	check_eq(w.state, &"smashed", "smashed")
	var acts := it.get_actions(_actor)
	check_eq(_ids(acts, true), [&"climb", &"clear_glass"], "climb + remove glass enabled")
	check_eq(acts[0].label, "Climb through (glass)", "glass label")
	check_eq(_find(acts, &"clear_glass").label, "Remove broken glass", "clear glass label")
	check(w.has_glass(), "shards on the floor")
	check(_find(acts, &"open").is_empty() and _find(acts, &"close").is_empty(),
		"open / close not listed once the frame is smashed (permanent)")
	check_eq(_ids(acts), [&"climb", &"clear_glass"], "smashed: climb + remove glass only")
	check_eq(w.open_window().reason, "Frame is smashed", "open still explains when called")
	check(not it.perform(&"smash", _actor).ok, "cannot smash twice")
	check(not it.perform(&"open", _actor).ok, "open refused")


func test_window_climb_moves_actor_to_far_side_and_flags_hazard() -> void:
	var w := _window()
	w.global_position = Vector3(10, 0, 0)
	_actor.global_position = Vector3(10, 0, 0.7)
	w.open_window()
	var done := [0]
	var cb := func(_a, _w, _h): done[0] += 1
	EventBus.window_climbed.connect(cb)
	var r := Interactable.of(w).perform(&"climb", _actor)
	check(r.ok, "climb ok")
	check(not r.hazard, "open window: no hazard")
	var landed := await wait_until(func(): return done[0] >= 1, 120)
	check(landed, "window_climbed event fired")
	check_lt(_actor.global_position.z, -0.5, "actor ended up on the -Z side")
	check_near(_actor.global_position.x, 10.0, 0.01, "x unchanged")
	check_near(_actor.global_position.y, 0.0, 0.01, "back on the floor")
	w.smash()
	r = Interactable.of(w).perform(&"climb", _actor)
	check(r.hazard, "smashed window: hazard flagged")
	check(w.last_climb_hazard, "window remembers hazard")
	var back := await wait_until(func(): return done[0] >= 2, 120)
	EventBus.window_climbed.disconnect(cb)
	check(back, "second climb finished")
	check_gt(_actor.global_position.z, 0.5, "climbed back to +Z side")


func test_window_landing_point_is_mirror_of_side() -> void:
	var w := _window()
	w.global_position = Vector3(0, 0, 0)
	w.rotation.y = PI * 0.5  # normal now along +X
	await frames(1)
	var land := w.landing_point(Vector3(0.6, 0, 0))
	check_lt(land.x, -0.5, "from +X lands at -X")
	land = w.landing_point(Vector3(-0.6, 0, 0))
	check_gt(land.x, 0.5, "from -X lands at +X")
