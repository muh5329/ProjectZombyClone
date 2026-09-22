class_name HealthComponent
extends Node
## Minimal health for humans (player, survivors). Round 4 adds body parts,
## bleeding and infection on top of this; the take_damage() contract stays.
##
## take_damage(amount, source, info) -> Dictionary
##   info is free-form: {region: &"random"|&"head"|..., type: &"bite"...}.
## Emits local [signal damaged] / [signal died] and the EventBus
## character_damaged / character_died with the owning character.

signal damaged(amount: float, source: Node, info: Dictionary)
signal died(source: Node)
signal changed(value: float, max_value: float)

@export var max_health: float = 100.0
## Damage is ignored while true (cutscenes, god mode, tests).
@export var invulnerable: bool = false

var health: float = 100.0
var dead: bool = false
## Owner character used in EventBus payloads (defaults to the parent).
var character: Node = null


func _ready() -> void:
	if character == null:
		character = get_parent()
	health = max_health


func is_dead() -> bool:
	return dead


func fraction() -> float:
	return 0.0 if max_health <= 0.0 else clampf(health / max_health, 0.0, 1.0)


func set_max(v: float, refill: bool = true) -> void:
	max_health = maxf(v, 0.0)
	health = max_health if refill else minf(health, max_health)
	changed.emit(health, max_health)


func take_damage(amount: float, source: Node = null, info: Dictionary = {}) -> Dictionary:
	if dead:
		return {"ok": false, "reason": "Already dead", "health": 0.0}
	if invulnerable or amount <= 0.0:
		return {"ok": false, "reason": "No effect", "health": health}
	health = maxf(0.0, health - amount)
	damaged.emit(amount, source, info)
	changed.emit(health, max_health)
	EventBus.character_damaged.emit(character, amount, source, info)
	if health <= 0.0:
		dead = true
		died.emit(source)
		EventBus.character_died.emit(character, source)
	return {"ok": true, "health": health, "dead": dead}


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = minf(max_health, health + amount)
	changed.emit(health, max_health)


func revive(full: bool = true) -> void:
	dead = false
	health = max_health if full else maxf(health, 1.0)
	changed.emit(health, max_health)
