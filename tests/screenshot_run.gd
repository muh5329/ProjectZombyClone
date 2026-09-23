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
	player.global_position = Vector3(-22, 0.1, 4)
	await _tap(&"camera_zoom_out")
	await _frames(5)
	await _tap(&"camera_zoom_out")
	var group_origin := player.global_position + Vector3(-7, 0, -6)
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
	var chaser: Node3D = spawner.spawn_at(player.global_position + Vector3(-5.5, 0, 0))
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

	await _round4(inst, player, cam, spawner, hud)
	await _round5(inst, player, cam, spawner, hud)
	await _round6(inst, player, cam, spawner, hud)
	await _round7(inst, player, cam, spawner, hud)

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
	# Climb through the smashed living-room window: glass laceration.
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
