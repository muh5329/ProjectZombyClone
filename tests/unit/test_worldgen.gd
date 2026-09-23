extends "res://tests/test_case.gd"
## Round 11: the procedural world layout (WorldGenerator) and building
## plans (BuildingPlanGenerator) — pure, no scene. Determinism by hash,
## no overlaps, one connected road network reaching every door, doors on
## the road side, valid plans on 20 seeds, required content, sane zones,
## full validation on 30 seeds, params scaling (384-1536 m), variety,
## rural groups, improvised weapons, deterministic RNG seeds, save hash.

const SEEDS_FULL := [1337, 7, 99, 4242, 31337]


func _gen(s: int) -> WorldLayout:
	return WorldGenerator.generate(s)


func test_same_seed_gives_identical_layout_and_plans() -> void:
	var a := _gen(1337)
	var b := _gen(1337)
	check_eq(a.layout_hash(), b.layout_hash(), "layout hash")
	check_eq(a.plan_hash(), b.plan_hash(), "plan hash")
	check_eq(a.to_json(), b.to_json(), "full json")
	var ids_a: Array = []
	for bl in a.buildings:
		ids_a.append(bl.id)
	var ids_b: Array = []
	for bl in b.buildings:
		ids_b.append(bl.id)
	check_eq(ids_a, ids_b, "building ids stable")


func test_different_seeds_give_different_layouts() -> void:
	var hashes := {}
	for s in [1, 2, 3, 1337]:
		hashes[_gen(s).layout_hash()] = true
	check_eq(hashes.size(), 4, "4 seeds → 4 distinct layouts")


func test_layout_budget_and_counts() -> void:
	var t0 := Time.get_ticks_msec()
	var l := _gen(1337)
	var ms := Time.get_ticks_msec() - t0
	check_lt(ms, 2000.0, "layout generation under 2 s")
	check_eq(l.chunks_x(), 12, "12 chunks across")
	check_eq(l.chunks_z(), 12, "12 chunks down")
	check_gt(l.buildings.size(), 40.0, "buildings")
	check_gt(l.tree_count(), 2000.0, "trees")
	check_gt(l.fields.size(), 5.0, "fields")
	check_eq(l.chunk_density.size(), 144, "density record per chunk")


func test_no_overlaps_connected_roads_doors_face_roads() -> void:
	for s in SEEDS_FULL:
		var l := _gen(s)
		for pr in WorldLayoutValidator.overlap_problems(l):
			fail("seed %d: %s" % [s, pr])
		for pr in WorldLayoutValidator.connectivity_problems(l):
			fail("seed %d: %s" % [s, pr])
		for pr in WorldLayoutValidator.door_problems(l):
			fail("seed %d: %s" % [s, pr])
		check(true, "seed %d checked" % s)


## The full validator (overlaps incl. rotated vehicle boxes, road crossings
## / overlaps / water, props vs driveways / doors, fences vs vehicles,
## connectivity, doors, content) on 30 seeds: zero problems. The 200-seed
## sweep is scripts/worldgen_sweep.sh (perf lane).
func test_full_validation_on_30_seeds() -> void:
	var total := 0
	for s in range(1, 31):
		var l := WorldGenerator.generate_fresh(s)
		var probs := WorldLayoutValidator.layout_problems(l)
		total += probs.size()
		for pr in probs:
			fail("seed %d: %s" % [s, pr])
	check_eq(total, 0, "0 problems on 30 seeds")


