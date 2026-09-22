extends "res://tests/test_case.gd"
## Round 5: ItemDB registry and the shared ItemContainer model (pure).


func _d(id: StringName) -> ItemData:
	return ItemDB.get_item(id)


func test_item_db_loads_catalogue() -> void:
	ItemDB.reload()
	var ids := ItemDB.all_ids()
	for id in [&"canned_beans", &"chips", &"apple", &"bread", &"water_bottle", &"soda",
			&"bandage", &"rag", &"disinfectant", &"painkillers", &"splint",
			&"hammer", &"screwdriver", &"saw", &"nails", &"nails_box", &"plank",
			&"lighter", &"newspaper", &"backpack", &"duffel_bag", &"tin_opener",
			&"baseball_bat", &"kitchen_knife", &"crowbar", &"pipe", &"fists", &"shove"]:
		check(ids.has(id), "ItemDB has %s" % id)
	var real := 0
	for id in ids:
		if not _d(id).has_tag(&"internal"):
			real += 1
	check_gt(float(real), 24.5, "at least 25 lootable items (%d)" % real)
	check(ItemDB.duplicates().is_empty(), "no duplicate ids (%s)" % str(ItemDB.duplicates()))
	check(ItemDB.get_item(&"nope") == null, "unknown id -> null")
	check(not ItemDB.has_item(&"nope"), "has_item false")
	# Same resource as a preload (cache), with the right subclasses.
	check(ItemDB.get_item(&"baseball_bat") == preload("res://data/items/weapons/baseball_bat.tres"), "cached weapon resource")
	check(_d(&"canned_beans") is FoodData and (_d(&"canned_beans") as FoodData).calories > 0.0, "beans are FoodData with calories")
	check(_d(&"water_bottle") is FoodData and _d(&"water_bottle").category == ItemData.Category.DRINK, "water is a drink")
	check((_d(&"bread") as FoodData).spoil_days > 0.0, "bread spoils")
	check(_d(&"bandage") is MedicalData and (_d(&"bandage") as MedicalData).bandage_quality == 1.0, "bandage quality 1")
	var rag := _d(&"rag") as MedicalData
	check(rag.bandage_quality < 1.0 and is_equal_approx(rag.rebleed_chance, 0.5) and is_equal_approx(rag.rebleed_after, 60.0), "rag: worse dressing, 50 % rebleed after 60 s")
	check((_d(&"disinfectant") as MedicalData).disinfectant > 0.0, "disinfectant strength")
	var bp := _d(&"backpack") as ContainerItemData
	check(bp != null and is_equal_approx(bp.capacity, 18.0) and is_equal_approx(bp.weight_reduction, 0.6), "backpack 18 / 0.6")
	check(_d(&"duffel_bag") is ContainerItemData, "duffel bag is a container item")
	check(_d(&"hammer").has_tag(&"hammer") and _d(&"hammer") is WeaponData, "hammer is a weapon tagged hammer")
	check_eq(_d(&"hammer").category_id(), &"weapon", "category_id")
	var seen_categories := {}
	for id in ids:
		var d := _d(id)
		check(d.category >= 0 and d.category < ItemData.CATEGORY_IDS.size(), "%s category valid" % id)
		seen_categories[d.category] = true
		check(d.display_name != "", "%s has a name" % id)
		check(d.weight >= 0.0, "%s weight" % id)
		check(not (d.has_condition() and d.max_stack > 1), "%s: condition items do not stack" % id)
		if not d.has_tag(&"internal"):
			check(d.description != "", "%s has a description" % id)
	check_eq(seen_categories.size(), ItemData.CATEGORY_IDS.size(), "every category has an item")
	check_eq(ItemDB.ids_in_category(ItemData.Category.MEDICAL).size(), 5, "5 medical items")
	var inst := ItemDB.instance(&"nails", 30)
	check(inst != null and inst.stack == 30 and inst.data.id == &"nails", "instance()")
	# Unique-id validation (pure helper used alongside the push_error at load).
	var a := ItemData.new()
	a.id = &"x"
	var b := ItemData.new()
	b.id = &"x"
	var c := ItemData.new()
	c.id = &"y"
	check_eq(ItemDB.find_duplicate_ids([a, b, c]), PackedStringArray(["x"]), "duplicate detection")
	check(ItemDB.find_duplicate_ids(ids.map(func(i): return _d(i))).is_empty(), "catalogue ids unique")


