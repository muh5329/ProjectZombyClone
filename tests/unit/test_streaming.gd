extends "res://tests/test_case.gd"
## Round 12 (pure): chunk streaming maths (radius, hysteresis, queue
## order), the WorldStateStore (delta capture / apply idempotence,
## spoilage while unloaded, save round trip) and the ZombiePopulation sim
## (movement between chunks, sound attraction, merge / split,
## determinism, conservation, compact save), save v1 → v2 migration and
## the schema of the new save parts.

const PARAMS := "res://data/worldgen/default_world.tres"


func _layout() -> WorldLayout:
	return WorldGenerator.generate(1337, load(PARAMS))


func _params() -> PopulationParams:
	return load("res://data/simulation/default_population.tres").duplicate()


func _pop(prm: PopulationParams = null) -> ZombiePopulation:
	var p := ZombiePopulation.new()
	p.setup(Vector2(768, 768), 64.0, prm if prm != null else _params(), 42)
	p.attractors = PackedVector2Array([Vector2(384, 384)])
	return p


# --- Streamer maths ----------------------------------------------------------------------

func test_chunks_within_radius_and_clamped() -> void:
	var all := ChunkStreamer.chunks_within(Vector2i(5, 5), 3, Vector2i(12, 12))
	check_eq(all.size(), 49, "7 x 7 around the middle")
	var corner := ChunkStreamer.chunks_within(Vector2i(0, 0), 3, Vector2i(12, 12))
	check_eq(corner.size(), 16, "4 x 4 in the corner (clamped)")
	for c in corner:
		check(c.x >= 0 and c.y >= 0, "inside the world")
	check_eq(ChunkStreamer.chebyshev(Vector2i(1, 1), Vector2i(4, -1)), 3, "Chebyshev distance")


func test_unload_hysteresis() -> void:
	var loaded := [Vector2i(5, 5), Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 9)]
	var out := ChunkStreamer.to_unload(loaded, Vector2i(5, 5), 4)
	check(not out.has(Vector2i(5, 5)), "own chunk kept")
	check(not out.has(Vector2i(8, 5)), "radius 3 kept")
	check(not out.has(Vector2i(9, 5)), "radius 4 kept (hysteresis: loaded ≤ 3, freed > 4)")
	check(out.has(Vector2i(10, 9)), "radius 5 freed")
	# Walking back and forth across one border never reloads / unloads.
	var r := ChunkStreamer.to_unload([Vector2i(2, 5), Vector2i(9, 5)], Vector2i(6, 5), 4)
	check(r.is_empty(), "a one-chunk step keeps everything (%s)" % str(r))


func test_queue_nearest_first_and_ahead_of_walking_direction() -> void:
	var pos := Vector2(5.5 * 64.0, 5.5 * 64.0)
	var list := ChunkStreamer.chunks_within(Vector2i(5, 5), 2, Vector2i(12, 12))
	var o := ChunkStreamer.order(list, pos, Vector2.ZERO, 64.0)
	check_eq(o[0], Vector2i(5, 5), "own chunk first")
	for i in range(1, 9):
		check_eq(ChunkStreamer.chebyshev(o[i], Vector2i(5, 5)), 1, "ring 1 before ring 2 (%s)" % o[i])
	var o2 := ChunkStreamer.order([Vector2i(3, 5), Vector2i(7, 5)], pos, Vector2(6.0, 0.0), 64.0)
	check_eq(o2[0], Vector2i(7, 5), "the chunk ahead (east, walking east) first")
	var o3 := ChunkStreamer.order([Vector2i(3, 5), Vector2i(7, 5)], pos, Vector2(-6.0, 0.0), 64.0)
	check_eq(o3[0], Vector2i(3, 5), "walking west: the west chunk first")
	var tie := ChunkStreamer.order([Vector2i(6, 5), Vector2i(4, 5), Vector2i(5, 4), Vector2i(5, 6)], pos, Vector2.ZERO, 64.0)
	check_eq(tie, ChunkStreamer.order([Vector2i(5, 6), Vector2i(5, 4), Vector2i(4, 5), Vector2i(6, 5)], pos, Vector2.ZERO, 64.0),
		"ties broken deterministically")


# --- WorldStateStore -------------------------------------------------------------------------

