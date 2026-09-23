class_name BuildingPlanGenerator
extends RefCounted
## Procedural BuildingPlans (Round 11) in exactly the format HouseBlockout
## consumes (rooms / walls / openings / furniture with explicit ids), from
## a building kind + a seed (derived from the world seed and the building
## id, so ids and loot are stable across regenerations).
##
## Kinds: house, farmhouse (row plans: living / kitchen / bedrooms /
## bathroom, optional attached garage), convenience_store,
## hardware_store, pharmacy (sales floor with shelf rows, counter, back
## storage + office), diner (dining room with tables and booths, kitchen,
## restroom), gas_station (small shop), warehouse (open hall with rack
## rows, loading area, office), barn (open floor + tack room).
##
## Plans are generated with the front wall on local +Z (south) and the
## entry ("front_door") on it; rotate_plan() turns them to face their
## road. Interior walls come from room adjacency; doors form a spanning
## tree from the entry room (every room reachable); windows on exterior
## walls; furniture against walls (never in a door's clearance, tall
## pieces never in front of windows) or in freestanding rows.
## check(plan) verifies all of that (tests run it on every plan).

const CATALOG := "res://data/buildings/furniture_catalog.tres"
const EPS := 0.01
const WALL_T := 0.2
## Kinds a building record may have.
const KINDS: Array[StringName] = [&"house", &"farmhouse", &"convenience_store", &"hardware_store", &"pharmacy",
	&"diner", &"gas_station", &"warehouse", &"barn", &"bar", &"church", &"post_office"]
const SIGNS := {&"convenience_store": ["GROCERY", "QUIK MART", "CORNER STORE", "FOOD MART"],
	&"hardware_store": ["HARDWARE", "TOOLS & SUPPLY"], &"pharmacy": ["PHARMACY", "DRUGSTORE"], &"diner": ["DINER", "EAT"],
	&"bar": ["BAR", "TAVERN", "RUSTY NAIL"], &"post_office": ["POST OFFICE"], &"gas_station": ["GAS"]}
const AWNINGS: Array[Color] = [Color(0.62, 0.18, 0.16), Color(0.18, 0.36, 0.28), Color(0.2, 0.3, 0.5), Color(0.75, 0.62, 0.2)]
const HOUSE_WALLS: Array[Color] = [Color(0.86, 0.84, 0.78), Color(0.78, 0.72, 0.6), Color(0.62, 0.7, 0.76),
	Color(0.85, 0.8, 0.6), Color(0.66, 0.66, 0.64), Color(0.64, 0.42, 0.34), Color(0.74, 0.8, 0.7),
	Color(0.9, 0.9, 0.88)]
const HOUSE_ROOFS: Array[Color] = [Color(0.3, 0.28, 0.28), Color(0.4, 0.3, 0.24), Color(0.28, 0.34, 0.3),
	Color(0.36, 0.36, 0.4), Color(0.45, 0.25, 0.2)]

static var _catalog: FurnitureCatalog


static func catalog() -> FurnitureCatalog:
	if _catalog == null:
		_catalog = load(CATALOG) as FurnitureCatalog
	return _catalog


## Quarter turns (+90° about Y each) that put the plan's front (+Z) on
## [front] (WorldLayout.FRONT_*).
static func quarter_turns_for(front: int) -> int:
	match front:
		WorldLayout.FRONT_S:
			return 0
		WorldLayout.FRONT_E:
			return 1
		WorldLayout.FRONT_N:
			return 2
	return 3


static func generate(kind: StringName, pseed: int, opts: Dictionary = {}) -> BuildingPlan:
	var d := Draft.new(pseed, opts)
	match kind:
		&"house":
			d.house(false)
		&"farmhouse":
			d.house(true)
		&"convenience_store", &"hardware_store", &"pharmacy", &"post_office":
			d.store(kind)
		&"bar":
			d.diner(true)
		&"church":
			d.church()
		&"diner":
			d.diner()
		&"gas_station":
			d.gas_station()
		&"warehouse":
			d.warehouse()
		&"barn":
			d.barn()
		_:
			d.house(false)
	return d.finish()


# --- Rotation / queries -----------------------------------------------------------------

static func _rot_point(pt: Vector2, k: int, fp: Vector2) -> Vector2:
	match posmod(k, 4):
		1:
			return Vector2(pt.y, fp.x - pt.x)
		2:
			return Vector2(fp.x - pt.x, fp.y - pt.y)
		3:
			return Vector2(fp.y - pt.y, pt.x)
	return pt


static func _rot_vec(v: Vector2, k: int) -> Vector2:
	match posmod(k, 4):
		1:
			return Vector2(v.y, -v.x)
		2:
			return -v
		3:
			return Vector2(-v.y, v.x)
	return v


static func _rot_rect(r: Rect2, k: int, fp: Vector2) -> Rect2:
	var a := _rot_point(r.position, k, fp)
	var b := _rot_point(r.end, k, fp)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs())


## A copy of [plan] turned by [k] quarter turns (+90° about Y: local +Z
## goes to +X), translated back to a min corner at the origin. Rooms stay
## axis-aligned; furniture keeps its room-relative placement.
static func rotate_plan(plan: BuildingPlan, k: int) -> BuildingPlan:
	var out := plan.duplicate(true) as BuildingPlan
	k = posmod(k, 4)
	if k == 0:
		return out
	var fp := plan.footprint
	out.footprint = Vector2(fp.y, fp.x) if k % 2 == 1 else fp
	var rooms: Array[Dictionary] = []
	for r in plan.rooms:
		var nr: Dictionary = r.duplicate(true)
		nr.rect = _rot_rect(r.rect, k, fp)
		rooms.append(nr)
	var walls: Array[Dictionary] = []
	for w in plan.walls:
		var nw: Dictionary = w.duplicate(true)
		nw.from = _rot_point(w.from, k, fp)
		nw.to = _rot_point(w.to, k, fp)
		if w.has("outward"):
			nw.outward = _rot_vec(w.outward, k)
		walls.append(nw)
	var furn: Array[Dictionary] = []
	for f in plan.furniture:
		var nf: Dictionary = f.duplicate(true)
		var room := plan.room_named(String(f.room))
		var old_rect: Rect2 = room.get("rect", Rect2())
		var abs_pos: Vector2 = old_rect.position + (f.position as Vector2)
		var new_rect := _rot_rect(old_rect, k, fp)
		nf.position = _rot_point(abs_pos, k, fp) - new_rect.position
		nf.rotation = wrapf(float(f.get("rotation", 0.0)) + 90.0 * k, -180.0, 180.0)
		furn.append(nf)
	out.rooms = rooms
	out.walls = walls
	out.furniture = furn
	return out


## Plan-local centre of the opening [id] (Vector2.INF when missing).
static func opening_point(plan: BuildingPlan, id: String) -> Vector2:
	for w in plan.walls:
		for o in w.get("openings", []):
			if String(o.get("id", "")) == id:
				var from: Vector2 = w.from
				var to: Vector2 = w.to
				return from + (to - from).normalized() * float(o.at)
	return Vector2.INF


## Plan-local points of every exterior door (openings of type "door" on
## walls with an outward normal), with that normal: [[point, outward], …].
static func exterior_doors(plan: BuildingPlan) -> Array:
	var out: Array = []
	for w in plan.walls:
		var n: Vector2 = w.get("outward", Vector2.ZERO)
		if n == Vector2.ZERO:
			continue
		for o in w.get("openings", []):
			if String(o.get("type", "")) != "door":
				continue
			var from: Vector2 = w.from
			var to: Vector2 = w.to
			out.append([from + (to - from).normalized() * float(o.at), n])
	return out


## Outward normal of the wall holding opening [id] (ZERO for interior / missing).
static func opening_outward(plan: BuildingPlan, id: String) -> Vector2:
	for w in plan.walls:
		for o in w.get("openings", []):
			if String(o.get("id", "")) == id:
				return w.get("outward", Vector2.ZERO)
	return Vector2.ZERO


