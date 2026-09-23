extends "res://tests/test_case.gd"
## Real test_ground scene: doors, windows, rooms and the occlusion cutaway,
## driven through the scripted PlayerController + PlayerInteraction API.
##
## House A: local origin at world (-14, 0, -10); footprint 10 x 8.
##   front door centre  (-11, -2)   (south wall, outward +Z)
##   bedroom door       (-12, -6)   (interior wall z = -6)
##   bedroom W window   (-14, -8)   bedroom N window (-12, -10)
##   living E window    (-4, -4)
## Camera yaw 45°: the eye is at +X +Z, so south and east walls get cut.

var scene: Node
var player: Character
var ctrl: PlayerController
var interaction: PlayerInteraction
var house: HouseBlockout
var occl: OcclusionManager


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	scene.get_node("Zombies").auto_spawn = false  # zombies have their own tests
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	interaction = player.get_node("Interaction")
	house = scene.get_node("Buildings/HouseA")
	occl = scene.get_node("OcclusionManager")
	ctrl.scripted = true
	interaction.scripted = true
	await physics_frames(10)


func teardown() -> void:
	await despawn(scene)


func _drive(dir: Vector3, frames_n: int, mode := MovementComponent.Mode.WALK) -> void:
	ctrl.scripted_direction = dir
	ctrl.scripted_mode = mode
	await physics_frames(frames_n)
	ctrl.scripted_direction = Vector3.ZERO
	await physics_frames(3)


func _teleport(p: Vector3) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = p
	player.velocity = Vector3.ZERO
	await physics_frames(8)


func _door_at(world: Vector3) -> Door:
	for d in house.doors:
		if (d.global_position - world).length() < 0.6:
			return d
	return null


func _window_at(world: Vector3) -> HouseWindow:
	for w in house.windows:
		if (w.global_position - world).length() < 0.3:
			return w
	return null


func _walls_with_outward(n: Vector3) -> Array[Node]:
	var out: Array[Node] = []
	for w in house.get_walls():
		var o: Vector3 = w.get_meta(&"outward", Vector3.ZERO)
		if o.is_equal_approx(n):
			out.append(w)
	return out


func _settle_occlusion() -> void:
	# 10 Hz update + 0.2 s tween.
	await physics_frames(8)
	occl.update_now()
	await physics_frames(16)


func test_house_generated_from_plan() -> void:
	check_eq(house.rooms.size(), 4, "four rooms")
	check_eq(house.doors.size(), 5, "five doors")
	check_eq(house.windows.size(), 7, "seven windows")
	check_eq(house.get_roofs().size(), 1, "one roof")
	check_gt(house.get_walls().size(), 20.0, "walls registered in group")
	check(house.room_at(Vector3(-9, 0.5, -4)) != null, "living room volume")
	check_eq(house.room_at(Vector3(-9, 0.5, -4)).room_name, "Living Room", "room name")
	check(house.room_at(Vector3(0, 0.5, 0)) == null, "spawn is outside")
	var loc := Building.locate(tree, Vector3(-12, 0.5, -8))
	check_eq(loc.building, house, "locate finds the building")
	check_eq(loc.room.room_name, "Bedroom", "locate finds the room")


func test_closed_door_blocks_then_opens_and_lets_player_in() -> void:
	var start := Vector3(-11, 0.1, 0.6)
	await _teleport(start)
	await _drive(Vector3.FORWARD, 120)  # 2 s north into the closed front door
	check_gt(player.global_position.z, -1.75, "closed door blocks the player")
	check_lt(player.global_position.z, -1.0, "but did walk up to it")
	check(interaction.current_target != null, "door is targeted")
	check_eq(interaction.current_actions[0].id, &"open", "first action is open")
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(door != null, "front door found")
	var r := interaction.interact()
	check(r.ok, "interact opened the door")
	check_eq(door.state, &"open", "door state open")
	await physics_frames(30)
	await _teleport(start)
	await _drive(Vector3.FORWARD, 120)  # same drive, same start: now passes
	check_lt(player.global_position.z, -2.3, "walked through the open doorway from the same start")
	check(house.contains_point(player.global_position), "now inside the house")