func test_params_validate_and_scale_with_world_size() -> void:
	var bad := WorldGenerator.default_params().duplicate() as WorldGenParams
	bad.world_size = Vector2(200, 200)
	bad.hamlet_count_min = 5
	bad.hamlet_count_max = 2
	var why := bad.validate()
	check(why.size() >= 2, "bad params reported: %s" % str(why))
	var small := WorldGenerator.default_params().duplicate() as WorldGenParams
	small.world_size = Vector2(384, 384)
	for s in range(1, 6):
		var l := WorldGenerator.generate_fresh(s, small)
		var hamlets := 0
		var farms := 0
		for st in l.settlements:
			if st.kind == &"hamlet":
				hamlets += 1
			elif st.kind == &"farmstead":
				farms += 1
		check(hamlets >= 1 and farms >= 2, "384 m seed %d: %d hamlets, %d farms" % [s, hamlets, farms])
		for kind in [&"warehouse", &"gas_station"]:
			var bl := l.buildings_of_kind(kind)
			check(bl.size() == 1 and Rect2(Vector2.ZERO, l.size).encloses(bl[0].rect), "384 m seed %d: %s inside" % [s, kind])
		for pr in WorldLayoutValidator.layout_problems(l):
			fail("384 m seed %d: %s" % [s, pr])
	var big := WorldGenerator.default_params().duplicate() as WorldGenParams
	big.world_size = Vector2(1536, 1536)
	var lb := WorldGenerator.generate_fresh(3, big)
	check_lt(float(lb.stats.total_ms), 2000.0, "1536 m layout under 2 s (%.0f ms)" % lb.stats.total_ms)
	check(lb.road("hw_2") != {}, "a second highway at 1536 m")
	check_gt(float(lb.stats.farm_target), 8.0, "farm target scales with area (%d)" % lb.stats.farm_target)
	check_eq(small.scaled_range(3, 8, 2), Vector2i(2, 2), "counts scale down (floor 2)")
	check_eq(big.scaled_range(3, 8, 2), Vector2i(12, 32), "counts scale up")


## Town variety over 12 seeds: centres spread, any orientation, several
## block shapes, hamlets on the county / highway roads, curvy rural roads.
func test_variety_across_seeds() -> void:
	var xs: Array[float] = []
	var angles: Array[float] = []
	var shapes := {}
	var crossroads := 0
	var ratios: Array[float] = []
	for s in range(200, 212):
		var l := _gen(s)
		var town := l.settlement("town")
		xs.append((town.center as Vector2).x)
		angles.append(fposmod(float(town.angle_deg), 180.0))
		shapes[String(town.blocks)] = true
		for st in l.settlements:
			if st.kind == &"hamlet":
				var rd := l.road(String(st.road))
				check(rd.kind in [&"county", &"highway"], "hamlet %s on a county / highway road (%s)" % [st.id, st.road])
				if st.layout == "crossroads":
					crossroads += 1
		for rd2 in l.roads:
			if not (rd2.kind in [&"highway", &"county"]) or String(rd2.id).begins_with("hamlet"):
				continue
			var pts: PackedVector2Array = rd2.points
			var length := 0.0
			for i in range(pts.size() - 1):
				length += pts[i].distance_to(pts[i + 1])
			var chord := pts[0].distance_to(pts[pts.size() - 1])
			if chord > 150.0:
				ratios.append(length / chord)
	check_gt(xs.max() - xs.min(), 200.0, "town centres spread (%.0f m)" % (xs.max() - xs.min()))
	check_gt(angles.max() - angles.min(), 90.0, "town orientations spread")
	check(shapes.size() >= 4, "block shapes vary (%s)" % str(shapes.keys()))
	check_gt(crossroads, 0.0, "some crossroads hamlets")
	var mean := 0.0
	for v in ratios:
		mean += v
	mean /= maxf(ratios.size(), 1.0)
	check(mean >= 1.15 and mean <= 1.35, "rural road length / chord %.2f in 1.15-1.35" % mean)


func test_rural_zombie_groups_outside_the_start_area() -> void:
	var l := _gen(7)
	check_gt(l.zombie_groups.size(), 2.0, "rural groups")
	var sc := l.chunk_of(l.spawn_point)
	for g in l.zombie_groups:
		var c: Vector2i = g.chunk
		check(maxi(absi(c.x - sc.x), absi(c.y - sc.y)) > 2, "group %s outside the active chunks" % g.id)
		check((g.points as PackedVector2Array).size() >= 1, "group %s has zombies" % g.id)


