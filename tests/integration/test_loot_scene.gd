extends "res://tests/test_case.gd"
## Round 5 in the real test_ground scene: furniture containers, lazy
## seeded loot, the loot window (ref-4 top panels), corpse search,
## bandages as consumables, pickup into the inventory.
##
## House A: origin (-14, 0, -10); the first kitchen cabinet is
## "HouseA/kitchen/0" against the kitchen's west partition, front facing +X.

var scene: Node
var player: Player
var ctrl: PlayerController
var combat: MeleeCombat
var injuries: InjuryComponent
var interaction: PlayerInteraction
var spawner: ZombieSpawner
var hud: CanvasLayer
var window: LootWindow
var house: HouseBlockout
var world: WorldConfig


func setup() -> void:
	await _load()


func _load() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	combat = player.get_node("Combat")
	injuries = player.get_node("Injuries")
	interaction = player.get_node("Interaction")
	hud = scene.get_node("HUD")
	window = scene.get_node("LootWindow")
	house = scene.get_node("Buildings/HouseA")
	world = scene.get_node("World")
	ctrl.scripted = true
	combat.scripted = true
	interaction.scripted = true
	injuries.rng.seed = 3
	var nav: NavBaker = scene.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(3)


func teardown() -> void:
	await despawn(scene)


func _container(pid: String) -> LootContainer:
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and c.persist_id == pid and scene.is_ancestor_of(c):
			return c
	return null


## Stand 0.75 m in front of [c], facing it.
func _stand_at(c: LootContainer, dist: float = 0.75) -> void:
	var front := c.global_basis.z
	front.y = 0.0
	front = front.normalized()
	var reach := c.size.z * 0.5 + dist if c.size != Vector3.ZERO else dist
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = c.global_position + front * reach + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	player.movement.facing = BodyHelpers.yaw_for(-front)
	await physics_frames(4)


## Open [c] through the interaction (rummage) and wait until open.
func _open(c: LootContainer) -> bool:
	await _stand_at(c)
	if interaction.current_target == null or interaction.current_target.body() != c:
		fail("container %s not targeted (target %s)" % [c.persist_id, interaction.current_target.body() if interaction.current_target else null])
		return false
	var r := interaction.interact()
	if not r.get("ok", false):
		fail("search refused: %s" % str(r))
		return false
	var ok := await wait_physics_until(func(): return c.is_open_for(player), 120)
	await physics_frames(2)  # the interaction target refreshes once not busy
	return ok


static func _snapshot(inv: ItemContainer) -> String:
	var parts: PackedStringArray = []
	for it in inv.items:
		parts.append("%s×%d@%d" % [it.id(), it.stack, it.condition])
	return ",".join(parts)


func _expected_counts(c: LootContainer) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = LootResolver.seed_for(world.world_seed, c.persist_id)
	var out := {}
	for f in c.fixed_items:
		out[StringName(f.id)] = out.get(StringName(f.id), 0) + int(f.get("count", 1))
	for e in LootResolver.roll(c.resolve_table(), rng, world.world_age_days):
		out[e.id] = out.get(e.id, 0) + int(e.count)
	return out


func _counts(inv: ItemContainer) -> Dictionary:
	var out := {}
	for it in inv.items:
		out[it.id()] = out.get(it.id(), 0) + it.stack
	return out


# --- Placement ---------------------------------------------------------------------

