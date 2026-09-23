class_name HouseWindow
extends WallFixture
## Window set into a wall opening. Occupies the FULL wall segment (sill,
## sash, header) so the wall generator leaves the opening empty.
##
## Collision: the sill and the header are wall (layer 1, always): you
## cannot walk through a window, open or not — you climb (ACTION_CLIMB).
## The glass is a separate child body ("Pane") on layer 8 ("window_panes")
## while closed and on no layer once open or smashed, so vision and
## interaction rays (masks 1+7+8) see through open / smashed windows only.
## The climb tween is owned by the ACTOR (Character.begin_busy), so the
## actor's busy lock always clears even if this window is freed mid-climb.
##
## States: closed / open / smashed. Smashing leaves GlassShards on the
## floor on both sides (a foot-scratch hazard) and shards in the frame:
## climbing is hazardous (laceration roll) until "Remove broken glass"
## (3 s busy, 3 m glass_clear noise) clears both. Sounds go through SoundManager: window_open /
## window_close (5 m), window_smash (20 m — the loudest thing a survivor
## can do so far). A closed pane muffles sound ×0.7; open / smashed lets
## it out (sound_passes()).

const STATE_CLOSED := &"closed"
const STATE_OPEN := &"open"
const STATE_SMASHED := &"smashed"
const ACTION_OPEN := &"open"
const ACTION_CLOSE := &"close"
const ACTION_SMASH := &"smash"
const ACTION_CLIMB := &"climb"
const ACTION_CLEAR_GLASS := &"clear_glass"
const CLIMB_CONTEXT := &"climb"
const CLEAR_GLASS_CONTEXT := &"clear_glass"
## Navigation layer of the window links (bit 2); zombie agents use 1 + 2.
const WINDOW_NAV_LAYER := 1 << 1
## Physics layer index (0-based) of "window_panes".
const PANE_LAYER_BIT := 7
## SoundManager categories (radii in data/audio/sound_categories.tres).
const SOUND_OPEN := &"window_open"
const SOUND_CLOSE := &"window_close"
const SOUND_SMASH := &"window_smash"

@export var width: float = 1.2
@export var wall_thickness: float = 0.2
@export var sill_height: float = 0.9
@export var top_height: float = 2.1
@export var wall_color: Color = Color(0.62, 0.58, 0.5)
@export var frame_color: Color = Color(0.92, 0.92, 0.9)
@export var glass_color: Color = Color(0.55, 0.75, 0.9, 0.45)
@export var climb_seconds: float = 0.8
## How far past the wall centre the climber lands.
@export var climb_clearance: float = 0.9
## Seconds of "Remove broken glass".
@export var clear_glass_seconds: float = 3.0
## Round 9: hit points of the closed pane against zombies (breakable
## contract): two bangs smash it.
@export var pane_health: float = 16.0
## Navigation link cost: EntryPlanner.window_link_cost (open 1 m,
## closed 10 m, + BarricadeData.nav_cost_per_plank per plank).
## Distance of the link ends from the wall centre (m).
@export var nav_link_offset: float = 0.75

var state: StringName = STATE_CLOSED
## Set by the last climb: true when the climber went through broken glass.
var last_climb_hazard: bool = false
var _pane: MeshInstance3D
var _shards: MeshInstance3D
var _pane_body: StaticBody3D
## Floor hazard left by a smash (null when none / cleared).
var glass: GlassShards = null
var _clearing_actor: Node = null
var _pane_hp: float = 16.0
## Zombie entry (Round 9): a NavigationLink3D through exterior windows so
## zombies path through them (cost by state and planks); null inside.
var nav_link: NavigationLink3D = null


## True while the pane glows (night).
var night_glow: bool = false


func _init() -> void:
	fixture_group = &"window"


func _ready() -> void:
	super._ready()
	_pane_hp = pane_health
	add_to_group(&"breakable")
	if outward.length_squared() > 0.5:
		nav_link = NavigationLink3D.new()
		nav_link.name = "NavLink"
		nav_link.bidirectional = true
		# Round 10: window links are for climbers (zombies: layers 1 + 2);
		# a path query on layer 1 only (survivors, bots) never routes
		# through a window.
		nav_link.navigation_layers = WINDOW_NAV_LAYER
		nav_link.start_position = Vector3(0, 0, nav_link_offset)
		nav_link.end_position = Vector3(0, 0, -nav_link_offset)
		add_child(nav_link)
		_update_nav_cost()


