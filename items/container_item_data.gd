class_name ContainerItemData
extends ItemData
## A carryable container (backpack, duffel bag). Worn / nested in Round 6.

## Weight it can hold (kg).
@export var capacity: float = 10.0
## Fraction of the contents' weight removed while worn (0.6 = 60 % lighter).
@export_range(0.0, 1.0) var weight_reduction: float = 0.0
