class_name WorldBuilder
extends Node3D
## Builds a WorldLayout into the scene (Round 11; node "Generated" in
## maps/world.tscn). At _ready: reads the seed (WorldConfig.world_seed)
## and params (WorldConfig.worldgen_params, else [params]), generates the
## layout (WorldGenerator, pure) and instantiates it:
##
##   Ground        one StaticBody (box) + one plane with the splat shader
##   Bounds        invisible walls around the world
##   Chunks/C_x_z  one Node3D per 64 m chunk (group "world_chunk", meta
##                 "chunk" = Vector2i) holding everything whose centre is
##                 in it: HouseBlockout buildings (plan from the layout,
##                 building_id = layout id → stable save ids), a road /
##                 sidewalk / marking / path mesh, "Solids" (StaticBody
##                 with one box / cylinder shape owner per fence piece,
##                 prop, tree trunk — parsed by the chunk navmesh bake)
##                 + one MultiMesh of vertex-coloured boxes (fences,
##                 props, crop rows), tree trunk / canopy MultiMeshes,
##                 vehicles, gas pumps, lamp lights, ponds.
##
## Everything is built at load (~60 buildings, ~7k trees); WorldNav bakes
## navigation only for chunks near the player; zombies exist only near the
## start (ZombieSpawner.spawn_points = layout.zombies). Round 12 streams
## chunks in / out using the same chunk nodes.

const GROUP := &"world_builder"
const DEFAULT_PARAMS := "res://data/worldgen/default_world.tres"
const VEHICLE_DIR := "res://data/vehicles/%s.tres"
## Road surface heights (stacked flat quads, no z-fight at 45 m ortho distance).
const Y_SIDEWALK := 0.012
const Y_PATH := 0.016
const Y_ROAD := 0.022
const Y_MARK := 0.03
const ROAD_COLORS := {&"highway": Color(0.2, 0.2, 0.22), &"street": Color(0.27, 0.27, 0.29),
	&"county": Color(0.24, 0.24, 0.25), &"dirt": Color(0.45, 0.36, 0.25)}
const SIDEWALK_COLOR := Color(0.6, 0.6, 0.57)
const PARKING_COLOR := Color(0.3, 0.3, 0.32)
const DRIVEWAY_COLOR := Color(0.52, 0.51, 0.48)
const PATH_COLOR := Color(0.62, 0.6, 0.55)
const DIRT_COLOR := Color(0.48, 0.39, 0.27)
const YELLOW := Color(0.85, 0.7, 0.15)
const WHITE := Color(0.85, 0.85, 0.82)
const CURB_COLOR := Color(0.72, 0.71, 0.67)
const CROPS := {&"corn": [Color(0.36, 0.52, 0.2), 1.7, 0.55], &"wheat": [Color(0.78, 0.68, 0.34), 0.8, 1.1],
	&"cabbage": [Color(0.4, 0.6, 0.34), 0.35, 0.5], &"fallow": [Color(0.4, 0.31, 0.21), 0.14, 0.8]}

@export var params: WorldGenParams
@export var build_on_ready: bool = true
## Build only chunks within this Chebyshev radius of the start (-1 = all).
@export var build_radius: int = -1
@export_group("Night lights")
## Lights (room lights, street lamps) are only on within this Chebyshev
## chunk radius of the player and [light_far] metres.
@export var light_chunk_radius: int = 2
@export var light_far: float = 60.0
## Only the nearest this many room lights cast shadows (street lamps never).
@export var shadowed_lights: int = 10

var layout: WorldLayout
var world_seed: int = 0
## Vector2i → chunk Node3D.
var chunks: Dictionary = {}
## Building id → HouseBlockout.
var buildings: Dictionary = {}
var layout_ms: float = 0.0
var build_ms: float = 0.0
var canopy_material: ShaderMaterial
var box_material: StandardMaterial3D
var road_material: StandardMaterial3D
var built: bool = false

var _batches: Dictionary = {}
var _roads: Dictionary = {}
var _solids: Dictionary = {}
var _shape_cache: Dictionary = {}
var _vehicle_data: Dictionary = {}
var _trees: Dictionary = {}
var _unit_box: BoxMesh


static func of(tree: SceneTree) -> WorldBuilder:
	return tree.get_first_node_in_group(GROUP) as WorldBuilder if tree != null else null


## Counts from the last light-budget pass (tests / perf).
var light_stats: Dictionary = {"on": false, "visible": 0, "shadowed": 0, "lamps": 0, "total": 0}
var _light_tick: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"light_budget")
	if build_on_ready:
		generate_and_build()


func generate_and_build() -> void:
	var cfg := WorldConfig.find(get_tree())
	world_seed = cfg.world_seed if cfg != null else 1337
	var prm := params
	if cfg != null and cfg.worldgen_params != "" and cfg.worldgen_params.begins_with("res://data/worldgen/"):
		var loaded := load(cfg.worldgen_params) as WorldGenParams
		if loaded != null:
			prm = loaded
	if prm == null:
		prm = load(DEFAULT_PARAMS) as WorldGenParams
	var t0 := Time.get_ticks_usec()
	layout = WorldGenerator.generate(world_seed, prm)
	layout_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if cfg != null:
		cfg.worldgen_params = prm.resource_path
	var t1 := Time.get_ticks_usec()
	build()
	build_ms = (Time.get_ticks_usec() - t1) / 1000.0
	_place_player()
	_configure_spawner()
	print("WorldBuilder: seed %d, layout %.0f ms, build %.0f ms, %d chunks, %d buildings, %d trees, %d nodes" % [
		world_seed, layout_ms, build_ms, chunks.size(), buildings.size(), layout.tree_count(), node_count()])


var _layout_hash: String = ""


