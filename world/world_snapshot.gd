class_name WorldSnapshot
extends RefCounted
## The micro-world as data (Round 10). capture(map) builds a JSON-safe
## Dictionary; apply_static / apply_dynamic put it back onto a FRESHLY
## loaded map (SaveManager reloads the map scene first — nothing is
## patched onto a running world). Never serializes nodes blindly:
##
## - world: seed, age (loot), water shut-off day. time: game minutes (the
##   speed is not saved: a loaded game runs at 1×).
## - statics {persist_id: save_state()}: every Saveable (containers incl.
##   vehicle trunks / gloveboxes, doors, windows with their barricades,
##   furniture moved in front of doors). destroyed: ids of statics that
##   were smashed / taken apart → remove_for_load() on load; a live static
##   merely missing from the save keeps its default; an unknown saved id
##   → warning, skipped.
## - spawners {stable id: bookkeeping}, zombies [living, spawn records],
##   corpses [spawn records + container], items [dropped WorldItems],
##   player, blood (newest splats), camera (heading + zoom).
## Records are sorted by id so the same world always gives the same text.

## Keys of the dynamic part (validated as arrays by SaveFile).
const KEY_ZOMBIES := "zombies"
const KEY_CORPSES := "corpses"
const KEY_ITEMS := "items"

## uid → ItemInstance of every item lying in the map, filled while a load
## applies (Equipment resolves hotbar slots pointing at uncarried items).
static var _items_by_uid: Dictionary = {}


static func find_item(uid: int) -> ItemInstance:
	return _items_by_uid.get(uid) as ItemInstance


static func _index_container(c: ItemContainer) -> void:
	if c == null:
		return
	for it in c.items:
		_items_by_uid[it.uid] = it
		if it.contents != null:
			_index_container(it.contents)


## Every item in the map's containers, corpses and on the floor.
static func index_items(map: Node) -> void:
	_items_by_uid.clear()
	for c in _in_map(map, LootContainer.GROUP):
		_index_container((c as LootContainer).inventory if c is LootContainer else null)
	for w in _in_map(map, WorldItem.GROUP):
		var wi := w as WorldItem
		if wi != null and wi.item != null:
			_items_by_uid[wi.item.uid] = wi.item
			if wi.item.contents != null:
				_index_container(wi.item.contents)


static func player_of(map: Node) -> Node:
	for p in map.get_tree().get_nodes_in_group(&"player"):
		if map.is_ancestor_of(p):
			return p
	return null


static func spawners_of(map: Node) -> Array[ZombieSpawner]:
	var out: Array[ZombieSpawner] = []
	_find_spawners(map, out)
	return out


static func _find_spawners(n: Node, out: Array[ZombieSpawner]) -> void:
	for c in n.get_children():
		if c is ZombieSpawner:
			out.append(c)
		elif c.get_child_count() > 0 and not c is Zombie and not c is HouseBlockout:
			_find_spawners(c, out)


static func _in_map(map: Node, group: StringName) -> Array[Node]:
	var out: Array[Node] = []
	for n in map.get_tree().get_nodes_in_group(group):
		if map.is_ancestor_of(n) and not n.is_queued_for_deletion():
			out.append(n)
	return out


# --- Capture ---------------------------------------------------------------------------

