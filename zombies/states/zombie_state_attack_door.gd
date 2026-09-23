class_name ZombieStateAttackDoor
extends ZombieState
## Bang on the breakable in the path (ai.blocking_obstacle: a closed
## door…) until it no longer blocks, then resume (chase if the target is
## remembered, else investigate). Same windup / cooldown rhythm and lunge
## tell as a normal attack. The obstacle announces its own bangs.
## Round 9: obstacles with attacker slots (BarricadeComponent: at most
## BarricadeData.max_attackers per opening) are claimed on entry. A zombie
## without a slot QUEUES: it keeps profile.queue_distance from the
## obstacle (steps back if closer), faces it, takes the first slot that
## frees up (then walks in to reach), and after a seeded
## profile.queue_detour_min..max seconds of waiting asks the EntryPlanner
## for a better opening of the building (detour). A slot holder farther
## than door_max_distance walks toward the obstacle first.

enum Phase { WINDUP, COOLDOWN }

var phase: Phase = Phase.WINDUP
var timer: float = 0.0
var hits: int = 0
## True while this zombie holds one of the obstacle's attacker slots (or
## the obstacle has no slots).
var has_slot: bool = false
var _slot_owner: Node = null
## Seconds left before a queued zombie reconsiders its entry.
var queue_left: float = 0.0


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	hits = 0
	has_slot = _claim()
	queue_left = ai.random_range(profile().queue_detour_min, profile().queue_detour_max)
	phase = Phase.WINDUP
	timer = profile().attack_windup
	if _obstacle_ok():
		zombie.face_toward(_obstacle_position())


func exit(_to: StringName) -> void:
	zombie.visual.lunge = 0.0
	_release()


func _claim() -> bool:
	var o := ai.blocking_obstacle
	if o == null or not is_instance_valid(o) or not o.has_method(&"claim_attacker"):
		return true
	if bool(o.call(&"claim_attacker", zombie)):
		_slot_owner = o
		return true
	return false


func _release() -> void:
	if _slot_owner != null and is_instance_valid(_slot_owner) and _slot_owner.has_method(&"release_attacker"):
		_slot_owner.call(&"release_attacker", zombie)
	_slot_owner = null
	has_slot = false


func _obstacle_ok() -> bool:
	var o := ai.blocking_obstacle
	return o != null and is_instance_valid(o) and o.is_inside_tree() and o.blocks_path()


func _obstacle_position() -> Vector3:
	var o := ai.blocking_obstacle
	if o.has_method(&"interaction_prompt_position"):
		return o.call(&"interaction_prompt_position")
	return o.global_position


func update(delta: float) -> StringName:
	if not _obstacle_ok():
		ai.blocking_obstacle = null
		return ai.after_obstacle_state()
	var at := _obstacle_position()
	var d := ai.distance_to(at)
	var reach := profile().door_max_distance
	if d > (reach if has_slot and hits > 0 else profile().queue_max_distance):
		ai.blocking_obstacle = null
		return ai.after_obstacle_state()
	zombie.face_toward(at)
	if ai.target_valid() and zombie.senses.visible_target != zombie.target:
		ai.memory_left -= delta
	if not has_slot:
		has_slot = _claim()
	if not has_slot:
		return _queue(at, d, delta)
	if d > reach:
		# Our turn, but still in the crowd's back row: walk in.
		zombie.visual.lunge = 0.0
		_step(at, 1.0)
		return &""
	ai.stop()
	timer -= delta
	match phase:
		Phase.WINDUP:
			var windup := profile().attack_windup
			zombie.visual.lunge = profile().lunge_distance * clampf(1.0 - timer / windup, 0.0, 1.0) if windup > 0.0 else 0.0
			if timer <= 0.0:
				zombie.visual.lunge = 0.0
				zombie.visual.flash(profile().swing_flash_seconds)
				ai.blocking_obstacle.call(&"take_damage", profile().door_damage, zombie)
				hits += 1
				EventBus.zombie_attacked.emit(zombie, ai.blocking_obstacle, true)
				phase = Phase.COOLDOWN
				timer = profile().attack_cooldown
		Phase.COOLDOWN:
			if timer <= 0.0:
				phase = Phase.WINDUP
				timer = profile().attack_windup
	return &""


## Waiting for a slot: hold queue_distance, reconsider the entry now and
## then (another opening may be free).
func _queue(at: Vector3, d: float, delta: float) -> StringName:
	zombie.visual.lunge = 0.0
	if d < profile().queue_distance - 0.2:
		_step(at, -1.0)
	else:
		ai.stop()
	queue_left -= delta
	if queue_left <= 0.0:
		queue_left = ai.random_range(profile().queue_detour_min, profile().queue_detour_max)
		if ai.consider_detour(ai.blocking_obstacle):
			ai.blocking_obstacle = null
			return ai.after_obstacle_state()
	return &""


## Walk straight toward (+1) / away from (-1) [at] (no path: a step).
func _step(at: Vector3, sign_dir: float) -> void:
	var dir := at - zombie.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		ai.stop()
		return
	zombie.set_intent(dir.normalized() * sign_dir, MovementComponent.Mode.WALK)
	if sign_dir < 0.0:
		zombie.face_toward(at)
