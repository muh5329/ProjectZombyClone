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
## + barricades (9: furniture pushed in front of a door, R9)
const MASK_ALIVE := (1 << 0) | (1 << 1) | (1 << 2) | (1 << 6) | (1 << 7) | (1 << 8)
const PHYSICS_HZ := 60.0
## Cheap movers step every other physics frame (double delta).
const CHEAP_MOVE_DIVIDER := 2

@export var profile: ZombieProfile
## Seed for this zombie's random decisions and tick phases (0 = random).
## The spawner sets it so runs are repeatable.
@export var ai_seed: int = 0
## Stable, unique id from the spawner ("Zombies/7"); keys the corpse's
## loot seed and save entry.
@export var spawn_id: String = ""

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
## Round 12: the PopulationDirector that folded this zombie back into data
## (it is out of the tree then, freed at the end of the frame).
var folded_by: Object = null
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
## Remaining knockback displacement (flat), applied at profile.knockback_speed.
var _knock_left: Vector3 = Vector3.ZERO
## Round 9 window climb: from → over (sill) → to in _climb_seconds.
var _climb_t: float = -1.0
var _climb_seconds: float = 1.6
var _climb_from: Vector3
var _climb_over: Vector3
var _climb_to: Vector3


## Hand-placed zombies (seed 0) get a deterministic seed from their node
## path (look, tick phases, AI randomness), before the children are ready.
func _enter_tree() -> void:
	if ai_seed == 0:
		ai_seed = hash(String(get_path())) | 1


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


## Freed without dying (despawn, scene change): give back the attack slot
## so the static registry does not keep the target "full" forever.
func _exit_tree() -> void:
	if ai and ai.has_attack_slot:
		ai.release_attack_slot()


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
	if cheap_veto > 0.0:
		cheap_veto -= delta
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
	if _climb_t >= 0.0:
		_step_climb(delta)
	elif _knock_left != Vector3.ZERO:
		_step_knockback(delta)
	elif not _settled or intent_direction.x != 0.0 or intent_direction.z != 0.0:
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
	visual.animate(delta)


## Seconds during which the AI may not switch cheap movement back on
## (set when a cheap step would have entered a building).
var cheap_veto: float = 0.0


## True when moving [a] → [b] goes from outside every building room to
## inside one (the bounding-circle early-out keeps this cheap).
func _enters_building(a: Vector3, b: Vector3) -> bool:
	var tree := get_tree()
	if not WorldQuery.is_inside_building(tree, b + Vector3.UP * 0.5, 0.3):
		return false
	return not WorldQuery.is_inside_building(tree, a + Vector3.UP * 0.5, 0.3)


## Movement step: MovementComponent computes the velocity; cheap movers
## integrate it directly, the others move_and_slide.
func _step_movement(delta: float) -> void:
	var wants_move := intent_direction.x != 0.0 or intent_direction.z != 0.0
	_settled = false
	movement.mode = intent_mode
	if cheap_movement:
		velocity.y = 0.0
		velocity = movement.compute_velocity(intent_direction, velocity, delta)
		var step := Vector3(velocity.x, 0.0, velocity.z) * delta
		# Round 12: a cheap mover has no collision — it must never slide
		# through a wall or a closed door into a building. A step that
		# enters a room from outside hands over to full physics (doors and
		# windows then block / get attacked as usual).
		if _enters_building(global_position, global_position + step):
			cheap_veto = 3.0
			cheap_movement = false
			velocity = Vector3.ZERO
			return
		global_position += step
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


# --- Window climbing (Round 9, ZombieStateClimbWindow) ------------------------

## Move over a sill: [from] → [over] → [to] in [seconds], no collision.
func start_climb(from: Vector3, over: Vector3, to: Vector3, seconds: float) -> void:
	cheap_movement = false
	_climb_from = from
	_climb_over = over
	_climb_to = to
	_climb_seconds = maxf(seconds, 0.05)
	_climb_t = 0.0
	_knock_left = Vector3.ZERO
	velocity = Vector3.ZERO
	intent_direction = Vector3.ZERO
	collision_mask = 0
	_settled = false


