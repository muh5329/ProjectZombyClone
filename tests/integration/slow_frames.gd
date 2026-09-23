extends Node
## Test helper (Round 11): makes every frame slow (artificial load) while
## it is in the tree.

@export var delay_msec: int = 25


func _physics_process(_delta: float) -> void:
	OS.delay_msec(delay_msec)
