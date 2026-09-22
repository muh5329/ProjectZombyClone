class_name FoodData
extends ItemData
## Food and drink. The numbers are consumed by the needs system (Round 7);
## Round 5 only ships them as data.

## Energy in kcal for eating the whole item.
@export var calories: float = 0.0
## Hunger removed (0..100 scale of the needs system, Round 7).
@export var hunger: float = 0.0
## Thirst removed (negative = makes you thirsty, e.g. salty chips).
@export var thirst: float = 0.0
## Days until the item goes stale / rotten (0 = never spoils).
@export var spoil_days: float = 0.0
## True when it needs a tin opener (or a knife, badly) to eat.
@export var needs_opener: bool = false
