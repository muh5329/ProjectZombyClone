class_name WeaponData
extends ItemData
## Melee weapon definition. Every number the MeleeCombat component uses
## for a swing comes from here (fists and the shove are WeaponData too).
##
## Timing: a swing lasts [swing_time] seconds: windup
## (swing_time × windup_fraction) → active window
## (swing_time × active_fraction, targets are resolved at its start and
## the arc is shown) → recovery (the rest). Stamina is charged when the
## swing starts.

@export_group("Damage")
@export var damage_min: float = 3.0
@export var damage_max: float = 5.0
## Chance per target of a critical hit (× crit_multiplier).
@export_range(0.0, 1.0) var crit_chance: float = 0.05
@export var crit_multiplier: float = 2.0
## Chance per target that the hit lands on the head (target applies its
## own head multiplier).
@export_range(0.0, 1.0) var head_hit_chance: float = 0.1

@export_group("Reach")
## Metres from the attacker's centre to the far edge of the arc.
@export var reach: float = 0.8
## Full arc angle in degrees (60 = ±30°).
@export var arc_degrees: float = 60.0
@export var max_targets: int = 1

@export_group("Timing")
@export var swing_time: float = 0.5
@export_range(0.05, 0.9) var windup_fraction: float = 0.35
@export_range(0.05, 0.9) var active_fraction: float = 0.2
@export var stamina_cost: float = 2.0

@export_group("Impact")
## Metres the target is pushed back.
@export var knockback: float = 0.2
@export_range(0.0, 1.0) var knockdown_chance: float = 0.0
## Knockdown chance against a target that is winding up an attack
## (< 0 = same as knockdown_chance).
@export var knockdown_chance_vs_windup: float = -1.0
## False: hits never stagger (stun) the target, whatever the damage
## (quick stabs: the knife).
@export var can_stagger: bool = true
## Shoves deal no damage and interrupt attacks.
@export var is_shove: bool = false

@export_group("Wear")
## Chance per swing that hits something to lose [condition_loss] points.
@export_range(0.0, 1.0) var condition_loss_chance: float = 0.0
@export var condition_loss: int = 1

@export_group("Noise")
## Radius (m) of the sound a hit makes (SoundManager melee_hit / shove;
## overrides the category radius).
@export var noise_radius: float = 6.0

@export_group("Handling")
## Needs both hands: equipped in the primary hand it also occupies the
## secondary hand (Equipment, Round 6).
@export var two_handed: bool = false


func windup_time() -> float:
	return swing_time * windup_fraction


func active_time() -> float:
	return swing_time * active_fraction


func recovery_time() -> float:
	return maxf(swing_time - windup_time() - active_time(), 0.0)


func arc_radians() -> float:
	return deg_to_rad(arc_degrees)


func knockdown_chance_against(winding_up: bool) -> float:
	if winding_up and knockdown_chance_vs_windup >= 0.0:
		return knockdown_chance_vs_windup
	return knockdown_chance
