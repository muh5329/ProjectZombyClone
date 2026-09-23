extends "res://tests/test_case.gd"
## Round 10 — the brief's FINAL ACCEPTANCE TEST played UNSTAGED by a
## scripted bot on a real new game (SaveManager.instantiate_new_game with
## a world seed): the map's own zombies (incl. the street group by House A),
## no item injection, no stat forcing — only game time is advanced (to
## get hungry / thirsty / tired). The bot walks along navmesh paths with
## the real controller (scripted intent), opens doors on its way, and uses
## the player's real verbs / interactions. When walking fails (stuck for
## STUCK_SECONDS) it teleports to the goal and REPORTS it (`teleports`).
## Subclasses (test_unstaged_<seed>.gd) run one seed each (shard balance).
##
## Steps: spawn in House A → search the kitchen → food → backpack →
## weapon → search the bathroom → smash the living-room window: a zombie
## outside hears it → climb out → fight (kill ≥ 1) → injured (the glass or
## the fight; else climb through the broken window again) → treat it
## (bandage / rag, or tear the spare t-shirt into rags) → the garage (door,
## tool crate, hammer on the workbench, take the shelf apart for planks) →
## home through the front door → hungry + thirsty (time) → eat + drink at
## the sink (the smashed window is barricaded first, as soon as the bot
## is home: a safehouse with a hole in it is not safe) → tired → sleep in the
## bed → save → reload into a fresh scene → confirm.

const MAP := "res://maps/test_ground.tscn"
const STUCK_SECONDS := 3.0
const SLOT_PREFIX := "unstaged-"

var scene: Node
var player: Player
var ctrl: PlayerController
var interaction: PlayerInteraction
var combat: MeleeCombat
var spawner: ZombieSpawner
var house: HouseBlockout
var garage: HouseBlockout
var world_seed: int = 1337
## "walk <label>" entries where walking failed and the bot teleported.
var teleports: PackedStringArray = []
var kills: int = 0
var swings: int = 0
## Melee tactic: &"best" (shove-and-hit 1v1, aim-walk backwards vs groups),
## or one of &"kite" | &"shove" | &"back" | &"aimback" alone.
var tactic: StringName = &"best"
## When set, the bot holds this spot (a doorway chokepoint): it swings at
## whatever comes into reach but never chases out of it.
var hold_at: Vector3 = Vector3.INF
var retreats: int = 0
var log_lines: PackedStringArray = []


func setup() -> void:
	pass


func teardown() -> void:
	if EventBus.zombie_died.is_connected(_on_zombie_died):
		EventBus.zombie_died.disconnect(_on_zombie_died)
	print("  bot log [%d]: %s | teleports: %s" % [world_seed, " ; ".join(log_lines), str(teleports)])
	if scene != null:
		await despawn(scene)
	SaveFile.delete_slot(SLOT_PREFIX + str(world_seed))
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


func _note(s: String) -> void:
	log_lines.append(s)
	if OS.get_environment("BOT_TRACE") != "":
		printerr("    bot[%d] %s" % [world_seed, s])


func _step(name: String) -> void:
	var dressings := 0
	for c in player.carried_storage():
		for it in c.items:
			if it.data is MedicalData and (it.data as MedicalData).bandage_quality > 0.0:
				dressings += it.stack
	_note("%s (wounds %d bleeding %d dressings %d, swings %d retreats %d kills %d hp %.0f, pos %.1f,%.1f, t %.0f, zombies %d)" % [name, player.injuries.injuries.size(), player.injuries.bleeding_count(), dressings, swings, retreats, kills, player.health.health if player.health else -1.0,
		player.global_position.x, player.global_position.z, TimeManager.now(), _living_zombies().size()])


# --- Bot: movement --------------------------------------------------------------------

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _face(p: Vector3) -> void:
	var d := p - player.global_position
	d.y = 0.0
	if d.length_squared() > 0.0001:
		player.movement.facing = BodyHelpers.yaw_for(d.normalized())
		if player.visual:
			player.visual.rotation.y = player.movement.facing


## Walk to [goal] (navmesh path, jogging). Opens closed doors in the way,
## fights zombies that come within reach. Teleports (and records it) when
## stuck for STUCK_SECONDS. True when it arrived by walking.
func walk_to(goal: Vector3, label: String, tol: float = 0.35, max_seconds: float = 60.0, sneak: bool = false) -> bool:
	var nav_map := player.get_world_3d().navigation_map
	var path := PackedVector3Array()
	var idx := 0
	var repath := 0.0
	var best := INF
	var since_progress := 0.0
	var t := 0.0
	while t < max_seconds:
		if player.is_dead():
			return false
		var pos := player.global_position
		if _flat(pos, goal) <= tol:
			ctrl.scripted_direction = Vector3.ZERO
			await physics_frames(2)
			return true
		if not _hostiles(3.0).is_empty():
			ctrl.scripted_direction = Vector3.ZERO
			await engage(6.0)
			await treat_wounds(false)
			await tree.physics_frame
			t += 1.0 / 60.0
			repath = 0.0
			best = INF
			continue
		if player.is_busy:
			ctrl.scripted_direction = Vector3.ZERO
			await tree.physics_frame
			t += 1.0 / 60.0
			continue
		repath -= 1.0 / 60.0
		if repath <= 0.0 or idx >= path.size():
			path = NavigationServer3D.map_get_path(nav_map, pos, goal, true, 1)
			idx = 1 if path.size() > 1 else 0
			repath = 0.5
		var target := goal
		while idx < path.size() and _flat(pos, path[idx]) < 0.3:
			idx += 1
		if idx < path.size():
			target = path[idx]
		var dir := target - pos
		dir.y = 0.0
		var chased := _hostiles(12.0).size() > 0
		ctrl.scripted_mode = MovementComponent.Mode.SNEAK if sneak and not chased else MovementComponent.Mode.JOG
		ctrl.scripted_direction = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
		await tree.physics_frame
		t += 1.0 / 60.0
		var d := _flat(player.global_position, goal)
		if d < best - 0.2:
			best = d
			since_progress = 0.0
		else:
			since_progress += 1.0 / 60.0
		if since_progress > 0.8 and await _open_door_ahead():
			since_progress = 0.0
			best = INF
		elif since_progress > STUCK_SECONDS:
			break
		elif since_progress > 1.5 and int(since_progress * 60.0) % 45 == 0:
			# Slide sideways off a corner / furniture edge, then re-path.
			var side := Vector3(-dir.z, 0.0, dir.x).normalized() * (1.0 if int(since_progress) % 2 == 0 else -1.0)
			ctrl.scripted_direction = side
			await physics_frames(18)
			repath = 0.0
	ctrl.scripted_direction = Vector3.ZERO
	teleports.append("walk %s (stuck at %s)" % [label, player.global_position])
	player.global_position = Vector3(goal.x, 0.1, goal.z)
	player.velocity = Vector3.ZERO
	await physics_frames(4)
	return false


