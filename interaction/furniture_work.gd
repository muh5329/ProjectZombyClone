class_name FurnitureWork
extends Node3D
## Carpentry on a piece of furniture (Round 9): a child "FurnitureWork" of
## a dresser / shelf / fridge / sofa body, in group
## Interactable.GROUP_EXTENSION so the body's Interactable lists its
## actions next to the body's own ("Search dresser", "Rest"…):
##
## - "Block door" (movable pieces): 2 s busy + a 6 m `furniture_scrape`,
##   then the piece snaps flush behind the nearest closed door within
##   [door_search_radius] m, on the inside (the side the piece is on for
##   interior doors). The door then refuses to open ("Blocked by
##   furniture") and the piece becomes a breakable (group "breakable",
##   physics layer 9 "barricades" so the zombie obstacle ray finds it)
##   with [block_health] (200) hit points: zombies that broke the door
##   must smash it too. "Move back" returns it to where it stood.
## - "Disassemble" (pieces with a [disassemble_yield]): hammer or saw,
##   [disassemble_seconds] (10 s × carpentry) of loud work (hammering 18 m
##   / sawing 10 m); yields planks + nails, +[xp] carpentry; contents drop
##   on the floor. The renewable-ish plank source (PZ-like).
##
## Numbers come from the FurnitureCatalog entry (data/buildings/
## furniture_catalog.tres keys movable / block_health / disassemble).
## Known limit: the navmesh is not re-baked, so the old spot stays a hole
## and the new one is found by the zombies' obstacle ray.

const NODE_NAME := "FurnitureWork"
const ACTION_BLOCK := &"block_door"
const ACTION_UNBLOCK := &"unblock_door"
const ACTION_DISASSEMBLE := &"disassemble"
const CONTEXT_MOVE := &"move_furniture"
const CONTEXT_DISASSEMBLE := &"disassemble"
const GROUP_BREAKABLE := &"breakable"
## Physics layer 9 ("barricades", 0-based 8).
const BARRICADE_LAYER_BIT := 8
## Characters (player 2, zombies 3) that must not stand where it goes.
const CHARACTER_MASK := (1 << 1) | (1 << 2)

@export var display_name: String = "Furniture"
## Furniture footprint (x width, y height, z depth), origin at the floor.
@export var size: Vector3 = Vector3(1, 1, 0.5)
@export var movable: bool = false
@export var move_seconds: float = 2.0
@export var door_search_radius: float = 3.5
@export var block_health: float = 200.0
## {item_id: [min, max]} given by "Disassemble" (empty = cannot).
@export var disassemble_yield: Dictionary = {}
@export var disassemble_seconds: float = 10.0
@export var disassemble_tools: Array[StringName] = [&"hammer", &"saw"]
@export var xp: float = 15.0

var body: CollisionObject3D
## Round 10: stable save id ("HouseA/furniture/3"), set by HouseBlockout.
var persist_id: String = ""
## The door this piece is pushed against (null when not blocking).
var blocking_door: Node3D = null
var health: float = 200.0
var home: Transform3D
var work: TimedWork = null
var _rng := RandomNumberGenerator.new()
## World-layer bit the body had before it was pushed to a door.
var _world_layer: int = 1


func _ready() -> void:
	body = get_parent() as CollisionObject3D
	add_to_group(Interactable.GROUP_EXTENSION)
	if persist_id != "":
		add_to_group(Saveable.GROUP)
	health = block_health
	if body != null:
		home = body.global_transform
		_rng.seed = hash(String(body.get_path()))


static func of(n: Node) -> FurnitureWork:
	return n.get_node_or_null(NODE_NAME) as FurnitureWork if n != null else null


func can_disassemble() -> bool:
	return not disassemble_yield.is_empty()


func is_blocking() -> bool:
	return blocking_door != null and is_instance_valid(blocking_door)


## Door contract: is this piece still in front of [door]?
func blocks_door(door: Node) -> bool:
	return is_blocking() and blocking_door == door


# --- Breakable contract (only while blocking) -------------------------------------

func blocks_path() -> bool:
	return is_blocking()


func interaction_prompt_position() -> Vector3:
	return body.global_position + Vector3.UP * minf(size.y, 1.0) if body else global_position


