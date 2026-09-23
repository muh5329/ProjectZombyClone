class_name WorldLayoutValidator
extends RefCounted
## Invariants of a generated WorldLayout (Round 11) — what the unit tests
## and scripts/worldgen_sweep.sh assert on many seeds. Each check returns
## a list of problems ([] = fine):
##   overlap_problems      buildings / lots / fields / parking vs each
##                         other, roads (+ sidewalks), water, the world
##                         edge; trees vs roads / buildings / water / fences
##   road_problems         crossings without a shared vertex, roads running
##                         on top of each other, roads in water
##   vehicle_problems      rotated vehicle boxes vs buildings, fences,
##                         other vehicles, sidewalks, water
##   prop_problems         lamps near driveways, props on driveways /
##                         doorways / roads, mailboxes on the driveway side
##   connectivity_problems one road network (shared vertices) reaching
##                         every building's access point through a walk
##                         path that crosses no building, fence or water
##   door_problems         every front door on the building side facing
##                         its road
##   content_problems      required building kinds, settlement counts,
##                         zone ratios, spawn, population
##   plan_problems         BuildingPlan.validate() + generator check()

const EPS := 0.05


static func all_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	out.append_array(overlap_problems(layout))
	out.append_array(road_problems(layout))
	out.append_array(vehicle_problems(layout))
	out.append_array(prop_problems(layout))
	out.append_array(connectivity_problems(layout))
	out.append_array(door_problems(layout))
	out.append_array(content_problems(layout))
	out.append_array(plan_problems(layout))
	return out


## Fast subset for sweeps (no plan checks).
static func layout_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	out.append_array(overlap_problems(layout))
	out.append_array(road_problems(layout))
	out.append_array(vehicle_problems(layout))
	out.append_array(prop_problems(layout))
	out.append_array(connectivity_problems(layout))
	out.append_array(door_problems(layout))
	out.append_array(content_problems(layout))
	return out


# --- Spatial index of road segments --------------------------------------------------------

class RoadIndex:
	extends RefCounted
	const BIN := 32.0
	var bins: Dictionary = {}

	func _init(layout: WorldLayout) -> void:
		var uid := 0
		for rd in layout.roads:
			var pts: PackedVector2Array = rd.points
			var reach := float(rd.width) * 0.5 + float(rd.sidewalk) + float(rd.get("cap", 0.0))
			for i in range(pts.size() - 1):
				_add(pts[i], pts[i + 1], rd, reach, uid)
				uid += 1
			if rd.has("cap"):
				_add(pts[pts.size() - 1], pts[pts.size() - 1], rd, reach, uid)
				uid += 1

	func _add(a: Vector2, b: Vector2, rd: Dictionary, reach: float, uid: int) -> void:
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(reach, reach)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(reach, reach)
		for bz in range(int(floor(lo.y / BIN)), int(floor(hi.y / BIN)) + 1):
			for bx in range(int(floor(lo.x / BIN)), int(floor(hi.x / BIN)) + 1):
				var k := Vector2i(bx, bz)
				if not bins.has(k):
					bins[k] = []
				bins[k].append([a, b, rd, uid])

	func near(bb: Rect2) -> Array:
		var out: Array = []
		var seen := {}
		for bz in range(int(floor(bb.position.y / BIN)), int(floor(bb.end.y / BIN)) + 1):
			for bx in range(int(floor(bb.position.x / BIN)), int(floor(bb.end.x / BIN)) + 1):
				for e in bins.get(Vector2i(bx, bz), []):
					if not seen.has(e[3]):
						seen[e[3]] = true
						out.append(e)
		return out

	## Smallest (distance − needed clearance) from [poly] to any road;
	## need = half width + sidewalk (turning circles: cap radius).
	func clearance(poly: PackedVector2Array, with_sidewalk: bool = true) -> Array:
		var best := INF
		var who := ""
		for e in near(WorldLayout.poly_aabb(poly).grow(16.0)):
			var rd: Dictionary = e[2]
			var sw := float(rd.sidewalk) if with_sidewalk else 0.0
			var need := float(rd.width) * 0.5 + sw
			if e[0] == e[1]:
				need = float(rd.get("cap", 0.0)) + sw
			var d := WorldLayout.seg_poly_distance(e[0], e[1], poly) - need
			if d < best:
				best = d
				who = String(rd.id)
		return [best, who]

	## Road surface (no sidewalk) under [p] within [extra] m ("" = none).
	func road_at(p: Vector2, extra: float = 0.0) -> String:
		for e in near(Rect2(p, Vector2.ZERO).grow(12.0)):
			var rd: Dictionary = e[2]
			var half := float(rd.width) * 0.5 if e[0] != e[1] else float(rd.get("cap", 0.0))
			if Geometry2D.get_closest_point_to_segment(p, e[0], e[1]).distance_to(p) <= half + extra:
				return String(rd.id)
		return ""


