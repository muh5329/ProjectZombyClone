class_name ZombieProfile
extends Resource
## Data-driven tuning for one kind of zombie. Edit the .tres, not the code.
## Every number the zombie AI uses lives here — no magic constants in code.
##
## Design intent (Project Zomboid shamblers): slower than a jogging human
## (jog 3.4 m/s) even when lunging, so a fresh survivor always escapes —
## but an exhausted one (×0.6 → 2.0 m/s) is only a little faster than a
## lunge and a group in the open is lethal if you stop.

@export_group("Movement")
## Wandering / investigating speed (m/s).
@export var shamble_speed: float = 0.9
## Chase speed once a target is in mind (m/s).
@export var chase_speed: float = 1.6
## Visual turn rate (rad/s). Zombies turn slowly.
@export var turn_speed: float = 4.0
@export var acceleration: float = 5.0
## Beyond this distance from the player, non-hostile zombies slide along
## the navmesh without collision ("cheap movement").
@export var cheap_distance: float = 8.0

@export_group("Senses")
@export var vision_range: float = 14.0
## Full field of view in degrees (120 = ±60°).
@export var vision_fov_degrees: float = 120.0
## Eye height above the feet (m).
@export var eye_height: float = 1.5
## Multiplier on incoming sound radii (1 = normal; deaf = 0).
@export var hearing_sensitivity: float = 1.0
## Sound radius multiplier when a wall / closed door lies between the ear
## and the sound (Round 8 replaces this with real propagation).
@export var hearing_wall_attenuation: float = 0.5
## Anything this close (with line of sight) is noticed regardless of facing.
@export var proximity_range: float = 1.5
## Seconds a lost target is still pursued to its last known position.
@export var memory_seconds: float = 8.0
## Perception checks per second while calm.
@export var sense_hz: float = 6.0
## Seconds between perception checks while chasing with the target in sight.
@export var chase_sense_interval: float = 0.5
## Sneaking / sprinting target detection range multipliers.
@export var sneak_range_multiplier: float = 0.5
@export var sprint_range_multiplier: float = 1.25

@export_group("Attack")
@export var attack_range: float = 0.9
@export var attack_windup: float = 0.5
@export var attack_cooldown: float = 1.5
@export var attack_damage: float = 12.0
## Extra reach tolerated at the moment of the hit.
@export var attack_hit_slack: float = 0.25
## Leaving this far beyond attack range during cooldown resumes the chase.
@export var attack_leash_slack: float = 0.6
## Visual dot required to land a hit (0.4 ≈ ±66°).
@export var attack_facing_dot: float = 0.4
## How far the visual lunges forward during the windup (m).
@export var lunge_distance: float = 0.25
## Seconds the head flashes white at the swing.
@export var swing_flash_seconds: float = 0.15
## At most this many zombies attack one target; the rest hold nearby.
@export var max_attackers: int = 4
## Distance the surplus zombies hold at (m).
@export var hold_distance: float = 1.4
## Surplus zombies also hold once they have been pushing into the crowd
## without moving for this long…
@export var hold_stuck_seconds: float = 0.5
## …and try again after this long.
@export var hold_recheck_seconds: float = 1.5
## Damage per bang against doors / breakables.
@export var door_damage: float = 8.0
## A breakable further than this is no longer "in the way".
@export var door_max_distance: float = 1.8
## Length of the ray that looks for a breakable ahead on the path (m).
@export var door_check_distance: float = 1.2

@export_group("Health")
@export var health: float = 60.0
@export var head_hit_multiplier: float = 3.0
## A single hit of at least this much damage stuns (Round 4 combat).
@export var stagger_damage: float = 20.0
@export var stun_seconds: float = 0.8

@export_group("Behaviour")
## AI ticks per second while hostile (chase / attack) and while calm.
@export var ai_hz_hostile: float = 20.0
@export var ai_hz_calm: float = 10.0
## Path re-computations per second.
@export var repath_hz: float = 2.0
## Wander destinations are picked within this radius of the spawn point.
@export var wander_radius: float = 10.0
@export var wander_timeout: float = 25.0
## Seconds of wanting to move without moving before giving up.
@export var wander_stuck_seconds: float = 1.5
@export var idle_time_min: float = 2.0
@export var idle_time_max: float = 8.0
@export var investigate_timeout: float = 40.0
@export var investigate_arrive_distance: float = 1.0
@export var investigate_stuck_seconds: float = 2.0
@export var search_time_min: float = 4.0
@export var search_time_max: float = 6.0
@export var search_turn_period_min: float = 0.9
@export var search_turn_period_max: float = 1.6
@export var search_walk_chance: float = 0.35
@export var search_walk_radius: float = 2.0
@export var search_stuck_seconds: float = 1.0
## Within this distance of the last known position, a lost target is
## searched for on the spot instead of walked to.
@export var lost_near_distance: float = 1.5


func vision_fov_radians() -> float:
	return deg_to_rad(vision_fov_degrees)
