extends "res://tests/test_case.gd"
## Round 6 (pure-ish): encumbrance math, equipment slot rules, nested bag
## cycle prevention, save round trips, drain / noise multipliers, item
## actions.


class FakeOwner:
	extends Node
	var inventory := ItemContainer.new(20.0)


var owner_node: Node
var eq: Equipment


func setup() -> void:
	owner_node = FakeOwner.new()
	eq = Equipment.new()
	eq.name = "Equipment"
	owner_node.add_child(eq)
	tree.root.add_child(owner_node)


func teardown() -> void:
	owner_node.free()


func _d(id: StringName) -> ItemData:
	return ItemDB.get_item(id)


func _inst(id: StringName, n: int = 1) -> ItemInstance:
	return ItemInstance.new(_d(id), -1, n)


func _main() -> ItemContainer:
	return owner_node.inventory


# --- Encumbrance math ------------------------------------------------------------

func test_encumbrance_thresholds_and_effects() -> void:
	var st := func(w: float) -> StringName: return Encumbrance.state_for(w, 8.0, 12.0, 15.0)
	check_eq(st.call(0.0), &"ok", "empty")
	check_eq(st.call(8.0), &"ok", "exactly capacity is ok")
	check_eq(st.call(8.01), &"light", "just over capacity")
	check_eq(st.call(12.0), &"light", "12 still light")
	check_eq(st.call(12.4), &"heavy", "12.4 heavy")
	check_eq(st.call(15.0), &"heavy", "15 heavy")
	check_eq(st.call(15.1), &"overloaded", "over 15 overloaded")
	var p := CharacterStatsProfile.new()
	var ok := Encumbrance.effects_for(&"ok", p)
	check(ok.speed == 1.0 and ok.drain == 1.0 and ok.noise == 1.0 and ok.sprint, "ok: no effect")
	var light := Encumbrance.effects_for(&"light", p)
	check(is_equal_approx(light.speed, 0.92) and is_equal_approx(light.drain, 1.15) and light.sprint, "light matters: ×0.92 speed, +15 % drain, can sprint")
	var heavy := Encumbrance.effects_for(&"heavy", p)
	check_near(heavy.speed, 0.85, 0.0001, "heavy speed")
	check_near(heavy.drain, 1.3, 0.0001, "heavy +30 % drain")
	check_near(heavy.noise, 1.2, 0.0001, "heavy footsteps ×1.2")
	check(heavy.sprint, "heavy can still sprint")
	var over := Encumbrance.effects_for(&"overloaded", p)
	check_near(over.speed, 0.65, 0.0001, "overloaded speed")
	check_near(over.drain, 1.7, 0.0001, "overloaded +70 % drain")
	check(not over.sprint, "overloaded: no sprint")
	check_eq(Encumbrance.state_label(&"overloaded"), "Overloaded", "label")


func test_carried_weight_with_worn_bag_reduction() -> void:
	var bag := _inst(&"backpack")
	check(bag.is_bag() and bag.contents.capacity == 7.0, "a school bag instance owns a 7 kg container")
	check(bag.contents.add(_inst(&"plank", 2)).ok, "6 kg in")  # 6 kg
	check(not bag.contents.add(_inst(&"plank", 1)).ok, "a third plank does not fit 7 kg")
	check_near(bag.unit_weight(), 0.7 + 6.0, 0.0001, "unworn bag weighs everything")
	check_near(Encumbrance.worn_bag_weight(bag), 0.7 + 6.0 * 0.7, 0.0001, "worn: contents × (1 − 0.3)")
	var main := ItemContainer.new(20.0)
	main.add(_inst(&"water_bottle", 2))
	var bat := _inst(&"baseball_bat")
	var w := Encumbrance.carried_weight(main, [bat], [bag])
	check_near(w, main.total_weight() + 1.5 + 0.7 + 4.2, 0.0001, "main + hands + reduced bag")
	# The same bag in the main inventory counts in full.
	var main2 := ItemContainer.new(20.0)
	main2.add(bag)
	check_near(Encumbrance.carried_weight(main2, [], []), 6.7, 0.0001, "bag in the pack counts in full")
	check_near(main2.total_weight(), 6.7, 0.0001, "container weight includes nested contents")
	var duffel := _inst(&"duffel_bag")
	check(is_equal_approx(duffel.data.weight, 1.8) and is_equal_approx((duffel.data as ContainerItemData).weight_reduction, 0.4) \
		and is_equal_approx((duffel.data as ContainerItemData).worn_speed_multiplier, 0.97), "duffel: heavier, 40 % lighter contents, ×0.97 speed")


