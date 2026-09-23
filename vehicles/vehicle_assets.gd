class_name VehicleAssets
extends Node
## Shared vehicle resources: meshes cached per (VehicleData id, seed) and
## one material per (surface, lit). Node "VehicleAssets" under the root
## (added deferred), like CharacterAssets.

const NODE_NAME := &"VehicleAssets"
const EMISSION := {
	&"head": Color(1.0, 0.95, 0.75), &"tail": Color(1.0, 0.1, 0.05),
	&"beacon_a": Color(1.0, 0.12, 0.08), &"beacon_b": Color(0.2, 0.35, 1.0),
}

var _meshes: Dictionary[String, ArrayMesh] = {}
var _materials: Dictionary[String, StandardMaterial3D] = {}

static var _instance: VehicleAssets = null


static func of(tree: SceneTree) -> VehicleAssets:
	if is_instance_valid(_instance) and not _instance.is_queued_for_deletion():
		return _instance
	var root := tree.root
	var n := root.get_node_or_null(NodePath(NODE_NAME)) as VehicleAssets
	if n == null:
		n = VehicleAssets.new()
		n.name = NODE_NAME
		root.add_child.call_deferred(n)
	_instance = n
	return n


## Shared mesh for [data] + [seed_value] with materials applied.
func mesh_for(data: VehicleData, seed_value: int) -> ArrayMesh:
	var key := "%s|%d" % [data.id, seed_value]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := VehicleBuilder.build_mesh(data, seed_value)
	var index: Dictionary = mesh.get_meta(&"surfaces", {})
	for s: StringName in index:
		mesh.surface_set_material(index[s], material(s, false))
	_meshes[key] = mesh
	return mesh


func mesh_count() -> int:
	return _meshes.size()


## Vertex-coloured material per surface (so the occlusion fade, which
## overrides every surface with surface 0's material, keeps the colours);
## [lit] adds emission (lamps / beacons at night).
func material(surface: StringName, lit: bool) -> StandardMaterial3D:
	var key := "%s|%d" % [surface, int(lit)]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	match surface:
		&"body":
			m.roughness = 0.6
			m.metallic = 0.1
		&"glass":
			m.roughness = 0.1
			m.metallic = 0.35
			m.metallic_specular = 0.7
		_:
			m.roughness = 0.3
	if lit:
		m.emission_enabled = true
		m.emission = EMISSION.get(surface, Color.WHITE)
		m.emission_energy_multiplier = 2.5
	_materials[key] = m
	return m
