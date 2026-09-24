class_name WorldNav
extends NavBaker
## Chunked navigation for the generated world (Round 11). Replaces the
## single-region NavBaker in maps/world.tscn but keeps its contract
## (group "nav_baker", `baked`, `navigation_ready`, `rebaked`,
## `request_rebake()`, `bake_now()`, `bake_ms`), so ZombieSpawner,
## SaveManager and FurnitureWork work unchanged.
##
## One NavigationRegion3D per 64 m chunk ("Nav_x_z"), baked for the chunks
## within [radius] of the focus (the player; SaveManager sets it to the
## saved player position via focus_on() before a load's bake). Each
## chunk's source geometry is parsed once from its chunk node (static
## colliders on layer 1) + the ground quad, merged with its 8 neighbours
## and baked on a worker thread with a border so neighbouring tiles meet.
##
## No coroutines: everything is driven from _physics_process, so freeing
## the map mid-bake leaves nothing suspended. A handed-over region only
## counts once it is *verified*: the server processed its mesh (iteration
## id > 0), the map lists it, and a closest-point query at a probe point
## on its mesh answers within 1 m. navigation_ready / rebaked are emitted
## only after every region involved is verified (under heavy load the
## server can lag many frames behind the hand-over).
##
## While walking: chunks within [radius] of the player and of a point
## [lookahead] seconds ahead along the player's velocity are queued (up to
## [max_parallel] background bakes); regions farther than [keep_radius]
## are freed (hysteresis: keep_radius > radius), with their parsed sources.

## Emitted when a region is added or freed (the spawner re-checks groups).
signal chunk_regions_changed

## Chebyshev chunk radius baked around the focus.
@export var radius: int = 2
## Regions beyond this Chebyshev distance from the player are freed.
@export var keep_radius: int = 4
## Seconds of walking ahead (along the velocity) that are pre-baked.
@export var lookahead: float = 4.0
## Background bakes in flight at once while walking.
@export var max_parallel: int = 2
## Border (m) baked beyond each chunk and cut away again (a multiple of
## cell_size so tile edges align).
@export var border: float = 2.4
## Frames to wait for verification before emitting anyway (warning).
@export var verify_timeout_frames: int = 900

var builder: WorldBuilder
## Vector2i → NavigationRegion3D (null while its first bake runs).
var regions: Dictionary = {}
## Stats for tests / perf: regions freed, verification frames of the last
## initial bake, max regions alive.
var freed_count: int = 0
var verify_frames: int = 0
var max_alive: int = 0
## Main-thread µs spent handing regions over (_apply_chunk) since the
## counter was last reset (perf probes read and zero it).
var apply_usec: int = 0

var _sources: Dictionary = {}
var _probe: Dictionary = {}  # Vector2i → Vector3 (a point on the region's mesh)
var _pending: Dictionary = {}  # Vector2i → purpose ("initial" / "rebake" / "queue")
var _focus: Vector3 = Vector3.INF
var _last_chunk: Vector2i = Vector2i(-999, -999)
var _poll: float = 0.0
var _queue: Array[Vector2i] = []
var _wait: int = -1  # physics frames left before the initial bake (-1 = idle)
var _verify: String = ""  # "" / "initial" / "rebake"
var _verify_chunks: Array[Vector2i] = []
var _verify_count: int = 0
var _verify_iter: int = -1
var _rebake_chunk: Vector2i = Vector2i(-999, -999)
var _warned: bool = false
var _tasks: Dictionary = {}  # WorkerThreadPool task id → true (bakes in flight)
var _ready_cache: Dictionary = {}  # Vector2i → the verified region
var _ready_asked: Dictionary = {}  # Vector2i → physics frame of the last check


func _ready() -> void:
	add_to_group(&"nav_baker")
	_match_map_cells()
	# Round 12: on a 2-core machine two background bakes starve the main
	# thread (chunk building / zombies measured 3-10× slower meanwhile).
	if OS.get_processor_count() <= 2:
		max_parallel = mini(max_parallel, 1)
	# This node only coordinates: its own region stays empty and disabled.
	navigation_mesh = null
	enabled = false
	if bake_on_ready:
		_wait = maxi(wait_frames, 0)


func _find_builder() -> WorldBuilder:
	if builder == null or not is_instance_valid(builder):
		builder = WorldBuilder.of(get_tree())
	return builder