## Footprint rect (plan-local, room-independent) of a furniture entry.
static func furniture_rect(plan: BuildingPlan, f: Dictionary) -> Rect2:
	var room := plan.room_named(String(f.get("room", "")))
	var rr: Rect2 = room.get("rect", Rect2())
	var spec := catalog().resolve(StringName(f.get("type", &"")), f)
	var s: Vector3 = spec.size
	var rot := int(round(float(f.get("rotation", 0.0)) / 90.0))
	var ext := Vector2(s.x, s.z) if posmod(rot, 2) == 0 else Vector2(s.z, s.x)
	var c: Vector2 = rr.position + (f.position as Vector2)
	return Rect2(c - ext * 0.5, ext)


## Rooms on both sides of every door (and of open room pairs, which share
## an edge without any wall): {room name: [neighbour names]}.
static func door_graph(plan: BuildingPlan) -> Dictionary:
	var g := {}
	for r in plan.rooms:
		g[String(r.name)] = []
	for w in plan.walls:
		var from: Vector2 = w.from
		var to: Vector2 = w.to
		var dir := (to - from).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		for o in w.get("openings", []):
			if String(o.get("type", "door")) != "door":
				continue
			var c := from + dir * float(o.at)
			var a := _room_at(plan, c + nrm * 0.3)
			var b := _room_at(plan, c - nrm * 0.3)
			if a != "" and b != "" and a != b:
				g[a].append(b)
				g[b].append(a)
	# Open pairs: rooms sharing an edge interval not covered by any wall.
	for i in plan.rooms.size():
		for j in range(i + 1, plan.rooms.size()):
			var sh := Draft.shared_edge(plan.rooms[i].rect, plan.rooms[j].rect)
			if sh.is_empty() or float(sh.hi) - float(sh.lo) < 1.0:
				continue
			var mid := (float(sh.lo) + float(sh.hi)) * 0.5
			var pt := Vector2(float(sh.c), mid) if sh.orient == "v" else Vector2(mid, float(sh.c))
			if not _wall_covers(plan, pt):
				g[String(plan.rooms[i].name)].append(String(plan.rooms[j].name))
				g[String(plan.rooms[j].name)].append(String(plan.rooms[i].name))
	return g


static func _wall_covers(plan: BuildingPlan, pt: Vector2) -> bool:
	for w in plan.walls:
		var q := Geometry2D.get_closest_point_to_segment(pt, w.from, w.to)
		if q.distance_to(pt) < 0.05:
			return true
	return false


static func _room_at(plan: BuildingPlan, pt: Vector2) -> String:
	for r in plan.rooms:
		if (r.rect as Rect2).has_point(pt):
			return String(r.name)
	return ""


## Name of the room holding the front door (entry).
static func entry_room(plan: BuildingPlan) -> String:
	var c := opening_point(plan, "front_door")
	if c == Vector2.INF:
		return ""
	var n := opening_outward(plan, "front_door")
	return _room_at(plan, c - n * 0.3)


## Generator-level invariants beyond BuildingPlan.validate(): a front door
## on an exterior wall; every room reachable from the entry through doors;
## furniture inside its room, not overlapping, never in a door's
## clearance; tall pieces never in front of a window; living rooms,
## kitchens and bedrooms have a window. Returns problems ([] = fine).
static func check(plan: BuildingPlan) -> Array[String]:
	var out: Array[String] = []
	var entry := entry_room(plan)
	if entry == "":
		out.append("no front door / entry room")
	else:
		var g := door_graph(plan)
		var seen := {entry: true}
		var queue: Array[String] = [entry]
		while not queue.is_empty():
			var cur: String = queue.pop_front()
			for nb in g.get(cur, []):
				if not seen.has(nb):
					seen[nb] = true
					queue.append(nb)
		for r in plan.rooms:
			if not seen.has(String(r.name)):
				out.append("room '%s' unreachable from the entry" % r.name)
	var zones := Draft.door_zones_of(plan)
	var windows := Draft.window_zones_of(plan)
	var rects: Array = []
	for f in plan.furniture:
		var fr := furniture_rect(plan, f)
		var room := plan.room_named(String(f.room))
		var inner: Rect2 = (room.get("rect", Rect2()) as Rect2).grow(-WALL_T * 0.5 + 0.005)
		if not inner.encloses(fr):
			out.append("furniture %s sticks out of room %s" % [f.id, f.room])
		for z in zones:
			if (z as Rect2).intersects(fr.grow(-0.01)):
				out.append("furniture %s blocks a door" % f.id)
				break
		var spec := catalog().resolve(StringName(f.type), f)
		if (spec.size as Vector3).y > 0.95:
			for wz in windows:
				if (wz as Rect2).intersects(fr.grow(-0.01)):
					out.append("tall furniture %s in front of a window" % f.id)
					break
		for o in rects:
			if (o[0] as Rect2).intersects(fr.grow(-0.01)):
				out.append("furniture %s overlaps %s" % [f.id, o[1]])
		rects.append([fr, f.id])
	for r in plan.rooms:
		var t := BuildingPlan.room_type_of(r)
		if t in [&"living_room", &"kitchen", &"bedroom"]:
			if not Draft.room_has_window(plan, r):
				out.append("room %s has no window" % r.name)
	return out


# =====================================================================================
# Draft: builds one plan.
# =====================================================================================

