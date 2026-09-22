extends "res://tests/test_case.gd"
## Round 6 in the real test_ground scene: equipment, the school bag on the
## bedroom bed, nested storage, encumbrance effects on real movement /
## stamina / sprint, dropping, the hotbar (real keys), the inventory
## screen (Tab, tabs as loot targets, drag and drop, context actions).

var scene: Node
var player: Player
var ctrl: PlayerController
var combat: MeleeCombat
var injuries: InjuryComponent
var interaction: PlayerInteraction
var hud: CanvasLayer
var window: LootWindow
var eq: Equipment
var enc: Encumbrance


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	scene.get_node("Zombies").auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	combat = player.get_node("Combat")
	injuries = player.get_node("Injuries")
	interaction = player.get_node("Interaction")
	hud = scene.get_node("HUD")
	window = scene.get_node("LootWindow")
	eq = player.equipment
	enc = player.encumbrance
	ctrl.scripted = true
	combat.scripted = true
	interaction.scripted = true
	var nav: NavBaker = scene.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(3)


func teardown() -> void:
	for a in [&"move_right", &"sprint", &"toggle_inventory", &"drop_item"]:
		Input.action_release(a)
	await despawn(scene)


func _container(pid: String) -> LootContainer:
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and c.persist_id == pid and scene.is_ancestor_of(c):
			return c
	return null


func _open(c: LootContainer) -> bool:
	var front := c.global_basis.z
	front.y = 0.0
	front = front.normalized()
	player.global_position = c.global_position + front * (c.size.z * 0.5 + 0.75) + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.movement.facing = BodyHelpers.yaw_for(-front)
	await physics_frames(4)
	if interaction.current_target == null or interaction.current_target.body() != c:
		fail("container %s not targeted" % c.persist_id)
		return false
	interaction.interact()
	var ok := await wait_physics_until(func(): return c.is_open_for(player), 120)
	await physics_frames(2)
	return ok


func _key(physical: Key, pressed: bool, alt: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.keycode = physical
	ev.pressed = pressed
	ev.alt_pressed = alt
	Input.parse_input_event(ev)


func _tap_key(physical: Key, alt: bool = false) -> void:
	_key(physical, true, alt)
	await frames(2)
	_key(physical, false, alt)
	await frames(2)


func _tap_action(a: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = a
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = a
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)


func _screen(c: Control) -> Vector2:
	return c.get_viewport().get_final_transform() * c.get_global_rect().get_center()


var _last_mouse := Vector2.ZERO


func _mouse(p: Vector2, pressed: int = -1) -> void:
	if pressed < 0:
		var mv := InputEventMouseMotion.new()
		mv.position = p
		mv.global_position = p
		# The GUI's drag detection accumulates `relative`.
		mv.relative = p - _last_mouse
		_last_mouse = p
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 0
		Input.parse_input_event(mv)
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed == 1 else 0
	ev.pressed = pressed == 1
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)


## Jog along +X in the open for [frames] physics frames; flat distance.
func _jog_distance(n: int, mode := MovementComponent.Mode.JOG) -> float:
	player.global_position = Vector3(18, 0.1, 18)
	player.velocity = Vector3.ZERO
	await physics_frames(3)
	var p0 := player.global_position
	ctrl.scripted_mode = mode
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(n)
	ctrl.scripted_direction = Vector3.ZERO
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	var d := player.global_position - p0
	return Vector2(d.x, d.z).length()


func _overload() -> void:
	player.inventory.add_id(&"plank", 5)  # 15 kg
	player.inventory.add_id(&"water_bottle", 2)  # > 15 kg: overloaded
	await physics_frames(1)


# --- Backpack from the house ------------------------------------------------------

