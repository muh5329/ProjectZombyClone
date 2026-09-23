class_name MeleeVisuals
extends Node3D
## Presentation for a sibling MeleeCombat (child "CombatVisuals" of the
## character): the weapon in hand (blockout box that sweeps through the
## arc), a ground ring at reach + a faint arc preview while aiming (ring
## turns orange when something is in reach), and a bright arc on the
## ground during the active window (fades out). No gameplay logic.

const COL_RING := Color(1, 1, 1, 0.55)
const COL_RING_TARGET := Color(1.0, 0.55, 0.15, 0.85)
const COL_PREVIEW := Color(1.0, 0.95, 0.7, 0.32)
const COL_SWING := Color(1.0, 0.45, 0.1, 0.75)
const COL_SHOVE := Color(0.6, 0.85, 1.0, 0.55)
const GROUND_Y := 0.06
## Seconds the swing arc stays visible (at least the active window).
const SWING_ARC_SECONDS := 0.3
## Resting tilt of the held weapon (tip up, radians about the pivot's X).
const REST_PITCH := 0.8
## Grip point in the hand bone's space (the hand hangs along -Y) and the
## weapon's tilt there (tip forward and down while the arm hangs).
const HAND_GRIP := Vector3(0.0, -0.085, -0.01)
const HAND_PITCH := -0.6

var combat: MeleeCombat
## True when the weapon is parented to the character model's right hand
## bone (the animation swings it; no procedural sweep).
var on_hand_bone: bool = false
var ring: MeshInstance3D
var preview_arc: MeshInstance3D
var swing_arc: MeshInstance3D
var weapon_pivot: Node3D
var weapon_mesh: MeshInstance3D

var _ring_mat: StandardMaterial3D
var _preview_mat: StandardMaterial3D
var _swing_mat: StandardMaterial3D
var _weapon_mat: StandardMaterial3D
var _swing_left: float = 0.0
var _swing_total: float = SWING_ARC_SECONDS
var _swing_color: Color = COL_SWING
var _built_for: WeaponData = null


func _ready() -> void:
	combat = get_parent().get_node_or_null("Combat") as MeleeCombat
	top_level = false
	_ring_mat = _material(COL_RING)
	_preview_mat = _material(COL_PREVIEW)
	_swing_mat = _material(COL_SWING)
	ring = MeshInstance3D.new()
	ring.name = "AimRing"
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	preview_arc = MeshInstance3D.new()
	preview_arc.name = "AimArc"
	preview_arc.material_override = _preview_mat
	preview_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview_arc.visible = false
	add_child(preview_arc)
	swing_arc = MeshInstance3D.new()
	swing_arc.name = "SwingArc"
	swing_arc.material_override = _swing_mat
	swing_arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	swing_arc.visible = false
	add_child(swing_arc)
	# The weapon rides on the rotated body visual so it faces with it.
	var body_visual := get_parent().get_node_or_null("Visual") as Node3D
	weapon_pivot = Node3D.new()
	weapon_pivot.name = "WeaponPivot"
	var model := body_visual.get_node_or_null("Model") as CharacterModel if body_visual else null
	if model and model.skeleton:
		# Round 8.5: gripped by the right hand bone; the swing clips move it.
		on_hand_bone = true
		weapon_pivot.position = HAND_GRIP
		weapon_pivot.rotation.x = HAND_PITCH
		model.attach(&"hand_r").add_child(weapon_pivot)
	else:
		# Held in the right hand, at the side of the body (readable from the
		# dimetric camera); at rest the weapon points forward-up.
		weapon_pivot.position = Vector3(0.36, 0.95, -0.05)
		(body_visual if body_visual else self).add_child(weapon_pivot)
	_weapon_mat = StandardMaterial3D.new()
	weapon_mesh = MeshInstance3D.new()
	weapon_mesh.name = "Weapon"
	weapon_mesh.material_override = _weapon_mat
	weapon_pivot.add_child(weapon_mesh)
	if combat:
		combat.equipped_changed.connect(func(_i): _rebuild())
		combat.active_started.connect(_on_active_started)
		combat.aim_changed.connect(_on_aim_changed)
	_rebuild()


static func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = c
	m.no_depth_test = false
	return m


