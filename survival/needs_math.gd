class_name NeedsMath
extends RefCounted
## Pure maths of the survival needs (Round 7), unit-tested without a scene:
## threshold levels with hysteresis, the level → effect mapping, per-hour
## rates by activity, and what eating / drinking a portion does.

const HUNGER := &"hunger"
const THIRST := &"thirst"
const FATIGUE := &"fatigue"
const SICKNESS := &"sickness"
const NEEDS: Array[StringName] = [HUNGER, THIRST, FATIGUE, SICKNESS]


## Level (0 = fine … thresholds.size()) of a need at [value], given the
## [current] level. Rising: the highest level whose enter value is reached.
## Falling: a level is only left once the value is [hysteresis] below its
## enter value (so eating a crumb at 25.1 → 24.9 does not flicker).
static func level_for(value: float, current: int, thresholds: Array, hysteresis: float) -> int:
	var up := 0
	for t in thresholds:
		if value >= float(t):
			up += 1
	current = clampi(current, 0, thresholds.size())
	if up >= current:
		return up
	var lvl := current
	while lvl > up and value < float(thresholds[lvl - 1]) - hysteresis:
		lvl -= 1
	return lvl


static func thresholds_of(need: StringName, p: NeedsProfile) -> Array[float]:
	match need:
		HUNGER: return p.hunger_thresholds
		THIRST: return p.thirst_thresholds
		FATIGUE: return p.fatigue_thresholds
		SICKNESS: return p.sickness_thresholds
	return []


static func label_of(need: StringName, level: int, p: NeedsProfile) -> String:
	if level <= 0:
		return ""
	var labels: PackedStringArray
	match need:
		HUNGER: labels = p.hunger_labels
		THIRST: labels = p.thirst_labels
		FATIGUE: labels = p.fatigue_labels
		SICKNESS: labels = p.sickness_labels
	return labels[mini(level, labels.size()) - 1] if not labels.is_empty() else String(need).capitalize()


static func _at(arr: Array, level: int, fallback: float) -> float:
	if arr.is_empty():
		return fallback
	return float(arr[clampi(level, 0, arr.size() - 1)])


## Behaviour effects of the current levels ({hunger, thirst, fatigue,
## sickness} → int). Returns:
##   max_stamina: multiplier of max stamina
##   stamina_regen: multiplier of stamina recovery
##   speed: movement speed multiplier
##   swing_time: melee swing time multiplier
##   heal: wound healing speed multiplier
##   regen: health regeneration allowed
##   health_drain: health lost per game hour
static func effects_for(levels: Dictionary, p: NeedsProfile) -> Dictionary:
	var h := int(levels.get(HUNGER, 0))
	var t := int(levels.get(THIRST, 0))
	var f := int(levels.get(FATIGUE, 0))
	var s := int(levels.get(SICKNESS, 0))
	return {
		"max_stamina": _at(p.hunger_max_stamina, h, 1.0) * _at(p.thirst_max_stamina, t, 1.0) * _at(p.sickness_max_stamina, s, 1.0),
		"stamina_regen": _at(p.fatigue_stamina_regen, f, 1.0),
		"speed": _at(p.fatigue_speed, f, 1.0) * _at(p.thirst_speed, t, 1.0),
		"swing_time": _at(p.fatigue_swing_time, f, 1.0),
		"heal": _at(p.hunger_heal, h, 1.0) * _at(p.thirst_heal, t, 1.0) * _at(p.sickness_heal, s, 1.0),
		"regen": h < p.hunger_no_regen_level and t < p.thirst_no_regen_level and s < p.sickness_no_regen_level,
		"health_drain": _at(p.hunger_health_drain, h, 0.0) + _at(p.thirst_health_drain, t, 0.0) + _at(p.sickness_health_drain, s, 0.0),
	}


## Change per game hour of [need] for an activity: [exerting] (jog /
## sprint / climb), [sleeping], [resting].
static func rate_per_hour(need: StringName, p: NeedsProfile, exerting: bool, sleeping: bool, resting: bool) -> float:
	match need:
		HUNGER:
			return p.hunger_sleep_per_hour if sleeping else p.hunger_per_hour * (p.exertion_multiplier if exerting else 1.0)
		THIRST:
			return p.thirst_sleep_per_hour if sleeping else p.thirst_per_hour * (p.exertion_multiplier if exerting else 1.0)
		FATIGUE:
			if sleeping:
				return p.sleep_fatigue_per_hour
			if resting:
				return p.rest_fatigue_per_hour
			return p.fatigue_per_hour
		SICKNESS:
			return -p.sickness_decay_per_hour
	return 0.0


## What consuming [portion] (0..1) of [food] in [spoil_state]
## (FoodData.SpoilState) does: {hunger, thirst, sickness} — hunger / thirst
## are REDUCTIONS (positive = the need goes down), sickness is added.
static func consume_effect(food: FoodData, portion: float, spoil_state: int, p: NeedsProfile) -> Dictionary:
	if food == null:
		return {"hunger": 0.0, "thirst": 0.0, "sickness": 0.0}
	portion = clampf(portion, 0.0, 1.0)
	var mult := 1.0
	var sick := 0.0
	match spoil_state:
		FoodData.SpoilState.STALE:
			mult = p.stale_food_multiplier
			sick = p.stale_sickness
		FoodData.SpoilState.ROTTEN:
			mult = p.rotten_food_multiplier
			sick = p.rotten_sickness
	# Negative thirst (salty food) is not softened by spoilage.
	var thirst := food.thirst * portion * (mult if food.thirst > 0.0 else 1.0)
	return {"hunger": hunger_of(food, p) * portion * mult, "thirst": thirst, "sickness": sick * portion}


## Hunger removed by a whole [food]: calories / kcal_per_hunger (the
## data's `hunger` only for 0-kcal items).
static func hunger_of(food: FoodData, p: NeedsProfile) -> float:
	if food == null:
		return 0.0
	if food.calories > 0.0 and p.kcal_per_hunger > 0.0:
		return food.calories / p.kcal_per_hunger
	return food.hunger


## [values] may be keyed by String or StringName.
static func _val(values: Dictionary, need: StringName) -> float:
	return float(values.get(String(need), values.get(need, 0.0)))


## Game hours a sleep would last from [fatigue] (to 0 at the sleep rate).
static func expected_sleep_hours(fatigue: float, p: NeedsProfile) -> float:
	return fatigue / maxf(-p.sleep_fatigue_per_hour, 0.01)


## The need (&"hunger" / &"thirst") that would reach its critical level
## (last threshold) during a full sleep from [values], or &"".
static func sleep_risk(values: Dictionary, p: NeedsProfile) -> StringName:
	var hours := expected_sleep_hours(_val(values, FATIGUE), p)
	for need in [THIRST, HUNGER]:
		var th := thresholds_of(need, p)
		if th.is_empty():
			continue
		var predicted := _val(values, need) + rate_per_hour(need, p, false, true, false) * hours
		if predicted >= th[-1]:
			return need
	return &""


## Can a character with [fatigue_level] fall asleep?
static func can_sleep(fatigue_level: int, p: NeedsProfile) -> bool:
	return fatigue_level >= p.sleep_min_fatigue_level
