extends "res://tests/test_case.gd"
## Round 4 in the real test_ground scene: melee swings (hit / miss /
## multi-target / knockdown / condition / stamina refusal / queued),
## shove, aim, injuries (zombie wounds, bleeding, bandage, leg slow,
## glass), pickup + weapon cycling, HUD and two balance checks.
##
## Layout: player spawns at the origin on open ground; the "Wall" prop is
## an 8 m slab at z = 2 (x -10..-2, 0.3 thick); House A spans x -14..-4,
## z -10..-2 with the bat in the living room (-6.5, -3.2) and the knife in
## the kitchen (-5.2, -8.8). Yaw 0 faces -Z; yaw PI faces +Z.

const BAT := preload("res://data/items/weapons/baseball_bat.tres")
const KNIFE := preload("res://data/items/weapons/kitchen_knife.tres")
const FISTS := preload("res://data/items/weapons/fists.tres")

var scene: Node
var player: Player
var ctrl: PlayerController
var combat: MeleeCombat
var injuries: InjuryComponent
var spawner: ZombieSpawner
var hud: CanvasLayer
var house: HouseBlockout


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	combat = player.get_node("Combat")
	injuries = player.get_node("Injuries")
	hud = scene.get_node("HUD")
	house = scene.get_node("Buildings/HouseA")
	ctrl.scripted = true
	combat.scripted = true
	combat.rng.seed = 11
	injuries.rng.seed = 11
	player.get_node("Interaction").scripted = true
	# Round 5: bandaging consumes dressings from the inventory.
	player.inventory.add_id(&"bandage", 5)
	var nav: NavBaker = scene.get_node("NavRegion")
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


func _spawn(p: Vector3, yaw: float = PI) -> Zombie:
	var z := spawner.spawn_at(p)
	z.snap_facing(yaw)
	await physics_frames(2)
	return z


## A weapon with some numbers overridden (deterministic tests).
func _weapon(base: WeaponData, overrides: Dictionary) -> WeaponData:
	var w: WeaponData = base.duplicate()
	for k in overrides:
		w.set(k, overrides[k])
	return w


func _equip(data: WeaponData) -> ItemInstance:
	var item := ItemInstance.new(data)
	player.pick_up_item(item)
	combat.equip(item)
	return item


func _aim(dir: Vector3) -> void:
	combat.aim_direction = dir
	combat.set_aiming(true)


func _wait_idle(max_frames: int = 120) -> bool:
	return await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.IDLE, max_frames)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Swings -------------------------------------------------------------------

func test_bat_swing_hits_zombie_in_front() -> void:
	var bat := _weapon(BAT, {"crit_chance": 0.0, "head_hit_chance": 0.0, "knockdown_chance": 0.0})
	_equip(bat)
	var z := await _spawn(Vector3(0, 0, -1.0))
	_aim(Vector3.FORWARD)
	var swings := []
	var hits := []
	var sounds := []
	var cb_s := func(a, id, c): swings.append([a, id, c])
	var cb_h := func(a, t, d, i): hits.append([a, t, d, i])
	var cb_n := func(_p, r, _i, cat, _s): sounds.append([cat, r])
	EventBus.melee_swing.connect(cb_s)
	EventBus.melee_hit.connect(cb_h)
	EventBus.sound_emitted.connect(cb_n)
	var st0 := player.stats.get_value(Character.STAMINA)
	var decals: BloodDecals = scene.get_node("BloodDecals")
	check(combat.attack_now(1.0), "swing starts")
	check_near(player.stats.get_value(Character.STAMINA), st0 - bat.stamina_cost, 0.2, "stamina paid at swing start")
	check_eq(swings.size(), 1, "melee_swing once")
	check(swings[0][1] == &"baseball_bat" and is_equal_approx(swings[0][2], 1.3), "…with weapon id and full charge")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.ACTIVE, 40), "active window")
	await frames(1)
	var vis: MeleeVisuals = player.get_node("CombatVisuals")
	check(vis.swing_arc_visible(), "arc mesh visible during the active window")
	check_eq(combat.last_hits.size(), 1, "one target hit")
	check_eq(hits.size(), 1, "melee_hit once")
	var dmg: float = hits[0][2]
	check(dmg >= 12.0 * 1.3 - 0.01 and dmg <= 18.0 * 1.3 + 0.01, "damage in bat range × charge (%.1f)" % dmg)
	check_near(z.health(), 60.0 - dmg, 0.01, "zombie health")
	check(z.visual.is_hit_flashing(), "hit flash")
	check(sounds.any(func(s): return s[0] == &"melee_hit" and is_equal_approx(s[1], bat.noise_radius)), "hit makes noise")
	check_gt(float(decals.count), 0.0, "blood decal")
	await physics_frames(20)
	check_gt(_flat(z.global_position, player.global_position), 1.2, "knocked back")
	check_eq(z.target, player, "the zombie now targets the attacker")
	check(z.state() == &"stunned" or z.state() == &"chase", "heavy hit staggers (%s)" % z.state())
	check(await _wait_idle(), "swing finishes")
	EventBus.melee_swing.disconnect(cb_s)
	EventBus.melee_hit.disconnect(cb_h)
	EventBus.sound_emitted.disconnect(cb_n)


