extends "res://tests/test_case.gd"
## Round 8 sound propagation + zombie hearing in the real test_ground
## scene: footsteps vs an idle zombie, window smash through the window vs
## behind walls, an open front door letting sound out, shout (H) lure,
## moan recruitment, glass hazard + "Remove broken glass", noise rings /
## HUD meter for player sounds only, F4 overlay, listener cleanup.
##
## Layout: House A x −14..−4, z −10..−2 (front door centre (−11, −2) in the
## south wall, living-room window (−7, −2), bedroom north window
## (−12, −10)); interior wall z = −6. Player spawns at the origin.
## A fresh zombie faces −Z (yaw 0); yaw PI faces +Z.

var scene: Node
var player: Character
var ctrl: PlayerController
var house: HouseBlockout
var nav: NavBaker
var spawner: ZombieSpawner
var hud: CanvasLayer
var _listeners0: int = 0


func setup() -> void:
	_listeners0 = SoundManager.listener_count()
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	house = scene.get_node("Buildings/HouseA")
	nav = scene.get_node("NavRegion")
	hud = scene.get_node("HUD")
	ctrl.scripted = true
	player.get_node("Interaction").scripted = true
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(5)
	SoundManager.clear()


func teardown() -> void:
	GameManager.sound_debug = false
	await despawn(scene)


func _teleport(p: Vector3) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = p
	player.velocity = Vector3.ZERO
	await physics_frames(3)


func _spawn(p: Vector3, yaw: float = 0.0, stay_idle: bool = true) -> Zombie:
	var z := spawner.spawn_at(p)
	z.snap_facing(yaw)
	if stay_idle:
		# Never wander off on its own: only sounds / sight move it.
		z.profile = z.profile.duplicate()
		z.profile.idle_time_min = 999.0
		z.profile.idle_time_max = 999.0
		z.ai.machine.change_to(&"idle", true)
	await physics_frames(3)
	return z


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _window_at(world: Vector3) -> HouseWindow:
	for w in house.windows:
		if (w.global_position - world).length() < 0.3:
			return w
	return null


func _door_at(world: Vector3) -> Door:
	for d in house.doors:
		if (d.global_position - world).length() < 0.2:
			return d
	return null


func _heard(z: Zombie) -> bool:
	return not z.senses.last_heard.is_empty()


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(1)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(1)


func test_sneaking_behind_idle_zombie_is_not_heard_but_sprinting_is() -> void:
	var z := await _spawn(Vector3(20, 0, 10))  # faces −Z; the player is behind it
	await _teleport(Vector3(18.5, 0.1, 14))
	ctrl.scripted_mode = MovementComponent.Mode.SNEAK
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(60 * 3)
	ctrl.scripted_direction = Vector3.ZERO
	check_eq(player.effective_mode, MovementComponent.Mode.SNEAK, "was sneaking")
	check_lt(_flat(player.global_position, z.global_position), 5.0, "stayed ~4 m behind (%.1f)" % _flat(player.global_position, z.global_position))
	check(not _heard(z), "sneak steps (2 m) not heard at 4 m (%s)" % str(z.senses.last_heard))
	check_eq(z.state(), &"idle", "still idle")
	# Sprinting the same way is heard (14 m).
	await _teleport(Vector3(18.5, 0.1, 14))
	ctrl.scripted_mode = MovementComponent.Mode.SPRINT
	ctrl.scripted_direction = Vector3.RIGHT
	var heard := await wait_physics_until(func(): return _heard(z), 60 * 2)
	ctrl.scripted_direction = Vector3.ZERO
	check(heard, "sprint footsteps heard")
	check_eq(z.senses.last_heard.get("category"), &"footstep_sprint", "category")
	check(z.state() == &"investigate" or z.state() == &"chase", "reacts (%s)" % z.state())


