class_name MeleeCombat
extends Node
## Melee attacks and shoves for any Character (child node "Combat").
## Generic: the player drives it through PlayerCombatInput, NPCs (later)
## and tests call the API directly (set [scripted] so player input is
## ignored).
##
## Thin facade over two helpers:
## - SwingStateMachine (timing): charge, WINDUP → ACTIVE → RECOVERY, the
##   one-deep input queue (cleared by every finish, normal or interrupted).
## - HitResolver (damage): target query + LOS, damage / crit / head /
##   knockback / knockdown / shove, wear of the swung ItemInstance, events.
## This node owns what touches the character: stamina (paid at swing
## start; refused with EventBus.attack_refused "Too tired to swing"),
## movement modifiers, facing, aiming, pain effects
## (InjuryComponent.pain_combat_modifiers) and the local signals the
## visuals listen to. Shared tuning: CombatProfile
## (data/combat/combat_profile.tres); per weapon: WeaponData.
##
## Round 6: what is held comes from the actor's Equipment (child
## "Equipment"): [equipped] mirrors its primary hand through
## Equipment.equipped_changed; equip() is a convenience that asks the
## Equipment (so the slot rules / "Mid-swing" / "No room" apply). Actors
## without an Equipment keep the old direct assignment.

signal swing_started(weapon: WeaponData, direction: Vector3, charge: float)
## The active window opened; [hits] = [{target, damage, info}].
signal active_started(weapon: WeaponData, direction: Vector3, hits: Array)
signal swing_finished(weapon: WeaponData)
signal equipped_changed(item: ItemInstance)
signal aim_changed(aiming: bool, in_reach: int)

const Phase = SwingStateMachine.Phase
const LAYER_ZOMBIES := 1 << 2
## world (1) + doors (7) + window panes (8)
const LOS_MASK := (1 << 0) | (1 << 6) | (1 << 7)

@export var profile: CombatProfile = preload("res://data/combat/combat_profile.tres")
@export var fists: WeaponData = preload("res://data/items/weapons/fists.tres")
@export var shove_weapon: WeaponData = preload("res://data/items/weapons/shove.tres")
@export_flags_3d_physics var target_mask: int = LAYER_ZOMBIES
@export_flags_3d_physics var los_mask: int = LOS_MASK

## Tests / NPC brains drive the API; PlayerCombatInput ignores input.
var scripted: bool = false
var equipped: ItemInstance = null
var aiming: bool = false
## World direction to swing at while aiming (XZ). Settable (tests, NPCs).
var aim_direction: Vector3 = Vector3.ZERO
## Result of the last resolved active window: [{target, damage, info}].
var last_hits: Array = []
var last_refusal: String = ""
var in_reach: int = 0
var rng := RandomNumberGenerator.new()
var actor: Character
var swing := SwingStateMachine.new()
var resolver: HitResolver

## SwingStateMachine.Phase value (compare with MeleeCombat.Phase.*).
var phase: int:
	get: return swing.phase
var charge_time: float:
	get: return swing.charge_time
var current: WeaponData:
	get: return swing.weapon
var current_charge: float:
	get: return swing.charge
var swing_direction: Vector3:
	get: return swing.direction
var phase_left: float:
	get: return swing.phase_left

var _aim_accum: float = 0.0


func _ready() -> void:
	actor = get_parent() as Character
	rng.seed = WorldConfig.rng_seed_for(self, "melee")
	var eq := _equipment()
	if eq != null:
		eq.equipped_changed.connect(_on_equipment_changed)
		equipped = eq.primary()
	var exclude: Array[RID] = []
	if actor:
		exclude.append(actor.get_rid())
	resolver = HitResolver.new(profile, rng, target_mask, los_mask, exclude)
	# Announce the starting weapon once listeners (HUD) are ready. A
	# deferred call on this node is dropped if it is freed first.
	call_deferred(&"_announce_weapon")


func _announce_weapon() -> void:
	EventBus.weapon_equipped.emit(actor, item_summary())


func charge_multiplier_for(held: float) -> float:
	return SwingStateMachine.charge_multiplier(held, profile.charge_min, profile.charge_max, profile.charge_seconds)


# --- Equipment -------------------------------------------------------------------

## The weapon the next swing uses (equipped, or fists).
func weapon() -> WeaponData:
	if equipped != null and equipped.data is WeaponData and not equipped.is_broken():
		return equipped.data
	return fists


