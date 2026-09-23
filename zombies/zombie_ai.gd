class_name ZombieAI
extends Node
## Zombie brain: a StateMachine of ZombieState objects (zombies/states/)
## plus the shared helpers the states use (navigation, target bookkeeping,
## breakable-obstacle detection, attacker slots, seeded randomness).
##
## States: idle → wander (random nav point near home) ⇄ idle;
## sound → investigate → search → wander; sight → chase → attack;
## lost (memory expired) → search; breakable in the path → attack_door;
## stunned (hit hard) → back; dead.
##
## This node knows nothing about doors or buildings: anything that
## blocks the path is a "breakable" (group "breakable", duck-typed
## `take_damage(amount, source)` and `blocks_path()`), and world lookups
## go through WorldQuery. All numbers come from the ZombieProfile.
##
## Per-tick cost: the AI runs at profile.ai_hz_*; re-pathing at
## profile.repath_hz staggered from the seed; the breakable ray only at
## re-path ticks; query objects are created once.

const S_IDLE := &"idle"
const S_WANDER := &"wander"
const S_INVESTIGATE := &"investigate"
const S_SEARCH := &"search"
const S_CHASE := &"chase"
const S_ATTACK := &"attack"
const S_ATTACK_DOOR := &"attack_door"
const S_LOST := &"lost_target"
const S_STUNNED := &"stunned"
const S_KNOCKED_DOWN := &"knocked_down"
const S_CLIMB_WINDOW := &"climb_window"
const S_DEAD := &"dead"
const GROUP_BREAKABLE := &"breakable"

## Tint per state for ZombieVisual.set_tint().
const TINTS := {
	S_INVESTIGATE: &"alert", S_SEARCH: &"alert", S_ATTACK_DOOR: &"alert", S_CLIMB_WINDOW: &"alert",
	S_CHASE: &"hostile", S_ATTACK: &"hostile", S_LOST: &"hostile",
	S_KNOCKED_DOWN: &"hostile", S_STUNNED: &"hostile",
	S_DEAD: &"dead",
}
## Layers for the "breakable ahead" ray: 7 doors + 9 barricades
## (furniture pushed in front of a door, Round 9).
const BREAKABLE_MASK := (1 << 6) | (1 << 8)
## Layers that block an attack: 1 world + 7 doors + 8 window panes.
const ATTACK_LOS_MASK := (1 << 0) | (1 << 6) | (1 << 7)
## Height of the chest-to-chest attack ray.
const CHEST_HEIGHT := 1.0

## Attack slots per target (instance id -> number of attackers), shared by
## every zombie so only profile.max_attackers bite at once.
static var _attack_slots: Dictionary = {}

var zombie: Zombie
var machine: StateMachine
var nav: NavigationAgent3D
var rng := RandomNumberGenerator.new()

## Last position where the target was seen (chase / lost).
var last_known_position: Vector3 = Vector3.ZERO
## Where a heard sound came from (investigate).
var investigate_position: Vector3 = Vector3.ZERO
## Round 8 hearing: strength (0..1) of the sound being investigated and
## the AI time it was heard (priority), whether it was loud (investigate
## at chase speed), whether the zombie first pauses to turn toward a faint
## one, and how many moans relayed it (hordes).
var sound_strength: float = 0.0
var sound_time: float = -INF
var investigate_loud: bool = false
var investigate_pause: bool = false
var sound_hops: int = 0
## Category of the sound being investigated (&"shout" lures search longer).
var investigate_category: StringName = &""
## AI time of the last zombie_moan.
var last_moan_time: float = -INF
## Seconds of target memory left once out of sight.
var memory_left: float = 0.0
## Breakable obstacle found in the path (attack_door). Duck-typed.
var blocking_obstacle: Node3D = null
## Round 9: the window this zombie is about to climb (climb_window).
var climb_window: Node3D = null
## Round 9: a better entry point than the barricade in front of us (a
## point to walk to first) and until when (AI time) to keep going there.
var detour_point: Vector3 = Vector3.INF
var detour_until: float = -INF
## The door / window the detour leads to.
var detour_fixture: Node3D = null
var _last_link_check: float = -INF
## Seconds the zombie has wanted to move but did not (stuck detection).
var stuck_time: float = 0.0
## True while this zombie holds an attack slot on zombie.target.
var has_attack_slot: bool = false
## Duration of the next / current stun (set by stun()).
var stun_seconds: float = 0.8
## AI time (s) of the last stagger; no new stagger within
## profile.stagger_immunity_seconds of it (no stun-lock).
var _last_stagger_time: float = -INF
var _time: float = 0.0