class Draft:
	extends RefCounted

	var r := RandomNumberGenerator.new()
	var opts: Dictionary
	var plan := BuildingPlan.new()
	var W: float = 10.0
	var D: float = 8.0
	## {id, name, type, rect}
	var rooms: Array[Dictionary] = []
	var open_pairs: Array = []
	var entry: String = ""
	## Exterior doors: {room, side: "S"|"N"|"E"|"W", width, id, pos (optional along-side coord)}
	var ext_doors: Array[Dictionary] = []
	## Rooms that get windows, with width overrides.
	var window_width: Dictionary = {}
	var no_window: Dictionary = {}
	var window_spacing: float = 3.2
	## Walls built by finish(): exterior sides + merged interior lines.
	var walls: Array[Dictionary] = []
	var furniture: Array[Dictionary] = []
	var _placed: Array = []
	var _door_zones: Array = []
	var _window_zones: Array = []
	var _furn_count: Dictionary = {}
	## Furniture requests executed after the walls exist: Callables.
	var _furnish: Array[Callable] = []

	func _init(pseed: int, o: Dictionary) -> void:
		r.seed = pseed
		opts = o

	func _size(w_min: float, w_max: float, d_min: float, d_max: float) -> void:
		var hint: Vector2 = opts.get("size", Vector2.ZERO)
		W = snappedf(r.randf_range(w_min, w_max), 0.1) if hint == Vector2.ZERO else hint.x
		D = snappedf(r.randf_range(d_min, d_max), 0.1) if hint == Vector2.ZERO else hint.y
		W = minf(W, float(opts.get("max_width", 999.0)))
		D = minf(D, float(opts.get("max_depth", 999.0)))
		W = maxf(W, w_min * 0.85)
		D = maxf(D, d_min * 0.85)

	func add_room(name: String, type: StringName, rect: Rect2) -> Dictionary:
		var base := String(type)
		var id := base
		var n := 2
		while _room_by_id(id) != {}:
			id = "%s_%d" % [base, n]
			n += 1
		var rm := {"id": id, "name": name, "type": type, "rect": rect}
		rooms.append(rm)
		return rm

	func _room_by_id(id: String) -> Dictionary:
		for rm in rooms:
			if rm.id == id:
				return rm
		return {}

	func _mirror(flip: bool) -> void:
		if not flip:
			return
		for rm in rooms:
			var rc: Rect2 = rm.rect
			rm.rect = Rect2(W - rc.end.x, rc.position.y, rc.size.x, rc.size.y)

	# --- Kinds -----------------------------------------------------------------------

	func house(farm: bool) -> void:
		plan.building_type = &"farmhouse" if farm else &"house"
		plan.display_name = "Farmhouse" if farm else "House"
		var garage := bool(opts.get("garage", false)) and not farm
		var gw := 3.6 if garage else 0.0
		if farm:
			_size(10.0, 13.0, 8.5, 10.0)
		else:
			_size(8.0, 12.0, 7.0, 10.0)
		if garage:
			W = minf(W, float(opts.get("max_width", 99.0)) - gw)
		W = maxf(W, 7.6)
		var db := clampf(snappedf(D * r.randf_range(0.42, 0.52), 0.1), 3.2, 4.6)
		var df := D - db
		var variants: Array[String] = ["B"]
		if W >= 8.6:
			variants.append("A")
		if W >= 10.0:
			variants.append("C")
		var v: String = "C" if farm else variants[r.randi_range(0, variants.size() - 1)]
		var bath := snappedf(r.randf_range(2.2, 2.6), 0.1)
		match v:
			"A":
				var kit := snappedf(r.randf_range(3.0, 3.6), 0.1)
				var bed := W - bath - kit
				add_room("Bedroom", &"bedroom", Rect2(0, 0, bed, db))
				add_room("Bathroom", &"bathroom", Rect2(bed, 0, bath, db))
				add_room("Kitchen", &"kitchen", Rect2(bed + bath, 0, kit, db))
				add_room("Living Room", &"living_room", Rect2(0, db, W, df))
			"B":
				var liv := snappedf(W * r.randf_range(0.55, 0.62), 0.1)
				add_room("Living Room", &"living_room", Rect2(0, db, liv, df))
				add_room("Kitchen", &"kitchen", Rect2(liv, db, W - liv, df))
				add_room("Bedroom", &"bedroom", Rect2(0, 0, W - bath, db))
				add_room("Bathroom", &"bathroom", Rect2(W - bath, 0, bath, db))
			_:
				var liv2 := snappedf(W * r.randf_range(0.52, 0.6), 0.1)
				add_room("Living Room", &"living_room", Rect2(0, db, liv2, df))
				add_room("Kitchen", &"kitchen", Rect2(liv2, db, W - liv2, df))
				var b1 := snappedf((W - bath) * r.randf_range(0.45, 0.55), 0.1)
				add_room("Bedroom", &"bedroom", Rect2(0, 0, b1, db))
				add_room("Bathroom", &"bathroom", Rect2(b1, 0, bath, db))
				add_room("Bedroom", &"bedroom", Rect2(b1 + bath, 0, W - b1 - bath, db))
		_mirror(r.randf() < 0.5)
		if garage:
			var left := r.randf() < 0.5
			if left:
				for rm in rooms:
					rm.rect = Rect2((rm.rect as Rect2).position + Vector2(gw, 0), (rm.rect as Rect2).size)
			var g := add_room("Garage", &"garage", Rect2(0.0 if left else W, 0, gw, D))
			W += gw
			ext_doors.append({"room": g.id, "side": "S", "width": 2.4, "id": "garage_door"})
			window_spacing = 3.0
		entry = "living_room"
		ext_doors.push_front({"room": "living_room", "side": "S", "width": 0.9, "id": "front_door"})
		var kitchen := _room_by_id("kitchen")
		if r.randf() < 0.75:
			for side in ["N", "E", "W"]:
				if _touches(kitchen.rect, side) and _side_free_len(kitchen.rect, side) >= 3.6:
					ext_doors.append({"room": "kitchen", "side": side, "width": 0.9, "id": "back_door"})
					break
		window_width["bathroom"] = 0.8
		window_width["garage"] = 1.0
		var palette := r.randi_range(0, HOUSE_WALLS.size() - 1)
		plan.wall_color = HOUSE_WALLS[palette]
		plan.roof_color = HOUSE_ROOFS[r.randi_range(0, HOUSE_ROOFS.size() - 1)]
		plan.floor_color = Color(0.45, 0.36, 0.28).lerp(Color(0.55, 0.45, 0.33), r.randf())
		plan.roof_style = &"gable" if r.randf() < (0.8 if farm else 0.6) else &"hip"
		plan.roof_pitch = r.randf_range(0.45, 0.7)
		plan.storeys = 2 if r.randf() < (0.6 if farm else 0.25) and W >= 8.5 else 1
		if r.randf() < (0.7 if farm else 0.5):
			plan.porch = {"width": r.randf_range(3.6, 5.0), "depth": r.randf_range(1.8, 2.2)}
		_furnish.append(_furnish_house)
		_furnish.append(_arm_house)

	func store(kind: StringName) -> void:
		plan.building_type = kind
		plan.display_name = {&"convenience_store": "Convenience Store", &"hardware_store": "Hardware Store",
			&"pharmacy": "Pharmacy", &"post_office": "Post Office"}[kind]
		_size(14.0, 17.0, 11.0, 14.0)
		plan.wall_height = 3.2
		plan.window_top_height = 2.4
		var db := snappedf(r.randf_range(3.6, 4.2), 0.1)
		var ow := 3.8
		add_room("Sales Floor", &"sales_floor", Rect2(0, db, W, D - db))
		add_room("Storage", &"storage", Rect2(0, 0, W - ow, db))
		add_room("Office", &"office", Rect2(W - ow, 0, ow, db))
		_mirror(r.randf() < 0.5)
		entry = "sales_floor"
		ext_doors.append({"room": "sales_floor", "side": "S", "width": 1.6, "id": "front_door",
			"pos": W * r.randf_range(0.35, 0.65)})
		ext_doors.append({"room": "storage", "side": "N", "width": 0.9, "id": "back_door"})
		window_width["sales_floor"] = 2.2
		window_spacing = 3.4
		no_window["storage"] = true
		plan.wall_color = [Color(0.62, 0.36, 0.3), Color(0.7, 0.66, 0.58), Color(0.5, 0.52, 0.56), Color(0.66, 0.5, 0.36)][r.randi_range(0, 3)]
		plan.roof_color = Color(0.24, 0.24, 0.26)
		plan.floor_color = Color(0.72, 0.72, 0.68)
		plan.interior_wall_color = Color(0.82, 0.8, 0.74)
		if kind == &"post_office":
			plan.display_name = "Post Office"
			plan.wall_color = Color(0.72, 0.68, 0.6)
			rooms[0].name = "Lobby"
			rooms[0].type = &"lobby"
		_sign(kind)
		_furnish.append(_furnish_store.bind(kind))

	func diner(bar: bool = false) -> void:
		plan.building_type = &"bar" if bar else &"diner"
		plan.display_name = "Bar" if bar else "Diner"
		_size(14.0, 17.0, 10.0, 12.0)
		plan.wall_height = 3.0
		plan.window_top_height = 2.3
		var db := snappedf(r.randf_range(3.8, 4.2), 0.1)
		var rw := 2.6
		add_room("Bar Room" if bar else "Dining Room", &"dining_room", Rect2(0, db, W, D - db))
		add_room("Storage" if bar else "Kitchen", &"storage" if bar else &"kitchen", Rect2(0, 0, W - rw, db))
		add_room("Restroom", &"restroom", Rect2(W - rw, 0, rw, db))
		_mirror(r.randf() < 0.5)
		entry = "dining_room"
		ext_doors.append({"room": "dining_room", "side": "S", "width": 1.2, "id": "front_door",
			"pos": W * r.randf_range(0.4, 0.6)})
		ext_doors.append({"room": "storage" if bar else "kitchen", "side": "N", "width": 0.9, "id": "back_door"})
		window_width["dining_room"] = 2.0
		window_width["restroom"] = 0.8
		window_spacing = 3.0
		plan.wall_color = [Color(0.85, 0.85, 0.82), Color(0.62, 0.72, 0.74), Color(0.8, 0.4, 0.35)][r.randi_range(0, 2)]
		plan.roof_color = Color(0.3, 0.3, 0.32)
		plan.floor_color = Color(0.78, 0.76, 0.7) if not bar else Color(0.42, 0.3, 0.22)
		if bar:
			plan.wall_color = [Color(0.36, 0.24, 0.2), Color(0.3, 0.32, 0.3), Color(0.5, 0.3, 0.25)][r.randi_range(0, 2)]
		_sign(plan.building_type)
		_furnish.append(_furnish_diner.bind(bar))

	func gas_station() -> void:
		plan.building_type = &"gas_station"
		plan.display_name = "Gas Station"
		_size(9.0, 11.0, 7.0, 8.5)
		plan.wall_height = 3.0
		plan.window_top_height = 2.3
		var db := 2.6
		var rw := 2.4
		add_room("Shop", &"sales_floor", Rect2(0, db, W, D - db))
		add_room("Storage", &"storage", Rect2(0, 0, W - rw, db))
		add_room("Restroom", &"restroom", Rect2(W - rw, 0, rw, db))
		_mirror(r.randf() < 0.5)
		entry = "sales_floor"
		ext_doors.append({"room": "sales_floor", "side": "S", "width": 1.2, "id": "front_door",
			"pos": W * r.randf_range(0.35, 0.65)})
		window_width["sales_floor"] = 2.0
		window_width["restroom"] = 0.8
		no_window["storage"] = true
		plan.wall_color = Color(0.9, 0.9, 0.88)
		plan.roof_color = Color(0.7, 0.2, 0.15)
		plan.floor_color = Color(0.75, 0.75, 0.72)
		_sign(&"gas_station")
		_furnish.append(_furnish_gas)

	func warehouse() -> void:
		plan.building_type = &"warehouse"
		plan.display_name = "Warehouse"
		_size(24.0, 30.0, 16.0, 20.0)
		plan.wall_height = 5.0
		plan.door_height = 3.0
		plan.window_sill_height = 2.6
		plan.window_top_height = 3.6
		var oh := 4.5
		var ow := 5.5
		add_room("Warehouse Floor", &"hall", Rect2(0, 0, W, D - oh))
		add_room("Office", &"office", Rect2(0, D - oh, ow, oh))
		add_room("Loading Area", &"hall", Rect2(ow, D - oh, W - ow, oh))
		open_pairs.append(["hall", "hall_2"])
		_mirror(r.randf() < 0.5)
		entry = "office"
		ext_doors.append({"room": "office", "side": "S", "width": 0.9, "id": "front_door"})
		ext_doors.append({"room": "hall_2", "side": "S", "width": 3.0, "id": "loading_door"})
		var hall := _room_by_id("hall")
		for side in ["E", "W"]:
			if _touches(hall.rect, side):
				ext_doors.append({"room": "hall", "side": side, "width": 0.9, "id": "side_door"})
				break
		window_spacing = 6.0
		window_width["hall"] = 1.6
		window_width["hall_2"] = 1.6
		plan.wall_color = Color(0.55, 0.57, 0.6)
		plan.interior_wall_color = Color(0.7, 0.7, 0.7)
		plan.roof_color = Color(0.4, 0.42, 0.45)
		plan.floor_color = Color(0.5, 0.5, 0.5)
		_furnish.append(_furnish_warehouse)

	func barn() -> void:
		plan.building_type = &"barn"
		plan.display_name = "Barn"
		_size(12.0, 16.0, 10.0, 13.0)
		plan.wall_height = 4.2
		plan.door_height = 3.0
		plan.window_sill_height = 1.8
		plan.window_top_height = 2.8
		var tw := 3.6
		var tb := 4.0
		add_room("Barn", &"barn", Rect2(0, tb, W, D - tb))
		add_room("Stalls", &"barn", Rect2(0, 0, W - tw, tb))
		add_room("Tack Room", &"storage", Rect2(W - tw, 0, tw, tb))
		open_pairs.append(["barn", "barn_2"])
		_mirror(r.randf() < 0.5)
		entry = "barn"
		ext_doors.append({"room": "barn", "side": "S", "width": 3.0, "id": "front_door"})
		window_spacing = 4.5
		window_width["barn"] = 1.0
		window_width["barn_2"] = 1.0
		window_width["storage"] = 0.8
		plan.wall_color = [Color(0.6, 0.2, 0.16), Color(0.55, 0.45, 0.35), Color(0.5, 0.22, 0.2)][r.randi_range(0, 2)]
		plan.interior_wall_color = Color(0.55, 0.42, 0.3)
		plan.roof_color = Color(0.3, 0.3, 0.32)
		plan.floor_color = Color(0.45, 0.38, 0.28)
		plan.roof_style = &"gambrel"
		plan.roof_pitch = 0.75
		_furnish.append(_furnish_barn)

	func church() -> void:
		plan.building_type = &"church"
		plan.display_name = "Church"
		_size(10.0, 12.0, 14.0, 17.0)
		plan.wall_height = 4.5
		plan.door_height = 2.6
		plan.window_sill_height = 1.4
		plan.window_top_height = 3.6
		var ob := 3.4
		add_room("Nave", &"nave", Rect2(0, ob, W, D - ob))
		add_room("Office", &"office", Rect2(0, 0, W * 0.5, ob))
		add_room("Vestry", &"storage", Rect2(W * 0.5, 0, W * 0.5, ob))
		_mirror(r.randf() < 0.5)
		entry = "nave"
		ext_doors.append({"room": "nave", "side": "S", "width": 1.6, "id": "front_door", "pos": W * 0.5})
		window_width["nave"] = 1.0
		window_spacing = 2.8
		plan.wall_color = [Color(0.9, 0.9, 0.88), Color(0.72, 0.66, 0.6)][r.randi_range(0, 1)]
		plan.roof_color = Color(0.25, 0.25, 0.28)
		plan.floor_color = Color(0.5, 0.4, 0.3)
		plan.roof_style = &"gable"
		plan.roof_pitch = 1.0
		_furnish.append(_furnish_church)

	func _sign(kind: StringName) -> void:
		var names: Array = SIGNS.get(kind, [])
		if not names.is_empty():
			plan.sign_text = String(names[r.randi_range(0, names.size() - 1)])
		if kind != &"gas_station":
			plan.awning_color = AWNINGS[r.randi_range(0, AWNINGS.size() - 1)]

	## A fixed item in the first container of [types] in a room of
	## [room_type] (always in the loot: the generator's weapon budget).
	func _add_fixed(room_type: StringName, types: Array, item_id: StringName) -> bool:
		for f in furniture:
			var rm := {}
			for rr in rooms:
				if rr.pname == f.room:
					rm = rr
			if rm.is_empty() or StringName(rm.type) != room_type or not (StringName(f.type) in types):
				continue
			if f.has("container_type") and f.container_type == null:
				continue
			if not f.has("fixed"):
				f["fixed"] = []
			f.fixed.append({"id": item_id, "count": 1})
			return true
		return false

	## Improvised weapons (seeded per plan): a kitchen knife in 40 % of
	## kitchens, a pan / rolling pin in 25 %, a hammer or screwdriver in half
	## the garages, a bat in 10 % of bedrooms / garages; opts.hammer puts a
	## hammer in this house for sure (one per hamlet).
	func _arm_house() -> void:
		if r.randf() < 0.4:
			_add_fixed(&"kitchen", [&"kitchen_cabinet", &"counter"], &"kitchen_knife")
		if r.randf() < 0.25:
			_add_fixed(&"kitchen", [&"kitchen_cabinet", &"counter"], &"frying_pan" if r.randf() < 0.5 else &"rolling_pin")
		if r.randf() < 0.5:
			_add_fixed(&"garage", [&"tool_crate", &"shelf"], &"hammer" if r.randf() < 0.5 else &"screwdriver")
		if r.randf() < 0.1:
			if not _add_fixed(&"garage", [&"shelf", &"tool_crate"], &"baseball_bat"):
				_add_fixed(&"bedroom", [&"wardrobe", &"dresser"], &"baseball_bat")
		if bool(opts.get("hammer", false)):
			if not _add_fixed(&"garage", [&"tool_crate", &"shelf"], &"hammer"):
				_add_fixed(&"kitchen", [&"kitchen_cabinet", &"counter"], &"hammer")

	func _furnish_church() -> void:
		var nid := "nave"
		var rc := _rc(nid)
		place_wall(nid, &"table", Vector2(rc.get_center().x, rc.position.y), {"name": "Altar"})
		var z := rc.position.y + 2.4
		while z < rc.end.y - 2.6:
			for sx in [-1.0, 1.0]:
				place_at(nid, &"pew", Vector2(rc.get_center().x + sx * 2.3, z), 180.0, {}, 0.0)
			z += 1.5
		place_wall("office", &"desk", _back("office"))
		place_wall("office", &"shelf", Vector2(_rc("office").position.x, _rc("office").end.y))
		place_wall("storage", &"shelf", _back("storage"))
		place_wall("storage", &"crate", Vector2(_rc("storage").end.x, _rc("storage").end.y))

	# --- Geometry helpers ------------------------------------------------------------

	func _touches(rc: Rect2, side: String) -> bool:
		match side:
			"N":
				return rc.position.y <= EPS
			"S":
				return rc.end.y >= D - EPS
			"W":
				return rc.position.x <= EPS
			"E":
				return rc.end.x >= W - EPS
		return false

	## Interval (along the side's wall coordinate) where the room meets it.
	func _side_interval(rc: Rect2, side: String) -> Vector2:
		if side == "N" or side == "S":
			return Vector2(rc.position.x, rc.end.x)
		return Vector2(rc.position.y, rc.end.y)

	func _side_free_len(rc: Rect2, side: String) -> float:
		var iv := _side_interval(rc, side)
		return iv.y - iv.x

	## {orient: "v"|"h", c, lo, hi} of two rooms' shared edge ({} if none).
	static func shared_edge(a: Rect2, b: Rect2) -> Dictionary:
		if absf(a.end.x - b.position.x) < EPS or absf(b.end.x - a.position.x) < EPS:
			var c := a.end.x if absf(a.end.x - b.position.x) < EPS else a.position.x
			var lo := maxf(a.position.y, b.position.y)
			var hi := minf(a.end.y, b.end.y)
			if hi - lo > EPS:
				return {"orient": "v", "c": c, "lo": lo, "hi": hi}
		if absf(a.end.y - b.position.y) < EPS or absf(b.end.y - a.position.y) < EPS:
			var c2 := a.end.y if absf(a.end.y - b.position.y) < EPS else a.position.y
			var lo2 := maxf(a.position.x, b.position.x)
			var hi2 := minf(a.end.x, b.end.x)
			if hi2 - lo2 > EPS:
				return {"orient": "h", "c": c2, "lo": lo2, "hi": hi2}
		return {}

	func _is_open(a: String, b: String) -> bool:
		for pr in open_pairs:
			if (pr[0] == a and pr[1] == b) or (pr[0] == b and pr[1] == a):
				return true
		return false

	# --- Finish: walls, doors, windows, furniture -------------------------------------

	func finish() -> BuildingPlan:
		plan.footprint = Vector2(W, D)
		# Exterior walls (same conventions as house_a.tres).
		var ext := {
			"N": {"from": Vector2(0, 0), "to": Vector2(W, 0), "outward": Vector2(0, -1), "openings": []},
			"S": {"from": Vector2(0, D), "to": Vector2(W, D), "outward": Vector2(0, 1), "openings": []},
			"W": {"from": Vector2(0, 0), "to": Vector2(0, D), "outward": Vector2(-1, 0), "openings": []},
			"E": {"from": Vector2(W, 0), "to": Vector2(W, D), "outward": Vector2(1, 0), "openings": []},
		}
		# Interior walls: shared edges grouped by line, merged.
		var pairs: Array = []
		var lines := {}
		for i in rooms.size():
			for j in range(i + 1, rooms.size()):
				var sh := shared_edge(rooms[i].rect, rooms[j].rect)
				if sh.is_empty():
					continue
				sh["a"] = i
				sh["b"] = j
				pairs.append(sh)
				if _is_open(rooms[i].id, rooms[j].id):
					continue
				var key := "%s:%.2f" % [sh.orient, sh.c]
				if not lines.has(key):
					lines[key] = []
				lines[key].append(Vector2(sh.lo, sh.hi))
		var interior: Array[Dictionary] = []
		var keys: Array = lines.keys()
		keys.sort()
		for key in keys:
			var ivs: Array = lines[key]
			ivs.sort_custom(func(x, y): return x.x < y.x)
			var merged: Array[Vector2] = []
			for iv in ivs:
				if not merged.is_empty() and iv.x <= merged[-1].y + EPS:
					merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, iv.y))
				else:
					merged.append(iv)
			var parts := String(key).split(":")
			var c := float(parts[1])
			for m in merged:
				var w := {"openings": [], "orient": parts[0], "c": c, "lo": m.x, "hi": m.y}
				if parts[0] == "v":
					w["from"] = Vector2(c, m.x)
					w["to"] = Vector2(c, m.y)
				else:
					w["from"] = Vector2(m.x, c)
					w["to"] = Vector2(m.y, c)
				interior.append(w)
		# Exterior doors.
		for ed in ext_doors:
			var rm := _room_by_id(String(ed.room))
			if rm.is_empty() or not _touches(rm.rect, String(ed.side)):
				continue
			var iv := _side_interval(rm.rect, String(ed.side))
			var wdt := float(ed.width)
			var margin := wdt * 0.5 + 0.35
			if iv.y - iv.x < wdt + 0.7:
				continue
			var pos: float = ed.get("pos", -1.0)
			if pos < 0.0:
				# Near one end of the room's side: leaves room for a window.
				var slack := iv.y - iv.x - 2.0 * margin
				var off := r.randf_range(0.0, minf(slack, 0.6)) if slack > 0.0 else slack * 0.5
				pos = iv.x + margin + off if r.randf() < 0.5 else iv.y - margin - off
			pos = clampf(pos, iv.x + margin, iv.y - margin)
			if not _fits(ext[ed.side].openings, pos, wdt):
				continue
			ext[ed.side].openings.append({"type": "door", "id": String(ed.id), "at": snappedf(pos, 0.01), "width": wdt})
		# Interior doors: a spanning tree from the entry room (Prim, by preference).
		var visited := {}
		var entry_i := -1
		for i in rooms.size():
			if rooms[i].id == entry:
				entry_i = i
		if entry_i < 0:
			entry_i = 0
		visited[entry_i] = true
		var guard := 0
		while visited.size() < rooms.size() and guard < 64:
			guard += 1
			var best: Dictionary = {}
			var best_score := INF
			for sh in pairs:
				var a: int = sh.a
				var b: int = sh.b
				if visited.has(a) == visited.has(b):
					continue
				var parent := a if visited.has(a) else b
				var child := b if parent == a else a
				var span := float(sh.hi) - float(sh.lo)
				var open := _is_open(rooms[a].id, rooms[b].id)
				if not open and span < 1.6:
					continue
				var score := _link_score(rooms[parent].type, rooms[child].type) + (0.0 if span >= 1.9 else 0.5)
				if open:
					score = -1.0
				score += 0.001 * (parent * rooms.size() + child)
				if score < best_score:
					best_score = score
					best = {"sh": sh, "parent": parent, "child": child, "open": open}
			if best.is_empty():
				break
			visited[int(best.child)] = true
			if best.open:
				continue
			var sh2: Dictionary = best.sh
			var dw := 0.9 if float(sh2.hi) - float(sh2.lo) >= 1.9 else 0.8
			var m := dw * 0.5 + 0.35
			var lo := float(sh2.lo) + m
			var hi := float(sh2.hi) - m
			var pos2 := r.randf_range(lo, hi) if hi - lo > 0.2 else (lo + hi) * 0.5
			var wall := _interior_wall_for(interior, sh2, pos2)
			if wall.is_empty():
				continue
			var at := pos2 - float(wall.lo)
			var pa := String(rooms[int(best.parent)].id)
			var pc := String(rooms[int(best.child)].id)
			if not _fits(wall.openings, at, dw):
				continue
			wall.openings.append({"type": "door", "id": "door_%s_%s" % [pa, pc], "at": snappedf(at, 0.01), "width": dw})
		# Windows on exterior sides.
		for rm in rooms:
			if no_window.has(rm.id) or no_window.has(String(rm.type)):
				continue
			var ww: float = window_width.get(rm.id, window_width.get(String(rm.type), plan.window_width))
			for side in ["S", "N", "E", "W"]:
				if not _touches(rm.rect, side):
					continue
				var iv2 := _side_interval(rm.rect, side)
				var usable := iv2.y - iv2.x - 0.9
				if usable < ww:
					continue
				var n := maxi(1, int(floor((usable + 0.6) / window_spacing)))
				var step := (iv2.y - iv2.x) / float(n + 1) if n > 1 else 0.0
				var k := 0
				for wi in n:
					var pos3 := (iv2.x + iv2.y) * 0.5 if n == 1 else iv2.x + step * (wi + 1)
					# Slide off doors.
					if not _fits(ext[side].openings, pos3, ww, 0.3):
						var moved := false
						for d in [0.8, -0.8, 1.6, -1.6, 2.4, -2.4]:
							var q: float = pos3 + d
							if q - ww * 0.5 >= iv2.x + 0.45 and q + ww * 0.5 <= iv2.y - 0.45 and _fits(ext[side].openings, q, ww, 0.3):
								pos3 = q
								moved = true
								break
						if not moved:
							continue
					k += 1
					ext[side].openings.append({"type": "window", "id": "win_%s_%s_%d" % [rm.id, side.to_lower(), k],
						"at": snappedf(pos3, 0.01), "width": ww})
		# Living rooms, kitchens and bedrooms always get a window: fall back
		# to a narrow one anywhere it fits on any exterior side.
		for rm in rooms:
			if not (StringName(rm.type) in [&"living_room", &"kitchen", &"bedroom"]):
				continue
			if _has_window(ext, rm):
				continue
			var done := false
			for side in ["S", "N", "E", "W"]:
				if done or not _touches(rm.rect, side):
					continue
				var iv4 := _side_interval(rm.rect, side)
				var q2 := iv4.x + 0.85
				while q2 <= iv4.y - 0.85 and not done:
					if _fits(ext[side].openings, q2, 0.8, 0.2):
						ext[side].openings.append({"type": "window", "id": "win_%s_%s_x" % [rm.id, side.to_lower()],
							"at": snappedf(q2, 0.01), "width": 0.8})
						done = true
					q2 += 0.1
		# Assemble walls.
		var out_walls: Array[Dictionary] = []
		for side in ["S", "N", "W", "E"]:
			var ew: Dictionary = ext[side]
			out_walls.append({"from": ew.from, "to": ew.to, "outward": ew.outward, "openings": ew.openings})
		for w in interior:
			out_walls.append({"from": w.from, "to": w.to, "openings": w.openings})
		plan.walls = out_walls
		# Porch centred on the front door, clear of the garage door.
		if not plan.porch.is_empty():
			var fd := BuildingPlanGenerator.opening_point(plan, "front_door")
			var pw := float(plan.porch.width)
			var at := clampf(fd.x, pw * 0.5, W - pw * 0.5)
			var gd := BuildingPlanGenerator.opening_point(plan, "garage_door")
			if gd != Vector2.INF and absf(gd.x - at) < pw * 0.5 + 1.6:
				plan.porch = {}
			elif fd == Vector2.INF or absf(fd.x - at) > pw * 0.5 - 0.6:
				plan.porch = {}
			else:
				plan.porch["at"] = snappedf(at, 0.01)
		# Room names must be unique (furniture refers to rooms by name):
		# duplicates become "Bedroom 1", "Bedroom 2".
		var prs: Array[Dictionary] = []
		var seen_names := {}
		for rm in rooms:
			var nm := String(rm.name)
			if not _name_unique(rm):
				var k2: int = seen_names.get(nm, 0) + 1
				seen_names[nm] = k2
				nm = "%s %d" % [nm, k2]
			rm["pname"] = nm
			prs.append({"id": String(rm.id), "name": nm, "room_type": StringName(rm.type), "rect": rm.rect})
		plan.rooms = prs
		_door_zones = door_zones_of(plan)
		_window_zones = window_zones_of(plan)
		for fn in _furnish:
			fn.call()
		plan.furniture = furniture
		return plan

	func _has_window(ext: Dictionary, rm: Dictionary) -> bool:
		var rc: Rect2 = (rm.rect as Rect2).grow(0.05)
		for side in ext:
			var w: Dictionary = ext[side]
			var dir := ((w.to as Vector2) - (w.from as Vector2)).normalized()
			for o in w.openings:
				if o.type == "window" and rc.has_point((w.from as Vector2) + dir * float(o.at)):
					return true
		return false

	func _name_unique(rm: Dictionary) -> bool:
		for o in rooms:
			if o != rm and o.name == rm.name:
				return false
		return true

	func _link_score(parent_type: StringName, child_type: StringName) -> float:
		if child_type == &"garage":
			return 0.0 if parent_type == &"kitchen" else 1.0
		if parent_type in [&"living_room", &"sales_floor", &"dining_room", &"hall", &"barn"]:
			if child_type == &"kitchen" and parent_type == &"living_room":
				return 0.0
			return 0.2
		if parent_type == &"kitchen":
			return 1.0 if child_type != &"restroom" else 0.3
		if parent_type == &"storage":
			return 0.8
		return 2.0

	func _interior_wall_for(interior: Array[Dictionary], sh: Dictionary, pos: float) -> Dictionary:
		for w in interior:
			if w.orient == sh.orient and absf(float(w.c) - float(sh.c)) < EPS and pos >= float(w.lo) - EPS and pos <= float(w.hi) + EPS:
				return w
		return {}

	static func _fits(openings: Array, at: float, width: float, clearance: float = 0.15) -> bool:
		for o in openings:
			var ow := float(o.get("width", 0.9))
			if absf(float(o.at) - at) < (ow + width) * 0.5 + clearance:
				return false
		return true

	# --- Zones (static: check() reuses them) ------------------------------------------

	## Door clearance rects (plan-local): the opening ± 0.25 m along the wall,
	## ± (width + 0.25) m across it (covers the swing on both sides).
	static func door_zones_of(p: BuildingPlan) -> Array:
		var out: Array = []
		for w in p.walls:
			var from: Vector2 = w.from
			var to: Vector2 = w.to
			var dir := (to - from).normalized()
			for o in w.get("openings", []):
				if String(o.get("type", "door")) != "door":
					continue
				var wd := p.opening_width(o)
				var c := from + dir * float(o.at)
				var half_along := wd * 0.5 + 0.25
				var half_across := wd + 0.25
				var ext := Vector2(absf(dir.x) * half_along + absf(dir.y) * half_across,
					absf(dir.y) * half_along + absf(dir.x) * half_across)
				out.append(Rect2(c - ext, ext * 2.0))
		return out

	## In front of windows (inside): the opening ± 0.1 m, 0.7 m deep.
	static func window_zones_of(p: BuildingPlan) -> Array:
		var out: Array = []
		for w in p.walls:
			if not w.has("outward"):
				continue
			var from: Vector2 = w.from
			var to: Vector2 = w.to
			var dir := (to - from).normalized()
			var inward := -(w.outward as Vector2)
			for o in w.get("openings", []):
				if String(o.get("type", "door")) != "window":
					continue
				var wd := p.opening_width(o)
				var c := from + dir * float(o.at)
				var a := c - dir * (wd * 0.5 + 0.1)
				var b := c + dir * (wd * 0.5 + 0.1) + inward * 0.8
				out.append(Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()))
		return out

	static func room_has_window(p: BuildingPlan, room: Dictionary) -> bool:
		var rc: Rect2 = (room.rect as Rect2).grow(0.05)
		for w in p.walls:
			if not w.has("outward"):
				continue
			var from: Vector2 = w.from
			var to: Vector2 = w.to
			var dir := (to - from).normalized()
			for o in w.get("openings", []):
				if String(o.get("type", "door")) == "window" and rc.has_point(from + dir * float(o.at)):
					return true
		return false

	# --- Furniture -----------------------------------------------------------------------

	func _room(id: String) -> Dictionary:
		return _room_by_id(id)

	func _size_of(type: StringName, overrides: Dictionary = {}) -> Vector3:
		return BuildingPlanGenerator.catalog().resolve(type, overrides).size

	## Is [fr] free: inside [inner], clear of placed pieces, door zones and
	## (for tall pieces) windows.
	func _free(fr: Rect2, inner: Rect2, tall: bool, gap: float = 0.05) -> bool:
		if not inner.encloses(fr):
			return false
		for z in _door_zones:
			if (z as Rect2).intersects(fr):
				return false
		if tall:
			for wz in _window_zones:
				if (wz as Rect2).intersects(fr):
					return false
		for o in _placed:
			if (o as Rect2).grow(gap).intersects(fr):
				return false
		return true

	func _emit(rm: Dictionary, type: StringName, center: Vector2, rot_deg: float, extra: Dictionary = {}) -> void:
		var n: int = _furn_count.get(rm.id, 0)
		_furn_count[rm.id] = n + 1
		var e := {"id": "%s/%d" % [rm.id, n], "type": type, "room": String(rm.pname),
			"position": (center - (rm.rect as Rect2).position).snapped(Vector2(0.01, 0.01)), "rotation": rot_deg}
		e.merge(extra, true)
		furniture.append(e)

	static func _ext_for(size: Vector3, rot_deg: float) -> Vector2:
		var q := posmod(int(round(rot_deg / 90.0)), 2)
		return Vector2(size.x, size.z) if q == 0 else Vector2(size.z, size.x)

	## Put [type] against a wall of room [room_id], its back to the wall,
	## as close as possible to [pref] (plan-local). Returns success.
	func place_wall(room_id: String, type: StringName, pref: Vector2, extra: Dictionary = {}) -> bool:
		var rm := _room(room_id)
		if rm.is_empty():
			return false
		var size := _size_of(type, extra)
		var tall := size.y > 0.95
		var inner: Rect2 = (rm.rect as Rect2).grow(-WALL_T * 0.5 - 0.02)
		var best := {}
		var best_d := INF
		# side -> rotation (front faces into the room).
		for side in [["N", 0.0], ["S", 180.0], ["W", 90.0], ["E", -90.0]]:
			var rot: float = side[1]
			var ext := _ext_for(size, rot)
			var along_len := inner.size.x if side[0] in ["N", "S"] else inner.size.y
			var along_ext := ext.x if side[0] in ["N", "S"] else ext.y
			var t := 0.0
			while t <= along_len - along_ext + EPS:
				var pos: Vector2
				match side[0]:
					"N":
						pos = Vector2(inner.position.x + t, inner.position.y)
					"S":
						pos = Vector2(inner.position.x + t, inner.end.y - ext.y)
					"W":
						pos = Vector2(inner.position.x, inner.position.y + t)
					_:
						pos = Vector2(inner.end.x - ext.x, inner.position.y + t)
				var fr := Rect2(pos, ext)
				var d := fr.get_center().distance_to(pref)
				if d < best_d and _free(fr, inner, tall):
					best_d = d
					best = {"fr": fr, "rot": rot}
				t += 0.2
		if best.is_empty():
			return false
		_placed.append(best.fr)
		_emit(rm, type, (best.fr as Rect2).get_center(), best.rot, extra)
		return true

	## A freestanding piece centred at [c] with [rot]; skipped when not free.
	func place_at(room_id: String, type: StringName, c: Vector2, rot: float, extra: Dictionary = {}, gap: float = 0.05) -> bool:
		var rm := _room(room_id)
		if rm.is_empty():
			return false
		var size := _size_of(type, extra)
		var ext := _ext_for(size, rot)
		var fr := Rect2(c - ext * 0.5, ext)
		var inner: Rect2 = (rm.rect as Rect2).grow(-WALL_T * 0.5 - 0.02)
		if not _free(fr, inner, size.y > 0.95, gap):
			return false
		_placed.append(fr)
		_emit(rm, type, c, rot, extra)
		return true

	func _rc(id: String) -> Rect2:
		return _room(id).get("rect", Rect2())

	## Plan-local points: middle of the back (N) wall / front (S) wall of a room.
	func _back(id: String) -> Vector2:
		var rc := _rc(id)
		return Vector2(rc.get_center().x, rc.position.y)

	func _front(id: String) -> Vector2:
		var rc := _rc(id)
		return Vector2(rc.get_center().x, rc.end.y)

	func _furnish_house() -> void:
		for rm in rooms.duplicate():
			var id := String(rm.id)
			var rc: Rect2 = rm.rect
			match StringName(rm.type):
				&"living_room":
					place_wall(id, &"sofa", _back(id))
					place_wall(id, &"shelf", Vector2(rc.position.x, rc.position.y))
					place_wall(id, &"table", Vector2(rc.end.x, rc.get_center().y))
					if rc.size.x > 5.0:
						place_wall(id, &"shelf", Vector2(rc.end.x, rc.position.y))
				&"kitchen":
					place_wall(id, &"fridge", Vector2(rc.position.x, rc.position.y))
					place_wall(id, &"counter", _back(id))
					place_wall(id, &"stove", _back(id))
					place_wall(id, &"kitchen_cabinet", _back(id))
					place_wall(id, &"sink", Vector2(rc.end.x, rc.position.y))
					place_wall(id, &"kitchen_cabinet", Vector2(rc.end.x, rc.end.y))
					if rc.size.x * rc.size.y > 13.0:
						place_wall(id, &"table", rc.get_center())
				&"bedroom":
					place_wall(id, &"bed", _back(id))
					place_wall(id, &"dresser", Vector2(rc.end.x, rc.get_center().y))
					place_wall(id, &"wardrobe", Vector2(rc.position.x, rc.end.y))
				&"bathroom":
					place_wall(id, &"toilet", _back(id))
					place_wall(id, &"sink", Vector2(rc.end.x, rc.get_center().y))
					place_wall(id, &"bathroom_cabinet", Vector2(rc.position.x, rc.get_center().y))
				&"garage":
					place_wall(id, &"workbench", _back(id))
					place_wall(id, &"tool_crate", Vector2(rc.position.x, rc.position.y))
					place_wall(id, &"shelf", Vector2(rc.end.x, rc.get_center().y))
					if r.randf() < 0.5:
						place_wall(id, &"crate", Vector2(rc.position.x, rc.get_center().y))

	## Rows of back-to-back shelving along x in [area] (plan-local), aisles
	## of [aisle] m. [type] freestanding; every [container_every]-th piece
	## holds loot, the rest are empty display units (plain).
	func _shelf_rows(room_id: String, area: Rect2, type: StringName, aisle: float, container_every: int = 1) -> void:
		var size := _size_of(type)
		var depth := size.z * 2.0
		var z := area.position.y + aisle
		var k := 0
		while z + depth <= area.end.y - aisle + EPS:
			var x := area.position.x
			while x + size.x <= area.end.x + EPS:
				for s in 2:
					var cz := z + size.z * 0.5 + (size.z if s == 1 else 0.0)
					var rot := 180.0 if s == 0 else 0.0
					var extra := {}
					if container_every > 1 and k % container_every != 0:
						extra = {"container_type": null, "name": ""}
					place_at(room_id, type, Vector2(x + size.x * 0.5, cz), rot, extra, 0.0)
					k += 1
				x += size.x
			z += depth + aisle

	func _furnish_store(kind: StringName) -> void:
		var sid := "sales_floor"
		var rc := _rc(sid)
		var door := BuildingPlanGenerator.opening_point(plan, "front_door")
		# Register counter beside the entrance, coolers / counter at the back.
		place_wall(sid, &"counter", door + Vector2(2.4, -0.5), {"name": "Register"})
		place_wall(sid, &"counter", door + Vector2(3.6, -0.5))
		if kind == &"convenience_store":
			place_wall(sid, &"cooler", Vector2(rc.position.x, rc.position.y))
			place_wall(sid, &"cooler", Vector2(rc.end.x, rc.position.y))
		elif kind == &"post_office":
			place_wall(sid, &"crate", Vector2(rc.position.x, rc.position.y))
			place_wall(sid, &"crate", Vector2(rc.end.x, rc.position.y))
		elif kind == &"pharmacy":
			place_wall(sid, &"counter", Vector2(rc.get_center().x, rc.position.y), {"name": "Pharmacy counter"})
			place_wall(sid, &"counter", Vector2(rc.get_center().x + 1.3, rc.position.y), {"name": "Pharmacy counter"})
		else:
			place_wall(sid, &"workbench", Vector2(rc.position.x, rc.position.y))
		var area := Rect2(rc.position.x + 1.6, rc.position.y + 1.4, rc.size.x - 3.2, rc.size.y - 4.4)
		_shelf_rows(sid, area, &"store_shelf", 1.5, 2)
		var st := "storage"
		var src := _rc(st)
		place_wall(st, &"crate", Vector2(src.position.x, src.position.y))
		place_wall(st, &"crate", Vector2(src.position.x + 1.0, src.position.y))
		place_wall(st, &"shelf", Vector2(src.end.x, src.position.y))
		place_wall(st, &"crate", Vector2(src.position.x, src.end.y))
		place_wall("office", &"desk", _back("office"))
		place_wall("office", &"shelf", Vector2(_rc("office").end.x, _rc("office").end.y))
		if kind == &"hardware_store":
			_add_fixed(&"sales_floor", [&"counter"], &"hammer")

	func _furnish_diner(bar: bool = false) -> void:
		var did := "dining_room"
		var rc := _rc(did)
		place_wall(did, &"counter", Vector2(rc.position.x + 1.0, rc.position.y), {"name": "Diner counter"})
		place_wall(did, &"counter", Vector2(rc.position.x + 2.3, rc.position.y), {"name": "Diner counter"})
		# Booths under the front windows, tables in a grid.
		var x := rc.position.x + 1.4
		while x < rc.end.x - 1.4:
			place_at(did, &"sofa", Vector2(x, rc.end.y - 0.55), 180.0, {"name": "Booth"})
			x += 3.2
		var z := rc.position.y + 2.2
		while z < rc.end.y - 2.0:
			var tx := rc.position.x + 2.0
			while tx < rc.end.x - 1.2:
				place_at(did, &"table", Vector2(tx, z), 0.0, {}, 0.8)
				tx += 2.6
			z += 2.2
		var k := "storage" if bar else "kitchen"
		var kr := _rc(k)
		if bar:
			place_wall(k, &"fridge", Vector2(kr.position.x, kr.position.y))
			place_wall(k, &"crate", _back(k))
			place_wall(k, &"crate", Vector2(kr.end.x, kr.position.y))
			place_wall(k, &"shelf", Vector2(kr.end.x, kr.end.y))
			place_wall("restroom", &"toilet", _back("restroom"))
			place_wall("restroom", &"sink", Vector2(_rc("restroom").end.x, _rc("restroom").end.y))
			return
		place_wall(k, &"fridge", Vector2(kr.position.x, kr.position.y))
		place_wall(k, &"fridge", Vector2(kr.position.x + 1.0, kr.position.y))
		place_wall(k, &"stove", _back(k))
		place_wall(k, &"stove", _back(k) + Vector2(0.8, 0))
		place_wall(k, &"counter", Vector2(kr.end.x, kr.position.y))
		place_wall(k, &"kitchen_cabinet", Vector2(kr.end.x, kr.position.y))
		place_wall(k, &"sink", Vector2(kr.end.x, kr.end.y))
		place_wall(k, &"crate", Vector2(kr.position.x, kr.end.y))
		place_wall("restroom", &"toilet", _back("restroom"))
		place_wall("restroom", &"sink", Vector2(_rc("restroom").end.x, _rc("restroom").end.y))

	func _furnish_gas() -> void:
		var sid := "sales_floor"
		var rc := _rc(sid)
		var door := BuildingPlanGenerator.opening_point(plan, "front_door")
		place_wall(sid, &"counter", door + Vector2(2.0, -0.5), {"name": "Register"})
		place_wall(sid, &"cooler", Vector2(rc.position.x, rc.position.y))
		var area := Rect2(rc.position.x + 1.4, rc.position.y + 1.1, rc.size.x - 2.8, rc.size.y - 3.2)
		_shelf_rows(sid, area, &"store_shelf", 1.3, 2)
		place_wall("storage", &"crate", _back("storage"))
		place_wall("storage", &"shelf", Vector2(_rc("storage").end.x, _rc("storage").position.y))
		place_wall("restroom", &"toilet", _back("restroom"))
		place_wall("restroom", &"sink", Vector2(_rc("restroom").end.x, _rc("restroom").end.y))

	func _furnish_warehouse() -> void:
		var hid := "hall"
		var rc := _rc(hid)
		# Racks along the back wall, then freestanding double rows.
		var rack := _size_of(&"rack")
		var x := rc.position.x + 1.2
		var k := 0
		while x + rack.x <= rc.end.x - 1.2:
			var extra := {} if k % 3 == 0 else {"container_type": null, "name": ""}
			place_at(hid, &"rack", Vector2(x + rack.x * 0.5, rc.position.y + 0.12 + rack.z * 0.5), 0.0, extra, 0.0)
			x += rack.x
			k += 1
		var area := Rect2(rc.position.x + 2.0, rc.position.y + 1.1 + rack.z, rc.size.x - 4.0, rc.size.y - 3.4 - rack.z)
		_shelf_rows(hid, area, &"rack", 2.2, 3)
		var lid := "hall_2"
		var lr := _rc(lid)
		for i in 4:
			place_wall(lid, &"crate", Vector2(lr.end.x, lr.position.y + i))
		place_wall(lid, &"pallet", Vector2(lr.get_center().x, lr.position.y))
		place_wall(lid, &"pallet", Vector2(lr.get_center().x + 2.0, lr.position.y))
		place_wall("office", &"desk", _back("office"))
		place_wall("office", &"shelf", Vector2(_rc("office").position.x, _rc("office").end.y))

	func _furnish_barn() -> void:
		for id in ["barn", "barn_2"]:
			var rc := _rc(id)
			for i in 4:
				place_wall(id, &"hay_bale", Vector2(rc.position.x + i * 1.6, rc.position.y))
			place_wall(id, &"crate", Vector2(rc.end.x, rc.end.y))
		var t := "storage"
		place_wall(t, &"workbench", _back(t))
		place_wall(t, &"tool_crate", Vector2(_rc(t).end.x, _rc(t).end.y))
		place_wall(t, &"shelf", Vector2(_rc(t).position.x, _rc(t).end.y))
		if not _add_fixed(&"storage", [&"tool_crate"], &"hammer"):
			_add_fixed(&"barn", [&"crate"], &"hammer")