func test_swing_misses_behind_and_through_walls() -> void:
	_equip(_weapon(BAT, {"knockdown_chance": 0.0}))
	var z := await _spawn(Vector3(0, 0, 1.0), 0.0)  # behind the player
	_aim(Vector3.FORWARD)
	var st0 := player.stats.get_value(Character.STAMINA)
	check(combat.attack_now(0.0), "swing")
	check_near(player.stats.get_value(Character.STAMINA), st0 - BAT.stamina_cost, 0.2, "a miss still costs stamina")
	await _wait_idle()
	check(combat.last_hits.is_empty(), "nothing in the arc")
	check_eq(z.health(), 60.0, "zombie behind untouched")
	z.queue_free()
	# Wall prop at z = 2: player south face side, zombie on the far side.
	await _teleport(Vector3(-6, 0.1, 1.45))
	var z2 := await _spawn(Vector3(-6, 0, 2.5), 0.0)
	check_lt(_flat(z2.global_position, player.global_position), 1.4, "within reach")
	_aim(Vector3.BACK)
	check(combat.attack_now(0.0), "swing at the wall")
	await _wait_idle()
	check(combat.last_hits.is_empty(), "no hit through the wall")
	check_eq(z2.health(), 60.0, "zombie behind the wall untouched")


func test_multi_target_bat_vs_knife() -> void:
	var pts := [Vector3(-0.6, 0, -1.0), Vector3(0, 0, -1.1), Vector3(0.6, 0, -1.0)]
	var zs: Array[Zombie] = []
	for p in pts:
		zs.append(await _spawn(p))
	_equip(_weapon(KNIFE, {"crit_chance": 0.0, "head_hit_chance": 0.0}))
	_aim(Vector3.FORWARD)
	check(combat.attack_now(0.0), "knife swing")
	await _wait_idle()
	check_eq(combat.last_hits.size(), 1, "knife: one target")
	check(combat.last_hits[0].target == zs[1], "…the one straight ahead")
	for z in zs:
		z.queue_free()
	await physics_frames(2)
	zs.clear()
	for p in pts:
		zs.append(await _spawn(p))
	_equip(_weapon(BAT, {"knockdown_chance": 0.0}))
	check(combat.attack_now(0.0), "bat swing")
	await _wait_idle()
	check_eq(combat.last_hits.size(), 2, "bat: two targets (max_targets)")
	var damaged := zs.filter(func(z): return z.health() < 60.0).size()
	check_eq(damaged, 2, "two of the three damaged")


func test_knockdown_down_multiplier_and_get_up() -> void:
	_equip(_weapon(BAT, {"knockdown_chance": 1.0, "crit_chance": 0.0, "head_hit_chance": 0.0}))
	var z := await _spawn(Vector3(0, 0, -1.0))
	_aim(Vector3.FORWARD)
	var downs := []
	var ups := []
	var cb_d := func(zb, s): downs.append([zb, s])
	var cb_u := func(zb): ups.append(zb)
	EventBus.zombie_knocked_down.connect(cb_d)
	EventBus.zombie_got_up.connect(cb_u)
	var hp_player := player.health.health
	check(combat.attack_now(0.0), "swing")
	check(await wait_physics_until(func(): return z.state() == &"knocked_down", 40), "knocked down")
	check_eq(downs.size(), 1, "zombie_knocked_down event")
	check_eq(downs[0][1], player, "…with the attacker")
	check_near(z.visual.rotation.x, PI * 0.5, 0.01, "visual lies on the ground")
	var hp := z.health()
	var r := z.take_damage(10.0, player, {})
	check_near(hp - z.health(), 15.0, 0.01, "×1.5 damage while down")
	check(r.get("knocked_down", false), "still down after a hit")
	await physics_frames(90)
	check_eq(z.state(), &"knocked_down", "still down after 1.5 s")
	check_near(player.health.health, hp_player, 0.5, "no bites while down")
	check(await wait_physics_until(func(): return z.state() != &"knocked_down", 90), "gets up after 2.5 s")
	check_eq(ups.size(), 1, "zombie_got_up event")
	check_near(z.visual.rotation.x, 0.0, 0.01, "standing again")
	EventBus.zombie_knocked_down.disconnect(cb_d)
	EventBus.zombie_got_up.disconnect(cb_u)


func test_shove_cancels_windup_and_pushes_back() -> void:
	combat.shove_weapon = _weapon(combat.shove_weapon, {"knockdown_chance_vs_windup": 0.0})
	var z := await _spawn(Vector3(0, 0, -0.85))
	check(await wait_physics_until(func(): return z.is_winding_up(), 120), "zombie winds up a bite")
	var hp0 := player.health.health
	var st0 := player.stats.get_value(Character.STAMINA)
	var d0 := _flat(z.global_position, player.global_position)
	_aim(Vector3.FORWARD)
	check(combat.shove(), "shove")
	check_near(player.stats.get_value(Character.STAMINA), st0 - 5.0, 0.2, "shove costs 5 stamina")
	check(await wait_physics_until(func(): return not z.is_winding_up(), 20), "windup cancelled")
	check_eq(z.state(), &"stunned", "staggered")
	check_eq(z.visual.lunge, 0.0, "lunge reset")
	await physics_frames(30)
	check_near(player.health.health, hp0, 0.3, "the bite never landed")
	check_gt(_flat(z.global_position, player.global_position) - d0, 0.8, "pushed back ~1.2 m")
	check_eq(z.health(), 60.0, "shove deals no damage")
	# A shove with guaranteed knockdown floors it.
	await _wait_idle()
	combat.shove_weapon = _weapon(combat.shove_weapon, {"knockdown_chance": 1.0, "knockdown_chance_vs_windup": 1.0, "reach": 3.0})
	check(combat.shove(), "second shove")
	check(await wait_physics_until(func(): return z.state() == &"knocked_down", 30), "knocked down by a shove")


