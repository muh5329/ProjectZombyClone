class_name VehicleBuilder
extends RefCounted
## Procedural low-poly 80s/90s American vehicles (fully owned geometry):
## the lower body is the side profile (with real wheel arches) extruded
## across the width, the greenhouse a tapered extrusion with dark glass and
## body-colour pillars, plus wheels with hubcaps, bumpers, grille, head /
## tail lights, plates, mirrors and livery parts (police doors, fire
## stripes, light bars, pickup bed and lockers). Flat-shaded, vertex
## coloured; a few surfaces so glass and lights get their own materials:
## SURFACES (body, glass, head, tail, beacon_a, beacon_b — only non-empty
## ones are committed; mesh meta "surfaces" maps name → index).
##
## Pure (no scene tree): a parked Vehicle and a future VehicleBody3D build
## the same mesh from (VehicleData, seed). Faces -Z; origin on the ground
## at the centre.

const SURFACES: Array[StringName] = [&"body", &"glass", &"head", &"tail", &"beacon_a", &"beacon_b"]
const ROCKER := 0.3
const GLASS := Color(0.12, 0.15, 0.19)
const TYRE := Color(0.07, 0.07, 0.07)
const HUBCAP := Color(0.68, 0.69, 0.7)
const RUST := Color(0.42, 0.21, 0.09)
const RUST_DARK := Color(0.3, 0.16, 0.08)
## Upper band of the windows (sky reflection).
const GLASS_TOP := Color(0.28, 0.32, 0.36)
## Body paint is muted like PZ: saturation ×0.75, value ≤ 0.75.
const PAINT_SATURATION := 0.75
const PAINT_MAX_VALUE := 0.75
## Road dirt on the lowest part of the body.
const DIRT_HEIGHT := 0.35
const DIRT_DARKEN := 0.25
const HEADLIGHT := Color(0.95, 0.92, 0.78)
const TAILLIGHT := Color(0.62, 0.04, 0.04)
const DARK := Color(0.1, 0.1, 0.11)
const PLATE := Color(0.92, 0.9, 0.78)

var data: VehicleData
var variation: Dictionary
var _st: Dictionary = {}
## True while emitting wheels: no paint / dirt / sag.
var _plain: bool = false
## Flat tyre: that corner of the body sags by [_sag] (bilinear falloff).
var _sag: float = 0.0
var _sag_corner: Vector2 = Vector2.ZERO
var _hl: float = 2.4
var _hw: float = 0.9
var _belt: float = 0.9
var _roof: float = 1.4
var _tris: Dictionary = {}