func test_house_has_furniture_and_eight_containers() -> void:
	check_gt(float(house.containers.size()), 7.5, "≥ 8 containers in House A (%d)" % house.containers.size())
	var types := {}
	for c in house.containers:
		types[c.container_type] = true
		check(c.collision_layer & 1 and c.collision_layer & 8, "%s on layers 1 + 4" % c.persist_id)
		check(c.room_type != &"", "%s knows its room" % c.persist_id)
		check(c.building_type == &"house", "%s building type" % c.persist_id)
		check(not c.searched, "%s not rolled before opening" % c.persist_id)
		check(c.inventory.is_empty(), "%s empty until opened" % c.persist_id)
	for t in [&"kitchen_cabinet", &"counter", &"fridge", &"bathroom_cabinet", &"dresser", &"shelf"]:
		check(types.has(t), "has a %s" % t)
	var plain := 0
	for f in house.furniture:
		if not f is LootContainer:
			plain += 1
	check_gt(float(plain), 2.5, "bed, sofa, toilet as plain furniture (%d)" % plain)
	var ids := {}
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		check(not ids.has(c.persist_id), "unique persist id %s" % c.persist_id)
		ids[c.persist_id] = true
	var garage: HouseBlockout = scene.get_node("Buildings/Garage")
	check_eq(garage.containers.size(), 2, "garage: tool crate + shelf")
	check_eq(garage.containers[0].resolve_table().resource_path, "res://data/loot/garage/tool_crate.tres", "garage tool crate table")
	check(_container("Map/SupplyCrate") != null, "standalone supply crate outside")
	var dresser: LootContainer = null
	for c in house.containers:
		if c.container_type == &"dresser":
			dresser = c
	check_eq(LootTableDB.resolve_id(dresser.building_type, dresser.room_type, dresser.container_type), "bedroom_dresser", "dresser → bedroom_dresser")
	check(house.room_at(Vector3(-13, 0.5, -9)).room_type == &"bedroom", "Room.room_type")


# --- Open / rummage / reopen ----------------------------------------------------------

func test_open_kitchen_cabinet_rummages_then_shows_items() -> void:
	var c := _container("HouseA/kitchen/0")
	check(c != null and c.container_type == &"kitchen_cabinet", "kitchen cabinet")
	c.fixed_items = [{"id": &"canned_beans", "count": 1}]
	await _stand_at(c)
	check(interaction.current_target != null and interaction.current_target.body() == c, "targeted")
	check_eq(interaction.current_actions[0].label, "Search Kitchen cabinet", "action label")
	var opened := []
	var cb := func(a, cont): opened.append(cont)
	EventBus.container_opened.connect(cb)
	var r := interaction.interact()
	check(r.ok and r.get("searching", false), "rummage started (%s)" % str(r))
	check(player.is_busy, "busy while rummaging")
	check(not c.searched and c.inventory.is_empty(), "nothing rolled yet")
	check(not window.is_open(), "window not open yet")
	await physics_frames(20)
	check(hud.action_bar.visible and hud.action_bar.value > 5.0, "HUD rummage progress (%.0f)" % hud.action_bar.value)
	check(hud.notice_label.text.begins_with("Rummaging"), "HUD notice (%s)" % hud.notice_label.text)
	var p0 := player.global_position
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(20)
	ctrl.scripted_direction = Vector3.ZERO
	check_lt(p0.distance_to(player.global_position), 0.01, "cannot walk while rummaging")
	var t0 := Engine.get_physics_frames()
	check(await wait_physics_until(func(): return c.is_open_for(player), 120), "opened")
	var secs := float(Engine.get_physics_frames() - t0 + 40) / 60.0
	check(secs > 0.5 and secs < 1.2, "rummage 0.5-1 s (%.2f)" % secs)
	check(not player.is_busy, "free again")
	check(c.searched, "rolled on first open")
	check_eq(opened.size(), 1, "container_opened once")
	check_eq(_counts(c.inventory), _expected_counts(c), "contents = fixed + seeded roll")
	check_gt(float(c.inventory.item_count()), 0.5, "items appeared")
	await frames(2)
	check(window.is_open() and window.container_panel_visible() and window.player_panel_visible(), "loot window: both panels")
	check_eq(window.container_title.text, "Kitchen cabinet", "container header")
	check_eq(window.rows(LootWindow.SIDE_CONTAINER).size(), c.inventory.items.size(), "one row per stack")
	check_eq(window.visible_row_count(LootWindow.SIDE_CONTAINER), c.inventory.items.size(), "row nodes")
	check(window.container_weight.text.ends_with(" kg"), "container weight in kg (%s)" % window.container_weight.text)
	check_eq(window.rows(LootWindow.SIDE_CONTAINER)[0].category, LootWindow.category_short(c.inventory.items[0].data), "type column")
	var room_label: Label = hud.room_label
	check(not room_label.get_global_rect().intersects(window.root.get_global_rect()), "room label not hidden by the window")
	check(window.player_weight.text.ends_with("/ 15 kg"), "player header weight (%s)" % window.player_weight.text)
	check_eq(window.loot_all_button.text, "Loot All", "Loot All button")
	check_eq(window.transfer_all_button.text, "Transfer All", "Transfer All button")
	await physics_frames(20)
	check_gt(c.lid_open_fraction(), 0.9, "lid swung open")
	check_eq(interaction.current_actions[0].label, "Close", "Close action while open")
	EventBus.container_opened.disconnect(cb)


