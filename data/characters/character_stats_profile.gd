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
## Resting on a bed / sofa multiplies idle stamina recovery (Round 7).
@export var stamina_rest_multiplier: float = 3.0

@export_group("Carrying")
## Carried weight (kg) the character handles without penalty; above it
## the load is "light" (Encumbrance). Strength-based later.
@export var carry_capacity: float = 8.0
## Above this: "heavy". Above [carry_overloaded_kg]: "overloaded".
@export var carry_heavy_kg: float = 12.0
@export var carry_overloaded_kg: float = 15.0
## Hard weight limit of the main inventory (bags add their own capacity).
@export var inventory_capacity: float = 20.0
## Movement speed multiplier per state (light / heavy / overloaded).
@export var encumbrance_speed_light: float = 0.92
@export var encumbrance_speed_heavy: float = 0.85
@export var encumbrance_speed_overloaded: float = 0.65
## Stamina DRAIN multiplier per state (+15 % light, +30 % heavy, +70 % overloaded).
@export var encumbrance_drain_light: float = 1.15
@export var encumbrance_drain_heavy: float = 1.3
@export var encumbrance_drain_overloaded: float = 1.7
## Footstep radius multiplier per state.
@export var encumbrance_noise_heavy: float = 1.2
@export var encumbrance_noise_overloaded: float = 1.35

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
		# Searching a container: kneeling / rummaging, idle recovery.
		&"search": stamina_rate_idle,
		# Round 7: eating / drinking / sleeping recover like idle; resting
		# (sitting / lying awake) recovers faster.
		&"eat": stamina_rate_idle,
		&"sleep": stamina_rate_idle,
		&"rest": stamina_rate_idle * stamina_rest_multiplier,
	}


func stamina_thresholds() -> Dictionary:
	return {
		&"low": stamina_low_fraction,
		&"exhausted": {"enter": stamina_exhausted_enter, "exit": stamina_exhausted_exit},
	}
