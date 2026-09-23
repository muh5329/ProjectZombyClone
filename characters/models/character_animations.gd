class_name CharacterAnimations
extends RefCounted
## Procedural animation clips for the HumanoidBuilder skeleton, built in
## code into one AnimationLibrary shared by every CharacterModel (held by
## CharacterAssets). Every clip keys every bone (rotation) plus the hips
## position, so cross-fades never leave a bone behind.
##
## Poses are {bone: Vector3 euler degrees, &"root": Vector3 hips offset}.
## Conventions (parent-aligned bone space): +X swings an arm / leg forward,
## -X on a shin bends the knee, +X on a forearm bends the elbow, -X on the
## spine / chest leans forward, +Y twists left.
##
## Human: idle, walk, jog, sprint, sneak, sneak_idle, windup_* / strike_*
## (2h, 1h, punch, shove), climb, eat, search, bandage, sit, sleep, death,
## hit, hammer (Round 9: nailing planks, arm swinging at chest height),
## push (leaning into furniture). Zombie: z_idle, z_walk, z_chase, z_attack, z_bang, z_knockdown,
## z_getup, z_death, z_hit.

## Speed (m/s) at which a locomotion clip's feet do not slide.
const DESIGN_SPEED := {
	&"walk": 1.8, &"jog": 3.4, &"sprint": 5.6, &"sneak": 1.3,
	&"z_walk": 0.9, &"z_chase": 1.6,
}
const LOOPING: Array[StringName] = [&"idle", &"walk", &"jog", &"sprint", &"sneak", &"sneak_idle", &"eat",
	&"search", &"bandage", &"sit", &"sleep", &"hammer", &"push", &"z_idle", &"z_walk", &"z_chase", &"z_bang"]
const ROOT := &"root"
const KEYS_PER_CYCLE := 8


static func build_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	var clips := {
		&"idle": _cycle(3.0, _idle),
		&"walk": _cycle(1.0, _walk.bind(1.0)),
		&"jog": _cycle(0.7, _jog),
		&"sprint": _cycle(0.55, _sprint),
		&"sneak": _cycle(1.1, _sneak),
		&"sneak_idle": _cycle(2.0, func(p: float) -> Dictionary: return _sneak_pose(p, 0.0)),
		&"windup_2h": _keys(1.0, [[0.0, _ready_2h()], [1.0, _windup_2h()]]),
		&"strike_2h": _keys(1.0, [[0.0, _windup_2h()], [0.55, _strike_2h(0.6)], [1.0, _strike_2h(1.0)]]),
		&"windup_1h": _keys(1.0, [[0.0, {}], [1.0, _windup_1h()]]),
		&"strike_1h": _keys(1.0, [[0.0, _windup_1h()], [0.6, _strike_1h()], [1.0, _strike_1h()]]),
		&"windup_punch": _keys(1.0, [[0.0, {}], [1.0, _windup_punch()]]),
		&"strike_punch": _keys(1.0, [[0.0, _windup_punch()], [0.5, _strike_punch()], [1.0, _strike_punch()]]),
		&"windup_shove": _keys(1.0, [[0.0, {}], [1.0, _windup_shove()]]),
		&"strike_shove": _keys(1.0, [[0.0, _windup_shove()], [0.5, _strike_shove()], [1.0, _strike_shove()]]),
		&"climb": _keys(1.0, [[0.0, {}], [0.3, _climb_a()], [0.7, _climb_b()], [1.0, {}]]),
		&"eat": _cycle(1.6, _eat),
		&"search": _cycle(1.2, _search),
		&"bandage": _cycle(1.0, _bandage),
		&"hammer": _cycle(0.5, _hammer),
		&"push": _cycle(1.0, _push),
		&"sit": _cycle(3.0, _sit),
		&"sleep": _cycle(4.0, _sleep),
		&"death": _keys(1.2, [[0.0, {}], [0.35, _buckle(8.0)], [0.8, _falling_back()], [1.2, _lying_back(true)]]),
		&"hit": _keys(0.35, [[0.0, {}], [0.1, _flinch()], [0.35, {}]]),
		&"z_idle": _cycle(3.2, _z_idle),
		&"z_walk": _cycle(1.4, _z_walk),
		&"z_chase": _cycle(1.0, _z_chase),
		&"z_attack": _keys(1.0, [[0.0, _z_chase(0.0)], [0.75, _z_lunge()], [1.0, _z_grab()]]),
		&"z_bang": _cycle(0.9, _z_bang),
		&"z_knockdown": _keys(0.6, [[0.0, _z_chase(0.0)], [0.25, _falling_back()], [0.6, _lying_back(false)]]),
		&"z_getup": _keys(0.9, [[0.0, _lying_back(false)], [0.35, _z_sit_up()], [0.65, _z_kneel()], [0.9, _z_idle(0.0)]]),
		&"z_death": _keys(1.0, [[0.0, _z_chase(0.0)], [0.35, _buckle(-25.0)], [0.7, _falling_front()], [1.0, _lying_front()]]),
		&"z_hit": _keys(0.4, [[0.0, _z_idle(0.0)], [0.12, _z_stagger()], [0.4, _z_idle(0.0)]]),
	}
	for n: StringName in clips:
		var a: Animation = clips[n]
		if n in LOOPING:
			a.loop_mode = Animation.LOOP_LINEAR
		lib.add_animation(n, a)
	return lib