## The layout's hash (computed once; saves store it).
func layout_hash() -> String:
	if _layout_hash == "" and layout != null:
		_layout_hash = layout.layout_hash()
	return _layout_hash


func node_count() -> int:
	return _count(self)


static func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


## The chunk node holding world point [p] (null when not built).
func chunk_node_at(p: Vector3) -> Node3D:
	return chunks.get(layout.chunk_of(Vector2(p.x, p.z))) as Node3D


func start_position() -> Vector3:
	return Vector3(layout.spawn_point.x, 0.1, layout.spawn_point.y)


# --- Build ----------------------------------------------------------------------------

func _wanted(c: Vector2i) -> bool:
	if build_radius < 0:
		return true
	var sc := layout.chunk_of(layout.spawn_point)
	return maxi(absi(c.x - sc.x), absi(c.y - sc.y)) <= build_radius


func _chunk(c: Vector2i) -> Node3D:
	if chunks.has(c):
		return chunks[c]
	var holder := get_node_or_null("Chunks")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Chunks"
		add_child(holder)
	var n := Node3D.new()
	n.name = "C_%02d_%02d" % [c.x, c.y]
	n.set_meta(&"chunk", c)
	n.add_to_group(&"world_chunk")
	holder.add_child(n)
	chunks[c] = n
	return n


func _chunk_of(p: Vector2) -> Vector2i:
	return layout.chunk_of(p)


func build() -> void:
	built = false
	_unit_box = BoxMesh.new()
	box_material = StandardMaterial3D.new()
	box_material.vertex_color_use_as_albedo = true
	box_material.roughness = 1.0
	_unit_box.material = box_material
	road_material = StandardMaterial3D.new()
	road_material.vertex_color_use_as_albedo = true
	road_material.roughness = 0.95
	canopy_material = ShaderMaterial.new()
	canopy_material.shader = load("res://assets/materials/tree_canopy.gdshader")
	_build_ground()
	for cz in layout.chunks_z():
		for cx in layout.chunks_x():
			if _wanted(Vector2i(cx, cz)):
				_chunk(Vector2i(cx, cz))
	_build_roads()
	_build_paths()
	_build_buildings()
	_build_fences()
	_build_fields()
	_build_props()
	_build_vehicles()
	_build_trees()
	_build_ponds()
	_flush()
	built = true


# --- Ground -----------------------------------------------------------------------------

func _build_ground() -> void:
	var size := layout.size
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x + 40.0, 1.0, size.y + 40.0)
	shape.shape = box
	shape.position = Vector3(size.x * 0.5, -0.5, size.y * 0.5)
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	var pm := PlaneMesh.new()
	pm.size = size + Vector2(40.0, 40.0)
	mi.mesh = pm
	mi.position = Vector3(size.x * 0.5, 0.0, size.y * 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/materials/world_ground.gdshader")
	mat.set_shader_parameter(&"splat", ImageTexture.create_from_image(splat_image(layout)))
	mat.set_shader_parameter(&"world_size", size)
	mi.material_override = mat
	body.add_child(mi)
	# Invisible walls around the world edge.
	var bounds := StaticBody3D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)
	for e in [[Vector3(size.x * 0.5, 2.0, -0.5), Vector3(size.x + 2.0, 4.0, 1.0)],
			[Vector3(size.x * 0.5, 2.0, size.y + 0.5), Vector3(size.x + 2.0, 4.0, 1.0)],
			[Vector3(-0.5, 2.0, size.y * 0.5), Vector3(1.0, 4.0, size.y + 2.0)],
			[Vector3(size.x + 0.5, 2.0, size.y * 0.5), Vector3(1.0, 4.0, size.y + 2.0)]]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = e[1]
		cs.shape = bs
		cs.position = e[0]
		bounds.add_child(cs)


## Round 11 palette: olive / desaturated greens (saturation −30 %,
## value −15 % of the Round-10 greens).
static func olive(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s * 0.7, c.v * 0.85)


## Ground colours, 1 texel per 2 m: meadow, woods floor, farmland soil,
## gravel verges along rural roads, yards (lots), pond banks.
static func splat_image(l: WorldLayout) -> Image:
	var mpp := 2.0
	var w := int(ceil(l.size.x / mpp))
	var h := int(ceil(l.size.y / mpp))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var meadow := olive(Color(0.36, 0.47, 0.24))
	var woods := olive(Color(0.24, 0.3, 0.16))
	var field := olive(Color(0.42, 0.45, 0.24))
	for y in h:
		for x in w:
			var z := l.zone_at(Vector2((x + 0.5) * mpp, (y + 0.5) * mpp))
			img.set_pixel(x, y, woods if z == WorldLayout.Zone.WOODS else (field if z == WorldLayout.Zone.FIELD else meadow))
	for rd in l.roads:
		if not (rd.kind in [&"highway", &"county"]):
			continue
		var pts: PackedVector2Array = rd.points
		for i in range(pts.size() - 1):
			_fill_capsule(img, pts[i], pts[i + 1], float(rd.width) * 0.5 + 1.8, Color(0.5, 0.47, 0.38), mpp)
	for lot in l.lots:
		var col := olive(Color(0.4, 0.52, 0.27))
		if lot.use == &"farmstead":
			col = Color(0.45, 0.42, 0.3)
		elif lot.use in [&"gas_station", &"warehouse", &"parking"]:
			col = Color(0.46, 0.45, 0.4)
		_fill_poly(img, WorldLayout.poly_of(lot), col, mpp)
	for fl in l.fields:
		var fxf: Transform2D = fl.xf
		var fsz: Vector2 = fl.size
		_fill_poly(img, WorldLayout.obb_poly(fxf * Transform2D(0.0, Vector2(-0.6, -0.6)), fsz + Vector2(1.2, 1.2)),
			Color(0.36, 0.28, 0.19), mpp)
	for pd in l.ponds:
		var c: Vector2 = pd.center
		var rad := float(pd.radius) + 2.0
		for yy in range(int((c.y - rad) / mpp), int((c.y + rad) / mpp) + 1):
			for xx in range(int((c.x - rad) / mpp), int((c.x + rad) / mpp) + 1):
				if xx >= 0 and yy >= 0 and xx < w and yy < h and Vector2((xx + 0.5) * mpp, (yy + 0.5) * mpp).distance_to(c) < rad:
					img.set_pixel(xx, yy, Color(0.5, 0.46, 0.33))
	return img