func test_backpack_on_the_bed_equip_extends_capacity_and_lightens() -> void:
	var wi: WorldItem = scene.get_node("Items/Backpack")
	check(wi != null and wi.item.is_bag(), "a school bag lies in the bedroom")
	var room := (scene.get_node("Buildings/HouseA") as HouseBlockout).room_at(wi.global_position + Vector3.DOWN * 0.4)
	check(room != null and room.room_type == &"bedroom", "…in the bedroom")
	player.global_position = Vector3(-11.1, 0.1, -7.2)
	var to_bag := wi.global_position - player.global_position
	to_bag.y = 0.0
	player.movement.facing = BodyHelpers.yaw_for(to_bag.normalized())
	await physics_frames(4)
	check(interaction.current_target != null and interaction.current_target.body() == wi, "bag targeted (%s)" % str(interaction.current_target))
	var labels := interaction.current_actions.map(func(a): return a.label)
	check(labels.has("Pick up School Bag") and labels.has("Open School Bag"), "pick up + open (%s)" % str(labels))
	check(interaction.interact().ok, "picked up")
	var bag := player.inventory.find(&"backpack")
	check(bag != null, "bag in the main inventory")
	check_eq(window.player_tabs().size(), 1, "one container tab while carried")
	# Wear it (context action), then fill it.
	var r := window.perform_context(LootWindow.SIDE_PLAYER, bag, ItemActions.EQUIP)
	check(r.ok and eq.back_bag() == bag, "worn on the back (%s)" % str(r))
	check(not player.inventory.has(bag), "out of the main inventory")
	await frames(2)
	check_eq(window.player_tabs().size(), 2, "Inventory + School Bag tabs")
	check_eq(hud.notice_label.text, "Wearing School Bag", "HUD notice")
	# Capacity grows: 20 kg main + 7 kg bag.
	player.inventory.add_id(&"plank", 6)  # 18 kg
	check(not player.inventory.add_id(&"plank", 1).ok, "main inventory refuses a 7th plank")
	var w_before := player.carried_weight()
	check(bag.contents.add_id(&"plank", 2).ok, "…the bag takes 2 more (6 kg)")
	check_near(player.carried_weight() - w_before, 6.0 * 0.7, 0.001, "bag contents count 70 %")
	check_near(player.carried_weight(), 18.0 + 0.7 + 4.2, 0.001, "carried = main + bag (reduced)")
	check_eq(enc.state, &"overloaded", "22.9 kg is overloaded")
	# The same load unworn weighs more: it does not fit the pack.
	var r2 := eq.unequip(bag)
	check(not r2.ok and r2.reason == "No room in inventory", "a 6.7 kg bag does not fit the full pack (%s)" % str(r2))
	# Taking it off through the player drops it at the feet (PZ) with a notice.
	var r3 := player.unequip_item(bag)
	check(r3.ok and r3.get("dropped", false) and eq.back_bag() == null, "taken off → dropped (%s)" % str(r3))
	var w3: WorldItem = r3.world_item
	check(is_instance_valid(w3) and w3.item == bag and bag.contents.count_of(&"plank") == 2, "bag + contents on the floor")
	await frames(1)
	check(hud.notice_label.text.begins_with("No room: dropped School Bag"), "notice (%s)" % hud.notice_label.text)


func test_loot_into_the_active_tab() -> void:
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(bag)
	check(player.equip_item(bag).ok, "worn")
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"soda", "count": 3}, {"id": &"nails", "count": 30}]
	check(await _open(c), "cabinet open")
	await frames(2)
	check_eq(window.tab_buttons.size(), 2, "two tabs")
	check(window.tab_buttons[1].visible, "bag tab shown")
	window.select_tab(1)
	check(window.active_player_container() == bag.contents, "bag is the loot target")
	check_eq(window.player_title.text, "School Bag", "header follows the tab")
	var soda := c.inventory.find(&"soda")
	var n_soda := soda.stack
	var r := window.transfer_item(LootWindow.SIDE_CONTAINER, soda)
	check(r.ok and bag.contents.count_of(&"soda") == n_soda and player.inventory.count_of(&"soda") == 0, "click → into the bag (%s)" % str(r))
	window.select_tab(0)
	r = window.loot_all()
	check(r.ok and player.inventory.count_of(&"nails") == 30, "Loot All → main inventory")
	await frames(2)
	check(window.player_weight.text.begins_with("Space ") and window.player_weight.text.ends_with("/ 20 kg"), "main header is storage space (%s)" % window.player_weight.text)
	check(window.load_label.text.begins_with("Carrying") and window.load_label.text.ends_with("/ 8 kg"), "load readout next to the tabs (%s)" % window.load_label.text)
	window.select_tab(1)
	await frames(1)
	check(window.player_weight.text.ends_with("/ 7 kg"), "bag header (%s)" % window.player_weight.text)
	# Transfer All from the bag tab empties the bag only.
	r = window.transfer_all()
	check(r.ok and bag.contents.is_empty() and player.inventory.count_of(&"nails") == 30, "Transfer All from the active tab")


# --- Encumbrance in real movement -------------------------------------------------

func test_heavy_load_slows_real_movement() -> void:
	var d0 := await _jog_distance(120)
	check_gt(d0, 5.5, "unloaded jog covers ground (%.2f m)" % d0)
	await _overload()
	check_eq(enc.state, &"overloaded", "overloaded (%.2f kg)" % enc.weight)
	check_near(player.movement.speed_modifiers.get(&"encumbrance", 1.0), 0.65, 0.0001, "movement modifier")
	var d1 := await _jog_distance(120)
	check_near(d1 / d0, 0.65, 0.06, "2 s of jogging: ×0.65 distance (%.2f vs %.2f m)" % [d1, d0])
	# Drop back to heavy: in between.
	player.inventory.remove_id(&"water_bottle", 2)
	check_eq(enc.state, &"heavy", "15 kg is heavy")
	var d2 := await _jog_distance(120)
	check_near(d2 / d0, 0.85, 0.06, "heavy ×0.85 (%.2f m)" % d2)
	# Footsteps are louder when heavy.
	var radii := []
	var cb := func(_p, r, _i, cat, src):
		if cat == &"footstep" and src == player:
			radii.append(r)
	EventBus.sound_emitted.connect(cb)
	await _jog_distance(80)
	EventBus.sound_emitted.disconnect(cb)
	check(not radii.is_empty() and is_equal_approx(radii[0], 8.0 * 1.2), "heavy jog footsteps 9.6 m (%s)" % str(radii))