func test_open_door_can_be_closed_and_blocks_again() -> void:
	await _teleport(Vector3(-11, 0.1, -0.7))
	await physics_frames(3)
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(interaction.interact().ok, "open")
	await physics_frames(3)
	check_eq(interaction.current_actions[0].id, &"close", "close offered while open")
	check(not interaction.current_actions[0].enabled and interaction.current_actions[0].reason == "Busy", "…but Busy during the cooldown")
	await physics_frames(35)
	check(interaction.current_actions[0].enabled, "close enabled after cooldown")
	check(interaction.interact().ok, "close")
	check_eq(door.state, &"closed", "closed")
	await physics_frames(35)
	await _drive(Vector3.FORWARD, 60)
	check_gt(player.global_position.z, -1.75, "closed again: blocked")


func test_inside_cutaway_hides_roof_and_cuts_camera_facing_walls() -> void:
	var got := []
	var cb := func(room, _b): got.append(room)
	EventBus.player_room_changed.connect(cb)
	await _teleport(Vector3(-9, 0.1, -4))
	await _settle_occlusion()
	EventBus.player_room_changed.disconnect(cb)
	check(occl.current_room != null and occl.current_room.room_name == "Living Room", "inside living room")
	check(got.size() >= 1 and got[-1] == occl.current_room, "player_room_changed emitted")
	var roof: Node = house.get_roofs()[0]
	check_eq(occl.state_of(roof), &"hidden", "roof hidden")
	check(not roof.get_node("Visual").visible, "roof visual invisible after fade")
	var south := _walls_with_outward(Vector3(0, 0, 1))
	var north := _walls_with_outward(Vector3(0, 0, -1))
	var east := _walls_with_outward(Vector3(1, 0, 0))
	var west := _walls_with_outward(Vector3(-1, 0, 0))
	check_gt(south.size(), 2.0, "south wall has segments")
	for w in south:
		check_eq(occl.state_of(w), &"stub", "south (camera-facing) segment %s cut" % w.name)
		check_near(w.get_node("Visual").scale.y, occl.stub_height / 2.7, 0.02, "visual scaled to stub")
	# Collision untouched: walk into the stubbed south wall (z = -2) from inside.
	await _teleport(Vector3(-9, 0.1, -2.7))
	await _drive(Vector3.BACK, 60)
	check_lt(player.global_position.z, -2.35, "stubbed wall still blocks (z stays inside)")
	check(house.contains_point(player.global_position), "still inside")
	await _teleport(Vector3(-9, 0.1, -4))
	await _settle_occlusion()
	for w in east:
		check_eq(occl.state_of(w), &"stub", "east (camera-facing) segment cut")
	for w in north:
		check_eq(occl.state_of(w), &"full", "north (far) wall standing")
	for w in west:
		check_eq(occl.state_of(w), &"full", "west (far) wall standing")
	# Leave the house: everything restored.
	await _teleport(Vector3(4, 0.1, 4))
	await _settle_occlusion()
	check(occl.current_room == null, "outside again")
	check_eq(occl.state_of(roof), &"full", "roof restored")
	check(roof.get_node("Visual").visible, "roof visible")
	for w in south:
		check_eq(occl.state_of(w), &"full", "south wall restored")
		check_near(w.get_node("Visual").scale.y, 1.0, 0.02, "scale restored")


func test_occlusion_does_not_thrash_when_standing_still() -> void:
	await _teleport(Vector3(-9, 0.1, -4))
	await _settle_occlusion()
	var snapshot := occl.states.duplicate()
	var roof: Node = house.get_roofs()[0]
	var visual: Node3D = roof.get_node("Visual")
	var vis0 := visual.visible
	for i in 30:
		await tree.physics_frame
		check(visual.visible == vis0, "roof visibility stable")
	check_eq(occl.states, snapshot, "states unchanged while standing still")


func test_outside_behind_house_fades_occluding_walls() -> void:
	# West of the house: the eye is at +X +Z, so the house is between.
	await _teleport(Vector3(-15.2, 0.1, -8))
	await _settle_occlusion()
	check(occl.current_room == null, "outside")
	var faded := 0
	for w in house.get_walls():
		if occl.state_of(w) == &"faded":
			faded += 1
	check_gt(faded, 0.0, "at least one wall segment faded between eye and player")
	var roof: Node = house.get_roofs()[0]
	check(occl.state_of(roof) != &"hidden", "roof not hidden when outside")


