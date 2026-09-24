class_name SaveFile
extends RefCounted
## Save files on disk (Round 10): slots, JSON, schema version +
## migration hook, validation, atomic writes. Pure statics — the
## SaveManager autoload orchestrates, WorldSnapshot captures / applies.
##
## Layout: user://saves/<slot>/world.json (the world, deterministic: the
## same world always serializes to the same bytes) + meta.json (version,
## timestamp, game time, player summary — what a slot list shows).
## Writes go to "<file>.tmp" first and are renamed over the old file, so a
## crash mid-write leaves the previous save intact.

const VERSION := 2
const ROOT := "user://saves"
## Where the tests / tools write (SaveManager switches to it when a test
## runner, the screenshot run or a perf probe is the main loop).
const TEST_ROOT := "user://test_saves"
const MAPS_DIR := "res://maps"
const MAX_SLOT_LENGTH := 48
const WORLD_FILE := "world.json"
const META_FILE := "meta.json"
const TMP_SUFFIX := ".tmp"
const OLD_SUFFIX := ".old"
## Top-level keys every world.json must have, with their JSON types.
const REQUIRED := {
	"version": TYPE_FLOAT, "map": TYPE_STRING, "world": TYPE_DICTIONARY,
	"time": TYPE_DICTIONARY, "player": TYPE_DICTIONARY, "statics": TYPE_DICTIONARY,
}

## Migration hook: {from_version (int): Callable(data: Dictionary) ->
## Dictionary returning the data at from_version + 1}. Version 1 is the
## first schema, so the table starts empty; tests register a fake 0 → 1.
static var migrations: Dictionary = {}
## The saves directory in use (ROOT, or TEST_ROOT for tests / tools).
static var root: String = ROOT


# --- Paths ---------------------------------------------------------------------------

## True for a slot name the player may use: 1..MAX_SLOT_LENGTH characters
## after trimming ("" is refused, never mapped to a default).
static func is_valid_slot(slot: String) -> bool:
	var t := slot.strip_edges()
	return t != "" and t.length() <= MAX_SLOT_LENGTH


## Slot name → directory name, injective: letters, digits and "-" are
## kept, every other byte (space, "_", "/", "."…) becomes "_xx" (hex), so
## two different names never share a directory. "" for an invalid name.
static func encode_slot(slot: String) -> String:
	if not is_valid_slot(slot):
		return ""
	var out := ""
	for b in slot.strip_edges().to_utf8_buffer():
		var ch := char(b)
		if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 45:
			out += ch
		else:
			out += "_%02x" % b
	return out


## Directory name → slot name ("" when it is not an encoded name).
static func decode_slot(dir_name: String) -> String:
	var bytes := PackedByteArray()
	var i := 0
	while i < dir_name.length():
		var ch := dir_name[i]
		if ch == "_":
			var hx := dir_name.substr(i + 1, 2)
			if hx.length() != 2 or not hx.is_valid_hex_number():
				return ""
			bytes.append(hx.hex_to_int())
			i += 3
		else:
			bytes.append(ch.unicode_at(0))
			i += 1
	return bytes.get_string_from_utf8()


static func slot_dir(slot: String) -> String:
	var enc := encode_slot(slot)
	return "%s/%s" % [root, enc] if enc != "" else ""


static func world_path(slot: String) -> String:
	var d := slot_dir(slot)
	return "%s/%s" % [d, WORLD_FILE] if d != "" else ""


static func meta_path(slot: String) -> String:
	var d := slot_dir(slot)
	return "%s/%s" % [d, META_FILE] if d != "" else ""


## Maps a save may name: the scenes in res://maps (never another path).
static func allowed_maps() -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(MAPS_DIR)
	if da == null:
		return out
	for f in da.get_files():
		var fname := f.trim_suffix(".remap")
		if fname.ends_with(".tscn") and not out.has("%s/%s" % [MAPS_DIR, fname]):
			out.append("%s/%s" % [MAPS_DIR, fname])
	return out


static func allowed_map(path: String) -> bool:
	return allowed_maps().has(path)


# --- JSON --------------------------------------------------------------------------------

## Deterministic JSON: sorted keys, full float precision (a load → save
## round trip reproduces the same text).
static func to_json(data: Dictionary) -> String:
	return JSON.stringify(data, "", true, true)


