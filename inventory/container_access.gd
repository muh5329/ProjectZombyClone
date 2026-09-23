class_name ContainerAccess
extends RefCounted
## Access service of one LootContainer (owned by it): the timed
## "rummaging" state and the transfer rules / moves between the
## container's `inventory` and an actor's `inventory`.
##
## Rummage: search(actor) makes the actor busy (begin_busy(&"search"),
## the actor owns the tween) for search / reopen seconds, emits
## timed_action_started + a small sound; getting hurt cancels it
## (EventBus.character_damaged); on completion the container opens.
##
## Transfers (take / put / take_all / put_all) check, in order: the
## container is open for the actor, both inventories exist, the actor is
## not busy, and — for items leaving the actor — the actor's
## can_release_item(item) (duck-typed; the player refuses its equipped /
## swung weapon mid-swing). Each move emits
## EventBus.item_transferred(from, to, item); refusals go out as
## EventBus.interaction_refused(actor, container, reason).
##
## Round 6: [container] is any node with `inventory`, `display_name`,
## `is_open_for(actor)` (LootContainer, a bag WorldItem on the ground).
## The actor side of a move may be any ItemContainer the actor owns
## (duck-typed actor.owns_container(c): main inventory, worn bag,
## equipment slots); default = the actor's `inventory`. Items leave the
## actor from wherever they are (item.owner_container()).

const SEARCH_CONTEXT := &"search"

## The owning container node (LootContainer / WorldItem), duck-typed.
var container: Node
var searching_actor: Node = null


func _init(c: Node) -> void:
	container = c


# --- Rummaging ---------------------------------------------------------------

func is_searching() -> bool:
	return searching_actor != null and is_instance_valid(searching_actor) \
			and bool(searching_actor.get("is_busy")) \
			and searching_actor.get("busy_context") == SEARCH_CONTEXT


func search(actor: Node, seconds: float) -> Dictionary:
	if actor == null:
		return {"ok": false, "reason": "Nobody"}
	if bool(actor.get("is_busy")):
		return {"ok": false, "reason": "Busy"}
	if seconds <= 0.0 or not actor.has_method(&"begin_busy"):
		container.open(actor)
		return {"ok": true, "opened": true}
	searching_actor = actor
	if not EventBus.character_damaged.is_connected(_on_character_damaged):
		EventBus.character_damaged.connect(_on_character_damaged)
	if actor.has_signal(&"busy_cancelled") and not actor.is_connected(&"busy_cancelled", _on_busy_cancelled):
		actor.connect(&"busy_cancelled", _on_busy_cancelled)
	var tw: Tween = actor.call(&"begin_busy", SEARCH_CONTEXT)
	tw.tween_interval(seconds)
	tw.tween_callback(_finish.bind(actor))
	EventBus.timed_action_started.emit(actor, SEARCH_CONTEXT, "Rummaging in %s…" % container.display_name.to_lower(), seconds)
	if container.search_noise_radius > 0.0:
		var at: Vector3 = (actor as Node3D).global_position if actor is Node3D else container.global_position
		SoundManager.emit_sound(&"rummage", at, actor, {"radius": container.search_noise_radius})
	return {"ok": true, "searching": true, "seconds": seconds}


## Abort a running rummage: the actor's busy action is cancelled, nothing opens.
func cancel_search() -> void:
	var actor := searching_actor
	if actor == null or not is_instance_valid(actor):
		_stop_listening()
		searching_actor = null
		return
	if not (actor.has_method(&"cancel_busy") and bool(actor.call(&"cancel_busy", SEARCH_CONTEXT))):
		_on_busy_cancelled(SEARCH_CONTEXT)


## The rummage busy action was cut (hurt, overridden by another busy
## action, death): nothing opens.
func _on_busy_cancelled(context: StringName) -> void:
	if context != SEARCH_CONTEXT or searching_actor == null:
		return
	var actor := searching_actor
	_stop_listening()
	searching_actor = null
	if not is_instance_valid(actor):
		return
	EventBus.timed_action_finished.emit(actor, SEARCH_CONTEXT, false)
	EventBus.interaction_refused.emit(actor, container, "Interrupted")


func _on_character_damaged(character: Node, _amount: float, _source: Node, _info: Dictionary) -> void:
	if character != null and character == searching_actor:
		cancel_search()


func _stop_listening() -> void:
	if EventBus.character_damaged.is_connected(_on_character_damaged):
		EventBus.character_damaged.disconnect(_on_character_damaged)
	var a := searching_actor
	if a != null and is_instance_valid(a) and a.has_signal(&"busy_cancelled") and a.is_connected(&"busy_cancelled", _on_busy_cancelled):
		a.disconnect(&"busy_cancelled", _on_busy_cancelled)


func _finish(actor: Node) -> void:
	_stop_listening()
	searching_actor = null
	if not is_instance_valid(actor) or not is_instance_valid(container) or not container.is_inside_tree():
		return
	EventBus.timed_action_finished.emit(actor, SEARCH_CONTEXT, true)
	container.open(actor)


