class_name HouseBlockout
extends Building
## Generates blockout geometry for a [BuildingPlan] at runtime: floor slab,
## wall segments (split around openings), lintels above doors, Door and
## HouseWindow nodes in the openings, Room volumes and a flat roof.
##
## Groups / metadata contract (used by OcclusionManager through groups):
##   "wall"  StaticBody3D with child "Visual" whose origin is at floor level,
##           meta "outward" (Vector3 world normal, ZERO for interior) and
##           meta "wall_height". Doors and windows are in "wall" too.
##   "roof"  StaticBody3D (layer 6 only) with child "Visual".
##   "occluder" anything that should fade when between eye and player.
## Physics: walls on layers 1 + 6.
##
## Round 5 furniture: every plan.furniture entry becomes a StaticBody3D
## blockout box (FurnitureCatalog sizes/colours) on layer 1 (so the
## navmesh bakes it as an obstacle) — plus layer 4 when it is a container
## (a LootContainer with persist_id "<building_id>/<room_type>/<n>") and
## layer 6 + group "occluder" when taller than [occluder_min_height].
## Group "furniture".

const EPS := 0.001
const DEFAULT_CATALOG := "res://data/buildings/furniture_catalog.tres"

@export var plan: BuildingPlan
## Stable id used in container persist ids (defaults to the node name).
@export var building_id: String = ""
@export var furniture_catalog: FurnitureCatalog
## Furniture at least this tall fades when it hides the player.
@export var occluder_min_height: float = 1.2

var doors: Array[Door] = []
var windows: Array[HouseWindow] = []
var wall_segments: Array[StaticBody3D] = []
var roof: Node3D
var furniture: Array[StaticBody3D] = []
var containers: Array[LootContainer] = []


func _ready() -> void:
	if plan != null:
		display_name = plan.display_name
		for problem in plan.validate():
			push_warning("HouseBlockout '%s': %s" % [name, problem])
		build()
	super._ready()


