extends Node
## Gameplay sound propagation (autoload: SoundManager). Not audio playback.
##
## Emitters call emit_sound(category, position, source, overrides); the
## category's defaults come from data/audio/sound_categories.tres. Each
## event is dispatched ONCE, synchronously, to the registered listeners
## near it (a SpatialHash of listener ears, refreshed at 5 Hz — dispatch
## cost is O(listeners near the sound), not O(all zombies)), then kept for
## [duration] seconds for the debug overlay / noise rings.
## EventBus.sound_emitted is still emitted for every event (UI, sleep,
## debug); gameplay listeners (zombies) register here instead.
##
## Propagation for a listener at flat distance d (SoundMath):
## - direct: an iterative ray sound → ear on layers 1+7+8 (hit_from_inside,
##   each hit body excluded and the ray re-cast, up to MAX_HITS): EVERY
##   obstacle multiplies — walls ×0.5, closed doors ×0.6, closed windows
##   ×0.7, other solids ×0.85 — product ≥ 0.15. Cached per event by the
##   ear's EAR_CELL (1.5 m) cell.
## - via openings (OPEN exterior doors / windows, open or smashed):
##   sound inside building A, ear outside → through A's opening (ear on
##   its outward side); sound outside, ear inside building B → through B's
##   opening (sound on its outward side); A → B → through one opening of
##   each (the leg between them assumed clear). Each leg's attenuation is
##   one iterative ray, cached per event (per opening, or per opening and
##   ear cell). The best path wins.
## A listener hears when effective radius × its sensitivity × ambient
## masking ≥ the path length; it gets on_sound(event, {strength, slack,
## attenuation, path, distance}).
##
## Listener contract (duck-typed): sound_ear_position() -> Vector3,
## sound_sensitivity() -> float (0 = deaf now), sound_owner() -> Object
## (its own sounds are skipped), on_sound(event: SoundEvent, info: Dictionary).

const CATEGORIES_PATH := "res://data/audio/sound_categories.tres"
## Layers that muffle sound: 1 world + 7 doors + 8 window panes.
const OBSTACLE_MASK := (1 << 0) | (1 << 6) | (1 << 7)
## Sounds are traced from this height above their (feet-level) position.
const SOUND_HEIGHT := 1.2
const LISTENER_REFRESH_SECONDS := 0.2
const HASH_CELL := 8.0
## Obstacles counted per ray (each one re-casts the ray).
const MAX_HITS := 5
## Per-event attenuation cache cell (m) for listener ears.
const EAR_CELL := 1.5
## Queued sounds (zombie moans) dispatched per physics frame at most.
const MAX_QUEUED_PER_FRAME := 2
## Listeners may be more sensitive than 1 (the hash query covers this).
const MAX_SENSITIVITY := 2.0
## Listeners move between hash refreshes: query this much wider.
const QUERY_SLACK := 2.0
const MAX_EVENTS := 256
const MAX_HEARINGS := 64
## Radius used for an unknown category without a radius override.
const DEFAULT_RADIUS := 5.0

## Emitted after every dispatch (debug / tests): how many listeners heard it.
signal sound_dispatched(event: SoundEvent, heard: int)

var categories: SoundCategoryTable
## Global multiplier on every radius (weather / rain later; 1 = none).
var ambient_masking: float = 1.0
## Counters for tests / perf: events, rays, deliveries.
var stats: Dictionary = {"events": 0, "rays": 0, "deliveries": 0}

var _events: Array[SoundEvent] = []
var _next_id: int = 1
## instance id -> listener Object.
var _listeners: Dictionary = {}
var _hash := SpatialHash.new(HASH_CELL)
var _refresh_accum: float = 0.0
## [{ear, at, time, path, category, strength}] most recent last.
var _hearings: Array[Dictionary] = []
var _ray: PhysicsRayQueryParameters3D
## listener id -> building (Node) or null, refreshed with the hash.
var _ear_building: Dictionary = {}
## [category, position, source, overrides] waiting for queue dispatch.
var _queue: Array = []


