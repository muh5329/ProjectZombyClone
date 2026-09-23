extends "res://tests/test_case.gd"
## Round 8 sound model: attenuation maths, category data, spatial hash,
## priority rules, SoundEvent, SoundManager dispatch with fake listeners.


class FakeListener extends RefCounted:
	var ear := Vector3.ZERO
	var sensitivity := 1.0
	var owner_obj: Object = null
	var heard: Array = []

	func sound_ear_position() -> Vector3:
		return ear

	func sound_sensitivity() -> float:
		return sensitivity

	func sound_owner() -> Object:
		return owner_obj

	func on_sound(event: SoundEvent, info: Dictionary) -> void:
		heard.append([event, info])


class FakeNodeListener extends Node:
	var heard: int = 0

	func sound_ear_position() -> Vector3:
		return Vector3(1, 1.5, 0)

	func sound_sensitivity() -> float:
		return 1.0

	func sound_owner() -> Object:
		return self

	func on_sound(_event: SoundEvent, _info: Dictionary) -> void:
		heard += 1


var _listeners: Array = []


func teardown() -> void:
	for l in _listeners:
		if l is Object and is_instance_valid(l):
			SoundManager.unregister_listener(l)
	_listeners.clear()
	SoundManager.ambient_masking = 1.0


func _listen(at: Vector3, sens: float = 1.0) -> FakeListener:
	var l := FakeListener.new()
	l.ear = at
	l.sensitivity = sens
	SoundManager.register_listener(l)
	_listeners.append(l)
	return l


func test_attenuation_math() -> void:
	check_near(SoundMath.attenuation([]), 1.0, 0.0001, "nothing in the way")
	check_near(SoundMath.attenuation([SoundMath.WALL]), 0.5, 0.0001, "one wall ×0.5")
	check_near(SoundMath.attenuation([SoundMath.WALL, SoundMath.WALL]), 0.25, 0.0001, "two walls ×0.25")
	check_near(SoundMath.attenuation([SoundMath.DOOR_CLOSED]), 0.6, 0.0001, "closed door ×0.6")
	check_near(SoundMath.attenuation([SoundMath.WINDOW_CLOSED]), 0.7, 0.0001, "closed window ×0.7")
	check_near(SoundMath.attenuation([SoundMath.OPEN]), 1.0, 0.0001, "open door / window ×1")
	check_near(SoundMath.attenuation([SoundMath.WALL, SoundMath.DOOR_CLOSED]), 0.3, 0.0001, "wall + closed door")
	check_near(SoundMath.attenuation([SoundMath.WALL, SoundMath.WALL, SoundMath.WALL]), 0.15, 0.0001, "three walls clamp at 0.15")
	check_near(SoundMath.attenuation([SoundMath.WALL, SoundMath.WALL, SoundMath.WALL, SoundMath.WALL]), SoundMath.MIN_ATTENUATION, 0.0001, "never below the minimum")
	check_near(SoundMath.obstacle_factor(&"nonsense"), 0.5, 0.0001, "unknown kinds count as wall")
	check_near(SoundMath.effective_radius(20.0, 0.5, 1.0, 1.0), 10.0, 0.0001, "effective radius")
	check_near(SoundMath.effective_radius(20.0, 1.0, 0.5, 0.8), 8.0, 0.0001, "× sensitivity × masking")
	check_near(SoundMath.slack(10.0, 4.0), 6.0, 0.0001, "slack")
	check_near(SoundMath.perceived(1.0, 5.0, 20.0), 0.25, 0.0001, "perceived = intensity × slack / radius")
	check_near(SoundMath.perceived(0.5, -1.0, 20.0), 0.0, 0.0001, "inaudible = 0")
	check_near(SoundMath.perceived(1.0, 30.0, 20.0), 1.0, 0.0001, "clamped to 1")