var _claimed_key: int = 0
var _obstacle_ray: PhysicsRayQueryParameters3D
var _attack_ray: PhysicsRayQueryParameters3D
var _nav_target: Vector3 = Vector3.INF
var _repath_accum: float = 0.0
var _repath_period: float = 0.5


## Called by Zombie._ready() (children are ready before the parent's
## @onready vars exist, so the zombie wires us up explicitly).
func setup(z: Zombie) -> void:
	zombie = z
	nav = zombie.nav_agent
	if zombie.ai_seed != 0:
		rng.seed = zombie.ai_seed
	else:
		rng.randomize()
	_obstacle_ray = PhysicsRayQueryParameters3D.new()
	_obstacle_ray.collision_mask = BREAKABLE_MASK
	_obstacle_ray.collide_with_areas = false
	_obstacle_ray.exclude = [zombie.get_rid()]
	_attack_ray = PhysicsRayQueryParameters3D.new()
	_attack_ray.collision_mask = ATTACK_LOS_MASK
	_attack_ray.collide_with_areas = false
	_attack_ray.exclude = [zombie.get_rid()]
	_repath_period = 1.0 / maxf(zombie.profile.repath_hz, 0.1)
	machine = StateMachine.new(zombie)
	machine.add_state(ZombieStateIdle.new(S_IDLE, self))
	machine.add_state(ZombieStateWander.new(S_WANDER, self))
	machine.add_state(ZombieStateInvestigate.new(S_INVESTIGATE, self))
	machine.add_state(ZombieStateSearch.new(S_SEARCH, self))
	machine.add_state(ZombieStateChase.new(S_CHASE, self))
	machine.add_state(ZombieStateAttack.new(S_ATTACK, self))
	machine.add_state(ZombieStateAttackDoor.new(S_ATTACK_DOOR, self))
	machine.add_state(ZombieStateLostTarget.new(S_LOST, self))
	machine.add_state(ZombieStateStunned.new(S_STUNNED, self))
	machine.add_state(ZombieStateKnockedDown.new(S_KNOCKED_DOWN, self))
	machine.add_state(ZombieStateClimbWindow.new(S_CLIMB_WINDOW, self))
	machine.add_state(ZombieStateDead.new(S_DEAD, self))
	machine.state_changed.connect(_on_state_changed)
	zombie.senses.target_seen.connect(_on_target_seen)
	zombie.senses.sound_heard.connect(_on_sound_heard)
	# Spread re-paths across the horde (seeded, so runs repeat).
	_repath_accum = rng.randf() * _repath_period
	machine.change_to(S_IDLE)


func state_id() -> StringName:
	return machine.current_id() if machine else &""


func is_in(id: StringName) -> bool:
	return machine != null and machine.is_in(id)


func change_to(id: StringName) -> bool:
	return machine.change_to(id)


func profile() -> ZombieProfile:
	return zombie.profile


## One AI step (called by Zombie at the profile's AI rate with the
## accumulated delta).
func tick(delta: float) -> void:
	if zombie.dead:
		return
	_time += delta
	_repath_accum += delta
	if zombie.has_move_intent() and zombie.speed() < 0.05:
		stuck_time += delta
	else:
		stuck_time = 0.0
	machine.update(delta)
	_update_movement_mode()


## Hostile → full physics and AI rate; calm and far from the player →
## cheap navmesh sliding. An unknown distance (no sense check yet) counts
## as near.
func _update_movement_mode() -> void:
	var s := machine.current_id()
	var hostile := s == S_CHASE or s == S_ATTACK or s == S_ATTACK_DOOR or s == S_STUNNED or s == S_KNOCKED_DOWN \
		or s == S_CLIMB_WINDOW
	var far := zombie.senses.last_target_distance != INF and zombie.senses.last_target_distance > profile().cheap_distance
	zombie.cheap_movement = not hostile and far
	if zombie.hostile != hostile:
		zombie.hostile = hostile


