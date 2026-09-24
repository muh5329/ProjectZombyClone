extends SceneTree
## Round 12 streaming performance probe (headless, part of
## `scripts/perf.sh --world`; alone: `-s tests/perf/perf_streaming.gd`):
##
## 1. memory: static memory + node count at the start house, then after a
##    1 km walk (sprint speed, out and back) at the same spot — no growth
##    beyond MEM_BUDGET_MB / 10 % nodes (no leaks from streaming);
## 2. sprint through town and through woods (6.5 m/s, 250 m each): whole
##    main-loop frame times (FrameTimer: avg / p99 / worst) and the
##    scene-tree part of every physics step (perf_zombies' PhysicsProbe:
##    avg / p99);
## 3. the population sim with 1000 zombies: µs per tick (0.5 game min,
##    what the director runs at 2 Hz) — budget < 1 ms average;
## 4. save / load of a world with 50 changed objects (searched containers
##    / opened doors in loaded and unloaded chunks): ms and bytes.
## Exit 1 when over budget. No static typing against gameplay classes.

const MEM_BUDGET_MB := 16.0
## Round 12 critic fix: trunks are no longer carved into the navmesh and
## far goals are walked in 40 m legs (no unreachable-target searches), so
## both sprint legs hold the 33 ms line.
const FRAME_WORST_BUDGET_MS := 33.0
const FRAME_P99_BUDGET_MS := 20.0
const SIM_TICK_BUDGET_US := 1000.0
const SAVE_BUDGET_MS := 200.0
const LOAD_BUDGET_MS := 8000.0

const FrameTimer = preload("res://tests/integration/frame_timer.gd")
const Probe = preload("res://tests/perf/perf_zombies.gd")

var ok: bool = true


func _init() -> void:
	call_deferred("_run")


func _check(cond: bool, what: String) -> void:
	if not cond:
		ok = false
		print("PERF streaming OVER BUDGET: ", what)