func test_overloaded_refuses_sprint_and_drains_stamina_faster() -> void:
	player.stats.set_value(Character.STAMINA, 80.0)
	await _jog_distance(2)
	var s0 := player.stats.get_value(Character.STAMINA)
	await _jog_distance(120)
	var drop_ok := s0 - player.stats.get_value(Character.STAMINA)
	await _overload()
	player.stats.set_value(Character.STAMINA, 80.0)
	await _jog_distance(2)
	s0 = player.stats.get_value(Character.STAMINA)
	await _jog_distance(120)
	var drop_heavy := s0 - player.stats.get_value(Character.STAMINA)
	check_gt(drop_ok, 1.0, "jogging costs stamina (%.2f)" % drop_ok)
	check_near(drop_heavy / drop_ok, 1.7, 0.2, "overloaded drains ×1.7 (%.2f vs %.2f)" % [drop_heavy, drop_ok])
	# Sprint refused, with the reason.
	var denied := []
	var cb := func(c): denied.append(c)
	EventBus.sprint_denied.connect(cb)
	player.global_position = Vector3(18, 0.1, 18)
	ctrl.scripted_mode = MovementComponent.Mode.SPRINT
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(20)
	check_eq(player.effective_mode, MovementComponent.Mode.JOG, "sprint → jog")
	check(player.sprint_denied and denied.size() == 1, "sprint_denied once")
	check_eq(player.sprint_denied_reason(), "Too heavy", "reason")
	await frames(1)
	check_eq(hud.notice_label.text, "Too heavy", "HUD says why")
	ctrl.scripted_direction = Vector3.ZERO
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	EventBus.sprint_denied.disconnect(cb)
	check(hud.weight_label.text.contains("Overloaded"), "HUD weight readout (%s)" % hud.weight_label.text)
	check(hud.weight_label.get_theme_color(&"font_color").r > 0.9 and hud.weight_label.get_theme_color(&"font_color").g < 0.4, "…in red")
	check(hud.weight_label.text.begins_with("Carrying 17.0 / 8 kg"), "weight / capacity (%s)" % hud.weight_label.text)
	# Unload → sprint works again.
	player.inventory.clear()
	check_eq(enc.state, &"ok", "unloaded")
	check(player.can_sprint(), "sprint allowed again")


func test_encumbrance_event_and_hud_notice() -> void:
	var got := []
	var cb := func(c, s, w): got.append([s, w])
	EventBus.encumbrance_changed.connect(cb)
	player.inventory.add_id(&"plank", 3)  # 9 kg: light
	await frames(1)
	check(not got.is_empty() and got[-1][0] == &"light" and is_equal_approx(got[-1][1], 9.0), "event (%s)" % str(got))
	player.inventory.add_id(&"plank", 1)  # 12: still light
	await frames(1)
	check_eq(got[-1][0], &"light", "12 kg light")
	player.inventory.add_id(&"water_bottle", 1)
	await frames(1)
	check_eq(got[-1][0], &"heavy", "heavy")
	check(hud.notice_label.text.begins_with("Heavy load"), "HUD notice on change (%s)" % hud.notice_label.text)
	check(hud.weight_label.text.ends_with("Heavy load"), "readout (%s)" % hud.weight_label.text)
	EventBus.encumbrance_changed.disconnect(cb)


# --- Drop / pick up -------------------------------------------------------------------

func test_drop_item_and_pick_it_up_again() -> void:
	player.global_position = Vector3(18, 0.1, 18)
	player.movement.facing = 0.0
	await physics_frames(3)
	player.inventory.add_id(&"hammer", 1)
	var hammer := player.inventory.find(&"hammer")
	var before := tree.get_nodes_in_group(&"world_item").size()
	var r := player.drop_item(hammer)
	check(r.ok, "dropped")
	check(not player.carries(hammer), "gone from the player")
	var w: WorldItem = r.world_item
	check(is_instance_valid(w) and w.get_parent() == scene, "a WorldItem in the scene")
	check_eq(tree.get_nodes_in_group(&"world_item").size(), before + 1, "one more world item")
	check_eq(w.collision_layer, 8, "on layer 4")
	check_lt(Vector2(w.global_position.x - player.global_position.x, w.global_position.z - player.global_position.z).length(), 0.8, "at the feet")
	await frames(1)
	check(hud.notice_label.text.begins_with("Dropped Hammer"), "HUD notice")
	await physics_frames(3)
	check(interaction.current_target != null and interaction.current_target.body() == w, "targetable")
	check(interaction.interact().ok, "picked up again")
	check(player.inventory.has(hammer) or eq.primary() == hammer, "carried again (same instance)")
	await physics_frames(2)
	check(not is_instance_valid(w), "world item gone")


