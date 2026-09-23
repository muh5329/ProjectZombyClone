extends "res://tests/test_case.gd"
## Zombies in the real test_ground scene: navigation, senses, the AI state
## machine, attacks, doors, death, spawning and the HUD danger/death UI.
##
## Layout (see test_house_scene.gd): House A x -14..-4, z -10..-2, front
## door hinge (-11.45, -2) in the south wall; the "Wall" prop is an 8 m
## slab at z = 2 spanning x -10..-2. Player spawns at the origin.
## A fresh zombie faces -Z (movement.facing = 0).

var scene: Node
var player: Character
var ctrl: PlayerController
var house: HouseBlockout
var nav: NavBaker
var spawner: ZombieSpawner
var hud: CanvasLayer


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	house = scene.get_node("Buildings/HouseA")
	nav = scene.get_node("NavRegion")
	hud = scene.get_node("HUD")
	ctrl.scripted = true
	player.get_node("Interaction").scripted = true
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(5)


func teardown() -> void:
	await despawn(scene)


func _teleport(p: Vector3) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = p
	player.velocity = Vector3.ZERO
	await physics_frames(3)


func _spawn(p: Vector3, yaw: float = 0.0) -> Zombie:
	var z := spawner.spawn_at(p)
	z.snap_facing(yaw)
	await physics_frames(3)
	return z


func _door_at(world: Vector3) -> Door:
	for d in house.doors:
		if (d.global_position - world).length() < 0.2:
			return d
	return null


func _window_at(world: Vector3) -> HouseWindow:
	for w in house.windows:
		if (w.global_position - world).length() < 0.3:
			return w
	return null


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _wait_state(z: Zombie, id: StringName, max_frames: int) -> bool:
	return await wait_physics_until(func(): return z.state() == id, max_frames)


func test_nav_mesh_covers_ground_and_house_interior() -> void:
	check(nav.baked, "navmesh baked")
	check_gt(float(nav.navigation_mesh.get_polygon_count()), 10.0, "polygons")
	check_lt(nav.distance_to_mesh(Vector3(20, 0.2, 20)), 0.3, "open ground walkable")
	check_lt(nav.distance_to_mesh(Vector3(-9, 0.2, -4)), 0.3, "living room walkable")
	check_lt(nav.distance_to_mesh(Vector3(-11, 0.2, -2)), 0.3, "front doorway walkable (door leaf not baked)")
	var map := nav.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, Vector3(-11, 0.2, 2), Vector3(-12, 0.2, -8), true)
	check_gt(float(path.size()), 2.0, "path from outside into the bedroom exists")
	check_lt(path[-1].distance_to(Vector3(-12, 0.2, -8)), 0.6, "…and reaches it (through the doorways)")
	check_gt(nav.distance_to_mesh(Vector3(-14, 0.2, -6)), 0.25, "wall is not walkable")


func test_idle_then_wander_moves() -> void:
	var z := await _spawn(Vector3(20, 0, 20))
	check_eq(z.state(), &"idle", "starts idle")
	check(z.is_in_group(&"zombie"), "group")
	check_eq(z.collision_layer, 4, "layer 3 (zombies)")
	check_eq(z.collision_mask, 455, "mask world+player+zombies+doors+panes+barricades")
	var p0 := z.global_position
	var wandering := await _wait_state(z, &"wander", 60 * 9)
	check(wandering, "wanders within idle_time_max (got %s)" % z.state())
	await physics_frames(120)
	check_gt(_flat_dist(z.global_position, p0), 0.5, "moved while wandering")
	check_lt(z.speed(), z.profile.shamble_speed + 0.05, "shamble speed")
	check_lt(_flat_dist(z.global_position, z.home_position), z.profile.wander_radius + 1.0, "stays near home")


