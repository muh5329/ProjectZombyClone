extends "res://tests/test_case.gd"
## Round 9 pure rules: BarricadeData, BarricadeComponent plank rules and
## damage, material consumption through the barricade action, carpentry
## XP / levels (SkillComponent), furniture disassemble yields.

const WindowScript = preload("res://interaction/window.gd")
const HUDScript = preload("res://ui/hud/hud.gd")

var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


## A bare actor: Node3D with an unlimited `inventory` (no begin_busy →
## timed work completes at once).
func _actor(items: Dictionary = {}) -> Node3D:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar inventory := ItemContainer.new(-1.0)\n"
	s.reload()
	var a := Node3D.new()
	a.set_script(s)
	tree.root.add_child(a)
	_nodes.append(a)
	for id in items:
		a.get("inventory").add_id(StringName(id), int(items[id]))
	return a


func _window() -> HouseWindow:
	var w: HouseWindow = WindowScript.new()
	tree.root.add_child(w)
	_nodes.append(w)
	return w


func test_barricade_data_loads_with_brief_numbers() -> void:
	var d := BarricadeComponent.default_data()
	check(d != null, "wood_planks.tres loads")
	check_eq(d.validate().size(), 0, "valid: %s" % [d.validate()])
	check_eq(d.material, BarricadeData.MATERIAL_WOOD, "wood planks")
	check_eq(d.plank_health, 60.0, "plank health 60")
	check_eq(d.max_planks_for(&"window"), 4, "4 per window")
	check_eq(d.max_planks_for(&"door"), 4, "4 per door")
	check_eq(d.build_tool_tags, [&"hammer"] as Array[StringName], "hammer")
	check_eq(d.material_item, &"plank", "plank item")
	check_eq(d.nails_per_plank, 2, "2 nails")
	check_eq(d.build_seconds, 3.0, "3 s")
	check_eq(d.build_noise, &"hammering", "hammering")
	check_eq(d.max_attackers, 3, "3 attackers per opening")
	check(ItemDB.has_item(d.material_item) and ItemDB.has_item(d.nails_item), "items exist")
	var table: SoundCategoryTable = load("res://data/audio/sound_categories.tres")
	check_eq(table.get_category(&"hammering").radius, 18.0, "hammering 18 m")
	check_eq(table.get_category(&"wood_break").radius, 10.0, "wood_break 10 m")
	check(table.has_category(&"barricade_bang") and table.has_category(&"furniture_scrape"), "bang / scrape")


func test_missing_reason_order() -> void:
	var d := BarricadeComponent.default_data()
	check_eq(d.missing_reason(0, 4, true, 1, 2), "", "all there")
	check_eq(d.missing_reason(4, 4, true, 1, 2), "Fully barricaded", "full first")
	check_eq(d.missing_reason(0, 4, false, 1, 2), "Need a hammer", "tool")
	check_eq(d.missing_reason(0, 4, true, 0, 2), "Need planks", "planks")
	check_eq(d.missing_reason(0, 4, true, 1, 1), "Need 2 nails", "nails")
	check_eq(d.missing_reason(0, 4, false, 0, 0), "Need a hammer", "tool before materials")
	check(BarricadeData.can_add(3, 4) and not BarricadeData.can_add(4, 4), "can_add")


func test_remove_yield_sound_vision_and_skill_scaling() -> void:
	var d := BarricadeComponent.default_data()
	var crowbar := d.remove_spec([&"tool", &"crowbar"])
	var hammer := d.remove_spec([&"tool", &"hammer"])
	check_eq(float(crowbar.seconds), 2.0, "crowbar 2 s")
	check_lt(float(crowbar.seconds), float(hammer.seconds), "crowbar faster than hammer")
	check_eq(d.remove_spec([&"blade"]), {}, "a knife cannot pry")
	check_eq(d.remove_yield(crowbar, 0.69, 0.49), {"plank": 1, "nails": 2}, "under both chances → both back")
	check_eq(d.remove_yield(crowbar, 0.71, 0.51), {"plank": 0, "nails": 0}, "over → nothing")
	check_eq(d.remove_yield(hammer, 0.6, 0.1), {"plank": 0, "nails": 2}, "hammer: 50 % plank")
	check_near(d.sound_factor(0), 1.0, 0.0001, "no planks: ×1")
	check_near(d.sound_factor(2), 0.64, 0.0001, "two planks ×0.8²")
	check(not d.vision_blocked(1) and d.vision_blocked(2), "vision blocked from 2 planks")
	check_near(d.build_seconds_for(SkillComponent.carpentry_time_multiplier(0)), 3.0, 0.001, "3 s at level 0")
	check_near(d.build_seconds_for(SkillComponent.carpentry_time_multiplier(4)), 2.4, 0.001, "−20 % at level 4")
	check_near(d.plank_health_for(SkillComponent.carpentry_health_multiplier(2)), 66.0, 0.001, "+10 % at level 2")
	check_gt(d.color_for(1.0).v, d.color_for(0.1).v, "damaged planks are darker")
	check_lt(EntryPlanner.score(5.0, 0, 8.0), EntryPlanner.score(0.0, 1, 8.0),
		"an open entry 5 m away beats one plank here")
	check_lt(EntryPlanner.score(3.0, 1, 8.0), EntryPlanner.score(0.0, 1, 8.0, false, false, true),
		"a crowded (slots full) opening is worse than the same one 3 m away")
	check_gt(EntryPlanner.score(0.0, 0, 8.0, false, true), EntryPlanner.score(0.0, 0, 8.0, true),
		"a closed door costs more than a closed window")
	check_near(EntryPlanner.window_link_cost(false, 2, 8.0), 17.0, 0.001, "open window + 2 planks")
	check_near(EntryPlanner.window_link_cost(true, 0, 8.0), 10.0, 0.001, "closed window")


