class_name BarricadeComponent
extends Node3D
## Planks nailed across a door or a window (Round 9). A child "Barricade"
## of the fixture (Door / HouseWindow), created on demand by the first
## plank (ensure()). Planks are an Array of {health, max, tilt}; the last
## one is the OUTERMOST (nailed last) and takes the hits first.
##
## Rules (numbers in BarricadeData, data/barricades/wood_planks.tres):
## - "Barricade (N/4)": hammer carried (hands or bags) + 1 plank + 2 nails;
##   3 s busy (× carpentry), loud `hammering` (18 m, repeated while
##   working); materials are consumed only on completion (a hit on the
##   actor interrupts: nothing consumed). +10 carpentry XP per plank.
##   Planks go on the actor's side (`side`); the other side cannot add or
##   remove ("Barricaded on the other side").
## - "Remove barricade": crowbar (2 s, plank back 70 %, nails 50 %) or
##   hammer (4 s, 50 % / 30 %); the outermost plank comes off.
## - Blocks: movement / climbing (the fixture refuses "Barricaded"),
##   doors from both sides; sight through a window from
##   vision_block_planks (2) planks (a StaticBody on the window-pane layer
##   8 covers the opening); sound ×0.8 per plank (WallFixture
##   sound_barricade_factor(), used by SoundManager for rays and openings).
## - Zombies: group "breakable" (take_damage + blocks_path); at most
##   data.max_attackers (3) bang at once (claim_attacker); every hit makes a
##   12 m `barricade_bang`, a broken plank a 10 m `wood_break` + splinters.
##   Once empty, the opening is what it was underneath (window closed /
##   open / smashed, door closed).
## Visual: boards across the opening on `side`, stacked outward with a
## seeded ±8° tilt, nail heads at both ends; they darken with damage and
## show a crack below half health. Under the fixture's Visual so the
## cutaway stubs / fades them with the wall.

const NODE_NAME := "Barricade"
const GROUP := &"barricade"
const GROUP_BREAKABLE := &"breakable"
const DEFAULT_DATA := "res://data/barricades/wood_planks.tres"
const ACTION_ADD := &"barricade"
const ACTION_REMOVE := &"unbarricade"
const CONTEXT_ADD := &"barricade"
const CONTEXT_REMOVE := &"unbarricade"
## Window-pane layer (8, 0-based 7): blocks sight / bites / sound rays.
const VISION_LAYER_BIT := 7
## Board cross-section (height across the opening × thickness).
const BOARD_HEIGHT := 0.2
const BOARD_THICKNESS := 0.04
const BOARD_OVERHANG := 0.16
const MAX_TILT_DEGREES := 8.0
## Height fractions (of the opening) of successive planks: the first goes
## across the middle, the rest fill above / below.
const SLOTS_WINDOW: Array[float] = [0.6, 0.3, 0.86, 0.1]
const SLOTS_DOOR: Array[float] = [0.52, 0.28, 0.76, 0.08]

var data: BarricadeData
var fixture: Node3D
## &"door" / &"window".
var kind: StringName = &"window"
## [{health, max, tilt}] — index 0 innermost, last = outermost.
var planks: Array[Dictionary] = []
## +1: planks on the fixture's local +Z face, -1: on the -Z face.
var side: float = 1.0
## Zombies currently banging (instance id → weakref).
var attackers: Dictionary = {}
## The running nail / pry action (kept alive here).
var work: TimedWork = null

var _boards: Array[Node3D] = []
## Removal rolls (seeded from the fixture path: repeatable runs).
var _rng := RandomNumberGenerator.new()
var _rng_seeded: bool = false
var _serial: int = 0
var _body: StaticBody3D = null
var _nail_mat: StandardMaterial3D


## A StaticBody over a window opening while it blocks sight: sound rays
## that hit it are muffled through the fixture's barricade factor, not as
## a wall.
class PlanksBody:
	extends StaticBody3D
	var owner_fixture: Node = null

	func sound_obstacle_kind() -> StringName:
		return SoundMath.OPEN

	func barricade_fixture() -> Node:
		return owner_fixture

	func breakable_target() -> Node:
		return owner_fixture.call(&"breakable_target") if owner_fixture != null and owner_fixture.has_method(&"breakable_target") else null


# --- Lookup ------------------------------------------------------------------------

