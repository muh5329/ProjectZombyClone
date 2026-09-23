class_name Splinters
extends MultiMeshInstance3D
## Wood splinters left on the floor where a plank / a piece of furniture
## broke (decal-like, one MultiMesh per burst, group "splinters"). The
## number of bursts in the scene is capped (oldest freed first).

const GROUP := &"splinters"
const MAX_BURSTS := 24
const PIECES := 10


## Scatter a burst on the floor around [at] (world), thrown toward
## [toward] (flat direction; zero = all around), under [parent].
static func spawn(parent: Node, at: Vector3, toward: Vector3 = Vector3.ZERO, color: Color = Color(0.55, 0.4, 0.24), seed_value: int = 0) -> Splinters:
	if parent == null or not parent.is_inside_tree():
		return null
	var existing := parent.get_tree().get_nodes_in_group(GROUP)
	if existing.size() >= MAX_BURSTS:
		existing[0].queue_free()
	var s := Splinters.new()
	s.name = "Splinters"
	s.add_to_group(GROUP)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.025, 0.035)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	mm.mesh = box
	mm.instance_count = PIECES
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else hash(at)
	var dir := Vector3(toward.x, 0.0, toward.z)
	if dir.length_squared() > 0.0001:
		dir = dir.normalized()
	for i in PIECES:
		var off := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6)) + dir * rng.randf_range(0.1, 0.9)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		var sc := rng.randf_range(0.6, 1.4)
		mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(sc, 1.0, 1.0)), off + Vector3(0, 0.015, 0)))
	s.multimesh = mm
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)
	s.global_position = Vector3(at.x, at.y, at.z)
	return s