func test_stamina_refusal() -> void:
	_equip(BAT)
	var refusals := []
	var cb := func(a, r): refusals.append([a, r])
	EventBus.attack_refused.connect(cb)
	player.stats.set_value(Character.STAMINA, 4.0)
	check(not combat.attack_now(1.0), "bat refused at 4 stamina")
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "no swing")
	check(refusals.size() == 1 and refusals[0][1] == "Too tired to swing", "attack_refused reason")
	await frames(1)
	check_eq(hud.notice_label.text, "Too tired to swing", "HUD notice")
	check(not combat.shove(), "shove refused too")
	check_eq(refusals[-1][1], "Too tired to shove", "shove reason")
	combat.equip(null)
	check(combat.attack_now(0.0), "fists (2 stamina) still work")
	EventBus.attack_refused.disconnect(cb)


func test_condition_loss_and_break() -> void:
	var fragile := _weapon(BAT, {"max_condition": 2, "condition_loss_chance": 1.0, "knockdown_chance": 0.0, "crit_chance": 0.0, "head_hit_chance": 0.0, "damage_min": 5.0, "damage_max": 5.0})
	var item := _equip(fragile)
	_aim(Vector3.FORWARD)
	var broken := []
	var cb := func(a, it): broken.append(it)
	EventBus.weapon_broken.connect(cb)
	# A miss does not wear the weapon.
	check(combat.attack_now(0.0), "miss")
	await _wait_idle()
	check_eq(item.condition, 2, "no wear on a miss")
	var z := await _spawn(Vector3(0, 0, -1.0))
	check(combat.attack_now(0.0), "hit 1")
	await _wait_idle()
	check_eq(item.condition, 1, "lost one point")
	await frames(1)
	check(hud.weapon_label.text.contains("(1/2)"), "HUD condition (%s)" % hud.weapon_label.text)
	z.global_position = Vector3(0, 0.05, -1.0)
	await physics_frames(2)
	check(combat.attack_now(0.0), "hit 2")
	await _wait_idle()
	check(item.is_broken(), "broken")
	check_eq(broken.size(), 1, "weapon_broken once")
	check(combat.equipped == null and combat.weapon() == combat.fists, "back to fists")
	check(not player.inventory.has(item), "broken weapon dropped from the inventory")
	await frames(1)
	check_eq(hud.weapon_label.text, "Weapon: Fists", "HUD shows fists")
	check(hud.notice_label.text.contains("broke"), "HUD notice")
	EventBus.weapon_broken.disconnect(cb)


func test_queued_attack_during_recovery() -> void:
	combat.equip(null)
	var swings := []
	var cb := func(a, id, c): swings.append(c)
	EventBus.melee_swing.connect(cb)
	check(combat.attack_now(0.0), "first swing")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.RECOVERY, 40), "recovery")
	check(combat.start_attack(), "press during recovery is queued")
	check(combat.release_attack(), "release queued")
	check_eq(swings.size(), 1, "not yet")
	check(await wait_physics_until(func(): return swings.size() == 2, 40), "queued swing fires after recovery")
	await _wait_idle()
	# Held through the recovery: keeps charging, swings on release.
	check(combat.attack_now(0.0), "third")
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.RECOVERY, 40), "recovery")
	combat.start_attack()
	check(await wait_physics_until(func(): return combat.phase == MeleeCombat.Phase.CHARGING, 40), "charging after recovery")
	await physics_frames(30)
	combat.release_attack()
	check_eq(swings.size(), 4, "charged queued swing")
	check_gt(swings[-1], 0.6, "charge counted from the press")
	EventBus.melee_swing.disconnect(cb)


# --- Aim --------------------------------------------------------------------------

func test_aim_mouse_projection_facing_walk_cap_and_reach_count() -> void:
	var cam := player.get_viewport().get_camera_3d()
	check(cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "orthographic camera")
	var world := player.global_position + Vector3(2.0, 0.0, -1.0)
	world.y = player.global_position.y
	var screen := cam.unproject_position(world)
	var back := PlayerCombatInput.ground_point(cam, screen, player.global_position.y)
	check_lt(back.distance_to(world), 0.05, "mouse → ground round trip (got %s)" % str(back))
	var other := PlayerCombatInput.ground_point(cam, screen + Vector2(40, 0), player.global_position.y)
	check_gt(other.distance_to(back), 0.1, "a different pixel is a different ground point (ortho origin moves)")
	_aim(Vector3.RIGHT)
	await physics_frames(20)
	check_gt(player.facing_vector().dot(Vector3.RIGHT), 0.99, "faces the aim")
	await frames(1)
	check_eq(hud.aim_label.text, "Aiming — 0 in reach", "HUD aim label")
	var vis: MeleeVisuals = player.get_node("CombatVisuals")
	check(vis.ring.visible, "ring at reach while aiming")
	await _spawn(Vector3(0.7, 0, 0.1), -PI * 0.5)
	check(await wait_physics_until(func(): return combat.in_reach == 1, 20), "1 in reach")
	await frames(1)
	check_eq(hud.aim_label.text, "Aiming — 1 in reach", "HUD count")
	ctrl.scripted_mode = MovementComponent.Mode.SPRINT
	ctrl.scripted_direction = Vector3.BACK
	await physics_frames(40)
	check_eq(player.effective_mode, MovementComponent.Mode.WALK, "aiming walks")
	check_lt(player.speed(), 2.05, "walk speed")
	check_gt(player.facing_vector().dot(Vector3.RIGHT), 0.99, "still facing the aim while walking")
	ctrl.scripted_direction = Vector3.ZERO
	combat.set_aiming(false)
	await frames(1)
	check_eq(hud.aim_label.text, "", "label cleared")
	check(not vis.ring.visible, "ring hidden")