static func _fill_poly(img: Image, poly: PackedVector2Array, c: Color, mpp: float) -> void:
	var r := WorldLayout.poly_aabb(poly)
	var x0 := clampi(int(r.position.x / mpp), 0, img.get_width())
	var y0 := clampi(int(r.position.y / mpp), 0, img.get_height())
	var x1 := clampi(int(ceil(r.end.x / mpp)), 0, img.get_width())
	var y1 := clampi(int(ceil(r.end.y / mpp)), 0, img.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) * mpp, (y + 0.5) * mpp), poly):
				img.set_pixel(x, y, c)


static func _fill_capsule(img: Image, a: Vector2, b: Vector2, half: float, c: Color, mpp: float) -> void:
	var x0 := clampi(int((minf(a.x, b.x) - half) / mpp), 0, img.get_width())
	var y0 := clampi(int((minf(a.y, b.y) - half) / mpp), 0, img.get_height())
	var x1 := clampi(int(ceil((maxf(a.x, b.x) + half) / mpp)), 0, img.get_width())
	var y1 := clampi(int(ceil((maxf(a.y, b.y) + half) / mpp)), 0, img.get_height())
	for y in range(y0, y1):
		for x in range(x0, x1):
			var q := Vector2((x + 0.5) * mpp, (y + 0.5) * mpp)
			if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < half:
				img.set_pixel(x, y, c)


# --- Flat surfaces (roads, sidewalks, paths, parking) -------------------------------------

func _st(c: Vector2i) -> SurfaceTool:
	if not _roads.has(c):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		_roads[c] = st
	return _roads[c]


func _quad(st: SurfaceTool, a: Vector2, b: Vector2, width: float, y: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.001:
		return
	var n := Vector2(-d.y, d.x).normalized() * width * 0.5
	var p0 := Vector3(a.x + n.x, y, a.y + n.y)
	var p1 := Vector3(b.x + n.x, y, b.y + n.y)
	var p2 := Vector3(b.x - n.x, y, b.y - n.y)
	var p3 := Vector3(a.x - n.x, y, a.y - n.y)
	st.set_color(col)
	# Counter-clockwise seen from above (+Y normal faces up).
	for v in _up_facing([p0, p1, p2, p0, p2, p3]):
		st.add_vertex(v)


## Reorder triangles so they face +Y.
static func _up_facing(v: Array) -> Array:
	var out: Array = []
	for i in range(0, v.size(), 3):
		var a: Vector3 = v[i]
		var b: Vector3 = v[i + 1]
		var c: Vector3 = v[i + 2]
		if (b - a).cross(c - a).y > 0.0:
			out.append_array([a, c, b])
		else:
			out.append_array([a, b, c])
	return out


func _disc(st: SurfaceTool, c: Vector2, rad: float, y: float, col: Color, sides: int = 10) -> void:
	st.set_color(col)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var tri := _up_facing([Vector3(c.x, y, c.y), Vector3(c.x + cos(a0) * rad, y, c.y + sin(a0) * rad),
			Vector3(c.x + cos(a1) * rad, y, c.y + sin(a1) * rad)])
		for v in tri:
			st.add_vertex(v)


func _rect_quad(st: SurfaceTool, r: Rect2, y: float, col: Color) -> void:
	var cy := r.get_center().y
	_quad(st, Vector2(r.position.x, cy), Vector2(r.end.x, cy), r.size.y, y, col)


## An oriented rectangle (Transform2D local frame, [size]) as a flat quad.
func _obb_quad(st: SurfaceTool, xf: Transform2D, size: Vector2, y: float, col: Color) -> void:
	var a := xf * Vector2(0.0, size.y * 0.5)
	var b := xf * Vector2(size.x, size.y * 0.5)
	_quad(st, a, b, size.y, y, col)


## Road polylines split into ≤ 16 m pieces, each assigned to the chunk of
## its midpoint.
static func pieces(pts: PackedVector2Array, max_len: float = 16.0) -> Array:
	var out: Array = []
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / max_len)))
		for k in n:
			out.append([a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), i, k, n])
	return out


