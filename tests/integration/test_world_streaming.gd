extends "res://tests/test_case.gd"
## Round 12 in the real maps/world.tscn (new game, seed 1337): chunk
## streaming (content freed 400 m away and rebuilt on return with every
## change — searched container, opened door, window planks, dropped item,
## corpse, blood), killed zombies stay dead, a loud sound far away pulls a
## simulated group that later walks in as real zombies, the population is
## conserved over a game day and moves under fast-forward, an untouched
## world saves under 50 KB, save / load after exploring restores the
## deltas of unloaded chunks, the active-zombie cap, and frame times while
## sprinting across chunk borders.

const SLOT := "world streaming test"
const SEED := 1337

var scene: Node
var player: Player
var builder: WorldBuilder
var nav: WorldNav
var streamer: ChunkStreamer
var pd: PopulationDirector


func setup() -> void:
	scene = SaveManager.instantiate_new_game("res://maps/world.tscn", SEED)
	tree.root.add_child(scene)
	_bind(scene)
	await wait_physics_until(func(): return nav.baked, 1800)
	await physics_frames(5)


func teardown() -> void:
	TimeManager.set_speed(TimeManager.STEP_NORMAL)
	await despawn(scene)
	SaveFile.delete_slot(SLOT)
	tree.paused = false


func _bind(map: Node) -> void:
	scene = map
	player = map.get_node("Player")
	builder = map.get_node("Generated")
	nav = map.get_node("NavRegion")
	streamer = map.get_node("Streamer")
	pd = map.get_node("Population")
	player.get_node("Controller").scripted = true
	player.get_node("Interaction").scripted = true
	player.get_node("Health").invulnerable = true


## Teleport to [p] and let the streamer / navmesh settle.
func _go(p: Vector3, settle: int = 30) -> void:
	player.global_position = Vector3(p.x, 0.1, p.z)
	player.velocity = Vector3.ZERO
	await physics_frames(3)
	streamer.flush()
	await wait_physics_until(func(): return nav.chunk_ready(streamer.chunk_at(player.global_position)), 900)
	await physics_frames(settle)


## A point [dist] m from [from] toward the middle of the world.
func _far_from(from: Vector3, dist: float) -> Vector3:
	var mid := Vector3(builder.layout.size.x * 0.5, 0.0, builder.layout.size.y * 0.5)
	var dir := (mid - from)
	dir.y = 0.0
	if dir.length() < 1.0:
		dir = Vector3.RIGHT
	var p := from + dir.normalized() * dist
	if p.x < 10.0 or p.z < 10.0 or p.x > builder.layout.size.x - 10.0 or p.z > builder.layout.size.y - 10.0:
		p = from - dir.normalized() * dist
	return Vector3(clampf(p.x, 20.0, builder.layout.size.x - 20.0), 0.0, clampf(p.z, 20.0, builder.layout.size.y - 20.0))


func _nearest_zombies(n: int) -> Array:
	var list: Array = []
	for z in pd.real_zombies():
		list.append([z.global_position.distance_to(player.global_position), z])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var out: Array = []
	for i in mini(n, list.size()):
		out.append(list[i][1])
	return out