# --- Injuries ------------------------------------------------------------------------

func test_zombie_attack_inflicts_region_injury_and_infection() -> void:
	var z := await _spawn(Vector3(0, 0, -1.1))
	var hp0 := player.health.health
	check(await wait_physics_until(func(): return player.health.health < hp0, 60 * 4), "bitten")
	check_eq(injuries.injuries.size(), 1, "one wound")
	var inj: Injury = injuries.injuries[0]
	check(z.profile.attack_region_weights.has(inj.region_id()), "region from the zombie weights (%s)" % inj.region_id())
	check(z.profile.attack_type_weights.has(inj.type_id()), "type from the zombie weights (%s)" % inj.type_id())
	await frames(1)
	check(hud.injury_label.text.contains(inj.label()), "HUD lists the wound (%s)" % hud.injury_label.text)
	z.queue_free()
	await physics_frames(2)
	var r := player.take_damage(5.0, null, {"region": &"left_hand", "type": &"bite", "infectious": true})
	check(r.ok, "bite")
	check(injuries.infected, "bites always infect")
	var inf0 := injuries.infection()
	injuries.tick(100.0)
	check_near(injuries.infection() - inf0, 2.0, 0.05, "infection rises slowly (2 % per 100 s)")
	await frames(1)
	check(not hud.infected_label.visible, "infection hidden before symptoms (%.1f)" % injuries.infection())
	player.stats.set_value(InjuryComponent.INFECTION, 30.0)
	await frames(1)
	check(hud.infected_label.visible and hud.infected_label.text == "Feverish", "Feverish at 30")
	player.stats.set_value(InjuryComponent.INFECTION, 70.0)
	await frames(1)
	check(hud.infected_label.text == "Infected", "Infected at 70")
	check_gt(hud.infected_label.get_theme_color(&"font_color").r, 0.9, "red, never green")
	check_lt(hud.infected_label.get_theme_color(&"font_color").g, 0.5, "…not green")
	check(hud.pain_label.text.begins_with("Pain ") and not hud.pain_label.text.ends_with(" 0%"), "pain shown (%s)" % hud.pain_label.text)
	# Non-infectious damage (a fall, glass) never infects.
	var clean := Injury.new()
	check(not clean.infected, "default clean")
	player.stats.set_value(InjuryComponent.INFECTION, 100.0)
	var hp := player.health.health
	injuries.tick(2.0)
	check_lt(player.health.health, hp - 0.9, "full infection drains health")


func test_bleeding_drains_health_and_stops() -> void:
	var decals: BloodDecals = scene.get_node("BloodDecals")
	var inj := injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	check(inj.bleeding, "laceration bleeds")
	await frames(1)
	check(hud.injury_label.text.contains("Left arm — Laceration  BLEEDING"), "HUD marks bleeding (%s)" % hud.injury_label.text)
	var hp0 := player.health.health
	var n0 := decals.count
	var flashes := []
	var cb := func(c, a, s, i): flashes.append(a)
	EventBus.character_damaged.connect(cb)
	injuries.tick(10.0)
	check_near(player.health.health, hp0 - injuries.profile.laceration.bleed_rate * 10.0, 0.05, "bleeding drains health")
	check(flashes.is_empty(), "bleeding is not a hit (no flash / injury)")
	check_gt(float(decals.count), float(n0), "blood drips")
	await frames(1)
	check_near(hud.health_bar.value, player.health.health, 0.5, "HUD health follows the drain")
	var hp1 := player.health.health
	await physics_frames(60)
	check_lt(player.health.health, hp1, "drains in real time too")
	injuries.tick(injuries.profile.laceration.bleed_seconds)
	check(not inj.bleeding, "stops on its own after bleed_seconds")
	EventBus.character_damaged.disconnect(cb)
	var hp2 := player.health.health
	injuries.tick(5.0)
	check_near(player.health.health, hp2, 0.001, "no more drain")
	# The decal pool never grows past max_decals (oldest splats are reused).
	for i in decals.max_decals + 50:
		decals.add_splat(Vector3(float(i % 20), 0.0, float(i / 20)), 0.5)
	check_eq(decals.count, 200, "pool capped at 200")
	check_eq(decals.multimesh.instance_count, 200, "one multimesh of 200")
	check_eq(decals.multimesh.visible_instance_count, 200, "all visible")


