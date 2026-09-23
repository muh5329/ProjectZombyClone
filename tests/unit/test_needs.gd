extends "res://tests/test_case.gd"
## Round 7 (pure): world-time derivations, needs threshold levels with
## hysteresis, the level → effect mapping, activity rates, spoilage by age
## (with / without a fridge), consume maths (portions, reductions, stale /
## rotten), tool resolution, lighting curve, max-stamina combination.

var p: NeedsProfile


func setup() -> void:
	p = load("res://data/survival/needs_profile.tres")


func _d(id: StringName) -> ItemData:
	return ItemDB.get_item(id)


# --- World time --------------------------------------------------------------------

func test_clock_derivations_and_day_rollover() -> void:
	var start := 7.0 * 60.0  # 07:00
	check_eq(GameClock.hour_of(0.0, start), 7, "start hour")
	check_eq(GameClock.minute_of(70.0, start), 10, "08:10 minute")
	check_eq(GameClock.format_time(GameClock.hour_of(70.0, start), GameClock.minute_of(70.0, start)), "08:10", "format")
	check_eq(GameClock.days_elapsed(16.0 * 60.0 + 59.0, start), 0, "23:59 still day 0")
	check_eq(GameClock.days_elapsed(17.0 * 60.0, start), 1, "midnight rolls the day")
	check_eq(GameClock.hour_of(17.0 * 60.0, start), 0, "00:00")
	check_near(GameClock.hour_float(30.0, start), 7.5, 0.001, "hour float")


func test_calendar_month_rollover_and_seasons() -> void:
	check_eq(GameClock.date_after(7, 1, 0), {"month": 7, "day": 1}, "start date")
	check_eq(GameClock.date_after(7, 1, 11), {"month": 7, "day": 12}, "07/12")
	check_eq(GameClock.date_after(7, 1, 31), {"month": 8, "day": 1}, "July has 31 days")
	check_eq(GameClock.date_after(12, 31, 1), {"month": 1, "day": 1}, "year wraps")
	check_eq(GameClock.date_after(2, 28, 1), {"month": 3, "day": 1}, "no leap day")
	check_eq(GameClock.format_date(7, 12), "07/12", "MM/DD")
	check_eq(GameClock.season_of(7), &"summer", "July summer")
	check_eq(GameClock.season_of(12), &"winter", "Dec winter")
	check_eq(GameClock.season_of(2), &"winter", "Feb winter")
	check_eq(GameClock.season_of(3), &"spring", "Mar spring")
	check_eq(GameClock.season_of(9), &"autumn", "Sep autumn")
	var t_july := GameClock.c_to_f(GameClock.temperature_c(7, 8.17))
	check(t_july > 65.0 and t_july < 80.0, "July morning ~70°F (%.1f)" % t_july)
	check_gt(GameClock.temperature_c(7, 15.0), GameClock.temperature_c(7, 3.0), "afternoon warmer than night")
	check_gt(GameClock.temperature_c(7, 12.0), GameClock.temperature_c(1, 12.0), "July warmer than January")
	check_eq(ClockWidget.format_info(71.6, "07/12"), "71.6°F 07/12", "clock info line")


func test_time_manager_advance_emits_units() -> void:
	TimeManager.reset()
	var got := {"min": 0, "hour": [], "day": []}
	var on_min := func(_m: int) -> void: got.min += 1
	var on_hour := func(h: int, _d: int) -> void: got.hour.append(h)
	var on_day := func(d: int) -> void: got.day.append(d)
	EventBus.minute_passed.connect(on_min)
	EventBus.hour_passed.connect(on_hour)
	EventBus.day_passed.connect(on_day)
	TimeManager.advance(17.0 * 60.0 + 5.0)  # 07:00 → 00:05 next day
	EventBus.minute_passed.disconnect(on_min)
	EventBus.hour_passed.disconnect(on_hour)
	EventBus.day_passed.disconnect(on_day)
	check_eq(got.min, 17 * 60 + 5, "one minute_passed per minute")
	check_eq((got.hour as Array).size(), 17, "hours 08..00")
	check_eq(got.hour[0], 8, "first hour 08")
	check_eq(got.hour[-1], 0, "last hour 00")
	check_eq(got.day, [1], "one day rollover")
	check_eq(TimeManager.clock_text(), "00:05", "clock")
	check_eq(TimeManager.date_text(), "07/02", "date")
	check_eq(TimeManager.day_index(), 1, "day index")
	var saved := TimeManager.to_dict()
	TimeManager.reset()
	TimeManager.from_dict(saved)
	check_eq(TimeManager.clock_text(), "00:05", "round trip")
	TimeManager.reset()


