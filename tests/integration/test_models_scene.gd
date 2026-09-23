extends "res://tests/test_case.gd"
## Round 8.5 in the real test_ground scene: the player / zombie models are
## present and their animation follows gameplay (walk, sneak, swing, hit,
## death; zombie chase shamble, knockdown, corpse pose), the weapon rides
## the right-hand bone, the worn bag the back; parked vehicles block
## movement, are baked into the navmesh (paths go around), have searchable
## trunks / gloveboxes and light up at night (emergency vehicles).

var scene: Node
var player: Player
var ctrl: PlayerController
var combat: MeleeCombat
var interaction: PlayerInteraction
var animator: CharacterAnimator
var spawner: ZombieSpawner
var nav: NavBaker


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	combat = player.get_node("Combat")
	interaction = player.get_node("Interaction")
	animator = player.get_node("Animator")
	nav = scene.get_node("NavRegion")
	ctrl.scripted = true
	combat.scripted = true
	interaction.scripted = true
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(3)


func teardown() -> void:
	await despawn(scene)


func _teleport(p: Vector3, yaw: float = 0.0) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.movement.facing = yaw
	await physics_frames(4)


# --- Player -------------------------------------------------------------------------

func test_player_model_follows_movement() -> void:
	var model: CharacterModel = player.get_node("Visual/Model")
	check(model != null and model.skeleton != null, "player has a skinned model")
	check_eq(model.skeleton.get_bone_count(), 17, "humanoid skeleton")
	check_eq(model.appearance.outfit.id, &"player_survivor", "distinct survivor outfit")
	check(not player.get_node("Visual").has_node("Body"), "the old capsule is gone")
	check(await wait_physics_until(func(): return animator.clip() == &"idle", 30), "idle while standing")
	ctrl.scripted_mode = MovementComponent.Mode.WALK
	ctrl.scripted_direction = Vector3.RIGHT
	check(await wait_physics_until(func(): return animator.clip() == &"walk", 30), "walk clip while walking")
	var q0 := model.bone_pose_rotation(&"thigh_l")
	await physics_frames(12)
	check(not model.bone_pose_rotation(&"thigh_l").is_equal_approx(q0), "legs actually move")
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	check(await wait_physics_until(func(): return animator.clip() == &"jog", 30), "jog clip")
	ctrl.scripted_mode = MovementComponent.Mode.SNEAK
	check(await wait_physics_until(func(): return animator.clip() == &"sneak", 40), "sneak clip (crouched)")
	var hips_y := model.bone_global_position(&"hips").y - player.global_position.y
	await physics_frames(20)
	hips_y = model.bone_global_position(&"hips").y - player.global_position.y
	check_lt(hips_y, 0.85, "crouched hips (%.2f)" % hips_y)
	ctrl.scripted_direction = Vector3.ZERO
	check(await wait_physics_until(func(): return animator.clip() == &"sneak_idle", 60), "crouched idle")


func test_weapon_on_hand_bone_and_swing_clips() -> void:
	var vis: MeleeVisuals = player.get_node("CombatVisuals")
	var ba := vis.weapon_pivot.get_parent() as BoneAttachment3D
	check(ba != null and ba.bone_name == "hand_r", "weapon pivot on the right hand bone")
	check(vis.on_hand_bone, "procedural sweep disabled")
	var bat := ItemDB.instance(&"baseball_bat")
	check(player.equip_item(bat).get("ok", false), "bat equipped")
	await physics_frames(2)
	check(vis.weapon_mesh.visible, "bat visible in the hand")
	check(combat.attack_now(1.0), "swing")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.WINDUP and animator.clip() == &"windup_2h", 30), "two-handed windup clip")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.ACTIVE, 60), "active")
	await physics_frames(1)
	var tip_windup := vis.weapon_mesh.global_position
	check_eq(animator.clip(), &"strike_2h", "strike clip in the active window")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.RECOVERY, 60), "recovery")
	check_gt(vis.weapon_mesh.global_position.distance_to(tip_windup), 0.2, "the bat swings with the arm")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.IDLE, 90), "swing done")
	check(await wait_physics_until(func(): return animator.clip() == &"idle", 20), "back to idle")
	var knife := ItemDB.instance(&"kitchen_knife")
	player.equip_item(knife)
	await physics_frames(2)
	check(combat.attack_now(0.0), "knife swing")
	check(await wait_physics_until(func(): return animator.clip() == &"windup_1h", 30), "one-handed clip for the knife")