## Pure: split one wall description into segment descriptors.
## Returns [{kind: "wall"|"lintel"|"door"|"window", a0, a1, y0, y1}] with
## a0/a1 distances along the wall from `from`.
static func segments_for_wall(wall: Dictionary, p: BuildingPlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var from: Vector2 = wall.get("from", Vector2.ZERO)
	var to: Vector2 = wall.get("to", Vector2.ZERO)
	var length := from.distance_to(to)
	if length <= EPS:
		return out
	var h := p.wall_height
	var exterior := _is_exterior(wall)
	var ext := p.wall_thickness * 0.5 if exterior else 0.0
	var openings: Array = (wall.get("openings", []) as Array).duplicate()
	openings.sort_custom(func(a, b): return float(a.get("at", 0.0)) < float(b.get("at", 0.0)))
	var cursor := -ext
	for o in openings:
		var w := p.opening_width(o)
		var at := float(o.get("at", 0.0))
		var a0 := clampf(at - w * 0.5, 0.0, length)
		var a1 := clampf(at + w * 0.5, 0.0, length)
		if a1 - a0 <= EPS:
			continue
		if a0 > cursor + EPS:
			out.append({"kind": "wall", "a0": cursor, "a1": a0, "y0": 0.0, "y1": h})
		var kind := String(o.get("type", "door"))
		if kind == "door":
			var dh := minf(p.door_height, h)
			out.append({"kind": "door", "a0": a0, "a1": a1, "y0": 0.0, "y1": dh})
			if h > dh + EPS:
				out.append({"kind": "lintel", "a0": a0, "a1": a1, "y0": dh, "y1": h})
		else:
			out.append({"kind": "window", "a0": a0, "a1": a1, "y0": 0.0, "y1": h})
		cursor = maxf(cursor, a1)
	if length + ext > cursor + EPS:
		out.append({"kind": "wall", "a0": cursor, "a1": length + ext, "y0": 0.0, "y1": h})
	return out


static func _is_exterior(wall: Dictionary) -> bool:
	var n: Vector2 = wall.get("outward", Vector2.ZERO)
	return n.length_squared() > 0.5


## Counts per kind for a whole plan: {"wall": n, "lintel": n, "door": n, "window": n}.
static func count_segments(p: BuildingPlan) -> Dictionary:
	var counts := {"wall": 0, "lintel": 0, "door": 0, "window": 0}
	for w in p.walls:
		for s in segments_for_wall(w, p):
			counts[s.kind] = counts.get(s.kind, 0) + 1
	return counts


func build() -> void:
	for c in get_children():
		c.queue_free()
	doors.clear()
	windows.clear()
	furniture.clear()
	containers.clear()
	wall_segments.clear()
	rooms.clear()
	_build_floor()
	for r in plan.rooms:
		_build_room(r)
	for w in plan.walls:
		_build_wall(w)
	_build_roof()
	_build_furniture()


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _build_floor() -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(plan.footprint.x, 0.04, plan.footprint.y)
	box.material = _material(plan.floor_color)
	slab.mesh = box
	slab.position = Vector3(plan.footprint.x * 0.5, 0.02, plan.footprint.y * 0.5)
	slab.add_to_group(&"floor")
	add_child(slab)


func _build_room(r: Dictionary) -> void:
	var rect: Rect2 = r.get("rect", Rect2())
	var room := Room.new()
	room.name = String(r.get("name", "Room")).replace(" ", "")
	room.room_name = String(r.get("name", "Room"))
	room.room_type = BuildingPlan.room_type_of(r)
	room.size = Vector3(rect.size.x, plan.wall_height, rect.size.y)
	room.position = Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	add_child(room)
	rooms.append(room)


func _build_wall(wall: Dictionary) -> void:
	var from: Vector2 = wall.get("from", Vector2.ZERO)
	var to: Vector2 = wall.get("to", Vector2.ZERO)
	var dir2 := (to - from).normalized()
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	var yaw := atan2(-dir.z, dir.x)  # local +X -> wall direction
	var exterior := _is_exterior(wall)
	var n2: Vector2 = wall.get("outward", Vector2.ZERO)
	var outward := Vector3(n2.x, 0.0, n2.y)
	var color := plan.wall_color if exterior else plan.interior_wall_color
	var origin := Vector3(from.x, 0.0, from.y)
	for seg in segments_for_wall(wall, plan):
		var a0: float = seg.a0
		var a1: float = seg.a1
		match String(seg.kind):
			"wall", "lintel":
				var mid := origin + dir * ((a0 + a1) * 0.5)
				_add_segment(mid, yaw, a1 - a0, seg.y0, seg.y1, outward, color, String(seg.kind))
			"door":
				var door := Door.new()
				door.name = "Door"
				door.width = a1 - a0
				door.height = minf(plan.door_height, plan.wall_height)
				door.wall_height = plan.wall_height
				door.outward = outward
				var mount := Node3D.new()
				mount.name = "DoorMount"
				mount.position = origin + dir * a0
				mount.rotation.y = yaw
				add_child(mount)
				mount.add_child(door)
				doors.append(door)
			"window":
				var win := HouseWindow.new()
				win.name = "Window"
				win.width = a1 - a0
				win.wall_height = plan.wall_height
				win.wall_thickness = plan.wall_thickness
				win.sill_height = plan.window_sill_height
				win.top_height = plan.window_top_height
				win.wall_color = color
				win.outward = outward
				win.position = origin + dir * ((a0 + a1) * 0.5)
				win.rotation.y = yaw
				add_child(win)
				windows.append(win)


func _add_segment(mid: Vector3, yaw: float, length: float, y0: float, y1: float,
		outward: Vector3, color: Color, kind: String) -> void:
	var body := StaticBody3D.new()
	body.name = "Wall" if kind == "wall" else "Lintel"
	body.collision_layer = (1 << 0) | (1 << 5)
	body.collision_mask = 0
	body.position = mid
	body.rotation.y = yaw
	body.add_to_group(&"wall")
	body.add_to_group(&"occluder")
	body.set_meta(&"outward", outward)
	body.set_meta(&"wall_height", plan.wall_height)
	body.set_meta(&"exterior", outward.length_squared() > 0.5)
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(length, y1 - y0, plan.wall_thickness)
	box.material = _material(color)
	mi.mesh = box
	mi.position = Vector3(0, (y0 + y1) * 0.5, 0)
	visual.add_child(mi)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	shape.position = mi.position
	body.add_child(shape)
	add_child(body)
	wall_segments.append(body)


func _build_roof() -> void:
	var body := StaticBody3D.new()
	body.name = "Roof"
	body.collision_layer = 1 << 5  # occluders only: never blocks anything
	body.collision_mask = 0
	body.add_to_group(&"roof")
	body.add_to_group(&"occluder")
	var t := plan.wall_thickness
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(plan.footprint.x + t, 0.15, plan.footprint.y + t)
	box.material = _material(plan.roof_color)
	mi.mesh = box
	visual.add_child(mi)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size
	shape.shape = bs
	body.add_child(shape)
	body.position = Vector3(plan.footprint.x * 0.5, plan.wall_height + 0.075, plan.footprint.y * 0.5)
	add_child(body)
	roof = body


# --- Furniture (Round 5) -----------------------------------------------------

func stable_id() -> String:
	return building_id if building_id != "" else String(name)


## Pure: building-local transform data for a furniture entry:
## {position: Vector3 (floor centre), yaw: float (radians)}.
static func furniture_placement(entry: Dictionary, p: BuildingPlan) -> Dictionary:
	var room := p.room_named(String(entry.get("room", "")))
	var rect: Rect2 = room.get("rect", Rect2())
	var at: Vector2 = rect.position + (entry.get("position", Vector2.ZERO) as Vector2)
	return {"position": Vector3(at.x, 0.0, at.y), "yaw": deg_to_rad(float(entry.get("rotation", 0.0)))}


func _build_furniture() -> void:
	if plan.furniture.is_empty():
		return
	var catalog := furniture_catalog if furniture_catalog else load(DEFAULT_CATALOG) as FurnitureCatalog
	var holder := Node3D.new()
	holder.name = "Furniture"
	add_child(holder)
	var per_room := {}
	for entry in plan.furniture:
		var room := plan.room_named(String(entry.get("room", "")))
		if room.is_empty():
			continue
		var type := StringName(entry.get("type", &""))
		var spec := catalog.resolve(type, entry)
		var room_type := BuildingPlan.room_type_of(room)
		var place := furniture_placement(entry, plan)
		var ctype := StringName(spec.container_type) if spec.container_type != null else &""
		var body: StaticBody3D
		if ctype != &"":
			var c := LootContainer.new()
			c.container_type = ctype
			c.capacity = float(spec.capacity)
			c.room_type = room_type
			c.building_type = plan.building_type
			var idx: int = per_room.get(room_type, 0)
			per_room[room_type] = idx + 1
			c.persist_id = "%s/%s/%d" % [stable_id(), room_type, idx]
			c.display_name = String(spec.name) if String(spec.name) != "" else LootContainer.default_name(ctype)
			c.prompt_height = minf((spec.size as Vector3).y, 1.1)
			c.size = spec.size
			c.color = spec.color
			c.lid_style = StringName(spec.lid)
			c.occluder_min_height = occluder_min_height
			var fixed: Array[Dictionary] = []
			for f in entry.get("fixed", []):
				fixed.append(f)
			c.fixed_items = fixed
			body = c
			containers.append(c)
		else:
			body = StaticBody3D.new()
			_furnish(body, spec)
		body.name = "%s%s" % [String(type).to_pascal_case(), String(room_type).to_pascal_case()]
		body.position = place.position
		body.rotation.y = place.yaw
		body.add_to_group(&"furniture")
		body.set_meta(&"furniture_type", type)
		holder.add_child(body, true)
		furniture.append(body)


## Blockout mesh + collision for a plain (non-container) piece: layer 1
## (+ 6 / "occluder" when tall). Origin at the floor centre.
func _furnish(body: StaticBody3D, spec: Dictionary) -> void:
	var size: Vector3 = spec.size
	var color: Color = spec.color
	body.collision_layer = 1
	body.collision_mask = 0
	if size.y >= occluder_min_height:
		body.collision_layer |= 1 << 5
		body.add_to_group(&"occluder")
	var visual := Node3D.new()
	visual.name = "Visual"
	body.add_child(visual)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	mi.mesh = box
	mi.position = Vector3(0, size.y * 0.5, 0)
	visual.add_child(mi)
	# Beds get a pillow at the head (-Z end) so orientation reads.
	if StringName(spec.get("detail", &"")) == &"pillow":
		var pl := MeshInstance3D.new()
		pl.name = "Pillow"
		var pb := BoxMesh.new()
		pb.size = Vector3(size.x * 0.7, 0.12, 0.35)
		pb.material = _material(Color(0.95, 0.95, 0.92))
		pl.mesh = pb
		pl.position = Vector3(0, size.y + 0.06, -size.z * 0.5 + 0.25)
		visual.add_child(pl)
	elif StringName(spec.get("detail", &"")) == &"backrest":
		var br := MeshInstance3D.new()
		br.name = "Backrest"
		var bb := BoxMesh.new()
		bb.size = Vector3(size.x, 0.45, 0.2)
		bb.material = _material(color.darkened(0.15))
		br.mesh = bb
		br.position = Vector3(0, size.y + 0.225, -size.z * 0.5 + 0.1)
		visual.add_child(br)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(shape)