func test_capacity_checks_use_bag_contents() -> void:
	var bag := _inst(&"backpack")
	bag.contents.add(_inst(&"plank", 2))  # 6.7 kg total
	var small := ItemContainer.new(6.0)
	var r := small.add(bag)
	check(not r.ok and r.reason == "Too heavy", "a full bag does not fit where its empty weight would")
	check_eq(small.fit_item(bag), 0, "fit_item sees the contents")
	var big := ItemContainer.new(7.0)
	check(big.add(bag).ok, "fits a 7 kg container")


func test_stats_drain_multiplier_only_scales_drains() -> void:
	var sc := StatsComponent.new()
	sc.character = null
	sc.add_stat(&"stamina", 100.0, {&"jog": -2.0, &"idle": 4.0})
	sc.set_value(&"stamina", 50.0)
	sc.set_drain_multiplier(&"stamina", &"encumbrance", 1.7)
	sc.tick(1.0, &"jog")
	check_near(sc.get_value(&"stamina"), 50.0 - 3.4, 0.0001, "drain ×1.7")
	sc.tick(1.0, &"idle")
	check_near(sc.get_value(&"stamina"), 46.6 + 4.0, 0.0001, "regen untouched")
	sc.set_drain_multiplier(&"stamina", &"encumbrance", 1.0)
	check_near(sc.drain_multiplier(&"stamina"), 1.0, 0.0001, "cleared")
	sc.free()


func test_footstep_radius_multiplier() -> void:
	var f := FootstepEmitter.new()
	check_near(f.radius_for(MovementComponent.Mode.JOG), 8.0, 0.001, "jog 8 m")
	f.set_multiplier(&"encumbrance", 1.2)
	check_near(f.radius_for(MovementComponent.Mode.JOG), 9.6, 0.001, "heavy ×1.2")
	f.set_multiplier(&"encumbrance", 1.0)
	check_near(f.radius_for(MovementComponent.Mode.SNEAK), 2.0, 0.001, "cleared")
	f.free()


# --- Slot rules -------------------------------------------------------------------

func test_two_handed_occupies_both_hands() -> void:
	var bat := _inst(&"baseball_bat")
	var knife := _inst(&"kitchen_knife")
	var hammer := _inst(&"hammer")
	_main().add(bat)
	_main().add(knife)
	_main().add(hammer)
	check(eq.equip(knife, Equipment.SECONDARY).ok, "knife in the off hand")
	check(eq.equip(hammer).ok, "hammer in the main hand")
	check(eq.primary() == hammer and eq.secondary() == knife, "two one-handers")
	var r := eq.equip(bat)
	check(r.ok, "bat equipped (%s)" % str(r))
	check(eq.primary() == bat and eq.secondary() == bat, "two-handed: both hands")
	check(_main().has(hammer) and _main().has(knife), "both one-handers went back to the pack")
	check(not _main().has(bat), "the bat left the pack")
	check_eq(eq.hand_items().size(), 1, "one item in the hands")
	# A one-hander in the off hand displaces the two-hander.
	check(eq.equip(knife, Equipment.SECONDARY).ok, "knife to the off hand")
	check(eq.primary() == null and eq.secondary() == knife, "bat put away")
	check(_main().has(bat), "bat back in the pack")
	# Asking for the secondary hand with a two-hander means both hands.
	check(eq.equip(bat, Equipment.SECONDARY).ok and eq.primary() == bat and eq.secondary() == bat, "two-hander always primary")