func test_interior_door_and_room_change() -> void:
	await _teleport(Vector3(-12, 0.1, -5.2))
	await _drive(Vector3.FORWARD, 10)
	var door := _door_at(Vector3(-12.45, 0, -6))
	check(door != null, "bedroom door found")
	check_eq(interaction.current_target, Interactable.of(door), "bedroom door targeted")
	check(interaction.interact().ok, "opened bedroom door")
	await physics_frames(30)
	await _drive(Vector3.FORWARD, 60)
	await _settle_occlusion()
	check(occl.current_room != null and occl.current_room.room_name == "Bedroom", "now in the bedroom")


func test_open_window_climb_out_lands_outside() -> void:
	await _teleport(Vector3(-13.3, 0.1, -8))
	await _drive(Vector3.LEFT, 5)  # face west
	var win := _window_at(Vector3(-14, 0, -8))
	check(win != null, "bedroom west window found")
	check_eq(interaction.current_target, Interactable.of(win), "window targeted")
	check_eq(interaction.current_actions[0].id, &"open", "E opens a closed window")
	check(interaction.interact().ok, "opened")
	check_eq(win.state, &"open", "open")
	check_eq(interaction.current_actions[0].id, &"climb", "E now climbs")
	check(not interaction.current_actions[0].label.contains("glass"), "no glass warning on an intact window")
	var r := interaction.interact()
	check(r.ok, "climb accepted")
	check(not r.hazard, "no hazard")
	check(player.is_busy, "player busy while climbing")
	# Intent is ignored while busy.
	ctrl.scripted_direction = Vector3.BACK
	await physics_frames(10)
	check_lt(player.speed(), 0.01, "no locomotion while busy")
	var landed := await wait_until(func(): return not player.is_busy, 120)
	ctrl.scripted_direction = Vector3.ZERO
	check(landed, "climb finished")
	check_lt(player.global_position.x, -14.3, "landed outside (west of the wall)")
	check_near(player.global_position.z, -8.0, 0.2, "stayed on the window's axis")
	await physics_frames(10)
	check(not house.contains_point(player.global_position), "outside the building")
	check_near(player.global_position.y, 0.0, 0.1, "on the ground")


func test_smashed_window_climb_sets_hazard() -> void:
	await _teleport(Vector3(-12, 0.1, -10.7))  # outside, north of the bedroom N window
	await physics_frames(3)
	var win := _window_at(Vector3(-12, 0, -10))
	check(win != null, "north window found")
	check_eq(interaction.current_target, Interactable.of(win), "window targeted from behind")
	var r := interaction.perform_action(&"smash")
	check(r.ok, "smashed")
	check_eq(win.state, &"smashed", "state smashed")
	check_eq(interaction.current_actions[0].label, "Climb through (glass)", "glass label")
	var events := []
	var cb := func(actor, w, hazard): events.append([actor, w, hazard])
	EventBus.window_climbed.connect(cb)
	r = interaction.interact()
	check(r.ok and r.hazard, "climb through glass flags hazard")
	var landed := await wait_until(func(): return not player.is_busy, 120)
	EventBus.window_climbed.disconnect(cb)
	check(landed, "finished")
	check_gt(player.global_position.z, -9.6, "ended inside (south of the wall)")
	check(house.room_at(player.global_position) != null and house.room_at(player.global_position).room_name == "Bedroom", "in the bedroom")
	check_eq(events.size(), 1, "window_climbed event")
	check(events[0][2] == true, "event carries hazard")


func test_window_blocks_walking_even_when_open() -> void:
	await _teleport(Vector3(-3.0, 0.1, -4))  # outside, east of the living E window
	await _drive(Vector3.LEFT, 60)
	check_gt(player.global_position.x, -3.85, "closed window blocks")
	var win := _window_at(Vector3(-4, 0, -4))
	check(win != null, "east window found")
	win.open_window()
	await physics_frames(5)
	await _drive(Vector3.LEFT, 60)
	check_gt(player.global_position.x, -3.85, "open window still blocks walking")
	check(not house.contains_point(player.global_position), "still outside")


