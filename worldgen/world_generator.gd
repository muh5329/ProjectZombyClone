class_name WorldGenerator
extends RefCounted
## Pure, seeded generator of the starting world (Round 11):
## WorldGenerator.generate(seed, params) -> WorldLayout. No nodes; the
## same (seed, params) always gives an identical layout (hash-tested).
##
## Pipeline: town (a grid of 2×1..4×3 blocks at any angle and position,
## L / T shapes, cul-de-sacs, continuous shop frontage on the main street,
## gas station + warehouse on the highway approaches) → zones (noise +
## a woods mass beside the town) → hamlets (linear or crossroads villages
## placed ON the county roads / highway leaving town) → ponds → roads
## (A* on a cost grid with wiggle waypoints; existing roads are solid so
## roads only meet at junction vertices; a second highway on big maps,
## else a loop road between hamlets) → farmsteads along the rural roads
## (yard + fields around the farmhouse + a dirt drive) → buildings (plans
## from BuildingPlanGenerator, placed in lot frames) → fields along roads
## → fences, props, vehicles → trees → the player start (a random town /
## hamlet / farm house) → zombie density, start population, rural groups.

const VERSION := 2
const DEFAULT_PARAMS := "res://data/worldgen/default_world.tres"
const TOWN_NAMES := ["Ashford", "Millbrook", "Harlow", "Cedar Falls", "Brookfield", "Rosewood", "Fallow Creek",
	"Dunmore", "Westbury", "Riverton", "Oakhaven", "Lowell Springs"]
const HAMLET_NAMES := ["Pine Hollow", "Crossroads", "Elm Corner", "Stony Ford", "Birch Hill", "Mill End",
	"Kettle Run", "Hawk Ridge", "Cold Spring", "Maple Bend"]
const VEHICLE_WEIGHTS := {&"sedan": 34.0, &"station_wagon": 20.0, &"pickup": 22.0, &"van": 14.0,
	&"police_sedan": 4.0, &"fire_pickup": 2.0}
const CROPS := [&"corn", &"wheat", &"cabbage", &"fallow"]
const SHOP_USES: Array[StringName] = [&"convenience_store", &"diner", &"hardware_store", &"pharmacy", &"bar"]
const BLOCK_CELL := 2.0
const BIN := 32.0
const END_OPEN := 9.0

## Last generated layout, reused by WorldBuilder / SaveManager when the
## seed and params match (a load checks the layout hash before swapping).
static var _cache_key: String = ""
static var _cache: WorldLayout

var p: WorldGenParams
var layout: WorldLayout
var rng: RandomNumberGenerator
var _reserves: Array[Dictionary] = []   # {id, poly, aabb}
var _grid: AStarGrid2D
var _gw: int = 0
var _gh: int = 0
var _cell: float = 8.0
var _road_cells: Dictionary = {}
var _bins: Dictionary = {}
var _blocked: PackedByteArray = PackedByteArray()
var _bw: int = 0
var _bh: int = 0
var _woods_noise: FastNoiseLite
var _field_noise: FastNoiseLite
var _road_noise: FastNoiseLite
var _town: Dictionary = {}
var _hamlets: Array[Dictionary] = []
var _lot_seq: Dictionary = {}
var _tree_grid := PackedByteArray()
var _exempt: Array[Vector2] = []
var _debug := OS.get_environment("WORLDGEN_DEBUG") != ""
var _t_last := 0
var _vdims: Dictionary = {}
var _seg_uid: int = 0


static func generate(world_seed: int, params: WorldGenParams = null) -> WorldLayout:
	var prm := params if params != null else default_params()
	var key := "%d|%s|%d" % [world_seed, prm.resource_path if prm.resource_path != "" else str(prm.get_instance_id()), VERSION]
	if key == _cache_key and _cache != null:
		return _cache
	var g := WorldGenerator.new()
	var l := g.run(world_seed, prm)
	if prm.resource_path != "":
		_cache_key = key
		_cache = l
	return l


## Generate without touching the cache (tests measuring time / purity).
static func generate_fresh(world_seed: int, params: WorldGenParams = null) -> WorldLayout:
	return WorldGenerator.new().run(world_seed, params if params != null else default_params())


static func clear_cache() -> void:
	_cache_key = ""
	_cache = null


static func default_params() -> WorldGenParams:
	return load(DEFAULT_PARAMS) as WorldGenParams


## Deterministic sub-seed of [world_seed] for [tag].
static func sub_seed(world_seed: int, tag: String) -> int:
	return int(("%d:%s" % [world_seed, tag]).hash()) & 0x7fffffff