func test_window_smash_heard_through_the_window_not_behind_two_walls() -> void:
	await _teleport(Vector3(30, 0.1, 30))
	var win := _window_at(Vector3(-12, 0, -10))
	check(win != null, "bedroom north window")
	var front := await _spawn(Vector3(-12, 0, -25))  # 15 m out, in front of the window
	var behind := await _spawn(Vector3(-14.5, 0, 4.8), PI)  # 15 m, bedroom + south walls between
	check_near(_flat(front.global_position, win.global_position), 15.0, 0.1, "front zombie 15 m")
	check_near(_flat(behind.global_position, win.global_position), 15.0, 0.2, "behind zombie 15 m")
	check(win.smash().ok, "smashed")
	check(await _wait_state(front, &"investigate", 20), "front zombie investigates (%s)" % front.state())
	check_eq(front.senses.last_heard.get("path"), &"direct", "heard straight through the smashed window")
	check_lt((front.ai.investigate_position - win.global_position).length(), 0.5, "goes to the window")
	await physics_frames(60)
	check(not _heard(behind), "zombie behind two walls heard nothing (%s)" % str(behind.senses.last_heard))
	check_eq(behind.state(), &"idle", "…and does not react")


func test_open_front_door_carries_sound_further_than_a_wall() -> void:
	await _teleport(Vector3(30, 0.1, 30))
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(door != null and door.state == &"closed", "front door closed")
	var in_line := await _spawn(Vector3(-11, 0, 6.5), PI)  # 11 m, in line with the doorway
	var walled := await _spawn(Vector3(-17.5, 0, -5.5), PI)  # 6.6 m, behind the west wall
	var at := Vector3(-11, 0, -4.5)  # living room
	check(house.contains_point(at), "sound inside")
	# Closed door: 12 m × 0.6 = 7.2 m < 11 m.
	SoundManager.emit_sound(&"door_bang", at, null)
	await physics_frames(2)
	check(not _heard(in_line), "closed door muffles (%s)" % str(in_line.senses.last_heard))
	check(door.open_door(null).ok, "door opened")
	await physics_frames(30)
	SoundManager.emit_sound(&"door_bang", at, null)
	await physics_frames(2)
	check(_heard(in_line), "open door: 11 m away in line with the door hears it")
	check(not _heard(walled), "6.6 m away behind the wall does not (12 × 0.5 = 6 m)")
	var d_in := _flat(in_line.global_position, at)
	var d_wall := _flat(walled.global_position, at)
	check_gt(d_in, d_wall, "the one that heard is further away (%.1f vs %.1f)" % [d_in, d_wall])


func test_sound_escapes_through_an_opening_around_a_corner() -> void:
	# Ear outside, not in line: the direct ray crosses the south wall
	# (12 × 0.5 = 6 m < 7.5 m) but the path through the open front door
	# (2.5 + 5.7 = 8.2 m) fits the 12 m radius.
	await _teleport(Vector3(30, 0.1, 30))
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(door.open_door(null).ok, "door opened")
	await physics_frames(30)
	var z := await _spawn(Vector3(-15.5, 0, 1.5), PI)
	SoundManager.emit_sound(&"door_bang", Vector3(-11, 0, -4.5), null)
	await physics_frames(2)
	check(_heard(z), "heard via the doorway")
	check_eq(z.senses.last_heard.get("path"), &"opening", "path = opening")


func test_shout_lures_a_zombie_from_18_m() -> void:
	await _teleport(Vector3(20, 0.1, 0))
	var z := await _spawn(Vector3(20, 0, 18), PI)  # faces away
	var st0 := player.stats.get_value(Character.STAMINA)
	var shouts := []
	var cb := func(c, ok, reason): shouts.append([c, ok, reason])
	EventBus.shouted.connect(cb)
	await _press(&"shout")  # H through the input map
	EventBus.shouted.disconnect(cb)
	check_eq(shouts.size(), 1, "one shout")
	check(shouts.size() == 1 and shouts[0][1] == true, "shout ok")
	check_near(player.stats.get_value(Character.STAMINA), st0 - player.profile.shout_stamina_cost, 0.3, "costs stamina")
	check_eq(hud.notice_label.text, "You shout!", "HUD notice")
	var again: Dictionary = player.get_node("Shout").shout()
	check(not again.ok and again.reason == "Cooldown", "1 s cooldown")
	check(await _wait_state(z, &"investigate", 10), "zombie 18 m away investigates (%s)" % z.state())
	check_eq(z.senses.last_heard.get("category"), &"shout", "heard the shout")
	check_lt(_flat(z.ai.investigate_position, player.global_position), 0.5, "heads for the shout")
	var d0 := _flat(z.global_position, player.global_position)
	await physics_frames(60 * 5)
	var d1 := _flat(z.global_position, player.global_position)
	check_lt(d1, d0 - 2.0, "walks toward the player (%.1f → %.1f)" % [d0, d1])