func test_bags_only_on_back_and_hand_rules() -> void:
	var bag := _inst(&"backpack")
	_main().add(bag)
	var r := eq.equip(bag, Equipment.PRIMARY)
	check(not r.ok and r.reason == "Bags go on the back", "no bag in the hand (%s)" % str(r))
	r = eq.equip(_inst(&"hammer"), Equipment.BACK)
	check(not r.ok and r.reason == "Only bags go on the back", "only bags on the back")
	var apple := _inst(&"apple")
	_main().add(apple)
	r = eq.equip(apple)
	check(not r.ok and r.reason == "Can't hold that", "food is not held")
	check(eq.equip(bag).ok and eq.back_bag() == bag, "default slot of a bag is the back")
	check(eq.storage().size() == 2 and eq.storage()[1] == bag.contents, "worn bag is carried storage")
	check(eq.owns_container(bag.contents) and eq.owns_container(eq.slots[Equipment.BACK]), "owns bag + slot")
	# Stacks: one item is taken.
	var driver := _inst(&"screwdriver")
	_main().add(driver)
	check(eq.equip(driver).ok, "tool in hand")
	var foreign := _inst(&"hammer")
	var other := ItemContainer.new()
	other.add(foreign)
	check_eq(eq.equip(foreign).get("reason", ""), "Not carried", "can't equip from someone else's container")


func test_unequip_goes_to_inventory_or_refused() -> void:
	var bat := _inst(&"baseball_bat")
	_main().add(bat)
	check(eq.equip(bat).ok, "equipped")
	_main().add(_inst(&"plank", 6))
	_main().add(_inst(&"nails", 200))  # 20 kg: full
	var r := eq.unequip(bat)
	check(not r.ok and r.reason == "No room in inventory", "refused when full (%s)" % str(r))
	check(eq.primary() == bat, "still in hand")
	# Swapping a weapon in is refused too when the old one has nowhere to go.
	var knife := _inst(&"kitchen_knife")
	check_eq(eq.equip(knife).get("reason", ""), "No room in inventory", "swap refused (displaced bat does not fit)")
	check(knife.owner_container() == null and eq.primary() == bat, "nothing changed")
	# A worn bag with room takes it.
	var bag := _inst(&"backpack")
	check(eq.equip(bag).ok, "bag straight onto the back")
	r = eq.unequip(Equipment.PRIMARY)
	check(r.ok and bag.contents.has(bat), "unequip falls back to the worn bag (%s)" % str(r))


func test_equip_swap_frees_room_from_the_source() -> void:
	# The pack is full, but the new weapon leaves it: the old one fits.
	var bat := _inst(&"baseball_bat")
	var crowbar := _inst(&"crowbar")
	_main().add(bat)
	check(eq.equip(bat).ok, "bat")
	_main().add(crowbar)
	var fill := 20.0 - _main().total_weight()
	_main().add(_inst(&"nails", int(floor(fill / 0.01))))
	check_lt(_main().free_weight(), 0.02, "pack full (%.3f free)" % _main().free_weight())
	var r := eq.equip(crowbar)
	check(r.ok, "swap works: the crowbar's weight leaves the pack first (%s)" % str(r))
	check(eq.primary() == crowbar and _main().has(bat), "bat in the pack")


# --- Nested containers ---------------------------------------------------------------