func _build_roads() -> void:
	for rd in layout.roads:
		var w := float(rd.width)
		var sw := float(rd.sidewalk)
		var col: Color = ROAD_COLORS.get(StringName(rd.kind), ROAD_COLORS[&"street"])
		var pts: PackedVector2Array = rd.points
		var y := Y_ROAD - (0.004 if rd.kind == &"dirt" else 0.0)
		for pc in pieces(pts):
			var a: Vector2 = pc[0]
			var b: Vector2 = pc[1]
			var c := _chunk_of((a + b) * 0.5)
			if not chunks.has(c):
				continue
			var st := _st(c)
			if sw > 0.0:
				_quad(st, a, b, w + 2.0 * sw, Y_SIDEWALK, SIDEWALK_COLOR)
			_quad(st, a, b, w, y, col)
		for i in pts.size():
			var c2 := _chunk_of(pts[i])
			if not chunks.has(c2):
				continue
			var st2 := _st(c2)
			if sw > 0.0:
				_disc(st2, pts[i], (w + 2.0 * sw) * 0.5, Y_SIDEWALK, SIDEWALK_COLOR, 12)
			_disc(st2, pts[i], w * 0.5, y, col, 12)
		# Cul-de-sac turning circle.
		if float(rd.get("cap", 0.0)) > 0.0:
			var endp := pts[pts.size() - 1]
			var c3 := _chunk_of(endp)
			if chunks.has(c3):
				_disc(_st(c3), endp, float(rd.cap) + sw, Y_SIDEWALK, SIDEWALK_COLOR, 20)
				_disc(_st(c3), endp, float(rd.cap), y, col, 20)
		# Curbs: a pale kerb line on both road edges of streets.
		if sw > 0.0:
			_dashes(rd, w * 0.5 + 0.1, 1000.0, 0.0, 0.2, CURB_COLOR, Y_ROAD + 0.002)
			_dashes(rd, -(w * 0.5 + 0.1), 1000.0, 0.0, 0.2, CURB_COLOR, Y_ROAD + 0.002)
		# Markings: dashed yellow centre line on through roads, white edge
		# lines on the highway.
		if rd.kind in [&"highway", &"county"] or rd.id == "town_main":
			_dashes(rd, 0.0, 3.0, 3.5, 0.16, YELLOW)
		if rd.kind == &"highway":
			_dashes(rd, w * 0.5 - 0.35, 1000.0, 0.0, 0.12, WHITE)
			_dashes(rd, -(w * 0.5 - 0.35), 1000.0, 0.0, 0.12, WHITE)
	_build_crosswalks()


## Dashes along a road at lateral [offset]; [dash] / [gap] metres
## (gap 0 = solid). Kept clear of junction vertices of other roads.
func _dashes(rd: Dictionary, offset: float, dash: float, gap: float, width: float, col: Color, y_mark: float = Y_MARK) -> void:
	var pts: PackedVector2Array = rd.points
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var dir := (b - a) / len
		var nrm := Vector2(-dir.y, dir.x)
		var t := 1.5 if gap > 0.0 else 0.0
		var end := len - (1.5 if gap > 0.0 else 0.0)
		while t < end:
			var t1 := minf(t + minf(dash, 16.0), end)
			var p0 := a + dir * t + nrm * offset
			var p1 := a + dir * t1 + nrm * offset
			var c := _chunk_of((p0 + p1) * 0.5)
			if chunks.has(c) and not _near_junction((p0 + p1) * 0.5, rd):
				_quad(_st(c), p0, p1, width, y_mark, col)
			t = t1 + gap


## Zebra crossings on every street arm of a town junction (just outside
## the crossing street's sidewalk).
func _build_crosswalks() -> void:
	for j in layout.junctions:
		var arms: Array = []
		var widest := 0.0
		var town := true
		for rd in layout.roads:
			var pts: PackedVector2Array = rd.points
			for i in pts.size():
				if pts[i].distance_to(j) > 0.01:
					continue
				if not String(rd.id).begins_with("town_") or rd.kind != &"street":
					town = false
				widest = maxf(widest, float(rd.width) * 0.5 + float(rd.sidewalk))
				if i > 0:
					arms.append([rd, (pts[i - 1] - j).normalized()])
				if i < pts.size() - 1:
					arms.append([rd, (pts[i + 1] - j).normalized()])
		if not town or arms.size() < 3:
			continue
		for arm in arms:
			var rd2: Dictionary = arm[0]
			var dir: Vector2 = arm[1]
			var nrm := Vector2(-dir.y, dir.x)
			var half := float(rd2.width) * 0.5 - 0.4
			var mid := j + dir * (widest + 1.6)
			var c := _chunk_of(mid)
			if not chunks.has(c):
				continue
			var k := -half + 0.3
			while k <= half - 0.2:
				var q := mid + nrm * k
				_quad(_st(c), q - dir * 1.3, q + dir * 1.3, 0.45, Y_MARK, WHITE)
				k += 0.9


func _near_junction(p: Vector2, own: Dictionary) -> bool:
	for rd in layout.roads:
		if rd == own:
			continue
		if WorldLayout.distance_to_road(p, rd) < float(rd.width) * 0.5 + 0.5:
			return true
	return false


func _build_paths() -> void:
	for pth in layout.paths:
		if pth.has("xf"):
			var pxf: Transform2D = pth.xf
			var psz: Vector2 = pth.size
			var c := _chunk_of(pxf * (psz * 0.5))
			if chunks.has(c):
				_obb_quad(_st(c), pxf, psz, Y_PATH, PARKING_COLOR)
			continue
		var a: Vector2 = pth.a
		var b: Vector2 = pth.b
		var farm := String(pth.get("lot", "")).begins_with("farm")
		var col := DRIVEWAY_COLOR if pth.kind == &"driveway" else PATH_COLOR
		if farm:
			col = DIRT_COLOR
		for pc in pieces(PackedVector2Array([a, b])):
			var c2 := _chunk_of((pc[0] + pc[1]) * 0.5)
			if chunks.has(c2):
				_quad(_st(c2), pc[0], pc[1], float(pth.width), Y_PATH, col)
	for pk in layout.parking:
		var kxf: Transform2D = pk.xf
		var ksz: Vector2 = pk.size
		var c3 := _chunk_of(kxf * (ksz * 0.5))
		if not chunks.has(c3):
			continue
		var st := _st(c3)
		_obb_quad(st, kxf, ksz, Y_PATH, PARKING_COLOR)
		# Stall lines (lot-local: stalls across x, 5 m deep from each long edge).
		var n := int(ksz.x / 2.8)
		var rows := 2 if ksz.y >= 12.0 else 1
		for row in rows:
			for i in n + 1:
				var t := 0.2 + float(i) * 2.8
				var d0 := 0.3 if row == 0 else ksz.y - 5.3
				_quad(st, kxf * Vector2(t, d0), kxf * Vector2(t, d0 + 5.0), 0.1, Y_MARK, WHITE)