func test_add_remove_plank_rules_and_sides() -> void:
	var w := _window()
	var b := BarricadeComponent.ensure(w)
	check_eq(b.kind, &"window", "window kind")
	check_eq(BarricadeComponent.ensure(w), b, "ensure reuses the component")
	check(not b.blocks_path(), "empty barricade does not block")
	check(b.add_plank(-1.0, -1.0).ok, "first plank")
	check_eq(b.side, -1.0, "first plank decides the side")
	var other := b.add_plank(-1.0, 1.0)
	check(not other.ok and other.reason == "Barricaded on the other side", "other side refused")
	for i in 3:
		check(b.add_plank(-1.0, -1.0).ok, "plank %d" % (i + 2))
	check_eq(b.plank_count(), 4, "4 planks")
	var full := b.add_plank(-1.0, -1.0)
	check(not full.ok and full.reason == "Fully barricaded", "5th refused")
	check(b.blocks_path() and w.is_barricaded(), "blocks")
	check(b.is_in_group(&"breakable"), "breakable group while planked")
	check_eq(b.board_count(), 4, "4 boards drawn")
	check_eq(w.breakable_target(), b, "zombies hit the planks")
	check(not w.can_climb(), "cannot climb")
	var climber := Node3D.new()
	check_eq(w.climb(climber).reason, "Barricaded", "climb refused Barricaded")
	climber.free()
	b.planks[3].health = 11.0
	var r := b.remove_plank()
	check(r.ok and is_equal_approx(float(r.plank.health), 11.0), "remove pops the outermost")
	check_eq(b.plank_count(), 3, "3 left")
	for i in 3:
		b.remove_plank()
	check(not b.remove_plank().ok, "nothing left to remove")
	check(not b.blocks_path() and not b.is_in_group(&"breakable"), "empty → not breakable")
	check_eq(w.breakable_target(), w, "back to the window itself")
	check_eq(b.board_count(), 0, "boards gone")


func test_damage_hits_the_outermost_plank_first() -> void:
	var w := _window()
	var b := BarricadeComponent.ensure(w)
	b.add_plank(60.0, 1.0)
	b.add_plank(50.0, 1.0)
	var r := b.take_damage(30.0)
	check(r.ok and not r.broken, "hit, no break")
	check_near(float(b.planks[1].health), 20.0, 0.001, "outer plank took it")
	check_near(float(b.planks[0].health), 60.0, 0.001, "inner untouched")
	check_lt(b.plank_fraction(1), 0.5, "outer below half")
	r = b.take_damage(45.0)
	check(r.broken, "outer breaks")
	check_eq(b.plank_count(), 1, "one left")
	check_near(float(b.planks[0].health), 60.0, 0.001, "overflow does not cascade to the next plank")
	check(not b.take_damage(0.0).ok, "zero damage no-op")
	b.take_damage(60.0)
	check_eq(b.plank_count(), 0, "all broken")
	check(not b.take_damage(10.0).ok, "nothing to hit")
	check_eq(w.state, &"closed", "window underneath still closed")