func test_improvised_weapons_in_houses() -> void:
	var knives := 0
	for s in 200:
		var plan := BuildingPlanGenerator.generate(&"house", 9000 + s, {"garage": s % 3 == 0, "max_width": 16.0})
		for f in plan.furniture:
			for it in f.get("fixed", []):
				if it.id == &"kitchen_knife":
					knives += 1
	check(knives >= 60 and knives <= 100, "kitchen knife in ~40 %% of kitchens (%d / 200)" % knives)
	var armed := BuildingPlanGenerator.generate(&"house", 5, {"garage": false, "max_width": 16.0, "hammer": true})
	var has_hammer := false
	for f in armed.furniture:
		for it in f.get("fixed", []):
			if it.id == &"hammer":
				has_hammer = true
	check(has_hammer, "opts.hammer puts a hammer in the house")


func test_component_rng_seeds_are_deterministic() -> void:
	var a := Node.new()
	a.name = "Player"
	var b := Node.new()
	b.name = "Player"
	check_eq(WorldConfig.rng_seed_for(a, "melee"), WorldConfig.rng_seed_for(b, "melee"), "same owner + tag → same seed")
	check(WorldConfig.rng_seed_for(a, "melee") != WorldConfig.rng_seed_for(a, "injuries"), "tags differ")
	a.free()
	b.free()


func test_required_content_and_zone_ratios() -> void:
	for s in SEEDS_FULL:
		var l := _gen(s)
		for pr in WorldLayoutValidator.content_problems(l):
			fail("seed %d: %s" % [s, pr])
		var town_houses := 0
		for b in l.buildings:
			if b.kind == &"house" and b.settlement == "town":
				town_houses += 1
		check(town_houses >= 8, "seed %d: >= 8 town houses (%d)" % [s, town_houses])
		check(l.buildings_of_kind(&"convenience_store").size() >= 1, "store")
		check(l.buildings_of_kind(&"warehouse").size() >= 1, "warehouse")
		check(l.buildings_of_kind(&"gas_station").size() >= 1, "gas station")
		var farms := 0
		for st in l.settlements:
			if st.kind == &"farmstead":
				farms += 1
		check(farms >= 3, "seed %d: >= 3 farmsteads (%d)" % [s, farms])
		var z := l.zone_ratios()
		check(z[WorldLayout.Zone.WOODS] > 0.1 and z[WorldLayout.Zone.WOODS] < 0.55, "woods ratio %.2f" % z[WorldLayout.Zone.WOODS])
		check(z[WorldLayout.Zone.FIELD] > 0.08, "farmland ratio %.2f" % z[WorldLayout.Zone.FIELD])


func test_every_settlement_on_one_road_network() -> void:
	var l := _gen(99)
	var comps := WorldLayoutValidator.road_components(l)
	var main: String = comps.find.call(comps.key.call((l.roads[0].points as PackedVector2Array)[0]))
	for st in l.settlements:
		var reached := false
		for b in l.buildings:
			if b.settlement == st.id and WorldLayoutValidator.component_at(l, comps, b.access) == main:
				reached = true
		check(reached, "settlement %s reaches the network" % st.id)


func test_generated_plans_valid_on_20_seeds() -> void:
	var n := 0
	for s in range(500, 520):
		var l := _gen(s)
		for pr in WorldLayoutValidator.plan_problems(l):
			fail("seed %d: %s" % [s, pr])
		n += l.plans.size()
	check_gt(n, 800.0, "plans checked")