func test_walking_away_unloads_and_returning_restores_the_chunk() -> void:
	pd.enabled = false
	var house: HouseBlockout = builder.buildings[builder.layout.spawn_building]
	var origin := player.global_position
	var oc := streamer.chunk_at(origin)
	var hc := streamer.chunk_at(house.global_position)
	# Searched container with a hammer put in.
	var box: LootContainer = house.containers[0]
	box.open(player)
	box.close()
	box.inventory.add_id(&"hammer", 1)
	var box_items := box.inventory.to_dict()
	# An opened door, a barricaded window.
	var door: Door = house.doors[0]
	door.open_door(player)
	await wait_physics_until(func(): return door.is_open(), 120)
	var win: HouseWindow = house.windows[0]
	BarricadeComponent.ensure(win).add_plank(-1.0, 1.0)
	BarricadeComponent.ensure(win).add_plank(-1.0, 1.0)
	# A dropped item, a killed zombie's corpse, blood.
	var wi := WorldItem.drop(ItemInstance.new(ItemDB.get_item(&"crowbar")), player)
	var item_pos := wi.global_position
	var item_uid := wi.item.uid
	var sp: ZombieSpawner = scene.get_node("Zombies")
	var z := sp.spawn_at(origin + Vector3(3.0, 0.0, 0.0))
	await physics_frames(2)
	var corpse := z.die(player)
	await physics_frames(2)
	var corpse_pos := corpse.global_position
	var corpse_id := corpse.persist_id
	var blood: BloodDecals = scene.get_node("BloodDecals")
	blood.add_splat(origin + Vector3(1.0, 0.0, 1.0), 1.0)
	var rect := builder.layout.chunk_rect(oc)
	var blood_before := 0
	for t in blood.transforms():
		if rect.has_point(Vector2(t.origin.x, t.origin.z)):
			blood_before += 1
	var ids := {"box": box.persist_id, "door": door.persist_id, "win": win.persist_id}
	var nodes_before := builder.node_count()
	# Walk (teleport) 400 m away.
	await _go(_far_from(origin, 400.0))
	check(not builder.chunks.has(oc), "origin chunk unloaded")
	check(not builder.chunks.has(hc), "the start house's chunk unloaded")
	check(not builder.buildings.has(builder.layout.spawn_building), "the start house is gone")
	check(builder.impostor_visible(hc), "an impostor stands in for it")
	check(not is_instance_valid(box) or box.is_queued_for_deletion(), "its container node freed")
	check(not is_instance_valid(wi) or wi.is_queued_for_deletion(), "the dropped item left the world")
	check(streamer.store.statics.has(ids.box), "container delta stored")
	check(streamer.store.statics.has(ids.door), "door delta stored")
	check(streamer.store.statics.has(ids.win), "window delta stored")
	check(streamer.store.has_dynamic(oc), "item / corpse / blood kept for the origin chunk")
	check_gt(float(streamer.unloads), 10.0, "chunks unloaded (%d)" % streamer.unloads)
	check(builder.chunks.size() <= 81, "only the chunks around the player are loaded (%d ≤ 9 x 9)" % builder.chunks.size())
	print("  nodes near start %d, 400 m away %d" % [nodes_before, builder.node_count()])
	# Untouched objects were not stored (deltas only).
	var untouched := 0
	for id in streamer.store.statics:
		if String(id).begins_with(builder.layout.spawn_building + "/"):
			untouched += 1
	check_eq(untouched, 3, "only the 3 changed objects of the start house are stored")
	# Come back.
	await _go(origin, 10)
	check(builder.chunks.has(oc), "origin chunk loaded again")
	var box2 := SaveManager.find_saveable(ids.box) as LootContainer
	check(box2 != null and box2 != box, "the container again (a fresh node)")
	if box2 != null:
		check(box2.searched, "still searched (not re-rolled)")
		check_eq(box2.inventory.to_dict(), box_items, "same items")
	var door2 := SaveManager.find_saveable(ids.door) as Door
	check(door2 != null and door2.is_open(), "the door is still open")
	var win2 := SaveManager.find_saveable(ids.win) as HouseWindow
	check(win2 != null and BarricadeComponent.planks_on(win2) == 2, "two planks on the window")
	var found: WorldItem = null
	for n in tree.get_nodes_in_group(WorldItem.GROUP):
		if scene.is_ancestor_of(n) and (n as WorldItem).item.uid == item_uid:
			found = n
	check(found != null, "the dropped crowbar is back")
	if found != null:
		check_lt(found.global_position.distance_to(item_pos), 0.01, "where it was left")
	var c2: ZombieCorpse = null
	for n in tree.get_nodes_in_group(&"corpse"):
		if scene.is_ancestor_of(n) and (n as ZombieCorpse).persist_id == corpse_id:
			c2 = n
	check(c2 != null, "the corpse is back")
	if c2 != null:
		check_lt(c2.global_position.distance_to(corpse_pos), 0.01, "where the zombie was killed")
	var blood_after := 0
	for t in blood.transforms():
		if rect.has_point(Vector2(t.origin.x, t.origin.z)):
			blood_after += 1
	check_eq(blood_after, blood_before, "blood splats back")
	check(not builder.impostor_visible(hc), "impostor hidden again")