func test_bags_cannot_contain_themselves() -> void:
	var a := _inst(&"backpack")
	var b := _inst(&"duffel_bag")
	var r := a.contents.add(a)
	check(not r.ok and r.reason == ItemContainer.REASON_CYCLE, "a bag in itself (%s)" % str(r))
	check(a.contents.add(b).ok, "duffel inside the backpack")
	r = b.contents.add(a)
	check(not r.ok and r.reason == ItemContainer.REASON_CYCLE, "a bag inside a bag it contains")
	var c := _inst(&"backpack")
	check(b.contents.add(c).ok, "third level")
	check_eq(c.contents.accept_reason(a), ItemContainer.REASON_CYCLE, "any depth")
	var holder := ItemContainer.new()
	check(a.contents.transfer_to(holder, b).ok, "move the duffel out")
	var t := holder.transfer_to(b.contents, b)
	check(not t.ok and t.reason == ItemContainer.REASON_CYCLE, "transfer_to refuses the cycle too")
	check(holder.has(b), "…and moves nothing")


func test_worn_bag_never_goes_into_another_bag() -> void:
	var worn := _inst(&"backpack")
	check(eq.equip(worn).ok, "worn")
	var ground := _inst(&"duffel_bag")
	var r: Dictionary = eq.slots[Equipment.BACK].transfer_to(ground.contents, worn)
	check(not r.ok and r.reason == ItemContainer.REASON_WORN_BAG, "worn bag into another bag (%s)" % str(r))
	r = eq.slots[Equipment.BACK].transfer_to(worn.contents, worn)
	check(not r.ok and r.reason == ItemContainer.REASON_CYCLE, "worn bag into its own contents")
	check(eq.back_bag() == worn, "still worn")
	check(eq.unequip(worn).ok and _main().has(worn), "taking it off puts it in the pack")


# --- Save ------------------------------------------------------------------------------

func test_equipment_and_nested_bags_round_trip() -> void:
	var bag := _inst(&"backpack")
	var inner := _inst(&"duffel_bag")
	inner.contents.add(_inst(&"nails", 42))
	bag.contents.add(inner)
	bag.contents.add(_inst(&"bandage", 2))
	check(eq.equip(bag).ok, "bag worn")
	var bat := ItemInstance.new(_d(&"baseball_bat"), 7)
	_main().add(bat)
	check(eq.equip(bat).ok, "bat in hand")
	var knife := _inst(&"kitchen_knife")
	_main().add(knife)
	_main().add(_inst(&"apple", 3))
	var hammer := _inst(&"hammer")
	bag.contents.add(hammer)
	check(eq.assign_hotbar(0, bat).ok and eq.assign_hotbar(1, knife).ok and eq.assign_hotbar(2, hammer).ok, "hotbar assigned")
	var saved := {"inventory": _main().to_dict(), "equipment": eq.to_dict()}
	var json: Dictionary = JSON.parse_string(JSON.stringify(saved))
	# Fresh owner.
	var o2 := FakeOwner.new()
	var eq2 := Equipment.new()
	eq2.name = "Equipment"
	o2.add_child(eq2)
	tree.root.add_child(o2)
	o2.inventory.from_dict(json.inventory)
	eq2.from_dict(json.equipment)
	var bag2 := eq2.back_bag()
	check(bag2 != null and bag2.id() == &"backpack", "bag restored on the back")
	check_eq(bag2.contents.count_of(&"bandage"), 2, "bag contents")
	var inner2 := bag2.contents.find(&"duffel_bag")
	check(inner2 != null and inner2.contents.count_of(&"nails") == 42, "nested bag contents")
	check(eq2.primary() != null and eq2.primary().id() == &"baseball_bat" and eq2.primary().condition == 7, "bat + condition in hand")
	check(eq2.secondary() == eq2.primary(), "two-hander restored in both hands")
	check_eq(o2.inventory.count_of(&"apple"), 3, "main inventory")
	check(eq2.hotbar_item(0) == eq2.primary(), "hotbar 1 → the equipped bat")
	check(eq2.hotbar_item(1) != null and eq2.hotbar_item(1).id() == &"kitchen_knife" and o2.inventory.has(eq2.hotbar_item(1)), "hotbar 2 → knife in the pack")
	check(eq2.hotbar_item(2) != null and eq2.hotbar_item(2).id() == &"hammer" and bag2.contents.has(eq2.hotbar_item(2)), "hotbar 3 → hammer in the bag")
	check_near(Encumbrance.carried_weight(o2.inventory, eq2.hand_items(), [bag2]),
		Encumbrance.carried_weight(_main(), eq.hand_items(), [bag]), 0.0001, "same carried weight")
	o2.free()


