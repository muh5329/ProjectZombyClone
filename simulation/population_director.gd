class_name PopulationDirector
extends Node
## Bridges the zombie population DATA (ZombiePopulation) and the real
## Zombie nodes (Round 12; node "Population" in maps/world.tscn).
##
## - Sim: every [tick_seconds] of real time the population advances by the
##   GAME minutes that passed (TimeManager), so fast-forward and sleep move
##   groups proportionally (sub-stepped inside ZombiePopulation.tick).
## - Sound: a sound whose category has sim_carry > 0 (window smash, door
##   break / bang, hammering, shout, wood breaking, alarm, gunshot,
##   vehicle…; never footsteps) reaches every data group within radius ×
##   sim_carry (× params.indoor_factor when made inside a building); those
##   groups — and groups near them (relay) — walk toward it.
## - Active area: chunks within [active_radius] of the player that are
##   loaded and have a verified navmesh. Their groups become real zombies
##   (nearest first, at most [spawn_per_sync] per pass, never more than
##   [max_active] alive), spawn id "pop/<member>", look seed from the
##   member id. Zombies farther than [release_radius] chunks from the
##   player — or in a chunk that is unloading — fold back into data with
##   their position, calm state / investigation target and wounds. A
##   zombie killed stays dead: its member is gone (deaths counted) and its
##   corpse belongs to the chunk it lies in (ChunkStreamer).
## - Saves: save_state() = population.to_dict(); real zombies are saved
##   by WorldSnapshot as usual (their spawn ids name their members).

const GROUP := &"population_director"
const DEFAULT_PARAMS := "res://data/simulation/default_population.tres"

@export var params: PopulationParams
@export var active_radius: int = 2
@export var release_radius: int = 3
@export var max_active: int = 120
@export var tick_seconds: float = 0.5
@export var sync_seconds: float = 0.25
## Members queued for instantiation per sync pass.
@export var spawn_per_sync: int = 24
## Instantiation time per physics frame (ms; at least one zombie).
@export var spawn_budget_ms: float = 5.0
@export var enabled: bool = true
## Calm zombies farther than this are frozen (LOD), woken within
## [wake_distance] or when a sound changes their state.
@export var freeze_distance: float = 50.0
@export var wake_distance: float = 42.0

var population: ZombiePopulation
var builder: WorldBuilder
var streamer: ChunkStreamer
var spawner: ZombieSpawner
var nav: NavBaker
## Stats: µs of the last sim tick, instantiated / folded counts.
var sim_usec: int = 0
var sim_usec_max: int = 0
var spawned_count: int = 0
var folded_count: int = 0
var died_count: int = 0
var frozen_count: int = 0
## Reach (m) of the last sound forwarded into the sim (tests / debug).
var last_sound_reach: float = 0.0
var last_sound_groups: int = 0
var last_sound_relays: int = 0
var sync_usec: int = 0
var active_usec: int = 0

var _last_minute: float = 0.0
var _tick_accum: float = 0.0
var _sync_accum: float = 0.0
var _retry_at: Dictionary = {}  # group id → physics seconds of the next try
var _spawn_list: Array = []  # [group id, member, index in the group]
var _fold_list: Array = []  # zombies to fold back into data
## µs of fold / spawn work in process frame [work_frame] (the streamer
## takes it off its own build budget).
var work_usec: int = 0
var work_frame: int = -1
## Running average cost of one instantiation (µs): a spawn only starts
## when it fits the frame's budget (the first one always does).
var spawn_cost_usec: float = 4000.0


static func of(tree: SceneTree) -> PopulationDirector:
	return tree.get_first_node_in_group(GROUP) as PopulationDirector if tree != null else null


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if params == null:
		params = load(DEFAULT_PARAMS) as PopulationParams
	builder = WorldBuilder.of(get_tree())
	streamer = ChunkStreamer.of(get_tree())
	var map := get_parent()
	spawner = map.get_node_or_null("Zombies") as ZombieSpawner
	for c in map.get_children():
		if c is NavBaker:
			nav = c
	if builder == null or builder.layout == null or not enabled:
		return
	var cfg := WorldConfig.find(get_tree())
	var saved: Dictionary = cfg.stream_state.get("population", {}) if cfg != null else {}
	population = ZombiePopulation.generate(builder.layout, builder.world_seed, params)
	if saved.get("legacy", false):
		_drop_legacy(saved)
	elif not saved.is_empty():
		population.from_dict(saved)
	_last_minute = TimeManager.now()
	if streamer != null:
		streamer.chunk_unloading.connect(_on_chunk_unloading)
	SoundManager.sound_dispatched.connect(_on_sound)
	EventBus.zombie_died.connect(_on_zombie_died)


