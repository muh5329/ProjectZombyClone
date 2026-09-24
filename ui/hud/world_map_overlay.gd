class_name WorldMapOverlay
extends CanvasLayer
## Full-screen map of the generated world (Round 11): M (action
## `toggle_map`) toggles it. The picture is WorldMapRenderer's render of
## the WorldBuilder's layout (made on first open, ~0.2 s) with settlement
## names and a live player marker (position + facing).
## Round 12: F2 (`toggle_chunk_debug`) adds the streaming debug layer —
## the chunk grid (loaded chunks green, queued amber, the chunk being
## built outlined), the number of simulated zombies per chunk, the data
## groups as dots (red = investigating a noise, orange = migrating) and
## the live zombies — and opens the map if it is closed.

const MPP := 1.5

var panel: Control
var map_rect: TextureRect
var marker: Control
var title: Label
var is_open: bool = false
var _texture: ImageTexture
var _labels: Array[Label] = []
## Round 12 chunk debug layer (F2).
var debug_chunks: bool = false
var debug_label: Label


func _ready() -> void:
	layer = 6
	add_to_group(&"world_map_overlay")
	panel = Control.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	add_child(panel)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	map_rect = TextureRect.new()
	map_rect.name = "Map"
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	panel.add_child(map_rect)
	marker = Control.new()
	marker.name = "Marker"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.draw.connect(_draw_marker)
	map_rect.add_child(marker)
	title = Label.new()
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", Color(0.92, 0.9, 0.84))
	title.position = Vector2(24, 12)
	panel.add_child(title)
	debug_label = Label.new()
	debug_label.name = "DebugStats"
	debug_label.add_theme_font_size_override(&"font_size", 14)
	debug_label.add_theme_color_override(&"font_color", Color(0.85, 0.95, 0.8))
	debug_label.position = Vector2(24, 40)
	debug_label.visible = false
	panel.add_child(debug_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_map") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_chunk_debug") and not event.is_echo():
		set_debug(not debug_chunks)
		get_viewport().set_input_as_handled()


## Chunk debug layer on / off (opens the map when turning it on).
func set_debug(on: bool) -> void:
	debug_chunks = on
	debug_label.visible = on
	if on and not is_open:
		set_open(true)
	_update_marker()


func toggle() -> void:
	set_open(not is_open)


func set_open(on: bool) -> void:
	var b := WorldBuilder.of(get_tree())
	if on and (b == null or b.layout == null):
		return
	is_open = on
	panel.visible = on
	if on:
		if _texture == null:
			_render(b)
		_layout_rect()
		_update_marker()


func _render(b: WorldBuilder) -> void:
	_texture = ImageTexture.create_from_image(WorldMapRenderer.render(b.layout, MPP))
	map_rect.texture = _texture
	var town := ""
	for s in b.layout.settlements:
		if s.kind == &"farmstead":
			continue
		var l := Label.new()
		l.text = String(s.name)
		l.add_theme_font_size_override(&"font_size", 15 if s.kind == &"town" else 12)
		l.add_theme_color_override(&"font_color", Color(1, 1, 1))
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override(&"outline_size", 4)
		l.set_meta(&"world", s.center)
		map_rect.add_child(l)
		_labels.append(l)
		if s.kind == &"town":
			town = String(s.name)
	title.text = "%s county  ·  seed %d  ·  M: close" % [town, b.world_seed]


func _layout_rect() -> void:
	var vp := get_viewport().get_visible_rect().size
	var side := minf(vp.y - 80.0, vp.x - 80.0)
	map_rect.size = Vector2(side, side)
	map_rect.position = Vector2((vp.x - side) * 0.5, (vp.y - side) * 0.5 + 16.0)
	marker.size = map_rect.size
	var b := WorldBuilder.of(get_tree())
	for l in _labels:
		var w: Vector2 = l.get_meta(&"world")
		l.position = w / b.layout.size * side - Vector2(l.get_combined_minimum_size().x * 0.5, 22.0)


func _process(_delta: float) -> void:
	if is_open:
		_update_marker()


func _update_marker() -> void:
	marker.queue_redraw()


