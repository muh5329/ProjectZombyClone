extends "res://tests/test_case.gd"
## Round 7 in the real test_ground scene: world time → needs → moodles,
## eating (tools, portions, interruption), drinking + the empty bottle,
## sinks, starvation, rotten food, the fridge, sleep / rest on the House A
## bed and sofa, fast-forward, day / night lighting.
##
## Layout: House A x -14..-4, z -10..-2. Bed (bedroom) centre
## (-10.75, -8.85), 1.4 × 2 m; kitchen sink (-4.4, -6.7) facing -X; sofa
## (-7.2, -4.75) facing +Z; fridge = container "HouseA/kitchen/2".

var scene: Node
var player: Player
var ctrl: PlayerController
var interaction: PlayerInteraction
var needs: NeedsComponent
var consume: ConsumeAction
var rest: RestComponent
var hud: CanvasLayer
var window: LootWindow
var spawner: ZombieSpawner


func setup() -> void:
	scene = await spawn_scene("res://maps/test_ground.tscn")
	spawner = scene.get_node("Zombies")
	spawner.auto_spawn = false
	player = scene.get_node("Player")
	ctrl = player.get_node("Controller")
	interaction = player.get_node("Interaction")
	needs = player.get_node("Needs")
	consume = player.get_node("Consume")
	rest = player.get_node("Rest")
	hud = scene.get_node("HUD")
	window = scene.get_node("LootWindow")
	ctrl.scripted = true
	interaction.scripted = true
	player.get_node("Combat").scripted = true
	var nav: NavBaker = scene.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	await physics_frames(3)


func teardown() -> void:
	await despawn(scene)
	Engine.time_scale = 1.0


func _stand(at: Vector3, look_at: Vector3) -> void:
	ctrl.scripted_direction = Vector3.ZERO
	player.global_position = at + Vector3.UP * 0.1
	player.velocity = Vector3.ZERO
	var d := look_at - at
	d.y = 0.0
	player.movement.facing = BodyHelpers.yaw_for(d.normalized())
	await physics_frames(4)


func _target_actions() -> Array:
	return interaction.current_actions if interaction.current_target != null else []


func _action(id: StringName) -> Dictionary:
	for a in _target_actions():
		if a.id == id:
			return a
	return {}


func _wait_idle(max_frames: int = 900) -> bool:
	return await wait_physics_until(func(): return not player.is_busy, max_frames)


func _container_of_type(t: StringName) -> LootContainer:
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and scene.is_ancestor_of(c) and c.container_type == t:
			return c
	return null


# --- Time → needs → moodles -----------------------------------------------------------

func test_eight_hours_make_hungry_and_thirsty_with_moodles() -> void:
	check_eq(TimeManager.clock_text(), "07:00", "world starts at 07:00")
	check_eq(hud.clock.shown_time(), "07:00", "HUD clock")
	check_eq(needs.level(&"hunger"), 0, "starts fed")
	TimeManager.advance(8.0 * 60.0)
	await frames(2)
	check_eq(needs.label(&"hunger"), "Hungry", "hungry after 8 h (%.1f)" % needs.value(&"hunger"))
	check_eq(needs.label(&"thirst"), "Thirsty", "thirsty after 8 h (%.1f)" % needs.value(&"thirst"))
	var labels: PackedStringArray = hud.moodle_list.labels()
	check(labels.has("Hungry") and labels.has("Thirsty"), "moodles show (%s)" % str(labels))
	check_eq(hud.moodle_list.get_child_count(), labels.size(), "one row per moodle")
	check_eq(hud.clock.shown_time(), "15:00", "HUD clock follows")
	# Effects: hungry + thirsty lower max stamina.
	check_near(player.stats.get_max(Character.STAMINA), 100.0 * 0.9 * 0.9, 0.01, "max stamina −10 % × −10 %")


func test_jogging_makes_you_thirsty_faster() -> void:
	var t0 := needs.value(&"thirst")
	ctrl.scripted_direction = Vector3.RIGHT
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	await physics_frames(20)
	# While jogging: 60 game minutes.
	TimeManager.advance(60.0)
	ctrl.scripted_direction = Vector3.ZERO
	check_near(needs.value(&"thirst") - t0, 5.25, 0.3, "3.5/h × 1.5 while jogging")