func _on_state_changed(from: StringName, to: StringName) -> void:
	zombie.visual.set_tint(TINTS.get(to, &"normal"))
	EventBus.zombie_state_changed.emit(zombie, from, to)


# --- Perception / damage hooks ----------------------------------------------

func _on_target_seen(t: Node3D) -> void:
	if zombie.dead:
		return
	last_known_position = t.global_position
	memory_left = profile().memory_seconds
	zombie.target = t
	var s := state_id()
	if s == S_CHASE or s == S_ATTACK or s == S_ATTACK_DOOR or s == S_STUNNED or s == S_KNOCKED_DOWN or s == S_DEAD \
			or s == S_CLIMB_WINDOW:
		return
	EventBus.zombie_spotted_target.emit(zombie, t)
	machine.change_to(S_CHASE)


## A sound reached this zombie with [strength] (0..1, SoundMath.perceived).
## Calm zombies investigate it; an investigating one switches only to a
## sound at least as strong as its current one (which fades over time).
## Loud (≥ profile.loud_sound_strength) → investigate at chase speed;
## faint → turn toward it, pause, then shamble. A zombie_moan carries a
## lure: the moaner's own investigate target (hordes follow the noise,
## not each other). Chasing / attacking zombies ignore sounds.
func _on_sound_heard(position: Vector3, _category: StringName, strength: float = 0.3, event: SoundEvent = null) -> void:
	if zombie.dead:
		return
	var s := state_id()
	if not (s == S_IDLE or s == S_WANDER or s == S_SEARCH or s == S_INVESTIGATE):
		return
	if s == S_INVESTIGATE and not SoundMath.should_retarget(sound_strength, _time - sound_time,
			strength, profile().sound_priority_decay):
		return
	var goal := position
	var hops := 0
	if event != null and event.extras.has(&"lure"):
		goal = event.extras[&"lure"]
		hops = int(event.extras.get(&"hops", 1))
	var loud := strength >= profile().loud_sound_strength
	investigate_category = event.category if event != null else _category
	if s == S_INVESTIGATE:
		# Re-targeting never downgrades: a loud investigation stays loud
		# and a moan relay never raises the hop count of a first-hand one.
		var decayed := sound_strength - (_time - sound_time) * profile().sound_priority_decay
		investigate_position = goal
		sound_strength = maxf(strength, decayed)
		sound_time = _time
		sound_hops = mini(sound_hops, hops)
		investigate_loud = investigate_loud or loud
		set_destination(goal)
		return
	investigate_position = goal
	sound_strength = strength
	sound_time = _time
	sound_hops = hops
	investigate_loud = loud
	investigate_pause = not investigate_loud
	zombie.face_toward(position)
	machine.change_to(S_INVESTIGATE)


## Investigating zombies moan every profile.moan_cooldown seconds; the
## moan (6 m) lures neighbours to the same spot. Relays stop after
## profile.moan_max_hops. Called by the investigate state.
## Moans go through SoundManager.queue_sound: a whole crowd starting to
## investigate at once moans over several frames, not in one spike.
func maybe_moan() -> bool:
	if sound_hops >= profile().moan_max_hops or _time - last_moan_time < profile().moan_cooldown:
		return false
	last_moan_time = _time
	SoundManager.queue_sound(&"zombie_moan", zombie.global_position, zombie,
		{"lure": investigate_position, "hops": sound_hops + 1})
	return true


## Investigate [p] without a sound (hit by something, lost target): no
## pause, shamble speed, lowest priority for the next sound.
func investigate_quietly(p: Vector3) -> void:
	investigate_position = p
	sound_strength = 0.0
	sound_time = _time
	sound_hops = 0
	investigate_loud = false
	investigate_pause = false
	investigate_category = &""


