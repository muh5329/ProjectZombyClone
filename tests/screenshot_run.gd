extends SceneTree
## Plays the main scene with REAL input actions (Input.action_press) and saves
## screenshots to tests/output/. Needs a display (use xvfb-run on CI).
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/screenshot_run.gd
##
## Exit code 1 if anything looks wrong (player didn't move, etc.).

const OUT := "res://tests/output/"

var _problems: PackedStringArray = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scene: PackedScene = load("res://maps/test_ground.tscn")
	if scene == null:
		printerr("SCREENSHOT_RUN: failed to load main scene")
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	await _frames(20)
	var player: Node3D = inst.get_node("Player")
	var cam: Node3D = inst.get_node("IsometricCamera")
	if OS.get_environment("SCREENSHOT_ONLY") in ["world", "streaming"]:
		# Dev shortcut: only the generated-world sections (Rounds 11-12;
		# "streaming" = Round 12 alone).
		inst.queue_free()
		await process_frame
		if OS.get_environment("SCREENSHOT_ONLY") == "world":
			await _round11()
		await _round12()
		_finish()
		return
	if OS.get_environment("SCREENSHOT_ONLY") == "r9":
		# Dev shortcut: only the Round-9 section (not used by screenshots.sh).
		var sp: Node = inst.get_node("Zombies")
		sp.auto_spawn = false
		await _round9(inst, player, cam, sp, inst.get_node("HUD"))
		_finish()
		return

	await _shot("01_spawn")

	# Jog forward (W) for 1.5 s using the real action.
	var p0 := player.global_position
	_press(&"move_forward")
	await _frames(90)
	_release(&"move_forward")
	await _frames(10)
	if (player.global_position - p0).length() < 2.0:
		_problems.append("player did not jog forward via input map")
	await _shot("02_after_jog")

	# Rotate the camera twice (Q) and move "forward" again: should be a
	# different world direction (camera-relative).
	var yaw_before: float = cam.target_yaw_degrees()
	await _tap(&"camera_rotate_left")
	await _frames(5)
	await _tap(&"camera_rotate_left")
	await _frames(60)
	if is_equal_approx(cam.target_yaw_degrees(), yaw_before):
		_problems.append("camera did not rotate via input map")
	var p1 := player.global_position
	_press(&"move_forward")
	await _frames(60)
	_release(&"move_forward")
	await _frames(5)
	var d_new := (player.global_position - p1).normalized()
	var d_old := (player.global_position - p0).normalized()
	if d_new.dot(d_old) > 0.7:
		_problems.append("movement not camera-relative after rotation")
	await _shot("03_rotated_camera")

	# Zoom out twice.
	await _tap(&"camera_zoom_out")
	await _frames(5)
	await _tap(&"camera_zoom_out")
	await _frames(60)
	await _shot("04_zoomed_out")

	# Sprint until exhausted (Shift + A; left = away from the house).
	_press(&"sprint")
	_press(&"move_left")
	await _frames(60 * 7)
	if not player.exhausted:
		_problems.append("player did not become exhausted after 7 s sprint")
	await _shot("05_exhausted")
	_release(&"sprint")
	_release(&"move_left")

	# Sneak
	_press(&"sneak")
	_press(&"move_back")
	await _frames(45)
	await _shot("06_sneak")
	_release(&"sneak")
	_release(&"move_back")

	# --- Round 2: house, door, cutaway, window climb -----------------------
	# House A occupies x -14..-4, z -10..-2; front door centre world (-11, -2).
	var occl: Node = inst.get_node("OcclusionManager")
	var house: Node = inst.get_node("Buildings/HouseA")
	# Back to the default heading (45°) and zoom so the framing is canonical.
	await _tap(&"camera_rotate_right")
	await _frames(5)
	await _tap(&"camera_rotate_right")
	await _tap(&"camera_zoom_in")
	await _frames(5)
	await _tap(&"camera_zoom_in")
	player.global_position = Vector3(-11, 0.1, -0.6)
	await _frames(60)
	if not is_equal_approx(cam.target_yaw_degrees(), 45.0):
		_problems.append("camera not back at 45° (got %.0f)" % cam.target_yaw_degrees())
	var interaction: Node = player.get_node("Interaction")
	if interaction.current_target == null:
		_problems.append("no interaction target in front of the front door")
	await _shot("07_door_prompt")
	await _tap(&"interact")
	await _frames(30)
	var front_door: Node = null
	for d in house.doors:
		if (d.global_position - Vector3(-11.45, 0, -2)).length() < 0.2:
			front_door = d
	if front_door == null or not front_door.is_open():
		_problems.append("front door did not open via E")
	# W + D at camera yaw 45° is straight north (-Z): through the doorway.
	_press(&"move_forward")
	_press(&"move_right")
	await _frames(55)
	_release(&"move_forward")
	_release(&"move_right")
	await _frames(30)
	if occl.current_room == null:
		_problems.append("player not detected inside a room after walking through the door (pos %s)" % str(player.global_position))
	var roof_hidden := false
	for r in house.get_roofs():
		roof_hidden = roof_hidden or occl.state_of(r) == &"hidden"
	if not roof_hidden:
		_problems.append("roof not hidden while inside")
	await _shot("08_inside_cutaway")

	# West window of the living room: world (-14, -4). Stand 0.7 m inside.
	player.global_position = Vector3(-13.3, 0.1, -4)
	await _frames(20)
	await _tap(&"interact")  # Open window
	await _frames(25)
	await _shot("09_window_open")
	await _tap(&"interact")  # Climb through
	await _frames(70)
	if player.global_position.x > -14.3:
		_problems.append("player did not end up outside after climbing (x=%.2f)" % player.global_position.x)
	if occl.current_room != null:
		_problems.append("still 'inside' after climbing out")
	await _frames(20)
	await _shot("10_after_climb")

	# --- Round 3: zombies --------------------------------------------------
	# Into the open field south-west of the house, zoomed out, with a small
	# group of shamblers nearby (facing away) so several are in frame.
	var spawner: Node = inst.get_node("Zombies")
	var hud: Node = inst.get_node("HUD")
	if spawner.zombies.size() < 10:
		_problems.append("map spawner placed %d zombies (expected 10)" % spawner.zombies.size())
	# R8.5: at the default zoom (14) so the zombies read as hunched
	# shamblers, not specks.
	player.global_position = Vector3(-22, 0.1, 4)
	var group_origin := player.global_position + Vector3(-4, 0, -4)
	var jitter := RandomNumberGenerator.new()
	jitter.seed = 7
	for i in 7:
		var off := Vector3(float(i % 4) * 1.5 - 2.2 + jitter.randf_range(-0.4, 0.4), 0.0,
			float(i / 4) * 1.6 - 0.8 + jitter.randf_range(-0.4, 0.4))
		var z: Node3D = spawner.spawn_at(group_origin + off)
		var yaw := PI * 0.5 + jitter.randf_range(-0.6, 0.6)  # roughly west, away from the player
		z.snap_facing(yaw)
	await _frames(60)
	await _shot("11_zombies_overview")

	# One zombie in front of the player: it must spot and chase within 1 s.
	var chaser: Node3D = spawner.spawn_at(player.global_position + Vector3(-4.5, 0, 0))
	chaser.face_toward(player.global_position)
	chaser.snap_facing(chaser.movement.facing)
	var chasing := false
	for i in 90:
		await physics_frame
		if chaser.state() == &"chase":
			chasing = true
			break
	if not chasing:
		_problems.append("zombie did not chase the player (state %s)" % chaser.state())
	await _frames(30)
	if not String(hud.danger_label.text).begins_with("!"):
		_problems.append("HUD danger indicator missing (got '%s')" % hud.danger_label.text)
	await _shot("12_chase")

	# Stand still until it bites: damage flash + health bar drop.
	var hp0: float = player.health.health
	var bitten := false
	for i in 60 * 8:
		await physics_frame
		if player.health.health < hp0:
			bitten = true
			break
	if not bitten:
		_problems.append("zombie never damaged the player")
	if hud.flash_strength() < 0.05:
		_problems.append("damage flash not visible after the hit (strength %.2f)" % hud.flash_strength())
	await _shot("13_damage_flash")
	# Back to the zoom the later sections were framed with.
	await _tap(&"camera_zoom_out")
	await _frames(5)
	await _tap(&"camera_zoom_out")

	await _round4(inst, player, cam, spawner, hud)
	await _round5(inst, player, cam, spawner, hud)
	await _round6(inst, player, cam, spawner, hud)
	await _round7(inst, player, cam, spawner, hud)
	await _round8(inst, player, cam, spawner, hud)
	await _round85(inst, player, cam, spawner, hud)
	await _round9(inst, player, cam, spawner, hud)
	await _round10(inst, player, cam, hud)
	await _round11()
	await _round12()
	_finish()


