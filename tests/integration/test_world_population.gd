extends "res://tests/test_case.gd"
## Round 12 critic fixes in the real maps/world.tscn (seed 1337):
## cheap-moving zombies never slide into sealed houses; unloading a chunk
## that is still being built keeps its stored items; a zombie killed in
## the frame it was folded back stays dead; noise draws the population in
## play (a smashed window in town pulls a simulated group from 100-200 m
## — zombies follow zombies — that walks into the active area as real
## zombies; a car alarm pulls groups from ~300 m); sprinting through the
## woods makes no far / unreachable path queries and no slow frames.

const SEED := 1337
const _FrameTimer := preload("res://tests/integration/frame_timer.gd")

var scene: Node
var player: Player
var builder: WorldBuilder
var nav: WorldNav
var streamer: ChunkStreamer
var pd: PopulationDirector


func setup() -> void:
	scene = SaveManager.instantiate_new_game("res://maps/world.tscn", SEED)
	tree.root.add_child(scene)
	scene_bind(scene)
	await wait_physics_until(func(): return nav.baked, 1800)
	await physics_frames(5)


func teardown() -> void:
	TimeManager.set_speed(TimeManager.STEP_NORMAL)
	await despawn(scene)
	tree.paused = false


func scene_bind(map: Node) -> void:
	scene = map
	player = map.get_node("Player")
	builder = map.get_node("Generated")
	nav = map.get_node("NavRegion")
	streamer = map.get_node("Streamer")
	pd = map.get_node("Population")
	player.get_node("Controller").scripted = true
	player.get_node("Interaction").scripted = true
	player.get_node("Health").invulnerable = true


func _go(p: Vector3, settle: int = 30) -> void:
	player.global_position = Vector3(p.x, 0.1, p.z)
	player.velocity = Vector3.ZERO
	await physics_frames(3)
	streamer.flush()
	await wait_physics_until(func(): return nav.chunk_ready(streamer.chunk_at(player.global_position)), 900)
	await physics_frames(settle)


func _private_params() -> void:
	# The params .tres is a shared cached resource: tests change a copy.
	pd.population.params = pd.population.params.duplicate()


## Doors closed + locked, windows closed: every opening intact.
static func _seal(hb: HouseBlockout) -> void:
	for d in hb.doors:
		d.load_state({"state": "closed", "health": d.health_max, "locked": true, "swing": 0.0})
	for w in hb.windows:
		w.load_state({"state": "closed", "glass": true, "pane_hp": w.pane_health})


static func _still_sealed(hb: HouseBlockout) -> bool:
	for d in hb.doors:
		if d.is_open() or d.is_broken():
			return false
	for w in hb.windows:
		if w.state != HouseWindow.STATE_CLOSED:
			return false
	return true