# --- Hotbar ---------------------------------------------------------------------------

func test_hotbar_assign_use_and_prune() -> void:
	var knife := _inst(&"kitchen_knife")
	_main().add(knife)
	check(not eq.assign_hotbar(0, _inst(&"hammer")).ok, "not carried → refused")
	var nails := _inst(&"nails")
	_main().add(nails)
	check_eq(eq.assign_hotbar(0, nails).get("reason", ""), "Can't hold that", "materials not on the hotbar")
	var apple := _inst(&"apple")
	_main().add(apple)
	check(eq.assign_hotbar(0, apple).ok, "food / drink can go on the hotbar (R7)")
	eq.assign_hotbar(0, null)
	check(eq.assign_hotbar(0, knife).ok, "assigned")
	check(eq.assign_hotbar(2, knife).ok and eq.hotbar_item(0) == null and eq.hotbar_item(2) == knife, "one slot per item")
	check(eq.use_hotbar(2).ok and eq.primary() == knife, "key 3 equips")
	var s: Array = eq.hotbar_summary()
	check(bool(s[2].equipped) and s[2].name == "Kitchen Knife", "summary")
	check(eq.use_hotbar(2).ok and eq.primary() == null and _main().has(knife), "again: put away")
	check_eq(eq.use_hotbar(0).get("reason", ""), "Hotbar slot 1 is empty", "empty slot")
	var gone := _main().remove(knife)
	check(eq.hotbar_item(2) == null, "a dropped item is not usable from the hotbar")
	check_eq(eq.use_hotbar(2).get("reason", ""), "Not carried", "key refused while not carried")
	check(not bool(eq.hotbar_summary()[2].carried), "summary greys it")
	_main().add(gone)
	check(eq.hotbar_item(2) == knife, "picked back up: same slot again")


# --- Item actions -----------------------------------------------------------------------

func test_item_actions_lists() -> void:
	var fake := Node.new()  # no equipment → no equip / hotbar entries
	var rag := _inst(&"rag")
	var acts := ItemActions.for_item(fake, rag)
	var ids := acts.map(func(a): return a.id)
	check(ids.has(ItemActions.USE) and ids.has(ItemActions.DROP), "rag: use + drop (%s)" % str(ids))
	var beans := _inst(&"canned_beans", 3)
	acts = ItemActions.for_item(fake, beans)
	check(not acts.any(func(a): return a.id == ItemActions.USE or a.id == ItemActions.CONSUME),
			"no eat entry without a ConsumeAction on the actor (R7)")
	check(acts.any(func(a): return a.id == ItemActions.SPLIT), "stack → split")
	check(acts.any(func(a): return a.id == ItemActions.DROP_ONE), "stack → drop one")
	fake.free()


# --- Round 6 critic regressions ---------------------------------------------------------

