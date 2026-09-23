class_name ZombieVisual
extends Node3D
## The zombie's look (Round 8.5): a procedural CharacterModel — a former
## townsperson in one of CharacterAssets.ZOMBIE_VARIANTS looks (grey-green skin,
## bloodied / torn clothes from the shared outfit pool) — animated from
## the zombie's state: z_idle sway, z_walk shamble (hunched, limping),
## z_chase (arms reaching), z_attack lunge (driven by the attack state's
## `lunge`), z_bang (doors), z_knockdown / z_getup, z_hit, z_death (kept
## by the corpse). Mood tell: the eyes (dark sockets when calm, dim yellow
## glow when alert, red when hostile, white flash on the bite).
##
## Cost: the owner calls animate() every physics tick; the AnimationPlayer
## (manual mode) only advances every _divider()-th tick (2 while hostile
## within 12 m of its target or in a one-shot clip, 3 otherwise, 6 for far
## "cheap movement" zombies), phase-staggered by the seed. Meshes / skin /
## clips are shared (CharacterAssets).

## Height of the hips while lying knocked down (tests / debug).
const KNOCKDOWN_HEIGHT := 0.3
const ANIM_DIVIDER_NEAR := 2
const ANIM_DIVIDER_CALM := 3
const ANIM_DIVIDER_FAR := 6
## Hostile zombies closer than this (squared, m²) to their target animate
## at the near rate.
const NEAR_DISTANCE_SQ := 144.0
## Speed above which the chase shamble replaces the walk shamble (m/s).
const CHASE_ANIM_SPEED := 1.2
## Portion of z_attack reached at full lunge (the rest is the grab).
const LUNGE_CLIP_END := 0.75
## Length of the red hit tint (seconds).
const HIT_TINT_SECONDS := 0.08

## Yaw the body wants to face (set by the owner); the mesh turns toward it
## at [turn_speed].
var wanted_facing: float = 0.0
var turn_speed: float = 4.0
## Forward lunge offset in metres (attack tell); 0 = none. Drives the
## z_attack windup.
var lunge: float = 0.0:
	set(v):
		if lunge == v:
			return
		var was := lunge
		lunge = v
		if model:
			model.position.z = -v
		_on_lunge(was, v)
var tint: StringName = &""
var knocked_down: bool = false
var dead: bool = false
var model: CharacterModel
## Look seed when the visual is not under a Zombie (a corpse restored from
## a save, Round 10); 0 = the parent zombie's ai_seed / the node path.
var seed_override: int = 0
var spray: CPUParticles3D
var _zombie: Zombie
var _flash_left: float = 0.0
var _hit_left: float = 0.0
var _aligned: bool = false
var _anim_counter: int = 0
var _anim_accum: float = 0.0
## A clip that must finish before locomotion takes over again.
var _one_shot: StringName = &""


func _ready() -> void:
	_zombie = get_parent() as Zombie
	var seed_value := _zombie.ai_seed if _zombie and _zombie.ai_seed != 0 else hash(String(get_path()))
	if seed_override != 0:
		seed_value = seed_override
	model = CharacterModel.new()
	model.name = "Model"
	model.appearance = CharacterAssets.of(get_tree()).zombie_appearance(seed_value)
	add_child(model)
	# Height per zombie, not per shared look (twins differ).
	model.scale = Vector3.ONE * CharacterAssets.height_for_seed(seed_value)
	set_tint(&"normal")
	model.play(&"z_idle", 0.0)
	# Desynchronise the crowd (hashed: spawner seeds are all odd).
	model.advance(float(posmod(hash(seed_value + 1), 97)) / 97.0 * 3.0)
	_anim_counter = anim_phase(seed_value)
	set_process(false)


## Pure: the LOD phase (0..ANIM_DIVIDER_FAR-1) for a seed, hashed so the
## all-odd spawner seeds still spread evenly over the phases.
static func anim_phase(seed_value: int) -> int:
	return posmod(hash(seed_value), ANIM_DIVIDER_FAR)


## True while something (turning, flashing) still needs per-tick updates.
func needs_update() -> bool:
	return not _aligned or _flash_left > 0.0 or _hit_left > 0.0


