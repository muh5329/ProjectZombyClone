extends "res://tests/test_case.gd"
## Round 9 in the real test_ground scene: nailing planks through the
## player's Interaction (hammer + plank + nails, busy + hammering noise,
## interruption, carpentry XP), what planks block (climbing, doors, sight,
## sound), zombies breaking planks one by one and climbing in (attacker
## slots, detour to the weakest entry), prying planks off, pushing
## furniture in front of a door and disassembling furniture.
##
## Layout (see test_house_scene.gd): House A x -14..-4, z -10..-2. South
## (front) wall z = -2: front door hinge (-11.45, -2), living-room window
## centred (-7, -2) (local +Z = outward = south). Back door (-5.75, -10).

var scene: Node
var player: Player
var ctrl: PlayerController
var interaction: PlayerInteraction
var house: HouseBlockout
var nav: NavBaker
var spawner: ZombieSpawner
var hud: CanvasLayer
var fast: ZombieProfile


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	interaction = player.get_node("Interaction")
	house = scene.get_node("Buildings/HouseA")
	nav = scene.get_node("NavRegion")
	hud = scene.get_node("HUD")
	ctrl.scripted = true
	interaction.scripted = true
	if not nav.baked:
		await nav.navigation_ready
	# Quicker bangs so plank-breaking tests stay short (same rules).
	fast = (load("res://data/zombies/zombie_basic.tres") as ZombieProfile).duplicate()
	fast.attack_cooldown = 0.5
	await physics_frames(5)


func teardown() -> void:
	await despawn(scene)


func _teleport(p: Vector3, yaw: float = 0.0) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.movement.facing = yaw
	if player.visual:
		player.visual.rotation.y = yaw
	await physics_frames(8)


func _give(items: Dictionary) -> void:
	for id in items:
		player.inventory.add_id(StringName(id), int(items[id]))


func _front_window() -> HouseWindow:
	for w in house.windows:
		if (w.global_position - Vector3(-7, 0, -2)).length() < 0.3:
			return w
	return null


func _door_at(world: Vector3) -> Door:
	for d in house.doors:
		if (d.global_position - world).length() < 0.2:
			return d
	return null


func _spawn(p: Vector3, yaw: float = 0.0, prof: ZombieProfile = null) -> Zombie:
	var z := spawner.spawn_at(p, prof)
	z.snap_facing(yaw)
	await physics_frames(3)
	return z


func _action(id: StringName) -> Dictionary:
	for a in interaction.current_actions:
		if a.id == id:
			return a
	return {}


## Nail planks directly (setup for the zombie tests).
func _board(f: Node3D, n: int, hp: float, side: float) -> BarricadeComponent:
	var b := BarricadeComponent.ensure(f)
	for i in n:
		b.add_plank(hp, side)
	return b


func _wait_state(z: Zombie, id: StringName, max_frames: int) -> bool:
	return await wait_physics_until(func(): return is_instance_valid(z) and z.state() == id, max_frames)


# --- Player nailing -----------------------------------------------------------------