## Time goes on in unloaded chunks: milk left in a kitchen container is
## five days older (stale: fresh for 4) when the player comes back five
## game days later.
func test_food_in_an_unloaded_chunk_keeps_spoiling() -> void:
	pd.enabled = false
	var house: HouseBlockout = builder.buildings[builder.layout.spawn_building]
	# A container at room temperature (not the fridge).
	var box: LootContainer = house.containers[0]
	for cc in house.containers:
		if cc.spoil_multiplier >= 1.0:
			box = cc
			break
	box.open(player)
	box.close()
	var milk := ItemInstance.new(ItemDB.get_item(&"milk"))
	box.inventory.add(milk)
	var uid := milk.uid
	var age0 := milk.effective_age()
	var rate := box.inventory.spoil_multiplier
	var id := box.persist_id
	var origin := player.global_position
	await _go(_far_from(origin, 400.0))
	check(not builder.chunks.has(streamer.chunk_at(origin)), "the kitchen's chunk is unloaded")
	TimeManager.advance(5.0 * 1440.0)
	await _go(origin, 10)
	var box2 := SaveManager.find_saveable(id) as LootContainer
	check(box2 != null, "the container is back")
	if box2 == null:
		return
	var m2: ItemInstance = null
	for it in box2.inventory.items:
		if it.uid == uid:
			m2 = it
	check(m2 != null, "the same carton of milk")
	if m2 != null:
		check_near(m2.effective_age() - age0, 5.0 * 1440.0 * rate, 30.0, "aged five game days at the container's rate (%.0f min)" % (m2.effective_age() - age0))
		if rate >= 1.0:
			check(m2.spoil_state() != FoodData.SpoilState.FRESH, "no longer fresh after five days out")


## A Round-11 (version 1) save of the generated world loads: its statics,
## dropped items and zombies come back, and the new population leaves out
## the start pack the save already accounts for.
func test_round11_save_migrates_and_loads() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	var saved := SaveManager.save_game(SLOT, scene)
	check(saved.ok, "saved")
	var v2: Dictionary = SaveManager.read_slot(SLOT).data
	var p: Vector3 = Saveable.to_vec3(v2.player.position)
	var house: HouseBlockout = builder.buildings[builder.layout.spawn_building]
	var door_id: String = house.doors[0].persist_id
	var zrec: Dictionary = (v2.zombies as Array)[0].duplicate(true)
	zrec.spawn_id = "Zombies/1"
	var v1 := {"version": 1, "map": v2.map, "world": v2.world, "time": v2.time,
		"statics": {door_id: {"kind": "door", "state": "open", "health": 100.0, "locked": false, "swing": 1.5}},
		"destroyed": [], "spawners": {"Zombies": {"spawn_counter": 40, "rng_state": "7", "groups_spawned": []}},
		"zombies": [zrec], "corpses": [],
		"items": [{"item": {"id": "crowbar", "count": 1, "uid": 900001}, "position": [p.x + 1.0, 0.0, p.z], "yaw": 0.0}],
		"player": v2.player}
	var d := SaveFile.decode(SaveFile.to_json(v1))
	check(d.ok, "v1 save migrates: %s" % d.get("error", ""))
	if not d.ok:
		return
	var r: Dictionary = await SaveManager.load_data(d.data, scene)
	check(r.ok, "loaded: %s" % str(r))
	if not r.ok:
		return
	_bind(r.map)
	await physics_frames(10)
	var door := SaveManager.find_saveable(door_id) as Door
	check(door != null and door.is_open(), "the saved door state applied")
	var item_ok := false
	for n in tree.get_nodes_in_group(WorldItem.GROUP):
		if scene.is_ancestor_of(n) and (n as WorldItem).item.uid == 900001:
			item_ok = true
	check(item_ok, "the dropped crowbar is back")
	var zs: ZombieSpawner = scene.get_node("Zombies")
	var z_ok := false
	for z in zs.zombies:
		if is_instance_valid(z) and z.spawn_id == "Zombies/1":
			z_ok = true
	check(z_ok, "the saved zombie is back")
	var fresh := ZombiePopulation.generate(builder.layout, builder.world_seed, pd.params)
	check_eq(pd.population.total() + pd.active_count() - 1, fresh.total() - builder.layout.zombies.size(),
		"population = generated minus the start pack (+ the save's own zombie)")


func test_killed_zombies_stay_dead_after_unload_and_reload() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	var total0 := pd.total_alive()
	var victims := _nearest_zombies(5)
	var killed := {}
	for z in victims:
		killed[String(z.spawn_id)] = true
		z.die(player)
	await physics_frames(3)
	check_eq(pd.died_count, 5, "5 deaths recorded")
	check_eq(pd.total_alive(), total0 - 5, "5 fewer alive")
	var origin := player.global_position
	await _go(_far_from(origin, 400.0))
	check(pd.folded_count > 0, "start zombies folded back into data (%d)" % pd.folded_count)
	await _go(origin, 60)
	await wait_physics_until(func(): return pd.active_count() >= 20, 600)
	pd.flush_spawns()
	for z in pd.real_zombies():
		check(not killed.has(String(z.spawn_id)), "killed zombie %s not back" % z.spawn_id)
	var corpses := 0
	for n in tree.get_nodes_in_group(&"corpse"):
		if scene.is_ancestor_of(n) and killed.has(String((n as ZombieCorpse).persist_id).trim_prefix("corpse/")):
			corpses += 1
	check_eq(corpses, 5, "their 5 corpses lie where they fell")
	check_eq(pd.total_alive(), total0 - 5, "population conserved (minus the dead)")