func _rng(tag: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = sub_seed(layout.world_seed, tag)
	return r


func _dbg(what: String) -> void:
	if _debug:
		var now := Time.get_ticks_msec()
		print("worldgen: %s %d ms" % [what, now - _t_last])
		_t_last = now


func run(world_seed: int, params: WorldGenParams) -> WorldLayout:
	var t0 := Time.get_ticks_usec()
	_t_last = Time.get_ticks_msec()
	p = params
	for pr in p.validate():
		push_warning("WorldGenParams: %s (clamped)" % pr)
	layout = WorldLayout.new()
	layout.version = VERSION
	layout.world_seed = world_seed
	layout.params_path = p.resource_path
	layout.size = Vector2(clampf(p.world_size.x, WorldGenParams.MIN_WORLD, WorldGenParams.MAX_WORLD),
		clampf(p.world_size.y, WorldGenParams.MIN_WORLD, WorldGenParams.MAX_WORLD))
	layout.chunk_size = p.chunk_size
	layout.zone_cell = p.zone_cell
	_cell = p.effective_route_cell()
	rng = _rng("main")
	var marks := {}
	_choose_town()
	_zones()
	marks["zones"] = Time.get_ticks_usec()
	_dbg("zones")
	_place_town()
	_dbg("town")
	_plan_hamlets()
	_place_ponds()
	marks["settlements"] = Time.get_ticks_usec()
	_dbg("hamlets+ponds")
	_init_router()
	_route_network()
	_dbg("roads")
	_place_farms()
	_compute_junctions()
	marks["roads"] = Time.get_ticks_usec()
	_dbg("farms")
	_place_buildings()
	_choose_spawn()
	marks["buildings"] = Time.get_ticks_usec()
	_dbg("buildings")
	_build_blocked_raster()
	marks["raster"] = Time.get_ticks_usec()
	_place_fields()
	marks["fields"] = Time.get_ticks_usec()
	_place_fences()
	_place_props()
	marks["props"] = Time.get_ticks_usec()
	_place_vehicles()
	marks["vehicles"] = Time.get_ticks_usec()
	_dbg("fields/fences/props/vehicles")
	_place_trees()
	marks["trees"] = Time.get_ticks_usec()
	_dbg("trees")
	_population()
	marks["population"] = Time.get_ticks_usec()
	_dbg("population")
	var t1 := Time.get_ticks_usec()
	var prev := t0
	for k in marks:
		layout.stats["%s_ms" % k] = (marks[k] - prev) / 1000.0
		prev = marks[k]
	layout.stats["total_ms"] = (t1 - t0) / 1000.0
	layout.stats["buildings"] = layout.buildings.size()
	layout.stats["trees"] = layout.tree_count()
	layout.stats["roads"] = layout.roads.size()
	layout.stats["town_blocks"] = _town.get("blocks_desc", "")
	layout.stats["town_angle_deg"] = rad_to_deg(float(_town.get("theta", 0.0)))
	return layout


# --- Geometry helpers ---------------------------------------------------------------

static func rot90(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)


## A lot / area frame whose front edge runs p0 → p1 (either order) and
## whose local +y points along [away]; [depth] deep.
static func frame_rec(p0: Vector2, p1: Vector2, away: Vector2, depth: float) -> Dictionary:
	var a := p0
	var b := p1
	if rot90((b - a).normalized()).dot(away) < 0.0:
		a = p1
		b = p0
	var e := (b - a).normalized()
	var xf := Transform2D(atan2(e.y, e.x), a)
	var sz := Vector2(a.distance_to(b), depth)
	return {"xf": xf, "size": sz, "rect": WorldLayout.poly_aabb(WorldLayout.obb_poly(xf, sz))}


func _inside_world(poly: PackedVector2Array, margin: float) -> bool:
	for q in poly:
		if q.x < margin or q.y < margin or q.x > layout.size.x - margin or q.y > layout.size.y - margin:
			return false
	return true


func _reserve(id: String, poly: PackedVector2Array) -> void:
	_reserves.append({"id": id, "poly": poly, "aabb": WorldLayout.poly_aabb(poly)})


func _hits_reserve(poly: PackedVector2Array, grow: float = 0.0, ignore: String = "") -> bool:
	var bb := WorldLayout.poly_aabb(poly).grow(grow)
	for r in _reserves:
		if r.id == ignore or not (r.aabb as Rect2).intersects(bb):
			continue
		if grow <= 0.0:
			if WorldLayout.polys_overlap(poly, r.poly, 0.01):
				return true
		else:
			if WorldLayout.polys_overlap(_grow_poly(poly, grow), r.poly, 0.01):
				return true
	return false


## Convex polygon pushed out by [g] (corners follow; fine for boxes).
static func _grow_poly(poly: PackedVector2Array, g: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for q in poly:
		c += q
	c /= poly.size()
	var out := PackedVector2Array()
	for i in poly.size():
		var prv := poly[(i + poly.size() - 1) % poly.size()]
		var cur := poly[i]
		var nxt := poly[(i + 1) % poly.size()]
		var n1 := rot90(cur - prv).normalized()
		var n2 := rot90(nxt - cur).normalized()
		if n1.dot(c - cur) > 0.0:
			n1 = -n1
		if n2.dot(c - cur) > 0.0:
			n2 = -n2
		out.append(cur + (n1 + n2) * g)
	return out


func _in_reserve(pt: Vector2, grow: float = 0.0) -> bool:
	for r in _reserves:
		if not (r.aabb as Rect2).grow(grow + 0.1).has_point(pt):
			continue
		if Geometry2D.is_point_in_polygon(pt, r.poly):
			return true
		if grow > 0.0:
			var poly: PackedVector2Array = r.poly
			for i in poly.size():
				if Geometry2D.get_closest_point_to_segment(pt, poly[i], poly[(i + 1) % poly.size()]).distance_to(pt) < grow:
					return true
	return false


# --- Road index ------------------------------------------------------------------------

func _index_segment(a: Vector2, b: Vector2, rd: Dictionary) -> void:
	var reach := float(rd.width) * 0.5 + float(rd.get("sidewalk", 0.0)) + float(rd.get("cap", 0.0))
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
	for bz in range(int(floor(lo.y / BIN)), int(floor(hi.y / BIN)) + 1):
		for bx in range(int(floor(lo.x / BIN)), int(floor(hi.x / BIN)) + 1):
			var k := Vector2i(bx, bz)
			if not _bins.has(k):
				_bins[k] = []
			_bins[k].append([a, b, rd, _seg_uid])
	_seg_uid += 1


func _index_road(rd: Dictionary) -> void:
	var pts: PackedVector2Array = rd.points
	for i in range(pts.size() - 1):
		_index_segment(pts[i], pts[i + 1], rd)
	if rd.has("cap"):
		_index_segment(pts[pts.size() - 1], pts[pts.size() - 1], rd)


## Road segments whose bins touch [bb].
func _segments_near(bb: Rect2) -> Array:
	var out: Array = []
	var seen := {}
	for bz in range(int(floor(bb.position.y / BIN)), int(floor(bb.end.y / BIN)) + 1):
		for bx in range(int(floor(bb.position.x / BIN)), int(floor(bb.end.x / BIN)) + 1):
			for e in _bins.get(Vector2i(bx, bz), []):
				var id: int = e[3]
				if not seen.has(id):
					seen[id] = true
					out.append(e)
	return out


## Clearance between polygon [poly] and every road surface (incl.
## sidewalks and turning circles) minus [need]: < 0 = too close.
func _road_clearance(poly: PackedVector2Array, extra: float = 0.0) -> float:
	var best := INF
	for e in _segments_near(WorldLayout.poly_aabb(poly).grow(16.0)):
		var rd: Dictionary = e[2]
		var need := float(rd.width) * 0.5 + float(rd.get("sidewalk", 0.0)) + extra
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		if a == b:
			need = float(rd.get("cap", 0.0)) + float(rd.get("sidewalk", 0.0)) + extra
		best = minf(best, WorldLayout.seg_poly_distance(a, b, poly) - need)
	return best


## Distance from [pt] to the nearest road surface edge (< 0 = on a road).
func _road_gap(pt: Vector2) -> float:
	var best := INF
	for e in _segments_near(Rect2(pt, Vector2.ZERO).grow(16.0)):
		var rd: Dictionary = e[2]
		var d := Geometry2D.get_closest_point_to_segment(pt, e[0], e[1]).distance_to(pt)
		var half := float(rd.width) * 0.5 if e[0] != e[1] else float(rd.get("cap", 0.0))
		best = minf(best, d - half)
	return best


# --- Records ----------------------------------------------------------------------------

func _add_road(id: String, kind: StringName, width: float, pts: PackedVector2Array, sidewalk: float = 0.0) -> Dictionary:
	var rec := {"id": id, "kind": kind, "width": width, "sidewalk": sidewalk, "points": pts}
	layout.roads.append(rec)
	_index_road(rec)
	return rec


func _lot_free(poly: PackedVector2Array) -> bool:
	if not _inside_world(poly, 4.0):
		return false
	var bb := WorldLayout.poly_aabb(poly)
	for l in layout.lots:
		if (l.rect as Rect2).intersects(bb) and WorldLayout.polys_overlap(poly, WorldLayout.poly_of(l), 0.05):
			return false
	for pd in layout.ponds:
		var c: Vector2 = pd.center
		if WorldLayout.seg_poly_distance(c, c, poly) < float(pd.radius) + 3.0:
			return false
	return _road_clearance(poly, -0.05) >= 0.0


## A lot along the front edge p0 → p1 extending [depth] along [away];
## added only when free. Returns {} when refused.
func _try_lot(settlement: String, p0: Vector2, p1: Vector2, away: Vector2, depth: float, use: StringName,
		road_id: String, ignore_reserve: String = "") -> Dictionary:
	var rec := frame_rec(p0, p1, away, depth)
	var poly := WorldLayout.obb_poly(rec.xf, rec.size)
	if not _lot_free(poly):
		return {}
	if ignore_reserve != "*" and _hits_reserve(poly, 0.0, ignore_reserve):
		return {}
	var n: int = _lot_seq.get(settlement, 0) + 1
	_lot_seq[settlement] = n
	rec["id"] = "%s_%02d" % [settlement, n]
	rec["settlement"] = settlement
	rec["front_dir"] = -away.normalized()
	rec["front"] = WorldLayout.front_of(-away)
	rec["use"] = use
	rec["road"] = road_id
	layout.lots.append(rec)
	return rec


## Lots along street segment a → b on [side] (+1 = left of a→b), between
## [t0] and [t1] metres along it, [near] m from the centre line.
func _frontage(settlement: String, road_id: String, a: Vector2, b: Vector2, side: float, near: float, depth: float,
		t0: float, t1: float, w_min: float, w_max: float, use: StringName, r: RandomNumberGenerator,
		ignore_reserve: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := (b - a).normalized()
	var n := rot90(e) * side
	var t := t0
	while t1 - t >= w_min - 0.01:
		var w := r.randf_range(w_min, w_max)
		if t1 - (t + w) < w_min:
			w = t1 - t if t1 - t <= w_max + w_min * 0.5 else (t1 - t) * 0.5
		var p0 := a + e * t + n * near
		var p1 := a + e * (t + w) + n * near
		var lot := _try_lot(settlement, p0, p1, n, depth, use, road_id, ignore_reserve)
		if not lot.is_empty():
			out.append(lot)
		t += w
	return out


static func _shuffle(a: Array, r: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


# --- Town ---------------------------------------------------------------------------------

## Town frame, grid and position: candidates anywhere in the middle of the
## map, any angle; the first that fits the world (with its approaches)
## and sits on the most open ground wins.
func _choose_town() -> void:
	var r := _rng("town")
	var sz := layout.size
	var small := minf(sz.x, sz.y) < 600.0
	var noise := FastNoiseLite.new()
	noise.seed = sub_seed(layout.world_seed, "woods")
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = p.woods_frequency
	noise.fractal_octaves = 3
	var best := {}
	var best_score := -INF
	for attempt in 60:
		var nx := r.randi_range(p.town_blocks_min, p.town_blocks_max)
		var ny := r.randi_range(p.town_rows_min, p.town_rows_max)
		if small:
			nx = mini(nx, 2)
			ny = 1
		var rp := 1 if ny == 1 else (1 if ny == 2 else 2)
		var rn := ny - rp
		var theta := r.randf_range(0.0, PI)
		var c := Vector2(r.randf_range(0.22, 0.78) * sz.x, r.randf_range(0.22, 0.78) * sz.y)
		var half_u := nx * p.block_length * 0.5 + (p.town_approach if small else p.town_approach + 40.0)
		var extra := 50.0 if small else 90.0  # outer rows, cul-de-sacs, gas / warehouse lots
		var v_hi := rp * p.block_depth + extra
		var v_lo := -(rn * p.block_depth + extra)
		var xf := Transform2D(theta, c)
		var poly := PackedVector2Array([xf * Vector2(-half_u, v_lo), xf * Vector2(half_u, v_lo), xf * Vector2(half_u, v_hi),
			xf * Vector2(-half_u, v_hi)])
		if not _inside_world(poly, 12.0):
			continue
		var score := 0.0
		for i in 12:
			var q := xf * Vector2(r.randf_range(-half_u, half_u) * 0.6, r.randf_range(v_lo, v_hi) * 0.6)
			score -= 1.0 if noise.get_noise_2dv(q) > p.woods_threshold else 0.0
		score += r.randf() * 2.0
		if score > best_score:
			best_score = score
			best = {"center": c, "theta": theta, "nx": nx, "rp": rp, "rn": rn, "xf": xf, "small": small}
	if best.is_empty():
		# Tiny world fallback: axis-aligned, centred, the smallest town.
		best = {"center": sz * 0.5, "theta": 0.0, "nx": 2, "rp": 1, "rn": 0, "xf": Transform2D(0.0, sz * 0.5), "small": true}
	_town = best
	_town["rng"] = r


func _small() -> bool:
	return minf(layout.size.x, layout.size.y) < 600.0


func _tw(u: float, v: float) -> Vector2:
	return (_town.xf as Transform2D) * Vector2(u, v)


func _place_town() -> void:
	var r: RandomNumberGenerator = _town.rng
	var nx: int = _town.nx
	var rp: int = _town.rp
	var rn: int = _town.rn
	var bl := p.block_length
	var bd := p.block_depth
	var u0 := -nx * bl * 0.5
	var sw := p.sidewalk_width
	var main_w := p.street_width + 1.0
	var m_end := p.street_width * 0.5 + sw
	var name: String = TOWN_NAMES[r.randi_range(0, TOWN_NAMES.size() - 1)]
	var along := (_town.xf as Transform2D).x.normalized()
	var perp := (_town.xf as Transform2D).y.normalized()
	# Blocks (i, k): k in -rn .. rp-1; k = 0 / -1 border the main street.
	var blocks := {}
	for i in nx:
		for k in range(-rn, rp):
			blocks[Vector2i(i, k)] = true
	# L / T shapes: drop end blocks of the rows away from the main street.
	var dropped := 0
	for k in range(-rn, rp):
		if k == 0 or (k == -1 and rn == 1 and rp == 1 and nx <= 2):
			continue
		for i in [0, nx - 1]:
			if nx >= 2 and r.randf() < 0.35 and blocks.size() - 1 >= nx:
				blocks.erase(Vector2i(i, k))
				dropped += 1
	_town["blocks_desc"] = "%dx%d-%d" % [nx, rp + rn, dropped]
	_town["blocks"] = blocks.size()
	var us: Array[float] = []
	for i in nx + 1:
		us.append(u0 + i * bl)
	var has_block := func(i: int, k: int) -> bool: return blocks.has(Vector2i(i, k))
	# --- Streets: horizontal lines v = k*bd, vertical at every u_i.
	var hsegs := {}  # Vector2i(i, k) → true: segment u_i..u_i+1 on line k
	for k in range(-rn, rp + 1):
		for i in nx:
			if has_block.call(i, k) or has_block.call(i, k - 1):
				hsegs[Vector2i(i, k)] = true
	var vsegs := {}  # Vector2i(i, k): u_i, v from k*bd to (k+1)*bd
	for i in nx + 1:
		for k in range(-rn, rp):
			if has_block.call(i - 1, k) or has_block.call(i, k):
				vsegs[Vector2i(i, k)] = true
	var street_of := {}  # segment key → road id
	for k in range(-rn, rp + 1):
		var run: Array[int] = []
		var runs: Array = []
		for i in nx:
			if hsegs.has(Vector2i(i, k)):
				run.append(i)
			elif not run.is_empty():
				runs.append(run)
				run = []
		if not run.is_empty():
			runs.append(run)
		for ri in runs.size():
			var rr: Array = runs[ri]
			var pts := PackedVector2Array()
			for i in range(int(rr[0]), int(rr[-1]) + 2):
				pts.append(_tw(us[i], k * bd))
			var id := "town_main" if k == 0 else "town_h%d_%d" % [k + rn, ri]
			_add_road(id, &"street", main_w if k == 0 else p.street_width, pts, sw)
			for i in rr:
				street_of[Vector2i(i, k)] = id
	var vstreet_of := {}
	for i in nx + 1:
		var run2: Array[int] = []
		var runs2: Array = []
		for k in range(-rn, rp):
			if vsegs.has(Vector2i(i, k)):
				run2.append(k)
			elif not run2.is_empty():
				runs2.append(run2)
				run2 = []
		if not run2.is_empty():
			runs2.append(run2)
		for ri in runs2.size():
			var rr2: Array = runs2[ri]
			var pts2 := PackedVector2Array()
			for k in range(int(rr2[0]), int(rr2[-1]) + 2):
				pts2.append(_tw(us[i], k * bd))
			_add_road("town_v%d_%d" % [i, ri], &"street", p.street_width, pts2, sw)
			for k in rr2:
				vstreet_of[Vector2i(i, k)] = "town_v%d_%d" % [i, ri]
	# --- Approaches (straight, then a bend): planned highway heads.
	var approach: Array = []
	for end in 2:
		var sgn := -1.0 if end == 0 else 1.0
		var start := _tw(us[0] if end == 0 else us[nx], 0.0)
		var pts3 := PackedVector2Array([start])
		var straight := p.town_approach
		pts3.append(start + along * sgn * straight)
		if not _town.small:
			var bend := deg_to_rad(r.randf_range(12.0, 35.0)) * (1.0 if r.randf() < 0.5 else -1.0)
			var dir := (along * sgn).rotated(bend * 0.5)
			pts3.append(pts3[1] + dir * 18.0)
			dir = (along * sgn).rotated(bend)
			pts3.append(pts3[2] + dir * 22.0)
		approach.append(pts3)
		# Indexed now so lots keep off it; becomes part of the highway.
		_index_road({"id": "hw_%d" % end, "kind": &"highway", "width": p.highway_width, "sidewalk": 0.0, "points": pts3})
	_town["approach"] = approach
	# --- County stubs out of the grid (top line and bottom line).
	var stubs: Array = []
	for top in [true, false]:
		var k_line := rp if top else -rn
		var cands: Array[int] = []
		for i in nx + 1:
			var ok: bool = vsegs.has(Vector2i(i, rp - 1)) if top else (vsegs.has(Vector2i(i, -rn)) if rn > 0 else true)
			if ok and i > 0 and i < nx:
				cands.append(i)
		# Else any vertex of the outermost line that has a street (L / T
		# shapes can leave the nominal outer line empty).
		var kl_try := k_line
		while cands.is_empty() and kl_try >= -rn and kl_try <= rp:
			for i in nx + 1:
				if hsegs.has(Vector2i(i - 1, kl_try)) or hsegs.has(Vector2i(i, kl_try)):
					cands.append(i)
			if cands.is_empty():
				kl_try += -1 if top else 1
		k_line = kl_try
		var ci: int = cands[r.randi_range(0, cands.size() - 1)]
		var s0 := _tw(us[ci], k_line * bd)
		var dirv := perp * (1.0 if top else -1.0)
		var s1 := s0 + dirv * 100.0
		for shrink in 10:
			if s1.x > 12.0 and s1.y > 12.0 and s1.x < layout.size.x - 12.0 and s1.y < layout.size.y - 12.0:
				break
			s1 = s0 + dirv * (100.0 - 9.0 * (shrink + 1))
		var stub := {"id": "county_%d" % (0 if top else 1), "kind": &"county", "width": p.county_width, "sidewalk": 0.0,
			"points": PackedVector2Array([s0, s1])}
		_index_road(stub)
		# If the stub starts mid-street (bottom line = main street), that
		# point is already a vertex of the main street polyline.
		stubs.append({"start": s0, "end": s1, "dir": dirv})
	_town["stubs"] = stubs
	# --- Cul-de-sacs off outer streets.
	var culs: Array = []
	var cul_count := r.randi_range(0, p.cul_de_sac_max) if not _town.small else 0
	var outer_h: Array = []
	for key in hsegs:
		var kk: Vector2i = key
		if kk.y == 0:
			continue
		if has_block.call(kk.x, kk.y) != has_block.call(kk.x, kk.y - 1):
			outer_h.append(kk)
	outer_h.sort()
	_shuffle(outer_h, r)
	for ci2 in mini(cul_count, outer_h.size()):
		var kk2: Vector2i = outer_h[ci2]
		var out_sign := 1.0 if has_block.call(kk2.x, kk2.y - 1) else -1.0
		var um := (us[kk2.x] + us[kk2.x + 1]) * 0.5
		var j0 := _tw(um, kk2.y * bd)
		var dirc := perp * out_sign
		var j1 := j0 + dirc * 46.0
		var sid: String = street_of[kk2]
		var srd := layout.road(sid)
		# Insert the junction vertex into the street.
		var spts: PackedVector2Array = srd.points
		for si in range(spts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(j0, spts[si], spts[si + 1]).distance_to(j0) < 0.01:
				spts.insert(si + 1, j0)
				break
		srd.points = spts
		var cul := _add_road("town_cul_%d" % ci2, &"street", 6.0, PackedVector2Array([j0, j1]), 1.5)
		cul["cap"] = 8.0
		_index_segment(j1, j1, cul)
		culs.append({"a": j0, "b": j1, "dir": dirc, "id": cul.id})
	# --- Lots, in priority order.
	var near_main := main_w * 0.5 + sw
	var near_st := p.street_width * 0.5 + sw
	var shop_lots: Array[Dictionary] = []
	var house_lots: Array[Dictionary] = []
	# 1. Continuous shop frontage along the main street, both sides.
	for i in nx:
		var a := _tw(us[i], 0.0)
		var b := _tw(us[i + 1], 0.0)
		var len := a.distance_to(b)
		for side in [1.0, -1.0]:
			# Left of a→b (+1) is the +v side (rot90 of +u is +v).
			shop_lots.append_array(_frontage("town", "town_main", a, b, side, near_main, p.lot_depth,
				m_end, len - m_end, p.shop_lot_width_min, p.shop_lot_width_max, &"shop", r))
	# 2. Block rows along the other streets (inside blocks).
	var outer_rows: Array = []
	for key in hsegs:
		var kk3: Vector2i = key
		if kk3.y == 0:
			continue
		var a2 := _tw(us[kk3.x], kk3.y * bd)
		var b2 := _tw(us[kk3.x + 1], kk3.y * bd)
		var len2 := a2.distance_to(b2)
		for side2 in [1.0, -1.0]:
			var k_block := kk3.y if side2 > 0.0 else kk3.y - 1
			if has_block.call(kk3.x, k_block):
				house_lots.append_array(_frontage("town", street_of[kk3], a2, b2, side2, near_st, p.lot_depth,
					m_end, len2 - m_end, p.house_lot_width_min, p.house_lot_width_max, &"house", r))
			else:
				outer_rows.append([street_of[kk3], a2, b2, side2, len2])
	# 3. Warehouse and gas station on the approaches.
	var wh_end := r.randi_range(0, 1)
	for end in 2:
		var pts4: PackedVector2Array = approach[end]
		var a3 := pts4[0]
		var b3 := pts4[1]
		var side3 := 1.0 if r.randf() < 0.5 else -1.0
		var near_h := p.highway_width * 0.5 + 2.0
		var is_wh := end == wh_end
		var lot_len := 48.0 if is_wh else 40.0
		var depth := 44.0 if is_wh else 34.0
		var got := {}
		for s_try in [side3, -side3]:
			for t_start in [m_end + 10.0, m_end + 4.0]:
				if not got.is_empty():
					break
				if t_start + lot_len > p.town_approach - 4.0:
					continue
				var e3 := (b3 - a3).normalized()
				var n3: Vector2 = rot90(e3) * float(s_try)
				got = _try_lot("town", a3 + e3 * t_start + n3 * near_h, a3 + e3 * (t_start + lot_len) + n3 * near_h,
					n3, depth, &"warehouse" if is_wh else &"gas_station", "hw_%d" % end)
		if not got.is_empty():
			got.id = "town_warehouse" if is_wh else "town_gas"
	# 4. Cul-de-sac lots.
	for cul2 in culs:
		var ca: Vector2 = cul2.a
		var cb: Vector2 = cul2.b
		var clen := ca.distance_to(cb)
		for side4 in [1.0, -1.0]:
			house_lots.append_array(_frontage("town", cul2.id, ca, cb, side4, 3.0 + 1.5, 20.0,
				12.0, clen - 2.0, 14.0, 17.0, &"house", r))
		var dirc2: Vector2 = cul2.dir
		var endc := cb + dirc2 * (8.0 + 1.5)
		var pc := rot90(dirc2)
		var el := _try_lot("town", endc - pc * 8.0, endc + pc * 8.0, dirc2, 20.0, &"house", cul2.id)
		if not el.is_empty():
			house_lots.append(el)
	# 5. Outer rows facing outward (half of the free edges) + along outer
	#    cross streets.
	for key in vsegs:
		var kv: Vector2i = key
		var inner_l: bool = has_block.call(kv.x - 1, kv.y)
		var inner_r: bool = has_block.call(kv.x, kv.y)
		if inner_l == inner_r:
			continue
		var a5 := _tw(us[kv.x], kv.y * bd)
		var b5 := _tw(us[kv.x], (kv.y + 1) * bd)
		# Left of a5→b5 (+v direction) is -u.
		outer_rows.append([vstreet_of[kv], a5, b5, 1.0 if inner_r else -1.0, a5.distance_to(b5), 0.4])
	var optional: Array = []
	for orow in outer_rows:
		optional.append(orow)
	_shuffle(optional, r)
	var deferred: Array = []
	for orow2 in optional:
		var chance := float(orow2[5]) if orow2.size() > 5 else 0.55
		if _town.small:
			chance = 0.0
		if r.randf() < chance:
			house_lots.append_array(_frontage("town", orow2[0], orow2[1], orow2[2], orow2[3], near_st, p.lot_depth,
				m_end, float(orow2[4]) - m_end, p.house_lot_width_min, p.house_lot_width_max, &"house", r))
		else:
			deferred.append(orow2)
	# Too small a town: add the remaining rows until the minimum is met.
	for orow3 in deferred:
		if shop_lots.size() + house_lots.size() >= (12 if _town.small else p.town_lots_min + 2):
			break
		house_lots.append_array(_frontage("town", orow3[0], orow3[1], orow3[2], orow3[3], near_st, p.lot_depth,
			m_end, float(orow3[4]) - m_end, p.house_lot_width_min, p.house_lot_width_max, &"house", r))
	# Lot budget: trim the outermost house lots above the max (all town
	# lots count, incl. the gas station / warehouse).
	var total := 0
	for tl in layout.lots:
		if tl.settlement == "town":
			total += 1
	if total > p.town_lots_max:
		house_lots.sort_custom(func(x, y): return (x.rect as Rect2).get_center().distance_to(_town.center) > (y.rect as Rect2).get_center().distance_to(_town.center))
		var drop := total - p.town_lots_max
		for di in drop:
			layout.lots.erase(house_lots[di])
		house_lots = house_lots.slice(drop)
	# Shop uses: every kind once, church or post office, then repeats; a
	# parking lot; a few older homes.
	var uses: Array[StringName] = SHOP_USES.duplicate()
	uses.append(&"church" if r.randf() < 0.5 else &"post_office")
	var more: Array[StringName] = [&"convenience_store", &"post_office", &"diner", &"parking", &"house", &"bar", &"house"]
	var order: Array[int] = []
	for i in shop_lots.size():
		order.append(i)
	_shuffle(order, r)
	for k2 in order.size():
		var lot2: Dictionary = shop_lots[order[k2]]
		lot2.use = uses[k2] if k2 < uses.size() else more[(k2 - uses.size()) % more.size()]
	for lot3 in house_lots:
		lot3.use = &"house" if r.randf() > 0.05 else &"empty"
	# Reserve: everything the town placed, in its frame (+ 6 m).
	var inv := (_town.xf as Transform2D).affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for l in layout.lots:
		if l.settlement != "town":
			continue
		for q in WorldLayout.poly_of(l):
			var lq := inv * q
			lo = Vector2(minf(lo.x, lq.x), minf(lo.y, lq.y))
			hi = Vector2(maxf(hi.x, lq.x), maxf(hi.y, lq.y))
	for rd in layout.roads:
		if String(rd.id).begins_with("town_"):
			for q2 in rd.points:
				var lq2: Vector2 = inv * (q2 as Vector2)
				lo = Vector2(minf(lo.x, lq2.x - 12.0), minf(lo.y, lq2.y - 12.0))
				hi = Vector2(maxf(hi.x, lq2.x + 12.0), maxf(hi.y, lq2.y + 12.0))
	lo -= Vector2(6, 6)
	hi += Vector2(6, 6)
	var rpoly := PackedVector2Array([_tw(lo.x, lo.y), _tw(hi.x, lo.y), _tw(hi.x, hi.y), _tw(lo.x, hi.y)])
	_reserve("town", rpoly)
	var sxf := (_town.xf as Transform2D) * Transform2D(0.0, lo)
	layout.settlements.append({"id": "town", "kind": &"town", "name": name, "center": _town.center, "xf": sxf,
		"size": hi - lo, "rect": WorldLayout.poly_aabb(rpoly), "angle_deg": rad_to_deg(float(_town.theta)),
		"blocks": _town.blocks_desc})


# --- Zones ------------------------------------------------------------------------------

func _zones() -> void:
	_woods_noise = FastNoiseLite.new()
	_woods_noise.seed = sub_seed(layout.world_seed, "woods")
	_woods_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_woods_noise.frequency = p.woods_frequency
	_woods_noise.fractal_octaves = 3
	_field_noise = FastNoiseLite.new()
	_field_noise.seed = sub_seed(layout.world_seed, "fields")
	_field_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_field_noise.frequency = p.field_frequency
	_field_noise.fractal_octaves = 2
	_road_noise = FastNoiseLite.new()
	_road_noise.seed = sub_seed(layout.world_seed, "roadcost")
	_road_noise.frequency = 0.02
	layout.zone_w = int(ceil(layout.size.x / p.zone_cell))
	layout.zone_h = int(ceil(layout.size.y / p.zone_cell))
	layout.zones.resize(layout.zone_w * layout.zone_h)
	var r := _rng("woodsmass")
	var perp := (_town.xf as Transform2D).y.normalized()
	var side := 1.0 if r.randf() < 0.5 else -1.0
	var rows := float(_town.rp if side > 0.0 else _town.rn)
	var woods_c: Vector2 = (_town.center as Vector2) + perp * side * (rows * p.block_depth + 90.0 + p.town_woods_distance) \
		+ (_town.xf as Transform2D).x.normalized() * r.randf_range(-60.0, 60.0)
	_town["woods_c"] = woods_c
	for z in layout.zone_h:
		for x in layout.zone_w:
			var wp := Vector2((x + 0.5) * p.zone_cell, (z + 0.5) * p.zone_cell)
			var wn := _woods_noise.get_noise_2dv(wp)
			var boost := 1.0 - wp.distance_to(woods_c) / p.town_woods_radius
			if boost > 0.0:
				wn = maxf(wn, p.woods_threshold + 0.35 * boost)
			var zone := WorldLayout.Zone.MEADOW
			if wn > p.woods_threshold:
				zone = WorldLayout.Zone.WOODS
			elif _field_noise.get_noise_2dv(wp) > p.field_threshold:
				zone = WorldLayout.Zone.FIELD
			layout.zones[z * layout.zone_w + x] = zone


func _set_zone_poly(poly: PackedVector2Array, zone: int) -> void:
	var bb := WorldLayout.poly_aabb(poly)
	var x0 := clampi(int(bb.position.x / p.zone_cell), 0, layout.zone_w - 1)
	var x1 := clampi(int(bb.end.x / p.zone_cell), 0, layout.zone_w - 1)
	var z0 := clampi(int(bb.position.y / p.zone_cell), 0, layout.zone_h - 1)
	var z1 := clampi(int(bb.end.y / p.zone_cell), 0, layout.zone_h - 1)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) * p.zone_cell, (z + 0.5) * p.zone_cell), poly):
				layout.zones[z * layout.zone_w + x] = zone


# --- Hamlets ------------------------------------------------------------------------------

## Hamlets sit ON the roads leaving town: county roads first, then the
## highway. Each is a straight village street (linear) or a crossroads
## with a side road; its lots are made now, the road through it later.
func _plan_hamlets() -> void:
	var r := _rng("hamlets")
	var rng_count := p.scaled_range(p.hamlet_count_min, p.hamlet_count_max, 1)
	var count := r.randi_range(rng_count.x, rng_count.y)
	count = mini(count, 3)
	var names := HAMLET_NAMES.duplicate()
	_shuffle(names, r)
	_set_zone_poly(_reserves[0].poly, WorldLayout.Zone.MEADOW)
	var hosts: Array = []
	for st in _town.stubs:
		hosts.append({"road": "county_%d" % hosts.size(), "start": st.end, "dir": st.dir})
	var appr: Array = _town.approach
	var ahead := r.randi_range(0, 1)
	var apts: PackedVector2Array = appr[ahead]
	hosts.append({"road": "hw_%d" % ahead, "start": apts[apts.size() - 1],
		"dir": (apts[apts.size() - 1] - apts[apts.size() - 2]).normalized()})
	var made := 0
	for host in hosts:
		if made >= count:
			break
		var h := _try_hamlet(host, "hamlet%d" % (made + 1), names[made % names.size()], r)
		if not h.is_empty():
			_hamlets.append(h)
			made += 1
	# Never zero hamlets: retry every host with small villages, then a
	# standalone hamlet with its own link road (routed later).
	if made == 0:
		for host2 in hosts:
			var h2 := _try_hamlet(host2, "hamlet1", names[0], r, 4)
			if not h2.is_empty():
				_hamlets.append(h2)
				made = 1
				break
	if made == 0:
		var h3 := _try_hamlet({"standalone": true, "road": "hamlet1_link"}, "hamlet1", names[0], r, 6)
		if not h3.is_empty():
			_hamlets.append(h3)
		else:
			_rej("standalone_failed")


func _edge_target(from: Vector2, dir: Vector2, r: RandomNumberGenerator) -> Vector2:
	var sz := layout.size
	var t := INF
	if dir.x > 0.001:
		t = minf(t, (sz.x - from.x) / dir.x)
	elif dir.x < -0.001:
		t = minf(t, -from.x / dir.x)
	if dir.y > 0.001:
		t = minf(t, (sz.y - from.y) / dir.y)
	elif dir.y < -0.001:
		t = minf(t, -from.y / dir.y)
	if t == INF:
		t = 0.0
	var q := from + dir * t
	q = Vector2(clampf(q.x, 0.0, sz.x), clampf(q.y, 0.0, sz.y))
	if q.x <= 0.01 or q.x >= sz.x - 0.01:
		q.y = clampf(q.y + r.randf_range(-0.12, 0.12) * sz.y, 30.0, sz.y - 30.0)
	else:
		q.x = clampf(q.x + r.randf_range(-0.12, 0.12) * sz.x, 30.0, sz.x - 30.0)
	return q


func _try_hamlet(host: Dictionary, sid: String, hname: String, r: RandomNumberGenerator, max_houses: int = -1) -> Dictionary:
	var standalone := bool(host.get("standalone", false))
	var start: Vector2 = host.get("start", Vector2.ZERO)
	var dir: Vector2 = host.get("dir", Vector2.RIGHT)
	var target := start
	if not standalone:
		target = _edge_target(start, dir, r)
		host["target"] = target
		if start.distance_to(target) < 110.0:
			return {}
	for attempt in (200 if standalone else 30):
		var houses := r.randi_range(p.hamlet_houses_min, mini(p.hamlet_houses_max, 6) if _small() else p.hamlet_houses_max)
		if max_houses > 0:
			houses = mini(houses, max_houses)
		var crossroads := r.randf() < p.hamlet_crossroads_chance and houses >= 4
		var main_houses := houses if not crossroads else int(ceil(houses * 0.6))
		var per_side := int(ceil(main_houses / 2.0))
		var length := per_side * 17.0 + 14.0 + (16.0 if crossroads else 0.0)
		var anchor: Vector2
		var sdir: Vector2
		if standalone:
			anchor = Vector2(r.randf_range(60.0, layout.size.x - 60.0), r.randf_range(60.0, layout.size.y - 60.0))
			sdir = Vector2.RIGHT.rotated(r.randf_range(0.0, PI))
		else:
			var t := r.randf_range(0.3, 0.7)
			anchor = start.lerp(target, t) + rot90((target - start).normalized()) * r.randf_range(-50.0, 50.0)
			sdir = (target - start).normalized().rotated(deg_to_rad(r.randf_range(-20.0, 20.0)))
		var half := length * 0.5
		var depth := p.lot_depth + 1.5
		var side_len := 0.0
		if crossroads:
			side_len = r.randf_range(36.0, 52.0)
		var span_v := maxf(depth + 6.0, side_len + 4.0)
		var xf := Transform2D(atan2(sdir.y, sdir.x), anchor)
		var poly := PackedVector2Array([xf * Vector2(-half - 1.0, -span_v), xf * Vector2(half + 1.0, -span_v),
			xf * Vector2(half + 1.0, span_v), xf * Vector2(-half - 1.0, span_v)])
		var relax := standalone and attempt >= 100
		if not _inside_world(poly, (8.0 if relax else 15.0) if _small() else 30.0) \
				or _hits_reserve(poly, (6.0 if relax else 15.0) if _small() else (20.0 if relax else 40.0)):
			continue
		var near_fixed := false
		for st in _town.stubs:
			if WorldLayout.seg_poly_distance(st.start, st.end, poly) < 14.0:
				near_fixed = true
		for ap in _town.approach:
			if WorldLayout.polyline_poly_distance(ap, poly) < 14.0:
				near_fixed = true
		if near_fixed and standalone:
			continue
		if not relax and anchor.distance_to(_town.center) < minf(200.0, 0.25 * minf(layout.size.x, layout.size.y)):
			continue
		if standalone and _water_at(anchor):
			continue
		# Streets: [exit_a, A, (mid), B, exit_b] along sdir.
		var a := anchor - sdir * half
		var b := anchor + sdir * half
		var street := PackedVector2Array([a, anchor, b])
		_reserve(sid, poly)
		_set_zone_poly(poly, WorldLayout.Zone.MEADOW)
		var road_id: String = host.road
		var sw := 6.0
		var planned := {"id": road_id, "kind": &"county", "width": sw, "sidewalk": 0.0, "points": street}
		_index_road(planned)
		var side_rd := {}
		if crossroads:
			var pp := rot90(sdir)
			side_rd = _add_road("%s_side" % sid, &"street", 5.5, PackedVector2Array([anchor - pp * side_len, anchor, anchor + pp * side_len]))
		var lots: Array[Dictionary] = []
		var near := sw * 0.5 + 1.5
		var gap := 7.0 if crossroads else 0.0
		for s in [1.0, -1.0]:
			lots.append_array(_frontage(sid, road_id, a, anchor, s, near, p.lot_depth, 4.0, half - gap, 15.0, 19.0, &"house", r, sid))
			lots.append_array(_frontage(sid, road_id, anchor, b, s, near, p.lot_depth, gap, half - 4.0, 15.0, 19.0, &"house", r, sid))
		if crossroads:
			var sp: PackedVector2Array = side_rd.points
			for s2 in [1.0, -1.0]:
				lots.append_array(_frontage(sid, side_rd.id, sp[1], sp[0], s2, 5.5 * 0.5 + 1.5, p.lot_depth, 9.0, side_len - 2.0,
					15.0, 18.0, &"house", r, sid))
				lots.append_array(_frontage(sid, side_rd.id, sp[1], sp[2], s2, 5.5 * 0.5 + 1.5, p.lot_depth, 9.0, side_len - 2.0,
					15.0, 18.0, &"house", r, sid))
		var n := 0
		for l in lots:
			n += 1
			l.use = &"house" if n <= houses else &"empty"
		if lots.size() >= 7 and r.randf() < 0.6:
			lots[r.randi_range(0, lots.size() - 1)].use = &"convenience_store"
		if lots.size() < mini(2, houses):
			_drop_settlement(sid)
			continue
		layout.settlements.append({"id": sid, "kind": &"hamlet", "name": hname, "center": anchor, "xf": xf * Transform2D(0.0, Vector2(-half - 1.0, -span_v)),
			"size": Vector2(length + 2.0, span_v * 2.0), "rect": WorldLayout.poly_aabb(poly),
			"layout": "crossroads" if crossroads else "linear", "road": road_id})
		return {"id": sid, "road": road_id, "street": street, "exit_a": a - sdir * 7.0, "exit_b": b + sdir * 7.0,
			"host": host, "side": side_rd, "standalone": standalone}
	return {}


# --- Ponds ------------------------------------------------------------------------------------

func _place_ponds() -> void:
	var r := _rng("ponds")
	var count := r.randi_range(p.pond_count_min, p.pond_count_max)
	count = int(round(count * sqrt(p.area_scale())))
	var made := 0
	for attempt in 200:
		if made >= count:
			break
		var c := Vector2(r.randf_range(60.0, layout.size.x - 60.0), r.randf_range(60.0, layout.size.y - 60.0)).round()
		var rad := r.randf_range(p.pond_radius_min, p.pond_radius_max)
		if _in_reserve(c, rad + 25.0):
			continue
		var clash := false
		for q in layout.ponds:
			if (q.center as Vector2).distance_to(c) < float(q.radius) + rad + 60.0:
				clash = true
		for st in _town.stubs:
			if Geometry2D.get_closest_point_to_segment(c, st.start, st.end).distance_to(c) < rad + 14.0:
				clash = true
		for ap in _town.approach:
			if WorldLayout.polyline_poly_distance(ap, PackedVector2Array([c])) < rad + 14.0:
				clash = true
		for hm in _hamlets:
			var hs: PackedVector2Array = hm.street
			if WorldLayout.polyline_poly_distance(hs, PackedVector2Array([c])) < rad + 30.0:
				clash = true
		if clash or _road_gap(c) < rad + 12.0:
			continue
		layout.ponds.append({"center": c, "radius": rad})
		made += 1
		var cells := int(ceil(rad / p.zone_cell)) + 1
		var cx := int(c.x / p.zone_cell)
		var cz := int(c.y / p.zone_cell)
		for z in range(cz - cells, cz + cells + 1):
			for x in range(cx - cells, cx + cells + 1):
				if x < 0 or z < 0 or x >= layout.zone_w or z >= layout.zone_h:
					continue
				var wp := Vector2((x + 0.5) * p.zone_cell, (z + 0.5) * p.zone_cell)
				if wp.distance_to(c) <= rad:
					layout.zones[z * layout.zone_w + x] = WorldLayout.Zone.WATER


# --- Road routing -----------------------------------------------------------------------------

func _init_router() -> void:
	_gw = int(ceil(layout.size.x / _cell))
	_gh = int(ceil(layout.size.y / _cell))
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0, 0, _gw, _gh)
	_grid.cell_size = Vector2(_cell, _cell)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	_grid.update()
	for z in _gh:
		for x in _gw:
			var wp := _cell_center(Vector2i(x, z))
			var zone := layout.zone_at(wp)
			var w := 1.0 + 1.2 * (_road_noise.get_noise_2dv(wp) + 1.0) * 0.5
			if zone == WorldLayout.Zone.WOODS:
				w += 1.6
			elif zone == WorldLayout.Zone.FIELD:
				w += 0.3
			_grid.set_point_weight_scale(Vector2i(x, z), w)
			if _water_at(wp) or _in_reserve(wp, 5.0):
				_grid.set_point_solid(Vector2i(x, z), true)
	for rd in layout.roads:
		_mark_road_cells(rd)


func _cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * _cell


func _cell_of(w: Vector2) -> Vector2i:
	return Vector2i(clampi(int(w.x / _cell), 0, _gw - 1), clampi(int(w.y / _cell), 0, _gh - 1))


func _water_at(wp: Vector2) -> bool:
	for q in layout.ponds:
		if wp.distance_to(q.center) < float(q.radius) + 6.0:
			return true
	return false


## Roads may not pass here: water (+ bank), settlement reserves (+ margin).
## Points within END_OPEN of the route being built's own ends are exempt
## from the reserves.
func _solid_at(wp: Vector2, margin: float = 5.0) -> bool:
	if _water_at(wp):
		return true
	for e in _exempt:
		if wp.distance_to(e) < END_OPEN:
			return false
	return _in_reserve(wp, margin)


## Cells a road occupies become solid for later routes (they may only
## meet it at their opened ends = a junction).
func _mark_road_cells(rd: Dictionary) -> void:
	var pts: PackedVector2Array = rd.points
	var reach := float(rd.width) * 0.5 + 5.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var lo := _cell_of(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach))
		var hi := _cell_of(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach))
		for z in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c := Vector2i(x, z)
				var cc := _cell_center(c)
				if Geometry2D.get_closest_point_to_segment(cc, a, b).distance_to(cc) <= reach:
					if not _grid.is_point_solid(c):
						_road_cells[c] = true
						_grid.set_point_solid(c, true)