func test_barricade_window_from_outside_consumes_materials_and_blocks_climbing() -> void:
	var win := _front_window()
	check(win != null, "front window")
	_give({&"hammer": 1, &"plank": 2, &"nails": 5})
	await _teleport(Vector3(-7, 0.1, -1.1), 0.0)  # outside, facing north (-Z) at the window
	check_eq(interaction.current_target, Interactable.of(win), "window targeted")
	var a := _action(&"barricade")
	check(not a.is_empty() and a.enabled, "Barricade offered (%s)" % str(a))
	check_eq(a.label, "Barricade (0/4)", "count in the label")
	await frames(2)
	check(String(hud.prompt_label.text).contains("Barricade (0/4)"), "HUD prompt shows the count (%s)" % hud.prompt_label.text)
	var sounds := []
	var cb := func(_p, radius, _i, cat, src): if cat == &"hammering": sounds.append([radius, src])
	EventBus.sound_emitted.connect(cb)
	var r := interaction.perform_action(&"barricade")
	check(r.ok and r.get("busy", false), "busy action started (%s)" % str(r))
	check(player.is_busy and player.busy_context == &"barricade", "busy hammering")
	check_eq(player.equipment.primary().id(), &"hammer", "hammer in hand")
	await physics_frames(10)
	check_eq(player.get_node("Visual/Model").current, &"hammer", "hammering animation")
	check_eq(HUD_busy_label(), "Hammering", "HUD state label")
	check_gt(hud.action_progress(), 0.0, "action bar running")
	check_eq(player.inventory.count_of(&"plank"), 2, "nothing consumed mid-way")
	await frames(1)
	check_eq(String(hud.notice_label.text), "Hammering is loud!", "first-time loud notice")
	var done := await wait_physics_until(func(): return not player.is_busy, 60 * 4)
	EventBus.sound_emitted.disconnect(cb)
	check(done, "finished within 4 s")
	check_eq(win.barricade_planks(), 1, "one plank nailed")
	check_eq(player.inventory.count_of(&"plank"), 1, "1 plank consumed")
	check_eq(player.inventory.count_of(&"nails"), 3, "2 nails consumed")
	check_gt(float(sounds.size()), 1.0, "hammering repeats while working (%d)" % sounds.size())
	check_eq(sounds[0][0], 18.0, "18 m hammering")
	var b := BarricadeComponent.of(win)
	check_eq(b.side, 1.0, "planks on the actor's (outside) side")
	check_eq(b.board_count(), 1, "one board drawn")
	var board := win.get_node("Visual").get_node_or_null("Plank0") as Node3D
	check(board != null and board.visible, "board under the window visual")
	check_gt(win.to_local(board.global_position).z, 0.1, "on the outside face")
	check_near(SkillComponent.of(player).get_xp(&"carpentry"), 10.0, 0.01, "+10 carpentry XP")
	await physics_frames(3)
	check_eq(_action(&"barricade").label, "Barricade (1/4)", "label counts up")
	r = interaction.perform_action(&"barricade")
	check(r.ok, "second plank")
	await wait_physics_until(func(): return not player.is_busy, 60 * 4)
	check_eq(win.barricade_planks(), 2, "two planks")
	await physics_frames(3)
	var nope := _action(&"barricade")
	check(not nope.enabled and nope.reason == "Need planks", "out of planks (%s)" % str(nope))
	win.smash(player)
	await physics_frames(3)
	var climb := _action(&"climb")
	check(not climb.enabled and climb.reason == "Barricaded", "climb refused Barricaded")
	var refused := interaction.perform_action(&"climb")
	check(not refused.ok and refused.reason == "Barricaded", "perform refused")
	check(not house.contains_point(player.global_position), "still outside")


func HUD_busy_label() -> String:
	return hud.busy_label_for(player)


func test_missing_hammer_is_refused_with_reason() -> void:
	var win := _front_window()
	_give({&"plank": 1, &"nails": 2})
	await _teleport(Vector3(-7, 0.1, -3.0), PI)  # inside, facing south at the window
	check_eq(interaction.current_target, Interactable.of(win), "window targeted from inside")
	var a := _action(&"barricade")
	check(not a.enabled and a.reason == "Need a hammer", "disabled: Need a hammer")
	await frames(2)
	check(String(hud.prompt_label.text).contains("Barricade (0/4) (Need a hammer)"), "prompt shows the requirement")
	var r := interaction.perform_action(&"barricade")
	check(not r.ok and r.reason == "Need a hammer", "refused")
	await frames(1)
	check_eq(String(hud.notice_label.text), "Need a hammer", "HUD notice")
	check(not player.is_busy, "not busy")
	check_eq(player.inventory.count_of(&"plank"), 1, "nothing consumed")
	player.inventory.remove_id(&"nails", 1)
	_give({&"hammer": 1})
	await physics_frames(3)
	check_eq(_action(&"barricade").reason, "Need 2 nails", "then nails")


func test_zombie_hit_interrupts_hammering_and_consumes_nothing() -> void:
	var win := _front_window()
	_give({&"hammer": 1, &"plank": 1, &"nails": 2})
	await _teleport(Vector3(-7, 0.1, -1.1), 0.0)
	var r := interaction.perform_action(&"barricade")
	check(r.ok, "started")
	var finished := []
	var cb := func(actor, action, completed): if actor == player: finished.append([action, completed])
	EventBus.timed_action_finished.connect(cb)
	var z := await _spawn(Vector3(-7, 0, -0.3), PI)  # right behind the player
	z.ai.force_target(player)
	var hurt := await wait_physics_until(func(): return player.health.health < player.health.max_health, 60 * 3)
	EventBus.timed_action_finished.disconnect(cb)
	check(hurt, "the zombie hit the player")
	check(not player.is_busy or player.busy_context != &"barricade", "hammering interrupted")
	check_eq(finished, [[&"barricade", false]], "timed action finished incomplete")
	check_eq(win.barricade_planks(), 0, "no plank")
	check_eq(player.inventory.count_of(&"plank"), 1, "plank kept")
	check_eq(player.inventory.count_of(&"nails"), 2, "nails kept")
	check_eq(SkillComponent.of(player).get_xp(&"carpentry"), 0.0, "no XP")
	z.die()


