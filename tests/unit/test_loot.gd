extends "res://tests/test_case.gd"
## Round 5: loot tables + LootResolver (pure, seeded) + table selection.


func _table(entries: Array, rolls := Vector2i(1, 1)) -> LootTable:
	var t := LootTable.new()
	t.rolls_min = rolls.x
	t.rolls_max = rolls.y
	var typed: Array[Dictionary] = []
	for e in entries:
		typed.append(e)
	t.entries = typed
	return t


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func _count(items: Array, id: StringName = &"") -> int:
	var n := 0
	for e in items:
		if id == &"" or e.id == id:
			n += int(e.count)
	return n


func test_all_tables_valid_against_item_db() -> void:
	LootTableDB.reload()
	var ids := LootTableDB.all_ids()
	for want in ["kitchen_cabinet", "fridge", "counter", "bathroom_cabinet", "bedroom_dresser",
			"wardrobe", "living_room_shelf", "shelf", "crate", "garage/tool_crate",
			"zombie_corpse", "convenience_store_shelf", "default"]:
		check(ids.has(want), "table %s exists (%s)" % [want, str(ids)])
	for id in ids:
		var t := LootTableDB.get_table(id)
		check(t != null, "loads %s" % id)
		var problems := t.validate(id)
		check(problems.is_empty(), "%s valid: %s" % [id, str(problems)])
		for iid in t.item_ids():
			check(ItemDB.has_item(iid), "%s: %s in ItemDB" % [id, iid])
			check(not ItemDB.get_item(iid).has_tag(&"internal"), "%s: no internal items (%s)" % [id, iid])
	var bad := _table([{"item_id": &"unobtainium", "weight": 1.0, "rarity": &"legendary"}])
	check_eq(bad.validate("bad").size(), 2, "unknown id + unknown rarity reported")
	# Corpse pockets: small change, a rag, sometimes a bandage / snack.
	var corpse := LootTableDB.get_table("zombie_corpse")
	for iid in [&"coins", &"rag", &"bandage", &"candy_bar"]:
		check(corpse.item_ids().has(iid), "corpse table has %s" % iid)


func test_determinism_with_seed() -> void:
	var t := LootTableDB.get_table("kitchen_cabinet")
	for s in [1, 42, 9001]:
		var a := LootResolver.roll(t, _rng(s), 0.0)
		var b := LootResolver.roll(t, _rng(s), 0.0)
		check_eq(str(a), str(b), "same seed %d → same loot" % s)
	var distinct := {}
	for s in 30:
		distinct[str(LootResolver.roll(t, _rng(s), 0.0))] = true
	check_gt(float(distinct.size()), 8.0, "seeds vary the loot")
	check_eq(LootResolver.seed_for(7, "HouseA/kitchen/0"), LootResolver.seed_for(7, "HouseA/kitchen/0"), "stable seed")
	check(LootResolver.seed_for(7, "HouseA/kitchen/0") != LootResolver.seed_for(7, "HouseA/kitchen/1"), "seed per container")
	check(LootResolver.seed_for(7, "a") != LootResolver.seed_for(8, "a"), "seed per world")


func test_weight_and_chance_distribution_10k() -> void:
	# One roll per container: apple weight 3, soda weight 1 with chance 0.5.
	var t := _table([
		{"item_id": &"apple", "weight": 3.0},
		{"item_id": &"soda", "weight": 1.0, "chance": 0.5},
	])
	var rng := _rng(123)
	var n := 10000
	var apples := 0
	var sodas := 0
	for i in n:
		var r := LootResolver.roll(t, rng)
		apples += _count(r, &"apple")
		sodas += _count(r, &"soda")
	check_near(float(apples) / n, 0.75, 0.015, "apple 75 %")
	check_near(float(sodas) / n, 0.125, 0.01, "soda 25 % × 50 %")
	# Counts: uniform min..max → mean 3 for 1..5; rolls 2..4 → mean 3.
	var t2 := _table([{"item_id": &"nails", "weight": 1.0, "min_count": 1, "max_count": 5}], Vector2i(2, 4))
	var total := 0
	for i in n:
		total += _count(LootResolver.roll(t2, rng))
	check_near(float(total) / n, 9.0, 0.15, "mean 3 rolls × 3 nails")
	# Empty chance.
	t2.empty_chance = 0.4
	var empties := 0
	for i in n:
		if LootResolver.roll(t2, rng).is_empty():
			empties += 1
	check_near(float(empties) / n, 0.4, 0.015, "empty 40 %")
	# Rarity tiers multiply the chance.
	var t3 := _table([{"item_id": &"crowbar", "weight": 1.0, "rarity": &"rare"}])
	var hits := 0
	for i in n:
		hits += _count(LootResolver.roll(t3, rng))
	check_near(float(hits) / n, 0.3, 0.015, "rare = ×0.3")
	check_near(LootTable.rarity_multiplier(&"very_rare"), 0.1, 0.0001, "very rare ×0.1")
	check_near(LootTable.rarity_multiplier(&"nonsense"), 1.0, 0.0001, "unknown → common")


