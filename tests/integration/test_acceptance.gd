extends "res://tests/test_case.gd"
## Round 10 — the brief's FINAL ACCEPTANCE TEST as a scripted playthrough
## of the real test_ground scene (fresh game, its own seeded zombies),
## then save → reload into a fresh scene → confirm the world:
##
##   spawn in a house → search the kitchen → find food → equip a backpack
##   → find a weapon → hear zombies (a smashed window's noise reaches a
##   zombie outside, whose moan reaches the player) → climb out through the
##   window (broken glass: injured) → fight and kill it → explore the
##   garage (open its door, search, take the shelf apart) → supplies from
##   the crate by the garage (hammer, bandage) → treat the injury → carry
##   it all home through the front door → hungry and thirsty (time) → eat
##   and drink (the kitchen sink) → barricade the smashed window → push
##   the living-room shelf in front of the front door → sleep → save.
##
## Then: the player (position, health, needs, wounds), inventory (exact
## items / counts / conditions, bag contents, hands, hotbar), dead
## zombies stay dead (corpse at the same spot, living count matches),
## looted containers stay looted and unsearched ones unrolled, barricades
## (planks + health), world time, doors / windows, dropped items, moved
## and destroyed furniture. Save → load → save gives identical files;
## a corrupt save is refused and the running game is untouched.
##
## Layout: House A x -14..-4, z -10..-2 (front door hinge (-11.45, -2),
## living-room window (-7, -2), kitchen x -7.5..-4, z -10..-6, sink
## (-4.4, -6.7), bed (-10.75, -8.85)); Garage x 6..10, z -16..-13 (door
## centre (8, -13)); supply crate (10.9, -12.2).

const SLOT := "acceptance_test"
const SLOT_B := "acceptance_test_b"

var scene: Node
var player: Player
var ctrl: PlayerController
var interaction: PlayerInteraction
var combat: MeleeCombat
var spawner: ZombieSpawner
var house: HouseBlockout
var garage: HouseBlockout


func setup() -> void:
	# A completely fresh game: the map's own spawner populates the world.
	scene = await spawn_scene("res://maps/test_ground.tscn")
	_bind(scene)
	var nav: NavBaker = scene.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	await wait_physics_until(func(): return spawner.zombies.size() >= spawner.count, 120)
	await physics_frames(3)


func teardown() -> void:
	await despawn(scene)
	SaveFile.delete_slot(SLOT)
	SaveFile.delete_slot(SLOT_B)
	Engine.time_scale = 1.0
	tree.paused = false


func _bind(map: Node) -> void:
	scene = map
	player = map.get_node("Player")
	ctrl = player.get_node("Controller")
	interaction = player.get_node("Interaction")
	combat = player.get_node("Combat")
	spawner = map.get_node("Zombies")
	house = map.get_node("Buildings/HouseA")
	garage = map.get_node("Buildings/Garage")
	ctrl.scripted = true
	interaction.scripted = true
	combat.scripted = true


# --- Helpers ------------------------------------------------------------------------------

func _stand(at: Vector3, look_at: Vector3) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = Vector3(at.x, 0.1, at.z)
	player.velocity = Vector3.ZERO
	var d := look_at - at
	d.y = 0.0
	player.movement.facing = BodyHelpers.yaw_for(d.normalized())
	if player.visual:
		player.visual.rotation.y = player.movement.facing
	await physics_frames(4)


func _action(id: StringName) -> Dictionary:
	if interaction.current_target == null:
		return {}
	for a in interaction.current_actions:
		if a.id == id:
			return a
	return {}


func _wait_idle(max_frames: int = 900) -> bool:
	return await wait_physics_until(func(): return not player.is_busy, max_frames)


func _container(pid: String) -> LootContainer:
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and c.persist_id == pid and scene.is_ancestor_of(c) and not c.is_queued_for_deletion():
			return c
	return null


func _door_at(b: HouseBlockout, world: Vector3) -> Door:
	for d in b.doors:
		if (d.global_position - world).length() < 0.3:
			return d
	return null


func _front_window() -> HouseWindow:
	for w in house.windows:
		if (w.global_position - Vector3(-7, 0, -2)).length() < 0.3:
			return w
	return null


func _furniture(b: HouseBlockout, type: StringName, room_contains: String) -> StaticBody3D:
	for f in b.furniture:
		if is_instance_valid(f) and f.get_meta(&"furniture_type", &"") == type and String(f.name).contains(room_contains):
			return f
	return null


