class_name SaveSchema
extends RefCounted
## Round 10: the FULL typed check of a world.json, run before a load
## touches anything (phase 1 of the two-phase load: validate the whole
## snapshot, then apply). Any wrong type, non-finite / out-of-range
## number, unknown item / profile / enum id or malformed record refuses
## the whole save with the path of the first problem, e.g.
## "Corrupt save (zombies/3/position: not a finite vector)".
## Saves never name files: items are ItemDB ids, zombie profiles registry
## ids, the map an allow-listed res://maps/*.tscn (SaveFile.allowed_map).
##
## The load_state / from_dict methods still clamp what they read
## (defence in depth), but they are only ever given checked data.

const MAX_COORD := 100000.0
const MAX_HEALTH := 100000.0
const MAX_NEST := 8
const MAX_PLANKS := 8
const MAX_STAT := 100000.0
const DOOR_STATES := ["open", "closed", "broken"]
const WINDOW_STATES := ["open", "closed", "smashed"]
const ZOMBIE_STATES := ["idle", "wander", "investigate"]
const CORPSE_POSES := ["death", "knockdown"]
const STATIC_KINDS := ["container", "door", "window", "furniture"]

var error: String = ""


## "" when [data] is a loadable world, else "Corrupt save (<path>: why)".
static func check(data: Variant) -> String:
	var s := SaveSchema.new()
	s._world(data)
	return "" if s.error == "" else "Corrupt save (%s)" % s.error


# --- Primitives (each returns true when fine; the first failure sticks) --------------

func _fail(path: String, why: String) -> bool:
	if error == "":
		error = "%s: %s" % [path, why]
	return false


func _dict(v: Variant, path: String) -> bool:
	return true if v is Dictionary else _fail(path, "not an object")


func _arr(v: Variant, path: String, max_size: int = 100000) -> bool:
	if not v is Array:
		return _fail(path, "not a list")
	return true if (v as Array).size() <= max_size else _fail(path, "too many entries")


func _str(v: Variant, path: String, max_len: int = 256) -> bool:
	if not v is String:
		return _fail(path, "not a string")
	return true if (v as String).length() <= max_len else _fail(path, "too long")


func _bool(v: Variant, path: String) -> bool:
	return true if v is bool else _fail(path, "not true / false")


func _num(v: Variant, path: String, lo: float = -INF, hi: float = INF) -> bool:
	if not (v is float or v is int):
		return _fail(path, "not a number")
	var f := float(v)
	if not is_finite(f):
		return _fail(path, "not finite")
	if f < lo or f > hi:
		return _fail(path, "out of range (%s)" % str(v))
	return true


func _int(v: Variant, path: String, lo: float, hi: float) -> bool:
	if not _num(v, path, lo, hi):
		return false
	return true if is_equal_approx(float(v), roundf(float(v))) else _fail(path, "not a whole number")


func _vec3(v: Variant, path: String, limit: float = MAX_COORD) -> bool:
	if not v is Array or (v as Array).size() != 3:
		return _fail(path, "not a finite vector")
	for i in 3:
		var c: Variant = v[i]
		if not (c is float or c is int) or not is_finite(float(c)) or absf(float(c)) > limit:
			return _fail(path, "not a finite vector")
	return true


func _enum(v: Variant, path: String, allowed: Array) -> bool:
	if not v is String:
		return _fail(path, "not a string")
	return true if allowed.has(v) else _fail(path, "unknown value '%s'" % v)


## Optional key: absent is fine, present must pass [check].
func _opt(d: Dictionary, key: String, path: String, check: Callable) -> bool:
	return true if not d.has(key) else check.call(d[key], "%s/%s" % [path, key])


# --- Records --------------------------------------------------------------------------