func _near_road(pt: Vector2, clearance: float) -> bool:
	for e in _exempt:
		if pt.distance_to(e) < END_OPEN:
			return false
	return _road_gap(pt) < clearance


## A* from [a] to [b] with wiggle waypoints; roads solid unless
## [allow_cross]. Returns the simplified, smoothed polyline a → b, or []
## when there is no way.
func _route(a: Vector2, b: Vector2, allow_cross: bool = false, wiggle: bool = true) -> PackedVector2Array:
	var way: Array[Vector2] = [a]
	var d := a.distance_to(b)
	if wiggle and d > 120.0:
		var r := _rng("wiggle:%d,%d" % [int(a.x), int(a.y)])
		var n := clampi(int(d / 130.0), 1, 5)
		var e := (b - a) / d
		var pp := rot90(e)
		var spacing := d / (n + 1)
		var sgn := 1.0 if r.randf() < 0.5 else -1.0
		for i in n:
			var base := a + e * spacing * (i + 1)
			var off := sgn * r.randf_range(0.6, 1.0) * p.road_wiggle * spacing
			sgn = -sgn
			for tries in 3:
				var w := base + pp * off
				if w.x > 20.0 and w.y > 20.0 and w.x < layout.size.x - 20.0 and w.y < layout.size.y - 20.0 \
						and not _grid.is_point_solid(_cell_of(w)):
					way.append(w)
					break
				off *= 0.5
	way.append(b)
	var out := PackedVector2Array([a])
	for i in range(way.size() - 1):
		var seg := _astar(way[i], way[i + 1], allow_cross, a, b)
		if seg.is_empty():
			if i > 0 or way.size() > 2:
				# Retry straight to the goal without the remaining waypoints.
				var rest := _astar(way[i], b, allow_cross, a, b)
				if rest.is_empty():
					return PackedVector2Array()
				rest.remove_at(0)
				out.append_array(rest)
				break
			return PackedVector2Array()
		seg.remove_at(0)
		out.append_array(seg)
	_exempt = [a, b]
	out = _simplify(out, 9.0, allow_cross)
	var smooth := _chaikin(out, 2)
	if _path_clear(smooth, allow_cross):
		out = smooth
	_exempt = []
	return out


