class_name ZombieStateAttack
extends ZombieState
## Windup (attack_windup, the visual lunges forward) → hit if the target
## is still in range, in a clear line and faced (head flashes white) →
## cooldown → again while in range, else chase. Holds one of the target's
## attack slots while active.

enum Phase { WINDUP, COOLDOWN }

var phase: Phase = Phase.WINDUP
var timer: float = 0.0
var last_hit: bool = false


func enter(_from: StringName) -> void:
	ai.stop()
	ai.clear_destination()
	ai.claim_attack_slot()
	_start_windup()


func exit(_to: StringName) -> void:
	zombie.visual.lunge = 0.0
	ai.release_attack_slot()


## Lose the windup (shoved while stagger-immune): straight to cooldown.
func interrupt() -> void:
	if phase == Phase.WINDUP:
		zombie.visual.lunge = 0.0
		phase = Phase.COOLDOWN
		timer = profile().attack_cooldown


func _start_windup() -> void:
	phase = Phase.WINDUP
	timer = profile().attack_windup


func update(delta: float) -> StringName:
	if not ai.target_valid():
		return ZombieAI.S_LOST
	var t := zombie.target
	zombie.face_toward(t.global_position)
	if zombie.senses.visible_target == t:
		ai.last_known_position = zombie.senses.last_seen_position
		ai.memory_left = profile().memory_seconds
	timer -= delta
	match phase:
		Phase.WINDUP:
			var windup := profile().attack_windup
			zombie.visual.lunge = profile().lunge_distance * clampf(1.0 - timer / windup, 0.0, 1.0) if windup > 0.0 else 0.0
			if timer <= 0.0:
				_swing(t)
				zombie.visual.lunge = 0.0
				phase = Phase.COOLDOWN
				timer = profile().attack_cooldown
		Phase.COOLDOWN:
			if not ai.target_in_attack_range(profile().attack_leash_slack):
				return ZombieAI.S_CHASE
			if timer <= 0.0:
				if ai.target_in_attack_range() and ai.has_attack_line():
					_start_windup()
				else:
					return ZombieAI.S_CHASE
	return &""


func _swing(t: Node3D) -> void:
	var hit := ai.target_in_attack_range(profile().attack_hit_slack) \
		and ai.facing_point(t.global_position, profile().attack_facing_dot) \
		and ai.has_attack_line()
	zombie.visual.flash(profile().swing_flash_seconds)
	if hit and t.has_method(&"take_damage"):
		t.call(&"take_damage", profile().attack_damage, zombie, ai.roll_attack_info())
	last_hit = hit
	EventBus.zombie_attacked.emit(zombie, t, hit)