## {ok, data, error}. Anything that is not a JSON object is refused.
static func parse(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": false, "error": "Save file is empty"}
	var j := JSON.new()
	var err := j.parse(text)
	if err != OK:
		return {"ok": false, "error": "Corrupt save (JSON error line %d: %s)" % [j.get_error_line(), j.get_error_message()]}
	if not j.data is Dictionary:
		return {"ok": false, "error": "Corrupt save (not a JSON object)"}
	return {"ok": true, "data": j.data}


# --- Version / validation --------------------------------------------------------------

## Bring [data] up to VERSION through [migrations]. {ok, data, error}.
static func migrate(data: Dictionary) -> Dictionary:
	if not (data.get("version") is float or data.get("version") is int):
		return {"ok": false, "error": "Corrupt save (no version)"}
	var v := int(data.version)
	if v > VERSION:
		return {"ok": false, "error": "Save is from a newer version (%d > %d)" % [v, VERSION]}
	var d := data
	while v < VERSION:
		var mig: Callable = migrations.get(v, builtin_migration(v))
		if not mig.is_valid():
			return {"ok": false, "error": "Save version %d is too old (no migration)" % v}
		d = mig.call(d.duplicate(true))
		if d == null or not d is Dictionary:
			return {"ok": false, "error": "Migration from version %d failed" % v}
		v += 1
		d["version"] = v
	return {"ok": true, "data": d}


## The migrations that ship with the game (tests add their own through
## [migrations], which win).
static func builtin_migration(from_version: int) -> Callable:
	match from_version:
		1:
			return migrate_1_to_2
	return Callable()


## Round 12: version 2 = streamed worlds. Hand-made maps keep the Round-10
## format unchanged. A Round-11 generated-world save (every static in
## full, dropped items / corpses / blood as flat lists) becomes a streamed
## one: its statics are the store's deltas (objects equal to their
## default are pruned on the next unload), items / corpses / blood move
## into the record of the chunk they lie in, and the population is
## generated from the seed minus the start pack and the rural groups the
## save had already spawned (those are in its zombie records).
static func migrate_1_to_2(d: Dictionary) -> Dictionary:
	var w: Variant = d.get("world")
	if not w is Dictionary or not (w as Dictionary).has("worldgen"):
		return d
	var cs := 64.0
	var gp := String((w as Dictionary).get("worldgen_params", ""))
	if gp.begins_with("res://data/worldgen/") and gp.ends_with(".tres") and not gp.contains("..") and ResourceLoader.exists(gp):
		var prm := load(gp) as WorldGenParams
		if prm != null and prm.chunk_size > 0.0:
			cs = prm.chunk_size
	var t := 0.0
	if d.get("time") is Dictionary:
		t = float((d.time as Dictionary).get("minutes", 0.0))
	var chunks := {}
	var put := func(pos: Variant, key: String, rec: Variant) -> void:
		var p := Saveable.to_vec3(pos)
		var k := WorldStateStore.key(Vector2i(maxi(int(floor(p.x / cs)), 0), maxi(int(floor(p.z / cs)), 0)))
		if not chunks.has(k):
			chunks[k] = {"items": [], "corpses": [], "blood": [], "t": t}
		(chunks[k][key] as Array).append(rec)
	for rec in d.get("items", []):
		if rec is Dictionary:
			put.call(rec.get("position"), "items", rec)
	for rec in d.get("corpses", []):
		if rec is Dictionary:
			put.call(rec.get("position"), "corpses", rec)
	if d.get("blood") is Dictionary:
		for x in (d.blood as Dictionary).get("splats", []):
			if x is Array and (x as Array).size() == 12:
				put.call([x[9], x[10], x[11]], "blood", x)
	d["items"] = []
	d["corpses"] = []
	d.erase("blood")
	d["chunks"] = chunks
	var spawned: Array = []
	if d.get("spawners") is Dictionary:
		for sid in d.spawners:
			var sp: Variant = d.spawners[sid]
			if sp is Dictionary:
				spawned.append_array((sp as Dictionary).get("groups_spawned", []))
	d["population"] = {"legacy": true, "groups_spawned": spawned}
	return d


## "" when [data] (already migrated) is loadable, else the reason: the
## whole snapshot is type-checked by SaveSchema before anything is applied.
static func validate(data: Dictionary) -> String:
	return SaveSchema.check(data)


## Parse + migrate + validate. {ok, data, error}.
static func decode(text: String) -> Dictionary:
	var r := parse(text)
	if not r.ok:
		return r
	var m := migrate(r.data)
	if not m.ok:
		return m
	var why := validate(m.data)
	if why != "":
		return {"ok": false, "error": why}
	return {"ok": true, "data": m.data}


# --- Disk --------------------------------------------------------------------------------

## Write [text] to [path] atomically: <path>.tmp → flush → rename over the
## old file (kept as <path>.old until the rename succeeded). Returns OK or
## the error; the old file is untouched on failure.
static func write_atomic(path: String, text: String) -> Error:
	if path == "":
		return ERR_INVALID_PARAMETER
	var dir := path.get_base_dir()
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	var werr := f.get_error()
	f.close()
	if werr != OK:
		DirAccess.remove_absolute(tmp)
		return werr
	var old := path + OLD_SUFFIX
	var had_old := FileAccess.file_exists(path)
	if had_old:
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
		err = DirAccess.rename_absolute(path, old)
		if err != OK:
			DirAccess.remove_absolute(tmp)
			return err
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		if had_old:
			DirAccess.rename_absolute(old, path)  # put the old save back
		return err
	if had_old:
		DirAccess.remove_absolute(old)
	return OK


## {ok, text, error}. Falls back to <path>.old when a crash happened
## between the two renames.
static func read_text(path: String) -> Dictionary:
	if path == "":
		return {"ok": false, "error": "Invalid save name"}
	var p := path
	if not FileAccess.file_exists(p) and FileAccess.file_exists(path + OLD_SUFFIX):
		p = path + OLD_SUFFIX
	if not FileAccess.file_exists(p):
		return {"ok": false, "error": "No save in this slot"}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Can't open save (%s)" % error_string(FileAccess.get_open_error())}
	var text := f.get_as_text()
	f.close()
	return {"ok": true, "text": text}


## Saved slots, newest first: [{slot, meta}] — meta is always a
## Dictionary (an unreadable / tampered meta.json gives {}), with typed
## fields read through meta_num / meta_str.
static func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var da := DirAccess.open(root)
	if da == null:
		return out
	for d in da.get_directories():
		var slot := decode_slot(d)
		if slot == "" or encode_slot(slot) != d:
			continue
		if not FileAccess.file_exists(world_path(slot)) and not FileAccess.file_exists(world_path(slot) + OLD_SUFFIX):
			continue
		var meta := {}
		var r := read_text(meta_path(slot))
		if r.ok:
			var pr := parse(r.text)
			if pr.ok and pr.data is Dictionary:
				meta = pr.data
		out.append({"slot": slot, "meta": meta})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return meta_num(a.meta, "timestamp") > meta_num(b.meta, "timestamp"))
	return out