func test_add_stacking_and_weight() -> void:
	var inv := ItemContainer.new(10.0)
	var n := [0]
	inv.changed.connect(func(): n[0] += 1)
	check(inv.add_new(_d(&"nails"), 60).ok, "60 nails")
	check(inv.add_new(_d(&"nails"), 60).ok, "60 more")
	check_eq(inv.count_of(&"nails"), 120, "count")
	check_eq(inv.items.size(), 2, "two stacks (max 100)")
	check_eq(inv.items[0].stack, 100, "first stack full")
	check_near(inv.total_weight(), 1.2, 0.0001, "weight 120 × 0.01")
	check_eq(n[0], 2, "one changed per add")
	# Non-stackables: one instance per item.
	check(inv.add_new(_d(&"tin_opener"), 3).ok, "3 tin openers (max_stack 1)")
	check_eq(inv.find_all(&"tin_opener").size(), 3, "3 instances")
	check_eq(inv.count_of(&"tin_opener"), 3, "count 3")
	# Condition items never stack.
	inv.add_new(_d(&"kitchen_knife"), 1)
	inv.add_new(_d(&"kitchen_knife"), 1)
	check_eq(inv.find_all(&"kitchen_knife").size(), 2, "knives separate")
	var g := inv.grouped()
	check_eq(g.size(), 3, "grouped rows: nails, tin opener, knife")
	check_eq(int(g[0].count), 120, "row count")
	check_near(float(g[1].weight), 0.6, 0.0001, "row weight")


func test_capacity_refusal() -> void:
	var inv := ItemContainer.new(5.0)
	check(inv.add_new(_d(&"plank"), 1).ok, "3 kg")
	var r := inv.add_new(_d(&"plank"), 1)
	check(not r.ok and r.reason == "Too heavy", "second plank refused (%s)" % str(r))
	check_eq(inv.count_of(&"plank"), 1, "unchanged")
	check(inv.can_add(_d(&"water_bottle"), 2).ok, "2 × 1 kg fits exactly")
	check(not inv.can_add(_d(&"water_bottle"), 3).ok, "3 do not")
	check_eq(inv.fit_count(_d(&"nails"), 500), 200, "200 nails fit in 2 kg")
	var unlimited := ItemContainer.new()
	check(unlimited.add_new(_d(&"plank"), 50).ok, "unlimited capacity")


func test_remove_and_find() -> void:
	var inv := ItemContainer.new()
	inv.add_new(_d(&"bandage"), 4)
	var b := inv.find(&"bandage")
	var got := inv.remove(b, 1)
	check(got != null and got.stack == 1 and got != b, "split one off")
	check_eq(inv.count_of(&"bandage"), 3, "3 left")
	check_eq(inv.remove_id(&"bandage", 5), 3, "removes what is there")
	check(inv.is_empty(), "empty")
	check(inv.remove(b) == null, "gone")
	inv.add_new(_d(&"rag"), 2)
	var dressing := inv.find_where(func(it): return it.data is MedicalData and it.data.bandage_quality > 0.0)
	check(dressing != null and dressing.id() == &"rag", "find_where")


func test_transfer_partial_and_all() -> void:
	var box := ItemContainer.new(50.0)
	var bag := ItemContainer.new(4.0)
	box.add_new(_d(&"water_bottle"), 3)
	box.add_new(_d(&"nails"), 50)
	box.add_new(_d(&"plank"), 1)
	var w := box.find(&"water_bottle")
	var r := box.transfer_to(bag, w, 1)
	check(r.ok and r.moved == 1, "one bottle moved (%s)" % str(r))
	check_eq(bag.count_of(&"water_bottle"), 1, "bag +1")
	check_eq(box.count_of(&"water_bottle"), 2, "box -1")
	var nails := box.find(&"nails")
	r = box.transfer_to(bag, nails, 10)
	check(r.ok and r.moved == 10, "10 nails")
	check_eq(box.count_of(&"nails"), 40, "40 left")
	# Plank (3 kg) does not fit in the 2.9 kg left.
	r = box.transfer_to(bag, box.find(&"plank"))
	check(not r.ok and r.reason == "Too heavy", "plank refused")
	# Transfer all: moves what fits, reports the rest.
	var all := box.transfer_all(bag)
	check(all.ok and all.get("reason", "") == "Too heavy", "partial loot all (%s)" % str(all))
	check_lt(bag.total_weight(), 4.0 + 0.0001, "never over capacity")
	check(box.count_of(&"plank") == 1, "plank stays")
	check_eq(bag.count_of(&"nails"), 50, "all nails merged in the bag")
	check_eq(bag.find_all(&"nails").size(), 1, "one nail stack")
	# transfer_id
	var a := ItemContainer.new()
	var b2 := ItemContainer.new(1.0)
	a.add_new(_d(&"apple"), 8)
	r = a.transfer_id(b2, &"apple")
	check(r.ok and r.moved == 5 and r.partial, "5 apples fit in 1 kg (%s)" % str(r))