## Hit by [source] for [dmg] (after multipliers). info.knockdown floors
## it; a hit of at least profile.stagger_damage stuns; a creature that
## hits us (anything with take_damage that is not a zombie) becomes the
## target; anything else makes a target-less zombie turn and investigate.
## A zombie lying on the ground stays down.
func on_damaged(source: Node, dmg: float, info: Dictionary = {}) -> void:
	if zombie.dead or is_in(S_KNOCKED_DOWN) or is_in(S_CLIMB_WINDOW):
		return
	var attacker := _creature(source)
	if attacker != null:
		_remember_attacker(attacker)
	if bool(info.get("knockdown", false)):
		knock_down(source)
		return
	if dmg >= profile().stagger_damage and bool(info.get("stagger", true)) and can_be_staggered():
		stun(profile().stun_seconds)
		return
	if attacker != null:
		var s := state_id()
		if s != S_CHASE and s != S_ATTACK and s != S_STUNNED:
			machine.change_to(S_CHASE)
		return
	if zombie.target == null and source is Node3D and is_instance_valid(source):
		var p: Vector3 = (source as Node3D).global_position
		zombie.face_toward(p)
		var s := state_id()
		if s == S_IDLE or s == S_WANDER or s == S_SEARCH or s == S_INVESTIGATE:
			investigate_quietly(p)
			if s == S_INVESTIGATE:
				set_destination(p)
			else:
				machine.change_to(S_INVESTIGATE)


## Shoved by [source]: the attack windup is lost; knocked down or
## staggered for profile.shove_stun_seconds.
func on_shoved(source: Node, knockdown: bool) -> void:
	if zombie.dead or is_in(S_KNOCKED_DOWN) or is_in(S_CLIMB_WINDOW):
		return
	var attacker := _creature(source)
	if attacker != null:
		_remember_attacker(attacker)
	if knockdown:
		knock_down(source)
	elif can_be_staggered():
		stun(profile().shove_stun_seconds)
	else:
		# Still reeling from the last stagger: the bite is lost, no stun.
		interrupt_attack()


func _creature(source: Node) -> Node3D:
	if source is Node3D and is_instance_valid(source) and source.has_method(&"take_damage") \
			and not source.is_in_group(&"zombie") and source.is_inside_tree():
		if source.has_method(&"is_dead") and source.is_dead():
			return null
		return source
	return null


func _remember_attacker(attacker: Node3D) -> void:
	if zombie.target != attacker:
		release_attack_slot()
	zombie.target = attacker
	last_known_position = attacker.global_position
	memory_left = profile().memory_seconds
	zombie.face_toward(attacker.global_position)


func can_be_staggered() -> bool:
	return _time - _last_stagger_time >= profile().stagger_immunity_seconds


## Cancel a bite windup (straight into the cooldown).
func interrupt_attack() -> void:
	if is_in(S_ATTACK):
		(machine.current as ZombieStateAttack).interrupt()


## Freeze for [seconds] (re-entering restarts the timer).
func stun(seconds: float = -1.0) -> void:
	if zombie.dead or is_in(S_KNOCKED_DOWN):
		return
	_last_stagger_time = _time
	stun_seconds = seconds if seconds > 0.0 else profile().stun_seconds
	machine.change_to(S_STUNNED, true)


func knock_down(source: Node = null) -> void:
	if zombie.dead or is_in(S_KNOCKED_DOWN):
		return
	# The knockback of the blow that floored it keeps sliding the body.
	machine.change_to(S_KNOCKED_DOWN)
	EventBus.zombie_knocked_down.emit(zombie, source)


## True during the windup phase of a bite.
func is_winding_up() -> bool:
	if not is_in(S_ATTACK):
		return false
	var st := machine.current as ZombieStateAttack
	return st != null and st.phase == ZombieStateAttack.Phase.WINDUP


## Roll where / how a bite lands: {region, type, infectious}.
func roll_attack_info() -> Dictionary:
	var region := Injury.roll_weighted(profile().attack_region_weights, rng.randf())
	var type := Injury.roll_weighted(profile().attack_type_weights, rng.randf())
	return {
		"region": region if region != &"" else &"random",
		"type": type if type != &"" else &"scratch",
		"infectious": profile().attack_infectious,
	}