## Bake around [p] next time (a load: the saved player position).
func focus_on(p: Vector3) -> void:
	_focus = p


func _focus_point() -> Vector3:
	if _focus != Vector3.INF:
		return _focus
	var pl := GameManager.player as Node3D
	if pl != null and is_instance_valid(pl) and pl.is_inside_tree():
		return pl.global_position
	var b := _find_builder()
	return b.start_position() if b != null and b.layout != null else Vector3.ZERO


func _new_mesh(c: Vector2i) -> NavigationMesh:
	var cs := builder.layout.chunk_size
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = geometry_mask
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.agent_radius = agent_radius
	nm.agent_height = agent_height
	nm.agent_max_climb = 0.3
	nm.cell_size = cell_size
	nm.cell_height = cell_height
	nm.border_size = border
	nm.filter_baking_aabb = AABB(Vector3(c.x * cs - border, -2.0, c.y * cs - border),
		Vector3(cs + 2.0 * border, 8.0, cs + 2.0 * border))
	return nm


## Source geometry of one chunk node (+ its ground quad), parsed once.
func _source_of(c: Vector2i, fresh: bool = false) -> NavigationMeshSourceGeometryData3D:
	if _sources.has(c) and not fresh:
		return _sources[c]
	_parse_jobs.erase(c)
	while not _parse_step(c):
		if not builder.chunks.has(c):
			return null
	return _sources[c]


var _parse_jobs: Dictionary = {}  # Vector2i → {src, nodes}
const _PARSE_GROUP := &"_world_nav_parse"


## Parse chunk [c]'s source geometry incrementally: one child node (a
## building, a vehicle, the Solids body…) per call. True when complete
## (then _sources[c] is set).
func _parse_step(c: Vector2i) -> bool:
	var node: Node3D = builder.chunks.get(c)
	if node == null:
		_parse_jobs.erase(c)
		return false
	if _parse_jobs.has(c) and _parse_jobs[c].get("node") != node:
		_parse_jobs.erase(c)  # the chunk was unloaded and rebuilt meanwhile
	if not _parse_jobs.has(c):
		var nodes: Array = []
		for ch in node.get_children():
			if ch.name == "Buildings" or ch.name == "Vehicles":
				nodes.append_array(ch.get_children())
			elif ch.name != "Solids":
				# The Solids body (fences, props, trunks: hundreds of
				# shapes) is turned into faces from the chunk recipe on the
				# bake worker thread instead (_solid_faces).
				nodes.append(ch)
		_parse_jobs[c] = {"src": NavigationMeshSourceGeometryData3D.new(), "nodes": nodes, "node": node}
	var job: Dictionary = _parse_jobs[c]
	var nodes2: Array = job.nodes
	while not nodes2.is_empty():
		var nv: Variant = nodes2.pop_front()  # untyped: may have been freed
		if not is_instance_valid(nv) or not (nv as Node).is_inside_tree():
			continue
		var n: Node = nv
		var nm := _new_mesh(c)
		nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
		nm.geometry_source_group_name = _PARSE_GROUP
		var part := NavigationMeshSourceGeometryData3D.new()
		n.add_to_group(_PARSE_GROUP)
		NavigationServer3D.parse_source_geometry_data(nm, part, n)
		n.remove_from_group(_PARSE_GROUP)
		(job.src as NavigationMeshSourceGeometryData3D).merge(part)
		break
	if not nodes2.is_empty():
		return false
	var src: NavigationMeshSourceGeometryData3D = job.src
	var cs := builder.layout.chunk_size
	var x0 := c.x * cs
	var z0 := c.y * cs
	src.add_faces(PackedVector3Array([
		Vector3(x0, 0, z0), Vector3(x0 + cs, 0, z0), Vector3(x0 + cs, 0, z0 + cs),
		Vector3(x0, 0, z0), Vector3(x0 + cs, 0, z0 + cs), Vector3(x0, 0, z0 + cs)]), Transform3D.IDENTITY)
	_sources[c] = src
	_parse_jobs.erase(c)
	return true