static func of(f: Node) -> BarricadeComponent:
	return f.get_node_or_null(NODE_NAME) as BarricadeComponent if f != null else null


static func planks_on(f: Node) -> int:
	var b := of(f)
	return b.plank_count() if b != null else 0


## The component of [f], created when missing.
static func ensure(f: Node3D) -> BarricadeComponent:
	var b := of(f)
	if b != null:
		return b
	b = BarricadeComponent.new()
	b.name = NODE_NAME
	b.fixture = f
	f.add_child(b)
	return b


static func default_data() -> BarricadeData:
	return load(DEFAULT_DATA) as BarricadeData


func _ready() -> void:
	_setup()
	add_to_group(GROUP)
	if not planks.is_empty():
		_changed()  # restored (from_dict) before entering the tree


## Defaults (also when used outside the tree: unit tests).
func _setup() -> void:
	if fixture == null:
		fixture = get_parent() as Node3D
	if data == null:
		data = default_data()
	if fixture != null and fixture.has_method(&"barricade_kind"):
		kind = StringName(fixture.call(&"barricade_kind"))
	if not _rng_seeded and fixture != null and fixture.is_inside_tree():
		_rng.seed = hash(String(fixture.get_path()))
		_rng_seeded = true
	if _nail_mat == null:
		_nail_mat = StandardMaterial3D.new()
		_nail_mat.albedo_color = Color(0.2, 0.2, 0.22)


func plank_count() -> int:
	return planks.size()


func max_planks() -> int:
	_setup()
	return data.max_planks_for(kind)


func is_full() -> bool:
	return plank_count() >= max_planks()


func total_health() -> float:
	var h := 0.0
	for p in planks:
		h += float(p.health)
	return h


## Health fraction of plank [i] (0..1).
func plank_fraction(i: int) -> float:
	if i < 0 or i >= planks.size():
		return 0.0
	return clampf(float(planks[i].health) / maxf(float(planks[i].max), 0.01), 0.0, 1.0)


## Which face of the fixture [p] is on (+1 local +Z, -1 local -Z).
func side_of(p: Vector3) -> float:
	var f := fixture if fixture != null else get_parent() as Node3D
	return 1.0 if f.to_local(p).z >= 0.0 else -1.0


# --- Planks (pure rules; the timed actions call these) ---------------------------

## Nail one plank with [health] on [p_side] (the first plank decides the
## side). Returns {ok, reason?, planks}.
func add_plank(health: float = -1.0, p_side: float = 0.0) -> Dictionary:
	_setup()
	if is_full():
		return {"ok": false, "reason": "Fully barricaded", "planks": plank_count()}
	var block: String = String(fixture.call(&"barricade_block_reason", null)) if fixture != null and fixture.has_method(&"barricade_block_reason") else ""
	if block != "":
		return {"ok": false, "reason": block, "planks": plank_count()}
	if planks.is_empty() and p_side != 0.0:
		side = signf(p_side)
	elif not planks.is_empty() and p_side != 0.0 and signf(p_side) != side:
		return {"ok": false, "reason": "Barricaded on the other side", "planks": plank_count()}
	var hp := health if health > 0.0 else data.plank_health
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(fixture.get_path()) if fixture and fixture.is_inside_tree() else "", planks.size(), _serial])
	_serial += 1
	planks.append({"health": hp, "max": hp, "tilt": rng.randf_range(-MAX_TILT_DEGREES, MAX_TILT_DEGREES)})
	_changed()
	return {"ok": true, "planks": plank_count()}



## Pry the outermost plank off. Returns {ok, reason?, plank: {…}}.
func remove_plank() -> Dictionary:
	if planks.is_empty():
		return {"ok": false, "reason": "Not barricaded"}
	var p: Dictionary = planks.pop_back()
	_changed()
	return {"ok": true, "plank": p, "planks": plank_count()}


