class_name ZombiePopulation
extends RefCounted
## The county's zombies as DATA (Round 12): every zombie that is not an
## instantiated Zombie node near the player is a member (an int id) of a
## small group {id, pos, heading, state, target, timer, members}.
## Pure and deterministic (one seeded rng, groups processed in id order):
## unit tests drive it directly; PopulationDirector (the node in the map)
## ticks it with game minutes, forwards loud sounds, instantiates the
## groups of active chunks as real zombies and folds them back.
##
## States: WANDER (slow random walk, drifting back toward the nearest
## attractor — town / hamlet / farm centre — when farther than
## attractor_radius; now and then sets off to another attractor),
## MIGRATE (walks to that attractor), INVESTIGATE (walks to a heard noise,
## then wanders there; gives up after investigate_minutes).
## Groups closer than merge_radius in the same state merge (≤ max_group);
## big wandering groups split. Members only move between groups, so
## total() + instantiated zombies is constant except for deaths.
##
## Member ids: the look of member m is look_seed(world seed, m) unless
## [looks] overrides it (a zombie that was spawned elsewhere and folded
## in keeps its own look); [hurt] keeps the health of wounded members.

enum State { WANDER, MIGRATE, INVESTIGATE }
const STATE_NAMES := ["wander", "migrate", "investigate"]

var params: PopulationParams
var world_size: Vector2 = Vector2(768, 768)
var chunk_size: float = 64.0
var world_seed: int = 0
## id → group Dictionary.
var groups: Dictionary = {}
var next_group: int = 1
var next_member: int = 0
var deaths: int = 0
## member id → ai / look seed override.
var looks: Dictionary = {}
## member id → health (wounded members only).
var hurt: Dictionary = {}
## Town / hamlet / farm centres (wander drift, migration goals).
var attractors: PackedVector2Array = PackedVector2Array()
var rng := RandomNumberGenerator.new()
## Stats (tests / perf): ticks, sounds heard, merges, splits.
var ticks: int = 0
var merges: int = 0
var splits: int = 0
var heard: int = 0
## Merge / split passes look at 1 / MERGE_SLICES of the groups per step.
const MERGE_SLICES := 4
var _slice: int = 0
var _parity: int = 0
var _grid: Dictionary = {}
var _ids: Array = []
var _ids_key: Vector3i = Vector3i(-1, -1, -1)
var _mut: int = 0


func setup(p_size: Vector2, p_chunk: float, prm: PopulationParams, p_seed: int) -> void:
	world_size = p_size
	chunk_size = p_chunk
	params = prm if prm != null else PopulationParams.new()
	world_seed = p_seed
	rng.seed = WorldGenerator.sub_seed(p_seed, "population")


## The deterministic look / ai seed of member [m] of a world.
static func look_seed(p_world_seed: int, m: int) -> int:
	return (WorldGenerator.sub_seed(p_world_seed, "pop:%d" % m) & 0x7fffffff) | 1


func member_seed(m: int) -> int:
	return int(looks.get(m, look_seed(world_seed, m)))


# --- Generation ------------------------------------------------------------------------------

