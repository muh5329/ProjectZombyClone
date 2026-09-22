class_name CharacterStatsProfile
extends Resource
## Data-driven tuning for a character's stats (Phase 1: stamina only).
## Edit the .tres, not the code. Rates are per second; fractions are 0..1.
##
## Design intent (vulnerable human): sprinting is short and expensive,
## jogging is NOT free, recovery is slow, and being winded has teeth.

@export_group("Stamina")
@export var stamina_max: float = 100.0
## Per-context rates. Context names match MovementComponent mode names plus
## "idle". Negative drains, positive recovers.
@export var stamina_rate_idle: float = 3.5
@export var stamina_rate_sneak: float = 1.0
@export var stamina_rate_walk: float = 1.0
@export var stamina_rate_jog: float = -1.5
@export var stamina_rate_sprint: float = -18.0
## Climbing through windows / over obstacles.
@export var stamina_rate_climb: float = -12.0
## "low" warning state (no mechanical effect yet; UI + future stress).
@export_range(0.0, 1.0) var stamina_low_fraction: float = 0.25
## Exhausted: entered at/below `enter`, left only at/above `exit`.
@export_range(0.0, 1.0) var stamina_exhausted_enter: float = 0.02
@export_range(0.0, 1.0) var stamina_exhausted_exit: float = 0.40
## Speed multiplier while exhausted.
@export_range(0.1, 1.0) var exhausted_speed_multiplier: float = 0.6
## Minimum seconds sprint stays blocked after becoming exhausted, even if
## stamina somehow recovers faster (e.g. future items).
@export var winded_min_seconds: float = 4.0

@export_group("Body")
## Height of the eyes / interaction focus above the feet (metres).
@export var eye_height: float = 0.9
## Hit points (Round 4 layers injuries on top).
@export var health_max: float = 100.0


func stamina_rates() -> Dictionary:
	return {
		&"idle": stamina_rate_idle,
		&"sneak": stamina_rate_sneak,
		&"walk": stamina_rate_walk,
		&"jog": stamina_rate_jog,
		&"sprint": stamina_rate_sprint,
		&"climb": stamina_rate_climb,
		# Bandaging is sitting still: idle recovery.
		&"bandage": stamina_rate_idle,
	}


func stamina_thresholds() -> Dictionary:
	return {
		&"low": stamina_low_fraction,
		&"exhausted": {"enter": stamina_exhausted_enter, "exit": stamina_exhausted_exit},
	}
