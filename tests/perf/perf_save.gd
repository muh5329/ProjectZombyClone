extends SceneTree
## Save / load timing (Round 10, headless):
##
##   godot --headless --path . -s tests/perf/perf_save.gd
##
## test_ground with ZOMBIES living zombies (+ CORPSES killed ones, every
## House A container searched, a few dropped items), then
## SaveManager.save_game (capture + JSON + atomic write) and
## SaveManager.load_game (fresh map, static state, navmesh bake, 200
## zombies re-created, player). Budgets: save < SAVE_BUDGET_MS, load <
## LOAD_BUDGET_MS. Exit 1 when over budget or when the reload lost data.
## No static typing against gameplay classes (-s scripts compile first).

const ZOMBIES := 200
const CORPSES := 20
const SAVE_BUDGET_MS := 200.0
const LOAD_BUDGET_MS := 3000.0
const SLOT := "perf_save"
const ITEMS := 3000
const ITEMS_SAVE_BUDGET_MS := 200.0
const ITEMS_LOAD_BUDGET_MS := 2000.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var sm: Node = root.get_node("SaveManager")
	var scene: PackedScene = load("res://maps/test_ground.tscn")
	var inst := scene.instantiate()
	inst.get_node("Zombies").auto_spawn = false
	root.add_child(inst)
	var nav = inst.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	var spawner = inst.get_node("Zombies")
	spawner.min_player_distance = 4.0
	spawner.spawn_radius = 30.0
	spawner.rng.seed = 42
	var made := 0
	while made < ZOMBIES + CORPSES:
		var p: Vector3 = spawner.pick_spawn_point()
		if p == Vector3.INF:
			continue
		spawner.spawn_at(p)
		made += 1
	for i in 30:
		await physics_frame
	var player: Node3D = inst.get_node("Player")
	for i in CORPSES:
		spawner.zombies[i].die(player)
	for c in get_nodes_in_group(&"container"):
		if String(c.persist_id).begins_with("HouseA/"):
			c.ensure_loot()
	player.inventory.add_id(&"apple", 3)
	for i in 3:
		player.drop_item(player.inventory.find(&"apple"), 1)
	for i in 5:
		await physics_frame
	var alive_before := _alive(inst)
	# Warm-up save (first-call costs), then the measured one.
	sm.save_game(SLOT, inst)
	var times: Array[float] = []
	for i in 3:
		var r: Dictionary = sm.save_game(SLOT, inst)
		if not r.ok:
			printerr("PERF_SAVE: save failed: %s" % r.get("error", "?"))
			quit(1)
			return
		times.append(float(r.ms))
	times.sort()
	var save_ms: float = times[1]
	var bytes := FileAccess.get_file_as_string(load("res://core/save_file.gd").world_path(SLOT)).length()
	var lr: Dictionary = await sm.load_game(SLOT, inst)
	if not lr.ok:
		printerr("PERF_SAVE: load failed: %s" % lr.get("error", "?"))
		quit(1)
		return
	var load_ms: float = lr.ms
	var map: Node = lr.map
	var alive_after := _alive(map)
	var corpses := 0
	for c in get_nodes_in_group(&"corpse"):
		if map.is_ancestor_of(c):
			corpses += 1
	print("PERF_SAVE: %d living zombies, %d corpses, %d bytes" % [alive_after, corpses, bytes])
	print("PERF_SAVE: save %.1f ms (median of 3; budget %.0f ms)" % [save_ms, SAVE_BUDGET_MS])
	print("PERF_SAVE: load %.1f ms (incl. navmesh bake %.0f ms; budget %.0f ms)" % [load_ms, float(map.get_node("NavRegion").bake_ms), LOAD_BUDGET_MS])
	sm.delete_slot(SLOT)
	var ok := save_ms < SAVE_BUDGET_MS and load_ms < LOAD_BUDGET_MS
	if alive_after != alive_before or corpses != CORPSES:
		printerr("PERF_SAVE: reload lost data (alive %d → %d, corpses %d)" % [alive_before, alive_after, corpses])
		ok = false
	# --- 3000 dropped items (spread over the lot, a few kinds) -------------------
	var wi_script: Script = load("res://items/world_item.gd")
	var inst_script: Script = load("res://items/item_instance.gd")
	var idb: Node = root.get_node("ItemDB")
	var kinds := [&"apple", &"nails", &"plank", &"bandage", &"baseball_bat", &"backpack", &"soda", &"rag"]
	for i in ITEMS:
		var it_inst = inst_script.new(idb.get_item(kinds[i % kinds.size()]), -1, 1)
		var w = wi_script.for_instance(it_inst)
		map.add_child(w)
		w.global_position = Vector3(-30.0 + float(i % 60), 0.0, -30.0 + float(i / 60))
	for i in 5:
		await physics_frame
	var t2: Array[float] = []
	for i in 3:
		var r2: Dictionary = sm.save_game(SLOT, map)
		t2.append(float(r2.get("ms", 1e9)))
	t2.sort()
	var lr2: Dictionary = await sm.load_game(SLOT, map)
	var items_after := 0
	if lr2.ok:
		for w in get_nodes_in_group(&"world_item"):
			if lr2.map.is_ancestor_of(w):
				items_after += 1
	print("PERF_SAVE: %d dropped items: save %.1f ms (budget %.0f), load %.1f ms (budget %.0f), %d back" % [ITEMS, t2[1],
		ITEMS_SAVE_BUDGET_MS, float(lr2.get("ms", 1e9)), ITEMS_LOAD_BUDGET_MS, items_after])
	if t2[1] >= ITEMS_SAVE_BUDGET_MS or float(lr2.get("ms", 1e9)) >= ITEMS_LOAD_BUDGET_MS or items_after < ITEMS:
		ok = false
	sm.delete_slot(SLOT)
	if lr2.ok:
		lr2.map.queue_free()
	else:
		map.queue_free()
	await process_frame
	print("PERF_SAVE: %s" % ("OK" if ok else "OVER BUDGET"))
	quit(0 if ok else 1)


func _alive(map: Node) -> int:
	var n := 0
	for z in get_nodes_in_group(&"zombie"):
		if map.is_ancestor_of(z) and not z.dead:
			n += 1
	return n
