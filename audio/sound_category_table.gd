class_name SoundCategoryTable
extends Resource
## All gameplay sound categories (data/audio/sound_categories.tres).
## Lookup by id; unknown ids return null (SoundManager falls back to the
## emitter's overrides).

@export var categories: Array[SoundCategory] = []
## Player noise at least this big (m) counts as LOUD: HUD noise meter
## tick + red, and the noise ring's warning colour. One number for both.
@export var player_loud_radius: float = 10.0

var _by_id: Dictionary = {}


func get_category(id: StringName) -> SoundCategory:
	if _by_id.size() != categories.size():
		_index()
	return _by_id.get(id)


func has_category(id: StringName) -> bool:
	return get_category(id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for c in categories:
		out.append(c.id)
	return out


func _index() -> void:
	_by_id.clear()
	for c in categories:
		if c != null:
			_by_id[c.id] = c