func _world(data: Variant) -> void:
	if not _dict(data, "save"):
		return
	var d: Dictionary = data
	if not _int(d.get("version"), "version", 0, 1000000):
		return
	if not _str(d.get("map"), "map") or not SaveFile.allowed_map(String(d.map)):
		_fail("map", "not an allowed map")
		return
	if not _dict(d.get("world"), "world"):
		return
	var w: Dictionary = d.world
	if not (_int(w.get("seed", 0), "world/seed", -9.0e15, 9.0e15) and _num(w.get("age_days", 0.0), "world/age_days", 0.0, 1.0e6)
			and _int(w.get("water_shutoff_day", -1), "world/water_shutoff_day", -1.0, 1.0e6)):
		return
	if not _dict(d.get("time"), "time") or not _num((d.time as Dictionary).get("minutes"), "time/minutes", 0.0, 1.0e9):
		return
	if not _dict(d.get("statics"), "statics"):
		return
	for id in d.statics:
		if not _str(id, "statics") or not _static(d.statics[id], "statics/%s" % id):
			return
	if d.has("destroyed"):
		if not _arr(d.destroyed, "destroyed"):
			return
		for i in (d.destroyed as Array).size():
			if not _str(d.destroyed[i], "destroyed/%d" % i):
				return
	if d.has("spawners"):
		if not _dict(d.spawners, "spawners"):
			return
		for id in d.spawners:
			var sp: Variant = d.spawners[id]
			var p := "spawners/%s" % id
			if not _dict(sp, p) or not _int((sp as Dictionary).get("spawn_counter", 0), p + "/spawn_counter", 0, 1.0e9):
				return
			var st: Variant = (sp as Dictionary).get("rng_state", "0")
			if not st is String or not (st as String).is_valid_int():
				_fail(p + "/rng_state", "not an integer string")
				return
	for key in [WorldSnapshot.KEY_ZOMBIES, WorldSnapshot.KEY_CORPSES, WorldSnapshot.KEY_ITEMS]:
		if not _arr(d.get(key, []), key):
			return
		var list: Array = d.get(key, [])
		for i in list.size():
			var p := "%s/%d" % [key, i]
			var ok := false
			match key:
				WorldSnapshot.KEY_ZOMBIES: ok = _zombie(list[i], p)
				WorldSnapshot.KEY_CORPSES: ok = _corpse(list[i], p)
				_: ok = _world_item(list[i], p)
			if not ok:
				return
	if not _player(d.get("player"), "player"):
		return
	if d.has("blood"):
		if not _dict(d.blood, "blood") or not _arr((d.blood as Dictionary).get("splats", []), "blood/splats", 1000):
			return
		var sp: Array = (d.blood as Dictionary).get("splats", [])
		for i in sp.size():
			if not sp[i] is Array or (sp[i] as Array).size() != 12:
				_fail("blood/splats/%d" % i, "not a transform")
				return
			for j in 12:
				if not _num(sp[i][j], "blood/splats/%d" % i, -MAX_COORD, MAX_COORD):
					return
	if d.has("camera"):
		if not _dict(d.camera, "camera") or not _int((d.camera as Dictionary).get("yaw_index", 0), "camera/yaw_index", -1000, 1000) \
				or not _int((d.camera as Dictionary).get("zoom_index", 0), "camera/zoom_index", -1000, 1000):
			return


func _static(v: Variant, path: String) -> bool:
	if not _dict(v, path):
		return false
	var d: Dictionary = v
	if not _enum(d.get("kind"), path + "/kind", STATIC_KINDS):
		return false
	match String(d.kind):
		"container":
			return _bool(d.get("searched"), path + "/searched") and _container(d.get("inventory", {}), path + "/inventory", 0)
		"door":
			return _enum(d.get("state"), path + "/state", DOOR_STATES) and _num(d.get("health"), path + "/health", 0.0, MAX_HEALTH) \
				and _bool(d.get("locked"), path + "/locked") and _num(d.get("swing", 0.0), path + "/swing", -7.0, 7.0) \
				and _opt(d, "barricade", path, _barricade)
		"window":
			return _enum(d.get("state"), path + "/state", WINDOW_STATES) and _bool(d.get("glass"), path + "/glass") \
				and _num(d.get("pane_hp"), path + "/pane_hp", 0.0, MAX_HEALTH) and _opt(d, "barricade", path, _barricade)
		"furniture":
			return _str(d.get("blocking"), path + "/blocking") and _num(d.get("health"), path + "/health", 0.0, MAX_HEALTH)
	return false