# --- Eating ---------------------------------------------------------------------------

func test_beans_need_an_opener() -> void:
	player.inventory.add_id(&"canned_beans", 1)
	var beans := player.inventory.find(&"canned_beans")
	var acts := ItemActions.for_item(player, beans)
	var eat: Array = acts.filter(func(a): return a.id == ItemActions.CONSUME)
	check(not eat.is_empty() and not eat[0].enabled and eat[0].reason == "Need a can opener", "context menu Eat disabled (%s)" % str(eat))
	var r := player.consume_item(beans)
	check(not r.ok and r.reason == "Need a can opener", "refused (%s)" % str(r))
	await frames(1)
	check_eq(hud.notice_label.text, "Need a can opener", "HUD notice")
	check_eq(player.inventory.count_of(&"canned_beans"), 1, "can still there")
	check(not player.is_busy, "not busy")


func test_beans_with_a_knife_open_and_fill_you_up() -> void:
	needs.set_need(&"hunger", 50.0)
	player.inventory.add_id(&"canned_beans", 2)
	player.inventory.add_id(&"kitchen_knife", 1)
	consume.rng.seed = 7
	var beans := player.inventory.find(&"canned_beans")
	var started := {"label": ""}
	var cb := func(a: Node, _id: StringName, label: String, _s: float) -> void:
		if a == player:
			started.label = label
	EventBus.timed_action_started.connect(cb)
	var r := window.perform_context(LootWindow.SIDE_PLAYER, beans, ItemActions.CONSUME)
	EventBus.timed_action_started.disconnect(cb)
	check(r.ok and r.tool == &"fallback", "opened with the knife (%s)" % str(r))
	check_eq(started.label, "Eating Canned Beans…", "busy bar label")
	check(player.is_busy, "busy while eating")
	await physics_frames(2)
	check(hud.action_bar.visible, "HUD progress bar")
	if bool(consume.last_open.get("cut", false)):
		check_gt(player.injuries.injuries.size(), 0, "the knife cut a hand")
	check(await _wait_idle(), "finished eating")
	check_near(needs.value(&"hunger"), 50.0 - 380.0 / 25.0, 0.6, "−15.2 hunger (380 kcal)")
	check_eq(player.inventory.count_of(&"canned_beans"), 1, "one can eaten")
	# Force a cut to see the injury path.
	(ItemDB.get_item(&"canned_beans") as FoodData).fallback_injury_chance = 1.0
	var n := player.injuries.injuries.size()
	r = player.consume_item(player.inventory.find(&"canned_beans"))
	(ItemDB.get_item(&"canned_beans") as FoodData).fallback_injury_chance = 0.25
	check(r.ok and bool(consume.last_open.cut), "cut this time")
	check_eq(player.injuries.injuries.size(), n + 1, "hand wound added")
	check(player.is_busy, "the cut does not cancel the meal")
	await _wait_idle()


func test_eat_half_leaves_a_half_item() -> void:
	needs.set_need(&"hunger", 40.0)
	player.inventory.add_id(&"bread", 1)
	var bread := player.inventory.find(&"bread")
	var r := window.perform_context(LootWindow.SIDE_PLAYER, bread, ItemActions.CONSUME_HALF)
	check(r.ok and is_equal_approx(float(r.portion), 0.5), "half (%s)" % str(r))
	check(await _wait_idle(), "done")
	check_near(needs.value(&"hunger"), 40.0 - 48.0 * 0.5, 0.5, "half the hunger (1200 kcal / 2)")
	var left := player.inventory.find(&"bread")
	check(left != null and is_equal_approx(left.portion, 0.5), "half a loaf left")
	check(String(LootWindow.row_texts(left).name).contains("50%"), "row shows the portion")
	check(not ItemActions.for_item(player, left).any(func(a): return a.id == ItemActions.CONSUME_HALF), "no 'Eat half' of a half")
	player.consume_item(left)
	check(await _wait_idle(), "done")
	check_eq(player.inventory.count_of(&"bread"), 0, "all eaten")


