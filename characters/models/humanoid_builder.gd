class_name HumanoidBuilder
extends RefCounted
## Procedural low-poly person (fully owned: no third-party assets). Builds
## a 17-bone Skeleton3D and a rigidly skinned ArrayMesh (~600 triangles)
## from tapered prisms, ellipsoids and boxes with realistic proportions
## (1.75 m, feet at y = 0, facing -Z, right hand on +X). Clothing is
## vertex colour from an Appearance (Outfit + skin / hair / decay), so a
## whole person is ONE draw call for the body plus a tiny "eyes" surface
## whose material carries the zombie mood tint.
##
## Rest pose: arms hanging at the sides, every bone's rest rotation is
## identity (animations rotate bones in parent-aligned space: +X swings a
## limb forward, -X leans the spine forward). Pure: no scene tree needed.

const SURFACE_BODY := 0
const SURFACE_EYES := 1

const BONE_NAMES: Array[StringName] = [
	&"hips", &"spine", &"chest", &"neck", &"head",
	&"upperarm_l", &"forearm_l", &"hand_l", &"upperarm_r", &"forearm_r", &"hand_r",
	&"thigh_l", &"shin_l", &"foot_l", &"thigh_r", &"shin_r", &"foot_r",
]
const BONE_PARENTS: Array[int] = [-1, 0, 1, 2, 3, 2, 5, 6, 2, 8, 9, 0, 11, 12, 0, 14, 15]
## Joint positions in model space (rest pose).
const BONE_HEADS: Array[Vector3] = [
	Vector3(0, 0.95, 0), Vector3(0, 1.07, 0), Vector3(0, 1.25, 0), Vector3(0, 1.47, 0), Vector3(0, 1.54, 0),
	Vector3(-0.23, 1.43, 0), Vector3(-0.245, 1.15, 0), Vector3(-0.255, 0.9, 0),
	Vector3(0.23, 1.43, 0), Vector3(0.245, 1.15, 0), Vector3(0.255, 0.9, 0),
	Vector3(-0.1, 0.92, 0), Vector3(-0.105, 0.5, 0), Vector3(-0.105, 0.09, 0),
	Vector3(0.1, 0.92, 0), Vector3(0.105, 0.5, 0), Vector3(0.105, 0.09, 0),
]
const HEIGHT := 1.78
## Head scale over realistic proportions (readability at the iso zoom).
const HS := 1.15
const BLOOD := Color(0.26, 0.02, 0.02)
const BLOOD_SHADES: Array[Color] = [Color(0.3, 0.03, 0.03), Color(0.2, 0.05, 0.04), Color(0.25, 0.12, 0.08)]
## Share of the chest / sleeve grid cells that get blood at blood = 1.
const BLOOD_COVERAGE := 0.55
const CLOTH_SATURATION := 0.75
const CLOTH_MAX_VALUE := 0.75
const EYE_COLOR := Color(0.08, 0.07, 0.06)

var _body: SurfaceTool
var _eyes: SurfaceTool
var _app: Appearance
var _tris: int = 0


static func bone_index(bone: StringName) -> int:
	return BONE_NAMES.find(bone)


## A Skeleton3D with the humanoid bones (identity rest rotations).
static func build_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for i in BONE_NAMES.size():
		sk.add_bone(BONE_NAMES[i])
	for i in BONE_NAMES.size():
		var p := BONE_PARENTS[i]
		if p >= 0:
			sk.set_bone_parent(i, p)
		var local := BONE_HEADS[i] - (BONE_HEADS[p] if p >= 0 else Vector3.ZERO)
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, local))
	sk.reset_bone_poses()
	return sk


## Bind poses matching build_skeleton() (shared by every instance).
static func build_skin() -> Skin:
	var skin := Skin.new()
	for i in BONE_NAMES.size():
		skin.add_bind(i, Transform3D(Basis.IDENTITY, -BONE_HEADS[i]))
	return skin


## Rest position of a bone's joint in model space.
static func rest_position(bone: StringName) -> Vector3:
	return BONE_HEADS[bone_index(bone)]


