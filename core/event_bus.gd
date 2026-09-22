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

# --- World / debug ----------------------------------------------------------
## Free-form debug message for the on-screen log (dev only).
signal debug_message(text: String)


func debug(text: String) -> void:
	debug_message.emit(text)