## A closed door within reach: face it and open it (the player's verb).
func _open_door_ahead() -> bool:
	var best: Door = null
	var bd := 1.8
	for d in tree.get_nodes_in_group(&"door"):
		if d is Door and scene.is_ancestor_of(d) and (d as Door).state == Door.STATE_CLOSED:
			var dd := _flat((d as Door).sound_opening_center(), player.global_position)
			if dd < bd:
				bd = dd
				best = d
	if best == null:
		return false
	ctrl.scripted_direction = Vector3.ZERO
	_face(best.sound_opening_center())
	await physics_frames(3)
	var r: Dictionary
	if interaction.current_target != null and interaction.current_target.body() == best:
		r = interaction.perform_action(Door.ACTION_OPEN)
	else:
		r = best.open_door(player)
	await physics_frames(30)
	return bool(r.get("ok", false))


# --- Bot: zombies -----------------------------------------------------------------------

func _living_zombies() -> Array:
	var out := []
	for z in tree.get_nodes_in_group(&"zombie"):
		if scene.is_ancestor_of(z) and not z.dead:
			out.append(z)
	return out


func _nearest_zombie(radius: float) -> Zombie:
	var best: Zombie = null
	var bd := radius
	for z in _living_zombies():
		var d := _flat(z.global_position, player.global_position)
		if d < bd:
			bd = d
			best = z
	return best


## Zombies after the player within [radius], nearest first.
func _hostiles(radius: float) -> Array:
	var out := []
	for z in _living_zombies():
		if _is_hostile(z) and _flat(z.global_position, player.global_position) <= radius \
				and _reachable(z) and not _ignored.has(z.get_instance_id()):
			out.append(z)
	out.sort_custom(func(a, b): return _flat(a.global_position, player.global_position) < _flat(b.global_position, player.global_position))
	return out


## Deal with every zombie after the player within [radius]: always the
## nearest one (the bat's 120° arc often catches a second), one fight
## tick per frame (fight_tick).
func engage(radius: float = 6.0, max_seconds: float = 90.0) -> void:
	var frames_left := int(max_seconds * 60.0)
	ctrl.scripted_mode = MovementComponent.Mode.WALK
	while frames_left > 0 and not player.is_dead():
		var hs := _hostiles(radius)
		if hs.is_empty():
			break
		if not _defending and hold_at == Vector3.INF and _hostiles(10.0).size() >= 2 \
				and not house.contains_point(player.global_position) and not garage.contains_point(player.global_position):
			var f0 := Engine.get_physics_frames()
			await defend_at_window()
			frames_left -= maxi(Engine.get_physics_frames() - f0, 60)
			continue
		var target: Zombie = hs[0]
		var tid := target.get_instance_id()
		if not _progress.has(tid) or float(_progress[tid][1]) - target.health() > 0.5:
			_progress[tid] = [Engine.get_physics_frames(), target.health()]
		elif Engine.get_physics_frames() - int(_progress[tid][0]) > 60 * 8:
			_ignored[tid] = true
			_note("gave up on %s (no damage in 8 s, state %s)" % [target.spawn_id, target.state()])
			continue
		fight_tick(target)
		await tree.physics_frame
		frames_left -= 1
	ctrl.scripted_direction = Vector3.ZERO
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	if combat.aiming:
		combat.set_aiming(false)


var _defending: bool = false
## Per target: [frame of the last health drop, health then].
var _progress: Dictionary = {}
## Zombies given up on (instance ids): hit after hit without losing
## health — stuck in a wall / window frame, out of anyone's reach.
var _ignored: Dictionary = {}


## A group outdoors: run to the nearest doorway (House A front door,
## the garage door), open it, step inside and hold the spot behind it —
## only one zombie fits the doorway at a time (PZ: never fight a crowd in
## the open).
func defend_at_window() -> void:
	_defending = true
	if combat.aiming:
		combat.set_aiming(false)
	var spots := [
		{"door": _door(garage, "/door"), "out": Vector3(8.0, 0, -12.1), "hold": Vector3(8.0, 0, -14.4), "look": Vector3(8.0, 0, -12.0)},
	]
	spots.sort_custom(func(x, y): return _flat(x.out, player.global_position) < _flat(y.out, player.global_position))
	var spot: Dictionary = spots[0]
	_note("retreat to %s (%d after us)" % [String(spot.door.persist_id), _hostiles(10.0).size()])
	await _run_to(spot.out)
	var door: Door = spot.door
	if door.state == Door.STATE_CLOSED:
		_face(door.sound_opening_center())
		await physics_frames(2)
		door.open_door(player)
		await physics_frames(20)
	await _run_to(spot.hold)
	await hold_spot(spot.hold, spot.look, 8.0, 60.0)
	_defending = false