# --- Buildings --------------------------------------------------------------------------

func _build_buildings() -> void:
	for b in layout.buildings:
		var r: Rect2 = b.rect
		var c := _chunk_of(r.get_center())
		if not chunks.has(c):
			continue
		var holder := _sub(c, "Buildings")
		var hb := HouseBlockout.new()
		hb.name = String(b.id)
		hb.building_id = String(b.id)
		hb.plan = layout.plans[b.id]
		var bxf: Transform2D = b.xf
		hb.position = Vector3(bxf.origin.x, 0.0, bxf.origin.y)
		hb.rotation.y = -bxf.get_rotation()
		hb.set_meta(&"kind", b.kind)
		holder.add_child(hb)
		buildings[b.id] = hb


func _sub(c: Vector2i, name: String) -> Node3D:
	var ch: Node3D = chunks[c]
	var n := ch.get_node_or_null(name) as Node3D
	if n == null:
		n = Node3D.new()
		n.name = name
		ch.add_child(n)
	return n


# --- Box batches + solids ------------------------------------------------------------------

## A vertex-coloured unit box instance in chunk [c].
func _box(c: Vector2i, center: Vector3, size: Vector3, yaw: float, col: Color) -> void:
	if not _batches.has(c):
		_batches[c] = []
	var basis := Basis(Vector3.UP, yaw).scaled_local(size)
	_batches[c].append([Transform3D(basis, center), col])


## A collision box (shape owner of the chunk's "Solids" body).
func _solid_box(c: Vector2i, center: Vector3, size: Vector3, yaw: float) -> void:
	var key := "b%.2f,%.2f,%.2f" % [size.x, size.y, size.z]
	if not _shape_cache.has(key):
		var bs := BoxShape3D.new()
		bs.size = size
		_shape_cache[key] = bs
	_solid_shape(c, _shape_cache[key], Transform3D(Basis(Vector3.UP, yaw), center))


func _solid_shape(c: Vector2i, shape: Shape3D, xf: Transform3D) -> void:
	var body := _solid_body(c)
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, shape)
	body.shape_owner_set_transform(owner_id, xf)


func _solid_body(c: Vector2i) -> StaticBody3D:
	if not _solids.has(c):
		var body := StaticBody3D.new()
		body.name = "Solids"
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group(&"world_solids")
		chunks[c].add_child(body)
		_solids[c] = body
	return _solids[c]


func _flush() -> void:
	for c in _batches:
		var list: Array = _batches[c]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _unit_box
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Boxes"
		mmi.multimesh = mm
		chunks[c].add_child(mmi)
	_batches.clear()
	for c in _roads:
		var st: SurfaceTool = _roads[c]
		var mi := MeshInstance3D.new()
		mi.name = "Roads"
		mi.mesh = st.commit()
		mi.material_override = road_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		chunks[c].add_child(mi)
	_roads.clear()
	for c in _trees:
		_flush_trees(c, _trees[c])
	_trees.clear()


# --- Fences -------------------------------------------------------------------------------

func _build_fences() -> void:
	for fe in layout.fences:
		for pc in pieces(PackedVector2Array([fe.a, fe.b]), 12.0):
			var a: Vector2 = pc[0]
			var b: Vector2 = pc[1]
			var c := _chunk_of((a + b) * 0.5)
			if not chunks.has(c):
				continue
			var len := a.distance_to(b)
			if len < 0.05:
				continue
			var mid := (a + b) * 0.5
			var dir := (b - a) / len
			var yaw := atan2(-dir.y, dir.x)
			match StringName(fe.kind):
				&"hedge":
					_box(c, Vector3(mid.x, 0.65, mid.y), Vector3(len, 1.3, 0.8), yaw, Color(0.2, 0.36, 0.17))
					_solid_box(c, Vector3(mid.x, 0.65, mid.y), Vector3(len, 1.3, 0.8), yaw)
				&"wire":
					var n := maxi(1, int(round(len / 3.0)))
					for k in n + 1:
						var p := a.lerp(b, float(k) / n)
						_box(c, Vector3(p.x, 0.55, p.y), Vector3(0.08, 1.1, 0.08), yaw, Color(0.45, 0.4, 0.34))
					for h in [0.35, 0.7, 1.0]:
						_box(c, Vector3(mid.x, h, mid.y), Vector3(len, 0.025, 0.025), yaw, Color(0.55, 0.55, 0.55))
					_solid_box(c, Vector3(mid.x, 0.6, mid.y), Vector3(len, 1.2, 0.12), yaw)
				_:
					var n2 := maxi(1, int(round(len / 2.4)))
					for k in n2 + 1:
						var p2 := a.lerp(b, float(k) / n2)
						_box(c, Vector3(p2.x, 0.6, p2.y), Vector3(0.12, 1.2, 0.12), yaw, Color(0.4, 0.28, 0.18))
					for h in [0.45, 0.95]:
						_box(c, Vector3(mid.x, h, mid.y), Vector3(len, 0.1, 0.05), yaw, Color(0.5, 0.36, 0.22))
					_solid_box(c, Vector3(mid.x, 0.6, mid.y), Vector3(len, 1.2, 0.12), yaw)


# --- Fields -------------------------------------------------------------------------------

