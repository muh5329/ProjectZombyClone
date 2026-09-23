class_name FurnitureCatalog
extends Resource
## Blockout furniture types (data/buildings/furniture_catalog.tres):
## types = {type: {size: Vector3 (x width, y height, z depth; front = +Z),
##                 color: Color, container_type: StringName (omit for
##                 plain furniture), capacity: float (kg), name: String,
##                 lid: &"front" | &"top" | &"none" (containers),
##                 detail: &"pillow" | &"backrest" (plain pieces),
##                 spoil_multiplier: float (containers: fridge 0.25, R7),
##                 interaction: &"bed" | &"seat" | &"sink" (plain pieces
##                 that offer Sleep / Rest / Drink, R7),
##                 movable: bool (R9: "Block door"), block_health: float
##                 (R9: hit points while blocking a door, default 200),
##                 disassemble: {item_id: [min, max]} (R9: "Disassemble")}}.
## BuildingPlan.furniture entries reference a type and may override any
## of these per piece.

const KEYS := ["size", "color", "container_type", "capacity", "name", "lid", "detail", "spoil_multiplier", "interaction",
	"movable", "block_health", "disassemble"]

@export var types: Dictionary = {}


func has_type(type: StringName) -> bool:
	return types.has(type) or types.has(String(type))


## Defaults merged with [overrides] (a plan furniture entry).
func resolve(type: StringName, overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = types.get(type, types.get(String(type), {}))
	var out := {
		"size": Vector3(1, 1, 1), "color": Color(0.6, 0.6, 0.6),
		"container_type": null, "capacity": 20.0, "name": "", "lid": &"front",
		"detail": &"", "spoil_multiplier": 1.0, "interaction": &"",
		"movable": false, "block_health": 200.0, "disassemble": {},
	}
	out.merge(base, true)
	for k in KEYS:
		if overrides.has(k):
			out[k] = overrides[k]
	return out
