class_name HoldoutMode
extends GameMode
## LAST FLAG STANDING: the same board as capture the flag, one rule
## different — lose your flag and your team is out. Runs on a clock,
## because two sides properly dug in never finish each other off.

func _init() -> void:
	key = "holdout"
	label = "Last flag"
	note = "Lose your flag and your team is out"

func has_rounds() -> bool:
	return true

func has_clock() -> bool:
	return true

func has_flags() -> bool:
	return true

func flag_loss_is_out() -> bool:
	return true

func kicker() -> String:
	return "LAST FLAG STANDING"

func kit(_world: Node, _id: String) -> Array:
	return Weapons.STARTING_KIT_CTF

func round_seconds(world: Node) -> float:
	return world.battle.holdout_seconds()

func on_time_up(world: Node) -> void:
	world.battle.end_holdout()

## Settled by whoever still holds a flag; end_holdout finishes the round
## itself, so from here it is always "keep going".
func winner(world: Node, _teams_alive: Array) -> int:
	world.battle.check_holdout_over()
	return CONTINUE
