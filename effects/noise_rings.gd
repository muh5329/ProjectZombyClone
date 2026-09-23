class_name NoiseRings
extends Node3D
## Player noise feedback (Project Zomboid's noise rings): every sound the
## player causes (EventBus.sound_emitted with source == the player) shows
## a flat ring on the ground at the sound's position that expands to the
## sound's radius and fades out. Pooled (max [pool_size]); only the
## player's sounds — zombie / world noises never show (F4 debug does).

@export var pool_size: int = 20
@export var lifetime: float = 1.1
## Rings start at this fraction of the radius.
@export var start_fraction: float = 0.25
@export var color: Color = Color(1.0, 0.86, 0.4)
## Sounds at least SoundCategoryTable.player_loud_radius (m) get this.
@export var loud_color: Color = Color(1.0, 0.42, 0.25)

const SHADER := preload("res://effects/noise_ring.gdshader")

var _rings: Array[MeshInstance3D] = []
## Per ring: {age, radius, alpha0} (age < 0 = free).
var _state: Array[Dictionary] = []
## Rings spawned so far (tests).
var spawned: int = 0


func _ready() -> void:
	add_to_group(&"noise_rings")
	for i in pool_size:
		var mi := MeshInstance3D.new()
		mi.name = "Ring%d" % i
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		mi.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_rings.append(mi)
		_state.append({"age": -1.0, "radius": 0.0, "alpha0": 1.0})
	EventBus.sound_emitted.connect(_on_sound_emitted)
	set_process(false)


func _on_sound_emitted(position: Vector3, radius: float, intensity: float, _category: StringName, source: Node) -> void:
	var p := GameManager.player
	if p == null or source != p or radius <= 0.0:
		return
	if p.has_method(&"is_dead") and p.is_dead():
		return
	spawn(position, radius, intensity)


## Show a ring (reuses the oldest when the pool is full).
func spawn(position: Vector3, radius: float, intensity: float = 1.0) -> void:
	var idx := -1
	var oldest := -1.0
	for i in _state.size():
		var a: float = _state[i].age
		if a < 0.0:
			idx = i
			break
		if a > oldest:
			oldest = a
			idx = i
	if idx < 0:
		return
	var mi := _rings[idx]
	_state[idx] = {"age": 0.0, "radius": radius, "alpha0": clampf(0.35 + intensity * 0.65, 0.35, 1.0)}
	mi.global_position = Vector3(position.x, position.y + 0.04, position.z)
	var mat := mi.material_override as ShaderMaterial
	mat.set_shader_parameter(&"ring_color", loud_color if radius >= loud_radius() else color)
	mat.set_shader_parameter(&"radius_m", radius)
	_apply(idx)
	mi.visible = true
	spawned += 1
	set_process(true)


static func loud_radius() -> float:
	return SoundManager.categories.player_loud_radius if SoundManager.categories else 10.0


func active_count() -> int:
	var n := 0
	for st in _state:
		if float(st.age) >= 0.0:
			n += 1
	return n


## Radii of the visible rings (tests).
func active_radii() -> Array[float]:
	var out: Array[float] = []
	for st in _state:
		if float(st.age) >= 0.0:
			out.append(float(st.radius))
	return out


func _process(delta: float) -> void:
	var any := false
	for i in _state.size():
		var st: Dictionary = _state[i]
		if float(st.age) < 0.0:
			continue
		st.age = float(st.age) + delta
		if st.age >= lifetime:
			st.age = -1.0
			_rings[i].visible = false
			continue
		any = true
		_apply(i)
	if not any:
		set_process(false)


func _apply(i: int) -> void:
	var st: Dictionary = _state[i]
	var t := clampf(float(st.age) / lifetime, 0.0, 1.0)
	# Fast expansion (ease-out), slower fade.
	var grow := 1.0 - pow(1.0 - t, 3.0)
	var r: float = float(st.radius) * lerpf(start_fraction, 1.0, grow)
	_rings[i].scale = Vector3(r, 1.0, r)
	var mat := _rings[i].material_override as ShaderMaterial
	mat.set_shader_parameter(&"radius_m", r)
	mat.set_shader_parameter(&"alpha", float(st.alpha0) * (1.0 - t * t))