func test_drop_equipped_and_g_key_on_the_inventory_screen() -> void:
	player.global_position = Vector3(18, 0.1, 18)
	await physics_frames(2)
	player.inventory.add_id(&"crowbar", 1)
	var crowbar := player.inventory.find(&"crowbar")
	check(player.equip_item(crowbar).ok, "equipped")
	var r := player.drop_item(crowbar)
	check(r.ok and eq.primary() == null and combat.weapon() == combat.fists, "dropping the equipped weapon empties the hand")
	# G on the selected row of the Tab screen.
	player.inventory.add_id(&"apple", 4)
	var apples := player.inventory.find(&"apple")
	window.toggle_inventory()
	await frames(2)
	window.click_row(LootWindow.SIDE_PLAYER, apples)
	check(window.selected == apples, "row selected")
	await _tap_action(&"drop_item")
	check(not player.carries(apples), "G dropped the selected stack")
	var dropped := tree.get_nodes_in_group(&"world_item").filter(func(n): return n.item == apples)
	check_eq(dropped.size(), 1, "as one WorldItem ×4")
	window.toggle_inventory()


# --- Hotbar ------------------------------------------------------------------------------

func test_hotbar_assign_and_real_key_press_equips() -> void:
	player.inventory.add_id(&"kitchen_knife", 1)
	player.inventory.add_id(&"hammer", 1)
	var knife := player.inventory.find(&"kitchen_knife")
	var hammer := player.inventory.find(&"hammer")
	var acts := window.context_actions(LootWindow.SIDE_PLAYER, knife).map(func(a): return a.id)
	check(acts.has(&"hotbar_0") and acts.has(&"hotbar_2"), "Assign to hotbar 1-3 in the menu (%s)" % str(acts))
	check(window.perform_context(LootWindow.SIDE_PLAYER, knife, &"hotbar_0").ok, "knife → slot 1")
	check(window.perform_context(LootWindow.SIDE_PLAYER, hammer, &"hotbar_1").ok, "hammer → slot 2")
	await frames(2)
	check_eq(hud.hotbar.slot_name(0), "Kitchen Knife", "HUD slot 1")
	check_eq(hud.hotbar.slot_name(1), "Hammer", "HUD slot 2")
	check_eq(hud.hotbar.slot_name(2), "", "slot 3 empty")
	combat.scripted = false
	await _tap_key(KEY_1)
	check(eq.primary() == knife and combat.weapon().id == &"kitchen_knife", "key 1 equips the knife")
	check(hud.hotbar.slot_equipped(0), "HUD marks it equipped")
	await _tap_key(KEY_2)
	check(eq.primary() == hammer and player.inventory.has(knife), "key 2 swaps to the hammer")
	await _tap_key(KEY_2)
	check(eq.primary() == null and player.inventory.has(hammer), "key 2 again puts it away")
	combat.scripted = true
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "no attack")


func test_keys_4_to_7_pick_interaction_alternatives() -> void:
	# The west living-room window: [5] is "Smash" on a closed window.
	player.global_position = Vector3(-13.3, 0.1, -4)
	player.movement.facing = PI * 0.5
	await physics_frames(4)
	var idx := -1
	for i in interaction.current_actions.size():
		if interaction.current_actions[i].id == &"smash":
			idx = i
	check_eq(idx, 1, "smash is the second action (%s)" % str(interaction.current_actions))
	await frames(1)
	check(hud.prompt_label.text.contains("[5] Smash window"), "prompt names key 5 (%s)" % hud.prompt_label.text)
	var w := interaction.current_target.body() as HouseWindow
	interaction.scripted = false
	await _tap_key(KEY_2)
	check(w.state != &"smashed", "2 is the hotbar, not the window")
	await _tap_key(KEY_5)
	await physics_frames(2)
	check_eq(w.state, &"smashed", "5 smashed it")
	interaction.scripted = true


func test_hotbar_works_while_sprint_sneak_or_walk_is_held() -> void:
	player.inventory.add_id(&"kitchen_knife", 1)
	var knife := player.inventory.find(&"kitchen_knife")
	check(eq.assign_hotbar(0, knife).ok, "assigned")
	combat.scripted = false
	for mods in [["shift"], ["ctrl"], ["alt"]]:
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_1
		ev.keycode = KEY_1
		ev.pressed = true
		ev.shift_pressed = mods[0] == "shift"
		ev.ctrl_pressed = mods[0] == "ctrl"
		ev.alt_pressed = mods[0] == "alt"
		Input.parse_input_event(ev)
		await frames(2)
		var up := ev.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
		await frames(2)
		check(eq.primary() == knife, "%s+1 equips" % mods[0])
		check(eq.unequip(knife).ok, "reset")
	combat.scripted = true


