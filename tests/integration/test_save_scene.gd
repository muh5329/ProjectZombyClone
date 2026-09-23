extends "res://tests/test_case.gd"
## Round 10 (critic fixes) in the real test_ground scene: a tampered save
## refused through the real load path; stable data ids (a save still
## applies after the plan's furniture array is reordered) and the explicit
## destroyed list; hotbar slots pointing at uncarried items survive; no
## spurious infection notice on load; autosave rules (rested wake only, no
## danger); the menus (named slots, overwrite / delete confirmations, the
## loading overlay, "Unsaved progress will be lost"); a new game starts
## inside House A with the spare t-shirt that tears into rags.

const SLOT := "save scene test"
const SLOT_2 := "save scene test 2"

var scene: Node
var player: Player
var spawner: ZombieSpawner
var house: HouseBlockout


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	_bind(scene)
	spawner.auto_spawn = false
	var nav: NavBaker = scene.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(3)


func teardown() -> void:
	if SaveManager.is_confirming():
		SaveManager.answer(false)
	SaveManager.show_loading(false)
	await despawn(scene)
	for s in [SLOT, SLOT_2]:
		SaveFile.delete_slot(s)
	tree.paused = false


func _bind(map: Node) -> void:
	scene = map
	player = map.get_node("Player")
	spawner = map.get_node("Zombies")
	house = map.get_node("Buildings/HouseA")
	player.get_node("Controller").scripted = true
	player.get_node("Interaction").scripted = true


func _reload(slot: String) -> bool:
	var r: Dictionary = await SaveManager.load_game(slot, scene)
	if r.ok:
		_bind(r.map)
	return r.ok


func _container(pid: String) -> LootContainer:
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and c.persist_id == pid and scene.is_ancestor_of(c) and not c.is_queued_for_deletion():
			return c
	return null


func _furniture(type: StringName, room: String) -> StaticBody3D:
	for f in house.furniture:
		if is_instance_valid(f) and not f.is_queued_for_deletion() and f.get_meta(&"furniture_type", &"") == type and String(f.name).contains(room):
			return f
	return null


# --- Two-phase load: tampered data never touches the running game -------------------

func test_tampered_save_is_refused_before_anything_changes() -> void:
	player.inventory.add_id(&"apple", 2)
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	for tamper in ["null position", "item path", "negative health", "huge count", "map outside maps"]:
		var r0 := SaveManager.read_slot(SLOT)
		var d: Dictionary = r0.data
		match tamper:
			"null position": d.player.position = null
			"item path": d.player.carried.inventory.items[0] = {"path": "res://maps/test_ground.tscn", "count": 1}
			"negative health": d.player.health.health = -5.0
			"huge count": d.player.carried.inventory.items[0].count = 1e12
			"map outside maps": d.map = "res://ui/menus/main_menu.tscn"
		SaveFile.write_atomic(SaveFile.world_path(SLOT), SaveFile.to_json(d))
		var before_scene := scene
		var r: Dictionary = await SaveManager.load_game(SLOT, scene)
		check(not r.ok and String(r.error).begins_with("Corrupt save"), "%s refused (%s)" % [tamper, str(r.get("error", ""))])
		check(before_scene.is_inside_tree() and GameManager.player == player, "%s: the running game is untouched" % tamper)
		check(not SaveManager.loading and not SaveManager.is_loading_shown(), "%s: no load in progress" % tamper)
		check(SaveManager.save_game(SLOT, scene).ok, "re-save a clean copy")
	check_eq(player.inventory.count_of(&"apple"), 2, "inventory as it was")
	check_eq(SaveManager.save_game("", scene).get("error", ""), "Invalid save name", "empty slot name refused")


# --- Stable ids from data --------------------------------------------------------------

