class_name FoodData
extends ItemData
## Food and drink (consumed by the needs system, Round 7).
##
## Eating: ConsumeAction (survival/) makes the character busy for
## [eat_seconds] × portion ("Eating Canned Beans…", damage interrupts),
## then removes [hunger] / [thirst] × portion × the spoil-state factor.
## Portions: "Eat" = the whole item, "Eat half" = 0.5 (the rest stays as a
## half-eaten item, ItemInstance.portion). A drink with [empty_item_id]
## leaves that item behind (water bottle → empty bottle).
## Tools: [requires_tool] is an item tag (&"can_opener") that must be
## carried; otherwise a carried item tagged [fallback_tool_tag] (&"blade":
## knives) opens it with [fallback_injury_chance] of a hand cut.
## Spoilage: fresh for [fresh_days], stale until [rotten_days], then rotten
## (ItemInstance ages; fridges age it slower). 0 fresh_days = never spoils.

enum SpoilState { FRESH, STALE, ROTTEN }
const SPOIL_IDS: Array[StringName] = [&"fresh", &"stale", &"rotten"]
const SPOIL_LABELS: Array[String] = ["Fresh", "Stale", "Rotten"]

## Energy in kcal for eating the whole item (display / future weight model).
@export var calories: float = 0.0
## Hunger removed by the whole item (needs scale 0..100).
@export var hunger: float = 0.0
## Thirst removed by the whole item (negative = makes you thirsty: chips).
@export var thirst: float = 0.0
## Game days the item stays fresh (0 = never spoils).
@export var fresh_days: float = 0.0
## Game days until it is rotten (0 → 2 × fresh_days).
@export var rotten_days: float = 0.0
## Busy seconds to consume the whole item (half portion: half the time).
@export var eat_seconds: float = 3.0
## "Eat half" / "Drink half" is offered.
@export var can_eat_half: bool = true
## Item tag that must be carried to open it (&"can_opener"); &"" = none.
@export var requires_tool: StringName = &""
## Tag of carried items that can open it instead, badly (&"blade").
@export var fallback_tool_tag: StringName = &""
## Chance the fallback tool cuts a hand (scratch / laceration).
@export_range(0.0, 1.0) var fallback_injury_chance: float = 0.25
## Item left behind when the whole thing is consumed (&"water_bottle_empty").
@export var empty_item_id: StringName = &""


func is_drink() -> bool:
	return category == Category.DRINK


func spoils() -> bool:
	return fresh_days > 0.0


func rotten_after_days() -> float:
	return rotten_days if rotten_days > fresh_days else fresh_days * 2.0


## Pure: spoil state for an effective age in game MINUTES.
static func spoil_state_for(age_minutes: float, fresh: float, rotten: float) -> int:
	if fresh <= 0.0:
		return SpoilState.FRESH
	var rot := rotten if rotten > fresh else fresh * 2.0
	var days := age_minutes / 1440.0
	if days >= rot:
		return SpoilState.ROTTEN
	if days >= fresh:
		return SpoilState.STALE
	return SpoilState.FRESH


func spoil_state(age_minutes: float) -> int:
	return spoil_state_for(age_minutes, fresh_days, rotten_days)
