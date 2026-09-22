extends "res://tests/test_case.gd"
## Pure injury maths (InjuryComponent statics) and injury / zombie data.

const PROFILE := preload("res://data/injuries/human_injuries.tres")
const ZPROFILE := preload("res://data/zombies/zombie_basic.tres")


func _inj(region: int, type: int, bandaged := false, bleeding := true) -> Injury:
	var i := Injury.new(region, type)
	i.bandaged = bandaged
	i.bleeding = bleeding and PROFILE.spec(type).bleed_rate > 0.0
	return i


func _sum(w: Dictionary) -> float:
	var t := 0.0
	for k in w:
		t += float(w[k])
	return t


func test_region_weights_sum_to_one_and_are_valid() -> void:
	for pair in [["default", PROFILE.default_region_weights], ["glass", PROFILE.glass_region_weights], ["zombie", ZPROFILE.attack_region_weights]]:
		check_near(_sum(pair[1]), 1.0, 0.0001, "%s region weights sum" % pair[0])
		for k in pair[1]:
			check(Injury.region_from_id(StringName(k)) >= 0, "%s: %s is a region" % [pair[0], k])
	check_near(_sum(ZPROFILE.attack_type_weights), 1.0, 0.0001, "zombie type weights sum")
	for k in ZPROFILE.attack_type_weights:
		check(Injury.type_from_id(StringName(k)) >= 0, "%s is an injury type" % k)
	check_eq(Injury.REGION_IDS.size(), 10, "ten body regions")
	check_eq(Injury.TYPE_IDS.size(), 6, "six injury types")
	for r in PROFILE.glass_region_weights:
		var id := Injury.region_from_id(StringName(r))
		check(id != Injury.Region.HEAD and id != Injury.Region.NECK, "glass never cuts head/neck")


func test_roll_weighted() -> void:
	var w := {&"a": 0.25, &"b": 0.5, &"c": 0.25}
	check_eq(Injury.roll_weighted(w, 0.0), &"a", "low end")
	check_eq(Injury.roll_weighted(w, 0.3), &"b", "middle")
	check_eq(Injury.roll_weighted(w, 0.99), &"c", "high end")
	check_eq(Injury.roll_weighted(w, 1.0), &"c", "1.0 clamps")
	check_eq(Injury.roll_weighted({}, 0.5), &"", "empty")
	check_eq(Injury.roll_weighted({&"x": 0.0, &"y": 2.0}, 0.0), &"y", "zero weight skipped")
	var counts := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 4000:
		var k := Injury.roll_weighted(ZPROFILE.attack_type_weights, rng.randf())
		counts[k] = counts.get(k, 0) + 1
	check_near(counts.get(&"scratch", 0) / 4000.0, 0.6, 0.03, "scratch ≈ 60 %")
	check_near(counts.get(&"bite", 0) / 4000.0, 0.12, 0.03, "bite ≈ 12 %")


func test_infection_chances_from_spec() -> void:
	check_eq(PROFILE.bite.infection_chance, 1.0, "bite 100 %")
	check_near(PROFILE.scratch.infection_chance, 0.07, 0.0001, "scratch 7 %")
	check_near(PROFILE.laceration.infection_chance, 0.25, 0.0001, "laceration 25 %")
	check_eq(PROFILE.burn.infection_chance, 0.0, "burns never")
	check_eq(PROFILE.fracture.bleed_rate, 0.0, "fractures do not bleed")
	check_gt(PROFILE.infection_rise_per_second, 0.0, "infection rises")
	check_gt(100.0 / PROFILE.infection_rise_per_second, 1800.0, "…but takes more than 30 min to peak")


func test_bleed_rate_and_bandage() -> void:
	var list: Array[Injury] = [_inj(Injury.Region.LEFT_ARM, Injury.Type.LACERATION), _inj(Injury.Region.HEAD, Injury.Type.SCRATCH)]
	check_near(InjuryComponent.total_bleed_rate(list, PROFILE), PROFILE.laceration.bleed_rate + PROFILE.scratch.bleed_rate, 0.0001, "sum of bleeders")
	list[0].bandaged = true
	check_near(InjuryComponent.total_bleed_rate(list, PROFILE), PROFILE.scratch.bleed_rate, 0.0001, "bandaged stops")
	list[1].bleeding = false
	check_eq(InjuryComponent.total_bleed_rate(list, PROFILE), 0.0, "stopped")
	var burn: Array[Injury] = [_inj(Injury.Region.LEFT_ARM, Injury.Type.BURN)]
	check_eq(InjuryComponent.total_bleed_rate(burn, PROFILE), 0.0, "burns don't bleed")