func test_reopen_keeps_the_same_items() -> void:
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"soda", "count": 2}]
	check(await _open(c), "open 1")
	var snap := _snapshot(c.inventory)
	var first_items := c.inventory.items.duplicate()
	var rc := interaction.interact()
	check(rc.ok, "E → Close (%s, target %s, actions %s)" % [str(rc), interaction.current_target, str(interaction.current_actions)])
	await physics_frames(2)
	check(not c.is_open() and not window.is_open(), "closed")
	await physics_frames(20)
	check_lt(c.lid_open_fraction(), 0.1, "lid closed")
	var t0 := Engine.get_physics_frames()
	check(await _open(c), "open 2")
	check_lt(float(Engine.get_physics_frames() - t0), 60.0, "re-open rummage is short (0.5 s)")
	check_eq(_snapshot(c.inventory), snap, "same items, not re-rolled")
	check_eq(c.inventory.items, first_items, "same instances")


func test_loot_all_transfer_all_and_row_clicks() -> void:
	var c := _container("HouseA/kitchen/0")
	c.fixed_items = [{"id": &"nails", "count": 20}, {"id": &"water_bottle", "count": 1}]
	check(await _open(c), "open")
	var moved := []
	var cb := func(f, t, item): moved.append([f, t, item])
	EventBus.item_transferred.connect(cb)
	var total := c.inventory.item_count()
	var want := _counts(c.inventory)
	# Shift-click: one nail.
	var nails_i := c.inventory.index_of(c.inventory.find(&"nails"))
	var r := window.transfer_index(LootWindow.SIDE_CONTAINER, nails_i, true)
	check(r.ok and r.moved == 1, "shift-click moves one (%s)" % str(r))
	check_eq(player.inventory.count_of(&"nails"), 1, "1 nail carried")
	check_eq(c.inventory.count_of(&"nails"), 19, "19 left")
	check(moved.size() == 1 and moved[0][0] == c and moved[0][1] == player and moved[0][2].id == &"nails", "item_transferred(from, to, item)")
	# Click: whole stack.
	r = window.transfer_index(LootWindow.SIDE_CONTAINER, c.inventory.index_of(c.inventory.find(&"nails")))
	check(r.ok and r.moved == 19, "click moves the stack")
	check_eq(player.inventory.find_all(&"nails").size(), 1, "merged into one stack")
	# Loot All.
	r = window.loot_all()
	check(r.ok, "loot all (%s)" % str(r))
	check(c.inventory.is_empty(), "container empty")
	check_eq(player.inventory.item_count(), total, "player has everything")
	check_eq(_counts(player.inventory), want, "same items")
	await frames(2)
	check_eq(window.visible_row_count(LootWindow.SIDE_CONTAINER), 0, "no container rows")
	check(window._empty_labels[LootWindow.SIDE_CONTAINER].visible, "(empty) shown")
	check_eq(window.visible_row_count(LootWindow.SIDE_PLAYER), player.inventory.items.size(), "player rows")
	check(window.loot_all_button.disabled, "Loot All disabled when empty")
	# Transfer All back.
	r = window.transfer_all()
	check(r.ok and player.inventory.is_empty() and c.inventory.item_count() == total, "transfer all back")
	# A real mouse click on a row (left button) moves the stack.
	await frames(2)
	var row: Button = window.row_node(LootWindow.SIDE_CONTAINER, 0)
	var at := row.get_viewport().get_final_transform() * row.get_global_rect().get_center()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	Input.parse_input_event(ev)
	await frames(2)
	var ev2 := ev.duplicate() as InputEventMouseButton
	ev2.pressed = false
	ev2.button_mask = 0
	Input.parse_input_event(ev2)
	await frames(3)
	check_gt(float(player.inventory.item_count()), 0.5, "mouse click on a row transferred it")
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "the click did not start an attack")
	EventBus.item_transferred.disconnect(cb)