## A zombie hits the piece. At 0 it is destroyed (wood_break, splinters,
## contents on the floor). Returns {ok, broken, health}.
func take_damage(amount: float, source: Node = null, _info: Dictionary = {}) -> Dictionary:
	if not is_blocking() or amount <= 0.0:
		return {"ok": false, "broken": false, "health": health}
	health -= amount
	if health <= 0.0:
		destroy(source)
		return {"ok": true, "broken": true, "health": 0.0}
	SoundManager.emit_sound(&"barricade_bang", body.global_position, source)
	if is_inside_tree():
		var v := body.get_node_or_null("Visual") as Node3D
		if v:
			var tw := create_tween()
			tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
			tw.tween_property(v, "position:x", 0.0, 0.15).from(0.04)
	return {"ok": true, "broken": false, "health": health}


## Break the piece apart: contents dropped, splinters, noise, body freed.
func destroy(source: Node = null) -> void:
	if body == null or body.is_queued_for_deletion():
		return
	_release_door()
	_drop_contents()
	var at := body.global_position
	SoundManager.emit_sound(&"wood_break", at, source)
	Splinters.spawn(body.get_parent(), at, Vector3.ZERO, Color(0.5, 0.36, 0.22))
	EventBus.furniture_destroyed.emit(body, source)
	WorldConfig.record_destroyed(self)
	body.collision_layer = 0  # out of the re-bake right away
	body.queue_free()
	NavBaker.request_rebake_in(get_tree())


# --- Interaction extension --------------------------------------------------------

func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var busy := TimedWork.is_busy(actor)
	if movable:
		if is_blocking():
			out.append(Interactable.action(ACTION_UNBLOCK, "Move %s back" % display_name.to_lower(), not busy, "Busy" if busy else ""))
		else:
			var reason := "Busy" if busy else block_reason()
			out.append(Interactable.action(ACTION_BLOCK, "Block door with %s" % display_name.to_lower(), reason == "", reason))
	if can_disassemble():
		var r2 := "Busy" if busy else ""
		if r2 == "" and CarriedItems.find_tool(actor, disassemble_tools) == null:
			r2 = "Need a hammer or saw"
		out.append(Interactable.action(ACTION_DISASSEMBLE, "Disassemble", r2 == "", r2))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	match action_id:
		ACTION_BLOCK:
			return start_block(actor)
		ACTION_UNBLOCK:
			return start_unblock(actor)
		ACTION_DISASSEMBLE:
			return start_disassemble(actor)
	return {"ok": false, "reason": "Unknown action"}


# --- Door blocking --------------------------------------------------------------

## The nearest closed, unbroken door within door_search_radius (flat, from
## the piece), or null.
func nearest_door() -> Node3D:
	if body == null or not body.is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := door_search_radius
	for d in body.get_tree().get_nodes_in_group(&"door"):
		if not d is Door:
			continue
		var c: Vector3 = (d as Door).sound_opening_center()
		var dist := Vector2(c.x - body.global_position.x, c.z - body.global_position.z).length()
		if dist <= best_d and reachable_door(d):
			best_d = dist
			best = d
	return best


## Can this piece be pushed to [door]'s block spot without passing a
## wall? The spot must be in the piece's room (same building room, or
## both outdoors) with a clear line (world layer) from the piece to it.
func reachable_door(door: Door) -> bool:
	var t := block_transform(door)
	var building := EntryPlanner.building_of(door)
	var room_here: Node = building.call(&"room_at", body.global_position) if building != null and building.has_method(&"room_at") else null
	var room_there: Node = building.call(&"room_at", t.origin) if building != null and building.has_method(&"room_at") else null
	if room_here != room_there:
		return false
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3.UP * 0.5, t.origin + Vector3.UP * 0.5, 1)
	q.exclude = [body.get_rid()]
	return space.intersect_ray(q).is_empty()


## "" when the piece can be pushed in front of a door now.
func block_reason() -> String:
	var d := nearest_door() as Door
	if d == null:
		return "No door nearby"
	if d.is_broken():
		return "Door is broken"
	if d.is_open():
		return "Close the door first"
	if d.furniture_blocker() != null:
		return "Door already blocked"
	if body is LootContainer and (body as LootContainer).is_searching():
		return "Busy"
	var t := block_transform(d)
	if _occupied(t):
		return "Blocked"
	return ""