func test_bandage_worst_bleeding_takes_4s() -> void:
	var scratch := injuries.add_injury(Injury.Region.LEFT_HAND, Injury.Type.SCRATCH)
	var deep := injuries.add_injury(Injury.Region.LEFT_LEG, Injury.Type.DEEP_WOUND)
	var started := []
	var cb := func(c, r, s): started.append([r, s])
	EventBus.bandage_started.connect(cb)
	var r := injuries.bandage_worst()
	check(r.ok and r.region == &"left_leg", "worst bleeding wound first (%s)" % str(r))
	check(started.size() == 1 and is_equal_approx(started[0][1], 4.0), "bandage_started with 4 s")
	check(player.is_busy, "busy while bandaging")
	var p0 := player.global_position
	ctrl.scripted_direction = Vector3.FORWARD
	await physics_frames(60 * 3 + 30)
	check(not deep.bandaged, "not done after 3.5 s")
	check_lt(_flat(player.global_position, p0), 0.01, "can't walk while bandaging")
	check(not combat.attack_now(0.0), "can't swing while bandaging")
	check(await wait_physics_until(func(): return deep.bandaged, 60), "bandaged after 4 s")
	ctrl.scripted_direction = Vector3.ZERO
	check(not deep.bleeding, "bleeding stopped")
	check(not player.is_busy, "free again")
	await frames(1)
	check(hud.injury_label.text.contains("Left leg — Deep wound  (bandaged)"), "HUD (%s)" % hud.injury_label.text)
	# Second one through the real input action (B).
	combat.scripted = false
	var ev := InputEventAction.new()
	ev.action = &"bandage"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	ev = InputEventAction.new()
	ev.action = &"bandage"
	ev.pressed = false
	Input.parse_input_event(ev)
	check(player.is_busy and injuries.bandaging == scratch, "B bandages the scratch")
	check(await wait_physics_until(func(): return scratch.bandaged, 60 * 5), "done")
	combat.scripted = true
	r = injuries.bandage_worst()
	check(not r.ok and r.reason == "Nothing to bandage", "nothing left")
	EventBus.bandage_started.disconnect(cb)


func test_leg_injury_slows_and_wounds_cut_max_stamina() -> void:
	ctrl.scripted_direction = Vector3.FORWARD
	await physics_frames(40)
	var v0 := player.speed()
	check_near(v0, 3.4, 0.1, "jogging")
	injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	await physics_frames(30)
	check_near(player.speed(), v0, 0.05, "arm wound: same speed")
	injuries.add_injury(Injury.Region.RIGHT_LEG, Injury.Type.LACERATION)
	await physics_frames(40)
	var m := injuries.profile.laceration.leg_speed_multiplier
	check_near(player.movement.speed_modifiers.get(&"injury", 1.0), m, 0.001, "movement modifier &injury")
	check_near(player.speed(), 3.4 * m, 0.1, "leg wound slows")
	ctrl.scripted_direction = Vector3.ZERO
	check_near(player.stats.get_max(Character.STAMINA), 100.0 - 2.0 * injuries.profile.laceration.max_stamina_penalty, 0.01, "max stamina lowered")
	check_near(player.stats.get_value(InjuryComponent.PAIN), 2.0 * injuries.profile.laceration.pain, 0.01, "pain stat")


func test_smashed_window_climb_lacerates() -> void:
	var win: HouseWindow = null
	for w in house.windows:
		if (w.global_position - Vector3(-14, 0, -4)).length() < 0.3:
			win = w
	check(win != null, "living room west window")
	# 40 % in play (data); forced here to test the cut itself.
	injuries.profile = injuries.profile.duplicate()
	injuries.profile.glass_laceration_chance = 1.0
	win.smash()
	await _teleport(Vector3(-13.3, 0.1, -4))
	var hp0 := player.health.health
	check(win.climb(player).ok, "climb")
	check(await wait_physics_until(func(): return not player.is_busy, 90), "climbed")
	await physics_frames(2)
	check_eq(injuries.injuries.size(), 1, "one cut")
	var inj: Injury = injuries.injuries[0]
	check_eq(inj.type, Injury.Type.LACERATION, "laceration")
	check(injuries.profile.glass_region_weights.has(inj.region_id()), "hand / arm / leg (%s)" % inj.region_id())
	check(not inj.infected, "glass does not infect")
	check_near(player.health.health, hp0 - injuries.profile.glass_damage, 0.1, "glass damage")


# --- Pickup / cycle ---------------------------------------------------------------------