func test_via_opening_math() -> void:
	# 20 m sound, 3 m to an open door (clear), ear 10 m beyond it.
	check_near(SoundMath.via_opening_slack(20.0, 1.0, 3.0, 10.0), 7.0, 0.0001, "slack through the door")
	check_near(SoundMath.via_opening_slack(20.0, 0.5, 3.0, 10.0), -3.0, 0.0001, "an inner wall before the door")
	var c := Vector3(0, 0, 0)
	check(SoundMath.on_outward_side(c, Vector3(0, 0, 1), Vector3(2, 1, 5)), "in front of the opening")
	check(not SoundMath.on_outward_side(c, Vector3(0, 0, 1), Vector3(2, 1, -5)), "behind it")


func test_priority_rules() -> void:
	check(SoundMath.should_retarget(0.3, 0.0, 0.5, 0.05), "a louder sound wins")
	check(SoundMath.should_retarget(0.3, 0.0, 0.3, 0.05), "an equally loud one wins (newer / nearer)")
	check(not SoundMath.should_retarget(0.6, 0.0, 0.2, 0.05), "a faint one is ignored while following a loud one")
	check(not SoundMath.should_retarget(0.6, 4.0, 0.2, 0.05), "…still after 4 s (0.6 − 0.2 = 0.4)")
	check(SoundMath.should_retarget(0.6, 9.0, 0.2, 0.05), "…but the old sound fades (0.6 − 0.45 < 0.2)")
	check(SoundMath.should_retarget(0.0, 0.0, 0.01, 0.05), "anything beats nothing")


func test_category_data_loads() -> void:
	var t := load("res://data/audio/sound_categories.tres") as SoundCategoryTable
	check(t != null, "table loads")
	var want := {
		&"footstep_sneak": 2.0, &"footstep_walk": 4.0, &"footstep_jog": 8.0, &"footstep_sprint": 14.0,
		&"door_open": 6.0, &"door_close": 8.0, &"door_bang": 12.0, &"window_open": 5.0,
		&"window_smash": 20.0, &"melee_swing": 4.0, &"melee_hit": 7.0, &"shove": 5.0,
		&"rummage": 3.0, &"eat": 1.5, &"bottle_fill": 4.0, &"shout": 20.0, &"zombie_moan": 6.0,
		&"alarm": 60.0, &"gunshot": 60.0, &"generator": 25.0, &"vehicle": 30.0, &"glass_clear": 3.0,
	}
	for id in want:
		var c := t.get_category(id)
		check(c != null, "category %s" % id)
		if c:
			check_near(c.radius, want[id], 0.0001, "%s radius" % id)
			check(c.intensity >= 0.0 and c.intensity <= 1.0 and c.duration > 0.0, "%s intensity / duration" % id)
	check(t.get_category(&"nope") == null, "unknown id")
	check_near(t.player_loud_radius, 10.0, 0.0001, "one LOUD threshold in data")
	check_near(NoiseRings.loud_radius(), t.player_loud_radius, 0.0001, "rings use it")
	check_near(SoundManager.category_radius(&"window_smash"), 20.0, 0.0001, "manager lookup")
	check(t.get_category(&"window_smash").radius >= t.get_category(&"footstep_sprint").radius, "smash is the loudest player noise")
	check_eq(FootstepEmitter.category_for(MovementComponent.Mode.SNEAK), &"footstep_sneak", "sneak step category")
	check_eq(FootstepEmitter.category_for(MovementComponent.Mode.SPRINT), &"footstep_sprint", "sprint step category")