func test_store_keeps_only_deltas_and_is_idempotent() -> void:
	var s := WorldStateStore.new()
	var door := {"kind": "door", "state": "closed", "health": 100.0, "locked": false, "swing": 0.0}
	var box := {"kind": "container", "persist_id": "a/b", "type": "crate", "searched": false, "inventory": {"capacity": 20.0, "items": []}}
	s.record_default("h/door", door.duplicate(true))
	s.record_default("h/box", box.duplicate(true))
	check(not s.capture("h/door", door.duplicate(true), 10.0), "untouched door not stored")
	check(not s.capture("h/box", box.duplicate(true), 10.0), "unsearched container not stored")
	check(s.statics.is_empty(), "store empty for an untouched chunk")
	var open := door.duplicate(true)
	open.state = "open"
	open.swing = 1.57
	check(s.capture("h/door", open, 10.0), "opened door stored")
	var searched := box.duplicate(true)
	searched.searched = true
	searched.inventory.items = [{"id": "hammer", "count": 1, "condition": 10, "uid": 5}]
	check(s.capture("h/box", searched, 12.0), "searched container stored")
	check_eq(float(s.statics["h/box"]._t), 12.0, "container stamped with the capture minute")
	check(not s.delta_for("h/box").has("_t"), "delta handed to load_state without bookkeeping")
	var before := s.to_dict()
	# Capture the same state again (unload → load → unload untouched).
	s.capture("h/door", open, 10.0)
	s.capture("h/box", searched, 12.0)
	check_eq(s.to_dict(), before, "capturing the same state twice changes nothing")
	# Applying a delta then capturing gives the same delta back.
	var applied := s.delta_for("h/door")
	check(WorldStateStore.states_equal(applied, open), "apply(delta) == the captured state")
	check_eq(s.elapsed_for("h/box", 100.0), 88.0, "elapsed minutes since capture")
	# Closed again: back to default → dropped from the store.
	s.capture("h/door", door.duplicate(true), 20.0)
	check(not s.statics.has("h/door"), "a door closed again is no delta")
	var rt := WorldStateStore.new()
	rt.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check_eq(rt.statics.keys(), s.statics.keys(), "JSON round trip keeps the deltas")


func test_store_dynamic_records_per_chunk() -> void:
	var s := WorldStateStore.new()
	s.put_dynamic(Vector2i(3, 4), [{"item": {"id": "hammer", "count": 1}, "position": [200.0, 0.0, 260.0], "yaw": 0.0}], [], [], 5.0)
	s.put_dynamic(Vector2i(1, 1), [], [], [], 5.0)
	check(s.has_dynamic(Vector2i(3, 4)), "items kept for their chunk")
	check(not s.has_dynamic(Vector2i(1, 1)), "empty chunk has no record")
	check_eq(s.dynamic_count(), 1, "one object held")
	var d := s.take_dynamic(Vector2i(3, 4))
	check_eq((d.items as Array).size(), 1, "taken back on load")
	check(not s.has_dynamic(Vector2i(3, 4)), "taken out of the store")
	check_eq(WorldStateStore.key_to_chunk(WorldStateStore.key(Vector2i(7, 11))), Vector2i(7, 11), "chunk key round trip")
	check_eq(WorldStateStore.key_to_chunk("x,1"), Vector2i(-1, -1), "bad key")


func test_food_spoils_while_its_chunk_is_unloaded() -> void:
	var inv := ItemContainer.new(20.0)
	var milk := ItemInstance.new(ItemDB.get_item(&"milk"))
	check(milk.perishable(), "milk is perishable")
	inv.add(milk)
	var age0 := milk.effective_age()
	WorldStateStore.age_inventory(inv, 3.0 * 1440.0)
	check_near(milk.effective_age() - age0, 3.0 * 1440.0, 1.0, "three days older")
	var fridge := ItemContainer.new(20.0)
	fridge.set_spoil_multiplier(0.25)
	var m2 := ItemInstance.new(ItemDB.get_item(&"milk"))
	fridge.add(m2)
	var a2 := m2.effective_age()
	WorldStateStore.age_inventory(fridge, 1440.0)
	check_near(m2.effective_age() - a2, 360.0, 1.0, "a fridge ages it at its rate")


# --- ZombiePopulation -----------------------------------------------------------------------------

