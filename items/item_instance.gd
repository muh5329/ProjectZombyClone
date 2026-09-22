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


## The ItemContainer holding this stack, or null.
func owner_container() -> ItemContainer:
	return _owner_ref.get_ref() as ItemContainer if _owner_ref != null else null


func _set_owner_container(c: RefCounted) -> void:
	_owner_ref = weakref(c) if c != null else null


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
	return data.weight + (contents.total_weight() if contents != null else 0.0)


## Weight of the whole stack incl. a bag's contents (kg).
func total_weight() -> float:
	if data == null:
		return 0.0
	return data.weight * stack + (contents.total_weight() if contents != null else 0.0)


## True when [other] could merge into this stack (same id, stackable).
func can_stack_with(other: ItemInstance) -> bool:
	return other != null and data != null and other.data != null \
			and other.data.id == data.id and data.is_stackable() \
			and contents == null and other.contents == null


## Take [n] items off this stack as a new instance (same data/condition).
## n >= stack returns a copy of everything (caller removes this one).
func split(n: int) -> ItemInstance:
	n = clampi(n, 1, stack)
	var out := ItemInstance.new(data, condition, n)
	stack -= n
	return out


func to_dict() -> Dictionary:
	var d := {"id": String(id()), "path": data.resource_path if data else "", "condition": condition, "count": stack}
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
	return inst