func _build_visual() -> void:
	var t := wall_thickness
	# Sill (wall below the glass) and header (wall above).
	_box(visual, Vector3(width, sill_height, t), Vector3(0, sill_height * 0.5, 0), wall_color)
	var header_h := wall_height - top_height
	_box(visual, Vector3(width, header_h, t), Vector3(0, top_height + header_h * 0.5, 0), wall_color)
	# Frame posts and rails.
	var fw := 0.08
	var open_h := top_height - sill_height
	_box(visual, Vector3(fw, open_h, t + 0.02), Vector3(-width * 0.5 + fw * 0.5, sill_height + open_h * 0.5, 0), frame_color)
	_box(visual, Vector3(fw, open_h, t + 0.02), Vector3(width * 0.5 - fw * 0.5, sill_height + open_h * 0.5, 0), frame_color)
	_box(visual, Vector3(width, fw, t + 0.02), Vector3(0, sill_height + fw * 0.5, 0), frame_color)
	_box(visual, Vector3(width, fw, t + 0.02), Vector3(0, top_height - fw * 0.5, 0), frame_color)
	# Glass pane (slides up when open, hidden when smashed).
	_pane = _box(visual, Vector3(width - fw * 2.0, open_h - fw * 2.0, 0.03),
		Vector3(0, sill_height + open_h * 0.5, 0), glass_color, true)
	_pane.name = "Pane"
	_shards = _box(visual, Vector3(width - fw * 2.0, 0.12, 0.03),
		Vector3(0, sill_height + fw + 0.06, 0), Color(0.75, 0.85, 0.95, 0.7), true)
	_shards.name = "Shards"
	_shards.visible = false
	# Sill and header block walking (and bake into the navmesh); the glass
	# is its own body on the pane layer.
	_add_shape(Vector3(width, sill_height, t), Vector3(0, sill_height * 0.5, 0))
	_add_shape(Vector3(width, header_h, t), Vector3(0, top_height + header_h * 0.5, 0))
	_pane_body = StaticBody3D.new()
	_pane_body.name = "Pane"
	_pane_body.collision_layer = 1 << PANE_LAYER_BIT
	_pane_body.collision_mask = 0
	var ps := CollisionShape3D.new()
	var pbs := BoxShape3D.new()
	pbs.size = Vector3(width, open_h, t)
	ps.shape = pbs
	ps.position = Vector3(0, sill_height + open_h * 0.5, 0)
	_pane_body.add_child(ps)
	add_child(_pane_body)


## Round 7: warm, emissive glass while the house lights are on (night,
## DayNightLighting); plain glass otherwise.
func set_night_glow(on: bool) -> void:
	night_glow = on
	if _pane == null:
		return
	var m := (_pane.mesh as BoxMesh).material as StandardMaterial3D
	if m == null:
		return
	m.emission_enabled = on
	m.emission = Color(1.0, 0.55, 0.2)
	m.emission_energy_multiplier = 0.8
	m.albedo_color = Color(0.95, 0.62, 0.3, 0.9) if on else glass_color


func can_climb() -> bool:
	return state != STATE_CLOSED and not is_barricaded()


# --- Barricade hooks / zombie entry (Round 9) ------------------------------------------

func barricade_kind() -> StringName:
	return &"window"


## The opening in this node's local space.
func barricade_opening() -> Dictionary:
	return {"center_x": 0.0, "width": width, "bottom": sill_height, "top": top_height,
		"face": wall_thickness * 0.5}


## Characters (player 2, zombies 3) in the opening block nailing.
const CLIMBER_MASK := (1 << 1) | (1 << 2)


func barricade_block_reason(_actor: Node) -> String:
	if someone_in_opening():
		return "Someone is in the window"
	return ""


## True while a body (a climbing player or zombie) is inside the opening.
func someone_in_opening() -> bool:
	var h := top_height - sill_height
	return _box_blocked(Vector3(width, h, 0.5), Vector3(0, sill_height + h * 0.5, 0), Basis(), CLIMBER_MASK)


func on_barricade_changed(_planks: int) -> void:
	_update_nav_cost()
	EventBus.window_state_changed.emit(self, state)


## Breakable contract: zombies must get past planks, then a closed pane.
func blocks_path() -> bool:
	return state == STATE_CLOSED or is_barricaded()