func _exit_tree() -> void:
	if SoundManager.sound_dispatched.is_connected(_on_sound):
		SoundManager.sound_dispatched.disconnect(_on_sound)
	if EventBus.zombie_died.is_connected(_on_zombie_died):
		EventBus.zombie_died.disconnect(_on_zombie_died)


## A Round-11 save: its start pack and spawned rural groups are in the
## save's zombie records already (drop them from the fresh population).
func _drop_legacy(saved: Dictionary) -> void:
	var spawned := {}
	for g in saved.get("groups_spawned", []):
		spawned[String(g)] = true
	for id in population.groups.keys():
		var tag := String(population.groups[id].get("tag", ""))
		if tag == "start" or spawned.has(tag):
			population.erase_group(id)


# --- Queries -----------------------------------------------------------------------------------

## Living real zombies of the spawner.
func real_zombies() -> Array[Zombie]:
	var out: Array[Zombie] = []
	if spawner == null:
		return out
	for z in spawner.zombies:
		if is_instance_valid(z) and not z.dead and not z.is_queued_for_deletion():
			out.append(z)
	return out


func active_count() -> int:
	return real_zombies().size()


## Members in data + real zombies (constant except for deaths).
func total_alive() -> int:
	return (population.total() if population != null else 0) + active_count()


static func member_of(z: Zombie) -> int:
	var sid := String(z.spawn_id)
	if sid.begins_with("pop/") and sid.substr(4).is_valid_int():
		return sid.substr(4).to_int()
	return -1


func _player_pos() -> Variant:
	var pl := GameManager.player as Node3D
	if pl != null and is_instance_valid(pl) and pl.is_inside_tree() and get_parent().is_ancestor_of(pl):
		return pl.global_position
	return null


func _chunk(p: Vector3) -> Vector2i:
	return builder.layout.chunk_of(Vector2(p.x, p.z))


## Chunks whose groups may be instantiated now.
func active_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var pp: Variant = _player_pos()
	if pp == null or builder == null:
		return out
	for c in builder.layout.chunks_around(_chunk(pp), active_radius):
		if builder.chunks.has(c) and (nav == null or not nav.has_method(&"chunk_ready") or bool(nav.call(&"chunk_ready", c))):
			out.append(c)
	return out


# --- Per frame --------------------------------------------------------------------------------

func _ready_to_run() -> bool:
	return population != null and enabled and not SaveManager.loading and spawner != null \
		and (nav == null or nav.baked)


## µs of the last physics tick (perf probes).
var frame_usec: int = 0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_frame(delta)
	frame_usec = Time.get_ticks_usec() - t0


func _frame(delta: float) -> void:
	if not _ready_to_run():
		_last_minute = TimeManager.now()
		return
	_tick_accum += delta / maxf(Engine.time_scale, 0.001)
	if _tick_accum >= tick_seconds:
		_tick_accum = 0.0
		tick_now()
	_sync_accum += delta
	if _sync_accum >= sync_seconds:
		_sync_accum = 0.0
		var ts := Time.get_ticks_usec()
		sync_now()
		sync_usec = Time.get_ticks_usec() - ts
	if not _fold_list.is_empty() or not _spawn_list.is_empty():
		_work()


## Advance the sim by the game minutes since the last tick.
func tick_now() -> void:
	var now := TimeManager.now()
	var dt := now - _last_minute
	_last_minute = now
	if dt <= 0.0:
		return
	var t0 := Time.get_ticks_usec()
	population.tick(dt)
	sim_usec = Time.get_ticks_usec() - t0
	sim_usec_max = maxi(sim_usec_max, sim_usec)