func test_damage_interrupts_rummaging() -> void:
	var c := _container("HouseA/bathroom/0")
	await _stand_at(c)
	check(interaction.interact().ok, "rummage")
	await physics_frames(20)
	player.take_damage(2.0, null, {})
	await physics_frames(2)
	check(not player.is_busy, "interrupted")
	check(not hud.action_bar.visible, "progress bar gone")
	check_eq(hud.notice_label.text, "Interrupted", "HUD notice")
	await physics_frames(60)
	check(not c.is_open() and not c.searched, "nothing opened, nothing rolled")
	check(await _open(c), "can search again")


func test_double_press_same_row_moves_one_stack() -> void:
	var c := _container("HouseA/kitchen/0")
	check(await _open(c), "open")
	c.inventory.clear()
	c.inventory.add_id(&"hammer", 1)
	c.inventory.add_id(&"saw", 1)
	c.inventory.add_id(&"wrench", 1)
	window.refresh()
	var row := window.row_node(LootWindow.SIDE_CONTAINER, 0)
	var nodes_before := window.container_list.get_child_count()
	row.pressed.emit()
	row.pressed.emit()  # same frame: the list has not refreshed yet
	check_eq(player.inventory.items.size(), 1, "exactly one stack moved")
	check_eq(player.inventory.count_of(&"hammer"), 1, "the hammer it showed")
	check_eq(c.inventory.items.size(), 2, "saw + wrench stay")
	await frames(3)
	check_eq(window.visible_row_count(LootWindow.SIDE_CONTAINER), 2, "two rows after refresh")
	check_eq(window.container_list.get_child_count(), nodes_before, "rows pooled, not rebuilt")


func test_equipped_weapon_cannot_be_stored_mid_swing() -> void:
	var c := _container("HouseA/kitchen/0")
	player.inventory.add_id(&"baseball_bat", 1)
	var bat := player.inventory.find(&"baseball_bat")
	combat.equip(bat)
	player.inventory.add_id(&"apple", 1)
	check(await _open(c), "open")
	check(combat.attack_now(0.0), "swinging")
	check_eq(player.can_release_item(bat).reason, "Mid-swing", "can_release_item refuses")
	var r := c.put(player, bat)
	check(not r.ok and r.reason == "Mid-swing", "put refused (%s)" % str(r))
	r = window.transfer_all()
	check_eq(r.get("reason", ""), "Mid-swing", "Transfer All skips the swung weapon (%s)" % str(r))
	check(player.inventory.has(bat), "bat still carried")
	check_eq(player.inventory.count_of(&"apple"), 0, "…the apple went in")
	check(combat.equipped == bat, "still equipped")
	await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.IDLE, 120)
	check(player.can_release_item(bat).ok, "free once the swing ends")
	check(c.put(player, bat).ok, "stored after the swing")


