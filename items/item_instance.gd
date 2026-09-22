class_name ItemInstance
extends RefCounted
## One concrete item: a pointer to its ItemData plus its own condition and
## stack count. Plain object so it can live in hands, containers or the
## save file (to_dict / from_dict).

signal condition_changed(value: int, max_value: int)
signal broken

var data: ItemData
var condition: int = 0
var stack: int = 1
## Weak back-reference to the ItemContainer holding this stack (set /
## cleared by ItemContainer only). One instance lives in at most one
## container: add() refuses an instance owned by another container.
var _owner_ref: WeakRef = null


## The ItemContainer holding this stack, or null.
func owner_container() -> RefCounted:
	return _owner_ref.get_ref() as RefCounted if _owner_ref != null else null


func _set_owner_container(c: RefCounted) -> void:
	_owner_ref = weakref(c) if c != null else null


func _init(p_data: ItemData = null, p_condition: int = -1, p_stack: int = 1) -> void:
	data = p_data
	if data != null:
		condition = data.max_condition if p_condition < 0 else clampi(p_condition, 0, data.max_condition)
	stack = maxi(p_stack, 1)


func id() -> StringName:
	return data.id if data else &""


func display_name() -> String:
	return data.display_name if data else ""


func is_weapon() -> bool:
	return data is WeaponData


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


## Weight of the whole stack (kg).
func total_weight() -> float:
	return data.weight * stack if data else 0.0


## True when [other] could merge into this stack (same id, stackable).
func can_stack_with(other: ItemInstance) -> bool:
	return other != null and data != null and other.data != null \
			and other.data.id == data.id and data.is_stackable()


## Take [n] items off this stack as a new instance (same data/condition).
## n >= stack returns a copy of everything (caller removes this one).
func split(n: int) -> ItemInstance:
	n = clampi(n, 1, stack)
	var out := ItemInstance.new(data, condition, n)
	stack -= n
	return out


func to_dict() -> Dictionary:
	return {"id": String(id()), "path": data.resource_path if data else "", "condition": condition, "stack": stack}


## Rebuild from to_dict() (or from {id, count, condition} save entries).
## The id is resolved through ItemDB; the path is a fallback.
static func from_dict(d: Dictionary) -> ItemInstance:
	var res: ItemData = null
	var id := StringName(String(d.get("id", "")))
	if id != &"":
		res = ItemDB.get_item(id)
	if res == null and String(d.get("path", "")) != "":
		res = load(String(d.get("path", "")))
	if res == null:
		return null
	var n := int(d.get("stack", d.get("count", 1)))
	return ItemInstance.new(res, int(d.get("condition", -1)), n)