func test_loud_sound_is_chased_faint_one_turns_first_and_priority() -> void:
	await _teleport(Vector3(40, 0.1, 40))
	var near := await _spawn(Vector3(20, 0, 3))
	var far := await _spawn(Vector3(20, 0, 18.5), PI)
	SoundManager.emit_sound(&"shout", Vector3(20, 0, 0), null)
	await physics_frames(2)
	check(near.ai.investigate_loud, "3 m from a shout: loud (strength %.2f)" % near.ai.sound_strength)
	check(not far.ai.investigate_loud and far.ai.investigate_pause, "18.5 m: faint → turn first")
	await physics_frames(24)
	check_lt(far.speed(), 0.05, "faint: stands and turns first")
	await physics_frames(60)
	check_gt(near.speed(), near.profile.shamble_speed + 0.2, "loud: investigates at chase speed (%.2f)" % near.speed())
	check(far.speed() > 0.3 and far.speed() <= far.profile.shamble_speed + 0.05, "faint: then shambles (%.2f)" % far.speed())
	# Priority: the near zombie follows the loud shout; a faint rummage
	# elsewhere does not steal it.
	var goal := near.ai.investigate_position
	SoundManager.emit_sound(&"rummage", near.global_position + Vector3(2.5, 0, 0), null)
	await physics_frames(2)
	check_lt((near.ai.investigate_position - goal).length(), 0.01, "fainter sound ignored while investigating a loud one")
	SoundManager.emit_sound(&"window_smash", near.global_position + Vector3(0, 0, 4), null)
	await physics_frames(2)
	check_gt((near.ai.investigate_position - goal).length(), 1.0, "a louder one re-targets")


func test_moan_recruits_a_neighbour() -> void:
	await _teleport(Vector3(60, 0.1, 60))
	var z1 := await _spawn(Vector3(20, 0, 20))
	var z2 := await _spawn(Vector3(24, 0, 20))
	var lure := Vector3(20, 0, 26)
	SoundManager.emit_sound(&"shout", lure, null, {"radius": 7.0})
	check(await _wait_state(z1, &"investigate", 10), "z1 (6 m) investigates")
	check(await wait_physics_until(func(): return _heard(z2), 30), "z2 hears z1's moan")
	check_eq(z2.senses.last_heard.get("category"), &"zombie_moan", "…a moan (z2 was 7.2 m from the shout)")
	check(await _wait_state(z2, &"investigate", 20), "z2 recruited (%s)" % z2.state())
	check_lt(_flat(z2.ai.investigate_position, lure), 0.1, "z2 heads for the lure, not for z1")
	check_eq(z2.ai.sound_hops, 1, "one relay hop")
	# No second moan from z1 within the cooldown.
	var moans := []
	var cb := func(ev, _n): if ev.category == &"zombie_moan" and ev.is_from(z1): moans.append(ev)
	SoundManager.sound_dispatched.connect(cb)
	await physics_frames(60 * 3)
	SoundManager.sound_dispatched.disconnect(cb)
	check_eq(moans.size(), 0, "moan cooldown")


func test_zombie_door_banging_recruits_other_zombies() -> void:
	await _teleport(Vector3(30, 0.1, 30))
	var door := _door_at(Vector3(-11.45, 0, -2))
	var banger := await _spawn(Vector3(-11, 0, -1))
	var other := await _spawn(Vector3(-11, 0, 8), PI)  # 10 m out
	door.take_damage(8.0, banger)
	await physics_frames(2)
	check(_heard(other), "door bang heard 10 m away")
	check_eq(other.senses.last_heard.get("category"), &"door_bang", "category")
	check(not _heard(banger), "the banger does not hear itself")
	check(await _wait_state(other, &"investigate", 10), "recruited")