func test_capacity_refusal_greys_rows() -> void:
	var c := _container("HouseA/kitchen/0")
	check(await _open(c), "open")
	c.inventory.clear()
	c.inventory.add_id(&"plank", 1)
	c.inventory.add_id(&"bandage", 1)
	player.inventory.add_id(&"plank", 4)  # 12 of 15 kg
	player.inventory.add_id(&"water_bottle", 1)  # 13 kg: a 3 kg plank won't fit
	check_near(player.inventory.total_weight(), 13.0, 0.001, "13 kg carried")
	await frames(3)
	var rows := window.rows(LootWindow.SIDE_CONTAINER)
	var plank_i := c.inventory.index_of(c.inventory.find(&"plank"))
	var band_i := c.inventory.index_of(c.inventory.find(&"bandage"))
	check(not window.row_enabled(LootWindow.SIDE_CONTAINER, plank_i), "plank row greyed (does not fit)")
	check_eq(rows[plank_i].reason, "Too heavy", "reason")
	check(window.row_enabled(LootWindow.SIDE_CONTAINER, band_i), "bandage row fine")
	var row: Button = window.row_node(LootWindow.SIDE_CONTAINER, plank_i)
	check_eq(row.tooltip_text, "Too heavy", "tooltip")
	check_lt(row.modulate.a, 0.9, "greyed")
	var r := window.transfer_index(LootWindow.SIDE_CONTAINER, plank_i)
	check(not r.ok and r.reason == "Too heavy", "refused (%s)" % str(r))
	check_eq(c.inventory.count_of(&"plank"), 1, "plank stays")
	check_near(player.inventory.total_weight(), 13.0, 0.001, "nothing added")
	await frames(1)
	check_eq(window.status_label.text, "Too heavy", "window notice")
	# Loot All moves what fits and says why the rest stayed.
	r = window.loot_all()
	check(r.ok and r.moved == 1 and r.get("reason", "") == "Too heavy", "partial loot all (%s)" % str(r))
	# Pickup refusal too.
	var bat := WorldItem.for_instance(ItemInstance.new(preload("res://data/items/weapons/crowbar.tres")))
	player.inventory.add_id(&"plank", 1)
	var pr := player.pick_up_item(bat.item)
	check(not pr.ok and pr.reason == "Too heavy", "pickup refused when full")
	bat.free()


func test_window_closes_walking_away_and_on_e() -> void:
	# The living-room shelf faces east across the open living room.
	var c := _container("HouseA/living_room/0")
	check(await _open(c), "open")
	# Walk east (away from the cabinet's front) for ~1 s at jog speed.
	ctrl.scripted_direction = c.global_basis.z.normalized()
	check(await wait_physics_until(func(): return not c.is_open(), 120), "closed after walking away")
	ctrl.scripted_direction = Vector3.ZERO
	check_gt(c.distance_to(player), 2.0, "more than 2 m away (%.2f)" % c.distance_to(player))
	await frames(2)
	check(not window.is_open() and not window.container_panel_visible() and not window.player_panel_visible(), "window gone")
	# E (the real input action) closes it too.
	check(await _open(c), "re-open")
	await frames(2)
	check(window.is_open(), "open again")
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var ev2 := InputEventAction.new()
	ev2.action = &"interact"
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await physics_frames(3)
	check(not c.is_open() and not window.is_open(), "E closed it")
	check(not player.is_busy, "…without starting another rummage")


func test_tab_toggles_player_panel_alone() -> void:
	player.inventory.add_id(&"apple", 2)
	player.inventory.add_id(&"tin_opener", 1)
	check(not window.player_panel_visible(), "hidden at start")
	var ev := InputEventAction.new()
	ev.action = &"toggle_inventory"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var ev2 := InputEventAction.new()
	ev2.action = &"toggle_inventory"
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await frames(2)
	check(window.player_panel_visible() and not window.container_panel_visible(), "Tab: player panel alone")
	check_eq(window.visible_row_count(LootWindow.SIDE_PLAYER), 2, "rows: apples ×2 (one stack), tin opener")
	check_eq(window.rows(LootWindow.SIDE_PLAYER)[0].count, "×2", "stack count shown")
	check(window.transfer_all_button.disabled, "Transfer All disabled without a container")
	window.toggle_inventory()
	check(not window.player_panel_visible(), "Tab again hides it")