## Chunks within [radius] of [p] (only those the builder built).
func wanted_chunks(p: Vector3, r: int = -1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var b := _find_builder()
	if b == null or b.layout == null:
		return out
	for c in b.layout.chunks_around(b.layout.chunk_of(Vector2(p.x, p.z)), radius if r < 0 else r):
		if b.chunks.has(c):
			out.append(c)
	return out


func bake_now() -> void:
	_wait = -1
	if not _pending.is_empty() or _find_builder() == null or not builder.built:
		_wait = 1  # try again next frame
		return
	baked = false
	_bake_started_at = Time.get_ticks_msec()
	var p := _focus_point()
	_last_chunk = builder.layout.chunk_of(Vector2(p.x, p.z))
	var list := wanted_chunks(p)
	for c in list:
		_bake_chunk(c, "initial")
	if list.is_empty():
		_start_verify("initial", [])


func _bake_chunk(c: Vector2i, purpose: String, fresh: bool = false) -> void:
	var b := _find_builder()
	var parts: Array = []
	var solids: Array = []
	for nb in b.layout.chunks_around(c, 1):
		if not b.chunks.has(nb):
			continue
		var part := _source_of(nb, fresh and nb == c)
		if part != null:
			parts.append(part)
			solids.append((b.recipes.get(nb, {}) as Dictionary).get("solids", []))
	var nm := _new_mesh(c)
	if not regions.has(c):
		regions[c] = null
	_pending[c] = purpose
	# Round 12: merging the 3 x 3 sources copies every vertex (10-30 ms on
	# the main thread in town): merge and bake on a worker thread. Parsed
	# sources are never modified once complete.
	var tid := WorkerThreadPool.add_task(_merge_and_bake.bind(parts, solids, nm, _apply_chunk.bind(c, nm)), false, "WorldNav chunk bake")
	_tasks[tid] = true


## Worker thread: merge the neighbour sources and bake (thread-safe
## server call); the hand-over is deferred to the main thread. Static: it
## never touches the node (which may be freed meanwhile; _exit_tree waits
## for running tasks anyway).
static func _merge_and_bake(parts: Array, solids: Array, nm: NavigationMesh, done: Callable) -> void:
	var src := NavigationMeshSourceGeometryData3D.new()
	for part in parts:
		src.merge(part)
	var aabb := nm.filter_baking_aabb
	for list in solids:
		var faces := solid_faces(list, aabb)
		if not faces.is_empty():
			src.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	done.call_deferred()


## Triangles of a chunk recipe's solids ([shape, transform]: boxes and
## cylinders — 8-sided prisms) whose centre lies within [aabb] grown by
## the shape's size (the rest is cut away by the bake anyway).
static func solid_faces(solids: Array, aabb: AABB) -> PackedVector3Array:
	var out := PackedVector3Array()
	var grown := aabb.grow(3.0)
	for e in solids:
		var shape: Shape3D = e[0]
		var xf: Transform3D = e[1]
		if not grown.has_point(xf.origin):
			continue
		if shape is BoxShape3D:
			var h := (shape as BoxShape3D).size * 0.5
			var v: Array[Vector3] = []
			for k in 8:
				v.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
			for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
				out.append_array([v[q[0]], v[q[1]], v[q[2]], v[q[0]], v[q[2]], v[q[3]]])
		elif shape is CylinderShape3D:
			# CRITIC FIX: tree trunks (thin cylinders) are not carved out of
			# the navmesh: they fragment the woods into ~4x the polygons of a
			# town chunk; zombies slide around trunks (move_and_slide).
			if (shape as CylinderShape3D).radius < 0.45:
				continue
			var r := (shape as CylinderShape3D).radius
			var hh := (shape as CylinderShape3D).height * 0.5
			var ring: Array[Vector2] = []
			for k in 8:
				var a := TAU * k / 8.0
				ring.append(Vector2(cos(a), sin(a)) * r)
			var top := xf * Vector3(0, hh, 0)
			for k in 8:
				var p0 := ring[k]
				var p1 := ring[(k + 1) % 8]
				var a0 := xf * Vector3(p0.x, -hh, p0.y)
				var a1 := xf * Vector3(p1.x, -hh, p1.y)
				var b0 := xf * Vector3(p0.x, hh, p0.y)
				var b1 := xf * Vector3(p1.x, hh, p1.y)
				out.append_array([a0, a1, b1, a0, b1, b0, top, b1, b0])
	return out


func _exit_tree() -> void:
	for tid in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(tid)
	_tasks.clear()


func _on_chunk_baked(c: Vector2i, nm: NavigationMesh) -> void:
	# May arrive on a worker thread: hand over on the main thread (a
	# deferred call on a freed node is simply dropped).
	_apply_chunk.call_deferred(c, nm)


func _apply_chunk(c: Vector2i, nm: NavigationMesh) -> void:
	for tid in _tasks.keys():
		if WorkerThreadPool.is_task_completed(tid):
			WorkerThreadPool.wait_for_task_completion(tid)
			_tasks.erase(tid)
	if not is_inside_tree():
		return
	var t0 := Time.get_ticks_usec()
	_hand_over(c, nm)
	apply_usec += Time.get_ticks_usec() - t0


func _hand_over(c: Vector2i, nm: NavigationMesh) -> void:
	var purpose: String = _pending.get(c, "queue")
	_pending.erase(c)
	if not regions.has(c) and purpose == "queue":
		return  # freed while baking
	var old: NavigationRegion3D = regions.get(c)
	var region := NavigationRegion3D.new()
	region.name = "Nav_%02d_%02d" % [c.x, c.y]
	region.navigation_mesh = nm
	if old != null and is_instance_valid(old):
		# Re-bake: the new region replaces the old one (the old mesh stays
		# live until the new one is in).
		old.name = old.name + "_old"
		old.queue_free()
	add_child(region)
	regions[c] = region
	_probe[c] = _probe_point(nm, c)
	max_alive = maxi(max_alive, regions.size())
	if purpose == "initial" and not _pending.values().has("initial"):
		_start_verify("initial", regions.keys())
	elif purpose == "rebake":
		_start_verify("rebake", [c])
	chunk_regions_changed.emit()


## A navmesh vertex near the chunk centre (the query target that proves
## the region is live), or INF for an empty mesh.
func _probe_point(nm: NavigationMesh, c: Vector2i) -> Vector3:
	var verts := nm.get_vertices()
	if verts.is_empty():
		return Vector3.INF
	var cs := builder.layout.chunk_size
	var centre := Vector3((c.x + 0.5) * cs, 0.0, (c.y + 0.5) * cs)
	var best := Vector3.INF
	var bd := INF
	for i in range(0, verts.size(), maxi(1, verts.size() / 64)):
		var v := verts[i]
		var d := v.distance_squared_to(centre)
		if d < bd:
			bd = d
			best = v
	return best


func _start_verify(kind: String, list: Array) -> void:
	_verify = kind
	_verify_chunks.clear()
	for c in list:
		_verify_chunks.append(c)
	_verify_count = 0
	_verify_iter = NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)


