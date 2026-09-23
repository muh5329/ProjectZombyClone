class_name WorldLayout
extends RefCounted
## The generated world as plain data (Round 11) — WorldGenerator's output,
## WorldBuilder's input. No nodes. World coordinates: metres, x → x and
## Vector2 .y → world z; the world spans [0, size].
##
## Areas are ORIENTED boxes (towns, hamlets and farms sit at any angle):
## `xf` (Transform2D, local → world, rotation only — never a reflection)
## + `size`; the local box is [0, size.x] × [0, size.y]. `rect` is the
## world AABB (broad phase / chunk assignment only).
##
## Records (Dictionaries, JSON-friendly through to_dict()):
##   roads      {id, kind: highway|street|county|dirt, width, sidewalk,
##               points: PackedVector2Array, cap (turning circle radius, opt.)}
##   junctions  PackedVector2Array: vertices shared by two or more roads
##   settlements{id, kind: town|hamlet|farmstead, name, center, xf, size, rect}
##   lots       {id, settlement, xf, size, rect, front_dir, front, use, road}
##              — lot-local x runs along the front edge, y goes AWAY from
##              the road (the road is on the local y < 0 side)
##   buildings  {id, lot, settlement, kind, xf (plan-local → world: the
##               plan's front wall y = size.y faces the road), size, rect,
##               front_dir, front, door, access, access_path}
##   paths      {a, b, width, kind: driveway|path} or {xf, size, kind: apron}
##   parking    {xf, size, rect, lot}
##   fields     {id, xf, size, rect, axis (0: rows along local x), crop, farm}
##   fences     {a, b, kind: wood|hedge|wire}
##   ponds      {center, radius}
##   props      {kind: lamp|mailbox|trash|bench|pump|canopy|hay|silo|pole, pos,
##               yaw, (size / id / radius)}
##   vehicles   {id, data, pos, yaw, seed, length, width}
##   trees      PackedFloat32Array, 4 floats per tree: x, z, scale, variant
##   zombies    PackedVector2Array: the start population
##   zombie_groups [{id, chunk: Vector2i, points: PackedVector2Array}]:
##               rural groups instantiated when their chunk's nav is baked
##   chunk_density PackedFloat32Array: expected zombies per chunk
## Plans (id → BuildingPlan in generated orientation) are in [plans];
## not serialized (regenerated from the seed), covered by plan_hash().

enum Zone { MEADOW, WOODS, FIELD, WATER }
const FRONT_N := 0
const FRONT_E := 1
const FRONT_S := 2
const FRONT_W := 3
const FRONT_DIRS: Array[Vector2] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]

var version: int = 0
var world_seed: int = 0
var params_path: String = ""
var size: Vector2 = Vector2(768, 768)
var chunk_size: float = 64.0
var zone_cell: float = 4.0
var zone_w: int = 0
var zone_h: int = 0
var zones: PackedByteArray = PackedByteArray()

var roads: Array[Dictionary] = []
var junctions: PackedVector2Array = PackedVector2Array()
var settlements: Array[Dictionary] = []
var lots: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var paths: Array[Dictionary] = []
var parking: Array[Dictionary] = []
var fields: Array[Dictionary] = []
var fences: Array[Dictionary] = []
var ponds: Array[Dictionary] = []
var props: Array[Dictionary] = []
var vehicles: Array[Dictionary] = []
var trees: PackedFloat32Array = PackedFloat32Array()
var zombies: PackedVector2Array = PackedVector2Array()
var zombie_groups: Array[Dictionary] = []
var chunk_density: PackedFloat32Array = PackedFloat32Array()
var spawn_building: String = ""
var spawn_point: Vector2 = Vector2.ZERO
var plans: Dictionary = {}
var stats: Dictionary = {}
var _hash: String = ""


static func front_dir(front: int) -> Vector2:
	return FRONT_DIRS[posmod(front, 4)]


## Nearest cardinal FRONT_* of a direction.
static func front_of(dir: Vector2) -> int:
	var best := 0
	var bd := -INF
	for i in 4:
		var d := FRONT_DIRS[i].dot(dir)
		if d > bd:
			bd = d
			best = i
	return best


# --- Oriented boxes ------------------------------------------------------------------------