## The initial population of [layout]: the layout's start pack (one
## member per point, where Round 11 spawned them), its rural groups, and
## a fill over the rest of the county by chunk density (towns dense,
## woods sparse) up to the county total.
static func generate(layout: WorldLayout, p_seed: int, prm: PopulationParams) -> ZombiePopulation:
	var pop := ZombiePopulation.new()
	pop.setup(layout.size, layout.chunk_size, prm, p_seed)
	for s in layout.settlements:
		pop.attractors.append(s.get("yard_center", s.center))
	for q in layout.zombies:
		pop.add_group(q, pop.new_members(1), State.WANDER, Vector2.INF, {"tag": "start"})
	for g in layout.zombie_groups:
		var pts: PackedVector2Array = g.points
		if pts.is_empty():
			continue
		var c := Vector2.ZERO
		for q in pts:
			c += q
		pop.add_group(c / pts.size(), pop.new_members(pts.size()), State.WANDER, Vector2.INF, {"tag": String(g.id)})
	var area := layout.size.x * layout.size.y / (768.0 * 768.0)
	var total := clampi(int(round(prm.total_at_768 * area)), prm.total_min, prm.total_max)
	var fill := total - pop.total()
	if fill <= 0:
		return pop
	var r := RandomNumberGenerator.new()
	r.seed = WorldGenerator.sub_seed(p_seed, "population:fill")
	var sc := layout.chunk_of(layout.spawn_point)
	var chunks: Array[Vector2i] = []
	var tw := 0.0
	for cz in layout.chunks_z():
		for cx in layout.chunks_x():
			var c2 := Vector2i(cx, cz)
			if maxi(absi(c2.x - sc.x), absi(c2.y - sc.y)) <= prm.start_radius:
				continue
			chunks.append(c2)
			tw += layout.chunk_density[layout.chunk_index(c2)]
	# Largest remainder allocation.
	var alloc: Array[int] = []
	var rema: Array = []
	var assigned := 0
	for i in chunks.size():
		var exact := float(fill) * layout.chunk_density[layout.chunk_index(chunks[i])] / maxf(tw, 0.001)
		alloc.append(int(floor(exact)))
		assigned += int(floor(exact))
		rema.append([exact - floor(exact), i])
	rema.sort_custom(func(a, b): return a[0] > b[0] if a[0] != b[0] else a[1] < b[1])
	for k in fill - assigned:
		alloc[rema[k % rema.size()][1]] += 1
	for i in chunks.size():
		var left := alloc[i]
		var rect := layout.chunk_rect(chunks[i])
		while left > 0:
			var n := mini(left, r.randi_range(prm.group_min, prm.group_max))
			var q := Vector2.INF
			for attempt in 12:
				var cand := Vector2(r.randf_range(rect.position.x + 2.0, rect.end.x - 2.0), r.randf_range(rect.position.y + 2.0, rect.end.y - 2.0))
				if layout.zone_at(cand) == WorldLayout.Zone.WATER or not layout.building_at(cand, 1.5).is_empty():
					continue
				q = cand
				break
			if q == Vector2.INF:
				q = rect.get_center()
			pop.add_group(q, pop.new_members(n), State.WANDER, Vector2.INF)
			left -= n
	return pop


# --- Members / groups --------------------------------------------------------------------------