func _finish() -> void:
	if _problems.is_empty():
		print("SCREENSHOT_RUN: OK")
		quit(0)
	else:
		for p in _problems:
			printerr("SCREENSHOT_RUN PROBLEM: " + p)
		quit(1)


# --- Round 4: pickup, aim, swing, knockdown, injuries, bandage -------------
func _round4(inst: Node, player: Node3D, cam: Node3D, spawner: Node, hud: Node) -> void:
	var combat: Node = player.get_node("Combat")
	var injuries: Node = player.get_node("Injuries")
	# Deterministic hits / knockdowns / wounds for the evidence run.
	combat.rng.seed = 20260922
	injuries.rng.seed = 7
	# Clear the stage: every zombie so far goes away; top the player up.
	for z in get_nodes_in_group(&"zombie"):
		z.queue_free()
	await _frames(2)
	player.get_node("Health").heal(100.0)
	player.get_node("Stats").set_value(&"stamina", 100.0)
	await _tap(&"camera_zoom_in")
	await _frames(5)
	await _tap(&"camera_zoom_in")
	# Pick up the bat in the living room with E.
	player.global_position = Vector3(-6.5, 0.1, -2.5)
	player.movement.facing = 0.0  # face -Z (toward the bat)
	await _frames(20)
	await _tap(&"interact")
	await _frames(10)
	if combat.weapon().id != &"baseball_bat":
		_problems.append("bat not picked up / equipped via E (weapon %s)" % combat.weapon().id)
	# Out into the open (closest zoom): three zombies screen-right, in reach.
	await _tap(&"camera_zoom_in")
	player.global_position = Vector3(10, 0.1, 12)
	await _frames(30)
	var camera: Camera3D = cam.camera
	# Aim to screen-right so the arc and the zombies read side by side.
	var fwd := camera.global_basis.x
	fwd.y = 0.0
	fwd = fwd.normalized()
	var zs: Array = []
	for a in [-0.9, 0.0, 0.9]:
		var d := fwd.rotated(Vector3.UP, a)
		var z: Node3D = spawner.spawn_at(player.global_position + d * 1.5)
		z.face_toward(player.global_position)
		z.snap_facing(z.movement.facing)
		# Staging only: they notice the player after the aim shot, so the
		# spacing (and the arc under them) stays readable in 14.
		z.senses.enabled = false
		zs.append(z)
	await _frames(2)
	# Aim (RMB) at the middle one with the mouse.
	var target_screen := camera.unproject_position(player.global_position + fwd * 1.25)
	_mouse_to(target_screen)
	_press(&"aim")
	await _frames(12)
	_mouse_to(target_screen)
	await _frames(6)
	if not combat.aiming:
		_problems.append("RMB did not enter aim mode")
	if combat.aim_direction.dot(fwd) < 0.9:
		_problems.append("aim does not follow the mouse (aim %s, want %s)" % [str(combat.aim_direction), str(fwd)])
	if combat.in_reach < 2:
		_problems.append("expected >= 2 zombies in reach while aiming (got %d)" % combat.in_reach)
	if not String(hud.aim_label.text).begins_with("Aiming"):
		_problems.append("HUD aim label missing (got '%s')" % hud.aim_label.text)
	await _shot("14_aim_arc")
	for z in zs:
		z.senses.enabled = true
	# Hold LMB ~0.4 s, release: the bat sweeps the arc.
	_press(&"attack")
	await _frames(24)
	_release(&"attack")
	var active := false
	for i in 40:
		await physics_frame
		if combat.is_active():
			active = true
			break
	if not active:
		_problems.append("swing never reached the active window")
	elif combat.last_hits.is_empty():
		_problems.append("bat swing hit nobody")
	else:
		var flashing := false
		for h in combat.last_hits:
			flashing = flashing or h.target.visual.is_hit_flashing()
		if not flashing:
			_problems.append("no hit flash on the struck zombie")
	await _shot("15_swing_hit")
	# Shove (Space) / swing until one of them is on the ground.
	var downed: Node3D = null
	for attempt in 8:
		for i in 60:
			await physics_frame
			if combat.phase == 0:
				break
		for z in zs:
			if is_instance_valid(z) and not z.dead and z.state() == &"knocked_down":
				downed = z
		if downed:
			break
		var near: Node3D = null
		for z in zs:
			if is_instance_valid(z) and not z.dead:
				near = z
				break
		if near == null:
			break
		_mouse_to(camera.unproject_position(near.global_position))
		await _frames(2)
		await _tap(&"shove" if attempt % 2 == 0 else &"attack")
		for i in 30:
			await physics_frame
			if near.dead or near.state() == &"knocked_down":
				break
		if is_instance_valid(near) and not near.dead and near.state() == &"knocked_down":
			downed = near
			break
	if downed == null:
		_problems.append("no zombie was knocked down by shove / bat")
	await _frames(8)
	await _shot("16_knockdown")
	_release(&"aim")
	for z in zs:
		if is_instance_valid(z):
			z.queue_free()
	await _frames(5)
	# Climb through the smashed living-room window: glass laceration
	# (40 % in play; certain here so the evidence is deterministic).
	injuries.profile = injuries.profile.duplicate()
	injuries.profile.glass_laceration_chance = 1.0
	player.get_node("Health").heal(100.0)
	player.global_position = Vector3(-13.3, 0.1, -4)
	player.movement.facing = PI * 0.5  # face -X (the window)
	await _frames(20)
	var n_before: int = injuries.injuries.size()
	var interaction: Node = player.get_node("Interaction")
	var idx := -1
	for i in interaction.current_actions.size():
		if interaction.current_actions[i].id == &"smash":
			idx = i
	if idx < 0:
		_problems.append("no smash action on the west window")
	else:
		await _tap(StringName("action_%d" % (idx + 1)))
		await _frames(20)
		await _tap(&"interact")
		await _frames(70)
	var glass := false
	for inj in injuries.injuries:
		glass = glass or inj.type == 1  # laceration
	if injuries.injuries.size() <= n_before or not glass:
		_problems.append("smashed-window climb did not lacerate (injuries %d → %d)" % [n_before, injuries.injuries.size()])
	if not String(hud.injury_label.text).contains("BLEEDING"):
		_problems.append("HUD injury list shows no bleeding wound: '%s'" % hud.injury_label.text)
	# Step away from the wall so the player is in plain view.
	player.global_position = Vector3(-17.5, 0.1, -0.5)
	await _frames(20)
	await _shot("17_injury_panel")
	# B: bandage the worst bleeding wound (4 s). Round 5: bandages are
	# consumables — stage two in the pack (as if looted from a bathroom).
	player.inventory.add_id(&"bandage", 2)
	await _tap(&"bandage")
	await _frames(60)
	if not injuries.is_bandaging():
		_problems.append("B did not start bandaging")
	if not String(hud.notice_label.text).begins_with("Bandaging"):
		_problems.append("HUD bandaging notice missing (got '%s')" % hud.notice_label.text)
	await _shot("18_bandaging")
	for i in 60 * 4:
		await physics_frame
		if not injuries.is_bandaging():
			break
	var any_bandaged := false
	for inj in injuries.injuries:
		any_bandaged = any_bandaged or inj.bandaged
	if not any_bandaged:
		_problems.append("no wound bandaged after 4 s")


