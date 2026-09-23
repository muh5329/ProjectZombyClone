class_name BloodDecals
extends Node3D
## Pooled blood splats on the ground: one MultiMeshInstance3D with
## [max_decals] instances (one draw call); the oldest splat is reused when
## the pool is full. Listens to EventBus melee_hit (on the target),
## character_damaged (on the victim) and blood_spilled (bleeding drips).
## Group "blood_decals".

@export var max_decals: int = 200
@export var color: Color = Color(0.35, 0.02, 0.02, 0.9)
@export var base_size: float = 0.45

var multimesh: MultiMesh
var count: int = 0
var _next: int = 0
var _rng := RandomNumberGenerator.new()
var _mmi: MultiMeshInstance3D


func _ready() -> void:
	add_to_group(&"blood_decals")
	_rng.seed = 4242
	# Flat low-poly disc (irregularly scaled per splat → blobs, not squares).
	var quad := CylinderMesh.new()
	quad.top_radius = 0.5
	quad.bottom_radius = 0.5
	quad.height = 0.002
	quad.radial_segments = 9
	quad.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = max_decals
	multimesh.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Splats"
	_mmi.multimesh = multimesh
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)
	EventBus.melee_hit.connect(_on_melee_hit)
	EventBus.character_damaged.connect(_on_character_damaged)
	EventBus.blood_spilled.connect(_on_blood_spilled)


## Add a splat at [p] (feet level); [amount] 0..1 scales it.
func add_splat(p: Vector3, amount: float = 0.6) -> void:
	if max_decals <= 0:
		return
	var s := base_size * lerpf(0.5, 1.6, clampf(amount, 0.0, 1.0)) * _rng.randf_range(0.7, 1.2)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, 1.0, s * _rng.randf_range(0.6, 1.0)))
	var jitter := Vector3(_rng.randf_range(-0.25, 0.25), 0.0, _rng.randf_range(-0.25, 0.25))
	# Tiny height offset per slot so overlapping splats never z-fight.
	var y := p.y + 0.045 + 0.0004 * float(_next % 16)
	multimesh.set_instance_transform(_next, Transform3D(basis, Vector3(p.x, y, p.z) + jitter))
	_next = (_next + 1) % max_decals
	count = mini(count + 1, max_decals)
	multimesh.visible_instance_count = count


func _on_melee_hit(_actor: Node, target: Node, damage: float, _info: Dictionary) -> void:
	if damage > 0.0 and target is Node3D and is_instance_valid(target):
		add_splat((target as Node3D).global_position, damage / 20.0)


func _on_character_damaged(character: Node, amount: float, _source: Node, _info: Dictionary) -> void:
	if character is Node3D and is_instance_valid(character):
		add_splat((character as Node3D).global_position, amount / 20.0)


func _on_blood_spilled(p: Vector3, amount: float) -> void:
	add_splat(p, amount * 0.5)


# --- Save (Round 10, optional, capped) --------------------------------------------------

## The newest [cap] splats, oldest first: 12 floats each (transform).
func to_dict(cap: int = 64) -> Dictionary:
	var out: Array = []
	var n := mini(count, cap)
	for i in n:
		var slot := posmod(_next - n + i, max_decals)
		out.append(Saveable.xform(multimesh.get_instance_transform(slot)))
	return {"splats": out}


func from_dict(d: Dictionary) -> void:
	count = 0
	_next = 0
	for t in d.get("splats", []):
		if max_decals <= 0:
			break
		multimesh.set_instance_transform(_next, Saveable.to_xform(t))
		_next = (_next + 1) % max_decals
		count = mini(count + 1, max_decals)
	multimesh.visible_instance_count = count
