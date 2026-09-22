class_name PlayerCombatInput
extends Node
## Player input for fighting and first aid (child of the Player):
## attack (LMB, hold to charge), aim (RMB: face the mouse on the ground,
## walk speed), shove (Space), cycle_weapon (X), bandage (B), hotbar
## 1-3 (keys 1-3 with ANY modifier held — sprinting, sneaking, walking —
## equip / put away the assigned item; the interaction alternatives are on
## keys 4-7, see PlayerInteraction). Attacks are ignored while the
## inventory / loot screen is open and when the press starts over GUI.
## Drives the sibling MeleeCombat / InjuryComponent; no gameplay rules
## here. Ignored while the combat component is [scripted] (tests).

@onready var character: Character = get_parent() as Character
@onready var combat: MeleeCombat = get_parent().get_node_or_null("Combat") as MeleeCombat

## True while the inventory / loot screen is visible.
var screen_open: bool = false


func _ready() -> void:
	EventBus.inventory_screen_toggled.connect(func(v: bool): screen_open = v)


func _unhandled_input(event: InputEvent) -> void:
	if combat == null or combat.scripted or character == null or character.is_dead():
		return
	if event.is_action_pressed(&"attack"):
		if screen_open or (event is InputEventMouseButton and _mouse_over_gui()):
			return  # a click meant for the inventory screen
		_update_aim()
		combat.start_attack()
	elif event.is_action_released(&"attack"):
		combat.release_attack()
	elif event.is_action_pressed(&"shove"):
		_update_aim()
		combat.shove()
	elif event.is_action_pressed(&"cycle_weapon"):
		if character.has_method(&"cycle_weapon"):
			character.call(&"cycle_weapon")
	elif event.is_action_pressed(&"bandage"):
		if character.injuries:
			character.injuries.bandage_worst()
	else:
		for i in 3:
			# Non-exact: Shift / Ctrl / Alt (sprint / sneak / walk) may be held.
			if event.is_action_pressed(StringName("hotbar_%d" % (i + 1))):
				if character.has_method(&"use_hotbar"):
					character.call(&"use_hotbar", i)
				return


func _physics_process(_delta: float) -> void:
	if combat == null or combat.scripted or character == null:
		return
	var want_aim := Input.is_action_pressed(&"aim") and not character.is_dead()
	if want_aim and not combat.aiming and _mouse_over_gui():
		want_aim = false  # right-click on the inventory is a context menu
	if want_aim:
		_update_aim()
	if want_aim != combat.aiming:
		combat.set_aiming(want_aim)
	# A release can be lost (focus change, GUI): never charge forever.
	if combat.phase == MeleeCombat.Phase.CHARGING and not Input.is_action_pressed(&"attack"):
		combat.release_attack()


func _mouse_over_gui() -> bool:
	var vp := get_viewport()
	return vp != null and vp.gui_get_hovered_control() != null


func _update_aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := ground_point(cam, get_viewport().get_mouse_position(), character.global_position.y)
	if p == Vector3.INF:
		return
	var d := p - character.global_position
	d.y = 0.0
	if d.length_squared() > 0.01:
		combat.aim_direction = d.normalized()


## Where the ray through [screen_pos] meets the horizontal plane at
## [plane_y] (works for the orthographic camera: the ray ORIGIN moves with
## the pixel, the normal is constant). Vector3.INF when parallel / behind.
static func ground_point(cam: Camera3D, screen_pos: Vector2, plane_y: float) -> Vector3:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, plane_y).intersects_ray(from, dir)
	return hit if hit is Vector3 else Vector3.INF
