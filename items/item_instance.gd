class_name ItemInstance
extends RefCounted
## One concrete item: a pointer to its ItemData plus its own condition and
## stack count. Plain object so it can live in hands, containers or the
## save file (to_dict / from_dict).
##
## Round 6: an instance of a ContainerItemData (a bag) owns an
## ItemContainer [contents] (capacity = the data's capacity_kg) whose
## weight counts toward the bag's own weight (total_weight) — a bag
## carried in the main inventory or lying on the ground counts in full;
## only a worn bag gets its weight_reduction (Encumbrance). Every
## instance gets a monotonic [uid] (stable weapon-cycle order).
##
## Round 7: [portion] (1 = whole; a half-eaten item is 0.5, never stacks,
## weighs half) and spoilage for perishable food (FoodData.fresh_days >
## 0): [created_minute] (TimeManager game minute) and an effective
## [age_minutes] that grows lazily by the elapsed game time × the rate of
## the container holding it (ItemContainer.spoil_multiplier: a fridge
## 0.25). Stacks only merge with the same spoil state; the merged stack
## keeps the older age.

signal condition_changed(value: int, max_value: int)
signal broken

static var _next_uid: int = 1

var data: ItemData
var condition: int = 0
var stack: int = 1
## Creation order (unique per run): X cycles weapons in this order.
var uid: int = 0
## Contents of a bag (ContainerItemData); null for every other item.
var contents: ItemContainer = null
## Weak back-reference to the ItemContainer holding this stack (set /
## cleared by ItemContainer only). One instance lives in at most one
## container: add() refuses an instance owned by another container.
var _owner_ref: WeakRef = null
## Fraction of one item left (half-eaten food: 0.5). Only < 1 on single items.
var portion: float = 1.0
## Game minute (TimeManager) this instance was created.
var created_minute: float = 0.0
## Effective spoil age in game minutes (container rate applied), updated
## lazily by sync_age().
var age_minutes: float = 0.0
var _age_stamp: float = 0.0
## TimeManager.epoch of [_age_stamp] (a loaded / reset clock re-stamps).
var _age_epoch: int = 0
var _age_rate: float = 1.0


## The ItemContainer holding this stack, or null.
func owner_container() -> ItemContainer:
	return _owner_ref.get_ref() as ItemContainer if _owner_ref != null else null


func _set_owner_container(c: RefCounted) -> void:
	_owner_ref = weakref(c) if c != null else null
	if perishable():
		set_age_rate(float(c.get("spoil_multiplier")) if c != null else 1.0)


func _init(p_data: ItemData = null, p_condition: int = -1, p_stack: int = 1) -> void:
	uid = _next_uid
	_next_uid += 1
	data = p_data
	if data != null:
		condition = data.max_condition if p_condition < 0 else clampi(p_condition, 0, data.max_condition)
	stack = maxi(p_stack, 1)
	if data is ContainerItemData:
		contents = ItemContainer.new((data as ContainerItemData).capacity_kg)
		contents._set_owner_item(self)
	created_minute = _clock()
	_age_stamp = created_minute
	_age_epoch = _epoch()


## Current game minute (TimeManager autoload).
static func _clock() -> float:
	return TimeManager.now()


static func _epoch() -> int:
	return TimeManager.epoch


# --- Spoilage / portions (Round 7) ---------------------------------------------

## Food that goes stale / rotten with age.
func perishable() -> bool:
	return data is FoodData and (data as FoodData).spoils()


## Bring [age_minutes] up to [now] (default: the TimeManager clock). A
## clock from another epoch (loaded / reset world) or one that went
## backwards only re-stamps: saved ages are elapsed minutes, never
## absolute stamps, so loading items before or after the clock is the same.
func sync_age(now: float = NAN) -> void:
	if is_nan(now):
		now = _clock()
	var ep := _epoch()
	if ep == _age_epoch and now > _age_stamp:
		age_minutes += (now - _age_stamp) * _age_rate
	_age_stamp = now
	_age_epoch = ep


## Age from now on at [rate] × game time (fridge 0.25).
func set_age_rate(rate: float, now: float = NAN) -> void:
	sync_age(now)
	_age_rate = maxf(rate, 0.0)


func age_rate() -> float:
	return _age_rate


## Effective age in game minutes (synced).
func effective_age(now: float = NAN) -> float:
	sync_age(now)
	return age_minutes


## FoodData.SpoilState (FRESH for anything that does not spoil).
func spoil_state(now: float = NAN) -> int:
	if not perishable():
		return FoodData.SpoilState.FRESH
	return (data as FoodData).spoil_state(effective_age(now))