## Fold far zombies back, queue the groups of active chunks for
## instantiation (nearest first). At the cap, calm live zombies much
## farther away than the nearest waiting group make room for it.
func sync_now() -> void:
	var pp: Variant = _player_pos()
	if pp == null or population == null:
		return
	var p3: Vector3 = pp
	var pc := _chunk(p3)
	var live: Array = []
	var far: Array = []
	for z in real_zombies():
		var zc := _chunk(z.global_position)
		var d := z.global_position.distance_to(p3)
		if ChunkStreamer.chebyshev(zc, pc) > release_radius or not builder.chunks.has(zc):
			far.append([-d, z])
		else:
			live.append([d, z])
	_apply_lod(live)
	far.sort_custom(func(a, b): return a[0] < b[0])
	_fold_list.clear()
	for e in far:
		_fold_list.append(e[1])
	_spawn_list.clear()
	var ta := Time.get_ticks_usec()
	var act := active_chunks()
	active_usec = Time.get_ticks_usec() - ta
	if act.is_empty():
		return
	var set := {}
	for c in act:
		set[c] = true
	var cands: Array = []
	var p2 := Vector2(p3.x, p3.z)
	for id in population.groups:
		var g: Dictionary = population.groups[id]
		if not set.has(population.chunk_of(g.pos)):
			continue
		if float(_retry_at.get(id, 0.0)) > SoundManager.now():
			continue
		cands.append([p2.distance_to(g.pos), id])
	if cands.is_empty():
		return
	cands.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var room := max_active - live.size()
	if room <= 0:
		# Nearest first: swap far calm zombies for nearer waiting groups.
		live.sort_custom(func(a, b): return a[0] > b[0])
		var nearest: float = cands[0][0]
		var swaps := 0
		for e in live:
			if swaps >= 4 or float(e[0]) < maxf(nearest + 30.0, 48.0):
				break
			var z: Zombie = e[1]
			if z.hostile:
				continue
			_fold_list.append(z)
			swaps += 1
		return
	var want := mini(spawn_per_sync, room)
	for cand in cands:
		if _spawn_list.size() >= want:
			break
		var gid := int(cand[1])
		var g: Dictionary = population.groups[gid]
		var mm: PackedInt32Array = g.members
		for i in mm.size():
			if _spawn_list.size() >= want:
				break
			_spawn_list.append([gid, mm[i], i])


## Medium-distance LOD (the brief's "simplified simulation"): a calm
## (idle / wandering) zombie farther than [freeze_distance] from the
## player stops its per-frame AI / senses / movement; it stays a body in
## the world and a sound listener. It wakes when the player comes within
## [wake_distance] or when a sound changed its state (heard → investigate).
func _apply_lod(live: Array) -> void:
	var n := 0
	for e in live:
		var d: float = e[0]
		var z: Zombie = e[1]
		var s := z.state()
		var calm := not z.hostile and (s == ZombieAI.S_IDLE or s == ZombieAI.S_WANDER)
		var frozen := not z.is_physics_processing()
		if frozen and (d < wake_distance or not calm):
			z.set_physics_process(true)
		elif not frozen and calm and d > freeze_distance and not z.is_climbing():
			z.set_physics_process(false)
			z.velocity = Vector3.ZERO
		if not z.is_physics_processing():
			n += 1
	frozen_count = n


## Fold queued zombies back and instantiate queued members within
## [spawn_budget_ms] per physics frame (at least one): building a zombie
## costs a few ms (model, navigation agent), freeing one about 1 ms.
func _work() -> void:
	var t0 := Time.get_ticks_usec()
	var budget := int(spawn_budget_ms * 1000.0)
	var done := 0
	while not _fold_list.is_empty():
		if done > 0 and Time.get_ticks_usec() - t0 > budget:
			break
		var z: Variant = _fold_list.pop_front()
		if z != null and is_instance_valid(z):
			fold_zombie(z)
			done += 1
	if _fold_list.is_empty():
		_spawn_queued(t0, done)
	work_usec = Time.get_ticks_usec() - t0
	work_frame = Engine.get_process_frames()