func new_members(n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in n:
		out.append(next_member)
		next_member += 1
	return out


func add_group(pos: Vector2, members: PackedInt32Array, state: int = State.WANDER, target: Vector2 = Vector2.INF,
		extra: Dictionary = {}) -> int:
	var id := next_group
	next_group += 1
	var g := {"id": id, "pos": _clamp(pos), "heading": rng.randf() * TAU, "state": state,
		"target": target, "timer": params.investigate_minutes if state == State.INVESTIGATE else 0.0,
		"members": members}
	for k in extra:
		g[k] = extra[k]
	groups[id] = g
	return id


## Members in data (not instantiated).
func total() -> int:
	var n := 0
	for id in groups:
		n += (groups[id].members as PackedInt32Array).size()
	return n


func chunk_of(p: Vector2) -> Vector2i:
	var cx := int(ceil(world_size.x / chunk_size))
	var cz := int(ceil(world_size.y / chunk_size))
	return Vector2i(clampi(int(floor(p.x / chunk_size)), 0, cx - 1), clampi(int(floor(p.y / chunk_size)), 0, cz - 1))


## Group ids whose position is in chunk [c] (id order).
func groups_in_chunk(c: Vector2i) -> Array[int]:
	var out: Array[int] = []
	for id in _sorted_ids():
		if chunk_of(groups[id].pos) == c:
			out.append(id)
	return out


## chunk → members in data (debug overlay, map).
func chunk_counts() -> Dictionary:
	var out := {}
	for id in groups:
		var c := chunk_of(groups[id].pos)
		out[c] = int(out.get(c, 0)) + (groups[id].members as PackedInt32Array).size()
	return out


## Take up to [n] members out of group [gid] (they become real zombies).
## The group disappears when emptied. Returns the member ids.
func take_members(gid: int, n: int) -> PackedInt32Array:
	var g: Dictionary = groups.get(gid, {})
	if g.is_empty():
		return PackedInt32Array()
	var m: PackedInt32Array = g.members
	var k := mini(n, m.size())
	var out := m.slice(0, k)
	g.members = m.slice(k)
	if (g.members as PackedInt32Array).is_empty():
		erase_group(gid)
	return out


## Take member [m] out of group [gid] (it becomes a real zombie).
func take_member(gid: int, m: int) -> bool:
	var g: Dictionary = groups.get(gid, {})
	if g.is_empty():
		return false
	var mm: PackedInt32Array = g.members
	var i := mm.find(m)
	if i < 0:
		return false
	mm.remove_at(i)
	g.members = mm
	if mm.is_empty():
		erase_group(gid)
	return true


## A real zombie leaves the active area: member [m] joins the nearest
## group within merge_radius in the same state (and toward the same
## target), else a new group of one at [pos]. [health] < 0 = unhurt.
func fold(m: int, pos: Vector2, state: int = State.WANDER, target: Vector2 = Vector2.INF, health: float = -1.0,
		seed_override: int = 0) -> int:
	if health >= 0.0:
		hurt[m] = health
	else:
		hurt.erase(m)
	if seed_override != 0 and seed_override != look_seed(world_seed, m):
		looks[m] = seed_override
	var best := -1
	var bd := params.merge_radius
	for id in _sorted_ids():
		var g: Dictionary = groups[id]
		if int(g.state) != state or (g.members as PackedInt32Array).size() >= params.max_group:
			continue
		if state != State.WANDER and (g.target as Vector2).distance_to(target) > params.merge_radius:
			continue
		var d := (g.pos as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = id
	if best >= 0:
		var gm: PackedInt32Array = groups[best].members
		gm.append(m)
		groups[best].members = gm
		return best
	return add_group(pos, PackedInt32Array([m]), state, target)


## Remove member [m] from whichever group holds it (true when found).
func remove_member(m: int) -> bool:
	for id in _sorted_ids():
		if take_member(id, m):
			return true
	return false


## A member died as a real zombie (its corpse is a chunk object now).
func record_death(m: int) -> void:
	deaths += 1
	hurt.erase(m)
	looks.erase(m)


## Where member [m] of group [g] stands: the group position plus a small
## deterministic offset (a loose cluster, not a stack).
func member_position(g: Dictionary, index: int) -> Vector2:
	if index == 0:
		return g.pos
	var a := float(index) * 2.39996
	var r := 1.3 * sqrt(float(index))
	return _clamp((g.pos as Vector2) + Vector2(cos(a), sin(a)) * r)


# --- Simulation ----------------------------------------------------------------------------------

## Advance [minutes] of game time (sub-stepped by max_step_minutes).
func tick(minutes: float) -> void:
	if minutes <= 0.0:
		return
	var left := minutes
	var guard := 0
	while left > 0.0001 and guard < 500:
		var dt := minf(left, params.max_step_minutes)
		_step(dt)
		left -= dt
		guard += 1
	ticks += 1


func _step(dt: float) -> void:
	var ids := _sorted_ids()
	var wander_step := params.wander_speed * dt
	var turn := minf(1.0, dt / 4.0)
	var pull := minf(1.0, 0.25 * dt / 4.0 + 0.1)
	var att_r2 := params.attractor_radius * params.attractor_radius
	var migrate_p := params.migrate_chance_per_hour * dt / 60.0
	# Wandering is slow: half of the wander groups move per step, by twice
	# the step (id parity alternates).
	_parity = 1 - _parity
	for id in ids:
		var g: Dictionary = groups.get(id, {})
		if g.is_empty():
			continue
		match int(g.state):
			State.WANDER:
				if int(id) % 2 == _parity:
					_wander(g, wander_step * 2.0, minf(1.0, turn * 2.0), pull, att_r2, migrate_p * 2.0)
			State.MIGRATE:
				if _walk_to(g, params.migrate_speed * dt):
					g.state = State.WANDER
					g.target = Vector2.INF
			State.INVESTIGATE:
				g.timer = float(g.timer) - dt
				if _walk_to(g, params.investigate_speed * dt) or float(g.timer) <= 0.0:
					g.state = State.WANDER
					g.target = Vector2.INF
					g.timer = 0.0
	# Merging / splitting: a quarter of the groups per step (slow
	# processes; keeps every tick cheap).
	_slice = (_slice + 1) % MERGE_SLICES
	_merge(ids, _slice)
	_split(dt * MERGE_SLICES, _slice, ids)


func _wander(g: Dictionary, step: float, turn: float, pull: float, att_r2: float, migrate_p: float) -> void:
	var h: float = g.heading + rng.randf_range(-turn, turn)
	var pos: Vector2 = g.pos
	# The nearest attractor is cached per group (refreshed every ~40 m).
	var att: Variant = g.get("att")
	if att == null or pos.distance_squared_to(g.att_from) > 1600.0:
		att = nearest_attractor(pos)
		g.att = att
		g.att_from = pos
	var av: Vector2 = att
	if av.x != INF and pos.distance_squared_to(av) > att_r2:
		h = lerp_angle(h, (av - pos).angle(), pull)
	var np := pos + Vector2(cos(h), sin(h)) * step
	if np.x < 2.0 or np.y < 2.0 or np.x > world_size.x - 2.0 or np.y > world_size.y - 2.0:
		h += PI
		np = _clamp(np)
	if h > PI:
		h -= TAU
	elif h < -PI:
		h += TAU
	g.pos = np
	g.heading = h
	if migrate_p > 0.0 and attractors.size() > 1 and rng.randf() < migrate_p:
		var pick := attractors[rng.randi_range(0, attractors.size() - 1)]
		if pick.distance_to(np) > 60.0:
			g.state = State.MIGRATE
			g.target = pick + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))


