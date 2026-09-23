class_name WorldMapRenderer
extends RefCounted
## Renders a WorldLayout to an Image (Round 11): the in-game map overlay
## (M) and the verification PNGs (tests/tools/world_map_preview.gd).
## Pure: no nodes, no viewport — works headless.

const MEADOW := Color(0.55, 0.66, 0.4)
const WOODS := Color(0.23, 0.38, 0.2)
const FIELD := Color(0.7, 0.64, 0.42)
const WATER := Color(0.3, 0.47, 0.66)
const LOT := Color(0.6, 0.7, 0.45)
const FARMYARD := Color(0.62, 0.6, 0.42)
const TREE := Color(0.15, 0.28, 0.14)
const ROAD := {&"highway": Color(0.25, 0.25, 0.27), &"street": Color(0.33, 0.33, 0.35),
	&"county": Color(0.3, 0.3, 0.32), &"dirt": Color(0.52, 0.42, 0.3)}
const SIDEWALK := Color(0.66, 0.66, 0.62)
const LANE := Color(0.9, 0.78, 0.2)
const PARKING := Color(0.4, 0.4, 0.42)
const PATH := Color(0.62, 0.6, 0.55)
const DRIVEWAY := Color(0.45, 0.44, 0.42)
const FENCE := {&"wood": Color(0.42, 0.3, 0.2), &"hedge": Color(0.2, 0.36, 0.18), &"wire": Color(0.5, 0.5, 0.48)}
const BUILDING := {&"house": Color(0.62, 0.38, 0.3), &"farmhouse": Color(0.66, 0.44, 0.32),
	&"convenience_store": Color(0.3, 0.45, 0.66), &"hardware_store": Color(0.36, 0.5, 0.6),
	&"pharmacy": Color(0.4, 0.6, 0.62), &"diner": Color(0.62, 0.52, 0.28), &"gas_station": Color(0.85, 0.5, 0.2),
	&"warehouse": Color(0.42, 0.44, 0.48), &"barn": Color(0.62, 0.16, 0.14), &"bar": Color(0.5, 0.3, 0.5),
	&"church": Color(0.85, 0.85, 0.8), &"post_office": Color(0.3, 0.5, 0.75)}
const CROP := {&"corn": Color(0.52, 0.62, 0.26), &"wheat": Color(0.8, 0.72, 0.38), &"cabbage": Color(0.42, 0.6, 0.38),
	&"fallow": Color(0.5, 0.4, 0.28)}


## Render at [mpp] metres per pixel. [detail] draws trees, fences, cars.
static func render(layout: WorldLayout, mpp: float = 1.5, detail: bool = true) -> Image:
	var w := int(ceil(layout.size.x / mpp))
	var h := int(ceil(layout.size.y / mpp))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(MEADOW)
	# Zones.
	for y in h:
		for x in w:
			var wp := Vector2((x + 0.5) * mpp, (y + 0.5) * mpp)
			match layout.zone_at(wp):
				WorldLayout.Zone.WOODS:
					img.set_pixel(x, y, WOODS)
				WorldLayout.Zone.FIELD:
					img.set_pixel(x, y, MEADOW.lerp(FIELD, 0.12))
				WorldLayout.Zone.WATER:
					img.set_pixel(x, y, MEADOW)
	for pd in layout.ponds:
		_disc(img, pd.center, float(pd.radius), WATER, mpp)
	for lot in layout.lots:
		_poly(img, WorldLayout.poly_of(lot), LOT if lot.use != &"farmstead" else FARMYARD, mpp)
	for fl in layout.fields:
		var col: Color = CROP.get(StringName(fl.crop), FIELD)
		var xf: Transform2D = fl.xf
		var fs: Vector2 = fl.size
		_poly(img, WorldLayout.poly_of(fl), col.darkened(0.25), mpp)
		# Crop rows along the field's own axis.
		var step := 3.2
		if int(fl.axis) == 0:
			var z := 1.0
			while z < fs.y - 0.5:
				_line(img, xf * Vector2(1.0, z), xf * Vector2(fs.x - 1.0, z), 0.7, col, mpp)
				z += step
		else:
			var x2 := 1.0
			while x2 < fs.x - 0.5:
				_line(img, xf * Vector2(x2, 1.0), xf * Vector2(x2, fs.y - 1.0), 0.7, col, mpp)
				x2 += step
	for pk in layout.parking:
		_poly(img, WorldLayout.poly_of(pk), PARKING, mpp)
	for pth in layout.paths:
		if pth.has("xf"):
			_poly(img, WorldLayout.poly_of(pth), PARKING, mpp)
		else:
			_line(img, pth.a, pth.b, float(pth.width), DRIVEWAY if pth.kind == &"driveway" else PATH, mpp)
	# Roads: sidewalks, surface, then lane markings.
	for rd in layout.roads:
		if float(rd.sidewalk) > 0.0:
			_polyline(img, rd.points, float(rd.width) + 2.0 * float(rd.sidewalk), SIDEWALK, mpp)
			if rd.has("cap"):
				var e: Vector2 = (rd.points as PackedVector2Array)[(rd.points as PackedVector2Array).size() - 1]
				_disc(img, e, float(rd.cap) + float(rd.sidewalk), SIDEWALK, mpp)
	for rd in layout.roads:
		var rc: Color = ROAD.get(StringName(rd.kind), ROAD[&"street"])
		_polyline(img, rd.points, float(rd.width), rc, mpp)
		if rd.has("cap"):
			var e2: Vector2 = (rd.points as PackedVector2Array)[(rd.points as PackedVector2Array).size() - 1]
			_disc(img, e2, float(rd.cap), rc, mpp)
	if detail:
		for rd in layout.roads:
			if rd.kind == &"highway" or rd.kind == &"county":
				_polyline(img, rd.points, 0.35, LANE, mpp)
	if detail:
		var t := layout.trees
		for i in range(0, t.size(), 4):
			_disc(img, Vector2(t[i], t[i + 1]), 1.3 * t[i + 2], TREE if t[i + 3] < 3.0 else TREE.lightened(0.15), mpp)
		for fe in layout.fences:
			_line(img, fe.a, fe.b, 0.5 if fe.kind != &"hedge" else 0.9, FENCE.get(StringName(fe.kind), FENCE[&"wood"]), mpp)
	for b in layout.buildings:
		var col2: Color = BUILDING.get(StringName(b.kind), Color(0.5, 0.3, 0.3))
		var bp := WorldLayout.poly_of(b)
		_poly(img, bp, col2.darkened(0.35), mpp)
		_poly(img, WorldGenerator._grow_poly(bp, -maxf(mpp * 0.7, 0.4)), col2, mpp)
		_disc(img, b.door, 0.9, Color(0.95, 0.9, 0.7), mpp)
	for pr in layout.props:
		if pr.kind == &"canopy" and pr.has("xf"):
			_poly(img, WorldLayout.obb_poly(pr.xf, pr.size), Color(0.8, 0.8, 0.82), mpp)
		elif pr.kind == &"silo":
			_disc(img, pr.pos, float(pr.get("radius", 2.0)), Color(0.75, 0.75, 0.72), mpp)
	if detail:
		for v in layout.vehicles:
			_poly(img, WorldLayout.vehicle_poly(v), Color(0.75, 0.2, 0.2), mpp)
	return img