func test_nailing_consumes_materials_only_when_complete_and_gives_xp() -> void:
	var w := _window()
	var a := _actor({&"hammer": 1, &"plank": 2, &"nails": 3})
	var skills := SkillComponent.new()
	skills.name = "Skills"
	a.add_child(skills)
	var acts := BarricadeComponent.actions_for(w, a)
	check_eq(acts[0].id, &"barricade", "barricade action")
	check_eq(acts[0].label, "Barricade (0/4)", "label with count")
	check(acts[0].enabled, "enabled with hammer + plank + nails")
	var r := BarricadeComponent.perform(w, &"barricade", a)
	check(r.ok, "nailed (instant for a non-busy actor)")
	check_eq(BarricadeComponent.planks_on(w), 1, "one plank")
	var inv: ItemContainer = a.get("inventory")
	check_eq(inv.count_of(&"plank"), 1, "1 plank consumed")
	check_eq(inv.count_of(&"nails"), 1, "2 nails consumed")
	check_eq(inv.count_of(&"hammer"), 1, "hammer kept")
	check_near(skills.get_xp(SkillComponent.CARPENTRY), 10.0, 0.001, "+10 carpentry XP")
	acts = BarricadeComponent.actions_for(w, a)
	check_eq(acts[0].label, "Barricade (1/4)", "count shown")
	check(not acts[0].enabled and acts[0].reason == "Need 2 nails", "1 nail left → Need 2 nails")
	check_eq(acts[1].id, &"unbarricade", "remove listed")
	check(acts[1].enabled, "hammer can remove")
	check(not Interactable.is_default_candidate(Interactable.normalise_action(acts[1])), "remove is never the E action")
	var prompt := HUDScript.format_prompt("Window", [Interactable.normalise_action(acts[0]), Interactable.normalise_action(acts[1])])
	check(not prompt.contains("E: Remove"), "prompt: E not on Remove barricade (%s)" % prompt)
	check(prompt.contains("[5] Remove barricade"), "…its number key instead (%s)" % prompt)
	var none := _actor({&"plank": 1, &"nails": 2})
	var a2 := BarricadeComponent.actions_for(w, none)
	check(not a2[0].enabled and a2[0].reason == "Need a hammer", "no hammer")
	check(not a2[1].enabled and a2[1].reason == "Need a hammer or crowbar", "no pry tool")
	var refused := BarricadeComponent.perform(w, &"barricade", none)
	check(not refused.ok and refused.reason == "Need a hammer", "perform refused with the reason")
	check_eq((none.get("inventory") as ItemContainer).count_of(&"plank"), 1, "nothing consumed when refused")


func test_carried_items_helpers() -> void:
	var a := _actor({&"nails": 5, &"crowbar": 1})
	check_eq(CarriedItems.count(a, &"nails"), 5, "count")
	check(CarriedItems.find_tool(a, [&"hammer", &"crowbar"]) != null, "crowbar found by tag")
	check(CarriedItems.find_tool(a, [&"saw"]) == null, "no saw")
	check_eq(CarriedItems.consume(a, &"nails", 6), 0, "all-or-nothing")
	check_eq(CarriedItems.consume(a, &"nails", 2), 2, "consume 2")
	check_eq(CarriedItems.count(a, &"nails"), 3, "3 left")
	check_eq(CarriedItems.give(a, &"plank", 2).added, 2, "give planks")
	check_eq(CarriedItems.count(a, &"plank"), 2, "planks carried")


func test_skill_xp_levels_math() -> void:
	check_eq(SkillComponent.level_for_xp(0.0), 0, "0 xp → 0")
	check_eq(SkillComponent.level_for_xp(29.9), 0, "just under level 1")
	check_eq(SkillComponent.level_for_xp(30.0), 1, "30 → 1")
	check_eq(SkillComponent.level_for_xp(99999.0), 10, "capped at 10")
	check_eq(SkillComponent.xp_for_level(3), 150.0, "level 3 threshold")
	check_near(SkillComponent.carpentry_time_multiplier(10), 0.5, 0.001, "−50 % at 10")
	check_near(SkillComponent.carpentry_health_multiplier(10), 1.5, 0.001, "+50 % at 10")
	var s := SkillComponent.new()
	var ups := []
	s.leveled.connect(func(sk, lvl): ups.append([sk, lvl]))
	s.add_xp(SkillComponent.CARPENTRY, 20.0)
	check_eq(s.level(SkillComponent.CARPENTRY), 0, "20 xp: level 0")
	var r := s.add_xp(SkillComponent.CARPENTRY, 10.0)
	check(r.leveled_up and r.level == 1, "level up at 30")
	check_eq(ups, [[SkillComponent.CARPENTRY, 1]], "leveled signal once")
	check_near(s.carpentry_time(), 0.95, 0.001, "−5 % build time at 1")
	var d := s.to_dict()
	var s2 := SkillComponent.new()
	s2.from_dict(d)
	check_eq(s2.level(SkillComponent.CARPENTRY), 1, "round-trip")
	s2.from_dict({"xp": {"carpentry": -5.0}})
	check_eq(s2.get_xp(SkillComponent.CARPENTRY), 0.0, "negative xp ignored")
	s.free()
	s2.free()