func test_pickup_and_cycle_weapons() -> void:
	var interaction: PlayerInteraction = player.get_node("Interaction")
	await _teleport(Vector3(-6.5, 0.1, -2.5))
	player.movement.facing = BodyHelpers.yaw_for(Vector3(0, 0, -1))
	await physics_frames(3)
	check(interaction.current_target != null, "bat targeted")
	check_eq(interaction.current_target.display_name(), "Baseball Bat", "name")
	check_eq(interaction.current_actions[0].label, "Pick up Baseball Bat", "action label")
	var body := interaction.current_target.body() as WorldItem
	check(body != null and body.collision_layer == 8, "world item on layer 4")
	check(interaction.interact().ok, "picked up")
	await physics_frames(2)
	check(not is_instance_valid(body), "world item removed")
	check_eq(player.held_weapons().size(), 1, "carried")
	check(player.equipment.primary() == player.held_weapons()[0], "the bat is in the hands")
	check_near(player.carried_weight(), BAT.weight + 0.5, 0.001, "carried weight = bat + setup bandages")
	check(combat.weapon() == BAT, "auto-equipped (hands were empty)")
	await frames(1)
	check_eq(hud.weapon_label.text, "Weapon: Baseball Bat  (12/12)", "HUD weapon + condition")
	await _teleport(Vector3(-5.2, 0.1, -8.2))
	player.movement.facing = BodyHelpers.yaw_for(Vector3(0, 0, -1))
	await physics_frames(3)
	check(interaction.current_target != null and interaction.current_target.display_name() == "Kitchen Knife", "knife targeted")
	check(interaction.interact().ok, "knife picked up")
	check(combat.weapon() == BAT, "bat stays equipped")
	player.cycle_weapon()
	check(combat.weapon() == KNIFE, "X → knife")
	player.cycle_weapon()
	check(combat.weapon() == combat.fists, "X → fists")
	# Real input action.
	combat.scripted = false
	var ev := InputEventAction.new()
	ev.action = &"cycle_weapon"
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	ev = InputEventAction.new()
	ev.action = &"cycle_weapon"
	ev.pressed = false
	Input.parse_input_event(ev)
	combat.scripted = true
	check(combat.weapon() == BAT, "X (input map) → bat")
	await frames(1)
	check(hud.weapon_label.text.begins_with("Weapon: Baseball Bat"), "HUD follows")


# --- Balance ---------------------------------------------------------------------------

func test_balance_surrounded_player_dies_within_30s() -> void:
	await _teleport(Vector3(20, 0.1, 20))
	for d in [Vector3(0, 0, -0.8), Vector3(0, 0, 0.8), Vector3(0.8, 0, 0), Vector3(-0.8, 0, 0)]:
		var z := await _spawn(player.global_position + d)
		z.face_toward(player.global_position)
		z.snap_facing(z.movement.facing)
	var t0 := Engine.get_physics_frames()
	var died := await wait_physics_until(func(): return player.is_dead(), 60 * 30)
	var secs := (Engine.get_physics_frames() - t0) / 60.0
	check(died, "surrounded player dies (health %.0f)" % player.health.health)
	check_lt(secs, 30.0, "within 30 s (took %.1f s)" % secs)
	check_gt(secs, 3.0, "…but not instantly (%.1f s)" % secs)
	check_gt(float(injuries.injuries.size()), 2.0, "wounds accumulated")


# --- Critic regressions (Round 4) -------------------------------------------

func test_b1_interrupted_swing_drops_queue() -> void:
	combat.equip(null)
	injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	var swings := []
	var cb := func(a, id, c): swings.append(id)
	EventBus.melee_swing.connect(cb)
	check(combat.attack_now(0.0), "swing")
	check(combat.start_attack() and combat.release_attack(), "queue a follow-up")
	check(combat.shove(), "…and a shove over it")
	check(injuries.bandage_worst().ok, "bandage during the windup")
	await physics_frames(2)
	check_eq(combat.phase, MeleeCombat.Phase.IDLE, "swing interrupted")
	check(not combat.swing.queued, "queue cleared")
	check(await wait_physics_until(func(): return not player.is_busy, 60 * 5), "bandaged")
	await physics_frames(30)
	check_eq(swings.size(), 1, "no queued swing fired after the bandage")
	var st0 := player.stats.get_value(Character.STAMINA)
	check(combat.attack_now(0.0), "one attack")
	check_near(player.stats.get_value(Character.STAMINA), st0 - FISTS.stamina_cost, 0.05, "exactly one stamina charge")
	await _wait_idle()
	await physics_frames(30)
	check_eq(swings.size(), 2, "exactly one more swing")
	EventBus.melee_swing.disconnect(cb)


func test_b2_no_weapon_swap_to_dodge_wear() -> void:
	var a := _equip(_weapon(BAT, {"condition_loss_chance": 1.0, "knockdown_chance": 0.0, "damage_min": 2.0, "damage_max": 2.0}))
	var knife := ItemInstance.new(KNIFE)
	player.pick_up_item(knife)
	await _spawn(Vector3(0, 0, -1.0))
	_aim(Vector3.FORWARD)
	var refusals := []
	var cb := func(_a, r): refusals.append(r)
	EventBus.attack_refused.connect(cb)
	check(combat.attack_now(0.0), "swing")
	check(not player.cycle_weapon(), "X refused mid-swing")
	check(refusals.has("Mid-swing"), "reason Mid-swing")
	check(combat.weapon() == a.data, "still the bat")
	# Even a programmatic swap mid-windup cannot dodge the wear.
	combat.equip(knife)
	await _wait_idle()
	check_eq(combat.last_hits.size(), 1, "the bat swing hit")
	check_eq(a.condition, a.data.max_condition - 1, "wear landed on the swung bat")
	check_eq(knife.condition, KNIFE.max_condition, "knife untouched")
	check(player.cycle_weapon(), "X works when idle")
	await frames(1)
	check(hud.notice_label.text == "Mid-swing" or refusals.size() == 1, "HUD refusal shown")
	EventBus.attack_refused.disconnect(cb)