## Clip from explicit keys [[time, pose], …] (length = [length] s).
static func _keys(length: float, keys: Array) -> Animation:
	var a := Animation.new()
	a.length = length
	var tracks := {}
	for bone in HumanoidBuilder.BONE_NAMES:
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, NodePath("Skeleton3D:%s" % bone))
		tracks[bone] = t
	var root_track := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(root_track, NodePath("Skeleton3D:hips"))
	var rest := HumanoidBuilder.rest_position(&"hips")
	for k in keys:
		var time: float = k[0]
		var pose: Dictionary = k[1]
		for bone in HumanoidBuilder.BONE_NAMES:
			var e: Vector3 = pose.get(bone, Vector3.ZERO)
			var q := Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
			a.rotation_track_insert_key(tracks[bone], time, q)
		a.position_track_insert_key(root_track, time, rest + pose.get(ROOT, Vector3.ZERO))
	return a


## Looping clip sampled from [fn(phase 0..1) -> pose].
static func _cycle(length: float, fn: Callable) -> Animation:
	var keys := []
	for i in KEYS_PER_CYCLE + 1:
		var p := float(i) / KEYS_PER_CYCLE
		keys.append([p * length, fn.call(fmod(p, 1.0))])
	return _keys(length, keys)


# --- Human locomotion -----------------------------------------------------------

static func _legs(pose: Dictionary, p: float, thigh_amp: float, knee_amp: float, knee_base: float) -> void:
	var s := sin(TAU * p)
	var c := cos(TAU * p)
	pose[&"thigh_l"] = Vector3(thigh_amp * s, 0, 0)
	pose[&"thigh_r"] = Vector3(-thigh_amp * s, 0, 0)
	pose[&"shin_l"] = Vector3(-knee_base - knee_amp * maxf(0.0, c), 0, 0)
	pose[&"shin_r"] = Vector3(-knee_base - knee_amp * maxf(0.0, -c), 0, 0)
	pose[&"foot_l"] = Vector3(-8.0 * s, 0, 0)
	pose[&"foot_r"] = Vector3(8.0 * s, 0, 0)


static func _arms(pose: Dictionary, p: float, amp: float, elbow: float, spread: float = 4.0) -> void:
	var s := sin(TAU * p)
	pose[&"upperarm_l"] = Vector3(-amp * s, 0, -spread)
	pose[&"upperarm_r"] = Vector3(amp * s, 0, spread)
	pose[&"forearm_l"] = Vector3(elbow + maxf(0.0, -s) * elbow * 0.4, 0, 0)
	pose[&"forearm_r"] = Vector3(elbow + maxf(0.0, s) * elbow * 0.4, 0, 0)


static func _idle(p: float) -> Dictionary:
	var b := sin(TAU * p)
	return {
		&"chest": Vector3(1.5 * b, 0, 0), &"head": Vector3(-1.0 * b, 3.0 * sin(TAU * p * 0.5 + 0.3), 0),
		&"upperarm_l": Vector3(2.0 * b, 0, -4), &"upperarm_r": Vector3(-2.0 * b, 0, 4),
		&"forearm_l": Vector3(8, 0, 0), &"forearm_r": Vector3(8, 0, 0),
		ROOT: Vector3(0, 0.004 * b, 0),
	}


