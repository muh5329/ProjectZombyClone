class_name SpatialHash
extends RefCounted
## Uniform grid on the XZ plane: integer ids → cells of [cell_size] metres.
## insert / update / remove are O(1); query_radius visits only the cells
## overlapping the circle. Used by SoundManager so a sound is dispatched to
## the listeners near it, not to every zombie on the map.

var cell_size: float = 8.0
## Vector2i cell -> Array[int] ids.
var _cells: Dictionary = {}
## id -> Vector2i cell.
var _where: Dictionary = {}
## id -> Vector3 last known position.
var _pos: Dictionary = {}


func _init(p_cell_size: float = 8.0) -> void:
	cell_size = maxf(p_cell_size, 0.1)


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))


func size() -> int:
	return _where.size()


func cell_count() -> int:
	return _cells.size()


func has(id: int) -> bool:
	return _where.has(id)


func position_of(id: int) -> Vector3:
	return _pos.get(id, Vector3.INF)


func insert(id: int, p: Vector3) -> void:
	if _where.has(id):
		update(id, p)
		return
	var c := cell_of(p)
	_where[id] = c
	_pos[id] = p
	var arr: Array = _cells.get(c, [])
	if arr.is_empty():
		_cells[c] = arr
	arr.append(id)


## Move [id] to [p]. Returns true when it changed cell.
func update(id: int, p: Vector3) -> bool:
	if not _where.has(id):
		insert(id, p)
		return true
	_pos[id] = p
	var c := cell_of(p)
	var old: Vector2i = _where[id]
	if c == old:
		return false
	_remove_from_cell(id, old)
	_where[id] = c
	var arr: Array = _cells.get(c, [])
	if arr.is_empty():
		_cells[c] = arr
	arr.append(id)
	return true


func remove(id: int) -> bool:
	if not _where.has(id):
		return false
	_remove_from_cell(id, _where[id])
	_where.erase(id)
	_pos.erase(id)
	return true


func clear() -> void:
	_cells.clear()
	_where.clear()
	_pos.clear()


## Ids whose cell overlaps the circle (center [p], [radius]) — a superset
## of the ids within [radius]; callers do the exact distance test.
func query_radius(p: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	var r := maxf(radius, 0.0)
	var c0 := cell_of(p - Vector3(r, 0.0, r))
	var c1 := cell_of(p + Vector3(r, 0.0, r))
	# A huge radius on a small population: just return everything.
	if (c1.x - c0.x + 1) * (c1.y - c0.y + 1) > _cells.size() * 2:
		for c: Vector2i in _cells:
			out.append_array(_cells[c])
		return out
	for x in range(c0.x, c1.x + 1):
		for z in range(c0.y, c1.y + 1):
			var arr: Variant = _cells.get(Vector2i(x, z))
			if arr != null:
				out.append_array(arr)
	return out


## Exact: ids whose stored position is within [radius] (flat) of [p].
func query_exact(p: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	var r2 := radius * radius
	for id in query_radius(p, radius):
		var q: Vector3 = _pos[id]
		var dx := q.x - p.x
		var dz := q.z - p.z
		if dx * dx + dz * dz <= r2:
			out.append(id)
	return out


func _remove_from_cell(id: int, c: Vector2i) -> void:
	var arr: Variant = _cells.get(c)
	if arr == null:
		return
	(arr as Array).erase(id)
	if (arr as Array).is_empty():
		_cells.erase(c)