func test_loud_noise_far_away_draws_a_simulated_group() -> void:
	# A private copy: the params .tres is a shared, cached resource.
	pd.population.params = pd.population.params.duplicate()
	pd.population.params.wander_speed = 0.0
	pd.population.params.migrate_chance_per_hour = 0.0
	var pc := streamer.chunk_at(player.global_position)
	# A data group well outside the active / loaded area.
	var gid := -1
	for id in pd.population.groups:
		var g: Dictionary = pd.population.groups[id]
		if ChunkStreamer.chebyshev(pd.population.chunk_of(g.pos), pc) >= 5 and (g.members as PackedInt32Array).size() >= 2:
			gid = id
			break
	check(gid >= 0, "a group far away")
	if gid < 0:
		return
	var g0: Dictionary = pd.population.groups[gid]
	var members: PackedInt32Array = (g0.members as PackedInt32Array).duplicate()
	var gpos: Vector2 = g0.pos
	# The smash: 24 m from the group (window_smash radius 20 × hearing 1.5).
	var dir := Vector2(1, 0) if gpos.x < builder.layout.size.x * 0.5 else Vector2(-1, 0)
	var smash := gpos + dir * 24.0
	check(not builder.chunks.has(builder.layout.chunk_of(smash)), "the noise is in an unloaded chunk")
	SoundManager.emit_sound(&"window_smash", Vector3(smash.x, 0.0, smash.y))
	check_eq(int(pd.population.groups[gid].state), ZombiePopulation.State.INVESTIGATE, "the group heard it")
	var d0 := gpos.distance_to(smash)
	TimeManager.advance(12.0)
	pd.tick_now()
	var d1 := (pd.population.groups[gid].pos as Vector2).distance_to(smash)
	check_lt(d1, d0 - 5.0, "12 game minutes later the group is nearer (%.1f → %.1f m)" % [d0, d1])
	TimeManager.advance(30.0)
	pd.tick_now()
	# Go there: the chunk loads and the group walks in as real zombies.
	await _go(Vector3(smash.x + 12.0, 0.0, smash.y + 12.0), 20)
	await wait_physics_until(func(): return not pd.population.groups.has(gid), 600)
	pd.flush_spawns()
	var near := 0
	var mset := {}
	for m in members:
		mset["pop/%d" % m] = true
	for z in pd.real_zombies():
		if mset.has(String(z.spawn_id)):
			var zd := Vector2(z.global_position.x, z.global_position.z).distance_to(smash)
			check_lt(zd, d0 - 5.0, "%s nearer the smash than the group started (%.1f m)" % [z.spawn_id, zd])
			near += 1
	check_eq(near, members.size(), "every member instantiated (%d / %d)" % [near, members.size()])