## The player's map position (0..1) and facing (radians, 0 = +Z).
func player_uv() -> Vector2:
	var b := WorldBuilder.of(get_tree())
	var p := GameManager.player as Node3D
	if b == null or p == null or not is_instance_valid(p):
		return Vector2(-1, -1)
	return Vector2(p.global_position.x, p.global_position.z) / b.layout.size


func _draw_marker() -> void:
	if debug_chunks:
		_draw_debug()
	var uv := player_uv()
	if uv.x < 0.0:
		return
	var c := uv * map_rect.size
	var p := GameManager.player as Node3D
	var fwd := Vector2(0, 1)
	var mv: Variant = p.get(&"movement") if p != null else null
	if mv != null:
		# MovementComponent.facing = atan2(-dir.x, -dir.z).
		var yaw := float((mv as Object).get(&"facing"))
		fwd = Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-fwd.y, fwd.x)
	marker.draw_circle(c, 9.0, Color(0, 0, 0, 0.6))
	marker.draw_colored_polygon(PackedVector2Array([c + fwd * 10.0, c - fwd * 6.0 + side * 6.0, c - fwd * 6.0 - side * 6.0]),
		Color(1.0, 0.25, 0.2))


# --- Round 12: streaming debug layer --------------------------------------------------------

## Chunk grid, loaded / queued chunks, simulated zombies per chunk, data
## groups and live zombies.
func _draw_debug() -> void:
	var b := WorldBuilder.of(get_tree())
	if b == null or b.layout == null:
		return
	var st := ChunkStreamer.of(get_tree())
	var pd := PopulationDirector.of(get_tree())
	var scale := map_rect.size / b.layout.size
	var cs := b.layout.chunk_size
	var queued := {}
	if st != null:
		for c in st.queued():
			queued[c] = true
	var counts: Dictionary = pd.population.chunk_counts() if pd != null and pd.population != null else {}
	var font := ThemeDB.fallback_font
	for cz in b.layout.chunks_z():
		for cx in b.layout.chunks_x():
			var c := Vector2i(cx, cz)
			var r := Rect2(Vector2(c) * cs * scale, Vector2(cs, cs) * scale)
			if b.chunks.has(c):
				marker.draw_rect(r.grow(-1.0), Color(0.3, 1.0, 0.45, 0.9), false, 2.0)
			elif b.building_chunks.has(c):
				marker.draw_rect(r, Color(1.0, 0.9, 0.2, 0.35))
			elif queued.has(c):
				marker.draw_rect(r, Color(1.0, 0.6, 0.1, 0.3))
			else:
				# Not loaded: data only (dimmed).
				marker.draw_rect(r, Color(0.0, 0.0, 0.05, 0.35))
			marker.draw_rect(r, Color(1, 1, 1, 0.25), false, 1.0)
			var n := int(counts.get(c, 0))
			if n > 0:
				marker.draw_string(font, r.position + Vector2(3, 13), str(n), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.85, 0.8))
	if pd != null and pd.population != null:
		for id in pd.population.groups:
			var g: Dictionary = pd.population.groups[id]
			var col := Color(0.95, 0.95, 0.95, 0.85)
			match int(g.state):
				ZombiePopulation.State.INVESTIGATE:
					col = Color(1.0, 0.2, 0.15)
				ZombiePopulation.State.MIGRATE:
					col = Color(1.0, 0.6, 0.1)
			var rad := 1.5 + sqrt(float((g.members as PackedInt32Array).size()))
			marker.draw_circle((g.pos as Vector2) * scale, rad, col)
		for z in pd.real_zombies():
			marker.draw_circle(Vector2(z.global_position.x, z.global_position.z) * scale, 2.0, Color(0.3, 1.0, 0.4))
		debug_label.text = "F2 chunk debug · loaded (green frame) %d/%d chunks · simulated %d zombies in %d groups (white · red investigating · orange migrating) · live %d / %d (green) · dead %d" % [
			b.chunks.size(), b.recipes.size(), pd.population.total(), pd.population.groups.size(),
			pd.active_count(), pd.max_active, pd.died_count]
	elif debug_label != null:
		debug_label.text = "F2 chunk debug · loaded %d chunks" % b.chunks.size()
