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
## Round 7: one warm OmniLight3D per room, on at night (DayNightLighting).
@export var interior_lights: bool = true

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
			out.append({"kind": "door", "a0": a0, "a1": a1, "y0": 0.0, "y1": dh, "id": String(o.get("id", ""))})
			if h > dh + EPS:
				out.append({"kind": "lintel", "a0": a0, "a1": a1, "y0": dh, "y1": h})
		else:
			out.append({"kind": "window", "a0": a0, "a1": a1, "y0": 0.0, "y1": h, "id": String(o.get("id", ""))})
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
	_bound_r = -1.0
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
	if interior_lights:
		_add_room_light(room, rect)


## Round 7: a warm ceiling light per room (group `interior_light`),
## hidden by day — DayNightLighting switches them on at night. A shadowed
## SpotLight3D aimed at the floor whose cone just covers the room: walls
## keep the light inside (no bleeding through into the dark), light only
## escapes through doorways / windows.
func _add_room_light(room: Room, rect: Rect2) -> void:
	var l := SpotLight3D.new()
	l.name = "Light"
	var h := plan.wall_height - 0.3
	l.light_color = Color(1.0, 0.78, 0.5)
	l.light_energy = 3.0
	l.spot_range = h + 0.8
	l.spot_attenuation = 0.6
	var half := maxf(rect.size.x, rect.size.y) * 0.5
	l.spot_angle = clampf(rad_to_deg(atan(half / h)) + 6.0, 30.0, 80.0)
	l.spot_angle_attenuation = 0.6
	l.shadow_enabled = true
	l.position = Vector3(0.0, h, 0.0)
	l.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	l.visible = false
	l.add_to_group(&"interior_light")
	room.add_child(l)


func _build_wall(wall: Dictionary) -> void:
	var from: Vector2 = wall.get("from", Vector2.ZERO)
	var to: Vector2 = wall.get("to", Vector2.ZERO)
	var dir2 := (to - from).normalized()
	var dir := Vector3(dir2.x, 0.0, dir2.y)
	var yaw := atan2(-dir.z, dir.x)  # local +X -> wall direction
	var exterior := _is_exterior(wall)
	var n2: Vector2 = wall.get("outward", Vector2.ZERO)
	# Round 11: consumers (occlusion, sound, entry planner) read `outward`
	# as a WORLD vector — a rotated building turns its plan normals.
	var outward := Vector3(n2.x, 0.0, n2.y)
	if outward.length_squared() > 0.5 and is_inside_tree():
		outward = (global_basis * outward).normalized()
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
				door.persist_id = _entry_id(String(seg.get("id", "")), "door/%d" % doors.size())
				door.width = a1 - a0
				door.height = minf(plan.door_height, plan.wall_height)
				door.wall_height = plan.wall_height
				door.wall_thickness = plan.wall_thickness
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
				win.persist_id = _entry_id(String(seg.get("id", "")), "window/%d" % windows.size())
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
	var fp := plan.footprint
	var style := StringName(plan.roof_style)
	var upper := UPPER_STOREY_HEIGHT if plan.storeys >= 2 else 0.0
	var rise := 0.0
	if style == &"flat":
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		var box := BoxMesh.new()
		box.size = Vector3(fp.x + t, 0.15, fp.y + t)
		box.material = _material(plan.roof_color)
		mi.mesh = box
		mi.position = Vector3(0, upper, 0)
		visual.add_child(mi)
	else:
		var span := minf(fp.x, fp.y) * 0.5 + ROOF_OVERHANG
		rise = plan.roof_pitch * span
		var mi2 := MeshInstance3D.new()
		mi2.name = "Mesh"
		mi2.mesh = roof_mesh(style, fp, rise, ROOF_OVERHANG, plan.roof_color, plan.wall_color)
		mi2.position = Vector3(-fp.x * 0.5, upper - 0.075, -fp.y * 0.5)
		visual.add_child(mi2)
	if upper > 0.0:
		_build_upper_storey(visual, upper)
	if not plan.porch.is_empty():
		_build_porch(visual)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(fp.x + t, 0.15 + rise + upper, fp.y + t)
	shape.shape = bs
	shape.position = Vector3(0, (rise + upper) * 0.5, 0)
	body.add_child(shape)
	body.position = Vector3(fp.x * 0.5, plan.wall_height + 0.075, fp.y * 0.5)
	add_child(body)
	roof = body
	_build_facade_extras()


const ROOF_OVERHANG := 0.4
const UPPER_STOREY_HEIGHT := 2.6


