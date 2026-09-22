class_name ZombieVisual
extends MeshInstance3D
## The zombie's look: one MeshInstance3D with a shared three-surface mesh
## (body / head / arms), head tint per AI mood, the attack lunge tell, the
## swing flash and the death collapse. Shared assets live on a
## `ZombieAssets` node under the scene root (never in statics: resources
## held by a script at exit are reported as leaks).

const SURFACE_BODY := 0
const SURFACE_HEAD := 1
const SURFACE_ARMS := 2
const COLOR_BODY := Color(0.3, 0.34, 0.3)
const COLOR_ARMS := Color(0.36, 0.4, 0.34)
const COLOR_HEAD := Color(0.24, 0.27, 0.22)
const TINT_COLORS := {
	&"normal": Color(0.24, 0.27, 0.22),
	&"alert": Color(0.85, 0.75, 0.25),
	&"hostile": Color(0.85, 0.15, 0.12),
	&"flash": Color(1.0, 0.95, 0.9),
	&"dead": Color(0.18, 0.18, 0.16),
}
const COLOR_HIT := Color(1.0, 0.35, 0.3)
const ASSETS_NODE := &"ZombieAssets"
## Height of the body while lying knocked down.
const KNOCKDOWN_HEIGHT := 0.3
## Visual offset of the collapsed corpse (capsule radius).
const COLLAPSE_HEIGHT := 0.28

## Yaw the body wants to face (set by the owner); the mesh turns toward it
## at [turn_speed].
var wanted_facing: float = 0.0
var turn_speed: float = 4.0
## Forward lunge offset in metres (attack tell); 0 = none.
var lunge: float = 0.0:
	set(v):
		if lunge != v:
			lunge = v
			position.z = -v
var tint: StringName = &""
var knocked_down: bool = false
var _flash_left: float = 0.0
var _hit_left: float = 0.0
var _aligned: bool = false


func _ready() -> void:
	mesh = assets(get_tree()).shared_mesh
	set_tint(&"normal")


## True while something (turning, flashing) still needs per-tick updates.
func needs_update() -> bool:
	return not _aligned or _flash_left > 0.0 or _hit_left > 0.0


## Called by the owner each physics tick (only when needs_update()).
func update(delta: float) -> void:
	if not _aligned:
		var y := lerp_angle(rotation.y, wanted_facing, clampf(turn_speed * delta, 0.0, 1.0))
		if absf(angle_difference(y, wanted_facing)) < 0.002:
			y = wanted_facing
			_aligned = true
		rotation.y = y
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _hit_left <= 0.0:
			_apply_tint(tint)
	if _hit_left > 0.0:
		_hit_left -= delta
		if _hit_left <= 0.0:
			_clear_hit_flash()


func set_facing(yaw: float) -> void:
	if yaw != wanted_facing:
		wanted_facing = yaw
		_aligned = false


func snap_facing(yaw: float) -> void:
	wanted_facing = yaw
	rotation.y = yaw
	_aligned = true


## Direction the mesh actually points right now.
func facing_vector() -> Vector3:
	return BodyHelpers.facing_vector(rotation.y)


## Head tint by AI mood: &"normal", &"alert", &"hostile", &"dead".
func set_tint(t: StringName) -> void:
	if tint == t:
		return
	tint = t
	if _flash_left <= 0.0 and _hit_left <= 0.0:
		_apply_tint(t)


func _apply_tint(t: StringName) -> void:
	set_surface_override_material(SURFACE_HEAD, assets(get_tree()).head_material(t))


## Head goes white for [seconds] (attack swing tell).
func flash(seconds: float) -> void:
	_flash_left = seconds
	if _hit_left <= 0.0:
		_apply_tint(&"flash")


## Body flashes red-white for [seconds] (took a hit).
func hit_flash(seconds: float) -> void:
	_hit_left = seconds
	var m := assets(get_tree()).hit_material()
	set_surface_override_material(SURFACE_BODY, m)
	set_surface_override_material(SURFACE_ARMS, m)
	set_surface_override_material(SURFACE_HEAD, m)


## Back to the plain body and the head colour of the current state.
func _clear_hit_flash() -> void:
	_hit_left = 0.0
	set_surface_override_material(SURFACE_BODY, null)
	set_surface_override_material(SURFACE_ARMS, null)
	_apply_tint(&"flash" if _flash_left > 0.0 else tint)


func is_hit_flashing() -> bool:
	return _hit_left > 0.0


## Lie on the back (knocked down) or stand back up.
func set_knocked_down(v: bool) -> void:
	knocked_down = v
	lunge = 0.0
	if v:
		rotation.x = PI * 0.5
		position.y = KNOCKDOWN_HEIGHT
	else:
		rotation.x = 0.0
		position.y = 0.0


func head_material() -> StandardMaterial3D:
	return get_surface_override_material(SURFACE_HEAD)


## Lie down (death): rotate forward and drop to the ground.
func collapse() -> void:
	lunge = 0.0
	_flash_left = 0.0
	_clear_hit_flash()
	rotation.x = -PI * 0.5
	position.y = COLLAPSE_HEIGHT
	set_tint(&"dead")
	_aligned = true


## The shared-assets node (created on first use under the scene root).
static func assets(tree: SceneTree) -> ZombieAssets:
	var root := tree.root
	var n := root.get_node_or_null(NodePath(ASSETS_NODE)) as ZombieAssets
	if n == null:
		n = ZombieAssets.new()
		n.name = ASSETS_NODE
		# Zombies spawn at runtime (never inside a scene instantiate), so the
		# root is not busy setting up children here.
		root.add_child(n)
	return n


class ZombieAssets extends Node:
	var shared_mesh: ArrayMesh
	var _head_materials: Dictionary = {}

	func _init() -> void:
		shared_mesh = _build_mesh()

	var _hit_material: StandardMaterial3D

	func hit_material() -> StandardMaterial3D:
		if _hit_material == null:
			_hit_material = StandardMaterial3D.new()
			_hit_material.albedo_color = COLOR_HIT
			_hit_material.emission_enabled = true
			_hit_material.emission = COLOR_HIT
			_hit_material.emission_energy_multiplier = 0.6
		return _hit_material

	func head_material(t: StringName) -> StandardMaterial3D:
		if _head_materials.has(t):
			return _head_materials[t]
		var m := StandardMaterial3D.new()
		m.albedo_color = TINT_COLORS.get(t, COLOR_HEAD)
		_head_materials[t] = m
		return m

	## Body capsule + head sphere + arms box merged into one mesh with three
	## surfaces.
	static func _build_mesh() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var body := CapsuleMesh.new()
		body.radius = 0.28
		body.height = 1.3
		var head := SphereMesh.new()
		head.radius = 0.2
		head.height = 0.4
		var arms := BoxMesh.new()
		arms.size = Vector3(0.5, 0.1, 0.55)
		var parts := [
			[body, Vector3(0, 0.65, 0), COLOR_BODY],
			[head, Vector3(0, 1.47, 0), COLOR_HEAD],
			[arms, Vector3(0, 1.05, -0.35), COLOR_ARMS],
		]
		for part in parts:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.append_from(part[0], 0, Transform3D(Basis.IDENTITY, part[1]))
			var m := StandardMaterial3D.new()
			m.albedo_color = part[2]
			st.set_material(m)
			st.commit(mesh)
		return mesh
