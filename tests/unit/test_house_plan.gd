extends "res://tests/test_case.gd"
## Pure tests for BuildingPlan -> wall segment generation.

const PlanScript = preload("res://buildings/building_plan.gd")
const HouseScript = preload("res://buildings/house_blockout.gd")


func _plan() -> BuildingPlan:
	var p: BuildingPlan = PlanScript.new()
	p.wall_height = 2.7
	p.wall_thickness = 0.2
	return p


func _kinds(segs: Array[Dictionary]) -> Array:
	var out := []
	for s in segs:
		out.append(s.kind)
	return out


func test_plain_wall_is_one_segment() -> void:
	var p := _plan()
	var segs := HouseBlockout.segments_for_wall({"from": Vector2(0, 0), "to": Vector2(6, 0)}, p)
	check_eq(segs.size(), 1, "one segment")
	check_eq(segs[0].kind, "wall", "kind")
	check_near(segs[0].a0, 0.0, 0.001, "interior wall starts at 0")
	check_near(segs[0].a1, 6.0, 0.001, "ends at length")
	check_near(segs[0].y1, 2.7, 0.001, "full height")


func test_exterior_wall_extends_by_half_thickness() -> void:
	var p := _plan()
	var segs := HouseBlockout.segments_for_wall({"from": Vector2(0, 0), "to": Vector2(6, 0), "outward": Vector2(0, -1)}, p)
	check_eq(segs.size(), 1, "one segment")
	check_near(segs[0].a0, -0.1, 0.001, "corner fill at start")
	check_near(segs[0].a1, 6.1, 0.001, "corner fill at end")


func test_door_splits_wall_and_adds_lintel() -> void:
	var p := _plan()
	var wall := {"from": Vector2(0, 0), "to": Vector2(6, 0), "openings": [{"type": "door", "at": 3.0}]}
	var segs := HouseBlockout.segments_for_wall(wall, p)
	check_eq(_kinds(segs), ["wall", "door", "lintel", "wall"], "segment order")
	var door := segs[1]
	check_near(door.a0, 2.55, 0.001, "door uses plan door_width")
	check_near(door.a1, 3.45, 0.001, "door end")
	check_near(segs[2].y0, p.door_height, 0.001, "lintel starts at door height")
	check_near(segs[2].y1, 2.7, 0.001, "lintel reaches wall top")
	check_near(segs[0].a1, 2.55, 0.001, "left wall ends at door")
	check_near(segs[3].a0, 3.45, 0.001, "right wall starts after door")


func test_window_has_no_lintel_and_custom_width() -> void:
	var p := _plan()
	var wall := {"from": Vector2(0, 0), "to": Vector2(0, 8), "outward": Vector2(-1, 0),
		"openings": [{"type": "window", "at": 2.0}, {"type": "window", "at": 6.0, "width": 0.8}]}
	var segs := HouseBlockout.segments_for_wall(wall, p)
	check_eq(_kinds(segs), ["wall", "window", "wall", "window", "wall"], "windows split walls, no lintel")
	check_near(segs[1].a1 - segs[1].a0, 1.2, 0.001, "default window width")
	check_near(segs[3].a1 - segs[3].a0, 0.8, 0.001, "explicit width honoured")


func test_openings_are_sorted_and_edge_openings_do_not_produce_slivers() -> void:
	var p := _plan()
	var wall := {"from": Vector2(0, 0), "to": Vector2(4, 0),
		"openings": [{"type": "door", "at": 3.55}, {"type": "door", "at": 0.45}]}
	var segs := HouseBlockout.segments_for_wall(wall, p)
	check_eq(_kinds(segs), ["door", "lintel", "wall", "door", "lintel"], "sorted, no zero-length walls at edges")


func test_zero_length_wall_yields_nothing() -> void:
	var p := _plan()
	check_eq(HouseBlockout.segments_for_wall({"from": Vector2(1, 1), "to": Vector2(1, 1)}, p).size(), 0, "degenerate wall ignored")


func test_house_a_counts() -> void:
	var p: BuildingPlan = load("res://data/buildings/house_a.tres")
	check(p != null, "house_a.tres loads")
	var c := HouseBlockout.count_segments(p)
	check_eq(c["door"], 5, "2 exterior + 3 interior doors")
	check_eq(c["lintel"], 5, "one lintel per door")
	check_eq(c["window"], 7, "windows")
	# Walls: S 3, N 4, W 3, E 3, interior z=4: 4, x=4: 1, x=6.5: 1
	check_eq(c["wall"], 19, "solid wall segments")
	check_eq(p.rooms.size(), 4, "four rooms")


func test_validate_reports_problems() -> void:
	var p := _plan()
	p.rooms = []
	p.window_sill_height = 2.3  # above top
	p.walls = [
		{"from": Vector2(0, 0), "to": Vector2(2, 0), "outward": Vector2(0, -1),
			"openings": [{"type": "window", "at": 1.0, "width": 3.0}]},           # wider than wall
		{"from": Vector2(0, 0), "to": Vector2(6, 0),
			"openings": [{"type": "door", "at": 0.2}]},                            # past the start
		{"from": Vector2(0, 0), "to": Vector2(6, 0),
			"openings": [{"type": "door", "at": 3.0}, {"type": "window", "at": 3.5}]},  # overlap
		{"from": Vector2(1, 1), "to": Vector2(1, 1)},                              # zero length
	]
	var problems := p.validate()
	var text := "\n".join(problems)
	check(text.contains("no rooms"), "zero rooms reported")
	check(text.contains("window heights inconsistent"), "window heights reported")
	check(text.contains("wider"), "opening wider than wall reported")
	check(text.contains("past the wall end"), "opening past wall end reported")
	check(text.contains("overlaps"), "overlapping openings reported")
	check(text.contains("zero length"), "zero-length wall reported")
	check_gt(problems.size(), 5.0, "several problems")


func test_house_a_validates_clean() -> void:
	var p: BuildingPlan = load("res://data/buildings/house_a.tres")
	check_eq(p.validate(), [] as Array[String], "house_a has no plan problems")