## Abort a climb; [back] = return to where it started.
func stop_climb(back: bool) -> void:
	if _climb_t < 0.0:
		return
	_climb_t = -1.0
	if back:
		global_position = _climb_from
	collision_mask = MASK_ALIVE


func is_climbing() -> bool:
	return _climb_t >= 0.0


## 0..1 while climbing (1 when not).
func climb_progress() -> float:
	return clampf(_climb_t / _climb_seconds, 0.0, 1.0) if _climb_t >= 0.0 else 1.0


func _step_climb(delta: float) -> void:
	_climb_t += delta
	var f := clampf(_climb_t / _climb_seconds, 0.0, 1.0)
	if f < 0.5:
		global_position = _climb_from.lerp(_climb_over, smoothstep(0.0, 1.0, f * 2.0))
	else:
		global_position = _climb_over.lerp(_climb_to, smoothstep(0.0, 1.0, (f - 0.5) * 2.0))
	if f >= 1.0:
		_climb_t = -1.0
		collision_mask = MASK_ALIVE
		velocity = Vector3.ZERO


# --- Damage / death ---------------------------------------------------------

## info (all optional): region (&"head" applies profile.head_hit_multiplier),
## knockback_dir (Vector3) + knockback (m), knockdown (bool).
## Damage taken while knocked down is multiplied by
## profile.knockdown_damage_multiplier. A hit of at least
## profile.stagger_damage stuns; a hit from a creature makes it the target.
## Returns {ok, health, dead}; ok is false for no-op damage.
func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> Dictionary:
	if dead:
		return {"ok": false, "reason": "Already dead", "health": 0.0}
	if amount <= 0.0:
		return {"ok": false, "reason": "No effect", "health": health()}
	var dmg := amount
	if info.get("region", &"") == &"head":
		dmg *= profile.head_hit_multiplier
	if is_knocked_down():
		dmg *= profile.knockdown_damage_multiplier
	stats.modify(HEALTH, -dmg)
	var hp := stats.get_value(HEALTH)
	if hp <= 0.0:
		die(source)
		return {"ok": true, "health": 0.0, "dead": true, "damage": dmg}
	cheap_movement = false
	visual.hit_flash(profile.hit_flash_seconds)
	_apply_knockback(info)
	if ai:
		ai.on_damaged(source, dmg, info)
	return {"ok": true, "health": hp, "dead": false, "damage": dmg, "knocked_down": is_knocked_down()}


## A shove: no damage, cancels an attack windup, pushes back and either
## knocks down (info.knockdown) or staggers for profile.shove_stun_seconds.
func receive_shove(source: Node = null, info: Dictionary = {}) -> Dictionary:
	if dead:
		return {"ok": false, "reason": "Already dead"}
	cheap_movement = false
	var was_winding_up := is_winding_up()
	_apply_knockback(info)
	if ai:
		ai.on_shoved(source, bool(info.get("knockdown", false)))
	return {"ok": true, "knocked_down": is_knocked_down(), "interrupted": was_winding_up}


## True during the windup of a bite (a shove is more likely to floor it).
func is_winding_up() -> bool:
	return ai != null and ai.is_winding_up()


func is_knocked_down() -> bool:
	return ai != null and ai.is_in(ZombieAI.S_KNOCKED_DOWN)


func _apply_knockback(info: Dictionary) -> void:
	var dist := float(info.get("knockback", 0.0))
	var dir: Vector3 = info.get("knockback_dir", Vector3.ZERO)
	dir.y = 0.0
	if dist <= 0.0 or dir.length_squared() < 0.0001 or is_knocked_down():
		return
	_knock_left = dir.normalized() * dist