# --- Round 5: containers, loot window, corpse search ----------------------
func _round5(inst: Node, player: Node3D, cam: Node3D, spawner: Node, hud: Node) -> void:
	var window: Node = inst.get_node("LootWindow")
	# The showcase cabinet: its (food-heavy, 2-3 roll) table always has
	# something on the default world seed (unit-tested).
	var cabinet: Node3D = null
	for c in get_nodes_in_group(&"container"):
		if c.persist_id == "HouseA/kitchen/0":
			cabinet = c
	if cabinet == null:
		_problems.append("kitchen cabinet HouseA/kitchen/0 missing")
		return
	player.get_node("Health").heal(100.0)
	# Stand in front of the cabinet (front faces +X), facing it.
	var front: Vector3 = cabinet.global_basis.z
	player.global_position = cabinet.global_position + front * 1.05 + Vector3.UP * 0.1
	player.movement.facing = atan2(front.x, front.z)  # yaw facing -front
	await _frames(30)
	var interaction: Node = player.get_node("Interaction")
	if interaction.current_target == null or interaction.current_target.body() != cabinet:
		_problems.append("kitchen cabinet not targeted (target %s)" % str(interaction.current_target))
	elif not String(interaction.current_actions[0].label).begins_with("Search"):
		_problems.append("cabinet action is '%s'" % interaction.current_actions[0].label)
	await _tap(&"interact")
	await _frames(10)
	if not player.is_busy:
		_problems.append("E did not start rummaging the cabinet")
	for i in 90:
		await physics_frame
		if cabinet.is_open():
			break
	await _frames(20)
	if not window.is_open():
		_problems.append("loot window did not open for the kitchen cabinet")
	elif cabinet.inventory.is_empty():
		_problems.append("kitchen cabinet rolled empty (seed 1337)")
	else:
		# Real mouse click on the first container row: moves the stack.
		var row: Control = window.row_node(&"container", 0)
		var at: Vector2 = row.get_viewport().get_final_transform() * row.get_global_rect().get_center()
		var n0: int = player.inventory.item_count()
		_mouse_to(at)
		await _frames(2)
		await _click(at)
		await _frames(10)
		if player.inventory.item_count() <= n0:
			_problems.append("clicking a loot row did not move the item")
		_mouse_to(Vector2(640, 600))
	await _frames(10)
	await _shot("19_loot_window")
	# Walk away: the window closes (> 2 m).
	_press(&"move_back")
	await _frames(60)
	_release(&"move_back")
	await _frames(10)
	if window.is_open():
		_problems.append("loot window still open after walking away")
	# A zombie dies in the open; search its pockets.
	player.global_position = Vector3(10, 0.1, 12)
	await _frames(20)
	var z: Node3D = spawner.spawn_at(player.global_position + Vector3(0.6, 0, -1.2))
	z.senses.enabled = false
	await _frames(5)
	z.take_damage(999.0, player, {})
	await _frames(10)
	var corpse: Node3D = null
	for c in get_nodes_in_group(&"corpse"):
		corpse = c
	if corpse == null:
		_problems.append("no corpse after killing the zombie")
		return
	corpse.inventory.add_id(&"rag", 1)  # staging: never an empty pocket shot
	var to: Vector3 = corpse.global_position - player.global_position
	player.movement.facing = atan2(-to.x, -to.z)
	await _frames(10)
	await _tap(&"interact")
	for i in 120:
		await physics_frame
		if corpse.is_open():
			break
	await _frames(15)
	if not window.is_open() or String(window.container_title.text) != "Zombie corpse":
		_problems.append("corpse loot window not open (title '%s')" % window.container_title.text)
	await _shot("20_corpse_loot")
	await _tap(&"interact")
	await _frames(5)
	if window.is_open():
		_problems.append("E did not close the loot window")


