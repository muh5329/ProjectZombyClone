class_name Player
extends Character
## The player-controlled survivor. Thin: registers itself and hosts the
## controller/interaction/combat child nodes. Gameplay logic lives in those
## nodes and in the shared Character/components, never here.
##
## Round 4 stopgap: [held_items] is a flat list of picked-up items and X
## cycles the equipped weapon through fists + held weapons. Round 6
## replaces this with the real inventory / equipment slots.

## Items picked up from the world (ItemInstance). Temporary until Round 6.
var held_items: Array[ItemInstance] = []

@onready var combat: MeleeCombat = get_node_or_null("Combat")


func _enter_tree() -> void:
	# _enter_tree (not _ready) so re-parenting / chunk streaming re-registers.
	add_to_group(&"player")
	GameManager.register_player(self)


func _exit_tree() -> void:
	GameManager.unregister_player(self)


## Pick up [item] (WorldItem calls this). Auto-equips a weapon when the
## hands are empty. Returns {ok, reason?}.
func pick_up_item(item: ItemInstance) -> Dictionary:
	if item == null or item.data == null:
		return {"ok": false, "reason": "Nothing there"}
	if is_dead() or is_busy:
		return {"ok": false, "reason": "Busy"}
	held_items.append(item)
	EventBus.item_picked_up.emit(self, {"id": item.id(), "name": item.display_name()})
	if combat and combat.equipped == null and item.is_weapon():
		combat.equip(item)
	return {"ok": true}


## Held weapons in pick-up order.
func held_weapons() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	for it in held_items:
		if it.is_weapon() and not it.is_broken():
			out.append(it)
	return out


## X: fists → first held weapon → … → fists.
func cycle_weapon() -> bool:
	if combat == null:
		return false
	if combat.is_swinging():
		# No swapping mid-swing (the swing would dodge its own wear).
		EventBus.attack_refused.emit(self, "Mid-swing")
		return false
	var options: Array = [null]
	options.append_array(held_weapons())
	var i := options.find(combat.equipped)
	combat.equip(options[(i + 1) % options.size()])
	return true


## MeleeCombat calls this when the equipped weapon breaks.
func on_weapon_broken(item: ItemInstance) -> void:
	held_items.erase(item)