func test_world_click_does_not_attack_while_screen_open() -> void:
	player.global_position = Vector3(18, 0.1, 18)
	var swings := [0]
	var cb := func(a, _id, _c): if a == player: swings[0] += 1
	EventBus.melee_swing.connect(cb)
	combat.scripted = false
	window.toggle_inventory()
	await frames(3)
	var at := Vector2(1100, 500)  # the world, right of the panels
	var p := get_viewport_pos(at)
	_mouse(p)
	await frames(1)
	_mouse(p, 1)
	await frames(2)
	_mouse(p, 0)
	await frames(2)
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "no swing with the inventory open")
	check_eq(swings[0], 0, "no melee_swing")
	window.toggle_inventory()
	await frames(2)
	_mouse(p, 1)
	await frames(2)
	_mouse(p, 0)
	await frames(2)
	check(swings[0] == 1, "the same click attacks once the screen is closed (%d)" % swings[0])
	await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.IDLE, 120)
	EventBus.melee_swing.disconnect(cb)
	combat.scripted = true
	_mouse(Vector2(640, 600))


func get_viewport_pos(canvas: Vector2) -> Vector2:
	return window.root.get_viewport().get_final_transform() * canvas


# --- Inventory screen ------------------------------------------------------------------

func test_tab_screen_click_selects_without_attacking_and_movement_works() -> void:
	player.global_position = Vector3(18, 0.1, 18)
	player.inventory.add_id(&"hammer", 1)
	player.inventory.add_id(&"bandage", 2)
	combat.scripted = false
	ctrl.scripted = false
	await _tap_action(&"toggle_inventory")
	check(window.is_visible_screen() and window.player_panel_visible() and not window.container_panel_visible(), "Tab: inventory screen alone")
	check(not window.is_open(), "no container")
	await frames(2)
	var row := window.row_node(LootWindow.SIDE_PLAYER, 0)
	check(row != null, "a row")
	var at := _screen(row)
	_mouse(at)
	await frames(1)
	_mouse(at, 1)
	await frames(2)
	_mouse(at, 0)
	await frames(3)
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "clicking the inventory never attacks")
	check(window.selected != null and window.selected == window.side_items(LootWindow.SIDE_PLAYER)[0], "the click selected the row")
	# WASD still moves the player with the screen open.
	var p0 := player.global_position
	Input.action_press(&"move_right")
	await physics_frames(30)
	Input.action_release(&"move_right")
	check_gt(p0.distance_to(player.global_position), 0.5, "movement works with the screen open")
	await _tap_action(&"toggle_inventory")
	check(not window.is_visible_screen(), "Tab closes it")
	combat.scripted = true
	ctrl.scripted = true
	_mouse(Vector2(640, 600))


func test_rows_grouped_by_category_equipped_first() -> void:
	player.inventory.add_id(&"nails", 10)
	player.inventory.add_id(&"apple", 1)
	player.inventory.add_id(&"hammer", 1)
	player.inventory.add_id(&"crowbar", 1)
	check(player.equip_item(player.inventory.find(&"crowbar")).ok, "crowbar in hand")
	window.toggle_inventory()
	await frames(3)
	var r := window.rows(LootWindow.SIDE_PLAYER)
	check(r[0].equipped and r[0].name == "Crowbar" and r[0].category == "Hands", "equipped first (%s)" % str(r[0]))
	var names := r.map(func(x): return x.name)
	check(names.find("Apple") < names.find("Hammer") and names.find("Hammer") < names.find("Nails"), "category order food < weapon < material (%s)" % str(names))
	check_eq(window.panel(LootWindow.SIDE_PLAYER).header_count(), 4, "Equipped / Food / Weapons / Materials headers")
	check_eq(window.visible_row_count(LootWindow.SIDE_PLAYER), 4, "four item rows")
	window.toggle_inventory()


func test_ctrl_click_splits_half_in_place() -> void:
	player.inventory.add_id(&"nails", 40)
	var nails := player.inventory.find(&"nails")
	window.toggle_inventory()
	await frames(2)
	var r := window.click_row(LootWindow.SIDE_PLAYER, nails, false, true)
	check(r.ok, "split")
	var stacks := player.inventory.find_all(&"nails")
	check(stacks.size() == 2 and stacks[0].stack == 20 and stacks[1].stack == 20, "20 + 20 in the same container")
	window.toggle_inventory()
	# Container side too.
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"soda", "count": 5}]
	check(await _open(c), "open")
	var soda := c.inventory.find(&"soda")
	var n := soda.stack
	r = window.click_row(LootWindow.SIDE_CONTAINER, soda, false, true)
	check(r.ok and c.inventory.find_all(&"soda").size() == 2 and soda.stack == n - n / 2, "container stack split")