## Called by the owner each physics tick (only when needs_update()).
func update(delta: float) -> void:
	if not _aligned:
		var y := lerp_angle(rotation.y, wanted_facing, clampf(turn_speed * delta, 0.0, 1.0))
		if absf(angle_difference(y, wanted_facing)) < 0.002:
			y = wanted_facing
			_aligned = true
		rotation.y = y
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _hit_left <= 0.0:
			_apply_tint(tint)
	if _hit_left > 0.0:
		_hit_left -= delta
		if _hit_left <= 0.0:
			_clear_hit_flash()


## Called by the owner every physics tick: advances the animation at the
## LOD rate and picks the clip from the zombie's state.
func animate(delta: float) -> void:
	_anim_accum += delta
	_anim_counter += 1
	if _anim_counter < _divider():
		return
	_anim_counter = 0
	_choose_clip()
	model.advance(_anim_accum)
	_anim_accum = 0.0


func _divider() -> int:
	if _zombie == null:
		return ANIM_DIVIDER_NEAR
	if _one_shot != &"" or lunge > 0.0 or knocked_down:
		return ANIM_DIVIDER_NEAR
	if _zombie.hostile:
		# Full rate only close to its target (what the player looks at).
		var t := _zombie.target
		if t == null or _zombie.global_position.distance_squared_to(t.global_position) < NEAR_DISTANCE_SQ:
			return ANIM_DIVIDER_NEAR
		return ANIM_DIVIDER_CALM
	return ANIM_DIVIDER_FAR if _zombie.cheap_movement else ANIM_DIVIDER_CALM


## Pure: the looping clip for a zombie's state and speed, with its speed
## scale. [state] is a ZombieAI state id.
static func clip_for(state: StringName, speed: float) -> Array:
	if state == &"attack_door":
		return [&"z_bang", 1.0]
	if state == &"climb_window":
		return [&"climb", 0.6]
	if speed > 0.15:
		var clip := &"z_chase" if speed > CHASE_ANIM_SPEED else &"z_walk"
		return [clip, clampf(speed / float(CharacterAnimations.DESIGN_SPEED[clip]), 0.5, 1.6)]
	return [&"z_idle", 1.0]


func _choose_clip() -> void:
	if dead or knocked_down or lunge > 0.0:
		return
	if _one_shot != &"":
		if model.current == _one_shot and not model.is_finished():
			return
		_one_shot = &""
	var c := clip_for(_zombie.state() if _zombie else &"idle", _zombie.speed() if _zombie else 0.0)
	model.play(c[0], 0.25, c[1])


func _on_lunge(was: float, v: float) -> void:
	if model == null or dead or knocked_down:
		return
	if _zombie and _zombie.state() == &"attack_door":
		return
	if v > 0.0:
		var dist := _zombie.profile.lunge_distance if _zombie and _zombie.profile else 0.5
		model.play(&"z_attack", 0.1, 0.0)
		model.anim.seek(clampf(v / maxf(dist, 0.01), 0.0, 1.0) * LUNGE_CLIP_END, true)
	elif was > 0.0 and _one_shot != &"z_attack":
		# Windup interrupted (shove / stun): back to locomotion.
		_one_shot = &""
		_choose_clip()


## Clip currently playing (tests / debug).
func clip() -> StringName:
	return model.current if model else &""


func set_facing(yaw: float) -> void:
	if yaw != wanted_facing:
		wanted_facing = yaw
		_aligned = false


func snap_facing(yaw: float) -> void:
	wanted_facing = yaw
	rotation.y = yaw
	_aligned = true


## Direction the mesh actually points right now.
func facing_vector() -> Vector3:
	return BodyHelpers.facing_vector(rotation.y)


## Eye glow by AI mood: &"normal", &"alert", &"hostile", &"dead".
func set_tint(t: StringName) -> void:
	if tint == t:
		return
	tint = t
	if _flash_left <= 0.0 and _hit_left <= 0.0:
		_apply_tint(t)


func _apply_tint(t: StringName) -> void:
	if model:
		model.set_eye_material(CharacterAssets.of(get_tree()).eye_material(t))


