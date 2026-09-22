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

const SEARCH_CONTEXT := &"search"

var container: LootContainer
var searching_actor: Node = null


func _init(c: LootContainer) -> void:
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
	var tw: Tween = actor.call(&"begin_busy", SEARCH_CONTEXT)
	tw.tween_interval(seconds)
	tw.tween_callback(_finish.bind(actor))
	EventBus.timed_action_started.emit(actor, SEARCH_CONTEXT, "Rummaging in %s…" % container.display_name.to_lower(), seconds)
	if container.search_noise_radius > 0.0:
		var at: Vector3 = (actor as Node3D).global_position if actor is Node3D else container.global_position
		EventBus.sound_emitted.emit(at, container.search_noise_radius, 0.3, &"search", actor)
	return {"ok": true, "searching": true, "seconds": seconds}


## Abort a running rummage: the actor's busy tween is killed, nothing opens.
func cancel_search() -> void:
	var actor := searching_actor
	_stop_listening()
	searching_actor = null
	if actor == null or not is_instance_valid(actor):
		return
	if bool(actor.get("is_busy")) and actor.get("busy_context") == SEARCH_CONTEXT:
		var tw: Variant = actor.get("busy_tween")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		if actor.has_method(&"end_busy"):
			actor.call(&"end_busy")
	EventBus.timed_action_finished.emit(actor, SEARCH_CONTEXT, false)
	EventBus.interaction_refused.emit(actor, container, "Interrupted")


func _on_character_damaged(character: Node, _amount: float, _source: Node, _info: Dictionary) -> void:
	if character != null and character == searching_actor:
		cancel_search()


func _stop_listening() -> void:
	if EventBus.character_damaged.is_connected(_on_character_damaged):
		EventBus.character_damaged.disconnect(_on_character_damaged)


func _finish(actor: Node) -> void:
	searching_actor = null
	_stop_listening()
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


func take(actor: Node, item: ItemInstance, count: int = -1) -> Dictionary:
	return _move(actor, container, actor, item, count)


func put(actor: Node, item: ItemInstance, count: int = -1) -> Dictionary:
	return _move(actor, actor, container, item, count)


func take_all(actor: Node) -> Dictionary:
	return _move_all(actor, container, actor)


func put_all(actor: Node) -> Dictionary:
	return _move_all(actor, actor, container)


func _check(actor: Node, from: ItemContainer, to: ItemContainer) -> String:
	if not container.is_open_for(actor):
		return "Not open"
	if from == null or to == null:
		return "Can't carry"
	if bool(actor.get("is_busy")):
		return "Busy"
	return ""


func _move(actor: Node, src: Node, dst: Node, item: ItemInstance, count: int) -> Dictionary:
	var from := inventory_of(src)
	var to := inventory_of(dst)
	var why := _check(actor, from, to)
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


func _move_all(actor: Node, src: Node, dst: Node) -> Dictionary:
	var from := inventory_of(src)
	var to := inventory_of(dst)
	var why := _check(actor, from, to)
	if why != "":
		return _refused(actor, why)
	if from.is_empty():
		return _refused(actor, "Nothing there")
	var moved := 0
	var reason := ""
	for it in from.items.duplicate():
		if src == actor:
			var rel := can_release(actor, it)
			if not rel.get("ok", true):
				reason = String(rel.get("reason", "Can't let go"))
				continue
		var r := from.transfer_to(to, it)
		moved += int(r.get("moved", 0))
		if not r.ok or r.get("partial", false):
			reason = ItemContainer.REASON_HEAVY
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