## Equip [item] in the primary hand (null = put it away → fists).
## Goes through the actor's Equipment when it has one (refusals: slot
## rules, "Mid-swing", "No room in inventory"). The swing in progress
## keeps its own weapon and instance (wear still lands on what was swung).
func equip(item: ItemInstance) -> Dictionary:
	if item != null and not item.is_weapon():
		return {"ok": false, "reason": "Not a weapon"}
	var eq := _equipment()
	if eq != null:
		if item == null:
			return eq.unequip(Equipment.PRIMARY) if eq.primary() != null else {"ok": true}
		return eq.equip(item, Equipment.PRIMARY)
	_set_equipped(item)
	return {"ok": true}


func _equipment() -> Equipment:
	return actor.get_node_or_null("Equipment") as Equipment if actor else null


func _on_equipment_changed(slot: StringName, item: ItemInstance) -> void:
	if slot == Equipment.PRIMARY:
		_set_equipped(item)


func _set_equipped(item: ItemInstance) -> void:
	equipped = item
	equipped_changed.emit(equipped)
	EventBus.weapon_equipped.emit(actor, item_summary())


## {id, name, condition, max_condition} of the equipped weapon (or fists).
func item_summary() -> Dictionary:
	var w := weapon()
	var cond := equipped.condition if equipped != null else 0
	return {"id": w.id, "name": w.display_name, "condition": cond, "max_condition": w.max_condition}


# --- Actions ----------------------------------------------------------------------

func is_swinging() -> bool:
	return swing.is_swinging()


func is_active() -> bool:
	return swing.phase == Phase.ACTIVE


## 0..1 while charging (for the HUD meter), -1 otherwise.
func charge_fraction() -> float:
	if swing.phase != Phase.CHARGING:
		return -1.0
	return clampf(swing.charge_time / maxf(profile.charge_seconds, 0.01), 0.0, 1.0)


## Begin charging (or queue behind the swing in progress).
func start_attack() -> bool:
	if swing.phase == Phase.IDLE and not _can_act():
		return false
	var r := swing.press()
	if r == &"charge":
		_set_modifier(&"charge", profile.charge_speed_multiplier)
	return r != &""


## Swing with the charge held so far (or mark the queued swing released).
func release_attack() -> bool:
	var was_queued := swing.queued and swing.queued_held
	if swing.release():
		_set_modifier(&"charge", 1.0)
		return _begin_swing(weapon(), equipped, charge_multiplier_for(swing.charge_time))
	return was_queued


## Cancel a charge (and any queued follow-up) without swinging.
func cancel_charge() -> void:
	swing.cancel_charge()
	_set_modifier(&"charge", 1.0)


## Tests / NPCs: swing now as if the button was held [held] seconds.
func attack_now(held: float = 0.0) -> bool:
	if swing.phase != Phase.IDLE or not _can_act():
		return false
	return _begin_swing(weapon(), equipped, charge_multiplier_for(held))


## Shove (Space). Cancels a charge; queues behind a swing in progress.
func shove() -> bool:
	if swing.is_swinging():
		swing.queue_shove()
		return true
	if swing.phase == Phase.CHARGING:
		cancel_charge()
	if not _can_act():
		return false
	return _begin_swing(shove_weapon, null, 1.0)


func set_aiming(v: bool) -> void:
	if aiming == v:
		return
	aiming = v
	if not v:
		in_reach = 0
	else:
		_aim_accum = 0.0
		in_reach = count_in_reach()
	_update_facing()
	aim_changed.emit(aiming, in_reach)
	EventBus.melee_aim_changed.emit(actor, aiming, in_reach)


## Direction a swing started now would go.
func attack_direction() -> Vector3:
	if aiming and (aim_direction.x != 0.0 or aim_direction.z != 0.0):
		return Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	if actor:
		return actor.facing_vector()
	return Vector3.FORWARD


func _can_act() -> bool:
	if actor == null or not actor.is_inside_tree():
		return false
	if actor.is_dead():
		_refuse("Can't fight now")
		return false
	if actor.is_busy:
		_refuse("Busy")
		return false
	return true


func _refuse(reason: String) -> void:
	last_refusal = reason
	EventBus.attack_refused.emit(actor, reason)


## (damage multiplier, swing time multiplier) from the actor's pain.
func pain_modifiers() -> Vector2:
	var inj := actor.injuries if actor else null
	if inj == null:
		return Vector2.ONE
	return InjuryComponent.pain_combat_modifiers(inj.pain(), inj.profile)


func _begin_swing(w: WeaponData, item: ItemInstance, charge: float) -> bool:
	if actor.stats.get_value(Character.STAMINA) < w.stamina_cost:
		_refuse("Too tired to shove" if w.is_shove else "Too tired to swing")
		return false
	last_refusal = ""
	actor.stats.modify(Character.STAMINA, -w.stamina_cost)
	var pain := pain_modifiers()
	var slow: float = actor.swing_time_multiplier() if actor.has_method(&"swing_time_multiplier") else 1.0
	swing.begin(w, item if item != null and item.data == w else null, charge, attack_direction(), pain.y * slow)
	last_hits = []
	_set_modifier(&"attack", profile.swing_speed_multiplier)
	_update_facing()
	swing_started.emit(w, swing.direction, charge)
	EventBus.melee_swing.emit(actor, w.id, charge)
	if not w.is_shove:
		SoundManager.emit_sound(&"melee_swing", actor.global_position, actor)
	return true