## Walk toward the group's target; true when arrived.
func _walk_to(g: Dictionary, step: float) -> bool:
	var t: Vector2 = g.target
	if t == Vector2.INF:
		return true
	var pos: Vector2 = g.pos
	var d := pos.distance_to(t)
	if d <= step:
		g.pos = _clamp(t)
		return true
	var dir := (t - pos) / d
	g.pos = _clamp(pos + dir * step)
	g.heading = dir.angle()
	return d - step <= 3.0


func nearest_attractor(p: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for a in attractors:
		var d := a.distance_squared_to(p)
		if d < bd:
			bd = d
			best = a
	return best


func _merge(ids: Array, slice: int = -1) -> void:
	var inv := 1.0 / maxf(params.merge_radius, 1.0)
	var r2 := params.merge_radius * params.merge_radius
	# The cell grid is rebuilt once per round of slices (groups move a few
	# decimetres per step; distances are checked on current positions).
	if slice <= 0 or _grid.is_empty():
		_grid.clear()
		for id in ids:
			var g: Dictionary = groups.get(id, {})
			if g.is_empty():
				continue
			var gp: Vector2 = g.pos
			var k := (floori(gp.x * inv) << 16) + floori(gp.y * inv)
			if _grid.has(k):
				(_grid[k] as Array).append(id)
			else:
				_grid[k] = [id]
	var grid := _grid
	for id in ids:
		if slice >= 0 and int(id) % MERGE_SLICES != slice:
			continue
		var g: Dictionary = groups.get(id, {})
		if g.is_empty():
			continue
		var gp: Vector2 = g.pos
		var kx := floori(gp.x * inv)
		var kz := floori(gp.y * inv)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var cell: Variant = grid.get(((kx + dx) << 16) + kz + dz)
				if cell == null:
					continue
				for oid in cell:
					if oid <= id or not groups.has(oid):
						continue
					var o: Dictionary = groups[oid]
					if int(o.state) != int(g.state):
						continue
					if (o.pos as Vector2).distance_squared_to(g.pos) > r2:
						continue
					var gm: PackedInt32Array = g.members
					var om: PackedInt32Array = o.members
					if gm.size() + om.size() > params.max_group:
						continue
					if int(g.state) != State.WANDER and (o.target as Vector2).distance_to(g.target) > params.merge_radius * 2.0:
						continue
					var w := float(gm.size()) / float(gm.size() + om.size())
					g.pos = (o.pos as Vector2).lerp(g.pos, w)
					gm.append_array(om)
					g.members = gm
					erase_group(oid)
					merges += 1


func _split(dt: float, slice: int = -1, ids: Array = []) -> void:
	for id in (ids if not ids.is_empty() else _sorted_ids()):
		if slice >= 0 and int(id) % MERGE_SLICES != slice:
			continue
		var g: Dictionary = groups.get(id, {})
		if g.is_empty() or int(g.state) != State.WANDER:
			continue
		var m: PackedInt32Array = g.members
		if m.size() <= params.split_size:
			continue
		if rng.randf() >= params.split_chance_per_hour * dt / 60.0:
			continue
		var half := m.size() / 2
		g.members = m.slice(0, m.size() - half)
		var h := float(g.heading) + PI * 0.5
		# Far enough apart not to merge straight back; walking apart.
		var off := Vector2.from_angle(h) * (params.merge_radius + 3.0)
		var nid := add_group((g.pos as Vector2) + off, m.slice(m.size() - half), State.WANDER)
		groups[nid].heading = h
		g.heading = h + PI
		splits += 1


## A loud sound at [pos] carried [reach] metres ([relays]: positions of
## live zombies within reach, which pass it on too): every data group in reach
## walks to it (INVESTIGATE, with a small scatter); groups within
## relay_radius of an attracted group follow as well (zombies follow
## zombies, up to relay_hops; at most max_attracted zombies join by relay,
## nearest first — every group in direct reach turns). Returns how many
## groups turned.
func hear(pos: Vector2, reach: float, relays: PackedVector2Array = PackedVector2Array()) -> int:
	var cands: Array = []
	for id in _sorted_ids():
		cands.append([(groups[id].pos as Vector2).distance_to(pos), id])
	cands.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var attracted: Array = []  # positions of groups already turned
	var chosen := {}
	var members := 0
	var cap := params.max_attracted
	# Hop 0: direct hearing; hop k: within relay_radius of hop k-1 groups.
	var frontier: Array = []
	for c in cands:
		if float(c[0]) > reach:
			break
		chosen[c[1]] = true
		frontier.append(groups[c[1]].pos)
	# [relays]: live zombies that heard it too (the director's) — the
	# groups around them follow them.
	for q in relays:
		frontier.append(q)
	attracted.append_array(frontier)
	var r2 := params.relay_radius * params.relay_radius
	for hop in params.relay_hops:
		if frontier.is_empty() or members >= cap:
			break
		var next: Array = []
		for c in cands:
			if members >= cap:
				break
			var id: int = c[1]
			if chosen.has(id):
				continue
			var gp: Vector2 = groups[id].pos
			for f in frontier:
				if gp.distance_squared_to(f) <= r2:
					chosen[id] = true
					next.append(gp)
					members += (groups[id].members as PackedInt32Array).size()
					break
		frontier = next
	for id in _sorted_ids():
		if not chosen.has(id):
			continue
		var g: Dictionary = groups[id]
		g.state = State.INVESTIGATE
		g.target = _clamp(pos + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)))
		g.timer = params.investigate_minutes + g.pos.distance_to(pos) / maxf(params.investigate_speed, 0.01)
	heard += chosen.size()
	return chosen.size()


