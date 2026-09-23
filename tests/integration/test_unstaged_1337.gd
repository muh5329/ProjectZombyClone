extends "res://tests/integration/acceptance_bot.gd"
## The brief's FINAL ACCEPTANCE TEST, unstaged, on world seed 1337
## (see acceptance_bot.gd).


func test_unstaged_acceptance_seed_1337() -> void:
	await play(1337)