func test_spatial_hash_insert_remove_query() -> void:
	var h := SpatialHash.new(8.0)
	h.insert(1, Vector3(1, 0, 1))
	h.insert(2, Vector3(20, 0, 0))
	h.insert(3, Vector3(-30, 0, -30))
	check_eq(h.size(), 3, "three entries")
	check_eq(h.cell_count(), 3, "three cells")
	var near := h.query_radius(Vector3.ZERO, 5.0)
	check(near.has(1) and not near.has(2) and not near.has(3), "query finds the near one only (%s)" % str(near))
	var exact := h.query_exact(Vector3(15, 0, 0), 6.0)
	check_eq(exact, [2] as Array[int], "exact query")
	check(not h.update(1, Vector3(2, 0, 2)), "moving inside a cell: no cell change")
	check(h.update(1, Vector3(19, 0, 1)), "moving across cells")
	check_eq(h.cell_count(), 2, "old cell dropped when empty")
	var q := h.query_exact(Vector3(20, 0, 0), 3.0)
	check(q.has(1) and q.has(2), "both near 20,0 now")
	check(h.remove(2), "removed")
	check(not h.remove(2), "second remove is a no-op")
	check_eq(h.size(), 2, "two left")
	check(not h.query_radius(Vector3(20, 0, 0), 3.0).has(2), "removed id never returned")
	check_eq(h.query_radius(Vector3.ZERO, 1000.0).size(), 2, "huge radius returns all")
	h.clear()
	check_eq(h.size(), 0, "cleared")


func test_sound_event_holds_source_weakly() -> void:
	var n := Node.new()
	var ev := SoundEvent.new(&"shout", Vector3.ZERO, 20.0, 0.9, n)
	check(ev.source() == n and ev.is_from(n), "source")
	n.free()
	check(ev.source() == null, "freed source reads as null (no crash)")
	ev.duration = 2.0
	ev.created_time = 10.0
	check_near(ev.time_left(11.0), 1.0, 0.0001, "time left")
	check_near(ev.life_fraction(11.5), 0.25, 0.0001, "life fraction")


func test_manager_dispatches_by_radius_and_sensitivity() -> void:
	SoundManager.clear()
	var near := _listen(Vector3(3, 1.5, 0))
	var far := _listen(Vector3(9, 1.5, 0))
	var deaf := _listen(Vector3(1, 1.5, 0), 0.0)
	var keen := _listen(Vector3(0, 1.5, 11), 2.0)
	var emitted := []
	var cb := func(p, r, i, cat, src): emitted.append([cat, r])
	EventBus.sound_emitted.connect(cb)
	var ev := SoundManager.emit_sound(&"footstep_jog", Vector3(0, 0, 0))
	EventBus.sound_emitted.disconnect(cb)
	check_eq(emitted.size(), 1, "EventBus.sound_emitted still fires (UI / debug)")
	check(emitted[0][0] == &"footstep_jog" and is_equal_approx(emitted[0][1], 8.0), "…with category and radius")
	check_eq(near.heard.size(), 1, "3 m < 8 m: heard")
	check_eq(far.heard.size(), 0, "9 m > 8 m: not heard")
	check_eq(deaf.heard.size(), 0, "deaf listener")
	check_eq(keen.heard.size(), 1, "sensitivity 2 hears 11 m")
	var info: Dictionary = near.heard[0][1]
	check_near(float(info.strength), SoundMath.perceived(0.35, 5.0, 8.0), 0.001, "strength")
	check_eq(info.path, &"direct", "direct path")
	check(near.heard[0][0] == ev, "gets the event")
	check(SoundManager.active_events().has(ev), "event kept alive for its duration")
	# Overrides + extras.
	var ev2 := SoundManager.emit_sound(&"zombie_moan", Vector3(0, 0, 0), null, {"radius": 2.0, "lure": Vector3(5, 0, 5), "hops": 1})
	check_near(ev2.radius, 2.0, 0.0001, "radius override")
	check_eq(ev2.extras.get(&"lure"), Vector3(5, 0, 5), "extras carried")
	check_eq(near.heard.size(), 1, "2 m radius does not reach 3 m")
	# Ambient masking (rain later) shrinks every radius.
	SoundManager.ambient_masking = 0.3
	SoundManager.emit_sound(&"footstep_jog", Vector3(0, 0, 0))
	check_eq(near.heard.size(), 1, "masked: 8 × 0.3 = 2.4 m < 3 m")
	SoundManager.ambient_masking = 1.0