## Breakable contract: something (a zombie) hits the barricade. The
## outermost plank takes it; at 0 it breaks off. Returns {ok, broken,
## planks, health}.
func take_damage(amount: float, source: Node = null, _info: Dictionary = {}) -> Dictionary:
	_setup()
	if planks.is_empty():
		return {"ok": false, "broken": false, "planks": 0, "health": 0.0}
	if amount <= 0.0:
		return {"ok": false, "broken": false, "planks": plank_count(), "health": total_health()}
	var top: Dictionary = planks[planks.size() - 1]
	top.health = float(top.health) - amount
	if float(top.health) <= 0.0:
		planks.pop_back()
		_emit(data.break_noise, source)
		_splinters(source)
		EventBus.barricade_plank_broken.emit(fixture, source)
		_changed()
		return {"ok": true, "broken": true, "planks": plank_count(), "health": total_health()}
	_emit(data.bang_noise, source)
	_refresh_board(planks.size() - 1)
	_shudder(planks.size() - 1)
	return {"ok": true, "broken": false, "planks": plank_count(), "health": total_health()}


## Breakable contract: planks are in the way.
func blocks_path() -> bool:
	return not planks.is_empty()


## Where a zombie faces / measures its distance to.
func interaction_prompt_position() -> Vector3:
	if fixture != null and fixture.has_method(&"interaction_prompt_position"):
		return fixture.call(&"interaction_prompt_position")
	return global_position


# --- Zombie attacker slots ---------------------------------------------------------

## Become one of the data.max_attackers banging on this opening.
func claim_attacker(z: Node) -> bool:
	_prune_attackers()
	var id := z.get_instance_id()
	if attackers.has(id):
		return true
	if attackers.size() >= data.max_attackers:
		return false
	attackers[id] = weakref(z)
	return true


func release_attacker(z: Node) -> void:
	if z != null:
		attackers.erase(z.get_instance_id())


func attacker_count() -> int:
	_prune_attackers()
	return attackers.size()


func _prune_attackers() -> void:
	for id in attackers.keys():
		var z: Variant = (attackers[id] as WeakRef).get_ref()
		if z == null or not is_instance_valid(z) or (z.has_method(&"is_dead") and z.is_dead()):
			attackers.erase(id)


# --- Interaction (listed by the fixture) ---------------------------------------------