func test_bag_hit_and_death_poses() -> void:
	var bag := ItemDB.instance(&"backpack")
	check(player.equip_item(bag, &"back").get("ok", false), "backpack worn")
	await physics_frames(3)
	check(animator.bag_visual != null and animator.bag_visual.visible, "bag shown on the back")
	check((animator.bag_visual.get_parent() as BoneAttachment3D).bone_name == "chest", "…on the chest bone")
	player.unequip_item(bag)
	await physics_frames(2)
	check(not animator.bag_visual.visible, "bag hidden once taken off")
	player.take_damage(5.0, null, {})
	check(await wait_physics_until(func(): return animator.clip() == &"hit", 5), "hit flinch")
	player.take_damage(1000.0, null, {})
	check(await wait_physics_until(func(): return animator.clip() == &"death", 10), "death fall")
	await physics_frames(100)
	var model: CharacterModel = player.get_node("Visual/Model")
	var up := Basis(model.bone_pose_rotation(&"hips")) * Vector3.UP
	check_lt(absf(up.y), 0.4, "the body lies on the ground")


# --- Zombies ------------------------------------------------------------------------

func test_zombie_model_follows_state() -> void:
	var z := spawner.spawn_at(Vector3(0, 0, -5))
	z.snap_facing(PI)  # faces the player at the origin
	await physics_frames(3)
	check(z.visual.model != null and z.visual.model.appearance.zombie, "zombie model")
	check(z.visual.model.appearance.outfit.id != &"player_survivor", "wears a townsperson's outfit")
	check(await wait_physics_until(func(): return z.state() == &"chase", 90), "chases")
	check(await wait_physics_until(func(): return z.visual.clip() == &"z_chase", 60), "chase shamble clip (%s)" % z.visual.clip())
	z.receive_shove(player, {"knockdown": true})
	check(await wait_physics_until(func(): return z.state() == &"knocked_down", 20), "knocked down")
	check_eq(z.visual.clip(), &"z_knockdown", "fall clip")
	check(await wait_physics_until(func(): return z.visual.is_lying(), 60), "lies on the ground")
	var r := z.take_damage(1000.0, player, {})
	check(r.get("dead", false), "killed")
	var corpse := z.corpse
	var vis := corpse.get_node("Visual") as ZombieVisual
	await physics_frames(90)
	check(is_instance_valid(vis) and vis.dead, "corpse keeps the model")
	check_eq(vis.clip(), &"z_knockdown", "killed while down: stays on its back (no pop-up)")
	check(vis.is_lying(), "corpse pose lies on the ground")
	await physics_frames(60)
	check(vis.is_lying(), "…and persists")
	# A standing zombie falls face down with the death clip.
	var z2 := spawner.spawn_at(Vector3(3, 0, -5))
	await physics_frames(3)
	z2.take_damage(1000.0, player, {})
	var vis2 := z2.corpse.get_node("Visual") as ZombieVisual
	check_eq(vis2.clip(), &"z_death", "death fall clip")
	check(await wait_physics_until(func(): return vis2.is_lying(), 90), "falls to the ground")


func test_zombie_crowd_shares_meshes() -> void:
	var assets := CharacterAssets.of(tree)
	var looks := {}
	for i in 24:
		var z := spawner.spawn_at(Vector3(-20 + (i % 6) * 1.5, 0, 12 + (i / 6) * 1.5))
		looks[z.visual.model.appearance.key()] = true
	await physics_frames(2)
	check_gt(float(looks.size()), 8.0, "varied outfits in a crowd (%d looks)" % looks.size())
	check(assets.mesh_count() <= CharacterAssets.ZOMBIE_VARIANTS + 8, "meshes are shared (%d)" % assets.mesh_count())


# --- Vehicles --------------------------------------------------------------------------

func _vehicle(n: String) -> Vehicle:
	return scene.get_node("Vehicles/%s" % n) as Vehicle


func test_vehicles_present_and_varied() -> void:
	var vs := tree.get_nodes_in_group(Vehicle.GROUP).filter(func(v): return scene.is_ancestor_of(v))
	check(vs.size() >= 5, "parked vehicles on the street (%d)" % vs.size())
	var shapes := {}
	for v: Vehicle in vs:
		shapes[v.data.shape] = true
		check_eq(v.collision_layer, 1 | (1 << 5), "%s on world + occluder layers" % v.name)
		check(v.is_in_group(&"occluder"), "%s fades like a prop" % v.name)
	check(shapes.size() >= 3, "several body shapes")
	check_eq(_vehicle("PoliceCar").data.livery, &"police", "a police car")
	check(not scene.has_node("Props/Car"), "the blue box car is gone")