func _astar(x: Vector2, y: Vector2, allow_cross: bool, ra: Vector2, rb: Vector2) -> PackedVector2Array:
	var cx := _cell_of(x)
	var cy := _cell_of(y)
	var opened: Array[Vector2i] = []
	for c in [cx, cy]:
		var anchor: Vector2 = x if c == cx else y
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var q: Vector2i = c + Vector2i(dx, dz)
				if not _grid.is_in_boundsv(q) or not _grid.is_point_solid(q):
					continue
				var wp := _cell_center(q)
				if (dx != 0 or dz != 0) and (_water_at(wp) or wp.distance_to(anchor) > END_OPEN + 2.0):
					continue
				_grid.set_point_solid(q, false)
				opened.append(q)
	var relaxed: Array[Vector2i] = []
	var old_w: Array[float] = []
	if allow_cross:
		for c2 in _road_cells:
			if _grid.is_point_solid(c2):
				_grid.set_point_solid(c2, false)
				relaxed.append(c2)
				old_w.append(_grid.get_point_weight_scale(c2))
				_grid.set_point_weight_scale(c2, 12.0)
	var ids := _grid.get_id_path(cx, cy)
	for q in opened:
		_grid.set_point_solid(q, true)
	for qi in relaxed.size():
		_grid.set_point_solid(relaxed[qi], true)
		_grid.set_point_weight_scale(relaxed[qi], old_w[qi])
	if ids.is_empty():
		return PackedVector2Array()
	var pts := PackedVector2Array([x])
	for i in range(1, ids.size() - 1):
		pts.append(_cell_center(ids[i]))
	pts.append(y)
	return pts


func _segment_clear(a: Vector2, b: Vector2, allow_cross: bool = false) -> bool:
	var n := int(ceil(a.distance_to(b) / 2.5)) + 1
	for i in range(1, n):
		var q := a.lerp(b, float(i) / float(n))
		if _solid_at(q, 1.0):
			return false
		if not allow_cross and _near_road(q, 3.0):
			return false
	return true


func _path_clear(pts: PackedVector2Array, allow_cross: bool = false) -> bool:
	for i in range(pts.size() - 1):
		if not _segment_clear(pts[i], pts[i + 1], allow_cross):
			return false
	return true


