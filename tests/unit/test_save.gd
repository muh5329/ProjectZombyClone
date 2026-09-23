extends "res://tests/test_case.gd"
## Round 10 (pure-ish): every to_dict / from_dict (save_state /
## load_state) pair survives a JSON round trip, the save file format
## (version + migration hook, validation, corrupt JSON refused, atomic
## writes, slots) and the Saveable helpers.

const SLOT := "unit_test_slot"


func teardown() -> void:
	SaveFile.delete_slot(SLOT)
	SaveFile.migrations.clear()


## JSON round trip (what really happens on disk).
func _json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(SaveFile.to_json(d))


func _inst(id: StringName, n: int = 1, cond: int = -1) -> ItemInstance:
	return ItemInstance.new(ItemDB.get_item(id), cond, n)


# --- Component round trips ------------------------------------------------------------

func test_stats_round_trip() -> void:
	var s := StatsComponent.new()
	s.add_stat(&"stamina", 100.0)
	s.add_stat(&"hunger", 100.0)
	s.set_value(&"stamina", 37.5)
	s.set_value(&"hunger", 61.25)
	var s2 := StatsComponent.new()
	s2.add_stat(&"stamina", 100.0)
	s2.add_stat(&"hunger", 100.0)
	s2.from_dict(_json(s.to_dict()))
	check_near(s2.get_value(&"stamina"), 37.5, 0.0001, "stamina")
	check_near(s2.get_value(&"hunger"), 61.25, 0.0001, "hunger")
	s.free()
	s2.free()


func test_health_round_trip() -> void:
	var h := HealthComponent.new()
	h.max_health = 100.0
	h.health = 42.5
	var h2 := HealthComponent.new()
	h2.character = h2  # no EventBus payload issues
	h2.from_dict(_json(h.to_dict()))
	check_near(h2.health, 42.5, 0.0001, "health")
	check(not h2.dead, "alive")
	h2.from_dict({"health": 500.0})
	check_near(h2.health, 100.0, 0.0001, "clamped to max")
	h.free()
	h2.free()


func test_injury_round_trip_keeps_timers_and_infinite_bleeding() -> void:
	var i := Injury.new(Injury.Region.LEFT_ARM, Injury.Type.BITE)
	i.bleeding = true
	i.bleed_left = INF
	i.heal_left = 33.0
	i.heal_total = 120.0
	i.bandaged = true
	i.bandage_quality = 0.5
	i.rebleed_left = 12.0
	i.infected = true
	i.age = 7.5
	var d := _json(i.save_dict())
	check_eq(float(d.bleed_left), -1.0, "INF stored as -1 (JSON-safe)")
	var b := Injury.from_save(d)
	check(b != null, "rebuilt")
	check_eq(b.region, Injury.Region.LEFT_ARM, "region")
	check_eq(b.type, Injury.Type.BITE, "type")
	check(b.bleeding and b.bleed_left == INF, "infinite bleed restored")
	check_near(b.heal_left, 33.0, 0.001, "heal left")
	check_near(b.heal_total, 120.0, 0.001, "heal total")
	check(b.bandaged and is_equal_approx(b.bandage_quality, 0.5), "bandage + quality")
	check_near(b.rebleed_left, 12.0, 0.001, "rebleed timer")
	check(b.infected, "infected")
	check_near(b.age, 7.5, 0.001, "age")
	check(Injury.from_save({"region": "tail", "type": "bite"}) == null, "unknown region refused")


func test_skills_round_trip() -> void:
	var s := SkillComponent.new()
	s.add_xp(SkillComponent.CARPENTRY, 130.0)
	var s2 := SkillComponent.new()
	s2.from_dict(_json(s.to_dict()))
	check_near(s2.get_xp(SkillComponent.CARPENTRY), 130.0, 0.001, "xp")
	check_eq(s2.level(SkillComponent.CARPENTRY), s.level(SkillComponent.CARPENTRY), "level")
	s.free()
	s2.free()


