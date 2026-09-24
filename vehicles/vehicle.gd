class_name Vehicle
extends StaticBody3D
## A parked vehicle (Round 8.5): procedural VehicleBuilder mesh from
## [data] + [variant_seed] (colour, rust, flat tyre, missing hubcap), a box
## collider on layers 1 (world: blocks movement, baked into the navmesh so
## zombies path around it) + 6 (occluder: fades when it hides the player),
## groups "vehicle" / "occluder", and two VehicleContainer children:
## "Trunk" ("Search trunk" / "Search truck bed", table vehicle_trunk) at
## the rear and "Glovebox" ("Search glovebox", table vehicle_glovebox) at
## the driver's (left) door. Night: emergency vehicles (lights_at_night +
## light bar) run their alternating beacons and one small OmniLight3D
## (budget MAX_BEACON_LIGHTS); DayNightLighting calls set_night_lights on
## the "vehicle" group. Meshes / materials come from VehicleAssets.
## Driving is a later round: a VehicleBody3D will reuse VehicleData +
## VehicleBuilder the same way.
## Round 12: [has_alarm] cars (parked in town) may go off when broken into
## (the first search of the trunk / glovebox): [alarm_chance], rolled
## deterministically from the world seed and the car's id; the alarm
## sounds (category "alarm", [alarm_radius] m) every ALARM_REPEAT seconds
## for [alarm_seconds] — loud enough to pull the zombie population from
## a few hundred metres (SoundCategory.sim_carry).

const GROUP := &"vehicle"
const LAYER_WORLD := 1
const LAYER_OCCLUDERS := 1 << 5
const BEACON_HZ := 2.0
const BEACON_GROUP := &"vehicle_beacon_light"
## Global budget of emergency light pools at night.
const MAX_BEACON_LIGHTS := 4

@export var data: VehicleData
## Wear / colour seed (0 = derived from the node name).
@export var variant_seed: int = 0
## Persist id prefix for the containers ("" = "Vehicle/<name>").
@export var persist_prefix: String = ""
@export var has_alarm: bool = false
@export var alarm_chance: float = 0.3
@export var alarm_radius: float = 90.0
@export var alarm_seconds: float = 30.0

const ALARM_REPEAT := 5.0
## Seconds of alarm left (> 0 while it sounds).
var alarm_left: float = 0.0
var _alarm_emit: float = 0.0

var visual: Node3D
var mesh_instance: MeshInstance3D
var trunk: VehicleContainer
var glovebox: VehicleContainer
var variation: Dictionary = {}
var lights_on: bool = false
var beacon_light: OmniLight3D
var _beacon_phase_a: bool = false
var _surfaces: Dictionary = {}
var _beacon_t: float = 0.0


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"occluder")
	collision_layer = LAYER_WORLD | LAYER_OCCLUDERS
	collision_mask = 0
	if data == null:
		data = VehicleData.new()
	if variant_seed == 0:
		variant_seed = hash(String(name)) | 1
	variation = VehicleBuilder.variation_for(data, variant_seed)
	_build_visual()
	_build_collision()
	_build_containers()
	set_process(false)
	var dn := get_tree().get_first_node_in_group(&"day_night")
	if dn != null and bool(dn.get("lights_on")):
		set_night_lights(true)


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	visual.add_child(mesh_instance)
	var mesh := VehicleAssets.of(get_tree()).mesh_for(data, variant_seed)
	mesh_instance.mesh = mesh
	_surfaces = mesh.get_meta(&"surfaces", {})
	# OcclusionManager: never fade a car below half alpha and keep writing
	# depth while faded, so its inner faces (cabin, wheels, underside) do
	# not show through (x-ray).
	mesh_instance.set_meta(&"occl_min_alpha", 0.5)
	mesh_instance.set_meta(&"occl_depth_always", true)


func _build_collision() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	var s := VehicleBuilder.collision_size(data)
	box.size = s
	shape.shape = box
	shape.position = Vector3(0, s.y * 0.5, 0)
	add_child(shape)