func test_drink_water_leaves_empty_bottle_and_refill_at_sink() -> void:
	needs.set_need(&"thirst", 60.0)
	player.inventory.add_id(&"water_bottle", 1)
	var bottle := player.inventory.find(&"water_bottle")
	var acts := ItemActions.for_item(player, bottle)
	check(acts.any(func(a): return a.id == ItemActions.CONSUME and a.label == "Drink" and a.enabled), "Drink entry")
	var r := window.perform_context(LootWindow.SIDE_PLAYER, bottle, ItemActions.CONSUME)
	check(r.ok, "drinking (%s)" % str(r))
	check(await _wait_idle(), "done")
	check_near(needs.value(&"thirst"), 20.0, 0.5, "−40 thirst")
	check_eq(player.inventory.count_of(&"water_bottle"), 0, "bottle drunk")
	check_eq(player.inventory.count_of(&"water_bottle_empty"), 1, "empty bottle left")
	# Refill at the kitchen sink through the real interaction.
	await _stand(Vector3(-5.45, 0, -6.7), Vector3(-4.4, 0, -6.7))
	check(interaction.current_target != null and interaction.current_target.body() is Sink, "sink targeted (%s)" % str(interaction.current_target))
	var fill := _action(Sink.FILL)
	check(bool(fill.get("enabled", false)), "Fill bottle enabled (%s)" % str(fill))
	interaction.perform_action(Sink.FILL)
	check(await _wait_idle(), "filled")
	check_eq(player.inventory.count_of(&"water_bottle"), 1, "water bottle again")
	check_eq(player.inventory.count_of(&"water_bottle_empty"), 0, "no empty bottle")
	await physics_frames(2)
	check_eq(String(_action(Sink.FILL).get("reason", "")), "No empty bottles", "nothing else to fill")
	# Drinking straight from the tap.
	interaction.perform_action(Sink.DRINK)
	check(await _wait_idle(), "drank")
	check_near(needs.value(&"thirst"), 0.0, 0.5, "thirst gone")
	await physics_frames(2)
	check_eq(String(_action(Sink.DRINK).get("reason", "")), "Not thirsty", "Drink disabled when not thirsty")


func test_eating_is_interrupted_by_a_zombie_hit() -> void:
	needs.set_need(&"hunger", 50.0)
	player.inventory.add_id(&"apple", 2)
	var z := spawner.spawn_at(player.global_position + Vector3(20, 0, 0))
	z.get_node("Senses").set("enabled", false)
	player.consume_item(player.inventory.find(&"apple"))
	await physics_frames(20)
	check(consume.is_consuming(), "eating")
	player.take_damage(4.0, z, {"type": &"scratch", "region": &"left_arm", "infectious": true})
	await physics_frames(2)
	check(not player.is_busy and not consume.is_consuming(), "interrupted")
	check_eq(player.inventory.count_of(&"apple"), 2, "the apple went back")
	check_near(needs.value(&"hunger"), 50.0, 0.5, "nothing eaten")
	check(not hud.action_bar.visible, "bar hidden")


func test_hotbar_use_eats_food() -> void:
	needs.set_need(&"hunger", 30.0)
	player.inventory.add_id(&"candy_bar", 1)
	var candy := player.inventory.find(&"candy_bar")
	check(player.equipment.assign_hotbar(0, candy).ok, "candy on the hotbar")
	var r := player.use_hotbar(0)
	check(r.ok and player.is_busy, "key 1 eats it (%s)" % str(r))
	check(await _wait_idle(), "done")
	check_lt(needs.value(&"hunger"), 30.0, "less hungry")


func test_starving_drains_health() -> void:
	needs.set_need(&"hunger", 85.0)
	check_eq(needs.label(&"hunger"), "Starving", "starving")
	var h0 := player.health.health
	TimeManager.advance(60.0)
	check_near(player.health.health, h0 - 6.0, 0.3, "6 hp per game hour")
	check_near(player.stats.get_max(Character.STAMINA), 75.0, 0.01, "max stamina −25 %")