func test_every_kind_of_plan_is_valid_and_reachable() -> void:
	for kind in BuildingPlanGenerator.KINDS:
		for s in 25:
			var plan := BuildingPlanGenerator.generate(kind, 1000 + s, {"garage": s % 2 == 0, "max_width": 16.0 if kind == &"house" else 999.0})
			for pr in plan.validate():
				fail("%s #%d: %s" % [kind, s, pr])
			for pr in BuildingPlanGenerator.check(plan):
				fail("%s #%d: %s" % [kind, s, pr])
			check(BuildingPlanGenerator.opening_point(plan, "front_door") != Vector2.INF, "%s has a front door" % kind)
			check(plan.rooms.size() >= 3, "%s has rooms" % kind)
	# House room programme: living, kitchen, bedroom(s), bathroom, 3-6 rooms.
	for s in 20:
		var hp := BuildingPlanGenerator.generate(&"house", 77 + s, {"garage": true, "max_width": 16.0})
		var types := {}
		for r in hp.rooms:
			types[BuildingPlan.room_type_of(r)] = true
		for t in [&"living_room", &"kitchen", &"bedroom", &"bathroom"]:
			check(types.has(t), "house #%d has a %s" % [s, t])
		check(hp.rooms.size() >= 3 and hp.rooms.size() <= 6, "3-6 rooms (%d)" % hp.rooms.size())
		check(hp.footprint.x >= 6.0 and hp.footprint.y >= 7.0, "house footprint %s" % hp.footprint)


func test_store_warehouse_gas_station_barn_programmes() -> void:
	var store := BuildingPlanGenerator.generate(&"convenience_store", 5)
	var counts := {}
	for f in store.furniture:
		counts[f.type] = int(counts.get(f.type, 0)) + 1
	check_gt(counts.get(&"store_shelf", 0), 3.0, "store shelf rows")
	check(counts.has(&"counter"), "store counter")
	check(store.room_named("Office") != {}, "store office")
	check(store.room_named("Storage") != {}, "store back storage")
	var wh := BuildingPlanGenerator.generate(&"warehouse", 5)
	var racks := 0
	for f in wh.furniture:
		if f.type == &"rack":
			racks += 1
	check_gt(racks, 6.0, "warehouse racks")
	check(BuildingPlanGenerator.opening_point(wh, "loading_door") != Vector2.INF, "loading door")
	var gas := BuildingPlanGenerator.generate(&"gas_station", 5)
	check_eq(gas.building_type, &"gas_station", "gas station type")
	var barn := BuildingPlanGenerator.generate(&"barn", 5)
	var hay := 0
	for f in barn.furniture:
		if f.type == &"hay_bale":
			hay += 1
	check_gt(hay, 3.0, "hay in the barn")


func test_rotate_plan_four_times_is_identity_and_stays_valid() -> void:
	var plan := BuildingPlanGenerator.generate(&"house", 42, {"garage": true, "max_width": 16.0})
	var cur := plan
	for k in 4:
		cur = BuildingPlanGenerator.rotate_plan(cur, 1)
		check(cur.validate().is_empty(), "rotated %d validates %s" % [k + 1, str(cur.validate())])
		check(BuildingPlanGenerator.check(cur).is_empty(), "rotated %d checks %s" % [k + 1, str(BuildingPlanGenerator.check(cur))])
	check(cur.footprint.is_equal_approx(plan.footprint), "footprint back")
	for i in plan.rooms.size():
		check((cur.rooms[i].rect as Rect2).is_equal_approx(plan.rooms[i].rect), "room %d rect back" % i)
	for i in plan.furniture.size():
		check((cur.furniture[i].position as Vector2).distance_to(plan.furniture[i].position) < 0.01, "furniture %d back" % i)
	# Front (+Z) → east after one turn: the front door's wall faces +X.
	var e := BuildingPlanGenerator.rotate_plan(plan, BuildingPlanGenerator.quarter_turns_for(WorldLayout.FRONT_E))
	check(BuildingPlanGenerator.opening_outward(e, "front_door").is_equal_approx(Vector2(1, 0)), "front door faces east")
	var nn := BuildingPlanGenerator.rotate_plan(plan, BuildingPlanGenerator.quarter_turns_for(WorldLayout.FRONT_N))
	check(BuildingPlanGenerator.opening_outward(nn, "front_door").is_equal_approx(Vector2(0, -1)), "front door faces north")


func test_plan_ids_are_explicit_and_unique() -> void:
	var l := _gen(7)
	for id in l.plans:
		var pr: Array[String] = (l.plans[id] as BuildingPlan).id_problems()
		check(pr.is_empty(), "plan %s ids: %s" % [id, str(pr)])