func _barricade(v: Variant, path: String) -> bool:
	if not _dict(v, path) or not _num((v as Dictionary).get("side", 1.0), path + "/side", -1.0, 1.0):
		return false
	if not _arr((v as Dictionary).get("planks"), path + "/planks", MAX_PLANKS):
		return false
	var ps: Array = v.planks
	for i in ps.size():
		var p := "%s/planks/%d" % [path, i]
		if not _dict(ps[i], p):
			return false
		var pl: Dictionary = ps[i]
		if not (_num(pl.get("max"), p + "/max", 0.001, MAX_HEALTH) and _num(pl.get("health"), p + "/health", 0.0, MAX_HEALTH)
				and _num(pl.get("tilt", 0.0), p + "/tilt", -90.0, 90.0)):
			return false
	return true


func _container(v: Variant, path: String, depth: int) -> bool:
	if not _dict(v, path):
		return false
	if depth > MAX_NEST:
		return _fail(path, "bags nested too deep")
	var d: Dictionary = v
	if not _opt(d, "capacity", path, func(x, p): return _num(x, p, -1.0, 1.0e6)):
		return false
	if not _arr(d.get("items", []), path + "/items", 10000):
		return false
	var items: Array = d.get("items", [])
	for i in items.size():
		if not _item(items[i], "%s/items/%d" % [path, i], depth):
			return false
	return true


func _item(v: Variant, path: String, depth: int = 0) -> bool:
	if not _dict(v, path):
		return false
	var d: Dictionary = v
	if not _str(d.get("id"), path + "/id", 64):
		return false
	var data: ItemData = ItemDB.get_item(StringName(String(d.id)))
	if data == null:
		return _fail(path + "/id", "unknown item '%s'" % d.id)
	var max_count := float(data.max_stack) if data.is_stackable() else 1.0
	if not _int(d.get("count", d.get("stack", 1)), path + "/count", 1.0, maxf(max_count, 1.0)):
		return false
	if not _int(d.get("condition", data.max_condition), path + "/condition", 0.0, float(maxi(data.max_condition, 0))):
		return false
	if not (_opt(d, "uid", path, func(x, p): return _int(x, p, 1.0, 1.0e15))
			and _opt(d, "portion", path, func(x, p): return _num(x, p, 0.001, 1.0))
			and _opt(d, "age", path, func(x, p): return _num(x, p, 0.0, 1.0e9))):
		return false
	if d.has("contents"):
		if not data is ContainerItemData:
			return _fail(path + "/contents", "not a bag")
		return _container(d.contents, path + "/contents", depth + 1)
	return true


func _zombie(v: Variant, path: String) -> bool:
	if not _dict(v, path):
		return false
	var d: Dictionary = v
	if not (_str(d.get("spawn_id"), path + "/spawn_id") and _int(d.get("seed", 0), path + "/seed", 0.0, 4294967296.0)
			and _vec3(d.get("position"), path + "/position") and _num(d.get("facing", 0.0), path + "/facing", -100.0, 100.0)
			and _num(d.get("health"), path + "/health", 0.001, MAX_HEALTH) and _vec3(d.get("home"), path + "/home")
			and _enum(d.get("state", "idle"), path + "/state", ZOMBIE_STATES)):
		return false
	var t: Variant = d.get("target")
	if t != null and not _vec3(t, path + "/target"):
		return false
	if d.has("profile"):
		if not _str(d.profile, path + "/profile", 64) or ZombieProfile.by_id(String(d.profile)) == null:
			return _fail(path + "/profile", "unknown zombie profile")
	return true


func _corpse(v: Variant, path: String) -> bool:
	if not _dict(v, path):
		return false
	var d: Dictionary = v
	if not (_str(d.get("persist_id"), path + "/persist_id") and _int(d.get("seed", 0), path + "/seed", 0.0, 4294967296.0)
			and _vec3(d.get("position"), path + "/position") and _num(d.get("yaw", 0.0), path + "/yaw", -100.0, 100.0)
			and _enum(d.get("pose", "death"), path + "/pose", CORPSE_POSES) and _dict(d.get("container"), path + "/container")):
		return false
	var c: Dictionary = d.container
	return _bool(c.get("searched"), path + "/container/searched") and _container(c.get("inventory", {}), path + "/container/inventory", 0)


func _world_item(v: Variant, path: String) -> bool:
	if not _dict(v, path):
		return false
	var d: Dictionary = v
	return _item(d.get("item"), path + "/item") and _vec3(d.get("position"), path + "/position") \
		and _num(d.get("yaw", 0.0), path + "/yaw", -100.0, 100.0)