func test_item_container_round_trip_nested_bags_conditions_ages() -> void:
	var c := ItemContainer.new(50.0)
	c.add(_inst(&"baseball_bat", 1, 7))
	c.add(_inst(&"nails", 23))
	var apple := _inst(&"apple")
	apple.portion = 0.5
	apple.age_minutes = 1234.0
	c.add(apple)
	var bag := _inst(&"backpack")
	var duffel := _inst(&"duffel_bag")
	duffel.contents.add(_inst(&"nails", 30))
	bag.contents.add(duffel)
	bag.contents.add(_inst(&"bandage", 2))
	c.add(bag)
	var c2 := ItemContainer.new(50.0)
	c2.from_dict(_json(c.to_dict()))
	check_eq(c2.items.size(), 4, "four stacks")
	var bat := c2.find(&"baseball_bat")
	check(bat != null and bat.condition == 7, "condition kept")
	check_eq(c2.count_of(&"nails"), 23, "stack count")
	var a2 := c2.find(&"apple")
	check(a2 != null and is_equal_approx(a2.portion, 0.5), "portion kept")
	check_near(a2.effective_age(), 1234.0, 1.0, "age kept")
	var b2 := c2.find(&"backpack")
	check(b2 != null and b2.contents.count_of(&"bandage") == 2, "bag contents")
	var d2 := b2.contents.find(&"duffel_bag") if b2 else null
	check(d2 != null and d2.contents.count_of(&"nails") == 30, "nested bag contents")
	check_eq(SaveFile.to_json(_json(c2.to_dict())), SaveFile.to_json(_json(c.to_dict())), "idempotent")


func test_barricade_round_trip() -> void:
	var b := BarricadeComponent.new()
	b.from_dict({"side": -1.0, "planks": [{"health": 30.0, "max": 60.0, "tilt": 3.0}]})
	var b2 := BarricadeComponent.new()
	b2.from_dict(_json(b.to_dict()))
	check_eq(b2.plank_count(), 1, "planks")
	check_eq(b2.side, -1.0, "side")
	check_near(float(b2.planks[0].health), 30.0, 0.001, "plank health")
	b.free()
	b2.free()


func test_loot_container_round_trip_searched_and_unsearched() -> void:
	var c := LootContainer.new()
	c.persist_id = "T/c"
	c.searched = true
	c.inventory.add(_inst(&"apple", 2))
	var c2 := LootContainer.new()
	c2.load_state(_json(c.save_state()))
	check(c2.searched, "searched flag")
	check_eq(c2.inventory.count_of(&"apple"), 2, "contents")
	var u := LootContainer.new()
	var u2 := LootContainer.new()
	u2.load_state(_json(u.save_state()))
	check(not u2.searched and u2.inventory.is_empty(), "unsearched stays unrolled")
	for n in [c, c2, u, u2]:
		n.free()


func test_time_round_trip_resets_speed() -> void:
	TimeManager.reset()
	TimeManager.advance(125.0)
	var saved := _json(TimeManager.to_dict())
	TimeManager.reset()
	TimeManager.from_dict({"minutes": saved.minutes})
	check_near(TimeManager.now(), 125.0, 0.001, "minutes")
	check_eq(TimeManager.speed_step, TimeManager.STEP_NORMAL, "1×")
	TimeManager.reset()


func test_spawner_state_keeps_64_bit_rng() -> void:
	var s := ZombieSpawner.new()
	s.rng.seed = 987654321
	s.rng.randi()
	s.spawn_counter = 17
	var want := s.rng.randi()
	s.rng.seed = 987654321
	s.rng.randi()
	var d := _json(s.save_state())
	var s2 := ZombieSpawner.new()
	s2.load_state(d)
	check_eq(s2.spawn_counter, 17, "counter")
	check_eq(s2.rng.randi(), want, "rng state survives JSON (stored as a string)")
	s.free()
	s2.free()


# --- Save file format ---------------------------------------------------------------------

func _minimal() -> Dictionary:
	return {"version": SaveFile.VERSION, "map": "res://maps/test_ground.tscn",
		"world": {"seed": 1}, "time": {"minutes": 10.0},
		"player": {"position": [0, 0, 0], "carried": {"inventory": {"items": []}}}, "statics": {}}


