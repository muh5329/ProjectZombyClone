extends Node
## Save / load of the whole micro-world (autoload: SaveManager, Round 10).
##
## - save_game(slot) → WorldSnapshot.capture(map) → SaveFile (JSON,
##   atomic) at <root>/<encoded slot>/world.json + meta.json. Refused for
##   an invalid slot name (""), while the player is busy (eating /
##   bandaging / sleeping: an item or a dressing would be out of its
##   container), dead, or while loading.
## - load_game(slot) (coroutine) is TWO-PHASE: phase 1 reads, migrates and
##   type-checks the whole snapshot (SaveSchema: every field, every item
##   id, profile id, map allow-list) and instances the saved map to check
##   it has a WorldConfig — any failure refuses the load and the running
##   game is not touched (HUD notice). Phase 2 swaps the maps and applies:
##   world config → static objects by id (before the navmesh bakes) →
##   [navmesh ready] → time → dropped items / corpses / zombies → player →
##   blood / camera → EventBus.game_loaded (the HUD resyncs). A "Loading…"
##   overlay covers the swap. Nothing from a save is ever load()ed.
## - F9 quick-save, F10 quick-load (slot [quick_slot]); quick-load and quit
##   to menu ask "Unsaved progress will be lost" when the last save is
##   more than UNSAVED_MINUTES game minutes old (confirm()).
## - Autosave (slot "autosave") after a RESTED wake-up and every
##   [autosave_real_minutes] of real time, never with danger around, and
##   only for the running game (the map is tree.current_scene).
## - new_game / instantiate_new_game: a fresh map with the player at its
##   PlayerStart inside House A and the starter kit (WorldConfig).
## - Saves live in user://saves; tests and tools (test runner, screenshot
##   run, perf probes) write to user://test_saves.

const QUICK_SLOT := "quick"
const AUTO_SLOT := "autosave"
const MANUAL_SLOT := "manual"
const MAIN_MENU := "res://ui/menus/main_menu.tscn"
const NEW_GAME_MAP := "res://maps/test_ground.tscn"
const AUTOSAVE_DANGER_RADIUS := 15.0
## Quick-load / quit ask for confirmation past this many unsaved minutes.
const UNSAVED_MINUTES := 2.0
## Main-loop scripts that are tests / tools (their saves go to TEST_ROOT).
const TOOL_SCRIPTS := ["tests/test_runner.gd", "tests/screenshot_run.gd", "tests/perf/"]

## Autosave every N real minutes while playing (<= 0 = off).
@export var autosave_real_minutes: float = 30.0
@export var autosave_on_wake: bool = true
## Slot of F9 / F10 (the screenshot run uses its own).
var quick_slot: String = QUICK_SLOT

var last_error: String = ""
var last_save_ms: float = 0.0
var last_load_ms: float = 0.0
## True while a load is in progress (saving / a second load are refused).
var loading: bool = false
## persist_id → node while a load applies state (cross references).
var _index: Dictionary = {}
var _autosave_accum: float = 0.0
## Overlay (loading curtain + confirmation dialog), above everything.
var overlay: CanvasLayer
var loading_panel: Control
var confirm_panel: Control
var confirm_label: Label
var _confirm_yes: Callable = Callable()
var _confirm_paused_before: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.sleep_ended.connect(_on_sleep_ended)
	for a in OS.get_cmdline_args():
		for t in TOOL_SCRIPTS:
			if String(a).contains(t):
				SaveFile.root = SaveFile.TEST_ROOT
	_build_overlay()


# --- Queries ----------------------------------------------------------------------------

## The running game's map (the node holding the WorldConfig), or null.
func current_map() -> Node:
	var cfg := WorldConfig.find(get_tree())
	return cfg.get_parent() if cfg != null else null


## A Saveable by persist_id (during a load: the index being applied).
func find_saveable(id: String) -> Node:
	if _index.has(id) and is_instance_valid(_index[id]):
		return _index[id]
	for n in Saveable.collect(get_tree()):
		if String(n.get(&"persist_id")) == id:
			return n
	return null