func test_drag_and_drop_between_panels_and_tabs() -> void:
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(bag)
	check(player.equip_item(bag).ok, "worn")
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"water_bottle", "count": 1}, {"id": &"plank", "count": 1}]
	check(await _open(c), "open")
	var water := c.inventory.find(&"water_bottle")
	var data := window.drag_payload(LootWindow.SIDE_CONTAINER, water)
	check(window.can_drop_payload(LootWindow.TARGET_PLAYER, data), "can drop on the player list")
	check(not window.can_drop_payload(LootWindow.TARGET_CONTAINER, data), "not back onto its own panel")
	var r := window.drop_payload(LootWindow.TARGET_PLAYER, data)
	check(r.ok and player.inventory.has(water), "container → inventory (%s)" % str(r))
	# Player row onto the bag tab.
	data = window.drag_payload(LootWindow.SIDE_PLAYER, water)
	check(window.can_drop_payload(&"tab_1", data), "can drop on the bag tab")
	r = window.drop_payload(&"tab_1", data)
	check(r.ok and bag.contents.has(water), "inventory → bag via the tab")
	# The worn bag onto its own tab is refused.
	data = window.drag_payload(LootWindow.SIDE_PLAYER, bag)
	check(not window.can_drop_payload(&"tab_1", data), "the bag cannot go into itself")
	# Player row onto the container panel.
	data = window.drag_payload(LootWindow.SIDE_PLAYER, water)
	r = window.drop_payload(LootWindow.TARGET_CONTAINER, data)
	check(r.ok and c.inventory.has(water), "bag → container")
	# Too heavy: greyed and refused.
	player.inventory.add_id(&"plank", 6)
	player.inventory.add_id(&"nails", 200)
	var plank := c.inventory.find(&"plank")
	check(not window.can_drop_payload(LootWindow.TARGET_PLAYER, window.drag_payload(LootWindow.SIDE_CONTAINER, plank)), "full pack refuses the drop")


func test_real_mouse_drag_moves_an_item() -> void:
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"soda", "count": 2}]
	check(await _open(c), "open")
	c.inventory.clear()
	c.inventory.add_id(&"soda", 2)
	await frames(3)
	var row := window.row_node(LootWindow.SIDE_CONTAINER, 0)
	var from := _screen(row)
	var to := _screen(window.player_scroll)
	_mouse(from)
	await frames(1)
	_mouse(from, 1)
	await frames(1)
	for i in 12:
		_mouse(from.lerp(to, (i + 1) / 12.0))
		await frames(1)
	_mouse(to, 0)
	await frames(3)
	check_eq(player.inventory.count_of(&"soda"), 2, "dragged the soda stack onto the inventory")
	check(c.inventory.is_empty(), "container empty")
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "no attack")
	_mouse(Vector2(640, 600))


func test_bag_on_the_ground_opens_like_a_container() -> void:
	player.global_position = Vector3(18, 0.1, 18)
	player.movement.facing = 0.0
	await physics_frames(2)
	var duffel := ItemInstance.new(ItemDB.get_item(&"duffel_bag"))
	duffel.contents.add_id(&"canned_beans", 3)
	var w := WorldItem.drop(duffel, player)
	await physics_frames(3)
	check(interaction.current_target != null and interaction.current_target.body() == w, "bag targeted")
	var r := interaction.perform_action(&"open")
	check(r.ok and w.is_open_for(player), "opened")
	await frames(2)
	check(window.is_open() and window.container_title.text == "Duffel Bag", "loot window on the ground bag")
	check_eq(window.rows(LootWindow.SIDE_CONTAINER).size(), 1, "its contents")
	r = window.loot_all()
	check(r.ok and player.inventory.count_of(&"canned_beans") == 3, "looted from the ground bag")
	# A worn bag never goes into it.
	var pack := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(pack)
	check(player.equip_item(pack).ok, "wear a backpack")
	r = window.transfer_item(LootWindow.SIDE_PLAYER, pack)
	check(not r.ok and r.reason == ItemContainer.REASON_WORN_BAG, "worn bag refused (%s)" % str(r))
	# Walking away closes it.
	ctrl.scripted_direction = Vector3.BACK
	check(await wait_physics_until(func(): return not w.is_open_for(player), 120), "closes > 2 m away")
	ctrl.scripted_direction = Vector3.ZERO
	await frames(2)
	check(not window.is_open(), "window closed")