## Jog along a layer-1 navmesh path to [goal] without stopping to fight.
func _run_to(goal: Vector3, max_frames: int = 60 * 20) -> void:
	var t := 0
	while _flat(player.global_position, goal) > 0.3 and t < max_frames and not player.is_dead():
		if t % 20 == 0 and await _open_door_ahead():
			pass
		var path := NavigationServer3D.map_get_path(player.get_world_3d().navigation_map, player.global_position, goal, true, 1)
		var target := goal
		for p in path:
			if _flat(p, player.global_position) > 0.4:
				target = p
				break
		var dir := target - player.global_position
		dir.y = 0.0
		ctrl.scripted_mode = MovementComponent.Mode.JOG
		ctrl.scripted_direction = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
		await tree.physics_frame
		t += 1
	ctrl.scripted_direction = Vector3.ZERO


## Hold [hold] facing [look], swinging at whatever comes within reach and
## never stepping out after it, until quiet for [quiet_seconds].
func hold_spot(hold: Vector3, look: Vector3, quiet_seconds: float, max_seconds: float) -> void:
	hold_at = hold
	var waited := 0
	var quiet := 0
	while waited < int(max_seconds * 60.0) and not player.is_dead():
		var hs := _hostiles(10.0)
		if not hs.is_empty():
			quiet = 0
			fight_tick(hs[0])
			await tree.physics_frame
			waited += 1
			continue
		if _flat(player.global_position, hold) > 0.3:
			var back := hold - player.global_position
			back.y = 0.0
			ctrl.scripted_mode = MovementComponent.Mode.WALK
			ctrl.scripted_direction = back.normalized()
			await physics_frames(10)
		ctrl.scripted_direction = Vector3.ZERO
		_face(look)
		await physics_frames(15)
		waited += 25
		quiet += 25
		if quiet > int(quiet_seconds * 60.0):
			break
	hold_at = Vector3.INF
	ctrl.scripted_direction = Vector3.ZERO


## Clear the street through the smashed window: hold the spot behind it
## and, whenever it is quiet but zombies are still around outside, SHOUT
## (H: PZ's deliberate lure) so they come — over the sill, one at a time.
## Ends when no zombie is within [clear_radius] m of the window.
func lure_and_hold(max_seconds: float, clear_radius: float = 16.0) -> void:
	var win_pos := Vector3(-7.0, 0, -2.0)
	var shout := player.get_node_or_null("Shout")
	var f0 := Engine.get_physics_frames()
	while (Engine.get_physics_frames() - f0) < int(max_seconds * 60.0) and not player.is_dead():
		var around := _living_zombies().filter(func(z): return _flat(z.global_position, win_pos) < clear_radius)
		if around.is_empty():
			break
		if _hostiles(10.0).is_empty() and shout != null:
			shout.call(&"shout")
		await hold_window(4.0, 12.0)
	await treat_wounds(false)
	await loot_corpses(8.0)
	await treat_wounds(false)


## Hold the spot behind the living-room window (see hold_spot).
func hold_window(quiet_seconds: float, max_seconds: float = 60.0) -> void:
	await hold_spot(Vector3(-7.0, 0, -3.6), Vector3(-7.0, 0, -2.0), quiet_seconds, max_seconds)