# --- Round 6: backpack, inventory screen, hotbar, encumbrance --------------
func _round6(inst: Node, player: Node3D, _cam: Node3D, _spawner: Node, hud: Node) -> void:
	var window: Node = inst.get_node("LootWindow")
	var eq: Node = player.get_node("Equipment")
	var bagw: Node3D = inst.get_node_or_null("Items/Backpack")
	if bagw == null:
		_problems.append("no school bag in the bedroom")
		return
	player.get_node("Health").heal(100.0)
	player.global_position = Vector3(-11.1, 0.1, -7.2)
	var to: Vector3 = bagw.global_position - player.global_position
	player.movement.facing = atan2(-to.x, -to.z)
	await _frames(20)
	await _tap(&"interact")
	await _frames(10)
	var bag = player.inventory.find(&"backpack")
	if bag == null:
		_problems.append("E did not pick up the school bag")
		return
	# Staging: a few things worth carrying (as if looted).
	player.inventory.add_id(&"hammer", 1)
	player.inventory.add_id(&"kitchen_knife", 1)
	player.inventory.add_id(&"canned_beans", 2)
	player.inventory.add_id(&"water_bottle", 1)
	player.inventory.add_id(&"bandage", 2)
	await _tap(&"toggle_inventory")
	await _frames(5)
	if not window.is_visible_screen():
		_problems.append("Tab did not open the inventory screen")
	# Wear the bag through the row's context menu (real right-click).
	var row: Control = window.row_for(&"player", bag)
	if row == null:
		_problems.append("no inventory row for the school bag")
	else:
		var at: Vector2 = row.get_viewport().get_final_transform() * row.get_global_rect().get_center()
		_mouse_to(at)
		await _frames(2)
		_right_click(at)
		await _frames(5)
		if not window.context_menu.visible:
			_problems.append("right-click did not open the context menu")
		var idx := -1
		for i in window.context_menu.item_count:
			if window.context_menu.get_item_text(i) == "Wear on back":
				idx = i
		window.context_menu.hide()
		if idx >= 0:
			window.context_menu.id_pressed.emit(idx)
		_mouse_to(Vector2(640, 600))
	await _frames(5)
	if eq.back_bag() != bag:
		_problems.append("the school bag is not worn")
	bag.contents.add_id(&"nails", 40)
	bag.contents.add_id(&"rag", 2)
	bag.contents.add_id(&"duct_tape", 1)
	# Hotbar: knife 1, hammer 2, bat 3 (if still carried); key 2 draws the hammer.
	var knife = player.inventory.find(&"kitchen_knife")
	var hammer = player.inventory.find(&"hammer")
	eq.assign_hotbar(0, knife)
	eq.assign_hotbar(1, hammer)
	for w in player.held_weapons():
		if w.id() == &"baseball_bat":
			eq.assign_hotbar(2, w)
	await _tap(&"hotbar_2")
	await _frames(10)
	if eq.primary() != hammer:
		_problems.append("hotbar key 2 did not equip the hammer")
	if hud.hotbar.slot_name(1) != "Hammer" or not hud.hotbar.slot_equipped(1):
		_problems.append("HUD hotbar does not show the equipped hammer")
	if window.player_tabs().size() != 2:
		_problems.append("no School Bag tab in the container column")
	window.refresh()
	await _frames(10)
	await _shot("21_inventory_screen")
	await _tap(&"toggle_inventory")
	await _frames(5)
	# Overloaded: planks from the garage (staging), then jog with real input.
	player.global_position = Vector3(-6, 0.1, 4)
	player.inventory.add_id(&"plank", 4)
	await _frames(5)
	var enc: Node = player.get_node("Encumbrance")
	if enc.state != &"overloaded":
		_problems.append("not overloaded after the planks (%s, %.1f kg)" % [enc.state, enc.weight])
	_press(&"sprint")
	_press(&"move_right")
	await _frames(50)
	var spd: float = player.speed()
	await _shot("22_overloaded")
	_release(&"move_right")
	_release(&"sprint")
	await _frames(5)
	if spd > 3.4 * 0.7:
		_problems.append("overloaded player not slowed (%.2f m/s)" % spd)
	if not String(hud.weight_label.text).contains("Overloaded"):
		_problems.append("HUD weight readout missing 'Overloaded': '%s'" % hud.weight_label.text)
	if player.sprint_denied_reason() != "Too heavy":
		_problems.append("sprint not refused as Too heavy")


# --- Round 7: clock + moodles, eating, night ---------------------------------
func _round7(inst: Node, player: Node3D, cam: Node3D, spawner: Node, hud: Node) -> void:
	var tm: Node = root.get_node("TimeManager")
	var window: Node = inst.get_node("LootWindow")
	var needs: Node = player.get_node("Needs")
	player.inventory.remove_id(&"plank", 4)
	player.get_node("Health").heal(100.0)
	# Keep the roaming zombies out of the kitchen for these shots.
	for z in root.get_tree().get_nodes_in_group(&"zombie"):
		z.get_node("Senses").set("enabled", false)
		z.set_physics_process(false)
		z.hostile = false
	# Speed keys (F7 = 2×, F6 = back to 1×) through the input map.
	await _tap(&"time_speed_2")
	await _frames(3)
	if not is_equal_approx(Engine.time_scale, 2.0):
		_problems.append("F7 did not fast-forward (time_scale %.1f)" % Engine.time_scale)
	await _tap(&"time_speed_1")
	await _frames(3)
	# Kitchen, in front of the sink; six hours later: hungry and thirsty.
	player.global_position = Vector3(-5.45, 0.1, -6.7)
	player.movement.facing = atan2(-1.0, 0.0)  # face +X (the sink)
	await _frames(20)
	var before_minutes: float = tm.now()
	tm.advance(8.0 * 60.0 + 10.0)
	await _frames(10)
	var labels: PackedStringArray = hud.moodle_list.labels()
	if not ((labels.has("Hungry") or labels.has("Very Hungry")) and (labels.has("Thirsty") or labels.has("Parched"))):
		_problems.append("moodles missing after 8 h (%s)" % str(labels))
	if tm.now() - before_minutes < 490.0 or hud.clock.shown_time() != tm.clock_text():
		_problems.append("clock did not follow the 8 h advance (%s vs %s)" % [hud.clock.shown_time(), tm.clock_text()])
	await _shot("23_moodles_clock")
	# Eat the beans through the inventory context menu (the knife opens them).
	await _tap(&"toggle_inventory")
	await _frames(5)
	var beans = player.inventory.find(&"canned_beans")
	var row: Control = window.row_for(&"player", beans) if beans != null else null
	if row == null:
		_problems.append("no canned beans row")
	else:
		var at: Vector2 = row.get_viewport().get_final_transform() * row.get_global_rect().get_center()
		_mouse_to(at)
		await _frames(2)
		_right_click(at)
		await _frames(5)
		var idx := -1
		for i in window.context_menu.item_count:
			if window.context_menu.get_item_text(i) == "Eat":
				idx = i
		window.context_menu.hide()
		if idx < 0:
			_problems.append("no Eat entry in the context menu")
		else:
			window.context_menu.id_pressed.emit(idx)
		_mouse_to(Vector2(640, 600))
	await _frames(3)
	await _tap(&"toggle_inventory")
	await _frames(60)
	if not player.is_busy or not hud.action_bar.visible:
		_problems.append("not eating (busy %s, bar %s)" % [player.is_busy, hud.action_bar.visible])
	if not String(hud.notice_label.text).begins_with("Eating Canned Beans"):
		_problems.append("eating notice missing ('%s')" % hud.notice_label.text)
	await _shot("25_eating")
	var h0: float = needs.value(&"hunger")
	var guard := 0
	while player.is_busy and guard < 600:
		await _frames(10)
		guard += 10
	if needs.value(&"hunger") > h0 - 12.0:
		_problems.append("beans did not reduce hunger (%.1f → %.1f)" % [h0, needs.value(&"hunger")])
	# Night: 23:00 outside the front door, house lights on.
	var dn: Node = inst.get_node("DayNight")
	var day_energy: float = dn.sun_energy()
	tm.set_time_of_day(23, 0)
	player.global_position = Vector3(-8.5, 0.1, 1.5)
	await _tap(&"camera_zoom_out")
	await _frames(60)
	if dn.sun_energy() >= day_energy * 0.5:
		_problems.append("night not darker (%.2f vs %.2f)" % [dn.sun_energy(), day_energy])
	await _shot("24_night")