# --- Levels / hysteresis --------------------------------------------------------------

func test_need_levels_with_hysteresis() -> void:
	var th: Array[float] = [15.0, 25.0, 45.0, 70.0]
	check_eq(NeedsMath.level_for(5.0, 0, th, 5.0), 0, "fine")
	check_eq(NeedsMath.level_for(15.0, 0, th, 5.0), 1, "peckish at enter")
	check_eq(NeedsMath.level_for(26.0, 1, th, 5.0), 2, "hungry")
	check_eq(NeedsMath.level_for(80.0, 0, th, 5.0), 4, "jumps straight to starving")
	check_eq(NeedsMath.level_for(24.0, 2, th, 5.0), 2, "24 < 25 but within hysteresis: still hungry")
	check_eq(NeedsMath.level_for(19.9, 2, th, 5.0), 1, "below 20: peckish")
	check_eq(NeedsMath.level_for(5.0, 4, th, 5.0), 0, "eat a lot: straight to fine")
	check_eq(NeedsMath.level_for(41.0, 3, th, 5.0), 3, "very hungry holds at 41")
	check_eq(NeedsMath.level_for(39.0, 3, th, 5.0), 2, "drops at 39")
	check_eq(NeedsMath.label_of(&"hunger", 2, p), "Hungry", "label")
	check_eq(NeedsMath.label_of(&"thirst", 1, p), "Thirsty", "thirst label")
	check_eq(NeedsMath.label_of(&"fatigue", 3, p), "Exhausted", "fatigue label")
	check_eq(NeedsMath.label_of(&"hunger", 0, p), "", "no label when fine")


func test_effects_mapping() -> void:
	var fine := NeedsMath.effects_for({}, p)
	check_near(fine.max_stamina, 1.0, 0.0001, "fine max stamina")
	check(fine.regen, "fine regenerates")
	check_near(fine.health_drain, 0.0, 0.0001, "no drain")
	var hungry := NeedsMath.effects_for({&"hunger": 2}, p)
	check_near(hungry.max_stamina, 0.9, 0.0001, "hungry −10 % max stamina")
	check(hungry.regen, "hungry still regenerates")
	var very := NeedsMath.effects_for({&"hunger": 3}, p)
	check_near(very.max_stamina, 0.75, 0.0001, "very hungry −25 %")
	check(not very.regen, "very hungry: regen off")
	check_near(very.heal, 0.5, 0.0001, "very hungry heals at half speed")
	var starving := NeedsMath.effects_for({&"hunger": 4}, p)
	check_near(starving.health_drain, 6.0, 0.0001, "starving drains 6 hp / game hour")
	check_near(starving.heal, 0.0, 0.0001, "starving: wounds do not heal")
	var parched := NeedsMath.effects_for({&"thirst": 2}, p)
	check(not parched.regen, "parched: regen off (harsher than hunger)")
	check_lt(parched.max_stamina, 0.8, "parched max stamina")
	var dying := NeedsMath.effects_for({&"thirst": 3}, p)
	check_gt(dying.health_drain, starving.health_drain, "thirst kills faster")
	var tired := NeedsMath.effects_for({&"fatigue": 3}, p)
	check_near(tired.speed, 0.9, 0.0001, "exhausted ×0.9 speed")
	check_near(tired.swing_time, 1.2, 0.0001, "exhausted ×1.2 swing time")
	check_lt(tired.stamina_regen, 1.0, "fatigue slows stamina regen")
	var both := NeedsMath.effects_for({&"hunger": 2, &"thirst": 1}, p)
	check_near(both.max_stamina, 0.9 * 0.9, 0.0001, "multipliers combine")