func test_b3_knockdown_keeps_its_knockback() -> void:
	combat.shove_weapon = _weapon(combat.shove_weapon, {"knockdown_chance": 1.0, "knockdown_chance_vs_windup": 1.0})
	var z := await _spawn(Vector3(0, 0, -1.0))
	z.senses.enabled = false
	var d0 := _flat(z.global_position, player.global_position)
	_aim(Vector3.FORWARD)
	check(combat.shove(), "shove")
	check(await wait_physics_until(func(): return z.state() == &"knocked_down", 30), "knocked down")
	await physics_frames(30)
	check_gt(_flat(z.global_position, player.global_position) - d0, 1.0, "still slid ≥ 1 m while going down")


func test_swing_blocked_by_closed_door_and_window_pane() -> void:
	_equip(_weapon(BAT, {"knockdown_chance": 0.0}))
	# Front door (closed leaf on layer 7) at z = -2, x -11.45..-10.55.
	await _teleport(Vector3(-11, 0.1, -2.6))
	var z := await _spawn(Vector3(-11, 0, -1.35), 0.0)
	z.senses.enabled = false
	check_lt(_flat(z.global_position, player.global_position), 1.4, "within reach")
	_aim(Vector3.BACK)
	check(combat.attack_now(0.0), "swing at the door")
	await _wait_idle()
	check(combat.last_hits.is_empty(), "no hit through a closed door")
	check_eq(z.health(), 60.0, "untouched")
	z.queue_free()
	# Living-room west window (pane on layer 8 while closed).
	var win: HouseWindow = null
	for w in house.windows:
		if (w.global_position - Vector3(-14, 0, -4)).length() < 0.3:
			win = w
	await _teleport(Vector3(-13.45, 0.1, -4))
	var z2 := await _spawn(Vector3(-14.6, 0, -4), -PI * 0.5)
	z2.senses.enabled = false
	_aim(Vector3.LEFT)
	check(combat.attack_now(0.0), "swing at the closed window")
	await _wait_idle()
	check(combat.last_hits.is_empty(), "no hit through a closed pane")
	check(win.open_window().ok, "open it")
	await physics_frames(3)
	check(combat.attack_now(0.0), "swing through the open window")
	await _wait_idle()
	check_eq(combat.last_hits.size(), 1, "hits once the pane is gone (hit height clears the sill)")


func test_damage_interrupts_bandage_and_fractures_refused() -> void:
	var interrupted := []
	var cb := func(c, r): interrupted.append(r)
	EventBus.bandage_interrupted.connect(cb)
	var inj := injuries.add_injury(Injury.Region.LEFT_LEG, Injury.Type.LACERATION)
	check(injuries.bandage_worst().ok, "bandaging")
	await physics_frames(60)
	check_gt(hud.bandage_bar.value, 10.0, "HUD bandage progress")
	check(hud.bandage_bar.visible, "progress bar visible")
	player.take_damage(3.0, null, {"region": &"head", "type": &"scratch"})
	await frames(1)
	check(not player.is_busy, "bandaging interrupted by damage")
	check(not inj.bandaged, "wound not bandaged")
	check_eq(interrupted.size(), 1, "bandage_interrupted event")
	check_eq(hud.notice_label.text, "Interrupted", "HUD notice")
	await physics_frames(60 * 5)
	check(not inj.bandaged, "the cancelled tween never completes")
	EventBus.bandage_interrupted.disconnect(cb)
	# Only bleeding, bandageable wounds count: a fracture is refused.
	injuries.injuries.clear()
	injuries.add_injury(Injury.Region.RIGHT_LEG, Injury.Type.FRACTURE)
	var r := injuries.bandage_worst()
	check(not r.ok and r.reason == "Nothing to bandage", "fracture needs a splint, not a bandage")


func test_stagger_immunity_and_knife_never_staggers() -> void:
	var z := await _spawn(Vector3(0, 0, -1.0))
	z.take_damage(16.5, player, {})
	check_eq(z.state(), &"stunned", "first heavy hit staggers")
	await physics_frames(36)
	check(z.state() != &"stunned", "short stun (0.5 s)")
	z.take_damage(16.5, player, {})
	check(z.state() != &"stunned", "no re-stagger within 1.2 s (%s)" % z.state())
	await physics_frames(60)
	z.take_damage(6.0, player, {"region": &"head", "stagger": false})
	check(z.state() != &"stunned", "a knife hit (stagger false) never stuns, even 18 on the head")
	z.stats.set_value(Zombie.HEALTH, 60.0)
	z.take_damage(16.5, player, {})
	check_eq(z.state(), &"stunned", "staggerable again after the immunity window")


func test_pain_slows_and_weakens_swings() -> void:
	combat.equip(null)
	player.stats.set_value(InjuryComponent.PAIN, 90.0)
	check(combat.attack_now(0.0), "swing in pain")
	check_near(combat.swing.time_scale, 1.3, 0.001, "severe pain: swing ×1.3")
	check_near(combat.phase_left, FISTS.windup_time() * 1.3, 0.02, "longer windup")
	check_near(combat.pain_modifiers().x, 0.7, 0.0001, "damage ×0.7")
	await _wait_idle()
	player.stats.set_value(InjuryComponent.PAIN, 0.0)
	check(combat.attack_now(0.0), "swing without pain")
	check_near(combat.swing.time_scale, 1.0, 0.001, "normal")