# --- Round 8: noise rings, window smash, shout, F4 sound debug ---------------
func _round8(inst: Node, player: Node3D, _cam: Node3D, spawner: Node, hud: Node) -> void:
	var tm: Node = root.get_node("TimeManager")
	var sm: Node = root.get_node("SoundManager")
	var rings: Node = inst.get_node("NoiseRings")
	var house: Node = inst.get_node("Buildings/HouseA")
	tm.set_time_of_day(13, 0)
	for z in root.get_tree().get_nodes_in_group(&"zombie"):
		z.queue_free()
	await _frames(5)
	player.get_node("Health").heal(100.0)
	player.stats.set_value(&"stamina", 100.0)
	# A loose group south of the house, facing away (+Z).
	var spots := [Vector3(-12, 0, 7), Vector3(-8, 0, 9), Vector3(-3.5, 0, 6.5), Vector3(-15.5, 0, 10), Vector3(-6, 0, 13)]
	var zs: Array = []
	for p in spots:
		var z: Node3D = spawner.spawn_at(p)
		z.snap_facing(PI)
		zs.append(z)
	# Sprint east along the front of the house (real input: S + D at the
	# 45° camera is +X), then smash the living-room window from outside.
	var inj: Node = player.get_node("Injuries")
	inj.injuries.clear()
	inj.call(&"_changed")
	player.global_position = Vector3(-14.5, 0.1, -0.6)
	player.velocity = Vector3.ZERO
	await _frames(10)
	_press(&"sprint")
	_press(&"move_back")
	_press(&"move_right")
	await _frames(75)
	if rings.active_count() == 0 or not rings.active_radii().has(14.0):
		_problems.append("no 14 m sprint rings (%s)" % str(rings.active_radii()))
	_release(&"move_back")
	_release(&"move_right")
	_release(&"sprint")
	await _frames(3)
	player.global_position = Vector3(-7, 0.1, -1.0)
	player.velocity = Vector3.ZERO
	player.movement.facing = 0.0  # face -Z (the window)
	await _frames(4)
	var interaction: Node = player.get_node("Interaction")
	var win: Node = null
	for w in house.windows:
		if (w.global_position - Vector3(-7, 0, -2)).length() < 0.3:
			win = w
	var tgt: Node = interaction.current_target
	if tgt == null or (tgt != win and tgt.get_parent() != win):
		_problems.append("living-room window not targeted for the smash (%s)" % str(interaction.current_target))
	await _tap(&"action_2")  # [2] Smash window
	await _frames(4)
	# Slow motion for the shot: the ring (real-time animation at the
	# renderer's ~7 fps under Xvfb) is caught mid-expansion.
	Engine.time_scale = 0.05
	await _frames(6)
	if win == null or win.state != &"smashed":
		_problems.append("window not smashed via key 5")
	var radii: Array = rings.active_radii()
	if not radii.has(20.0):
		_problems.append("no 20 m ring for the smash (%s)" % str(radii))
	var turned := 0
	for z in zs:
		if is_instance_valid(z) and z.state() == &"investigate":
			turned += 1
	if turned < 3:
		_problems.append("only %d zombies reacted to the smash" % turned)
	if not hud.noise_meter.is_loud():
		_problems.append("HUD noise meter not LOUD after the smash")
	await _shot("26_noise_rings")
	Engine.time_scale = 1.0
	# F4 debug overlay: every sound + hearing lines; shout (H) to call them.
	await _frames(90)
	await _tap(&"toggle_sound_debug")
	await _frames(2)
	if not root.get_node("GameManager").sound_debug:
		_problems.append("F4 did not enable the sound debug overlay")
	await _tap(&"shout")
	await _frames(12)
	var dbg: Node = inst.get_node("SoundDebug")
	if dbg.drawn_circles == 0 or dbg.drawn_lines == 0:
		_problems.append("debug overlay drew nothing (circles %d, lines %d)" % [dbg.drawn_circles, dbg.drawn_lines])
	if sm.stats.events == 0:
		_problems.append("SoundManager saw no events")
	await _shot("27_debug_sound")
	await _tap(&"toggle_sound_debug")
	await _frames(2)


# --- Round 8.5: procedural people, zombies and parked vehicles ---------------
func _round85(inst: Node, player: Node3D, cam: Node3D, spawner: Node, _hud: Node) -> void:
	var tm: Node = root.get_node("TimeManager")
	tm.set_time_of_day(13, 0)
	for z in root.get_tree().get_nodes_in_group(&"zombie"):
		z.queue_free()
	await _frames(5)
	player.get_node("Health").invulnerable = true
	player.get_node("Health").heal(100.0)
	# Close-up: the survivor with a bat, a shambling crowd of townspeople.
	player.global_position = Vector3(-24, 0.1, 16)
	player.velocity = Vector3.ZERO
	player.movement.facing = 0.0
	for i in 4:
		await _tap(&"camera_zoom_in")
		await _frames(3)
	var looks := {}
	var ring := [Vector3(-2.6, 0, -2.2), Vector3(-1.0, 0, -3.3), Vector3(0.8, 0, -3.4), Vector3(2.5, 0, -2.4),
		Vector3(-3.4, 0, -0.4), Vector3(3.3, 0, -0.8), Vector3(1.8, 0, -5.0)]
	for off in ring:
		var z: Node3D = spawner.spawn_at(player.global_position + off)
		z.face_toward(player.global_position)
		z.snap_facing(z.movement.facing)
		looks[z.visual.model.appearance.key()] = true
	if looks.size() < 5:
		_problems.append("zombie crowd not varied (%d looks)" % looks.size())
	await _frames(70)
	var model: Node = player.get_node("Visual/Model")
	if model == null or model.skeleton == null:
		_problems.append("player has no character model")
	var moving := 0
	for z in root.get_tree().get_nodes_in_group(&"zombie"):
		if z.visual.clip() in [&"z_walk", &"z_chase", &"z_attack"]:
			moving += 1
	if moving < 3:
		_problems.append("zombies not shambling toward the player (%d)" % moving)
	await _shot("28_characters_closeup")
	for z in root.get_tree().get_nodes_in_group(&"zombie"):
		z.queue_free()
	await _frames(3)
	# The street: parked cars incl. the police car, zoomed out like ref 2.
	player.global_position = Vector3(0.5, 0.1, 25)
	player.velocity = Vector3.ZERO
	for i in 6:
		await _tap(&"camera_zoom_out")
		await _frames(3)
	var wander := [Vector3(-3, 0, 20), Vector3(2, 0, 22), Vector3(-1.5, 0, 29), Vector3(4, 0, 31),
		Vector3(-4.5, 0, 25), Vector3(1, 0, 17), Vector3(5, 0, 27), Vector3(-2, 0, 33)]
	for p in wander:
		var z: Node3D = spawner.spawn_at(p)
		z.snap_facing(float(int(p.x * 7.0 + p.z)) * 0.7)
	await _frames(60)
	var vehicles := root.get_tree().get_nodes_in_group(&"vehicle")
	if vehicles.size() < 5:
		_problems.append("expected ≥ 5 parked vehicles (%d)" % vehicles.size())
	if not vehicles.any(func(v): return v.data.livery == &"police"):
		_problems.append("no police car")
	await _shot("29_street_vehicles")
	for i in 2:
		await _tap(&"camera_zoom_in")
		await _frames(3)
	# Night street: the abandoned fire truck's light bar and its red /
	# white light pool, other parked cars dark.
	tm.set_time_of_day(23, 0)
	player.global_position = Vector3(-3.5, 0.1, 31)
	player.velocity = Vector3.ZERO
	await _frames(40)
	var lit := vehicles.filter(func(v): return v.lights_on)
	if lit.is_empty():
		_problems.append("no emergency lights at night")
	if vehicles.any(func(v): return v.lights_on and not v.data.lights_at_night):
		_problems.append("a civilian car lit its lamps")
	await _shot("30_night_street")
	tm.set_time_of_day(13, 0)
	await _frames(5)


