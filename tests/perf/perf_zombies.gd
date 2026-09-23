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
## Modes: default "loud" (one 30 m noise wakes a share of them), --hostile
## (all chase the player), --noisy (Round 8: NOISY_EVENTS_PER_SECOND
## random sounds per second at random positions through SoundManager —
## propagation rays, moans and re-targeting under load), --horde-noise
## (HORDE_ZOMBIES clustered + HORDE_SMASHES_PER_SECOND window smashes right
## next to them: every zombie hears every smash, moan storm). Every mode
## also has a p99 frame budget.
## No static typing against gameplay classes (-s scripts compile before
## autoloads exist).

const ZOMBIES := 200
const FRAMES := 600
const BUDGET_MS := 8.0
const BUDGET_HOSTILE_MS := 10.0
const BUDGET_NOISY_MS := 10.0
const BUDGET_HORDE_MS := 10.0
## 99th-percentile physics step budgets.
const P99_MS := 16.0
const P99_HORDE_MS := 20.0
const HORDE_ZOMBIES := 60
const HORDE_SMASHES_PER_SECOND := 10.0
const HORDE_CENTER := Vector3(20, 0, 20)
const NOISY_EVENTS_PER_SECOND := 30.0
const NOISY_CATEGORIES: Array[StringName] = [&"footstep_walk", &"footstep_jog", &"footstep_sprint",
	&"door_open", &"door_close", &"door_bang", &"window_smash", &"melee_hit", &"shove",
	&"rummage", &"shout", &"eat"]


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
	var noisy := OS.get_cmdline_user_args().has("--noisy")
	var horde := OS.get_cmdline_user_args().has("--horde-noise")
	if hostile:
		mode = "hostile"
	elif noisy:
		mode = "noisy"
	elif horde:
		mode = "horde-noise"
		want = HORDE_ZOMBIES
	var cluster_rng := RandomNumberGenerator.new()
	cluster_rng.seed = 5
	for i in want:
		if horde:
			var a := cluster_rng.randf() * TAU
			var rr := sqrt(cluster_rng.randf()) * 5.0
			spawner.spawn_at(HORDE_CENTER + Vector3(cos(a) * rr, 0.0, sin(a) * rr))
			spawned += 1
			continue
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
	elif mode != "quiet" and not noisy and not horde:
		sound_manager().emit_sound(&"shout", player.global_position, null, {"radius": 30.0, "intensity": 1.0})
	var noise_rng := RandomNumberGenerator.new()
	noise_rng.seed = 99
	var noise_accum := 0.0
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
	if horde:
		var hs := NoiseSource.new()
		hs.rng = noise_rng
		hs.center = HORDE_CENTER
		hs.spread = 3.0
		hs.sm = sound_manager()
		hs.categories = [&"window_smash"] as Array[StringName]
		hs.per_frame = HORDE_SMASHES_PER_SECOND / 60.0
		probe.add_child(hs)
	if noisy:
		# The random sounds are emitted from INSIDE the measured bracket
		# (a node between the probe's start and end), so the dispatch cost
		# (rays, listener callbacks, moans) is counted.
		var src := NoiseSource.new()
		src.rng = noise_rng
		src.center = player.global_position
		src.sm = sound_manager()
		src.categories = NOISY_CATEGORIES
		src.per_frame = NOISY_EVENTS_PER_SECOND / 60.0
		probe.add_child(src)
	root.add_child(probe)
	sound_manager().clear()
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
	var p99: float = samples[mini(int(samples.size() * 0.99), samples.size() - 1)]
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
	print("PERF zombies=%d frames=%d avg_physics_ms=%.3f p90_ms=%.3f p99_ms=%.3f worst_ms=%.3f nav_ms=%.3f wall_s=%.1f" % [spawned, counted, avg, p90, p99, worst, total_nav, wall])
	print("PERF states: %s" % str(states))
	print("PERF nodes=%d objects=%d phys_active=%d phys_pairs=%d nav_agents=%d nav_regions=%d" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT), Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT)])
	print("PERF navmesh polys=%d bake_ms=%.0f" % [nav.navigation_mesh.get_polygon_count(), nav.bake_ms])
	var sst: Dictionary = sound_manager().stats
	print("PERF sound events=%d rays=%d deliveries=%d listeners=%d hashed=%d" % [sst.events, sst.rays, sst.deliveries,
		sound_manager().listener_count(), sound_manager().hashed_count()])
	var budget := BUDGET_HOSTILE_MS if hostile else (BUDGET_NOISY_MS if noisy else (BUDGET_HORDE_MS if horde else BUDGET_MS))
	var p99_budget := P99_HORDE_MS if horde else P99_MS
	var ok := avg < budget and p99 <= p99_budget and spawned >= want * 0.9
	print("PERF_RESULT %s: %s avg %.2f ms (budget %.1f ms), p99 %.2f ms (budget %.1f ms)" % [mode if mode != "" else "loud",
		"OK" if ok else "OVER BUDGET", avg, budget, p99, p99_budget])
	inst.queue_free()
	await process_frame
	quit(0 if ok else 1)


func sound_manager() -> Node:
	return root.get_node("SoundManager")


## --noisy: emits per_frame random sounds (fractional, accumulated) per
## physics step at random points within 30 m of [center].
class NoiseSource extends Node:
	var rng: RandomNumberGenerator
	var center: Vector3
	var sm: Node
	var categories: Array[StringName] = []
	var per_frame: float = 0.5
	var spread: float = 30.0
	var _accum: float = 0.0

	func _physics_process(_delta: float) -> void:
		_accum += per_frame
		while _accum >= 1.0:
			_accum -= 1.0
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * spread
			var p := center + Vector3(cos(a) * r, 0.0, sin(a) * r)
			p.y = 0.0
			sm.emit_sound(categories[rng.randi() % categories.size()], p, null)


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