static func _walk(p: float, amp: float) -> Dictionary:
	var pose := {}
	_legs(pose, p, 24.0 * amp, 32.0, 4.0)
	_arms(pose, p, 18.0 * amp, 10.0)
	pose[&"chest"] = Vector3(0, 5.0 * sin(TAU * p), 0)
	pose[&"spine"] = Vector3(-2, 0, 0)
	pose[ROOT] = Vector3(0, -0.018 * absf(sin(TAU * p)), 0)
	return pose


static func _jog(p: float) -> Dictionary:
	var pose := {}
	_legs(pose, p, 36.0, 70.0, 10.0)
	_arms(pose, p, 34.0, 70.0, 8.0)
	pose[&"spine"] = Vector3(-8, 0, 0)
	pose[&"chest"] = Vector3(0, 8.0 * sin(TAU * p), 0)
	pose[ROOT] = Vector3(0, -0.035 + 0.03 * absf(cos(TAU * p)), 0)
	return pose


static func _sprint(p: float) -> Dictionary:
	var pose := {}
	_legs(pose, p, 50.0, 95.0, 12.0)
	_arms(pose, p, 55.0, 85.0, 8.0)
	pose[&"spine"] = Vector3(-15, 0, 0)
	pose[&"head"] = Vector3(10, 0, 0)
	pose[&"chest"] = Vector3(0, 10.0 * sin(TAU * p), 0)
	pose[ROOT] = Vector3(0, -0.05 + 0.04 * absf(cos(TAU * p)), 0)
	return pose


static func _sneak_pose(p: float, amp: float) -> Dictionary:
	var s := sin(TAU * p)
	var c := cos(TAU * p)
	return {
		&"spine": Vector3(-22, 0, 0), &"chest": Vector3(-8, 0, 0), &"head": Vector3(22, 0, 0),
		&"thigh_l": Vector3(45 + amp * s, 0, -4), &"thigh_r": Vector3(45 - amp * s, 0, 4),
		&"shin_l": Vector3(-80 - amp * maxf(0.0, c), 0, 0), &"shin_r": Vector3(-80 - amp * maxf(0.0, -c), 0, 0),
		&"foot_l": Vector3(35, 0, 0), &"foot_r": Vector3(35, 0, 0),
		&"upperarm_l": Vector3(25 - amp * 0.5 * s, 0, -8), &"upperarm_r": Vector3(25 + amp * 0.5 * s, 0, 8),
		&"forearm_l": Vector3(45, 0, 0), &"forearm_r": Vector3(45, 0, 0),
		ROOT: Vector3(0, -0.22 - 0.01 * absf(s), 0.05),
	}


static func _sneak(p: float) -> Dictionary:
	return _sneak_pose(p, 18.0)


# --- Human combat ----------------------------------------------------------------

static func _ready_2h() -> Dictionary:
	return {&"upperarm_l": Vector3(35, 0, 20), &"upperarm_r": Vector3(30, 0, -5), &"forearm_l": Vector3(40, 0, 0), &"forearm_r": Vector3(35, 0, 0)}


static func _windup_2h() -> Dictionary:
	# Bat cocked over the right shoulder, torso twisted right.
	return {
		&"spine": Vector3(0, -22, 0), &"chest": Vector3(0, -30, 0), &"head": Vector3(0, 40, 0),
		&"upperarm_l": Vector3(115, 0, 30), &"upperarm_r": Vector3(100, 0, -15),
		&"forearm_l": Vector3(60, 0, 0), &"forearm_r": Vector3(80, 0, 0),
		&"hand_l": Vector3(20, 0, 0), &"hand_r": Vector3(20, 0, 0),
		&"thigh_l": Vector3(12, 0, -6), &"thigh_r": Vector3(-10, 0, 6), &"shin_l": Vector3(-8, 0, 0),
	}


static func _strike_2h(t: float) -> Dictionary:
	var twist := lerpf(10.0, 32.0, t)
	return {
		&"spine": Vector3(-6, twist * 0.6, 0), &"chest": Vector3(-4, twist, 0), &"head": Vector3(0, -twist * 0.9, 0),
		&"upperarm_l": Vector3(lerpf(80, 55, t), 0, 35), &"upperarm_r": Vector3(lerpf(85, 60, t), 0, -30),
		&"forearm_l": Vector3(10, 0, 0), &"forearm_r": Vector3(15, 0, 0),
		&"hand_l": Vector3(-10, 0, 0), &"hand_r": Vector3(-10, 0, 0),
		&"thigh_l": Vector3(15, 0, -6), &"thigh_r": Vector3(-12, 0, 6), &"shin_r": Vector3(-10, 0, 0),
	}


