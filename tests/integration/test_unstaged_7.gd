extends "res://tests/integration/acceptance_bot.gd"
## The brief's FINAL ACCEPTANCE TEST, unstaged, on world seed 7
## (see acceptance_bot.gd).


func test_unstaged_acceptance_seed_7() -> void:
	await play(7)