func test_trunk_and_glovebox_searchable() -> void:
	var car := _vehicle("Sedan")
	var trunk := car.trunk
	var out := trunk.global_position - car.global_position
	out.y = 0.0
	out = out.normalized()
	await _teleport(trunk.global_position + out * 0.5 + Vector3.UP * 0.1, BodyHelpers.yaw_for(-out))
	check(interaction.current_target != null and interaction.current_target.body() == trunk, "trunk targeted (%s)" % (interaction.current_target.body() if interaction.current_target else null))
	check_eq(interaction.current_actions[0].label, "Search trunk", "Search trunk action")
	check(interaction.interact().get("ok", false), "search starts")
	check(await wait_physics_until(func(): return trunk.is_open_for(player), 150), "trunk opens")
	check_eq(trunk.table_id, "vehicle_trunk", "vehicle_trunk loot table")
	trunk.close()
	await physics_frames(3)
	var gb := car.glovebox
	var side := gb.global_position - car.global_position
	side = (side - car.global_basis.z * side.dot(car.global_basis.z))
	side.y = 0.0
	side = side.normalized()
	await _teleport(gb.global_position + side * 0.45 + Vector3.UP * 0.1, BodyHelpers.yaw_for(-side))
	check(interaction.current_target != null and interaction.current_target.body() == gb, "glovebox targeted")
	check_eq(interaction.current_actions[0].label, "Search glovebox", "Search glovebox action")
	gb.open(player)
	check_eq(gb.table_id, "vehicle_glovebox", "vehicle_glovebox loot table")
	var pickup := _vehicle("Pickup")
	check_eq(pickup.trunk.search_label, "Search truck bed", "pickups have a truck bed")


func test_vehicle_blocks_player() -> void:
	var car := _vehicle("Van")
	var right := car.global_basis.x
	await _teleport(car.global_position + right * (car.data.width * 0.5 + 1.2) + Vector3.UP * 0.1)
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	ctrl.scripted_direction = -right
	await physics_frames(90)
	ctrl.scripted_direction = Vector3.ZERO
	var local := car.to_local(player.global_position)
	check_gt(absf(local.x), car.data.width * 0.5 + 0.2, "stopped at the side of the van (x %.2f)" % local.x)


func test_navmesh_routes_around_vehicles() -> void:
	var car := _vehicle("Sedan2")
	var right := car.global_basis.x
	var a := car.global_position + right * 2.5
	var b := car.global_position - right * 2.5
	var path := NavigationServer3D.map_get_path(nav.get_navigation_map(), a, b, true)
	check(path.size() >= 2, "a path exists")
	var inside := false
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
		for k in 11:
			var p := car.to_local(path[i].lerp(path[i + 1], k / 10.0))
			if absf(p.x) < car.data.width * 0.5 - 0.05 and absf(p.z) < car.data.length * 0.5 - 0.05:
				inside = true
	check(not inside, "the path never crosses the car")
	check_gt(length, 5.5, "it goes around (%.1f m)" % length)


func test_emergency_lights_at_night() -> void:
	var police := _vehicle("PoliceCar")
	var sedan := _vehicle("Sedan")
	TimeManager.set_time_of_day(12)
	await physics_frames(3)
	check(not police.lights_on, "lights off by day")
	TimeManager.set_time_of_day(23)
	check(await wait_physics_until(func(): return police.lights_on, 30), "police lights on at night")
	check(not sedan.lights_on, "civilian cars stay dark")
	check(police.mesh_instance.get_surface_override_material(police._surfaces[&"head"]) == null, "parked: headlights stay off")
	check(police.beacon_light != null and police.beacon_light.visible, "red / blue light pool")
	check(tree.get_nodes_in_group(Vehicle.BEACON_GROUP).size() <= Vehicle.MAX_BEACON_LIGHTS, "light budget")
	var c0 := police.beacon_light.light_color
	check(await wait_physics_until(func(): return not police.beacon_light.light_color.is_equal_approx(c0), 60), "the light alternates colour")
	TimeManager.set_time_of_day(12)
	check(await wait_physics_until(func(): return not police.lights_on, 30), "off again by day")
	check(not police.beacon_light.visible, "light pool off by day")


func test_faded_vehicle_keeps_depth_and_half_alpha() -> void:
	var occl = scene.get_node("OcclusionManager")
	var car := _vehicle("Sedan")
	occl.set_physics_process(false)
	occl.set_process(false)
	occl._transition(car, &"faded")
	await physics_frames(30)
	var m := car.mesh_instance.material_override as StandardMaterial3D
	check(m != null, "fade override")
	check_eq(m.depth_draw_mode, BaseMaterial3D.DEPTH_DRAW_ALWAYS, "writes depth (no x-ray)")
	check(m.albedo_color.a >= 0.49, "alpha floor 0.5 (%.2f)" % m.albedo_color.a)