func test_same_seed_same_loot_across_scene_loads() -> void:
	var ids := ["HouseA/kitchen/0", "HouseA/kitchen/1", "HouseA/kitchen/2", "HouseA/bedroom/0", "HouseA/bathroom/0", "HouseA/living_room/0", "Garage/garage/0", "Map/SupplyCrate"]
	var first := {}
	for pid in ids:
		var c := _container(pid)
		check(c != null, "%s exists" % pid)
		c.ensure_loot()
		first[pid] = _snapshot(c.inventory)
	await despawn(scene)
	await _load()
	var nonempty := 0
	for pid in ids:
		var c := _container(pid)
		c.ensure_loot()
		check_eq(_snapshot(c.inventory), first[pid], "%s identical after a fresh load" % pid)
		if not c.inventory.is_empty():
			nonempty += 1
	check_gt(float(nonempty), 3.5, "most containers hold something (%d)" % nonempty)
	# Another world seed rolls different loot (for at least one container).
	await despawn(scene)
	await _load()
	world.world_seed = 4242
	var differs := 0
	for pid in ids:
		var c := _container(pid)
		c.ensure_loot()
		if _snapshot(c.inventory) != first[pid]:
			differs += 1
	check_gt(float(differs), 0.5, "different world seed → different loot (%d differ)" % differs)


# --- Corpses -------------------------------------------------------------------------

func test_search_corpse_after_killing_a_zombie() -> void:
	player.global_position = Vector3(20, 0.1, 20)
	player.movement.facing = 0.0
	await physics_frames(3)
	var z := spawner.spawn_at(Vector3(20, 0, 19.0))
	z.senses.enabled = false
	await physics_frames(2)
	z.take_damage(999.0, player, {})
	await physics_frames(3)
	var corpses := tree.get_nodes_in_group(&"corpse")
	check_eq(corpses.size(), 1, "one corpse")
	var corpse: ZombieCorpse = corpses[0]
	check(corpse is LootContainer and corpse.collision_layer == 8, "corpse: container on layer 4 only")
	check(corpse.persist_id.begins_with("corpse/"), "stable id %s" % corpse.persist_id)
	player.global_position = corpse.global_position + Vector3(0, 0.1, 0.9)
	player.movement.facing = 0.0
	await physics_frames(4)
	check(interaction.current_target != null and interaction.current_target.body() == corpse, "corpse targeted")
	check_eq(interaction.current_actions[0].label, "Search corpse", "Search corpse")
	check(interaction.current_actions[0].enabled, "enabled now")
	check(interaction.interact().ok, "search")
	check(player.is_busy, "rummaging the pockets")
	check(await wait_physics_until(func(): return corpse.is_open_for(player), 120), "opened")
	check_eq(corpse.resolve_table().resource_path, "res://data/loot/zombie_corpse.tres", "zombie_corpse table")
	check_eq(_counts(corpse.inventory), _expected_counts(corpse), "pockets = seeded corpse roll")
	await frames(2)
	check(window.is_open() and window.container_title.text == "Zombie corpse", "loot window on the corpse")
	corpse.inventory.add_id(&"rag", 1)
	var r := window.loot_all()
	check(r.ok and corpse.inventory.is_empty(), "looted the corpse")
	check_gt(float(player.inventory.count_of(&"rag")), 0.5, "rag carried")