static func _windup_1h() -> Dictionary:
	return {
		&"chest": Vector3(0, -18, 0), &"head": Vector3(0, 18, 0),
		&"upperarm_r": Vector3(150, 0, 10), &"forearm_r": Vector3(55, 0, 0), &"hand_r": Vector3(20, 0, 0),
		&"upperarm_l": Vector3(30, 0, -10), &"forearm_l": Vector3(40, 0, 0),
		&"thigh_l": Vector3(12, 0, 0), &"thigh_r": Vector3(-8, 0, 0),
	}


static func _strike_1h() -> Dictionary:
	return {
		&"spine": Vector3(-8, 0, 0), &"chest": Vector3(-6, 14, 0), &"head": Vector3(0, -12, 0),
		&"upperarm_r": Vector3(65, 0, -10), &"forearm_r": Vector3(5, 0, 0), &"hand_r": Vector3(-15, 0, 0),
		&"upperarm_l": Vector3(-15, 0, -12), &"forearm_l": Vector3(30, 0, 0),
		&"thigh_l": Vector3(15, 0, 0), &"thigh_r": Vector3(-10, 0, 0),
	}


static func _windup_punch() -> Dictionary:
	return {
		&"chest": Vector3(0, -20, 0), &"upperarm_r": Vector3(20, 0, 10), &"forearm_r": Vector3(110, 0, 0),
		&"upperarm_l": Vector3(45, 0, -10), &"forearm_l": Vector3(100, 0, 0),
	}


static func _strike_punch() -> Dictionary:
	return {
		&"chest": Vector3(-5, 18, 0), &"upperarm_r": Vector3(88, 0, -12), &"forearm_r": Vector3(8, 0, 0),
		&"upperarm_l": Vector3(30, 0, -10), &"forearm_l": Vector3(105, 0, 0), &"thigh_l": Vector3(12, 0, 0),
	}


static func _windup_shove() -> Dictionary:
	return {
		&"spine": Vector3(4, 0, 0), &"upperarm_l": Vector3(45, 0, 10), &"upperarm_r": Vector3(45, 0, -10),
		&"forearm_l": Vector3(100, 0, 0), &"forearm_r": Vector3(100, 0, 0),
	}


static func _strike_shove() -> Dictionary:
	return {
		&"spine": Vector3(-14, 0, 0), &"upperarm_l": Vector3(88, 0, 12), &"upperarm_r": Vector3(88, 0, -12),
		&"forearm_l": Vector3(10, 0, 0), &"forearm_r": Vector3(10, 0, 0), &"hand_l": Vector3(-50, 0, 0),
		&"hand_r": Vector3(-50, 0, 0), &"thigh_l": Vector3(25, 0, 0), &"thigh_r": Vector3(-15, 0, 0),
		ROOT: Vector3(0, -0.03, -0.08),
	}


static func _flinch() -> Dictionary:
	return {
		&"spine": Vector3(10, 0, 0), &"chest": Vector3(8, 0, 6), &"head": Vector3(15, 0, -8),
		&"upperarm_l": Vector3(30, 0, -25), &"upperarm_r": Vector3(35, 0, 25),
		&"forearm_l": Vector3(70, 0, 0), &"forearm_r": Vector3(70, 0, 0), ROOT: Vector3(0, -0.02, 0.04),
	}


# --- Human busy actions ------------------------------------------------------------

static func _climb_a() -> Dictionary:
	return {
		&"spine": Vector3(-30, 0, 0), &"upperarm_l": Vector3(70, 0, 0), &"upperarm_r": Vector3(70, 0, 0),
		&"forearm_l": Vector3(30, 0, 0), &"forearm_r": Vector3(30, 0, 0),
		&"thigh_r": Vector3(95, 0, 10), &"shin_r": Vector3(-100, 0, 0), &"thigh_l": Vector3(-5, 0, 0),
		ROOT: Vector3(0, 0.05, 0),
	}