static func obb_poly(xf: Transform2D, sz: Vector2) -> PackedVector2Array:
	return PackedVector2Array([xf * Vector2.ZERO, xf * Vector2(sz.x, 0), xf * sz, xf * Vector2(0, sz.y)])


static func poly_of(rec: Dictionary) -> PackedVector2Array:
	return obb_poly(rec.xf, rec.size)


static func poly_aabb(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for q in poly:
		r = r.expand(q)
	return r


## [p] inside the box grown by [grow] metres on every side.
static func obb_has_point(xf: Transform2D, sz: Vector2, p: Vector2, grow: float = 0.0) -> bool:
	var l := xf.affine_inverse() * p
	return l.x >= -grow and l.y >= -grow and l.x <= sz.x + grow and l.y <= sz.y + grow


static func rec_has_point(rec: Dictionary, p: Vector2, grow: float = 0.0) -> bool:
	return obb_has_point(rec.xf, rec.size, p, grow)


## Box grown by [g] on every side (same orientation).
static func obb_grown(xf: Transform2D, sz: Vector2, g: float) -> Dictionary:
	return {"xf": xf * Transform2D(0.0, Vector2(-g, -g)), "size": sz + Vector2(g, g) * 2.0}


static func poly_area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## Convex polygons overlap by more than [min_area] m².
static func polys_overlap(a: PackedVector2Array, b: PackedVector2Array, min_area: float = 0.01) -> bool:
	if not poly_aabb(a).intersects(poly_aabb(b)):
		return false
	var total := 0.0
	for piece in Geometry2D.intersect_polygons(a, b):
		total += poly_area(piece)
	return total > min_area


## Distance from segment a-b to a convex polygon (0 when touching / inside).
static func seg_poly_distance(a: Vector2, b: Vector2, poly: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var c := poly[i]
		var d := poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return 0.0
		best = minf(best, Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c))
		var cp := Geometry2D.get_closest_points_between_segments(a, b, c, d)
		best = minf(best, cp[0].distance_to(cp[1]))
	return best


static func polyline_poly_distance(pts: PackedVector2Array, poly: PackedVector2Array) -> float:
	var best := INF
	for i in range(pts.size() - 1):
		best = minf(best, seg_poly_distance(pts[i], pts[i + 1], poly))
	return best


## A vehicle's footprint polygon (yaw: forward = (sin yaw, cos yaw)).
static func vehicle_poly(v: Dictionary, grow: float = 0.0) -> PackedVector2Array:
	var yaw := float(v.yaw)
	var f := Vector2(sin(yaw), cos(yaw))
	var r := Vector2(cos(yaw), -sin(yaw))
	var hl := float(v.get("length", 5.0)) * 0.5 + grow
	var hw := float(v.get("width", 1.9)) * 0.5 + grow
	var c: Vector2 = v.pos
	return PackedVector2Array([c + f * hl + r * hw, c + f * hl - r * hw, c - f * hl - r * hw, c - f * hl + r * hw])


# --- Chunks -----------------------------------------------------------------------------

func chunks_x() -> int:
	return int(ceil(size.x / chunk_size))


func chunks_z() -> int:
	return int(ceil(size.y / chunk_size))


func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / chunk_size)), 0, chunks_x() - 1),
		clampi(int(floor(p.y / chunk_size)), 0, chunks_z() - 1))


func chunk_index(c: Vector2i) -> int:
	return c.y * chunks_x() + c.x


func chunk_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c) * chunk_size, Vector2(chunk_size, chunk_size))


