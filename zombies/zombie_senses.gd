class_name ZombieSenses
extends Node
## Perception for a Zombie: vision, hearing and proximity.
##
## Vision (checked every period(), staggered per zombie from its seed):
## the target must be within range, inside the field of view and visible
## along a ray from the zombie's eye to the target's eye on [los_mask]
## (walls, closed doors and closed window panes block; open / smashed
## windows are see-through). A sneaking target halves the detection
## range, a sprinting one raises it by 25 %. Anything within
## profile.proximity_range with a clear chest-to-chest line is noticed
## regardless of facing. While the target is in sight and the zombie is
## hostile, checks slow down to profile.chase_sense_interval.
##
## Hearing (Round 8): the senses node is a SoundManager listener (ear at
## eye height, profile.hearing_sensitivity, 0 while disabled / dead).
## SoundManager does the propagation (walls, doors, windows, openings)
## and calls on_sound(); a heard sound → [signal sound_heard] with its
## perceived strength. Registered in setup(), unregistered on death and
## when leaving the tree (no stale listeners).
##
## The cone/range test is the pure static can_see() (unit-tested).

signal target_seen(target: Node3D)
signal sound_heard(position: Vector3, category: StringName, strength: float, event: SoundEvent)

## Layers that block sight: 1 world + 7 doors + 8 window panes.
@export_flags_3d_physics var los_mask: int = (1 << 0) | (1 << 6) | (1 << 7)

var enabled: bool = true
## The target currently in sight (null when none). Updated each check.
var visible_target: Node3D = null
var last_seen_position: Vector3 = Vector3.ZERO
## Flat distance to the candidate target at the last check; INF = unknown
## (no check yet / no target). The AI treats unknown as "not far".
var last_target_distance: float = INF
## Set by the last check: why the target was / was not seen (debug).
var last_reason: StringName = &"none"
## Last sound heard: {category, position, strength, path, time} (debug / tests).
var last_heard: Dictionary = {}

var _zombie: Zombie
var _ray: PhysicsRayQueryParameters3D
var _period_calm: float = 1.0 / 6.0
var _period_now: float = 1.0 / 6.0


func setup(z: Zombie) -> void:
	_zombie = z
	_period_calm = 1.0 / maxf(z.profile.sense_hz, 0.1)
	_period_now = _period_calm
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = los_mask
	_ray.collide_with_areas = false
	_ray.exclude = [_zombie.get_rid()]
	if is_inside_tree():
		SoundManager.register_listener(self)


func _enter_tree() -> void:
	if _zombie != null and not _zombie.dead:
		SoundManager.register_listener(self)


func _exit_tree() -> void:
	SoundManager.unregister_listener(self)


## Stop hearing for good (death).
func stop_listening() -> void:
	enabled = false
	SoundManager.unregister_listener(self)


## Seconds until the next check (calm rate, or the slower chase rate while
## the target is in sight and the zombie is hostile).
func period() -> float:
	return _period_now


## Run one perception check now (tests call this directly).
func check() -> void:
	if not enabled:
		return
	var t := _candidate_target()
	if t == null:
		visible_target = null
		last_reason = &"no_target"
		last_target_distance = INF
		_period_now = _period_calm
		return
	last_target_distance = BodyHelpers.flat_distance(t.global_position, _zombie.global_position)
	if can_see_target(t):
		visible_target = t
		last_seen_position = t.global_position
		_period_now = _zombie.profile.chase_sense_interval if _zombie.hostile else _period_calm
		target_seen.emit(t)
	else:
		visible_target = null
		_period_now = _period_calm


## Round 3: the player is the only prey. NPCs join later through a group.
func _candidate_target() -> Node3D:
	var p := GameManager.player as Node3D
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return null
	if p.has_method(&"is_dead") and p.is_dead():
		return null
	return p


## Full vision test against [t] (proximity with LOS, range, cone, LOS).
func can_see_target(t: Node3D) -> bool:
	var from := _zombie.global_position
	var to := t.global_position
	var dist := BodyHelpers.flat_distance(from, to)
	if dist <= _zombie.profile.proximity_range:
		if has_line_of_sight(from + Vector3.UP * 1.0, to + Vector3.UP * 1.0, t):
			last_reason = &"proximity"
			return true
		last_reason = &"occluded"
		return false
	var range_m := effective_range(t)
	if not can_see(from, to, _zombie.facing_vector(), range_m, _zombie.profile.vision_fov_radians(), true):
		last_reason = &"out_of_cone" if dist <= range_m else &"out_of_range"
		return false
	var target_eye := to + Vector3.UP * _target_eye_height(t)
	if not has_line_of_sight(_zombie.eye_position(), target_eye, t):
		last_reason = &"occluded"
		return false
	last_reason = &"seen"
	return true


## Detection range against [t] given its movement mode.
func effective_range(t: Node) -> float:
	var mode: Variant = t.get("effective_mode")
	var mult := 1.0
	if mode is int:
		mult = range_multiplier_for_mode(mode, _zombie.profile.sneak_range_multiplier, _zombie.profile.sprint_range_multiplier)
	return _zombie.profile.vision_range * mult


static func range_multiplier_for_mode(mode: int, sneak_mult: float = 0.5, sprint_mult: float = 1.25) -> float:
	match mode:
		MovementComponent.Mode.SNEAK:
			return sneak_mult
		MovementComponent.Mode.SPRINT:
			return sprint_mult
	return 1.0


func _target_eye_height(t: Node) -> float:
	if t.has_method(&"eye_height"):
		return float(t.call(&"eye_height"))
	return 0.9


## Pure cone test: [to] is within [range_m] of [from] (flat distance) and
## within ±fov/2 of [facing]; [los_ok] is the caller's raycast result.
static func can_see(from: Vector3, to: Vector3, facing: Vector3, range_m: float, fov_radians: float, los_ok: bool) -> bool:
	if not los_ok:
		return false
	var d := Vector2(to.x - from.x, to.z - from.z)
	var dist := d.length()
	if dist > range_m:
		return false
	if dist < 0.001:
		return true
	var f := Vector2(facing.x, facing.z)
	if f.length_squared() < 0.0001:
		return true
	var cos_half := cos(fov_radians * 0.5)
	return d.normalized().dot(f.normalized()) >= cos_half - 0.0001


## True when nothing on los_mask lies between [from] and [to] (a hit on
## [target] itself counts as clear). Reuses one query object.
func has_line_of_sight(from: Vector3, to: Vector3, target: Node = null) -> bool:
	if not _zombie.is_inside_tree():
		return true
	var space := _zombie.get_world_3d().direct_space_state
	if space == null:
		return true
	_ray.from = from
	_ray.to = to
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return true
	var col: Node = hit.get("collider")
	return col == null or col == target


# --- SoundManager listener contract ------------------------------------------------

func sound_ear_position() -> Vector3:
	return _zombie.eye_position() if _zombie != null and is_instance_valid(_zombie) else Vector3(1e6, 0.0, 1e6)


func sound_sensitivity() -> float:
	if not enabled or _zombie == null or _zombie.dead:
		return 0.0
	return _zombie.profile.hearing_sensitivity


func sound_owner() -> Object:
	return _zombie


func on_sound(event: SoundEvent, info: Dictionary) -> void:
	if not enabled or _zombie == null or _zombie.dead:
		return
	last_heard = {"category": event.category, "position": event.position,
		"strength": float(info.get("strength", 0.0)), "path": info.get("path", &"direct"),
		"time": SoundManager.now()}
	sound_heard.emit(event.position, event.category, float(info.get("strength", 0.0)), event)