# --- Transfers ---------------------------------------------------------------

## The ItemContainer a node exposes as `inventory`, or null.
static func inventory_of(node: Node) -> ItemContainer:
	if node == null:
		return null
	var inv: Variant = node.get("inventory")
	return inv as ItemContainer if inv is ItemContainer else null


## {ok, reason} — may [actor] let go of [item]? (duck-typed
## actor.can_release_item; anything without it always may).
static func can_release(actor: Node, item: ItemInstance) -> Dictionary:
	if actor != null and actor.has_method(&"can_release_item"):
		return actor.call(&"can_release_item", item)
	return {"ok": true}


## True when [c] is one of [actor]'s own containers.
static func actor_owns(actor: Node, c: ItemContainer) -> bool:
	if actor == null or c == null:
		return false
	if actor.has_method(&"owns_container"):
		return bool(actor.call(&"owns_container", c))
	return c == inventory_of(actor)


## Container → actor ([into]: one of the actor's containers, default its
## main inventory).
func take(actor: Node, item: ItemInstance, count: int = -1, into: ItemContainer = null) -> Dictionary:
	return _move(actor, container, actor, item, count, inventory_of(container), into if into != null else inventory_of(actor))


## Actor → container, from wherever the actor keeps [item].
func put(actor: Node, item: ItemInstance, count: int = -1) -> Dictionary:
	var from := item.owner_container() if item != null else null
	if from == null or not actor_owns(actor, from):
		from = inventory_of(actor)
	return _move(actor, actor, container, item, count, from, inventory_of(container))


func take_all(actor: Node, into: ItemContainer = null) -> Dictionary:
	return _move_all(actor, container, actor, inventory_of(container), into if into != null else inventory_of(actor))


## Everything in [from] (default: the actor's main inventory) goes in.
func put_all(actor: Node, from: ItemContainer = null) -> Dictionary:
	return _move_all(actor, actor, container, from if from != null else inventory_of(actor), inventory_of(container))


func _check(actor: Node, from: ItemContainer, to: ItemContainer, actor_side: ItemContainer) -> String:
	if not container.is_open_for(actor):
		return "Not open"
	if from == null or to == null:
		return "Can't carry"
	if not actor_owns(actor, actor_side):
		return "Can't carry"
	if to.equipment_slot != &"":
		return "Use Equip"  # only Equipment fills its slots
	if bool(actor.get("is_busy")):
		return "Busy"
	return ""


func _move(actor: Node, src: Node, dst: Node, item: ItemInstance, count: int, from: ItemContainer, to: ItemContainer) -> Dictionary:
	var why := _check(actor, from, to, from if src == actor else to)
	if why != "":
		return _refused(actor, why)
	if item == null or not from.has(item):
		return _refused(actor, "Not here")
	if src == actor:
		var rel := can_release(actor, item)
		if not rel.get("ok", true):
			return _refused(actor, String(rel.get("reason", "Can't let go")))
	var info := {"id": item.id(), "name": item.display_name()}
	var r := from.transfer_to(to, item, count)
	if not r.ok:
		return _refused(actor, String(r.reason))
	info["count"] = r.moved
	EventBus.item_transferred.emit(src, dst, info)
	if r.get("partial", false):
		EventBus.interaction_refused.emit(actor, container, ItemContainer.REASON_HEAVY)
	return r


func _move_all(actor: Node, src: Node, dst: Node, from: ItemContainer, to: ItemContainer) -> Dictionary:
	var why := _check(actor, from, to, from if src == actor else to)
	if why != "":
		return _refused(actor, why)
	if from.is_empty():
		return _refused(actor, "Nothing there")
	var moved := 0
	var reason := ""
	# One transaction: one `changed` per side (UI refresh, encumbrance).
	from.begin_batch()
	to.begin_batch()
	for it in from.items.duplicate():
		if src == actor:
			var rel := can_release(actor, it)
			if not rel.get("ok", true):
				reason = String(rel.get("reason", "Can't let go"))
				continue
		var r := from.transfer_to(to, it)
		moved += int(r.get("moved", 0))
		if not r.ok or r.get("partial", false):
			reason = String(r.get("reason", ItemContainer.REASON_HEAVY)) if not r.ok else ItemContainer.REASON_HEAVY
	to.end_batch()
	from.end_batch()
	var out := {"ok": moved > 0, "moved": moved, "left": from.item_count()}
	if moved > 0:
		EventBus.item_transferred.emit(src, dst, {"id": &"", "name": "", "count": moved})
	if reason != "":
		out["reason"] = reason
		EventBus.interaction_refused.emit(actor, container, reason)
	elif moved == 0:
		out["reason"] = "Nothing there"
	return out


func _refused(actor: Node, reason: String) -> Dictionary:
	EventBus.interaction_refused.emit(actor, container, reason)
	return {"ok": false, "reason": reason, "moved": 0}