func _spawn_queued(t0: int = -1, done: int = 0) -> void:
	if t0 < 0:
		t0 = Time.get_ticks_usec()
	var made := done
	while not _spawn_list.is_empty():
		if made > 0 and Time.get_ticks_usec() - t0 + spawn_cost_usec > spawn_budget_ms * 1000.0:
			break
		if active_count() >= max_active:
			_spawn_list.clear()
			break
		var e: Array = _spawn_list.pop_front()
		var gid := int(e[0])
		var m := int(e[1])
		var g: Dictionary = population.groups.get(gid, {})
		if g.is_empty() or not (g.members as PackedInt32Array).has(m):
			continue
		var q := population.member_position(g, int(e[2]))
		var p := spawner.find_spot(Vector3(q.x, 0.0, q.y))
		made += 1  # a failed attempt costs as much as a spawn
		if p == Vector3.INF:
			# Nowhere to stand (inside a building, too near the player):
			# the whole group waits a few seconds.
			_retry_at[gid] = SoundManager.now() + 5.0
			_spawn_list = _spawn_list.filter(func(x): return int(x[0]) != gid)
			continue
		if not population.take_member(gid, m):
			continue
		var ts := Time.get_ticks_usec()
		_spawn_member(m, g, p)
		spawn_cost_usec = lerpf(spawn_cost_usec, float(Time.get_ticks_usec() - ts), 0.2)


## Fold / instantiate everything queued now (tests / tools).
func flush_spawns() -> void:
	var keep := spawn_budget_ms
	spawn_budget_ms = 1.0e6
	_work()
	spawn_budget_ms = keep


## [p] clamped into the loaded chunks around the player (4 m inset).
func clamp_to_loaded(p: Vector2) -> Vector2:
	var pp: Variant = _player_pos()
	if pp == null or builder == null:
		return p
	var cs := builder.layout.chunk_size
	var pc := _chunk(pp)
	var r := streamer.load_radius if streamer != null else 2
	var lo := Vector2(maxi(pc.x - r, 0), maxi(pc.y - r, 0)) * cs + Vector2(4, 4)
	var hi := Vector2(mini(pc.x + r + 1, builder.layout.chunks_x()), mini(pc.y + r + 1, builder.layout.chunks_z())) * cs - Vector2(4, 4)
	return Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))


func _spawn_member(m: int, g: Dictionary, p: Vector3) -> Zombie:
	var state := "idle" if m % 3 != 0 else "wander"
	var target: Variant = null
	if int(g.state) != ZombiePopulation.State.WANDER and (g.target as Vector2) != Vector2.INF:
		state = "investigate"
		# A group's goal can lie hundreds of metres away, off the streamed
		# navmesh: the live zombie heads for the same goal clamped into the
		# loaded area (it folds back into the group's data if it walks out).
		var t := clamp_to_loaded(g.target)
		target = [t.x, 0.0, t.y]
	var rec := {"spawn_id": "pop/%d" % m, "seed": population.member_seed(m), "position": Saveable.vec3(p),
		"facing": float(g.heading), "home": Saveable.vec3(p), "state": state, "target": target,
		"health": float(population.hurt.get(m, 1.0e9))}
	population.hurt.erase(m)
	var z := spawner.restore_zombie(rec)
	spawned_count += 1
	return z


## Zombie [z] leaves the active area: back into the data.
func fold_zombie(z: Zombie) -> void:
	if z == null or not is_instance_valid(z) or z.dead or z.is_queued_for_deletion() or z.get_parent() == null:
		return
	var rec := z.save_record()
	var m := member_of(z)
	var seed_override := 0
	if m < 0:
		m = population.new_members(1)[0]
		seed_override = z.ai_seed
	var pos := Saveable.to_vec3(rec.position)
	var state := ZombiePopulation.State.WANDER
	var target := Vector2.INF
	if rec.get("target") != null and String(rec.state) == "investigate":
		var t := Saveable.to_vec3(rec.target)
		state = ZombiePopulation.State.INVESTIGATE
		target = Vector2(t.x, t.z)
	var hp := float(rec.health)
	var full := z.profile.health if z.profile != null else hp
	population.fold(m, Vector2(pos.x, pos.z), state, target, hp if hp < full - 0.01 else -1.0, seed_override)
	z.folded_by = self
	z.set_meta(&"pop_member", m)
	spawner.zombies.erase(z)
	z.remove_from_group(&"zombie")
	z.get_parent().remove_child(z)
	z.queue_free()
	folded_count += 1


