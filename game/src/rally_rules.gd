class_name RallyRules
## WHO A KNOCKED-OUT PLAYER WALKS TO.
##
## This is four lines of arithmetic and it lived inline in bot_director,
## where it was written with the team test the wrong way round:
##
##     if other == id or downed.has(other) or not teams_differ(id, other):
##         continue
##
## `not teams_differ` skips your own side, so the search that was supposed
## to find a team-mate to be picked up by walked at the nearest ENEMY —
## and, finding none within twenty blocks, fell through to "head for your
## own flag" almost every time. On the field that reads as a knocked-out
## player running straight past the team-mate trying to revive them, all
## the way home.
##
## That file has four of these polarity tests and they are not all the same
## way round: a keeper hunting a raider genuinely does want `not
## teams_differ`. Reading them side by side is how one ends up inverted.
## So the one that decides who picks you up lives here, where it has no
## world behind it and a test can simply ask it: given an enemy standing
## closer than a team-mate, which do you choose?

## The nearest team-mate who could actually pick this player up. Returns an
## index into `others`, or -1 for "nobody is coming".
##
## Each entry is {team, pos, downed, out}. Somebody on the floor cannot
## lift anyone, and neither can somebody out of the round, so both are
## passed over however close they are.
static func pick_up_at(my_team: int, from: Vector3, others: Array,
		reach: float) -> int:
	var best := -1
	var best_d := reach
	for i in others.size():
		var them: Dictionary = others[i]
		if int(them.get("team", -1)) != my_team:
			continue
		if bool(them.get("downed", false)) or bool(them.get("out", false)):
			continue
		var d: float = from.distance_to(them.get("pos", Vector3.INF))
		if d < best_d:
			best_d = d
			best = i
	return best

## Is this body mine to go and get, or is somebody better placed?
##
## Every able team-mate runs the same search and used to reach the same
## answer, so one knockout pulled a whole side out of the fight to walk to
## a single spot. Picking somebody up is a one-player job: the closest goes
## and the rest get on with the round.
static func mine_to_take(my_distance: float, rival_distances: Array) -> bool:
	for d: Variant in rival_distances:
		if float(d) < my_distance:
			return false
	return true