## A valid snapshot with one of every record (the tamper tests break it).
func _rich() -> Dictionary:
	var d := _minimal()
	d.statics = {
		"HouseA/kitchen/0": {"kind": "container", "searched": true, "inventory": {"capacity": 20.0,
			"items": [{"id": "apple", "count": 2, "condition": 0, "uid": 5}]}},
		"HouseA/front_door": {"kind": "door", "state": "closed", "health": 250.0, "locked": false, "swing": 0.0,
			"barricade": {"side": 1.0, "planks": [{"health": 30.0, "max": 60.0, "tilt": 2.0}]}},
		"HouseA/window_living_s": {"kind": "window", "state": "smashed", "glass": true, "pane_hp": 0.0},
		"HouseA/sofa/furniture": {"kind": "furniture", "blocking": "", "health": 220.0},
	}
	d.destroyed = ["HouseA/living_room/0/furniture"]
	d.spawners = {"Zombies": {"spawn_counter": 3, "rng_state": "123456789012345"}}
	d.zombies = [{"spawn_id": "Zombies/1", "seed": 7, "position": [1, 0, 2], "facing": 0.5, "health": 40.0,
		"home": [1, 0, 2], "state": "investigate", "target": [3, 0, 3], "profile": "zombie_basic"}]
	d.corpses = [{"persist_id": "corpse/Zombies/2", "seed": 9, "position": [4, 0, 4], "yaw": 1.0, "pose": "death",
		"container": {"searched": false, "inventory": {"items": []}}}]
	d.items = [{"item": {"id": "backpack", "count": 1, "condition": 0, "uid": 11,
		"contents": {"items": [{"id": "nails", "count": 30, "condition": 0}]}}, "position": [0, 0, 1], "yaw": 0.0}]
	d.player = {"position": [0, 0.1, 0], "facing": 0.0, "stats": {"stamina": 80.0, "hunger": 10.0},
		"health": {"health": 90.0, "max": 100.0, "dead": false},
		"injuries": {"injuries": [{"region": "left_arm", "type": "scratch", "bleeding": false, "bleed_left": -1.0,
			"heal_left": 10.0, "heal_total": 60.0, "bandaged": true, "bandage_quality": 1.0, "rebleed_left": -1.0,
			"infected": false, "age": 3.0}], "infected": false},
		"needs": {"hunger": 10.0}, "skills": {"xp": {"carpentry": 20.0}},
		"carried": {"inventory": {"items": [{"id": "baseball_bat", "count": 1, "condition": 7, "uid": 1}]},
			"equipment": {"slots": {"back": {"id": "backpack", "count": 1, "condition": 0}}, "hotbar": [{"uid": 1}, null, null]}}}
	d.blood = {"splats": [[1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.05, 0]]}
	d.camera = {"yaw_index": 1, "zoom_index": 1}
	return d


func test_every_tampered_field_is_refused() -> void:
	check_eq(SaveFile.validate(_json(_rich())), "", "the rich snapshot is valid")
	var cases := {
		"null position": func(d): d.player.position = null,
		"infinite coordinate": func(d): d.zombies[0].position = [1e999, 0, 0],
		"item not a dict": func(d): d.items[0].item = "apple",
		"item path to a scene": func(d): d.items[0].item = {"path": "res://maps/test_ground.tscn", "count": 1},
		"unknown item id": func(d): d.statics["HouseA/kitchen/0"].inventory.items[0].id = "res://evil.tres",
		"planks not dicts": func(d): d.statics["HouseA/front_door"].barricade.planks = [5],
		"carried a string": func(d): d.player.carried = "abc",
		"corpse container a string": func(d): d.corpses[0].container = "full",
		"locked as text": func(d): d.statics["HouseA/front_door"].locked = "yes",
		"spawners a string": func(d): d.spawners = "Zombies",
		"blood a string": func(d): d.blood = "lots",
		"negative health": func(d): d.player.health.health = -5.0,
		"huge count": func(d): d.statics["HouseA/kitchen/0"].inventory.items[0].count = 1e12,
		"count over max_stack": func(d): d.player.carried.inventory.items[0].count = 2,
		"condition over max": func(d): d.player.carried.inventory.items[0].condition = 999,
		"unknown kind": func(d): d.statics["HouseA/sofa/furniture"].kind = "bomb",
		"bad door state": func(d): d.statics["HouseA/front_door"].state = "ajar",
		"zombie profile path": func(d): d.zombies[0].profile = "res://data/zombies/zombie_basic.tres",
		"zombie dead health": func(d): d.zombies[0].health = 0.0,
		"zombie state": func(d): d.zombies[0].state = "chase",
		"bad rng state": func(d): d.spawners.Zombies.rng_state = 5,
		"contents on a non-bag": func(d): d.player.carried.inventory.items[0].contents = {"items": []},
		"wound region": func(d): d.player.injuries.injuries[0].region = "tail",
		"hotbar entry": func(d): d.player.carried.equipment.hotbar[0] = 3,
		"equipment slot": func(d): d.player.carried.equipment.slots = {"head": {"id": "apple", "count": 1}},
		"map outside res://maps": func(d): d.map = "res://ui/menus/main_menu.tscn",
		"map with ..": func(d): d.map = "res://maps/../ui/menus/main_menu.tscn",
		"world time negative": func(d): d.time.minutes = -3.0,
		"destroyed not strings": func(d): d.destroyed = [1, 2],
		"statics entry a list": func(d): d.statics["HouseA/front_door"] = [],
		"blood splat short": func(d): d.blood.splats = [[1, 2]],
		"stat NaN-ish string": func(d): d.player.stats.stamina = "80",
	}
	for name in cases:
		var d := _json(_rich())
		(cases[name] as Callable).call(d)
		var why := SaveFile.validate(d)
		check(why.begins_with("Corrupt save"), "%s → refused (%s)" % [name, why])


