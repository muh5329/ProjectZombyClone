class_name ShoutComponent
extends Node
## Deliberate noise (PZ "shout"): child "Shout" of a Character. shout()
## pays profile.shout_stamina_cost (6), emits the SoundManager "shout"
## category (20 m) at the character and refuses while on
## profile.shout_cooldown (3 s), busy, dead (silently) or out of breath.
## Zombies that reach a shout search there 8-12 s (ZombieStateSearch). The player presses
## H (action "shout", PlayerCombatInput). EventBus.shouted reports the
## result for the HUD.

var character: Character
var _last_time: float = -INF


func _ready() -> void:
	character = get_parent() as Character


func cooldown() -> float:
	return character.profile.shout_cooldown if character and character.profile else 3.0


func cost() -> float:
	return character.profile.shout_stamina_cost if character and character.profile else 6.0


func cooldown_left() -> float:
	return maxf(0.0, cooldown() - (SoundManager.now() - _last_time))


## Returns {ok, reason?}.
func shout() -> Dictionary:
	if character == null or character.is_dead():
		return {"ok": false, "reason": "Dead"}  # silent: no notice for the dead
	if cooldown_left() > 0.0:
		return {"ok": false, "reason": "Cooldown"}  # silent: key repeat
	if character.is_busy:
		return _result(false, "Busy")
	if character.stats.get_value(Character.STAMINA) < cost():
		return _result(false, "Too out of breath to shout")
	_last_time = SoundManager.now()
	character.stats.modify(Character.STAMINA, -cost())
	SoundManager.emit_sound(&"shout", character.global_position, character)
	return _result(true, "")


func _result(ok: bool, reason: String) -> Dictionary:
	EventBus.shouted.emit(character, ok, reason)
	return {"ok": ok, "reason": reason} if not ok else {"ok": true}