## The barricade actions of [f] for [actor] (Door / HouseWindow append them).
static func actions_for(f: Node3D, actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var b := of(f)
	var d := b.data if b != null else default_data()
	var kind_id := StringName(f.call(&"barricade_kind")) if f.has_method(&"barricade_kind") else &"window"
	var n := b.plank_count() if b != null else 0
	var mx := d.max_planks_for(kind_id)
	var busy := TimedWork.is_busy(actor)
	var label := "Barricade (%d/%d)" % [n, mx]
	var reason := ""
	var block: String = String(f.call(&"barricade_block_reason", actor)) if f.has_method(&"barricade_block_reason") else ""
	if busy:
		reason = "Busy"
	elif block != "":
		reason = block
	elif b != null and n > 0 and actor is Node3D and b.side_of((actor as Node3D).global_position) != b.side:
		reason = "Barricaded on the other side"
	else:
		var tool := CarriedItems.find_tool(actor, d.build_tool_tags)
		reason = d.missing_reason(n, mx, tool != null, CarriedItems.count(actor, d.material_item),
			CarriedItems.count(actor, d.nails_item))
	out.append(Interactable.action(ACTION_ADD, label, reason == "", reason))
	if n > 0:
		var r2 := ""
		if busy:
			r2 = "Busy"
		elif actor is Node3D and b.side_of((actor as Node3D).global_position) != b.side:
			r2 = "Barricaded on the other side"
		elif CarriedItems.find_tool(actor, d.remove_tool_tags()) == null:
			r2 = "Need a hammer or crowbar"
		out.append(Interactable.action(ACTION_REMOVE, "Remove barricade", r2 == "", r2, true))
	return out


## Perform a barricade action on [f]. Returns the TimedWork start result.
static func perform(f: Node3D, action_id: StringName, actor: Node) -> Dictionary:
	for a in actions_for(f, actor):
		if a.id == action_id and not a.enabled:
			return {"ok": false, "reason": a.reason}
	match action_id:
		ACTION_ADD:
			return ensure(f).start_nailing(actor)
		ACTION_REMOVE:
			var b := of(f)
			return b.start_prying(actor) if b != null else {"ok": false, "reason": "Not barricaded"}
	return {"ok": false, "reason": "Unknown action"}


## Nail one plank: busy for build_seconds × carpentry, then consume 1 plank
## + 2 nails and add the plank (health × carpentry). Materials are checked
## again at the end (they could have been dropped meanwhile).
func start_nailing(actor: Node) -> Dictionary:
	_equip_tool(actor, CarriedItems.find_tool(actor, data.build_tool_tags))
	var skills := SkillComponent.of(actor)
	var secs := data.build_seconds_for(skills.carpentry_time() if skills else 1.0)
	var at_side := side_of((actor as Node3D).global_position) if actor is Node3D else side
	work = TimedWork.new()
	var holder := [at_side]
	_watch_fixture(true)
	var r := work.start(actor, CONTEXT_ADD, "Barricading… (%d/%d)" % [plank_count() + 1, max_planks()], secs,
		func(a: Node) -> void:
			_watch_fixture(false)
			_finish_nailing(a, holder[0]),
		func(_a: Node) -> void: _watch_fixture(false),
		data.build_noise, null, 1.5)
	if not bool(r.get("ok", false)):
		_watch_fixture(false)
	return r


## While nailing / prying: the fixture changing state underneath (door
## broken or opened, window smashed…) cancels the job.
var _watch_state: StringName = &""


func _watch_fixture(on: bool) -> void:
	if on:
		_watch_state = StringName(fixture.get(&"state")) if fixture != null else &""
		if not EventBus.door_state_changed.is_connected(_on_fixture_state):
			EventBus.door_state_changed.connect(_on_fixture_state)
			EventBus.window_state_changed.connect(_on_fixture_state)
	elif EventBus.door_state_changed.is_connected(_on_fixture_state):
		EventBus.door_state_changed.disconnect(_on_fixture_state)
		EventBus.window_state_changed.disconnect(_on_fixture_state)


func _on_fixture_state(f: Node, state: StringName) -> void:
	if f == fixture and state != _watch_state and work != null and work.running:
		work.cancel("Interrupted")


## PZ-like: the tool goes into the hands for the job (a hammer is also a
## weapon, so the survivor ends up holding it).
static func _equip_tool(actor: Node, tool: ItemInstance) -> void:
	if tool == null or actor == null or not actor.has_method(&"equip_item"):
		return
	var eq: Variant = actor.get("equipment") if "equipment" in actor else null
	if eq is Equipment and (eq as Equipment).hand_items().has(tool):
		return
	actor.call(&"equip_item", tool)


func _finish_nailing(actor: Node, at_side: float) -> void:
	var tool := CarriedItems.find_tool(actor, data.build_tool_tags)
	var reason := data.missing_reason(plank_count(), max_planks(), tool != null,
		CarriedItems.count(actor, data.material_item), CarriedItems.count(actor, data.nails_item))
	if reason != "":
		EventBus.interaction_refused.emit(actor, fixture, reason)
		return
	var skills := SkillComponent.of(actor)
	var hp := data.plank_health_for(skills.carpentry_health() if skills else 1.0)
	# The plank must actually go on (door still closed, nobody in the
	# window, same side…) before anything is used up or learned.
	var added := add_plank(hp, at_side)
	if not bool(added.ok):
		EventBus.interaction_refused.emit(actor, fixture, String(added.reason))
		return
	CarriedItems.consume(actor, data.material_item, data.material_per_plank)
	CarriedItems.consume(actor, data.nails_item, data.nails_per_plank)
	if skills:
		skills.add_xp(SkillComponent.CARPENTRY, data.xp_per_plank)


## Pry the outermost plank off with a crowbar (fast) or a hammer.
func start_prying(actor: Node) -> Dictionary:
	var tool := CarriedItems.find_tool(actor, data.remove_tool_tags())
	if tool == null:
		return {"ok": false, "reason": "Need a hammer or crowbar"}
	_equip_tool(actor, tool)
	var spec := data.remove_spec(tool.data.tags)
	var skills := SkillComponent.of(actor)
	var secs := float(spec.get("seconds", 3.0)) * (skills.carpentry_time() if skills else 1.0)
	work = TimedWork.new()
	var holder := [spec]
	_watch_fixture(true)
	var r := work.start(actor, CONTEXT_REMOVE, "Removing barricade…", secs,
		func(a: Node) -> void:
			_watch_fixture(false)
			_finish_prying(a, holder[0]),
		func(_a: Node) -> void: _watch_fixture(false),
		data.remove_noise, null, 1.5)
	if not bool(r.get("ok", false)):
		_watch_fixture(false)
	return r


func _finish_prying(actor: Node, spec: Dictionary) -> void:
	if remove_plank().ok:
		_setup()
		var y := data.remove_yield(spec, _rng.randf(), _rng.randf())
		if int(y.plank) > 0:
			CarriedItems.give(actor, data.material_item, int(y.plank))
		if int(y.nails) > 0:
			CarriedItems.give(actor, data.nails_item, int(y.nails))


# --- Effects -------------------------------------------------------------------

func _emit(category: StringName, source: Node) -> void:
	if not is_inside_tree() or fixture == null:
		return
	var p: Vector3 = fixture.call(&"sound_position", source) if fixture.has_method(&"sound_position") else global_position
	SoundManager.emit_sound(category, p, source)


func _splinters(source: Node) -> void:
	if fixture == null or not fixture.is_inside_tree():
		return
	var n := _normal() * side
	var host := fixture.get_parent()
	var at := _opening_world_center()
	at.y = fixture.global_position.y
	var toward := n
	if source is Node3D:
		toward = ((source as Node3D).global_position - at)
	Splinters.spawn(host, at + n * 0.35, toward, data.plank_color.darkened(0.1), hash([String(fixture.get_path()), plank_count()]))


func _normal() -> Vector3:
	var n := fixture.global_basis.z
	n.y = 0.0
	return n.normalized() if n.length_squared() > 0.0001 else Vector3.BACK


func _opening() -> Dictionary:
	if fixture != null and fixture.has_method(&"barricade_opening"):
		return fixture.call(&"barricade_opening")
	return {"center_x": 0.0, "width": 1.0, "bottom": 0.9, "top": 2.1, "face": 0.1}


func _opening_world_center() -> Vector3:
	var o := _opening()
	return fixture.global_transform * Vector3(float(o.center_x), (float(o.bottom) + float(o.top)) * 0.5, 0.0)


# --- Visual --------------------------------------------------------------------

func _changed() -> void:
	_rebuild_visual()
	_update_body()
	if fixture != null and fixture.has_method(&"on_barricade_changed"):
		fixture.call(&"on_barricade_changed", plank_count())
	if is_inside_tree():
		EventBus.barricade_changed.emit(fixture, plank_count())
		get_tree().call_group(&"occlusion_manager", &"forget_meshes", fixture)
	if planks.is_empty():
		remove_from_group(GROUP_BREAKABLE)
		attackers.clear()
	elif not is_in_group(GROUP_BREAKABLE):
		add_to_group(GROUP_BREAKABLE)


func _visual_parent() -> Node3D:
	var v := fixture.get_node_or_null("Visual") as Node3D if fixture != null else null
	return v if v != null else self


func _rebuild_visual() -> void:
	for b in _boards:
		if is_instance_valid(b):
			b.queue_free()
	_boards.clear()
	if fixture == null:
		return
	var o := _opening()
	var slots := SLOTS_DOOR if kind == &"door" else SLOTS_WINDOW
	var h := float(o.top) - float(o.bottom)
	var length := float(o.width) + BOARD_OVERHANG * 2.0
	var parent := _visual_parent()
	for i in planks.size():
		var p: Dictionary = planks[i]
		var frac: float = slots[i % slots.size()]
		var board := Node3D.new()
		board.name = "Plank%d" % i
		var z := side * (float(o.face) + BOARD_THICKNESS * 0.5 + 0.01 + i * 0.012)
		board.position = Vector3(float(o.center_x), float(o.bottom) + h * frac, z)
		board.rotation.z = deg_to_rad(float(p.tilt))
		var mi := MeshInstance3D.new()
		mi.name = "Board"
		var box := BoxMesh.new()
		box.size = Vector3(length, BOARD_HEIGHT, BOARD_THICKNESS)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.color_for(plank_fraction(i))
		mat.roughness = 0.95
		box.material = mat
		mi.mesh = box
		board.add_child(mi)
		# Grain line and nail heads so a board reads as a board.
		var grain := MeshInstance3D.new()
		grain.name = "Grain"
		var gb := BoxMesh.new()
		gb.size = Vector3(length * 0.92, 0.018, 0.004)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = data.plank_color.darkened(0.3)
		gb.material = gm
		grain.mesh = gb
		grain.position = Vector3(0, BOARD_HEIGHT * 0.18, side * (BOARD_THICKNESS * 0.5 + 0.002))
		board.add_child(grain)
		for sx in [-1.0, 1.0]:
			var nail := MeshInstance3D.new()
			nail.name = "Nail"
			var nb := BoxMesh.new()
			nb.size = Vector3(0.035, 0.035, 0.01)
			nb.material = _nail_mat
			nail.mesh = nb
			nail.position = Vector3(sx * (length * 0.5 - 0.07), 0.0, side * (BOARD_THICKNESS * 0.5 + 0.004))
			board.add_child(nail)
		var crack := MeshInstance3D.new()
		crack.name = "Crack"
		var cb := BoxMesh.new()
		cb.size = Vector3(length * 0.35, 0.022, 0.006)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.08, 0.06, 0.04)
		cb.material = cm
		crack.mesh = cb
		crack.position = Vector3(length * 0.12, -BOARD_HEIGHT * 0.1, side * (BOARD_THICKNESS * 0.5 + 0.003))
		crack.rotation.z = deg_to_rad(-12.0)
		crack.visible = plank_fraction(i) < 0.5
		board.add_child(crack)
		parent.add_child(board)
		_boards.append(board)