## Search [c] through the real interaction (rummage → open).
func _open(c: LootContainer) -> bool:
	var front := c.global_basis.z
	front.y = 0.0
	front = front.normalized()
	var reach := c.size.z * 0.5 + 0.75 if c.size != Vector3.ZERO else 0.9
	await _stand(c.global_position + front * reach, c.global_position)
	if interaction.current_target == null or interaction.current_target.body() != c:
		fail("%s not targeted" % c.persist_id)
		return false
	var r := interaction.interact()
	if not r.get("ok", false):
		fail("search %s refused: %s" % [c.persist_id, str(r)])
		return false
	var ok := await wait_physics_until(func(): return c.is_open_for(player), 180)
	await physics_frames(2)
	return ok


func _alive_zombies(map: Node) -> int:
	var n := 0
	for z in tree.get_nodes_in_group(&"zombie"):
		if map.is_ancestor_of(z) and not z.dead:
			n += 1
	return n


## Swing the equipped weapon at [z] until it dies (the player steps in to
## reach when needed). True when it died.
func _fight(z: Zombie, max_frames: int = 60 * 25) -> bool:
	var ref: WeakRef = weakref(z)
	for i in max_frames:
		var zz: Zombie = ref.get_ref()
		if zz == null or zz.dead:
			return true
		if player.is_dead():
			return false
		var to := zz.global_position - player.global_position
		to.y = 0.0
		player.movement.facing = BodyHelpers.yaw_for(to.normalized())
		if to.length() > 1.3:
			ctrl.scripted_direction = to.normalized()
		else:
			ctrl.scripted_direction = Vector3.ZERO
			if not combat.is_swinging():
				combat.attack_now(0.35)
		await tree.physics_frame
	ctrl.scripted_direction = Vector3.ZERO
	return ref.get_ref() == null or (ref.get_ref() as Zombie).dead


func _counts(inv: ItemContainer) -> Dictionary:
	var out := {}
	for it in inv.items:
		out[String(it.id())] = int(out.get(String(it.id()), 0)) + it.stack
	return out


## Everything carried as {id: [count, conditions…]} (exact inventory check).
func _carried(p: Player) -> Dictionary:
	var out := {}
	var add := func(it: ItemInstance, where: String):
		var k := "%s@%s" % [String(it.id()), where]
		if not out.has(k):
			out[k] = [0]
		out[k][0] += it.stack
		out[k].append(it.condition)
	for it in p.inventory.items:
		add.call(it, "main")
	for it in p.equipment.hand_items():
		add.call(it, "hand")
	var bag := p.equipment.back_bag()
	if bag != null:
		add.call(bag, "back")
		for it in bag.contents.items:
			add.call(it, "bag")
	for k in out:
		var conds: Array = out[k].slice(1)
		conds.sort()
		out[k] = [out[k][0]] + conds
	return out


# --- The playthrough -------------------------------------------------------------------------

