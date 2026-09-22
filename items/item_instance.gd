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


func to_dict() -> Dictionary:
	return {"id": String(id()), "path": data.resource_path if data else "", "condition": condition, "stack": stack}


static func from_dict(d: Dictionary) -> ItemInstance:
	var res: ItemData = load(String(d.get("path", ""))) if String(d.get("path", "")) != "" else null
	return ItemInstance.new(res, int(d.get("condition", -1)), int(d.get("stack", 1)))