func _ready() -> void:
	categories = load(CATEGORIES_PATH) as SoundCategoryTable
	if categories == null:
		push_error("SoundManager: cannot load %s" % CATEGORIES_PATH)
		categories = SoundCategoryTable.new()
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = OBSTACLE_MASK
	_ray.collide_with_areas = false
	# A sound or ear inside a wall / door still counts that obstacle.
	_ray.hit_from_inside = true


## Physics seconds (the clock event durations use).
static func now() -> float:
	return Engine.get_physics_frames() / float(Engine.physics_ticks_per_second)


func category(id: StringName) -> SoundCategory:
	return categories.get_category(id) if categories else null


## Base radius of [id] (DEFAULT_RADIUS when unknown).
func category_radius(id: StringName) -> float:
	var c := category(id)
	return c.radius if c else DEFAULT_RADIUS


# --- Emitting -------------------------------------------------------------------------

## Make a gameplay noise. [overrides]: radius, intensity, duration (replace
## the category's), anything else goes to event.extras (&"lure", &"hops"…).
func emit_sound(category_id: StringName, position: Vector3, source: Object = null, overrides: Dictionary = {}) -> SoundEvent:
	if not position.is_finite() or (overrides.has("radius") and not is_finite(float(overrides["radius"]))):
		push_warning("SoundManager: rejected non-finite sound '%s' at %s" % [category_id, position])
		return null
	var cat := category(category_id)
	if cat == null and not overrides.has("radius"):
		push_warning("SoundManager: unknown sound category '%s'" % category_id)
	var ev := SoundEvent.new(category_id, position,
		cat.radius if cat else DEFAULT_RADIUS, cat.intensity if cat else 0.5, source)
	ev.duration = cat.duration if cat else 1.0
	for k: Variant in overrides:
		match String(k):
			"radius": ev.radius = maxf(float(overrides[k]), 0.0)
			"intensity": ev.intensity = clampf(float(overrides[k]), 0.0, 1.0)
			"duration": ev.duration = maxf(float(overrides[k]), 0.0)
			_: ev.extras[StringName(k)] = overrides[k]
	ev.id = _next_id
	_next_id += 1
	ev.created_time = now()
	var tm := get_node_or_null(^"/root/TimeManager")
	if tm and tm.has_method(&"now"):
		ev.created_minute = float(tm.call(&"now"))
	_events.append(ev)
	if _events.size() > MAX_EVENTS:
		_events.remove_at(0)
	if not is_finite(ev.radius) or not is_finite(ev.intensity):
		push_warning("SoundManager: rejected non-finite sound '%s'" % category_id)
		_events.pop_back()
		return null
	stats.events += 1
	EventBus.sound_emitted.emit(position, ev.radius, ev.intensity, category_id, source as Node)
	var heard := _dispatch(ev)
	sound_dispatched.emit(ev, heard)
	return ev


## Emit later, spread over physics frames (at most MAX_QUEUED_PER_FRAME
## per frame): for bursts of low-priority sounds (zombie moans).
func queue_sound(category_id: StringName, position: Vector3, source: Object = null, overrides: Dictionary = {}) -> void:
	_queue.append([category_id, position, weakref(source) if source != null else null, overrides])


func queued_count() -> int:
	return _queue.size()


## Events still alive (expired ones are dropped).
func active_events() -> Array[SoundEvent]:
	_expire()
	return _events


## Listener hearings of the last [max_age] seconds (debug lines).
func recent_hearings(max_age: float = 1.5) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := now()
	for h in _hearings:
		if t - float(h.time) <= max_age:
			out.append(h)
	return out


## Forget events / hearings / counters (tests). Listeners stay.
func clear() -> void:
	_events.clear()
	_queue.clear()
	_hearings.clear()
	stats = {"events": 0, "rays": 0, "deliveries": 0}


# --- Listeners --------------------------------------------------------------------------

func register_listener(l: Object) -> void:
	if l == null:
		return
	var id := l.get_instance_id()
	_listeners[id] = l
	var ear: Vector3 = l.call(&"sound_ear_position")
	_hash.insert(id, ear)
	_ear_building[id] = building_at(ear)


func unregister_listener(l: Object) -> void:
	if l == null:
		return
	var id := l.get_instance_id()
	_listeners.erase(id)
	_hash.remove(id)
	_ear_building.erase(id)


