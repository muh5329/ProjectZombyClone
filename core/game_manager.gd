extends Node
## Game-level state (autoload: GameManager).
##
## Round 1 scope: holds a reference to the active player and exposes
## debug toggles. Save/load, time, and world management are added in later
## rounds as their own managers; this node must NOT grow into a god object.

## The currently controlled player node, registered by Player._ready().
var player: Node = null

## When true, HUD shows extra debug info (toggle with F3 / "toggle_debug").
var debug_overlay: bool = true

## When true, the SoundDebugOverlay draws every live sound event and the
## zombie hearing lines (toggle with F4 / "toggle_sound_debug").
var sound_debug: bool = false

## Set by the test harness so gameplay code can skip things that need a
## real window (e.g. mouse capture).
var headless: bool = false


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"


func register_player(p: Node) -> void:
	player = p


func unregister_player(p: Node) -> void:
	if player == p:
		player = null


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		debug_overlay = not debug_overlay
	elif event.is_action_pressed(&"toggle_sound_debug"):
		sound_debug = not sound_debug