func test_nested_bag_changes_propagate_and_weights_stay_right() -> void:
	var main := ItemContainer.new(-1.0)
	var outer := _inst(&"duffel_bag")
	var inner := _inst(&"backpack")
	check(outer.contents.add(inner).ok and main.add(outer).ok, "bag in a bag in the pack")
	var n := [0]
	main.changed.connect(func(): n[0] += 1)
	var w0 := main.total_weight()
	check(inner.contents.add(_inst(&"plank", 1)).ok, "3 kg into the inner bag (API)")
	check_eq(n[0], 1, "the pack heard about it (recursive)")
	check_near(main.total_weight(), w0 + 3.0, 0.0001, "cached weight invalidated through two levels")
	inner.contents.remove_id(&"plank", 1)
	check_near(main.total_weight(), w0, 0.0001, "and back")
	# Removing the bag stops the propagation.
	var out := main.remove(outer)
	n[0] = 0
	inner.contents.add(_inst(&"apple", 1))
	check_eq(n[0], 0, "no longer connected once removed")
	check_near(main.total_weight(), 0.0, 0.0001, "empty")
	check(out == outer, "removed")


func test_batch_emits_one_changed_and_cache_matches() -> void:
	var a := ItemContainer.new(-1.0)
	var b := ItemContainer.new(-1.0)
	for i in 50:
		a.add(_inst(&"hammer"))
	a.add(_inst(&"nails", 250))
	var na := [0]
	var nb := [0]
	a.changed.connect(func(): na[0] += 1)
	b.changed.connect(func(): nb[0] += 1)
	var r := a.transfer_all(b)
	check(r.ok and a.is_empty(), "moved everything")
	check(na[0] == 1 and nb[0] == 1, "one changed per side (%d / %d)" % [na[0], nb[0]])
	var sum := 0.0
	for it in b.items:
		sum += it.total_weight()
	check_near(b.total_weight(), sum, 0.0001, "incremental cache = recomputed sum")
	check_near(b.total_weight(), 52.5, 0.0001, "50 hammers + 250 nails")


func test_save_uses_count_and_reads_legacy_stack() -> void:
	var it := _inst(&"nails", 7)
	var d := it.to_dict()
	check(d.has("count") and not d.has("stack") and int(d.count) == 7, "ItemInstance writes count (%s)" % str(d))
	var legacy := ItemInstance.from_dict({"id": "nails", "stack": 9})
	check(legacy != null and legacy.stack == 9, "old 'stack' key still read")
	var c := ItemContainer.new()
	c.add(it)
	var e: Dictionary = c.to_dict().items[0]
	check(e.has("count") and not e.has("stack"), "ItemContainer entries use count too")


func test_equipment_from_dict_applies_slot_rules() -> void:
	var bat := _inst(&"baseball_bat").to_dict()
	var knife := _inst(&"kitchen_knife").to_dict()
	var bag := _inst(&"backpack").to_dict()
	eq.from_dict({"slots": {"primary_hand": bat, "secondary_hand": knife}})
	check(eq.primary() != null and eq.primary().id() == &"baseball_bat", "two-hander loaded")
	check(eq.secondary() == eq.primary() and eq.item_in(Equipment.SECONDARY) == null, "knife rejected next to a two-hander")
	eq.from_dict({"slots": {"secondary_hand": bat}})
	check(eq.item_in(Equipment.SECONDARY) == null and eq.primary() == null, "two-hander never in the secondary hand")
	eq.from_dict({"slots": {"primary_hand": bag, "back": knife}})
	check(eq.primary() == null and eq.back_bag() == null, "bag in hand / knife on back rejected")
	eq.from_dict({"slots": {"back": bag, "primary_hand": knife}})
	check(eq.back_bag() != null and eq.primary() != null and eq.primary().id() == &"kitchen_knife", "valid combo loads")


func test_hotbar_class() -> void:
	var h := Hotbar.new()
	var a := _inst(&"hammer")
	var n := [0]
	h.changed.connect(func(): n[0] += 1)
	check(h.assign(1, a) and h.item_at(1) == a and h.index_of(a) == 1, "assign")
	check(h.assign(0, a) and h.item_at(1) == null and h.index_of(a) == 0, "one slot per item")
	check(not h.assign(3, a), "bounds")
	h.clear()
	check(h.item_at(0) == null and n[0] == 3, "clear + signals")