func test_corpse_ids_unique_across_spawners_on_one_seed() -> void:
	var other := ZombieSpawner.new()
	other.name = "Zombies2"
	other.auto_spawn = false
	other.seed = spawner.seed
	scene.add_child(other)
	var fresh := ZombieSpawner.new()
	fresh.name = "Zombies3"
	fresh.auto_spawn = false
	fresh.seed = spawner.seed
	scene.add_child(fresh)
	var ids := {}
	var seeds_equal := 0
	for i in 3:
		var a := spawner.spawn_at(Vector3(30 + i, 0, 30))
		var b := other.spawn_at(Vector3(30 + i, 0, 33))
		if a.ai_seed == b.ai_seed:
			seeds_equal += 1
		for z in [a, b]:
			z.senses.enabled = false
			check(not ids.has(z.spawn_id), "unique spawn id %s" % z.spawn_id)
			ids[z.spawn_id] = true
	check_eq(seeds_equal, 3, "same seed → same ai seeds (the old corpse-id collision)")
	check_eq(spawner.spawn_counter, 3, "monotonic counter")
	await physics_frames(2)
	for z in tree.get_nodes_in_group(&"zombie"):
		z.take_damage(999.0, player, {})
	await physics_frames(2)
	var pids := {}
	for c in tree.get_nodes_in_group(&"corpse"):
		check(not pids.has(c.persist_id), "unique corpse id %s" % c.persist_id)
		pids[c.persist_id] = true
	check_eq(pids.size(), 6, "six distinct corpses")
	check(pids.has("corpse/Zombies/1") and pids.has("corpse/Zombies2/1"), "ids = spawner path + counter (%s)" % str(pids.keys()))


# --- Bandages as consumables ------------------------------------------------------------

func test_bandage_consumes_a_bandage_and_none_is_refused() -> void:
	var refusals := []
	var cb := func(a, t, why): refusals.append(why)
	EventBus.interaction_refused.connect(cb)
	var inj := injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	var r := injuries.bandage_worst()
	check(not r.ok and r.reason == "No bandages", "refused without dressings (%s)" % str(r))
	check(refusals.has("No bandages"), "refusal event")
	await frames(1)
	check_eq(hud.notice_label.text, "No bandages", "HUD notice")
	check(not player.is_busy, "not busy")
	player.inventory.add_id(&"bandage", 2)
	player.inventory.add_id(&"rag", 1)
	r = injuries.bandage_worst()
	check(r.ok and r.dressing == &"bandage", "the best dressing (bandage) is used")
	check_eq(player.inventory.count_of(&"bandage"), 1, "one bandage consumed")
	check_eq(player.inventory.count_of(&"rag"), 1, "rag kept")
	check(await wait_physics_until(func(): return inj.bandaged, 60 * 5), "bandaged")
	check_near(inj.bandage_quality, 1.0, 0.001, "clean bandage quality")
	check_lt(inj.rebleed_left, 0.0, "a clean bandage holds")
	# Interrupted: the dressing comes back.
	var inj2 := injuries.add_injury(Injury.Region.RIGHT_ARM, Injury.Type.SCRATCH)
	check(injuries.bandage_worst().ok, "second bandage")
	check_eq(player.inventory.count_of(&"bandage"), 0, "taken")
	player.take_damage(1.0, null, {})
	await frames(1)
	check(not inj2.bandaged, "interrupted")
	check_eq(player.inventory.count_of(&"bandage"), 1, "bandage returned on interrupt")
	EventBus.interaction_refused.disconnect(cb)


func test_interrupted_bandage_with_full_pack_drops_the_dressing() -> void:
	player.inventory.add_id(&"bandage", 1)
	injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	check(injuries.bandage_worst().ok, "bandaging")
	player.inventory.add_id(&"plank", 5)  # 15 kg: the pack is now full
	var before := tree.get_nodes_in_group(&"world_item").size()
	player.take_damage(1.0, null, {})
	await frames(2)
	check_eq(player.inventory.count_of(&"bandage"), 0, "no room to return it")
	var dropped := tree.get_nodes_in_group(&"world_item")
	check_eq(dropped.size(), before + 1, "dropped at the player's feet")
	var w: WorldItem = dropped[-1]
	check(w.item.id() == &"bandage" and w.global_position.distance_to(player.global_position) < 1.0, "a bandage WorldItem nearby")