func test_corrupt_json_is_refused_with_a_reason() -> void:
	var r := SaveFile.decode("{\"version\": 1, \"map\": ")
	check(not r.ok, "truncated JSON refused")
	check(String(r.get("error", "")).begins_with("Corrupt save"), "clear error (%s)" % r.get("error"))
	check(not SaveFile.decode("").ok, "empty refused")
	check(not SaveFile.decode("[1, 2, 3]").ok, "not an object refused")
	var no_player := _minimal()
	no_player.erase("player")
	var r2 := SaveFile.decode(SaveFile.to_json(no_player))
	check(not r2.ok and String(r2.error).contains("player"), "missing key named (%s)" % r2.get("error"))
	var bad_map := _minimal()
	bad_map.map = "res://maps/nope.tscn"
	check(not SaveFile.decode(SaveFile.to_json(bad_map)).ok, "missing map refused")
	var bad_time := _minimal()
	bad_time.time = {"minutes": "noon"}
	check(not SaveFile.decode(SaveFile.to_json(bad_time)).ok, "bad time refused")
	check(SaveFile.decode(SaveFile.to_json(_minimal())).ok, "minimal save accepted")


func test_version_check_and_migration_hook() -> void:
	var newer := _minimal()
	newer.version = SaveFile.VERSION + 1
	var r := SaveFile.decode(SaveFile.to_json(newer))
	check(not r.ok and String(r.error).contains("newer"), "newer save refused (%s)" % r.get("error"))
	var old := _minimal()
	old.version = 0
	old.erase("statics")
	check(not SaveFile.decode(SaveFile.to_json(old)).ok, "no migration → refused")
	SaveFile.migrations[0] = func(d: Dictionary) -> Dictionary:
		d["statics"] = {}
		return d
	var m := SaveFile.decode(SaveFile.to_json(old))
	check(m.ok, "migrated 0 → 1 (%s)" % m.get("error", ""))
	check_eq(int(m.data.version), SaveFile.VERSION, "version bumped")
	check(m.data.statics is Dictionary, "migration applied")
	var nov := _minimal()
	nov.erase("version")
	check(not SaveFile.decode(SaveFile.to_json(nov)).ok, "no version refused")