static func _climb_b() -> Dictionary:
	return {
		&"spine": Vector3(-20, 0, 0), &"upperarm_l": Vector3(40, 0, -10), &"upperarm_r": Vector3(40, 0, 10),
		&"forearm_l": Vector3(20, 0, 0), &"forearm_r": Vector3(20, 0, 0),
		&"thigh_l": Vector3(90, 0, -10), &"shin_l": Vector3(-100, 0, 0), &"thigh_r": Vector3(-10, 0, 0),
		ROOT: Vector3(0, 0.08, 0),
	}


static func _eat(p: float) -> Dictionary:
	var b := maxf(0.0, sin(TAU * p))
	return {
		&"head": Vector3(-6 + 6 * b, 0, 0),
		&"upperarm_r": Vector3(25 + 10 * b, 0, -25), &"forearm_r": Vector3(115 + 20 * b, 0, 0), &"hand_r": Vector3(10, 0, 0),
		&"upperarm_l": Vector3(20, 0, 15), &"forearm_l": Vector3(70, 0, 0),
		ROOT: Vector3(0, 0.003 * b, 0),
	}


static func _search(p: float) -> Dictionary:
	var s := sin(TAU * p)
	return {
		&"spine": Vector3(-28, 0, 0), &"chest": Vector3(-10, 6 * s, 0), &"head": Vector3(10, 0, 0),
		&"upperarm_l": Vector3(55 + 15 * s, 0, 8), &"upperarm_r": Vector3(55 - 15 * s, 0, -8),
		&"forearm_l": Vector3(30, 0, 0), &"forearm_r": Vector3(30, 0, 0),
		&"thigh_l": Vector3(20, 0, 0), &"thigh_r": Vector3(20, 0, 0), &"shin_l": Vector3(-35, 0, 0), &"shin_r": Vector3(-35, 0, 0),
		&"foot_l": Vector3(15, 0, 0), &"foot_r": Vector3(15, 0, 0),
		ROOT: Vector3(0, -0.07, 0.04),
	}


## Nailing: left hand holds the plank up, right arm hammers (raise →
## strike twice per second), body leaning in a little.
static func _hammer(p: float) -> Dictionary:
	var s := sin(TAU * p)
	var strike := maxf(0.0, s)
	return {
		&"spine": Vector3(-6, 0, 0), &"chest": Vector3(-4, -8 + 4 * s, 0), &"head": Vector3(-8, 0, 0),
		&"upperarm_l": Vector3(75, 0, 20), &"forearm_l": Vector3(55, 0, 0), &"hand_l": Vector3(0, 0, 0),
		&"upperarm_r": Vector3(55 + 45 * strike, 0, -12), &"forearm_r": Vector3(95 - 60 * strike, 0, 0),
		&"hand_r": Vector3(-20 + 40 * strike, 0, 0),
		&"thigh_l": Vector3(6, 0, 0), &"thigh_r": Vector3(-6, 0, 0),
		ROOT: Vector3(0, -0.01 * strike, 0),
	}


## Pushing furniture: leaning forward, both arms out, short steps.
static func _push(p: float) -> Dictionary:
	var pose := _walk(p, 0.5)
	pose[&"spine"] = Vector3(-22, 0, 0)
	pose[&"head"] = Vector3(12, 0, 0)
	pose[&"upperarm_l"] = Vector3(80, 0, 8)
	pose[&"upperarm_r"] = Vector3(80, 0, -8)
	pose[&"forearm_l"] = Vector3(15, 0, 0)
	pose[&"forearm_r"] = Vector3(15, 0, 0)
	return pose


static func _bandage(p: float) -> Dictionary:
	var s := sin(TAU * p)
	var pose := _sneak_pose(0.0, 0.0)
	pose[&"upperarm_l"] = Vector3(40 + 10 * s, 0, 15)
	pose[&"upperarm_r"] = Vector3(40 - 10 * s, 0, -15)
	pose[&"forearm_l"] = Vector3(75, 0, 0)
	pose[&"forearm_r"] = Vector3(75, 0, 0)
	pose[&"head"] = Vector3(35, 0, 0)
	return pose


static func _sit(p: float) -> Dictionary:
	var b := sin(TAU * p)
	return {
		&"spine": Vector3(8, 0, 0), &"chest": Vector3(1.5 * b, 0, 0),
		&"thigh_l": Vector3(88, 0, -4), &"thigh_r": Vector3(88, 0, 4), &"shin_l": Vector3(-88, 0, 0), &"shin_r": Vector3(-88, 0, 0),
		&"upperarm_l": Vector3(20, 0, -6), &"upperarm_r": Vector3(20, 0, 6), &"forearm_l": Vector3(50, 0, 0), &"forearm_r": Vector3(50, 0, 0),
		ROOT: Vector3(0, -0.45, 0.1),
	}