func on_death() -> void:
	if machine and not is_in(S_DEAD):
		machine.change_to(S_DEAD)
	release_attack_slot()


## Tests / perf: aim this zombie at [t] as if it had just been seen.
func force_target(t: Node3D) -> void:
	zombie.senses.visible_target = t
	zombie.senses.last_seen_position = t.global_position
	zombie.senses.last_target_distance = BodyHelpers.flat_distance(t.global_position, zombie.global_position)
	_on_target_seen(t)


# --- Attack slots ------------------------------------------------------------

func _slot_key() -> int:
	return zombie.target.get_instance_id() if zombie.target else 0


## Try to become one of the profile.max_attackers on the current target.
func claim_attack_slot() -> bool:
	if has_attack_slot:
		return true
	var key := _slot_key()
	if key == 0:
		return false
	var n: int = _attack_slots.get(key, 0)
	if n >= profile().max_attackers:
		return false
	_attack_slots[key] = n + 1
	has_attack_slot = true
	_claimed_key = key
	return true


func release_attack_slot() -> void:
	if not has_attack_slot:
		return
	has_attack_slot = false
	# The key remembered at claim time (the target may be freed by now).
	var key := _claimed_key
	var n: int = _attack_slots.get(key, 0) - 1
	if n <= 0:
		_attack_slots.erase(key)
	else:
		_attack_slots[key] = n


static func attackers_on(target: Node) -> int:
	return _attack_slots.get(target.get_instance_id(), 0) if target else 0


# --- Navigation helpers -----------------------------------------------------

## Set the nav destination if it moved by more than 0.5 m.
func set_destination(p: Vector3) -> void:
	if _nav_target != Vector3.INF and p.distance_squared_to(_nav_target) < 0.25:
		return
	_nav_target = p
	nav.target_position = p


func clear_destination() -> void:
	_nav_target = Vector3.INF


## True once per re-path period (consumes the tick).
func repath_due() -> bool:
	if _repath_accum >= _repath_period:
		_repath_accum = fmod(_repath_accum, _repath_period)
		return true
	return false


## Steer along the current path at [mode]. Returns true when the agent
## reports the destination reached (or there is no path to follow).
func move_along_path(mode: MovementComponent.Mode) -> bool:
	if _nav_target == Vector3.INF or nav.is_navigation_finished():
		zombie.set_intent(Vector3.ZERO, mode)
		return true
	var next := nav.get_next_path_position()
	var dir := next - zombie.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0025:
		zombie.set_intent(Vector3.ZERO, mode)
		return nav.is_navigation_finished()
	zombie.set_intent(dir.normalized(), mode)
	return false


func stop() -> void:
	zombie.set_intent(Vector3.ZERO, MovementComponent.Mode.WALK)


## Flat distance from the zombie to [p].
func distance_to(p: Vector3) -> float:
	return BodyHelpers.flat_distance(zombie.global_position, p)


func target_valid() -> bool:
	var t := zombie.target
	if t == null or not is_instance_valid(t) or not t.is_inside_tree():
		return false
	if t.has_method(&"is_dead") and t.is_dead():
		return false
	return true


func distance_to_target() -> float:
	return distance_to(zombie.target.global_position) if target_valid() else INF


func target_in_attack_range(slack: float = 0.0) -> bool:
	return distance_to_target() <= profile().attack_range + slack


## True when nothing solid (wall, door, pane) lies between the zombie's
## and the target's chest: no biting through walls.
func has_attack_line() -> bool:
	if not target_valid() or not zombie.is_inside_tree():
		return false
	var space := zombie.get_world_3d().direct_space_state
	if space == null:
		return true
	_attack_ray.from = zombie.global_position + Vector3.UP * CHEST_HEIGHT
	_attack_ray.to = zombie.target.global_position + Vector3.UP * CHEST_HEIGHT
	var hit := space.intersect_ray(_attack_ray)
	if hit.is_empty():
		return true
	var col: Node = hit.get("collider")
	return col == null or col == zombie.target