func test_atomic_write_replaces_and_leaves_no_temp() -> void:
	var path := SaveFile.world_path(SLOT)
	check_eq(SaveFile.write_atomic(path, "{\"a\": 1}"), OK, "first write")
	check_eq(SaveFile.write_atomic(path, "{\"a\": 2}"), OK, "overwrite")
	var r := SaveFile.read_text(path)
	check(r.ok and r.text == "{\"a\": 2}", "new content")
	check(not FileAccess.file_exists(path + SaveFile.TMP_SUFFIX), "no temp left")
	check(not FileAccess.file_exists(path + SaveFile.OLD_SUFFIX), "no backup left")
	# A crash between the renames leaves only the .old: still readable.
	DirAccess.rename_absolute(path, path + SaveFile.OLD_SUFFIX)
	var r2 := SaveFile.read_text(path)
	check(r2.ok and r2.text == "{\"a\": 2}", "falls back to the previous file")
	# A stale temp from an interrupted write is ignored and overwritten.
	var f := FileAccess.open(path + SaveFile.TMP_SUFFIX, FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	check_eq(SaveFile.write_atomic(path, "{\"a\": 3}"), OK, "write over a stale temp")
	check_eq(String(SaveFile.read_text(path).text), "{\"a\": 3}", "content")


func test_slots_list_and_delete() -> void:
	SaveFile.write_atomic(SaveFile.world_path(SLOT), SaveFile.to_json(_minimal()))
	SaveFile.write_atomic(SaveFile.meta_path(SLOT), JSON.stringify({"timestamp": 5.0, "day": 3, "clock": "07:00"}))
	var found := false
	for e in SaveFile.list_slots():
		if e.slot == SLOT:
			found = true
			check_eq(int(e.meta.day), 3, "meta read")
	check(found, "slot listed")
	check(SaveFile.delete_slot(SLOT), "deleted")
	check(not FileAccess.file_exists(SaveFile.world_path(SLOT)), "gone")


func test_slot_names_are_encoded_without_collisions() -> void:
	check_eq(SaveFile.encode_slot(""), "", "empty refused")
	check_eq(SaveFile.encode_slot("   "), "", "blank refused")
	check(not SaveFile.is_valid_slot("x".repeat(SaveFile.MAX_SLOT_LENGTH + 1)), "too long refused")
	check_eq(SaveFile.encode_slot("quick"), "quick", "plain names unchanged")
	var names := ["a b", "a_20b", "a_b", "a/b", "../x", "a.b", "a-b", "Ä", "a b "]
	var dirs := {}
	for n in names:
		var enc := SaveFile.encode_slot(n)
		check(enc != "" and not enc.contains("/") and not enc.contains(".") and not enc.contains(" "), "%s → safe dir %s" % [n, enc])
		check_eq(SaveFile.decode_slot(enc), n.strip_edges(), "%s round-trips" % n)
		dirs[enc] = dirs.get(enc, []) + [n.strip_edges()]
	for k in dirs:
		var uniq := {}
		for n in dirs[k]:
			uniq[n] = true
		check_eq(uniq.size(), 1, "no collision in %s (%s)" % [k, str(dirs[k])])
	check(SaveFile.slot_dir("x").begins_with(SaveFile.root), "under the save root")


func test_tests_write_to_their_own_root() -> void:
	check_eq(SaveFile.root, SaveFile.TEST_ROOT, "tests use user://test_saves")


func test_meta_fields_are_type_safe() -> void:
	var weird := {"slot": 5, "meta": {"day": "x", "clock": 3, "player": "hp", "datetime": ["a"], "timestamp": "late"}}
	var t := MenuStyle.slot_text(weird)
	check(t.contains("Day 1") and t.contains("--:--"), "bad fields fall back (%s)" % t)
	check(MenuStyle.slot_text("garbage").contains("?"), "non-dict entry")
	check_eq(SaveFile.meta_num({"timestamp": "late"}, "timestamp", 0.0), 0.0, "meta_num typed")


func test_json_is_deterministic_and_lossless() -> void:
	var d := {"b": 0.1 + 0.2, "a": [1.0 / 3.0, Vector3(0.3, 0.1, 0.7).x], "c": {"z": 1, "y": 2}}
	var t1 := SaveFile.to_json(d)
	var t2 := SaveFile.to_json(JSON.parse_string(t1))
	var t3 := SaveFile.to_json(JSON.parse_string(t2))
	check_eq(t3, t2, "parse → stringify is stable (floats keep full precision)")
	check(t1.contains("0.30000000000000004") and t1.contains("0.30000001192092896"), "full precision")
	check(t1.find("\"a\"") < t1.find("\"b\""), "sorted keys")


func test_saveable_helpers() -> void:
	check_eq(Saveable.to_vec3(Saveable.vec3(Vector3(1, 2, 3))), Vector3(1, 2, 3), "vec3")
	check_eq(Saveable.to_vec3(null, Vector3.ONE), Vector3.ONE, "fallback")
	var t := Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(2, 1, 1)), Vector3(4, 5, 6))
	check(Saveable.to_xform(_json({"t": Saveable.xform(t)}).t).is_equal_approx(t), "transform")
	check_eq(Saveable.finite_or(INF), -1.0, "INF → -1")
