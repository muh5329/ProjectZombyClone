class_name ZombieStateChase
extends ZombieState
## Pursue the target at chase speed toward its last known position,
## re-pathing at repath_hz. Sight refreshes memory; out of sight the
## memory decays and the target is lost. In range with a clear line and a
## free attack slot → attack; slots full → hold at hold_distance (the
## crowd surrounds instead of stacking). A breakable in the path →
## attack_door. Unreachable targets: the path ends at the closest
## reachable point, where the zombie stands facing the target and keeps
## re-trying.

var holding: bool = false
var _hold_left: float = 0.0


func enter(_from: StringName) -> void:
	holding = false
	if ai.target_valid():
		ai.last_known_position = zombie.target.global_position
		ai.set_destination(ai.last_known_position)


func update(delta: float) -> StringName:
	if not ai.target_valid():
		return ZombieAI.S_LOST
	var in_sight := zombie.senses.visible_target == zombie.target
	if in_sight:
		# Snapshot from the last sense check, never the live position:
		# between checks the target may already be out of sight.
		ai.last_known_position = zombie.senses.last_seen_position
		ai.memory_left = profile().memory_seconds
	else:
		ai.memory_left -= delta
		if ai.memory_left <= 0.0:
			return ZombieAI.S_LOST
	var dist := ai.distance_to_target()
	if dist <= profile().attack_range and ai.has_attack_line():
		if ai.claim_attack_slot():
			return ZombieAI.S_ATTACK
	if in_sight and ai.attackers_on(zombie.target) >= profile().max_attackers \
			and (dist <= profile().hold_distance or ai.stuck_time >= profile().hold_stuck_seconds or holding):
		# Surrounded target: wait for a slot instead of pushing into the
		# crowd (cheaper, and the ring reads better than a blob).
		if not holding:
			holding = true
			_hold_left = profile().hold_recheck_seconds
			ai.stop()
			ai.clear_destination()
		zombie.face_toward(zombie.target.global_position)
		_hold_left -= delta
		if _hold_left > 0.0:
			return &""
		holding = false
	else:
		holding = false
	if ai.repath_due():
		ai.set_destination(ai.last_known_position)
		var obstacle := ai.breakable_ahead()
		if obstacle != null:
			ai.blocking_obstacle = obstacle
			return ZombieAI.S_ATTACK_DOOR
	if ai.move_along_path(MovementComponent.Mode.JOG):
		# At the end of the path but not biting: unreachable, or a wall
		# between us. Face the target and retry at the next re-path.
		zombie.face_toward(ai.last_known_position)
	return &""
