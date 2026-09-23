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

var state: WorldState = WorldState.new()


func _enter_tree() -> void:
	add_to_group(&"world_config")


## A loaded world starts at its time config's start instant, at 1× (R7).
func _ready() -> void:
	TimeManager.reset()


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