func test_player_in_vision_cone_is_chased_within_1s() -> void:
	await _teleport(Vector3(10, 0.1, 2))
	var spotted := []
	var cb := func(zb, t): spotted.append([zb, t])
	EventBus.zombie_spotted_target.connect(cb)
	var z := await _spawn(Vector3(10, 0, 10))  # faces -Z, player 8 m ahead
	var chased := await _wait_state(z, &"chase", 60)
	EventBus.zombie_spotted_target.disconnect(cb)
	check(chased, "chase within 1 s (state %s, reason %s)" % [z.state(), z.senses.last_reason])
	check_eq(z.target, player, "target is the player")
	check_eq(spotted.size(), 1, "zombie_spotted_target once")
	check(z.visual.head_material().albedo_color.r > 0.7, "red eyes while hostile")
	await frames(1)
	check_eq(hud.chasing_count(), 1, "HUD counts one chaser")
	check_eq(hud.danger_label.text, "!  1 chasing", "danger label")
	await physics_frames(60)
	check_lt(z.speed(), z.profile.chase_speed + 0.05, "chase speed capped")
	check_gt(z.speed(), z.profile.shamble_speed, "faster than shambling")
	check_lt(_flat_dist(z.global_position, player.global_position), 7.5, "closing in")


func test_behind_a_wall_is_not_spotted() -> void:
	# Wall prop at z = 2 between the zombie (z 5) and the player (z -1).
	await _teleport(Vector3(-6, 0.1, -1))
	var z := await _spawn(Vector3(-6, 0, 5))
	await physics_frames(120)
	check(z.state() != &"chase", "not chasing through the wall (state %s)" % z.state())
	check_eq(z.senses.last_reason, &"occluded", "vision blocked by the wall")
	# Same side of the wall, inside the cone → seen.
	await _teleport(Vector3(-4, 0.1, 3))
	check(await _wait_state(z, &"chase", 60), "seen once in the open")


func test_sneaking_beyond_half_range_is_not_spotted() -> void:
	await _teleport(Vector3(10, 0.1, 0))  # 10 m ahead: inside 14, outside 7
	ctrl.scripted_mode = MovementComponent.Mode.SNEAK
	await physics_frames(3)
	check_eq(player.effective_mode, MovementComponent.Mode.SNEAK, "sneaking")
	var z := await _spawn(Vector3(10, 0, 10))
	await physics_frames(120)
	check(z.state() != &"chase", "sneaking at 10 m not seen (state %s)" % z.state())
	check_eq(z.senses.last_reason, &"out_of_range", "out of the halved range")
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	await physics_frames(3)
	check(await _wait_state(z, &"chase", 60), "standing normally at 10 m is seen")


func test_window_smash_sound_makes_zombie_investigate() -> void:
	await _teleport(Vector3(30, 0.1, 30))  # far away, out of sight
	var z := await _spawn(Vector3(-20, 0, -14), PI)  # NW of the house, facing +Z
	var win := _window_at(Vector3(-12, 0, -10))
	check(win != null, "bedroom north window")
	check_lt(_flat_dist(z.global_position, win.global_position), 18.0, "within smash radius")
	win.smash()
	var investigating := await _wait_state(z, &"investigate", 10)
	check(investigating, "investigates the smash (state %s)" % z.state())
	check(z.visual.head_material().albedo_color.g > 0.6, "yellow eyes while investigating")
	check_lt((z.ai.investigate_position - win.global_position).length(), 0.5, "goes to the window (sound 0.3 m outside it)")
	var arrived := await wait_physics_until(func(): return _flat_dist(z.global_position, win.global_position) < 2.0, 60 * 20)
	check(arrived, "reached near the window (dist %.1f, state %s)" % [_flat_dist(z.global_position, win.global_position), z.state()])
	var searching := await _wait_state(z, &"search", 60 * 4)
	check(searching, "searches after arriving")


