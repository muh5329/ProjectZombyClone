class_name WorldState
extends RefCounted
## Registry of everything that persists (Round 10 serializes it).
##
## Persistables are nodes in group "persistent" with a stable string
## `persist_id` and to_dict() / from_dict(d). The map's WorldConfig owns
## one WorldState; nothing here is an autoload.
##
## - snapshot(tree) -> {persist_id: node.to_dict()} for every persistable.
## - apply(tree, snap): from_dict() on every live node with a matching id;
##   ids with no live node stay [pending] and are applied when a node with
##   that id registers later (corpses, streamed chunks).

const GROUP := &"persistent"

## persist_id -> dict waiting for its node.
var pending: Dictionary = {}


static func collect(tree: SceneTree) -> Array[Node]:
	var out: Array[Node] = []
	for n in tree.get_nodes_in_group(GROUP):
		if n.has_method(&"to_dict") and String(n.get("persist_id")) != "":
			out.append(n)
	return out


## persist_ids used by more than one live node (should be empty).
static func duplicate_ids(tree: SceneTree) -> PackedStringArray:
	var seen := {}
	var dups := PackedStringArray()
	for n in collect(tree):
		var id := String(n.get("persist_id"))
		if seen.has(id) and not dups.has(id):
			dups.append(id)
		seen[id] = true
	return dups


func snapshot(tree: SceneTree) -> Dictionary:
	var out := {}
	for n in collect(tree):
		out[String(n.get("persist_id"))] = n.call(&"to_dict")
	# Entries not yet claimed by a node survive a save round trip.
	for id in pending:
		if not out.has(id):
			out[id] = pending[id]
	return out


## Apply [snap]; returns how many live nodes were restored.
func apply(tree: SceneTree, snap: Dictionary) -> int:
	pending = snap.duplicate(true)
	var n := 0
	for node in collect(tree):
		var id := String(node.get("persist_id"))
		if pending.has(id):
			node.call(&"from_dict", pending[id])
			pending.erase(id)
			n += 1
	return n


## Called by a persistable when it enters the world: restores pending state.
func register(node: Node) -> void:
	var id := String(node.get("persist_id"))
	if id != "" and pending.has(id):
		node.call(&"from_dict", pending[id])
		pending.erase(id)