func test_generation_density_and_total() -> void:
	var l := _layout()
	var prm := _params()
	var pop := ZombiePopulation.generate(l, 1337, prm)
	var total := pop.total()
	check(total >= prm.total_min and total <= prm.total_max, "county total in range (%d)" % total)
	var counts := pop.chunk_counts()
	var town := 0.0
	var town_n := 0
	var woods := 0.0
	var woods_n := 0
	var sc := l.chunk_of(l.spawn_point)
	var town_chunks := {}
	for b in l.buildings:
		if String(b.settlement).begins_with("town"):
			town_chunks[l.chunk_of((b.rect as Rect2).get_center())] = true
	for cz in l.chunks_z():
		for cx in l.chunks_x():
			var c := Vector2i(cx, cz)
			if ChunkStreamer.chebyshev(c, sc) <= prm.start_radius:
				continue
			var n := float(counts.get(c, 0))
			var z := l.zone_at(l.chunk_rect(c).get_center())
			if town_chunks.has(c):
				town += n
				town_n += 1
			elif z == WorldLayout.Zone.WOODS:
				woods += n
				woods_n += 1
	if town_n > 0 and woods_n > 0:
		check_gt(town / town_n, woods / woods_n, "town chunks denser than woods (%.1f vs %.1f)" % [town / town_n, woods / woods_n])
	var start := 0
	for c in l.chunks_around(sc, prm.start_radius):
		start += int(counts.get(c, 0))
	check_lt(float(start), float(l.zombies.size()) + 25.0, "no fill in the start area (%d)" % start)
	var again := ZombiePopulation.generate(l, 1337, prm)
	check_eq(again.to_dict(), pop.to_dict(), "same seed → same population")


func test_group_follows_a_loud_sound_across_chunks() -> void:
	var pop := _pop()
	var gid := pop.add_group(Vector2(100, 100), pop.new_members(4))
	var far := pop.add_group(Vector2(600, 600), pop.new_members(3))
	var sound := Vector2(170, 100)
	check_eq(pop.hear(sound, 20.0 * 1.5), 0, "a 20 m sound 70 m away is not heard")
	check_eq(pop.hear(sound, 60.0 * 1.5), 1, "a gunshot 70 m away is heard by one group")
	check_eq(int(pop.groups[gid].state), ZombiePopulation.State.INVESTIGATE, "investigating")
	check_eq(int(pop.groups[far].state), ZombiePopulation.State.WANDER, "the far group did not hear it")
	var c0 := pop.chunk_of(pop.groups[gid].pos)
	var d0 := (pop.groups[gid].pos as Vector2).distance_to(sound)
	pop.tick(30.0)
	var d1 := (pop.groups[gid].pos as Vector2).distance_to(sound)
	check_lt(d1, d0 - 20.0, "30 game minutes later it is much nearer (%.0f → %.0f m)" % [d0, d1])
	pop.tick(60.0)
	check_lt((pop.groups[gid].pos as Vector2).distance_to(sound), 6.0, "arrived at the noise")
	check(pop.chunk_of(pop.groups[gid].pos) != c0, "moved into the next chunk (%s → %s)" % [c0, pop.chunk_of(pop.groups[gid].pos)])
	check_eq(int(pop.groups[gid].state), ZombiePopulation.State.WANDER, "wanders there after arriving")


func test_merge_and_split_conserve_members() -> void:
	var prm := _params()
	prm.split_chance_per_hour = 0.0
	var pop := _pop(prm)
	var a := pop.add_group(Vector2(300, 300), pop.new_members(3))
	var b := pop.add_group(Vector2(303, 301), pop.new_members(2))
	pop.add_group(Vector2(500, 300), pop.new_members(2))
	pop.params.wander_speed = 0.0
	for i in 8:
		pop.tick(0.5)
	check(pop.groups.has(a) != pop.groups.has(b), "the two close groups merged")
	check_eq(pop.total(), 7, "members conserved by the merge")
	check_eq(pop.groups.size(), 2, "the far group stayed apart")
	var big := pop.add_group(Vector2(100, 600), pop.new_members(20))
	pop.params.split_chance_per_hour = 1.0e6
	for i in 8:
		pop.tick(0.5)
	check_lt(float((pop.groups[big].members as PackedInt32Array).size()), 20.0, "a big wandering group split")
	check_eq(pop.total(), 27, "members conserved by the split")


func test_determinism_and_save_round_trip() -> void:
	var l := _layout()
	var a := ZombiePopulation.generate(l, 1337, _params())
	var b := ZombiePopulation.generate(l, 1337, _params())
	for i in 40:
		a.tick(0.5)
		b.tick(0.5)
	a.hear(Vector2(300, 300), 90.0)
	b.hear(Vector2(300, 300), 90.0)
	a.tick(12.0)
	b.tick(12.0)
	check_eq(a.to_dict(), b.to_dict(), "same seed + same inputs → same population")
	# JSON round trip, then both continue identically.
	var c := ZombiePopulation.generate(l, 1337, _params())
	c.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	check_eq(c.to_dict(), a.to_dict(), "save round trip is exact")
	check_eq(c.total(), a.total(), "same members after load")
	var s := JSON.stringify(a.to_dict())
	check_lt(float(s.length()), 30000.0, "population save is compact (%d bytes)" % s.length())