func test_attack_damages_player_after_windup() -> void:
	await _teleport(Vector3(5, 0.1, 3.5))
	var hp0: float = player.health.health
	var attacks := []
	var cb := func(zb, t, hit): attacks.append([zb, t, hit])
	EventBus.zombie_attacked.connect(cb)
	var z := await _spawn(Vector3(5, 0, 4.7))  # 1.2 m: proximity
	check(await _wait_state(z, &"chase", 30), "noticed by proximity")
	check(await _wait_state(z, &"attack", 60 * 3), "in attack range")
	var t_attack := Engine.get_physics_frames()
	var hit := await wait_physics_until(func(): return player.health.health < hp0, 90)
	EventBus.zombie_attacked.disconnect(cb)
	check(hit, "player took damage")
	var windup_frames := Engine.get_physics_frames() - t_attack
	check_gt(float(windup_frames), 20.0, "hit came after the 0.5 s windup (%d frames)" % windup_frames)
	check_near(player.health.health, hp0 - z.profile.attack_damage, 0.05, "damage = profile.attack_damage")
	check_eq(attacks.size(), 1, "one zombie_attacked event")
	check(attacks[0][2] == true, "…with hit = true")
	await frames(1)
	check_gt(hud.flash_strength(), 0.05, "damage flash on screen")
	check_near(hud.health_bar.value, 88.0, 0.5, "health bar updated")
	# Second hit only after the cooldown.
	await physics_frames(40)
	# (Round 4: the wound bleeds a little in the meantime.)
	check_gt(player.health.health, hp0 - z.profile.attack_damage - 1.0, "no second hit during cooldown")
	var again := await wait_physics_until(func(): return player.health.health < hp0 - z.profile.attack_damage - 1.0, 150)
	check(again, "second hit after cooldown + windup")


func test_losing_the_target_leads_to_search_then_wander() -> void:
	await _teleport(Vector3(0, 0.1, 3))
	var z := await _spawn(Vector3(0, 0, 8))
	check(await _wait_state(z, &"chase", 60), "chasing")
	var lost := []
	var cb := func(zb): lost.append(zb)
	EventBus.zombie_lost_target.connect(cb)
	var states := []
	var cb2 := func(zb, _f, to): if zb == z: states.append(to)
	EventBus.zombie_state_changed.connect(cb2)
	# The player vanishes far away: the zombie heads for the last known spot.
	await _teleport(Vector3(60, 0.1, 60))
	var t0 := Engine.get_physics_frames()
	await physics_frames(60 * 4)
	check_eq(z.state(), &"chase", "still chasing on memory after 4 s")
	var gave_up := await wait_physics_until(func(): return z.state() == &"search", 60 * 7)
	EventBus.zombie_lost_target.disconnect(cb)
	var elapsed := (Engine.get_physics_frames() - t0) / 60.0
	check(gave_up, "search after memory expires (state %s)" % z.state())
	check_gt(elapsed, 7.5, "memory lasted ~8 s (%.1f)" % elapsed)
	check_eq(lost.size(), 1, "zombie_lost_target once")
	check(z.target == null, "target forgotten")
	check(states.has(&"lost_target"), "went through lost_target")
	var wandering := await _wait_state(z, &"wander", 60 * 8)
	EventBus.zombie_state_changed.disconnect(cb2)
	check(wandering, "wanders after searching (state %s)" % z.state())
	await frames(1)
	check_eq(hud.chasing_count(), 0, "HUD no longer shows a chaser")
	check_eq(hud.danger_label.text, "", "danger label cleared")


func test_zombie_breaks_closed_door_and_enters_house() -> void:
	await _teleport(Vector3(-9, 0.1, -4))  # living room, front door closed
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(door != null and door.state == &"closed", "front door closed")
	door.health = 16.0  # two bangs (keeps the test short; 300 hp = ~75 s alone)
	var z := await _spawn(Vector3(-11, 0, 1.5), PI)  # outside, 3.5 m south of the door
	var states := []
	var cb := func(zb, _f, to): if zb == z: states.append(to)
	EventBus.zombie_state_changed.connect(cb)
	# A sprint footstep inside (14 m, ×0.5 through the south wall = 7 m;
	# the zombie is ~6 m away): heard, so the zombie investigates and finds
	# the door in its path.
	SoundManager.emit_sound(&"footstep_sprint", player.global_position, player)
	check(await _wait_state(z, &"investigate", 10), "heard the footstep")
	var banging := await _wait_state(z, &"attack_door", 60 * 8)
	check(banging, "attacks the door in its path (state %s, pos %s)" % [z.state(), z.global_position])
	var damaged := await wait_physics_until(func(): return door.health < 16.0, 90)
	check(damaged, "door health dropped")
	var broken := await wait_physics_until(func(): return door.state == &"broken", 60 * 4)
	check(broken, "door broken (health %.0f)" % door.health)
	check(door.is_open(), "broken door is passable")
	var inside := await wait_physics_until(func(): return house.contains_point(z.global_position), 60 * 10)
	EventBus.zombie_state_changed.disconnect(cb)
	check(inside, "zombie entered the house (state %s, pos %s)" % [z.state(), z.global_position])
	check(states.has(&"attack_door"), "state log has attack_door")
	# Now inside with the player: proximity/vision → chase.
	check(await _wait_state(z, &"chase", 60 * 6), "chases the player inside")