func test_health_regenerates_when_fed_and_unhurt() -> void:
	player.health.drain(20.0)
	var h0 := player.health.health
	TimeManager.advance(60.0)
	check_near(player.health.health, h0 + 6.0, 0.3, "+6 per game hour")
	needs.set_need(&"hunger", 50.0)  # very hungry: no regen
	var h1 := player.health.health
	TimeManager.advance(60.0)
	check_near(player.health.health, h1, 0.01, "no regen while very hungry")


func test_rotten_food_makes_you_sick() -> void:
	player.inventory.add_id(&"bread", 1)
	var bread := player.inventory.find(&"bread")
	bread.age_minutes = 11.0 * 1440.0
	check_eq(bread.spoil_state(), FoodData.SpoilState.ROTTEN, "rotten")
	check_eq(LootWindow.row_texts(bread).condition, "Rotten", "shown as Rotten")
	player.consume_item(bread)
	check(await _wait_idle(), "eaten")
	check_gt(needs.value(&"sickness"), 40.0, "sick")
	check(hud.moodle_list.labels().has("Nauseous"), "Nauseous moodle (%s)" % str(hud.moodle_list.labels()))
	var h0 := player.health.health
	TimeManager.advance(30.0)
	check_near(player.health.health, h0 - 3.0, 0.2, "food poisoning drains 6 / game hour while nauseous")
	check_lt(needs.value(&"sickness"), 45.0, "sickness wears off slowly")


func test_fridge_slows_spoilage_vs_cabinet() -> void:
	var fridge := _container_of_type(&"fridge")
	var cabinet := _container_of_type(&"kitchen_cabinet")
	check(fridge != null and cabinet != null, "found fridge + cabinet")
	check_near(fridge.inventory.spoil_multiplier, 0.25, 0.001, "fridge flag from the catalog")
	fridge.inventory.add_id(&"milk", 1)
	cabinet.inventory.add_id(&"milk", 1)
	var cold: ItemInstance = fridge.inventory.find_all(&"milk")[-1]
	var warm: ItemInstance = cabinet.inventory.find_all(&"milk")[-1]
	TimeManager.set_minutes(TimeManager.now() + 5.0 * 1440.0)  # milk: fresh 4 days
	check_eq(warm.spoil_state(), FoodData.SpoilState.STALE, "cabinet milk stale")
	check_eq(cold.spoil_state(), FoodData.SpoilState.FRESH, "fridge milk fresh")


# --- Sleep / rest ---------------------------------------------------------------------

func _at_bed() -> void:
	await _stand(Vector3(-11.95, 0, -8.85), Vector3(-10.75, 0, -8.85))


func test_sleep_refused_when_not_tired() -> void:
	await _at_bed()
	check(interaction.current_target != null and interaction.current_target.body() is RestFurniture, "bed targeted")
	var s := _action(RestFurniture.SLEEP)
	check(not s.is_empty() and not s.enabled and s.reason == "Not tired", "Sleep disabled: Not tired (%s)" % str(s))
	var r := interaction.perform_action(RestFurniture.SLEEP)
	check(not r.ok and r.reason == "Not tired", "refused")
	check(not rest.sleeping, "awake")


func test_sleep_refused_with_danger_nearby() -> void:
	needs.set_need(&"fatigue", 60.0)
	await _at_bed()
	var z := spawner.spawn_at(Vector3(-11.9, 0, -0.5))  # outside, ~8 m away
	z.get_node("Senses").set("enabled", false)
	await physics_frames(3)
	var r := rest.sleep(null)
	check(not r.ok and r.reason == "Can't sleep: danger nearby", "refused (%s)" % str(r))
	z.die(null)
	await physics_frames(3)
	check_eq(rest.sleep_block_reason(), "", "fine once it is dead")