# --- Round 9: barricades ---------------------------------------------------------
func _round9(inst: Node, player: Node3D, _cam: Node3D, spawner: Node, hud: Node) -> void:
	var tm: Node = root.get_node("TimeManager")
	tm.set_time_of_day(13, 0)
	for z in root.get_tree().get_nodes_in_group(&"zombie"):
		z.queue_free()
	await _frames(5)
	var house: Node = inst.get_node("Buildings/HouseA")
	# Loaded at run time: -s scripts must not reference gameplay classes
	# statically (they compile before the autoloads exist).
	var bc: Script = load("res://interaction/barricade_component.gd")
	var interaction: Node = player.get_node("Interaction")
	player.get_node("Health").invulnerable = true
	player.get_node("Health").heal(100.0)
	player.stats.set_value(&"stamina", 100.0)
	var win: Node3D = null
	for w in house.windows:
		if (w.global_position - Vector3(-7, 0, -2)).length() < 0.3:
			win = w
	var door: Node3D = null
	for d in house.doors:
		if (d.global_position - Vector3(-11.45, 0, -2)).length() < 0.2:
			door = d
	if win == null or door == null:
		_problems.append("round 9: front window / door not found")
		return
	# Tools and materials (the pack is emptied first: planks weigh 3 kg).
	var inv = player.inventory
	inv.clear()
	inv.add_id(&"hammer", 1)
	inv.add_id(&"plank", 3)
	inv.add_id(&"nails", 10)
	# Outside the living-room window (smashed in round 8), facing it.
	player.global_position = Vector3(-7, 0.1, -1.1)
	player.velocity = Vector3.ZERO
	player.movement.facing = 0.0
	await _tap(&"camera_zoom_in")
	await _frames(10)
	var idx := -1
	for i in interaction.current_actions.size():
		if interaction.current_actions[i].id == &"barricade":
			idx = i
	if idx < 0 or idx > 3 or not interaction.current_actions[idx].enabled:
		_problems.append("round 9: no enabled Barricade action (%s)" % str(interaction.current_actions))
		return
	# Real input: the barricade entry's number key (4-7 = action_1..4).
	await _tap(StringName("action_%d" % (idx + 1)))
	await _frames(80)
	if not player.is_busy or player.busy_context != &"barricade":
		_problems.append("round 9: not hammering after the key press (%s)" % player.busy_context)
	if player.get_node("Visual/Model").current != &"hammer":
		_problems.append("round 9: no hammering animation (%s)" % player.get_node("Visual/Model").current)
	if hud.action_progress() <= 0.0:
		_problems.append("round 9: no busy bar")
	await _shot("33_hammering")
	for i in 3:
		for f in 240:
			if not player.is_busy:
				break
			await _frames(1)
		await _frames(4)
		if i < 2:
			await _tap(&"interact")  # barricaded: E nails the next plank
			await _frames(4)
	if win.barricade_planks() != 3:
		_problems.append("round 9: expected 3 planks on the window (%d)" % win.barricade_planks())
	# Board the rest of the street-facing openings like ref 2 (the front
	# door was left open by earlier sections: shut it first).
	if door.state != &"closed":
		for f in 60:
			if door.close_door(null).ok or door.state == &"closed":
				break
			await _frames(1)
		await _frames(30)
	var b_door = bc.ensure(door)
	for i in 3:
		b_door.add_plank(60.0, 1.0)
	if door.barricade_planks() != 3:
		_problems.append("round 9: front door not boarded (%d, state %s)" % [door.barricade_planks(), door.state])
	var n := 2
	for w in house.windows:
		if w == win or (w.outward.z < 0.5 and w.outward.x < 0.5):
			continue
		var b = bc.ensure(w)
		var side: float = w.side_of(w.global_position + w.outward)
		for i in n:
			b.add_plank(60.0, side)
		n = 4 if n == 2 else 2
	await _tap(&"camera_zoom_out")
	# Between the house and the Wall prop: the prop fades (eye → player).
	player.global_position = Vector3(-4.2, 0.1, 0.9)
	player.velocity = Vector3.ZERO
	player.movement.facing = PI * 0.25
	await _frames(40)
	await _shot("31_barricaded_window")
	# Zombies breaking in: three on the window planks, three on the door,
	# two more waiting their turn.
	var slots := [[win, Vector3(-0.5, 0, 0)], [win, Vector3(0.0, 0, 0.1)], [win, Vector3(0.5, 0, 0)],
		[win, Vector3(0.1, 0, 0.8)], [door, Vector3(-0.4, 0, 0)], [door, Vector3(0.1, 0, 0.1)],
		[door, Vector3(0.55, 0, 0)], [door, Vector3(0.0, 0, 0.8)]]
	var zs: Array = []
	for sl in slots:
		var f: Node3D = sl[0]
		var base: Vector3 = f.call(&"sound_opening_center") + Vector3(0, 0, 0.75)
		var z: Node3D = spawner.spawn_at(base + sl[1])
		z.face_toward(f.call(&"sound_opening_center"))
		z.snap_facing(z.movement.facing)
		zs.append([z, f])
	await _frames(3)
	for pair in zs:
		var z: Node = pair[0]
		z.ai.blocking_obstacle = bc.of(pair[1])
		z.ai.change_to(&"attack_door")
	await _frames(280)
	var banging := 0
	for pair in zs:
		if pair[0].visual.clip() == &"z_bang":
			banging += 1
	if banging < 4:
		_problems.append("round 9: zombies not banging on the barricades (%d)" % banging)
	var bw = bc.of(win)
	if bw.attacker_count() > 3:
		_problems.append("round 9: more than 3 attackers on one window")
	if bw.total_health() >= 180.0:
		_problems.append("round 9: window planks undamaged")
	await _shot("32_zombies_breaking_in")
	for pair in zs:
		if is_instance_valid(pair[0]):
			pair[0].queue_free()
	await _frames(3)


# --- Round 10: pause menu, quick save / load, main menu -----------------------
const SHOT_SLOT := "screenshot_run"


## HUD values that must survive a save → load (compared as text).
func _hud_values(hud: Node) -> Dictionary:
	return {
		"health": hud.health_label.text, "stamina": hud.stamina_label.text,
		"weapon": hud.weapon_label.text, "weight": hud.weight_label.text,
		"injuries": hud.injury_label.text, "pain": hud.pain_label.text,
		"clock": hud.clock.shown_time(), "moodles": hud.moodle_list.get_child_count(),
	}