## Eyes flash white for [seconds] and the lunge ends in the grab (the
## bite lands now).
func flash(seconds: float) -> void:
	_flash_left = seconds
	if _hit_left <= 0.0:
		_apply_tint(&"flash")
	if model and not dead and not knocked_down and model.current == &"z_attack":
		_one_shot = &"z_attack"
		model.set_speed(1.0 / maxf(seconds, 0.15) * (1.0 - LUNGE_CLIP_END))


## Took a hit: a short tint (vertex colours kept, pulled 30 % toward red
## for HIT_TINT_SECONDS), a blood spray, and the stagger clip (restarted
## on every hit).
func hit_flash(seconds: float) -> void:
	_hit_left = minf(seconds, HIT_TINT_SECONDS)
	if model == null:
		return
	model.set_body_material(CharacterAssets.of(get_tree()).hit_material())
	_spray()
	if not dead and not knocked_down and lunge <= 0.0:
		_one_shot = &"z_hit"
		model.play(&"z_hit", 0.05, 1.0, true)


func _spray() -> void:
	if spray == null:
		spray = CPUParticles3D.new()
		spray.name = "BloodSpray"
		spray.one_shot = true
		spray.emitting = false
		spray.amount = 14
		spray.lifetime = 0.45
		spray.explosiveness = 0.9
		spray.direction = Vector3(0, 0.6, 1)
		spray.spread = 40.0
		spray.initial_velocity_min = 1.2
		spray.initial_velocity_max = 2.6
		spray.gravity = Vector3(0, -9.8, 0)
		spray.scale_amount_min = 0.5
		spray.scale_amount_max = 1.0
		var quad := BoxMesh.new()
		quad.size = Vector3(0.04, 0.04, 0.04)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.35, 0.02, 0.02)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material = m
		spray.mesh = quad
		spray.position = Vector3(0, 1.3, 0)
		add_child(spray)
	spray.restart()


## Back to the plain body and the eyes of the current state.
func _clear_hit_flash() -> void:
	_hit_left = 0.0
	if model:
		model.set_body_material(null)
	_apply_tint(&"flash" if _flash_left > 0.0 else tint)


func is_hit_flashing() -> bool:
	return _hit_left > 0.0


## Fall on the back (knocked down) or get back up.
func set_knocked_down(v: bool) -> void:
	if knocked_down == v:
		return
	knocked_down = v
	lunge = 0.0
	if model == null:
		return
	if v:
		_one_shot = &""
		model.play(&"z_knockdown", 0.08)
	else:
		_one_shot = &"z_getup"
		model.play(&"z_getup", 0.05)


## True once the current pose lies on the ground (hips rotated flat).
func is_lying() -> bool:
	if model == null or model.skeleton == null:
		return false
	var up := Basis(model.bone_pose_rotation(&"hips")) * Vector3.UP
	return absf(up.y) < 0.5


## The eyes' current material (mood tint).
func head_material() -> StandardMaterial3D:
	return model.eye_material() as StandardMaterial3D if model else null


## Death: fall face down; the corpse keeps the model and the final pose.
func collapse() -> void:
	# The AI leaves knocked_down (→ set_knocked_down(false)) before the
	# corpse adopts us, so also trust the pose.
	var was_down := knocked_down or is_lying()
	lunge = 0.0
	_flash_left = 0.0
	_clear_hit_flash()
	dead = true
	knocked_down = false
	_one_shot = &""
	set_tint(&"dead")
	_aligned = true
	if model and not was_down:
		model.play(&"z_death", 0.1)
	elif model:
		# Killed while lying on its back: it stays there (no stand-up-and-
		# fall pop); the knockdown clip finishes and holds.
		model.play(&"z_knockdown", 0.0, 1.0, true)
		model.finish()
	# Nobody calls animate() any more: finish the fall on our own.
	set_process(true)


## Round 10: a restored corpse lies in its final pose at once (no fall).
func collapse_now(on_back: bool = false) -> void:
	lunge = 0.0
	_flash_left = 0.0
	dead = true
	knocked_down = false
	_one_shot = &""
	set_tint(&"dead")
	_aligned = true
	if model:
		model.play(&"z_knockdown" if on_back else &"z_death", 0.0, 1.0, true)
		model.finish()
	set_process(false)


func _process(delta: float) -> void:
	if model == null or model.is_finished():
		set_process(false)
		return
	model.advance(delta)