## Pure: a pitched roof mesh over footprint [fp] (plan-local, origin at
## the footprint's min corner, eaves at y 0): gable / hip / gambrel with
## the ridge along the longer axis. Surface 0 = roof, 1 = gable ends.
static func roof_mesh(style: StringName, fp: Vector2, rise: float, o: float, roof_col: Color, wall_col: Color) -> ArrayMesh:
	var along_x := fp.x >= fp.y
	# Work in (a, b): a along the ridge (length L), b across (width B).
	var L := fp.x if along_x else fp.y
	var B := fp.y if along_x else fp.x
	var P := func(a: float, y: float, b: float) -> Vector3:
		return Vector3(a, y, b) if along_x else Vector3(b, y, a)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ends := SurfaceTool.new()
	ends.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quad := func(tool: SurfaceTool, q: Array) -> void:
		for idx in [0, 1, 2, 0, 2, 3]:
			tool.add_vertex(q[idx])
	var tri := func(tool: SurfaceTool, q: Array) -> void:
		for v in q:
			tool.add_vertex(v)
	var mid := B * 0.5
	match style:
		&"hip":
			var inset := minf(B * 0.5 + o, L * 0.5 + o)
			var r0: Vector3 = P.call(-o + inset, rise, mid)
			var r1: Vector3 = P.call(L + o - inset, rise, mid)
			var c00: Vector3 = P.call(-o, 0.0, -o)
			var c10: Vector3 = P.call(L + o, 0.0, -o)
			var c11: Vector3 = P.call(L + o, 0.0, B + o)
			var c01: Vector3 = P.call(-o, 0.0, B + o)
			quad.call(st, [c00, c10, r1, r0])
			quad.call(st, [c11, c01, r0, r1])
			tri.call(st, [c01, c00, r0])
			tri.call(st, [c10, c11, r1])
		&"gambrel":
			var knee := B * 0.2
			var kh := rise * 0.72
			var prof := [[-o, 0.0], [knee, kh], [mid, rise], [B - knee, kh], [B + o, 0.0]]
			for i in 4:
				var p0: Array = prof[i]
				var p1: Array = prof[i + 1]
				quad.call(st, [P.call(-o, p0[1], p0[0]), P.call(L + o, p0[1], p0[0]), P.call(L + o, p1[1], p1[0]), P.call(-o, p1[1], p1[0])])
			for a in [0.0, L]:
				var ctr: Vector3 = P.call(a, rise * 0.45, mid)
				for i in 4:
					var p0b: Array = prof[i]
					var p1b: Array = prof[i + 1]
					tri.call(ends, [ctr, P.call(a, maxf(p0b[1], 0.0), clampf(p0b[0], 0.0, B)), P.call(a, maxf(p1b[1], 0.0), clampf(p1b[0], 0.0, B))])
				tri.call(ends, [ctr, P.call(a, 0.0, B), P.call(a, 0.0, 0.0)])
		_:  # gable
			var r0g: Vector3 = P.call(-o, rise, mid)
			var r1g: Vector3 = P.call(L + o, rise, mid)
			quad.call(st, [P.call(-o, 0.0, -o), P.call(L + o, 0.0, -o), r1g, r0g])
			quad.call(st, [P.call(L + o, 0.0, B + o), P.call(-o, 0.0, B + o), r0g, r1g])
			for a2 in [0.0, L]:
				tri.call(ends, [P.call(a2, 0.0, 0.0), P.call(a2, 0.0, B), P.call(a2, rise, mid)])
	st.generate_normals()
	ends.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	ends.commit(mesh)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = roof_col
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, rm)
	if mesh.get_surface_count() > 1:
		var wm := StandardMaterial3D.new()
		wm.albedo_color = wall_col
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(1, wm)
	return mesh


## A decorative upper storey (walls + windows) on the roof node: hidden
## with the roof when the player is inside (the interior is one floor).
func _build_upper_storey(visual: Node3D, h: float) -> void:
	var fp := plan.footprint
	var t := plan.wall_thickness
	var box := MeshInstance3D.new()
	box.name = "Upper"
	var bm := BoxMesh.new()
	bm.size = Vector3(fp.x + t, h, fp.y + t)
	bm.material = _material(plan.wall_color)
	box.mesh = bm
	box.position = Vector3(0, h * 0.5 - 0.075, 0)
	visual.add_child(box)
	var glass := _material(Color(0.32, 0.4, 0.48))
	var trim := _material(plan.wall_color.lightened(0.35))
	for side in 4:
		var along_x := side < 2
		var length := fp.x if along_x else fp.y
		var n := maxi(1, int(length / 3.2))
		for i in n:
			var off := -length * 0.5 + length * (i + 0.5) / n
			var w := MeshInstance3D.new()
			var wbm := BoxMesh.new()
			wbm.size = Vector3(0.95, 1.15, 0.05) if along_x else Vector3(0.05, 1.15, 0.95)
			wbm.material = glass
			w.mesh = wbm
			var sgn := -1.0 if side % 2 == 0 else 1.0
			w.position = Vector3(off, h * 0.55, sgn * (fp.y + t) * 0.5) if along_x else Vector3(sgn * (fp.x + t) * 0.5, h * 0.55, off)
			visual.add_child(w)
			var sill := MeshInstance3D.new()
			var sbm := BoxMesh.new()
			sbm.size = Vector3(1.15, 0.08, 0.1) if along_x else Vector3(0.1, 0.08, 1.15)
			sbm.material = trim
			sill.mesh = sbm
			sill.position = w.position + Vector3(0, -0.62, 0)
			visual.add_child(sill)