func test_sleep_advances_time_and_reduces_fatigue() -> void:
	needs.set_need(&"fatigue", 60.0)
	await _at_bed()
	check(bool(_action(RestFurniture.SLEEP).get("enabled", false)), "Sleep enabled when tired")
	var t0 := TimeManager.now()
	var r := interaction.perform_action(RestFurniture.SLEEP)
	check(r.ok and rest.sleeping, "asleep (%s)" % str(r))
	check(player.is_busy, "busy while asleep")
	check_near(Engine.time_scale, TimeManager.config.sleep_engine_time_scale, 0.001, "engine sped up")
	await frames(3)
	check(hud.sleep_overlay.visible, "screen fades")
	check(await wait_physics_until(func(): return not rest.sleeping, 60 * 30), "woke up")
	check_eq(rest.last_wake_reason, "", "woke rested")
	check_lt(needs.value(&"fatigue"), 0.5, "fatigue gone")
	var slept := TimeManager.now() - t0
	check(slept > 4.0 * 60.0 and slept < 5.5 * 60.0, "≈ 4.8 game hours passed (%.0f min)" % slept)
	check_near(Engine.time_scale, 1.0, 0.001, "engine back to normal")
	check(not player.is_busy, "can move again")
	await frames(2)
	check_eq(hud.notice_label.text, "You wake up rested", "HUD notice")


func test_sleep_refused_while_bleeding_and_heals_wounds() -> void:
	needs.set_need(&"fatigue", 60.0)
	var inj := player.injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.SCRATCH)
	check_eq(rest.sleep_block_reason(), "Can't sleep: bleeding", "bleeding blocks sleep")
	inj.bleeding = false
	var left0 := inj.heal_left
	check(rest.sleep(null).ok, "asleep once it stopped bleeding")
	check(await wait_physics_until(func(): return not rest.sleeping, 60 * 30), "woke")
	check(not player.injuries.injuries.has(inj) or inj.heal_left < left0 - 200.0,
			"a night's sleep healed the scratch (%.0f → %.0f)" % [left0, inj.heal_left])


func test_sleep_interrupted_by_zombie_noise() -> void:
	needs.set_need(&"fatigue", 90.0)
	await _at_bed()
	check(rest.sleep(null).ok, "asleep")
	await physics_frames(30)
	check(rest.sleeping, "still asleep")
	# A zombie bangs on the front door 6 m away.
	EventBus.sound_emitted.emit(player.global_position + Vector3(0, 0, 6), 10.0, 1.0, &"door", null)
	await physics_frames(2)
	check(not rest.sleeping, "woke")
	check_eq(rest.last_wake_reason, "Woken by noise!", "reason")
	check_gt(needs.value(&"fatigue"), 50.0, "still tired")
	check_near(Engine.time_scale, 1.0, 0.001, "engine normal")
	# Far noise does not wake.
	check(rest.sleep(null).ok, "asleep again")
	EventBus.sound_emitted.emit(player.global_position + Vector3(30, 0, 0), 14.0, 1.0, &"footstep", null)
	await physics_frames(2)
	check(rest.sleeping, "far noise ignored")
	# Getting hit wakes you.
	player.take_damage(3.0, null, {})
	await physics_frames(1)
	check_eq(rest.last_wake_reason, "Woken: under attack!", "hit wakes")


func test_rest_on_sofa_regenerates_stamina_faster() -> void:
	player.stats.set_value(Character.STAMINA, 20.0)
	await _stand(Vector3(-7.2, 0, -3.55), Vector3(-7.2, 0, -4.75))
	check(interaction.current_target != null and interaction.current_target.body() is RestFurniture, "sofa targeted")
	check(_action(RestFurniture.SLEEP).is_empty(), "no Sleep on a sofa")
	var r := interaction.perform_action(RestFurniture.REST)
	check(r.ok and rest.resting, "resting")
	var s0 := player.stats.get_value(Character.STAMINA)
	await physics_frames(60)
	var gained := player.stats.get_value(Character.STAMINA) - s0
	check_near(gained, player.profile.stamina_rate_idle * 3.0, 0.8, "×3 idle regen per second (%.2f)" % gained)
	ctrl.scripted_direction = Vector3.BACK
	await physics_frames(3)
	check(not rest.resting and not player.is_busy, "moving gets you up")
	ctrl.scripted_direction = Vector3.ZERO


# --- Time controls / lighting ----------------------------------------------------------