func test_cheap_moving_zombies_never_slide_into_sealed_houses() -> void:
	pd.enabled = false
	var sp: ZombieSpawner = scene.get_node("Zombies")
	for z in sp.zombies:
		if is_instance_valid(z):
			z.queue_free()
	await physics_frames(2)
	# The 8 houses nearest the start (not the one the player is in).
	var list: Array = []
	for id in builder.buildings:
		var hb: HouseBlockout = builder.buildings[id]
		if String(id) == builder.layout.spawn_building or not (hb.get_meta(&"kind", &"") in [&"house", &"farmhouse"]):
			continue
		list.append([hb.global_position.distance_to(player.global_position), hb])
	list.sort_custom(func(a, b): return a[0] < b[0])
	var houses: Array = []
	for e in list.slice(0, 8):
		houses.append(e[1])
	check_eq(houses.size(), 8, "8 houses near the start")
	var zombies: Array = []
	for hb in houses:
		_seal(hb)
		var d: Door = hb.doors[0]
		for k in 3:
			var q := sp.find_spot(d.global_position + d.outward * (4.0 + 2.0 * k) + Vector3(float(k) - 1.0, 0, 0) * 2.0, 4.0, 8)
			if q != Vector3.INF:
				zombies.append(sp.spawn_at(q))
	check_gt(float(zombies.size()), 16.0, "zombies around the houses (%d)" % zombies.size())
	# The player stands well away (every zombie is a far, calm — cheap —
	# mover), and a noise inside each house keeps pulling them in.
	var far := builder.start_position() + Vector3(0, 0, 0)
	var best := -INF
	for dx in [-60.0, 60.0]:
		for dz in [-60.0, 60.0]:
			var p: Vector3 = (houses[0] as HouseBlockout).global_position + Vector3(dx, 0, dz)
			var dmin := INF
			for hb in houses:
				dmin = minf(dmin, (hb as HouseBlockout).global_position.distance_to(p))
			if dmin > best and not WorldQuery.is_inside_building(tree, p):
				best = dmin
				far = p
	await _go(far, 5)
	TimeManager.set_speed(3)
	var cheap_seen := 0
	for minute in 5:
		for hb in houses:
			var room: Room = (hb as HouseBlockout).rooms[0]
			SoundManager.emit_sound(&"hammering", room.global_position, null, {"radius": 25.0})
		for f in 15 * 60 / 4:
			await tree.physics_frame
			if f % 30 == 0:
				for z in zombies:
					if is_instance_valid(z) and z.cheap_movement:
						cheap_seen += 1
	TimeManager.set_speed(TimeManager.STEP_NORMAL)
	check_gt(float(cheap_seen), 0.0, "zombies moved cheaply meanwhile (%d samples)" % cheap_seen)
	var inside := 0
	var sealed := 0
	for hb in houses:
		if not _still_sealed(hb):
			continue
		sealed += 1
		for z in zombies:
			if is_instance_valid(z) and not z.dead and (hb as HouseBlockout).room_at(z.global_position + Vector3.UP * 0.5) != null:
				inside += 1
				fail("%s inside sealed %s at %s" % [z.spawn_id, hb.name, z.global_position])
	check_gt(float(sealed), 3.0, "houses still sealed after 5 game minutes (%d)" % sealed)
	check_eq(inside, 0, "no zombie inside a sealed house")


func test_unloading_a_half_built_chunk_keeps_its_stored_items() -> void:
	pd.enabled = false
	var pc := streamer.chunk_at(player.global_position)
	var c := Vector2i(-1, -1)
	for cc in builder.recipes:
		if not builder.chunks.has(cc) and not (builder.recipes[cc].buildings as Array).is_empty() \
				and ChunkStreamer.chebyshev(cc, pc) >= 5:
			c = cc
			break
	check(c != Vector2i(-1, -1), "an unloaded chunk with buildings")
	var rect := builder.layout.chunk_rect(c)
	var at := rect.get_center()
	var rec := {"item": {"id": "crowbar", "count": 1, "uid": 910001}, "position": [at.x, 0.0, at.y], "yaw": 0.0}
	streamer.store.put_dynamic(c, [rec], [], [], TimeManager.now())
	# Start building it, then unload it mid-build (a teleport away).
	streamer._do_step(c, "base")
	streamer._do_step(c, 0)
	check(builder.building_chunks.has(c) and not builder.chunks.has(c), "half built")
	streamer.unload(c)
	streamer.free_detached()
	check(streamer.store.has_dynamic(c), "the stored item record survived the aborted build")
	# Build it for real: the crowbar appears; unload: it is stored again.
	streamer.load_now(c)
	await physics_frames(2)
	var found := false
	for n in tree.get_nodes_in_group(WorldItem.GROUP):
		if scene.is_ancestor_of(n) and (n as WorldItem).item.uid == 910001:
			found = true
	check(found, "the crowbar lies in the loaded chunk")
	streamer.unload(c)
	streamer.free_detached()
	check(streamer.store.has_dynamic(c), "stored again after a full unload")


func test_zombie_killed_in_the_frame_it_is_folded_stays_dead() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	pd.flush_spawns()
	var z: Zombie = null
	for zz in pd.real_zombies():
		if PopulationDirector.member_of(zz) >= 0:
			z = zz
			break
	check(z != null, "a population zombie")
	if z == null:
		return
	var m := PopulationDirector.member_of(z)
	var total0 := pd.total_alive() + pd.died_count
	var deaths0 := pd.population.deaths
	pd.fold_zombie(z)
	var corpse := z.die(player)
	check(z.dead, "dead")
	check(corpse != null, "a corpse was laid")
	var still := false
	for id in pd.population.groups:
		if (pd.population.groups[id].members as PackedInt32Array).has(m):
			still = true
	check(not still, "member %d is not back in the population" % m)
	check_eq(pd.population.deaths, deaths0 + 1, "death recorded")
	await physics_frames(3)
	check_eq(pd.total_alive() + pd.died_count, total0, "conserved (a death, not a resurrection)")
	var corpses := 0
	for n in tree.get_nodes_in_group(&"corpse"):
		if scene.is_ancestor_of(n) and (n as ZombieCorpse).persist_id == "corpse/pop/%d" % m:
			corpses += 1
	check_eq(corpses, 1, "its corpse lies in the world")


