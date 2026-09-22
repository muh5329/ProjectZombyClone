extends Node
## Loot table registry — autoload `LootTableDB` (like ItemDB; no
## class_name). Scans res://data/loot recursively at startup; id = path
## relative to that folder without ".tres" ("fridge", "garage/tool_crate").
## Duplicate ids → push_error.
##
## Selection: resolve(building, room, container) walks the fallback chain
## of LootResolver.table_candidates() — container-specific tables first,
## then the room's, then "default".

const ROOT := "res://data/loot"

var _tables: Dictionary = {}  # id -> LootTable
var _paths: Dictionary = {}
var _scanned: bool = false


func _ready() -> void:
	_ensure()


func get_table(id: String) -> LootTable:
	_ensure()
	return _tables.get(id) as LootTable


func has_table(id: String) -> bool:
	_ensure()
	return _paths.has(id)


func all_ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	for k in _paths:
		out.append(k)
	out.sort()
	return out


## Id of the table used for (building, room, container) ("" when not even
## "default" exists).
func resolve_id(building: StringName, room: StringName, container: StringName) -> String:
	_ensure()
	for id in LootResolver.table_candidates(building, room, container):
		if _paths.has(id):
			return id
	return ""


func resolve(building: StringName, room: StringName, container: StringName) -> LootTable:
	var id := resolve_id(building, room, container)
	return get_table(id) if id != "" else null


func reload() -> void:
	_scanned = false
	_paths.clear()
	_tables.clear()
	_ensure()


func _ensure() -> void:
	if _scanned:
		return
	_scanned = true
	_scan(ROOT, "")


func _scan(dir_path: String, prefix: String) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	var files := da.get_files()
	files.sort()
	for f in files:
		var fname := f.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var path := "%s/%s" % [dir_path, fname]
		var res := load(path)
		if not res is LootTable:
			continue
		var id := prefix + fname.get_basename()
		if _paths.has(id):
			push_error("LootTableDB: duplicate table id '%s' (%s)" % [id, path])
			continue
		_paths[id] = path
		_tables[id] = res
	for d in da.get_directories():
		_scan("%s/%s" % [dir_path, d], prefix + d + "/")
