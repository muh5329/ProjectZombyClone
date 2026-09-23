class_name NeedsProfile
extends Resource
## Survival-needs tuning (data/survival/needs_profile.tres, Round 7).
## Needs run 0 (fine) … 100 (critical); rates are per GAME hour (world
## time, see TimeManager). Threshold arrays hold the ENTER values of levels
## 1..n in ascending order; a level is left only [hysteresis] points below
## its enter value. Effect arrays are indexed by level (0 = fine).

@export_group("Start")
@export var start_hunger: float = 5.0
@export var start_thirst: float = 5.0
@export var start_fatigue: float = 5.0

@export_group("Rates (per game hour)")
@export var hunger_per_hour: float = 2.5
@export var thirst_per_hour: float = 3.5
## Awake. Sleeping uses [sleep_fatigue_per_hour], resting [rest_fatigue_per_hour].
@export var fatigue_per_hour: float = 4.0
## Hunger / thirst multiplier while jogging, sprinting or climbing.
@export var exertion_multiplier: float = 1.5
## Hunger / thirst per game hour while asleep.
@export var hunger_sleep_per_hour: float = 1.2
@export var thirst_sleep_per_hour: float = 1.8
## Fatigue change while asleep (−12.5/h: 100 → 0 in 8 h).
@export var sleep_fatigue_per_hour: float = -12.5
## Fatigue change while resting awake on a bed / sofa.
@export var rest_fatigue_per_hour: float = -2.0
## Food sickness recovers by this much per game hour.
@export var sickness_decay_per_hour: float = 8.0
## Health regained per game hour while fed, watered, not sick and unhurt.
@export var health_regen_per_hour: float = 6.0

@export_group("Thresholds")
@export var hysteresis: float = 5.0
@export var hunger_thresholds: Array[float] = [15.0, 25.0, 50.0, 80.0]
@export var hunger_labels: PackedStringArray = ["Peckish", "Hungry", "Very Hungry", "Starving"]
@export var thirst_thresholds: Array[float] = [25.0, 55.0, 88.0]
@export var thirst_labels: PackedStringArray = ["Thirsty", "Parched", "Dying of Thirst"]
@export var fatigue_thresholds: Array[float] = [30.0, 55.0, 80.0]
@export var fatigue_labels: PackedStringArray = ["Tired", "Very Tired", "Exhausted"]
@export var sickness_thresholds: Array[float] = [20.0, 45.0, 70.0]
@export var sickness_labels: PackedStringArray = ["Queasy", "Nauseous", "Food Poisoning"]

@export_group("Effects (indexed by level)")
## Max stamina multipliers (hungry −10 %, very hungry / starving −25 %).
@export var hunger_max_stamina: Array[float] = [1.0, 1.0, 0.9, 0.75, 0.75]
@export var thirst_max_stamina: Array[float] = [1.0, 0.9, 0.75, 0.6]
@export var sickness_max_stamina: Array[float] = [1.0, 0.95, 0.85, 0.7]
## Health lost per game hour (starving 6, dying of thirst 10 — death takes
## most of a day in the critical band; no water ≈ 36-48 game hours).
@export var hunger_health_drain: Array[float] = [0.0, 0.0, 0.0, 0.0, 6.0]
@export var thirst_health_drain: Array[float] = [0.0, 0.0, 0.0, 10.0]
@export var sickness_health_drain: Array[float] = [0.0, 0.0, 6.0, 30.0]
## Health regen is off from these levels on (very hungry / parched / nauseous).
@export var hunger_no_regen_level: int = 3
@export var thirst_no_regen_level: int = 2
@export var sickness_no_regen_level: int = 2
## Wound healing speed multipliers (InjuryComponent.heal_multiplier).
@export var hunger_heal: Array[float] = [1.0, 1.0, 1.0, 0.5, 0.0]
@export var thirst_heal: Array[float] = [1.0, 1.0, 0.5, 0.0]
@export var sickness_heal: Array[float] = [1.0, 1.0, 0.75, 0.5]
## Fatigue: stamina regeneration, movement speed and melee swing time.
@export var fatigue_stamina_regen: Array[float] = [1.0, 0.85, 0.7, 0.5]
@export var fatigue_speed: Array[float] = [1.0, 1.0, 1.0, 0.9]
@export var fatigue_swing_time: Array[float] = [1.0, 1.0, 1.1, 1.2]
## Thirst also slows you once parched / dying.
@export var thirst_speed: Array[float] = [1.0, 1.0, 0.95, 0.85]
## Sleeping is possible from this fatigue level on (1 = Tired).
@export var sleep_min_fatigue_level: int = 1
## Round 8: a sound wakes the sleeper when its propagated strength at the
## ear (SoundManager, walls / doors included) is at least this (0..1).
@export var wake_sound_strength: float = 0.1

@export_group("Food")
## Food's hunger reduction derives from its calories: 1 hunger point per
## this many kcal (FoodData.hunger is only the fallback for 0 kcal).
@export var kcal_per_hunger: float = 25.0
## Hunger / thirst reduction multiplier of stale / rotten food.
@export var stale_food_multiplier: float = 0.8
@export var rotten_food_multiplier: float = 0.5
## Sickness added by a whole stale / rotten item.
@export var stale_sickness: float = 5.0
@export var rotten_sickness: float = 45.0
## Hand cut from opening a can with a knife.
@export var fallback_cut_damage: float = 3.0