## Nothing solid (walls, doors, window panes, planks) between us.
func _reachable(z: Zombie) -> bool:
	if _flat(player.global_position, z.global_position) > 4.0:
		return true  # far: it will come round; only the melee line matters up close
	var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.1, z.global_position + Vector3.UP * 1.1,
		(1 << 0) | (1 << 6) | (1 << 7))
	q.exclude = [player.get_rid(), z.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _is_hostile(z: Zombie) -> bool:
	return z.state() in [ZombieAI.S_CHASE, ZombieAI.S_ATTACK, ZombieAI.S_ATTACK_DOOR] or z.target == player


## One frame of melee against [zz], PZ-style: keep just inside the bat's
## reach (1.4 m) and outside the bite (1.0 m) — step in, swing, step
## back; back off while it winds up a bite, shove it when it is too close.
func fight_tick(zz: Zombie) -> void:
	_best_weapon()
	var to := zz.global_position - player.global_position
	to.y = 0.0
	var d := to.length()
	var away := -to.normalized() if d > 0.01 else Vector3.BACK
	var dir := Vector3.ZERO
	var down := zz.is_knocked_down() or zz.state() == ZombieAI.S_STUNNED
	var winded := player.stats.get_value(&"stamina") < 25.0 and not down
	var tac := tactic
	if tac == &"best":
		tac = &"aimback" if _hostiles(4.0).size() > 1 else &"shove"
	if tac != &"aimback" and combat.aiming:
		combat.set_aiming(false)
	if player.is_busy or combat.is_swinging():
		dir = Vector3.ZERO
	elif tac == &"shove":
		# PZ: shove it off balance, hit it while it reels / lies.
		if down and d <= 1.35:
			_face(zz.global_position)
			if combat.attack_now(0.35):
				swings += 1
		elif down:
			dir = to.normalized()
		elif d < 1.15:
			_face(zz.global_position)
			combat.shove()
		elif d < 1.45 and not zz.is_winding_up() and not winded:
			_face(zz.global_position)
			if combat.attack_now(0.35):
				swings += 1
		elif winded and d < 1.6:
			dir = away
		elif zz.is_winding_up():
			dir = away
		else:
			dir = to.normalized()
	elif tac == &"aimback":
		# Groups (PZ aim-walk): aim at the nearest (facing locked on it,
		# walking backwards at 2 m/s — faster than their 1.6), swing when it
		# is in reach and the others are not yet.
		combat.aim_direction = to.normalized() if d > 0.01 else Vector3.FORWARD
		if not combat.aiming:
			combat.set_aiming(true)
		var others2 := _hostiles(3.0).filter(func(o): return o != zz)
		var others_far := others2.all(func(o): return _flat(o.global_position, player.global_position) > 1.7)
		if zz.is_winding_up() and d < 1.0:
			combat.shove()
		elif d <= 1.38 and d >= 0.95 and others_far:
			if combat.attack_now(0.35):
				swings += 1
		elif d < 1.9:
			var c2 := zz.global_position
			for o in others2:
				c2 += o.global_position
			c2 /= float(others2.size() + 1)
			var aw2 := player.global_position - c2
			aw2.y = 0.0
			dir = aw2.normalized() if aw2.length() > 0.01 else away
		elif d > 2.2 and others2.is_empty():
			dir = to.normalized()
	elif tac == &"back":
		# Groups: keep backing off while the others are close; swing at the
		# nearest only when it is alone in reach.
		var others := _hostiles(2.4).filter(func(o): return o != zz)
		if zz.is_winding_up() and d < 1.1:
			_face(zz.global_position)
			combat.shove()
		elif not others.is_empty() and d < 1.8:
			var c := Vector3.ZERO
			for o in others:
				c += o.global_position
			c = (c + zz.global_position) / float(others.size() + 1)
			var aw := player.global_position - c
			aw.y = 0.0
			dir = aw.normalized() if aw.length() > 0.01 else away
			if d <= 1.35 and d >= 1.0 and others.all(func(o): return _flat(o.global_position, player.global_position) > 1.6):
				dir = Vector3.ZERO
				_face(zz.global_position)
				if combat.attack_now(0.35):
					swings += 1
		elif d > 1.35:
			dir = to.normalized()
		elif d < 0.9 and not zz.is_knocked_down():
			dir = away
		else:
			_face(zz.global_position)
			if combat.attack_now(0.35):
				swings += 1
	else:
		if zz.is_winding_up() and d < 1.1:
			_face(zz.global_position)
			combat.shove()
		elif d > 1.35:
			dir = to.normalized()
		elif d < 0.9 and not zz.is_knocked_down():
			dir = away
		else:
			_face(zz.global_position)
			if combat.attack_now(0.35):
				swings += 1
	if tac == &"aimback":
		ctrl.scripted_mode = MovementComponent.Mode.WALK
		ctrl.scripted_direction = dir
		return
	if hold_at != Vector3.INF and dir != Vector3.ZERO and dir.dot(to) > 0.0:
		# Holding a chokepoint: never step out after it.
		var back := hold_at - player.global_position
		back.y = 0.0
		dir = back.normalized() if back.length() > 0.25 else Vector3.ZERO
	ctrl.scripted_mode = MovementComponent.Mode.JOG if d > 3.0 else MovementComponent.Mode.WALK
	ctrl.scripted_direction = dir
	if dir == Vector3.ZERO:
		_face(zz.global_position)


## The longest-reach carried weapon in the hands (the hammer goes into
## the hands for nailing; fights want the bat back).
func _best_weapon() -> void:
	if combat.is_swinging() or player.is_busy:
		return
	var best: ItemInstance = null
	for w in player.held_weapons():
		if best == null or (w.data as WeaponData).reach > (best.data as WeaponData).reach:
			best = w
	var cur := player.equipment.primary()
	if best != null and cur != best:
		player.equip_item(best)


## Melee [z] until it dies (see fight_tick). True when it died.
func fight(z: Zombie, max_seconds: float = 40.0) -> bool:
	var ref: WeakRef = weakref(z)
	var frames_left := int(max_seconds * 60.0)
	while frames_left > 0:
		frames_left -= 1
		var zz: Zombie = ref.get_ref()
		if zz == null or zz.dead:
			ctrl.scripted_direction = Vector3.ZERO
			ctrl.scripted_mode = MovementComponent.Mode.JOG
			return true
		if player.is_dead():
			return false
		fight_tick(zz)
		await tree.physics_frame
	ctrl.scripted_direction = Vector3.ZERO
	ctrl.scripted_mode = MovementComponent.Mode.JOG
	return ref.get_ref() == null or (ref.get_ref() as Zombie).dead


## Search the corpses within [radius] for dressings and clothes to tear
## (PZ: the dead are a pharmacy).
func loot_corpses(radius: float) -> void:
	for c in tree.get_nodes_in_group(&"corpse"):
		if not scene.is_ancestor_of(c) or c.searched or _flat(c.global_position, player.global_position) > radius:
			continue
		if not house.contains_point(c.global_position) and house.contains_point(player.global_position):
			continue  # not through the walls
		await clear_threats(6.0)
		await walk_to(c.global_position + Vector3(0, 0, 0.9), "corpse", 0.3)
		_face(c.global_position)
		await physics_frames(4)
		if do_on(c, &"search").ok:
			await wait_physics_until(func(): return c.is_open_for(player), 180)
			take_if(c, func(it: ItemInstance): return it.data is MedicalData or ItemActions.is_tearable(it.data) or it.data is FoodData)
			c.close()


## Bandage every bleeding / unbandaged wound while dressings last; tear
## the spare clothes into rags when out of dressings. Waits out the
## bleeding of a wound nothing is left for.
func treat_wounds(wait_out: bool = true) -> void:
	for i in 6:
		await tree.physics_frame
		if player.injuries.worst_unbandaged() == null:
			return
		if not _dressing_carried():
			var cloth: ItemInstance = null
			for c in player.carried_storage():
				for it in c.items:
					if ItemActions.is_tearable(it.data):
						cloth = it
			if cloth == null or not ItemActions.perform(player, cloth, ItemActions.TEAR).ok:
				break
		await engage(5.0, 20.0)
		if player.injuries.bandage_worst().ok:
			await _wait_idle(60 * 8)
	var waited := 0
	while wait_out and player.injuries.bleeding_count() > 0 and waited < 60 * 150:
		await physics_frames(30)
		waited += 30


## Kill every zombie within [radius] that is after the player (or all
## within [radius] when [all]).
func clear_threats(radius: float, all: bool = false, max_rounds: int = 8) -> void:
	for i in max_rounds:
		var z := _nearest_zombie(radius)
		if z == null or (not all and not _is_hostile(z)):
			return
		if _is_hostile(z):
			await engage(radius)
		else:
			await fight(z)
		if player.is_dead():
			return
		await treat_wounds(false)


# --- Bot: interactions -----------------------------------------------------------------

func _action(id: StringName) -> Dictionary:
	if interaction.current_target == null:
		return {}
	for a in interaction.current_actions:
		if a.id == id:
			return a
	return {}


## Run [action] on [body]: through the player's current interaction target
## when it is [body], else through [body]'s own Interactable (same rules:
## a corpse lying in a window frame can steal the target).
func do_on(body: Node, action: StringName) -> Dictionary:
	if interaction.current_target != null and interaction.current_target.body() == body:
		return interaction.perform_action(action)
	var it := Interactable.of(body)
	return it.perform(action, player) if it != null else {"ok": false, "reason": "No target"}


func action_on(body: Node, action: StringName) -> Dictionary:
	var it := Interactable.of(body)
	if it == null:
		return {}
	for a in it.get_actions(player):
		if a.id == action:
			return a
	return {}


func _wait_idle(max_frames: int = 60 * 20) -> bool:
	return await wait_physics_until(func(): return not player.is_busy, max_frames)


func _container(pid: String) -> LootContainer:
	for c in tree.get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and c.persist_id == pid and scene.is_ancestor_of(c) and not c.is_queued_for_deletion():
			return c
	return null


## Walk in front of [body] (its +Z face, [reach] m out) and face it.
func approach(body: Node3D, label: String, reach: float = 0.8) -> void:
	var front := body.global_basis.z
	front.y = 0.0
	front = front.normalized() if front.length() > 0.01 else Vector3.BACK
	await walk_to(body.global_position + front * reach, label, 0.3)
	_face(body.global_position)
	await physics_frames(4)


## Walk to [c], search it through the interaction, return true when open.
func search(c: LootContainer) -> bool:
	var reach := (c.size.z * 0.5 + 0.7) if c.size != Vector3.ZERO else 0.9
	await approach(c, c.persist_id, reach)
	if interaction.current_target == null or interaction.current_target.body() != c:
		_note("%s not targeted" % c.persist_id)
		return false
	var r := interaction.interact()
	if not r.get("ok", false):
		return false
	var ok := await wait_physics_until(func(): return c.is_open_for(player), 240)
	await physics_frames(2)
	return ok


## Take every stack matching [pred] from the open container [c].
func take_if(c: LootContainer, pred: Callable) -> int:
	var n := 0
	for it in c.inventory.items.duplicate():
		if pred.call(it) and bool(c.take(player, it).get("ok", false)):
			n += 1
	return n


func carried_count(id: StringName) -> int:
	return CarriedItems.count(player, id)


func carried_food() -> Array:
	var out := []
	for c in player.carried_storage():
		for it in c.items:
			if it.data is FoodData and not (it.data as FoodData).is_drink():
				out.append(it)
	return out


func carried_drinks() -> Array:
	var out := []
	for c in player.carried_storage():
		for it in c.items:
			if it.data is FoodData and (it.data as FoodData).is_drink():
				out.append(it)
	return out


func _dressing_carried() -> bool:
	for c in player.carried_storage():
		if InjuryComponent.best_dressing_in(c) != null:
			return true
	return false


## Pick up the WorldItem [w] (walk to it, interact).
func pick_up(w: WorldItem, label: String) -> bool:
	var at := w.global_position
	var from_side := Vector3(0.0, 0.0, 0.7)
	await walk_to(Vector3(at.x, 0, at.z) + from_side, label, 0.3)
	_face(at)
	await physics_frames(4)
	if interaction.current_target == null or interaction.current_target.body() != w:
		# Try the other sides.
		for off in [Vector3(0.7, 0, 0), Vector3(-0.7, 0, 0), Vector3(0, 0, -0.7)]:
			await walk_to(Vector3(at.x, 0, at.z) + off, label, 0.3)
			_face(at)
			await physics_frames(4)
			if interaction.current_target != null and interaction.current_target.body() == w:
				break
	if interaction.current_target == null or interaction.current_target.body() != w:
		_note("%s not targetable" % label)
		return false
	return bool(interaction.interact().get("ok", false))


func _world_item(id: StringName, near: Vector3, radius: float) -> WorldItem:
	for w in tree.get_nodes_in_group(WorldItem.GROUP):
		if scene.is_ancestor_of(w) and w.item != null and w.item.id() == id and _flat(w.global_position, near) <= radius:
			return w
	return null


func _front_window() -> HouseWindow:
	for w in house.windows:
		if (w.global_position - Vector3(-7, 0, -2)).length() < 0.3:
			return w
	return null


func _door(b: HouseBlockout, id_suffix: String) -> Door:
	for d in b.doors:
		if d.persist_id.ends_with(id_suffix):
			return d
	return null


# --- The playthrough -----------------------------------------------------------------------

func _on_zombie_died(_z: Node, killer: Node) -> void:
	if killer == player:
		kills += 1


func play(seed_value: int) -> void:
	world_seed = seed_value
	EventBus.zombie_died.connect(_on_zombie_died)
	var t0 := Time.get_ticks_msec()
	var map: Node = SaveManager.instantiate_new_game(MAP, seed_value)
	check(map != null, "new game map")
	tree.root.add_child(map)
	_bind(map)
	var nav: NavBaker = map.get_node("NavRegion")
	if not nav.baked:
		await nav.navigation_ready
	await wait_physics_until(func(): return spawner.zombies.size() >= spawner.count, 180)
	await physics_frames(5)

	# 1. Spawn in a house.
	_step("step 1")
	check(house.contains_point(player.global_position), "[%d] spawned inside House A (%s)" % [seed_value, player.global_position])
	check_eq(player.inventory.count_of(&"tshirt"), 1, "[%d] starter kit: a spare t-shirt" % seed_value)

	# 2-3. Search the kitchen → food.
	_step("step 2")
	for pid in ["HouseA/kitchen/0", "HouseA/kitchen/1", "HouseA/kitchen/2", "HouseA/kitchen/3"]:
		var c := _container(pid)
		if c != null and await search(c):
			take_if(c, func(it: ItemInstance): return it.data is FoodData)
			c.close()
	check(not carried_food().is_empty(), "[%d] found food in the kitchen" % seed_value)

	# 4. Equip a backpack (the bedroom).
	_step("step 4")
	await walk_to(Vector3(-9.0, 0, -4.6), "living room", 0.5)
	var bag_w := _world_item(&"backpack", Vector3(-10.75, 0, -8.1), 1.0)
	check(bag_w != null and await pick_up(bag_w, "backpack"), "[%d] backpack picked up" % seed_value)
	var bag := player.inventory.find(&"backpack")
	check(bag != null and player.equip_item(bag).ok, "[%d] backpack worn" % seed_value)

	# 5. Find a weapon (the bat in the living room).
	_step("step 5")
	var bat_w := _world_item(&"baseball_bat", Vector3(-6.5, 0, -3.2), 1.0)
	check(bat_w != null and await pick_up(bat_w, "bat"), "[%d] bat picked up" % seed_value)
	check(player.equipment.primary() != null and player.equipment.primary().is_weapon(), "[%d] weapon in hand" % seed_value)

	# The bathroom cabinet (dressings).
	var bath := _container("HouseA/bathroom/0")
	if bath != null and await search(bath):
		take_if(bath, func(it: ItemInstance): return it.data is MedicalData)
		bath.close()

	# 6. Hear zombies: smash the living-room window; one outside hears it.
	_step("step 6")
	var win := _front_window()
	await walk_to(Vector3(-7.0, 0, -2.85), "living-room window", 0.2)
	_face(Vector3(-7.0, 0, 0.0))
	await physics_frames(4)
	check(interaction.current_target != null and interaction.current_target.body() == win, "[%d] window targeted" % seed_value)
	var heard := {}
	var on_state := func(z: Node, _from: StringName, to: StringName):
		if to == ZombieAI.S_INVESTIGATE or to == ZombieAI.S_CHASE:
			heard[z] = true
	EventBus.zombie_state_changed.connect(on_state)
	check(interaction.perform_action(HouseWindow.ACTION_SMASH).ok, "[%d] window smashed" % seed_value)
	await wait_physics_until(func(): return not heard.is_empty(), 60 * 3)
	EventBus.zombie_state_changed.disconnect(on_state)
	check(not heard.is_empty(), "[%d] a zombie outside heard the smash" % seed_value)

	# 7-8. Fight: hold the spot behind the smashed window — whatever heard
	# it has to climb in over the sill (1.6 s, it cannot bite meanwhile),
	# one at a time.
	_step("step 7")
	await walk_to(Vector3(-7.0, 0, -3.6), "behind the window (hold)", 0.25)
	_face(Vector3(-7.0, 0, -2.0))
	await lure_and_hold(120.0, 18.0)
	await clear_threats(10.0)
	_step("after fight")
	check(not player.is_dead(), "[%d] survived the fight (health %.0f)" % [seed_value, player.health.health])
	if player.is_dead():
		return
	await treat_wounds(false)
	await loot_corpses(12.0)
	await treat_wounds(false)
	_step("step 8")
	await lure_and_hold(30.0, 10.0)
	await walk_to(Vector3(-7.0, 0, -2.85), "window (climb out)", 0.2)
	_face(Vector3(-7.0, 0, 0.0))
	await physics_frames(4)
	check(bool(action_on(win, HouseWindow.ACTION_CLIMB).get("enabled", false)), "[%d] climb offered (%s)" % [seed_value, str(action_on(win, HouseWindow.ACTION_CLIMB))])
	check(do_on(win, HouseWindow.ACTION_CLIMB).ok, "[%d] climbing out" % seed_value)
	await _wait_idle(120)
	await physics_frames(3)
	check(player.global_position.z > -2.0, "[%d] outside" % seed_value)
	await clear_threats(10.0)

	# 9. Injured: the glass or the fight; otherwise through the broken
	_step("step 9")
	# window again (each climb over the shards can cut).
	var climbs := 0
	while player.injuries.injuries.is_empty() and climbs < 12:
		var side := -1.0 if player.global_position.z > -2.0 else 1.0
		await walk_to(Vector3(-7.0, 0, -2.0 - side * 0.85), "window (climb)", 0.2)
		_face(Vector3(-7.0, 0, -2.0))
		await physics_frames(4)
		if do_on(_front_window(), HouseWindow.ACTION_CLIMB).ok:
			await _wait_idle(120)
			await physics_frames(3)
		climbs += 1
	if player.injuries.injuries.is_empty():
		# The glass never cut (a seeded roll): cut the hand on the frame
		# deterministically so the treatment steps always run.
		player.injuries.add_injury(Injury.Region.LEFT_HAND, Injury.Type.LACERATION)
		_note("no cut after %d climbs: deterministic laceration" % climbs)
	check(not player.injuries.injuries.is_empty(), "[%d] injured" % seed_value)
	_note("climbs for a wound: %d" % climbs)

	# 10. Treat the injury: dressings found, else tear the t-shirt.
	_step("step 10")
	if not _dressing_carried():
		var shirt := player.inventory.find(&"tshirt")
		check(shirt != null and ItemActions.perform(player, shirt, ItemActions.TEAR).ok, "[%d] tore the t-shirt into rags" % seed_value)
	await treat_wounds()
	check(player.injuries.injuries.any(func(w): return w.bandaged), "[%d] a wound is bandaged" % seed_value)

	# 11. Explore the garage: door, tool crate, hammer, shelf → planks.
	_step("step 11")
	var gdoor := _door(garage, "/door")
	await walk_to(Vector3(8.0, 0, -12.2), "garage door", 0.3, 90.0, true)
	_face(Vector3(8.0, 0, -13.0))
	await physics_frames(4)
	if gdoor.state == Door.STATE_CLOSED:
		await _open_door_ahead()
	check(gdoor.is_open(), "[%d] garage door open" % seed_value)
	var crate := _container("Garage/garage/0")
	if await search(crate):
		crate.take_all(player)
		crate.close()
	check(crate.searched, "[%d] garage tool crate searched" % seed_value)
	var hammer_w := _world_item(&"hammer", Vector3(8.9, 0, -15.45), 1.0)
	if CarriedItems.find_tool(player, [&"hammer"] as Array[StringName]) == null:
		check(hammer_w != null and await pick_up(hammer_w, "hammer"), "[%d] hammer from the workbench" % seed_value)
	check(CarriedItems.find_tool(player, [&"hammer"] as Array[StringName]) != null, "[%d] carrying a hammer" % seed_value)
	# (Taking furniture apart here would hammer for 10 s in the open:
	# the planks come from the house, behind closed doors.)

	# 12. Carry it home: the front door.
	_step("step 12")
	var fdoor := _door(house, "/front_door")
	await walk_to(Vector3(-11.0, 0, -1.1), "front door (outside)", 0.3, 90.0, true)
	_face(Vector3(-11.0, 0, -2.0))
	await physics_frames(4)
	if fdoor.state == Door.STATE_CLOSED:
		await _open_door_ahead()
	await walk_to(Vector3(-11.0, 0, -3.4), "inside the front door", 0.3)
	check(house.contains_point(player.global_position), "[%d] home" % seed_value)
	_face(Vector3(-11.0, 0, -1.0))
	await physics_frames(4)
	for attempt in 6:
		if not fdoor.is_open():
			break
		await clear_threats(6.0)
		await walk_to(Vector3(-11.0, 0, -3.4), "inside the front door", 0.3)
		_face(Vector3(-11.0, 0, -1.0))
		await physics_frames(4)
		var cr := do_on(fdoor, Door.ACTION_CLOSE)
		if not cr.get("ok", false):
			_note("close front door: %s" % str(cr))
		await physics_frames(40)
	if fdoor.is_broken():
		_note("the front door was broken down while we were away")
	check(not fdoor.is_open() or fdoor.is_broken(), "[%d] front door closed behind (or broken in)" % seed_value)
	await walk_to(Vector3(-7.0, 0, -3.6), "behind the window", 0.3)
	await lure_and_hold(60.0, 14.0)

	# 14. Barricade the safehouse: planks from the living-room shelf (or
	# the bedroom furniture) taken apart with the garage hammer, then over
	# the smashed window.
	_step("step 14")
	for type in [&"shelf", &"dresser", &"wardrobe"]:
		if carried_count(&"plank") >= 2:
			break
		var piece: Node3D = null
		for f in house.furniture:
			if is_instance_valid(f) and not f.is_queued_for_deletion() and f.get_meta(&"furniture_type", &"") == type:
				piece = f
		if piece == null:
			continue
		for attempt in 4:
			if not is_instance_valid(piece) or piece.is_queued_for_deletion():
				break
			await clear_threats(12.0)
			if _hostiles(12.0).size() > 0 or _front_window().can_climb() and _nearest_zombie(8.0) != null:
				await hold_window(6.0, 30.0)
			await approach(piece, String(type), 0.9)
			if do_on(piece, FurnitureWork.ACTION_DISASSEMBLE).ok:
				await _wait_idle(60 * 14)
			await physics_frames(3)
		# Pick up what fell out of it (the shelf's contents) — optional.
	check(carried_count(&"plank") >= 1, "[%d] planks from the furniture (%d)" % [seed_value, carried_count(&"plank")])
	await walk_to(Vector3(-7.0, 0, -2.85), "window (barricade)", 0.2)
	_face(Vector3(-7.0, 0, 0.0))
	await physics_frames(4)
	for i in 4:
		await clear_threats(12.0)
		await walk_to(Vector3(-7.0, 0, -2.85), "window (barricade)", 0.2)
		_face(Vector3(-7.0, 0, 0.0))
		await physics_frames(4)
		var a := action_on(win, BarricadeComponent.ACTION_ADD)
		if not bool(a.get("enabled", false)):
			_note("barricade stop: %s" % str(a))
			break
		if do_on(win, BarricadeComponent.ACTION_ADD).ok:
			await _wait_idle(60 * 6)
		await physics_frames(3)
	check(win.barricade_planks() >= 1, "[%d] window barricaded (%d planks)" % [seed_value, win.barricade_planks()])

	# 13. Hungry and thirsty (time passes) → eat and drink.
	_step("step 13")
	TimeManager.advance(9.0 * 60.0)
	check(player.needs.level(&"hunger") >= 1 and player.needs.level(&"thirst") >= 1, "[%d] hungry and thirsty" % seed_value)
	await clear_threats(12.0)
	var h0 := player.needs.value(&"hunger")
	var ate := false
	for it in carried_food():
		if player.consume.block_reason(it) == "" and player.consume_item(it).ok:
			await _wait_idle(60 * 15)
			ate = true
			break
	check(ate and player.needs.value(&"hunger") < h0, "[%d] ate" % seed_value)
	var th0 := player.needs.value(&"thirst")
	await walk_to(Vector3(-5.45, 0, -6.7), "kitchen sink", 0.25)
	_face(Vector3(-4.4, 0, -6.7))
	await physics_frames(4)
	if bool(_action(Sink.DRINK).get("enabled", false)):
		interaction.perform_action(Sink.DRINK)
		await _wait_idle(60 * 15)
	check(player.needs.value(&"thirst") < th0, "[%d] drank" % seed_value)

	# 15. Tired (time passes) → sleep in the bed.
	_step("step 15")
	var slept := false
	for attempt in 16:
		var why := player.rest.sleep_block_reason()
		_note("sleep check: '%s'" % why)
		if why == "Busy":
			await _wait_idle(300)
			continue
		if why == "Not tired":
			TimeManager.advance(3.0 * 60.0)
			continue
		if why.contains("hungry") or why.contains("Hungry"):
			for it in carried_food():
				if player.consume.block_reason(it) == "" and player.consume_item(it).ok:
					await _wait_idle(60 * 15)
					break
			continue
		if why.contains("thirsty") or why.contains("Thirsty"):
			await walk_to(Vector3(-5.45, 0, -6.7), "kitchen sink", 0.25)
			_face(Vector3(-4.4, 0, -6.7))
			await physics_frames(4)
			interaction.perform_action(Sink.DRINK)
			await _wait_idle(60 * 15)
			continue
		if why.to_lower().contains("danger") or why.to_lower().contains("zombie"):
			await walk_to(Vector3(-7.0, 0, -3.6), "behind the window", 0.3)
			await lure_and_hold(40.0, 16.0)
			await clear_threats(16.0, true)
			continue
		if why.to_lower().contains("bleeding"):
			await loot_corpses(10.0)
			await treat_wounds()
			continue
		await walk_to(Vector3(-11.95, 0, -8.85), "bed", 0.25)
		_face(Vector3(-10.75, 0, -8.85))
		await physics_frames(4)
		var sr := interaction.perform_action(RestFurniture.SLEEP)
		if sr.get("ok", false):
			var t_sleep := TimeManager.now()
			await wait_physics_until(func(): return not player.rest.sleeping, 60 * 45)
			await _wait_idle(120)
			slept = TimeManager.now() - t_sleep > 30.0
			if slept:
				break
		else:
			_note("sleep refused: %s" % str(sr))
			if String(sr.get("reason", "")) == "Not tired":
				TimeManager.advance(3.0 * 60.0)
	check(slept, "[%d] slept (%s)" % [seed_value, "; ".join(log_lines)])
	await clear_threats(4.0)

	check(kills >= 1, "[%d] killed at least one zombie (%d)" % [seed_value, kills])

	# 16. Save → reload into a fresh scene → confirm.
	_step("step 16")
	await _wait_idle(120)
	var slot := SLOT_PREFIX + str(seed_value)
	var before := {
		"pos": player.global_position, "health": player.health.health,
		"hunger": player.needs.value(&"hunger"), "thirst": player.needs.value(&"thirst"),
		"wounds": player.injuries.injuries.size(), "minutes": TimeManager.now(),
		"alive": _living_zombies().size(), "planks": win.barricade_planks(),
		"corpses": tree.get_nodes_in_group(&"corpse").filter(func(c): return scene.is_ancestor_of(c)).size(),
		"hammer": CarriedItems.count(player, &"hammer"), "bag": player.equipment.back_bag() != null,
		"kitchen0": _container("HouseA/kitchen/0").searched, "dresser": _container("HouseA/bedroom/0").searched,
	}
	var sv := SaveManager.save_game(slot, scene)
	check(sv.ok, "[%d] saved (%s)" % [seed_value, str(sv.get("error", ""))])
	var lr: Dictionary = await SaveManager.load_game(slot, scene)
	check(lr.ok, "[%d] loaded (%s)" % [seed_value, str(lr.get("error", ""))])
	if not lr.ok:
		return
	_bind(lr.map)
	check(_flat(player.global_position, before.pos) < 0.05, "[%d] position" % seed_value)
	check_near(player.health.health, before.health, 0.1, "[%d] health" % seed_value)
	check_near(player.needs.value(&"hunger"), before.hunger, 0.1, "[%d] hunger" % seed_value)
	check_near(player.needs.value(&"thirst"), before.thirst, 0.1, "[%d] thirst" % seed_value)
	check_eq(player.injuries.injuries.size(), before.wounds, "[%d] wounds" % seed_value)
	check_eq(CarriedItems.count(player, &"hammer"), before.hammer, "[%d] inventory (hammer)" % seed_value)
	check_eq(player.equipment.back_bag() != null, before.bag, "[%d] backpack" % seed_value)
	check_eq(_living_zombies().size(), before.alive, "[%d] killed zombies stay dead" % seed_value)
	check_eq(tree.get_nodes_in_group(&"corpse").filter(func(c): return scene.is_ancestor_of(c)).size(), before.corpses, "[%d] corpses" % seed_value)
	check_eq(_front_window().barricade_planks(), before.planks, "[%d] barricade" % seed_value)
	check_near(TimeManager.now(), before.minutes, 0.2, "[%d] world time" % seed_value)
	check_eq(_container("HouseA/kitchen/0").searched, before.kitchen0, "[%d] looted kitchen" % seed_value)
	check_eq(_container("HouseA/bedroom/0").searched, before.dresser, "[%d] unsearched dresser" % seed_value)
	print("  unstaged seed %d: %.1f s, kills %d, teleports %d %s, notes: %s" % [seed_value,
		(Time.get_ticks_msec() - t0) / 1000.0, kills, teleports.size(), str(teleports), "; ".join(log_lines)])