func _run() -> void:
	await process_frame
	var sm: Node = root.get_node("SaveManager")
	var map: Node = sm.instantiate_new_game("res://maps/world.tscn", 1337)
	root.add_child(map)
	var nav: Node = map.get_node("NavRegion")
	while not nav.baked:
		await physics_frame
	var player: Node3D = map.get_node("Player")
	player.get_node("Health").invulnerable = true
	player.get_node("Controller").scripted = true
	player.get_node("Interaction").scripted = true
	var builder: Node = map.get_node("Generated")
	var st: Node = map.get_node("Streamer")
	var pd: Node = map.get_node("Population")
	for i in 120:
		await physics_frame
	# --- 1. Memory over a 1 km walk ---------------------------------------------------------
	var start := player.global_position
	var mem0 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var size: Vector2 = builder.layout.size
	var dir := Vector3(size.x * 0.5, 0.0, size.y * 0.5) - start
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 1.0 else Vector3.RIGHT
	await _sprint(player, start, dir, 500.0, null)
	await _sprint(player, player.global_position, -dir, 500.0, null)
	for i in 240:
		await physics_frame
	st.flush()
	for i in 60:
		await physics_frame
	var mem1 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var nodes1 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	# The same walk again: caches (zombie looks, vehicle meshes, navmesh
	# sources) are warm now, so any further growth would be a leak.
	await _sprint(player, start, dir, 500.0, null)
	await _sprint(player, player.global_position, -dir, 500.0, null)
	for i in 240:
		await physics_frame
	st.flush()
	for i in 60:
		await physics_frame
	var mem2 := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var nodes2 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print("PERF streaming memory: static %.1f MB → %.1f MB after 1 km (first walk: caches warm up) → %.1f MB after 2 km (Δ second km %.1f MB, budget %.0f), nodes %d → %d → %d, chunks loaded %d, unloaded %d" % [
		mem0, mem1, mem2, mem2 - mem1, MEM_BUDGET_MB, nodes0, nodes1, nodes2, st.loads, st.unloads])
	_check(mem2 - mem1 < MEM_BUDGET_MB, "memory grew %.1f MB over the second km" % (mem2 - mem1))
	_check(nodes2 < nodes0 * 1.1 + 500, "node count grew %d → %d" % [nodes0, nodes2])
	# --- 2. Sprint through town and woods -------------------------------------------------------
	var town := _town_center(builder)
	var woods := _woods_line(builder)
	for leg in [["town", town], ["woods", woods]]:
		var a: Vector3 = leg[1][0]
		var b: Vector3 = leg[1][1]
		player.global_position = a
		for i in 30:
			await physics_frame
		st.flush()
		while not nav.chunk_ready(builder.layout.chunk_of(Vector2(a.x, a.z))):
			await physics_frame
		for i in 120:
			await physics_frame
		var ft = FrameTimer.new()
		root.add_child(ft)
		var pprobe = Probe.PhysicsProbe.new()
		root.add_child(pprobe)
		ft.probe = func() -> Array:
			return [snappedf(st.frame_ms, 0.1), snappedf(pd.frame_usec / 1000.0, 0.1), snappedf(pd.sync_usec / 1000.0, 0.1), snappedf(nav.tick_usec / 1000.0, 0.1),
				snappedf(pprobe.samples[pprobe.samples.size() - 1] if not pprobe.samples.is_empty() else 0.0, 0.1), st.loads, st.unloads, pd.spawned_count, pd.folded_count, pd.frozen_count]
		ft.start()
		await _sprint(player, a, (b - a).normalized(), minf(a.distance_to(b), 250.0), null)
		ft.stop()
		var phys: Array[float] = pprobe.samples.duplicate()
		pprobe.queue_free()
		var pavg := 0.0
		for v in phys:
			pavg += v
		pavg /= maxf(phys.size(), 1.0)
		phys.sort()
		var pp99: float = phys[mini(int(phys.size() * 0.99), phys.size() - 1)] if not phys.is_empty() else 0.0
		print("PERF streaming sprint %s: frames=%d avg_frame_ms=%.2f p99_frame_ms=%.2f worst_frame_ms=%.1f avg_physics_ms=%.2f p99_physics_ms=%.2f live_zombies=%d frozen=%d" % [
			leg[0], ft.intervals.size(), ft.average(), ft.percentile(0.99), ft.worst(), pavg, pp99, pd.active_count(), pd.frozen_count])
		for line in ft.slow_report(FRAME_WORST_BUDGET_MS):
			print("PERF streaming slow frame [streamer, director, sync, nav, physics, loads, unloads, spawned, folded, frozen] ", line)
		_check(ft.percentile(0.99) <= FRAME_P99_BUDGET_MS, "%s p99 frame %.1f ms" % [leg[0], ft.percentile(0.99)])
		_check(ft.worst() <= FRAME_WORST_BUDGET_MS, "%s worst frame %.1f ms" % [leg[0], ft.worst()])
		ft.queue_free()
	# --- 3. Population sim with 1000 zombies ----------------------------------------------------
	var prm: Resource = load("res://data/simulation/default_population.tres").duplicate()
	prm.total_at_768 = 1000
	prm.total_max = 1000
	var pop = load("res://simulation/zombie_population.gd").generate(builder.layout, 1337, prm)
	var ticks: Array[float] = []
	for i in 400:
		var t0 := Time.get_ticks_usec()
		pop.tick(0.5)
		if i >= 40:
			ticks.append(float(Time.get_ticks_usec() - t0))
	var tavg := 0.0
	for v in ticks:
		tavg += v
	tavg /= ticks.size()
	ticks.sort()
	print("PERF streaming population: %d zombies in %d groups, tick avg %.0f µs, p99 %.0f µs, max %.0f µs (budget avg %.0f µs); fast-forward 8 h: %.1f ms" % [
		pop.total(), pop.groups.size(), tavg, ticks[int(ticks.size() * 0.99)], ticks[ticks.size() - 1], SIM_TICK_BUDGET_US, _ff_ms(pop)])
	_check(tavg < SIM_TICK_BUDGET_US, "population tick %.0f µs" % tavg)
	# --- 4. Save / load with 50 changed objects ------------------------------------------------------
	player.global_position = start
	for i in 30:
		await physics_frame
	st.flush()
	var changed := 0
	for id in builder.buildings:
		var hb = builder.buildings[id]
		for c in hb.containers:
			if changed >= 35:
				break
			c.ensure_loot()
			changed += 1
		for d in hb.doors:
			if changed >= 50:
				break
			if not d.is_open() and d.state != &"broken":
				d.load_state({"state": "open", "health": d.health, "locked": false, "swing": 1.4})
				changed += 1
		if changed >= 50:
			break
	var r: Dictionary = sm.save_game("perf streaming", map)
	var data: Dictionary = sm.read_slot("perf streaming").data
	var lr: Dictionary = await sm.load_game("perf streaming", map)
	print("PERF streaming save/load with %d changed objects: save %.1f ms, %d bytes (%d statics), load %.0f ms" % [
		changed, float(r.get("ms", -1.0)), int(r.get("bytes", 0)), (data.get("statics", {}) as Dictionary).size(), float(lr.get("ms", -1.0))])
	_check(bool(r.get("ok", false)) and float(r.ms) < SAVE_BUDGET_MS, "save %.1f ms" % float(r.get("ms", -1.0)))
	_check(bool(lr.get("ok", false)) and float(lr.ms) < LOAD_BUDGET_MS, "load %.0f ms" % float(lr.get("ms", -1.0)))
	sm.delete_slot("perf streaming")
	print("PERF_RESULT streaming: %s" % ("OK" if ok else "OVER BUDGET"))
	var m2: Node = lr.get("map", map)
	m2.queue_free()
	await process_frame
	quit(0 if ok else 1)