func test_glass_hazard_scratches_feet_and_remove_glass_clears_it() -> void:
	var win := _window_at(Vector3(-7, 0, -2))
	check(win != null, "living-room window")
	check(win.smash(player).ok, "smashed")
	check(win.has_glass(), "glass on the floor")
	var glass: GlassShards = win.glass
	check(glass.is_in_group(&"glass_shards"), "hazard node")
	glass.scratch_chance_per_second = 1.0
	var hurt := []
	var cb := func(c, hz, region): hurt.append([c, hz, region])
	EventBus.hazard_hurt.connect(cb)
	# Sneaking across: careful steps.
	await _teleport(Vector3(-7.8, 0.1, -1.5))
	ctrl.scripted_mode = MovementComponent.Mode.SNEAK
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(90)
	check_eq(glass.scratches, 0, "sneaking avoids the shards")
	# Walking across: scratched.
	await _teleport(Vector3(-7.8, 0.1, -1.5))
	ctrl.scripted_mode = MovementComponent.Mode.WALK
	ctrl.scripted_direction = Vector3.RIGHT
	var scratched := await wait_physics_until(func(): return glass.scratches > 0, 60)
	ctrl.scripted_direction = Vector3.ZERO
	EventBus.hazard_hurt.disconnect(cb)
	check(scratched, "walking over glass scratches")
	check(hurt.size() >= 1 and hurt[0][1] == &"glass", "hazard_hurt event")
	var leg_scratch := player.injuries.injuries.any(func(i): return Injury.is_leg_region(i.region) and i.type == Injury.Type.SCRATCH)
	check(leg_scratch, "a foot (leg) scratch")
	await frames(1)
	check_eq(hud.notice_label.text, "Stepped on broken glass!", "HUD notice")
	# Remove broken glass: 3 s busy + a 3 m noise, then gone (floor + frame).
	await _teleport(Vector3(-7, 0.1, -1.2))
	var noises := []
	var cbn := func(_p, r2, _i, cat, src): if src == player: noises.append([cat, r2])
	EventBus.sound_emitted.connect(cbn)
	var acts := Interactable.of(win).get_actions(player)
	check(acts.any(func(a): return a.id == &"clear_glass" and a.enabled), "Remove broken glass offered")
	var r := Interactable.of(win).perform(&"clear_glass", player)
	check(r.ok and r.get("busy", false), "started")
	check(player.is_busy and player.busy_context == &"clear_glass", "busy clearing")
	EventBus.sound_emitted.disconnect(cbn)
	check(noises.any(func(n): return n[0] == &"glass_clear" and is_equal_approx(n[1], 3.0)), "removing glass makes a 3 m noise (%s)" % str(noises))
	await frames(1)
	check_eq(HUD_busy_label(), "Clearing glass", "HUD state label")
	await physics_frames(150)
	check(win.has_glass(), "not done after 2.5 s")
	check(await wait_physics_until(func(): return not win.has_glass(), 60), "cleared after 3 s")
	check(not player.is_busy, "free again")
	await frames(2)
	check(not is_instance_valid(glass) or glass.is_queued_for_deletion(), "hazard removed")
	acts = Interactable.of(win).get_actions(player)
	check(not acts.any(func(a): return a.id == &"clear_glass"), "no more glass to remove")
	check_eq(acts[0].label, "Climb through", "climbing is safe now")


func HUD_busy_label() -> String:
	return hud.busy_label_for(player)