## Re-colour plank [i] for its health (darker, cracked below half).
func _refresh_board(i: int) -> void:
	if i < 0 or i >= _boards.size() or not is_instance_valid(_boards[i]):
		return
	var f := plank_fraction(i)
	var mi := _boards[i].get_node_or_null("Board") as MeshInstance3D
	if mi:
		var m := (mi.mesh as BoxMesh).material as StandardMaterial3D
		m.albedo_color = data.color_for(f)
		if mi.material_override is StandardMaterial3D:
			var a := (mi.material_override as StandardMaterial3D).albedo_color.a
			var c := data.color_for(f)
			(mi.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, a)
	var crack := _boards[i].get_node_or_null("Crack") as Node3D
	if crack:
		crack.visible = f < 0.5


func _shudder(i: int) -> void:
	if i < 0 or i >= _boards.size() or not is_instance_valid(_boards[i]) or not is_inside_tree():
		return
	var b := _boards[i]
	var z0 := b.position.z
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.tween_property(b, "position:z", z0, 0.15).from(z0 - side * 0.03)


## Health fraction colours of the planks (tests / HUD).
func board_colors() -> Array[Color]:
	var out: Array[Color] = []
	for b in _boards:
		var mi := b.get_node_or_null("Board") as MeshInstance3D
		out.append(((mi.mesh as BoxMesh).material as StandardMaterial3D).albedo_color if mi else Color.BLACK)
	return out