func test_hammering_is_heard_18m_and_a_zombie_15m_away_investigates() -> void:
	_give({&"hammer": 1, &"plank": 1, &"nails": 2})
	await _teleport(Vector3(-7, 0.1, -1.1), 0.0)
	var z := await _spawn(Vector3(-7, 0, 13.9), PI)  # 15 m south, facing away
	await physics_frames(20)
	check_eq(z.state(), &"idle", "idle, cannot see the player")
	check(interaction.perform_action(&"barricade").ok, "hammering")
	var went := await _wait_state(z, &"investigate", 30)
	check(went, "investigates the hammering (state %s)" % z.state())
	check_lt(z.ai.investigate_position.distance_to(player.global_position), 1.5, "toward the noise")
	z.die()


# --- Blocking ---------------------------------------------------------------------

func test_barricaded_door_cannot_be_opened_from_either_side() -> void:
	var door := _door_at(Vector3(-11.45, 0, -2))
	check(door != null and door.state == &"closed", "front door closed")
	_give({&"hammer": 1, &"plank": 1, &"nails": 2})
	await _teleport(Vector3(-11, 0.1, -3.0), PI)  # inside, facing the door
	check_eq(interaction.current_target, Interactable.of(door), "door targeted")
	check(interaction.perform_action(&"barricade").ok, "nailing the door")
	await wait_physics_until(func(): return not player.is_busy, 60 * 4)
	check_eq(door.barricade_planks(), 1, "door planked")
	await physics_frames(3)
	var open := _action(&"open")
	check(not open.enabled and open.reason == "Barricaded", "Open disabled inside")
	check(not interaction.perform_action(&"open").ok, "refused inside")
	check_eq(door.state, &"closed", "still closed")
	await _teleport(Vector3(-11, 0.1, -1.0), 0.0)  # outside
	check_eq(interaction.current_target, Interactable.of(door), "door targeted from outside")
	check_eq(_action(&"open").reason, "Barricaded", "Open disabled outside")
	check_eq(door.open_door(player).reason, "Barricaded", "open_door refused")
	var add := _action(&"barricade")
	check(not add.enabled and add.reason == "Barricaded on the other side", "cannot nail from the other side")
	check_eq(door.breakable_target(), BarricadeComponent.of(door), "zombies hit the planks first")


func test_two_planks_block_zombie_sight_through_an_open_window() -> void:
	var win := _front_window()
	win.open_window()
	await _teleport(Vector3(-7, 0.1, -3.2), PI)
	var z := await _spawn(Vector3(-7, 0, 1.0), 0.0)  # outside (north of the Wall prop), facing the window
	var q := PhysicsRayQueryParameters3D.create(z.eye_position(), player.global_position + Vector3.UP * 1.6, (1 << 0) | (1 << 6) | (1 << 7))
	var hit := z.get_world_3d().direct_space_state.intersect_ray(q)
	check(z.senses.can_see_target(player), "seen through the open window (%s, hit %s at %s)" % [z.senses.last_reason, hit.get("collider"), hit.get("position")])
	var b := _board(win, 1, 60.0, -1.0)
	await physics_frames(2)
	check(z.senses.can_see_target(player), "one plank: still seen")
	b.add_plank(60.0, -1.0)
	await physics_frames(2)
	check(not z.senses.can_see_target(player), "two planks block sight")
	b.remove_plank()
	await physics_frames(2)
	check(z.senses.can_see_target(player), "back to one plank: seen again")
	z.die()


func test_planks_muffle_sound_through_the_window() -> void:
	var win := _front_window()
	win.smash(null)
	await physics_frames(2)
	var src := Vector3(-7, 0, -3.5)
	var ear := Vector3(-7, 1.5, 6.0)
	var ev := SoundManager.emit_sound(&"shout", src, null)
	var s0 := float(SoundManager.evaluate(ev, ear).slack)
	_board(win, 2, 60.0, 1.0)
	await physics_frames(2)
	var ev2 := SoundManager.emit_sound(&"shout", src, null)
	var s2 := float(SoundManager.evaluate(ev2, ear).slack)
	check_lt(s2, s0 - 2.0, "two planks muffle (%.1f → %.1f)" % [s0, s2])
	check_near(win.sound_barricade_factor(), 0.64, 0.001, "×0.8 per plank")