## Porch: deck + posts in front of the front wall (+Z side); its little
## roof rides on the roof node (hidden inside).
func _build_porch(visual: Node3D) -> void:
	var fp := plan.footprint
	var at := float(plan.porch.get("at", fp.x * 0.5))
	var pw := float(plan.porch.get("width", 4.0))
	var pd := float(plan.porch.get("depth", 2.0))
	var deck := MeshInstance3D.new()
	deck.name = "PorchDeck"
	var dm := BoxMesh.new()
	dm.size = Vector3(pw, 0.08, pd)
	dm.material = _material(Color(0.52, 0.42, 0.3))
	deck.mesh = dm
	deck.position = Vector3(at, 0.04, fp.y + pd * 0.5)
	add_child(deck)
	var posts := StaticBody3D.new()
	posts.name = "PorchPosts"
	posts.collision_layer = 1
	posts.collision_mask = 0
	add_child(posts)
	for sx in [-1.0, 1.0]:
		var pos := Vector3(at + sx * (pw * 0.5 - 0.12), plan.wall_height * 0.5, fp.y + pd - 0.12)
		var mi := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.14, plan.wall_height, 0.14)
		pm.material = _material(Color(0.9, 0.88, 0.82))
		mi.mesh = pm
		mi.position = pos
		posts.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = pm.size
		cs.shape = bs
		cs.position = pos
		posts.add_child(cs)
	# Porch roof (roof node local: origin at the footprint centre, wall top).
	var pr := MeshInstance3D.new()
	pr.name = "PorchRoof"
	var prm := BoxMesh.new()
	prm.size = Vector3(pw + 0.3, 0.12, pd + 0.2)
	prm.material = _material(plan.roof_color)
	pr.mesh = prm
	pr.position = Vector3(at - fp.x * 0.5, -0.1, fp.y * 0.5 + pd * 0.5)
	visual.add_child(pr)


## Sign board (Label3D) and awning over the front door.
func _build_facade_extras() -> void:
	if plan.sign_text == "" and plan.awning_color.a <= 0.0:
		return
	var door := Vector2.INF
	var n2 := Vector2.ZERO
	var along := Vector2.RIGHT
	for w in plan.walls:
		for o in w.get("openings", []):
			if String(o.get("id", "")) == "front_door":
				var from: Vector2 = w.from
				var to: Vector2 = w.to
				along = (to - from).normalized()
				door = from + along * float(o.at)
				n2 = w.get("outward", Vector2.ZERO)
	if door == Vector2.INF:
		return
	var outward := Vector3(n2.x, 0, n2.y)
	var base := Vector3(door.x, 0, door.y)
	var yaw := atan2(outward.x, outward.z)
	if plan.awning_color.a > 0.0:
		var aw := MeshInstance3D.new()
		aw.name = "Awning"
		var am := BoxMesh.new()
		am.size = Vector3(plan.door_width + 2.6, 0.12, 1.3)
		am.material = _material(plan.awning_color)
		aw.mesh = am
		aw.position = base + outward * 0.7 + Vector3.UP * (plan.door_height + 0.2)
		aw.rotation.y = yaw
		aw.rotation.x = 0.0
		add_child(aw)
	if plan.sign_text != "":
		var y := minf(plan.door_height + 0.7, plan.wall_height - 0.15)
		var board := MeshInstance3D.new()
		board.name = "SignBoard"
		var bm := BoxMesh.new()
		var bw := clampf(plan.sign_text.length() * 0.32 + 0.8, 2.0, 6.0)
		bm.size = Vector3(bw, 0.55, 0.08)
		bm.material = _material(Color(0.12, 0.14, 0.18))
		board.mesh = bm
		board.position = base + outward * 0.16 + Vector3.UP * y
		board.rotation.y = yaw
		add_child(board)
		var label := Label3D.new()
		label.name = "Sign"
		label.text = plan.sign_text
		label.font_size = 48
		label.pixel_size = 0.0075
		label.outline_size = 6
		label.modulate = Color(0.98, 0.92, 0.72)
		label.position = base + outward * 0.215 + Vector3.UP * y
		label.rotation.y = yaw
		add_child(label)