func test_disassemble_yields() -> void:
	var spec := {"plank": [2, 3], "nails": [2, 5]}
	check_eq(FurnitureWork.yield_for(spec, [0.0, 0.0]), {&"plank": 2, &"nails": 2}, "low rolls → minimum")
	check_eq(FurnitureWork.yield_for(spec, [0.999, 0.999]), {&"plank": 3, &"nails": 5}, "high rolls → maximum")
	check_eq(FurnitureWork.yield_for(spec, [0.5, 0.5]), {&"plank": 3, &"nails": 4}, "middle")
	var cat: FurnitureCatalog = load("res://data/buildings/furniture_catalog.tres")
	for t in [&"shelf", &"dresser"]:
		var r := cat.resolve(t)
		check(bool(r.movable), "%s movable" % t)
		var dis: Dictionary = r.disassemble
		check(dis.has("plank") and int(dis.plank[0]) >= 2 and int(dis.plank[1]) <= 3, "%s → 2-3 planks" % t)
		check(dis.has("nails"), "%s → nails" % t)
	check(bool(cat.resolve(&"fridge").movable) and bool(cat.resolve(&"sofa").movable), "fridge / sofa movable")
	check_eq(cat.resolve(&"fridge").disassemble, {}, "fridge cannot be taken apart")


func test_loot_tables_give_planks_nails_and_hammers() -> void:
	for id in ["garage/tool_crate", "garage/shelf", "crate"]:
		var t: LootTable = load("res://data/loot/%s.tres" % id)
		var ids := t.entries.map(func(e): return StringName(e.item_id))
		check(ids.has(&"plank"), "%s gives planks" % id)
		check(ids.has(&"nails"), "%s gives nails" % id)
	var tc: LootTable = load("res://data/loot/garage/tool_crate.tres")
	check(tc.entries.any(func(e): return e.item_id == &"hammer"), "tool crate gives hammers")
	check(tc.entries.any(func(e): return e.item_id == &"crowbar"), "…and crowbars")
	check_eq(tc.validate().size(), 0, "tool crate table valid")


func test_from_dict_before_ready_restores_planks() -> void:
	var b := BarricadeComponent.new()
	b.name = BarricadeComponent.NODE_NAME
	b.from_dict({"side": -1.0, "planks": [{"health": 30.0, "max": 60.0, "tilt": 3.0}, {"health": 60.0, "max": 60.0}]})
	check_eq(b.plank_count(), 2, "restored before entering the tree")
	check(b.blocks_path(), "blocks already")
	var w := _window()
	w.add_child(b)
	check_eq(BarricadeComponent.of(w), b, "found on the window")
	check_eq(w.barricade_planks(), 2, "window sees 2 planks")
	check_eq(b.side, -1.0, "side kept")
	check_eq(b.board_count(), 2, "boards drawn once in the tree")
	check_near(b.plank_fraction(0), 0.5, 0.001, "health kept")
	check_eq(b.to_dict().planks.size(), 2, "round-trip")
	var bad := BarricadeComponent.new()
	bad.from_dict({"planks": [{"health": -5.0, "max": 60.0}, {"health": 99.0, "max": 60.0}]})
	check_eq(bad.plank_count(), 1, "dead planks dropped")
	check_near(float(bad.planks[0].health), 60.0, 0.001, "health clamped to max")
	bad.free()


func test_box_of_nails_opens_into_50_nails() -> void:
	var a := _actor({&"nails_box": 1})
	var inv: ItemContainer = a.get("inventory")
	var box := inv.find(&"nails_box")
	var acts := ItemActions.for_item(a, box)
	var open := acts.filter(func(x): return x.id == ItemActions.OPEN_BOX)
	check_eq(open.size(), 1, "Open box listed")
	check(String(open[0].label).contains("50"), "label says 50 (%s)" % open[0].label)
	var r := ItemActions.perform(a, box, ItemActions.OPEN_BOX)
	check(r.ok, "opened")
	check_eq(inv.count_of(&"nails"), 50, "50 nails")
	check_eq(inv.count_of(&"nails_box"), 0, "box used up")
	var plank := ItemInstance.new(ItemDB.get_item(&"plank"))
	check(not ItemActions.for_item(a, plank).any(func(x): return x.id == ItemActions.OPEN_BOX), "planks are not boxes")