func test_ids_come_from_plan_data_and_survive_reordering() -> void:
	var fridge := _container("HouseA/kitchen/2")
	check(fridge != null and fridge.container_type == &"fridge", "container ids from the plan data")
	var door: Door = null
	for d in house.doors:
		if d.persist_id == "HouseA/front_door":
			door = d
	check(door != null, "door ids from the plan data (%s)" % str(house.doors.map(func(x): return x.persist_id)))
	check(FurnitureWork.of(_furniture(&"sofa", "LivingRoom")).persist_id == "HouseA/sofa/furniture", "furniture work ids")
	# World state tied to ids: a searched fridge, a moved shelf, a
	# destroyed dresser, a sofa pushed nowhere.
	fridge.ensure_loot()
	fridge.inventory.clear()
	fridge.inventory.add_id(&"soda", 3)
	var shelf := _furniture(&"shelf", "LivingRoom")
	var fw := FurnitureWork.of(shelf)
	player.global_position = shelf.global_position + Vector3(0.9, 0.1, 0.0)
	await physics_frames(3)
	fw._finish_block(player)
	check(fw.is_blocking() and door.furniture_blocker() == shelf, "shelf blocks the front door")
	var dresser := _furniture(&"dresser", "Bedroom")
	FurnitureWork.of(dresser).destroy(null)
	await physics_frames(2)
	player.global_position = Vector3(-9, 0.1, -4.6)
	await physics_frames(2)
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	var d: Dictionary = SaveManager.read_slot(SLOT).data
	check((d.destroyed as Array).has("HouseA/bedroom/0/furniture"), "destroyed list names the dresser (%s)" % str(d.destroyed))
	# Reorder the plan's furniture (and openings) — ids are data, not order.
	var plan: BuildingPlan = house.plan
	var original: Array = plan.furniture.duplicate()
	var reversed := original.duplicate()
	reversed.reverse()
	plan.furniture.assign(reversed)
	var ok := await _reload(SLOT)
	plan.furniture.assign(original)
	check(ok, "loaded with the reordered plan")
	if not ok:
		return
	var fridge2 := _container("HouseA/kitchen/2")
	check(fridge2 != null and fridge2.container_type == &"fridge", "the fridge is still HouseA/kitchen/2")
	check(fridge2.searched and fridge2.inventory.count_of(&"soda") == 3 and fridge2.inventory.items.size() == 1, "its contents came back to it")
	var shelf2 := _furniture(&"shelf", "LivingRoom")
	var door2: Door = null
	for dd in house.doors:
		if dd.persist_id == "HouseA/front_door":
			door2 = dd
	check(shelf2 != null and FurnitureWork.of(shelf2).is_blocking() and door2.furniture_blocker() == shelf2, "the same shelf blocks the same door")
	check(_furniture(&"dresser", "Bedroom") == null, "the destroyed dresser stays gone")
	check(_furniture(&"wardrobe", "Bedroom") != null, "the other bedroom furniture is still there")


func test_missing_from_save_keeps_default_unless_destroyed() -> void:
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	var d: Dictionary = SaveManager.read_slot(SLOT).data
	# An object the save does not know (e.g. added to the map later) keeps
	# its default state — it is NOT treated as destroyed.
	d.statics.erase("HouseA/wardrobe")
	d.statics.erase("HouseA/bedroom/1")
	d.statics.erase("HouseA/bedroom/1/furniture")
	SaveFile.write_atomic(SaveFile.world_path(SLOT), SaveFile.to_json(d))
	check(await _reload(SLOT), "loaded")
	check(_furniture(&"wardrobe", "Bedroom") != null, "wardrobe kept (not in the destroyed list)")


# --- Hotbar ghosts, infection, autosave ---------------------------------------------------