## Ramer–Douglas–Peucker that never keeps a shortcut over solid ground.
func _simplify(pts: PackedVector2Array, tol: float, allow_cross: bool = false) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var worst := -1.0
	var wi := -1
	for i in range(1, pts.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(pts[i], a, b).distance_to(pts[i])
		if d > worst:
			worst = d
			wi = i
	if worst <= tol and _segment_clear(a, b, allow_cross):
		return PackedVector2Array([a, b])
	if wi < 0:
		wi = pts.size() / 2
	var left := _simplify(pts.slice(0, wi + 1), tol, allow_cross)
	var right := _simplify(pts.slice(wi), tol, allow_cross)
	left.remove_at(left.size() - 1)
	left.append_array(right)
	return left


static func _chaikin(pts: PackedVector2Array, iterations: int) -> PackedVector2Array:
	var cur := pts
	for it in iterations:
		if cur.size() < 3:
			return cur
		var out := PackedVector2Array([cur[0]])
		for i in range(cur.size() - 1):
			var a := cur[i]
			var b := cur[i + 1]
			if i > 0:
				out.append(a.lerp(b, 0.25))
			if i < cur.size() - 2:
				out.append(a.lerp(b, 0.75))
		out.append(cur[cur.size() - 1])
		cur = out
	return cur


## Insert [pt] into road [rd] (a junction vertex); snaps to a vertex
## within 3 m. Returns the vertex used.
func _insert_junction(rd: Dictionary, pt: Vector2) -> Vector2:
	var pts: PackedVector2Array = rd.points
	var best := -1
	var bd := INF
	for i in range(pts.size() - 1):
		var d := Geometry2D.get_closest_point_to_segment(pt, pts[i], pts[i + 1]).distance_to(pt)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return pt
	for i in [best, best + 1]:
		if pts[i].distance_to(pt) < 3.0:
			return pts[i]
	var q := Geometry2D.get_closest_point_to_segment(pt, pts[best], pts[best + 1])
	pts.insert(best + 1, q)
	rd.points = pts
	return q


## Nearest point of a rural through-road (highway / county) outside all
## reserves: {point, road} or {}.
func _nearest_network_point(from: Vector2, kinds: Array) -> Dictionary:
	var best := {}
	var bd := INF
	for rd in layout.roads:
		if not kinds.has(rd.kind):
			continue
		var pts: PackedVector2Array = rd.points
		for i in range(pts.size() - 1):
			var seg_len := pts[i].distance_to(pts[i + 1])
			var steps := maxi(1, int(seg_len / 4.0))
			for k in steps + 1:
				var q := pts[i].lerp(pts[i + 1], float(k) / steps)
				var d := q.distance_to(from)
				if d < bd and not _in_reserve(q, 12.0):
					bd = d
					best = {"point": q, "road": rd}
	return best


## Road [rd] crossing any other road without a shared vertex gets one (X
## / T junction inserted in both polylines).
func _split_crossings(rd: Dictionary) -> void:
	var guard := 0
	var changed := true
	while changed and guard < 64:
		changed = false
		guard += 1
		var pts: PackedVector2Array = rd.points
		for i in range(pts.size() - 1):
			for o in layout.roads:
				if o == rd:
					continue
				var op: PackedVector2Array = o.points
				for j in range(op.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(pts[i], pts[i + 1], op[j], op[j + 1])
					if hit == null:
						continue
					var h: Vector2 = hit
					var shared := false
					for q in [pts[i], pts[i + 1]]:
						for q2 in [op[j], op[j + 1]]:
							if q.distance_to(q2) < 0.01 and q.distance_to(h) < 0.5:
								shared = true
					if shared:
						continue
					if h.distance_to(pts[i]) > 0.01 and h.distance_to(pts[i + 1]) > 0.01:
						pts.insert(i + 1, h)
						rd.points = pts
					if h.distance_to(op[j]) > 0.01 and h.distance_to(op[j + 1]) > 0.01:
						op.insert(j + 1, h)
						o.points = op
					changed = true
					break
				if changed:
					break
			if changed:
				break


## A through road: fixed [head] points, then (optionally) through a
## hamlet's street, then routed to the edge [target]. {} when impossible.
func _through_road(id: String, kind: StringName, width: float, head: PackedVector2Array, hamlet: Dictionary,
		target: Vector2, r: RandomNumberGenerator) -> Dictionary:
	var pts := head.duplicate()
	var cur := pts[pts.size() - 1]
	if not hamlet.is_empty():
		var r1 := _route(cur, hamlet.exit_a)
		if r1.is_empty():
			return {"failed_hamlet": true}
		r1.remove_at(0)
		pts.append_array(r1)
		var st: PackedVector2Array = hamlet.street
		pts.append_array(st)
		pts.append(hamlet.exit_b)
		cur = hamlet.exit_b
	var r2 := PackedVector2Array()
	for tries in 8:
		var tgt := _free_edge_point(target) if tries == 0 else _free_edge_point(_edge_target(cur, (target - cur).normalized().rotated(r.randf_range(-0.8, 0.8)), r))
		r2 = _route(cur, tgt)
		if not r2.is_empty():
			break
	if r2.is_empty():
		return {}
	r2.remove_at(0)
	pts.append_array(r2)
	var rec := _add_road(id, kind, width, pts)
	_mark_road_cells(rec)
	return rec


## [t] (on the map edge) slid along the edge until clear of settlements.
func _free_edge_point(t: Vector2) -> Vector2:
	var sz := layout.size
	var along := Vector2(0, 1) if t.x <= 0.01 or t.x >= sz.x - 0.01 else Vector2(1, 0)
	for k in 60:
		for sgn in [1.0, -1.0]:
			var q: Vector2 = t + along * sgn * 8.0 * k
			if along.x > 0.0 and (q.x < 30.0 or q.x > sz.x - 30.0):
				continue
			if along.y > 0.0 and (q.y < 30.0 or q.y > sz.y - 30.0):
				continue
			if not _solid_at(q, 30.0) and not _grid.is_point_solid(_cell_of(q)):
				return q
	return t


func _route_network() -> void:
	var r := _rng("roads")
	var appr: Array = _town.approach
	var stubs: Array = _town.stubs
	var hamlet_on := {}
	for h in _hamlets:
		hamlet_on[h.road] = h
	var dropped: Array[String] = []
	# Highway: both approaches out to the map edges (maybe through a hamlet).
	for k in 2:
		var apts: PackedVector2Array = appr[k]
		var dir := (apts[apts.size() - 1] - apts[apts.size() - 2]).normalized()
		var target := _edge_target(apts[apts.size() - 1], dir, r)
		var hid := "hw_%d" % k
		var h: Dictionary = hamlet_on.get(hid, {})
		if not h.is_empty():
			target = h.host.target
		var rec := _through_road(hid, &"highway", p.highway_width, apts, h, target, r)
		if rec.get("failed_hamlet", false):
			dropped.append(h.id)
			rec = _through_road(hid, &"highway", p.highway_width, apts, {}, target, r)
		if rec.is_empty() or rec.has("failed_hamlet"):
			# Keep the approach as a dead-end arm (the gas station / warehouse
			# still front it); recorded in the stats.
			layout.stats["highway_%d_truncated" % k] = true
			rec = _add_road(hid, &"highway", p.highway_width, apts)
			_mark_road_cells(rec)
		var pts: PackedVector2Array = rec.points
		pts.reverse()
		rec.points = pts
	# County roads from the town stubs (maybe through a hamlet).
	for k in stubs.size():
		var st: Dictionary = stubs[k]
		var cid := "county_%d" % k
		var h2: Dictionary = hamlet_on.get(cid, {})
		var target2 := _edge_target(st.end, st.dir, r)
		if not h2.is_empty():
			target2 = h2.host.target
		var rec2 := _through_road(cid, &"county", p.county_width, PackedVector2Array([st.start, st.end]), h2, target2, r)
		if rec2.get("failed_hamlet", false):
			dropped.append(h2.id)
			rec2 = _through_road(cid, &"county", p.county_width, PackedVector2Array([st.start, st.end]), {}, target2, r)
		if rec2.is_empty() or rec2.has("failed_hamlet"):
			# A dead-end stub is fine; keep it as a short road.
			var stub_rec := _add_road(cid, &"county", p.county_width, PackedVector2Array([st.start, st.end]))
			_mark_road_cells(stub_rec)
	for hid2 in dropped:
		_drop_settlement(hid2)
	# Crossroads side roads: already records; their cells become solid.
	for h3 in _hamlets:
		if not (h3.side as Dictionary).is_empty() and not dropped.has(h3.id):
			_mark_road_cells(h3.side)
	for h5 in _hamlets.duplicate():
		if not bool(h5.get("standalone", false)):
			continue
		var linked := false
		for ex in [h5.exit_a, h5.exit_b]:
			var np := _nearest_network_point(ex, [&"highway", &"county"])
			if np.is_empty():
				continue
			var j := _insert_junction(np.road, np.point)
			var route3 := _route(j, ex)
			if route3.is_empty() or _runs_along(route3, p.county_width):
				continue
			var st3: PackedVector2Array = h5.street
			if ex == h5.exit_b:
				st3 = st3.duplicate()
				st3.reverse()
			route3.append_array(st3)
			route3.append(h5.exit_b if ex == h5.exit_a else h5.exit_a)
			var rec5 := _add_road(String(h5.road), &"county", p.county_width - 0.5, route3)
			_mark_road_cells(rec5)
			_split_crossings(rec5)
			linked = true
			break
		if not linked:
			_rej("standalone_unlinked")
			dropped.append(h5.id)
			_drop_settlement(h5.id)
	# Big maps: a second highway crossing the map (X junctions allowed);
	# otherwise a loop road between two hamlets. Lanes come after.
	var alive: Array[Dictionary] = []
	for h4 in _hamlets:
		if not dropped.has(h4.id):
			alive.append(h4)
	if minf(layout.size.x, layout.size.y) >= p.second_highway_min_size:
		var perp := (_town.xf as Transform2D).y.normalized()
		var c: Vector2 = _town.center
		for tries in 4:
			var off := (_town.xf as Transform2D).x.normalized() * r.randf_range(0.2, 0.38) * layout.size.x * (1.0 if r.randf() < 0.5 else -1.0)
			var e1 := _free_edge_point(_edge_target(c + off, -perp, r))
			var e2 := _free_edge_point(_edge_target(c + off, perp, r))
			var route := _route(e1, e2, true)
			if route.is_empty() or _runs_along_crossing(route, p.highway_width):
				continue
			var rec3 := _add_road("hw_2", &"highway", p.highway_width, route)
			_split_crossings(rec3)
			_rebuild_index()
			var joined := false
			for v in rec3.points:
				for o in layout.roads:
					if o != rec3 and WorldLayoutValidator._is_vertex(o.points, v, 0.01):
						joined = true
			if not joined:
				layout.roads.erase(rec3)
				_rebuild_index()
				continue
			_mark_road_cells(rec3)
			break
	elif alive.size() >= 2 and r.randf() < 0.8:
		var pairs: Array = []
		for ia in alive.size():
			for ib in range(ia + 1, alive.size()):
				pairs.append([alive[ia], alive[ib]])
		for pair in pairs:
			if _loop_between(pair[0], pair[1]):
				break
	_country_lanes(r)


## A county loop road joining the far sides of two hamlets' roads; it may
## cross other roads (shared junction vertices), never run along one.
func _loop_between(ha: Dictionary, hb: Dictionary) -> bool:
	var ra := layout.road(String(ha.road))
	var rb := layout.road(String(hb.road))
	if ra.is_empty() or rb.is_empty() or ra == rb:
		return false
	var pa := _point_beyond(ra, ha.exit_b, 45.0)
	if pa == Vector2.INF:
		pa = _point_beyond(ra, ha.exit_b, 25.0)
	var pb := _point_beyond(rb, hb.exit_b, 45.0)
	if pb == Vector2.INF:
		pb = _point_beyond(rb, hb.exit_b, 25.0)
	if pa == Vector2.INF or pb == Vector2.INF or pa.distance_to(pb) < 60.0:
		_rej("loop_beyond")
		return false
	for cross in [false, true]:
		var route := _route(pa, pb, cross)
		if route.is_empty():
			continue
		if (not cross and _runs_along(route, p.county_width - 0.5)) or (cross and _runs_along_crossing(route, p.county_width - 0.5)):
			_rej("loop_along")
			continue
		route[0] = _insert_junction(ra, pa)
		route[route.size() - 1] = _insert_junction(rb, pb)
		var rec := _add_road("loop_0", &"county", p.county_width - 0.5, route)
		_split_crossings(rec)
		_rebuild_index()
		_mark_road_cells(rec)
		return true
	_rej("loop_route")
	return false


## Country lanes: 2-4 (scaled) branches off the rural roads toward open
## country (farms and fields line them); a lane ending near another road
## joins it (a loop).
func _country_lanes(r: RandomNumberGenerator) -> void:
	var rng_n := p.scaled_range(2, 4, 2)
	var want := r.randi_range(rng_n.x, rng_n.y)
	var made := 0
	for attempt in 40:
		if made >= want:
			break
		var rural: Array[Dictionary] = []
		for rd in layout.roads:
			if rd.kind == &"highway" or rd.kind == &"county":
				rural.append(rd)
		var rd2: Dictionary = rural[r.randi_range(0, rural.size() - 1)]
		var pts: PackedVector2Array = rd2.points
		if pts.size() < 2:
			continue
		var i := r.randi_range(0, pts.size() - 2)
		if pts[i].distance_to(pts[i + 1]) < 4.0:
			continue
		var q := pts[i].lerp(pts[i + 1], r.randf_range(0.2, 0.8))
		if _in_reserve(q, 40.0) or _near_junction_pts(q, 60.0):
			continue
		var e := (pts[i + 1] - pts[i]).normalized()
		var dir := rot90(e) * (1.0 if r.randf() < 0.5 else -1.0)
		dir = dir.rotated(deg_to_rad(r.randf_range(-30.0, 30.0)))
		var length := r.randf_range(220.0, 420.0) * maxf(sqrt(p.area_scale()), 0.6)
		var tgt := q + dir * length
		tgt = Vector2(clampf(tgt.x, 40.0, layout.size.x - 40.0), clampf(tgt.y, 40.0, layout.size.y - 40.0))
		if tgt.distance_to(q) < 150.0 or _solid_at(tgt, 20.0) or _grid.is_point_solid(_cell_of(tgt)):
			continue
		var j := _insert_junction(rd2, q)
		var route := _route(j, tgt)
		if route.is_empty():
			continue
		# Join another road when the lane ends near one.
		var np := _nearest_network_point(tgt, [&"highway", &"county"])
		if not np.is_empty() and (np.point as Vector2).distance_to(tgt) < 160.0 and np.road != rd2 \
				and not _near_junction_pts(np.point, 20.0):
			var jb := _insert_junction(np.road, np.point)
			var tail := _route(tgt, jb, false, false)
			if not tail.is_empty():
				tail.remove_at(0)
				route.append_array(tail)
		if _runs_along(route, p.county_width - 1.0):
			continue
		made += 1
		var lane := _add_road("lane_%d" % made, &"county", p.county_width - 1.0, route)
		_split_crossings(lane)
		_mark_road_cells(lane)


## A new road [pts] runs alongside an existing one (away from its own ends).
func _runs_along(pts: PackedVector2Array, width: float, skip_start: bool = true, skip_end: bool = true) -> bool:
	if pts.size() < 2:
		return false
	var a := pts[0]
	var z := pts[pts.size() - 1]
	for i in range(pts.size() - 1):
		var l := pts[i].distance_to(pts[i + 1])
		var steps := maxi(1, int(l / 4.0))
		for k in steps + 1:
			var q := pts[i].lerp(pts[i + 1], float(k) / steps)
			if (skip_start and q.distance_to(a) < 12.0) or (skip_end and q.distance_to(z) < 12.0):
				continue
			if _road_gap(q) < width * 0.5 + 0.5:
				return true
	return false


## Like _runs_along, but crossings are allowed: samples within 20 m of a
## point where [pts] crosses another road are ignored.
func _runs_along_crossing(pts: PackedVector2Array, width: float) -> bool:
	var crossings: Array[Vector2] = []
	for i in range(pts.size() - 1):
		for e in _segments_near(Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(2.0)):
			if e[0] == e[1]:
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(pts[i], pts[i + 1], e[0], e[1])
			if hit != null:
				crossings.append(hit)
	for i in range(pts.size() - 1):
		var l := pts[i].distance_to(pts[i + 1])
		var steps := maxi(1, int(l / 4.0))
		for k in steps + 1:
			var q := pts[i].lerp(pts[i + 1], float(k) / steps)
			var near_x := false
			for c in crossings:
				if c.distance_to(q) < 15.0:
					near_x = true
					break
			if near_x or q.distance_to(pts[0]) < 12.0 or q.distance_to(pts[pts.size() - 1]) < 12.0:
				continue
			if _road_gap(q) < width * 0.5 + 0.5:
				return true
	return false


func _near_junction_pts(q: Vector2, dist: float) -> bool:
	var count := {}
	for rd in layout.roads:
		for v in rd.points:
			if v.distance_to(q) < dist:
				var k := Vector2i(roundi(v.x * 100.0), roundi(v.y * 100.0))
				count[k] = int(count.get(k, 0)) + 1
				if int(count[k]) >= 2:
					return true
	return false


## A point [dist] m further along road [rd] past [from] (INF if none).
func _seg_wet(a: Vector2, b: Vector2) -> bool:
	var n := maxi(1, int(a.distance_to(b) / 2.0))
	for k in n + 1:
		var q := a.lerp(b, float(k) / n)
		for pd in layout.ponds:
			if (pd.center as Vector2).distance_to(q) < float(pd.radius) + 3.0:
				return true
	return false


func _point_beyond(rd: Dictionary, from: Vector2, dist: float) -> Vector2:
	var pts: PackedVector2Array = rd.points
	var start := -1
	for i in pts.size():
		if pts[i].distance_to(from) < 0.01:
			start = i
	if start < 0:
		return Vector2.INF
	var left := dist
	for i in range(start, pts.size() - 1):
		var l := pts[i].distance_to(pts[i + 1])
		if l >= left:
			var q := pts[i].lerp(pts[i + 1], left / l)
			return q if not _in_reserve(q, 8.0) else Vector2.INF
		left -= l
	return Vector2.INF


func _drop_settlement(sid: String) -> void:
	for i in range(layout.lots.size() - 1, -1, -1):
		if layout.lots[i].settlement == sid:
			layout.lots.remove_at(i)
	for i in range(layout.settlements.size() - 1, -1, -1):
		if layout.settlements[i].id == sid:
			layout.settlements.remove_at(i)
	for i in range(layout.roads.size() - 1, -1, -1):
		if String(layout.roads[i].id).begins_with(sid + "_"):
			layout.roads.remove_at(i)
	for i in range(_reserves.size() - 1, -1, -1):
		if _reserves[i].id == sid:
			_reserves.remove_at(i)
	for i in range(_hamlets.size() - 1, -1, -1):
		if _hamlets[i].id == sid:
			_hamlets.remove_at(i)
	_rebuild_index()


func _rebuild_index() -> void:
	_bins.clear()
	for rd in layout.roads:
		_index_road(rd)


# --- Farmsteads --------------------------------------------------------------------------------

## Farms along the rural roads: the yard faces the road 25-60 m off it,
## fields around it, a straight dirt drive (or a routed one) to the road.
func _place_farms() -> void:
	var r := _rng("farms")
	var rng_count := p.scaled_range(p.farmstead_count_min, p.farmstead_count_max, 2)
	var count := maxi(r.randi_range(rng_count.x, rng_count.y), r.randi_range(rng_count.x, rng_count.y))
	var rural: Array[Dictionary] = []
	for rd in layout.roads:
		if rd.kind == &"highway" or rd.kind == &"county":
			rural.append(rd)
	if rural.is_empty():
		return
	# Candidate road points every 12 m (arc length, so long rural roads
	# get the farms), away from settlements, in random order.
	var cands_q: Array = []
	for rd0 in rural:
		var pts0: PackedVector2Array = rd0.points
		for i0 in range(pts0.size() - 1):
			var l0 := pts0[i0].distance_to(pts0[i0 + 1])
			var steps := int(l0 / (6.0 if _small() else 12.0))
			for k0 in steps:
				var q0 := pts0[i0].lerp(pts0[i0 + 1], (k0 + 0.5) / maxf(float(steps), 1.0))
				if not _in_reserve(q0, 25.0 if _small() else 50.0):
					cands_q.append([rd0, i0, q0, 1.0])
					cands_q.append([rd0, i0, q0, -1.0])
	_shuffle(cands_q, r)
	layout.stats["farm_target"] = count
	layout.stats["farm_candidates"] = cands_q.size()
	var made := 0
	var min_farms := 2 if minf(layout.size.x, layout.size.y) < 600.0 else 3
	for attempt in mini(cands_q.size() * 3, 3600):
		if made >= count or (attempt >= cands_q.size() and made >= min_farms):
			break
		var cq: Array = cands_q[attempt % cands_q.size()]
		var rd: Dictionary = cq[0]
		var pts: PackedVector2Array = rd.points
		var q: Vector2 = cq[2]
		# Junctions inserted since: find q's segment again.
		var i := 0
		var bd0 := INF
		for k1 in range(pts.size() - 1):
			var dd := Geometry2D.get_closest_point_to_segment(q, pts[k1], pts[k1 + 1]).distance_to(q)
			if dd < bd0:
				bd0 = dd
				i = k1
		var a := pts[i]
		var b := pts[i + 1]
		# Local direction over a few vertices (smoothed roads have short segments).
		var ea := pts[maxi(i - 2, 0)]
		var eb := pts[mini(i + 3, pts.size() - 1)]
		if ea.distance_to(eb) < 1.0:
			continue
		var phase := attempt / cands_q.size()
		if _in_reserve(q, (10.0 if phase >= 2 else 25.0) if _small() else (30.0 if phase >= 2 else 50.0)):
			_rej("farm_near_settlement")
			continue
		var e := (eb - ea).normalized()
		var side: float = cq[3]
		var away := rot90(e) * side
		var gate := q + away * (float(rd.width) * 0.5 + ((r.randf_range(8.0, 60.0) if phase >= 2 else r.randf_range(10.0, 26.0)) if _small() else r.randf_range(22.0, 55.0)))
		var sid := "farm%d" % (made + 1)
		var yard := frame_rec(gate - e * 24.0, gate + e * 24.0, away, 40.0)
		var ypoly := WorldLayout.obb_poly(yard.xf, yard.size)
		if not _inside_world(ypoly, 6.0 if _small() else 20.0):
			_rej("farm_world")
			continue
		if _hits_reserve(ypoly, (15.0 if _small() else 30.0) if attempt < cands_q.size() else ((2.0 if phase >= 2 else 4.0) if _small() else 8.0)):
			_rej("farm_reserve")
			continue
		if _road_clearance(ypoly, 6.0) < 0.0:
			_rej("farm_road")
			continue
		if not _lot_free(ypoly):
			_rej("farm_lot")
			continue
		var xf: Transform2D = yard.xf
		var ok_zone := 0
		for k in 8:
			if layout.zone_at(xf * Vector2(r.randf_range(0, 48), r.randf_range(0, 40))) != WorldLayout.Zone.WOODS:
				ok_zone += 1
		if ok_zone < 5 and not (_small() and attempt >= cands_q.size()):
			_rej("farm_woods")
			continue
		# Drive: straight from 8 m in front of the gate to the road.
		var gate_local := Vector2(24.0, 0.0)
		var exit := xf * (gate_local + Vector2(0, -8.0))
		var jp := Geometry2D.get_closest_point_to_segment(exit, a, b)
		if _near_junction_pts(jp, 14.0 if phase >= 2 else 22.0):
			_rej("farm_junction")
			continue
		_exempt = [exit, jp]
		var straight_ok := _segment_clear(exit, jp) and exit.distance_to(jp) < 70.0 and not _seg_wet(exit, jp)
		_exempt = []
		var drive_pts := PackedVector2Array()
		if straight_ok:
			drive_pts = PackedVector2Array([exit, jp])
		else:
			drive_pts = _route(exit, jp, false, false)
			var dlen := 0.0
			for k2 in range(drive_pts.size() - 1):
				dlen += drive_pts[k2].distance_to(drive_pts[k2 + 1])
			if drive_pts.is_empty() or dlen > 150.0 or dlen > 2.0 * exit.distance_to(jp) + 10.0:
				_rej("farm_drive")
				continue
		var wet := false
		for k3 in range(drive_pts.size() - 1):
			if _seg_wet(drive_pts[k3], drive_pts[k3 + 1]):
				wet = true
		for pd in layout.ponds:
			if WorldLayout.seg_poly_distance(pd.center, pd.center, ypoly) < float(pd.radius) + 4.0:
				wet = true
		if wet:
			_rej("farm_wet")
			continue
		# Fields around the farmhouse (farm frame: x across, y back).
		var fields: Array[Dictionary] = []
		var cands := [
			[Vector2(-8.0, 44.0), Vector2(r.randf_range(50.0, 70.0), r.randf_range(34.0, 56.0))],
			[Vector2(52.0, 0.0), Vector2(r.randf_range(34.0, 56.0), r.randf_range(40.0, 70.0))],
			[Vector2(-4.0 - r.randf_range(34.0, 56.0), 0.0), Vector2(0.0, r.randf_range(40.0, 70.0))],
		]
		cands[2][1].x = -cands[2][0].x - 4.0
		var fpolys: Array = []
		for c in cands:
			var o: Vector2 = c[0]
			var s: Vector2 = c[1]
			var fxf := xf * Transform2D(0.0, o)
			var fpoly := WorldLayout.obb_poly(fxf, s)
			if not _inside_world(fpoly, 6.0 if _small() else 10.0) or _hits_reserve(fpoly, 6.0) or _road_clearance(fpoly, 3.0) < 0.0 \
					or not _lot_free(fpoly):
				continue
			var clash := false
			for fp in fpolys:
				if WorldLayout.polys_overlap(fp, fpoly):
					clash = true
			for fl in layout.fields:
				if WorldLayout.polys_overlap(WorldLayout.poly_of(fl), fpoly):
					clash = true
			if WorldLayout.seg_poly_distance(drive_pts[0], drive_pts[drive_pts.size() - 1], fpoly) < 4.0:
				clash = true
			if clash:
				continue
			fpolys.append(fpoly)
			fields.append({"xf": fxf, "size": s})
		if fields.is_empty() and not (_small() and attempt >= cands_q.size()):
			_rej("farm_fields")
			continue
		made += 1
		# Commit: junction, drive, yard lot, fields, reserve.
		if _runs_along(drive_pts, p.dirt_width, false, true):
			_rej("farm_drive_along")
			made -= 1
			continue
		_commit_farm(sid, made, rd, yard, away, ypoly, drive_pts, fields, r)
	# Fallback (small / crowded maps): a yard anywhere free with its own
	# routed drive to the nearest rural road.
	var tries := 0
	while made < min_farms and tries < 600:
		tries += 1
		var sid2 := "farm%d" % (made + 1)
		var c := Vector2(r.randf_range(40.0, layout.size.x - 40.0), r.randf_range(40.0, layout.size.y - 40.0))
		var ang := r.randf_range(-PI, PI)
		var xf2 := Transform2D(ang, c)
		var yard2 := {"xf": xf2, "size": Vector2(48, 40)}
		var ypoly2 := WorldLayout.obb_poly(xf2, yard2.size)
		yard2["rect"] = WorldLayout.poly_aabb(ypoly2)
		if not _inside_world(ypoly2, 6.0) or _hits_reserve(ypoly2, 4.0) or _road_clearance(ypoly2, 6.0) < 0.0 or not _lot_free(ypoly2):
			continue
		var wet2 := false
		for pd in layout.ponds:
			if WorldLayout.seg_poly_distance(pd.center, pd.center, ypoly2) < float(pd.radius) + 4.0:
				wet2 = true
		if wet2:
			continue
		var exit2 := xf2 * Vector2(24.0, -8.0)
		var np := _nearest_network_point(exit2, [&"highway", &"county"])
		if np.is_empty() or (np.point as Vector2).distance_to(exit2) > 160.0 or _near_junction_pts(np.point, 14.0):
			continue
		var dpts := _route(exit2, np.point, false, false)
		if dpts.is_empty() or _runs_along(dpts, p.dirt_width, false, true):
			continue
		var wet3 := false
		for k4 in range(dpts.size() - 1):
			if _seg_wet(dpts[k4], dpts[k4 + 1]):
				wet3 = true
			if WorldLayout.seg_poly_distance(dpts[k4], dpts[k4 + 1], ypoly2) < 3.0:
				wet3 = true
		if wet3:
			continue
		made += 1
		_rej("farm_standalone")
		var away2 := xf2.y.normalized()
		_commit_farm(sid2, made, np.road, yard2, away2, ypoly2, dpts, [], r)


func _commit_farm(sid: String, made: int, rd: Dictionary, yard: Dictionary, away: Vector2, ypoly: PackedVector2Array,
		drive_pts: PackedVector2Array, fields: Array, r: RandomNumberGenerator) -> void:
	var xf: Transform2D = yard.xf
	var gate_local := Vector2(24.0, 0.0)
	var exit := drive_pts[0]
	var j := _insert_junction(rd, drive_pts[drive_pts.size() - 1])
	drive_pts[drive_pts.size() - 1] = j
	var drv := _add_road("%s_drive" % sid, &"dirt", p.dirt_width, drive_pts)
	_split_crossings(drv)
	_mark_road_cells(drv)
	var lot := yard.duplicate()
	lot["id"] = "%s_yard" % sid
	lot["settlement"] = sid
	lot["front_dir"] = -away
	lot["front"] = WorldLayout.front_of(-away)
	lot["use"] = &"farmstead"
	lot["road"] = drv.id
	layout.lots.append(lot)
	var total := ypoly
	_reserve(sid, _grow_poly(ypoly, 3.0))
	for fi in fields.size():
		var fr: Dictionary = fields[fi]
		var fpoly2 := WorldLayout.obb_poly(fr.xf, fr.size)
		_reserve("%s_f%d" % [sid, fi], fpoly2)
		_set_zone_poly(fpoly2, WorldLayout.Zone.FIELD)
		layout.fields.append({"id": "%s_field%d" % [sid, fi + 1], "xf": fr.xf, "size": fr.size,
			"rect": WorldLayout.poly_aabb(fpoly2), "axis": 0 if (fr.size as Vector2).x >= (fr.size as Vector2).y else 1,
			"crop": CROPS[r.randi_range(0, CROPS.size() - 1)], "farm": sid})
	_set_zone_poly(ypoly, WorldLayout.Zone.MEADOW)
	layout.settlements.append({"id": sid, "kind": &"farmstead", "name": "Farm %d" % made,
		"center": xf * Vector2(24, 20), "xf": xf, "size": Vector2(48, 40), "rect": WorldLayout.poly_aabb(total),
		"gate": xf * gate_local, "exit": exit, "road": drv.id})


func _compute_junctions() -> void:
	var count := {}
	for rd in layout.roads:
		var seen := {}
		for q in rd.points:
			var k := Vector2i(roundi(q.x * 100.0), roundi(q.y * 100.0))
			if seen.has(k):
				continue
			seen[k] = true
			count[k] = int(count.get(k, 0)) + 1
	var out := PackedVector2Array()
	var keys: Array = count.keys()
	keys.sort()
	for k in keys:
		if int(count[k]) >= 2:
			out.append(Vector2(k) / 100.0)
	layout.junctions = out


# --- Buildings ----------------------------------------------------------------------------------

## Place a plan in lot-local sub-area [x0,x1] × [y0,y1] (front at y0 =
## road side): [setback] from y0, [lateral] 0..1 across. The plan's front
## (local y = D) faces the road.
func _add_building(lot: Dictionary, id: String, kind: StringName, x0: float, x1: float, y0: float, y1: float,
		setback: float, lateral: float, opts: Dictionary = {}) -> Dictionary:
	var pseed := sub_seed(layout.world_seed, "plan:" + id)
	var o := opts.duplicate()
	o["max_width"] = x1 - x0 - 2.0
	o["max_depth"] = y1 - y0 - setback - 1.5
	var plan := BuildingPlanGenerator.generate(kind, pseed, o)
	var fp := plan.footprint
	var a := x0 + (x1 - x0 - fp.x) * lateral
	var s := y0 + setback
	var bxf: Transform2D = (lot.xf as Transform2D) * Transform2D(PI, Vector2(a + fp.x, s + fp.y))
	var door_local := BuildingPlanGenerator.opening_point(plan, "front_door")
	var door := bxf * door_local
	var edge := (lot.xf as Transform2D) * Vector2(a + fp.x - door_local.x, 0.0)
	var access := _access_point(edge, lot)
	var rec := {"id": id, "lot": lot.id, "settlement": lot.settlement, "kind": kind, "xf": bxf, "size": fp,
		"rect": WorldLayout.poly_aabb(WorldLayout.obb_poly(bxf, fp)), "front_dir": lot.front_dir, "front": lot.front,
		"door": door, "access": access, "access_path": PackedVector2Array([door, edge, access]),
		"local": Rect2(a, s, fp.x, fp.y), "door_x": a + fp.x - door_local.x}
	layout.buildings.append(rec)
	layout.plans[id] = plan
	return rec


func _access_point(from: Vector2, lot: Dictionary) -> Vector2:
	var rd := layout.road(String(lot.road))
	if rd.is_empty():
		return from
	var pts: PackedVector2Array = rd.points
	var best := from
	var bd := INF
	for i in range(pts.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(from, pts[i], pts[i + 1])
		if q.distance_to(from) < bd:
			bd = q.distance_to(from)
			best = q
	return best


func _lw(lot: Dictionary, local: Vector2) -> Vector2:
	return (lot.xf as Transform2D) * local


func _place_buildings() -> void:
	var r := _rng("buildings")
	# One hammer guaranteed per hamlet (its first house); the town has the
	# hardware store, farms the barn tool crate.
	var armed := {}
	for lot in layout.lots:
		var use := StringName(lot.use)
		var w: float = (lot.size as Vector2).x
		var d: float = (lot.size as Vector2).y
		var bid := String(lot.id)
		match use:
			&"house":
				var garage := r.randf() < 0.3 and w >= 15.5
				var hammer: bool = String(lot.settlement).begins_with("hamlet") and not armed.has(lot.settlement)
				armed[lot.settlement] = true
				var b := _add_building(lot, bid, &"house", 0.0, w, 0.0, d, r.randf_range(4.5, 6.5), r.randf_range(0.15, 0.85),
					{"garage": garage, "hamlet": lot.settlement != "town", "hammer": hammer})
				_house_grounds(lot, b, r)
			&"convenience_store", &"hardware_store", &"pharmacy", &"diner", &"bar", &"church", &"post_office":
				var b2 := _add_building(lot, bid, use, 0.0, w, 0.0, d, 1.0 if use != &"church" else 3.0, 0.5)
				_path_to_front(b2)
				var back0: float = (b2.local as Rect2).end.y + 1.0
				if d - back0 >= 5.5:
					_parking_local(lot, Rect2(1.0, back0, w - 2.0, d - 0.5 - back0))
			&"parking":
				_parking_local(lot, Rect2(1.0, 1.0, w - 2.0, d - 2.0))
			&"warehouse":
				var b3 := _add_building(lot, bid, &"warehouse", 0.0, w, 0.0, d, 16.0, r.randf_range(0.3, 0.7))
				_parking_local(lot, Rect2(1.5, 1.0, w - 3.0, 13.0))
				_path_to_front(b3)
			&"gas_station":
				var b4 := _add_building(lot, bid, &"gas_station", 0.0, w, 0.0, d, 22.0, r.randf_range(0.2, 0.8))
				layout.paths.append({"xf": lot.xf * Transform2D(0.0, Vector2(0.5, 0.5)), "size": Vector2(w - 1.0, 20.0), "kind": &"apron"})
				lot["canopy_local"] = Rect2(9.0, 5.0, w - 18.0, 11.0)
				_path_to_front(b4)
			&"farmstead":
				_farmstead(lot, r)


func _path_to_front(b: Dictionary) -> void:
	var path: PackedVector2Array = b.access_path
	if path[0].distance_to(path[1]) > 0.3:
		layout.paths.append({"a": path[0], "b": path[1], "width": p.path_width, "kind": &"path", "lot": b.lot})


func _parking_local(lot: Dictionary, r: Rect2) -> void:
	var xf: Transform2D = (lot.xf as Transform2D) * Transform2D(0.0, r.position)
	layout.parking.append({"xf": xf, "size": r.size, "rect": WorldLayout.poly_aabb(WorldLayout.obb_poly(xf, r.size)),
		"lot": lot.id})


## Front path, a driveway on the wider side, mailbox on the other side of
## the path, trash can beside / behind the house (lot-local planning).
func _house_grounds(lot: Dictionary, b: Dictionary, r: RandomNumberGenerator) -> void:
	_path_to_front(b)
	var loc: Rect2 = b.local
	var w: float = (lot.size as Vector2).x
	var left := loc.position.x
	var right := w - loc.end.x
	var drive_side := 0.0
	if maxf(left, right) >= 3.4:
		drive_side = -1.0 if left >= right else 1.0
		var free := maxf(left, right)
		var cx := loc.position.x - minf(free, 4.0) * 0.5 if drive_side < 0.0 else loc.end.x + minf(free, 4.0) * 0.5
		var y1 := loc.position.y + minf(loc.size.y, 6.0)
		var a := _lw(lot, Vector2(cx, 0.0))
		var bpt := _lw(lot, Vector2(cx, y1))
		layout.paths.append({"a": a, "b": bpt, "width": p.driveway_width, "kind": &"driveway", "lot": lot.id})
		lot["driveway"] = [a, bpt]
		lot["driveway_local"] = [cx, y1]
	var door_x: float = b.door_x
	var mside := -drive_side if drive_side != 0.0 else (1.0 if r.randf() < 0.5 else -1.0)
	var mx := clampf(door_x + mside * 1.3, 0.8, w - 0.8)
	layout.props.append({"kind": &"mailbox", "pos": _lw(lot, Vector2(mx, 0.6)), "yaw": _yaw_toward(lot.front_dir)})
	# Trash can: beside the house (away from the driveway) or behind it,
	# never in front of any of its doors (1.8 m clear).
	var tside := -drive_side if drive_side != 0.0 else 1.0
	var room := left if tside < 0.0 else right
	var tx := loc.position.x - 0.8 if tside < 0.0 else loc.end.x + 0.8
	var cands: Array[Vector2] = []
	if room >= 1.6:
		cands.append_array([Vector2(tx, loc.position.y + 1.0), Vector2(tx, loc.end.y - 1.0)])
	var dl := (lot.size as Vector2).y
	if dl - loc.end.y >= 1.8:
		cands.append_array([Vector2(loc.position.x + 1.0, loc.end.y + 0.9), Vector2(loc.end.x - 1.0, loc.end.y + 0.9),
			Vector2(loc.get_center().x, loc.end.y + 0.9)])
	var bxf: Transform2D = b.xf
	var dsegs: Array = []
	for e in BuildingPlanGenerator.exterior_doors(layout.plans[b.id]):
		dsegs.append([bxf * (e[0] as Vector2), bxf * ((e[0] as Vector2) + (e[1] as Vector2) * 1.8)])
	for lc in cands:
		var tpos := _lw(lot, lc)
		var clear := not _near_driveway(tpos, 0.6)
		for ds in dsegs:
			if Geometry2D.get_closest_point_to_segment(tpos, ds[0], ds[1]).distance_to(tpos) < 1.2:
				clear = false
		if clear:
			layout.props.append({"kind": &"trash", "pos": tpos, "yaw": _yaw_toward(lot.front_dir)})
			break


## Yaw (radians about Y) that turns a prop's local +Z toward [dir].
static func _yaw_toward(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


func _farmstead(lot: Dictionary, r: RandomNumberGenerator) -> void:
	var sid := String(lot.settlement)
	var hs := 1.0 if r.randf() < 0.5 else -1.0
	# Farmhouse on one side of the central lane (x = 24), barn on the other.
	var hx0 := 2.0 if hs < 0.0 else 27.0
	var bx0 := 27.0 if hs < 0.0 else 2.0
	var house := _add_building(lot, "%s_house" % sid, &"farmhouse", hx0, hx0 + 19.0, 3.0, 24.0, 0.5, 0.5)
	var barn := _add_building(lot, "%s_barn" % sid, &"barn", bx0, bx0 + 19.0, 12.0, 30.0, 0.5, 0.5)
	var settle := layout.settlement(sid)
	var gate: Vector2 = _lw(lot, Vector2(24.0, 0.0))
	var exit: Vector2 = _lw(lot, Vector2(24.0, -8.0))
	layout.paths.append({"a": exit, "b": gate, "width": p.dirt_width, "kind": &"driveway", "lot": lot.id})
	layout.paths.append({"a": gate, "b": _lw(lot, Vector2(24.0, 16.0)), "width": p.dirt_width, "kind": &"driveway", "lot": lot.id})
	for bb in [house, barn]:
		var loc: Rect2 = bb.local
		var dx: float = bb.door_x
		var step_y := loc.position.y - 2.0
		var step := _lw(lot, Vector2(dx, step_y))
		var lane := _lw(lot, Vector2(24.0, step_y))
		layout.paths.append({"a": lane, "b": step, "width": p.path_width + 0.6, "kind": &"path", "lot": lot.id})
		layout.paths.append({"a": step, "b": bb.door, "width": p.path_width, "kind": &"path", "lot": lot.id})
		bb.access = exit
		bb.access_path = PackedVector2Array([bb.door, step, lane, gate, exit])
	var bloc: Rect2 = barn.local
	# Silo behind the barn, hay bales along the back fence on the house side.
	var silo_local := Vector2(bloc.get_center().x, minf(bloc.end.y + 3.2, 36.6))
	if silo_local.y - 2.4 > bloc.end.y + 0.3:
		layout.props.append({"kind": &"silo", "pos": _lw(lot, silo_local), "yaw": 0.0, "radius": 2.2, "height": 9.0})
	for i in r.randi_range(3, 6):
		var hl := Vector2(hx0 + 1.5 + r.randf_range(0.0, 16.0), r.randf_range(29.0, 37.5))
		layout.props.append({"kind": &"hay", "pos": _lw(lot, hl), "yaw": _yaw_toward(lot.front_dir) + r.randf_range(-0.3, 0.3)})
	lot["farm_yard_center"] = _lw(lot, Vector2(24.0, 9.0))
	lot["pickup_local"] = Vector2(24.0 - hs * 6.0, 7.0)
	if not settle.is_empty():
		settle["yard_center"] = lot.farm_yard_center


## Player start: a random house of a random settlement kind (town 50 %,
## hamlet 30 %, farm 20 %), seeded; start point = its living room.
func _choose_spawn() -> void:
	var r := _rng("spawn")
	var groups := {"town": [], "hamlet": [], "farm": []}
	for b in layout.buildings:
		var sid := String(b.settlement)
		if b.kind == &"house":
			groups["town" if sid == "town" else "hamlet"].append(b)
		elif b.kind == &"farmhouse":
			groups["farm"].append(b)
	var roll := r.randf()
	var order := ["town", "hamlet", "farm"] if roll < 0.5 else (["hamlet", "town", "farm"] if roll < 0.8 else ["farm", "town", "hamlet"])
	var best := {}
	for g in order:
		var list: Array = groups[g]
		if not list.is_empty():
			best = list[r.randi_range(0, list.size() - 1)]
			break
	if best.is_empty():
		return
	layout.spawn_building = best.id
	var plan: BuildingPlan = layout.plans[best.id]
	var room := {}
	for rm in plan.rooms:
		if BuildingPlan.room_type_of(rm) == &"living_room":
			room = rm
	if room.is_empty():
		room = plan.rooms[0]
	layout.spawn_point = (best.xf as Transform2D) * (room.rect as Rect2).get_center()
	layout.stats["spawn_kind"] = best.kind
	layout.stats["spawn_settlement"] = best.settlement


# --- Blocked raster (trees / fields / zombies) ----------------------------------------------------

func _build_blocked_raster() -> void:
	_bw = int(ceil(layout.size.x / BLOCK_CELL))
	_bh = int(ceil(layout.size.y / BLOCK_CELL))
	_blocked = PackedByteArray()
	_blocked.resize(_bw * _bh)
	for rd in layout.roads:
		var pts: PackedVector2Array = rd.points
		var half := float(rd.width) * 0.5 + float(rd.sidewalk) + 2.0
		for i in range(pts.size() - 1):
			_mark_capsule(pts[i], pts[i + 1], half, 1)
		if rd.has("cap"):
			_mark_capsule(pts[pts.size() - 1], pts[pts.size() - 1], float(rd.cap) + float(rd.sidewalk) + 2.0, 1)
	for pth in layout.paths:
		if pth.has("xf"):
			_mark_poly(WorldLayout.poly_of(pth), 1)
		else:
			_mark_capsule(pth.a, pth.b, float(pth.width) * 0.5 + 0.8, 1)
	for lot in layout.lots:
		_mark_poly(WorldLayout.poly_of(lot), 2)
	for q in layout.ponds:
		_mark_capsule(q.center, q.center, float(q.radius) + 2.0, 3)
	for pk in layout.parking:
		_mark_poly(WorldLayout.poly_of(pk), 1)
	for fl in layout.fields:
		_mark_poly(_grow_poly(WorldLayout.poly_of(fl), 1.5), 4)
	for rs in _reserves:
		if String(rs.id).begins_with("hamlet") or rs.id == "town":
			_mark_poly(rs.poly, 5)


func _mark_poly(poly: PackedVector2Array, v: int) -> void:
	var bb := WorldLayout.poly_aabb(poly).grow(BLOCK_CELL)
	var x0 := clampi(int(bb.position.x / BLOCK_CELL), 0, _bw - 1)
	var x1 := clampi(int(bb.end.x / BLOCK_CELL), 0, _bw - 1)
	var z0 := clampi(int(bb.position.y / BLOCK_CELL), 0, _bh - 1)
	var z1 := clampi(int(bb.end.y / BLOCK_CELL), 0, _bh - 1)
	var gpoly := _grow_poly(poly, BLOCK_CELL * 0.75)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2((x + 0.5) * BLOCK_CELL, (z + 0.5) * BLOCK_CELL)
			if Geometry2D.is_point_in_polygon(c, gpoly):
				var i := z * _bw + x
				if _blocked[i] == 0 or v == 1:
					_blocked[i] = v


func _mark_capsule(a: Vector2, b: Vector2, half: float, v: int) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(half, half)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(half, half)
	var x0 := clampi(int(lo.x / BLOCK_CELL), 0, _bw - 1)
	var x1 := clampi(int(hi.x / BLOCK_CELL), 0, _bw - 1)
	var z0 := clampi(int(lo.y / BLOCK_CELL), 0, _bh - 1)
	var z1 := clampi(int(hi.y / BLOCK_CELL), 0, _bh - 1)
	var reach := half + BLOCK_CELL * 0.71
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2((x + 0.5) * BLOCK_CELL, (z + 0.5) * BLOCK_CELL)
			if Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) <= reach:
				_blocked[z * _bw + x] = v


func _blocked_at(pt: Vector2) -> int:
	var x := int(pt.x / BLOCK_CELL)
	var z := int(pt.y / BLOCK_CELL)
	if x < 0 or z < 0 or x >= _bw or z >= _bh:
		return 9
	return _blocked[z * _bw + x]


# --- Farmland along the roads ----------------------------------------------------------------------

## Fields only beside a rural road (a strip frame aligned with it, 4-8 m
## off the verge) on farmland; exact polygon checks against lots,
## reserves, roads, other fields and ponds.
func _place_fields() -> void:
	var r := _rng("fields")
	var n := 0
	for rd in layout.roads:
		if not (rd.kind in [&"highway", &"county", &"dirt"]):
			continue
		var pts: PackedVector2Array = rd.points
		# Arc-length samples every 20 m with a direction smoothed over ±25 m.
		var acc := PackedFloat32Array([0.0])
		for i in range(pts.size() - 1):
			acc.append(acc[acc.size() - 1] + pts[i].distance_to(pts[i + 1]))
		var total := acc[acc.size() - 1]
		var sd := 10.0
		while sd < total - 10.0:
			var q := _at_arc(pts, acc, sd)
			var dir := (_at_arc(pts, acc, minf(sd + 25.0, total)) - _at_arc(pts, acc, maxf(sd - 25.0, 0.0))).normalized()
			sd += 20.0
			if dir == Vector2.ZERO or _in_reserve(q, 20.0):
				continue
			var sides := [1.0, -1.0]
			if r.randf() < 0.5:
				sides.reverse()
			for side in sides:
				var nn: Vector2 = rot90(dir) * float(side)
				for size_try in 2:
					var L := r.randf_range(40.0, 75.0) if size_try == 0 else r.randf_range(26.0, 40.0)
					var D := r.randf_range(30.0, 65.0) if size_try == 0 else r.randf_range(22.0, 35.0)
					var off := float(rd.width) * 0.5 + r.randf_range(4.0, 8.0)
					var p0: Vector2 = q - dir * L * 0.5 + nn * off
					var rec := frame_rec(p0, p0 + dir * L, nn, D)
					var poly := WorldLayout.obb_poly(rec.xf, rec.size)
					if not _field_ok(poly):
						_rej("field")
						continue
					n += 1
					_add_field("field%d" % n, rec, "", r)
					if r.randf() < 0.6:
						var D2 := r.randf_range(30.0, 60.0)
						var q0: Vector2 = p0 + nn * (D + 5.0)
						var rec2 := frame_rec(q0, q0 + dir * L, nn, D2)
						if _field_ok(WorldLayout.obb_poly(rec2.xf, rec2.size)):
							n += 1
							_add_field("field%d" % n, rec2, "", r)
					break


func _add_field(id: String, rec: Dictionary, farm: String, r: RandomNumberGenerator) -> void:
	var poly := WorldLayout.obb_poly(rec.xf, rec.size)
	_set_zone_poly(poly, WorldLayout.Zone.FIELD)
	layout.fields.append({"id": id, "xf": rec.xf, "size": rec.size, "rect": WorldLayout.poly_aabb(poly),
		"axis": r.randi_range(0, 1), "crop": CROPS[r.randi_range(0, CROPS.size() - 1)], "farm": farm})
	_mark_poly(_grow_poly(poly, 1.5), 4)


static func _at_arc(pts: PackedVector2Array, acc: PackedFloat32Array, s: float) -> Vector2:
	for i in range(pts.size() - 1):
		if s <= acc[i + 1] or i == pts.size() - 2:
			var l := acc[i + 1] - acc[i]
			return pts[i].lerp(pts[i + 1], clampf((s - acc[i]) / maxf(l, 0.001), 0.0, 1.0))
	return pts[pts.size() - 1]


func _field_ok(poly: PackedVector2Array) -> bool:
	if not _inside_world(poly, 8.0):
		_rej("field_world")
		return false
	if _hits_reserve(poly, 4.0):
		_rej("field_reserve")
		return false
	if _road_clearance(poly, 2.5) < 0.0:
		_rej("field_road")
		return false
	var bb := WorldLayout.poly_aabb(poly)
	for l in layout.lots:
		if (l.rect as Rect2).grow(4.0).intersects(bb) and WorldLayout.polys_overlap(_grow_poly(poly, 3.0), WorldLayout.poly_of(l)):
			return false
	for fl in layout.fields:
		if (fl.rect as Rect2).grow(4.0).intersects(bb) and WorldLayout.polys_overlap(_grow_poly(poly, 3.0), WorldLayout.poly_of(fl)):
			return false
	for pd in layout.ponds:
		if WorldLayout.seg_poly_distance(pd.center, pd.center, poly) < float(pd.radius) + 4.0:
			return false
	var bbp := bb.grow(8.0)
	for pth in layout.paths:
		if not pth.has("a"):
			continue
		var pa: Vector2 = pth.a
		var pb: Vector2 = pth.b
		if maxf(pa.x, pb.x) < bbp.position.x or minf(pa.x, pb.x) > bbp.end.x or maxf(pa.y, pb.y) < bbp.position.y or minf(pa.y, pb.y) > bbp.end.y:
			continue
		if WorldLayout.seg_poly_distance(pa, pb, poly) < float(pth.width) * 0.5 + 2.0:
			return false
	var inside := 0
	var woods := 0
	var total := 0
	var y := bb.position.y + 1.0
	while y < bb.end.y:
		var x := bb.position.x + 1.0
		while x < bb.end.x:
			var q := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(q, poly):
				total += 1
				var z := layout.zone_at(q)
				if z == WorldLayout.Zone.FIELD:
					inside += 1
				elif z == WorldLayout.Zone.WOODS or z == WorldLayout.Zone.WATER:
					woods += 1
			x += 5.0
		y += 5.0
	if not (total > 0 and float(inside) / total >= 0.35 and float(woods) / total <= 0.12):
		_rej("field_zone")
		return false
	return true


# --- Fences ------------------------------------------------------------------------------------------

## Lot-local fence runs (front edge = y 0) → world.
func _fence_local(lot: Dictionary, a: Vector2, b: Vector2, kind: StringName) -> void:
	if a.distance_to(b) > 1.0:
		layout.fences.append({"a": _lw(lot, a), "b": _lw(lot, b), "kind": kind})


func _place_fences() -> void:
	var r := _rng("fences")
	for lot in layout.lots:
		var use := StringName(lot.use)
		var w: float = (lot.size as Vector2).x - 0.3
		var d: float = (lot.size as Vector2).y - 0.3
		var i0 := 0.3
		if use == &"house":
			var kind: StringName = &"wood" if r.randf() < 0.7 else &"hedge"
			if r.randf() < 0.75:
				_fence_local(lot, Vector2(i0, d), Vector2(w, d), kind)
			if r.randf() < 0.6:
				var x := i0 if r.randf() < 0.5 else w
				var dl: Array = lot.get("driveway_local", [-99.0, 0.0])
				if absf(float(dl[0]) - x) > 3.0:
					_fence_local(lot, Vector2(x, 6.0), Vector2(x, d), kind)
		elif use == &"warehouse":
			_fence_local(lot, Vector2(i0, i0 + 0.0), Vector2(i0, d), &"wire")
			_fence_local(lot, Vector2(i0, d), Vector2(w, d), &"wire")
			_fence_local(lot, Vector2(w, d), Vector2(w, i0), &"wire")
		elif use == &"farmstead":
			_fence_local(lot, Vector2(i0, i0), Vector2(i0, d), &"wood")
			_fence_local(lot, Vector2(i0, d), Vector2(w, d), &"wood")
			_fence_local(lot, Vector2(w, d), Vector2(w, i0), &"wood")
			_fence_local(lot, Vector2(i0, i0), Vector2(21.0, i0), &"wood")
			_fence_local(lot, Vector2(27.0, i0), Vector2(w, i0), &"wood")
	for fl in layout.fields:
		if r.randf() > 0.55 and String(fl.farm) == "":
			continue
		var s: Vector2 = fl.size
		var corners := [Vector2(-0.8, -0.8), Vector2(s.x + 0.8, -0.8), Vector2(s.x + 0.8, s.y + 0.8), Vector2(-0.8, s.y + 0.8)]
		var gate_side := r.randi_range(0, 3)
		var xf: Transform2D = fl.xf
		for side in 4:
			var a: Vector2 = xf * (corners[side] as Vector2)
			var b: Vector2 = xf * (corners[(side + 1) % 4] as Vector2)
			if side == gate_side:
				var mid := (a + b) * 0.5
				var dir := (b - a).normalized()
				layout.fences.append({"a": a, "b": mid - dir * 2.5, "kind": &"wire"})
				layout.fences.append({"a": mid + dir * 2.5, "b": b, "kind": &"wire"})
			else:
				layout.fences.append({"a": a, "b": b, "kind": &"wire"})


# --- Props --------------------------------------------------------------------------------------------

func _near_junction(pt: Vector2, dist: float) -> bool:
	for j in layout.junctions:
		if j.distance_to(pt) < dist:
			return true
	return false


func _near_driveway(pt: Vector2, dist: float) -> bool:
	for pth in layout.paths:
		if pth.get("kind", &"") == &"driveway" and pth.has("a"):
			if Geometry2D.get_closest_point_to_segment(pt, pth.a, pth.b).distance_to(pt) < float(pth.width) * 0.5 + dist:
				return true
	return false


func _place_props() -> void:
	var r := _rng("props")
	# Yard trash cans placed before a neighbour existed: drop any that
	# ended up in front of some door.
	for i in range(layout.props.size() - 1, -1, -1):
		var pr: Dictionary = layout.props[i]
		if pr.kind != &"trash":
			continue
		if _blocks_door(pr.pos, 1.2):
			layout.props.remove_at(i)
	# Street lamps along town streets, alternating sides; clear of
	# junctions (10 m) and driveways (2 m).
	for rd in layout.roads:
		if not String(rd.id).begins_with("town_"):
			continue
		var pts: PackedVector2Array = rd.points
		var off := float(rd.width) * 0.5 + float(rd.sidewalk) * 0.5
		var k := 0
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 0.001)
			var nrm := rot90(dir)
			var t := 12.0
			while t < len - 11.0:
				var sgn := 1.0 if k % 2 == 0 else -1.0
				var pos := a + dir * t + nrm * sgn * off
				k += 1
				t += 26.0
				if _near_junction(pos, 10.0) or _near_driveway(pos, 2.0) or _blocks_door(pos, 1.3):
					continue
				layout.props.append({"kind": &"lamp", "pos": pos, "yaw": 0.0})
	# Utility poles along the rural roads (one side, every 36 m).
	for rd2 in layout.roads:
		if not (rd2.kind in [&"highway", &"county"]):
			continue
		var pts2: PackedVector2Array = rd2.points
		var side := 1.0 if r.randf() < 0.5 else -1.0
		var acc := 18.0
		for i in range(pts2.size() - 1):
			var a2 := pts2[i]
			var b2 := pts2[i + 1]
			var len2 := a2.distance_to(b2)
			var dir2 := (b2 - a2) / maxf(len2, 0.001)
			var t2 := acc
			while t2 < len2:
				var pos2 := a2 + dir2 * t2 + rot90(dir2) * side * (float(rd2.width) * 0.5 + 1.8)
				if not _in_reserve(pos2, 2.0) and _road_gap(pos2) > 0.9 and not _near_driveway(pos2, 2.0) \
						and not _near_junction(pos2, 8.0) and not _water_at(pos2) and not _blocks_door(pos2, 1.3):
					layout.props.append({"kind": &"pole", "pos": pos2, "yaw": atan2(dir2.x, dir2.y)})
				t2 += 36.0
			acc = t2 - len2
	# Benches / bins in front of shops; pumps + canopy at the gas station.
	for lot in layout.lots:
		var use := StringName(lot.use)
		if use in [&"convenience_store", &"diner", &"pharmacy", &"hardware_store", &"bar", &"post_office"] and lot.settlement == "town":
			var b := layout.building(String(lot.id))
			if b.is_empty():
				continue
			var dx: float = b.door_x
			var w: float = (lot.size as Vector2).x
			for spec in [[&"bench", 3.2], [&"trash", -2.2]]:
				var x := dx + float(spec[1])
				if x < 1.2 or x > w - 1.2:
					x = dx - float(spec[1])
				if x < 1.2 or x > w - 1.2 or _blocks_door(_lw(lot, Vector2(x, 0.45)), 1.2):
					continue
				layout.props.append({"kind": spec[0], "pos": _lw(lot, Vector2(x, 0.45)), "yaw": _yaw_toward(lot.front_dir)})
		elif use == &"gas_station" and lot.has("canopy_local"):
			var cl: Rect2 = lot.canopy_local
			var cxf: Transform2D = (lot.xf as Transform2D) * Transform2D(0.0, cl.position)
			layout.props.append({"kind": &"canopy", "pos": cxf * (cl.size * 0.5), "yaw": _yaw_toward(lot.front_dir),
				"size": Vector2(cl.size.x, cl.size.y), "xf": cxf})
			for i in 2:
				for j in 2:
					var lp := cl.position + Vector2(cl.size.x * (0.25 + 0.5 * i), cl.size.y * 0.5 + (float(j) - 0.5) * 3.4)
					layout.props.append({"kind": &"pump", "pos": _lw(lot, lp), "yaw": _yaw_toward(lot.front_dir),
						"id": "%s/pump_%d" % [lot.id, i * 2 + j + 1]})


# --- Vehicles -----------------------------------------------------------------------------------------

func _rej(k: String) -> void:
	layout.stats["rej_" + k] = int(layout.stats.get("rej_" + k, 0)) + 1


func _vehicle_id(r: RandomNumberGenerator, rural: bool) -> StringName:
	var total := 0.0
	for k in VEHICLE_WEIGHTS:
		if rural and k == &"police_sedan":
			continue
		total += VEHICLE_WEIGHTS[k]
	var x := r.randf() * total
	for k in VEHICLE_WEIGHTS:
		if rural and k == &"police_sedan":
			continue
		x -= VEHICLE_WEIGHTS[k]
		if x <= 0.0:
			return k
	return &"sedan"


func _dims(id: StringName) -> Vector2:
	if not _vdims.has(id):
		var d := load("res://data/vehicles/%s.tres" % id) as VehicleData
		_vdims[id] = Vector2(d.width, d.length) if d != null else Vector2(1.9, 5.0)
	return _vdims[id]


## Vehicle [id] at [pos] with [yaw] if its footprint is clear of
## buildings, fences, props, other vehicles (and [extra] polygons).
func _try_vehicle(r: RandomNumberGenerator, pos: Vector2, yaw: float, rural: bool, kind: StringName = &"",
		check_sidewalk: bool = true) -> bool:
	var id := kind if kind != &"" else _vehicle_id(r, rural)
	var dm := _dims(id)
	var v := {"data": id, "pos": pos, "yaw": yaw, "seed": (r.randi() % 997) + 1, "length": dm.y, "width": dm.x,
		"id": "veh_%03d" % (layout.vehicles.size() + 1)}
	var poly := WorldLayout.vehicle_poly(v, 0.3)
	if not _inside_world(poly, 2.0):
		_rej("veh_world")
		return false
	var bb := WorldLayout.poly_aabb(poly)
	for b in layout.buildings:
		if (b.rect as Rect2).intersects(bb.grow(1.0)) and WorldLayout.polys_overlap(poly, _grow_poly(WorldLayout.poly_of(b), 0.5)):
			_rej("veh_building")
			return false
	for o in layout.vehicles:
		if (o.pos as Vector2).distance_to(pos) < 8.0 and WorldLayout.polys_overlap(poly, WorldLayout.vehicle_poly(o, 0.2)):
			_rej("veh_vehicle")
			return false
	for fe in layout.fences:
		var fa: Vector2 = fe.a
		var fb: Vector2 = fe.b
		if maxf(fa.x, fb.x) < bb.position.x - 1.0 or minf(fa.x, fb.x) > bb.end.x + 1.0 or maxf(fa.y, fb.y) < bb.position.y - 1.0 or minf(fa.y, fb.y) > bb.end.y + 1.0:
			continue
		if WorldLayout.seg_poly_distance(fa, fb, poly) < 0.15:
			_rej("veh_fence")
			return false
	for pr in layout.props:
		var pp: Vector2 = pr.pos
		if pp.distance_to(pos) < 6.0 and WorldLayout.seg_poly_distance(pp, pp, poly) < 0.8:
			_rej("veh_prop")
			return false
	# Keep every exterior door clear (2.5 m in front of it).
	for dp in _door_points():
		if dp[0].distance_to(pos) < 8.0 and WorldLayout.seg_poly_distance(dp[0], dp[1], poly) < 0.6:
			_rej("veh_door")
			return false
	if check_sidewalk:
		for e in _segments_near(bb.grow(10.0)):
			var rd: Dictionary = e[2]
			if float(rd.get("sidewalk", 0.0)) <= 0.0 or e[0] == e[1]:
				continue
			for q in WorldLayout.vehicle_poly(v):
				var dd := Geometry2D.get_closest_point_to_segment(q, e[0], e[1]).distance_to(q)
				if dd > float(rd.width) * 0.5 and dd < float(rd.width) * 0.5 + float(rd.sidewalk) + 0.1 \
						and layout.road_at(q).is_empty():
					_rej("veh_sidewalk")
					return false
	layout.vehicles.append(v)
	return true


var _doors_cache: Array = []


func _blocks_door(q: Vector2, clear: float) -> bool:
	for dp in _door_points():
		if (dp[0] as Vector2).distance_to(q) < 6.0 and Geometry2D.get_closest_point_to_segment(q, dp[0], dp[1]).distance_to(q) < clear:
			return true
	return false


## World [door, 2.5 m out] segments of every exterior door (all buildings).
func _door_points() -> Array:
	if _doors_cache.is_empty():
		for b in layout.buildings:
			var bxf: Transform2D = b.xf
			for e in BuildingPlanGenerator.exterior_doors(layout.plans[b.id]):
				var lp: Vector2 = e[0]
				var ln: Vector2 = e[1]
				_doors_cache.append([bxf * lp, bxf * (lp + ln * 2.5)])
	return _doors_cache


func _place_vehicles() -> void:
	var r := _rng("vehicles")
	# Kerb-side parking along town and hamlet streets: ≥ 6 m from
	# intersections, clear of driveway mouths, never overlapping.
	for rd in layout.roads:
		var is_hamlet_street := false
		for h in _hamlets:
			if rd.id == h.road:
				is_hamlet_street = true
		if rd.kind != &"street" and not is_hamlet_street:
			continue
		var pts: PackedVector2Array = rd.points
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			if is_hamlet_street and (_in_reserve(a, 0.0) == false and _in_reserve(b, 0.0) == false):
				continue
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 0.001)
			var nrm := rot90(dir)
			var t := 9.0
			while t < len - 9.0:
				if r.randf() < 0.2:
					var sgn := 1.0 if r.randf() < 0.5 else -1.0
					var pos := a + dir * t + nrm * sgn * (float(rd.width) * 0.5 - 1.2)
					var yaw := atan2(dir.x, dir.y) + (0.0 if sgn > 0 else PI)
					if not _near_junction(pos, 6.0 + 2.6) and not _near_driveway(pos, 3.0):
						_try_vehicle(r, pos, yaw + r.randf_range(-0.04, 0.04), rd.id.begins_with("town") == false)
				t += 7.0
	# Driveways.
	for lot in layout.lots:
		if lot.has("driveway_local") and r.randf() < 0.45:
			var dl: Array = lot.driveway_local
			var pos2 := _lw(lot, Vector2(float(dl[0]), 3.2))
			var fwd: Vector2 = -lot.front_dir if r.randf() < 0.5 else lot.front_dir
			_try_vehicle(r, pos2, atan2(fwd.x, fwd.y), lot.settlement != "town", &"", false)
	# Parking lots: perpendicular stalls 2.8 m wide in one or two rows.
	for pk in layout.parking:
		var s: Vector2 = pk.size
		var xf: Transform2D = pk.xf
		var n := int(s.x / 2.8)
		var rows := 2 if s.y >= 12.0 else 1
		pk["stalls"] = n * rows
		for row in rows:
			for i in n:
				if r.randf() > 0.4:
					continue
				var lp := Vector2((float(i) + 0.5) * 2.8 + (s.x - n * 2.8) * 0.5, 2.7 if row == 0 else s.y - 2.7)
				var fwd2 := xf.basis_xform(Vector2(0, 1) if row == 0 else Vector2(0, -1)).normalized()
				_try_vehicle(r, xf * lp, atan2(fwd2.x, fwd2.y) + r.randf_range(-0.06, 0.06), false, &"", false)
	# A pickup in every farm yard, a customer car at the gas station.
	for lot2 in layout.lots:
		if lot2.use == &"farmstead" and lot2.has("pickup_local"):
			var fwd3: Vector2 = lot2.front_dir
			_try_vehicle(r, _lw(lot2, lot2.pickup_local), atan2(fwd3.x, fwd3.y), true, &"pickup", false)
		elif lot2.use == &"gas_station" and lot2.has("canopy_local"):
			var cl: Rect2 = lot2.canopy_local
			var lat := (lot2.xf as Transform2D).x.normalized()
			_try_vehicle(r, _lw(lot2, cl.get_center()), atan2(lat.x, lat.y), false, &"", false)
	# Abandoned cars on the highway.
	for rd2 in layout.roads:
		if rd2.kind != &"highway":
			continue
		var pts2: PackedVector2Array = rd2.points
		for k in r.randi_range(1, 2):
			var i2 := r.randi_range(0, pts2.size() - 2)
			var a2 := pts2[i2]
			var b2 := pts2[i2 + 1]
			if a2.distance_to(b2) < 20.0:
				continue
			var mid := a2.lerp(b2, r.randf_range(0.3, 0.7))
			if _in_reserve(mid, 10.0) or _near_junction(mid, 12.0):
				continue
			var dir2 := (b2 - a2).normalized()
			_try_vehicle(r, mid + rot90(dir2) * r.randf_range(-2.0, 2.0), atan2(dir2.x, dir2.y) + r.randf_range(-0.5, 0.5), true)


# --- Trees ---------------------------------------------------------------------------------------------

func _place_trees() -> void:
	var r := _rng("trees")
	var s := p.tree_spacing
	var nx := int(layout.size.x / s)
	var nz := int(layout.size.y / s)
	var copse := FastNoiseLite.new()
	copse.seed = sub_seed(layout.world_seed, "copse")
	copse.frequency = 0.03
	var out := PackedFloat32Array()
	var mchance := p.meadow_tree_chance * (s * s) / (p.zone_cell * p.zone_cell)
	var mmax := mchance * 4.0
	_tree_grid.resize(_bw * _bh)
	_tree_grid.fill(0)
	var zc := p.zone_cell
	var zw := layout.zone_w
	var zh := layout.zone_h
	var zones := layout.zones
	var woods := WorldLayout.Zone.WOODS
	var meadow := WorldLayout.Zone.MEADOW
	for gz in nz:
		for gx in nx:
			var q := Vector2((gx + 0.5 + r.randf_range(-0.4, 0.4)) * s, (gz + 0.5 + r.randf_range(-0.4, 0.4)) * s)
			var roll := r.randf()
			var zone: int = zones[mini(int(q.y / zc), zh - 1) * zw + mini(int(q.x / zc), zw - 1)]
			if zone == woods:
				if roll >= 0.82:
					continue
			elif zone == meadow:
				if roll >= mmax or roll >= mchance * (4.0 if copse.get_noise_2dv(q) > 0.45 else 0.6):
					continue
			else:
				continue
			var bx := int(q.x / BLOCK_CELL)
			var bz := int(q.y / BLOCK_CELL)
			if bx >= _bw or bz >= _bh or _blocked[bz * _bw + bx] != 0:
				continue
			out.append_array([q.x, q.y, r.randf_range(0.8, 1.3), float(r.randi_range(0, 3))])
			_tree_grid[bz * _bw + bx] = 1
	# Yard trees, mostly behind the house (lot-local planning).
	for lot in layout.lots:
		if lot.use != &"house":
			continue
		var b := layout.building(String(lot.id))
		if b.is_empty():
			continue
		var loc: Rect2 = (b.local as Rect2).grow(2.5)
		var sz: Vector2 = lot.size
		var placed: Array[Vector2] = []
		for k in r.randi_range(0, 2):
			for attempt in 12:
				var lq := Vector2(r.randf_range(1.5, sz.x - 1.5), r.randf_range(1.5, sz.y - 1.5))
				if loc.has_point(lq) or (lq.y < loc.position.y and r.randf() < 0.7):
					continue
				var wq := _lw(lot, lq)
				if _near_path(wq, 2.0) or _near_fence(wq, 1.0):
					continue
				var ok := true
				for o in placed:
					if o.distance_to(wq) < 4.0:
						ok = false
				if not ok:
					continue
				placed.append(wq)
				out.append_array([wq.x, wq.y, r.randf_range(0.8, 1.1), float(r.randi_range(0, 3))])
				_mark_tree(wq)
				break
	layout.trees = out


func _mark_tree(q: Vector2) -> void:
	var bx := int(q.x / BLOCK_CELL)
	var bz := int(q.y / BLOCK_CELL)
	if bx >= 0 and bz >= 0 and bx < _bw and bz < _bh:
		_tree_grid[bz * _bw + bx] = 1


func _near_path(q: Vector2, margin: float) -> bool:
	for pth in layout.paths:
		if pth.has("xf"):
			if WorldLayout.rec_has_point(pth, q, margin):
				return true
		elif Geometry2D.get_closest_point_to_segment(q, pth.a, pth.b).distance_to(q) < float(pth.width) * 0.5 + margin:
			return true
	for v in layout.vehicles:
		if (v.pos as Vector2).distance_to(q) < 3.5:
			return true
	for pr in layout.props:
		if (pr.pos as Vector2).distance_to(q) < 1.5:
			return true
	return false


func _near_fence(q: Vector2, margin: float) -> bool:
	for fe in layout.fences:
		if Geometry2D.get_closest_point_to_segment(q, fe.a, fe.b).distance_to(q) < margin:
			return true
	return false


# --- Population ------------------------------------------------------------------------------------------

func _population() -> void:
	var r := _rng("zombies")
	var n := layout.chunks_x() * layout.chunks_z()
	layout.chunk_density.resize(n)
	for i in n:
		layout.chunk_density[i] = p.zombies_per_chunk_base
	for b in layout.buildings:
		var c := layout.chunk_of((b.rect as Rect2).get_center())
		var s := layout.settlement(String(b.settlement))
		var w := p.zombies_per_farm_building
		if s.get("kind", &"") == &"town":
			w = p.zombies_per_town_building
		elif s.get("kind", &"") == &"hamlet":
			w = p.zombies_per_hamlet_building
		layout.chunk_density[layout.chunk_index(c)] += w
	for cz in layout.chunks_z():
		for cx in layout.chunks_x():
			var rect := layout.chunk_rect(Vector2i(cx, cz))
			var woods := 0
			var tot := 0
			var y := rect.position.y + 4.0
			while y < rect.end.y:
				var x := rect.position.x + 4.0
				while x < rect.end.x:
					tot += 1
					if layout.zone_at(Vector2(x, y)) == WorldLayout.Zone.WOODS:
						woods += 1
					x += 8.0
				y += 8.0
			layout.chunk_density[layout.chunk_index(Vector2i(cx, cz))] *= 1.0 - 0.7 * float(woods) / maxf(tot, 1.0)
	var start := layout.spawn_point
	var sc := layout.chunk_of(start)
	var chunks := layout.chunks_around(sc, p.active_chunk_radius)
	var total_w := 0.0
	for c in chunks:
		total_w += layout.chunk_density[layout.chunk_index(c)]
	var want := p.active_zombies
	var alloc: Array[int] = []
	var assigned := 0
	var rema: Array = []
	for c in chunks:
		var exact := float(want) * layout.chunk_density[layout.chunk_index(c)] / maxf(total_w, 0.001)
		alloc.append(int(floor(exact)))
		assigned += int(floor(exact))
		rema.append([exact - floor(exact), alloc.size() - 1])
	rema.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for k in want - assigned:
		alloc[rema[k % rema.size()][1]] += 1
	var pts := PackedVector2Array()
	var carry := 0
	for ci in chunks.size():
		var rect := layout.chunk_rect(chunks[ci])
		var need := alloc[ci] + carry
		carry = 0
		for k in need:
			var ok := false
			for attempt in 50:
				var q := Vector2(r.randf_range(rect.position.x + 1.0, rect.end.x - 1.0), r.randf_range(rect.position.y + 1.0, rect.end.y - 1.0))
				if q.distance_to(start) < p.zombie_min_start_distance or not _zombie_ok(q):
					continue
				if layout.zone_at(q) == WorldLayout.Zone.WOODS and r.randf() < 0.7:
					continue
				pts.append(q)
				ok = true
				break
			if not ok:
				carry += 1
	layout.zombies = pts
	# Rural groups: hamlets and farms outside the start area.
	var rg := _rng("groups")
	for s2 in layout.settlements:
		var kind: StringName = s2.kind
		if kind == &"town":
			continue
		var center: Vector2 = s2.get("yard_center", s2.center)
		var cc := layout.chunk_of(center)
		if maxi(absi(cc.x - sc.x), absi(cc.y - sc.y)) <= p.active_chunk_radius:
			continue
		var cnt := rg.randi_range(p.hamlet_group_min, p.hamlet_group_max) if kind == &"hamlet" else rg.randi_range(p.farm_group_min, p.farm_group_max)
		var gp := PackedVector2Array()
		for k in cnt:
			for attempt in 40:
				var q2 := center + Vector2(rg.randf_range(-22.0, 22.0), rg.randf_range(-22.0, 22.0))
				if _zombie_ok(q2):
					gp.append(q2)
					break
		if not gp.is_empty():
			layout.zombie_groups.append({"id": "group_%s" % s2.id, "chunk": layout.chunk_of(gp[0]), "points": gp})


## Outdoors, dry, not in a building / tree / fence / vehicle.
func _zombie_ok(q: Vector2) -> bool:
	if q.x < 2.0 or q.y < 2.0 or q.x > layout.size.x - 2.0 or q.y > layout.size.y - 2.0:
		return false
	if layout.zone_at(q) == WorldLayout.Zone.WATER:
		return false
	for pd in layout.ponds:
		if q.distance_to(pd.center) < float(pd.radius) + 1.5:
			return false
	if not layout.building_at(q, 1.5).is_empty():
		return false
	for fe in layout.fences:
		if Geometry2D.get_closest_point_to_segment(q, fe.a, fe.b).distance_to(q) < 1.0:
			return false
	for v in layout.vehicles:
		if (v.pos as Vector2).distance_to(q) < 3.2:
			return false
	for pr in layout.props:
		if (pr.pos as Vector2).distance_to(q) < float(pr.get("radius", 0.8)) + 0.8:
			return false
	var c := Vector2i(int(q.x / BLOCK_CELL), int(q.y / BLOCK_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx := c.x + dx
			var cz := c.y + dz
			if cx >= 0 and cz >= 0 and cx < _bw and cz < _bh and _tree_grid[cz * _bw + cx] != 0:
				return false
	return true