## True when the visual actually points at [p] (dot ≥ [min_dot]).
func facing_point(p: Vector3, min_dot: float) -> bool:
	var d := p - zombie.global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return true
	return zombie.visual_facing_vector().dot(d.normalized()) >= min_dot


## Random reachable point within [radius] of [center] (on the navmesh),
## optionally outdoors only.
func random_point_near(center: Vector3, radius: float, avoid_buildings: bool = false) -> Vector3:
	return WorldQuery.random_nav_point(nav.get_navigation_map(), rng, center, radius,
		zombie.global_position.y, avoid_buildings, zombie.get_tree())


func random_range(a: float, b: float) -> float:
	return rng.randf_range(a, b)


## A breakable obstacle (group "breakable", blocks_path() true) within
## profile.door_check_distance ahead (toward the next path point, or the
## facing when no path). Null otherwise.
func breakable_ahead(check_distance: float = -1.0) -> Node3D:
	if not zombie.is_inside_tree():
		return null
	var space := zombie.get_world_3d().direct_space_state
	if space == null:
		return null
	var dir := zombie.facing_vector()
	if _nav_target != Vector3.INF and not nav.is_navigation_finished():
		var d := nav.get_next_path_position() - zombie.global_position
		d.y = 0.0
		if d.length_squared() > 0.0001:
			dir = d.normalized()
	var from := zombie.global_position + Vector3.UP * CHEST_HEIGHT
	_obstacle_ray.from = from
	_obstacle_ray.to = from + dir * (check_distance if check_distance > 0.0 else profile().door_check_distance)
	var hit := space.intersect_ray(_obstacle_ray)
	if hit.is_empty():
		return null
	var col: Node = hit.get("collider")
	var b := resolve_breakable(col)
	if b != null and b.blocks_path():
		return b
	return null


## The breakable behind a collider: what it says it is
## (breakable_target(): a door with planks → its BarricadeComponent), a
## breakable child (furniture → its FurnitureWork), or itself.
static func resolve_breakable(col: Node) -> Node3D:
	if col == null:
		return null
	if col.has_method(&"breakable_target"):
		var t: Variant = col.call(&"breakable_target")
		if t is Node3D and is_breakable(t):
			return t
	if is_breakable(col):
		return col
	for c in col.get_children():
		if is_breakable(c):
			return c
	return null


static func is_breakable(n: Node) -> bool:
	return n != null and n is Node3D and n.is_in_group(GROUP_BREAKABLE) \
		and n.has_method(&"take_damage") and n.has_method(&"blocks_path")


## Where to go once an obstacle is no longer in the way.
func after_obstacle_state() -> StringName:
	if target_valid() and memory_left > 0.0:
		return S_CHASE
	return S_INVESTIGATE


# --- Windows and barricades (Round 9) -------------------------------------------

## Window this zombie's path crosses right here: a NavigationLink3D owned
## by a window (HouseWindow adds one per exterior window) whose end on our
## side is within profile.window_link_distance, while the path's goal is
## on the other side. Checked at re-path ticks and when stuck (walking
## into the sill).
func window_link_ahead(max_distance: float = -1.0) -> Node3D:
	var reach := max_distance if max_distance > 0.0 else profile().window_link_distance
	if _nav_target == Vector3.INF or nav == null:
		return null
	var res := nav.get_current_navigation_result()
	if res == null:
		return null
	var path := res.path
	var types := res.path_types
	var owners := res.path_owner_ids
	if path.is_empty() or types.size() != path.size() or owners.size() != path.size():
		return null
	var i0 := maxi(nav.get_current_navigation_path_index() - 1, 0)
	var i1 := mini(i0 + 4, path.size())
	for i in range(i0, i1):
		if types[i] != NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			continue
		var link := instance_from_id(owners[i]) as NavigationLink3D
		if link == null:
			continue
		var w := link.get_parent() as Node3D
		if w == null or not w.has_method(&"approach_point") or not w.has_method(&"side_of"):
			continue
		var here := zombie.global_position
		if distance_to(w.call(&"approach_point", here)) > reach:
			continue
		var goal: Vector3 = path[path.size() - 1]
		if float(w.call(&"side_of", goal)) == float(w.call(&"side_of", here)):
			continue
		return w
	return null