func test_final_acceptance_playthrough() -> void:
	var t_start := Time.get_ticks_msec()
	check(spawner.zombies.size() == spawner.count, "fresh world populated (%d zombies)" % spawner.zombies.size())
	# The seeded crowd roams the far side of the map; this run is about the
	# house and the garage.
	var k := 0
	for z in spawner.zombies:
		z.global_position = Vector3(28.0 + 2.5 * (k % 4), 0.05, 30.0 + 2.5 * (k / 4))
		z.home_position = z.global_position
		k += 1

	# 1. Spawn in a house (living room of House A).
	await _stand(Vector3(-9.0, 0, -4.0), Vector3(-9.0, 0, -8.0))
	check(house.contains_point(player.global_position), "spawned inside House A")

	# 2-3. Search the kitchen → find food.
	var food: ItemInstance = null
	for pid in ["HouseA/kitchen/0", "HouseA/kitchen/1", "HouseA/kitchen/2", "HouseA/kitchen/3"]:
		var c := _container(pid)
		if c == null or not await _open(c):
			continue
		for it in c.inventory.items.duplicate():
			if it.data is FoodData and food == null and it.data.weight <= 1.0:
				var r: Dictionary = c.take(player, it, 1)
				if r.get("ok", false):
					food = player.inventory.find(it.id())
		c.close()
		if food != null:
			break
	check(food != null, "found food in the kitchen")
	var food_id: StringName = food.id() if food else &""
	var dresser := _container("HouseA/bedroom/0")
	check(dresser != null and not dresser.searched, "the bedroom dresser stays unsearched")

	# 4. Equip a backpack (lying in the bedroom).
	await _stand(Vector3(-10.75, 0, -7.2), Vector3(-10.75, 0, -8.1))
	var bag_body: Node = interaction.current_target.body() if interaction.current_target else null
	check(bag_body is WorldItem and (bag_body as WorldItem).item.id() == &"backpack",
		"backpack targeted (%s)" % (interaction.current_target.display_name() if interaction.current_target else "nothing"))
	check(interaction.interact().ok, "backpack picked up")
	var bag := player.inventory.find(&"backpack")
	check(bag != null and player.equip_item(bag).ok, "backpack worn")
	check(player.equipment.back_bag() != null, "on the back")

	# 5. Find a weapon (the bat in the living room) — auto-equipped.
	await _stand(Vector3(-6.5, 0, -2.5), Vector3(-6.5, 0, -3.2))
	check(interaction.interact().ok, "bat picked up")
	check(player.equipment.primary() != null and player.equipment.primary().id() == &"baseball_bat", "bat in hand")
	check(player.equipment.assign_hotbar(0, player.equipment.primary()).ok, "bat on hotbar 1")

	# 6. Hear zombies outside: smash the living-room window; a zombie
	# 8 m out hears it, investigates and moans — the moan reaches us.
	var win := _front_window()
	var z1 := spawner.spawn_at(Vector3(-7.0, 0, 6.0))
	z1.snap_facing(0.0)
	await physics_frames(5)
	var moans := []
	var on_sound := func(pos: Vector3, radius: float, _i: float, cat: StringName, _src: Node):
		if cat == &"zombie_moan" and pos.distance_to(player.global_position) <= radius + 0.5:
			moans.append(pos)
	EventBus.sound_emitted.connect(on_sound)
	await _stand(Vector3(-7.0, 0, -2.9), Vector3(-7.0, 0, 0.0))
	check(interaction.current_target != null and interaction.current_target.body() == win, "window targeted")
	check(interaction.perform_action(HouseWindow.ACTION_SMASH).ok, "window smashed")
	check(await wait_physics_until(func(): return z1.state() == ZombieAI.S_INVESTIGATE or z1.state() == ZombieAI.S_CHASE, 60 * 3),
		"the zombie outside heard the smash (%s)" % z1.state())
	check(await wait_physics_until(func(): return not moans.is_empty() or z1.state() == ZombieAI.S_CHASE, 60 * 6),
		"a zombie is heard from inside (moan within earshot)")
	EventBus.sound_emitted.disconnect(on_sound)

	# 7. Climb through the smashed window (broken glass → injured).
	await physics_frames(2)
	var climb := _action(HouseWindow.ACTION_CLIMB)
	check(not climb.is_empty() and climb.enabled, "climb offered (%s)" % str(climb))
	# The glass cuts at glass_laceration_chance (0.4): seed the wound roll
	# so this run is the unlucky one.
	var rs := 1
	var probe := RandomNumberGenerator.new()
	while true:
		probe.seed = rs
		if probe.randf() < player.injuries.profile.glass_laceration_chance:
			break
		rs += 1
	player.injuries.rng.seed = rs
	var cr := interaction.perform_action(HouseWindow.ACTION_CLIMB)
	check(cr.ok and cr.get("hazard", false), "climbing out over broken glass (%s)" % str(cr))
	check(await _wait_idle(120), "climbed")
	await physics_frames(3)
	check(player.global_position.z > -2.0, "outside now")
	check(player.injuries.injuries.size() > 0, "cut by the glass (injured)")

	# 8. Fight: kill the zombie.
	var z1_id := z1.spawn_id
	var killed := await _fight(z1)
	check(killed, "zombie killed")
	check(not player.is_dead(), "survived the fight")
	await physics_frames(3)
	var corpse: ZombieCorpse = null
	for c in tree.get_nodes_in_group(&"corpse"):
		if scene.is_ancestor_of(c) and c.persist_id == "corpse/" + z1_id:
			corpse = c
	check(corpse != null, "its corpse lies there")
	var corpse_pos := corpse.global_position if corpse else Vector3.ZERO

	# 9. Explore another building: the garage (open its door, go in).
	var gdoor := _door_at(garage, Vector3(7.55, 0, -13.0))
	check(gdoor != null, "garage door")
	await _stand(Vector3(8.0, 0, -12.0), Vector3(8.0, 0, -14.0))
	check(interaction.current_target != null and interaction.current_target.body() == gdoor, "garage door targeted")
	check(interaction.perform_action(Door.ACTION_OPEN).ok, "garage door opened")
	await physics_frames(30)
	var crate := _container("Garage/garage/0")
	check(await _open(crate), "tool crate searched")
	var loot_all: Dictionary = crate.take_all(player)
	check(crate.searched, "crate looted (%s)" % str(loot_all))
	crate.close()

	# 10. Supplies from the crate outside the garage (staged: a hammer and a
	# bandage are guaranteed so the rest of the loop is deterministic).
	var supply := _container("Map/SupplyCrate")
	check(supply != null and not supply.searched, "supply crate untouched")
	supply.fixed_items = [{"id": &"hammer", "count": 1}, {"id": &"bandage", "count": 1}, {"id": &"nails", "count": 6}] as Array[Dictionary]
	check(await _open(supply), "supply crate searched")
	for id in [&"hammer", &"bandage", &"nails"]:
		var it := supply.inventory.find(id)
		if it != null:
			supply.take(player, it)
	supply.close()
	check(CarriedItems.find_tool(player, [&"hammer"] as Array[StringName]) != null, "carrying a hammer")

	# 11. Treat the injuries (B: bandage the worst wound, until none bleeds).
	CarriedItems.give(player, &"bandage", 2)  # the bathroom's first-aid kit
	for i in 4:
		if player.injuries.bleeding_count() == 0:
			break
		check(player.injuries.bandage_worst().ok, "bandaging")
		check(await _wait_idle(60 * 6), "bandaged")
	var bandaged := player.injuries.injuries.filter(func(i): return i.bandaged).size()
	check(bandaged >= 1, "a wound is bandaged")
	check_eq(player.injuries.bleeding_count(), 0, "no longer bleeding")

	# 12. Take the garage shelf apart for planks (furniture destroyed).
	var gshelf := _furniture(garage, &"shelf", "Garage")
	check(gshelf != null, "garage shelf")
	await _stand(gshelf.global_position + gshelf.global_basis.z.normalized() * 0.95, gshelf.global_position)
	check(interaction.current_target != null and interaction.current_target.body() == gshelf, "shelf targeted")
	check(interaction.perform_action(FurnitureWork.ACTION_DISASSEMBLE).ok, "disassembling")
	check(await _wait_idle(60 * 12), "taken apart")
	await physics_frames(2)
	check(not is_instance_valid(gshelf) or gshelf.is_queued_for_deletion(), "shelf gone")
	check_gt(float(CarriedItems.count(player, &"plank")), 1.5, "planks carried")

	# 13. Carry the supplies home through the front door; close it.
	var fdoor := _door_at(house, Vector3(-11.45, 0, -2.0))
	await _stand(Vector3(-11.0, 0, -1.0), Vector3(-11.0, 0, -3.0))
	check(interaction.current_target != null and interaction.current_target.body() == fdoor, "front door targeted")
	check(interaction.perform_action(Door.ACTION_OPEN).ok, "front door opened")
	await physics_frames(30)
	await _stand(Vector3(-11.0, 0, -3.2), Vector3(-11.0, 0, -1.0))
	check(house.contains_point(player.global_position), "home")
	check(interaction.current_target != null and interaction.current_target.body() == fdoor, "door targeted from inside")
	check(interaction.perform_action(Door.ACTION_CLOSE).ok, "front door closed")
	await physics_frames(30)
	# Drop the empty-handed junk we will not carry around (a dropped item).
	var dropped_id: StringName = &""
	for it in player.inventory.items:
		if not it.is_weapon() and it.id() != food_id and it.id() != &"plank" and it.id() != &"nails" and not it.is_bag():
			dropped_id = it.id()
			check(player.drop_item(it, 1).ok, "dropped a %s" % it.id())
			break
	if dropped_id == &"":
		player.inventory.add_id(&"newspaper", 1)
		dropped_id = &"newspaper"
		check(player.drop_item(player.inventory.find(&"newspaper")).ok, "dropped a newspaper")
	var dropped_pos := Vector3.ZERO
	for w in tree.get_nodes_in_group(WorldItem.GROUP):
		if scene.is_ancestor_of(w) and w.item != null and w.item.id() == dropped_id:
			dropped_pos = w.global_position

	# 14. Become hungry and thirsty (time passes), then eat and drink.
	TimeManager.advance(9.0 * 60.0)
	check_gt(float(player.needs.level(&"hunger")), 0.5, "hungry")
	check_gt(float(player.needs.level(&"thirst")), 0.5, "thirsty")
	var hunger_before := player.needs.value(&"hunger")
	var meal := player.inventory.find(food_id)
	if meal == null:
		meal = CarriedItems.containers(player).map(func(c): return c.find(food_id)).filter(func(x): return x != null).front()
	var er := player.consume_item(meal)
	check(er.ok, "eating (%s)" % str(er))
	check(await _wait_idle(60 * 12), "ate")
	check_lt(player.needs.value(&"hunger"), hunger_before, "less hungry")
	var thirst_before := player.needs.value(&"thirst")
	await _stand(Vector3(-5.45, 0, -6.7), Vector3(-4.4, 0, -6.7))
	check(interaction.current_target != null and interaction.current_target.body() is Sink, "sink targeted")
	check(interaction.perform_action(Sink.DRINK).ok, "drinking at the sink")
	check(await _wait_idle(60 * 12), "drank")
	check_lt(player.needs.value(&"thirst"), thirst_before, "less thirsty")

	# 15. Barricade the safehouse: two planks over the smashed window.
	await _stand(Vector3(-7.0, 0, -2.9), Vector3(-7.0, 0, 0.0))
	for i in 2:
		await physics_frames(3)
		var a := _action(BarricadeComponent.ACTION_ADD)
		check(not a.is_empty() and a.enabled, "Barricade offered (%s)" % str(a))
		check(interaction.perform_action(BarricadeComponent.ACTION_ADD).ok, "nailing plank %d" % (i + 1))
		check(await _wait_idle(60 * 5), "plank %d nailed" % (i + 1))
	check_eq(win.barricade_planks(), 2, "window barricaded (2 planks)")
	var bc := BarricadeComponent.of(win)
	bc.planks[0].health = 23.5  # a zombie already had a go at it
	# ...and push the living-room shelf in front of the front door.
	var lshelf := _furniture(house, &"shelf", "LivingRoom")
	await _stand(lshelf.global_position + Vector3(0.9, 0, 0.0), lshelf.global_position)
	check(interaction.current_target != null and interaction.current_target.body() == lshelf, "living-room shelf targeted")
	check(interaction.perform_action(FurnitureWork.ACTION_BLOCK).ok, "pushing the shelf")
	check(await _wait_idle(60 * 4), "pushed")
	check(FurnitureWork.of(lshelf).is_blocking() and fdoor.furniture_blocker() == lshelf, "front door blocked by furniture")
	var lshelf_xf := lshelf.global_transform

	# 16. Sleep in the bed.
	if player.needs.value(&"fatigue") < 40.0:
		player.needs.set_need(&"fatigue", 60.0)
	await _stand(Vector3(-11.95, 0, -8.85), Vector3(-10.75, 0, -8.85))
	var t_sleep := TimeManager.now()
	var sr := interaction.perform_action(RestFurniture.SLEEP)
	check(sr.ok, "asleep (%s)" % str(sr))
	check(await wait_physics_until(func(): return not player.rest.sleeping, 60 * 40), "woke up")
	check(await _wait_idle(60), "up again")
	check_gt(TimeManager.now() - t_sleep, 60.0, "hours passed asleep")
	check_eq(Engine.time_scale, 1.0, "engine speed back to normal")
	await physics_frames(3)

	# --- 17. Save -----------------------------------------------------------------------------
	var before := {
		"pos": player.global_position, "facing": player.movement.facing,
		"health": player.health.health, "hunger": player.needs.value(&"hunger"),
		"thirst": player.needs.value(&"thirst"), "fatigue": player.needs.value(&"fatigue"),
		"stamina": player.stats.get_value(&"stamina"),
		"wounds": player.injuries.injuries.map(func(i): return [i.region_id(), i.type_id(), i.bandaged]),
		"carried": _carried(player), "carpentry": SkillComponent.of(player).get_xp(&"carpentry"),
		"minutes": TimeManager.now(), "alive": _alive_zombies(scene),
		"hotbar0": player.equipment.hotbar_item(0).id() if player.equipment.hotbar_item(0) else &"",
		"primary": player.equipment.primary().id() if player.equipment.primary() else &"",
		"kitchen0": _counts(_container("HouseA/kitchen/0").inventory),
	}
	var sv := SaveManager.save_game(SLOT, scene)
	check(sv.ok, "saved (%s)" % str(sv))
	print("  acceptance: save %.1f ms, %d bytes" % [float(sv.get("ms", 0.0)), int(sv.get("bytes", 0))])
	check(SaveManager.has_slot(SLOT) and FileAccess.file_exists(SaveFile.meta_path(SLOT)), "world.json + meta.json on disk")
	var text1 := String(SaveFile.read_text(SaveFile.world_path(SLOT)).text)
	var data1: Dictionary = SaveFile.parse(text1).data

	# --- 18. Exit and reload into a fresh scene ---------------------------------------------
	var old_ref: WeakRef = weakref(scene)
	var lr: Dictionary = await SaveManager.load_game(SLOT, scene)
	check(lr.ok, "loaded (%s)" % str(lr.get("error", "")))
	if not lr.ok:
		return
	var map: Node = lr.map
	# Save again right away (same frame): identical to the first save.
	var sv2 := SaveManager.save_game(SLOT_B, map)
	check(sv2.ok, "second save")
	var text2 := String(SaveFile.read_text(SaveFile.world_path(SLOT_B)).text)
	var diff := SaveFile.first_difference(data1, SaveFile.parse(text2).data)
	check(diff == "", "save → load → save is identical (%d vs %d bytes)%s" % [text1.length(), text2.length(), diff])
	print("  acceptance: load %.1f ms" % float(lr.ms))
	_bind(map)
	await frames(1)
	check(old_ref.get_ref() == null or (old_ref.get_ref() as Node).is_queued_for_deletion(), "old world gone")
	check(map.is_inside_tree() and GameManager.player == player, "fresh player registered")

	# --- 19. Confirm ------------------------------------------------------------------------------
	# Player state.
	# (A frame has passed since the load: exactness is proven by the
	# identical re-save above; these read the live objects.)
	check(Vector2(player.global_position.x - before.pos.x, player.global_position.z - before.pos.z).length() < 0.02,
		"position (%s vs %s)" % [player.global_position, before.pos])
	check_near(player.movement.facing, before.facing, 0.0001, "facing")
	check_near(player.health.health, before.health, 0.05, "health")
	check_near(player.needs.value(&"hunger"), before.hunger, 0.05, "hunger")
	check_near(player.needs.value(&"thirst"), before.thirst, 0.05, "thirst")
	check_near(player.needs.value(&"fatigue"), before.fatigue, 0.05, "fatigue")
	check_near(player.stats.get_value(&"stamina"), before.stamina, 1.0, "stamina")
	check_eq(player.injuries.injuries.map(func(i): return [i.region_id(), i.type_id(), i.bandaged]), before.wounds, "wounds (bandaged)")
	check_near(SkillComponent.of(player).get_xp(&"carpentry"), before.carpentry, 0.001, "carpentry XP")
	check(not player.is_busy, "not busy after load")
	# Inventory.
	check_eq(_carried(player), before.carried, "inventory: exact items / counts / conditions / places")
	check(player.equipment.back_bag() != null and player.equipment.back_bag().id() == &"backpack", "backpack worn")
	check_eq(player.equipment.primary().id() if player.equipment.primary() else &"", before.primary, "same item in hand")
	check_eq(player.equipment.hotbar_item(0).id() if player.equipment.hotbar_item(0) else &"", before.hotbar0, "hotbar")
	check_eq(combat.weapon().id, before.primary, "combat uses it")
	# Killed zombies stay dead.
	check_eq(_alive_zombies(map), before.alive, "living zombie count")
	var ids := []
	for z in tree.get_nodes_in_group(&"zombie"):
		if map.is_ancestor_of(z):
			ids.append(z.spawn_id)
	check(not ids.has(z1_id), "the killed zombie did not respawn")
	var corpse2: ZombieCorpse = null
	for c in tree.get_nodes_in_group(&"corpse"):
		if map.is_ancestor_of(c) and c.persist_id == "corpse/" + z1_id:
			corpse2 = c
	check(corpse2 != null and corpse2.global_position.distance_to(corpse_pos) < 0.01, "corpse at the same place")
	check_eq(spawner.alive_count(), before.alive, "spawner did not re-spawn")
	# Containers.
	check(_container("HouseA/kitchen/0").searched, "looted kitchen cabinet stays searched")
	check_eq(_counts(_container("HouseA/kitchen/0").inventory), before.kitchen0, "and keeps what was left")
	var d2 := _container("HouseA/bedroom/0")
	check(d2 != null and not d2.searched and d2.inventory.is_empty(), "unsearched dresser still unrolled")
	check(_container("Garage/garage/0").searched and _container("Map/SupplyCrate").searched, "garage crate + supply crate looted")
	check(_container("Map/SupplyCrate").inventory.count_of(&"hammer") == 0, "the hammer is not back in the crate")
	# Barricades.
	var win2 := _front_window()
	check_eq(win2.barricade_planks(), 2, "2 planks on the window")
	check_near(float(BarricadeComponent.of(win2).planks[0].health), 23.5, 0.001, "plank health")
	check_eq(win2.state, HouseWindow.STATE_SMASHED, "window still smashed")
	check(win2.can_climb() == false, "barricaded window cannot be climbed")
	# World time.
	check_near(TimeManager.now(), before.minutes, 0.2, "world time")
	check_eq(TimeManager.speed_step, TimeManager.STEP_NORMAL, "time at 1×")
	# Doors / windows.
	check(_door_at(garage, Vector3(7.55, 0, -13.0)).is_open(), "garage door still open")
	var fdoor2 := _door_at(house, Vector3(-11.45, 0, -2.0))
	check(not fdoor2.is_open(), "front door closed")
	# Moved / destroyed furniture.
	var lshelf2 := _furniture(house, &"shelf", "LivingRoom")
	check(lshelf2 != null and FurnitureWork.of(lshelf2).is_blocking() and fdoor2.furniture_blocker() == lshelf2, "shelf still blocks the front door")
	check(lshelf2 != null and lshelf2.global_transform.origin.distance_to(lshelf_xf.origin) < 0.001, "shelf at the same spot")
	check_eq(fdoor2.open_door(player).get("reason", ""), "Blocked by furniture", "door refuses to open")
	var gshelf2 := _furniture(garage, &"shelf", "Garage")
	check(gshelf2 == null or gshelf2.is_queued_for_deletion(), "disassembled shelf stays gone")
	# Dropped items.
	var found_drop := false
	for w in tree.get_nodes_in_group(WorldItem.GROUP):
		if map.is_ancestor_of(w) and w.item != null and w.item.id() == dropped_id and w.global_position.distance_to(dropped_pos) < 0.01:
			found_drop = true
	check(found_drop, "the dropped %s lies where it was" % dropped_id)
	var bats := 0
	for w in tree.get_nodes_in_group(WorldItem.GROUP):
		if map.is_ancestor_of(w) and w.item != null and w.item.id() == &"baseball_bat":
			bats += 1
	check_eq(bats, 0, "the picked-up bat did not reappear on the floor")

	# --- 20. Load twice: idempotent ---------------------------------------------------------
	var lr2: Dictionary = await SaveManager.load_game(SLOT_B, map)
	check(lr2.ok, "second load")
	if lr2.ok:
		SaveManager.save_game(SLOT_B, lr2.map)
		_bind(lr2.map)
		var text3 := String(SaveFile.read_text(SaveFile.world_path(SLOT_B)).text)
		var diff3 := SaveFile.first_difference(data1, SaveFile.parse(text3).data)
		check(diff3 == "", "third save identical too %s" % diff3)
	print("  acceptance: whole playthrough %.1f s" % ((Time.get_ticks_msec() - t_start) / 1000.0))