# --- Overlaps ----------------------------------------------------------------------------

static func overlap_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	var idx := RoadIndex.new(layout)
	var bpolys: Array = []
	for b in layout.buildings:
		bpolys.append(WorldLayout.poly_of(b))
	for i in layout.buildings.size():
		var b: Dictionary = layout.buildings[i]
		var poly: PackedVector2Array = bpolys[i]
		for q in poly:
			if q.x < 0.0 or q.y < 0.0 or q.x > layout.size.x or q.y > layout.size.y:
				out.append("building %s outside the world" % b.id)
				break
		for j in range(i + 1, layout.buildings.size()):
			if WorldLayout.polys_overlap(poly, bpolys[j]):
				out.append("buildings %s and %s overlap" % [b.id, layout.buildings[j].id])
		var cl: Array = idx.clearance(poly)
		if float(cl[0]) < -EPS:
			out.append("building %s on road %s (%.2f m)" % [b.id, cl[1], cl[0]])
		for pd in layout.ponds:
			if WorldLayout.seg_poly_distance(pd.center, pd.center, poly) < float(pd.radius):
				out.append("building %s in water" % b.id)
		var lot := layout.lot(String(b.lot))
		if lot.is_empty():
			out.append("building %s has no lot" % b.id)
		else:
			for q2 in poly:
				if not WorldLayout.rec_has_point(lot, q2, EPS):
					out.append("building %s not inside its lot" % b.id)
					break
	var lpolys: Array = []
	for l in layout.lots:
		lpolys.append(WorldLayout.poly_of(l))
	for i in layout.lots.size():
		var lp: PackedVector2Array = lpolys[i]
		for q in lp:
			if q.x < 0.0 or q.y < 0.0 or q.x > layout.size.x or q.y > layout.size.y:
				out.append("lot %s outside the world" % layout.lots[i].id)
				break
		for j in range(i + 1, layout.lots.size()):
			if WorldLayout.polys_overlap(lp, lpolys[j], 0.05):
				out.append("lots %s and %s overlap" % [layout.lots[i].id, layout.lots[j].id])
		var cl2: Array = idx.clearance(lp)
		if float(cl2[0]) < -0.1:
			out.append("lot %s on road %s (%.2f m)" % [layout.lots[i].id, cl2[1], cl2[0]])
		for pd in layout.ponds:
			if WorldLayout.seg_poly_distance(pd.center, pd.center, lp) < float(pd.radius):
				out.append("lot %s in water" % layout.lots[i].id)
	for fi in layout.fields.size():
		var fl: Dictionary = layout.fields[fi]
		var fp := WorldLayout.poly_of(fl)
		for j in lpolys.size():
			if WorldLayout.polys_overlap(fp, lpolys[j]):
				out.append("field %s overlaps lot %s" % [fl.id, layout.lots[j].id])
		for fj in range(fi + 1, layout.fields.size()):
			if WorldLayout.polys_overlap(fp, WorldLayout.poly_of(layout.fields[fj])):
				out.append("fields %s and %s overlap" % [fl.id, layout.fields[fj].id])
		var cl3: Array = idx.clearance(fp, false)
		if float(cl3[0]) < 0.0:
			out.append("field %s on road %s" % [fl.id, cl3[1]])
		for pd in layout.ponds:
			if WorldLayout.seg_poly_distance(pd.center, pd.center, fp) < float(pd.radius):
				out.append("field %s in water" % fl.id)
	for pk in layout.parking:
		var pp := WorldLayout.poly_of(pk)
		for bp in bpolys:
			if WorldLayout.polys_overlap(pp, bp):
				out.append("parking of %s overlaps a building" % pk.lot)
	# Trees: never on a road surface, a building, water, a fence.
	var t := layout.trees
	var fence_bins := _fence_bins(layout)
	for i in range(0, t.size(), 4):
		var q := Vector2(t[i], t[i + 1])
		var hit := idx.road_at(q, 0.8)
		if hit != "":
			out.append("tree at %s on road %s" % [q, hit])
		if not layout.building_at(q, 0.5).is_empty():
			out.append("tree at %s in a building" % q)
		for pd in layout.ponds:
			if q.distance_to(pd.center) < float(pd.radius):
				out.append("tree at %s in water" % q)
		for fe in fence_bins.get(Vector2i(int(q.x / 16.0), int(q.y / 16.0)), []):
			if Geometry2D.get_closest_point_to_segment(q, fe.a, fe.b).distance_to(q) < 0.4:
				out.append("tree at %s on a fence" % q)
				break
	return out