# --- Furniture (Round 5) -----------------------------------------------------

func stable_id() -> String:
	return building_id if building_id != "" else String(name)


## "<building>/<data id>" (Round 10). Plans without ids (tests, old data)
## fall back to a build-order id, reported by BuildingPlan.validate().
func _entry_id(data_id: String, fallback: String) -> String:
	return "%s/%s" % [stable_id(), data_id if data_id != "" else fallback]


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
			c.persist_id = _entry_id(String(entry.get("id", "")), "%s/%d" % [room_type, idx])
			c.display_name = String(spec.name) if String(spec.name) != "" else LootContainer.default_name(ctype)
			c.prompt_height = minf((spec.size as Vector3).y, 1.1)
			c.size = spec.size
			c.color = spec.color
			c.lid_style = StringName(spec.lid)
			c.spoil_multiplier = float(spec.get("spoil_multiplier", 1.0))
			c.occluder_min_height = occluder_min_height
			var fixed: Array[Dictionary] = []
			for f in entry.get("fixed", []):
				fixed.append(f)
			c.fixed_items = fixed
			body = c
			containers.append(c)
		else:
			body = _interactive_piece(spec)
			_furnish(body, spec)
		body.name = "%s%s" % [String(type).to_pascal_case(), String(room_type).to_pascal_case()]
		body.position = place.position
		body.rotation.y = place.yaw
		body.add_to_group(&"furniture")
		body.set_meta(&"furniture_type", type)
		_add_furniture_work(body, spec, _entry_id(String(entry.get("id", "")), "furniture/%d" % furniture.size()))
		holder.add_child(body, true)
		furniture.append(body)


## Round 9: movable / disassemblable pieces (catalog keys movable,
## block_health, disassemble) get a FurnitureWork child: "Block door",
## "Disassemble". Only interactive bodies (containers, beds, sofas) — the
## actions ride on their Interactable.
func _add_furniture_work(body: StaticBody3D, spec: Dictionary, entry_persist_id: String = "") -> void:
	var movable := bool(spec.get("movable", false))
	var dis: Dictionary = spec.get("disassemble", {})
	if not movable and dis.is_empty():
		return
	if not (body is LootContainer or body is RestFurniture or body is Sink):
		return
	var fw := FurnitureWork.new()
	fw.name = FurnitureWork.NODE_NAME
	# Round 10: the save id comes from the plan entry's "id" (data).
	fw.persist_id = entry_persist_id + "/furniture" if entry_persist_id != "" else ""
	fw.display_name = String(spec.name) if String(spec.name) != "" else "Furniture"
	fw.size = spec.size
	fw.movable = movable
	fw.block_health = float(spec.get("block_health", 200.0))
	fw.disassemble_yield = dis.duplicate(true)
	body.add_child(fw)


## Round 7: a bed / sofa (RestFurniture) or a sink (Sink) when the catalog
## entry has an `interaction`; a plain StaticBody3D otherwise.
func _interactive_piece(spec: Dictionary) -> StaticBody3D:
	var kind := StringName(spec.get("interaction", &""))
	var nm := String(spec.get("name", ""))
	match kind:
		&"sink":
			var sk := Sink.new()
			sk.size = spec.size
			if nm != "":
				sk.display_name = nm
			return sk
		&"bed", &"seat":
			var rf := RestFurniture.new()
			rf.kind = kind
			rf.size = spec.size
			rf.display_name = nm if nm != "" else String(kind).capitalize()
			return rf
	return StaticBody3D.new()


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
	elif StringName(spec.get("detail", &"")) == &"basin":
		var bn := MeshInstance3D.new()
		bn.name = "Basin"
		var bm := BoxMesh.new()
		bm.size = Vector3(size.x * 0.6, 0.04, size.z * 0.6)
		bm.material = _material(Color(0.55, 0.62, 0.7))
		bn.mesh = bm
		bn.position = Vector3(0, size.y + 0.005, 0.03)
		visual.add_child(bn)
		var tap := MeshInstance3D.new()
		tap.name = "Tap"
		var tm := BoxMesh.new()
		tm.size = Vector3(0.05, 0.18, 0.05)
		tm.material = _material(Color(0.75, 0.76, 0.8))
		tap.mesh = tm
		tap.position = Vector3(0, size.y + 0.09, -size.z * 0.5 + 0.06)
		visual.add_child(tap)
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