static func triangle_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		n += (idx.size() if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


## Build the mesh for [app]. Materials are assigned by the caller
## (CharacterAssets) per surface.
static func build_mesh(app: Appearance) -> ArrayMesh:
	var b := HumanoidBuilder.new()
	return b._build(app)


func _build(app: Appearance) -> ArrayMesh:
	_app = app
	var o: Outfit = app.outfit if app.outfit else Outfit.new()
	_body = SurfaceTool.new()
	_body.begin(Mesh.PRIMITIVE_TRIANGLES)
	_eyes = SurfaceTool.new()
	_eyes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := app.skin
	var top := o.jacket_color if o.has_jacket else o.shirt_color
	var torso := o.vest_color if o.vest else top
	var pants := o.pants_color
	# --- Legs (chunky, PZ-like) ---------------------------------------------------
	for side in [-1.0, 1.0]:
		var s: float = side
		var sfx := "_l" if s < 0.0 else "_r"
		var hip := Vector3(0.1 * s, 0.95, 0)
		var knee := Vector3(0.105 * s, 0.5, 0.005)
		var ankle := Vector3(0.105 * s, 0.1, 0.01)
		var thigh := StringName("thigh" + sfx)
		var shin := StringName("shin" + sfx)
		var foot := StringName("foot" + sfx)
		if o.shorts:
			var mid := hip.lerp(knee, 0.62)
			_prism(hip, mid, Vector2(0.095, 0.097), Vector2(0.085, 0.088), 6, pants, thigh, true, false, true)
			_prism(mid, knee, Vector2(0.072, 0.075), Vector2(0.066, 0.068), 6, skin, thigh, false, false, false)
			_prism(knee, ankle, Vector2(0.066, 0.07), Vector2(0.05, 0.052), 6, skin, shin, false, false, false)
		else:
			_prism(hip, knee, Vector2(0.095, 0.097), Vector2(0.072, 0.076), 6, pants, thigh, true, false, true)
			_prism(knee, ankle, Vector2(0.072, 0.075), Vector2(0.06, 0.062), 6, pants, shin, false, false, true)
		# Shoe: ankle collar + foot box (toe forward = -Z).
		_prism(ankle + Vector3(0, 0.02, 0), Vector3(ankle.x, 0.0, 0.01), Vector2(0.058, 0.062), Vector2(0.06, 0.07), 6, o.shoes_color, foot, false, false, false)
		_box(Vector3(ankle.x, 0.045, -0.065), Vector3(0.11, 0.09, 0.22), o.shoes_color, foot)
	# --- Torso ----------------------------------------------------------------
	_prism(Vector3(0, 0.86, 0), Vector3(0, 1.03, 0), Vector2(0.172, 0.112), Vector2(0.168, 0.108), 8, pants, &"hips", true, false, true)
	if o.has_belt:
		_prism(Vector3(0, 1.0, 0), Vector3(0, 1.04, 0), Vector2(0.176, 0.114), Vector2(0.176, 0.114), 8, o.belt_color, &"hips", false, false, false)
	_prism(Vector3(0, 1.02, 0), Vector3(0, 1.22, 0), Vector2(0.168, 0.108), Vector2(0.182, 0.114), 8, torso, &"spine", false, false, true)
	_prism(Vector3(0, 1.2, 0), Vector3(0, 1.41, 0), Vector2(0.186, 0.116), Vector2(0.2, 0.115), 8, torso, &"chest", false, false, true)
	_prism(Vector3(0, 1.41, 0), Vector3(0, 1.49, 0), Vector2(0.2, 0.115), Vector2(0.1, 0.075), 8, torso, &"chest", false, true, true)
	if o.vest:
		# The shirt / jacket shows at the shoulders under the vest straps.
		_box(Vector3(0, 1.44, 0), Vector3(0.34, 0.05, 0.21), top, &"chest")
	if o.has_jacket and o.jacket_open:
		_box(Vector3(0, 1.22, -0.112), Vector3(0.08, 0.38, 0.02), o.shirt_color, &"chest")
	if o.stripes:
		_prism(Vector3(0, 1.08, 0), Vector3(0, 1.12, 0), Vector2(0.18, 0.115), Vector2(0.182, 0.117), 8, o.stripe_color, &"spine", false, false, false)
		_prism(Vector3(0, 1.3, 0), Vector3(0, 1.34, 0), Vector2(0.194, 0.12), Vector2(0.196, 0.12), 8, o.stripe_color, &"chest", false, false, false)
	if o.badge:
		_box(Vector3(-0.09, 1.35, -0.115), Vector3(0.05, 0.05, 0.012), o.badge_color, &"chest")
	if o.hood:
		_ellipsoid(Vector3(0, 1.47, 0.11), Vector3(0.12, 0.065, 0.055), 3, 6, top, &"chest")
	# --- Arms -----------------------------------------------------------------
	var sleeve := top
	for side in [-1.0, 1.0]:
		var s: float = side
		var sfx := "_l" if s < 0.0 else "_r"
		var shoulder := Vector3(0.23 * s, 1.43, 0)
		var elbow := Vector3(0.245 * s, 1.15, 0.01)
		var wrist := Vector3(0.255 * s, 0.9, 0.0)
		var hand_end := Vector3(0.258 * s, 0.75, -0.01)
		var upper := StringName("upperarm" + sfx)
		var fore := StringName("forearm" + sfx)
		var hand := StringName("hand" + sfx)
		var torn := app.torn_left if s < 0.0 else app.torn_right
		var long := o.has_jacket or not o.short_sleeves
		# Rounded shoulder (deltoid) in the sleeve colour.
		_ellipsoid(Vector3(0.21 * s, 1.425, 0.0), Vector3(0.075, 0.066, 0.072), 3, 6, sleeve, upper)
		if long:
			_prism(shoulder, elbow, Vector2(0.06, 0.062), Vector2(0.052, 0.054), 6, sleeve, upper, false, false, true)
			if torn:
				_prism(elbow, wrist, Vector2(0.044, 0.046), Vector2(0.036, 0.038), 6, skin, fore, false, false, false)
				# Ragged cuff left at the elbow.
				_prism(elbow + Vector3(0, 0.02, 0), elbow - Vector3(0, 0.05, 0), Vector2(0.055, 0.057), Vector2(0.05, 0.052), 6, sleeve, fore, false, false, true)
			else:
				_prism(elbow, wrist, Vector2(0.052, 0.054), Vector2(0.044, 0.046), 6, sleeve, fore, false, false, true)
				if o.stripes:
					_prism(wrist + Vector3(0, 0.09, 0), wrist + Vector3(0, 0.05, 0), Vector2(0.049, 0.051), Vector2(0.048, 0.05), 6, o.stripe_color, fore, false, false, false)
		else:
			var mid := shoulder.lerp(elbow, 0.45)
			_prism(shoulder, mid, Vector2(0.062, 0.064), Vector2(0.058, 0.06), 6, sleeve, upper, false, true, true)
			_prism(mid, elbow, Vector2(0.05, 0.052), Vector2(0.046, 0.048), 6, skin, upper, false, false, false)
			_prism(elbow, wrist, Vector2(0.046, 0.048), Vector2(0.037, 0.039), 6, skin, fore, false, false, false)
		_prism(wrist, hand_end, Vector2(0.04, 0.021), Vector2(0.034, 0.018), 4, skin, hand, false, true, false)
	# --- Neck & head (×1.15 for readability) ---------------------------------
	_prism(Vector3(0, 1.46, 0.005), Vector3(0, 1.56, 0.005), Vector2(0.055, 0.057), Vector2(0.052, 0.054), 6, skin, &"neck", false, false, false)
	var head_c := Vector3(0, 1.66, 0)
	var head_r := Vector3(0.093, 0.114, 0.104) * HS
	_ellipsoid(head_c, head_r, 6, 8, skin, &"head")
	var fz := -head_r.z
	# Nose and jaw bumps.
	_box(head_c + Vector3(0, -0.02, fz - 0.008), Vector3(0.03, 0.045, 0.03), skin.darkened(0.08), &"head", null, false)
	_box(head_c + Vector3(0, -0.095, fz + 0.035), Vector3(0.1, 0.045, 0.06), skin.darkened(0.04), &"head", null, false)
	for s in [-1.0, 1.0]:
		var ec := head_c + Vector3(0.042 * s, 0.012, fz + 0.012)
		# Dark eye sockets for everyone (deeper on zombies).
		_box(ec + Vector3(0, 0, 0.004), Vector3(0.04, 0.03, 0.01), skin.darkened(0.55 if app.zombie else 0.35), &"head", null, false)
		_box(ec + Vector3(0, 0, -0.004), Vector3(0.022, 0.013, 0.008), EYE_COLOR, &"head", _eyes)
		# Ears.
		_box(head_c + Vector3(head_r.x * s, -0.005, 0.005), Vector3(0.022, 0.05, 0.034), skin.darkened(0.05), &"head", null, false)
	if app.zombie:
		# Open mouth.
		_box(head_c + Vector3(0, -0.062, fz + 0.012), Vector3(0.055, 0.03, 0.012), Color(0.1, 0.02, 0.02), &"head", null, false)
	_hair(head_c, head_r, o)
	_hat(head_c, head_r, o)
	var mesh := ArrayMesh.new()
	_body.commit(mesh)
	_eyes.commit(mesh)
	return mesh


func _hair(c: Vector3, r: Vector3, o: Outfit) -> void:
	var col := _app.hair_color
	var covered := o.hat != &"none"
	match _app.hair_style:
		&"bald":
			return
		&"buzz":
			if not covered:
				_ellipsoid(c + HS * Vector3(0, 0.004, 0.004), r * 1.035, 4, 8, col, &"head", null, 0.1)
		&"short":
			_ellipsoid(c + HS * Vector3(0, 0.006, 0.008), r * Vector3(1.08, 1.06, 1.08), 4, 8, col, &"head", null, -0.05)
		&"long":
			_ellipsoid(c + HS * Vector3(0, 0.006, 0.008), r * Vector3(1.09, 1.07, 1.09), 4, 8, col, &"head", null, -0.2)
			_box(c + HS * Vector3(0, -0.12, 0.07), HS * Vector3(0.19, 0.2, 0.05), col, &"head", null, false)
		&"ponytail":
			_ellipsoid(c + HS * Vector3(0, 0.006, 0.008), r * Vector3(1.07, 1.05, 1.08), 4, 8, col, &"head", null, 0.0)
			_box(c + HS * Vector3(0, -0.06, 0.125), HS * Vector3(0.05, 0.16, 0.05), col, &"head", null, false)


func _hat(c: Vector3, r: Vector3, o: Outfit) -> void:
	var col := cloth_color(o.hat_color)
	match o.hat:
		&"cap":
			_ellipsoid(c + HS * Vector3(0, 0.012, 0.005), r * Vector3(1.12, 1.08, 1.12), 4, 8, col, &"head", null, 0.25)
			_box(c + HS * Vector3(0, 0.04, -0.14), HS * Vector3(0.16, 0.014, 0.1), col.darkened(0.1), &"head")
		&"beanie":
			_ellipsoid(c + HS * Vector3(0, 0.02, 0.005), r * Vector3(1.12, 1.12, 1.12), 4, 8, col, &"head", null, 0.1)
		&"police_cap":
			_prism(c + HS * Vector3(0, 0.05, 0.0), c + HS * Vector3(0, 0.14, 0.0), HS * Vector2(0.105, 0.115), HS * Vector2(0.125, 0.13), 8, col, &"head", false, true, false)
			_box(c + HS * Vector3(0, 0.055, -0.13), HS * Vector3(0.16, 0.014, 0.07), Color(0.05, 0.05, 0.05), &"head")
			_box(c + HS * Vector3(0, 0.1, -0.125), HS * Vector3(0.035, 0.035, 0.012), o.badge_color, &"head")
		&"hard_hat":
			_ellipsoid(c + HS * Vector3(0, 0.035, 0.0), r * Vector3(1.22, 1.12, 1.2), 4, 8, col, &"head", null, 0.2)
			_prism(c + HS * Vector3(0, 0.045, 0.0), c + HS * Vector3(0, 0.06, 0.0), HS * Vector2(0.14, 0.15), HS * Vector2(0.14, 0.15), 8, col, &"head", true, true, false)
		&"fire_helmet":
			_ellipsoid(c + HS * Vector3(0, 0.035, 0.0), r * Vector3(1.22, 1.14, 1.22), 4, 8, col, &"head", null, 0.15)
			_box(c + HS * Vector3(0, 0.035, 0.12), HS * Vector3(0.22, 0.016, 0.14), col, &"head", null, false)
			_box(c + HS * Vector3(0, 0.1, -0.12), HS * Vector3(0.06, 0.06, 0.012), o.badge_color, &"head")


# --- Primitive emitters (all vertices rigidly bound to one bone) -------------

## Dirt / blood variation for zombies (deterministic per vertex position).
func _shade(col: Color, p: Vector3, cloth: bool) -> Color:
	var c := col
	if cloth:
		# Muted PZ palette: saturation ×0.75, value ≤ 0.75.
		c = cloth_color(c)
	if not _app.zombie or not cloth:
		return c
	# Faded, filthy clothes.
	var lum := c.get_luminance()
	c = c.lerp(Color(lum, lum * 0.95, lum * 0.82), 0.35).darkened(0.2)
	# Blood only on the chest / collar and the lower sleeves, in soft
	# coherent patches (coarse grid) of three shades.
	var chest := p.y > 1.18 and p.y < 1.52 and p.z < 0.03 and absf(p.x) < 0.2
	var sleeve := p.y > 0.86 and p.y < 1.17 and absf(p.x) > 0.19
	if not (chest or sleeve):
		return c
	var h := _hash((p / 0.09).floor())
	if h < _app.blood * BLOOD_COVERAGE:
		var shade: Color = BLOOD_SHADES[int(_hash((p / 0.2).floor() + Vector3(3, 7, 11)) * 3.0) % 3]
		c = c.lerp(shade, 0.85)
	return c


## Pure: the muted PZ cloth colour (saturation ×0.75, value ≤ 0.75).
static func cloth_color(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s * CLOTH_SATURATION, minf(c.v, CLOTH_MAX_VALUE))


func _hash(p: Vector3) -> float:
	var v := sin(p.x * 127.1 + p.y * 311.7 + p.z * 74.7 + float(_app.pattern_seed) * 13.37) * 43758.5453
	return v - floorf(v)


func _vertex(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, bone: int) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_bones(PackedInt32Array([bone, 0, 0, 0]))
	st.set_weights(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	st.add_vertex(p)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color, bone: int) -> void:
	# Godot front faces are clockwise seen from the front.
	_vertex(st, a, na, ca, bone)
	_vertex(st, b, nb, cb, bone)
	_vertex(st, c, nc, cc, bone)
	_tris += 1


## Tapered elliptical prism from [a] to [b]; ra / rb = (radius along the
## side axis, radius front-back). Smooth sides, flat optional caps.
func _prism(a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, sides: int, col: Color, bone_name: StringName,
		cap_a: bool, cap_b: bool, cloth: bool, st: SurfaceTool = null) -> void:
	if st == null:
		st = _body
	var bone := bone_index(bone_name)
	var axis := (b - a).normalized()
	var u := Vector3.RIGHT - axis * axis.dot(Vector3.RIGHT)
	if u.length_squared() < 0.01:
		u = Vector3.UP - axis * axis.dot(Vector3.UP)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	var ring_a: Array[Vector3] = []
	var ring_b: Array[Vector3] = []
	var norms: Array[Vector3] = []
	for i in sides:
		var t := TAU * (float(i) + 0.5) / sides
		var cs := cos(t)
		var sn := sin(t)
		ring_a.append(a + u * cs * ra.x + v * sn * ra.y)
		ring_b.append(b + u * cs * rb.x + v * sn * rb.y)
		norms.append((u * cs / maxf(ra.x, 0.001) + v * sn / maxf(ra.y, 0.001)).normalized())
	for i in sides:
		var j := (i + 1) % sides
		# One colour per triangle: blood / dirt reads as crisp low-poly
		# patches instead of smeared gradients.
		var k1 := _shade(col, (ring_a[i] + ring_b[i] + ring_b[j]) / 3.0, cloth)
		var k2 := _shade(col, (ring_a[i] + ring_b[j] + ring_a[j]) / 3.0, cloth)
		_tri(st, ring_a[i], ring_b[i], ring_b[j], norms[i], norms[i], norms[j], k1, k1, k1, bone)
		_tri(st, ring_a[i], ring_b[j], ring_a[j], norms[i], norms[j], norms[j], k2, k2, k2, bone)
	if cap_a:
		var ca := _shade(col, a, cloth)
		for i in range(1, sides - 1):
			_tri(st, ring_a[0], ring_a[i], ring_a[i + 1], -axis, -axis, -axis, ca, ca, ca, bone)
	if cap_b:
		var cb := _shade(col, b, cloth)
		for i in range(1, sides - 1):
			_tri(st, ring_b[0], ring_b[i + 1], ring_b[i], axis, axis, axis, cb, cb, cb, bone)


## Ellipsoid (optionally only the part above [min_y_frac] of its height,
## -1..1) with smooth normals.
func _ellipsoid(c: Vector3, r: Vector3, rings: int, segs: int, col: Color, bone_name: StringName,
		st: SurfaceTool = null, min_y_frac: float = -1.0) -> void:
	if st == null:
		st = _body
	var bone := bone_index(bone_name)
	var lat0 := asin(clampf(min_y_frac, -1.0, 1.0))
	var cloth := false
	for ri in rings:
		var la := lerpf(lat0, PI * 0.5, float(ri) / rings)
		var lb := lerpf(lat0, PI * 0.5, float(ri + 1) / rings)
		for si in segs:
			var ta := TAU * float(si) / segs
			var tb := TAU * float(si + 1) / segs
			var n00 := Vector3(cos(la) * cos(ta), sin(la), cos(la) * sin(ta))
			var n01 := Vector3(cos(la) * cos(tb), sin(la), cos(la) * sin(tb))
			var n10 := Vector3(cos(lb) * cos(ta), sin(lb), cos(lb) * sin(ta))
			var n11 := Vector3(cos(lb) * cos(tb), sin(lb), cos(lb) * sin(tb))
			var p00 := c + n00 * r
			var p01 := c + n01 * r
			var p10 := c + n10 * r
			var p11 := c + n11 * r
			var k1 := _shade(col, (p00 + p01 + p11) / 3.0, cloth)
			var k2 := _shade(col, (p00 + p11 + p10) / 3.0, cloth)
			_tri(st, p00, p01, p11, n00, n01, n11, k1, k1, k1, bone)
			if ri < rings - 1:
				_tri(st, p00, p11, p10, n00, n11, n10, k2, k2, k2, bone)
	if min_y_frac > -0.99:
		# Close the bottom so a cut-off cap is not see-through from below.
		var yb := c.y + sin(lat0) * r.y
		var rb := cos(lat0)
		var center := Vector3(c.x, yb, c.z)
		var kc := _shade(col, center, cloth)
		for si in segs:
			var ta := TAU * float(si) / segs
			var tb := TAU * float(si + 1) / segs
			var pa := c + Vector3(cos(ta) * rb, sin(lat0), sin(ta) * rb) * r
			var pb := c + Vector3(cos(tb) * rb, sin(lat0), sin(tb) * rb) * r
			_tri(st, center, pb, pa, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, kc, kc, kc, bone)


## Axis-aligned box with flat faces.
func _box(c: Vector3, size: Vector3, col: Color, bone_name: StringName, st: SurfaceTool = null, cloth: bool = true) -> void:
	if st == null:
		st = _body
	var bone := bone_index(bone_name)
	var h := size * 0.5
	cloth = cloth and st == _body
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var up: Vector3 = f[1]
		var side: Vector3 = f[2]
		var fc := c + n * h
		var uu := up * h
		var ss := side * h
		var p0 := fc - uu - ss
		var p1 := fc + uu - ss
		var p2 := fc + uu + ss
		var p3 := fc - uu + ss
		var k := _shade(col, fc, cloth) if st == _body else col
		_tri(st, p0, p2, p1, n, n, n, k, k, k, bone)
		_tri(st, p0, p3, p2, n, n, n, k, k, k, bone)


## Triangles emitted by the last build (tests).
func emitted_triangles() -> int:
	return _tris