## &"fresh" / &"stale" / &"rotten" (&"" when it does not spoil).
func spoil_id() -> StringName:
	return FoodData.SPOIL_IDS[spoil_state()] if perishable() else &""


func is_partial() -> bool:
	return portion < 0.999


## Merging [other] into this stack: the stack keeps the older age.
func absorb_age(other: ItemInstance) -> void:
	if not perishable() or other == null:
		return
	sync_age()
	other.sync_age()
	age_minutes = maxf(age_minutes, other.age_minutes)
	created_minute = minf(created_minute, other.created_minute)


func id() -> StringName:
	return data.id if data else &""


func display_name() -> String:
	return data.display_name if data else ""


func is_weapon() -> bool:
	return data is WeaponData


## A bag (ContainerItemData with contents).
func is_bag() -> bool:
	return contents != null


func is_two_handed() -> bool:
	return data is WeaponData and (data as WeaponData).two_handed


func is_broken() -> bool:
	return data != null and data.has_condition() and condition <= 0


func condition_fraction() -> float:
	if data == null or not data.has_condition():
		return 1.0
	return float(condition) / float(data.max_condition)


## Lose [amount] condition points. Returns true when this broke the item.
func wear(amount: int) -> bool:
	if data == null or not data.has_condition() or amount <= 0 or condition <= 0:
		return false
	condition = maxi(condition - amount, 0)
	condition_changed.emit(condition, data.max_condition)
	if condition == 0:
		broken.emit()
		return true
	return false


## Weight of one item of this stack incl. a bag's contents (kg). This is
## what capacity checks use.
func unit_weight() -> float:
	if data == null:
		return 0.0
	return data.weight * portion + (contents.total_weight() if contents != null else 0.0)


## Weight of the whole stack incl. a bag's contents (kg).
func total_weight() -> float:
	if data == null:
		return 0.0
	return data.weight * stack * portion + (contents.total_weight() if contents != null else 0.0)


## True when [other] could merge into this stack (same id, stackable).
func can_stack_with(other: ItemInstance) -> bool:
	return other != null and data != null and other.data != null \
			and other.data.id == data.id and data.is_stackable() \
			and contents == null and other.contents == null \
			and not is_partial() and not other.is_partial() \
			and spoil_state() == other.spoil_state()


## Take [n] items off this stack as a new instance (same data/condition).
## n >= stack returns a copy of everything (caller removes this one).
func split(n: int) -> ItemInstance:
	n = clampi(n, 1, stack)
	var out := ItemInstance.new(data, condition, n)
	stack -= n
	out.portion = portion
	if perishable():
		sync_age()
		out.age_minutes = age_minutes
		out.created_minute = created_minute
		out._age_stamp = _age_stamp
		out._age_epoch = _age_epoch
	return out


func to_dict() -> Dictionary:
	var d := {"id": String(id()), "path": data.resource_path if data else "", "condition": condition, "count": stack}
	_spoil_to_dict(d)
	if contents != null and not contents.is_empty():
		d["contents"] = contents.to_dict()
	return d


## Rebuild from to_dict() / ItemContainer entries ({id, count, condition,
## contents?}; the old "stack" key is accepted as a fallback).
## The id is resolved through ItemDB; the path is a fallback. A bag's
## "contents" are restored too (nested bags recurse).
static func from_dict(d: Dictionary) -> ItemInstance:
	var res: ItemData = null
	var id := StringName(String(d.get("id", "")))
	if id != &"":
		res = ItemDB.get_item(id)
	if res == null and String(d.get("path", "")) != "":
		res = load(String(d.get("path", "")))
	if res == null:
		return null
	# "count" everywhere (ItemContainer entries too); "stack" is the
	# pre-Round-6 key, still read.
	var n := int(d.get("count", d.get("stack", 1)))
	var inst := ItemInstance.new(res, int(d.get("condition", -1)), n)
	if inst.contents != null and d.has("contents") and d.contents is Dictionary:
		var cd: Dictionary = (d.contents as Dictionary).duplicate()
		cd.erase("capacity")  # the data decides the bag's capacity
		inst.contents.from_dict(cd)
	inst._spoil_from_dict(d)
	return inst


## Adds portion / age (only when they matter) to a save entry.
func _spoil_to_dict(d: Dictionary) -> void:
	if is_partial():
		d["portion"] = portion
	if perishable():
		d["age"] = effective_age()


func _spoil_from_dict(d: Dictionary) -> void:
	portion = clampf(float(d.get("portion", 1.0)), 0.01, 1.0)
	if d.has("age"):
		age_minutes = maxf(float(d.age), 0.0)
		created_minute = _clock() - age_minutes
		_age_stamp = _clock()
		_age_epoch = _epoch()