func test_rates_by_activity() -> void:
	check_near(NeedsMath.rate_per_hour(&"hunger", p, false, false, false), 2.5, 0.001, "hunger awake")
	check_near(NeedsMath.rate_per_hour(&"thirst", p, false, false, false), 3.5, 0.001, "thirst awake")
	check_near(NeedsMath.rate_per_hour(&"thirst", p, true, false, false), 5.25, 0.001, "jogging ×1.5")
	check_near(NeedsMath.rate_per_hour(&"hunger", p, false, true, false), 1.2, 0.001, "hunger asleep")
	check_near(NeedsMath.rate_per_hour(&"thirst", p, false, true, false), 1.8, 0.001, "thirst asleep")
	check_near(NeedsMath.rate_per_hour(&"fatigue", p, false, false, false), 4.0, 0.001, "fatigue awake")
	check_lt(NeedsMath.rate_per_hour(&"fatigue", p, false, true, false), 0.0, "sleep reduces fatigue")
	check_lt(NeedsMath.rate_per_hour(&"fatigue", p, false, false, true), 0.0, "resting reduces fatigue")
	check(not NeedsMath.can_sleep(0, p) and NeedsMath.can_sleep(1, p), "sleep from Tired on")


# --- Spoilage --------------------------------------------------------------------------

func test_spoil_state_by_age() -> void:
	var day := 1440.0
	check_eq(FoodData.spoil_state_for(0.0, 5.0, 0.0), FoodData.SpoilState.FRESH, "new")
	check_eq(FoodData.spoil_state_for(4.9 * day, 5.0, 0.0), FoodData.SpoilState.FRESH, "day 4.9 fresh")
	check_eq(FoodData.spoil_state_for(5.0 * day, 5.0, 0.0), FoodData.SpoilState.STALE, "day 5 stale")
	check_eq(FoodData.spoil_state_for(10.0 * day, 5.0, 0.0), FoodData.SpoilState.ROTTEN, "rotten at 2× fresh by default")
	check_eq(FoodData.spoil_state_for(8.0 * day, 5.0, 8.0), FoodData.SpoilState.ROTTEN, "explicit rotten_days")
	check_eq(FoodData.spoil_state_for(999.0 * day, 0.0, 0.0), FoodData.SpoilState.FRESH, "cans never spoil")


func test_item_ages_slower_in_a_fridge() -> void:
	TimeManager.reset()
	var cabinet := ItemContainer.new(20.0)
	var fridge := ItemContainer.new(20.0)
	fridge.set_spoil_multiplier(0.25)
	cabinet.add_id(&"bread", 1)
	fridge.add_id(&"bread", 1)
	var a := cabinet.find(&"bread")
	var b := fridge.find(&"bread")
	check(a.perishable() and b.perishable(), "bread spoils")
	TimeManager.set_minutes(6.0 * 1440.0)  # 6 days (bread fresh 5)
	check_near(a.effective_age(), 6.0 * 1440.0, 0.5, "cabinet ages 1:1")
	check_near(b.effective_age(), 1.5 * 1440.0, 0.5, "fridge ages ×0.25")
	check_eq(a.spoil_state(), FoodData.SpoilState.STALE, "cabinet bread stale")
	check_eq(b.spoil_state(), FoodData.SpoilState.FRESH, "fridge bread fresh")
	# Taking it out of the fridge: it ages at full speed from then on.
	fridge.transfer_to(cabinet, b)
	TimeManager.set_minutes(8.0 * 1440.0)
	check_near(b.effective_age(), 3.5 * 1440.0, 0.5, "full speed after leaving the fridge")
	check(not a.can_stack_with(b), "stale and fresh bread do not stack")
	var saved := cabinet.to_dict()
	var copy := ItemContainer.new(20.0)
	copy.from_dict(saved)
	var ages: Array = copy.items.map(func(it: ItemInstance) -> float: return it.effective_age())
	ages.sort()
	check_near(float(ages[0]), 3.5 * 1440.0, 1.0, "age saved (fridge bread)")
	check_near(float(ages[1]), 8.0 * 1440.0, 1.0, "age saved (cabinet bread)")
	check_eq(LootWindow.row_texts(a).condition, "Stale", "8-day bread shows Stale in the condition column")
	TimeManager.set_minutes(11.0 * 1440.0)
	check_eq(LootWindow.row_texts(a).condition, "Rotten", "11-day bread: Rotten")
	TimeManager.reset()


