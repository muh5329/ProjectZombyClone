class_name WorldGenParams
extends Resource
## Tuning of the procedural starting world (Round 11). Edit
## data/worldgen/default_world.tres, not code. Everything the generator
## decides is derived from (world seed, these params): the same pair
## always gives the same layout, ids and loot. Counts marked "at 768 m"
## scale with the world area (see scaled_count); validate() lists
## problems (the generator clamps and warns).

const MIN_WORLD := 384.0
const MAX_WORLD := 2048.0
const REFERENCE_SIZE := 768.0

@export_group("World")
## World extent (x, z) in metres; the world spans [0, size]. 384..2048.
@export var world_size: Vector2 = Vector2(768, 768)
## Streaming chunk edge (m). world_size / chunk_size must be whole.
@export var chunk_size: float = 64.0
## Zone raster cell (m).
@export var zone_cell: float = 4.0
## Road routing grid cell (m); worlds above 1024 m use 1.5× (A* cost).
@export var route_cell: float = 8.0

@export_group("Zones")
@export var woods_frequency: float = 0.0065
## Noise above this is woods (noise range ~[-1, 1]).
@export var woods_threshold: float = 0.12
@export var field_frequency: float = 0.009
## Noise above this (outside woods) is farmland, below it meadow.
@export var field_threshold: float = 0.05
## A guaranteed woods mass beside the town (forest edge).
@export var town_woods_distance: float = 60.0
@export var town_woods_radius: float = 70.0
@export var pond_count_min: int = 1
@export var pond_count_max: int = 3
@export var pond_radius_min: float = 8.0
@export var pond_radius_max: float = 16.0

@export_group("Roads")
@export var highway_width: float = 8.0
@export var street_width: float = 7.0
@export var sidewalk_width: float = 2.0
@export var county_width: float = 6.5
@export var dirt_width: float = 4.0
@export var driveway_width: float = 3.0
@export var path_width: float = 1.2
## Rural route wiggle: waypoint offset as a fraction of the waypoint
## spacing (road length / straight distance ends up ~1.15-1.35).
@export var road_wiggle: float = 0.85
## Worlds at least this big get a second highway (else a loop road).
@export var second_highway_min_size: float = 1024.0

@export_group("Town")
## Blocks along the main street / block rows across it (random in range).
@export var town_blocks_min: int = 2
@export var town_blocks_max: int = 4
@export var town_rows_min: int = 1
@export var town_rows_max: int = 3
@export var block_length: float = 64.0
## Distance between parallel streets.
@export var block_depth: float = 56.0
@export var lot_depth: float = 22.0
@export var house_lot_width_min: float = 14.0
@export var house_lot_width_max: float = 18.0
@export var shop_lot_width_min: float = 18.0
@export var shop_lot_width_max: float = 24.0
## Straight highway approach beyond each end of the main street (the
## gas station / warehouse lots sit along it), then a bend.
@export var town_approach: float = 64.0
@export var cul_de_sac_max: int = 2
@export var town_lots_min: int = 20
@export var town_lots_max: int = 60

@export_group("Rural")
@export var hamlet_count_min: int = 1
@export var hamlet_count_max: int = 3
@export var hamlet_houses_min: int = 2
@export var hamlet_houses_max: int = 12
## Chance a hamlet is a crossroads village (a side road through it).
@export var hamlet_crossroads_chance: float = 0.4
@export var farmstead_count_min: int = 3
@export var farmstead_count_max: int = 8
## Trees in woods sit on a jittered grid of this spacing (m).
@export var tree_spacing: float = 4.2
## Chance of a lone tree per meadow cell (zone_cell²).
@export var meadow_tree_chance: float = 0.012

@export_group("Population")
## Zombies instantiated around the player start.
@export var active_zombies: int = 40
## Chebyshev chunk radius around the start that is simulated at load.
@export var active_chunk_radius: int = 2
## Zombies kept away from the player start (m).
@export var zombie_min_start_distance: float = 16.0
## Expected zombies per building by settlement kind, and per chunk.
@export var zombies_per_town_building: float = 1.6
@export var zombies_per_hamlet_building: float = 1.0
@export var zombies_per_farm_building: float = 0.5
@export var zombies_per_chunk_base: float = 0.6
## Rural groups (instantiated when their chunk's navmesh is baked).
@export var hamlet_group_min: int = 2
@export var hamlet_group_max: int = 6
@export var farm_group_min: int = 1
@export var farm_group_max: int = 3


## World area relative to the 768 m reference.
func area_scale() -> float:
	return (world_size.x * world_size.y) / (REFERENCE_SIZE * REFERENCE_SIZE)


## A count range given "at 768 m", scaled by area (at least [floor_min]).
func scaled_range(lo: int, hi: int, floor_min: int = 1) -> Vector2i:
	var s := area_scale()
	var a := maxi(floor_min, int(round(lo * s)))
	var b := maxi(a, int(round(hi * s)))
	return Vector2i(a, b)


func effective_route_cell() -> float:
	return route_cell * (1.5 if maxf(world_size.x, world_size.y) > 1024.0 else 1.0)


## Problems with these params ([] = fine).
func validate() -> Array[String]:
	var out: Array[String] = []
	if world_size.x < MIN_WORLD or world_size.y < MIN_WORLD:
		out.append("world_size %s below %d m" % [world_size, int(MIN_WORLD)])
	if world_size.x > MAX_WORLD or world_size.y > MAX_WORLD:
		out.append("world_size %s above %d m" % [world_size, int(MAX_WORLD)])
	if chunk_size <= 0.0 or not is_zero_approx(fmod(world_size.x, chunk_size)) or not is_zero_approx(fmod(world_size.y, chunk_size)):
		out.append("world_size must be a whole number of chunks (%s / %.0f)" % [world_size, chunk_size])
	if zone_cell <= 0.0 or route_cell < 4.0:
		out.append("zone_cell > 0 and route_cell >= 4 required")
	for pair in [["town_blocks", town_blocks_min, town_blocks_max, 1], ["town_rows", town_rows_min, town_rows_max, 1],
			["hamlet_count", hamlet_count_min, hamlet_count_max, 1], ["hamlet_houses", hamlet_houses_min, hamlet_houses_max, 1],
			["farmstead_count", farmstead_count_min, farmstead_count_max, 1], ["town_lots", town_lots_min, town_lots_max, 1],
			["pond_count", pond_count_min, pond_count_max, 0]]:
		if int(pair[1]) < int(pair[3]) or int(pair[1]) > int(pair[2]):
			out.append("%s range %d..%d invalid" % [pair[0], pair[1], pair[2]])
	for w in [highway_width, street_width, county_width, dirt_width, driveway_width, path_width, lot_depth, block_length]:
		if float(w) <= 0.0:
			out.append("widths / lengths must be > 0")
			break
	if block_depth < 2.0 * lot_depth + street_width + 2.0 * sidewalk_width + 1.0:
		out.append("block_depth %.0f too small for two lot rows" % block_depth)
	return out
