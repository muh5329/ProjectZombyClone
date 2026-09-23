class_name LootContainer
extends StaticBody3D
## A lootable container in the world (kitchen cabinet, fridge, dresser,
## crate…; ZombieCorpse extends it). Physics layers 1 + 4 (+ 6 when tall
## enough to hide the player), group "container".
##
## - Loot is rolled LAZILY the first time it is opened (Project Zomboid
##   style): fixed_items + LootResolver.roll() on the table resolved from
##   (building_type, room_type, container_type) through LootTableDB's
##   fallback chain (or [loot_table] when set), with an RNG seeded by
##   LootResolver.seed_for(world seed, persist_id) — the same world always
##   rolls the same loot, and an opened container is never re-rolled
##   (`searched`). Rolled items that do not fit the capacity are dropped.
## - Interaction: "Search <name>" → a busy "rummaging" action owned by the
##   actor ([search_seconds] the first time, [reopen_seconds] after) →
##   opens: lid swings open, EventBus.container_opened(actor, self), the
##   loot window reacts. While open: "Close". Walking more than
##   [max_open_distance] m away (flat distance to the box), dying or
##   leaving the tree closes it (EventBus.container_closed).
## - Rummaging and transfers live in `access` (ContainerAccess): take /
##   put / take_all / put_all here just delegate (rules: open for the
##   actor, not busy, fits, actor.can_release_item for outgoing items).
## - Blockout: with a non-zero [size] it builds its collision and a
##   ContainerVisual child "Visual" (box + lid tween).
## LootContainer itself is the interaction provider + persistence glue.
## - Persistence: to_dict()/from_dict() (searched flag + contents), group
##   "persistent" (WorldState) + "saveable" (Round 10: save_state / load_state).

const GROUP := &"container"
const LAYER_WORLD := 1
const LAYER_INTERACTABLES := 1 << 3
const LAYER_OCCLUDERS := 1 << 5

@export var container_type: StringName = &"crate"
## Player-facing name ("Kitchen cabinet"); derived from the type when empty.
@export var display_name: String = ""
## Weight capacity (kg).
@export var capacity: float = 20.0
## Explicit table; default: LootTableDB.resolve(building, room, type).
@export var loot_table: LootTable
## Stable id ("HouseA/kitchen/2"); seeds the loot and keys the save.
@export var persist_id: String = ""
## Loot context.
@export var room_type: StringName = &""
@export var building_type: StringName = &""
## Always added when the loot is rolled: [{id: StringName, count: int}].
@export var fixed_items: Array[Dictionary] = []
## Busy "rummaging" time of the first open / later opens (seconds).
@export var search_seconds: float = 1.0
@export var reopen_seconds: float = 0.5
@export var search_noise_radius: float = 3.0
@export var max_open_distance: float = 2.0
## Height of the interaction prompt above the origin.
@export var prompt_height: float = 1.0
## Label of the search action ("" → "Search <display name>").
@export var search_label: String = ""
## Spoil rate of food stored inside (fridge 0.25 — power is always on
## until electricity exists; Round 7).
@export var spoil_multiplier: float = 1.0
@export_group("Blockout")
## Box size (x width, y height, z depth; the front faces +Z). ZERO = the
## node brings its own visual / collision (corpses).
@export var size: Vector3 = Vector3.ZERO
@export var color: Color = Color(0.55, 0.4, 0.25)
## &"front" (door on the +Z face), &"top" (lid, crates), &"none".
@export var lid_style: StringName = &"front"
@export var occluder_min_height: float = 1.2

var inventory: ItemContainer
## True once the loot has been rolled (first open done).
var searched: bool = false
## Table id actually used by the roll (debug / tests).
var table_id: String = ""
## The actor currently looking inside (null = closed).
var opened_by: Node = null
## Rummage state + transfer service.
var access: ContainerAccess
## Blockout visual (null for corpses, which adopt the zombie's visual).
var visual: ContainerVisual
## Round 10: static containers join the Saveable group; corpses are
## dynamic (saved as spawn records by WorldSnapshot) and set this false.
var static_saveable: bool = true