## A point [dist] m from [from] toward the middle of the world.
func _data_groups_between(p: Vector2, lo: float, hi: float) -> Array:
	var out: Array = []
	for id in pd.population.groups:
		var d: float = (pd.population.groups[id].pos as Vector2).distance_to(p)
		if d >= lo and d <= hi:
			out.append(id)
	return out


func test_smashing_a_window_in_town_draws_a_simulated_group_from_afar() -> void:
	_private_params()
	pd.population.params.wander_speed = 0.0
	pd.population.params.migrate_chance_per_hour = 0.0
	# A shop window on the main street.
	var win: HouseWindow = null
	var hb0: HouseBlockout = null
	var road: Dictionary = builder.layout.road("town_main")
	var mid: Vector2 = (road.points as PackedVector2Array)[(road.points as PackedVector2Array).size() / 2]
	await _go(Vector3(mid.x, 0.0, mid.y), 20)
	var bd := INF
	for id in builder.buildings:
		var hb: HouseBlockout = builder.buildings[id]
		if not String(id).begins_with("town"):
			continue
		for w in hb.windows:
			var d := w.global_position.distance_to(player.global_position)
			if w.outward != Vector3.ZERO and d < bd:
				bd = d
				win = w
				hb0 = hb
	check(win != null, "a town window")
	if win == null:
		return
	await _go(win.global_position + win.outward * 1.2, 30)
	var sp2 := Vector2(player.global_position.x, player.global_position.z)
	var far_groups := _data_groups_between(sp2, 100.0, 200.0)
	check_gt(float(far_groups.size()), 0.0, "simulated groups 100-200 m away")
	var r := Interactable.of(win).perform(HouseWindow.ACTION_SMASH, player)
	check(r.get("ok", false), "window smashed: %s" % str(r))
	await physics_frames(2)
	check_gt(pd.last_sound_reach, 60.0, "the smash carries %.0f m for the simulation" % pd.last_sound_reach)
	var live_in := 0
	for z in pd.real_zombies():
		if Vector2(z.global_position.x, z.global_position.z).distance_to(sp2) <= pd.last_sound_reach:
			live_in += 1
	var dists: Array = []
	for id in far_groups:
		if pd.population.groups.has(id):
			var gp: Vector2 = pd.population.groups[id].pos
			var nd := INF
			for id2 in pd.population.groups:
				if id2 != id:
					nd = minf(nd, gp.distance_to(pd.population.groups[id2].pos))
			dists.append([snappedf(gp.distance_to(sp2), 1), snappedf(nd, 1)])
	print("  smash: reach %.0f m, %d groups turned, %d live zombies in reach; far groups [dist, nearest group] %s" % [pd.last_sound_reach, pd.last_sound_groups, live_in, str(dists)])
	var coming: Array = []
	for id in far_groups:
		if pd.population.groups.has(id) and int(pd.population.groups[id].state) == ZombiePopulation.State.INVESTIGATE:
			coming.append(id)
	check_gt(float(coming.size()), 0.0, "a group 100-200 m away turned toward the smash (%d of %d)" % [coming.size(), far_groups.size()])
	var members := {}
	for id in coming:
		for m in (pd.population.groups[id].members as PackedInt32Array):
			members["pop/%d" % m] = true
	# They shamble in (0.9 m per game minute = the live shamble speed at
	# 1×) and become real zombies once they cross into the active area.
	var arrived := 0
	for step in 40:
		TimeManager.advance(10.0)
		pd.tick_now()
		pd.sync_now()
		pd.flush_spawns()
		await physics_frames(2)
		arrived = 0
		for z in pd.real_zombies():
			if members.has(String(z.spawn_id)):
				arrived += 1
		if arrived > 0:
			print("  smash: %d groups 100-200 m away turned; first arrivals live after %d game minutes" % [coming.size(), (step + 1) * 10])
			break
	check_gt(float(arrived), 0.0, "zombies of those groups are live near the smash")


