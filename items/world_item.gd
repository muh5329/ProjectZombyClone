class_name WorldItem
extends StaticBody3D
## An item lying in the world: a blockout box (ItemData.color /
## world_size) on physics layer 4 (interactables) with an Interactable
## "Pick up <name>". Picking up hands an ItemInstance to the actor's
## duck-typed pick_up_item(item) -> {ok, reason?} and frees this node.
## Group "world_item".
##
## Round 6: a bag on the ground (an instance with `contents`) can also be
## opened like a container ("Open <bag>" / "Close"): it exposes its
## contents as `inventory`, opens instantly for the actor
## (EventBus.container_opened → the loot window), closes when the actor
## walks > [max_open_distance] away, is picked up, or leaves the tree;
## transfers go through a ContainerAccess exactly like a LootContainer.
## drop(item, actor) puts an item at an actor's feet (Player "Drop").

const LAYER_INTERACTABLES := 1 << 3
const GROUP := &"world_item"

@export var item_data: ItemData
## Starting condition (-1 = the data's max).
@export var condition: int = -1
@export var max_open_distance: float = 2.0

var item: ItemInstance
## The actor looking into this bag (null = closed).
var opened_by: Node = null
## Transfer rules when opened (bags only).
var access: ContainerAccess
## Rummage noise (none: opening a bag is instant and quiet).
var search_noise_radius: float = 0.0

## Player-facing name (the loot window header).
var display_name: String:
	get: return item.display_name() if item else "Item"

## The bag's contents (null for anything else) — ContainerAccess reads it.
var inventory: ItemContainer:
	get: return item.contents if item else null


func _ready() -> void:
	add_to_group(GROUP)
	collision_layer = LAYER_INTERACTABLES
	collision_mask = 0
	if item == null:
		item = ItemInstance.new(item_data, condition)
	if item_data == null and item != null:
		item_data = item.data
	access = ContainerAccess.new(self)
	var size := item_data.world_size if item_data else Vector3(0.3, 0.1, 0.3)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = item_data.color if item_data else Color.GRAY
	box.material = mat
	mesh.mesh = box
	mesh.position = Vector3(0, size.y * 0.5 + 0.04, 0)
	add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var bs := BoxShape3D.new()
	# A little taller than the mesh so the interaction query finds it easily.
	bs.size = Vector3(maxf(size.x, 0.3), 0.3, maxf(size.z, 0.3))
	shape.shape = bs
	shape.position = Vector3(0, 0.15, 0)
	add_child(shape)
	if Interactable.of(self) == null:
		var it := Interactable.new()
		it.name = "Interactable"
		add_child(it)
	set_physics_process(false)
	if is_bag() and not item.contents.changed.is_connected(_on_contents_changed):
		item.contents.changed.connect(_on_contents_changed)


func _on_contents_changed() -> void:
	EventBus.inventory_changed.emit(self)


## Build a WorldItem for an existing instance (drops, tests).
static func for_instance(inst: ItemInstance) -> WorldItem:
	var w := WorldItem.new()
	w.item_data = inst.data
	w.item = inst
	return w


## Put [inst] (already out of every container) on the ground at [actor]'s
## feet, a little in front, under the actor's parent (the map) so it stays
## in the scene. Returns the new WorldItem.
static func drop(inst: ItemInstance, actor: Node3D) -> WorldItem:
	var w := for_instance(inst)
	var parent := actor.get_parent() if actor != null else null
	if parent == null:
		return w
	parent.add_child(w)
	var fwd := Vector3.FORWARD
	if actor.has_method(&"facing_vector"):
		fwd = actor.call(&"facing_vector")
	# Scatter successive drops a little so they do not stack exactly.
	var n := actor.get_tree().get_nodes_in_group(GROUP).size()
	var side := Vector3(-fwd.z, 0, fwd.x) * (float(n % 5) - 2.0) * 0.08
	w.global_position = Vector3(actor.global_position.x, actor.global_position.y - 0.1, actor.global_position.z) + fwd * 0.45 + side
	w.rotation.y = randf() * TAU
	return w


func is_bag() -> bool:
	return item != null and item.contents != null


func is_open_for(actor: Node) -> bool:
	return actor != null and opened_by == actor


func interaction_display_name() -> String:
	return display_name


func interaction_prompt_position() -> Vector3:
	return global_position + Vector3.UP * 0.2


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var can := actor != null and actor.has_method(&"pick_up_item")
	out.append(Interactable.action(&"pick_up", "Pick up %s" % interaction_display_name(), can, "" if can else "Can't carry"))
	if is_bag():
		if is_open_for(actor):
			out.append(Interactable.action(&"close", "Close %s" % interaction_display_name()))
		else:
			out.append(Interactable.action(&"open", "Open %s" % interaction_display_name()))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	match action_id:
		&"open":
			if not is_bag():
				return {"ok": false, "reason": "Not a container"}
			open(actor)
			return {"ok": true, "opened": true}
		&"close":
			close()
			return {"ok": true}
		&"pick_up":
			if actor == null or not actor.has_method(&"pick_up_item"):
				return {"ok": false, "reason": "Can't carry"}
			if opened_by != null:
				close()
			var r: Dictionary = actor.call(&"pick_up_item", item)
			if r.get("ok", false):
				collision_layer = 0
				queue_free()
			return r
	return {"ok": false, "reason": "No such action"}


# --- Bag on the ground: open / close / transfers ----------------------------------

func open(actor: Node) -> void:
	if not is_bag() or opened_by == actor:
		return
	for c in get_tree().get_nodes_in_group(LootContainer.GROUP):
		if c is LootContainer and c.opened_by == actor:
			c.close()
	for w in get_tree().get_nodes_in_group(GROUP):
		if w != self and w is WorldItem and w.opened_by == actor:
			w.close()
	if opened_by != null:
		close()
	opened_by = actor
	set_physics_process(true)
	EventBus.container_opened.emit(actor, self)


func close() -> void:
	if opened_by == null:
		return
	var actor := opened_by
	opened_by = null
	set_physics_process(false)
	EventBus.container_closed.emit(actor if is_instance_valid(actor) else null, self)


func _physics_process(_delta: float) -> void:
	if opened_by == null:
		set_physics_process(false)
		return
	if not is_instance_valid(opened_by) or not opened_by.is_inside_tree() \
			or (opened_by.has_method(&"is_dead") and opened_by.call(&"is_dead")) \
			or _flat_distance(opened_by) > max_open_distance:
		close()


func _exit_tree() -> void:
	close()
	if is_bag() and item.contents.changed.is_connected(_on_contents_changed):
		item.contents.changed.disconnect(_on_contents_changed)


func _flat_distance(n: Node) -> float:
	if not n is Node3D:
		return INF
	var d := (n as Node3D).global_position - global_position
	return Vector2(d.x, d.z).length()


func take(actor: Node, it: ItemInstance, count: int = -1, into: ItemContainer = null) -> Dictionary:
	return access.take(actor, it, count, into)


func put(actor: Node, it: ItemInstance, count: int = -1) -> Dictionary:
	return access.put(actor, it, count)


func take_all(actor: Node, into: ItemContainer = null) -> Dictionary:
	return access.take_all(actor, into)


func put_all(actor: Node, from: ItemContainer = null) -> Dictionary:
	return access.put_all(actor, from)
