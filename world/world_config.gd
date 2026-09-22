class_name WorldConfig
extends Node
## Per-map world settings (node "World" in the map): the world seed that
## all lazily generated content derives from (container loot is seeded by
## LootResolver.seed_for(world_seed, container stable id)) and the world
## age in days since the outbreak (loot thins: LootResolver.age_multiplier).
## Owns the map's WorldState registry. Found through group "world_config";
## everything works with defaults when a map has none (seed 0, day 0).

@export var world_seed: int = 1337
@export var world_age_days: float = 0.0

var state: WorldState = WorldState.new()


func _enter_tree() -> void:
	add_to_group(&"world_config")


static func find(tree: SceneTree) -> WorldConfig:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"world_config") as WorldConfig
