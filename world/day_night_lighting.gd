class_name DayNightLighting
extends Node
## Sun / ambient lighting that follows world time (Round 7; node
## "DayNight" in the map). Every physics tick (cheap) the TimeManager hour
## picks a blend of keyframes (lighting_at, pure): full daylight 07:00-
## 18:30, a warm dusk, a dark-blue night (never pitch black: moonlight +
## blue ambient, reference 3), a pink-grey dawn. Interior lights (group
## `interior_light`, OmniLight3D per building room — HouseBlockout adds
## them) switch on while the sun is below [lights_on_below].

## Sun / moon DirectionalLight3D and the WorldEnvironment to drive.
@export var sun_path: NodePath = ^"../Sun"
@export var environment_path: NodePath = ^"../WorldEnvironment"
## Interior lights are on while the sun energy is below this.
@export var lights_on_below: float = 0.5

## [hour, sun_energy, sun_color, ambient_color, ambient_energy, background]
const KEYS: Array = [
	[0.0, 0.1, Color(0.72, 0.75, 0.85), Color(0.34, 0.35, 0.38), 0.3, Color(0.06, 0.06, 0.07)],
	[4.5, 0.1, Color(0.72, 0.75, 0.85), Color(0.34, 0.35, 0.38), 0.3, Color(0.06, 0.06, 0.07)],
	[5.75, 0.45, Color(1.0, 0.72, 0.6), Color(0.62, 0.58, 0.72), 0.32, Color(0.35, 0.33, 0.42)],
	[7.0, 0.85, Color(1.0, 1.0, 1.0), Color(0.75, 0.78, 0.85), 0.35, Color(0.45, 0.52, 0.6)],
	[18.5, 0.85, Color(1.0, 1.0, 1.0), Color(0.75, 0.78, 0.85), 0.35, Color(0.45, 0.52, 0.6)],
	[20.0, 0.42, Color(1.0, 0.62, 0.42), Color(0.6, 0.5, 0.6), 0.32, Color(0.32, 0.27, 0.36)],
	[21.5, 0.1, Color(0.72, 0.75, 0.85), Color(0.34, 0.35, 0.38), 0.3, Color(0.06, 0.06, 0.07)],
	[24.0, 0.1, Color(0.72, 0.75, 0.85), Color(0.34, 0.35, 0.38), 0.3, Color(0.06, 0.06, 0.07)],
]

var sun: DirectionalLight3D
var environment: Environment
var lights_on: bool = false
var _last_hour: float = -1.0


func _ready() -> void:
	add_to_group(&"day_night")
	sun = get_node_or_null(sun_path) as DirectionalLight3D
	var we := get_node_or_null(environment_path) as WorldEnvironment
	environment = we.environment if we else null
	# Lights created by buildings that are ready before / after us.
	apply(TimeManager.hour_float(), true)


## Pure: lighting for a fractional hour 0..24 → {sun_energy, sun_color,
## ambient_color, ambient_energy, background}.
static func lighting_at(hour_f: float) -> Dictionary:
	var h := fposmod(hour_f, 24.0)
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if h >= float(a[0]) and h <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var t := 0.0 if span <= 0.0 else (h - float(a[0])) / span
			t = t * t * (3.0 - 2.0 * t)  # smoothstep
			return {
				"sun_energy": lerpf(a[1], b[1], t),
				"sun_color": (a[2] as Color).lerp(b[2], t),
				"ambient_color": (a[3] as Color).lerp(b[3], t),
				"ambient_energy": lerpf(a[4], b[4], t),
				"background": (a[5] as Color).lerp(b[5], t),
			}
	var k: Array = KEYS[0]
	return {"sun_energy": k[1], "sun_color": k[2], "ambient_color": k[3], "ambient_energy": k[4], "background": k[5]}


func _physics_process(_delta: float) -> void:
	var h := TimeManager.hour_float()
	if absf(h - _last_hour) < 0.01:
		return
	apply(h)


func apply(hour_f: float, force: bool = false) -> void:
	_last_hour = hour_f
	var l := lighting_at(hour_f)
	if sun:
		sun.light_energy = l.sun_energy
		sun.light_color = l.sun_color
	if environment:
		environment.ambient_light_color = l.ambient_color
		environment.ambient_light_energy = l.ambient_energy
		environment.background_color = l.background
	var on := float(l.sun_energy) < lights_on_below
	if on != lights_on or force:
		lights_on = on
		for n in get_tree().get_nodes_in_group(&"interior_light"):
			(n as Node3D).visible = on
		# Round 11: a light budget (the generated world) trims that set.
		get_tree().call_group(&"light_budget", &"update_lights")
		for w in get_tree().get_nodes_in_group(&"window"):
			if w.has_method(&"set_night_glow"):
				w.call(&"set_night_glow", on)
		# Round 8.5: parked emergency vehicles left with their lights on.
		for v in get_tree().get_nodes_in_group(&"vehicle"):
			if v.has_method(&"set_night_lights"):
				v.call(&"set_night_lights", on)


## Current sun energy (tests compare noon vs night).
func sun_energy() -> float:
	return sun.light_energy if sun else 0.0
