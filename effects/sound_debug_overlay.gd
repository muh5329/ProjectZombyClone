class_name SoundDebugOverlay
extends Node3D
## F4 debug view of the sound system (GameManager.sound_debug): a circle
## at every live SoundEvent (its base radius; orange = the player's, cyan
## = anything else, fading over the event's life) and a line from each
## zombie ear that heard something to the sound (green = direct, yellow =
## through an opening) for [line_seconds], labelled with the perceived
## strength (pooled Label3Ds). Drawn with one ImmediateMesh, on top of
## everything. While off it does no work at all (cleared once on the
## switch-off frame).

@export var segments: int = 48
@export var line_seconds: float = 1.5
@export var player_color: Color = Color(1.0, 0.6, 0.15)
@export var other_color: Color = Color(0.3, 0.85, 1.0)
@export var direct_color: Color = Color(0.4, 1.0, 0.4)
@export var opening_color: Color = Color(1.0, 0.95, 0.3)

var _mesh := ImmediateMesh.new()
var _mi: MeshInstance3D
## Circles / lines drawn in the last frame (tests).
var drawn_circles: int = 0
var drawn_lines: int = 0
## Frames actually drawn (tests: must not grow while off).
var redraws: int = 0
@export var max_labels: int = 24
var _labels: Array[Label3D] = []
var _was_on: bool = false


func _ready() -> void:
	add_to_group(&"sound_debug")
	_mi = MeshInstance3D.new()
	_mi.name = "Lines"
	_mi.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	_mi.material_override = mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)
	for i in max_labels:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0012
		l.font_size = 40
		l.outline_size = 8
		l.render_priority = 11
		l.visible = false
		add_child(l)
		_labels.append(l)


## Label texts currently shown (tests).
func label_texts() -> Array[String]:
	var out: Array[String] = []
	for l in _labels:
		if l.visible:
			out.append(l.text)
	return out


func _process(_delta: float) -> void:
	if not GameManager.sound_debug:
		if _was_on:
			_was_on = false
			_mesh.clear_surfaces()
			_mi.visible = false
			drawn_circles = 0
			drawn_lines = 0
			for l in _labels:
				l.visible = false
		return
	_was_on = true
	_mi.visible = true
	redraws += 1
	_mesh.clear_surfaces()
	drawn_circles = 0
	drawn_lines = 0
	var li := 0
	var t := SoundManager.now()
	var player := GameManager.player
	var events := SoundManager.active_events()
	var hearings := SoundManager.recent_hearings(line_seconds)
	if events.is_empty() and hearings.is_empty():
		for l in _labels:
			l.visible = false
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for ev in events:
		var c := player_color if player != null and ev.is_from(player) else other_color
		c.a = 0.25 + 0.75 * ev.life_fraction(t)
		_circle(ev.position, ev.radius, c)
		_circle(ev.position, 0.25, c)
		drawn_circles += 1
	for h in hearings:
		var c := opening_color if h.path == &"opening" else direct_color
		c.a = clampf(1.0 - (t - float(h.time)) / line_seconds, 0.15, 1.0)
		var a: Vector3 = h.ear
		var b: Vector3 = h.at
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(a)
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(b.x, b.y + 0.1, b.z))
		drawn_lines += 1
		if li < _labels.size():
			var l := _labels[li]
			l.text = "%.2f" % float(h.strength)
			l.modulate = c
			l.global_position = a + Vector3.UP * 0.35
			l.visible = true
			li += 1
	for k in range(li, _labels.size()):
		_labels[k].visible = false
	_mesh.surface_end()


func _circle(center: Vector3, r: float, c: Color) -> void:
	var y := center.y + 0.06
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(center.x + cos(a0) * r, y, center.z + sin(a0) * r))
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(Vector3(center.x + cos(a1) * r, y, center.z + sin(a1) * r))