func is_listening(l: Object) -> bool:
	return l != null and _listeners.has(l.get_instance_id())


func listener_count() -> int:
	return _listeners.size()


## Entries in the spatial hash (must equal listener_count()).
func hashed_count() -> int:
	return _hash.size()


## Drop listeners that were freed without unregistering. Returns how many.
func prune() -> int:
	var n := 0
	for id: int in _listeners.keys():
		if not is_instance_valid(_listeners[id]):
			_drop(id)
			n += 1
	return n


func _physics_process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum >= LISTENER_REFRESH_SECONDS:
		_refresh_accum = 0.0
		_refresh_listeners()
	if not _events.is_empty():
		_expire()
	var n := 0
	while not _queue.is_empty() and n < MAX_QUEUED_PER_FRAME:
		var q: Array = _queue.pop_front()
		var src: Object = null
		if q[2] != null:
			src = (q[2] as WeakRef).get_ref()
			if src == null or not is_instance_valid(src):
				continue  # the moaner is gone
		emit_sound(q[0], q[1], src, q[3])
		n += 1


func _refresh_listeners() -> void:
	for id: int in _listeners.keys():
		var l: Variant = _listeners[id]
		if not is_instance_valid(l):
			_drop(id)
			continue
		var ear: Vector3 = (l as Object).call(&"sound_ear_position")
		_hash.update(id, ear)
		_ear_building[id] = building_at(ear)


func _drop(id: int) -> void:
	_listeners.erase(id)
	_hash.remove(id)
	_ear_building.erase(id)


## Drop every expired event (durations differ, so the whole list).
func _expire() -> void:
	var t := now()
	var keep: Array[SoundEvent] = []
	for ev in _events:
		if ev.time_left(t) > 0.0:
			keep.append(ev)
	if keep.size() != _events.size():
		_events = keep


# --- Dispatch ---------------------------------------------------------------------------

func _dispatch(ev: SoundEvent) -> int:
	if ev.radius <= 0.0 or _listeners.is_empty() or ambient_masking <= 0.0:
		return 0
	var reach := ev.radius * MAX_SENSITIVITY * ambient_masking + QUERY_SLACK
	var ids := _hash.query_radius(ev.position, reach)
	if ids.is_empty():
		return 0
	var src := ev.source()
	var ctx := {"direct": {}}
	var heard := 0
	for id in ids:
		var l: Variant = _listeners.get(id)
		if l == null or not is_instance_valid(l):
			_drop(id)
			continue
		var lo := l as Object
		if src != null and (lo == src or lo.call(&"sound_owner") == src):
			continue
		var sens := float(lo.call(&"sound_sensitivity"))
		if sens <= 0.0:
			continue
		var ear: Vector3 = lo.call(&"sound_ear_position")
		var d := _flat(ev.position, ear)
		var full := ev.radius * sens * ambient_masking
		# Unreachable even with nothing in the way: no rays at all.
		if d > full:
			continue
		var info := evaluate(ev, ear, sens, ctx, _ear_building.get(id, false))
		if float(info.slack) < 0.0:
			continue
		info["strength"] = SoundMath.perceived(ev.intensity, float(info.slack), full)
		info["distance"] = d
		heard += 1
		stats.deliveries += 1
		_hearings.append({"ear": ear, "at": ev.position, "time": now(), "path": info.path,
			"category": ev.category, "strength": info.strength})
		if _hearings.size() > MAX_HEARINGS:
			_hearings.remove_at(0)
		lo.call(&"on_sound", ev, info)
	return heard


