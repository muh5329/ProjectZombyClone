class_name WorldConfig
extends Node
## Per-map world settings (node "World" in the map): the world seed that
## all lazily generated content derives from (container loot is seeded by
## LootResolver.seed_for(world_seed, container stable id)) and the world
## age in days since the outbreak (loot thins: LootResolver.age_multiplier).
## Owns the map's WorldState registry. Found through group "world_config";
## everything works with defaults when a map has none (seed 0, day 0).
## Round 7: resets the TimeManager (minute 0, 1×) when the map loads and
## when it is freed.

@export var world_seed: int = 1337
@export var world_age_days: float = 0.0
## Day (since the outbreak) the mains water stops: sinks give nothing
## from then on (Round 7). < 0 = never.
@export var water_shutoff_day: int = 14
## Round 10: where a NEW game puts the player (a Marker3D inside House A)
## and what the survivor starts with (a spare t-shirt: "Tear into rags").
@export var player_start: NodePath = ^"../PlayerStart"
## Round 11: generated worlds — the WorldGenParams resource the layout is
## generated from (with world_seed it fully determines the layout; saved
## so a load regenerates the identical world). "" on hand-made maps.
@export var worldgen_params: String = ""
@export var starter_items: Dictionary = {"tshirt": 1}
## Round 11: share of rolled (not fixed) food kept in containers — the
## generated county has many more kitchens than the test ground, so it
## thins food to ~120-200 items per county (1.0 = tables as authored).
@export var loot_food_multiplier: float = 1.0

var state: WorldState = WorldState.new()
## Round 10: persist_ids of static objects destroyed in this world
## (furniture smashed / taken apart). Saved as an explicit list: only
## these are removed on load — an id merely missing from a save keeps its
## default state.
var destroyed_ids: Dictionary = {}
## Game minute of the last save / load / start of this world (the
## "unsaved progress" confirmation).
var last_saved_minute: float = 0.0
## Round 12: a load of a streamed world hands its chunk store over here
## BEFORE the map enters the tree ({statics, chunks, focus: Vector3,
## population, minutes}): ChunkStreamer builds the chunks around the saved
## player with the saved deltas applied, PopulationDirector restores the
## zombie population, and the clock is set before anything ages.
var stream_state: Dictionary = {}


func mark_destroyed(id: String) -> void:
	if id != "":
		destroyed_ids[id] = true


## Record [node]'s persist_id as destroyed in its world (no-op without one).
static func record_destroyed(node: Node) -> void:
	if node == null or not node.is_inside_tree():
		return
	var cfg := find(node.get_tree())
	if cfg != null:
		cfg.mark_destroyed(String(node.get(&"persist_id")))


func _enter_tree() -> void:
	add_to_group(&"world_config")


## A loaded world starts at its time config's start instant, at 1× (R7).
func _ready() -> void:
	TimeManager.reset()
	if stream_state.has("minutes"):
		TimeManager.from_dict({"minutes": float(stream_state.minutes)})


## Never leave the engine sped up / paused / asleep behind a freed world.
func _exit_tree() -> void:
	TimeManager.reset()


## Pure: is the water still on on [day] (days since the outbreak)?
static func water_on_for(shutoff_day: int, day: float) -> bool:
	return shutoff_day < 0 or day < float(shutoff_day)


static func find(tree: SceneTree) -> WorldConfig:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"world_config") as WorldConfig


## Round 11 (determinism): the seed of [node]'s random stream [tag] —
## WorldGenerator.sub_seed(world seed, "<owner id>/<tag>"), the owner id
## being the nearest ancestor's spawn_id (zombies) or node name (player).
## Components call this instead of randomize(), so a run repeats exactly.
static func rng_seed_for(node: Node, tag: String) -> int:
	var ws := 0
	if node != null and node.is_inside_tree():
		var cfg := find(node.get_tree())
		if cfg != null:
			ws = cfg.world_seed
	var owner_id := ""
	var n := node
	while n != null:
		var sid: Variant = n.get(&"spawn_id")
		if sid is String and String(sid) != "":
			owner_id = String(sid)
			break
		if n is Character:
			owner_id = String(n.name)
			break
		n = n.get_parent()
	if owner_id == "" and node != null:
		owner_id = String(node.name)
	return WorldGenerator.sub_seed(ws, "%s/%s" % [owner_id, tag])


## Round 10: set up a NOT yet added [map] as a new game — the player at
## the PlayerStart marker with the starter kit;
## [world_seed] >= 0 reseeds the world (loot rolls) and the zombie
## spawners (placement, looks).
static func prepare_new_game(map: Node, world_seed: int = -1) -> void:
	var cfg: WorldConfig = null
	for c in map.get_children():
		if c is WorldConfig:
			cfg = c
	if cfg == null:
		return
	if world_seed >= 0:
		cfg.world_seed = world_seed
		_reseed_spawners(map, world_seed)
	var player := map.get_node_or_null("Player") as Node3D
	var start := cfg.get_node_or_null(cfg.player_start) as Node3D if cfg.player_start != NodePath() else null
	if start == null and cfg.player_start != NodePath():
		start = map.get_node_or_null(String(cfg.player_start).trim_prefix("../")) as Node3D
	if player != null and start != null:
		player.position = start.position
	if player != null and not cfg.starter_items.is_empty():
		var items: Dictionary = (player.get(&"starting_items") as Dictionary).duplicate()
		for id in cfg.starter_items:
			items[id] = int(items.get(id, 0)) + int(cfg.starter_items[id])
		player.set(&"starting_items", items)


static func _reseed_spawners(n: Node, s: int) -> void:
	for c in n.get_children():
		if c is ZombieSpawner:
			(c as ZombieSpawner).seed = s
		elif c.get_child_count() > 0:
			_reseed_spawners(c, s)