func _player(v: Variant, path: String) -> bool:
	if not _dict(v, path):
		return false
	var d: Dictionary = v
	if not _vec3(d.get("position"), path + "/position") or not _num(d.get("facing", 0.0), path + "/facing", -100.0, 100.0):
		return false
	if d.has("stats"):
		if not _dict(d.stats, path + "/stats"):
			return false
		for k in d.stats:
			if not _str(k, path + "/stats") or not _num(d.stats[k], "%s/stats/%s" % [path, k], -MAX_STAT, MAX_STAT):
				return false
	if d.has("health"):
		if not _dict(d.health, path + "/health"):
			return false
		var h: Dictionary = d.health
		if not (_num(h.get("max", 100.0), path + "/health/max", 0.001, MAX_HEALTH)
				and _num(h.get("health"), path + "/health/health", 0.001, float(h.get("max", 100.0)))
				and _opt(h, "dead", path + "/health", func(x, p): return _bool(x, p))):
			return false
	if d.has("needs"):
		if not _dict(d.needs, path + "/needs"):
			return false
		for k in d.needs:
			if not _num(d.needs[k], "%s/needs/%s" % [path, k], 0.0, MAX_STAT):
				return false
	if d.has("skills"):
		if not _dict(d.skills, path + "/skills") or not _dict((d.skills as Dictionary).get("xp", {}), path + "/skills/xp"):
			return false
		var xp: Dictionary = (d.skills as Dictionary).get("xp", {})
		for k in xp:
			if not _num(xp[k], "%s/skills/xp/%s" % [path, k], 0.0, 1.0e9):
				return false
	if d.has("injuries") and not _injuries(d.injuries, path + "/injuries"):
		return false
	if not _dict(d.get("carried"), path + "/carried"):
		return false
	var c: Dictionary = d.carried
	if not _container(c.get("inventory", {}), path + "/carried/inventory", 0):
		return false
	if c.has("equipment"):
		if not _dict(c.equipment, path + "/carried/equipment"):
			return false
		var e: Dictionary = c.equipment
		if not _dict(e.get("slots", {}), path + "/carried/equipment/slots"):
			return false
		for s in e.get("slots", {}):
			if not Equipment.SLOTS.has(StringName(String(s))):
				return _fail("%s/carried/equipment/slots/%s" % [path, s], "unknown slot")
			if not _item(e.slots[s], "%s/carried/equipment/slots/%s" % [path, s]):
				return false
		if not _arr(e.get("hotbar", []), path + "/carried/equipment/hotbar", Equipment.HOTBAR_SIZE):
			return false
		for i in (e.get("hotbar", []) as Array).size():
			var r: Variant = e.hotbar[i]
			if r != null and not _dict(r, "%s/carried/equipment/hotbar/%d" % [path, i]):
				return false
	return true


func _injuries(v: Variant, path: String) -> bool:
	if not _dict(v, path) or not _opt(v, "infected", path, func(x, p): return _bool(x, p)):
		return false
	if not _arr((v as Dictionary).get("injuries", []), path + "/injuries", 200):
		return false
	var list: Array = (v as Dictionary).get("injuries", [])
	for i in list.size():
		var p := "%s/injuries/%d" % [path, i]
		if not _dict(list[i], p):
			return false
		var w: Dictionary = list[i]
		if not _str(w.get("region"), p + "/region") or Injury.region_from_id(StringName(String(w.region))) < 0:
			return _fail(p + "/region", "unknown region")
		if not _str(w.get("type"), p + "/type") or Injury.type_from_id(StringName(String(w.type))) < 0:
			return _fail(p + "/type", "unknown wound type")
		for k in ["bleeding", "bandaged", "infected"]:
			if not _opt(w, k, p, func(x, pp): return _bool(x, pp)):
				return false
		for k in ["bleed_left", "heal_left", "heal_total", "rebleed_left", "age"]:
			if not _opt(w, k, p, func(x, pp): return _num(x, pp, -1.0, 1.0e9)):
				return false
		if not _opt(w, "bandage_quality", p, func(x, pp): return _num(x, pp, 0.0, 10.0)):
			return false
	return true