func test_bandage_refunded_when_the_wound_vanishes() -> void:
	player.inventory.add_id(&"bandage", 1)
	var inj := injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.SCRATCH)
	check(injuries.bandage_worst().ok, "bandaging")
	check_eq(player.inventory.count_of(&"bandage"), 0, "taken")
	injuries.injuries.erase(inj)  # healed / removed meanwhile
	check(await wait_physics_until(func(): return not player.is_busy, 60 * 5), "finished")
	check_eq(player.inventory.count_of(&"bandage"), 1, "dressing refunded")


func test_rag_is_worse_and_can_reopen() -> void:
	# A rag that always gives way (rebleed_chance 1) → deterministic.
	var bad_rag: MedicalData = ItemDB.get_item(&"rag").duplicate()
	bad_rag.rebleed_chance = 1.0
	player.inventory.add(ItemInstance.new(bad_rag, -1, 1))
	var inj := injuries.add_injury(Injury.Region.LEFT_LEG, Injury.Type.LACERATION)
	var reopened := []
	var cb := func(c, region): reopened.append(region)
	EventBus.wound_reopened.connect(cb)
	check(injuries.bandage_worst().ok, "rag bandage")
	check(player.inventory.is_empty(), "rag consumed")
	check(await wait_physics_until(func(): return inj.bandaged, 60 * 5), "bandaged")
	check_near(inj.bandage_quality, 0.5, 0.001, "rag quality 0.5")
	check_lt(InjuryComponent.heal_rate(inj, injuries.profile), injuries.profile.bandaged_heal_multiplier, "heals slower than a bandage")
	check(not inj.bleeding, "bleeding stopped for now")
	injuries.tick(59.0)
	check(inj.bandaged and not inj.bleeding, "holds for 60 s")
	injuries.tick(2.0)
	check(not inj.bandaged and inj.bleeding, "bleeding resumed after 60 s")
	check_eq(reopened, [&"left_leg"], "wound_reopened")
	await frames(1)
	check(hud.notice_label.text.contains("reopened"), "HUD notice (%s)" % hud.notice_label.text)
	EventBus.wound_reopened.disconnect(cb)
	# The real rag: 50 % over many dressings.
	var rag := ItemDB.get_item(&"rag") as MedicalData
	var n := 0
	injuries.rng.seed = 99
	for i in 400:
		if injuries.rng.randf() < rag.rebleed_chance:
			n += 1
	check_near(n / 400.0, 0.5, 0.08, "rag rebleed ≈ 50 %")


# --- Pickup into the inventory -------------------------------------------------------------

func test_pickup_into_inventory_and_x_cycles() -> void:
	player.global_position = Vector3(-6.5, 0.1, -2.5)
	player.movement.facing = BodyHelpers.yaw_for(Vector3(0, 0, -1))
	await physics_frames(3)
	check(interaction.current_target != null and interaction.current_target.display_name() == "Baseball Bat", "bat targeted")
	check(interaction.interact().ok, "picked up")
	check_eq(player.inventory.count_of(&"baseball_bat"), 1, "bat in the inventory")
	check_near(player.inventory.total_weight(), 1.5, 0.001, "1.5 kg")
	check_eq(combat.weapon().id, &"baseball_bat", "auto-equipped")
	player.inventory.add_id(&"hammer", 1)
	player.inventory.add_id(&"apple", 1)
	check(player.cycle_weapon() and combat.weapon().id == &"hammer", "X → hammer (from inventory)")
	check(player.cycle_weapon() and combat.weapon() == combat.fists, "X → fists (apple is not a weapon)")
	check(player.cycle_weapon() and combat.weapon().id == &"baseball_bat", "X → bat")
	# Moving the equipped weapon out of the inventory unequips it.
	var c := _container("HouseA/kitchen/0")
	check(await _open(c), "open cabinet")
	var bat := player.inventory.find(&"baseball_bat")
	check(c.put(player, bat).ok, "stored the bat")
	check(combat.weapon() == combat.fists, "stored weapon leaves the hands")
	await frames(1)
	check_eq(hud.weapon_label.text, "Weapon: Fists", "HUD follows")
