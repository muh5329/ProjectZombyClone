extends Node
## Item registry — autoload `ItemDB` (no class_name: the autoload name is
## the global). On first use it scans res://data/items/ recursively for
## .tres files whose resource is an ItemData and indexes them by id.
##
## Lookups: ItemDB.get_item(id), has_item(id), all_ids(),
## ids_in_category(cat), instance(id, count, condition).
## Duplicate ids are reported with push_error at load (the first file in
## sorted path order wins) and listed by duplicates(). Resources are held
## by this node, which is freed with the tree (no static caches → no leak
## reports at exit).

const ROOT := "res://data/items"

var _items: Dictionary = {}  # StringName id -> ItemData
var _paths: Dictionary = {}  # StringName id -> String path
var _scanned: bool = false
var _duplicates: PackedStringArray = []


func _ready() -> void:
	_ensure()


func get_item(id: StringName) -> ItemData:
	_ensure()
	return _items.get(StringName(id)) as ItemData


func has_item(id: StringName) -> bool:
	_ensure()
	return _items.has(StringName(id))


func path_of(id: StringName) -> String:
	_ensure()
	return String(_paths.get(StringName(id), ""))


## Every registered id, sorted.
func all_ids() -> Array[StringName]:
	_ensure()
	var out: Array[StringName] = []
	for k in _items:
		out.append(k)
	out.sort()
	return out


## Ids of items in [category] (ItemData.Category value).
func ids_in_category(category: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in all_ids():
		if (_items[id] as ItemData).category == category:
			out.append(id)
	return out


## "path: id" strings of duplicate definitions found by the last scan.
func duplicates() -> PackedStringArray:
	_ensure()
	return _duplicates


## New ItemInstance of [id] (null for an unknown id).
func instance(id: StringName, count: int = 1, condition: int = -1) -> ItemInstance:
	var d := get_item(id)
	if d == null:
		return null
	return ItemInstance.new(d, condition, count)


## Re-scan (tests; hot-reloaded data).
func reload() -> void:
	_scanned = false
	_items.clear()
	_paths.clear()
	_duplicates.clear()
	_ensure()


## Register [data] at runtime (tests / mods). Returns false on a duplicate
## id (push_error, like the scan).
func register(data: ItemData, path: String = "<runtime>") -> bool:
	_ensure()
	if data == null or data.id == &"":
		push_error("ItemDB: item without an id (%s)" % path)
		return false
	if _items.has(data.id):
		_duplicates.append("%s: %s" % [path, data.id])
		push_error("ItemDB: duplicate item id '%s' in %s (first: %s)" % [data.id, path, _paths[data.id]])
		return false
	_items[data.id] = data
	_paths[data.id] = path
	return true


func _ensure() -> void:
	if _scanned:
		return
	_scanned = true
	_scan(ROOT)


func _scan(dir_path: String) -> void:
	var da := DirAccess.open(dir_path)
	if da == null:
		return
	var files := da.get_files()
	files.sort()
	for f in files:
		# Exported builds list converted resources as "x.tres.remap".
		var fname := f.trim_suffix(".remap")
		if not fname.ends_with(".tres"):
			continue
		var path := "%s/%s" % [dir_path, fname]
		var res := load(path)
		if res is ItemData:
			register(res as ItemData, path)
	var dirs := da.get_directories()
	dirs.sort()
	for d in dirs:
		_scan("%s/%s" % [dir_path, d])


## Pure: "id" strings that occur more than once in [datas] (ItemData list).
static func find_duplicate_ids(datas: Array) -> PackedStringArray:
	var seen := {}
	var out := PackedStringArray()
	for d in datas:
		if d == null:
			continue
		var id := String(d.id)
		if seen.has(id) and not out.has(id):
			out.append(id)
		seen[id] = true
	return out