func test_leg_injuries_slow_others_do_not() -> void:
	var arm: Array[Injury] = [_inj(Injury.Region.LEFT_ARM, Injury.Type.FRACTURE)]
	check_eq(InjuryComponent.leg_speed_multiplier(arm, PROFILE), 1.0, "arm fracture: no slow")
	var leg: Array[Injury] = [_inj(Injury.Region.LEFT_LEG, Injury.Type.LACERATION)]
	check_near(InjuryComponent.leg_speed_multiplier(leg, PROFILE), PROFILE.laceration.leg_speed_multiplier, 0.0001, "leg laceration slows")
	leg[0].bandaged = true
	var expect := 1.0 - (1.0 - PROFILE.laceration.leg_speed_multiplier) * PROFILE.bandaged_slow_factor
	check_near(InjuryComponent.leg_speed_multiplier(leg, PROFILE), expect, 0.0001, "bandaged slows half as much")
	var both: Array[Injury] = [_inj(Injury.Region.LEFT_LEG, Injury.Type.FRACTURE), _inj(Injury.Region.RIGHT_LEG, Injury.Type.FRACTURE)]
	check_near(InjuryComponent.leg_speed_multiplier(both, PROFILE), PROFILE.min_leg_speed_multiplier, 0.0001, "floored")


func test_pain_and_max_stamina_penalty() -> void:
	var list: Array[Injury] = [_inj(Injury.Region.UPPER_TORSO, Injury.Type.BITE), _inj(Injury.Region.LEFT_HAND, Injury.Type.SCRATCH)]
	check_near(InjuryComponent.total_pain(list, PROFILE), PROFILE.bite.pain + PROFILE.scratch.pain, 0.0001, "pain sums")
	list[0].bandaged = true
	check_near(InjuryComponent.total_pain(list, PROFILE), PROFILE.bite.pain * PROFILE.bandaged_pain_multiplier + PROFILE.scratch.pain, 0.0001, "bandage eases pain")
	var many: Array[Injury] = []
	for i in 10:
		many.append(_inj(Injury.Region.UPPER_TORSO, Injury.Type.FRACTURE))
	check_eq(InjuryComponent.total_pain(many, PROFILE), PROFILE.pain_max, "pain capped")
	check_eq(InjuryComponent.max_stamina_penalty(many, PROFILE), PROFILE.max_stamina_penalty_cap, "stamina penalty capped")
	check_near(InjuryComponent.max_stamina_penalty(list, PROFILE), PROFILE.bite.max_stamina_penalty + PROFILE.scratch.max_stamina_penalty, 0.0001, "penalty sums")
	check_eq(InjuryComponent.max_stamina_penalty([] as Array[Injury], PROFILE), 0.0, "none")


func test_injury_labels_and_dict() -> void:
	var i := Injury.new(Injury.Region.LEFT_LEG, Injury.Type.DEEP_WOUND)
	check(i.is_leg(), "left leg is a leg")
	check_eq(i.label(), "Left leg — Deep wound", "label")
	var d := i.to_dict()
	check(d.region == &"left_leg" and d.type == &"deep_wound", "ids in dict")
	check(not Injury.new(Injury.Region.LEFT_HAND).is_leg(), "hand is not")
	check_eq(Injury.region_from_id(&"nope"), -1, "unknown region")


func test_pain_combat_modifiers_and_infection_stages() -> void:
	check_eq(InjuryComponent.pain_combat_modifiers(0.0, PROFILE), Vector2.ONE, "no pain")
	check_eq(InjuryComponent.pain_combat_modifiers(50.0, PROFILE), Vector2.ONE, "50 is not above 50")
	check_eq(InjuryComponent.pain_combat_modifiers(60.0, PROFILE), Vector2(0.85, 1.15), "moderate pain")
	check_eq(InjuryComponent.pain_combat_modifiers(90.0, PROFILE), Vector2(0.7, 1.3), "severe pain")
	check_eq(InjuryComponent.infection_stage_for(10.0, PROFILE), &"none", "hidden early")
	check_eq(InjuryComponent.infection_stage_for(25.0, PROFILE), &"feverish", "fever at 25")
	check_eq(InjuryComponent.infection_stage_for(60.0, PROFILE), &"infected", "infected at 60")


func test_bandage_priority_data() -> void:
	for k in PROFILE.bandage_priority:
		check(Injury.type_from_id(StringName(k)) >= 0, "%s is a type" % k)
	check(not PROFILE.bandage_priority.has(&"fracture"), "fractures are never bandaged")
	check_gt(float(PROFILE.bandage_priority[&"deep_wound"]), float(PROFILE.bandage_priority[&"scratch"]), "deep wound first")