# --- Consumption ----------------------------------------------------------------------

func test_hunger_derives_from_calories() -> void:
	for id in ItemDB.ids_in_category(ItemData.Category.FOOD) + ItemDB.ids_in_category(ItemData.Category.DRINK):
		var f := ItemDB.get_item(id) as FoodData
		if f == null or f.calories <= 0.0:
			continue
		check_near(NeedsMath.hunger_of(f, p), f.calories / 25.0, 0.001, "%s: 25 kcal per hunger point" % id)
		check_near(f.hunger, f.calories / 25.0, 0.06, "%s: data hunger consistent with kcal" % id)
	check_near(NeedsMath.hunger_of(_d(&"water_bottle") as FoodData, p), 0.0, 0.001, "water has no calories")


func test_sleep_risk_prediction() -> void:
	check_near(NeedsMath.expected_sleep_hours(100.0, p), 8.0, 0.001, "100 fatigue = 8 h")
	check_eq(NeedsMath.sleep_risk({"fatigue": 90.0, "thirst": 50.0, "hunger": 10.0}, p), &"", "safe")
	check_eq(NeedsMath.sleep_risk({"fatigue": 90.0, "thirst": 80.0, "hunger": 10.0}, p), &"thirst", "80 + 1.8 × 7.2 ≥ 88")
	check_eq(NeedsMath.sleep_risk({&"fatigue": 90.0, &"thirst": 10.0, &"hunger": 75.0}, p), &"hunger", "StringName keys too")


func test_item_age_is_elapsed_not_a_stamp_whatever_the_load_order() -> void:
	TimeManager.reset()
	var c := ItemContainer.new(20.0)
	c.add_id(&"bread", 1)
	TimeManager.set_minutes(2.0 * 1440.0)
	var saved := c.to_dict()
	# Order 1: items first, then the clock (a later day) is loaded.
	TimeManager.reset()
	var a := ItemContainer.new(20.0)
	a.from_dict(saved)
	TimeManager.from_dict({"minutes": 10.0 * 1440.0})
	check_near(a.items[0].effective_age(), 2.0 * 1440.0, 1.0, "items then clock: still 2 days old")
	# Order 2: clock first, then items.
	TimeManager.reset()
	TimeManager.from_dict({"minutes": 10.0 * 1440.0})
	var b := ItemContainer.new(20.0)
	b.from_dict(saved)
	check_near(b.items[0].effective_age(), 2.0 * 1440.0, 1.0, "clock then items: 2 days old")
	TimeManager.advance(60.0)
	check_near(b.items[0].effective_age(), 2.0 * 1440.0 + 60.0, 1.0, "ages normally after the load")
	TimeManager.reset()


func test_consume_math_portions_and_spoilage() -> void:
	var beans := _d(&"canned_beans") as FoodData
	var e := NeedsMath.consume_effect(beans, 1.0, FoodData.SpoilState.FRESH, p)
	check_near(e.hunger, beans.hunger, 0.001, "whole can")
	check_near(e.sickness, 0.0, 0.001, "fresh: no sickness")
	var h := NeedsMath.consume_effect(beans, 0.5, FoodData.SpoilState.FRESH, p)
	check_near(h.hunger, beans.hunger * 0.5, 0.001, "half a can")
	var water := _d(&"water_bottle") as FoodData
	check_near(NeedsMath.consume_effect(water, 1.0, 0, p).thirst, 40.0, 0.001, "water −40 thirst")
	var chips := _d(&"chips") as FoodData
	check_lt(NeedsMath.consume_effect(chips, 1.0, 0, p).thirst, 0.0, "salty chips make you thirsty")
	var bread := _d(&"bread") as FoodData
	var rot := NeedsMath.consume_effect(bread, 1.0, FoodData.SpoilState.ROTTEN, p)
	check_near(rot.hunger, bread.hunger * p.rotten_food_multiplier, 0.001, "rotten food fills less")
	check_near(rot.sickness, p.rotten_sickness, 0.001, "rotten food makes you sick")
	var stale := NeedsMath.consume_effect(bread, 1.0, FoodData.SpoilState.STALE, p)
	check(stale.sickness > 0.0 and stale.sickness < rot.sickness, "stale: a little sick")
	check_eq(ConsumeAction.action_label(beans, false), "Eating Canned Beans…", "label")
	check_eq(ConsumeAction.action_label(water, true), "Drinking Water Bottle (half)…", "drink label")