## Flat fan (XZ, forward = -Z) of radius [reach] and full angle [arc].
static func build_arc_mesh(reach: float, arc: float, segments: int = 24, inner: float = 0.25) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := arc * 0.5
	for i in segments:
		var a0 := -half + arc * float(i) / segments
		var a1 := -half + arc * float(i + 1) / segments
		var o0 := Vector3(-sin(a0), 0, -cos(a0))
		var o1 := Vector3(-sin(a1), 0, -cos(a1))
		st.add_vertex(o0 * inner)
		st.add_vertex(o0 * reach)
		st.add_vertex(o1 * reach)
		st.add_vertex(o0 * inner)
		st.add_vertex(o1 * reach)
		st.add_vertex(o1 * inner)
	return st.commit()


static func build_ring_mesh(radius: float, width: float = 0.06, segments: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var r0 := radius - width * 0.5
		var r1 := radius + width * 0.5
		st.add_vertex(d0 * r0)
		st.add_vertex(d0 * r1)
		st.add_vertex(d1 * r1)
		st.add_vertex(d0 * r0)
		st.add_vertex(d1 * r1)
		st.add_vertex(d1 * r0)
	return st.commit()


func _rebuild() -> void:
	if combat == null:
		return
	var w := combat.weapon()
	_built_for = w
	ring.mesh = build_ring_mesh(w.reach)
	ring.position = Vector3(0, GROUND_Y, 0)
	preview_arc.mesh = build_arc_mesh(w.reach, w.arc_radians())
	preview_arc.position = Vector3(0, GROUND_Y - 0.005, 0)
	var is_fists := w == combat.fists
	weapon_mesh.visible = not is_fists
	if not is_fists:
		var box := BoxMesh.new()
		# Held pointing forward: length along -Z.
		box.size = Vector3(w.world_size.z, w.world_size.y, w.world_size.x)
		weapon_mesh.mesh = box
		# A little of the handle sticks out behind the fist.
		var behind := 0.08 if on_hand_bone else 0.0
		weapon_mesh.position = Vector3(0, 0, -w.world_size.x * 0.5 + behind)
		_weapon_mat.albedo_color = w.color


func _on_aim_changed(aiming: bool, in_reach: int) -> void:
	ring.visible = aiming
	preview_arc.visible = aiming
	_ring_mat.albedo_color = COL_RING_TARGET if in_reach > 0 else COL_RING


func _on_active_started(w: WeaponData, direction: Vector3, _hits: Array) -> void:
	swing_arc.mesh = build_arc_mesh(w.reach, w.arc_radians())
	swing_arc.position = Vector3(0, GROUND_Y, 0)
	swing_arc.rotation.y = BodyHelpers.yaw_for(direction)
	_swing_total = maxf(w.active_time(), SWING_ARC_SECONDS)
	_swing_left = _swing_total
	_swing_color = COL_SHOVE if w.is_shove else COL_SWING
	_swing_mat.albedo_color = _swing_color
	swing_arc.visible = true


func swing_arc_visible() -> bool:
	return swing_arc.visible


func _process(delta: float) -> void:
	if combat == null:
		return
	if _built_for != combat.weapon():
		_rebuild()
	if preview_arc.visible:
		preview_arc.rotation.y = BodyHelpers.yaw_for(combat.attack_direction())
	if _swing_left > 0.0:
		_swing_left -= delta
		var c := _swing_color
		c.a *= clampf(_swing_left / _swing_total, 0.0, 1.0) * 0.7 + 0.3
		_swing_mat.albedo_color = c
		if _swing_left <= 0.0:
			swing_arc.visible = false
	if on_hand_bone:
		return
	# Weapon sweep: raised to one side during the windup, across the arc
	# during the active window, back to rest in recovery.
	var w := combat.current
	var yaw := 0.0
	var pitch := REST_PITCH
	if w != null and combat.phase == MeleeCombat.Phase.WINDUP:
		yaw = w.arc_radians() * 0.5
		pitch = 0.2
	elif w != null and combat.phase == MeleeCombat.Phase.ACTIVE:
		pitch = 0.0
		var t := 1.0 - clampf(combat.phase_left / maxf(w.active_time() * combat.swing.time_scale, 0.001), 0.0, 1.0)
		yaw = lerpf(w.arc_radians() * 0.5, -w.arc_radians() * 0.5, t)
	elif combat.phase == MeleeCombat.Phase.CHARGING:
		yaw = 0.9
		pitch = 0.5
	var k := clampf(delta * 25.0, 0.0, 1.0)
	weapon_pivot.rotation.y = lerp_angle(weapon_pivot.rotation.y, yaw, k)
	weapon_pivot.rotation.x = lerp_angle(weapon_pivot.rotation.x, pitch, k)