## Three layouts side by side with a gap (the 37_world_map evidence).
static func side_by_side(images: Array, gap: int = 8) -> Image:
	var w := 0
	var h := 0
	for im in images:
		w += (im as Image).get_width() + gap
		h = maxi(h, (im as Image).get_height())
	var out := Image.create(maxi(w - gap, 1), h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.1, 0.1, 0.1))
	var x := 0
	for im in images:
		out.blit_rect(im, Rect2i(Vector2i.ZERO, (im as Image).get_size()), Vector2i(x, 0))
		x += (im as Image).get_width() + gap
	return out


static func _rect(img: Image, r: Rect2, c: Color, mpp: float) -> void:
	var x0 := clampi(int(floor(r.position.x / mpp)), 0, img.get_width())
	var y0 := clampi(int(floor(r.position.y / mpp)), 0, img.get_height())
	var x1 := clampi(int(ceil(r.end.x / mpp)), 0, img.get_width())
	var y1 := clampi(int(ceil(r.end.y / mpp)), 0, img.get_height())
	if x1 > x0 and y1 > y0:
		img.fill_rect(Rect2i(x0, y0, x1 - x0, y1 - y0), c)


static func _poly(img: Image, poly: PackedVector2Array, col: Color, mpp: float) -> void:
	var bb := WorldLayout.poly_aabb(poly)
	var x0 := clampi(int(floor(bb.position.x / mpp)), 0, img.get_width() - 1)
	var x1 := clampi(int(ceil(bb.end.x / mpp)), 0, img.get_width() - 1)
	var y0 := clampi(int(floor(bb.position.y / mpp)), 0, img.get_height() - 1)
	var y1 := clampi(int(ceil(bb.end.y / mpp)), 0, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Geometry2D.is_point_in_polygon(Vector2((x + 0.5) * mpp, (y + 0.5) * mpp), poly):
				img.set_pixel(x, y, col)


static func _disc(img: Image, c: Vector2, rad: float, col: Color, mpp: float) -> void:
	var cx := c.x / mpp
	var cy := c.y / mpp
	var rp := maxf(rad / mpp, 0.5)
	for y in range(int(floor(cy - rp)), int(ceil(cy + rp)) + 1):
		for x in range(int(floor(cx - rp)), int(ceil(cx + rp)) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= rp:
				img.set_pixel(x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, col: Color, mpp: float) -> void:
	var half := maxf(width * 0.5, mpp * 0.5)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(half, half)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(half, half)
	var x0 := clampi(int(floor(lo.x / mpp)), 0, img.get_width() - 1)
	var x1 := clampi(int(ceil(hi.x / mpp)), 0, img.get_width() - 1)
	var y0 := clampi(int(floor(lo.y / mpp)), 0, img.get_height() - 1)
	var y1 := clampi(int(ceil(hi.y / mpp)), 0, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var wp := Vector2((x + 0.5) * mpp, (y + 0.5) * mpp)
			if Geometry2D.get_closest_point_to_segment(wp, a, b).distance_to(wp) <= half:
				img.set_pixel(x, y, col)


static func _polyline(img: Image, pts: PackedVector2Array, width: float, col: Color, mpp: float) -> void:
	for i in range(pts.size() - 1):
		_line(img, pts[i], pts[i + 1], width, col, mpp)
