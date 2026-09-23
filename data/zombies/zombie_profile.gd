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
## Multiplier on incoming sound radii (1 = normal; deaf = 0). Walls /
## doors / windows between ear and sound are handled by SoundManager.
@export var hearing_sensitivity: float = 1.0
## A heard sound at least this strong (SoundMath.perceived, 0..1) is
## "loud": investigated at chase speed. Fainter ones: the zombie turns,
## pauses [faint_turn_seconds], then shambles over.
@export var loud_sound_strength: float = 0.4
@export var faint_turn_seconds: float = 0.8
## An investigating zombie only switches to a sound at least as strong as
## the one it follows, which fades by this much per second.
@export var sound_priority_decay: float = 0.05
## Investigating zombies moan (SoundManager zombie_moan, 6 m) at most this
## often; neighbours that hear it head for the same spot (hordes form).
@export var moan_cooldown: float = 10.0
## A moan relayed this many times is not relayed again (0 = never moan).
@export var moan_max_hops: int = 2
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
@export var attack_range: float = 1.0
@export var attack_windup: float = 0.4
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
## Where a zombie's hit lands on a human (Injury.REGION_IDS → weight,
## sums to 1) and what kind of wound it makes (Injury.TYPE_IDS → weight).
@export var attack_region_weights: Dictionary = {
	&"head": 0.05, &"neck": 0.1, &"upper_torso": 0.2, &"lower_torso": 0.1,
	&"left_arm": 0.15, &"right_arm": 0.15, &"left_hand": 0.08, &"right_hand": 0.08,
	&"left_leg": 0.045, &"right_leg": 0.045,
}
@export var attack_type_weights: Dictionary = {&"scratch": 0.6, &"laceration": 0.28, &"bite": 0.12}
## Zombie wounds roll the injury type's infection chance.
@export var attack_infectious: bool = true
## Damage per bang against doors / breakables.
@export var door_damage: float = 8.0
## A breakable further than this is no longer "in the way".
@export var door_max_distance: float = 1.8
## Length of the ray that looks for a breakable ahead on the path (m).
@export var door_check_distance: float = 1.2
## Round 9 — windows / barricades: seconds to climb through a window.
@export var window_climb_seconds: float = 1.6
## Round 10 (PZ): a zombie that climbed through a window tumbles in and
## lies on the floor this long (knocked down: no bites, ×1.5 damage) —
## what makes holding a window a real defence. 0 = lands on its feet.
@export var window_land_down_seconds: float = 1.4
## A window on the path is "reached" within this distance of its link end.
@export var window_link_distance: float = 0.9
## Facing a barricaded opening, a zombie goes to another entry of the
## same building when that one scores at least this much better (m of
## path + BarricadeData.nav_cost_per_plank per plank)…
@export var detour_margin: float = 4.0
## …within this radius, and gives the detour up after this long.
@export var detour_search_radius: float = 14.0
@export var detour_seconds: float = 20.0
## A zombie waiting for a slot at a barricade queues this far from it,
## leaves the queue beyond queue_max_distance, and reconsiders its entry
## every queue_detour_min..max seconds (seeded).
@export var queue_distance: float = 1.6
@export var queue_max_distance: float = 3.5
@export var queue_detour_min: float = 3.0
@export var queue_detour_max: float = 5.0
## Stuck in a crowd this long (s), a zombie looks this far ahead for the
## barricade the crowd is at (and queues there).
@export var crowd_stuck_seconds: float = 0.4
@export var crowd_check_distance: float = 3.0

@export_group("Health")
@export var health: float = 60.0
@export var head_hit_multiplier: float = 3.0
## A single hit of at least this much damage stuns (Round 4 combat).
@export var stagger_damage: float = 16.0
@export var stun_seconds: float = 0.5
## No new stagger (hit or shove stun) within this long of the last one:
## it takes the hit but keeps coming (no stun-lock).
@export var stagger_immunity_seconds: float = 1.2
## Knocked down (by a weapon's knockdown roll or a shove): lies for this
## long, then gets up; damage taken while down is multiplied.
@export var knockdown_seconds: float = 2.5
@export var knockdown_damage_multiplier: float = 1.5
## Knockback displacement speed (m/s); the distance comes from the weapon.
@export var knockback_speed: float = 5.0
## A shove that does not knock down staggers for this long (and cancels
## an attack windup).
@export var shove_stun_seconds: float = 0.6
## Seconds the body flashes when hit.
@export var hit_flash_seconds: float = 0.2

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
## Round 8: sounds that are deliberate lures (the player's shout): the
## search after arriving lasts longer and widens.
@export var lure_search_categories: Array[StringName] = [&"shout"]
@export var lure_search_time_min: float = 8.0
@export var lure_search_time_max: float = 12.0
@export var lure_search_extra_radius: float = 4.0
## Within this distance of the last known position, a lost target is
## searched for on the spot instead of walked to.
@export var lost_near_distance: float = 1.5


func vision_fov_radians() -> float:
	return deg_to_rad(vision_fov_degrees)


# --- Registry (Round 10: saves name profiles by id, never by path) -------------------

const REGISTRY_DIR := "res://data/zombies"
static var _registry: Dictionary = {}


## Profiles shipped in data/zombies, by file name ("zombie_basic").
static func registry() -> Dictionary:
	if _registry.is_empty():
		var da := DirAccess.open(REGISTRY_DIR)
		if da != null:
			for f in da.get_files():
				var fname := f.trim_suffix(".remap")
				if fname.ends_with(".tres"):
					var p := load("%s/%s" % [REGISTRY_DIR, fname]) as ZombieProfile
					if p != null:
						_registry[fname.get_basename()] = p
	return _registry


static func by_id(id: String) -> ZombieProfile:
	return registry().get(id) as ZombieProfile


## The registry id of [p] ("" for a runtime / duplicated profile).
static func id_of(p: ZombieProfile) -> String:
	if p == null or not p.resource_path.begins_with(REGISTRY_DIR + "/"):
		return ""
	var id := p.resource_path.get_file().get_basename()
	return id if registry().has(id) else ""
