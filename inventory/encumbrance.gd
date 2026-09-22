class_name Encumbrance
extends Node
## Carried weight → encumbrance state → effects (child "Encumbrance" of a
## Character that has `inventory` + an Equipment child).
##
## Carried weight = main inventory (a bag carried there counts in full)
## + items in the hands + the worn bag's own weight + its contents ×
## (1 − weight_reduction). States against the CharacterStatsProfile
## "Carrying" numbers (player: 8 / 12 / 15 kg):
##
## | state      | weight      | speed | stamina drain | footsteps | sprint |
## |------------|-------------|-------|---------------|-----------|--------|
## | ok         | ≤ 8         | ×1    | ×1            | ×1        | yes    |
## | light      | 8 – 12      | ×0.92 | ×1.15         | ×1        | yes    |
## | heavy      | 12 – 15     | ×0.85 | ×1.3          | ×1.2      | yes    |
## | overloaded | > 15        | ×0.65 | ×1.7          | ×1.35     | "Too heavy" |
##
## Effects go through the existing hooks only: MovementComponent modifier
## &"encumbrance", StatsComponent drain multiplier on stamina,
## FootstepEmitter radius multiplier, Character sprint lock; a worn bag
## with a `worn_speed_multiplier` (duffel ×0.97) adds the movement
## modifier &"worn_bag".
##
## Coalesced: carried-container changes only mark_dirty(); the weight is
## recomputed once, deferred to the end of the frame (reading [state] /
## [weight] flushes early), and EventBus.encumbrance_changed(character,
## state, weight) fires only when the FINAL weight or state differs — a
## transfer's intermediate "item belongs nowhere" step never flickers the
## state. The math is static and pure (unit-tested).

const SOURCE := &"encumbrance"
const OK := &"ok"
const LIGHT := &"light"
const HEAVY := &"heavy"
const OVERLOADED := &"overloaded"
const STATES: Array[StringName] = [OK, LIGHT, HEAVY, OVERLOADED]
const REASON_TOO_HEAVY := "Too heavy"
const SOURCE_BAG := &"worn_bag"

var character: Character
## Current state / carried weight (reading flushes a pending recompute).
var state: StringName:
	get:
		_flush()
		return _state
var weight: float:
	get:
		_flush()
		return _weight
## Number of encumbrance_changed emissions (tests / debugging).
var emit_count: int = 0

var _state: StringName = OK
var _weight: float = 0.0
var _dirty: bool = false
var _flush_queued: bool = false


func setup(c: Character) -> void:
	character = c
	recompute()


## Something carried changed: recompute once, at the end of the frame.
func mark_dirty() -> void:
	_dirty = true
	if not _flush_queued and is_inside_tree():
		_flush_queued = true
		call_deferred(&"_deferred_flush")


func _deferred_flush() -> void:
	_flush_queued = false
	_flush()


## Recompute the weight / state and apply the effects now.
func recompute() -> void:
	_dirty = true
	_flush()


func _flush() -> void:
	if not _dirty:
		return
	_dirty = false
	if character == null or not is_instance_valid(character):
		return
	var eq: Equipment = character.get_node_or_null("Equipment") as Equipment
	var main := ContainerAccess.inventory_of(character)
	var hands: Array = []
	var bags: Array = []
	if eq != null:
		hands = eq.hand_items()
		if eq.back_bag() != null:
			bags.append(eq.back_bag())
	var w := carried_weight(main, hands, bags)
	var p := character.profile
	var s := state_for(w, p.carry_capacity, p.carry_heavy_kg, p.carry_overloaded_kg) if p else OK
	var changed := s != _state or absf(w - _weight) > 0.0005
	_weight = w
	_state = s
	_apply(bags)
	if changed:
		emit_count += 1
		EventBus.encumbrance_changed.emit(character, _state, _weight)


## Capacity the HUD shows the weight against ("12.4 / 8 kg").
func capacity() -> float:
	return character.profile.carry_capacity if character and character.profile else 8.0


func _apply(worn_bags: Array) -> void:
	var e := effects_for(_state, character.profile)
	character.movement.set_modifier(SOURCE, e.speed)
	var bag_mult := 1.0
	for b in worn_bags:
		if (b as ItemInstance).data is ContainerItemData:
			bag_mult *= ((b as ItemInstance).data as ContainerItemData).worn_speed_multiplier
	character.movement.set_modifier(SOURCE_BAG, bag_mult)
	character.stats.set_drain_multiplier(StatsComponent.STAMINA, SOURCE, e.drain)
	var steps := character.get_node_or_null("Footsteps") as FootstepEmitter
	if steps:
		steps.set_multiplier(SOURCE, e.noise)
	character.set_sprint_lock(SOURCE, "" if e.sprint else REASON_TOO_HEAVY)


# --- Pure math ------------------------------------------------------------------

## Weight a worn bag adds: its own weight + contents × (1 − reduction).
static func worn_bag_weight(bag: ItemInstance) -> float:
	if bag == null or bag.data == null:
		return 0.0
	var red := 0.0
	if bag.data is ContainerItemData:
		red = clampf((bag.data as ContainerItemData).weight_reduction, 0.0, 1.0)
	var inner := bag.contents.total_weight() if bag.contents != null else 0.0
	return bag.data.weight * bag.stack + inner * (1.0 - red)


## main inventory (full) + hand items (full) + worn bags (reduced).
static func carried_weight(main: ItemContainer, hand_items: Array, worn_bags: Array) -> float:
	var w := main.total_weight() if main != null else 0.0
	for it in hand_items:
		if it != null:
			w += (it as ItemInstance).total_weight()
	for b in worn_bags:
		w += worn_bag_weight(b)
	return w


## ok ≤ capacity < light ≤ heavy_kg < heavy ≤ overloaded_kg < overloaded.
static func state_for(w: float, capacity_kg: float, heavy_kg: float, overloaded_kg: float) -> StringName:
	const EPS := 0.0001
	if w > overloaded_kg + EPS:
		return OVERLOADED
	if w > heavy_kg + EPS:
		return HEAVY
	if w > capacity_kg + EPS:
		return LIGHT
	return OK


## {speed, drain, noise, sprint} for [s] from the profile's numbers.
static func effects_for(s: StringName, p: CharacterStatsProfile) -> Dictionary:
	if p == null:
		p = CharacterStatsProfile.new()
	match s:
		LIGHT:
			return {"speed": p.encumbrance_speed_light, "drain": p.encumbrance_drain_light, "noise": 1.0, "sprint": true}
		HEAVY:
			return {"speed": p.encumbrance_speed_heavy, "drain": p.encumbrance_drain_heavy, "noise": p.encumbrance_noise_heavy, "sprint": true}
		OVERLOADED:
			return {"speed": p.encumbrance_speed_overloaded, "drain": p.encumbrance_drain_overloaded, "noise": p.encumbrance_noise_overloaded, "sprint": false}
	return {"speed": 1.0, "drain": 1.0, "noise": 1.0, "sprint": true}


## "Light load" … for HUD text.
static func state_label(s: StringName) -> String:
	match s:
		LIGHT: return "Light load"
		HEAVY: return "Heavy load"
		OVERLOADED: return "Overloaded"
	return "OK"