# --- Tick ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if actor == null:
		return
	if actor.is_dead():
		if swing.phase != Phase.IDLE:
			_interrupt()
		return
	if actor.is_busy and (swing.phase == Phase.CHARGING or swing.phase == Phase.WINDUP):
		# Climbing / bandaging took the body: charge and swing are lost,
		# and so is anything queued behind them.
		_interrupt()
	match swing.tick(delta):
		&"active":
			_resolve()
		&"recovery":
			_set_modifier(&"attack", 1.0)
		&"done":
			var q := swing.finish()
			_after_finish()
			_start_queued(q)
	if aiming:
		_aim_accum += delta
		if _aim_accum >= 1.0 / maxf(profile.aim_refresh_hz, 0.1):
			_aim_accum = 0.0
			var n := count_in_reach()
			if n != in_reach:
				in_reach = n
				aim_changed.emit(aiming, in_reach)
				EventBus.melee_aim_changed.emit(actor, aiming, in_reach)
	_update_facing()


## Abort whatever is going on (charge, swing, queue).
func _interrupt() -> void:
	var was_swinging := swing.is_swinging()
	swing.finish()
	_set_modifier(&"charge", 1.0)
	if was_swinging:
		_after_finish()
	else:
		_update_facing()


func _after_finish() -> void:
	_set_modifier(&"attack", 1.0)
	_update_facing()
	if swing.weapon != null:
		swing_finished.emit(swing.weapon)


func _start_queued(q: Dictionary) -> void:
	if not q.queued:
		return
	if q.shove:
		shove()
		return
	if not _can_act():
		return
	if q.held:
		# Still holding: keep charging from where the hold began.
		swing.resume_charge(q.charge_time)
		_set_modifier(&"charge", profile.charge_speed_multiplier)
		return
	_begin_swing(weapon(), equipped, charge_multiplier_for(q.charge_time))


func _update_facing() -> void:
	if actor == null:
		return
	if swing.phase == Phase.WINDUP or swing.phase == Phase.ACTIVE:
		actor.facing_override = swing.direction
	elif aiming and (aim_direction.x != 0.0 or aim_direction.z != 0.0):
		actor.facing_override = Vector3(aim_direction.x, 0.0, aim_direction.z).normalized()
	else:
		actor.facing_override = Vector3.ZERO


func _set_modifier(key: StringName, v: float) -> void:
	if actor and actor.movement:
		actor.movement.set_modifier(key, v)


# --- Targets --------------------------------------------------------------------------

## Targets [w] would hit swinging along [direction] right now (with LOS).
func targets_for(w: WeaponData, direction: Vector3) -> Array[Node3D]:
	return resolver.targets_for(actor, w, direction)


## How many targets are inside the current weapon's arc and reach along
## the aim direction (uncapped by max_targets).
func count_in_reach() -> int:
	if actor == null or resolver == null:
		return 0
	return resolver.targets_for(actor, weapon(), attack_direction(), 64).size()


# --- Resolve ------------------------------------------------------------------------------

func _resolve() -> void:
	var w := swing.weapon
	var stamina_mult := HitResolver.stamina_damage_multiplier(actor.exhausted,
		actor.stats.is_in_state(Character.STAMINA, &"low"),
		profile.exhausted_damage_multiplier, profile.low_stamina_damage_multiplier)
	var mult := swing.charge * stamina_mult * pain_modifiers().x
	var r := resolver.resolve(actor, w, swing.item, swing.direction, mult, swing.charge)
	last_hits = r.hits
	if swing.item != null and not r.hits.is_empty() and not w.is_shove and w.has_condition():
		_on_item_worn(swing.item, r.broke)
	active_started.emit(w, swing.direction, last_hits)


func _on_item_worn(item: ItemInstance, broke: bool) -> void:
	if equipped == item:
		EventBus.weapon_condition_changed.emit(actor, item_summary())
	if not broke:
		return
	var w := item.data
	EventBus.weapon_broken.emit(actor, {"id": w.id, "name": w.display_name, "condition": 0, "max_condition": w.max_condition})
	# The owner removes it (Equipment → equipped_changed → fists).
	if actor.has_method(&"on_weapon_broken"):
		actor.call(&"on_weapon_broken", item)
	if equipped == item:
		_set_equipped(null)