func test_hud_charge_meter_stamina_format_and_idle() -> void:
	combat.equip(null)
	check(combat.start_attack(), "charging")
	await physics_frames(30)
	await frames(1)
	check(hud.charge_bar.visible and hud.charge_bar.value > 30.0, "charge meter (%.0f)" % hud.charge_bar.value)
	combat.release_attack()
	await frames(1)
	check(not hud.charge_bar.visible, "hidden after release")
	await _wait_idle()
	await physics_frames(20)
	await frames(1)
	check(hud.mode_label.text.begins_with("Idle"), "Idle when standing (%s)" % hud.mode_label.text)
	check(not hud.stamina_label.text.contains("max"), "no max suffix unwounded (%s)" % hud.stamina_label.text)
	injuries.add_injury(Injury.Region.UPPER_TORSO, Injury.Type.FRACTURE)
	await frames(1)
	check(hud.stamina_label.text.contains(" · max 85 %"), "max suffix when wounded (%s)" % hud.stamina_label.text)
	check(hud.stamina_label.text.begins_with("Stamina "), "format")
	ctrl.scripted_direction = Vector3.FORWARD
	await physics_frames(20)
	await frames(1)
	check_eq(hud.mode_label.text, "Jog", "mode when moving")
	ctrl.scripted_direction = Vector3.ZERO


func _reset_player(p: Vector3) -> void:
	for z in spawner.zombies:
		if is_instance_valid(z):
			z.queue_free()
	spawner.zombies.clear()
	await physics_frames(2)
	combat.cancel_charge()
	combat.set_aiming(false)
	await _wait_idle()
	player.health.revive(true)
	player.end_busy()
	injuries.injuries.clear()
	injuries.infected = false
	injuries._changed()
	player.stats.set_value(InjuryComponent.INFECTION, 0.0)
	player.stats.set_value(Character.STAMINA, 100.0)
	await _teleport(p)


## The critic's bot: stands still, aims at the nearest zombie, swings with
## a 0.35 s charge when one is in reach, shoves when one winds up a bite.
## Returns the fraction of health lost (1.0 when killed).
func _bot_fight(n: int, seed_value: int, max_seconds: float = 30.0) -> Dictionary:
	var origin := Vector3(10, 0.1, 10)
	await _reset_player(origin)
	combat.rng.seed = seed_value
	injuries.rng.seed = seed_value
	spawner.rng.seed = seed_value * 101
	var zs: Array[Zombie] = []
	for i in n:
		var a := (float(i) - (n - 1) * 0.5) * 0.7
		var z := spawner.spawn_at(origin + Vector3(sin(a), 0, -cos(a)) * 4.0)
		zs.append(z)
	await physics_frames(2)
	for z in zs:
		z.ai.force_target(player)
	var hp0 := player.health.health
	var reach := combat.weapon().reach
	for i in int(max_seconds * 60.0):
		await tree.physics_frame
		if player.is_dead():
			break
		var alive := zs.filter(func(z): return is_instance_valid(z) and not z.dead)
		if alive.is_empty():
			break
		var nearest: Zombie = null
		var nd := INF
		var winding := false
		for z in alive:
			var d := _flat(z.global_position, player.global_position)
			if d < nd:
				nd = d
				nearest = z
			if z.is_winding_up() and d <= 1.3:
				winding = true
		var to := nearest.global_position - player.global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			combat.aim_direction = to.normalized()
		if not combat.aiming:
			combat.set_aiming(true)
		match combat.phase:
			MeleeCombat.Phase.IDLE:
				if winding:
					combat.shove()
				elif nd <= reach + 0.2:
					combat.start_attack()
			MeleeCombat.Phase.CHARGING:
				if combat.charge_time >= 0.35:
					combat.release_attack()
	var killed := zs.all(func(z): return not is_instance_valid(z) or z.dead)
	var lost := 1.0 if player.is_dead() else (hp0 - player.health.health) / player.health.max_health
	return {"lost": lost, "dead": player.is_dead(), "killed": killed}


func test_balance_bot_bat_vs_one_zombie_costs_5_to_35_percent() -> void:
	_equip(BAT)
	var total := 0.0
	var parts: PackedStringArray = []
	for s in range(1, 6):
		var r: Dictionary = await _bot_fight(1, s)
		check(r.killed and not r.dead, "seed %d: bot wins 1v1 (%s)" % [s, str(r)])
		total += r.lost
		parts.append("%d%%" % int(round(r.lost * 100.0)))
	var avg := total / 5.0
	check(avg >= 0.05 and avg <= 0.35, "1v1 bat costs 5–35 %% on average (avg %.0f %%: %s)" % [avg * 100.0, ", ".join(parts)])
	print("BALANCE 1v1: avg %.0f%% (%s)" % [avg * 100.0, ", ".join(parts)])


func test_balance_bot_three_zombies_is_deadly() -> void:
	_equip(BAT)
	var parts: PackedStringArray = []
	for s in range(1, 6):
		var r: Dictionary = await _bot_fight(3, s)
		parts.append("%d%%%s" % [int(round(r.lost * 100.0)), " dead" if r.dead else ""])
		check(r.dead or r.lost > 0.5, "seed %d: 3 zombies cost > 50 %% or kill (%s)" % [s, str(r)])
	print("BALANCE 3v1: ", ", ".join(parts))
