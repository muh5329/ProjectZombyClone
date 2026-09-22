extends "res://tests/test_case.gd"
## Pure vision-cone maths of ZombieSenses.can_see() and the profile data.

const SensesScript = preload("res://zombies/zombie_senses.gd")

const RANGE := 14.0
const FOV := deg_to_rad(120.0)


func _see(to: Vector3, facing := Vector3.FORWARD, los := true, range_m := RANGE) -> bool:
	return SensesScript.can_see(Vector3.ZERO, to, facing, range_m, FOV, los)


func test_in_cone_and_range() -> void:
	check(_see(Vector3(0, 0, -5)), "straight ahead")
	check(_see(Vector3(0, 0, -13.9)), "just inside range")
	check(not _see(Vector3(0, 0, -14.1)), "just outside range")
	check(_see(Vector3(0, 3, -5)), "height ignored (flat distance)")
	check(not _see(Vector3(0.5, 0, 0)), "pure cone test has no proximity rule (that is the senses node)")


func test_cone_edges() -> void:
	# 120° fov => ±60°. 59° off-axis in, 61° out.
	var d := 6.0
	var a_in := deg_to_rad(59.0)
	var a_out := deg_to_rad(61.0)
	check(_see(Vector3(sin(a_in) * d, 0, -cos(a_in) * d)), "59° inside the cone")
	check(not _see(Vector3(sin(a_out) * d, 0, -cos(a_out) * d)), "61° outside the cone")
	check(not _see(Vector3(0, 0, 5)), "directly behind")
	check(_see(Vector3(5, 0, 0), Vector3.RIGHT), "facing right sees right")
	check(not _see(Vector3(-5, 0, 0), Vector3.RIGHT), "facing right does not see left")


func test_los_and_degenerate_inputs() -> void:
	check(not _see(Vector3(0, 0, -5), Vector3.FORWARD, false), "no line of sight")
	check(_see(Vector3(0, 0, -5), Vector3.ZERO), "zero facing = omnidirectional")
	check(_see(Vector3.ZERO), "coincident points")
	check(not _see(Vector3(0, 0, -5), Vector3.FORWARD, true, 0.0), "zero range sees nothing")


func test_mode_multipliers() -> void:
	check_near(SensesScript.range_multiplier_for_mode(MovementComponent.Mode.SNEAK), 0.5, 0.0001, "sneak halves")
	check_near(SensesScript.range_multiplier_for_mode(MovementComponent.Mode.SPRINT), 1.25, 0.0001, "sprint +25%")
	check_near(SensesScript.range_multiplier_for_mode(MovementComponent.Mode.JOG), 1.0, 0.0001, "jog normal")
	check_near(SensesScript.range_multiplier_for_mode(MovementComponent.Mode.WALK), 1.0, 0.0001, "walk normal")


func test_profile_resource_loads_with_expected_values() -> void:
	var p: ZombieProfile = load("res://data/zombies/zombie_basic.tres")
	check(p != null, "profile loads")
	check_near(p.shamble_speed, 0.9, 0.0001, "shamble")
	check_near(p.chase_speed, 1.6, 0.0001, "chase")
	check_lt(p.chase_speed, 3.4, "slower than a jogging human")
	check_lt(p.chase_speed, 3.4 * 0.6, "an exhausted jogger (2.04 m/s) still barely outruns a lunge")
	check_gt(p.chase_speed, 1.3, "but a sneaking human is caught")
	check_near(p.vision_range, 14.0, 0.0001, "vision range")
	check_near(p.vision_fov_degrees, 120.0, 0.0001, "fov")
	check_near(p.vision_fov_radians(), deg_to_rad(120.0), 0.0001, "fov radians")
	check_near(p.memory_seconds, 8.0, 0.0001, "memory")
	check_near(p.attack_range, 0.9, 0.0001, "attack range")
	check_near(p.attack_windup, 0.5, 0.0001, "windup")
	check_near(p.attack_cooldown, 1.5, 0.0001, "cooldown")
	check_near(p.attack_damage, 12.0, 0.0001, "damage")
	check_near(p.health, 60.0, 0.0001, "health")
	check_gt(p.head_hit_multiplier, 1.0, "head multiplier")
	check_gt(p.wander_radius, 0.0, "wander radius")
	check(p.idle_time_min <= p.idle_time_max, "idle range")
