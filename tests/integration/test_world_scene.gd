extends "res://tests/test_case.gd"
## Round 11 in the real maps/world.tscn (a new game on world seed 1337):
## the generated county loads within budget, the player starts inside a
## house, 30+ zombies are around the start, a generated store's containers
## can be searched, a generated house door opens, the chunk navmesh joins
## across chunk borders, the M map opens, and a save / load in the
## generated world regenerates the same buildings (same ids) and restores
## the container / door state. Round 11 critic fixes: every door in the
## baked chunks is reachable from the start (2 seeds), the night light
## budget, navigation verified under artificial load, regions freed /
## baked ahead while walking + rural groups spawning, saves refused when
## the regenerated world differs.

const SLOT := "world scene test"
const SEED := 1337

var scene: Node
var player: Player
var builder: WorldBuilder
var nav: WorldNav
var load_ms: float = 0.0


func setup() -> void:
	var t0 := Time.get_ticks_msec()
	scene = SaveManager.instantiate_new_game("res://maps/world.tscn", SEED)
	tree.root.add_child(scene)
	load_ms = Time.get_ticks_msec() - t0
	_bind(scene)
	await wait_physics_until(func(): return nav.baked, 1800)
	await physics_frames(5)


func teardown() -> void:
	await despawn(scene)
	SaveFile.delete_slot(SLOT)
	tree.paused = false


func _bind(map: Node) -> void:
	scene = map
	player = map.get_node("Player")
	builder = map.get_node("Generated")
	nav = map.get_node("NavRegion")
	player.get_node("Controller").scripted = true
	player.get_node("Interaction").scripted = true


func _building_of_kind(kind: StringName, settlement: String = "") -> HouseBlockout:
	for id in builder.buildings:
		var hb: HouseBlockout = builder.buildings[id]
		if hb.get_meta(&"kind", &"") == kind and (settlement == "" or String(id).begins_with(settlement)):
			return hb
	return null


func test_world_loads_within_budget_with_chunked_nav() -> void:
	check_lt(load_ms, 20000.0, "generate + build under 20 s (%.0f ms)" % load_ms)
	check_lt(builder.layout_ms, 2000.0, "layout under 2 s")
	check(nav.baked, "chunk navmesh baked")
	check_eq(builder.recipes.size(), 144, "12 x 12 chunk recipes")
	# Round 12: only the chunks around the player are instantiated.
	check(builder.chunks.size() >= 25 and builder.chunks.size() <= 49, "7 x 7 chunks loaded at most (%d)" % builder.chunks.size())
	check_eq(nav.regions.size(), 25, "5 x 5 chunk nav regions around the start")
	check_gt(builder.buildings.size(), 40.0, "buildings instantiated")
	# A path that crosses chunk borders (tiles are joined).
	var map := nav.get_world_3d().navigation_map
	var a := NavigationServer3D.map_get_closest_point(map, player.global_position)
	var road: Dictionary = builder.layout.road("town_main")
	var pts: PackedVector2Array = road.points
	var far := Vector3(pts[0].x, 0, pts[0].y)
	var b := NavigationServer3D.map_get_closest_point(map, far)
	check_lt(b.distance_to(far), 1.5, "main street end on the navmesh")
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	check(path.size() >= 2 and path[path.size() - 1].distance_to(b) < 1.0, "path from the start house to the main street end")
	var ca := builder.layout.chunk_of(Vector2(a.x, a.z))
	var cb := builder.layout.chunk_of(Vector2(b.x, b.z))
	check(ca != cb, "the path crosses chunks (%s → %s)" % [ca, cb])


func test_player_spawns_inside_a_house() -> void:
	var loc := Building.locate(tree, player.global_position)
	check(loc.building != null, "inside a building")
	if loc.building != null:
		check_eq(String(loc.building.name), builder.layout.spawn_building, "the layout's start house")
		check(loc.building.get_meta(&"kind", &"") in [&"house", &"farmhouse"], "a house")
	check(loc.room != null, "inside a room")


func test_zombies_populate_the_start_area() -> void:
	var sp: ZombieSpawner = scene.get_node("Zombies")
	await wait_physics_until(func(): return sp.zombies.size() >= 30, 300)
	var near := 0
	for z in sp.zombies:
		if is_instance_valid(z) and z.global_position.distance_to(player.global_position) < 160.0:
			near += 1
			check(not WorldQuery.is_inside_building(tree, z.global_position), "zombie spawned outdoors")
	check(near >= 30, "30+ zombies near the start (%d)" % near)