# --- Zombies vs barricades ----------------------------------------------------------

func test_zombie_breaks_planks_one_by_one_then_climbs_in() -> void:
	var win := _front_window()
	win.smash(null)
	if win.has_glass():
		win.remove_glass()
	# Every other entry is boarded up heavily; the front window (2 weak
	# planks) is the best way in — the zombie reaches the barricaded front
	# door first and detours to it.
	for d in house.doors:
		if d.outward.length_squared() > 0.5:
			_board(d, 4, 60.0, 1.0 if d.to_local(Vector3(-7, 0, 5)).z >= 0.0 else -1.0)
	for w in house.windows:
		if w != win:
			_board(w, 4, 60.0, w.side_of(w.global_position + w.outward))
	_board(win, 2, 16.0, 1.0)
	await _teleport(Vector3(-8, 0.1, -4.5), 0.0)
	var broken := []
	var counts := []
	var cb := func(f, src): if f == win: broken.append(src); counts.append(win.barricade_planks())
	EventBus.barricade_plank_broken.connect(cb)
	var z := await _spawn(Vector3(-9.5, 0, 1.5), PI, fast)
	z.ai.force_target(player)
	var at_planks := await wait_physics_until(func(): return is_instance_valid(z) and z.state() == &"attack_door" \
		and z.ai.blocking_obstacle == BarricadeComponent.of(win), 60 * 15)
	check(at_planks, "bangs on the window planks (state %s, obstacle %s, pos %s)" % [z.state(), z.ai.blocking_obstacle, z.global_position])
	var climbed := await _wait_state(z, &"climb_window", 60 * 12)
	check(climbed, "climbs once the planks are gone (state %s, planks %d)" % [z.state(), win.barricade_planks()])
	EventBus.barricade_plank_broken.disconnect(cb)
	check_eq(broken.size(), 2, "two planks broken")
	check_eq(counts, [1, 0], "one by one (outermost first)")
	check(broken.all(func(s): return s == z), "by the zombie")
	check_gt(float(get_tree_splinters()), 0.0, "splinters left on the ground")
	var inside := await wait_physics_until(func(): return is_instance_valid(z) and house.contains_point(z.global_position), 60 * 4)
	check(inside, "zombie inside the house (%s)" % z.global_position)
	check_eq(win.state, &"smashed", "window underneath still smashed")
	z.die()


func get_tree_splinters() -> int:
	return scene.get_tree().get_nodes_in_group(&"splinters").size()


func _break_time(b: BarricadeComponent, zs: Array[Zombie]) -> int:
	for z in zs:
		z.ai.blocking_obstacle = b
		z.ai.change_to(&"attack_door")
	var start := Engine.get_physics_frames()
	await wait_physics_until(func(): return not b.blocks_path(), 60 * 30)
	return Engine.get_physics_frames() - start


func test_three_zombies_break_a_barricade_faster_than_one() -> void:
	await _teleport(Vector3(20, 0.1, 20))
	var ww: Array[HouseWindow] = []
	for w in house.windows:
		if w.outward.x < -0.5:  # the two west windows
			ww.append(w)
	check_eq(ww.size(), 2, "two west windows")
	var b1 := _board(ww[0], 2, 24.0, -1.0 if ww[0].to_local(ww[0].global_position + Vector3(-1, 0, 0)).z < 0.0 else 1.0)
	var b3 := _board(ww[1], 2, 24.0, b1.side)
	var one: Array[Zombie] = []
	var a1 := ww[0].approach_point(ww[0].global_position + Vector3(-2, 0, 0))
	one.append(await _spawn(a1, -PI * 0.5, fast))
	var t1 := await _break_time(b1, one)
	var three: Array[Zombie] = []
	var a3 := ww[1].approach_point(ww[1].global_position + Vector3(-2, 0, 0))
	for dz in [-0.55, 0.0, 0.55]:
		three.append(await _spawn(a3 + Vector3(-0.1, 0, dz), -PI * 0.5, fast))
	var extra := await _spawn(a3 + Vector3(-0.6, 0, 0.0), -PI * 0.5, fast)
	three.append(extra)
	for z in three:
		z.ai.blocking_obstacle = b3
		z.ai.change_to(&"attack_door")
	await physics_frames(3)
	check_eq(b3.attacker_count(), 3, "at most 3 attackers on one opening")
	var start := Engine.get_physics_frames()
	await wait_physics_until(func(): return not b3.blocks_path(), 60 * 30)
	var t3 := Engine.get_physics_frames() - start
	check(not b1.blocks_path() and not b3.blocks_path(), "both barricades down")
	check_lt(float(t3), float(t1) * 0.6, "3 zombies (%d frames) much faster than 1 (%d frames)" % [t3, t1])
	for z in one + three:
		if is_instance_valid(z):
			z.die()