func _init() -> void:
	inventory = ItemContainer.new(capacity)
	access = ContainerAccess.new(self)


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(WorldState.GROUP)
	if static_saveable and persist_id != "":
		add_to_group(Saveable.GROUP)
	inventory.capacity = capacity
	inventory.set_spoil_multiplier(spoil_multiplier)
	inventory.changed.connect(_on_inventory_changed)
	if display_name == "":
		display_name = default_name(container_type)
	if size != Vector3.ZERO:
		_build_blockout()
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)
	set_physics_process(false)
	var cfg := WorldConfig.find(get_tree())
	if cfg:
		cfg.state.register(self)


## "kitchen_cabinet" -> "Kitchen cabinet".
static func default_name(type: StringName) -> String:
	var s := String(type).replace("_", " ").strip_edges()
	return s.substr(0, 1).to_upper() + s.substr(1).to_lower() if s != "" else "Container"


func is_open() -> bool:
	return opened_by != null


func is_open_for(actor: Node) -> bool:
	return actor != null and opened_by == actor


func is_searching() -> bool:
	return access.is_searching()


# --- Loot --------------------------------------------------------------------

func resolve_table() -> LootTable:
	if loot_table != null:
		table_id = loot_table.resource_path
		return loot_table
	table_id = LootTableDB.resolve_id(building_type, room_type, container_type)
	return LootTableDB.get_table(table_id) if table_id != "" else null


func world_seed() -> int:
	var cfg := WorldConfig.find(get_tree()) if is_inside_tree() else null
	return cfg.world_seed if cfg else 0


func world_age_days() -> float:
	var cfg := WorldConfig.find(get_tree()) if is_inside_tree() else null
	return cfg.world_age_days if cfg else 0.0


## How old lazily rolled loot is (game minutes): the world's age at
## the start plus the game time played so far (Round 7).
func loot_age_minutes() -> float:
	return world_age_days() * 1440.0 + TimeManager.now()


func loot_seed() -> int:
	return LootResolver.seed_for(world_seed(), persist_id if persist_id != "" else String(name))


## Roll the contents once (no-op when already searched).
func ensure_loot() -> void:
	if searched:
		return
	searched = true
	var rng := RandomNumberGenerator.new()
	rng.seed = loot_seed()
	var list: Array[Dictionary] = []
	for f in fixed_items:
		list.append({"id": StringName(f.get("id", &"")), "count": int(f.get("count", 1)), "condition": int(f.get("condition", -1))})
	var fixed_n := list.size()
	var t := resolve_table()
	if t:
		list.append_array(LootResolver.roll(t, rng, world_age_days()))
	var cfg := WorldConfig.find(get_tree()) if is_inside_tree() else null
	var food_keep := cfg.loot_food_multiplier if cfg != null else 1.0
	for i in list.size():
		var e: Dictionary = list[i]
		var d := ItemDB.get_item(e.id)
		if d == null:
			push_warning("%s: unknown loot item '%s'" % [persist_id, e.id])
			continue
		if i >= fixed_n and food_keep < 1.0 and d.category == ItemData.Category.FOOD:
			var keep := 0
			for k in int(e.count):
				if rng.randf() < food_keep:
					keep += 1
			if keep == 0:
				continue
			e.count = keep
		var n := inventory.fit_count(d, int(e.count))
		if n > 0:
			var inst := ItemInstance.new(d, int(e.condition), n)
			if inst.perishable():
				# Rolled food is as old as the world (outbreak day 0 +
				# game time so far), aged at this container's rate.
				inst.age_minutes = loot_age_minutes() * spoil_multiplier
			inventory.add(inst)


# --- Interactable provider API --------------------------------------------------

func interaction_display_name() -> String:
	return display_name


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3.UP * prompt_height


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if is_open_for(actor):
		out.append(Interactable.action(&"close", "Close"))
	else:
		var busy := actor != null and bool(actor.get("is_busy"))
		var label := search_label if search_label != "" else "Search %s" % display_name
		out.append(Interactable.action(&"search", label, not busy, "Busy" if busy else ""))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	match action_id:
		&"search":
			return search(actor)
		&"close":
			close()
			return {"ok": true}
	return {"ok": false, "reason": "No such action"}


# --- Open / close ----------------------------------------------------------------

## Rummage ([search_seconds] first time, [reopen_seconds] after; the actor
## owns the busy tween, a little noise, damage cancels), then open for
## [actor]. Actors without begin_busy() open instantly.
func search(actor: Node) -> Dictionary:
	if actor != null and is_open_for(actor):
		return {"ok": true, "opened": true}
	return access.search(actor, reopen_seconds if searched else search_seconds)


func cancel_search() -> void:
	access.cancel_search()