func test_corrupt_save_is_refused_and_the_game_is_untouched() -> void:
	await _stand(Vector3(-9.0, 0, -4.0), Vector3(-9.0, 0, -8.0))
	player.inventory.add_id(&"apple", 2)
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	# Corrupt the file on disk (truncated JSON).
	var path := SaveFile.world_path(SLOT)
	var text := String(SaveFile.read_text(path).text)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text.substr(0, text.length() / 2))
	f.close()
	var notices := []
	var cb := func(t: String, _s: float): notices.append(t)
	EventBus.game_notice.connect(cb)
	var t0 := TimeManager.now()
	var r: Dictionary = await SaveManager.load_game(SLOT, scene)
	EventBus.game_notice.disconnect(cb)
	check(not r.ok and String(r.error).begins_with("Corrupt save"), "refused (%s)" % str(r))
	check(scene.is_inside_tree() and not scene.is_queued_for_deletion(), "current world kept")
	check(GameManager.player == player and player.inventory.count_of(&"apple") == 2, "player untouched")
	check(TimeManager.now() >= t0, "clock untouched")
	check(notices.any(func(t): return String(t).begins_with("Corrupt save")), "HUD notice")
	await frames(2)
	check(String((scene.get_node("HUD") as CanvasLayer).notice_label.text).begins_with("Corrupt save"), "shown on the HUD")
	# A missing slot is refused the same way.
	var r2: Dictionary = await SaveManager.load_game("no_such_slot_xyz", scene)
	check(not r2.ok and scene.is_inside_tree(), "missing slot refused")