func _round10(inst: Node, player: Node3D, _cam: Node3D, hud: Node) -> void:
	var sm: Node = root.get_node("SaveManager")
	var tm: Node = root.get_node("TimeManager")
	sm.quick_slot = SHOT_SLOT
	tm.set_time_of_day(15, 30)
	var health: Node = player.get_node("Health")
	health.invulnerable = false
	player.inventory.remove_id(&"apple", player.inventory.count_of(&"apple"))
	player.inventory.add_id(&"apple", 2)
	player.inventory.add_id(&"bandage", 1)
	player.get_node("Needs").set_need(&"hunger", 35.0)
	player.get_node("Needs").set_need(&"thirst", 30.0)
	player.global_position = Vector3(-9.0, 0.1, 1.0)
	player.movement.facing = PI
	await _frames(45)
	# Esc (ui_cancel through the input map) → pause menu.
	var menu: Node = inst.get_node("PauseMenu")
	await _tap(&"ui_cancel")
	await _frames(2)
	if not menu.is_open() or not paused:
		_problems.append("round 10: Esc did not open the pause menu / pause the game")
	await _shot("34_pause_menu")
	await _tap(&"ui_cancel")
	await _frames(2)
	if menu.is_open() or paused:
		_problems.append("round 10: Esc did not close the pause menu")
	# F9 quick-save through the input map, with the HUD values of the moment.
	await _frames(20)
	var before := _hud_values(hud)
	before["hotbar"] = _carried_hotbar(player)
	await _shot("36_before_save")
	await _tap(&"quick_save")
	await _frames(2)
	if not FileAccess.file_exists(load("res://core/save_file.gd").world_path(SHOT_SLOT)):
		_problems.append("round 10: F9 wrote no save")
	print("round 10: save %.1f ms" % sm.last_save_ms)
	# Change the world, then F10 quick-load puts it back.
	player.global_position = Vector3(3.0, 0.1, 3.0)
	player.inventory.clear()
	health.take_damage(30.0, null, {})
	var loaded := [null]
	var eb: Node = root.get_node("EventBus")
	var cb := func(m: Node): loaded[0] = m
	eb.game_loaded.connect(cb)
	await _tap(&"quick_load")
	for i in 600:
		if loaded[0] != null:
			break
		await physics_frame
	eb.game_loaded.disconnect(cb)
	var map: Node = loaded[0]
	if map == null:
		_problems.append("round 10: F10 did not load")
		return
	print("round 10: load %.1f ms" % sm.last_load_ms)
	var p2: Node3D = map.get_node("Player")
	var hud2: Node = map.get_node("HUD")
	if p2.global_position.distance_to(Vector3(-9.0, 0.1, 1.0)) > 0.3:
		_problems.append("round 10: player not back where it was saved (%s)" % p2.global_position)
	if p2.inventory.count_of(&"apple") != 2:
		_problems.append("round 10: inventory not restored")
	await _frames(20)
	var after := _hud_values(hud2)
	after["hotbar"] = _carried_hotbar(p2)
	await _shot("36_after_load")
	for k in before:
		if k == "clock":
			continue  # a few seconds pass between the two shots
		if str(before[k]) != str(after[k]):
			_problems.append("round 10: HUD %s differs after load ('%s' vs '%s')" % [k, before[k], after[k]])
	print("round 10: HUD before %s / after %s" % [str(before), str(after)])
	var ia: Image = Image.load_from_file(ProjectSettings.globalize_path(OUT + "36_before_save.png"))
	var ib: Image = Image.load_from_file(ProjectSettings.globalize_path(OUT + "36_after_load.png"))
	if ia != null and ib != null and ia.get_size() == ib.get_size():
		print("round 10: mean pixel difference before save / after load %.4f" % _mean_diff(ia, ib))
	# The title screen (the project's main scene) lists the save.
	map.queue_free()
	await process_frame
	var menu_scene: PackedScene = load("res://ui/menus/main_menu.tscn")
	var mm := menu_scene.instantiate()
	root.add_child(mm)
	await _frames(10)
	if mm.continue_button.disabled:
		_problems.append("round 10: main menu has no Continue")
	await _shot("35_main_menu")
	mm.queue_free()
	sm.delete_slot(SHOT_SLOT)
	sm.quick_slot = "quick"


# --- Round 11: the generated world -----------------------------------------------------
## 37: layouts of three seeds (rendered from data); 38-41 + 42 in the real
## world.tscn of seed 1337: main street, a farmstead, the woods edge, the
## town from the farthest zoom, the M map overlay (real input).
func _round11() -> void:
	var gen: GDScript = load("res://worldgen/world_generator.gd")
	var ren: GDScript = load("res://worldgen/world_map_renderer.gd")
	var imgs: Array = []
	for s in [1337, 7, 99]:
		imgs.append(ren.render(gen.generate(s), 1.5))
	(ren.side_by_side(imgs) as Image).save_png(OUT + "37_world_map.png")
	print("saved ", OUT + "37_world_map.png")
	var sm: Node = root.get_node("SaveManager")
	var tm: Node = root.get_node("TimeManager")
	var map: Node = sm.instantiate_new_game("res://maps/world.tscn", 1337)
	root.add_child(map)
	var nav: Node = map.get_node("NavRegion")
	for i in 1200:
		if nav.baked:
			break
		await physics_frame
	await _frames(20)
	var player: Node3D = map.get_node("Player")
	var cam: Node3D = map.get_node("IsometricCamera")
	var builder: Node = map.get_node("Generated")
	var layout = builder.layout
	player.get_node("Health").invulnerable = true
	player.get_node("Controller").scripted = true
	tm.set_time_of_day(11, 0)
	var sp: Node = map.get_node("Zombies")
	# Round 12: the population director instantiates the start pack a
	# few per frame.
	var pd: Node = map.get_node_or_null("Population")
	for i in 600:
		if pd == null or pd.active_count() >= 30:
			break
		await physics_frame
	if sp.zombies.size() < 30:
		_problems.append("round 11: only %d zombies in the generated world" % sp.zombies.size())
	var loc: Dictionary = load("res://buildings/building.gd").locate(self, player.global_position)
	if loc.building == null:
		_problems.append("round 11: the new game does not start inside a building")
	# 38: main street by a shop, default zoom.
	var shop: Dictionary = {}
	for b in layout.buildings:
		if b.kind == &"convenience_store" and b.settlement == "town":
			shop = b
			break
	if shop.is_empty():
		shop = layout.buildings[0]
	var front: Vector2 = shop.door + (shop.access - shop.door).normalized() * 3.5
	await _teleport(player, cam, Vector3(front.x, 0.1, front.y))
	await _shot("38_town_street")
	# 39: a farmstead yard.
	var farm_house: Dictionary = {}
	for b in layout.buildings:
		if b.kind == &"farmhouse":
			var d := (b.door as Vector2).distance_to(layout.spawn_point)
			if farm_house.is_empty() or d < (farm_house.door as Vector2).distance_to(layout.spawn_point):
				farm_house = b
	var fpos: Vector2 = farm_house.door
	for lot in layout.lots:
		if lot.id == farm_house.lot and lot.has("farm_yard_center"):
			fpos = lot.farm_yard_center
	await _tap(&"camera_zoom_out")
	await _frames(3)
	await _tap(&"camera_zoom_out")
	await _teleport(player, cam, Vector3(fpos.x, 0.1, fpos.y))
	await _shot("39_farmstead")
	# 40: the woods edge nearest the start (meadow cell next to woods).
	var edge := _woods_edge(layout, layout.spawn_point)
	await _teleport(player, cam, Vector3(edge.x, 0.1, edge.y))
	await _shot("40_woods_edge")
	# 43 (extra): the main street at night — street lamps and lit windows.
	await _teleport(player, cam, Vector3(front.x, 0.1, front.y))
	tm.set_time_of_day(23, 0)
	await _frames(30)
	await _shot("43_town_night")
	tm.set_time_of_day(11, 0)
	await _frames(10)
	# 41: the town from the farthest zoom (real input).
	var tc: Vector2 = layout.settlement("town").center
	await _teleport(player, cam, Vector3(tc.x + 3.0, 0.1, tc.y + 5.0))
	for i in 4:
		await _tap(&"camera_zoom_out")
		await _frames(3)
	await _frames(60)
	await _shot("41_town_overview")
	# 42: M opens the map overlay (real input).
	await _tap(&"toggle_map")
	await _frames(10)
	var overlay: Node = map.get_node("MapOverlay")
	if not overlay.is_open:
		_problems.append("round 11: M did not open the map overlay")
	await _shot("42_map_overlay")
	await _tap(&"toggle_map")
	await _frames(5)
	map.queue_free()
	await process_frame


