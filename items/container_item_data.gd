class_name ContainerItemData
extends ItemData
## A carryable container (school bag, duffel bag). Every ItemInstance of
## one owns an ItemContainer (`ItemInstance.contents`, [capacity_kg]).
## Worn in the Equipment "back" slot (Round 6), its contents count
## (1 − [weight_reduction]) of their weight toward the carried weight;
## a bag carried in the main inventory or lying on the ground counts in
## full.

## Weight its contents may reach (kg).
@export var capacity_kg: float = 10.0
## Fraction of the contents' weight removed while worn: 0.3 = contents
## count 70 % (30 % less). Encumbrance: contents × (1 − reduction).
@export_range(0.0, 1.0) var weight_reduction: float = 0.0
## Movement speed multiplier while worn (a bulky duffel: 0.97).
@export var worn_speed_multiplier: float = 1.0