func test_number_key_selects_alternative_action() -> void:
	await _teleport(Vector3(-13.3, 0.1, -8))
	await _drive(Vector3.LEFT, 5)
	var win := _window_at(Vector3(-14, 0, -8))
	check_eq(interaction.current_actions[1].id, &"smash", "[2] is smash on a closed window")
	var r := interaction.perform_index(1)
	check(r.ok, "index 1 performed")
	check_eq(win.state, &"smashed", "smashed via alternative action")
	check_eq(interaction.current_actions.size(), 2, "smashed: climb + remove glass (open / close hidden)")
	r = interaction.perform_index(4)
	check(not r.ok, "out-of-range index refused")
	var disabled := interaction.perform_action(&"open")
	check(not disabled.ok, "open on a smashed frame refused (%s)" % str(disabled))
	check(not interaction.current_actions.any(func(a): return a.id == &"open"), "…and no longer listed")


func test_hud_prompt_reflects_actions() -> void:
	var hud := scene.get_node("HUD")
	await _teleport(Vector3(-11, 0.1, -0.7))
	await physics_frames(5)
	check(String(hud.prompt_label.text).begins_with("E: Open door"), "prompt shows E: Open door, got '%s'" % hud.prompt_label.text)
	await _teleport(Vector3(4, 0.1, 4))
	check_eq(hud.prompt_label.text, "", "prompt cleared away from targets")
	var txt: String = hud.format_prompt("Window", [
		{"id": &"open", "label": "Open window", "enabled": true, "reason": ""},
		{"id": &"smash", "label": "Smash window", "enabled": true, "reason": ""},
		{"id": &"climb", "label": "Climb through", "enabled": false, "reason": "Window is closed"}])
	check_eq(txt, "E: Open window   [5] Smash window   [6] Climb through (Window is closed)", "formatter")
	await _teleport(Vector3(-9, 0.1, -4))
	await _settle_occlusion()
	await frames(2)
	check_eq(hud.room_label.text, "Inside: Living Room — House A", "room line")


func test_climb_survives_window_freed_mid_climb() -> void:
	await _teleport(Vector3(-13.3, 0.1, -8))
	await _drive(Vector3.LEFT, 5)
	var win := _window_at(Vector3(-14, 0, -8))
	check(interaction.interact().ok, "opened")
	check(interaction.interact().ok, "climbing")
	check(player.is_busy, "busy")
	await physics_frames(5)
	house.windows.erase(win)
	win.free()
	var done := await wait_until(func(): return not player.is_busy, 120)
	check(done, "busy lock cleared although the window is gone")
	check(player.busy_tween == null, "busy tween released")
	check_lt(player.global_position.x, -14.3, "still landed outside")
	check_near(player.global_position.y, 0.0, 0.15, "on the ground")
	await _drive(Vector3.LEFT, 20)
	check_lt(player.global_position.x, -14.8, "can move again")


func test_climb_costs_stamina() -> void:
	await _teleport(Vector3(-13.3, 0.1, -8))
	await _drive(Vector3.LEFT, 5)
	var win := _window_at(Vector3(-14, 0, -8))
	win.open_window()
	await physics_frames(3)
	var st0: float = player.stats.get_value(Character.STAMINA)
	check(interaction.interact().ok, "climbing")
	await wait_until(func(): return not player.is_busy, 120)
	var drop := st0 - player.stats.get_value(Character.STAMINA)
	check_gt(drop, 5.0, "climb drained stamina (0.8 s x 12/s ≈ 9.6), got %.1f" % drop)
	check_lt(drop, 14.0, "but not absurdly")


