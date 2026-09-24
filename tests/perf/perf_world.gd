extends SceneTree
## Round 11 world performance probe (headless, `scripts/perf.sh --world`):
## a new game in maps/world.tscn (seed 1337) — prints the layout time,
## build time, nav bake, node count and instantiated chunks — then the
## player stands on the main street with the start population (40
## zombies around the town), a shout wakes them, and 600 physics steps are
## measured with the same start / end probes as perf_zombies.gd.
## Then the player walks 300 m at sprint speed (whole-frame times while
## chunks bake ahead / regions are freed).
## Budgets: layout < 2 s, load (generate + build + nav) < 8 s (Round 12), avg < 10 ms,
## p99 < 16 ms (hostile physics and walking frames). Exit 1 when over budget.
## No static typing against gameplay classes (-s scripts compile first).

const FRAMES := 600
const LAYOUT_BUDGET_MS := 2000.0
const LOAD_BUDGET_MS := 8000.0
const AVG_BUDGET_MS := 10.0
const P99_BUDGET_MS := 16.0
const WANT_ZOMBIES := 40

const Probe = preload("res://tests/perf/perf_zombies.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var sm: Node = root.get_node("SaveManager")
	var t0 := Time.get_ticks_msec()
	var map: Node = sm.instantiate_new_game("res://maps/world.tscn", 1337)
	root.add_child(map)
	var t_built := Time.get_ticks_msec()
	var nav: Node = map.get_node("NavRegion")
	while not nav.baked:
		await physics_frame
	var t_nav := Time.get_ticks_msec()
	var builder: Node = map.get_node("Generated")
	var spawner: Node = map.get_node("Zombies")
	for i in 30:
		await physics_frame
	var player: Node3D = map.get_node("Player")
	player.get_node("Health").invulnerable = true
	player.get_node("Controller").scripted = true
	# On the main street, in the middle of town.
	var road: Dictionary = builder.layout.road("town_main")
	var pts: PackedVector2Array = road.points
	var mid: Vector2 = pts[pts.size() / 2]
	player.global_position = Vector3(mid.x + 2.0, 0.1, mid.y + 2.0)
	# Top up to 40 near the town if some start points were unusable.
	var extra := 0
	while spawner.alive_count() < WANT_ZOMBIES and extra < 20:
		var p: Vector3 = spawner.pick_spawn_point(player.global_position, 60.0, 10.0)
		extra += 1
		if p != Vector3.INF:
			spawner.spawn_at(p)
	for i in 30:
		await physics_frame
	root.get_node("SoundManager").emit_sound(&"shout", player.global_position, null, {"radius": 40.0, "intensity": 1.0})
	for i in 120:
		await physics_frame
	var probe = Probe.PhysicsProbe.new()
	root.add_child(probe)
	var tw := Time.get_ticks_msec()
	while probe.samples.size() < FRAMES:
		await physics_frame
	var wall := (Time.get_ticks_msec() - tw) / 1000.0
	var samples: Array[float] = probe.samples.duplicate()
	probe.queue_free()
	var total := 0.0
	var worst := 0.0
	for v in samples:
		total += v
		worst = maxf(worst, v)
	var avg := total / maxi(samples.size(), 1)
	samples.sort()
	var p99: float = samples[mini(int(samples.size() * 0.99), samples.size() - 1)]
	var states := {}
	var near := 0
	for z in spawner.zombies:
		if is_instance_valid(z) and not z.dead:
			states[z.state()] = states.get(z.state(), 0) + 1
			if z.global_position.distance_to(player.global_position) < 80.0:
				near += 1
	# Walking: 300 m at sprint speed (6.5 m/s, moved every physics step)
	# from the main street toward the far side of the map — chunks ahead
	# bake on worker threads, far regions are freed. Whole-frame times.
	var walk := await _walk(map, player, nav, 300.0, 6.5)
	var load_ms := float(t_nav - t0)
	print("PERF world seed=1337 layout_ms=%.0f build_ms=%.0f add_ms=%d nav_bake_ms=%.0f load_total_ms=%.0f" % [
		builder.layout_ms, builder.build_ms, t_built - t0, nav.bake_ms, load_ms])
	print("PERF world chunks=%d nav_regions=%d buildings=%d trees=%d world_nodes=%d scene_nodes=%d" % [
		builder.chunks.size(), nav.regions.size(), builder.buildings.size(), builder.layout.tree_count(),
		builder.node_count(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("PERF world zombies=%d (within 80 m: %d) states=%s" % [spawner.alive_count(), near, str(states)])
	print("PERF world frames=%d avg_physics_ms=%.3f p99_ms=%.3f worst_ms=%.3f wall_s=%.1f" % [samples.size(), avg, p99, worst, wall])
	print("PERF world walk %.0f m in %.1f s: frames=%d avg_frame_ms=%.3f p99_frame_ms=%.3f worst_ms=%.3f physics_p99_ms=%.3f regions_baked=%d freed=%d max_alive=%d player_chunk_unbaked=%d/%d" % [
		walk.dist, walk.secs, walk.frames, walk.avg, walk.p99, walk.worst, walk.phys_p99, walk.baked, nav.freed_count, nav.max_alive, walk.uncovered, walk.checks])
	var ok: bool = builder.layout_ms < LAYOUT_BUDGET_MS and load_ms < LOAD_BUDGET_MS and avg < AVG_BUDGET_MS \
		and p99 <= P99_BUDGET_MS and spawner.alive_count() >= WANT_ZOMBIES * 0.9 and walk.p99 <= P99_BUDGET_MS
	print("PERF_RESULT world: %s avg %.2f ms (budget %.1f), p99 %.2f ms (budget %.1f), layout %.0f ms (budget %.0f), load %.0f ms (budget %.0f)" % [
		"OK" if ok else "OVER BUDGET", avg, AVG_BUDGET_MS, p99, P99_BUDGET_MS, builder.layout_ms, LAYOUT_BUDGET_MS, load_ms, LOAD_BUDGET_MS])
	map.queue_free()
	await process_frame
	quit(0 if ok else 1)


func _walk(map: Node, player: Node3D, nav: Node, dist: float, speed: float) -> Dictionary:
	var builder: Node = map.get_node("Generated")
	var size: Vector2 = builder.layout.size
	var from := Vector2(player.global_position.x, player.global_position.z)
	# Toward the farthest map corner region (stays inside the world).
	var target := Vector2(size.x - 60.0 if from.x < size.x * 0.5 else 60.0, size.y - 60.0 if from.y < size.y * 0.5 else 60.0)
	var dir := (target - from).normalized()
	for z in map.get_node("Zombies").zombies:
		if is_instance_valid(z):
			z.set_physics_process(false)
	var probe = Probe.PhysicsProbe.new()
	root.add_child(probe)
	var fprobe := FrameProbe.new()
	fprobe.nav = nav
	fprobe.builder = builder
	fprobe.phys = probe
	root.add_child(fprobe)
	var baked0: int = nav.regions.size() + nav.freed_count
	var moved := 0.0
	var checks := 0
	var uncovered := 0
	var t0 := Time.get_ticks_msec()
	while moved < dist:
		await physics_frame
		var step := speed / float(Engine.physics_ticks_per_second)
		moved += step
		var q := from + dir * moved
		player.global_position = Vector3(q.x, 0.1, q.y)
		player.velocity = Vector3(dir.x, 0.0, dir.y) * speed
		checks += 1
		if checks % 10 == 0 and not nav.chunk_ready(builder.layout.chunk_of(q)):
			uncovered += 1

	player.velocity = Vector3.ZERO
	var phys: Array[float] = probe.samples.duplicate()
	probe.queue_free()
	var frame_ms: Array[float] = fprobe.samples.duplicate()
	fprobe.queue_free()
	frame_ms.remove_at(0)
	var total := 0.0
	var worst := 0.0
	for v in frame_ms:
		total += v
		worst = maxf(worst, v)
	frame_ms.sort()
	phys.sort()
	return {"dist": dist, "secs": (Time.get_ticks_msec() - t0) / 1000.0, "frames": frame_ms.size(),
		"avg": total / maxf(frame_ms.size(), 1.0), "p99": frame_ms[mini(int(frame_ms.size() * 0.99), frame_ms.size() - 1)],
		"worst": worst, "phys_p99": phys[mini(int(phys.size() * 0.99), phys.size() - 1)] if not phys.is_empty() else 0.0,
		"baked": nav.regions.size() + nav.freed_count - baked0, "uncovered": uncovered, "checks": checks / 10}


## Main-thread work per physics tick: the physics step's scripts (the
## PhysicsProbe window: movement, AI, WorldNav queueing / source parsing)
## + the region hand-over (deferred) + the light budget pass since the
## previous tick. (Wall time is paced by the 60 Hz physics clock and
## headless idles between ticks, so it is not a work measure.)
class FrameProbe extends Node:
	var samples: Array[float] = []
	var nav: Node
	var builder: Node
	var phys: Node

	func _ready() -> void:
		process_physics_priority = 100001

	func _physics_process(_delta: float) -> void:
		var p: float = phys.samples[phys.samples.size() - 1] if phys != null and not phys.samples.is_empty() else 0.0
		var extra: float = (float(nav.apply_usec) + float(builder.light_usec)) / 1000.0
		nav.apply_usec = 0
		builder.light_usec = 0
		samples.append(p + extra)