func board_count() -> int:
	var n := 0
	for b in _boards:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			n += 1
	return n


## Windows: a body over the opening on the window-pane layer while the
## planks block sight (vision_block_planks). Doors: the closed leaf
## already blocks everything.
func _update_body() -> void:
	if kind != &"window" or fixture == null:
		return
	var blocking := data.vision_blocked(plank_count())
	if _body == null:
		if not blocking:
			return
		var o := _opening()
		_body = PlanksBody.new()
		_body.name = "PlanksBody"
		_body.owner_fixture = fixture
		_body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(o.width), float(o.top) - float(o.bottom), 0.06)
		cs.shape = bs
		cs.position = Vector3(float(o.center_x), (float(o.bottom) + float(o.top)) * 0.5, side * (float(o.face) + 0.04))
		_body.add_child(cs)
		add_child(_body)
	_body.collision_layer = (1 << VISION_LAYER_BIT) if blocking else 0


# --- Save (Round 10) --------------------------------------------------------------

func to_dict() -> Dictionary:
	var ps: Array = []
	for p in planks:
		ps.append({"health": float(p.health), "max": float(p.max), "tilt": float(p.tilt)})
	return {"side": side, "planks": ps}


func from_dict(d: Dictionary) -> void:
	_setup()  # may run before _ready (save loading builds nodes first)
	side = float(d.get("side", 1.0))
	planks.clear()
	for p in d.get("planks", []):
		var mx := float(p.get("max", data.plank_health))
		var hp := clampf(float(p.get("health", mx)), 0.0, mx)
		if hp > 0.0 and planks.size() < max_planks():
			planks.append({"health": hp, "max": mx, "tilt": float(p.get("tilt", 0.0))})
	_changed()