static func _sleep(p: float) -> Dictionary:
	var pose := _lying_back(false)
	pose[&"chest"] = Vector3(2.0 * sin(TAU * p), 0, 0)
	pose[&"head"] = Vector3(0, 25, 0)
	pose[&"upperarm_l"] = Vector3(0, 0, -8)
	pose[&"upperarm_r"] = Vector3(10, 0, 20)
	pose[&"forearm_r"] = Vector3(60, 0, 0)
	return pose


# --- Falls (shared) -----------------------------------------------------------------

static func _buckle(lean: float) -> Dictionary:
	return {
		&"spine": Vector3(lean, 0, 0), &"head": Vector3(lean * 0.5, 0, 10),
		&"thigh_l": Vector3(50, 0, -5), &"thigh_r": Vector3(35, 0, 5), &"shin_l": Vector3(-90, 0, 0), &"shin_r": Vector3(-70, 0, 0),
		&"upperarm_l": Vector3(20, 0, -30), &"upperarm_r": Vector3(25, 0, 35), &"forearm_l": Vector3(40, 0, 0), &"forearm_r": Vector3(30, 0, 0),
		ROOT: Vector3(0, -0.32, 0.05),
	}


static func _falling_back() -> Dictionary:
	return {
		&"hips": Vector3(55, 0, 0), &"spine": Vector3(10, 0, 0), &"head": Vector3(-20, 0, 0),
		&"thigh_l": Vector3(60, 0, -5), &"thigh_r": Vector3(45, 0, 5), &"shin_l": Vector3(-60, 0, 0), &"shin_r": Vector3(-40, 0, 0),
		&"upperarm_l": Vector3(60, 0, -40), &"upperarm_r": Vector3(70, 0, 40), &"forearm_l": Vector3(30, 0, 0), &"forearm_r": Vector3(30, 0, 0),
		ROOT: Vector3(0, -0.55, 0.25),
	}


## On the back (face up), head toward +Z. [spread] = limp death pose.
static func _lying_back(spread: bool) -> Dictionary:
	var a := 55.0 if spread else 25.0
	return {
		&"hips": Vector3(90, 0, 0), &"head": Vector3(0, 30 if spread else 0, 0),
		&"thigh_l": Vector3(8, 0, -10 if spread else -3), &"thigh_r": Vector3(15, 0, 12 if spread else 3),
		&"shin_l": Vector3(-6, 0, 0), &"shin_r": Vector3(-20, 0, 0), &"foot_l": Vector3(-30, 0, 0), &"foot_r": Vector3(-30, 0, 0),
		&"upperarm_l": Vector3(10, 0, -a), &"upperarm_r": Vector3(20, 0, a),
		&"forearm_l": Vector3(20, 0, 0), &"forearm_r": Vector3(40, 0, 0),
		ROOT: Vector3(0, -0.83, 0.0),
	}


static func _falling_front() -> Dictionary:
	return {
		&"hips": Vector3(-55, 0, 0), &"spine": Vector3(-15, 0, 0), &"head": Vector3(20, 0, 0),
		&"thigh_l": Vector3(20, 0, -5), &"thigh_r": Vector3(5, 0, 5), &"shin_l": Vector3(-50, 0, 0), &"shin_r": Vector3(-30, 0, 0),
		&"upperarm_l": Vector3(90, 0, -20), &"upperarm_r": Vector3(80, 0, 20), &"forearm_l": Vector3(20, 0, 0), &"forearm_r": Vector3(20, 0, 0),
		ROOT: Vector3(0, -0.55, -0.2),
	}


## Face down, head toward -Z, arms flung above the head.
static func _lying_front() -> Dictionary:
	return {
		&"hips": Vector3(-90, 0, 0), &"head": Vector3(10, 55, 0),
		&"thigh_l": Vector3(-5, 0, -12), &"thigh_r": Vector3(5, 0, 8), &"shin_l": Vector3(-25, 0, 0), &"shin_r": Vector3(-5, 0, 0),
		&"foot_l": Vector3(40, 0, 0), &"foot_r": Vector3(40, 0, 0),
		&"upperarm_l": Vector3(150, 0, -35), &"upperarm_r": Vector3(100, 0, 60),
		&"forearm_l": Vector3(20, 0, 0), &"forearm_r": Vector3(50, 0, 0),
		ROOT: Vector3(0, -0.83, 0.0),
	}


