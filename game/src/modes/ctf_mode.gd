class_name CtfMode
extends GameMode
## CAPTURE THE FLAG: take theirs, keep hold of yours, first to the
## target. THE SCORING LIVES HERE. The platform has the flags — bases,
## poles, carrying, the touch that counts as taking one, tagging back in
## at your own — and tells this file when one is taken; what that is
## worth, when the flag comes back and when the round is won are this
## file's.
##
## Decided on the scoreboard, never by clearing the other side out, so
## winner() never ends it: knocking somebody down only buys you the time
## it takes them to get home.

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

## A point to the taker, a point off the side that lost it, the flag
## away and back later — and the capturer sent home, or one player could
## stand on an enemy flag and take it again every time it reappeared.
func on_flag_taken(world: Node, id: String, team: int, from_team: int) -> bool:
	world.ctf_scores[team] = int(world.ctf_scores.get(team, 0)) + 1
	world.ctf_scores[from_team] = int(world.ctf_scores.get(from_team, 0)) - 1
	world.ctf.send_flag_away(from_team)
	world.cl_fanfare.rpc("%s took %s's flag" % [_name_of(world, id),
		_side(world, from_team)], team)
	print("CTF: %s took team %d's flag (scores %s)" % [id, from_team, world.ctf_scores])
	if int(world.ctf_scores.get(team, 0)) >= int(world.ctf_target):
		world.battle.finish(team)
	return true

func _name_of(world: Node, id: String) -> String:
	return str(world.roster().get(id, {}).get("name", "Somebody"))

func _side(world: Node, team: int) -> String:
	var names: Array = world.team_names
	return str(names[team]) if team >= 0 and team < names.size() else "the other side"