static func capture(map: Node) -> Dictionary:
	var tree := map.get_tree()
	var cfg := WorldConfig.find(tree)
	var data := {
		"version": SaveFile.VERSION,
		"map": map.scene_file_path,
		"world": {
			"seed": cfg.world_seed if cfg else 0,
			"age_days": cfg.world_age_days if cfg else 0.0,
			"water_shutoff_day": cfg.water_shutoff_day if cfg else -1,
		},
		"time": {"minutes": TimeManager.now()},
	}
	if cfg != null and cfg.worldgen_params != "":
		data.world["worldgen_params"] = cfg.worldgen_params
	# Round 11: generated maps record the generator version and the layout
	# hash; a load regenerates the layout and refuses a mismatch.
	var wb := WorldBuilder.of(tree)
	if wb != null and wb.layout != null and map.is_ancestor_of(wb):
		data.world["worldgen"] = {"version": wb.layout.version, "layout_hash": wb.layout_hash()}
	var statics := {}
	for n in Saveable.collect(tree, map):
		var id := String(n.get(&"persist_id"))
		if statics.has(id):
			push_warning("WorldSnapshot: duplicate persist_id '%s' (second one not saved)" % id)
			continue
		statics[id] = n.call(&"save_state")
	data["statics"] = statics
	var destroyed: Array = cfg.destroyed_ids.keys() if cfg else []
	destroyed.sort()
	data["destroyed"] = destroyed
	var sp := {}
	for s in spawners_of(map):
		sp[s.stable_id()] = s.save_state()
	data["spawners"] = sp
	var zs: Array = []
	for z in _in_map(map, &"zombie"):
		if z is Zombie and not (z as Zombie).dead:
			zs.append((z as Zombie).save_record())
	zs.sort_custom(func(a, b): return String(a.spawn_id) < String(b.spawn_id))
	data[KEY_ZOMBIES] = zs
	var cs: Array = []
	for c in _in_map(map, &"corpse"):
		if c is ZombieCorpse:
			cs.append((c as ZombieCorpse).save_record())
	cs.sort_custom(func(a, b): return String(a.persist_id) < String(b.persist_id))
	data[KEY_CORPSES] = cs
	var items: Array = []
	var keyed: Array = []
	for w in _in_map(map, WorldItem.GROUP):
		var wi := w as WorldItem
		if wi == null or wi.item == null or wi.item.data == null or wi.item.stack <= 0:
			continue
		# Sort key computed once (uids are unique and survive a load).
		keyed.append([wi.item.uid, {"item": wi.item.to_dict(), "position": Saveable.vec3(wi.global_position),
			"yaw": wi.rotation.y}])
	keyed.sort_custom(func(a, b): return a[0] < b[0])
	for k in keyed:
		items.append(k[1])
	data[KEY_ITEMS] = items
	var player := player_of(map)
	data["player"] = player.call(&"save_state") if player != null and player.has_method(&"save_state") else {}
	var blood := tree.get_first_node_in_group(&"blood_decals")
	if blood != null and map.is_ancestor_of(blood):
		data["blood"] = blood.call(&"to_dict")
	var cam := tree.get_first_node_in_group(&"isometric_camera")
	if cam != null and map.is_ancestor_of(cam) and cam.has_method(&"view_state"):
		data["camera"] = cam.call(&"view_state")
	return data


## Counts for meta.json / the slot list.
static func summary(data: Dictionary) -> Dictionary:
	var p: Dictionary = data.get("player", {})
	var h: Dictionary = p.get("health", {})
	var st: Dictionary = p.get("stats", {})
	var inj: Dictionary = p.get("injuries", {})
	return {
		"health": float(h.get("health", 0.0)), "health_max": float(h.get("max", 100.0)),
		"hunger": float(st.get("hunger", 0.0)), "thirst": float(st.get("thirst", 0.0)),
		"fatigue": float(st.get("fatigue", 0.0)),
		"injuries": (inj.get("injuries", []) as Array).size(),
		"zombies_alive": (data.get(KEY_ZOMBIES, []) as Array).size(),
		"corpses": (data.get(KEY_CORPSES, []) as Array).size(),
	}


# --- Apply ---------------------------------------------------------------------------------

## Phase 0 (Round 11), on the fresh map BEFORE it enters the tree: the
## world config a generated map needs at _ready (seed + worldgen params:
## WorldBuilder regenerates the identical layout, so every saved static id
## exists again).
static func apply_world_config(map: Node, data: Dictionary) -> void:
	var w: Dictionary = data.get("world", {})
	for c in map.get_children():
		if c is WorldConfig:
			var cfg := c as WorldConfig
			cfg.world_seed = int(w.get("seed", cfg.world_seed))
			cfg.world_age_days = float(w.get("age_days", cfg.world_age_days))
			cfg.water_shutoff_day = int(w.get("water_shutoff_day", cfg.water_shutoff_day))
			var gp := String(w.get("worldgen_params", ""))
			if gp != "":
				cfg.worldgen_params = gp