## "" when [map] can be saved now, else the player-facing reason.
func save_block_reason(map: Node) -> String:
	if loading:
		return "Can't save while loading"
	if map == null:
		return "Nothing to save"
	var p := WorldSnapshot.player_of(map)
	if p == null:
		return "Nothing to save"
	if p.has_method(&"is_dead") and p.call(&"is_dead"):
		return "Can't save: you are dead"
	if bool(p.get(&"is_busy")):
		return "Can't save now: busy"
	return ""


func has_slot(slot: String) -> bool:
	var p := SaveFile.world_path(slot)
	return p != "" and FileAccess.file_exists(p)


func list_slots() -> Array[Dictionary]:
	return SaveFile.list_slots()


func delete_slot(slot: String) -> bool:
	return SaveFile.delete_slot(slot)


## Read + decode + fully type-check a slot without touching the game.
func read_slot(slot: String) -> Dictionary:
	if not SaveFile.is_valid_slot(slot):
		return {"ok": false, "error": "Invalid save name"}
	var r := SaveFile.read_text(SaveFile.world_path(slot))
	if not r.ok:
		return r
	return SaveFile.decode(r.text)


## Game minutes since the running world was last saved / loaded / started.
func unsaved_minutes(map: Node = null) -> float:
	if map == null:
		map = current_map()
	var cfg := WorldConfig.find(get_tree()) if map != null else null
	return maxf(TimeManager.now() - cfg.last_saved_minute, 0.0) if cfg != null else 0.0


# --- Save --------------------------------------------------------------------------------

## Save [map] (default: the running game) into [slot]. {ok, error?, ms, path}.
func save_game(slot: String = QUICK_SLOT, map: Node = null) -> Dictionary:
	if not SaveFile.is_valid_slot(slot):
		return _fail("Invalid save name")
	if map == null:
		map = current_map()
	var why := save_block_reason(map)
	if why != "":
		return _fail(why)
	var t0 := Time.get_ticks_usec()
	var data := WorldSnapshot.capture(map)
	var text := SaveFile.to_json(data)
	var path := SaveFile.world_path(slot)
	var err := SaveFile.write_atomic(path, text)
	if err != OK:
		return _fail("Save failed (%s)" % error_string(err))
	var meta := {
		"version": SaveFile.VERSION, "slot": slot.strip_edges(),
		"timestamp": Time.get_unix_time_from_system(),
		"datetime": Time.get_datetime_string_from_system(false, true),
		"map": data.map, "game_minutes": TimeManager.now(),
		"clock": TimeManager.clock_text(), "date": TimeManager.date_text(),
		"day": TimeManager.day_index() + 1,
		"player": WorldSnapshot.summary(data),
	}
	SaveFile.write_atomic(SaveFile.meta_path(slot), JSON.stringify(meta, "  ", true))
	last_save_ms = (Time.get_ticks_usec() - t0) / 1000.0
	last_error = ""
	_autosave_accum = 0.0
	var cfg := WorldConfig.find(get_tree())
	if cfg != null and map.is_ancestor_of(cfg):
		cfg.last_saved_minute = TimeManager.now()
	EventBus.game_saved.emit(slot.strip_edges())
	EventBus.game_notice.emit("Game saved" if slot != AUTO_SLOT else "Autosaved", 2.0)
	return {"ok": true, "ms": last_save_ms, "path": path, "bytes": text.length()}


# --- Load --------------------------------------------------------------------------------

## Load [slot] replacing [map] (default: the running game's map, or the
## current scene — the main menu). Coroutine: {ok, error?, map, ms}.
## On any error the running game is left exactly as it was.
func load_game(slot: String = QUICK_SLOT, map: Node = null) -> Dictionary:
	if loading:
		return _fail("Already loading")
	var r := read_slot(slot)
	if not r.ok:
		return _fail(String(r.error))
	return await load_data(r.data, map)


