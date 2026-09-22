class_name Zombie
extends CharacterBody3D
## A shambler. NOT a Character (no stamina, no input modes); reuses
## MovementComponent for velocity/facing and StatsComponent for health.
## Behaviour lives in the AI child (ZombieAI + StateMachine), perception in
## the Senses child (ZombieSenses), the look in the Visual child
## (ZombieVisual); this node integrates them per physics tick, takes
## damage and dies (leaving a ZombieCorpse).
##
## Per-tick cost is kept low for hordes: one _physics_process per zombie
## drives Senses (profile.sense_hz, or chase_sense_interval while the
## target is in sight) and AI (ai_hz_hostile / ai_hz_calm), all staggered
## from the seeded ai_seed; a standing zombie does no movement work; a
## zombie farther than profile.cheap_distance from the player and not
## hostile slides along its navmesh path without move_and_slide and with
## its body out of the physics space ("cheap movement").
##
## Physics: layer 3 (zombies), mask world + player + zombies + doors +
## window panes. Group "zombie".

const HEALTH := &"health"
const LAYER_ZOMBIES := 1 << 2
## world (1) + player (2) + zombies (3) + doors (7) + window panes (8)
const MASK_ALIVE := (1 << 0) | (1 << 1) | (1 << 2) | (1 << 6) | (1 << 7)
const PHYSICS_HZ := 60.0
## Cheap movers step every other physics frame (double delta).
const CHEAP_MOVE_DIVIDER := 2

@export var profile: ZombieProfile
## Seed for this zombie's random decisions and tick phases (0 = random).
## The spawner sets it so runs are repeatable.
@export var ai_seed: int = 0

@onready var movement: MovementComponent = $Movement
@onready var stats: StatsComponent = $Stats
@onready var senses: ZombieSenses = $Senses
@onready var ai: ZombieAI = $AI
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var visual: ZombieVisual = $Visual
@onready var collision: CollisionShape3D = $Collision

var intent_direction: Vector3 = Vector3.ZERO
var intent_mode: MovementComponent.Mode = MovementComponent.Mode.WALK
## Current pursued target (set by the AI). May be null.
var target: Node3D = null
## Where this zombie was spawned; wandering stays around it.
var home_position: Vector3 = Vector3.ZERO
var dead: bool = false
## The corpse left behind (valid after die()).
var corpse: ZombieCorpse = null
## True while cheap (collision-free) movement is in use. Decided by the AI.
## The body leaves the physics space meanwhile; it is re-added (and
## depenetrated by move_and_slide) when full physics resumes.
var cheap_movement: bool = false:
	set(v):
		if cheap_movement == v:
			return
		cheap_movement = v
		if not is_inside_tree():
			return
		PhysicsServer3D.body_set_space(get_rid(), RID() if v else get_world_3d().space)
## True while chasing / attacking: full-rate AI. Decided by the AI.
var hostile: bool = false:
	set(v):
		hostile = v
		_ai_divider = _divider_for(profile.ai_hz_hostile if v else profile.ai_hz_calm)

## True when standing still with nothing to do: movement code is skipped.
var _settled: bool = false
var _ai_accum: float = 0.0
var _ai_counter: int = 0
var _ai_divider: int = 6
var _sense_accum: float = 0.0
var _move_accum: float = 0.0
var _move_counter: int = 0


func _ready() -> void:
	add_to_group(&"zombie")
	if profile == null:
		profile = ZombieProfile.new()
	collision_layer = LAYER_ZOMBIES
	collision_mask = MASK_ALIVE
	movement.speed_sneak = profile.shamble_speed
	movement.speed_walk = profile.shamble_speed
	movement.speed_jog = profile.chase_speed
	movement.speed_sprint = profile.chase_speed
	movement.turn_speed = profile.turn_speed
	movement.acceleration = profile.acceleration
	movement.deceleration = profile.acceleration * 2.0
	visual.turn_speed = profile.turn_speed
	stats.character = self
	stats.add_stat(HEALTH, profile.health)
	home_position = global_position
	# Children are ready before the parent's @onready vars exist, so the
	# components are wired explicitly here.
	senses.setup(self)
	ai.setup(self)
	hostile = false
	# Deterministic tick phases from the seed (not from instance ids).
	var phase := RandomNumberGenerator.new()
	phase.seed = ai_seed if ai_seed != 0 else randi()
	_ai_counter = phase.randi_range(0, _ai_divider - 1)
	_sense_accum = phase.randf() * senses.period()
	_move_counter = phase.randi_range(0, CHEAP_MOVE_DIVIDER - 1)


static func _divider_for(hz: float) -> int:
	return maxi(int(round(PHYSICS_HZ / maxf(hz, 0.1))), 1)


func set_intent(direction: Vector3, mode: MovementComponent.Mode) -> void:
	intent_direction = direction
	intent_mode = mode