func test_containers_searchable_in_a_generated_store() -> void:
	scene.get_node("Zombies").auto_spawn = false
	var store := _building_of_kind(&"convenience_store", "town")
	check(store != null, "a town convenience store")
	if store == null:
		return
	check_gt(store.containers.size(), 3.0, "store containers")
	var c: LootContainer = null
	for cc in store.containers:
		if cc.container_type == &"store_shelf" or cc.container_type == &"counter":
			c = cc
			break
	check(c != null, "a shelf / counter")
	if c == null:
		return
	check(c.persist_id.begins_with(String(store.building_id) + "/"), "stable id from the layout building id")
	player.global_position = c.global_position + c.global_transform.basis.z * 1.0 + Vector3.UP * 0.1
	await physics_frames(3)
	var r := Interactable.of(c).perform(&"search", player)
	check(r.get("ok", false), "search accepted: %s" % str(r))
	await wait_physics_until(func(): return c.is_open_for(player), 200)
	check(c.is_open_for(player), "container open after searching")
	check(c.searched, "loot rolled")
	check_eq(c.building_type, &"convenience_store", "loot context building type")


func test_door_in_a_generated_house_opens() -> void:
	scene.get_node("Zombies").auto_spawn = false
	var house: HouseBlockout = builder.buildings[builder.layout.spawn_building]
	var door: Door = null
	for d in house.doors:
		if d.persist_id.ends_with("/front_door"):
			door = d
	check(door != null, "the start house has its front door")
	if door == null:
		return
	player.global_position = door.global_position + door.outward * 2.5 + Vector3.UP * 0.1
	await physics_frames(3)
	var r := Interactable.of(door).perform(Door.ACTION_OPEN, player)
	check(r.get("ok", false), "open accepted: %s" % str(r))
	await wait_physics_until(func(): return door.is_open(), 120)
	check(door.is_open(), "door open")


func test_map_overlay_opens_with_the_layout() -> void:
	var overlay: WorldMapOverlay = scene.get_node("MapOverlay")
	overlay.set_open(true)
	await frames(2)
	check(overlay.is_open, "open")
	check(overlay.map_rect.texture != null, "map rendered")
	var uv := overlay.player_uv()
	check(uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0, "player marker inside the map")
	overlay.set_open(false)
	check(not overlay.is_open, "closed")


func test_save_and_load_regenerate_the_same_world() -> void:
	var sp: ZombieSpawner = scene.get_node("Zombies")
	await wait_physics_until(func(): return sp.zombies.size() >= 30, 300)
	for z in sp.zombies:
		if is_instance_valid(z):
			z.set_physics_process(false)
	var store := _building_of_kind(&"convenience_store", "town")
	var c: LootContainer = store.containers[0]
	c.open(player)
	c.close()
	c.inventory.add_id(&"hammer", 1)
	var house: HouseBlockout = builder.buildings[builder.layout.spawn_building]
	var door: Door = house.doors[0]
	player.global_position = door.global_position + door.outward * 2.5 + Vector3.UP * 0.1
	await physics_frames(3)
	Interactable.of(door).perform(Door.ACTION_OPEN, player)
	await wait_physics_until(func(): return door.is_open(), 120)
	var ids_before: Array = builder.buildings.keys()
	var hash_before := builder.layout.layout_hash()
	var pos_before := player.global_position
	var zombies_before := sp.alive_count()
	var cid := c.persist_id
	var did := door.persist_id
	var saved := SaveManager.save_game(SLOT, scene)
	check(saved.ok, "saved: %s" % str(saved))
	var data := SaveManager.read_slot(SLOT)
	check_eq(int(data.data.world.seed), SEED, "seed in the save")
	check_eq(String(data.data.world.get("worldgen_params", "")), "res://data/worldgen/default_world.tres", "params in the save")
	var r: Dictionary = await SaveManager.load_game(SLOT, scene)
	check(r.ok, "loaded: %s" % str(r))
	if not r.ok:
		return
	_bind(r.map)
	check_eq(builder.world_seed, SEED, "same seed regenerated")
	check_eq(builder.layout.layout_hash(), hash_before, "identical layout")
	check_eq(builder.buildings.keys(), ids_before, "same building ids")
	var c2 := SaveManager.find_saveable(cid) as LootContainer
	check(c2 != null and c2 != c, "the container again (fresh node)")
	if c2 != null:
		check(c2.searched, "still searched")
		check_gt(c2.inventory.count_of(&"hammer"), 0.0, "the hammer put in is still there")
	var d2 := SaveManager.find_saveable(did) as Door
	check(d2 != null and d2.is_open(), "the door is still open")
	check_lt(player.global_position.distance_to(pos_before), 0.3, "player where saved")
	var sp2: ZombieSpawner = scene.get_node("Zombies")
	check_eq(sp2.alive_count(), zombies_before, "same living zombies")
	check(nav.baked, "nav baked around the saved position")