func test_fast_forward_refused_while_chased() -> void:
	var r := TimeManager.set_speed(3)
	check(r.ok and is_equal_approx(Engine.time_scale, 4.0), "4× when safe")
	TimeManager.set_speed(1)
	var z := spawner.spawn_at(player.global_position + Vector3(12, 0, 0))
	z.get_node("Senses").set("enabled", false)
	z.set_physics_process(false)  # keep the scripted chase state
	z.target = player
	z.hostile = true
	r = TimeManager.request_speed(2)
	check(not r.ok and r.reason == "Can't fast-forward: danger", "refused (%s)" % str(r))
	check_near(Engine.time_scale, 1.0, 0.001, "still 1×")
	await frames(1)
	check_eq(hud.notice_label.text, "Can't fast-forward: danger", "HUD notice")
	# Already fast when a chase starts → back to 1×.
	z.hostile = false
	check(TimeManager.set_speed(3).ok, "fast again")
	z.hostile = true
	check(await wait_physics_until(func(): return TimeManager.speed_step == 1, 30), "dropped to 1× on danger")
	check_near(Engine.time_scale, 1.0, 0.001, "engine normal")


func test_speed_keys_and_pause() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_F8
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	check_eq(TimeManager.speed_step, 3, "F8 → 4×")
	check_near(Engine.time_scale, 4.0, 0.001, "engine 4×")
	var t0 := TimeManager.now()
	await physics_frames(15)
	check_near(TimeManager.now() - t0, 1.0, 0.1, "15 physics frames at 4× = 1 game minute")
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	var p := InputEventKey.new()
	p.keycode = KEY_F5
	p.pressed = true
	Input.parse_input_event(p)
	await frames(2)
	check(tree.paused and TimeManager.is_paused(), "F5 pauses")
	var t1 := TimeManager.now()
	await frames(10)
	check_near(TimeManager.now(), t1, 0.0001, "time stands still")
	TimeManager.set_speed(1)
	check(not tree.paused, "resumed")


func test_lighting_follows_time_of_day() -> void:
	var dn: DayNightLighting = scene.get_node("DayNight")
	TimeManager.set_time_of_day(12, 0)
	await physics_frames(2)
	var noon := dn.sun_energy()
	var lights := tree.get_nodes_in_group(&"interior_light").filter(func(n): return scene.is_ancestor_of(n))
	check_gt(lights.size(), 3, "rooms have lights")
	check(not (lights[0] as Node3D).visible, "lights off at noon")
	TimeManager.set_time_of_day(23, 0)
	await physics_frames(2)
	var night := dn.sun_energy()
	check_lt(night, noon * 0.5, "23:00 darker than 12:00 (%.2f vs %.2f)" % [night, noon])
	check((lights[0] as Node3D).visible, "house lights on at night")
	check_eq(hud.clock.shown_time(), "23:00", "clock")


# --- Critic round: needs in sleep, busy cancellation, loot age, balance ----------------

func test_sleep_refused_when_thirst_would_turn_critical() -> void:
	needs.set_need(&"fatigue", 90.0)
	needs.set_need(&"thirst", 80.0)
	check_eq(rest.sleep_block_reason(), "Too thirsty to sleep", "predicted to reach Dying of Thirst")
	needs.set_need(&"thirst", 10.0)
	needs.set_need(&"hunger", 78.0)
	check_eq(rest.sleep_block_reason(), "Too hungry to sleep", "predicted to reach Starving")


func test_needs_turning_critical_wake_the_sleeper() -> void:
	needs.set_need(&"fatigue", 60.0)
	needs.set_need(&"thirst", 50.0)
	check(rest.sleep(null).ok, "asleep")
	await physics_frames(10)
	needs.set_need(&"thirst", 90.0)  # dying of thirst → health drain
	check(await wait_physics_until(func(): return not rest.sleeping, 30), "woke up")
	check_eq(rest.last_wake_reason, "Woken: dying of thirst", "reason")
	check_gt(player.health.health, 95.0, "woke before losing much")
	check(not player.is_dead(), "alive")


func test_die_while_eating_keeps_the_item() -> void:
	player.inventory.add_id(&"apple", 1)
	player.consume_item(player.inventory.find(&"apple"))
	await physics_frames(5)
	check(consume.is_consuming(), "eating")
	player.health.drain(1000.0)
	await physics_frames(2)
	check(player.is_dead(), "dead")
	check_eq(player.inventory.count_of(&"apple"), 1, "the apple is back in the (dead) inventory")
	check(consume.current.is_empty(), "no dangling action")