func _build_fields() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = WorldGenerator.sub_seed(world_seed, "crops")
	for fl in layout.fields:
		var fxf: Transform2D = fl.xf
		var fsz: Vector2 = fl.size
		var spec: Array = CROPS.get(StringName(fl.crop), CROPS[&"fallow"])
		var col: Color = spec[0]
		var h: float = spec[1]
		var rw: float = spec[2]
		var axis := int(fl.axis)
		var across := fsz.y - 2.0 if axis == 0 else fsz.x - 2.0
		var along := fsz.x - 2.0 if axis == 0 else fsz.y - 2.0
		var rows := int(across / 1.6)
		for i in rows:
			var off := 1.0 + (float(i) + 0.5) * across / rows
			var la := Vector2(1.0, off) if axis == 0 else Vector2(off, 1.0)
			var lb := la + (Vector2(along, 0.0) if axis == 0 else Vector2(0.0, along))
			for pc in pieces(PackedVector2Array([fxf * la, fxf * lb]), 8.0):
				var p0: Vector2 = pc[0]
				var p1: Vector2 = pc[1]
				var c := _chunk_of((p0 + p1) * 0.5)
				if not chunks.has(c):
					continue
				var len := p0.distance_to(p1) - 0.3
				var mid := (p0 + p1) * 0.5
				var hh := h * r.randf_range(0.85, 1.1)
				var shade := col.lerp(col.darkened(0.25), r.randf())
				var dir := (p1 - p0).normalized()
				_box(c, Vector3(mid.x, hh * 0.5, mid.y), Vector3(len, hh, rw), atan2(-dir.y, dir.x), shade)


# --- Props --------------------------------------------------------------------------------

func _build_props() -> void:
	for pr in layout.props:
		var p: Vector2 = pr.pos
		var c := _chunk_of(p)
		if not chunks.has(c):
			continue
		var yaw := float(pr.get("yaw", 0.0))
		match StringName(pr.kind):
			&"lamp":
				_lamp(c, p)
			&"mailbox":
				var fwd := Vector2(sin(yaw), cos(yaw))
				_box(c, Vector3(p.x, 0.5, p.y), Vector3(0.1, 1.0, 0.1), yaw, Color(0.3, 0.26, 0.2))
				_box(c, Vector3(p.x + fwd.x * 0.05, 1.12, p.y + fwd.y * 0.05), Vector3(0.24, 0.26, 0.48), yaw, Color(0.25, 0.3, 0.45))
				_solid_box(c, Vector3(p.x, 0.6, p.y), Vector3(0.25, 1.2, 0.3), yaw)
			&"trash":
				_box(c, Vector3(p.x, 0.47, p.y), Vector3(0.58, 0.94, 0.58), yaw, Color(0.22, 0.3, 0.24))
				_box(c, Vector3(p.x, 0.97, p.y), Vector3(0.64, 0.06, 0.64), yaw, Color(0.18, 0.22, 0.2))
				_solid_box(c, Vector3(p.x, 0.5, p.y), Vector3(0.6, 1.0, 0.6), yaw)
			&"bench":
				var back := -Vector2(sin(yaw), cos(yaw))
				_box(c, Vector3(p.x, 0.45, p.y), Vector3(1.7, 0.08, 0.45), yaw, Color(0.45, 0.32, 0.2))
				_box(c, Vector3(p.x + back.x * 0.22, 0.72, p.y + back.y * 0.22), Vector3(1.7, 0.4, 0.06), yaw, Color(0.45, 0.32, 0.2))
				for sx in [-0.75, 0.75]:
					var side: Vector2 = Vector2(cos(yaw), -sin(yaw)) * float(sx)
					_box(c, Vector3(p.x + side.x, 0.22, p.y + side.y), Vector3(0.08, 0.44, 0.45), yaw, Color(0.2, 0.2, 0.2))
				_solid_box(c, Vector3(p.x, 0.45, p.y), Vector3(1.7, 0.9, 0.5), yaw)
			&"hay":
				_box(c, Vector3(p.x, 0.4, p.y), Vector3(1.2, 0.8, 0.8), yaw, Color(0.8, 0.7, 0.36))
				_solid_box(c, Vector3(p.x, 0.4, p.y), Vector3(1.2, 0.8, 0.8), yaw)
			&"canopy":
				_canopy(c, pr)
			&"silo":
				_silo(c, p, float(pr.get("radius", 2.2)), float(pr.get("height", 9.0)))
			&"pole":
				_box(c, Vector3(p.x, 4.0, p.y), Vector3(0.24, 8.0, 0.24), yaw, Color(0.36, 0.27, 0.18))
				_box(c, Vector3(p.x, 7.4, p.y), Vector3(1.8, 0.12, 0.12), yaw + PI * 0.5, Color(0.33, 0.25, 0.17))
				_solid_box(c, Vector3(p.x, 1.5, p.y), Vector3(0.3, 3.0, 0.3), yaw)
			&"pump":
				var gp := GasPump.new()
				gp.name = String(pr.get("id", "pump")).replace("/", "_")
				gp.persist_id = String(pr.get("id", ""))
				gp.position = Vector3(p.x, 0.0, p.y)
				gp.rotation.y = yaw
				_sub(c, "Pumps").add_child(gp)


func _lamp(c: Vector2i, p: Vector2) -> void:
	_box(c, Vector3(p.x, 2.3, p.y), Vector3(0.14, 4.6, 0.14), 0.0, Color(0.25, 0.25, 0.27))
	_box(c, Vector3(p.x, 4.55, p.y), Vector3(0.5, 0.14, 0.3), 0.0, Color(0.85, 0.82, 0.7))
	_solid_box(c, Vector3(p.x, 2.3, p.y), Vector3(0.2, 4.6, 0.2), 0.0)
	var l := OmniLight3D.new()
	l.name = "Lamp"
	l.position = Vector3(p.x, 4.3, p.y)
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 1.4
	l.omni_range = 9.0
	l.omni_attenuation = 1.6
	l.shadow_enabled = false
	l.visible = false
	l.add_to_group(&"interior_light")
	l.add_to_group(&"street_lamp")
	_sub(c, "Lamps").add_child(l)


