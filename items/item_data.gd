class_name ItemData
extends Resource
## Static definition of one kind of item (a .tres under data/items/).
## Instances in the world / in hands / in containers are ItemInstance
## objects that point at this data and carry their own condition and
## stack count. Lookup by id: ItemDB.get_item(id) (autoload, items/item_db.gd).
##
## Subclasses add per-category numbers: WeaponData (melee), FoodData
## (food / drink), MedicalData (first aid), ContainerItemData (bags).

enum Category { FOOD, DRINK, MEDICAL, WEAPON, TOOL, MATERIAL, CLOTHING, CONTAINER, MISC }

## StringName ids of Category, in enum order (payloads, UI, loot filters).
const CATEGORY_IDS: Array[StringName] = [
	&"food", &"drink", &"medical", &"weapon", &"tool", &"material",
	&"clothing", &"container", &"misc",
]

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.MISC
## Free-form tags for recipes / tool checks (&"hammer", &"blade", &"canned"…).
## &"internal" marks items that never appear in loot (fists, shove).
@export var tags: Array[StringName] = []
## One or two lines of flavour / usage text (tooltips).
@export_multiline var description: String = ""
## Kilograms per item (encumbrance, Round 6).
@export var weight: float = 1.0
## Items of the same id merge into stacks of up to this many (1 = never).
## Items with a condition never stack.
@export var max_stack: int = 1
## 0 = no condition (never breaks).
@export var max_condition: int = 0
## Blockout colour of the item's mesh in the world / in hand / UI icon.
@export var color: Color = Color(0.7, 0.7, 0.7)
## Size of the blockout box lying on the ground (metres, X = length).
@export var world_size: Vector3 = Vector3(0.4, 0.08, 0.12)
## Item this becomes when filled with water at a sink (empty bottle →
## &"water_bottle"); &"" = cannot be filled (Round 7).
@export var fill_item_id: StringName = &""


func has_condition() -> bool:
	return max_condition > 0


## True when two instances of this item may share a stack.
func is_stackable() -> bool:
	return max_stack > 1 and not has_condition()


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func category_id() -> StringName:
	return CATEGORY_IDS[category] if category >= 0 and category < CATEGORY_IDS.size() else &"misc"


## Category enum value for a StringName id (-1 when unknown).
static func category_from_id(cid: StringName) -> int:
	return CATEGORY_IDS.find(cid)