func test_to_dict_roundtrip() -> void:
	var inv := ItemContainer.new(12.0)
	inv.add_new(_d(&"nails"), 130)
	inv.add_new(_d(&"baseball_bat"), 1, 7)
	inv.add_new(_d(&"soda"), 2)
	var d := inv.to_dict()
	var back := ItemContainer.new()
	back.from_dict(JSON.parse_string(JSON.stringify(d)))
	check_near(back.capacity, 12.0, 0.001, "capacity")
	check_eq(back.count_of(&"nails"), 130, "nails")
	check_eq(back.count_of(&"soda"), 2, "soda")
	check_eq(back.find(&"baseball_bat").condition, 7, "condition kept")
	check_near(back.total_weight(), inv.total_weight(), 0.0001, "same weight")


func test_can_fit_and_split_stack() -> void:
	var inv := ItemContainer.new(1.0)
	check(inv.can_fit(_d(&"nails"), 100), "100 nails = 1 kg fit")
	check(not inv.can_fit(_d(&"nails"), 101), "101 do not")
	inv.add_new(_d(&"nails"), 40)
	var s := inv.find(&"nails")
	var part := inv.split_stack(s, 15)
	check(part != null and part.stack == 15 and s.stack == 25, "split 15 off 40")
	check_eq(inv.items.size(), 2, "two stacks")
	check_eq(inv.index_of(part), inv.index_of(s) + 1, "new stack right after")
	check_eq(inv.count_of(&"nails"), 40, "count unchanged")
	check(inv.split_stack(s, 25) == null, "cannot split the whole stack")
	check(inv.split_stack(s, 0) == null, "nor zero")
	# Re-adding merges back into existing stacks.
	var moved := inv.remove(part)
	check(inv.add(moved).ok and inv.items.size() == 1 and inv.items[0].stack == 40, "merges back")
	check(inv.add_id(&"rag", 2).ok and inv.count_of(&"rag") == 2, "add_id via ItemDB")


func test_remove_zero_and_ownership() -> void:
	var a := ItemContainer.new()
	var b := ItemContainer.new()
	a.add_id(&"nails", 10)
	var n := a.find(&"nails")
	check(a.remove(n, 0) == null, "remove(item, 0) removes nothing")
	check_eq(a.count_of(&"nails"), 10, "still 10")
	check(n.owner_container() == a, "owner back-ref set on add")
	var r := b.add(n)
	check(not r.ok and r.reason == "Already in another container", "double add refused (%s)" % str(r))
	check(b.is_empty() and a.has(n), "nothing duplicated")
	check(not a.add(n).ok, "re-adding to the same container refused")
	var one := a.remove(n, 3)
	check(one.owner_container() == null and n.owner_container() == a, "split-off part is free, rest still owned")
	check(b.add(one).ok and one.owner_container() == b, "free part can be added elsewhere")
	var whole := a.remove(n)
	check(whole == n and n.owner_container() == null, "whole-stack removal frees it")
	check(a.transfer_to(b, n).reason == "Not here", "no longer in a")
	# Merged instances are spent (stack 0) and cannot be re-added.
	check(b.add(n).ok, "merge the 7 into b's stack")
	check_eq(b.count_of(&"nails"), 10, "10 in b")
	check_eq(n.stack, 0, "merged instance spent")
	check(not ItemContainer.new().add(n).ok, "spent instance refused")
	# split_stack owner.
	var s := b.split_stack(b.find(&"nails"), 4)
	check(s.owner_container() == b, "split_stack part owned by b")


func test_from_dict_skips_bad_counts_and_respects_capacity() -> void:
	var inv := ItemContainer.new(2.0)
	inv.from_dict({"items": [
		{"id": "nails", "count": 0},
		{"id": "apple", "count": -2},
		{"id": "water_bottle", "count": 3},
		{"id": "rag", "count": 2},
	]})
	check_eq(inv.count_of(&"nails") + inv.count_of(&"apple"), 0, "count <= 0 skipped")
	check_eq(inv.count_of(&"water_bottle"), 2, "only what fits (2 × 1 kg)")
	check_eq(inv.count_of(&"rag"), 0, "nothing past capacity")
	check_lt(inv.total_weight(), 2.0 + 0.0001, "never over capacity")
	for it in inv.items:
		check(it.owner_container() == inv, "loaded items owned")