func _canopy(c: Vector2i, pr: Dictionary) -> void:
	var h := 4.6
	var size: Vector2 = pr.size
	var cxf: Transform2D = pr.get("xf", Transform2D(0.0, (pr.pos as Vector2) - size * 0.5))
	var yaw := -cxf.get_rotation()
	var center := cxf * (size * 0.5)
	for lx in [1.2, size.x - 1.2]:
		for ly in [1.2, size.y - 1.2]:
			var q := cxf * Vector2(lx, ly)
			_box(c, Vector3(q.x, h * 0.5, q.y), Vector3(0.3, h, 0.3), yaw, Color(0.85, 0.85, 0.85))
			_solid_box(c, Vector3(q.x, h * 0.5, q.y), Vector3(0.3, h, 0.3), yaw)
	# Roof: an occluder (fades when it hides the player), never solid.
	var roof := StaticBody3D.new()
	roof.name = "CanopyRoof"
	roof.collision_layer = 1 << 5
	roof.collision_mask = 0
	roof.add_to_group(&"occluder")
	roof.position = Vector3(center.x, h + 0.2, center.y)
	roof.rotation.y = yaw
	var visual := Node3D.new()
	visual.name = "Visual"
	roof.add_child(visual)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, 0.4, size.y)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.88, 0.2, 0.16)
	bm.material = m
	mi.mesh = bm
	visual.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	cs.shape = bs
	roof.add_child(cs)
	_sub(c, "Props").add_child(roof)


## Farm silo: a corrugated-grey cylinder with a dome (solid trunk shape).
func _silo(c: Vector2i, p: Vector2, rad: float, height: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Silo"
	var cm := CylinderMesh.new()
	cm.top_radius = rad
	cm.bottom_radius = rad
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 1
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.66, 0.66, 0.64)
	m.metallic = 0.3
	m.roughness = 0.6
	cm.material = m
	mi.mesh = cm
	mi.position = Vector3(p.x, height * 0.5, p.y)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = rad
	sm.height = rad * 1.2
	sm.radial_segments = 16
	sm.rings = 6
	sm.material = m
	dome.mesh = sm
	dome.position = Vector3(0.0, height * 0.5, 0.0)
	mi.add_child(dome)
	_sub(c, "Props").add_child(mi)
	var cyl := CylinderShape3D.new()
	cyl.radius = rad
	cyl.height = height
	_solid_shape(c, cyl, Transform3D(Basis(), Vector3(p.x, height * 0.5, p.y)))


# --- Vehicles -----------------------------------------------------------------------------

func _build_vehicles() -> void:
	for v in layout.vehicles:
		var p: Vector2 = v.pos
		var c := _chunk_of(p)
		if not chunks.has(c):
			continue
		var id := StringName(v.data)
		if not _vehicle_data.has(id):
			_vehicle_data[id] = load(VEHICLE_DIR % id)
		var data := _vehicle_data[id] as VehicleData
		if data == null:
			continue
		var veh := Vehicle.new()
		veh.name = String(v.id)
		veh.data = data
		veh.variant_seed = int(v.seed)
		veh.persist_prefix = "Vehicle/%s" % v.id
		veh.position = Vector3(p.x, 0.0, p.y)
		veh.rotation.y = float(v.yaw)
		_sub(c, "Vehicles").add_child(veh)


# --- Trees --------------------------------------------------------------------------------

func _build_trees() -> void:
	var t := layout.trees
	for i in range(0, t.size(), 4):
		var p := Vector2(t[i], t[i + 1])
		var c := _chunk_of(p)
		if not chunks.has(c):
			continue
		if not _trees.has(c):
			_trees[c] = []
		_trees[c].append([p, t[i + 2], int(t[i + 3])])


var _trunk_mesh: Mesh
var _leaf_mesh: Mesh
var _pine_mesh: Mesh


func _tree_meshes() -> void:
	if _trunk_mesh != null:
		return
	var tm := CylinderMesh.new()
	tm.top_radius = 0.13
	tm.bottom_radius = 0.2
	tm.height = 3.0
	tm.radial_segments = 6
	tm.rings = 1
	_trunk_mesh = tm
	var sm := SphereMesh.new()
	sm.radius = 1.9
	sm.height = 3.2
	sm.radial_segments = 8
	sm.rings = 4
	_leaf_mesh = sm
	var pm := CylinderMesh.new()
	pm.top_radius = 0.0
	pm.bottom_radius = 1.6
	pm.height = 4.6
	pm.radial_segments = 7
	pm.rings = 1
	_pine_mesh = pm


func _flush_trees(c: Vector2i, list: Array) -> void:
	_tree_meshes()
	var r := RandomNumberGenerator.new()
	r.seed = WorldGenerator.sub_seed(world_seed, "treelook:%d,%d" % [c.x, c.y])
	var trunks: Array = []
	var leaves: Array = []
	var pines: Array = []
	var trunk_shapes := {}
	for e in list:
		var p: Vector2 = e[0]
		var s: float = e[1]
		var variant: int = e[2]
		var yaw := r.randf() * TAU
		var trunk_h := 3.0 * s
		trunks.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(p.x, trunk_h * 0.5, p.y)),
			Color(0.33, 0.24, 0.16).lerp(Color(0.4, 0.32, 0.22), r.randf())])
		if variant == 3:
			var ps := s * r.randf_range(0.9, 1.15)
			pines.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(ps, ps, ps)), Vector3(p.x, 2.2 * s + 2.3 * ps, p.y)),
				Color(0.16, 0.3, 0.18).lerp(Color(0.2, 0.36, 0.22), r.randf())])
		else:
			var ls := s * r.randf_range(0.85, 1.15)
			leaves.append([Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(ls, ls * r.randf_range(0.85, 1.1), ls)),
				Vector3(p.x, 2.6 * s + 1.3 * ls, p.y)),
				[Color(0.25, 0.42, 0.18), Color(0.3, 0.46, 0.2), Color(0.22, 0.38, 0.2)][variant % 3].lerp(Color(0.34, 0.48, 0.22), r.randf() * 0.5)])
		# Trunk collision: one cylinder shape owner per tree.
		var key := snappedf(0.22 * s, 0.02)
		if not trunk_shapes.has(key):
			var cyl := CylinderShape3D.new()
			cyl.radius = key
			cyl.height = 3.0
			trunk_shapes[key] = cyl
		_solid_shape(c, trunk_shapes[key], Transform3D(Basis(), Vector3(p.x, 1.5, p.y)))
	_multimesh(c, "TreeTrunks", _trunk_mesh, trunks, box_material)
	_multimesh(c, "TreeCanopies", _leaf_mesh, leaves, canopy_material)
	_multimesh(c, "TreePines", _pine_mesh, pines, canopy_material)