## Remove group [id] (keeps the sorted id cache valid).
func erase_group(id: int) -> void:
	if groups.erase(id):
		_mut += 1


func _sorted_ids() -> Array:
	var key := Vector3i(groups.size(), next_group, _mut)
	if key != _ids_key:
		_ids = groups.keys()
		_ids.sort()
		_ids_key = key
	return _ids


func _clamp(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 1.0, world_size.x - 1.0), clampf(p.y, 1.0, world_size.y - 1.0))


# --- Save (compact) ---------------------------------------------------------------------------

## Members as ranges: [0,1,2,5,7,8] → "0-2,5,7-8".
static func ranges_of(m: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	var i := 0
	while i < m.size():
		var j := i
		while j + 1 < m.size() and m[j + 1] == m[j] + 1:
			j += 1
		parts.append(str(m[i]) if j == i else "%d-%d" % [m[i], m[j]])
		i = j + 1
	return ",".join(parts)


## Inverse of ranges_of (empty array for malformed text).
static func parse_ranges(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if s == "":
		return out
	for part in s.split(","):
		var ab := part.split("-")
		if ab.size() == 1 and ab[0].is_valid_int():
			out.append(ab[0].to_int())
		elif ab.size() == 2 and ab[0].is_valid_int() and ab[1].is_valid_int():
			var a := ab[0].to_int()
			var b := ab[1].to_int()
			if b < a or b - a > 100000:
				return PackedInt32Array()
			for k in range(a, b + 1):
				out.append(k)
		else:
			return PackedInt32Array()
	return out


static func _r(v: float) -> float:
	return snappedf(v, 0.01)


## {groups: [[id, x, z, heading, state, tx, tz, timer, "members"]], …}.
func to_dict() -> Dictionary:
	var gl: Array = []
	for id in _sorted_ids():
		var g: Dictionary = groups[id]
		var t: Vector2 = g.target
		var has_t := t != Vector2.INF
		gl.append([id, _r(g.pos.x), _r(g.pos.y), _r(g.heading), int(g.state), _r(t.x) if has_t else -1.0,
			_r(t.y) if has_t else -1.0, _r(g.timer), ranges_of(g.members)])
	var lk := {}
	for m in looks:
		lk[str(m)] = looks[m]
	var hu := {}
	for m in hurt:
		hu[str(m)] = _r(hurt[m])
	return {"groups": gl, "next_group": next_group, "next_member": next_member, "deaths": deaths,
		"rng": str(rng.state), "looks": lk, "hurt": hu}


func from_dict(d: Dictionary) -> void:
	groups.clear()
	_mut += 1
	_grid.clear()
	for e in d.get("groups", []):
		var a: Array = e
		var t := Vector2.INF if float(a[5]) < 0.0 else Vector2(float(a[5]), float(a[6]))
		var id := int(a[0])
		groups[id] = {"id": id, "pos": Vector2(float(a[1]), float(a[2])), "heading": float(a[3]),
			"state": clampi(int(a[4]), 0, 2), "target": t, "timer": float(a[7]), "members": parse_ranges(String(a[8]))}
	next_group = int(d.get("next_group", next_group))
	next_member = int(d.get("next_member", next_member))
	deaths = int(d.get("deaths", 0))
	var st := String(d.get("rng", ""))
	if st.is_valid_int():
		rng.state = st.to_int()
	looks.clear()
	for k in (d.get("looks", {}) as Dictionary):
		looks[int(k)] = int(d.looks[k])
	hurt.clear()
	for k in (d.get("hurt", {}) as Dictionary):
		hurt[int(k)] = float(d.hurt[k])