# --- Removing ----------------------------------------------------------------------

func test_remove_barricade_with_crowbar_returns_materials() -> void:
	var win := _front_window()
	_board(win, 4, 60.0, -1.0)  # inside
	_give({&"crowbar": 1})
	await _teleport(Vector3(-7, 0.1, -3.0), PI)
	var a := _action(&"unbarricade")
	check(not a.is_empty() and a.enabled, "Remove barricade offered")
	var got_planks := 0
	for i in 4:
		var r := interaction.perform_action(&"unbarricade")
		check(r.ok, "prying %d" % i)
		check_near(float(r.get("seconds", 0.0)), 2.0, 0.01, "crowbar: 2 s")
		await wait_physics_until(func(): return not player.is_busy, 60 * 3)
		await physics_frames(2)
	check_eq(win.barricade_planks(), 0, "all planks off")
	got_planks = player.inventory.count_of(&"plank")
	var got_nails := player.inventory.count_of(&"nails")
	check_gt(float(got_planks + got_nails), 0.0, "some materials back (%d planks, %d nails)" % [got_planks, got_nails])
	check(got_planks <= 4 and got_nails <= 8, "never more than was nailed")
	check_eq(player.equipment.primary().id(), &"crowbar", "crowbar in hand")


# --- Furniture ---------------------------------------------------------------------

func _furniture(type: StringName, room_contains: String) -> StaticBody3D:
	for f in house.furniture:
		if f.get_meta(&"furniture_type", &"") == type and String(f.name).contains(room_contains):
			return f
	return null


func test_furniture_blocking_the_door_must_be_destroyed_by_zombies() -> void:
	var door := _door_at(Vector3(-11.45, 0, -2))
	var shelf := _furniture(&"shelf", "LivingRoom")
	check(shelf != null, "living-room shelf")
	var fw := FurnitureWork.of(shelf)
	check(fw != null and fw.movable, "shelf is movable")
	await _teleport(shelf.global_position + Vector3(0.9, 0.1, 0.0), PI * 0.5)
	await physics_frames(3)
	check_eq(interaction.current_target, Interactable.of(shelf), "shelf targeted")
	var a := _action(&"block_door")
	check(not a.is_empty() and a.enabled, "Block door offered (%s)" % str(a))
	var r := interaction.perform_action(&"block_door")
	check(r.ok, "pushing")
	await wait_physics_until(func(): return not player.is_busy, 60 * 3)
	check(fw.is_blocking(), "shelf blocks the door")
	check_eq(door.furniture_blocker(), shelf, "door knows")
	check_lt(Vector2(shelf.global_position.x - door.sound_opening_center().x, shelf.global_position.z - door.sound_opening_center().z).length(), 0.5,
		"snapped behind the doorway")
	check_lt(shelf.global_position.z, -2.0, "on the inside")
	check_eq(door.open_door(player).reason, "Blocked by furniture", "door cannot open")
	# A zombie outside wants the player: bangs the door, then the shelf.
	await _teleport(Vector3(-9, 0.1, -5.0))
	door.health = 16.0
	fw.health = 24.0
	var destroyed := []
	var cb := func(f, src): destroyed.append([f, src])
	EventBus.furniture_destroyed.connect(cb)
	var z := await _spawn(Vector3(-11, 0, 1.5), PI, fast)
	z.ai.force_target(player)
	var door_broken := await wait_physics_until(func(): return door.state == &"broken", 60 * 10)
	check(door_broken, "door broken first (state %s)" % z.state())
	var on_shelf := await wait_physics_until(func(): return is_instance_valid(z) and z.state() == &"attack_door" \
		and z.ai.blocking_obstacle == fw, 60 * 6)
	check(on_shelf, "then bangs on the shelf (state %s, obstacle %s)" % [z.state(), z.ai.blocking_obstacle])
	var shelf_ref: WeakRef = weakref(shelf)
	shelf = null
	var gone := await wait_physics_until(func(): return shelf_ref.get_ref() == null or (shelf_ref.get_ref() as Node).is_queued_for_deletion(), 60 * 8)
	EventBus.furniture_destroyed.disconnect(cb)
	check(gone, "shelf destroyed")
	check(destroyed.size() == 1 and destroyed[0][1] == z, "furniture_destroyed by the zombie")
	var inside := await wait_physics_until(func(): return is_instance_valid(z) and house.contains_point(z.global_position), 60 * 6)
	check(inside, "zombie gets in")
	if is_instance_valid(z):
		z.die()


