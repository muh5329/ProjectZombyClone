class_name GlassShards
extends Node3D
## Broken glass on the floor under a smashed window (1.2 m out on both
## sides of the wall). A hazard area, not an item: a character walking over it without
## foot protection, and not sneaking, gets a foot (leg-region) scratch at
## [scratch_chance_per_second] (rolled per physics tick as
## 1 − (1 − chance)^dt, so crossing it quickly is safer than lingering),
## at most once per [scratch_cooldown] seconds. The window's "Remove
## broken glass" action frees it. Group "glass_shards".
##
## Only the registered player is checked (NPC survivors later through a
## group); zombies don't care.

## Local X runs along the wall, local Z across it (the window's frame).
@export var size: Vector2 = Vector2(1.2, 2.4)
@export_range(0.0, 1.0) var scratch_chance_per_second: float = 0.25
@export var scratch_damage: float = 1.0
@export var scratch_cooldown: float = 1.5
## Nothing lies inside the wall itself.
@export var wall_gap: float = 0.15

var rng := RandomNumberGenerator.new()
## Scratches inflicted so far (tests / debug).
var scratches: int = 0
var _cooldown: float = 0.0
var _pieces: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group(&"glass_shards")
	if rng.seed == 0:
		rng.seed = hash(str(global_position))
	_build_visual()


func _build_visual() -> void:
	var vr := RandomNumberGenerator.new()
	vr.seed = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.96, 1.0, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.4
	mat.roughness = 0.05
	mat.emission_enabled = true
	mat.emission = Color(0.65, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.9
	for i in 40:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(vr.randf_range(0.1, 0.26), 0.015, vr.randf_range(0.06, 0.18))
		box.material = mat
		mi.mesh = box
		var side := 1.0 if i % 2 == 0 else -1.0
		# Denser near the wall, where the pane fell.
		var z := side * (wall_gap + pow(vr.randf(), 1.6) * (size.y * 0.5 - wall_gap))
		mi.position = Vector3(vr.randf_range(-size.x * 0.5, size.x * 0.5), 0.02, z)
		mi.rotation.y = vr.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pieces.append(mi)


func contains_point(p: Vector3) -> bool:
	var l := to_local(p)
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.y * 0.5 and l.y > -0.5 and l.y < 1.0


## True when [c] would get hurt by walking here now.
static func is_exposed(c: Node) -> bool:
	if c == null or not is_instance_valid(c):
		return false
	if c.has_method(&"is_dead") and c.is_dead():
		return false
	if not (c.has_method(&"is_moving") and c.is_moving()):
		return false
	var mode: Variant = c.get(&"effective_mode")
	if mode is int and mode == MovementComponent.Mode.SNEAK:
		return false  # careful steps avoid the shards
	if c.has_method(&"has_foot_protection") and c.has_foot_protection():
		return false
	return true


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	var p := GameManager.player as Node3D
	if p == null or not is_instance_valid(p) or not contains_point(p.global_position):
		return
	if _cooldown > 0.0 or bool(p.get(&"is_busy")) or not is_exposed(p):
		return
	var chance := 1.0 - pow(1.0 - clampf(scratch_chance_per_second, 0.0, 1.0), delta)
	if scratch_chance_per_second >= 1.0 or rng.randf() < chance:
		_scratch(p)


func _scratch(c: Node3D) -> void:
	_cooldown = scratch_cooldown
	scratches += 1
	var region := &"left_leg" if rng.randf() < 0.5 else &"right_leg"
	if c.has_method(&"take_damage"):
		c.call(&"take_damage", scratch_damage, self, {"region": region, "type": &"scratch"})
	EventBus.hazard_hurt.emit(c, &"glass", region)
