class_name ItemData
extends Resource
## Static definition of one kind of item (a .tres under data/items/).
## Instances in the world / in hands are ItemInstance objects that point at
## this data and carry their own condition and stack count.
## Round 5/6 (containers, inventory) build on this; Round 4 only needs
## weapons.

@export var id: StringName = &""
@export var display_name: String = ""
## Free-form category (&"weapon", &"food", &"medical"…).
@export var category: StringName = &"misc"
## Kilograms (encumbrance, Round 6).
@export var weight: float = 1.0
@export var max_stack: int = 1
## 0 = no condition (never breaks).
@export var max_condition: int = 0
## Blockout colour of the item's mesh in the world / in hand.
@export var color: Color = Color(0.7, 0.7, 0.7)
## Size of the blockout box lying on the ground (metres, X = length).
@export var world_size: Vector3 = Vector3(0.4, 0.08, 0.12)


func has_condition() -> bool:
	return max_condition > 0