func test_population_conserved_over_a_game_day_and_moved_by_fast_forward() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	var total0 := pd.total_alive()
	check(total0 >= 600 and total0 <= 1200, "county population in range (%d)" % total0)
	var before := {}
	for id in pd.population.groups:
		before[id] = pd.population.groups[id].pos
	# One game day of simulation, as the director would tick it — with the
	# player walking away and back (zombies fold into data and are
	# instantiated again) and killing some.
	var origin := player.global_position
	var far := _far_from(origin, 400.0)
	var spawned0 := pd.spawned_count
	var folded0 := pd.folded_count
	var kills := 0
	for h in 24:
		TimeManager.advance(60.0)
		pd.tick_now()
		pd.sync_now()
		pd.flush_spawns()
		if h % 6 == 2:
			await _go(far if h % 12 == 2 else origin, 20)
			pd.sync_now()
			pd.flush_spawns()
		if h % 8 == 4:
			var victims := _nearest_zombies(2)
			for z in victims:
				z.die(player)
				kills += 1
			await physics_frames(2)
		check_eq(pd.total_alive() + pd.died_count, total0, "hour %d: data + live + dead constant" % h)
	check_gt(float(pd.spawned_count - spawned0), 10.0, "zombies were instantiated during the day (%d)" % (pd.spawned_count - spawned0))
	check_gt(float(pd.folded_count - folded0), 10.0, "zombies were folded back during the day (%d)" % (pd.folded_count - folded0))
	check_gt(float(kills), 3.0, "zombies were killed during the day (%d)" % kills)
	check_eq(pd.total_alive() + pd.died_count, total0, "no zombie created or lost in a day")
	var moved := 0
	for id in before:
		if pd.population.groups.has(id) and (pd.population.groups[id].pos as Vector2).distance_to(before[id]) > 5.0:
			moved += 1
	check_gt(float(moved), float(before.size()) * 0.3, "groups moved over the day (%d / %d)" % [moved, before.size()])
	# Fast-forward (4×): game time runs 4× faster and the sim follows it.
	var snap := {}
	for id in pd.population.groups:
		snap[id] = pd.population.groups[id].pos
	var m0 := TimeManager.now()
	var r := TimeManager.set_speed(3)
	await physics_frames(240)
	var elapsed := TimeManager.now() - m0
	TimeManager.set_speed(TimeManager.STEP_NORMAL)
	if bool(r.get("ok", true)):
		check_gt(elapsed, 8.0, "fast-forward advanced game time (%.1f min)" % elapsed)
	var dist := 0.0
	var n := 0
	for id in snap:
		if pd.population.groups.has(id):
			dist += (pd.population.groups[id].pos as Vector2).distance_to(snap[id])
			n += 1
	check_gt(dist / maxf(n, 1.0), 0.02 * elapsed, "groups moved with the game time (%.2f m avg over %.1f min)" % [dist / maxf(n, 1.0), elapsed])
	check_eq(pd.total_alive() + pd.died_count, total0, "still conserved")


func test_untouched_world_saves_small() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	var saved := SaveManager.save_game(SLOT, scene)
	check(saved.ok, "saved: %s" % str(saved))
	check_lt(float(saved.get("bytes", 1e9)), 50000.0, "untouched world < 50 KB (%d bytes)" % saved.get("bytes", 0))
	var data: Dictionary = SaveManager.read_slot(SLOT).data
	check((data.statics as Dictionary).is_empty(), "no statics saved for an untouched world (%d)" % (data.statics as Dictionary).size())
	check(data.has("population"), "population saved as data")
	print("  untouched save %d bytes, %.0f ms" % [saved.bytes, saved.ms])


func test_save_and_load_after_exploring_restores_unloaded_chunks() -> void:
	pd.enabled = false
	var house: HouseBlockout = builder.buildings[builder.layout.spawn_building]
	var origin := player.global_position
	var box: LootContainer = house.containers[0]
	box.open(player)
	box.close()
	box.inventory.add_id(&"hammer", 1)
	var door: Door = house.doors[0]
	door.open_door(player)
	await wait_physics_until(func(): return door.is_open(), 120)
	var wi := WorldItem.drop(ItemInstance.new(ItemDB.get_item(&"crowbar")), player)
	var item_pos := wi.global_position
	var ids := {"box": box.persist_id, "door": door.persist_id}
	var far := _far_from(origin, 400.0)
	await _go(far)
	check(not builder.chunks.has(streamer.chunk_at(origin)), "origin unloaded before saving")
	# Change something where we are now too (the nearest building).
	var here: LootContainer = null
	var hd := INF
	for id in builder.buildings:
		var hb: HouseBlockout = builder.buildings[id]
		var d := hb.global_position.distance_to(player.global_position)
		if not hb.containers.is_empty() and d < hd:
			hd = d
			here = hb.containers[0]
	var here_id := ""
	if here != null:
		here.open(player)
		here.close()
		here_id = here.persist_id
	var saved := SaveManager.save_game(SLOT, scene)
	check(saved.ok, "saved: %s" % str(saved))
	var r: Dictionary = await SaveManager.load_game(SLOT, scene)
	check(r.ok, "loaded: %s" % str(r))
	if not r.ok:
		return
	_bind(r.map)
	pd.enabled = false
	check_lt(player.global_position.distance_to(Vector3(far.x, player.global_position.y, far.z)), 1.0, "player where saved")
	check(not builder.chunks.has(streamer.chunk_at(origin)), "the load built only the chunks near the player")
	if here_id != "":
		streamer.flush()
		var h2 := SaveManager.find_saveable(here_id) as LootContainer
		check(h2 != null and h2.searched, "the loaded chunk's change restored")
	await _go(origin, 10)
	var box2 := SaveManager.find_saveable(ids.box) as LootContainer
	check(box2 != null and box2.searched and box2.inventory.count_of(&"hammer") > 0, "far container restored after load")
	var door2 := SaveManager.find_saveable(ids.door) as Door
	check(door2 != null and door2.is_open(), "far door restored after load")
	var found := false
	for n in tree.get_nodes_in_group(WorldItem.GROUP):
		if scene.is_ancestor_of(n) and (n as WorldItem).global_position.distance_to(item_pos) < 0.01:
			found = true
	check(found, "the crowbar dropped in an unloaded chunk is back")