func has_move_intent() -> bool:
	return BodyHelpers.has_move_intent(intent_direction)


func speed() -> float:
	return BodyHelpers.flat_speed(velocity)


func is_dead() -> bool:
	return dead


func eye_height() -> float:
	return profile.eye_height


func eye_position() -> Vector3:
	return global_position + Vector3.UP * profile.eye_height


## Logical facing (where the movement component wants the body to face).
func facing_vector() -> Vector3:
	return BodyHelpers.facing_vector(movement.facing)


## Where the visual actually points right now (turns at profile.turn_speed).
func visual_facing_vector() -> Vector3:
	return visual.facing_vector() if visual else facing_vector()


## Turn (logically) toward [point]; the visual catches up at turn_speed.
func face_toward(point: Vector3) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	face_yaw(BodyHelpers.yaw_for(d))


func face_yaw(yaw: float) -> void:
	movement.facing = yaw
	visual.set_facing(yaw)


## Snap the visual too (spawning / tests).
func snap_facing(yaw: float) -> void:
	movement.facing = yaw
	visual.snap_facing(yaw)


func _physics_process(delta: float) -> void:
	if dead:
		return
	_sense_accum += delta
	if _sense_accum >= senses.period():
		_sense_accum = 0.0
		senses.check()
	_ai_accum += delta
	_ai_counter += 1
	if _ai_counter >= _ai_divider:
		_ai_counter = 0
		ai.tick(_ai_accum)
		_ai_accum = 0.0
	if not _settled or intent_direction.x != 0.0 or intent_direction.z != 0.0:
		if cheap_movement:
			_move_accum += delta
			_move_counter += 1
			if _move_counter >= CHEAP_MOVE_DIVIDER:
				_move_counter = 0
				_step_movement(_move_accum)
				_move_accum = 0.0
		else:
			_move_accum = 0.0
			_step_movement(delta)
	if visual.needs_update():
		visual.update(delta)


## Movement step: MovementComponent computes the velocity; cheap movers
## integrate it directly, the others move_and_slide.
func _step_movement(delta: float) -> void:
	var wants_move := intent_direction.x != 0.0 or intent_direction.z != 0.0
	_settled = false
	movement.mode = intent_mode
	if cheap_movement:
		velocity.y = 0.0
		velocity = movement.compute_velocity(intent_direction, velocity, delta)
		global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
	else:
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = 0.0
		velocity = movement.compute_velocity(intent_direction, velocity, delta)
		move_and_slide()
	if wants_move:
		visual.set_facing(movement.facing)
	elif velocity.x * velocity.x + velocity.z * velocity.z < 0.0004 and (cheap_movement or is_on_floor()):
		velocity = Vector3.ZERO
		_settled = true


# --- Damage / death ---------------------------------------------------------

## info.region == &"head" applies the profile's head multiplier. A hit of
## at least profile.stagger_damage stuns (Round 4 combat hooks in here).
## Returns {ok, health, dead}; ok is false for no-op damage.
func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> Dictionary:
	if dead:
		return {"ok": false, "reason": "Already dead", "health": 0.0}
	if amount <= 0.0:
		return {"ok": false, "reason": "No effect", "health": health()}
	var dmg := amount
	if info.get("region", &"") == &"head":
		dmg *= profile.head_hit_multiplier
	stats.modify(HEALTH, -dmg)
	var hp := stats.get_value(HEALTH)
	if hp <= 0.0:
		die(source)
		return {"ok": true, "health": 0.0, "dead": true}
	if ai:
		ai.on_damaged(source, dmg >= profile.stagger_damage)
	return {"ok": true, "health": hp, "dead": false}


func health() -> float:
	return stats.get_value(HEALTH)


## Die: leave a ZombieCorpse (static, layer 4, collapsed visual) where the
## body stood, announce it and free this node at the end of the frame.
func die(p_killer: Node = null) -> ZombieCorpse:
	if dead:
		return corpse
	dead = true
	target = null
	intent_direction = Vector3.ZERO
	velocity = Vector3.ZERO
	cheap_movement = false
	if ai:
		ai.on_death()
	if senses:
		senses.enabled = false
	remove_from_group(&"zombie")
	corpse = ZombieCorpse.new()
	corpse.name = name + "Corpse"
	corpse.killer = p_killer
	var parent := get_parent()
	if parent:
		parent.add_child(corpse)
		corpse.global_transform = Transform3D(Basis(Vector3.UP, visual.rotation.y), global_position)
		corpse.adopt_visual(visual)
	collision_layer = 0
	collision_mask = 0
	set_physics_process(false)
	EventBus.zombie_died.emit(self, p_killer)
	queue_free()
	return corpse


## Current AI state id (&"" before the AI is ready).
func state() -> StringName:
	return ai.state_id() if ai else &""
