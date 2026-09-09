class_name BattleMode
extends GameMode
## BATTLE ROYALE: everybody drops, a storm closes in, the last side
## standing wins.

func _init() -> void:
	key = "battle"
	label = "Battle royale"
	note = "Last one standing wins the round"

func has_rounds() -> bool:
	return true

func has_storm() -> bool:
	return true

func has_clock() -> bool:
	return true

func winner(_world: Node, teams_alive: Array) -> int:
	if teams_alive.size() > 1:
		return CONTINUE
	return int(teams_alive[0]) if teams_alive.size() == 1 else -1
