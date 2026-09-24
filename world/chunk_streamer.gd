class_name ChunkStreamer
extends Node
## World streaming (Round 12; node "Streamer" in maps/world.tscn, after
## "Generated"). The layout and every chunk's recipe stay in memory
## (WorldBuilder); chunk CONTENT is instantiated within [load_radius]
## (Chebyshev, chunks) of the player and freed beyond [unload_radius]
## (hysteresis).
##
## - Loading is spread over frames: a chunk is built step by step (base
##   meshes + collision, then building by building, then lights / vehicles
##   / props, then "finish") and each frame runs steps until [budget_ms]
##   is spent (always at least one). Chunks are queued nearest first,
##   those ahead of the player's walking direction earlier (priority()).
## - The player never stands in an unbuilt chunk: when the player's chunk
##   or a neighbour (within [sync_radius]) is missing it is built right
##   away (a teleport / a load); when that takes longer than 100 ms the
##   HUD says "Loading area…".
## - A chunk's saveables get their generated default recorded when built,
##   then the WorldStateStore deltas applied (and destroyed ids removed);
##   dropped items, corpses and blood of the chunk come back from the
##   store. Before a chunk is freed: chunk_unloading (the population
##   director folds its zombies back into data), then the saveables'
##   deltas, items, corpses and blood are captured into the store.
## - Saves: live_snapshot() = the store + the deltas of the loaded chunks
##   (nothing unloaded). A load hands the saved store over through
##   WorldConfig.stream_state before _ready.

signal chunk_loaded(c: Vector2i)
signal chunk_unloading(c: Vector2i)
signal chunk_unloaded(c: Vector2i)

const GROUP := &"chunk_streamer"

## Chunks within this Chebyshev radius of the player are loaded.
@export var load_radius: int = 3
## Loaded chunks beyond this radius are freed (> load_radius).
@export var unload_radius: int = 4
## Chunks within this radius are built synchronously when missing.
@export var sync_radius: int = 1
## Built synchronously at _ready (the rest follows over frames).
@export var initial_radius: int = 2
## Build time per frame (ms); at least one step always runs.
@export var budget_ms: float = 4.0
## Seconds of walking ahead that raise a chunk's priority.
@export var lookahead: float = 3.0
## Streaming on (false: the builder builds everything, Round 11).
@export var enabled: bool = true

var builder: WorldBuilder
var store := WorldStateStore.new()
## Vector2i → Array[Node] saveables of a loaded chunk.
var saveables: Dictionary = {}
## Stats (tests / perf): steps run, slowest step (ms), synchronous loads,
## chunks loaded / unloaded, last frame's build ms.
var steps_run: int = 0
var max_step_ms: float = 0.0
var sync_loads: int = 0
var loads: int = 0
var unloads: int = 0
var frame_ms: float = 0.0
var max_step_name: String = ""
var max_free_ms: float = 0.0
## ms spent pre-building one building of each kind at load.
var prewarm_ms: float = 0.0
var max_free_name: String = ""
var total_usec: int = 0

var _queue: Array[Vector2i] = []
## Nodes of unloaded chunks waiting to be freed (spread over frames).
var _trash: Array[Node] = []
var _unload_queue: Array[Vector2i] = []
var _trash_chunks: Dictionary = {}
var _deferred_dynamic: Array = []
var _deferred_frames: int = 0
var _current: Vector2i = Vector2i(-1, -1)
var _steps: Array = []
var _last_chunk: Vector2i = Vector2i(-999, -999)
var _poll: float = 0.0
var _started: bool = false


static func of(tree: SceneTree) -> ChunkStreamer:
	return tree.get_first_node_in_group(GROUP) as ChunkStreamer if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)
	# The builder (an earlier sibling) must not build every chunk itself.
	var b := get_parent().get_node_or_null("Generated") as WorldBuilder if get_parent() != null else null
	if b != null and enabled:
		b.streaming = true


func _ready() -> void:
	builder = WorldBuilder.of(get_tree())
	if builder == null or builder.layout == null or not enabled:
		return
	var cfg := WorldConfig.find(get_tree())
	var focus := builder.start_position()
	if cfg != null and not cfg.stream_state.is_empty():
		store.from_dict(cfg.stream_state)
		var f: Variant = cfg.stream_state.get("focus")
		if f is Vector3:
			focus = f
	_start(focus)