func test_die_while_bandaging_refunds_the_dressing() -> void:
	player.inventory.add_id(&"bandage", 1)
	player.injuries.add_injury(Injury.Region.LEFT_ARM, Injury.Type.LACERATION)
	check(player.injuries.bandage_worst().ok, "bandaging")
	check_eq(player.inventory.count_of(&"bandage"), 0, "dressing taken")
	await physics_frames(5)
	player.health.drain(1000.0)
	await physics_frames(2)
	check_eq(player.inventory.count_of(&"bandage"), 1, "dressing refunded")
	check(player.injuries.bandaging == null, "not bandaging")


func test_overriding_busy_mid_search_cancels_it() -> void:
	var cab := _container_of_type(&"kitchen_cabinet")
	var got := {"finished": 0, "completed": true}
	var cb := func(a: Node, action: StringName, completed: bool) -> void:
		if a == player and action == &"search":
			got.finished += 1
			got.completed = completed
	EventBus.timed_action_finished.connect(cb)
	check(cab.search(player).ok, "rummaging")
	await physics_frames(5)
	var tw := player.begin_busy(&"climb")  # e.g. a window climb takes the body
	tw.tween_interval(0.3)
	check(await _wait_idle(), "climb done")
	await physics_frames(90)
	EventBus.timed_action_finished.disconnect(cb)
	check(not cab.is_open(), "the cabinet never opened")
	check(got.finished == 1 and not got.completed, "search reported cancelled (%s)" % str(got))
	check(not cab.is_searching(), "no dangling search")


func test_fast_forward_resets_on_death() -> void:
	check(TimeManager.set_speed(3).ok, "4×")
	player.health.drain(1000.0)
	await physics_frames(1)
	check_eq(TimeManager.speed_step, 1, "back to 1×")
	check_near(Engine.time_scale, 1.0, 0.001, "engine normal")


func test_eating_refused_while_paused_and_busy_label() -> void:
	player.inventory.add_id(&"apple", 1)
	TimeManager.set_speed(0)
	var r := player.consume_item(player.inventory.find(&"apple"))
	TimeManager.set_speed(1)
	check(not r.ok and r.reason == "Paused", "refused while paused (%s)" % str(r))
	player.consume_item(player.inventory.find(&"apple"))
	await frames(3)
	check_eq(String(hud.mode_label.text), "Eating", "HUD state label")
	await _wait_idle()
	await frames(3)
	check_eq(String(hud.mode_label.text), "Idle", "idle again")


func test_second_worst_level_warns_loudly() -> void:
	needs.set_need(&"thirst", 60.0)  # Parched (2 of 3)
	await frames(3)
	check_eq(String(hud.notice_label.text), "WARNING: Parched — drink something soon!", "warning notice")
	check_eq(hud.moodle_list.pulsing, &"thirst", "thirst moodle pulses")


func test_fill_bottle_refused_without_room() -> void:
	player.inventory.add_id(&"water_bottle_empty", 1)
	while player.inventory.free_weight() > 0.5:
		if not player.inventory.add_id(&"nails", 1).ok:
			break
	if player.inventory.free_weight() > 0.8:
		player.inventory.add_id(&"plank", 1)
	check(player.inventory.free_weight() < 0.9, "pack almost full (%.2f)" % player.inventory.free_weight())
	check_eq(consume.fill_block_reason(), "No room for the water", "no room")


func test_water_shuts_off_on_day_14() -> void:
	await _stand(Vector3(-5.45, 0, -6.7), Vector3(-4.4, 0, -6.7))
	needs.set_need(&"thirst", 40.0)
	await physics_frames(2)
	check(bool(_action(Sink.DRINK).get("enabled", false)), "water on at day 1")
	TimeManager.set_minutes(TimeManager.now() + 14.0 * 1440.0)
	await physics_frames(3)
	var d := _action(Sink.DRINK)
	check(not d.get("enabled", true) and d.reason == "The water is off", "water off after day 14 (%s)" % str(d))
	check_eq(String(_action(Sink.FILL).get("reason", "")), "The water is off", "no filling either")


