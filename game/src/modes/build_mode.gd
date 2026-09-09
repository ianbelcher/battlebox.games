class_name BuildMode
extends GameMode
## JUST BUILDING: the platform with no game on it. The default, and what
## a room made by anything other than the front page gets.

func _init() -> void:
	key = "creative"
	label = "Just building"
	note = "No rounds, nobody gets knocked out"