## Slide the remaining knockback (collides with walls and bodies).
func _step_knockback(delta: float) -> void:
	var remaining := _knock_left.length()
	var step := minf(remaining, profile.knockback_speed * delta)
	var dir := _knock_left / remaining
	velocity = dir * (step / delta)
	move_and_slide()
	velocity = Vector3.ZERO
	_knock_left = Vector3.ZERO if remaining - step <= 0.001 else dir * (remaining - step)
	_settled = false


func health() -> float:
	return stats.get_value(HEALTH)


## Die: leave a ZombieCorpse (static, layer 4, collapsed visual) where the
## body stood, announce it and free this node at the end of the frame.
func die(p_killer: Node = null) -> ZombieCorpse:
	if dead:
		return corpse
	# Round 12: killed after the population director folded it back into
	# data (same frame, already out of the tree): the director removes the
	# member, counts the death and lays the corpse.
	if not is_inside_tree():
		dead = true
		if folded_by != null and is_instance_valid(folded_by):
			corpse = folded_by.call(&"on_folded_zombie_died", self, p_killer)
		return corpse
	dead = true
	target = null
	intent_direction = Vector3.ZERO
	velocity = Vector3.ZERO
	cheap_movement = false
	if ai:
		ai.on_death()
	if senses:
		senses.stop_listening()
	remove_from_group(&"zombie")
	corpse = ZombieCorpse.new()
	corpse.name = name + "Corpse"
	corpse.killer = p_killer
	corpse.look_seed = ai_seed
	corpse.yaw = visual.rotation.y
	# Stable id: the pockets' loot is seeded from it (and it keys the save).
	corpse.persist_id = "corpse/%s" % (spawn_id if spawn_id != "" else "%s@%d" % [name, get_instance_id()])
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


# --- Save (Round 10, WorldSnapshot spawn records) ----------------------------------------

## A living zombie as a spawn record: identity (spawn id + look seed),
## where it stands / faces, health, home and a SAFE state — calm states
## are kept; anything hostile (chase, attack, banging, stunned, knocked
## down, climbing) becomes "investigate the last known target position".
func save_record() -> Dictionary:
	var pos := global_position
	if is_climbing():
		pos = _climb_to  # never saved inside a wall
	var s := state()
	var target_pos: Variant = null
	var saved_state := "idle"
	match s:
		ZombieAI.S_IDLE:
			saved_state = "idle"
		ZombieAI.S_WANDER:
			saved_state = "wander"
		ZombieAI.S_INVESTIGATE, ZombieAI.S_SEARCH:
			saved_state = "investigate"
			target_pos = Saveable.vec3(ai.investigate_position)
		_:
			if ai.last_known_position != Vector3.ZERO:
				saved_state = "investigate"
				target_pos = Saveable.vec3(ai.last_known_position)
			elif ai.investigate_position != Vector3.ZERO:
				saved_state = "investigate"
				target_pos = Saveable.vec3(ai.investigate_position)
	var d := {
		"spawn_id": spawn_id, "seed": ai_seed,
		"position": Saveable.vec3(pos), "facing": movement.facing,
		"health": health(), "home": Saveable.vec3(home_position),
		"state": saved_state, "target": target_pos,
	}
	var pid := ZombieProfile.id_of(profile)
	if pid != "":
		d["profile"] = pid
	return d


## Apply a save_record() to a zombie that has just entered the tree
## (ZombieSpawner.restore_zombie sets seed / spawn id / position first).
func apply_record(d: Dictionary) -> void:
	stats.set_value(HEALTH, clampf(float(d.get("health", profile.health)), 1.0, profile.health))
	home_position = Saveable.to_vec3(d.get("home"), global_position)
	snap_facing(float(d.get("facing", 0.0)))
	match String(d.get("state", "idle")):
		"investigate":
			var t: Variant = d.get("target")
			if t != null:
				ai.investigate_quietly(Saveable.to_vec3(t))
				ai.change_to(ZombieAI.S_INVESTIGATE)
		"wander":
			ai.change_to(ZombieAI.S_WANDER)