## Zombie hits: the planks first; a closed pane smashes after
## [pane_health] damage (a 20 m window_smash, [source]'s noise).
func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> Dictionary:
	var planks := BarricadeComponent.of(self)
	if planks != null and planks.blocks_path():
		return planks.take_damage(amount, source, info)
	if amount <= 0.0 or state != STATE_CLOSED:
		return {"ok": false, "broken": state == STATE_SMASHED}
	_pane_hp -= amount
	if _pane_hp <= 0.0:
		smash(source)
		return {"ok": true, "broken": true}
	SoundManager.emit_sound(&"barricade_bang", sound_position(source), source, {"radius": 8.0})
	return {"ok": true, "broken": false}


## The flat point 0.75 m off the wall on [p]'s side (a zombie's link end).
func approach_point(p: Vector3) -> Vector3:
	var a := global_position + normal() * side_of(p) * nav_link_offset
	a.y = global_position.y
	return a


## Zombies crossing: extra path cost of the nav link.
func nav_cost() -> float:
	var b := BarricadeComponent.of(self)
	var per_plank := b.data.nav_cost_per_plank if b != null and b.data != null else 8.0
	return EntryPlanner.window_link_cost(state == STATE_CLOSED, barricade_planks(), per_plank)


func _update_nav_cost() -> void:
	if nav_link != null:
		nav_link.enter_cost = nav_cost()


## World-space normal of the window (local +Z).
func normal() -> Vector3:
	return global_basis.z.normalized()


## +1 if [p] is on the local +Z side, -1 otherwise.
func side_of(p: Vector3) -> float:
	return 1.0 if to_local(p).z >= 0.0 else -1.0


## Landing point for a climber currently at [from].
func landing_point(from: Vector3) -> Vector3:
	var s := side_of(from)
	var land := global_position - normal() * s * climb_clearance
	land.y = from.y
	return land


# --- Interactable provider API --------------------------------------------

func interaction_display_name() -> String:
	return "Window"


func interaction_prompt_position() -> Vector3:
	return global_position + global_basis.y * (sill_height + 0.6)