func test_manager_skips_own_sounds_and_unregisters() -> void:
	var me := Node.new()
	var l := _listen(Vector3(1, 1.5, 0))
	l.owner_obj = me
	SoundManager.emit_sound(&"shout", Vector3.ZERO, me)
	check_eq(l.heard.size(), 0, "own sound skipped")
	SoundManager.emit_sound(&"shout", Vector3.ZERO, null)
	check_eq(l.heard.size(), 1, "someone else's sound heard")
	var n0 := SoundManager.listener_count()
	SoundManager.unregister_listener(l)
	check_eq(SoundManager.listener_count(), n0 - 1, "unregistered")
	check_eq(SoundManager.hashed_count(), SoundManager.listener_count(), "hash in sync")
	SoundManager.emit_sound(&"shout", Vector3.ZERO, null)
	check_eq(l.heard.size(), 1, "no more deliveries")
	me.free()


func test_freed_listener_is_pruned() -> void:
	var n := FakeNodeListener.new()
	SoundManager.register_listener(n)
	var c0 := SoundManager.listener_count()
	check(SoundManager.is_listening(n), "registered")
	n.free()
	# Dispatching near it must not crash and must drop it.
	SoundManager.emit_sound(&"shout", Vector3.ZERO, null)
	check_eq(SoundManager.listener_count(), c0 - 1, "freed listener dropped on dispatch")
	check_eq(SoundManager.hashed_count(), SoundManager.listener_count(), "hash in sync")
	check_eq(SoundManager.prune(), 0, "nothing stale left")


func test_classify_obstacles() -> void:
	check_eq(SoundManager.classify(null), SoundMath.PROP, "null → prop")
	var wall := StaticBody3D.new()
	wall.add_to_group(&"wall")
	check_eq(SoundManager.classify(wall), SoundMath.WALL, "group wall")
	var door := Door.new()
	check_eq(SoundManager.classify(door), SoundMath.DOOR_CLOSED, "closed door")
	door.state = Door.STATE_OPEN
	check_eq(SoundManager.classify(door), SoundMath.PROP, "an open leaf barely muffles")
	var win := HouseWindow.new()
	var pane := StaticBody3D.new()
	win.add_child(pane)
	check_eq(SoundManager.classify(pane), SoundMath.WINDOW_CLOSED, "a pane asks its window")
	win.state = HouseWindow.STATE_SMASHED
	check(win.sound_passes(), "smashed window lets sound out")
	check_eq(SoundManager.classify(pane), SoundMath.WALL, "a hit on an open window's frame is wall")
	var prop := StaticBody3D.new()
	check_eq(SoundManager.classify(prop), SoundMath.PROP, "other solids")
	for o in [wall, door, win, prop]:
		o.free()


var _bodies: Array = []


func _wall(pos: Vector3, size: Vector3, group: StringName = &"wall") -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	if group != &"":
		b.add_to_group(group)
	tree.root.add_child(b)
	b.global_position = pos
	_bodies.append(b)
	return b


func _free_bodies() -> void:
	for b in _bodies:
		if is_instance_valid(b):
			b.queue_free()
	_bodies.clear()
	await physics_frames(2)