func test_car_alarm_pulls_groups_from_300_m() -> void:
	_private_params()
	var road: Dictionary = builder.layout.road("town_main")
	var mid: Vector2 = (road.points as PackedVector2Array)[(road.points as PackedVector2Array).size() / 2]
	await _go(Vector3(mid.x, 0.0, mid.y), 20)
	streamer.flush()
	var car: Vehicle = null
	var bd := INF
	for v in tree.get_nodes_in_group(Vehicle.GROUP):
		if scene.is_ancestor_of(v) and (v as Vehicle).has_alarm:
			var d := (v as Vehicle).global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				car = v
	check(car != null, "a town car with an alarm")
	if car == null:
		return
	var cp := Vector2(car.global_position.x, car.global_position.z)
	var far_groups := _data_groups_between(cp, 250.0, 310.0)
	check_gt(float(far_groups.size()), 0.0, "simulated groups 250-310 m from the car")
	car.sound_alarm()
	await physics_frames(3)
	check(car.is_alarm_sounding(), "the alarm sounds")
	check_gt(pd.last_sound_reach, 290.0, "the alarm carries %.0f m for the simulation" % pd.last_sound_reach)
	var turned := 0
	for id in far_groups:
		if pd.population.groups.has(id) and int(pd.population.groups[id].state) == ZombiePopulation.State.INVESTIGATE \
				and (pd.population.groups[id].target as Vector2).distance_to(cp) < 6.0:
			turned += 1
	check_eq(turned, far_groups.size(), "every group 250-310 m away walks to the car (%d)" % turned)
	# Breaking into an alarmed car: deterministic, ~30 % of cars go off.
	var cars := 0
	var loud := 0
	for v in tree.get_nodes_in_group(Vehicle.GROUP):
		if scene.is_ancestor_of(v) and (v as Vehicle).has_alarm and v != car:
			cars += 1
			(v as Vehicle).trunk.ensure_loot()
			if (v as Vehicle).is_alarm_sounding():
				loud += 1
	check_gt(float(cars), 3.0, "alarmed cars in town (%d)" % cars)
	check(loud > 0 and loud < cars, "some break-ins set the alarm off (%d of %d)" % [loud, cars])


func test_woods_sprint_makes_no_far_path_queries_and_no_slow_frames() -> void:
	await wait_physics_until(func(): return pd.active_count() >= 30, 600)
	var l := builder.layout
	var best := 0
	var best_z := 0
	for cz in l.chunks_z():
		var n := 0
		for cx in l.chunks_x():
			if l.zone_at(l.chunk_rect(Vector2i(cx, cz)).get_center()) == WorldLayout.Zone.WOODS:
				n += 1
		if n > best:
			best = n
			best_z = cz
	var y := (best_z + 0.5) * l.chunk_size
	var a := Vector3(40.0, 0.1, y)
	await _go(a, 120)
	pd.flush_spawns()
	ZombieAI.reset_query_stats()
	var ft: Node = _FrameTimer.new()
	tree.root.add_child(ft)
	await frames(2)
	ft.start()
	var pos := a
	var dir := Vector3.RIGHT
	var moved := 0.0
	while moved < 250.0:
		moved += 6.5 / 60.0
		pos = a + dir * moved
		player.global_position = Vector3(pos.x, 0.1, pos.z)
		player.velocity = dir * 6.5
		await tree.physics_frame
	ft.stop()
	player.velocity = Vector3.ZERO
	print("  woods sprint: %d frames, avg %.2f, p99 %.1f, worst %.1f ms; path queries %d (far %d, unreached %d); live %d frozen %d" % [
		ft.intervals.size(), ft.average(), ft.percentile(0.99), ft.worst(), ZombieAI.path_queries, ZombieAI.far_queries,
		ZombieAI.unreached_queries, pd.active_count(), pd.frozen_count])
	check_eq(ZombieAI.far_queries, 0, "no path query to a target beyond one leg (%d)" % ZombieAI.far_queries)
	check_eq(ZombieAI.unreached_queries, 0, "no path query to an unreachable target (%d of %d)" % [ZombieAI.unreached_queries, ZombieAI.path_queries])
	check_lt(ft.worst(), 40.0, "no frame over 40 ms in the woods (worst %.1f)" % ft.worst())
	ft.queue_free()