func test_disassemble_a_shelf_gives_planks_and_nails() -> void:
	var shelf := _furniture(&"shelf", "LivingRoom")
	_give({&"hammer": 1})
	await _teleport(shelf.global_position + Vector3(0.9, 0.1, 0.0), PI * 0.5)
	await physics_frames(3)
	check_eq(interaction.current_target, Interactable.of(shelf), "shelf targeted")
	var a := _action(&"disassemble")
	check(not a.is_empty() and a.enabled, "Disassemble offered")
	var loot := shelf as LootContainer
	check(not loot.searched, "never searched")
	loot.fixed_items = [{"id": &"apple", "count": 1}] as Array[Dictionary]
	var r := interaction.perform_action(&"disassemble")
	check(r.ok and is_equal_approx(float(r.seconds), 10.0), "10 s job (%s)" % str(r))
	check_eq(player.busy_context, &"disassemble", "busy disassembling")
	var done := await wait_physics_until(func(): return not player.is_busy, 60 * 11)
	check(done, "finished")
	await physics_frames(2)
	check(not is_instance_valid(shelf) or shelf.is_queued_for_deletion(), "shelf gone")
	var planks := player.inventory.count_of(&"plank")
	var nails := player.inventory.count_of(&"nails")
	check(planks >= 2 and planks <= 3, "2-3 planks (%d)" % planks)
	check(nails >= 2 and nails <= 4, "2-4 nails (%d)" % nails)
	check_near(SkillComponent.of(player).get_xp(&"carpentry"), 15.0, 0.01, "carpentry XP")
	check(scene.get_tree().get_nodes_in_group(&"world_item").any(func(w): return w.item != null and w.item.id() == &"apple"),
		"the unsearched shelf's contents dropped on the floor")
	var none := _furniture(&"dresser", "Bedroom")
	player.inventory.remove_id(&"hammer", 1)
	for it in player.equipment.hand_items():
		player.equipment.destroy(it)
	var acts := Interactable.of(none).get_actions(player)
	var dis: Dictionary = {}
	for x in acts:
		if x.id == &"disassemble":
			dis = x
	check(not dis.enabled and dis.reason == "Need a hammer or saw", "no tool → refused with reason")


# --- Carpentry -------------------------------------------------------------------

func test_carpentry_levels_up_and_shortens_building() -> void:
	var win := _front_window()
	var skills := SkillComponent.of(player)
	skills.xp[&"carpentry"] = 20.0
	_give({&"hammer": 1, &"plank": 2, &"nails": 4})
	await _teleport(Vector3(-7, 0.1, -3.0), PI)
	var r := interaction.perform_action(&"barricade")
	check_near(float(r.seconds), 3.0, 0.01, "3 s at level 0")
	await wait_physics_until(func(): return not player.is_busy, 60 * 4)
	check_eq(skills.level(&"carpentry"), 1, "level 1 at 30 XP")
	await frames(1)
	check_eq(hud.last_skill_notice, "Carpentry 1 ↑", "HUD level-up notice")
	await physics_frames(3)
	r = interaction.perform_action(&"barricade")
	check_near(float(r.seconds), 2.85, 0.01, "−5 % at level 1")
	await wait_physics_until(func(): return not player.is_busy, 60 * 4)
	var b := BarricadeComponent.of(win)
	check_near(float(b.planks[1].max), 63.0, 0.01, "+5 % plank health at level 1")
	skills.set_level(&"carpentry", 6)
	check_near(BarricadeComponent.default_data().build_seconds_for(skills.carpentry_time()), 2.1, 0.01, "−30 % at level 6")


# --- Critic round -------------------------------------------------------------------

func test_door_broken_mid_nailing_costs_nothing() -> void:
	var door := _door_at(Vector3(-11.45, 0, -2))
	_give({&"hammer": 1, &"plank": 1, &"nails": 2})
	await _teleport(Vector3(-11, 0.1, -3.0), PI)
	check(interaction.perform_action(&"barricade").ok, "nailing")
	await physics_frames(60)
	door.take_damage(1000.0, null)
	check_eq(door.state, &"broken", "door broken mid-job")
	await physics_frames(3)
	check(not player.is_busy, "job cancelled")
	await physics_frames(200)
	check_eq(door.barricade_planks(), 0, "no plank")
	check_eq(player.inventory.count_of(&"plank"), 1, "plank kept")
	check_eq(player.inventory.count_of(&"nails"), 2, "nails kept")
	check_eq(SkillComponent.of(player).get_xp(&"carpentry"), 0.0, "no XP")


