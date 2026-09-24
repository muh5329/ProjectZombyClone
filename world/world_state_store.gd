class_name WorldStateStore
extends RefCounted
## Persistent state of streamed chunks (Round 12). The generated world is
## deterministic, so a chunk rebuilt from its recipe is exactly its
## "generated default"; the store keeps only what differs from that:
##
## - [statics] {persist_id: save_state()} of every Saveable (container,
##   door, window, furniture, vehicle trunk…) whose state at unload time
##   differs from the state it had right after it was built. An
##   unsearched container equals its default (loot is rolled lazily from
##   the seed) and is never stored; a door that was opened and closed
##   again is dropped from the store. Containers carry "_t" (the game
##   minute of the capture) so food keeps spoiling while the chunk is
##   unloaded (reapply ages it by the elapsed minutes × the container's
##   spoil rate). Destroyed statics stay in WorldConfig.destroyed_ids.
## - [dynamic] {"x,z": {items, corpses, blood, t}}: dropped WorldItems,
##   corpses and blood splats that lay in that chunk when it unloaded
##   (ownership is by position at unload time, so an item carried or a
##   corpse dragged elsewhere belongs to the chunk it is in then).
##
## [defaults] (runtime only) holds the build-time state of the saveables
## of LOADED chunks; capture compares against it. Pure data: the
## ChunkStreamer walks the nodes and calls record_defaults / apply_static
## / capture_static; tests drive it with plain dictionaries too.

## persist_id → state that differs from the generated default.
var statics: Dictionary = {}
## chunk key "x,z" → {items: [], corpses: [], blood: [], t: minute}.
var dynamic: Dictionary = {}
## persist_id → build-time state (loaded chunks only; not saved).
var defaults: Dictionary = {}
## Counters (tests / debug).
var applied: int = 0
var captured: int = 0


static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func key_to_chunk(k: String) -> Vector2i:
	var p := k.split(",")
	if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(p[0].to_int(), p[1].to_int())


# --- Statics --------------------------------------------------------------------------

## Remember the generated default of [id] (right after it was built).
func record_default(id: String, state: Dictionary) -> void:
	defaults[id] = state


## The stored delta of [id] (without bookkeeping keys), or {} when the
## object is at its default.
func delta_for(id: String) -> Dictionary:
	var d: Variant = statics.get(id)
	if not d is Dictionary:
		return {}
	var out: Dictionary = (d as Dictionary).duplicate(true)
	out.erase("_t")
	return out


## Minutes since [id]'s state was captured at [now] (0 when unknown).
func elapsed_for(id: String, now: float) -> float:
	var d: Variant = statics.get(id)
	if not d is Dictionary or not (d as Dictionary).has("_t"):
		return 0.0
	return maxf(now - float(d._t), 0.0)


## Capture [id] with its current [state] at game minute [now]: stored
## when it differs from the recorded default, dropped from the store when
## it is back at the default. Returns true when a delta is stored.
func capture(id: String, state: Dictionary, now: float) -> bool:
	captured += 1
	var def: Variant = defaults.get(id)
	if def is Dictionary and states_equal(def, state):
		statics.erase(id)
		return false
	var s := state.duplicate(true)
	if String(s.get("kind", "")) == "container":
		s["_t"] = now
	statics[id] = s
	return true


## Deep equality of two JSON-like states (Dictionary == compares by value).
static func states_equal(a: Dictionary, b: Dictionary) -> bool:
	return a == b


## Forget [id]'s default (its chunk unloaded).
func forget_default(id: String) -> void:
	defaults.erase(id)


# --- Dynamic (items, corpses, blood) -----------------------------------------------------

## Store what lay in chunk [c] when it unloaded (replaces the old record;
## an empty chunk has no entry).
func put_dynamic(c: Vector2i, items: Array, corpses: Array, blood: Array, now: float) -> void:
	var k := key(c)
	if items.is_empty() and corpses.is_empty() and blood.is_empty():
		dynamic.erase(k)
		return
	dynamic[k] = {"items": items, "corpses": corpses, "blood": blood, "t": now}


## Take chunk [c]'s dynamic record out of the store ({} when none).
func take_dynamic(c: Vector2i) -> Dictionary:
	var k := key(c)
	var d: Dictionary = dynamic.get(k, {})
	dynamic.erase(k)
	return d


func has_dynamic(c: Vector2i) -> bool:
	return dynamic.has(key(c))


## Items + corpses + blood splats held for unloaded chunks (tests).
func dynamic_count() -> int:
	var n := 0
	for k in dynamic:
		var d: Dictionary = dynamic[k]
		n += (d.get("items", []) as Array).size() + (d.get("corpses", []) as Array).size() + (d.get("blood", []) as Array).size()
	return n


# --- Spoilage while unloaded ----------------------------------------------------------------

## Age the perishables in [inv] (and bags inside) by [minutes] of game time
## at the container's spoil rate (the chunk was unloaded meanwhile).
static func age_inventory(inv: ItemContainer, minutes: float) -> void:
	if inv == null or minutes <= 0.0:
		return
	for it in inv.items:
		if it.perishable():
			it.sync_age()
			it.age_minutes += minutes * inv.spoil_multiplier
		if it.contents != null:
			age_inventory(it.contents, minutes)


## Age one loose item (on the ground: rate 1).
static func age_item(it: ItemInstance, minutes: float) -> void:
	if it == null or minutes <= 0.0:
		return
	if it.perishable():
		it.sync_age()
		it.age_minutes += minutes
	if it.contents != null:
		age_inventory(it.contents, minutes)


# --- Save ----------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"statics": statics.duplicate(true), "chunks": dynamic.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	statics = (d.get("statics", {}) as Dictionary).duplicate(true)
	dynamic = (d.get("chunks", {}) as Dictionary).duplicate(true)
	defaults.clear()


func clear() -> void:
	statics.clear()
	dynamic.clear()
	defaults.clear()