func test_conservation_over_a_game_day_with_activation() -> void:
	var l := _layout()
	var pop := ZombiePopulation.generate(l, 7, _params())
	var start := pop.total()
	var real: Array = []  # [member, pos]
	for step in 96:  # 1 game day in 15-minute steps
		pop.tick(15.0)
		if step % 8 == 0:
			var ids := pop.groups.keys()
			ids.sort()
			var g: Dictionary = pop.groups[ids[step % ids.size()]]
			var gid := int(g.id)
			for m in pop.take_members(gid, 2):
				real.append([m, g.pos])
		if step % 8 == 4 and not real.is_empty():
			var r: Array = real.pop_front()
			pop.fold(int(r[0]), r[1])
		if step == 50 and not real.is_empty():
			var dead: Array = real.pop_back()
			pop.record_death(int(dead[0]))
	check_eq(pop.total() + real.size() + pop.deaths, start, "data + real + dead is constant over a day")
	check_eq(pop.deaths, 1, "one death recorded")


func test_fold_joins_a_nearby_group_and_keeps_wounds() -> void:
	var pop := _pop()
	var g := pop.add_group(Vector2(200, 200), pop.new_members(2))
	var m := pop.new_members(1)[0]
	check_eq(pop.fold(m, Vector2(202, 201), ZombiePopulation.State.WANDER, Vector2.INF, 40.0), g, "joins the group 2 m away")
	check_eq(float(pop.hurt[m]), 40.0, "wound kept")
	var m2 := pop.new_members(1)[0]
	var g2 := pop.fold(m2, Vector2(260, 200), ZombiePopulation.State.INVESTIGATE, Vector2(300, 200), -1.0, 99)
	check(g2 != g, "far / investigating → a group of its own")
	check_eq(pop.member_seed(m2), 99, "a foreign zombie keeps its look")
	check_eq(int(pop.groups[g2].state), ZombiePopulation.State.INVESTIGATE, "still investigating")


func test_member_ranges_round_trip() -> void:
	var m := PackedInt32Array([0, 1, 2, 5, 7, 8, 9, 20])
	check_eq(ZombiePopulation.ranges_of(m), "0-2,5,7-9,20", "ranges")
	check_eq(ZombiePopulation.parse_ranges("0-2,5,7-9,20"), m, "parsed back")
	check(ZombiePopulation.parse_ranges("3-1").is_empty(), "reversed range refused")
	check(ZombiePopulation.parse_ranges("a").is_empty(), "garbage refused")


# --- Saves ------------------------------------------------------------------------------------

func _v1_world() -> Dictionary:
	return {"version": 1, "map": "res://maps/world.tscn",
		"world": {"seed": 1337, "age_days": 0.0, "water_shutoff_day": 14, "worldgen_params": PARAMS,
			"worldgen": {"version": WorldGenerator.VERSION, "layout_hash": _layout().layout_hash()}},
		"time": {"minutes": 30.0}, "statics": {"town_01/front_door": {"kind": "door", "state": "open", "health": 100.0, "locked": false, "swing": 1.5}},
		"destroyed": [], "spawners": {"Zombies": {"spawn_counter": 3, "rng_state": "5", "groups_spawned": ["group_hamlet1"]}},
		"zombies": [], "corpses": [{"persist_id": "corpse/Zombies/1", "seed": 3, "position": [130.0, 0.0, 70.0], "yaw": 0.0,
			"pose": "death", "container": {"searched": false, "inventory": {"items": []}}}],
		"items": [{"item": {"id": "hammer", "count": 1}, "position": [10.0, 0.0, 200.0], "yaw": 0.0}],
		"player": {"position": [1.0, 0.0, 1.0], "facing": 0.0, "carried": {"inventory": {"items": []}}},
		"blood": {"splats": [[1, 0, 0, 0, 1, 0, 0, 0, 1, 70.0, 0.05, 70.0]]}}