static func _fence_bins(layout: WorldLayout) -> Dictionary:
	var bins := {}
	for fe in layout.fences:
		var a: Vector2 = fe.a
		var b: Vector2 = fe.b
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(2, 2)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(2, 2)
		for bz in range(int(lo.y / 16.0), int(hi.y / 16.0) + 1):
			for bx in range(int(lo.x / 16.0), int(hi.x / 16.0) + 1):
				var k := Vector2i(bx, bz)
				if not bins.has(k):
					bins[k] = []
				bins[k].append(fe)
	return bins


# --- Roads -------------------------------------------------------------------------------

static func _is_vertex(pts: PackedVector2Array, q: Vector2, tol: float = 0.05) -> bool:
	for v in pts:
		if v.distance_to(q) < tol:
			return true
	return false


static func road_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	var roads := layout.roads
	for i in roads.size():
		var a: Dictionary = roads[i]
		var ap: PackedVector2Array = a.points
		var abb := WorldLayout.poly_aabb(ap).grow(12.0)
		for pd in layout.ponds:
			var c: Vector2 = pd.center
			for k in range(ap.size() - 1):
				if Geometry2D.get_closest_point_to_segment(c, ap[k], ap[k + 1]).distance_to(c) < float(pd.radius) + float(a.width) * 0.5:
					out.append("road %s runs through water" % a.id)
					break
		for j in range(i + 1, roads.size()):
			var b: Dictionary = roads[j]
			var bp: PackedVector2Array = b.points
			if not abb.intersects(WorldLayout.poly_aabb(bp)):
				continue
			# Shared vertices = junctions between these two.
			var shared: Array[Vector2] = []
			for v in ap:
				if _is_vertex(bp, v, 0.01):
					shared.append(v)
			for k in range(ap.size() - 1):
				for m in range(bp.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(ap[k], ap[k + 1], bp[m], bp[m + 1])
					if hit == null:
						continue
					var h: Vector2 = hit
					var ok := false
					for sv in shared:
						if sv.distance_to(h) < 0.05:
							ok = true
					if not ok:
						out.append("roads %s and %s cross at %s without a junction" % [a.id, b.id, h])
			# Running on top of each other away from their junctions.
			var need := (float(a.width) + float(b.width)) * 0.5
			var near_count := 0
			for k in range(ap.size() - 1):
				var seg_len := ap[k].distance_to(ap[k + 1])
				var steps := maxi(1, int(seg_len / 4.0))
				for s in steps + 1:
					var q := ap[k].lerp(ap[k + 1], float(s) / steps)
					var far_from_j := true
					for sv in shared:
						if sv.distance_to(q) < need + 12.0:
							far_from_j = false
					if not far_from_j:
						continue
					if WorldLayout.distance_to_road(q, b) < need:
						near_count += 1
			if near_count >= 2:
				out.append("roads %s and %s run on top of each other (%d samples)" % [a.id, b.id, near_count])
	return out


# --- Vehicles ----------------------------------------------------------------------------

## [door point, point [out] m outside, label] of every exterior door
## (plans needed; none when the layout carries no plans).
static func exterior_door_segments(layout: WorldLayout, out_m: float) -> Array:
	var res: Array = []
	for b in layout.buildings:
		var plan: BuildingPlan = layout.plans.get(b.id)
		if plan == null:
			continue
		var bxf: Transform2D = b.xf
		for e in BuildingPlanGenerator.exterior_doors(plan):
			var lp: Vector2 = e[0]
			var ln: Vector2 = e[1]
			res.append([bxf * lp, bxf * (lp + ln * out_m), "%s@%s" % [b.id, lp]])
	return res


static func vehicle_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	var idx := RoadIndex.new(layout)
	var vpolys: Array = []
	for v in layout.vehicles:
		vpolys.append(WorldLayout.vehicle_poly(v))
	var doors := exterior_door_segments(layout, 2.0)
	for i in layout.vehicles.size():
		var v: Dictionary = layout.vehicles[i]
		var vp: PackedVector2Array = vpolys[i]
		var bb := WorldLayout.poly_aabb(vp)
		for b in layout.buildings:
			if (b.rect as Rect2).intersects(bb) and WorldLayout.polys_overlap(vp, WorldLayout.poly_of(b)):
				out.append("vehicle %s overlaps building %s" % [v.id, b.id])
		for j in range(i + 1, layout.vehicles.size()):
			if (layout.vehicles[j].pos as Vector2).distance_to(v.pos) < 7.0 and WorldLayout.polys_overlap(vp, vpolys[j]):
				out.append("vehicles %s and %s overlap" % [v.id, layout.vehicles[j].id])
		for fe in layout.fences:
			if WorldLayout.seg_poly_distance(fe.a, fe.b, vp) <= 0.0:
				out.append("vehicle %s on a fence" % v.id)
				break
		for pd in layout.ponds:
			if WorldLayout.seg_poly_distance(pd.center, pd.center, vp) < float(pd.radius):
				out.append("vehicle %s in water" % v.id)
		for dseg in doors:
			if (dseg[0] as Vector2).distance_to(v.pos) < 8.0 and WorldLayout.seg_poly_distance(dseg[0], dseg[1], vp) < 0.3:
				out.append("vehicle %s blocks door %s" % [v.id, dseg[2]])
		# A corner on a sidewalk (outside any road surface and any lot).
		for q in vp:
			if idx.road_at(q) != "":
				continue
			var in_lot := false
			for l in layout.lots:
				if (l.rect as Rect2).has_point(q) and WorldLayout.rec_has_point(l, q, 0.3):
					in_lot = true
					break
			if in_lot:
				continue
			for e in idx.near(Rect2(q, Vector2.ZERO).grow(10.0)):
				var rd: Dictionary = e[2]
				if float(rd.sidewalk) <= 0.0 or e[0] == e[1]:
					continue
				var d := Geometry2D.get_closest_point_to_segment(q, e[0], e[1]).distance_to(q)
				if d > float(rd.width) * 0.5 and d < float(rd.width) * 0.5 + float(rd.sidewalk):
					out.append("vehicle %s on the sidewalk of %s" % [v.id, rd.id])
					break
	return out


# --- Props ---------------------------------------------------------------------------------

static func prop_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	var drives: Array = []
	for pth in layout.paths:
		if pth.get("kind", &"") == &"driveway" and pth.has("a"):
			drives.append(pth)
	var idx := RoadIndex.new(layout)
	var doors := exterior_door_segments(layout, 1.5)
	for pr in layout.props:
		var q: Vector2 = pr.pos
		var kind := StringName(pr.kind)
		if kind in [&"canopy"]:
			continue
		for dseg in doors:
			if (dseg[0] as Vector2).distance_to(q) < 4.0 and Geometry2D.get_closest_point_to_segment(q, dseg[0], dseg[1]).distance_to(q) < 0.8:
				out.append("%s at %s blocks door %s" % [kind, q, dseg[2]])
		for dw in drives:
			var d := Geometry2D.get_closest_point_to_segment(q, dw.a, dw.b).distance_to(q) - float(dw.width) * 0.5
			if kind == &"lamp" and d < 2.0:
				out.append("lamp at %s within 2 m of a driveway" % q)
			elif kind != &"lamp" and kind != &"pump" and d < 0.3:
				out.append("%s at %s on a driveway" % [kind, q])
		if kind != &"pump" and idx.road_at(q, 0.2) != "":
			out.append("%s at %s on a road" % [kind, q])
		for b in layout.buildings:
			if (b.door as Vector2).distance_to(q) < 1.2:
				out.append("%s at %s blocks the door of %s" % [kind, q, b.id])
			if (b.rect as Rect2).grow(1.0).has_point(q) and WorldLayout.rec_has_point(b, q, float(pr.get("radius", 0.3))):
				out.append("%s at %s inside building %s" % [kind, q, b.id])
	# Mailboxes stand on the side of the front path away from the driveway.
	for lot in layout.lots:
		if not lot.has("driveway_local"):
			continue
		var b2 := layout.building(String(lot.id))
		if b2.is_empty():
			continue
		var inv := (lot.xf as Transform2D).affine_inverse()
		var dx: float = float((lot.driveway_local as Array)[0])
		for pr2 in layout.props:
			if pr2.kind != &"mailbox":
				continue
			var lq: Vector2 = inv * (pr2.pos as Vector2)
			if lq.y < -0.5 or lq.y > 1.5 or lq.x < -0.5 or lq.x > (lot.size as Vector2).x + 0.5:
				continue
			if signf(lq.x - float(b2.door_x)) == signf(dx - float(b2.door_x)):
				out.append("mailbox of %s on the driveway side" % lot.id)
	return out


# --- Connectivity --------------------------------------------------------------------------

## Union-find over road vertices: roads are chains; a road end lying on
## another road links them (junction vertices are shared exactly).
static func road_components(layout: WorldLayout) -> Dictionary:
	var parent := {}
	var find := func(k: String) -> String:
		var x := k
		while parent.get(x, x) != x:
			x = parent[x]
		return x
	var key := func(v: Vector2) -> String:
		return "%d,%d" % [roundi(v.x * 20.0), roundi(v.y * 20.0)]
	var union := func(a: String, b: String) -> void:
		var ra: String = find.call(a)
		var rb: String = find.call(b)
		if ra != rb:
			parent[ra] = rb
	for rd in layout.roads:
		var pts: PackedVector2Array = rd.points
		for i in pts.size():
			var k: String = key.call(pts[i])
			if not parent.has(k):
				parent[k] = k
			if i > 0:
				union.call(key.call(pts[i - 1]), k)
	for rd in layout.roads:
		var pts2: PackedVector2Array = rd.points
		for end in [pts2[0], pts2[pts2.size() - 1]]:
			for o in layout.roads:
				if o == rd:
					continue
				var op: PackedVector2Array = o.points
				for i in range(op.size() - 1):
					if Geometry2D.get_closest_point_to_segment(end, op[i], op[i + 1]).distance_to(end) < 0.05:
						union.call(key.call(end), key.call(op[i]))
	return {"parent": parent, "find": find, "key": key}


static func component_at(layout: WorldLayout, comps: Dictionary, p: Vector2) -> String:
	for rd in layout.roads:
		var pts: PackedVector2Array = rd.points
		for i in range(pts.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < 0.05:
				return comps.find.call(comps.key.call(pts[i]))
	return ""


static func connectivity_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	if layout.roads.is_empty():
		return ["no roads"]
	var comps := road_components(layout)
	var main_rd := layout.road("town_main")
	if main_rd.is_empty():
		main_rd = layout.roads[0]
	var main: String = comps.find.call(comps.key.call((main_rd.points as PackedVector2Array)[0]))
	for rd in layout.roads:
		var c: String = comps.find.call(comps.key.call((rd.points as PackedVector2Array)[0]))
		if c != main:
			out.append("road %s not connected to the network" % rd.id)
	var fences := _fence_bins(layout)
	for b in layout.buildings:
		var comp := component_at(layout, comps, b.access)
		if comp == "":
			out.append("building %s: access point %s is not on a road" % [b.id, b.access])
		elif comp != main:
			out.append("building %s on a disconnected road" % b.id)
		var path: PackedVector2Array = b.get("access_path", PackedVector2Array())
		if path.size() < 2 or path[0].distance_to(b.door) > 0.01 or path[path.size() - 1].distance_to(b.access) > 0.01:
			out.append("building %s: walk path does not join door and road" % b.id)
			continue
		for i in range(path.size() - 1):
			var a := path[i]
			var bb := path[i + 1]
			var seg_bb := Rect2(a, Vector2.ZERO).expand(bb).grow(1.0)
			for o in layout.buildings:
				if not (o.rect as Rect2).intersects(seg_bb):
					continue
				var shrunk := WorldGenerator._grow_poly(WorldLayout.poly_of(o), -0.15)
				if WorldLayout.seg_poly_distance(a, bb, shrunk) <= 0.0:
					out.append("building %s: walk path crosses building %s" % [b.id, o.id])
			var seen := {}
			for bz in range(int(seg_bb.position.y / 16.0), int(seg_bb.end.y / 16.0) + 1):
				for bx in range(int(seg_bb.position.x / 16.0), int(seg_bb.end.x / 16.0) + 1):
					for fe in fences.get(Vector2i(bx, bz), []):
						if seen.has(fe.hash()):
							continue
						seen[fe.hash()] = true
						if Geometry2D.segment_intersects_segment(a, bb, fe.a, fe.b) != null:
							out.append("building %s: walk path crosses a fence" % b.id)
			for pd in layout.ponds:
				if Geometry2D.get_closest_point_to_segment(pd.center, a, bb).distance_to(pd.center) < float(pd.radius):
					out.append("building %s: walk path crosses water" % b.id)
	for s in layout.settlements:
		var any := false
		for b in layout.buildings:
			if b.settlement == s.id:
				any = true
		if not any:
			out.append("settlement %s has no buildings" % s.id)
	return out


## Every door is on the plan's front wall (local y = D) and that wall
## faces the road.
static func door_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	for b in layout.buildings:
		var xf: Transform2D = b.xf
		var local := xf.affine_inverse() * (b.door as Vector2)
		var sz: Vector2 = b.size
		if absf(local.y - sz.y) > 0.05 or local.x < -0.05 or local.x > sz.x + 0.05:
			out.append("building %s: front door not on its front wall (%s)" % [b.id, local])
		var front := xf.basis_xform(Vector2(0, 1)).normalized()
		if front.dot(b.front_dir) < 0.99:
			out.append("building %s: front wall does not face its lot's road side" % b.id)
		var toward: Vector2 = (b.access_path as PackedVector2Array)[1] - (b.door as Vector2) if (b.access_path as PackedVector2Array).size() > 1 else Vector2.ZERO
		if toward.length() > 0.5 and toward.normalized().dot(front) < 0.3:
			out.append("building %s: door faces away from its road" % b.id)
	return out


## Required content (scaled with the world size).
static func content_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	var small := minf(layout.size.x, layout.size.y) < 600.0
	var town_houses := 0
	var town_lots := 0
	for l in layout.lots:
		if l.settlement == "town":
			town_lots += 1
	for b in layout.buildings:
		if b.kind == &"house" and b.settlement == "town":
			town_houses += 1
	if town_houses < (4 if small else 8):
		out.append("only %d houses in the town" % town_houses)
	if town_lots < (12 if small else 20) or town_lots > 60:
		out.append("town has %d lots" % town_lots)
	for k in [&"convenience_store", &"warehouse", &"gas_station", &"barn", &"farmhouse"]:
		if layout.buildings_of_kind(k).is_empty():
			out.append("no %s" % k)
	var farms := 0
	var hamlets := 0
	for s in layout.settlements:
		if s.kind == &"farmstead":
			farms += 1
		elif s.kind == &"hamlet":
			hamlets += 1
	if farms < (2 if small else 3):
		out.append("only %d farmsteads" % farms)
	if hamlets < 1:
		out.append("no hamlet")
	var z := layout.zone_ratios()
	if z[WorldLayout.Zone.WOODS] < 0.08 or z[WorldLayout.Zone.WOODS] > 0.55:
		out.append("woods ratio %.2f" % z[WorldLayout.Zone.WOODS])
	if z[WorldLayout.Zone.FIELD] < 0.08 or z[WorldLayout.Zone.FIELD] > 0.6:
		out.append("farmland ratio %.2f" % z[WorldLayout.Zone.FIELD])
	if z[WorldLayout.Zone.WATER] > 0.05:
		out.append("water ratio %.2f" % z[WorldLayout.Zone.WATER])
	var sb := layout.building(layout.spawn_building)
	if sb.is_empty() or not (sb.kind in [&"house", &"farmhouse"]):
		out.append("player does not start in a house")
	elif not WorldLayout.rec_has_point(sb, layout.spawn_point):
		out.append("spawn point outside the start house")
	if layout.zombies.size() < 30:
		out.append("only %d active zombies" % layout.zombies.size())
	for q in layout.zombies:
		if not layout.building_at(q).is_empty():
			out.append("zombie start %s inside a building" % q)
	return out


static func plan_problems(layout: WorldLayout) -> Array[String]:
	var out: Array[String] = []
	for id in layout.plans:
		var plan: BuildingPlan = layout.plans[id]
		var b := layout.building(String(id))
		if not b.is_empty() and not plan.footprint.is_equal_approx(b.size):
			out.append("plan %s footprint %s != building size %s" % [id, plan.footprint, b.size])
		for pr in plan.validate():
			out.append("plan %s: %s" % [id, pr])
		for pr in BuildingPlanGenerator.check(plan):
			out.append("plan %s: %s" % [id, pr])
	return out