# --- Zombie -----------------------------------------------------------------------

static func _z_base() -> Dictionary:
	# Hunched (spine −25°), neck pushed back up so the face looks ahead,
	# head drooping to one side, one arm hanging forward, right foot turned
	# out 20°.
	return {
		&"spine": Vector3(-25, 0, 4), &"chest": Vector3(-6, 6, -3), &"neck": Vector3(15, 0, 0), &"head": Vector3(8, 6, 16),
		&"upperarm_l": Vector3(45, 0, -4), &"upperarm_r": Vector3(18, 0, 10),
		&"forearm_l": Vector3(15, 0, 0), &"forearm_r": Vector3(10, 0, 0), &"hand_l": Vector3(10, 0, 0), &"hand_r": Vector3(5, 0, 0),
		&"thigh_l": Vector3(8, 0, -3), &"thigh_r": Vector3(2, -10, 5), &"shin_l": Vector3(-14, 0, 0), &"shin_r": Vector3(-8, 0, 0),
		&"foot_r": Vector3(0, -20, 0),
		ROOT: Vector3(0, -0.05, 0.03),
	}


static func _z_idle(p: float) -> Dictionary:
	var pose := _z_base()
	var s := sin(TAU * p)
	pose[&"hips"] = Vector3(0, 0, 3.0 * s)
	pose[&"chest"] = (pose[&"chest"] as Vector3) + Vector3(0, 4.0 * s, -4.0 * s)
	pose[&"head"] = (pose[&"head"] as Vector3) + Vector3(0, 6.0 * sin(TAU * p + 1.0), 3.0 * s)
	pose[&"upperarm_l"] = (pose[&"upperarm_l"] as Vector3) + Vector3(6.0 * s, 0, 0)
	pose[&"upperarm_r"] = (pose[&"upperarm_r"] as Vector3) + Vector3(-5.0 * s, 0, 0)
	return pose


static func _z_walk(p: float) -> Dictionary:
	var pose := _z_base()
	var s := sin(TAU * p)
	var c := cos(TAU * p)
	# Left leg strides, right leg drags stiffly (limp) and stays turned out;
	# the body lurches sideways onto the good leg (stagger).
	pose[&"thigh_l"] = Vector3(6 + 26 * s, 0, -3)
	pose[&"shin_l"] = Vector3(-12 - 40 * maxf(0.0, c), 0, 0)
	pose[&"thigh_r"] = Vector3(0 - 12 * s, -10, 6)
	pose[&"shin_r"] = Vector3(-8, 0, 0)
	pose[&"foot_r"] = Vector3(-15, -20, 0)
	pose[&"hips"] = Vector3(0, 7 * s, 7 * s)
	pose[&"spine"] = Vector3(-25, 0, 4 - 5 * s)
	pose[&"upperarm_l"] = Vector3(55 + 6 * s, 0, 4)
	pose[&"forearm_l"] = Vector3(18, 0, 0)
	pose[&"upperarm_r"] = Vector3(35 - 12 * s, 0, 8)
	pose[&"forearm_r"] = Vector3(12, 0, 0)
	pose[ROOT] = Vector3(0.03 * s, -0.06 - 0.035 * maxf(0.0, -s), 0.03)
	return pose