## Phase 1, right after the fresh map is ready and BEFORE the navmesh is
## baked (so moved / destroyed furniture bakes correctly): world config,
## every static object, spawners; the map's own world items / zombies /
## corpses are cleared (they come back from the save's records).
## [index] (id → node) is filled for cross references (furniture → door).
## Returns {applied, unknown, removed}.
static func apply_static(map: Node, data: Dictionary, index: Dictionary) -> Dictionary:
	var tree := map.get_tree()
	var cfg := WorldConfig.find(tree)
	var w: Dictionary = data.get("world", {})
	if cfg:
		cfg.world_seed = int(w.get("seed", cfg.world_seed))
		cfg.world_age_days = float(w.get("age_days", cfg.world_age_days))
		cfg.water_shutoff_day = int(w.get("water_shutoff_day", cfg.water_shutoff_day))
	index.clear()
	for n in Saveable.collect(tree, map):
		index[String(n.get(&"persist_id"))] = n
	var statics: Dictionary = data.get("statics", {})
	var out := {"applied": 0, "unknown": 0, "removed": 0}
	for id: String in statics:
		var node: Node = index.get(id)
		if node == null:
			push_warning("WorldSnapshot: saved object '%s' is not in the map (skipped)" % id)
			out.unknown += 1
			continue
		var d: Variant = statics[id]
		if d is Dictionary:
			node.call(&"load_state", d)
			out.applied += 1
	# Destroyed in the saved world (explicit list): gone again. An object
	# that is merely missing from the save (added to the map later, or an
	# id the save never had) keeps its default state.
	for id in data.get("destroyed", []):
		var node: Node = index.get(String(id))
		if cfg:
			cfg.mark_destroyed(String(id))
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.has_method(&"remove_for_load"):
			node.call(&"remove_for_load")
			out.removed += 1
	var sp: Dictionary = data.get("spawners", {})
	for s in spawners_of(map):
		s.auto_spawn = false
		if sp.has(s.stable_id()):
			s.load_state(sp[s.stable_id()])
	# Dynamic objects placed by the map itself (the starting bat / knife /
	# backpack, hand-placed zombies) are replaced by the save's records.
	for n in _in_map(map, WorldItem.GROUP):
		n.remove_from_group(WorldItem.GROUP)
		n.queue_free()
	for n in _in_map(map, &"zombie"):
		n.remove_from_group(&"zombie")
		n.queue_free()
	for n in _in_map(map, &"corpse"):
		n.remove_from_group(&"corpse")
		n.queue_free()
	return out


## Phase 2, once the navmesh is live: time, dropped items, corpses,
## zombies, the player, blood, camera. Synchronous: capture() right after
## gives back the same data.
static func apply_dynamic(map: Node, data: Dictionary) -> void:
	var tree := map.get_tree()
	TimeManager.from_dict({"minutes": float((data.get("time", {}) as Dictionary).get("minutes", 0.0))})
	for rec in data.get(KEY_ITEMS, []):
		if not rec is Dictionary:
			continue
		var inst := ItemInstance.from_dict(rec.get("item", {}))
		if inst == null:
			push_warning("WorldSnapshot: unknown dropped item %s (skipped)" % str(rec.get("item")))
			continue
		var wi := WorldItem.for_instance(inst)
		map.add_child(wi)
		wi.global_position = Saveable.to_vec3(rec.get("position"))
		wi.rotation.y = float(rec.get("yaw", 0.0))
	var spawners := spawners_of(map)
	var spawner: ZombieSpawner = spawners[0] if not spawners.is_empty() else null
	for rec in data.get(KEY_CORPSES, []):
		if rec is Dictionary:
			ZombieCorpse.restore(spawner if spawner != null else map, rec)
	for rec in data.get(KEY_ZOMBIES, []):
		if not rec is Dictionary:
			continue
		var sid := String(rec.get("spawn_id", ""))
		var s := _spawner_for(sid, spawners, spawner)
		if s == null:
			push_warning("WorldSnapshot: no spawner for zombie '%s' (skipped)" % sid)
			continue
		s.restore_zombie(rec)
	var player := player_of(map)
	index_items(map)
	if player != null and player.has_method(&"load_state"):
		player.call(&"load_state", data.get("player", {}))
	_items_by_uid.clear()
	var blood := tree.get_first_node_in_group(&"blood_decals")
	if blood != null and map.is_ancestor_of(blood) and data.has("blood"):
		blood.call(&"from_dict", data.blood)
	var cam := tree.get_first_node_in_group(&"isometric_camera")
	if cam != null and map.is_ancestor_of(cam) and data.has("camera") and cam.has_method(&"restore_view"):
		cam.call(&"restore_view", data.camera)


## The spawner whose stable id prefixes [spawn_id] ("Zombies/7"), else [fallback].
static func _spawner_for(spawn_id: String, spawners: Array[ZombieSpawner], fallback: ZombieSpawner) -> ZombieSpawner:
	for s in spawners:
		if spawn_id.begins_with(s.stable_id() + "/"):
			return s
	return fallback