## How [ev] reaches an ear at [ear] (eye height) with [sensitivity]:
## {slack, attenuation, path (&"direct" / &"opening")}. [p_ctx] is the
## per-event cache Dictionary (null for a one-off query); [ear_building]
## the building the ear is in (null = outdoors, false = look it up).
func evaluate(ev: SoundEvent, ear: Vector3, sensitivity: float = 1.0, p_ctx: Variant = null,
		ear_building: Variant = false) -> Dictionary:
	var ctx: Dictionary = p_ctx if p_ctx is Dictionary else {}
	if not ctx.has("direct"):
		ctx["direct"] = {}
	var d := _flat(ev.position, ear)
	var key := _ear_key(ear)
	var cache: Dictionary = ctx.direct
	var att: float
	if cache.has(key):
		att = cache[key]
	else:
		att = obstacle_attenuation(ev.position + Vector3.UP * SOUND_HEIGHT, ear)
		cache[key] = att
	var s := SoundMath.slack(SoundMath.effective_radius(ev.radius, att, sensitivity, ambient_masking), d)
	var path := &"direct"
	if att < 1.0:
		var eb: Node = null
		if ear_building is bool:
			eb = building_at(ear)
		elif ear_building is Node and is_instance_valid(ear_building):
			eb = ear_building
		var sb := _sound_building(ev, ctx)
		if sb != eb:
			var best := _opening_slack(ev, ear, key, sensitivity, sb, eb, ctx)
			if best > s:
				s = best
				path = &"opening"
	return {"slack": s, "attenuation": att, "path": path}


## Best slack through open exterior openings between the sound's building
## [sb] and the ear's [eb] (either may be null = outdoors). -INF if none.
func _opening_slack(ev: SoundEvent, ear: Vector3, key: Vector3i, sens: float, sb: Node, eb: Node, ctx: Dictionary) -> float:
	var best := -INF
	var r := ev.radius
	if sb != null:
		for o: Dictionary in _openings(sb, ctx):
			var att_so := _att_sound_to(ev, o, ctx)
			var d_so := _flat(ev.position, o.center)
			if eb == null:
				if SoundMath.on_outward_side(o.center, o.outward, ear):
					best = maxf(best, SoundMath.via_opening_slack(r, att_so, d_so, _flat(o.center, ear), sens, ambient_masking))
			else:
				# Building to building: out of one opening, into another
				# (the leg between them is assumed clear).
				for o2: Dictionary in _openings(eb, ctx):
					if not SoundMath.on_outward_side(o.center, o.outward, o2.center) \
							or not SoundMath.on_outward_side(o2.center, o2.outward, o.center):
						continue
					var att_oe := _att_opening_to_ear(o2, ear, key, ctx)
					var sl := SoundMath.effective_radius(r, att_so * att_oe, sens, ambient_masking) \
						- d_so - _flat(o.center, o2.center) - _flat(o2.center, ear)
					best = maxf(best, sl)
	elif eb != null:
		# Sound outdoors, ear indoors: in through one of the ear's openings.
		for o2: Dictionary in _openings(eb, ctx):
			if not SoundMath.on_outward_side(o2.center, o2.outward, ev.position):
				continue
			var att_oe := _att_opening_to_ear(o2, ear, key, ctx)
			best = maxf(best, SoundMath.via_opening_slack(r, att_oe, _flat(ev.position, o2.center),
				_flat(o2.center, ear), sens, ambient_masking))
	return best


## Radius multiplier for the obstacles between [from] and [to] (world
## points at the heights to trace): one ray re-cast past each hit body
## (at most MAX_HITS obstacles); every obstacle multiplies.
func obstacle_attenuation(from: Vector3, to: Vector3, skip_fixture: Node = null) -> float:
	var space := _space()
	if space == null:
		return 1.0
	var kinds: Array = []
	var exclude: Array[RID] = []
	# Round 9: planks on a fixture multiply once per fixture (a ray may hit
	# both the pane and the planks body of one window).
	var planks := 1.0
	var seen: Array[Node] = []
	if skip_fixture != null:
		seen.append(skip_fixture)  # its planks are counted by the caller
	_ray.from = from
	_ray.to = to
	for i in MAX_HITS:
		_ray.exclude = exclude
		var hit := space.intersect_ray(_ray)
		stats.rays += 1
		if hit.is_empty():
			break
		var col: Object = hit.get("collider")
		kinds.append(classify(col))
		var f := barricade_fixture_of(col)
		if f != null and not seen.has(f):
			seen.append(f)
			planks *= float(f.call(&"sound_barricade_factor"))
		exclude.append(hit.get("rid"))
	_ray.exclude = []
	if planks >= 1.0:
		return SoundMath.attenuation(kinds)
	return maxf(SoundMath.attenuation(kinds) * planks, SoundMath.MIN_ATTENUATION)