func test_noise_rings_only_for_player_sounds_and_hud_meter() -> void:
	var rings: NoiseRings = scene.get_node("NoiseRings")
	var meter: NoiseMeter = hud.noise_meter
	check(meter != null, "HUD noise meter")
	var n0 := rings.spawned
	var z := await _spawn(Vector3(30, 0, 30))
	SoundManager.emit_sound(&"door_bang", Vector3(5, 0, 5), null)
	SoundManager.emit_sound(&"zombie_moan", z.global_position, z)
	check_eq(rings.spawned, n0, "no ring for world / zombie sounds")
	check_near(meter.shown, 0.0, 0.01, "meter ignores them")
	SoundManager.emit_sound(&"shout", player.global_position, player)
	check_eq(rings.spawned, n0 + 1, "ring for the player's shout")
	check(rings.active_radii().has(20.0), "radius-sized (20 m)")
	check_near(meter.shown, 20.0, 0.01, "meter shows 20 m")
	check(meter.is_loud(), "past the loud line")
	await frames(1)
	check(meter._value_label.text.contains("LOUD"), "reads LOUD (%s)" % meter._value_label.text)
	# Jogging footsteps make rings too.
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(75)
	ctrl.scripted_direction = Vector3.ZERO
	check_gt(float(rings.spawned), float(n0 + 1), "footstep ring")
	# The pool never exceeds 20 and rings fade.
	for i in 30:
		rings.spawn(Vector3(i, 0, 0), 4.0)
	check(rings.active_count() <= 20, "pool capped at 20 (%d)" % rings.active_count())
	check(await wait_until(func(): return rings.active_count() == 0, 400), "rings fade out")
	check(await wait_until(func(): return meter.shown < 0.5, 400), "meter drains")


func test_f4_debug_overlay_draws_events_and_hearing_lines() -> void:
	var dbg: SoundDebugOverlay = scene.get_node("SoundDebug")
	check(not GameManager.sound_debug, "off by default")
	await _press(&"toggle_sound_debug")
	check(GameManager.sound_debug, "F4 turns it on")
	var z := await _spawn(Vector3(5, 0, 5))
	SoundManager.emit_sound(&"door_bang", Vector3(5, 0, 1), null)
	await frames(2)
	check_gt(float(dbg.drawn_circles), 0.0, "event circles drawn")
	check_gt(float(dbg.drawn_lines), 0.0, "hearing line drawn (%s)" % str(z.senses.last_heard))
	await _press(&"toggle_sound_debug")
	check(not GameManager.sound_debug, "F4 again turns it off")
	await frames(2)
	check_eq(dbg.drawn_circles, 0, "nothing drawn while off")


func test_listener_cleanup_when_zombies_are_freed() -> void:
	var base := SoundManager.listener_count()
	var a := await _spawn(Vector3(10, 0, 10))
	var b := await _spawn(Vector3(12, 0, 10))
	var c := await _spawn(Vector3(14, 0, 10))
	check_eq(SoundManager.listener_count(), base + 3, "three zombies listen")
	check_eq(SoundManager.hashed_count(), SoundManager.listener_count(), "hash in sync")
	check(SoundManager.is_listening(a.senses), "senses registered")
	a.die(null)
	check(not SoundManager.is_listening(a.senses), "dead zombies stop listening at once")
	b.queue_free()  # despawned without dying
	await frames(2)
	check_eq(SoundManager.listener_count(), base + 1, "freed zombie unregistered")
	SoundManager.emit_sound(&"shout", Vector3(12, 0, 10), null)
	check_eq(SoundManager.prune(), 0, "no stale entries")
	check_eq(SoundManager.hashed_count(), SoundManager.listener_count(), "hash still in sync")
	check(_heard(c), "the survivor still hears")
	await despawn(scene)
	scene = null
	await frames(2)
	check_eq(SoundManager.listener_count(), _listeners0, "scene freed: no listeners left")
	check_eq(SoundManager.hashed_count(), _listeners0, "…and none in the hash")


func _wait_state(z: Zombie, id: StringName, max_frames: int) -> bool:
	return await wait_physics_until(func(): return z.state() == id, max_frames)


# --- Round 8 critic fixes -------------------------------------------------------

