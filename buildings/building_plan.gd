class_name BuildingPlan
extends Resource
## Data description of a building floor plan. Edit the .tres, not code.
##
## All coordinates are building-local metres on the XZ plane: x to the
## right, z towards the front (south / +Z). The building origin is the
## footprint's min corner at floor level.
##
## rooms: [{ "name": "Kitchen", "rect": Rect2(x, z, w, d) }]
## walls: [{
##     "from": Vector2(x, z), "to": Vector2(x, z),
##     "outward": Vector2(nx, nz)     # unit normal for exterior walls, omit
##                                    # (or ZERO) for interior walls
##     "openings": [{ "type": "door"|"window", "at": float (distance from
##                   `from` to the opening centre), "width": float }]
## }]

@export var display_name: String = "House"
## Footprint size (x, z) in metres.
@export var footprint: Vector2 = Vector2(10, 8)
@export var wall_height: float = 2.7
@export var wall_thickness: float = 0.2
@export var door_width: float = 0.9
@export var door_height: float = 2.1
@export var window_width: float = 1.2
## Window sill (bottom of glass) and top of glass, from the floor.
@export var window_sill_height: float = 0.9
@export var window_top_height: float = 2.1
@export var wall_color: Color = Color(0.62, 0.58, 0.5)
@export var interior_wall_color: Color = Color(0.7, 0.68, 0.62)
@export var floor_color: Color = Color(0.45, 0.36, 0.28)
@export var roof_color: Color = Color(0.36, 0.3, 0.3)
@export var rooms: Array[Dictionary] = []
@export var walls: Array[Dictionary] = []


func opening_width(opening: Dictionary) -> float:
	if opening.has("width"):
		return float(opening["width"])
	return door_width if String(opening.get("type", "door")) == "door" else window_width


## Sanity-check the plan. Returns a list of human-readable problems (empty
## when the plan is fine). HouseBlockout warns about each at _ready.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if rooms.is_empty():
		problems.append("plan has no rooms")
	if wall_height <= 0.0:
		problems.append("wall_height must be > 0")
	if door_height <= 0.0 or door_height > wall_height:
		problems.append("door_height %.2f is outside (0, wall_height]" % door_height)
	if not (0.0 <= window_sill_height and window_sill_height < window_top_height and window_top_height <= wall_height):
		problems.append("window heights inconsistent: sill %.2f, top %.2f, wall %.2f" % [window_sill_height, window_top_height, wall_height])
	for wi in walls.size():
		var wall: Dictionary = walls[wi]
		var from: Vector2 = wall.get("from", Vector2.ZERO)
		var to: Vector2 = wall.get("to", Vector2.ZERO)
		var length := from.distance_to(to)
		var label := "wall %d (%s -> %s)" % [wi, from, to]
		if length <= 0.001:
			problems.append("%s has zero length" % label)
			continue
		var spans: Array = []
		for o in wall.get("openings", []):
			var w := opening_width(o)
			var at := float(o.get("at", 0.0))
			var kind := String(o.get("type", "door"))
			if w > length + 0.001:
				problems.append("%s: %s at %.2f is wider (%.2f) than the wall (%.2f)" % [label, kind, at, w, length])
			if at - w * 0.5 < -0.001 or at + w * 0.5 > length + 0.001:
				problems.append("%s: %s at %.2f (width %.2f) extends past the wall end" % [label, kind, at, w])
			spans.append([at - w * 0.5, at + w * 0.5, kind, at])
		spans.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(1, spans.size()):
			if spans[i][0] < spans[i - 1][1] - 0.001:
				problems.append("%s: %s at %.2f overlaps %s at %.2f" % [label, spans[i][2], spans[i][3], spans[i - 1][2], spans[i - 1][3]])
	return problems