## A zombie killed after it was folded (the same frame): its member leaves
## the population as a death and its corpse lies where it stood.
func on_folded_zombie_died(z: Zombie, _killer: Node) -> ZombieCorpse:
	var m := int(z.get_meta(&"pop_member", -1))
	if m >= 0 and population != null:
		population.remove_member(m)
		population.record_death(m)
	died_count += 1
	if spawner == null or not spawner.is_inside_tree():
		return null
	var sid := String(z.spawn_id) if String(z.spawn_id) != "" else "pop/%d" % m
	return ZombieCorpse.restore(spawner, {"persist_id": "corpse/%s" % sid, "seed": z.ai_seed,
		"position": Saveable.vec3(spawner.global_transform * z.position), "yaw": 0.0, "pose": "death",
		"container": {"searched": false, "inventory": {"items": []}}})


func _on_chunk_unloading(c: Vector2i) -> void:
	if population == null:
		return
	for z in real_zombies():
		if _chunk(z.global_position) == c:
			fold_zombie(z)


func _on_sound(ev: SoundEvent, _heard: int) -> void:
	if population == null or ev == null or not get_parent().is_inside_tree():
		return
	var reach := sim_reach(ev)
	if reach <= 0.0:
		return
	last_sound_reach = reach
	var p2 := Vector2(ev.position.x, ev.position.z)
	# Live zombies in reach pass it on to the groups beyond the active area
	# (zombies follow zombies): a smash in town reaches the county's data
	# groups through the town's own zombies.
	# Live zombies in reach — and, zombies following zombies, calm live
	# zombies within relay_radius of those (up to relay_hops, at most
	# max_attracted) — walk toward it too and pass it on to the data groups
	# beyond the active area: a smash in town reaches the county's groups
	# through the town's own zombies.
	var relays := PackedVector2Array()
	var live := real_zombies()
	var chained := {}
	var frontier: Array = []
	for z in live:
		var zp := Vector2(z.global_position.x, z.global_position.z)
		if zp.distance_to(p2) <= reach:
			chained[z] = true
			frontier.append(zp)
			relays.append(zp)
	var r2 := params.relay_radius * params.relay_radius
	var joined := 0
	for hop in params.relay_hops:
		var next: Array = []
		for z in live:
			if chained.has(z) or joined >= params.max_attracted:
				continue
			var zp := Vector2(z.global_position.x, z.global_position.z)
			for f in frontier:
				if zp.distance_squared_to(f) <= r2:
					chained[z] = true
					next.append(zp)
					relays.append(zp)
					joined += 1
					var s := z.state()
					if not z.hostile and (s == ZombieAI.S_IDLE or s == ZombieAI.S_WANDER):
						z.ai.investigate_quietly(ev.position)
						z.ai.change_to(ZombieAI.S_INVESTIGATE)
						if not z.is_physics_processing():
							z.set_physics_process(true)
					break
		if next.is_empty():
			break
		frontier = next
	last_sound_relays = relays.size()
	last_sound_groups = population.hear(p2, reach, relays)


## How far [ev] carries for the population (0 = not at all).
func sim_reach(ev: SoundEvent) -> float:
	var cat := SoundManager.category(ev.category)
	var carry := cat.sim_carry if cat != null else 0.0
	if carry <= 0.0:
		return 0.0
	var reach := ev.radius * carry
	if SoundManager.building_at(ev.position + Vector3.UP * 0.5) != null:
		reach *= params.indoor_factor
	return reach


func _on_zombie_died(z: Node, _killer: Node) -> void:
	if population == null or not z is Zombie or not get_parent().is_ancestor_of(z):
		return
	var m := member_of(z as Zombie)
	if m >= 0:
		population.record_death(m)
	died_count += 1


# --- Save --------------------------------------------------------------------------------------

func save_state() -> Dictionary:
	return population.to_dict() if population != null else {}