func _teleport(player: Node3D, cam: Node3D, p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	await _frames(2)
	# Round 12: build the streamed chunks around the new spot now (the
	# streamer would take a few dozen frames).
	var st: Node = player.get_parent().get_node_or_null("Streamer")
	if st != null:
		st.flush()
	cam.global_position = p + Vector3.UP * 0.9
	await _frames(40)


## Round 12: world streaming + the zombie population simulation.
## 44: M + F2 (real input) — the map with the chunk debug layer (loaded
## chunks, per-chunk simulated zombies, data groups, live zombies) after
## walking 250 m from the start; 45: a car alarm pulls a simulated horde
## from outside the active area; it is instantiated at the edge and walks
## in toward the noise (zoomed out).
func _round12() -> void:
	var sm: Node = root.get_node("SaveManager")
	var tm: Node = root.get_node("TimeManager")
	var map: Node = sm.instantiate_new_game("res://maps/world.tscn", 1337)
	root.add_child(map)
	var nav: Node = map.get_node("NavRegion")
	for i in 1200:
		if nav.baked:
			break
		await physics_frame
	await _frames(30)
	var player: Node3D = map.get_node("Player")
	var cam: Node3D = map.get_node("IsometricCamera")
	var builder: Node = map.get_node("Generated")
	var st: Node = map.get_node("Streamer")
	var pd: Node = map.get_node("Population")
	var layout = builder.layout
	player.get_node("Health").invulnerable = true
	player.get_node("Controller").scripted = true
	tm.set_time_of_day(11, 0)
	# Walk (teleport in steps) 250 m toward the town so chunks stream.
	var tc: Vector2 = layout.settlement("town").center
	var from := Vector2(player.global_position.x, player.global_position.z)
	var dir := (tc - from).normalized() if tc.distance_to(from) > 10.0 else Vector2(1, 0)
	for k in 25:
		var q := from + dir * 10.0 * (k + 1)
		player.global_position = Vector3(q.x, 0.1, q.y)
		await _frames(6)
	await _teleport(player, cam, player.global_position)
	if st.unloads == 0 and from.distance_to(Vector2(player.global_position.x, player.global_position.z)) > 200.0:
		_problems.append("round 12: no chunk unloaded after walking 250 m")
	await _tap(&"toggle_map")
	await _frames(5)
	await _tap(&"toggle_chunk_debug")
	await _frames(10)
	var overlay: Node = map.get_node("MapOverlay")
	if not overlay.is_open or not overlay.debug_chunks:
		_problems.append("round 12: M + F2 did not show the chunk debug map")
	await _shot("44_chunk_debug")
	await _tap(&"toggle_chunk_debug")
	await _tap(&"toggle_map")
	await _frames(5)
	# 45: the horde. Stand on an open spot, find the biggest simulated
	# groups 150-230 m away (outside the active area) and set off a car
	# alarm (a loud noise, radius 120 m).
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var pop = pd.population
	var cands: Array = []
	for id in pop.groups:
		var g: Dictionary = pop.groups[id]
		var d: float = pp.distance_to(g.pos)
		if d > 150.0 and d < 230.0:
			cands.append([-(g.members as PackedInt32Array).size(), id])
	cands.sort()
	var horde := 0
	for c in cands.slice(0, 6):
		horde += -int(c[0])
	if horde < 6:
		_problems.append("round 12: no simulated horde near enough (%d)" % horde)
	root.get_node("SoundManager").emit_sound(&"alarm", Vector3(pp.x, 0.0, pp.y), null, {"radius": 120.0, "intensity": 1.0})
	var coming := 0
	for id in pop.groups:
		if int(pop.groups[id].state) == 2:
			coming += (pop.groups[id].members as PackedInt32Array).size()
	print("round 12: %d simulated zombies heard the alarm" % coming)
	# Game time passes (the sim walks them in); zoom out to watch.
	var alive0: int = pd.active_count()
	for k in 12:
		tm.advance(6.0)
		pd.tick_now()
		pd.sync_now()
		await _frames(20)
	for i in 3:
		await _tap(&"camera_zoom_out")
		await _frames(3)
	await _frames(120)
	var walking := 0
	for z in pd.real_zombies():
		if z.state() == &"investigate" and z.global_position.distance_to(player.global_position) < 90.0:
			walking += 1
	print("round 12: live zombies %d → %d, %d walking in toward the alarm" % [alive0, pd.active_count(), walking])
	if walking < 5:
		_problems.append("round 12: the horde did not walk in (%d investigating)" % walking)
	await _shot("45_horde_arriving")
	map.queue_free()
	await process_frame


## A meadow point at the edge of a deep woods mass (woods for 40 m
## north-east of it — up-screen at the default heading), nearest [from].
func _woods_edge(layout, from: Vector2) -> Vector2:
	var best := from
	var bd := INF
	var cell: float = layout.zone_cell
	for z in range(1, layout.zone_h - 1):
		for x in range(1, layout.zone_w - 1):
			var p := Vector2((x + 0.5) * cell, (z + 0.5) * cell)
			if layout.zone_at(p) != 0:
				continue
			var deep := true
			for k in range(2, 11):
				if layout.zone_at(p + Vector2(0.7, -0.7) * cell * k) != 1:
					deep = false
					break
			if not deep:
				continue
			if not layout.road_at(p, 12.0).is_empty():
				continue
			var d := p.distance_to(from)
			if d < bd:
				bd = d
				best = p
	return best


## Hotbar slots holding carried items (a slot pointing at an item left
## elsewhere is a by-identity ghost the save does not keep).
func _carried_hotbar(p: Node) -> String:
	var out: PackedStringArray = []
	for e in p.get_node("Equipment").hotbar_summary():
		out.append(String(e.get("id", "")) if e.get("carried", false) else "-")
	return ",".join(out)


func _mean_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return total / maxf(float(n) * 3.0, 1.0)


func _right_click(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT
	ev.pressed = true
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)


func _click(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.pressed = true
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await process_frame
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)


func _mouse_to(p: Vector2) -> void:
	Input.warp_mouse(p)
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)


func _press(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _release(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


func _tap(action: StringName) -> void:
	_press(action)
	await process_frame
	_release(action)


## Waits n PHYSICS frames (= n/60 s of game time regardless of render fps).
func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	var path := OUT + name + ".png"
	img.save_png(path)
	print("saved ", path)
