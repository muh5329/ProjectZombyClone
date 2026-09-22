class_name InjuryProfile
extends Resource
## All injury tuning for humans (edit data/injuries/human_injuries.tres).
## Types: per-type InjuryTypeSpec. Region weights map Injury.REGION_IDS to
## weights that sum to 1 (unit-tested).

@export_group("Types")
@export var scratch: InjuryTypeSpec
@export var laceration: InjuryTypeSpec
@export var deep_wound: InjuryTypeSpec
@export var bite: InjuryTypeSpec
@export var burn: InjuryTypeSpec
@export var fracture: InjuryTypeSpec

@export_group("Regions")
## Where an untargeted hit (region &"random") lands.
@export var default_region_weights: Dictionary = {
	&"head": 0.05, &"neck": 0.05, &"upper_torso": 0.2, &"lower_torso": 0.1,
	&"left_arm": 0.12, &"right_arm": 0.12, &"left_hand": 0.08, &"right_hand": 0.08,
	&"left_leg": 0.1, &"right_leg": 0.1,
}
## Where broken glass cuts when climbing through a smashed window.
@export var glass_region_weights: Dictionary = {
	&"left_hand": 0.2, &"right_hand": 0.2, &"left_arm": 0.15, &"right_arm": 0.15,
	&"left_leg": 0.15, &"right_leg": 0.15,
}
## Chance a smashed-window climb lacerates (1 until "clear glass" exists).
@export_range(0.0, 1.0) var glass_laceration_chance: float = 1.0
## Immediate damage of a glass cut.
@export var glass_damage: float = 4.0

@export_group("Treatment")
@export var bandage_seconds: float = 4.0
## Which bleeding wound B treats first (higher first; ties → faster
## bleeder). Types missing here (fractures, burns) are never bandaged:
## they need splints / burn dressings later.
@export var bandage_priority: Dictionary = {&"deep_wound": 4.0, &"bite": 3.0, &"laceration": 2.0, &"scratch": 1.0}
## Bleed rate multiplier once bandaged (0 = stops).
@export var bandaged_bleed_multiplier: float = 0.0
@export var bandaged_heal_multiplier: float = 2.0
@export var bandaged_pain_multiplier: float = 0.6
## Leg slow penalty is scaled by this once bandaged (0.5 = half the slow).
@export var bandaged_slow_factor: float = 0.5

@export_group("Pain")
## Pain above these (0..100) slows swings and weakens hits.
@export var pain_moderate_threshold: float = 50.0
@export var pain_moderate_damage_multiplier: float = 0.85
@export var pain_moderate_swing_time_multiplier: float = 1.15
@export var pain_severe_threshold: float = 80.0
@export var pain_severe_damage_multiplier: float = 0.7
@export var pain_severe_swing_time_multiplier: float = 1.3

@export_group("Infection symptoms")
## The infection is invisible below [fever_threshold] (0..100); then
## "Feverish", from [infected_threshold] "Infected".
@export var fever_threshold: float = 25.0
@export var infected_threshold: float = 60.0

@export_group("Effects")
@export var pain_max: float = 100.0
@export var min_leg_speed_multiplier: float = 0.4
@export var max_stamina_penalty_cap: float = 40.0
## Infection stat (0..100) rise per second while infected: 100 after
## ~83 min of game time.
@export var infection_rise_per_second: float = 0.02
## Health lost per second once the infection is at 100.
@export var infection_lethal_damage_per_second: float = 0.5
## Injury bookkeeping rate (bleeding, healing, infection).
@export var tick_hz: float = 10.0
## Seconds between blood drops while bleeding.
@export var blood_drip_interval: float = 1.5


func spec(type: int) -> InjuryTypeSpec:
	match type:
		Injury.Type.SCRATCH: return scratch
		Injury.Type.LACERATION: return laceration
		Injury.Type.DEEP_WOUND: return deep_wound
		Injury.Type.BITE: return bite
		Injury.Type.BURN: return burn
		Injury.Type.FRACTURE: return fracture
	return scratch