## Load already-decoded [data] (see load_game). Phase 1 (checks) runs
## before anything in the running game changes.
func load_data(data: Dictionary, map: Node = null) -> Dictionary:
	if loading:
		return _fail("Already loading")
	var why := SaveFile.validate(data)
	if why != "":
		return _fail(why)
	var packed := load(String(data.map)) as PackedScene  # allow-listed res://maps scene
	if packed == null:
		return _fail("Save refers to a missing map (%s)" % data.map)
	var gen_why := check_worldgen(data)
	if gen_why != "":
		return _fail(gen_why)
	var fresh := packed.instantiate()
	if not _has_world_config(fresh):
		fresh.free()
		return _fail("Corrupt save (map: not a game map)")
	# --- Phase 2: swap and apply --------------------------------------------------------
	loading = true
	show_loading(true)
	var t0 := Time.get_ticks_usec()
	var tree := get_tree()
	if map == null:
		map = current_map()
	if map == null:
		map = tree.current_scene
	var parent: Node = map.get_parent() if map != null else tree.root
	var index := map.get_index() if map != null else -1
	var was_current := map != null and tree.current_scene == map
	_disable_spawners(fresh)
	# Round 11: seed + worldgen params before _ready (generated maps build
	# their layout from them).
	WorldSnapshot.apply_world_config(fresh, data)
	# The navmesh is baked AFTER the static objects are applied (furniture
	# moved / destroyed in the saved world bakes correctly, no re-bake).
	var nav := _nav_of(fresh)
	if nav != null:
		nav.bake_on_ready = false
	if map != null:
		parent.remove_child(map)  # _exit_tree: TimeManager reset, listeners out
		map.queue_free()
	tree.paused = false
	SoundManager.clear()
	SoundManager.prune()
	parent.add_child(fresh)
	if index >= 0:
		parent.move_child(fresh, mini(index, parent.get_child_count() - 1))
	if was_current or map == null:
		tree.current_scene = fresh
	await tree.process_frame
	WorldSnapshot.apply_static(fresh, data, _index)
	if nav != null:
		await tree.physics_frame  # freed furniture leaves the physics space
		# Chunked navigation (generated world) bakes around the saved player.
		if nav.has_method(&"focus_on") and (data.get("player", {}) as Dictionary).has("position"):
			nav.call(&"focus_on", Saveable.to_vec3(data.player.position))
		nav.bake_now()
		if not nav.baked:
			await nav.navigation_ready
	WorldSnapshot.apply_dynamic(fresh, data)
	_index.clear()
	var cfg := WorldConfig.find(tree)
	if cfg != null:
		cfg.last_saved_minute = TimeManager.now()
	loading = false
	show_loading(false)
	last_load_ms = (Time.get_ticks_usec() - t0) / 1000.0
	last_error = ""
	_autosave_accum = 0.0
	EventBus.game_loaded.emit(fresh)
	EventBus.game_notice.emit("Game loaded", 2.0)
	return {"ok": true, "map": fresh, "ms": last_load_ms}


## Round 11: a save of a generated world stores the generator version and
## the layout hash. The layout is regenerated from (seed, params) — cached,
## the map build reuses it — and must hash the same; a different version
## with the same hash is accepted (nothing to migrate). "" = fine.
static func check_worldgen(data: Dictionary) -> String:
	var w: Dictionary = data.get("world", {})
	if not w.has("worldgen"):
		return ""
	var wg: Dictionary = w.worldgen
	var prm: WorldGenParams = null
	var gp := String(w.get("worldgen_params", ""))
	if gp != "" and gp.begins_with("res://data/worldgen/"):
		prm = load(gp) as WorldGenParams
	if prm == null:
		prm = WorldGenerator.default_params()
	var seed := int(w.get("seed", 0))
	var layout := WorldGenerator.generate(seed, prm)
	var saved_v := int(wg.get("version", 0))
	if layout.layout_hash() == String(wg.get("layout_hash", "")):
		if saved_v != WorldGenerator.VERSION:
			print("SaveManager: save from world generator v%d loads unchanged in v%d" % [saved_v, WorldGenerator.VERSION])
		return ""
	if saved_v != WorldGenerator.VERSION:
		return "This save was made with world generator v%d; this build (v%d) generates a different world for seed %d, so it can't be loaded" % [
			saved_v, WorldGenerator.VERSION, seed]
	return "This save's world doesn't match its seed %d (layout hash mismatch): can't load" % seed


