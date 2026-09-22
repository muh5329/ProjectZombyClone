class_name Player
extends Character
## The player-controlled survivor. Thin: registers itself and hosts the
## controller/interaction/combat child nodes. Gameplay logic lives in those
## nodes and in the shared Character/components, never here.


func _enter_tree() -> void:
	# _enter_tree (not _ready) so re-parenting / chunk streaming re-registers.
	add_to_group(&"player")
	GameManager.register_player(self)


func _exit_tree() -> void:
	GameManager.unregister_player(self)