## A finite number from a meta dictionary (or [fallback]).
static func meta_num(meta: Variant, key: String, fallback: float = 0.0) -> float:
	if not meta is Dictionary:
		return fallback
	var v: Variant = (meta as Dictionary).get(key)
	return float(v) if (v is float or v is int) and is_finite(float(v)) else fallback


static func meta_str(meta: Variant, key: String, fallback: String = "") -> String:
	if not meta is Dictionary:
		return fallback
	var v: Variant = (meta as Dictionary).get(key)
	return (v as String).left(80) if v is String else fallback


static func meta_dict(meta: Variant, key: String) -> Dictionary:
	if not meta is Dictionary:
		return {}
	var v: Variant = (meta as Dictionary).get(key)
	return v if v is Dictionary else {}


## Remove a slot directory and its files. True when it existed.
static func delete_slot(slot: String) -> bool:
	var dir := slot_dir(slot)
	if dir == "":
		return false
	var da := DirAccess.open(dir)
	if da == null:
		return false
	for f in da.get_files():
		DirAccess.remove_absolute("%s/%s" % [dir, f])
	return DirAccess.remove_absolute(dir) == OK


## "" when [a] and [b] hold the same save data, else the first differing
## path ("zombies/3/position/0: 1.5 vs 1.6"). Floats compare with a tiny
## relative tolerance: Godot's JSON number parser is not always correctly
## rounded (the last bit of a double may change on a round trip), so
## "identical" means identical data, not identical bytes.
static func first_difference(a: Variant, b: Variant, path: String = "", rel_tol: float = 1e-9) -> String:
	var num_a := a is float or a is int
	var num_b := b is float or b is int
	if num_a and num_b:
		var x := float(a)
		var y := float(b)
		return "" if absf(x - y) <= rel_tol * maxf(1.0, maxf(absf(x), absf(y))) else "%s: %s vs %s" % [path, str(a), str(b)]
	if typeof(a) != typeof(b):
		return "%s: %s vs %s" % [path, str(a), str(b)]
	if a is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		for k in da:
			if not db.has(k):
				return "%s/%s: missing in the second" % [path, k]
			var d := first_difference(da[k], db[k], "%s/%s" % [path, k], rel_tol)
			if d != "":
				return d
		for k in db:
			if not da.has(k):
				return "%s/%s: missing in the first" % [path, k]
		return ""
	if a is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return "%s: %d vs %d entries" % [path, aa.size(), ab.size()]
		for i in aa.size():
			var d := first_difference(aa[i], ab[i], "%s/%d" % [path, i], rel_tol)
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, str(a), str(b)]