func test_use_rag_bandages_and_food_is_a_stub() -> void:
	player.inventory.add_id(&"rag", 1)
	player.inventory.add_id(&"bandage", 1)
	player.inventory.add_id(&"apple", 1)
	injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	var rag := player.inventory.find(&"rag")
	var r := window.perform_context(LootWindow.SIDE_PLAYER, rag, ItemActions.USE)
	check(r.ok and r.dressing == &"rag", "Use on the rag bandages with the rag (%s)" % str(r))
	check(injuries.is_bandaging(), "bandaging")
	check_eq(player.inventory.count_of(&"bandage"), 1, "the better bandage was kept")
	check(await wait_physics_until(func(): return not player.is_busy, 60 * 5), "done")
	var apple := player.inventory.find(&"apple")
	r = window.perform_context(LootWindow.SIDE_PLAYER, apple, ItemActions.USE)
	check(not r.ok and r.reason == "Eating comes in Round 7", "food stub (%s)" % str(r))
	await frames(1)
	check_eq(hud.notice_label.text, "Eating comes in Round 7", "HUD notice")
	# Dressings in the worn bag are found by B too.
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(bag)
	player.equip_item(bag)
	player.inventory.remove_id(&"bandage", 1)
	bag.contents.add_id(&"bandage", 1)
	injuries.add_injury(Injury.Region.RIGHT_ARM, Injury.Type.LACERATION)
	r = injuries.bandage_worst()
	check(r.ok and r.dressing == &"bandage" and bag.contents.count_of(&"bandage") == 0, "B takes the bandage from the bag")


func test_context_menu_opens_on_right_click() -> void:
	combat.scripted = false
	player.inventory.add_id(&"hammer", 1)
	window.toggle_inventory()
	await frames(3)
	var row := window.row_node(LootWindow.SIDE_PLAYER, 0)
	var at := _screen(row)
	_mouse(at)
	await frames(1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.button_mask = MOUSE_BUTTON_MASK_RIGHT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await frames(2)
	check(window.context_menu.visible, "context menu shown")
	var labels: Array = []
	for i in window.context_menu.item_count:
		labels.append(window.context_menu.get_item_text(i))
	check(labels.has("Equip") and labels.has("Drop") and labels.has("Assign to hotbar 1"), "entries (%s)" % str(labels))
	check(not combat.aiming, "right-click on the UI does not aim")
	window.context_menu.id_pressed.emit(labels.find("Equip"))
	check(eq.primary() != null and eq.primary().id() == &"hammer", "menu Equip worked")
	window.context_menu.hide()
	window.toggle_inventory()
	combat.scripted = true
	_mouse(Vector2(640, 600))


func test_x_cycles_through_bag_weapons_and_broken_weapon_leaves_equipment() -> void:
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(bag)
	player.equip_item(bag)
	player.inventory.add_id(&"hammer", 1)
	bag.contents.add_id(&"kitchen_knife", 1)
	var hammer := player.inventory.find(&"hammer")
	var knife := bag.contents.find(&"kitchen_knife")
	check(player.cycle_weapon() and eq.primary() == hammer, "X → hammer")
	check(player.cycle_weapon() and eq.primary() == knife, "X → knife (from the bag)")
	check(player.cycle_weapon() and eq.primary() == null, "X → fists")
	check(player.inventory.has(hammer) and player.inventory.has(knife), "both stowed in the main inventory")
	check(player.equip_item(knife).ok, "knife")
	player.on_weapon_broken(knife)
	check(eq.primary() == null and not player.carries(knife) and combat.equipped == null, "broken weapon removed from the hand")


func test_player_carried_round_trip() -> void:
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(bag)
	player.equip_item(bag)
	bag.contents.add_id(&"nails", 50)
	player.inventory.add_id(&"baseball_bat", 1)
	player.equip_item(player.inventory.find(&"baseball_bat"))
	eq.assign_hotbar(0, eq.primary())
	var d: Dictionary = JSON.parse_string(JSON.stringify(player.carried_to_dict()))
	var w0 := player.carried_weight()
	player.carried_from_dict({"inventory": {"items": []}, "equipment": {"slots": {}, "hotbar": []}})
	check_near(player.carried_weight(), 0.0, 0.001, "cleared")
	check(combat.equipped == null, "hands empty")
	player.carried_from_dict(d)
	check_near(player.carried_weight(), w0, 0.001, "same weight after load")
	check(eq.back_bag() != null and eq.back_bag().contents.count_of(&"nails") == 50, "bag + contents")
	check(combat.weapon().id == &"baseball_bat", "combat follows the loaded equipment")
	check(eq.hotbar_item(0) == eq.primary(), "hotbar ref")


# --- Round 6 critic regressions ----------------------------------------------------

func test_equip_from_pack_near_threshold_does_not_flicker() -> void:
	player.inventory.add_id(&"plank", 3)  # 9
	player.inventory.add_id(&"crowbar", 1)  # 11
	player.inventory.add_id(&"water_bottle", 4)  # 15
	player.inventory.add_id(&"nails", 70)  # 15.7 kg
	await frames(2)
	check_near(player.carried_weight(), 15.7, 0.001, "15.7 kg carried")
	check_eq(enc.state, &"overloaded", "overloaded")
	var got := []
	var cb := func(c, st, w): got.append(st)
	EventBus.encumbrance_changed.connect(cb)
	var crowbar := player.inventory.find(&"crowbar")
	check(player.equip_item(crowbar).ok, "equip the crowbar from the pack")
	await frames(2)
	check(got.is_empty(), "same weight, same state: no event, no flicker (%s)" % str(got))
	# A worn bag: moving an item into it changes the weight → at most one event.
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.remove_id(&"nails", 70)
	player.inventory.add(bag)
	check(player.equip_item(bag).ok, "bag on")
	await frames(2)
	got.clear()
	var n0 := enc.emit_count
	var water := player.inventory.find(&"water_bottle")
	check(player.move_item(water, bag.contents).ok, "water → bag")
	await frames(2)
	check_lt(float(enc.emit_count - n0), 1.5, "at most one encumbrance update (%d)" % (enc.emit_count - n0))
	EventBus.encumbrance_changed.disconnect(cb)


func test_take_into_an_equipment_slot_is_refused() -> void:
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"hammer", "count": 1}]
	check(await _open(c), "open")
	var hammer := c.inventory.find(&"hammer")
	var r := c.take(player, hammer, -1, eq.slots[Equipment.PRIMARY])
	check(not r.ok and r.reason == "Use Equip", "only Equipment fills slots (%s)" % str(r))
	check(eq.primary() == null and c.inventory.has(hammer), "nothing moved")