func test_window_behind_wall_is_not_targetable() -> void:
	# Outside, west of the bedroom W window, with an extra 0.2 m wall in between.
	var block := StaticBody3D.new()
	block.collision_layer = 1
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.2, 2.7, 3.0)
	shape.shape = bs
	shape.position = Vector3(0, 1.35, 0)
	block.add_child(shape)
	block.position = Vector3(-14.7, 0, -8)
	scene.add_child(block)
	await _teleport(Vector3(-15.4, 0.1, -8))
	await physics_frames(5)
	var win := _window_at(Vector3(-14, 0, -8))
	check(interaction.current_target != Interactable.of(win), "window behind a wall is not targeted")
	block.free()
	await physics_frames(5)
	check_eq(interaction.current_target, Interactable.of(win), "targeted once the wall is gone")


func test_door_refused_when_swing_arc_is_blocked() -> void:
	# A zombie-layer body where the leaf would end up (inside, along the hinge).
	var dummy := CharacterBody3D.new()
	dummy.collision_layer = 1 << 2
	dummy.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	shape.shape = cap
	shape.position = Vector3(0, 0.85, 0)
	dummy.add_child(shape)
	dummy.position = Vector3(-11.45, 0, -2.6)
	scene.add_child(dummy)
	await _teleport(Vector3(-11, 0.1, -0.7))
	await physics_frames(3)
	var door := _door_at(Vector3(-11.45, 0, -2))
	var act: Dictionary = interaction.current_actions[0]
	check(not act.enabled and act.reason == "Blocked", "open listed as Blocked")
	var refused := []
	var cb := func(_a, _t, reason): refused.append(reason)
	EventBus.interaction_refused.connect(cb)
	var r := interaction.interact()
	EventBus.interaction_refused.disconnect(cb)
	check(not r.ok and r.reason == "Blocked", "open refused with reason Blocked")
	check_eq(door.state, &"closed", "state unchanged")
	check_eq(refused, ["Blocked"], "interaction_refused emitted")
	var hud := scene.get_node("HUD")
	await frames(1)
	check_eq(hud.notice_label.text, "Blocked", "HUD shows the refusal reason")
	dummy.free()
	await physics_frames(3)
	check(interaction.interact().ok, "opens once the arc is clear")
	# Player in the doorway: closing is refused.
	await physics_frames(35)
	await _teleport(Vector3(-11, 0.1, -2.0))
	await physics_frames(3)
	check_eq(interaction.current_target, Interactable.of(door), "door targeted from the doorway")
	r = interaction.interact()
	check(not r.ok and r.reason == "Blocked", "close refused while standing in the doorway")
	check_eq(door.state, &"open", "still open")


func test_room_threshold_has_hysteresis() -> void:
	var door := _door_at(Vector3(-11.45, 0, -2))
	door.open_door(null)
	await physics_frames(30)
	var events := [0]
	var cb := func(_r, _b): events[0] += 1
	await _teleport(Vector3(-11, 0.1, -1.94))
	await _settle_occlusion()
	EventBus.player_room_changed.connect(cb)
	for i in 12:
		var z := -2.06 if i % 2 == 0 else -1.94
		player.global_position = Vector3(-11, 0.1, z)
		player.velocity = Vector3.ZERO
		await physics_frames(2)
		occl.update_now()
	EventBus.player_room_changed.disconnect(cb)
	check_lt(float(events[0]), 2.5, "shuffling across the threshold fired %d room changes (<= 2 allowed)" % events[0])
	# Walking well inside / well outside still switches.
	await _teleport(Vector3(-11, 0.1, -3.0))
	await _settle_occlusion()
	check(occl.current_room != null, "deep inside -> in a room")
	await _teleport(Vector3(-11, 0.1, 0.5))
	await _settle_occlusion()
	check(occl.current_room == null, "well outside -> no room")


func test_prompt_hidden_while_busy() -> void:
	var hud := scene.get_node("HUD")
	await _teleport(Vector3(-13.3, 0.1, -8))
	await _drive(Vector3.LEFT, 5)
	var win := _window_at(Vector3(-14, 0, -8))
	win.open_window()
	await physics_frames(3)
	await frames(1)
	check(hud.prompt_label.text.begins_with("E: Climb"), "prompt visible before climbing")
	interaction.interact()
	await physics_frames(3)
	await frames(1)
	check_eq(hud.prompt_label.text, "", "prompt hidden while busy")
	await wait_until(func(): return not player.is_busy, 120)