static func _has_world_config(n: Node) -> bool:
	for c in n.get_children():
		if c is WorldConfig:
			return true
	return false


# --- New game / menu ------------------------------------------------------------------

## A fresh, NOT yet added map for a new game: the player at the map's
## PlayerStart (inside House A) with the starter kit; [world_seed] >= 0
## reseeds the world (loot) and the zombie spawner. Tests add it
## themselves; new_game() makes it the current scene.
func instantiate_new_game(scene_path: String = NEW_GAME_MAP, world_seed: int = -1) -> Node:
	if not SaveFile.allowed_map(scene_path):
		return null
	var packed := load(scene_path) as PackedScene
	var map := packed.instantiate() if packed != null else null
	if map != null:
		WorldConfig.prepare_new_game(map, world_seed)
	return map


## Start a brand-new game (main menu "New game").
func new_game(scene_path: String = NEW_GAME_MAP, world_seed: int = -1) -> void:
	var map := instantiate_new_game(scene_path, world_seed)
	if map == null:
		_fail("Can't start a new game")
		return
	var tree := get_tree()
	tree.paused = false
	var old := tree.current_scene
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()
	tree.root.add_child(map)
	tree.current_scene = map


func quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)


## Quit to the title screen, asking first when progress would be lost.
func request_quit_to_menu() -> void:
	if current_map() != null and unsaved_minutes() > UNSAVED_MINUTES:
		confirm("Unsaved progress will be lost. Quit to the menu?", quit_to_menu)
	else:
		quit_to_menu()


## Load [slot] into the running game, asking first when progress would be
## lost. The load runs here (callers may be replaced by it).
func request_load(slot: String) -> void:
	var r := read_slot(slot)
	if not r.ok:
		_fail(String(r.error))
		return
	if current_map() != null and unsaved_minutes() > UNSAVED_MINUTES:
		confirm("Unsaved progress will be lost. Load '%s'?" % slot, func(): load_data(r.data))
	else:
		load_data(r.data)


static func _disable_spawners(n: Node) -> void:
	if n is ZombieSpawner:
		(n as ZombieSpawner).auto_spawn = false
	for c in n.get_children():
		_disable_spawners(c)


static func _nav_of(map: Node) -> NavBaker:
	for c in map.get_children():
		if c is NavBaker:
			return c
	return null


func _fail(reason: String) -> Dictionary:
	last_error = reason
	EventBus.game_notice.emit(reason, 3.0)
	return {"ok": false, "error": reason}


# --- Overlay: loading curtain + confirmation --------------------------------------------

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "SaveOverlay"
	overlay.layer = 50
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	var lp := ColorRect.new()
	lp.name = "Loading"
	lp.color = Color(0.03, 0.035, 0.04, 0.94)
	lp.set_anchors_preset(Control.PRESET_FULL_RECT)
	lp.mouse_filter = Control.MOUSE_FILTER_STOP
	var ll := MenuStyle.title("Loading…", 34)
	ll.set_anchors_preset(Control.PRESET_CENTER)
	ll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ll.grow_vertical = Control.GROW_DIRECTION_BOTH
	lp.add_child(ll)
	lp.visible = false
	overlay.add_child(lp)
	loading_panel = lp
	var cp := Control.new()
	cp.name = "Confirm"
	cp.set_anchors_preset(Control.PRESET_FULL_RECT)
	cp.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	cp.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	cp.add_child(center)
	var panel := MenuStyle.panel(Vector2(420, 0))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	panel.add_child(col)
	confirm_label = MenuStyle.label("", 18, MenuStyle.TITLE)
	col.add_child(confirm_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 12)
	col.add_child(row)
	var yes := MenuStyle.button("Yes", answer.bind(true))
	yes.custom_minimum_size = Vector2(140, 36)
	row.add_child(yes)
	var no := MenuStyle.button("No", answer.bind(false))
	no.custom_minimum_size = Vector2(140, 36)
	row.add_child(no)
	cp.visible = false
	overlay.add_child(cp)
	confirm_panel = cp


