extends "res://tests/test_case.gd"
## HealthComponent and Door.take_damage (pure-ish; nodes in the tree for
## EventBus payloads).

const HealthScript = preload("res://characters/health_component.gd")
const DoorScript = preload("res://interaction/door.gd")

var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _health(max_hp := 100.0) -> HealthComponent:
	var owner := Node3D.new()
	var h: HealthComponent = HealthScript.new()
	h.max_health = max_hp
	owner.add_child(h)
	tree.root.add_child(owner)
	_nodes.append(owner)
	return h


func test_damage_events_and_death() -> void:
	var h := _health()
	var got := []
	var bus := []
	h.damaged.connect(func(a, s, i): got.append([a, s, i]))
	h.died.connect(func(s): got.append(["died", s]))
	var cb := func(c, a, _s, _i): bus.append([c, a])
	var cb2 := func(c, _s): bus.append(["died", c])
	EventBus.character_damaged.connect(cb)
	EventBus.character_died.connect(cb2)
	var r := h.take_damage(30.0, null, {"region": &"arm"})
	check(r.ok and is_equal_approx(r.health, 70.0), "70 left")
	check_near(h.fraction(), 0.7, 0.0001, "fraction")
	check(not h.dead, "alive")
	r = h.take_damage(100.0)
	check(r.ok and r.dead and h.dead, "dead")
	check_eq(h.health, 0.0, "clamped at 0")
	check(not h.take_damage(5.0).ok, "no damage when dead")
	EventBus.character_damaged.disconnect(cb)
	EventBus.character_died.disconnect(cb2)
	check_eq(got.size(), 3, "damaged, damaged, died")
	check_eq(got[0][2].region, &"arm", "info passed through")
	check_eq(got[2][0], "died", "died last")
	check_eq(bus.size(), 3, "EventBus mirrored")
	check_eq(bus[0][0], h.character, "payload carries the owner (parent)")


func test_invulnerable_heal_and_revive() -> void:
	var h := _health(50.0)
	h.invulnerable = true
	check(not h.take_damage(10.0).ok, "invulnerable ignores damage")
	h.invulnerable = false
	h.take_damage(20.0)
	h.heal(100.0)
	check_eq(h.health, 50.0, "heal clamps to max")
	h.take_damage(999.0)
	h.revive()
	check(not h.dead and h.health == 50.0, "revived full")
	check(not h.take_damage(0.0).ok, "zero damage no effect")


func test_door_takes_damage_and_breaks() -> void:
	var d: Door = DoorScript.new()
	tree.root.add_child(d)
	_nodes.append(d)
	var states := []
	var sounds := []
	var cb := func(door, st): if door == d: states.append(st)
	var cb2 := func(_p, r, _i, cat, _s): sounds.append([cat, r])
	EventBus.door_state_changed.connect(cb)
	EventBus.sound_emitted.connect(cb2)
	check_eq(d.health, 300.0, "full health (300: ~75 s for one zombie at 8 per 2 s)")
	check(d.is_in_group(&"breakable") and d.blocks_path(), "closed door is a path-blocking breakable")
	var banged := []
	var cb3 := func(door, src): banged.append([door, src])
	EventBus.door_banged.connect(cb3)
	var r := d.take_damage(50.0)
	check(r.ok and not r.broken and is_equal_approx(r.health, 250.0), "damaged")
	check(not d.take_damage(0.0).ok, "zero damage is a no-op")
	check_eq(d.state, &"closed", "still closed")
	for i in 5:
		r = d.take_damage(50.0)
	EventBus.door_banged.disconnect(cb3)
	check_eq(banged.size(), 6, "door_banged per hit")
	check(r.broken, "broken after 300 damage")
	check(not d.blocks_path(), "broken door no longer blocks the path")
	check_eq(d.state, &"broken", "state broken")
	check(d.is_open() and d.is_broken(), "broken doors are passable")
	check_eq(d.collision_layer, 8, "broken door keeps a layer-4 body (targetable, not solid)")
	check(not d.visual.visible, "leaf visual gone")
	check(not d.open_door().ok and not d.close_door().ok, "cannot open/close a broken door")
	var act := Interactable.of(d).get_actions(null)
	check(act.size() == 1 and not act[0].enabled and act[0].reason == "Door is broken", "actions explain")
	check(not d.take_damage(10.0).ok, "no further damage")
	EventBus.door_state_changed.disconnect(cb)
	EventBus.sound_emitted.disconnect(cb2)
	check_eq(states, [&"broken"], "door_state_changed broken once")
	check_gt(sounds.size(), 5.0, "hits made noise")
	check_near(sounds[0][1], 10.0, 0.001, "bang radius 10 m recruits")
	check_eq(sounds[-1][0], &"door", "break sound category")
	check_near(sounds[-1][1], 18.0, 0.001, "break radius 18 m")