## Where the piece goes to block [door]: flush against the inside face,
## centred on the doorway, its depth along the wall normal.
func block_transform(door: Door) -> Transform3D:
	var c := door.sound_opening_center()
	var n := door.wall_normal()
	var inward := -n
	if door.outward.length_squared() > 0.5:
		inward = -door.outward.normalized()
	elif (body.global_position - c).dot(n) > 0.0:
		inward = n
	var pos := c + inward * (door.wall_thickness * 0.5 + size.z * 0.5 + 0.04)
	pos.y = body.global_position.y
	var yaw := atan2(inward.x, inward.z)
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func _occupied(t: Transform3D) -> bool:
	var space := body.get_world_3d().direct_space_state if body.is_inside_tree() else null
	if space == null:
		return false
	var q := PhysicsShapeQueryParameters3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(maxf(size.x - 0.08, 0.1), maxf(size.y - 0.1, 0.1), maxf(size.z - 0.08, 0.1))
	q.shape = bs
	# Characters, walls / props / furniture (world 1) and pieces already
	# blocking a door (barricades 9).
	q.collision_mask = CHARACTER_MASK | 1 | (1 << BARRICADE_LAYER_BIT)
	q.exclude = [body.get_rid()]
	q.transform = t * Transform3D(Basis(), Vector3(0, size.y * 0.5 + 0.05, 0))
	return not space.intersect_shape(q, 1).is_empty()


func start_block(actor: Node) -> Dictionary:
	var reason := block_reason()
	if reason != "":
		return {"ok": false, "reason": reason}
	_close_container()
	work = TimedWork.new()
	return work.start(actor, CONTEXT_MOVE, "Pushing the %s…" % display_name.to_lower(), move_seconds,
		_finish_block, Callable(), &"furniture_scrape", body, 1.0)


func _finish_block(actor: Node) -> void:
	var d := nearest_door() as Door
	if d == null or block_reason() != "":
		if actor != null:
			EventBus.interaction_refused.emit(actor, body, block_reason() if d != null else "No door nearby")
		return
	home = body.global_transform
	body.global_transform = block_transform(d)
	blocking_door = d
	d.blocker = body
	health = block_health
	# Like a door leaf: off the world layer (the navmesh keeps the doorway
	# and the old spot walkable after the re-bake; zombies path to the
	# door and find the piece with their obstacle ray on layer 9, which
	# characters also collide with).
	_world_layer = body.collision_layer & 1
	body.collision_layer = (body.collision_layer & ~1) | (1 << BARRICADE_LAYER_BIT)
	add_to_group(GROUP_BREAKABLE)
	NavBaker.request_rebake_in(get_tree())
	EventBus.furniture_moved.emit(body, d)


func start_unblock(actor: Node) -> Dictionary:
	if not is_blocking():
		return {"ok": false, "reason": "Not blocking a door"}
	work = TimedWork.new()
	return work.start(actor, CONTEXT_MOVE, "Pushing the %s back…" % display_name.to_lower(), move_seconds,
		_finish_unblock, Callable(), &"furniture_scrape", body, 1.0)


func _finish_unblock(actor: Node) -> void:
	if not is_blocking():
		return
	if _occupied(home):
		if actor != null:
			EventBus.interaction_refused.emit(actor, body, "Blocked")
		return
	_release_door()
	body.global_transform = home
	NavBaker.request_rebake_in(get_tree())
	EventBus.furniture_moved.emit(body, null)


func _release_door() -> void:
	if blocking_door != null and is_instance_valid(blocking_door) and blocking_door.get(&"blocker") == body:
		blocking_door.set(&"blocker", null)
	blocking_door = null
	if body != null and body.collision_layer & (1 << BARRICADE_LAYER_BIT):
		body.collision_layer = (body.collision_layer & ~(1 << BARRICADE_LAYER_BIT)) | _world_layer
	if is_in_group(GROUP_BREAKABLE):
		remove_from_group(GROUP_BREAKABLE)


# --- Disassemble ------------------------------------------------------------------

func start_disassemble(actor: Node) -> Dictionary:
	var tool := CarriedItems.find_tool(actor, disassemble_tools)
	if tool == null:
		return {"ok": false, "reason": "Need a hammer or saw"}
	if body is LootContainer and (body as LootContainer).is_searching():
		return {"ok": false, "reason": "Busy"}
	_close_container()
	var skills := SkillComponent.of(actor)
	var secs := disassemble_seconds * (skills.carpentry_time() if skills else 1.0)
	var noise := &"hammering" if tool.data.has_tag(&"hammer") else &"sawing"
	work = TimedWork.new()
	return work.start(actor, CONTEXT_DISASSEMBLE, "Disassembling the %s…" % display_name.to_lower(), secs,
		_finish_disassemble, Callable(), noise, body, 2.0)