func test_hotbar_slot_pointing_at_an_uncarried_item_survives() -> void:
	player.inventory.add_id(&"kitchen_knife", 1)
	var knife := player.inventory.find(&"kitchen_knife")
	check(player.equipment.assign_hotbar(1, knife).ok, "knife on hotbar 2")
	var cab := _container("HouseA/kitchen/0")
	cab.ensure_loot()
	check(player.inventory.transfer_to(cab.inventory, knife).ok, "knife put in the cabinet")
	check(player.equipment.hotbar_item(1) == null and player.equipment.hotbar.item_at(1) == knife, "ghost slot (not carried)")
	var uid := knife.uid
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	check(await _reload(SLOT), "loaded")
	var ghost := player.equipment.hotbar.item_at(1)
	check(ghost != null and ghost.uid == uid and ghost.id() == &"kitchen_knife", "the slot still points at that knife")
	var cab2 := _container("HouseA/kitchen/0")
	check(cab2.inventory.has(ghost), "the very instance lying in the cabinet")
	check(cab2.inventory.transfer_to(player.inventory, ghost).ok, "picked back up")
	check(player.equipment.hotbar_item(1) == ghost, "hotbar 2 works again")


func test_no_infection_notice_on_load() -> void:
	player.stats.set_value(&"infection", 40.0)
	await physics_frames(2)
	check(player.injuries.infection_stage != &"none", "feverish before saving (%s)" % player.injuries.infection_stage)
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	var events := []
	var cb := func(_c, stage): events.append(stage)
	EventBus.infection_stage_changed.connect(cb)
	var ok := await _reload(SLOT)
	EventBus.infection_stage_changed.disconnect(cb)
	check(ok, "loaded")
	check(events.is_empty(), "no infection_stage_changed while loading (%s)" % str(events))
	check(player.injuries.infection_stage != &"none", "stage restored silently")
	await frames(2)
	var hud: Node = scene.get_node("HUD")
	check(hud.infected_label.visible, "HUD shows the stage")


func test_autosave_only_after_a_rested_wake_and_never_in_danger() -> void:
	var p3 := player as Node3D
	check_eq(SaveManager.autosave_block_reason(scene), "", "calm: autosave allowed")
	var z := spawner.spawn_at(p3.global_position + Vector3(6, 0, 0))
	z.senses.enabled = false
	await physics_frames(3)
	check(SaveManager.autosave_block_reason(scene).begins_with("Autosave skipped"), "zombie within 15 m blocks it (%s)" % SaveManager.autosave_block_reason(scene))
	z.die()
	await physics_frames(2)
	# The wake hook needs the running game (current scene): make this map it.
	var old_current := tree.current_scene
	tree.current_scene = scene
	var saved := []
	var cb := func(slot): saved.append(slot)
	EventBus.game_saved.connect(cb)
	SaveFile.delete_slot(SaveManager.AUTO_SLOT)
	EventBus.sleep_ended.emit(player, "Woken by noise!")
	await physics_frames(5)
	check(saved.is_empty(), "woken by something: no autosave")
	EventBus.sleep_ended.emit(player, "")
	await physics_frames(5)
	check(saved.has(SaveManager.AUTO_SLOT), "rested wake: autosave (%s)" % str(saved))
	EventBus.game_saved.disconnect(cb)
	tree.current_scene = old_current
	SaveFile.delete_slot(SaveManager.AUTO_SLOT)


# --- Menus -----------------------------------------------------------------------------