func test_walking_off_or_the_cancel_key_stops_hammering() -> void:
	var win := _front_window()
	_give({&"hammer": 1, &"plank": 1, &"nails": 2})
	await _teleport(Vector3(-7, 0.1, -1.1), 0.0)
	var reasons := []
	var cb := func(a, _t, reason): if a == player: reasons.append(reason)
	EventBus.interaction_refused.connect(cb)
	check(interaction.perform_action(&"barricade").ok, "hammering")
	await physics_frames(20)
	ctrl.scripted_direction = Vector3.RIGHT
	await physics_frames(3)
	ctrl.scripted_direction = Vector3.ZERO
	check(not player.is_busy, "walking off stops it")
	check(reasons.has("Stopped"), "\"Stopped\" (%s)" % [reasons])
	await _teleport(Vector3(-7, 0.1, -1.1), 0.0)
	check(interaction.perform_action(&"barricade").ok, "hammering again")
	await physics_frames(20)
	interaction.scripted = false
	var ev := InputEventAction.new()
	ev.action = &"ui_cancel"
	ev.pressed = true
	interaction._unhandled_input(ev)
	interaction.scripted = true
	check(not player.is_busy, "Esc stops it")
	await _teleport(Vector3(-7, 0.1, -1.1), 0.0)
	check(interaction.perform_action(&"barricade").ok, "and again")
	await physics_frames(20)
	interaction.scripted = false
	var again := InputEventAction.new()
	again.action = &"interact"
	again.pressed = true
	interaction._unhandled_input(again)
	interaction.scripted = true
	check(not player.is_busy, "pressing E again stops it")
	EventBus.interaction_refused.disconnect(cb)
	await physics_frames(200)
	check_eq(win.barricade_planks(), 0, "never nailed")
	check_eq(player.inventory.count_of(&"plank"), 1, "plank kept")
	check_eq(player.inventory.count_of(&"nails"), 2, "nails kept")
	# Eating shares the same cancel path.
	player.inventory.add_id(&"apple", 1)
	var apple := player.inventory.find(&"apple")
	check(player.consume.start(apple).ok, "eating")
	await physics_frames(5)
	check(TimedWork.running_for(player) != null, "eating is a TimedWork")
	check(interaction.cancel_work(), "cancel key path")
	check(not player.is_busy, "stopped eating")
	check_eq(player.inventory.count_of(&"apple"), 1, "apple back")


func test_ten_zombies_crowd_the_weak_window_and_breach_it_faster() -> void:
	var win := _front_window()
	win.smash(null)
	if win.has_glass():
		win.remove_glass()
	for d in house.doors:
		if d.outward.length_squared() > 0.5:
			_board(d, 4, 60.0, 1.0 if d.to_local(Vector3(-7, 0, 5)).z >= 0.0 else -1.0)
	for w in house.windows:
		if w != win:
			_board(w, 4, 60.0, w.side_of(w.global_position + w.outward))
	await _teleport(Vector3(-8, 0.1, -4.5), 0.0)
	var t1 := await _breach_time(win, [Vector3(-9.5, 0, 1.5)])
	check_gt(float(t1.frames), 0.0, "one zombie breaches (%s)" % str(t1))
	await _teleport(Vector3(-8, 0.1, -4.5), 0.0)
	var spots: Array[Vector3] = []
	for i in 10:
		spots.append(Vector3(-11.0 + (i % 5) * 0.9, 0, 0.9 + (i / 5) * 0.8))
	var t10 := await _breach_time(win, spots)
	check_gt(float(t10.frames), 0.0, "ten zombies breach (%s)" % str(t10))
	check(int(t10.max_attackers) >= 3, "≥ 3 attackers at once (%d)" % int(t10.max_attackers))
	check(int(t10.max_attackers) <= 3, "never more than 3")
	check(t10.first, "the weak window is breached first")
	print("BREACH 1 zombie %s / 10 zombies %s" % [t1, t10])
	check_lt(float(t10.frames), float(t1.frames) * 0.6, "10 zombies (%d frames) < 60 %% of 1 (%d)" % [t10.frames, t1.frames])