func test_portion_weight_and_stacking() -> void:
	var inv := ItemContainer.new(20.0)
	inv.add_id(&"canned_beans", 2)
	var full := inv.find(&"canned_beans")
	var half := inv.remove(full, 1)
	half.portion = 0.5
	check_near(half.total_weight(), 0.3, 0.001, "half a can weighs half")
	inv.add(half)
	check_eq(inv.items.size(), 2, "half-eaten can does not stack with a full one")
	check_near(inv.total_weight(), 0.9, 0.001, "container weight")
	var d := half.to_dict()
	check_near(float(d.portion), 0.5, 0.001, "portion saved")
	check_near(ItemInstance.from_dict(d).portion, 0.5, 0.001, "portion loaded")


func test_empty_bottle_data() -> void:
	var water := _d(&"water_bottle") as FoodData
	check_eq(water.empty_item_id, &"water_bottle_empty", "bottle leaves an empty bottle")
	var empty := _d(&"water_bottle_empty")
	check(empty != null and not empty is FoodData, "empty bottle is not food")
	check_eq(empty.fill_item_id, &"water_bottle", "fills back into a water bottle")
	check(Equipment.is_consumable(ItemInstance.new(water)), "water can go on the hotbar")


func test_tool_resolution() -> void:
	var beans := _d(&"canned_beans") as FoodData
	var inv := ItemContainer.new(20.0)
	var r := ConsumeAction.resolve_tool(beans, [inv])
	check(not r.ok and r.reason == "Need a can opener", "no tool refused (%s)" % str(r))
	inv.add_id(&"kitchen_knife", 1)
	r = ConsumeAction.resolve_tool(beans, [inv])
	check(r.ok and r.kind == &"fallback" and (r.tool as ItemInstance).id() == &"kitchen_knife", "knife is the fallback")
	var bag := ItemContainer.new(10.0)
	bag.add_id(&"tin_opener", 1)
	r = ConsumeAction.resolve_tool(beans, [inv, bag])
	check(r.ok and r.kind == &"tool", "a tin opener anywhere carried wins")
	var broken := ItemContainer.new(10.0)
	broken.add_id(&"kitchen_knife", 1, 0)
	r = ConsumeAction.resolve_tool(beans, [broken])
	check(not r.ok, "a broken knife does not open cans")
	r = ConsumeAction.resolve_tool(_d(&"apple") as FoodData, [])
	check(r.ok and r.kind == &"none", "apples need no tool")


# --- Lighting / stamina -----------------------------------------------------------------

func test_lighting_curve() -> void:
	var noon := DayNightLighting.lighting_at(12.0)
	var night := DayNightLighting.lighting_at(23.0)
	var dusk := DayNightLighting.lighting_at(19.5)
	check_gt(noon.sun_energy, night.sun_energy * 3.0, "noon much brighter than 23:00")
	check(dusk.sun_energy < noon.sun_energy and dusk.sun_energy > night.sun_energy, "dusk in between")
	check_gt(night.sun_energy, 0.05, "night never pitch black")
	var bg: Color = night.background
	check(bg.b > bg.r, "night is blue")
	check_near(DayNightLighting.lighting_at(7.5).sun_energy, 0.85, 0.001, "morning = the Round 1-6 daylight")


func test_combined_max_stamina() -> void:
	check_near(Character.combined_max(100.0, {}, {}), 100.0, 0.001, "base")
	check_near(Character.combined_max(100.0, {&"injury": 20.0}, {&"needs": 0.9}), 72.0, 0.001, "(100-20)×0.9")
	check_near(Character.combined_max(100.0, {&"injury": 200.0}, {}), 0.0, 0.001, "never negative")