func test_unrolled_fridge_food_is_as_old_as_the_world() -> void:
	var fridge := _container_of_type(&"fridge")
	var fixed: Array[Dictionary] = [{"id": &"milk", "count": 1}]
	fridge.fixed_items = fixed
	TimeManager.set_minutes(40.0 * 1440.0)
	fridge.ensure_loot()
	var milk: ItemInstance = fridge.inventory.find(&"milk")
	check(milk != null, "milk rolled")
	check_near(milk.effective_age(), 10.0 * 1440.0, 2.0, "40 days × fridge 0.25 = 10 days old")
	check_eq(milk.spoil_state(), FoodData.SpoilState.ROTTEN, "day-40 fridge milk is rotten")


func test_balance_no_water_death_takes_36_to_48_hours() -> void:
	player.health.invulnerable = false
	var hours := 0
	while not player.is_dead() and hours < 96:
		needs.set_need(&"hunger", 5.0)  # fed, never drinks
		var h := hours % 24
		needs.sleeping = h >= 16  # 16 h awake, 8 h asleep
		needs.set_need(&"fatigue", 20.0)
		TimeManager.advance(60.0)
		hours += 1
	needs.sleeping = false
	check(hours >= 36 and hours <= 48, "no water: dead after %d game hours (36-48)" % hours)


func test_balance_house_a_food_lasts_days() -> void:
	var p: NeedsProfile = needs.profile
	var daily := 16.0 * p.hunger_per_hour + 8.0 * p.hunger_sleep_per_hour
	var cfg: WorldConfig = scene.get_node("World")
	var house := scene.get_node("Buildings/HouseA")
	var containers: Array = tree.get_nodes_in_group(LootContainer.GROUP).filter(func(c): return house.is_ancestor_of(c))
	check_gt(containers.size(), 5, "House A containers")
	var totals: Array[float] = []
	for s in 30:
		cfg.world_seed = 1000 + s * 7919
		var total := 0.0
		for c: LootContainer in containers:
			var rng := RandomNumberGenerator.new()
			rng.seed = c.loot_seed()
			var list: Array = LootResolver.roll(c.resolve_table(), rng, 0.0) if c.resolve_table() else []
			for f in c.fixed_items:
				list.append({"id": f.id, "count": f.get("count", 1)})
			for e in list:
				var fd := ItemDB.get_item(StringName(e.id)) as FoodData
				if fd:
					total += NeedsMath.hunger_of(fd, p) * int(e.count)
		totals.append(total / daily)
	var mean := 0.0
	for t in totals:
		mean += t
	mean /= totals.size()
	print("BALANCE house A food days: mean %.2f min %.2f max %.2f" % [mean, totals.min(), totals.max()])
	check(mean >= 2.5 and mean <= 7.0, "House A feeds one person %.1f days on average (2.5-7)" % mean)
	check_gt(totals.min(), 1.0, "even a poor roll gives > 1 day")
	check_lt(totals.max(), 10.0, "no feast house")
	cfg.world_seed = 1337


func test_zombie_reaches_the_house_while_you_sleep() -> void:
	needs.set_need(&"fatigue", 90.0)
	await _at_bed()
	var z := spawner.spawn_at(Vector3(-11.0, 0, 22.0))
	await physics_frames(3)
	var start: Vector3 = z.global_position
	check(rest.sleep(null).ok, "asleep (zombie %.0f m away)" % start.distance_to(player.global_position))
	var t0 := TimeManager.now()
	# It heard something at the front door the sleeper did not.
	z.get_node("AI").call(&"_on_sound_heard", Vector3(-11.0, 0, -1.3), &"door")
	check(await wait_physics_until(func(): return not rest.sleeping, 1500), "woken")
	check_eq(rest.last_wake_reason, "Woken by noise!", "woken by the zombie")
	check_gt(start.distance_to(z.global_position), 12.0, "the zombie walked to the house during the sleep")
	check_lt(Danger.nearest_zombie_distance(tree, player.global_position), 10.5, "it is at the door")
	check_lt(TimeManager.now() - t0, 180.0, "within the night")