## Chunks within Chebyshev [radius] of [center] (clamped to the world).
func chunks_around(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if x >= 0 and z >= 0 and x < chunks_x() and z < chunks_z():
				out.append(Vector2i(x, z))
	return out


# --- Zones ------------------------------------------------------------------------------

func zone_at(p: Vector2) -> int:
	var x := clampi(int(p.x / zone_cell), 0, zone_w - 1)
	var z := clampi(int(p.y / zone_cell), 0, zone_h - 1)
	return zones[z * zone_w + x]


func zone_ratios() -> Dictionary:
	var counts := {}
	for v in zones:
		counts[v] = int(counts.get(v, 0)) + 1
	var out := {}
	for k in [Zone.MEADOW, Zone.WOODS, Zone.FIELD, Zone.WATER]:
		out[k] = float(counts.get(k, 0)) / maxf(float(zones.size()), 1.0)
	return out


# --- Lookups ----------------------------------------------------------------------------

func building(id: String) -> Dictionary:
	for b in buildings:
		if b.id == id:
			return b
	return {}


func lot(id: String) -> Dictionary:
	for l in lots:
		if l.id == id:
			return l
	return {}


func settlement(id: String) -> Dictionary:
	for s in settlements:
		if s.id == id:
			return s
	return {}


func road(id: String) -> Dictionary:
	for r in roads:
		if r.id == id:
			return r
	return {}


func tree_count() -> int:
	return trees.size() / 4


func buildings_of_kind(kind: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in buildings:
		if StringName(b.kind) == kind:
			out.append(b)
	return out


func buildings_in_chunk(c: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in buildings:
		if chunk_of((b.rect as Rect2).get_center()) == c:
			out.append(b)
	return out


## The building whose footprint contains [p] ({} outdoors).
func building_at(p: Vector2, grow: float = 0.0) -> Dictionary:
	for b in buildings:
		if (b.rect as Rect2).grow(grow + 0.5).has_point(p) and rec_has_point(b, p, grow):
			return b
	return {}


static func distance_to_road(p: Vector2, r: Dictionary) -> float:
	var pts: PackedVector2Array = r.points
	var best := INF
	for i in range(pts.size() - 1):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best


## The road surface under [p] ({} when none): within half its width.
func road_at(p: Vector2, extra: float = 0.0) -> Dictionary:
	for r in roads:
		if distance_to_road(p, r) <= float(r.width) * 0.5 + extra:
			return r
	return {}


# --- Serialization / hash ----------------------------------------------------------------

static func _v(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


static func _jsonable(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2:
			return _v(v)
		TYPE_VECTOR2I:
			return [v.x, v.y]
		TYPE_RECT2:
			return [snappedf(v.position.x, 0.001), snappedf(v.position.y, 0.001), snappedf(v.size.x, 0.001), snappedf(v.size.y, 0.001)]
		TYPE_TRANSFORM2D:
			return [snappedf(v.origin.x, 0.001), snappedf(v.origin.y, 0.001), snappedf(v.get_rotation(), 0.0001)]
		TYPE_FLOAT:
			return snappedf(v, 0.001)
		TYPE_STRING_NAME:
			return String(v)
		TYPE_PACKED_VECTOR2_ARRAY:
			var a: Array = []
			for p in v:
				a.append(_v(p))
			return a
		TYPE_PACKED_FLOAT32_ARRAY:
			var f: Array = []
			for x in v:
				f.append(snappedf(x, 0.001))
			return f
		TYPE_DICTIONARY:
			var d := {}
			var keys: Array = (v as Dictionary).keys()
			keys.sort()
			for k in keys:
				d[String(k)] = _jsonable(v[k])
			return d
		TYPE_ARRAY:
			var arr: Array = []
			for x in v:
				arr.append(_jsonable(x))
			return arr
	return v


func to_dict() -> Dictionary:
	return _jsonable({
		"version": version, "seed": world_seed, "params": params_path, "size": size, "chunk_size": chunk_size,
		"zone_cell": zone_cell, "zones": Marshalls.raw_to_base64(zones),
		"roads": roads, "junctions": junctions, "settlements": settlements, "lots": lots, "buildings": buildings,
		"paths": paths, "parking": parking, "fields": fields, "fences": fences, "ponds": ponds,
		"props": props, "vehicles": vehicles, "trees": trees, "zombies": zombies, "zombie_groups": zombie_groups,
		"chunk_density": chunk_density, "spawn_building": spawn_building, "spawn_point": spawn_point,
	})


func to_json() -> String:
	return JSON.stringify(to_dict(), "", true)


## Hash of the generated content (the generator version is not part of
## it: a new generator version that yields the same world keeps saves).
func layout_hash() -> String:
	if _hash == "":
		var d := to_dict()
		d.erase("version")
		_hash = JSON.stringify(d, "", true).sha256_text()
	return _hash


func plan_hash() -> String:
	var ids: Array = plans.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id in ids:
		var p: BuildingPlan = plans[id]
		parts.append(JSON.stringify(_jsonable({"id": id, "fp": p.footprint, "rooms": p.rooms, "walls": p.walls,
			"furniture": p.furniture, "type": p.building_type}), "", true))
	return "\n".join(parts).sha256_text()