## The fixture whose barricade factor applies to [collider] (a Door /
## HouseWindow, a window pane, or a planks body), or null.
static func barricade_fixture_of(collider: Object) -> Node:
	var n := collider as Node
	if n == null:
		return null
	if n.has_method(&"barricade_fixture"):
		return n.call(&"barricade_fixture")
	if n.has_method(&"sound_barricade_factor"):
		return n
	var p := n.get_parent()
	if p != null and p.has_method(&"sound_barricade_factor"):
		return p
	return null


## Obstacle kind of a collider (SoundMath.WALL / DOOR_CLOSED / …). Fixtures
## answer sound_obstacle_kind() themselves (a window pane asks its window).
static func classify(collider: Object) -> StringName:
	var n := collider as Node
	if n == null:
		return SoundMath.PROP
	if n.has_method(&"sound_obstacle_kind"):
		return n.call(&"sound_obstacle_kind")
	var p := n.get_parent()
	if p != null and p.has_method(&"sound_obstacle_kind"):
		return p.call(&"sound_obstacle_kind")
	if n.is_in_group(&"wall"):
		return SoundMath.WALL
	return SoundMath.PROP


## The building whose room contains [p] (null outdoors).
func building_at(p: Vector3) -> Node:
	if not is_inside_tree():
		return null
	for b in get_tree().get_nodes_in_group(&"building"):
		if b.has_method(&"room_at") and b.room_at(p) != null:
			return b
	return null


func _sound_building(ev: SoundEvent, ctx: Dictionary) -> Node:
	if not ctx.has("sound_building"):
		ctx["sound_building"] = building_at(ev.position)
	return ctx.sound_building


## Open exterior openings of [b] (cached per event):
## [{center, outward, node, id}].
func _openings(b: Node, ctx: Dictionary) -> Array:
	var cache: Dictionary = ctx.get("openings", {})
	ctx["openings"] = cache
	var bid := b.get_instance_id()
	if cache.has(bid):
		return cache[bid]
	var out: Array = []
	cache[bid] = out
	var tree := get_tree()
	for group: StringName in [&"door", &"window"]:
		for f in tree.get_nodes_in_group(group):
			if not b.is_ancestor_of(f) or not f.has_method(&"sound_passes") or not f.sound_passes():
				continue
			var outward: Vector3 = f.get(&"outward")
			if outward.length_squared() < 0.5:
				continue  # interior opening
			var factor: float = f.call(&"sound_barricade_factor") if f.has_method(&"sound_barricade_factor") else 1.0
			out.append({"center": f.call(&"sound_opening_center"), "outward": outward, "node": f,
				"id": f.get_instance_id(), "factor": factor})
	return out


## Attenuation sound → opening (cached per event and opening).
func _att_sound_to(ev: SoundEvent, o: Dictionary, ctx: Dictionary) -> float:
	var cache: Dictionary = ctx.get("att_so", {})
	ctx["att_so"] = cache
	if not cache.has(o.id):
		var c: Vector3 = o.center
		# Planks across the opening muffle what passes through it (×0.8 each).
		cache[o.id] = obstacle_attenuation(ev.position + Vector3.UP * SOUND_HEIGHT,
			Vector3(c.x, c.y + SOUND_HEIGHT, c.z), o.node) * float(o.get("factor", 1.0))
	return cache[o.id]


## Attenuation opening → ear (cached per event, opening and ear cell).
func _att_opening_to_ear(o: Dictionary, ear: Vector3, key: Vector3i, ctx: Dictionary) -> float:
	var cache: Dictionary = ctx.get("att_oe", {})
	ctx["att_oe"] = cache
	var k := [o.id, key]
	if not cache.has(k):
		var c: Vector3 = o.center
		cache[k] = obstacle_attenuation(Vector3(c.x, c.y + SOUND_HEIGHT, c.z), ear, o.node) * float(o.get("factor", 1.0))
	return cache[k]


static func _ear_key(ear: Vector3) -> Vector3i:
	return Vector3i(floori(ear.x / EAR_CELL), floori(ear.y / EAR_CELL), floori(ear.z / EAR_CELL))


func _space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	if vp == null:
		return null
	var w := vp.find_world_3d()
	return w.direct_space_state if w else null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