func interaction_actions(actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var busy := on_cooldown()
	var barricaded := is_barricaded()
	match state:
		STATE_CLOSED:
			out.append(Interactable.action(ACTION_OPEN, "Open window", not busy, "Busy" if busy else ""))
			if not barricaded:  # (≤ 4 entries: the number keys 4-7)
				out.append(Interactable.action(ACTION_SMASH, "Smash window"))
			out.append(Interactable.action(ACTION_CLIMB, "Climb through", false, "Barricaded" if barricaded else "Window is closed"))
		STATE_OPEN:
			out.append(Interactable.action(ACTION_CLIMB, "Climb through", not barricaded, "Barricaded" if barricaded else ""))
			out.append(Interactable.action(ACTION_CLOSE, "Close window", not busy, "Busy" if busy else ""))
			if not barricaded:
				out.append(Interactable.action(ACTION_SMASH, "Smash window"))
		STATE_SMASHED:
			# Open / close are gone for good: not listed (no clutter).
			out.append(Interactable.action(ACTION_CLIMB, "Climb through (glass)" if has_glass() else "Climb through",
				not barricaded, "Barricaded" if barricaded else ""))
			if has_glass():
				out.append(Interactable.action(ACTION_CLEAR_GLASS, "Remove broken glass"))
	# Barricaded: "Barricade (N/4)" first so E nails the next plank;
	# "Remove barricade" is explicit (its number key only) and last.
	var planks := BarricadeComponent.actions_for(self, actor)
	if barricaded:
		var add: Array[Dictionary] = [planks[0]]
		out = add + out
		for i in range(1, planks.size()):
			out.append(planks[i])
	else:
		out.append_array(planks)
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	match action_id:
		ACTION_OPEN:
			return open_window(actor)
		ACTION_CLOSE:
			return close_window(actor)
		ACTION_SMASH:
			return smash(actor)
		ACTION_CLIMB:
			return climb(actor)
		ACTION_CLEAR_GLASS:
			return clear_glass(actor)
		BarricadeComponent.ACTION_ADD, BarricadeComponent.ACTION_REMOVE:
			return BarricadeComponent.perform(self, action_id, actor)
	return {"ok": false, "reason": "Unknown action"}


# --- State ------------------------------------------------------------------

func open_window(actor: Node = null) -> Dictionary:
	if state != STATE_CLOSED:
		return {"ok": false, "reason": "Frame is smashed" if state == STATE_SMASHED else "Already open"}
	if on_cooldown():
		return {"ok": false, "reason": "Busy"}
	_set_state(STATE_OPEN, actor)
	return {"ok": true}


func close_window(actor: Node = null) -> Dictionary:
	if state != STATE_OPEN:
		return {"ok": false, "reason": "Frame is smashed" if state == STATE_SMASHED else "Already closed"}
	if on_cooldown():
		return {"ok": false, "reason": "Busy"}
	_set_state(STATE_CLOSED, actor)
	return {"ok": true}


## Smash the pane ([actor] is who did it: the noise is theirs).
func smash(actor: Node = null) -> Dictionary:
	if state == STATE_SMASHED:
		return {"ok": false, "reason": "Already smashed"}
	_set_state(STATE_SMASHED, actor)
	_spawn_glass()
	return {"ok": true}


func _set_state(s: StringName, actor: Node = null) -> void:
	state = s
	_update_nav_cost()
	_mark_toggled()
	_refresh_visual()
	if _pane_body:
		_pane_body.collision_layer = (1 << PANE_LAYER_BIT) if s == STATE_CLOSED else 0
	EventBus.window_state_changed.emit(self, state)
	if is_inside_tree():
		var cat := SOUND_SMASH if s == STATE_SMASHED else (SOUND_OPEN if s == STATE_OPEN else SOUND_CLOSE)
		SoundManager.emit_sound(cat, sound_position(actor), actor)


# --- Broken glass -------------------------------------------------------------------

func _notification(what: int) -> void:
	# The glass lives next to the window (not under it): take it along.
	if what == NOTIFICATION_PREDELETE and glass != null and is_instance_valid(glass):
		glass.queue_free()


## True while shards lie on the floor / in the frame.
func has_glass() -> bool:
	return glass != null and is_instance_valid(glass)


func _spawn_glass() -> void:
	if has_glass():
		return
	glass = GlassShards.new()
	glass.name = "GlassShards"
	glass.size = Vector2(width, 2.4)
	# A sibling on the floor, not a child: the occlusion cutaway fades the
	# window's meshes, never the glass on the floor.
	var host := get_parent() if get_parent() != null else self
	host.add_child(glass)
	glass.global_transform = Transform3D(global_basis.orthonormalized(), global_position)


## "Remove broken glass": [clear_glass_seconds] busy for a Character
## (instant otherwise). Clears the floor hazard and the frame shards.
func clear_glass(actor: Node = null) -> Dictionary:
	if not has_glass():
		return {"ok": false, "reason": "No glass"}
	if actor == null or not actor.has_method(&"begin_busy"):
		remove_glass()
		return {"ok": true}
	if bool(actor.get(&"is_busy")):
		return {"ok": false, "reason": "Busy"}
	if actor.has_method(&"is_dead") and actor.is_dead():
		return {"ok": false, "reason": "Dead"}
	_clearing_actor = actor
	if actor.has_signal(&"busy_cancelled") and not actor.is_connected(&"busy_cancelled", _on_clear_cancelled):
		actor.connect(&"busy_cancelled", _on_clear_cancelled)
	var tw: Tween = actor.call(&"begin_busy", CLEAR_GLASS_CONTEXT)
	tw.tween_interval(clear_glass_seconds)
	tw.tween_callback(_finish_clear.bind(actor))
	EventBus.timed_action_started.emit(actor, CLEAR_GLASS_CONTEXT, "Removing broken glass…", clear_glass_seconds)
	SoundManager.emit_sound(&"glass_clear", sound_position(actor), actor)
	return {"ok": true, "busy": true, "seconds": clear_glass_seconds}


func is_clearing_glass() -> bool:
	return _clearing_actor != null and is_instance_valid(_clearing_actor) \
		and bool(_clearing_actor.get(&"is_busy")) and _clearing_actor.get(&"busy_context") == CLEAR_GLASS_CONTEXT


func remove_glass() -> void:
	if has_glass():
		glass.queue_free()
	glass = null
	if _shards:
		_shards.visible = false
	EventBus.window_state_changed.emit(self, state)


func _finish_clear(actor: Node) -> void:
	_stop_clearing(actor)
	remove_glass()
	EventBus.timed_action_finished.emit(actor, CLEAR_GLASS_CONTEXT, true)


func _on_clear_cancelled(context: StringName) -> void:
	if context != CLEAR_GLASS_CONTEXT:
		return
	var actor := _clearing_actor
	_stop_clearing(actor)
	EventBus.timed_action_finished.emit(actor, CLEAR_GLASS_CONTEXT, false)


func _stop_clearing(actor: Node) -> void:
	if actor != null and is_instance_valid(actor) and actor.is_connected(&"busy_cancelled", _on_clear_cancelled):
		actor.disconnect(&"busy_cancelled", _on_clear_cancelled)
	_clearing_actor = null


# --- Sound propagation --------------------------------------------------------------

func sound_passes() -> bool:
	return state != STATE_CLOSED


## A ray hitting the pane (closed) is muffled ×0.7; hitting the sill /
## header of an open window counts as wall.
func sound_obstacle_kind() -> StringName:
	return SoundMath.WINDOW_CLOSED if state == STATE_CLOSED else SoundMath.WALL


func _refresh_visual() -> void:
	if _pane == null:
		return
	var open_h := top_height - sill_height
	var closed_y := sill_height + open_h * 0.5
	_kill_tween()
	match state:
		STATE_CLOSED:
			_pane.visible = true
			_shards.visible = false
			_slide_pane(closed_y)
		STATE_OPEN:
			_pane.visible = true
			_shards.visible = false
			_slide_pane(closed_y + open_h * 0.45)
		STATE_SMASHED:
			_pane.visible = false
			_shards.visible = true


func _slide_pane(y: float) -> void:
	if not is_inside_tree():
		_pane.position.y = y
		return
	_new_tween().tween_property(_pane, "position:y", y, 0.3)


## Move [actor] to the other side over [climb_seconds]. The actor must be a
## Node3D; if it supports begin_busy() (Character) the tween is owned by the
## actor and its busy lock is released by the actor itself.
func climb(actor: Node) -> Dictionary:
	if is_barricaded():
		return {"ok": false, "reason": "Barricaded", "hazard": false}
	if not can_climb():
		return {"ok": false, "reason": "Window is closed", "hazard": false}
	var body := actor as Node3D
	if body == null:
		return {"ok": false, "reason": "No actor", "hazard": false}
	if "is_busy" in body and body.is_busy:
		return {"ok": false, "reason": "Busy", "hazard": false}
	var hazard := state == STATE_SMASHED and has_glass()
	last_climb_hazard = hazard
	var from := body.global_position
	var target := landing_point(from)
	var over := Vector3(global_position.x, from.y + sill_height + 0.05, global_position.z)
	var tw: Tween
	if body.has_method(&"begin_busy"):
		tw = body.begin_busy(CLIMB_CONTEXT)
	else:
		tw = body.create_tween()
		tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Up onto the sill, over, then down on the far side.
	tw.tween_property(body, "global_position", over, climb_seconds * 0.5)
	tw.tween_property(body, "global_position", target, climb_seconds * 0.5)
	# Bound to the window weakly: if we are freed mid-climb the actor still
	# lands (its own tween) and nothing here runs.
	tw.finished.connect(_on_climb_finished.bind(body, hazard))
	return {"ok": true, "hazard": hazard, "landing": target}


func _on_climb_finished(body: Node3D, hazard: bool) -> void:
	if is_instance_valid(self) and is_instance_valid(body):
		EventBus.window_climbed.emit(body, self, hazard)


# --- Save (Round 10) ------------------------------------------------------------------

## {state, glass, pane_hp, barricade?} (Saveable contract).
func save_state() -> Dictionary:
	var d := {"kind": "window", "state": String(state), "glass": has_glass(), "pane_hp": _pane_hp}
	var b := BarricadeComponent.of(self)
	if b != null and b.plank_count() > 0:
		d["barricade"] = b.to_dict()
	return d


## Silent restore: no sound, no tween; shards come back when [glass].
func load_state(d: Dictionary) -> void:
	var s := StringName(String(d.get("state", "closed")))
	if s != STATE_OPEN and s != STATE_SMASHED:
		s = STATE_CLOSED
	state = s
	_pane_hp = clampf(float(d.get("pane_hp", pane_health)), 0.0, pane_health)
	if _pane_body:
		_pane_body.collision_layer = (1 << PANE_LAYER_BIT) if s == STATE_CLOSED else 0
	_kill_tween()
	if _pane != null:
		var open_h := top_height - sill_height
		var closed_y := sill_height + open_h * 0.5
		_pane.visible = s != STATE_SMASHED
		_pane.position.y = closed_y + (open_h * 0.45 if s == STATE_OPEN else 0.0)
	var want_glass := bool(d.get("glass", false)) and s == STATE_SMASHED
	if want_glass:
		_spawn_glass()
	elif has_glass():
		glass.queue_free()
		glass = null
	if _shards:
		_shards.visible = want_glass
	if d.has("barricade"):
		BarricadeComponent.ensure(self).from_dict(d.barricade)
	elif BarricadeComponent.of(self) != null:
		BarricadeComponent.of(self).from_dict({"planks": []})
	_update_nav_cost()
