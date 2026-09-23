class_name VehicleData
extends Resource
## One kind of vehicle (data/vehicles/*.tres): body shape, dimensions,
## colour palette / livery and its storage. VehicleBuilder turns it into a
## low-poly mesh; Vehicle (parked, static) and later a VehicleBody3D
## (driving) reuse the same data + builder. Metres; the car faces -Z.

## &"sedan", &"wagon", &"pickup", &"van" (police / fire use a base shape
## plus a livery).
@export var id: StringName = &""
@export var display_name: String = "Car"
@export var shape: StringName = &"sedan"
@export_group("Dimensions")
@export var length: float = 4.9
@export var width: float = 1.86
## Top of the doors / hood line.
@export var belt_height: float = 0.92
@export var roof_height: float = 1.4
@export var wheel_radius: float = 0.33
@export var wheelbase: float = 2.8
## Cabin (greenhouse) along the length, as fractions from the front
## bumper: windshield base, roof front, roof rear, rear window base.
@export var cabin: Vector4 = Vector4(0.32, 0.44, 0.7, 0.8)
## Pickups: where the open bed starts (fraction from the front).
@export var bed_start: float = 0.6
@export_group("Look")
## One is picked per vehicle (seeded).
@export var palette: Array[Color] = [Color(0.55, 0.12, 0.1)]
@export var trim_color: Color = Color(0.62, 0.62, 0.6)
## &"none", &"police" (black-and-white doors + roof), &"fire" (white
## roof + side stripe).
@export var livery: StringName = &"none"
@export var livery_color: Color = Color(0.95, 0.95, 0.95)
@export var light_bar: bool = false
@export var light_bar_colors: Array[Color] = [Color(0.9, 0.1, 0.08), Color(0.1, 0.25, 0.95)]
## Pickup bed cargo boxes (fire trucks: equipment lockers).
@export var bed_boxes: bool = false
@export_group("Wear")
@export var rust_chance: float = 0.5
@export var flat_tire_chance: float = 0.15
@export_group("Storage")
@export var trunk_label: String = "Search trunk"
@export var trunk_capacity: float = 40.0
@export var glovebox_capacity: float = 4.0
## Extra lights at night while parked (abandoned emergency vehicles).
@export var lights_at_night: bool = false


func validate() -> Array[String]:
	var out: Array[String] = []
	if id == &"":
		out.append("vehicle without id")
	if not shape in [&"sedan", &"wagon", &"pickup", &"van"]:
		out.append("%s: unknown shape '%s'" % [id, shape])
	if palette.is_empty():
		out.append("%s: empty palette" % id)
	if wheelbase >= length or wheel_radius <= 0.0 or belt_height >= roof_height:
		out.append("%s: inconsistent dimensions" % id)
	if not (cabin.x < cabin.y and cabin.y < cabin.z and cabin.z < cabin.w):
		out.append("%s: cabin fractions must increase" % id)
	return out