func test_round11_world_save_migrates_to_streamed_format() -> void:
	var r := SaveFile.decode(SaveFile.to_json(_v1_world()))
	check(r.ok, "v1 generated-world save migrates and validates (%s)" % r.get("error", ""))
	if not r.ok:
		return
	var d: Dictionary = r.data
	check_eq(int(d.version), SaveFile.VERSION, "version 2")
	check(d.chunks.has("0,3"), "dropped item moved to its chunk record")
	check(d.chunks.has("2,1"), "corpse moved to its chunk record")
	check_eq((d.chunks["1,1"].blood as Array).size(), 1, "blood moved to its chunk")
	check((d.items as Array).is_empty() and (d.corpses as Array).is_empty(), "flat lists emptied")
	check(bool(d.population.legacy), "population regenerated (legacy)")
	check_eq(d.population.groups_spawned, ["group_hamlet1"], "spawned rural groups remembered")
	check(d.statics.has("town_01/front_door"), "statics kept as deltas")
	# A hand-made map's v1 save keeps its format.
	var tg := _v1_world()
	tg.map = "res://maps/test_ground.tscn"
	tg.world.erase("worldgen")
	tg.world.erase("worldgen_params")
	var r2 := SaveFile.decode(SaveFile.to_json(tg))
	check(r2.ok, "test-ground v1 save still loads (%s)" % r2.get("error", ""))
	if r2.ok:
		check(not r2.data.has("chunks"), "no chunk records for a hand-made map")
		check_eq((r2.data.items as Array).size(), 1, "items stay a flat list")


func test_schema_checks_chunks_and_population() -> void:
	var base: Dictionary = SaveFile.decode(SaveFile.to_json(_v1_world())).data
	var pop := _pop()
	pop.add_group(Vector2(10, 10), pop.new_members(3), ZombiePopulation.State.INVESTIGATE, Vector2(40, 40))
	base.population = JSON.parse_string(JSON.stringify(pop.to_dict()))
	check_eq(SaveSchema.check(base), "", "population record valid")
	var bad := base.duplicate(true)
	bad.population.groups[0][8] = "9-1"
	check(SaveSchema.check(bad).contains("members"), "bad member ranges refused: %s" % SaveSchema.check(bad))
	var bad2 := base.duplicate(true)
	bad2.population.groups[0][1] = "x"
	check(SaveSchema.check(bad2) != "", "non-numeric position refused")
	var bad3 := base.duplicate(true)
	bad3.chunks["zz"] = {"items": []}
	check(SaveSchema.check(bad3).contains("chunk key"), "bad chunk key refused")
	var bad4 := base.duplicate(true)
	bad4.chunks["0,3"].items[0].item.id = "no_such_item"
	check(SaveSchema.check(bad4).contains("unknown item"), "unknown item in a chunk refused")
	var bad5 := base.duplicate(true)
	bad5.statics["town_01/front_door"]["_t"] = -5.0
	check(SaveSchema.check(bad5) != "", "negative capture minute refused")


func test_zombies_follow_zombies_toward_a_noise() -> void:
	var pop := _pop()
	var a := pop.add_group(Vector2(160, 100), pop.new_members(2))   # 60 m: direct
	var b := pop.add_group(Vector2(200, 100), pop.new_members(2))   # 40 m from a
	var c := pop.add_group(Vector2(240, 100), pop.new_members(2))   # 40 m from b
	var lone := pop.add_group(Vector2(100, 500), pop.new_members(2))
	check_eq(pop.hear(Vector2(100, 100), 70.0), 3, "direct + two relay hops")
	for g in [a, b, c]:
		check_eq(int(pop.groups[g].state), ZombiePopulation.State.INVESTIGATE, "group %d walks to the noise" % g)
		check_lt((pop.groups[g].target as Vector2).distance_to(Vector2(100, 100)), 5.0, "toward the noise")
	check_eq(int(pop.groups[lone].state), ZombiePopulation.State.WANDER, "an isolated far group does not hear it")
	check_gt(float(pop.groups[c].timer), 90.0 + 130.0, "keeps investigating long enough to arrive")


func test_which_sounds_the_population_hears() -> void:
	for id in [&"footstep_sprint", &"footstep_jog", &"door_open", &"rummage", &"melee_hit"]:
		check_eq(SoundManager.category(id).sim_carry, 0.0, "%s never reaches the simulation" % id)
	for id in [&"window_smash", &"door_break", &"hammering", &"shout", &"alarm"]:
		check(SoundManager.category(id).sim_carry >= 3.0, "%s carries ×3+ for the simulation" % id)
	check_gt(SoundManager.category(&"alarm").radius * SoundManager.category(&"alarm").sim_carry, 180.0, "an alarm carries far")
