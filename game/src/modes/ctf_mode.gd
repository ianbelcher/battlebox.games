class_name CtfMode
extends GameMode
## CAPTURE THE FLAG: take theirs, keep hold of yours, first to the target.
## Decided on the scoreboard (CtfDirector.capture calls finish), never by
## clearing the other side out — so winner() never ends it.

func _init() -> void:
	key = "ctf"
	label = "Capture the flag"
	note = "Take theirs, keep hold of yours"

func has_rounds() -> bool:
	return true

func has_flags() -> bool:
	return true

func has_target() -> bool:
	return true

func kit(_world: Node, _id: String) -> Array:
	return Weapons.STARTING_KIT_CTF