func test_world_age_thinning() -> void:
	check_near(LootResolver.age_multiplier(0.0), 1.0, 0.0001, "day 0")
	check_near(LootResolver.age_multiplier(30.0), 0.5, 0.0001, "day 30 → 0.5")
	check_near(LootResolver.age_multiplier(48.0), 0.2, 0.0001, "day 48 → floor")
	check_near(LootResolver.age_multiplier(1000.0), 0.2, 0.0001, "floor 0.2")
	check_near(LootResolver.effective_chance({"chance": 0.5, "rarity": &"uncommon"}, 30.0), 0.15, 0.0001, "0.5 × 0.6 × 0.5")
	var t := _table([{"item_id": &"apple", "weight": 1.0}], Vector2i(2, 2))
	var n := 10000
	var avg := {}
	for age in [0.0, 30.0, 90.0]:
		var rng := _rng(5)
		var total := 0
		for i in n:
			total += _count(LootResolver.roll(t, rng, age))
		avg[age] = float(total) / n
	check_near(avg[0.0], 2.0, 0.001, "day 0: every roll")
	check_near(avg[30.0], 1.0, 0.05, "day 30: half")
	check_near(avg[90.0], 0.4, 0.04, "day 90: floor 20 %")
	# Thinning only removes items: the rng is consumed the same way, so a
	# day-30 container holds a subset of its day-0 contents.
	var kc := LootTableDB.get_table("kitchen_cabinet")
	for s in 50:
		var young := LootResolver.roll(kc, _rng(s), 0.0)
		var old := LootResolver.roll(kc, _rng(s), 30.0)
		for e in old:
			check(_count(young, e.id) >= int(e.count), "seed %d: %s ×%d also on day 0" % [s, e.id, e.count])
	# Multiset subset incl. condition items with max_count > 1, 500 seeds.
	var mixed := _table([
		{"item_id": &"baseball_bat", "weight": 2.0, "min_count": 1, "max_count": 3, "chance": 0.7},
		{"item_id": &"hammer", "weight": 1.0, "min_count": 1, "max_count": 2, "chance": 0.5, "rarity": &"uncommon"},
		{"item_id": &"nails", "weight": 3.0, "min_count": 5, "max_count": 20, "chance": 0.6},
		{"item_id": &"apple", "weight": 2.0, "min_count": 1, "max_count": 2},
	], Vector2i(1, 4))
	var bad := 0
	for sd in 500:
		var y := _multiset(LootResolver.roll(mixed, _rng(sd), 0.0))
		var o := _multiset(LootResolver.roll(mixed, _rng(sd), 40.0))
		for k in o:
			if int(y.get(k, 0)) < int(o[k]):
				bad += 1
				if bad < 5:
					fail("seed %d: age-40 %s ×%d not in age-0 roll" % [sd, k, o[k]])
	check_eq(bad, 0, "age-40 ⊆ age-0 for 500 seeds")


func test_condition_items_get_a_condition() -> void:
	var t := _table([{"item_id": &"baseball_bat", "weight": 1.0, "min_count": 2, "max_count": 2}])
	t.condition_min = 0.5
	t.condition_max = 0.5
	var r := LootResolver.roll(t, _rng(1))
	check_eq(r.size(), 2, "one entry per conditioned item")
	for e in r:
		check_eq(int(e.condition), 6, "50 % of 12")