func test_zombie_death_leaves_interactable_corpse() -> void:
	await _teleport(Vector3(20, 0.1, 5))
	var z := await _spawn(Vector3(20, 0, 3.2))
	var died := []
	var cb := func(zb, k): died.append([zb, k])
	EventBus.zombie_died.connect(cb)
	var r := z.take_damage(999.0, player)
	EventBus.zombie_died.disconnect(cb)
	check(r.ok and r.dead, "killed")
	check(z.dead and z.state() == &"dead", "dead state")
	check(not z.is_in_group(&"zombie"), "left the zombie group")
	check_eq(died.size(), 1, "zombie_died once")
	check_eq(died[0][1], player, "killer passed")
	var corpse := z.corpse
	check(corpse != null and corpse is ZombieCorpse, "corpse left behind")
	check(corpse.is_in_group(&"corpse"), "corpse group")
	check_eq(corpse.collision_layer, 8, "corpse on layer 4 only")
	check_eq(corpse.collision_mask, 0, "collides with nothing")
	var vis := corpse.get_node_or_null("Visual") as ZombieVisual
	check(vis != null, "visual re-parented to the corpse")
	check_eq(vis.clip(), &"z_death", "death fall playing (R8.5)")
	check(vis.head_material().albedo_color.r < 0.3, "dark eyes when dead")
	await physics_frames(2)
	check(not is_instance_valid(z), "zombie node freed")
	var it := Interactable.of(corpse)
	check(it != null, "corpse interactable")
	var acts := it.get_actions(player)
	# Round 5: the corpse is a LootContainer — searching works now.
	check(acts.size() == 1 and acts[0].label == "Search corpse" and acts[0].enabled, "search corpse enabled (R5)")
	# The player targets it and can walk over it.
	var interaction: PlayerInteraction = player.get_node("Interaction")
	ctrl.scripted_direction = Vector3.FORWARD
	ctrl.scripted_mode = MovementComponent.Mode.WALK
	await physics_frames(20)
	check_eq(interaction.current_target, it, "corpse targetable")
	await physics_frames(100)
	ctrl.scripted_direction = Vector3.ZERO
	check_lt(player.global_position.z, 2.8, "walked over the corpse")
	check(not corpse.take_damage(10.0).ok, "no damage to a corpse")


func test_zero_damage_is_a_no_op() -> void:
	var z := await _spawn(Vector3(20, 0, -20))
	var r := z.take_damage(0.0)
	check(not r.ok and is_equal_approx(r.health, 60.0), "0 damage refused like HealthComponent")
	r = z.take_damage(-5.0)
	check(not r.ok, "negative damage refused")
	check_eq(z.health(), 60.0, "health untouched")


func test_head_hit_multiplier_and_stun() -> void:
	await _teleport(Vector3(40, 0.1, 40))
	var z := await _spawn(Vector3(20, 0, -20))
	var r := z.take_damage(10.0, null, {"region": &"head"})
	check_near(r.health, 60.0 - 30.0, 0.01, "head hit ×3")
	check_eq(z.state(), &"stunned", "heavy hit stuns")
	await physics_frames(60)
	check(z.state() != &"stunned", "stun over after 0.8 s")
	# A light hit from something makes a target-less zombie turn and look.
	var rock := Node3D.new()
	rock.position = z.global_position + Vector3(6, 0, 0)
	scene.add_child(rock)
	r = z.take_damage(5.0, rock)
	check_near(r.health, 25.0, 0.01, "light hit")
	check(z.state() != &"stunned", "light hit does not stun")
	check_eq(z.state(), &"investigate", "investigates the attacker")
	check_lt((z.ai.investigate_position - rock.global_position).length(), 0.01, "…at its position")
	check(z.facing_vector().dot(Vector3.RIGHT) > 0.99, "turned toward it")
	rock.queue_free()