func _build_containers() -> void:
	var prefix := persist_prefix if persist_prefix != "" else "Vehicle/%s" % name
	var hl := data.length * 0.5
	var hw := data.width * 0.5
	trunk = VehicleContainer.new()
	trunk.name = "Trunk"
	trunk.container_type = &"vehicle_trunk"
	trunk.display_name = "Truck bed" if data.shape == &"pickup" else "Trunk"
	trunk.search_label = data.trunk_label
	trunk.capacity = data.trunk_capacity
	trunk.persist_id = prefix + "/trunk"
	trunk.search_seconds = 1.5
	trunk.shape_size = Vector3(data.width * 0.8, 0.9, 0.3)
	trunk.prompt_offset = Vector3(0, 1.0, 0.25)
	trunk.position = Vector3(0, 0, hl + 0.2)
	add_child(trunk)
	glovebox = VehicleContainer.new()
	glovebox.name = "Glovebox"
	glovebox.container_type = &"vehicle_glovebox"
	glovebox.display_name = "Glovebox"
	glovebox.search_label = "Search glovebox"
	glovebox.capacity = data.glovebox_capacity
	glovebox.persist_id = prefix + "/glovebox"
	glovebox.shape_size = Vector3(0.3, 1.0, 0.9)
	glovebox.prompt_offset = Vector3(-0.2, 1.05, 0)
	var zdoor := -hl + data.cabin.y * data.length + 0.2
	glovebox.position = Vector3(-hw - 0.18, 0, zdoor)
	add_child(glovebox)


## Night hook (DayNightLighting): emergency vehicles left with their
## light bar running glow after dark and cast one small alternating
## red / blue light pool (at most MAX_BEACON_LIGHTS in the scene).
## Parked cars keep their head / tail lamps off.
func set_night_lights(night: bool) -> void:
	var on := night and data.lights_at_night and data.light_bar
	if on == lights_on:
		return
	lights_on = on
	var assets := VehicleAssets.of(get_tree())
	for s: StringName in [&"beacon_a", &"beacon_b"]:
		if _surfaces.has(s):
			mesh_instance.set_surface_override_material(_surfaces[s], assets.material(s, true) if on else null)
	if on:
		if get_tree().get_nodes_in_group(BEACON_GROUP).size() < MAX_BEACON_LIGHTS:
			if beacon_light == null:
				beacon_light = OmniLight3D.new()
				beacon_light.name = "BeaconLight"
				beacon_light.omni_range = 4.0
				beacon_light.light_energy = 0.8
				beacon_light.shadow_enabled = false
				beacon_light.position = Vector3(0, data.roof_height + 0.4, 0)
				add_child(beacon_light)
			beacon_light.visible = true
			beacon_light.add_to_group(BEACON_GROUP)
	elif beacon_light:
		beacon_light.visible = false
		beacon_light.remove_from_group(BEACON_GROUP)
	_beacon_t = 0.0
	set_process(on or alarm_left > 0.0)


## Broken into (VehicleContainer's first search): maybe the alarm.
## Returns true when it went off.
func on_break_in() -> bool:
	if not has_alarm or alarm_left > 0.0:
		return false
	var ws := 0
	var cfg := WorldConfig.find(get_tree()) if is_inside_tree() else null
	if cfg != null:
		ws = cfg.world_seed
	var r := RandomNumberGenerator.new()
	r.seed = WorldGenerator.sub_seed(ws, "%s/alarm" % (persist_prefix if persist_prefix != "" else String(name)))
	if r.randf() >= alarm_chance:
		return false
	sound_alarm()
	return true


## Start the alarm now (tests call it directly).
func sound_alarm() -> void:
	alarm_left = alarm_seconds
	_alarm_emit = 0.0
	set_process(true)


func is_alarm_sounding() -> bool:
	return alarm_left > 0.0


func _process(delta: float) -> void:
	if alarm_left > 0.0:
		_alarm_emit -= delta
		if _alarm_emit <= 0.0:
			_alarm_emit = ALARM_REPEAT
			SoundManager.emit_sound(&"alarm", global_position, self, {"radius": alarm_radius, "intensity": 1.0})
		alarm_left -= delta
		if alarm_left <= 0.0 and not lights_on:
			set_process(false)
	if not lights_on:
		return
	# Alternate the light bar halves (and the light pool's colour).
	var first := _beacon_t == 0.0
	_beacon_t += delta
	var a_on := fmod(_beacon_t * BEACON_HZ, 1.0) < 0.5
	if a_on == _beacon_phase_a and not first:
		return
	_beacon_phase_a = a_on
	var assets := VehicleAssets.of(get_tree())
	if _surfaces.has(&"beacon_a"):
		mesh_instance.set_surface_override_material(_surfaces[&"beacon_a"], assets.material(&"beacon_a", a_on))
	if _surfaces.has(&"beacon_b"):
		mesh_instance.set_surface_override_material(_surfaces[&"beacon_b"], assets.material(&"beacon_b", not a_on))
	if beacon_light and beacon_light.visible:
		var cols := data.light_bar_colors
		var ca: Color = cols[0] if cols.size() > 0 else Color.RED
		var cb: Color = cols[1] if cols.size() > 1 else ca
		beacon_light.light_color = ca if a_on else cb


## Storage parts (tests / UI).
func containers() -> Array[VehicleContainer]:
	return [trunk, glovebox]