func _multimesh(c: Vector2i, name: String, mesh: Mesh, list: Array, mat: Material) -> void:
	if list.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i][0])
		mm.set_instance_color(i, list[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name
	mmi.multimesh = mm
	mmi.material_override = mat
	chunks[c].add_child(mmi)


# --- Ponds ---------------------------------------------------------------------------------

func _build_ponds() -> void:
	for pd in layout.ponds:
		var p: Vector2 = pd.center
		var c := _chunk_of(p)
		if not chunks.has(c):
			continue
		var rad := float(pd.radius)
		var mi := MeshInstance3D.new()
		mi.name = "Pond"
		var cm := CylinderMesh.new()
		cm.top_radius = rad
		cm.bottom_radius = rad
		cm.height = 0.04
		cm.radial_segments = 24
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.36, 0.5)
		m.roughness = 0.15
		cm.material = m
		mi.mesh = cm
		mi.position = Vector3(p.x, 0.02, p.y)
		chunks[c].add_child(mi)
		# Deep water: a low invisible wall (you cannot wade in; eye-level
		# rays pass over it).
		var cyl := CylinderShape3D.new()
		cyl.radius = rad
		cyl.height = 1.1
		_solid_shape(c, cyl, Transform3D(Basis(), Vector3(p.x, 0.55, p.y)))


# --- Game hookup -----------------------------------------------------------------------------

## New game: the player (and the PlayerStart marker) in the start house.
func _place_player() -> void:
	var map := get_parent()
	if map == null:
		return
	var start := start_position()
	var marker := map.get_node_or_null("PlayerStart") as Node3D
	if marker != null:
		marker.position = start
	var player := map.get_node_or_null("Player") as Node3D
	if player != null:
		player.position = start


## The start population: ZombieSpawner.spawn_points from the layout.
func _configure_spawner() -> void:
	var map := get_parent()
	if map == null:
		return
	var sp := map.get_node_or_null("Zombies") as ZombieSpawner
	if sp == null:
		return
	var pts := PackedVector3Array()
	for q in layout.zombies:
		pts.append(Vector3(q.x, 0.0, q.y))
	sp.spawn_points = pts
	sp.count = pts.size()
	sp.groups = layout.zombie_groups.duplicate(true)
	sp.position = Vector3.ZERO
	sp.min_player_distance = 10.0


## Night light budget: room lights and street lamps only near the player
## (active chunks, ≤ light_far); shadows only on the nearest
## [shadowed_lights] room lights. DayNightLighting calls this when it
## switches the lights; it also runs 4× a second.
func update_lights() -> void:
	if layout == null:
		return
	var dn := get_tree().get_first_node_in_group(&"day_night")
	var on := dn != null and bool(dn.get(&"lights_on"))
	var player := GameManager.player as Node3D
	var pp := start_position()
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		pp = player.global_position
	var pc := layout.chunk_of(Vector2(pp.x, pp.z))
	var rooms: Array = []
	var vis := 0
	var lamps := 0
	var total := 0
	for n in get_tree().get_nodes_in_group(&"interior_light"):
		if not is_ancestor_of(n):
			continue
		var l := n as Light3D
		total += 1
		var gp := l.global_position
		var c := layout.chunk_of(Vector2(gp.x, gp.z))
		var d := Vector2(gp.x - pp.x, gp.z - pp.z).length()
		var show := on and maxi(absi(c.x - pc.x), absi(c.y - pc.y)) <= light_chunk_radius and d <= light_far
		l.visible = show
		l.shadow_enabled = false
		if not show:
			continue
		vis += 1
		if l.is_in_group(&"street_lamp"):
			lamps += 1
		else:
			rooms.append([d, l])
	rooms.sort_custom(func(a, b): return a[0] < b[0])
	var shadowed := mini(shadowed_lights, rooms.size())
	for i in shadowed:
		(rooms[i][1] as Light3D).shadow_enabled = true
	light_stats = {"on": on, "visible": vis, "shadowed": shadowed, "lamps": lamps, "total": total}


## µs spent in update_lights since last reset (perf probes).
var light_usec: int = 0


func _process(delta: float) -> void:
	_light_tick += delta
	if _light_tick >= 0.25 and built:
		_light_tick = 0.0
		var t0 := Time.get_ticks_usec()
		update_lights()
		light_usec += Time.get_ticks_usec() - t0
	if canopy_material == null:
		return
	var player := GameManager.player as Node3D
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	canopy_material.set_shader_parameter(&"fade_center", player.global_position)
	var cam := get_tree().get_first_node_in_group(&"isometric_camera")
	if cam != null and cam.has_method(&"view_direction_flat"):
		var d: Vector3 = cam.call(&"view_direction_flat")
		canopy_material.set_shader_parameter(&"eye_dir", Vector2(d.x, d.z).normalized())