func test_spawner_places_10_zombies_on_navmesh_outside_buildings() -> void:
	var list := spawner.spawn_initial()
	check_eq(list.size(), 10, "ten zombies")
	check_eq(spawner.zombies.size(), 10, "tracked")
	await physics_frames(5)
	var positions := []
	for z in list:
		var p: Vector3 = z.global_position
		positions.append(p)
		check_lt(_flat_dist(nav.closest_point(p), p), 0.3, "on the navmesh: %s" % p)
		check(Building.locate(tree, p).building == null, "not inside a building: %s" % p)
		check_gt(_flat_dist(p, player.global_position), spawner.min_player_distance - 0.01, ">= 15 m from the player: %s" % p)
		check(z.ai_seed != 0, "seeded AI")
		check_lt(p.y, 0.3, "on the ground")
	# Determinism: a second spawner with the same seed picks the same spots
	# (the first batch is freed first, or the newcomers would be pushed
	# out of the occupied spots).
	for z in list:
		z.free()
	spawner.zombies.clear()
	var again := ZombieSpawner.new()
	again.auto_spawn = false
	again.seed = spawner.seed
	again.count = 10
	scene.add_child(again)
	var list2 := again.spawn_initial()
	await physics_frames(2)
	check_eq(list2.size(), 10, "second spawner: ten")
	for i in list2.size():
		check_lt(_flat_dist(list2[i].global_position, positions[i]), 0.01, "same seed → same position %d" % i)
	again.queue_free()


func test_player_death_shows_overlay_and_ignores_input() -> void:
	var r := player.take_damage(999.0, null)
	check(r.ok and r.dead, "dead")
	check(player.is_dead() and player.is_busy, "busy (input ignored)")
	await frames(2)
	check(hud.death_overlay.visible, "You died overlay")
	check_eq(hud.health_label.text, "♥ Dead", "health label")
	check_near(hud.health_bar.value, 0.0, 0.01, "empty bar")
	var p0 := player.global_position
	ctrl.scripted_direction = Vector3.FORWARD
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	await physics_frames(60)
	check_lt(_flat_dist(player.global_position, p0), 0.01, "does not move when dead")
	ctrl.scripted_direction = Vector3.ZERO
	# Zombies ignore dead players even face to face inside proximity range.
	var z := await _spawn(player.global_position + Vector3(0, 0, 1.2), 0.0)  # 1.2 m south, facing north (-Z)
	check_lt(_flat_dist(z.global_position, player.global_position), z.profile.proximity_range, "inside proximity range")
	check(z.facing_vector().dot((player.global_position - z.global_position).normalized()) > 0.9, "facing the body")
	await physics_frames(60)
	check(z.state() != &"chase" and z.target == null, "dead player is not a target (state %s, reason %s)" % [z.state(), z.senses.last_reason])
	check(hud.restart_action_name() == &"restart", "restart bound to an action")


func test_no_bite_through_a_wall() -> void:
	# Player inside the living room right behind the south wall; zombie
	# outside 0.8 m away: within attack range, but the wall is in between.
	await _teleport(Vector3(-8, 0.1, -2.35))
	var z := await _spawn(Vector3(-8, 0, -1.55))
	var hp0: float = player.health.health
	var bites := []
	var cb := func(_zb, t, hit): if t == player: bites.append(hit)
	EventBus.zombie_attacked.connect(cb)
	check_lt(_flat_dist(z.global_position, player.global_position), z.profile.attack_range, "inside attack range")
	# It knows the player is there (chest-to-chest is blocked, so no sight;
	# force the memory as if it had just seen them through a window).
	z.ai.force_target(player)
	await physics_frames(60 * 4)
	EventBus.zombie_attacked.disconnect(cb)
	check(not z.ai.has_attack_line(), "no attack line through the wall")
	check(z.state() != &"attack", "never entered attack through the wall (state %s)" % z.state())
	check(bites.is_empty(), "no swings at the player (banging the door instead is fine)")
	check_near(player.health.health, hp0, 0.001, "no damage through the wall")