func test_table_fallback_chain() -> void:
	var c := LootResolver.table_candidates(&"house", &"kitchen", &"fridge")
	check_eq(c[0], "house/kitchen/fridge", "most specific first")
	check_eq(c[-1], "default", "default last")
	check(c.find("fridge") < c.find("kitchen"), "container before room")
	check(c.find("kitchen") < c.find("default"), "room before default")
	# Real resolution through data/loot.
	check_eq(LootTableDB.resolve_id(&"house", &"kitchen", &"fridge"), "fridge", "container table")
	check_eq(LootTableDB.resolve_id(&"house", &"bedroom", &"dresser"), "bedroom_dresser", "room_container combo")
	check_eq(LootTableDB.resolve_id(&"house", &"living_room", &"shelf"), "living_room_shelf", "living room shelf")
	check_eq(LootTableDB.resolve_id(&"house", &"kitchen", &"shelf"), "shelf", "generic shelf elsewhere")
	check_eq(LootTableDB.resolve_id(&"shed", &"garage", &"tool_crate"), "garage/tool_crate", "room folder")
	check_eq(LootTableDB.resolve_id(&"shed", &"garage", &"shelf"), "garage/shelf", "garage shelf")
	check_eq(LootTableDB.resolve_id(&"convenience_store", &"", &"shelf"), "convenience_store_shelf", "building_container combo")
	check_eq(LootTableDB.resolve_id(&"house", &"attic", &"mystery_box"), "default", "unknown → default")
	check_eq(LootTableDB.resolve_id(&"", &"", &"zombie_corpse"), "zombie_corpse", "corpse")


## "id@condition" -> count.
func _multiset(items: Array) -> Dictionary:
	var out := {}
	for e in items:
		var k := "%s@%d" % [e.id, e.condition]
		out[k] = int(out.get(k, 0)) + int(e.count)
	return out


## Scarcity with stakes: a whole House A (its 8 plan containers) averages
## 5-11 pickups (stacks) over 50 world seeds; nails come 5-20; a corpse
## has a bandage ~5 % of the time.
func test_house_loot_budget_and_corpse_bandages() -> void:
	var plan: BuildingPlan = load("res://data/buildings/house_a.tres")
	var catalog: FurnitureCatalog = load("res://data/buildings/furniture_catalog.tres")
	var boxes: Array = []
	var per_room := {}
	for f in plan.furniture:
		var spec := catalog.resolve(StringName(f.type), f)
		if spec.container_type == null:
			continue
		var room := BuildingPlan.room_type_of(plan.room_named(String(f.room)))
		var idx: int = per_room.get(room, 0)
		per_room[room] = idx + 1
		boxes.append({"table": LootTableDB.resolve(plan.building_type, room, StringName(spec.container_type)), "id": "HouseA/%s/%d" % [room, idx]})
	check_eq(boxes.size(), 8, "8 containers in the plan")
	var stacks := 0
	var units := 0
	var empty_boxes := 0
	for ws in 50:
		for b in boxes:
			var r := LootResolver.roll(b.table, _rng(LootResolver.seed_for(ws, b.id)), 0.0)
			stacks += r.size()
			units += _count(r)
			if r.is_empty():
				empty_boxes += 1
	var avg := stacks / 50.0
	check(avg >= 5.0 and avg <= 11.0, "house averages 5-11 pickups (%.2f; %.1f items)" % [avg, units / 50.0])
	var empty_frac := empty_boxes / (50.0 * boxes.size())
	check(empty_frac >= 0.25 and empty_frac <= 0.55, "a third or so of containers are empty (%.2f)" % empty_frac)
	for id in LootTableDB.all_ids():
		for e in LootTableDB.get_table(id).entries:
			if e.item_id == &"nails":
				check(int(e.min_count) >= 5 and int(e.max_count) <= 20, "%s: nails 5-20" % id)
	var corpse := LootTableDB.get_table("zombie_corpse")
	var rng := _rng(77)
	var with_bandage := 0
	for i in 10000:
		if _count(LootResolver.roll(corpse, rng, 0.0), &"bandage") > 0:
			with_bandage += 1
	check_near(with_bandage / 10000.0, 0.05, 0.02, "corpse bandage ≈ 5 %")
	# The showcase cabinet holds food on the default world seed.
	var kc := LootResolver.roll(LootTableDB.get_table("kitchen_cabinet"), _rng(LootResolver.seed_for(1337, "HouseA/kitchen/0")), 0.0)
	var food := 0
	for e in kc:
		var d := ItemDB.get_item(e.id)
		if d.category == ItemData.Category.FOOD or d.category == ItemData.Category.DRINK:
			food += 1
	check_gt(float(food), 0.5, "HouseA/kitchen/0 has food on seed 1337 (%s)" % str(kc))