func test_door_closed_inside_is_muffled_outside() -> void:
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(door.open_door(null).ok, "front door opened")
	await physics_frames(40)
	var outside := await _spawn(Vector3(-11, 0, 5), PI)  # 7 m out, in line with the doorway
	await _teleport(Vector3(-11.2, 0.1, -3.0))  # inside, next to the door
	var ev_holder := []
	var cb := func(ev, _n): if ev.category == &"door_close": ev_holder.append(ev)
	SoundManager.sound_dispatched.connect(cb)
	check(door.close_door(player).ok, "closed from inside")
	check(ev_holder.is_empty(), "the slam comes when the leaf is shut, not at once")
	check(await wait_physics_until(func(): return not ev_holder.is_empty(), 60), "slammed after the 0.4 s swing")
	SoundManager.sound_dispatched.disconnect(cb)
	check_eq(ev_holder.size(), 1, "door_close sound")
	if ev_holder.is_empty():
		return
	var at: Vector3 = ev_holder[0].position
	check_lt(at.z, -2.1, "the sound starts on the closer's (inside) side (%s)" % str(at))
	check(house.contains_point(at), "…inside the house")
	await physics_frames(2)
	check(not _heard(outside), "8 m × 0.6 (closed leaf) = 4.8 m < 7 m: not heard outside")
	# The same slam with the door open would carry.
	var r := SoundManager.evaluate(SoundEvent.new(&"door_close", at, 8.0, 0.4), outside.eye_position())
	check_lt(float(r.attenuation), 0.65, "the leaf is counted (%.2f)" % float(r.attenuation))


func test_indoor_listener_hears_a_street_shout_through_an_open_door() -> void:
	await _teleport(Vector3(30, 0.1, 30))
	var inside := await _spawn(Vector3(-6, 0, -4.5), PI)  # living room, east end
	var shout_at := Vector3(-17, 0, 3)  # street, south-west
	var door := _door_at(Vector3(-11.45, 0, -2))
	SoundManager.emit_sound(&"shout", shout_at, null)
	await physics_frames(2)
	check(not _heard(inside), "front door closed: not heard (13.3 m, wall ×0.5)")
	check(door.open_door(null).ok, "door opened")
	await physics_frames(40)
	SoundManager.emit_sound(&"shout", shout_at, null)
	await physics_frames(2)
	check(_heard(inside), "open door: the shout comes in through the doorway")
	check_eq(inside.senses.last_heard.get("path"), &"opening", "path = opening (ear inside, sound outside)")


func test_moan_never_downgrades_a_loud_investigation() -> void:
	await _teleport(Vector3(60, 0.1, 60))
	var z := await _spawn(Vector3(20, 0, 20))
	SoundManager.emit_sound(&"window_smash", Vector3(20, 0, 23), null)
	await physics_frames(2)
	check(z.ai.investigate_loud and z.ai.sound_hops == 0, "loud, first-hand")
	var moan := SoundEvent.new(&"zombie_moan", Vector3(21, 0, 20), 6.0, 0.25)
	moan.extras = {&"lure": Vector3(25, 0, 25), &"hops": 1}
	z.ai.sound_strength = 0.0  # pretend the smash faded so the moan wins
	z.ai.call(&"_on_sound_heard", moan.position, moan.category, 0.2, moan)
	check_lt(_flat(z.ai.investigate_position, Vector3(25, 0, 25)), 0.1, "re-targeted to the lure")
	check(z.ai.investigate_loud, "still loud (max)")
	check_eq(z.ai.sound_hops, 0, "hops stay at the first-hand 0 (min)")


func test_dead_player_makes_no_shout_notice_or_meter() -> void:
	var meter: NoiseMeter = hud.noise_meter
	var rings: NoiseRings = scene.get_node("NoiseRings")
	player.take_damage(9999.0, null, {})
	await physics_frames(2)
	check(player.is_dead(), "dead")
	hud.notice_label.text = ""
	var shouts := []
	var cb := func(c, ok, reason): shouts.append(reason)
	EventBus.shouted.connect(cb)
	var r: Dictionary = player.get_node("Shout").shout()
	EventBus.shouted.disconnect(cb)
	check(not r.ok, "refused")
	check(shouts.is_empty(), "no shouted event for the dead")
	check_eq(hud.notice_label.text, "", "no notice")
	var n0 := rings.spawned
	SoundManager.emit_sound(&"window_smash", player.global_position, player)
	check_near(meter.shown, 0.0, 0.01, "meter ignores a dead player")
	check_eq(rings.spawned, n0, "no ring for a dead player")