func test_active_zombie_cap_is_honoured() -> void:
	pd.max_active = 25
	# The busiest chunk of the county (town).
	var best := Vector2i.ZERO
	var bn := -1
	for c in pd.population.chunk_counts():
		var n: int = pd.population.chunk_counts()[c]
		if n > bn:
			bn = n
			best = c
	var cs := builder.layout.chunk_size
	await _go(Vector3((best.x + 0.5) * cs, 0.0, (best.y + 0.5) * cs), 60)
	await wait_physics_until(func(): return pd.active_count() >= 25, 900)
	for i in 20:
		await physics_frames(10)
		check(pd.active_count() <= 25, "never more than the cap (%d)" % pd.active_count())
	check_eq(pd.active_count(), 25, "cap reached")
	# Nearest first: the live zombies are closer than the data left around.
	var farthest_live := 0.0
	for z in pd.real_zombies():
		farthest_live = maxf(farthest_live, z.global_position.distance_to(player.global_position))
	var p2 := Vector2(player.global_position.x, player.global_position.z)
	var nearest_data := INF
	for c in pd.active_chunks():
		for id in pd.population.groups_in_chunk(c):
			nearest_data = minf(nearest_data, p2.distance_to(pd.population.groups[id].pos))
	check(nearest_data == INF or nearest_data > farthest_live - 25.0, "nearest first (live ≤ %.0f m, data ≥ %.0f m)" % [farthest_live, nearest_data])


func test_no_slow_frame_sprinting_across_five_chunk_borders() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	var start := player.global_position
	var dir := (_far_from(start, 400.0) - start)
	dir.y = 0.0
	dir = dir.normalized()
	var speed := 6.5
	var ft: Node = _FrameTimer.new()
	tree.root.add_child(ft)
	ft.probe = func() -> Array:
		return [snappedf(streamer.frame_ms, 0.1), snappedf(pd.frame_usec / 1000.0, 0.1), snappedf(nav.tick_usec / 1000.0, 0.1),
			snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.1), streamer.loads, streamer.unloads,
			pd.spawned_count, pd.folded_count]
	await frames(2)
	ft.start()
	var frames_n := 0
	var crossed := 0
	var last := streamer.chunk_at(start)
	var pos := start
	var unbuilt := 0
	while crossed < 5 and frames_n < 60 * 90:
		pos += dir * speed / 60.0
		player.global_position = Vector3(pos.x, 0.1, pos.z)
		player.velocity = dir * speed
		await tree.physics_frame
		frames_n += 1
		var c := streamer.chunk_at(player.global_position)
		if not builder.chunks.has(c):
			unbuilt += 1
		if c != last:
			crossed += 1
			last = c
	ft.stop()
	check_eq(crossed, 5, "crossed 5 chunk borders (%d physics frames)" % frames_n)
	check_eq(unbuilt, 0, "never in an unbuilt chunk")
	var slow: Array = []
	for v in ft.intervals:
		if v > 33.0:
			slow.append(snappedf(v, 0.1))
	check(slow.is_empty(), "no frame over 33 ms (worst %.1f, p99 %.1f, avg %.2f over %d frames; slow %s)" % [
		ft.worst(), ft.percentile(0.99), ft.average(), ft.intervals.size(), str(slow.slice(0, 8))])
	for line in ft.slow_report(33.0):
		print("  slow frame [streamer ms, director ms, nav ms, physics ms (1 s monitor), loads, unloads, spawned, folded] ", line)
	print("  sprint: %d frames, avg %.2f ms, p99 %.1f, worst %.1f ms; %d loads, %d unloads, max build step %.1f ms (%s), live zombies %d (frozen %d)" % [
		ft.intervals.size(), ft.average(), ft.percentile(0.99), ft.worst(), streamer.loads, streamer.unloads,
		streamer.max_step_ms, streamer.max_step_name, pd.active_count(), pd.frozen_count])
	ft.queue_free()


const _FrameTimer := preload("res://tests/integration/frame_timer.gd")