## Pure: the yield for rolls [rolls] (one 0..1 per yield entry, in key
## order): {item_id: count}.
static func yield_for(spec: Dictionary, rolls: Array) -> Dictionary:
	var out := {}
	var i := 0
	for id in spec:
		var r: Array = spec[id]
		var lo := int(r[0])
		var hi := int(r[1]) if r.size() > 1 else lo
		var roll: float = rolls[i] if i < rolls.size() else 0.0
		out[StringName(id)] = lo + mini(int(floor(roll * float(hi - lo + 1))), hi - lo)
		i += 1
	return out


func _finish_disassemble(actor: Node) -> void:
	if body == null or body.is_queued_for_deletion():
		return
	var rolls: Array = []
	for _k in disassemble_yield:
		rolls.append(_rng.randf())
	var got := yield_for(disassemble_yield, rolls)
	for id: StringName in got:
		if int(got[id]) > 0:
			CarriedItems.give(actor, id, int(got[id]))
	var skills := SkillComponent.of(actor)
	if skills:
		skills.add_xp(SkillComponent.CARPENTRY, xp)
	_release_door()
	_drop_contents()
	Splinters.spawn(body.get_parent(), body.global_position, Vector3.ZERO, Color(0.5, 0.36, 0.22))
	EventBus.furniture_destroyed.emit(body, actor)
	WorldConfig.record_destroyed(self)
	body.collision_layer = 0
	body.queue_free()
	NavBaker.request_rebake_in(get_tree())


func _close_container() -> void:
	if body is LootContainer and (body as LootContainer).is_open():
		(body as LootContainer).close()


## The contents fall on the floor as world items (an unsearched piece
## rolls its loot first — it was in there all along).
func _drop_contents() -> void:
	if not body is LootContainer:
		return
	var c := body as LootContainer
	c.close()
	c.ensure_loot()
	if c.inventory == null:
		return
	var host := body.get_parent()
	var i := 0
	for it in c.inventory.items.duplicate():
		c.inventory.remove(it)
		var w := WorldItem.for_instance(it)
		host.add_child(w)
		w.global_position = body.global_position + Vector3(0.25 * cos(i * 1.3), 0.02, 0.25 * sin(i * 1.3))
		i += 1


# --- Save (Round 10) ------------------------------------------------------------------

## {blocking: door persist_id or "", health}. A destroyed piece is simply
## absent from the save (remove_for_load).
func save_state() -> Dictionary:
	var door_id := ""
	if is_blocking():
		door_id = String(blocking_door.get(&"persist_id"))
	return {"kind": "furniture", "blocking": door_id, "health": health}


## Silent restore: pushed back in front of its door (same transform and
## layers as _finish_block) without the noise / events.
func load_state(d: Dictionary) -> void:
	if body == null:
		return
	if is_blocking():
		_release_door()
		body.global_transform = home
	health = clampf(float(d.get("health", block_health)), 0.0, block_health)
	var door_id := String(d.get("blocking", ""))
	if door_id == "":
		return
	var door := SaveManager.find_saveable(door_id) as Door
	if door == null:
		push_warning("FurnitureWork %s: saved door '%s' not found" % [persist_id, door_id])
		return
	home = body.global_transform
	body.global_transform = block_transform(door)
	blocking_door = door
	door.blocker = body
	_world_layer = body.collision_layer & 1
	body.collision_layer = (body.collision_layer & ~1) | (1 << BARRICADE_LAYER_BIT)
	add_to_group(GROUP_BREAKABLE)


## The piece was destroyed / taken apart in the saved world: gone, with
## no drops (its contents were saved as world items) and no noise.
func remove_for_load() -> void:
	if body == null or body.is_queued_for_deletion():
		return
	_release_door()
	WorldConfig.record_destroyed(self)
	if body is LootContainer:
		(body as LootContainer).inventory.clear()
		(body as LootContainer).searched = true
	body.collision_layer = 0
	body.remove_from_group(Saveable.GROUP)
	remove_from_group(Saveable.GROUP)
	body.queue_free()