func test_iterative_ray_counts_every_obstacle() -> void:
	var far := Vector3(500, 0, 500)  # away from anything else in the world
	var from := far + Vector3(0, 1.2, 0)
	var to := far + Vector3(20, 1.5, 0)
	for x in [3.0, 7.0, 11.0]:
		_wall(far + Vector3(x, 1.35, 0), Vector3(0.2, 2.7, 4))
	await physics_frames(2)
	check_near(SoundManager.obstacle_attenuation(from, to), 0.15, 0.001, "three walls: 0.125 → clamped 0.15 (not 0.25)")
	await _free_bodies()
	_wall(far + Vector3(3, 1.35, 0), Vector3(0.2, 2.7, 4))
	await physics_frames(2)
	check_near(SoundManager.obstacle_attenuation(from, to), 0.5, 0.001, "one wall")
	# Furniture in front of the wall never hides it: both multiply.
	_wall(far + Vector3(1.5, 0.75, 0), Vector3(0.6, 1.5, 1.0), &"")
	await physics_frames(2)
	check_near(SoundManager.obstacle_attenuation(from, to), 0.5 * 0.85, 0.001, "prop + wall = 0.425 (quieter, never louder)")
	# A ray starting inside a wall counts that wall (hit_from_inside).
	check_near(SoundManager.obstacle_attenuation(far + Vector3(3, 1.2, 0), to), 0.5, 0.001, "sound inside a wall is muffled by it")
	await _free_bodies()


func test_rejects_non_finite_sounds() -> void:
	var n0: int = SoundManager.stats.events
	check(SoundManager.emit_sound(&"shout", Vector3(NAN, 0, 0)) == null, "NaN position rejected")
	check(SoundManager.emit_sound(&"shout", Vector3(INF, 0, 0)) == null, "INF position rejected")
	check(SoundManager.emit_sound(&"shout", Vector3.ZERO, null, {"radius": INF}) == null, "INF radius rejected")
	check(SoundManager.emit_sound(&"shout", Vector3.ZERO, null, {"radius": NAN}) == null, "NaN radius rejected")
	check_eq(SoundManager.stats.events, n0, "no events created")


func test_expire_drops_every_expired_event() -> void:
	SoundManager.clear()
	var long := SoundManager.emit_sound(&"alarm", Vector3(900, 0, 900))  # 10 s
	var short := SoundManager.emit_sound(&"footstep_walk", Vector3(900, 0, 900))  # 0.6 s
	check(SoundManager.active_events().has(short), "both alive")
	await physics_frames(50)
	var alive := SoundManager.active_events()
	check(alive.has(long) and not alive.has(short), "the short one expired behind a long one")


func test_queued_sounds_spread_over_frames() -> void:
	SoundManager.clear()
	var l := _listen(Vector3(800, 1.5, 800))
	for i in 7:
		SoundManager.queue_sound(&"zombie_moan", Vector3(801, 0, 800), null)
	check_eq(SoundManager.queued_count(), 7, "queued, nothing dispatched yet")
	check_eq(l.heard.size(), 0, "not yet")
	await physics_frames(1)
	check(l.heard.size() <= SoundManager.MAX_QUEUED_PER_FRAME, "at most %d per frame (%d)" % [SoundManager.MAX_QUEUED_PER_FRAME, l.heard.size()])
	await physics_frames(5)
	check_eq(l.heard.size(), 7, "all delivered over a few frames")
	# A freed source drops its queued sound.
	var n := Node.new()
	SoundManager.queue_sound(&"zombie_moan", Vector3(801, 0, 800), n)
	n.free()
	await physics_frames(2)
	check_eq(l.heard.size(), 7, "moan of a freed zombie dropped")


func test_shout_numbers_are_data() -> void:
	var prof := load("res://data/characters/player_stats.tres") as CharacterStatsProfile
	check_near(prof.shout_stamina_cost, 6.0, 0.001, "shout costs 6 stamina")
	check_near(prof.shout_cooldown, 3.0, 0.001, "3 s cooldown")
	var zp := load("res://data/zombies/zombie_basic.tres") as ZombieProfile
	check(zp.lure_search_categories.has(&"shout"), "shout is a lure")
	check(zp.lure_search_time_min >= 8.0 and zp.lure_search_time_max <= 12.0, "8-12 s lure search")
	var ip := load("res://data/injuries/human_injuries.tres") as InjuryProfile
	check_near(ip.glass_laceration_chance, 0.4, 0.001, "glass climb 40 %")