func test_saving_is_refused_while_busy() -> void:
	await _stand(Vector3(-9.0, 0, -4.0), Vector3(-9.0, 0, -8.0))
	player.inventory.add_id(&"apple", 1)
	check(player.consume_item(player.inventory.find(&"apple")).ok, "eating")
	var r := SaveManager.save_game(SLOT, scene)
	check(not r.ok and r.error == "Can't save now: busy", "refused while eating (%s)" % str(r))
	check(not SaveManager.has_slot(SLOT), "nothing written")
	await _wait_idle(60 * 10)
	check(SaveManager.save_game(SLOT, scene).ok, "fine afterwards")


func test_doors_windows_vehicles_and_zombie_states_round_trip() -> void:
	# Every kind of static state, set directly, then save → load.
	var back_door: Door = null
	var bedroom_door: Door = null
	for d in house.doors:
		if d.outward.z < -0.5:
			back_door = d
		elif d.outward.length_squared() < 0.5 and bedroom_door == null:
			bedroom_door = d
	check(back_door != null and bedroom_door != null, "doors found")
	back_door.take_damage(back_door.health + 1.0, null)
	check(back_door.is_broken(), "back door broken")
	bedroom_door.locked = true
	bedroom_door.health = 123.0
	var gdoor := _door_at(garage, Vector3(7.55, 0, -13.0))
	var planks := BarricadeComponent.ensure(gdoor)
	planks.add_plank(44.0, -1.0)
	planks.add_plank(60.0, -1.0)
	var side_win: HouseWindow = null
	for w in house.windows:
		if w != _front_window():
			side_win = w
			break
	side_win.open_window(null)
	var front := _front_window()
	front.smash(null)
	front.remove_glass()
	var trunk := _container("Vehicle/PoliceCar/trunk")
	check(trunk != null, "police car trunk (%s)" % str(trunk))
	trunk.ensure_loot()
	trunk.inventory.clear()
	trunk.inventory.add_id(&"crowbar", 1)
	# Zombies in different moods.
	var zi := spawner.spawn_at(Vector3(20, 0, 20))
	var zc := spawner.spawn_at(Vector3(24, 0, 20))
	await physics_frames(3)
	zc.ai.force_target(player)
	zc.take_damage(15.0, null, {})
	await physics_frames(3)
	var zc_health := zc.health()
	var zi_id := zi.spawn_id
	var zc_id := zc.spawn_id
	var counter := spawner.spawn_counter
	var back_id := back_door.persist_id
	var bed_id := bedroom_door.persist_id
	var win_id := side_win.persist_id
	await physics_frames(10)  # doors / windows tweens settle
	check(SaveManager.save_game(SLOT, scene).ok, "saved")
	var r: Dictionary = await SaveManager.load_game(SLOT, scene)
	check(r.ok, "loaded (%s)" % str(r.get("error", "")))
	if not r.ok:
		return
	_bind(r.map)
	var bd: Door = null
	for d in house.doors:
		if d.persist_id == back_id:
			bd = d
	check(bd.is_broken() and bd.collision_layer == 1 << 3 and not bd.visual.visible, "broken door stays broken (no leaf)")
	var bed_door: Door = null
	for d in house.doors:
		if d.persist_id == bed_id:
			bed_door = d
	check(bed_door != null and bed_door.locked and is_equal_approx(bed_door.health, 123.0), "locked door + health")
	check_eq(bed_door.open_door(player).get("reason", ""), "Locked", "still locked")
	var gd := _door_at(garage, Vector3(7.55, 0, -13.0))
	var gp := BarricadeComponent.of(gd)
	check(gp != null and gp.plank_count() == 2 and gp.side == -1.0, "door planks + side")
	check(gp != null and is_equal_approx(float(gp.planks[0].health), 44.0), "plank health")
	check_eq(gd.open_door(player).get("reason", ""), "Barricaded", "barricaded door refuses")
	var sw: HouseWindow = null
	for w in house.windows:
		if w.persist_id == win_id:
			sw = w
	check(sw != null and sw.state == HouseWindow.STATE_OPEN and sw.can_climb(), "open window stays open")
	var fw := _front_window()
	check(fw.state == HouseWindow.STATE_SMASHED and not fw.has_glass(), "smashed window, glass cleared")
	var t2 := _container("Vehicle/PoliceCar/trunk")
	check(t2.searched and t2.inventory.count_of(&"crowbar") == 1 and t2.inventory.items.size() == 1, "vehicle trunk contents")
	var z_ids := {}
	for z in tree.get_nodes_in_group(&"zombie"):
		if scene.is_ancestor_of(z):
			z_ids[z.spawn_id] = z
	check(z_ids.has(zi_id), "calm zombie back")
	check_eq(z_ids.size(), spawner.count + 2, "every living zombie back")
	var zc2: Zombie = z_ids.get(zc_id)
	check(zc2 != null and is_equal_approx(zc2.health(), zc_health), "wounded zombie keeps its health")
	check(zc2 != null and zc2.state() == ZombieAI.S_INVESTIGATE, "a chasing zombie comes back investigating (%s)" % (zc2.state() if zc2 else &""))
	check_eq(spawner.spawn_counter, counter, "spawn counter restored (new ids stay unique)")
	var zn := spawner.spawn_at(Vector3(26, 0, 22))
	check(not z_ids.has(zn.spawn_id), "a new zombie gets a fresh id (%s)" % zn.spawn_id)
