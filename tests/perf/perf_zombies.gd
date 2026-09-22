extends SceneTree
## Zombie AI performance probe (headless):
##
##   godot --headless --path . -s tests/perf/perf_zombies.gd
##
## Loads test_ground, waits for the navmesh, spawns ZOMBIES zombies on
## random navmesh points, lets the player stand in the middle (so plenty of
## them see/hear/chase), runs FRAMES physics frames and prints the average
## physics-step time (Performance.TIME_PHYSICS_PROCESS) plus navigation
## time. Budget: < BUDGET_MS average. Exit 1 when over budget.
## No static typing against gameplay classes (-s scripts compile before
## autoloads exist).

const ZOMBIES := 200
const FRAMES := 600
const BUDGET_MS := 8.0
const BUDGET_HOSTILE_MS := 10.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var scene: PackedScene = load("res://maps/test_ground.tscn")
	var inst := scene.instantiate()
	inst.get_node("Zombies").auto_spawn = false
	root.add_child(inst)
	var nav = inst.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	var spawner = inst.get_node("Zombies")
	spawner.min_player_distance = 4.0
	spawner.spawn_radius = 30.0
	spawner.seed = 42
	spawner.rng.seed = 42
	var spawned := 0
	var want := ZOMBIES
	if OS.get_environment("PERF_ZOMBIES") != "":
		want = int(OS.get_environment("PERF_ZOMBIES"))
	var mode := OS.get_environment("PERF_MODE")
	var hostile := OS.get_cmdline_user_args().has("--hostile")
	if hostile:
		mode = "hostile"
	for i in want:
		var p: Vector3 = spawner.pick_spawn_point()
		if p == Vector3.INF:
			continue
		spawner.spawn_at(p)
		spawned += 1
	# Let them settle, then wake a share of them with a loud noise.
	for i in 30:
		await physics_frame
	var player: Node3D = inst.get_node("Player")
	player.get_node("Health").invulnerable = true  # the horde must not end the run early
	if hostile:
		for z in spawner.zombies:
			z.get_node("AI").force_target(player)
	elif mode != "quiet":
		root.get_node("EventBus").sound_emitted.emit(player.global_position, 30.0, 1.0, &"test", null)
	# Warm up: let the spawn / bake catch-up burst finish before sampling.
	for i in 120:
		await physics_frame
	# Measure the scene-tree part of every physics step directly: a node
	# with the lowest physics priority stamps the start, one with the
	# highest stamps the end. (Performance.TIME_PHYSICS_PROCESS refreshes
	# only once per second and covers whole catch-up bursts.) The Jolt
	# step itself is tiny for kinematic bodies; move_and_slide runs inside
	# _physics_process and is therefore included.
	var probe := PhysicsProbe.new()
	root.add_child(probe)
	var t0 := Time.get_ticks_msec()
	var frame := 0
	while probe.samples.size() < FRAMES:
		await physics_frame
		frame += 1
		# Hostile: the player never leaves their sight (memory refreshed),
		# so all 200 keep chasing / attacking / holding for the whole run.
		if hostile and frame % 60 == 0:
			for z in spawner.zombies:
				if is_instance_valid(z) and not z.dead:
					z.get_node("AI").force_target(player)
	var wall := (Time.get_ticks_msec() - t0) / 1000.0
	var samples: Array[float] = probe.samples.duplicate()
	probe.queue_free()
	var counted := samples.size()
	var total_physics := 0.0
	var worst := 0.0
	for v in samples:
		total_physics += v
		worst = maxf(worst, v)
	var avg := total_physics / maxi(counted, 1)
	samples.sort()
	var median: float = samples[samples.size() / 2]
	var p90: float = samples[int(samples.size() * 0.9)]
	var over := 0
	for v in samples:
		if v > 16.0:
			over += 1
	var total_nav := Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var states := {}
	for z in spawner.zombies:
		if not is_instance_valid(z):
			continue
		var s: StringName = z.state()
		states[s] = states.get(s, 0) + 1
	print("PERF zombies=%d frames=%d avg_physics_ms=%.3f worst_ms=%.3f nav_ms=%.3f wall_s=%.1f" % [spawned, counted, avg, worst, total_nav, wall])
	print("PERF states: %s" % str(states))
	print("PERF nodes=%d objects=%d phys_active=%d phys_pairs=%d nav_agents=%d nav_regions=%d" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT), Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT)])
	print("PERF navmesh polys=%d bake_ms=%.0f" % [nav.navigation_mesh.get_polygon_count(), nav.bake_ms])
	var budget := BUDGET_HOSTILE_MS if hostile else BUDGET_MS
	var ok := avg < budget and spawned >= want * 0.9
	print("PERF_RESULT %s: %s avg %.2f ms (budget %.1f ms)" % [mode if mode != "" else "loud", "OK" if ok else "OVER BUDGET", avg, budget])
	inst.queue_free()
	await process_frame
	quit(0 if ok else 1)


## Brackets one physics step: the Start child (lowest physics priority)
## stamps the clock, the End child (highest) records the elapsed ms.
class PhysicsProbe extends Node:
	var samples: Array[float] = []
	var t0: int = 0

	func _ready() -> void:
		var a := ProbeStart.new()
		a.probe = self
		add_child(a)
		var b := ProbeEnd.new()
		b.probe = self
		add_child(b)


class ProbeStart extends Node:
	var probe: PhysicsProbe

	func _ready() -> void:
		process_physics_priority = -100000

	func _physics_process(_delta: float) -> void:
		probe.t0 = Time.get_ticks_usec()


class ProbeEnd extends Node:
	var probe: PhysicsProbe

	func _ready() -> void:
		process_physics_priority = 100000

	func _physics_process(_delta: float) -> void:
		probe.samples.append((Time.get_ticks_usec() - probe.t0) / 1000.0)
