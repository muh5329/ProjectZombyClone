extends Node
## Global gameplay event bus (autoload: EventBus).
##
## Systems talk to each other through signals here instead of holding direct
## references. Keep signals coarse and gameplay-meaningful. Payloads are plain
## values or Dictionaries so listeners never depend on emitter node types.

# --- Player / character -----------------------------------------------------
## Emitted when any character's movement mode changes (walk/jog/sprint/sneak).
signal movement_mode_changed(character: Node, mode: StringName)
## Emitted when a stat crosses a meaningful threshold (e.g. stamina exhausted).
signal stat_threshold(character: Node, stat: StringName, state: StringName)
## Emitted every time a stat value changes (throttle listeners if needed).
signal stat_changed(character: Node, stat: StringName, value: float, max_value: float)
## Emitted once when a sprint request starts being refused (winded).
signal sprint_denied(character: Node)

# --- Camera -----------------------------------------------------------------
## Emitted when the isometric camera snaps to a new yaw step (degrees).
signal camera_rotated(yaw_degrees: float)
## Emitted when the zoom level index changes.
signal camera_zoomed(level_index: int)

# --- Interaction ------------------------------------------------------------
## The actor's best interactable (or its action list) changed. target may be
## null; actions is the current Array[Dictionary] of {id,label,enabled,reason}.
signal interaction_target_changed(actor: Node, target: Node, actions: Array)
## An action was performed on an Interactable.
signal interaction_performed(actor: Node, target: Node, action_id: StringName)
## An action was refused (disabled, locked, blocked, busy…). reason is text.
signal interaction_refused(actor: Node, target: Node, reason: String)
## Something (a zombie) banged on a door. Recruits nearby zombies via sound.
signal door_banged(door: Node, source: Node)
## A door changed state (&"open" / &"closed" / &"broken").
signal door_state_changed(door: Node, state: StringName)
## A window changed state (&"open" / &"closed" / &"smashed").
signal window_state_changed(window: Node, state: StringName)
## A character finished climbing through a window. hazard = broken glass.
signal window_climbed(actor: Node, window: Node, hazard: bool)

# --- Health -----------------------------------------------------------------
## A character took damage. info: {region: StringName, ...} (free-form).
signal character_damaged(character: Node, amount: float, source: Node, info: Dictionary)
## A character's health reached 0.
signal character_died(character: Node, source: Node)

# --- Sound (stub; Round 8 adds propagation / occlusion) --------------------
## Something made a noise. radius in metres, intensity 0..1, category e.g.
## &"footstep", &"door", &"glass". source may be null.
signal sound_emitted(position: Vector3, radius: float, intensity: float, category: StringName, source: Node)

# --- Zombies ----------------------------------------------------------------
signal zombie_state_changed(zombie: Node, from: StringName, to: StringName)
signal zombie_spotted_target(zombie: Node, target: Node)
signal zombie_lost_target(zombie: Node)
## hit = false when the swing missed (target moved away / not facing).
signal zombie_attacked(zombie: Node, target: Node, hit: bool)
signal zombie_died(zombie: Node, killer: Node)

# --- Buildings / location ---------------------------------------------------
## The player entered a Room (or left all rooms: room == null).
signal player_room_changed(room: Node, building: Node)

# --- World / debug ----------------------------------------------------------
## Free-form debug message for the on-screen log (dev only).
signal debug_message(text: String)


func debug(text: String) -> void:
	debug_message.emit(text)