func test_vision_through_open_window_but_not_closed() -> void:
	# Player in the bedroom in front of its north window; zombie outside
	# north of it, facing south. Windows are see-through only when open.
	await _teleport(Vector3(-12, 0.1, -8.5))
	var win := _window_at(Vector3(-12, 0, -10))
	check(win != null and win.state == &"closed", "bedroom north window closed")
	var z := await _spawn(Vector3(-12, 0, -14), PI)  # 4 m north of the wall, facing +Z (south)
	await physics_frames(60)
	check(z.state() != &"chase", "closed window blocks vision (state %s)" % z.state())
	check_eq(z.senses.last_reason, &"occluded", "occluded by the pane")
	win.open_window()
	await physics_frames(5)
	check(await _wait_state(z, &"chase", 60), "seen through the open window (reason %s)" % z.senses.last_reason)
	check_eq(z.senses.last_reason, &"seen", "clear line through the opening")


func test_broken_door_prompt_reachable() -> void:
	var door := _door_at(Vector3(-11.45, 0, -2))
	door.take_damage(999.0)
	check(door.is_broken(), "broken")
	await _teleport(Vector3(-11, 0.1, -1.0))
	await physics_frames(5)
	var interaction: PlayerInteraction = player.get_node("Interaction")
	check_eq(interaction.current_target, Interactable.of(door), "broken door still targetable")
	var act: Dictionary = interaction.current_actions[0]
	check(not act.enabled and act.reason == "Door is broken", "Close door (Door is broken)")
	await frames(1)
	check(String(hud.prompt_label.text).contains("Door is broken"), "prompt shows the reason")
	# …and it does not block: walk straight through the doorway.
	ctrl.scripted_direction = Vector3.FORWARD
	ctrl.scripted_mode = MovementComponent.Mode.WALK
	await physics_frames(90)
	ctrl.scripted_direction = Vector3.ZERO
	check(house.contains_point(player.global_position), "walked through the broken door")


func test_stale_chase_count_is_pruned_when_zombie_freed() -> void:
	await _teleport(Vector3(10, 0.1, 2))
	var z := await _spawn(Vector3(10, 0, 8))
	check(await _wait_state(z, &"chase", 60), "chasing")
	await frames(1)
	check_eq(hud.chasing_count(), 1, "one chaser")
	z.free()  # e.g. a chunk unload: no death event
	await frames(2)
	check_eq(hud.chasing_count(), 0, "count pruned without a zombie_died event")
	check_eq(hud.danger_label.text, "", "label cleared")


func test_same_seed_gives_same_state_sequence() -> void:
	await _teleport(Vector3(60, 0.1, 60))  # nobody around
	var a := ZombieSpawner.new()
	a.auto_spawn = false
	a.seed = 99
	a.position = Vector3(-30, 0, 20)
	scene.add_child(a)
	var b := ZombieSpawner.new()
	b.auto_spawn = false
	b.seed = 99
	b.position = Vector3(20, 0, -30)
	scene.add_child(b)
	var za: Array[Zombie] = []
	var zb: Array[Zombie] = []
	for i in 3:
		var off := Vector3(i * 2.0, 0, 0)
		za.append(a.spawn_at(a.global_position + off))
		zb.append(b.spawn_at(b.global_position + off))
	await physics_frames(60 * 9)
	for i in 3:
		check_eq(za[i].ai_seed, zb[i].ai_seed, "zombie %d gets the same seed" % i)
		check_eq(za[i].ai.machine.history, zb[i].ai.machine.history, "zombie %d: same state sequence (%s vs %s)" % [i, za[i].ai.machine.history, zb[i].ai.machine.history])
		check_gt(float(za[i].ai.machine.history.size()), 1.5, "zombie %d moved through states" % i)
	check(za[0].ai.machine.history != za[1].ai.machine.history or za[0].ai_seed != za[1].ai_seed, "different seeds differ")
	a.queue_free()
	b.queue_free()