## Deterministic wear / colour for [seed_value]: {color, rust (0..1),
## flat (wheel index or -1), missing_hubcap (index or -1)}.
static func variation_for(d: VehicleData, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var col: Color = d.palette[rng.randi() % d.palette.size()] if not d.palette.is_empty() else Color.GRAY
	var rust := rng.randf_range(0.15, 0.55) if rng.randf() < d.rust_chance else 0.0
	var flat := rng.randi() % 4 if rng.randf() < d.flat_tire_chance else -1
	var hub := rng.randi() % 4 if rng.randf() < 0.3 else -1
	# Slight fade / dirt of the paint.
	col = col.darkened(rng.randf_range(0.0, 0.12))
	return {"color": col, "rust": rust, "flat": flat, "missing_hubcap": hub, "rust_seed": rng.randi()}


static func build_mesh(d: VehicleData, seed_value: int) -> ArrayMesh:
	var b := VehicleBuilder.new()
	return b._build(d, seed_value)


## Front and rear axle positions (z) for [d].
static func axles(d: VehicleData) -> Vector2:
	var front := -d.length * 0.5 + (d.length - d.wheelbase) * 0.45
	return Vector2(front, front + d.wheelbase)


## Collision box size (length along Z).
static func collision_size(d: VehicleData) -> Vector3:
	return Vector3(d.width, d.roof_height, d.length)


static func triangle_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


func _build(d: VehicleData, seed_value: int) -> ArrayMesh:
	data = d
	variation = variation_for(d, seed_value)
	for s in SURFACES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[s] = st
		_tris[s] = 0
	var body: Color = variation.color
	_hl = d.length * 0.5
	_hw = d.width * 0.5
	_belt = d.belt_height
	_roof = d.roof_height
	var ax0 := axles(d)
	var flat := int(variation.flat)
	if flat >= 0:
		_sag = d.wheel_radius * 0.14
		_sag_corner = Vector2(-1.0 if flat % 2 == 0 else 1.0, signf(ax0.x if flat < 2 else ax0.y))
	var hl := d.length * 0.5
	var hw := d.width * 0.5
	var belt := d.belt_height
	var roof := d.roof_height
	var ax := axles(d)
	var zc := Vector4(-hl + d.cabin.x * d.length, -hl + d.cabin.y * d.length, -hl + d.cabin.z * d.length, -hl + d.cabin.w * d.length)
	var roof_col := d.livery_color if d.livery in [&"police", &"fire"] else body
	# --- Lower body ---------------------------------------------------------------
	var top: Array[Vector2] = []
	top.append(Vector2(-hl + 0.07, belt - 0.12))
	if d.shape == &"van":
		top.append(Vector2(zc.x, belt))
	else:
		top.append(Vector2(zc.x, belt))
	var bed_z := -hl + d.bed_start * d.length
	var floor_y := belt - 0.42
	if d.shape == &"pickup":
		top.append(Vector2(bed_z, belt))
		top.append(Vector2(bed_z, floor_y))
		top.append(Vector2(hl - 0.03, floor_y))
	elif d.shape == &"sedan":
		top.append(Vector2(zc.w, belt))
		top.append(Vector2(hl - 0.08, belt - 0.03))
	else:
		top.append(Vector2(hl - 0.04, belt))
	var poly := PackedVector2Array()
	poly.append(Vector2(-hl + 0.06, ROCKER))
	poly.append(Vector2(-hl, 0.42))
	poly.append(Vector2(-hl, 0.66))
	for p in top:
		poly.append(p)
	var rear_top := top[top.size() - 1]
	poly.append(Vector2(hl, rear_top.y - 0.14 if d.shape != &"pickup" else floor_y - 0.02))
	poly.append(Vector2(hl, 0.42))
	poly.append(Vector2(hl - 0.06, ROCKER))
	for axle in [ax.y, ax.x]:
		for p in _arch(axle, d.wheel_radius):
			poly.append(p)
	_extrude(poly, hw, hw, body, &"body", [], true)
	_rust_patches(ax, d)
	# --- Pickup bed walls / cargo ----------------------------------------------------
	if d.shape == &"pickup":
		var bl := hl - bed_z
		var wh := belt - floor_y
		_box(Vector3(hw - 0.04, floor_y + wh * 0.5, bed_z + bl * 0.5), Vector3(0.08, wh, bl), body, &"body")
		_box(Vector3(-hw + 0.04, floor_y + wh * 0.5, bed_z + bl * 0.5), Vector3(0.08, wh, bl), body, &"body")
		_box(Vector3(0, floor_y + wh * 0.5, hl - 0.04), Vector3(d.width, wh, 0.08), body, &"body")
		_box(Vector3(0, floor_y + 0.005, bed_z + bl * 0.5), Vector3(d.width - 0.16, 0.01, bl - 0.08), DARK.lightened(0.12), &"body")
		if d.bed_boxes:
			# Equipment lockers along both bed walls + a red hose reel.
			for s in [-1.0, 1.0]:
				_box(Vector3(s * (hw - 0.3), floor_y + 0.3, bed_z + bl * 0.5), Vector3(0.38, 0.6, bl - 0.3), Color(0.78, 0.78, 0.76), &"body")
			_box(Vector3(0, floor_y + 0.2, bed_z + 0.4), Vector3(0.5, 0.4, 0.45), Color(0.75, 0.1, 0.07), &"body")
	# --- Greenhouse ------------------------------------------------------------------
	var gh := PackedVector2Array([Vector2(zc.x, belt), Vector2(zc.y, roof), Vector2(zc.z, roof), Vector2(zc.w, belt)])
	var side_col := body if d.shape == &"van" else GLASS
	var side_surface := &"body" if d.shape == &"van" else &"glass"
	# Edge colours: windshield, roof, rear window, (hidden bottom).
	var edges := [[GLASS, &"glass"], [roof_col, &"body"], [GLASS if d.shape != &"van" else body, &"glass" if d.shape != &"van" else &"body"], [body, &"body"]]
	_extrude(gh, hw - 0.07, hw - 0.2, side_col, side_surface, edges, false, belt, roof)
	var pillar_x := (hw - 0.07 + hw - 0.2) * 0.5
	var pillar_w := 0.16
	if d.shape == &"van":
		# Cab side windows only.
		var zw := lerpf(zc.y, zc.z, 0.12)
		for s in [-1.0, 1.0]:
			_box(Vector3(s * (pillar_x + 0.005), lerpf(belt, roof, 0.55), zw), Vector3(pillar_w, (roof - belt) * 0.6, 0.55), GLASS, &"glass")
	else:
		# B / C pillars in body colour.
		var zb := lerpf(zc.y, zc.z, 0.48 if d.shape != &"pickup" else 1.0)
		for s in [-1.0, 1.0]:
			if d.shape != &"pickup":
				_box(Vector3(s * pillar_x, (belt + roof) * 0.5, zb), Vector3(pillar_w, roof - belt, 0.09), roof_col, &"body")
			if d.shape == &"wagon":
				_box(Vector3(s * pillar_x, (belt + roof) * 0.5, lerpf(zc.y, zc.z, 0.78)), Vector3(pillar_w, roof - belt, 0.08), roof_col, &"body")
	# --- Livery ----------------------------------------------------------------------
	if d.livery == &"police":
		for s in [-1.0, 1.0]:
			_box(Vector3(s * (hw + 0.006), (0.42 + belt) * 0.5, (zc.x + zc.w) * 0.5 - 0.05), Vector3(0.012, belt - 0.46, zc.w - zc.x - 0.25), d.livery_color, &"body")
		_box(Vector3(0, 0.45, -hl - 0.12), Vector3(d.width * 0.55, 0.22, 0.06), DARK, &"body")
	elif d.livery == &"fire":
		for s in [-1.0, 1.0]:
			_box(Vector3(s * (hw + 0.006), belt - 0.1, 0.0 if d.shape != &"pickup" else (-hl + bed_z) * 0.5), Vector3(0.012, 0.07, d.length - 0.3 if d.shape != &"pickup" else bed_z + hl - 0.2), d.livery_color, &"body")
	if d.light_bar:
		var zl := (zc.y + zc.z) * 0.5 - 0.1
		_box(Vector3(0, roof + 0.03, zl), Vector3(0.9, 0.06, 0.24), DARK, &"body")
		var ca: Color = d.light_bar_colors[0] if d.light_bar_colors.size() > 0 else Color.RED
		var cb: Color = d.light_bar_colors[1] if d.light_bar_colors.size() > 1 else ca
		_box(Vector3(-0.23, roof + 0.1, zl), Vector3(0.42, 0.1, 0.2), ca, &"beacon_a")
		_box(Vector3(0.23, roof + 0.1, zl), Vector3(0.42, 0.1, 0.2), cb, &"beacon_b")
	# --- Front / rear details ------------------------------------------------------------
	_box(Vector3(0, 0.44, -hl - 0.03), Vector3(d.width + 0.04, 0.16, 0.1), d.trim_color, &"body")
	_box(Vector3(0, 0.44, hl + 0.03), Vector3(d.width + 0.04, 0.16, 0.1), d.trim_color, &"body")
	_box(Vector3(0, 0.63, -hl - 0.01), Vector3(d.width - 0.85, 0.15, 0.02), DARK, &"body")
	for s in [-1.0, 1.0]:
		_box(Vector3(s * (hw - 0.24), 0.63, -hl - 0.012), Vector3(0.3, 0.13, 0.025), HEADLIGHT, &"head")
		var ty := 0.66 if d.shape != &"pickup" else floor_y - 0.12
		_box(Vector3(s * (hw - 0.18), ty, hl + 0.012), Vector3(0.26, 0.13, 0.025), TAILLIGHT, &"tail")
		# Mirrors.
		_box(Vector3(s * (hw + 0.05), belt + 0.08, zc.x + 0.12), Vector3(0.07, 0.08, 0.12), body, &"body")
	_box(Vector3(0, 0.58 if d.shape != &"pickup" else floor_y - 0.12, hl + 0.012), Vector3(0.3, 0.15, 0.02), PLATE, &"body")
	# --- Wheels ----------------------------------------------------------------------
	var wi := 0
	_plain = true
	for z in [ax.x, ax.y]:
		for s in [-1.0, 1.0]:
			var r := d.wheel_radius
			if int(variation.flat) == wi:
				r -= _sag
			# Every wheel touches the ground (the flat one is just smaller;
			# its corner of the body sags instead).
			var cy := r
			var cx: float = s * (hw - 0.1)
			_cylinder_x(Vector3(cx, cy, z), r, 0.24, 10, TYRE, s)
			var hub := HUBCAP if int(variation.missing_hubcap) != wi else DARK.lightened(0.15)
			_cylinder_x(Vector3(cx + s * 0.125, cy, z), r * 0.55, 0.012, 10, hub, s)
			wi += 1
	_plain = false
	# Dark underside between the wheels (reads as the shadow gap).
	_box(Vector3(0, 0.22, 0), Vector3(d.width - 0.35, 0.16, d.length - 0.5), DARK, &"body")
	var mesh := ArrayMesh.new()
	var index := {}
	for s in SURFACES:
		if int(_tris[s]) == 0:
			continue
		(_st[s] as SurfaceTool).commit(mesh)
		index[s] = mesh.get_surface_count() - 1
	mesh.set_meta(&"surfaces", index)
	return mesh


## Arch over a wheel at [axle] (z) along the rocker line, rear → front.
func _arch(axle: float, r: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var big := r + 0.07
	var a0 := asin(clampf((ROCKER - r) / big, -1.0, 1.0))
	var steps := 7
	for i in steps + 1:
		var a := lerpf(a0, PI - a0, float(i) / steps)
		out.append(Vector2(axle + big * cos(a), r + big * sin(a)))
	return out


## Paint muting, road dirt and the glass sky band (not on wheels).
func _wear(c: Color, p: Vector3, surface: StringName) -> Color:
	if _plain:
		return c
	if surface == &"glass":
		return GLASS_TOP if p.y > _belt + 0.72 * (_roof - _belt) else c
	if surface != &"body":
		return c
	var k := mute(c)
	if p.y < DIRT_HEIGHT:
		k = k.darkened(DIRT_DARKEN)
	return k


## Pure: PZ-muted paint (saturation ×0.75, value capped at 0.75).
static func mute(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s * PAINT_SATURATION, minf(c.v, PAINT_MAX_VALUE), c.a)


## Visible rust: patches over the wheel arches and along the sills.
func _rust_patches(ax: Vector2, d: VehicleData) -> void:
	var rust: float = variation.rust
	if rust <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(variation.get("rust_seed", 1))
	var n := 2 + int(rust * 8.0)
	var r := d.wheel_radius
	for i in n:
		var s := -1.0 if rng.randf() < 0.5 else 1.0
		var col := RUST if rng.randf() < 0.6 else RUST_DARK
		var x := s * (_hw + 0.006)
		if rng.randf() < 0.55:
			# Arch lip.
			var axle := ax.x if rng.randf() < 0.5 else ax.y
			var off := rng.randf_range(-0.2, 0.2)
			var ang := acos(clampf(off / (r + 0.07), -1.0, 1.0))
			var y := r + (r + 0.07) * sin(ang) + 0.04
			_box(Vector3(x, y, axle + off), Vector3(0.012, rng.randf_range(0.05, 0.1), rng.randf_range(0.18, 0.34)), col, &"body")
		else:
			# Sill between the wheels.
			var z := rng.randf_range(ax.x + r + 0.15, ax.y - r - 0.15)
			_box(Vector3(x, ROCKER + rng.randf_range(0.04, 0.1), z), Vector3(0.012, rng.randf_range(0.05, 0.11), rng.randf_range(0.25, 0.6)), col, &"body")


## Flat-tyre sag of body vertices (bilinear toward the flat corner).
func _deform(p: Vector3) -> Vector3:
	if _sag <= 0.0 or _plain:
		return p
	var wx := clampf((1.0 + _sag_corner.x * p.x / _hw) * 0.5, 0.0, 1.0)
	var wz := clampf((1.0 + _sag_corner.y * p.z / _hl) * 0.5, 0.0, 1.0)
	return p - Vector3(0, _sag * wx * wz, 0)


func _tri(surface: StringName, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	# Godot front faces are clockwise from the viewer: (b-a)x(c-a) points
	# away from the side the normal is on.
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	var st: SurfaceTool = _st[surface]
	for pair in [[a, ca], [b, cb], [c, cc]]:
		st.set_normal(n)
		st.set_color(_wear(pair[1], pair[0], surface))
		st.add_vertex(_deform(pair[0]))
	_tris[surface] = int(_tris[surface]) + 1


func _quad(surface: StringName, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, c: Color) -> void:
	_tri(surface, p0, p1, p2, n, c, c, c)
	_tri(surface, p0, p2, p3, n, c, c, c)


## Extrude a (z, y) profile across X. Half-width goes from [hw_bottom] at
## [y0] to [hw_top] at [y1] (tumblehome); [edges] optionally colours each
## perimeter edge ([color, surface] per edge, else the side colour).
func _extrude(poly: PackedVector2Array, hw_bottom: float, hw_top: float, col: Color, surface: StringName,
		edges: Array, _body_part: bool, y0: float = 0.0, y1: float = 1.0) -> void:
	var tri := Geometry2D.triangulate_polygon(poly)
	var hwf := func(y: float) -> float:
		return lerpf(hw_bottom, hw_top, clampf((y - y0) / maxf(y1 - y0, 0.001), 0.0, 1.0)) if hw_bottom != hw_top else hw_bottom
	for s in [-1.0, 1.0]:
		var n := Vector3(s, 0, 0)
		for i in range(0, tri.size(), 3):
			var pts: Array[Vector3] = []
			for k in 3:
				var q := poly[tri[i + k]]
				pts.append(Vector3(s * float(hwf.call(q.y)), q.y, q.x))
			var fn := (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
			if fn.dot(n) < 0.0:
				fn = -fn
			_tri(surface, pts[0], pts[1], pts[2], fn, col, col, col)
	# Perimeter: orientation from the signed area.
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	var ccw := area > 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var d := b - a
		if d.length_squared() < 1e-8:
			continue
		var out2 := Vector2(d.y, -d.x) if ccw else Vector2(-d.y, d.x)
		var ha: float = hwf.call(a.y)
		var hb: float = hwf.call(b.y)
		var p0 := Vector3(-ha, a.y, a.x)
		var p1 := Vector3(ha, a.y, a.x)
		var p2 := Vector3(hb, b.y, b.x)
		var p3 := Vector3(-hb, b.y, b.x)
		var n := Vector3(0, out2.y, out2.x).normalized()
		var c := col
		var surf := surface
		if i < edges.size():
			c = edges[i][0]
			surf = edges[i][1]
		elif surface != &"body":
			c = variation.color
			surf = &"body"
		_quad(surf, p0, p1, p2, p3, n, c)


## Axis-aligned box.
func _box(c: Vector3, size: Vector3, col: Color, surface: StringName) -> void:
	var h := size * 0.5
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n: Vector3 in dirs:
		var u := Vector3.UP if absf(n.y) < 0.5 else Vector3.BACK
		var v := n.cross(u)
		var fc := c + n * h
		var uu := u * h
		var vv := v * h
		_quad(surface, fc - uu - vv, fc + uu - vv, fc + uu + vv, fc - uu + vv, n, col)


## Cylinder along X (wheels); [side] = which way the outer cap faces.
func _cylinder_x(c: Vector3, r: float, w: float, sides: int, col: Color, side: float) -> void:
	var hw := w * 0.5
	var ring: Array[Vector2] = []
	for i in sides:
		# Start at the bottom so a vertex touches the ground (y = c.y - r).
		var t := TAU * float(i) / sides - PI * 0.5
		ring.append(Vector2(cos(t), sin(t)) * r)
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		var n := Vector3(0, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5).normalized()
		_quad(&"body", c + Vector3(-hw, a.y, a.x), c + Vector3(hw, a.y, a.x), c + Vector3(hw, b.y, b.x), c + Vector3(-hw, b.y, b.x), n, col)
	var cap := c + Vector3(side * hw, 0, 0)
	for i in sides:
		var a := ring[i]
		var b := ring[(i + 1) % sides]
		_tri(&"body", cap, cap + Vector3(0, a.y, a.x), cap + Vector3(0, b.y, b.x), Vector3(side, 0, 0), col, col, col)