## Build the chunks around [focus] now (map load), queue the rest.
func _start(focus: Vector3) -> void:
	_started = true
	var fc := chunk_at(focus)
	for c in order(chunks_within(fc, initial_radius, dims()), Vector2(focus.x, focus.z), Vector2.ZERO, cs()):
		load_now(c)
	prewarm_ms = builder.prewarm_kinds()
	builder.built = true
	_last_chunk = Vector2i(-999, -999)
	_refresh(focus, Vector3.ZERO)


# --- Pure helpers (unit-tested) ----------------------------------------------------------

func dims() -> Vector2i:
	return Vector2i(builder.layout.chunks_x(), builder.layout.chunks_z())


func cs() -> float:
	return builder.layout.chunk_size


func chunk_at(p: Vector3) -> Vector2i:
	return builder.layout.chunk_of(Vector2(p.x, p.z))


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## Chunks within Chebyshev [r] of [center], clamped to a [size] grid.
static func chunks_within(center: Vector2i, r: int, size: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for z in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if x >= 0 and z >= 0 and x < size.x and z < size.y:
				out.append(Vector2i(x, z))
	return out


## Loaded chunks that must be freed: beyond [unload_r] of [center].
static func to_unload(loaded: Array, center: Vector2i, unload_r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in loaded:
		if chebyshev(c, center) > unload_r:
			out.append(c)
	return out


## Lower = sooner: distance from the player to the chunk centre, minus a
## bonus for chunks ahead along the velocity ([look] seconds).
static func priority(c: Vector2i, pos: Vector2, vel: Vector2, size: float, look: float = 3.0) -> float:
	var centre := (Vector2(c) + Vector2(0.5, 0.5)) * size
	var d := pos.distance_to(centre)
	if vel.length() > 0.5:
		var ahead := pos + vel * look
		d = minf(d, ahead.distance_to(centre) + size * 0.25)
	return d


## [list] sorted by priority() (ties: z, then x — deterministic).
static func order(list: Array, pos: Vector2, vel: Vector2, size: float, look: float = 3.0) -> Array[Vector2i]:
	var keyed: Array = []
	for c in list:
		keyed.append([priority(c, pos, vel, size, look), c])
	keyed.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		if a[1].y != b[1].y:
			return a[1].y < b[1].y
		return a[1].x < b[1].x)
	var out: Array[Vector2i] = []
	for k in keyed:
		out.append(k[1])
	return out


# --- Queries ---------------------------------------------------------------------------

func is_loaded(c: Vector2i) -> bool:
	return builder != null and builder.chunks.has(c)


func loaded_chunks() -> Array:
	return builder.chunks.keys() if builder != null else []


func queued() -> Array[Vector2i]:
	return _queue


func is_busy() -> bool:
	return not _queue.is_empty() or not _steps.is_empty()


# --- Loading ---------------------------------------------------------------------------

## Build chunk [c] completely now (and apply its stored state).
func load_now(c: Vector2i) -> void:
	if builder.chunks.has(c):
		return
	if _current == c:
		while not _steps.is_empty():
			_run_step()
		return
	_queue.erase(c)
	for st in builder.chunk_steps(c):
		_do_step(c, st)


## Load every chunk around [p] within [r] synchronously (tests / tools).
func ensure_loaded(p: Vector3, r: int = -1) -> void:
	var rr := sync_radius if r < 0 else r
	for c in order(chunks_within(chunk_at(p), rr, dims()), Vector2(p.x, p.z), Vector2.ZERO, cs()):
		load_now(c)


func _do_step(c: Vector2i, st: Variant) -> void:
	var t0 := Time.get_ticks_usec()
	if st is String and st == "base":
		# The old nodes of this chunk must be gone before it is rebuilt
		# (no two nodes with one persist id).
		if _trash_chunks.has(c):
			free_detached()
			_trash_chunks.clear()
		builder.build_chunk_step(c, st)
		saveables[c] = []
	elif st is int:
		var hb := builder.build_chunk_step(c, st)
		if hb != null:
			_adopt(c, hb)
	elif st is String and st == "nodes":
		builder.build_chunk_step(c, st)
	elif st is String and st.begins_with("v"):
		var veh := builder.build_chunk_step(c, st)
		if veh != null:
			_adopt(c, veh)
	elif st is String and st == "finish":
		_restore_dynamic(c)
		builder.build_chunk_step(c, st)
		loads += 1
		chunk_loaded.emit(c)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	total_usec += Time.get_ticks_usec() - t0
	if ms > max_step_ms:
		max_step_ms = ms
		max_step_name = "%s %s" % [c, st]
	steps_run += 1


## Record the defaults of the saveables under [root], apply the store's
## deltas, remove destroyed ones.
func _adopt(c: Vector2i, root: Node) -> void:
	var list: Array = []
	_collect(root, list)
	var cfg := WorldConfig.find(get_tree())
	var now := TimeManager.now()
	for n in list:
		var id := String(n.get(&"persist_id"))
		store.record_default(id, n.call(&"save_state"))
	for n in list:
		var id := String(n.get(&"persist_id"))
		var d := store.delta_for(id)
		if not d.is_empty():
			n.call(&"load_state", d)
			store.applied += 1
			var el := store.elapsed_for(id, now)
			if el > 0.0 and n is LootContainer:
				WorldStateStore.age_inventory((n as LootContainer).inventory, el)
	if cfg != null and not cfg.destroyed_ids.is_empty():
		for n in list:
			if cfg.destroyed_ids.has(String(n.get(&"persist_id"))) and n.has_method(&"remove_for_load") \
					and is_instance_valid(n) and not n.is_queued_for_deletion():
				n.call(&"remove_for_load")
	(saveables[c] as Array).append_array(list)


static func _collect(n: Node, out: Array) -> void:
	if n.is_in_group(Saveable.GROUP) and n.has_method(&"save_state") and String(n.get(&"persist_id")) != "":
		out.append(n)
	for ch in n.get_children():
		_collect(ch, out)


func _map() -> Node:
	return builder.get_parent()


func _restore_dynamic(c: Vector2i) -> void:
	var d := store.take_dynamic(c)
	if d.is_empty():
		return
	# While the map is still setting up its children (a load builds the
	# first chunks from _ready) nothing can be added to it yet, and the
	# spawner / blood decals are not ready: restore at the end of the frame.
	if not _map().is_node_ready():
		_deferred_dynamic.append(d)
		if _deferred_dynamic.size() == 1:
			_flush_deferred_dynamic.call_deferred()
		return
	_apply_dynamic_record(d)


func _flush_deferred_dynamic() -> void:
	var list := _deferred_dynamic.duplicate()
	_deferred_dynamic.clear()
	for d in list:
		_apply_dynamic_record(d)


func _apply_dynamic_record(d: Dictionary) -> void:
	var el := maxf(TimeManager.now() - float(d.get("t", TimeManager.now())), 0.0)
	var map := _map()
	for rec in d.get("items", []):
		var inst := ItemInstance.from_dict(rec.get("item", {}))
		if inst == null:
			continue
		WorldStateStore.age_item(inst, el)
		var wi := WorldItem.for_instance(inst)
		map.add_child(wi)
		wi.global_position = Saveable.to_vec3(rec.get("position"))
		wi.rotation.y = float(rec.get("yaw", 0.0))
	var sp := map.get_node_or_null("Zombies")
	for rec in d.get("corpses", []):
		var corpse := ZombieCorpse.restore(sp if sp != null else map, rec)
		if corpse.searched:
			WorldStateStore.age_inventory(corpse.inventory, el)
	var blood := get_tree().get_first_node_in_group(&"blood_decals")
	if blood != null and map.is_ancestor_of(blood):
		blood.call(&"add_transforms", d.get("blood", []))


# --- Unloading -------------------------------------------------------------------------------

## Capture chunk [c]'s state into the store and free its content (the
## node removal is spread over the next frames: [_trash]).
func unload(c: Vector2i) -> void:
	if not builder.chunks.has(c) and not builder.building_chunks.has(c):
		return
	if _current == c:
		_steps.clear()
		_current = Vector2i(-1, -1)
	chunk_unloading.emit(c)
	if builder.chunks.has(c):
		capture_chunk(c, true)
	else:
		# Still being built: its stored state was never applied in full
		# (the dynamic record is only taken at "finish") — capturing now
		# would overwrite the store with a half-built chunk. Just forget.
		for n in saveables.get(c, []):
			if is_instance_valid(n):
				store.forget_default(String(n.get(&"persist_id")))
	saveables.erase(c)
	var nodes := builder.detach_chunk(c)
	for n in nodes:
		if n is Node3D:
			(n as Node3D).visible = false
		if n.is_in_group(&"building"):
			n.remove_from_group(&"building")
	_trash.append_array(nodes)
	_trash_chunks[c] = true
	unloads += 1
	SoundManager.forget_buildings()
	chunk_unloaded.emit(c)


## Free detached nodes: one per call (a building ~ a few hundred nodes).
func _free_one() -> bool:
	if _trash.is_empty():
		_trash_chunks.clear()
	while not _trash.is_empty():
		var n: Node = _trash.pop_front()
		if not is_instance_valid(n):
			continue
		var t0 := Time.get_ticks_usec()
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.free()
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if ms > max_free_ms:
			max_free_ms = ms
			max_free_name = String(n.name) if is_instance_valid(n) else ""
		return true
	return false


## Free every detached node now (tests / map teardown).
func free_detached() -> void:
	while _free_one():
		pass


## Capture chunk [c]: statics into the store; with [take] the dynamic
## objects are removed from the world into the store, otherwise their
## records are only returned (live snapshots for a save).
func capture_chunk(c: Vector2i, take: bool) -> Dictionary:
	var now := TimeManager.now()
	for n in saveables.get(c, []):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var id := String(n.get(&"persist_id"))
		if not store.defaults.has(id):
			continue
		store.capture(id, n.call(&"save_state"), now)
		if take:
			store.forget_default(id)
	var rect := builder.layout.chunk_rect(c)
	var map := _map()
	var items: Array = []
	var keyed: Array = []
	for w in get_tree().get_nodes_in_group(WorldItem.GROUP):
		var wi := w as WorldItem
		if wi == null or not map.is_ancestor_of(wi) or wi.is_queued_for_deletion() or wi.item == null or wi.item.stack <= 0:
			continue
		if builder.layout.chunk_of(Vector2(wi.global_position.x, wi.global_position.z)) != c:
			continue
		keyed.append([wi.item.uid, {"item": wi.item.to_dict(), "position": Saveable.vec3(wi.global_position), "yaw": wi.rotation.y}])
		if take:
			wi.remove_from_group(WorldItem.GROUP)
			wi.get_parent().remove_child(wi)
			wi.queue_free()
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	for k in keyed:
		items.append(k[1])
	var corpses: Array = []
	for n in get_tree().get_nodes_in_group(&"corpse"):
		var co := n as ZombieCorpse
		if co == null or not map.is_ancestor_of(co) or co.is_queued_for_deletion():
			continue
		if builder.layout.chunk_of(Vector2(co.global_position.x, co.global_position.z)) != c:
			continue
		corpses.append(co.save_record())
		if take:
			co.remove_from_group(&"corpse")
			co.get_parent().remove_child(co)
			co.queue_free()
	corpses.sort_custom(func(a, b): return String(a.persist_id) < String(b.persist_id))
	var blood: Array = []
	var bd := get_tree().get_first_node_in_group(&"blood_decals")
	if bd != null and map.is_ancestor_of(bd):
		if take:
			blood = bd.call(&"take_in", rect)
		else:
			for t in bd.call(&"transforms"):
				var tt: Transform3D = t
				if rect.has_point(Vector2(tt.origin.x, tt.origin.z)):
					blood.append(Saveable.xform(tt))
	if take:
		store.put_dynamic(c, items, corpses, blood, now)
	return {"items": items, "corpses": corpses, "blood": blood, "t": now}


## The store as it would be if every loaded chunk unloaded now (a save):
## {statics, chunks}. Nothing in the world changes (the live deltas of
## loaded saveables are captured into the store, which is exactly what an
## unload would store).
func live_snapshot() -> Dictionary:
	var dyn_live := {}
	for c in builder.chunks.keys():
		var dyn := capture_chunk(c, false)
		if not ((dyn.items as Array).is_empty() and (dyn.corpses as Array).is_empty() and (dyn.blood as Array).is_empty()):
			dyn_live[WorldStateStore.key(c)] = dyn
	var out := store.to_dict()
	for k in dyn_live:
		out.chunks[k] = dyn_live[k]
	return out


# --- Per frame ---------------------------------------------------------------------------------

func _player_pos() -> Array:
	var pl := GameManager.player as Node3D
	if pl != null and is_instance_valid(pl) and pl.is_inside_tree() and _map().is_ancestor_of(pl):
		var v := Vector3.ZERO
		if pl is CharacterBody3D:
			v = (pl as CharacterBody3D).velocity
		return [pl.global_position, v]
	return []


## Re-plan: queue wanted chunks by priority, free far ones.
func _refresh(pos: Vector3, vel: Vector3) -> void:
	var pc := chunk_at(pos)
	var want := chunks_within(pc, load_radius, dims())
	var missing: Array = []
	for c in want:
		if not builder.chunks.has(c) and c != _current:
			missing.append(c)
	_queue = order(missing, Vector2(pos.x, pos.z), Vector2(vel.x, vel.z), cs(), lookahead)
	_unload_queue = to_unload(builder.chunks.keys(), pc, unload_radius)
	if _current != Vector2i(-1, -1) and chebyshev(_current, pc) > unload_radius:
		unload(_current)


func _run_step() -> void:
	if _steps.is_empty():
		return
	var st: Variant = _steps.pop_front()
	_do_step(_current, st)
	if _steps.is_empty():
		_current = Vector2i(-1, -1)


func _process(delta: float) -> void:
	if not _started or builder == null or not is_instance_valid(builder):
		return
	var pp := _player_pos()
	if pp.is_empty():
		return
	var pos: Vector3 = pp[0]
	var vel: Vector3 = pp[1]
	var t0 := Time.get_ticks_usec()
	var pc := chunk_at(pos)
	# Never stand in an unbuilt chunk.
	var sync_ms := 0.0
	for c in chunks_within(pc, sync_radius, dims()):
		if not builder.chunks.has(c):
			var ts := Time.get_ticks_usec()
			load_now(c)
			sync_ms += (Time.get_ticks_usec() - ts) / 1000.0
			sync_loads += 1
	if sync_ms > 100.0:
		EventBus.game_notice.emit("Loading area…", 1.0)
	_poll += delta
	if pc != _last_chunk or _poll >= 0.5:
		_poll = 0.0
		_last_chunk = pc
		_refresh(pos, vel)
	# Budgeted work: free one detached node, unload one chunk, then build.
	# The population director's instantiation work of this frame (it
	# runs in the physics step just before) comes off the budget; when it
	# used the whole frame share, only one light step runs.
	var budget := int(budget_ms * 1000.0)
	var pd := PopulationDirector.of(get_tree())
	var shared_used := 0
	if pd != null and pd.work_frame == Engine.get_process_frames():
		shared_used = pd.work_usec
	budget -= shared_used
	var ran := 0
	# A building step (~2-9 ms) waits when the director already worked
	# this frame (at most 2 frames in a row, so loading keeps going).
	var next_is_building := (not _steps.is_empty() and _steps[0] is int) or (_steps.is_empty() and not _queue.is_empty())
	if shared_used > 1000 and next_is_building and _deferred_frames < 2:
		_deferred_frames += 1
		frame_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return
	_deferred_frames = 0
	if _free_one():
		ran += 1
	elif not _unload_queue.is_empty():
		var uc: Vector2i = _unload_queue.pop_front()
		if builder.chunks.has(uc) and chebyshev(uc, pc) > unload_radius:
			unload(uc)
			ran += 1
	while Time.get_ticks_usec() - t0 < budget or ran == 0:
		# A building (~8 ms) always starts a frame of its own.
		if ran > 0 and ((not _steps.is_empty() and _steps[0] is int) or Time.get_ticks_usec() - t0 >= budget):
			break
		if _steps.is_empty():
			if _queue.is_empty():
				break
			_current = _queue.pop_front()
			if builder.chunks.has(_current):
				_current = Vector2i(-1, -1)
				continue
			_steps = builder.chunk_steps(_current)
		_run_step()
		ran += 1
	frame_ms = (Time.get_ticks_usec() - t0) / 1000.0


## Build everything queued now, unload / free what is due (tests / tools).
func flush() -> void:
	var pp := _player_pos()
	if not pp.is_empty():
		_refresh(pp[0], pp[1])
	while not _unload_queue.is_empty():
		unload(_unload_queue.pop_front())
	free_detached()
	while not _steps.is_empty():
		_run_step()
	while not _queue.is_empty():
		load_now(_queue.pop_front())


# --- Save / load ------------------------------------------------------------------------------

## {statics, chunks} for a save (store + live deltas of loaded chunks).
func save_state() -> Dictionary:
	return live_snapshot()