func test_main_menu_new_game_uses_the_generated_world_and_seed_field() -> void:
	var menu: MainMenu = load("res://ui/menus/main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await frames(2)
	check_eq(MainMenu.NEW_GAME_SCENE, "res://maps/world.tscn", "New game → generated world")
	check(SaveFile.allowed_map(MainMenu.NEW_GAME_SCENE), "world.tscn is an allowed save map")
	menu.seed_edit.text = "4242"
	check_eq(menu.chosen_seed(), 4242, "typed seed used")
	menu.seed_edit.text = ""
	var s1 := menu.chosen_seed()
	check(s1 >= 0 and s1 < 1000000, "random seed when empty")
	menu.queue_free()
	await frames(1)


## Every exterior door of a building lying in the baked chunks can be
## reached (inside and outside) from the start point — seeds 1337 and 7.
func test_doors_in_baked_chunks_reachable_from_spawn() -> void:
	for s in [SEED, 7]:
		if s != SEED:
			await despawn(scene)
			scene = SaveManager.instantiate_new_game("res://maps/world.tscn", s)
			tree.root.add_child(scene)
			_bind(scene)
			await wait_physics_until(func(): return nav.baked, 1800)
			await physics_frames(5)
		scene.get_node("Zombies").set_physics_process(false)
		var map := nav.get_world_3d().navigation_map
		var start := NavigationServer3D.map_get_closest_point(map, builder.start_position())
		var baked := {}
		for c in nav.baked_chunks():
			baked[c] = true
		var doors := 0
		for id in builder.buildings:
			var b: Dictionary = builder.layout.building(String(id))
			var r: Rect2 = (b.rect as Rect2).grow(2.0)
			var inside := true
			for q in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
				if not baked.has(builder.layout.chunk_of(q)):
					inside = false
			if not inside:
				continue
			var hb: HouseBlockout = builder.buildings[id]
			for d in hb.doors:
				if d.outward == Vector3.ZERO or String(d.persist_id).contains("garage"):
					continue
				doors += 1
				for sgn in [1.0, -1.0]:
					var target: Vector3 = d.global_position + d.outward * 1.2 * sgn
					target.y = 0.0
					var t := NavigationServer3D.map_get_closest_point(map, target)
					var path := NavigationServer3D.map_get_path(map, start, t, true)
					var ok := t.distance_to(target) < 1.0 and path.size() >= 2 and path[path.size() - 1].distance_to(t) < 1.0
					if not ok:
						fail("seed %d: %s %s side not reachable from the start" % [s, d.persist_id, "outer" if sgn > 0.0 else "inner"])
		check_gt(doors, 8.0, "seed %d: doors checked (%d)" % [s, doors])


## At night only lights near the player are on and at most the nearest
## [shadowed_lights] room lights cast shadows; lamps never do.
func test_night_light_budget() -> void:
	scene.get_node("Zombies").auto_spawn = false
	TimeManager.set_time_of_day(23, 0)
	await physics_frames(3)
	builder.update_lights()
	var st: Dictionary = builder.light_stats
	check(bool(st.on), "lights on at night")
	check_gt(float(st.visible), 5.0, "lights near the player on (%d of %d)" % [st.visible, st.total])
	check_lt(float(st.visible), float(st.total) * 0.7, "far lights off")
	check(int(st.shadowed) <= builder.shadowed_lights, "≤ %d shadowed (%d)" % [builder.shadowed_lights, st.shadowed])
	var pp := player.global_position
	for n in tree.get_nodes_in_group(&"interior_light"):
		if not scene.is_ancestor_of(n):
			continue
		var l := n as Light3D
		if l.visible:
			check_lt(Vector2(l.global_position.x - pp.x, l.global_position.z - pp.z).length(), builder.light_far + 0.1, "visible light within range")
		if l.is_in_group(&"street_lamp"):
			check(not l.shadow_enabled, "street lamps unshadowed")
	TimeManager.set_time_of_day(12, 0)
	await physics_frames(3)
	builder.update_lights()
	check_eq(int(builder.light_stats.visible), 0, "all off by day")


## Under artificial load (a busy worker thread + slow frames) the map
## still only reports ready once every region answers queries, and the
## start population spawns completely (no unusable points left).
func test_navigation_ready_only_when_regions_answer_under_load() -> void:
	await despawn(scene)
	var stop := [false]
	var busy := Thread.new()
	busy.start(func():
		var x := 0.0
		while not stop[0]:
			for i in 20000:
				x += sin(float(i)))
	var slow := Node.new()
	slow.set_script(_SlowFrames)
	tree.root.add_child(slow)
	scene = SaveManager.instantiate_new_game("res://maps/world.tscn", SEED)
	tree.root.add_child(scene)
	_bind(scene)
	var ready_ok := [false]
	nav.navigation_ready.connect(func(): ready_ok[0] = nav.regions_verified(nav.baked_chunks()))
	await wait_physics_until(func(): return nav.baked, 3000)
	check(nav.baked, "baked under load")
	check(ready_ok[0], "every region queryable when navigation_ready fired")
	var sp: ZombieSpawner = scene.get_node("Zombies")
	var want := builder.layout.zombies.size()
	await wait_physics_until(func(): return sp.zombies.size() >= want - 2, 600)
	check_gt(float(sp.zombies.size()), float(want - 3), "start population spawned (%d / %d)" % [sp.zombies.size(), want])
	stop[0] = true
	busy.wait_to_finish()
	slow.queue_free()


const _SlowFrames := preload("res://tests/integration/slow_frames.gd")


## Walking far: regions beyond keep_radius are freed, chunks ahead are
## baked, and a rural group (now population data, Round 12) turns into
## real zombies once its chunk is loaded and its navmesh is live.
func test_walking_frees_regions_bakes_ahead_and_spawns_rural_groups() -> void:
	var pd: PopulationDirector = scene.get_node("Population")
	var sp: ZombieSpawner = scene.get_node("Zombies")
	await wait_physics_until(func(): return sp.zombies.size() >= 30, 300)
	for z in sp.zombies:
		if is_instance_valid(z):
			z.set_physics_process(false)
	check_gt(float(builder.layout.zombie_groups.size()), 0.0, "rural groups in the layout")
	var g: Dictionary = builder.layout.zombie_groups[0]
	var best := INF
	for gg in builder.layout.zombie_groups:
		var d := (gg.points[0] as Vector2).distance_to(builder.layout.spawn_point)
		if d < best:
			best = d
			g = gg
	var goal: Vector2 = g.points[0]
	var tagged := -1
	for id in pd.population.groups:
		if String(pd.population.groups[id].get("tag", "")) == String(g.id):
			tagged = id
	check(tagged >= 0, "the rural group is a population group")
	# A private copy: the params .tres is a shared, cached resource.
	pd.population.params = pd.population.params.duplicate()
	pd.population.params.wander_speed = 0.0
	var from := Vector2(player.global_position.x, player.global_position.z)
	var dir := (goal - from).normalized()
	var steps := int(from.distance_to(goal) / 6.0)
	player.get_node("Health").invulnerable = true
	for i in steps:
		var q := from + dir * 6.0 * (i + 1)
		player.global_position = Vector3(q.x, 0.1, q.y)
		player.velocity = Vector3(dir.x, 0.0, dir.y) * 6.0
		await physics_frames(6)
	player.velocity = Vector3.ZERO
	await wait_physics_until(func(): return not pd.population.groups.has(tagged), 900)
	check(not pd.population.groups.has(tagged), "group %s instantiated near its hamlet / farm" % g.id)
	var near := 0
	for z in pd.real_zombies():
		if Vector2(z.global_position.x, z.global_position.z).distance_to(goal) < 40.0:
			near += 1
	check_gt(float(near), 0.0, "its zombies stand there (%d)" % near)
	if best > 64.0 * (nav.keep_radius + 1):
		check_gt(float(nav.freed_count), 0.0, "far regions freed (%d)" % nav.freed_count)
	check(nav.regions.size() <= (2 * nav.keep_radius + 1) * (2 * nav.keep_radius + 1), "regions bounded (%d)" % nav.regions.size())
	var gc := builder.layout.chunk_of(goal)
	check(nav.chunk_ready(gc), "the goal chunk is baked and queryable")


## A save whose generator version / layout hash doesn't match what this
## build generates for its seed is refused with a clear message; the
## running game stays.
func test_load_refuses_a_different_world() -> void:
	scene.get_node("Zombies").auto_spawn = false
	var saved := SaveManager.save_game(SLOT, scene)
	check(saved.ok, "saved")
	var data: Dictionary = SaveManager.read_slot(SLOT).data
	check_eq(int(data.world.worldgen.version), WorldGenerator.VERSION, "generator version saved")
	check_eq(String(data.world.worldgen.layout_hash), builder.layout.layout_hash(), "layout hash saved")
	data.world.worldgen.layout_hash = "f".repeat(64)
	data.world.worldgen.version = WorldGenerator.VERSION + 1
	var r: Dictionary = await SaveManager.load_data(data, scene)
	check(not r.ok, "refused")
	check(String(r.get("error", "")).contains("world generator v%d" % (WorldGenerator.VERSION + 1)), "clear message: %s" % r.get("error", ""))
	check(is_instance_valid(scene) and scene.is_inside_tree(), "the running game is untouched")