static func _z_chase(p: float) -> Dictionary:
	var pose := _z_base()
	var s := sin(TAU * p)
	var c := cos(TAU * p)
	pose[&"spine"] = Vector3(-28, 0, 3 - 4 * s)
	pose[&"neck"] = Vector3(18, 0, 0)
	pose[&"head"] = Vector3(10, 0, 12)
	pose[&"thigh_l"] = Vector3(10 + 34 * s, 0, -3)
	pose[&"shin_l"] = Vector3(-14 - 60 * maxf(0.0, c), 0, 0)
	pose[&"thigh_r"] = Vector3(4 - 24 * s, -10, 5)
	pose[&"shin_r"] = Vector3(-12 - 25 * maxf(0.0, -c), 0, 0)
	pose[&"foot_r"] = Vector3(0, -20, 0)
	pose[&"hips"] = Vector3(0, 7 * s, 5 * s)
	pose[&"upperarm_l"] = Vector3(68 + 8 * s, 0, 12)
	pose[&"upperarm_r"] = Vector3(58 - 8 * s, 0, -10)
	pose[&"forearm_l"] = Vector3(12, 0, 0)
	pose[&"forearm_r"] = Vector3(20, 0, 0)
	pose[&"hand_l"] = Vector3(-15, 0, 0)
	pose[&"hand_r"] = Vector3(-15, 0, 0)
	pose[ROOT] = Vector3(0.025 * s, -0.07 - 0.03 * absf(s), 0.03)
	return pose


static func _z_lunge() -> Dictionary:
	var pose := _z_chase(0.0)
	pose[&"spine"] = Vector3(-34, 0, 0)
	pose[&"chest"] = Vector3(-10, 0, 0)
	pose[&"head"] = Vector3(30, 0, 0)
	pose[&"upperarm_l"] = Vector3(100, 0, 18)
	pose[&"upperarm_r"] = Vector3(100, 0, -18)
	pose[&"forearm_l"] = Vector3(5, 0, 0)
	pose[&"forearm_r"] = Vector3(5, 0, 0)
	pose[&"thigh_l"] = Vector3(38, 0, -3)
	pose[&"shin_l"] = Vector3(-45, 0, 0)
	pose[&"thigh_r"] = Vector3(-22, 0, 5)
	pose[ROOT] = Vector3(0, -0.1, -0.12)
	return pose


static func _z_grab() -> Dictionary:
	var pose := _z_lunge()
	pose[&"upperarm_l"] = Vector3(80, 0, 30)
	pose[&"upperarm_r"] = Vector3(80, 0, -30)
	pose[&"forearm_l"] = Vector3(70, 0, 0)
	pose[&"forearm_r"] = Vector3(70, 0, 0)
	pose[&"head"] = Vector3(10, 0, 0)
	return pose


static func _z_bang(p: float) -> Dictionary:
	var pose := _z_base()
	var s := sin(TAU * p)
	pose[&"spine"] = Vector3(-8, 0, 0)
	pose[&"upperarm_l"] = Vector3(105 + 35 * s, 0, 10)
	pose[&"upperarm_r"] = Vector3(105 - 35 * s, 0, -10)
	pose[&"forearm_l"] = Vector3(30 + 20 * maxf(0.0, s), 0, 0)
	pose[&"forearm_r"] = Vector3(30 + 20 * maxf(0.0, -s), 0, 0)
	return pose


static func _z_sit_up() -> Dictionary:
	return {
		&"hips": Vector3(30, 0, 0), &"spine": Vector3(-35, 0, 0), &"chest": Vector3(-20, 0, 0),
		&"thigh_l": Vector3(60, 0, -8), &"thigh_r": Vector3(30, 0, 8), &"shin_l": Vector3(-100, 0, 0), &"shin_r": Vector3(-40, 0, 0),
		&"upperarm_l": Vector3(-20, 0, -20), &"upperarm_r": Vector3(-25, 0, 20),
		ROOT: Vector3(0, -0.68, 0.1),
	}


static func _z_kneel() -> Dictionary:
	return {
		&"spine": Vector3(-35, 0, 0), &"head": Vector3(30, 0, 0),
		&"thigh_l": Vector3(80, 0, -5), &"thigh_r": Vector3(-5, 0, 5), &"shin_l": Vector3(-90, 0, 0), &"shin_r": Vector3(-100, 0, 0),
		&"foot_r": Vector3(40, 0, 0),
		&"upperarm_l": Vector3(40, 0, -10), &"upperarm_r": Vector3(30, 0, 10),
		ROOT: Vector3(0, -0.42, 0.05),
	}


static func _z_stagger() -> Dictionary:
	var pose := _z_base()
	pose[&"spine"] = Vector3(8, 0, -8)
	pose[&"chest"] = Vector3(10, -10, 0)
	pose[&"head"] = Vector3(-15, 0, -20)
	pose[&"upperarm_l"] = Vector3(40, 0, -40)
	pose[&"upperarm_r"] = Vector3(30, 0, 45)
	pose[ROOT] = Vector3(0, -0.04, 0.08)
	return pose