func test_interrupted_bandage_returns_dressing_to_the_bag() -> void:
	var bag := ItemInstance.new(ItemDB.get_item(&"backpack"))
	player.inventory.add(bag)
	player.equip_item(bag)
	bag.contents.add_id(&"bandage", 1)
	injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	check(injuries.bandage_worst().ok, "bandaging with the bag's bandage")
	check_eq(bag.contents.count_of(&"bandage"), 0, "taken from the bag")
	player.take_damage(1.0, null, {})
	await frames(1)
	check_eq(bag.contents.count_of(&"bandage"), 1, "returned to the bag, not the main inventory")
	check_eq(player.inventory.count_of(&"bandage"), 0, "main untouched")


func test_hotbar_slot_survives_drop_and_pickup() -> void:
	player.global_position = Vector3(18, 0.1, 18)
	player.movement.facing = 0.0
	await physics_frames(2)
	player.inventory.add_id(&"hammer", 1)
	var hammer := player.inventory.find(&"hammer")
	check(eq.assign_hotbar(1, hammer).ok, "slot 2")
	var r := player.drop_item(hammer)
	await frames(2)
	check(not bool(hud.hotbar.summary[1].carried) and hud.hotbar.slot_name(1) == "Hammer", "HUD keeps it, greyed")
	check(player.use_hotbar(1).reason == "Not carried", "key refused while on the floor")
	await physics_frames(3)
	check(interaction.interact().ok, "picked up again")
	await frames(2)
	check(eq.hotbar_item(1) == hammer and bool(hud.hotbar.summary[1].carried), "back on the hotbar")
	if eq.primary() == hammer:
		check(player.use_hotbar(1).ok and eq.primary() == null, "key 2 works again (puts it away)")
	check(player.use_hotbar(1).ok and eq.primary() == hammer, "key 2 draws it")
	check(r.ok, "dropped")


func test_duffel_worn_slows_a_little_and_worn_row_shows_effective_weight() -> void:
	var duffel := ItemInstance.new(ItemDB.get_item(&"duffel_bag"))
	duffel.contents.add_id(&"plank", 2)
	player.inventory.add(duffel)
	check(player.equip_item(duffel).ok, "duffel on the back")
	check_eq(enc.state, &"ok", "5.4 kg is ok")
	check_near(player.movement.speed_modifiers.get(&"worn_bag", 1.0), 0.97, 0.0001, "bulky duffel ×0.97")
	check_near(enc.weight, 1.8 + 6.0 * 0.6, 0.001, "duffel contents count 60 %")
	window.toggle_inventory()
	await frames(2)
	var r := window.rows(LootWindow.SIDE_PLAYER)
	check(r[0].equipped and String(r[0].name).ends_with("7.8→5.40") and String(r[0].tip).contains("counts 5.40 kg") and r[0].weight == "5.40", "worn row shows the effective weight (%s)" % str(r[0]))
	window.toggle_inventory()
	check(player.unequip_item(duffel).ok, "off")
	await frames(1)
	check_near(player.movement.speed_modifiers.get(&"worn_bag", 1.0), 1.0, 0.0001, "modifier cleared")


func test_nested_bag_in_pack_updates_carried_weight() -> void:
	var outer := ItemInstance.new(ItemDB.get_item(&"duffel_bag"))
	var inner := ItemInstance.new(ItemDB.get_item(&"backpack"))
	outer.contents.add(inner)
	player.inventory.add(outer)
	await frames(1)
	var w0 := player.carried_weight()
	inner.contents.add_id(&"plank", 2)  # API mutation two levels down
	await frames(1)
	check_near(player.carried_weight(), w0 + 6.0, 0.001, "carried weight follows a bag inside a bag in the pack")
	check_eq(window.rows(LootWindow.SIDE_PLAYER).size(), 1, "one row (closed bag)")