## True when every region in [list] is processed, on the map and answers
## a closest-point query at its probe point (within 1 m).
func regions_verified(list: Array) -> bool:
	var map := get_world_3d().navigation_map
	var on_map := NavigationServer3D.map_get_regions(map)
	for c in list:
		var r: NavigationRegion3D = regions.get(c)
		if r == null or not is_instance_valid(r) or not r.is_inside_tree():
			continue
		var rid := r.get_rid()
		if NavigationServer3D.region_get_iteration_id(rid) <= 0 or not on_map.has(rid):
			return false
		var pr: Vector3 = _probe.get(c, Vector3.INF)
		if pr != Vector3.INF and NavigationServer3D.map_get_closest_point(map, pr).distance_to(pr) > 1.0:
			return false
	return true


func _step_verify() -> void:
	_verify_count += 1
	var map := get_world_3d().navigation_map
	var synced := NavigationServer3D.map_get_iteration_id(map) != _verify_iter or _verify_chunks.is_empty()
	var ok := synced and regions_verified(_verify_chunks)
	if not ok and _verify_count < verify_timeout_frames:
		return
	if not ok and not _warned:
		_warned = true
		push_warning("WorldNav: regions not queryable after %d frames; continuing" % _verify_count)
	var kind := _verify
	_verify = ""
	if kind == "initial":
		verify_frames = _verify_count
		bake_ms = float(Time.get_ticks_msec() - _bake_started_at)
		_focus = Vector3.INF
		baked = true
		print("WorldNav: %d chunk regions baked in %.0f ms (verified after %d frames)" % [regions.size(), bake_ms, _verify_count])
		navigation_ready.emit()
	else:
		_rebaking = false
		rebake_count += 1
		rebaked.emit()
		if _rebake_queued:
			_rebake_queued = false
			request_rebake()