## 8 game hours of population sim in one advance (sleep).
func _ff_ms(pop) -> float:
	var t0 := Time.get_ticks_usec()
	pop.tick(480.0)
	return (Time.get_ticks_usec() - t0) / 1000.0


## Move [player] from [from] along [d] for [dist] m at sprint speed, one
## step per physics frame.
func _sprint(player: Node3D, from: Vector3, d: Vector3, dist: float, phys) -> void:
	var moved := 0.0
	var speed := 6.5
	while moved < dist:
		moved += speed / 60.0
		var q := from + d * moved
		player.global_position = Vector3(q.x, 0.1, q.z)
		player.velocity = d * speed
		await physics_frame
	player.velocity = Vector3.ZERO


## A 250 m line through the town (along the main street, through its middle).
func _town_center(builder: Node) -> Array:
	var road: Dictionary = builder.layout.road("town_main")
	var pts: PackedVector2Array = road.points
	var a := pts[0]
	var b := pts[pts.size() - 1]
	var mid := (a + b) * 0.5
	var dir := (b - a).normalized()
	var p0 := _clampv(mid - dir * 125.0, builder.layout.size) + Vector2(0, 5)
	var p1 := _clampv(mid + dir * 125.0, builder.layout.size) + Vector2(0, 5)
	return [Vector3(p0.x, 0.1, p0.y), Vector3(p1.x, 0.1, p1.y)]


## A 250 m line through the most wooded row of chunks.
func _woods_line(builder: Node) -> Array:
	var l = builder.layout
	var best := 0
	var best_z := 0
	for cz in l.chunks_z():
		var n := 0
		for cx in l.chunks_x():
			if l.zone_at(l.chunk_rect(Vector2i(cx, cz)).get_center()) == 1:  # WOODS
				n += 1
		if n > best:
			best = n
			best_z = cz
	var y: float = (best_z + 0.5) * float(l.chunk_size)
	return [Vector3(40.0, 0.1, y), Vector3(290.0, 0.1, y)]


func _clampv(p: Vector2, size: Vector2) -> Vector2:
	return Vector2(clampf(p.x, 30.0, size.x - 30.0), clampf(p.y, 30.0, size.y - 30.0))