func test_active_zombies_near_start_and_density_records() -> void:
	var l := _gen(1337)
	var near := 0
	for q in l.zombies:
		if q.distance_to(l.spawn_point) < 160.0:
			near += 1
		check(q.distance_to(l.spawn_point) >= 15.0, "zombie away from the start house")
	check(near >= 30, "30+ zombies within 160 m of the start (%d)" % near)
	# Town chunks are denser than woods / fields chunks.
	var town := l.settlement("town")
	var tc := l.chunk_of(town.center)
	var tdens: float = l.chunk_density[l.chunk_index(tc)]
	var corner: float = l.chunk_density[0]
	check_gt(tdens, corner, "town chunk denser than a corner chunk")


func test_chunk_helpers() -> void:
	var l := _gen(3)
	check_eq(l.chunk_of(Vector2(10, 10)), Vector2i(0, 0), "chunk of origin")
	check_eq(l.chunk_of(Vector2(767, 700)), Vector2i(11, 10), "chunk near the far edge")
	check_eq(l.chunks_around(Vector2i(0, 0), 2).size(), 9, "corner chunk radius 2 → 3x3")
	check_eq(l.chunks_around(Vector2i(5, 5), 2).size(), 25, "radius 2 → 5x5")


func test_map_renderer_draws_the_layout() -> void:
	var l := _gen(1337)
	var img := WorldMapRenderer.render(l, 3.0)
	check_eq(img.get_width(), 256, "width")
	var b: Dictionary = l.buildings[0]
	var c: Vector2 = (b.rect as Rect2).get_center() / 3.0
	var px := img.get_pixel(int(c.x), int(c.y))
	check(px != WorldMapRenderer.MEADOW, "building drawn")


func test_save_schema_accepts_only_worldgen_params() -> void:
	var base := {"version": SaveFile.VERSION, "map": "res://maps/world.tscn",
		"world": {"seed": 5, "age_days": 0.0, "water_shutoff_day": 14, "worldgen_params": "res://data/worldgen/default_world.tres"},
		"time": {"minutes": 0.0}, "statics": {}, "destroyed": [], "spawners": {}, "zombies": [], "corpses": [], "items": [],
		"player": {}}
	var why := SaveSchema.check(base)
	check(not why.contains("worldgen"), "worldgen params accepted (%s)" % why)
	var bad := base.duplicate(true)
	bad.world.worldgen_params = "res://maps/test_ground.tscn"
	check(SaveSchema.check(bad).contains("worldgen_params"), "foreign path refused")
	var wg := base.duplicate(true)
	wg.world["worldgen"] = {"version": WorldGenerator.VERSION, "layout_hash": "ab".repeat(32)}
	check(not SaveSchema.check(wg).contains("worldgen"), "worldgen version + hash accepted")
	wg.world.worldgen.layout_hash = "nothex"
	check(SaveSchema.check(wg).contains("layout_hash"), "bad hash refused")


## Saves of a generated world carry the generator version and layout hash;
## a load regenerates and refuses a different world.
func test_save_worldgen_hash_check() -> void:
	var l := _gen(5)
	var data := {"world": {"seed": 5, "worldgen_params": "res://data/worldgen/default_world.tres",
		"worldgen": {"version": WorldGenerator.VERSION, "layout_hash": l.layout_hash()}}}
	check_eq(SaveManager.check_worldgen(data), "", "matching hash loads")
	data.world.worldgen.version = WorldGenerator.VERSION - 1
	check_eq(SaveManager.check_worldgen(data), "", "older version, same world: loads (nothing to migrate)")
	data.world.worldgen.layout_hash = "0".repeat(64)
	var why := SaveManager.check_worldgen(data)
	check(why.contains("world generator v%d" % (WorldGenerator.VERSION - 1)), "older version, different world refused: %s" % why)
	data.world.worldgen.version = WorldGenerator.VERSION
	check(SaveManager.check_worldgen(data).contains("hash mismatch"), "same version, different hash refused")