## Open for [actor] right away (no rummage; rolls the loot if needed).
func open(actor: Node) -> void:
	ensure_loot()
	if opened_by == actor:
		return
	# One open container per actor: close whatever else it was looking in.
	for c in get_tree().get_nodes_in_group(GROUP):
		if c != self and c is LootContainer and c.opened_by == actor:
			c.close()
	if opened_by != null:
		close()
	opened_by = actor
	set_physics_process(true)
	if visual:
		visual.set_open(true)
	EventBus.container_opened.emit(actor, self)


func close() -> void:
	if opened_by == null:
		return
	var actor := opened_by
	opened_by = null
	set_physics_process(false)
	if visual:
		visual.set_open(false)
	EventBus.container_closed.emit(actor if is_instance_valid(actor) else null, self)


func _physics_process(_delta: float) -> void:
	if opened_by == null:
		set_physics_process(false)
		return
	if not is_instance_valid(opened_by) or not opened_by.is_inside_tree() \
			or (opened_by.has_method(&"is_dead") and opened_by.call(&"is_dead")) \
			or distance_to(opened_by) > max_open_distance:
		close()


func _exit_tree() -> void:
	if access.searching_actor != null:
		access.cancel_search()
	close()


## Flat distance from [actor] to this container's box (0 when touching).
func distance_to(actor: Node) -> float:
	if not actor is Node3D:
		return INF
	var p: Vector3 = to_local((actor as Node3D).global_position)
	var s := _box_shape()
	if s == null:
		return Vector2(p.x, p.z).length()
	var half := (s.shape as BoxShape3D).size * 0.5
	var dx := maxf(absf(p.x - s.position.x) - half.x, 0.0)
	var dz := maxf(absf(p.z - s.position.z) - half.z, 0.0)
	return Vector2(dx, dz).length()


func _box_shape() -> CollisionShape3D:
	for ch in get_children():
		if ch is CollisionShape3D and ch.shape is BoxShape3D:
			return ch
	return null


# --- Transfers (the loot window calls these; see ContainerAccess) ------------

## The ItemContainer a node exposes as `inventory`, or null.
static func inventory_of(node: Node) -> ItemContainer:
	return ContainerAccess.inventory_of(node)


## Container → actor: [count] (< 0 = whole stack) of the stack [item],
## into [into] (one of the actor's containers; default main inventory).
func take(actor: Node, item: ItemInstance, count: int = -1, into: ItemContainer = null) -> Dictionary:
	return access.take(actor, item, count, into)


## Actor → container (from wherever the actor keeps [item]).
func put(actor: Node, item: ItemInstance, count: int = -1) -> Dictionary:
	return access.put(actor, item, count)


## "Loot All": everything that fits goes to the actor ([into]).
func take_all(actor: Node, into: ItemContainer = null) -> Dictionary:
	return access.take_all(actor, into)


## "Transfer All": everything in [from] (default the actor's main
## inventory) the actor may let go of goes in here.
func put_all(actor: Node, from: ItemContainer = null) -> Dictionary:
	return access.put_all(actor, from)


func _on_inventory_changed() -> void:
	EventBus.inventory_changed.emit(self)


# --- Blockout -------------------------------------------------------------------

func _build_blockout() -> void:
	collision_layer = LAYER_WORLD | LAYER_INTERACTABLES
	collision_mask = 0
	if size.y >= occluder_min_height:
		collision_layer |= LAYER_OCCLUDERS
		add_to_group(&"occluder")
	visual = ContainerVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.build(size, color, lid_style)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = Vector3(0, size.y * 0.5, 0)
	add_child(shape)


func lid_open_fraction() -> float:
	var f := visual.open_fraction() if visual else -1.0
	if f < 0.0:
		return 1.0 if is_open() else 0.0
	return f


# --- Persistence --------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"persist_id": persist_id, "type": String(container_type),
		"searched": searched, "inventory": inventory.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	searched = bool(d.get("searched", false))
	if searched:
		inventory.from_dict(d.get("inventory", {}))
		inventory.capacity = capacity
	else:
		inventory.clear()


## Saveable contract (Round 10): the same data as to_dict(). An unsearched
## container stays unrolled (its loot is rolled lazily from the seed).
func save_state() -> Dictionary:
	var d := to_dict()
	d["kind"] = "container"
	return d


func load_state(d: Dictionary) -> void:
	if is_open():
		close()
	from_dict(d)