## Furniture moved / destroyed: re-parse and re-bake the chunk under the
## player (async; the old mesh stays live meanwhile).
func request_rebake() -> void:
	if not baked or _pending.values().has("initial") or _rebaking:
		_rebake_queued = true
		return
	var p := _focus_point()
	var c := builder.layout.chunk_of(Vector2(p.x, p.z))
	if not builder.chunks.has(c):
		return
	_rebaking = true
	_rebake_queued = false
	_bake_started_at = Time.get_ticks_msec()
	_rebake_chunk = c
	_bake_chunk(c, "rebake", true)


## Background bakes for chunks that came into range. Source geometry is
## parsed on the main thread, so at most one chunk node is parsed per
## tick (no frame spike); the bake itself runs on a worker thread.
func _drain_queue() -> void:
	var parsed := false
	while not _queue.is_empty() and _pending.size() < max_parallel and not _rebaking:
		var c: Vector2i = _queue.front()
		if regions.has(c):
			_queue.pop_front()
			continue
		for nb in builder.layout.chunks_around(c, 1):
			if builder.chunks.has(nb) and not _sources.has(nb):
				if parsed:
					return
				# Round 12: one child node per tick (a town chunk parsed in
				# one go took ~25 ms on the main thread).
				parsed = true
				if not _parse_step(nb):
					return
		_queue.pop_front()
		_bake_chunk(c, "queue")


## Free regions (and parsed sources) beyond keep_radius of the player.
func _free_far(pc: Vector2i) -> void:
	for c in regions.keys():
		var cc: Vector2i = c
		if maxi(absi(cc.x - pc.x), absi(cc.y - pc.y)) <= keep_radius or _pending.has(cc):
			continue
		var r: NavigationRegion3D = regions[cc]
		if r != null and is_instance_valid(r):
			r.queue_free()
		regions.erase(cc)
		_probe.erase(cc)
		freed_count += 1
		chunk_regions_changed.emit()
	for c2 in _sources.keys():
		var s2: Vector2i = c2
		if maxi(absi(s2.x - pc.x), absi(s2.y - pc.y)) > keep_radius + 1:
			_sources.erase(s2)
	for c3 in _parse_jobs.keys():
		if not builder.chunks.has(c3):
			_parse_jobs.erase(c3)


## µs of the last _physics_process (perf probes).
var tick_usec: int = 0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_tick(delta)
	tick_usec = Time.get_ticks_usec() - t0


func _tick(delta: float) -> void:
	if _wait >= 0:
		if _wait == 0:
			_wait = -1
			if is_inside_tree():
				bake_now()
		else:
			_wait -= 1
		return
	if _verify != "":
		_step_verify()
		return
	if not baked or builder == null or not is_instance_valid(builder):
		return
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	var pl := GameManager.player as Node3D
	if pl == null or not is_instance_valid(pl) or not pl.is_inside_tree():
		return
	var pos := pl.global_position
	var c := builder.layout.chunk_of(Vector2(pos.x, pos.z))
	var vel := Vector3.ZERO
	if pl is CharacterBody3D:
		vel = (pl as CharacterBody3D).velocity
	vel.y = 0.0
	var want := wanted_chunks(pos)
	if vel.length() > 0.5:
		for ac in wanted_chunks(pos + vel * lookahead, 1):
			if not want.has(ac):
				want.append(ac)
	# Nearest first.
	want.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return maxi(absi(a.x - c.x), absi(a.y - c.y)) < maxi(absi(b.x - c.x), absi(b.y - c.y)))
	for nc in want:
		if not regions.has(nc) and not _queue.has(nc):
			_queue.append(nc)
	if c != _last_chunk:
		_last_chunk = c
		_free_far(c)
	_drain_queue()


func baked_chunks() -> Array:
	var out: Array = []
	for c in regions:
		if regions[c] != null:
			out.append(c)
	return out


## Whether chunk [c] has a live, verified region (spawning checks this).
## Round 12: a positive answer is cached until the region changes —
## navigation queries every few frames (the population director asks for
## every active chunk) kept the navigation map busy (~15 ms per physics
## frame on the 2-core box).
func chunk_ready(c: Vector2i) -> bool:
	if regions.get(c) == null:
		return false
	var r: NavigationRegion3D = regions[c]
	if _ready_cache.get(c) == r:
		return true
	var now := Engine.get_physics_frames()
	if int(_ready_asked.get(c, -100)) > now - 10:
		return false
	_ready_asked[c] = now
	if regions_verified([c]):
		_ready_cache[c] = r
		return true
	return false