func test_pause_menu_named_slots_overwrite_and_delete_confirmations() -> void:
	var menu: PauseMenu = scene.get_node("PauseMenu")
	menu.open()
	check(tree.paused and menu.is_open(), "paused")
	menu.show_save()
	check(menu.browser.visible and menu.browser.mode == &"save", "save browser")
	menu.browser.name_edit.text = SLOT
	menu.browser.save_new()
	check(SaveManager.has_slot(SLOT), "saved under the typed name")
	check(menu.browser.list_box.get_node_or_null("Slot_" + SaveFile.encode_slot(SLOT)) != null, "row for the new slot")
	# Overwrite asks first.
	menu.browser.name_edit.text = SLOT
	menu.browser.save_new()
	check(SaveManager.is_confirming() and SaveManager.confirm_text().contains("Overwrite"), "overwrite confirmation (%s)" % SaveManager.confirm_text())
	var t0 := FileAccess.get_modified_time(SaveFile.meta_path(SLOT))
	SaveManager.answer(false)
	check(not SaveManager.is_confirming(), "dialog closed")
	check(tree.paused, "still paused (the menu is open)")
	check_eq(FileAccess.get_modified_time(SaveFile.meta_path(SLOT)), t0, "No: nothing written")
	menu.browser.ask_overwrite(SLOT)
	SaveManager.answer(true)
	check(SaveManager.has_slot(SLOT), "Yes: overwritten")
	# Delete asks first.
	menu.browser.ask_delete(SLOT)
	check(SaveManager.confirm_text().contains("Delete"), "delete confirmation")
	SaveManager.answer(false)
	check(SaveManager.has_slot(SLOT), "No: kept")
	menu.browser.ask_delete(SLOT)
	SaveManager.answer(true)
	check(not SaveManager.has_slot(SLOT), "Yes: deleted")
	menu.close()
	check(not tree.paused, "resumed")


func test_quit_and_quick_load_ask_about_unsaved_progress_and_loading_overlay() -> void:
	check(SaveManager.save_game(SLOT_2, scene).ok, "saved")
	check_lt(SaveManager.unsaved_minutes(scene), 0.01, "nothing unsaved right after saving")
	TimeManager.advance(5.0)
	check_gt(SaveManager.unsaved_minutes(scene), 2.0, "5 game minutes unsaved")
	SaveManager.request_load(SLOT_2)
	check(SaveManager.is_confirming() and SaveManager.confirm_text().begins_with("Unsaved progress will be lost"), "quick-load asks (%s)" % SaveManager.confirm_text())
	SaveManager.answer(false)
	check(scene.is_inside_tree() and not SaveManager.loading, "No: nothing loaded")
	SaveManager.request_quit_to_menu()
	check(SaveManager.confirm_text().begins_with("Unsaved progress will be lost"), "quit asks too")
	SaveManager.answer(false)
	check(scene.is_inside_tree(), "No: still playing")
	# Yes → the load runs with the "Loading…" curtain up.
	var shown := [false]
	var watch := func(): shown[0] = shown[0] or SaveManager.is_loading_shown()
	SaveManager.request_load(SLOT_2)
	SaveManager.answer(true)
	check(SaveManager.loading, "loading")
	for i in 600:
		watch.call()
		if not SaveManager.loading:
			break
		await tree.process_frame
	check(shown[0], "loading overlay shown during the load")
	check(not SaveManager.is_loading_shown(), "overlay gone after")
	var map := SaveManager.current_map()
	check(map != null and map != scene, "loaded into a fresh map")
	if map != null:
		_bind(map)
	check_lt(SaveManager.unsaved_minutes(scene), 0.1, "fresh after the load")


func test_new_game_starts_inside_house_a_with_a_shirt_to_tear() -> void:
	var map := SaveManager.instantiate_new_game(SaveManager.NEW_GAME_MAP, 7)
	check(map != null, "new game map")
	map.get_node("Zombies").auto_spawn = false
	await despawn(scene)
	tree.root.add_child(map)
	await tree.process_frame
	_bind(map)
	check(house.contains_point(player.global_position), "the player starts inside House A (%s)" % player.global_position)
	check_eq(WorldConfig.find(tree).world_seed, 7, "world seed")
	var shirt := player.inventory.find(&"tshirt")
	check(shirt != null, "a spare t-shirt")
	var acts := ItemActions.for_item(player, shirt)
	check(acts.any(func(a): return a.id == ItemActions.TEAR), "Tear into rags offered")
	check(ItemActions.perform(player, shirt, ItemActions.TEAR).ok, "torn")
	check_eq(player.inventory.count_of(&"rag"), 3, "3 rags")
	check_eq(player.inventory.count_of(&"tshirt"), 0, "shirt used up")
	check(SaveManager.instantiate_new_game("res://ui/menus/main_menu.tscn") == null, "only res://maps scenes can be started")