## Handle a window on the path: breakable (planks / closed pane) → bang
## on it (attack_door), else climb through. Returns the next state id or
## &"" when there is no window here.
func window_transition() -> StringName:
	var w := _detour_window_reached()
	if w == null:
		# At re-path ticks, or when walking into something (a sill) — the
		# latter at most 4× a second (crowds are "stuck" a lot).
		var stuck := stuck_time > 0.15 and _time - _last_link_check >= 0.25
		if not (repath_due_peek() or stuck):
			return &""
		_last_link_check = _time
		w = window_link_ahead(profile().crowd_check_distance if in_crowd() else -1.0)
	if w == null:
		return &""
	if w.has_method(&"blocks_path") and w.blocks_path():
		var b := resolve_breakable(w)
		if b != null and consider_detour(b):
			return &""
		blocking_obstacle = b
		return S_ATTACK_DOOR if b != null else &""
	if distance_to(w.call(&"approach_point", zombie.global_position)) > profile().window_link_distance + 0.3:
		return &""  # open window, crowd in front: keep pushing
	climb_window = w
	return S_CLIMB_WINDOW


## Stuck long enough to be in a crowd in front of something.
func in_crowd() -> bool:
	return stuck_time >= profile().crowd_stuck_seconds


## The breakable ahead (farther when stuck in a crowd: join its queue).
func obstacle_ahead() -> Node3D:
	return breakable_ahead(profile().crowd_check_distance if in_crowd() else -1.0)


## A breakable found ahead: a barricade may send us to a better entry
## (detour, stay in the moving state: &""); otherwise bang on it.
func obstacle_transition(obstacle: Node3D) -> StringName:
	if obstacle is BarricadeComponent and consider_detour(obstacle):
		return &""
	blocking_obstacle = obstacle
	return S_ATTACK_DOOR


## Peek (without consuming) whether a re-path tick is due.
func repath_due_peek() -> bool:
	return _repath_accum >= _repath_period


## Facing barricade [b] (planks on a door / window): is another entry of
## the same building clearly better (fewer planks for the walk)? Then go
## there first (detour_point) and return true.
func consider_detour(b: Node3D) -> bool:
	if detour_active():
		return false
	var fixture: Node3D = b.get("fixture") if "fixture" in b else null
	if fixture == null or not fixture.has_method(&"barricade_planks"):
		return false
	var per_plank := 8.0
	var bd: Variant = b.get(&"data")
	if bd is BarricadeData:
		per_plank = (bd as BarricadeData).nav_cost_per_plank
	var best := EntryPlanner.better_entry(fixture, zombie.global_position, per_plank,
		profile().detour_search_radius, profile().detour_margin)
	if best.is_empty():
		return false
	detour_point = best.point
	detour_fixture = best.fixture
	detour_until = _time + profile().detour_seconds
	_nav_target = Vector3.INF
	set_destination(detour_point)
	return true


func detour_active() -> bool:
	if detour_point == Vector3.INF:
		return false
	if _time > detour_until or distance_to(detour_point) <= profile().window_link_distance:
		detour_point = Vector3.INF
		return false
	return true


func clear_detour() -> void:
	detour_point = Vector3.INF
	detour_fixture = null


## A detour that led to a window ends at it: take that window now (the
## navmesh alone would walk back to the free-to-path doorway).
func _detour_window_reached() -> Node3D:
	var w := detour_fixture
	if w == null or not is_instance_valid(w) or not w.has_method(&"approach_point"):
		return null
	if _time > detour_until:
		detour_fixture = null
		return null
	if distance_to(w.call(&"approach_point", zombie.global_position)) > profile().window_link_distance + 0.3:
		return null
	detour_fixture = null
	detour_point = Vector3.INF
	return w


## Where a moving state should head: the detour first while it lasts.
func goal_or_detour(goal: Vector3) -> Vector3:
	return detour_point if detour_active() else goal


## Forget the current path (after a climb: re-path from the new side).
func reset_path() -> void:
	_nav_target = Vector3.INF
	_repath_accum = _repath_period