func show_loading(on: bool) -> void:
	if loading_panel:
		loading_panel.visible = on


func is_loading_shown() -> bool:
	return loading_panel != null and loading_panel.visible


## Ask [text]; [on_yes] runs on "Yes". The game is paused meanwhile.
func confirm(text: String, on_yes: Callable) -> void:
	_confirm_yes = on_yes
	confirm_label.text = text
	if not confirm_panel.visible:
		_confirm_paused_before = get_tree().paused
	get_tree().paused = true
	confirm_panel.visible = true


func is_confirming() -> bool:
	return confirm_panel != null and confirm_panel.visible


func confirm_text() -> String:
	return confirm_label.text if is_confirming() else ""


func answer(yes: bool) -> void:
	if not is_confirming():
		return
	confirm_panel.visible = false
	get_tree().paused = _confirm_paused_before
	var cb := _confirm_yes
	_confirm_yes = Callable()
	if yes and cb.is_valid():
		cb.call()


# --- Input / autosave ------------------------------------------------------------------

## The running game (not tests / tools, which never make the map current).
func _playing() -> bool:
	var map := current_map()
	return map != null and map == get_tree().current_scene and not loading


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if is_confirming():
		if event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			answer(false)
		return
	if InputMap.has_action(&"quick_save") and event.is_action_pressed(&"quick_save"):
		get_viewport().set_input_as_handled()
		if current_map() != null:
			save_game(quick_slot)
	elif InputMap.has_action(&"quick_load") and event.is_action_pressed(&"quick_load"):
		get_viewport().set_input_as_handled()
		if has_slot(quick_slot):
			request_load(quick_slot)
		else:
			_fail("No quick save yet")


func _process(delta: float) -> void:
	if autosave_real_minutes <= 0.0 or get_tree().paused or not _playing():
		return
	_autosave_accum += delta / maxf(Engine.time_scale, 0.001)  # real seconds
	if _autosave_accum >= autosave_real_minutes * 60.0:
		_autosave_accum = 0.0
		autosave()


## Autosave now if the game can be saved (silently skipped otherwise).
func autosave() -> bool:
	var map := current_map()
	if autosave_block_reason(map) != "":
		return false
	return bool(save_game(AUTO_SLOT, map).ok)


## Autosaves also skip any danger (a zombie chasing, one within
## AUTOSAVE_DANGER_RADIUS m): an autosave must never lock in a death trap.
func autosave_block_reason(map: Node) -> String:
	var why := save_block_reason(map)
	if why != "":
		return why
	var p := WorldSnapshot.player_of(map) as Node3D
	var threat := Danger.threat_reason(get_tree(), p, AUTOSAVE_DANGER_RADIUS)
	return "Autosave skipped: %s" % threat if threat != "" else ""


func _on_sleep_ended(c: Node, reason: String) -> void:
	# Only a rested wake-up autosaves: woken by noise / an attack / thirst
	# (a non-empty reason) means trouble.
	if not autosave_on_wake or c != GameManager.player or not _playing() or reason != "":
		return
	# The sleeper is released from the bed a moment later.
	_autosave_after_wake.call_deferred()


func _autosave_after_wake() -> void:
	for i in 30:
		if not _playing():
			return
		var why := autosave_block_reason(current_map())
		if why == "":
			autosave()
			return
		if why.begins_with("Autosave skipped"):
			return
		await get_tree().physics_frame