## Board [win] with 3 weak planks, spawn zombies at [spots] hunting the
## player, return {frames from the first hit to the breach, max_attackers,
## first (no other opening lost all its planks)}.
func _breach_time(win: HouseWindow, spots: Array) -> Dictionary:
	var b := _board(win, 3, 24.0, 1.0)
	var zs: Array[Zombie] = []
	for p in spots:
		var z := await _spawn(p, PI, fast)
		z.ai.force_target(player)
		zs.append(z)
	var hit := await wait_physics_until(func(): return b.total_health() < 72.0, 60 * 25)
	var start := Engine.get_physics_frames()
	var max_att := 0
	var out := {"frames": -1, "max_attackers": 0, "first": false}
	if hit:
		for f in 60 * 25:
			max_att = maxi(max_att, b.attacker_count())
			if not b.blocks_path():
				out.frames = Engine.get_physics_frames() - start
				break
			await physics_frames(1)
	out.max_attackers = max_att
	var others_intact := true
	for f in house.doors + house.windows:
		if f != win and (f.outward as Vector3).length_squared() > 0.5 and f.barricade_planks() == 0:
			others_intact = false
	out.first = others_intact
	for z in zs:
		if is_instance_valid(z) and not z.dead:
			z.die()
	await physics_frames(3)
	return out


func test_block_door_through_a_wall_is_refused() -> void:
	var shelf := _furniture(&"shelf", "LivingRoom")
	var fw := FurnitureWork.of(shelf)
	var door := _door_at(Vector3(-11.45, 0, -2))
	# The shelf taken outside, 1.5 m in front of the front door: the door's
	# block spot is inside, behind the wall.
	shelf.global_position = Vector3(-11.0, 0, -0.5)
	await physics_frames(3)
	check(not fw.reachable_door(door), "front door not reachable from outside")
	check_eq(fw.block_reason(), "No door nearby", "refused (%s)" % fw.block_reason())
	check(not fw.start_block(player).ok, "start refused")
	check(door.furniture_blocker() == null, "door not blocked")


func test_no_plank_while_someone_is_in_the_window() -> void:
	var win := _front_window()
	win.smash(null)
	if win.has_glass():
		win.remove_glass()
	var z := await _spawn(Vector3(-7, 0, -1.0), 0.0, fast)
	z.ai.climb_window = win
	z.ai.change_to(&"climb_window")
	await physics_frames(40)
	check(z.is_climbing(), "zombie in the window")
	check(win.someone_in_opening(), "opening occupied")
	var r := BarricadeComponent.ensure(win).add_plank(60.0, -1.0)
	check(not r.ok and r.reason == "Someone is in the window", "plank refused (%s)" % str(r))
	_give({&"hammer": 1, &"plank": 1, &"nails": 2})
	var acts := BarricadeComponent.actions_for(win, player)
	check_eq(acts[0].reason, "Someone is in the window", "action disabled with the reason")
	await wait_physics_until(func(): return not z.is_climbing(), 120)
	await physics_frames(5)
	check(not win.someone_in_opening(), "free again")
	check(BarricadeComponent.ensure(win).add_plank(60.0, -1.0).ok, "then nailing works")
	z.die()


func test_moved_furniture_rebakes_navigation() -> void:
	var shelf := _furniture(&"shelf", "LivingRoom")
	var fw := FurnitureWork.of(shelf)
	var home := shelf.global_position
	check_gt(nav.distance_to_mesh(home + Vector3(0, 0.2, 0)), 0.2, "the shelf's spot is a navmesh hole")
	await _teleport(shelf.global_position + Vector3(0.9, 0.1, 0.0), PI * 0.5)
	var n0 := nav.rebake_count
	check(fw.start_block(player).ok, "pushing")
	await wait_physics_until(func(): return not player.is_busy, 60 * 3)
	check(fw.is_blocking(), "blocking")
	var ok := await wait_physics_until(func(): return nav.rebake_count > n0, 60 * 5)
	check(ok, "navmesh re-baked")
	check_lt(nav.distance_to_mesh(home + Vector3(0, 0.2, 0)), 0.3, "old spot walkable now")
	var door := _door_at(Vector3(-11.45, 0, -2))
	check_lt(nav.distance_to_mesh(door.sound_opening_center() + Vector3(0, 0.2, 0)), 0.3,
		"doorway stays walkable (zombies path to it and meet the shelf)")
	check_eq(shelf.collision_layer & 1, 0, "blocking piece off the world layer")
	check(shelf.collision_layer & (1 << 8) != 0, "on the barricades layer")
	check(player.collision_mask & (1 << 8) != 0, "the player collides with it")
