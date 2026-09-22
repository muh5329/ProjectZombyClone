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
## States: closed / open / smashed. Smashed windows can be climbed but with
## hazard = true (glass; injuries come in Round 4).

const STATE_CLOSED := &"closed"
const STATE_OPEN := &"open"
const STATE_SMASHED := &"smashed"
const ACTION_OPEN := &"open"
const ACTION_CLOSE := &"close"
const ACTION_SMASH := &"smash"
const ACTION_CLIMB := &"climb"
const CLIMB_CONTEXT := &"climb"
## Physics layer index (0-based) of "window_panes".
const PANE_LAYER_BIT := 7
## Noise radii (m) for EventBus.sound_emitted.
const SOUND_TOGGLE_RADIUS := 5.0
const SOUND_SMASH_RADIUS := 18.0

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

var state: StringName = STATE_CLOSED
## Set by the last climb: true when the climber went through broken glass.
var last_climb_hazard: bool = false
var _pane: MeshInstance3D
var _shards: MeshInstance3D
var _pane_body: StaticBody3D


func _init() -> void:
	fixture_group = &"window"


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


func can_climb() -> bool:
	return state != STATE_CLOSED


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


func interaction_actions(_actor: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var busy := on_cooldown()
	match state:
		STATE_CLOSED:
			out.append(Interactable.action(ACTION_OPEN, "Open window", not busy, "Busy" if busy else ""))
			out.append(Interactable.action(ACTION_SMASH, "Smash window"))
			out.append(Interactable.action(ACTION_CLIMB, "Climb through", false, "Window is closed"))
		STATE_OPEN:
			out.append(Interactable.action(ACTION_CLIMB, "Climb through"))
			out.append(Interactable.action(ACTION_CLOSE, "Close window", not busy, "Busy" if busy else ""))
			out.append(Interactable.action(ACTION_SMASH, "Smash window"))
		STATE_SMASHED:
			out.append(Interactable.action(ACTION_CLIMB, "Climb through (glass)"))
			out.append(Interactable.action(ACTION_OPEN, "Open window", false, "Frame is smashed"))
			out.append(Interactable.action(ACTION_CLOSE, "Close window", false, "Frame is smashed"))
	return out


func interaction_perform(action_id: StringName, actor: Node) -> Dictionary:
	match action_id:
		ACTION_OPEN:
			return open_window()
		ACTION_CLOSE:
			return close_window()
		ACTION_SMASH:
			return smash()
		ACTION_CLIMB:
			return climb(actor)
	return {"ok": false, "reason": "Unknown action"}


# --- State ------------------------------------------------------------------

func open_window() -> Dictionary:
	if state != STATE_CLOSED:
		return {"ok": false, "reason": "Frame is smashed" if state == STATE_SMASHED else "Already open"}
	if on_cooldown():
		return {"ok": false, "reason": "Busy"}
	_set_state(STATE_OPEN)
	return {"ok": true}


func close_window() -> Dictionary:
	if state != STATE_OPEN:
		return {"ok": false, "reason": "Frame is smashed" if state == STATE_SMASHED else "Already closed"}
	if on_cooldown():
		return {"ok": false, "reason": "Busy"}
	_set_state(STATE_CLOSED)
	return {"ok": true}


func smash() -> Dictionary:
	if state == STATE_SMASHED:
		return {"ok": false, "reason": "Already smashed"}
	_set_state(STATE_SMASHED)
	return {"ok": true}


func _set_state(s: StringName) -> void:
	state = s
	_mark_toggled()
	_refresh_visual()
	if _pane_body:
		_pane_body.collision_layer = (1 << PANE_LAYER_BIT) if s == STATE_CLOSED else 0
	EventBus.window_state_changed.emit(self, state)
	if is_inside_tree():
		if s == STATE_SMASHED:
			EventBus.sound_emitted.emit(global_position, SOUND_SMASH_RADIUS, 1.0, &"glass", null)
		else:
			EventBus.sound_emitted.emit(global_position, SOUND_TOGGLE_RADIUS, 0.3, &"window", null)


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
	if not can_climb():
		return {"ok": false, "reason": "Window is closed", "hazard": false}
	var body := actor as Node3D
	if body == null:
		return {"ok": false, "reason": "No actor", "hazard": false}
	if "is_busy" in body and body.is_busy:
		return {"ok": false, "reason": "Busy", "hazard": false}
	var hazard := state == STATE_SMASHED
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