func test_shout_costs_more_and_zombies_search_the_spot_longer() -> void:
	await _teleport(Vector3(20, 0.1, 0))
	var z := await _spawn(Vector3(20, 0, 6), PI)  # faces away, 6 m
	var st0 := player.stats.get_value(Character.STAMINA)
	var r: Dictionary = player.get_node("Shout").shout()
	check(r.ok, "shout")
	check_near(player.stats.get_value(Character.STAMINA), st0 - 6.0, 0.3, "6 stamina")
	# Slip away at once so the zombie arrives at an empty spot.
	player.global_position = Vector3(60, 0.1, -40)
	await physics_frames(60 * 2)
	check(not player.get_node("Shout").shout().ok, "still on the 3 s cooldown after 2 s")
	await physics_frames(70)
	check(player.get_node("Shout").shout().ok, "…and ready again after 3 s")
	check(await _wait_state(z, &"search", 60 * 12), "arrives and searches (%s)" % z.state())
	var st: ZombieStateSearch = z.ai.machine.current
	check(st.lure, "a lure search")
	check(st.total_seconds() >= 8.0 and st.total_seconds() <= 12.0, "8-12 s (%.1f)" % st.total_seconds())
	var r0 := st.walk_radius()
	await physics_frames(60 * 4)
	if z.state() == &"search":
		check_gt(st.walk_radius(), r0 + 0.5, "the search widens (%.1f → %.1f)" % [r0, st.walk_radius()])
	await physics_frames(60 * 3)
	check_eq(z.state(), &"search", "still searching after 7 s (a normal search is 4-6 s)")


func test_glass_climb_zone_and_walking_chance() -> void:
	var win := _window_at(Vector3(-7, 0, -2))
	win.smash(null)
	var glass: GlassShards = win.glass
	check_near(glass.size.y, 2.4, 0.001, "1.2 m out on both sides")
	check(glass.contains_point(win.global_position + Vector3(0, 0, 1.1)), "1.1 m outside is on glass")
	check(glass.contains_point(win.global_position + Vector3(0, 0, -1.1)), "1.1 m inside is on glass")
	check(not glass.contains_point(win.global_position + Vector3(0, 0, 1.4)), "1.4 m is clear")
	check_near(glass.scratch_chance_per_second, 0.25, 0.001, "25 %/s")
	# Climbing with glass in the frame: 40 % laceration (forced here).
	var inj := player.injuries
	inj.profile = inj.profile.duplicate()
	inj.profile.glass_laceration_chance = 1.0
	await _teleport(Vector3(-7, 0.1, -3.0))
	var n0 := inj.injuries.size()
	check(win.climb(player).ok and win.last_climb_hazard, "hazardous climb")
	await wait_physics_until(func(): return not player.is_busy, 90)
	check_gt(float(inj.injuries.size()), float(n0), "lacerated")
	# After removing the glass the same climb is safe.
	win.remove_glass()
	var n1 := inj.injuries.size()
	check(win.climb(player).ok and not win.last_climb_hazard, "safe climb")
	await wait_physics_until(func(): return not player.is_busy, 90)
	check_eq(inj.injuries.size(), n1, "no cut")


func test_f4_overlay_labels_strength_and_idles_when_off() -> void:
	var dbg: SoundDebugOverlay = scene.get_node("SoundDebug")
	var z := await _spawn(Vector3(5, 0, 5))
	GameManager.sound_debug = true
	SoundManager.emit_sound(&"door_bang", Vector3(5, 0, 1), null)
	await frames(2)
	var texts := dbg.label_texts()
	check(not texts.is_empty(), "strength label on the hearing line")
	check(texts.has("%.2f" % float(z.senses.last_heard.strength)), "label = perceived strength (%s)" % str(texts))
	GameManager.sound_debug = false
	await frames(2)
	var r0 := dbg.redraws
	SoundManager.emit_sound(&"door_bang", Vector3(5, 0, 1), null)
	await frames(5)
	check_eq(dbg.redraws, r0, "no drawing work while off")
	check(dbg.label_texts().is_empty(), "labels hidden")
