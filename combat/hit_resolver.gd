class_name HitResolver
extends RefCounted
## The damage half of a melee fighter: finds targets (sphere query on the
## target layer → pure select_targets() → line-of-sight ray), rolls and
## applies damage / crits / head hits / knockback / knockdown / shoves,
## wears the swinging ItemInstance and announces hits (EventBus melee_hit
## + a `melee` sound). No timing, no input (see SwingStateMachine).

var profile: CombatProfile
var rng: RandomNumberGenerator
var _query: PhysicsShapeQueryParameters3D
var _shape: SphereShape3D
var _ray: PhysicsRayQueryParameters3D


func _init(p_profile: CombatProfile, p_rng: RandomNumberGenerator, target_mask: int, los_mask: int, exclude: Array[RID] = []) -> void:
	profile = p_profile
	rng = p_rng
	_shape = SphereShape3D.new()
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _shape
	_query.collision_mask = target_mask
	_query.collide_with_areas = false
	_query.exclude = exclude
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = los_mask
	_ray.collide_with_areas = false
	_ray.exclude = exclude


# --- Pure maths (unit-tested) -------------------------------------------------

static func stamina_damage_multiplier(exhausted: bool, low: bool, exhausted_mult: float = 0.6, low_mult: float = 0.85) -> float:
	if exhausted:
		return exhausted_mult
	return low_mult if low else 1.0


## Indices of [positions] hit by an arc at [origin] facing [direction]:
## flat distance ≤ reach + radius and angle to the direction ≤ half the
## arc (widened by the target's angular radius). Closest first, at most
## [max_targets].
static func select_targets(origin: Vector3, direction: Vector3, reach: float, arc_radians: float,
		max_targets: int, positions: Array, radius: float = 0.0) -> Array[int]:
	var out: Array[int] = []
	var dir := Vector2(direction.x, direction.z)
	if dir.length_squared() < 0.000001 or max_targets <= 0:
		return out
	dir = dir.normalized()
	var half := arc_radians * 0.5
	var scored: Array = []
	for i in positions.size():
		var p: Vector3 = positions[i]
		var d := Vector2(p.x - origin.x, p.z - origin.z)
		var dist := d.length()
		if dist > reach + radius:
			continue
		var ang := 0.0
		if dist > 0.0001:
			ang = absf(dir.angle_to(d))
			var widen := asin(clampf(radius / dist, 0.0, 1.0)) if radius > 0.0 else 0.0
			if ang > half + widen:
				continue
		scored.append([dist, ang, i])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if not is_equal_approx(a[0], b[0]) else a[1] < b[1])
	for s in scored:
		if out.size() >= max_targets:
			break
		out.append(s[2])
	return out


# --- Queries ------------------------------------------------------------------

## Living damageable bodies on the target layer within [radius] of [actor].
func query_candidates(actor: Node3D, radius: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if actor == null or not actor.is_inside_tree():
		return out
	var space := actor.get_world_3d().direct_space_state
	if space == null:
		return out
	_shape.radius = radius
	_query.transform = Transform3D(Basis.IDENTITY, actor.global_position + Vector3.UP * profile.hit_height)
	for hit in space.intersect_shape(_query, 32):
		var col := hit.get("collider") as Node3D
		if col == null or out.has(col) or not col.has_method(&"take_damage"):
			continue
		if col.has_method(&"is_dead") and col.is_dead():
			continue
		out.append(col)
	return out


## Targets [w] reaches along [direction] with a clear line; [cap] < 0 =
## the weapon's max_targets.
func targets_for(actor: Node3D, w: WeaponData, direction: Vector3, cap: int = -1) -> Array[Node3D]:
	var cands := query_candidates(actor, w.reach + profile.target_radius)
	var out: Array[Node3D] = []
	if cands.is_empty():
		return out
	var positions: Array = []
	for c in cands:
		positions.append(c.global_position)
	var n := w.max_targets if cap < 0 else cap
	# Select generously, then drop the ones behind cover, then cap.
	for i in select_targets(actor.global_position, direction, w.reach, w.arc_radians(), positions.size(), positions, profile.target_radius):
		if out.size() >= n:
			break
		if has_line(actor, cands[i]):
			out.append(cands[i])
	return out


## Nothing solid (world, closed door leaf, closed window pane) between the
## attacker's and the target's chest.
func has_line(actor: Node3D, target: Node3D) -> bool:
	var space := actor.get_world_3d().direct_space_state
	if space == null:
		return true
	_ray.from = actor.global_position + Vector3.UP * profile.hit_height
	_ray.to = target.global_position + Vector3.UP * profile.hit_height
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return true
	var col: Node = hit.get("collider")
	return col == null or col == target


# --- Resolve ---------------------------------------------------------------------

## Apply one active window. [damage_mult] = charge × stamina × pain.
## Returns {hits: [{target, damage, info}], broke: bool}; wear goes to
## [item] (the instance that was swung, whatever is equipped now).
func resolve(actor: Node3D, w: WeaponData, item: ItemInstance, direction: Vector3, damage_mult: float, charge: float) -> Dictionary:
	var hits: Array = []
	for t in targets_for(actor, w, direction):
		var dir := t.global_position - actor.global_position
		dir.y = 0.0
		dir = dir.normalized() if dir.length_squared() > 0.0001 else direction
		var winding: bool = t.has_method(&"is_winding_up") and t.call(&"is_winding_up")
		var info := {
			"weapon": w.id,
			"knockback_dir": dir,
			"knockback": w.knockback,
			"knockdown": rng.randf() < w.knockdown_chance_against(winding),
			"stagger": w.can_stagger,
		}
		if w.is_shove:
			info["shove"] = true
			if t.has_method(&"receive_shove"):
				t.call(&"receive_shove", actor, info)
			hits.append({"target": t, "damage": 0.0, "info": info})
			EventBus.melee_hit.emit(actor, t, 0.0, info)
			continue
		var dmg := rng.randf_range(w.damage_min, w.damage_max) * damage_mult
		var crit := rng.randf() < w.crit_chance
		if crit:
			dmg *= w.crit_multiplier
		info["crit"] = crit
		info["region"] = profile.head_region if rng.randf() < w.head_hit_chance else profile.body_region
		info["charge"] = charge
		var r: Variant = t.call(&"take_damage", dmg, actor, info)
		if r is Dictionary and r.get("damage") != null:
			info["dealt"] = float(r.damage)
		hits.append({"target": t, "damage": dmg, "info": info})
		EventBus.melee_hit.emit(actor, t, dmg, info)
	var broke := false
	if not hits.is_empty():
		EventBus.sound_emitted.emit(actor.global_position, w.noise_radius,
			clampf(w.noise_radius / maxf(profile.noise_intensity_radius, 0.01), 0.0, 1.0), &"melee", actor)
		if not w.is_shove:
			broke = wear(w, item)
	return {"hits": hits, "broke": broke}


## Roll condition loss on [item] (must be the instance of [w]). True when it broke.
func wear(w: WeaponData, item: ItemInstance) -> bool:
	if item == null or item.data != w or not w.has_condition() or item.is_broken():
		return false
	if rng.randf() >= w.condition_loss_chance:
		return false
	return item.wear(w.condition_loss)
