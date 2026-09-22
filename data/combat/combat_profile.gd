class_name CombatProfile
extends Resource
## Tuning shared by every melee fighter (edit data/combat/combat_profile.tres).
## Per-weapon numbers live in WeaponData; pain effects in InjuryProfile.

@export_group("Charge")
## Damage multiplier for a tap → after [charge_seconds] of holding.
@export var charge_min: float = 0.6
@export var charge_max: float = 1.3
@export var charge_seconds: float = 1.0

@export_group("Stamina")
## Damage multiplier while exhausted / while stamina is "low".
@export var exhausted_damage_multiplier: float = 0.6
@export var low_stamina_damage_multiplier: float = 0.85

@export_group("Movement")
## Speed multiplier (modifier &"attack") during windup + active window.
@export var swing_speed_multiplier: float = 0.4
## Speed multiplier (modifier &"charge") while holding a charge.
@export var charge_speed_multiplier: float = 0.7

@export_group("Targets")
## Height of the target query centre and of the line-of-sight ray (chest:
## above window sills, below lintels).
@export var hit_height: float = 1.1
## Body radius assumed for targets (added to reach and to the arc).
@export var target_radius: float = 0.3
## Region names sent with a hit: head (head_hit_chance) or body.
@export var head_region: StringName = &"head"
@export var body_region: StringName = &"upper_torso"
## "N in reach" refresh rate while aiming.
@export var aim_refresh_hz: float = 10.0

@export_group("Noise")
## Sound intensity = noise_radius / this (clamped 0..1).
@export var noise_intensity_radius: float = 14.0
