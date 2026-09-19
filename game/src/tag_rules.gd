class_name TagRules
## THE ARITHMETIC OF A GAME OF TAG: when somebody who has just been tagged
## stops being safe, and where a computer player should be running.
##
## Pure — no nodes, no world, no autoloads — for the same reason
## climb_rule.gd, holdout_rules.gd and body_size.gd are. Both of the
## questions in here are the kind that are either exactly right or
## quietly wrong in a way no log will ever show: "can this one be tagged
## yet?" and "why are they all standing in a heap?". A test can ask both
## of these directly, with no round running and nobody in it.
##
## tag_mode.gd decides WHEN to ask. This decides the answer.

# ---- no tagging back ---------------------------------------------------

## HOW FAR YOU HAVE TO GET, in blocks, before the one you just tipped can
## tip you straight back.
##
## Tag with no rule like this is two children touching each other's arm
## nine times a second, which is not a game, and it was the whole of what
## happened when two players met: the tag swapped sides on every swing for
## as long as they stood together, and the "X is It!" line across the
## screen swapped with it.
##
## Ten blocks is the number that was asked for and it is a good one — far
## enough that you have to genuinely break away, near enough that it is
## over in a second or two of running.
const SAFE_DISTANCE := 10.0

## Has this one got clear? Measured flat: being ten blocks UP a tower from
## the person who is It is not getting away from them, it is standing on
## their head.
static func escaped(runner: Vector3, it: Vector3) -> bool:
	return Vector2(runner.x - it.x, runner.z - it.z).length() >= SAFE_DISTANCE

# ---- where a computer player runs --------------------------------------

## HOW FAR OFF A RUNNER NOTICES IT. Generous: It is twice the size on
## purpose, so that you can see across a field who is chasing you, and a
## computer player that only reacted inside twenty blocks would be
## pretending not to have seen something the mode goes out of its way to
## make visible.
const FLEE_SIGHT := 44.0

## How far ahead of itself a fleeing runner aims. Long enough to be a
## committed run rather than a flinch, short enough that it re-decides
## before it has gone somewhere stupid.
const FLEE_STEP := 26.0

## HOW CLOSE IS CROWDING, and how hard the shove is relative to the one
## away from It.
##
## THIS IS THE FIX FOR "THEY JUST CLUMP TOGETHER". Nothing in the platform
## ever told them to spread out: every computer player was running from
## the same chaser, and running directly away from one point is a rule
## that turns a scattered field into a single tight knot within about
## fifteen seconds — everybody is solving the same problem with the same
## answer. From the outside that is a huddle being herded, and it is the
## worst possible way to play tag: It walks into the knot and tags
## somebody every second, and nobody in the knot can get out past the
## others.
##
## So a runner is pushed off its nearest neighbours as well as off It.
## The weight is deliberately a good fraction of the chase: at 0.55 a
## runner being chased still mostly runs away, but two runners side by
## side peel apart as they go instead of racing each other in a line.
const CROWD_RADIUS := 16.0
const CROWD_WEIGHT := 0.55

## KEEP OFF THE WALL. The world is a square slab and the edge is a hard
## stop (WorldNode.world_half), so a runner fleeing in a straight line
## ends up in a corner with nowhere left to go — which looks exactly like
## the bot being too stupid to turn, and is in fact the bot doing as it
## was told. Inside this margin the edge pushes back, harder the closer
## it gets, so a run along the boundary curves away from it.
const EDGE_MARGIN := 18.0
const EDGE_WEIGHT := 1.6

## WHERE A RUNNER SHOULD BE GOING: away from every It that can see it, off
## its own crowd, and off the edge of the world.
##
## `its` and `mates` are plain positions. Returns Vector3.INF when nothing
## is pulling at all — no It in sight, nobody crowding, open ground — and
## the caller is then free to roam, which is what a game of tag looks like
## when the chase is somewhere else.
static func flee_goal(me: Vector3, its: Array, mates: Array,
		half_world: float) -> Vector3:
	var push := Vector3.ZERO
	for it_pos: Vector3 in its:
		push += _shove(me, it_pos, FLEE_SIGHT, 1.0)
	for mate_pos: Vector3 in mates:
		push += _shove(me, mate_pos, CROWD_RADIUS, CROWD_WEIGHT)
	push += _off_the_edge(me, half_world)
	if push.length() < 0.001:
		return Vector3.INF
	var goal := me + push.normalized() * FLEE_STEP
	# Never aim at a spot outside the slab: the walk would be stopped at
	# the wall and the bot would stand there pressed against it, still
	# being told to keep going.
	var keep := maxf(half_world - 4.0, 4.0)
	goal.x = clampf(goal.x, -keep, keep)
	goal.z = clampf(goal.z, -keep, keep)
	return goal

## One repulsion, flat and falling off to nothing at `reach`. Linear
## rather than inverse-square on purpose: inverse-square is all or
## nothing, and what is wanted here is a runner that has already started
## drifting apart from the next one before either of them is in trouble.
static func _shove(me: Vector3, from: Vector3, reach: float,
		weight: float) -> Vector3:
	var away := Vector3(me.x - from.x, 0.0, me.z - from.z)
	var gap := away.length()
	if gap > reach:
		return Vector3.ZERO
	if gap < 0.01:
		# Standing exactly on somebody. Any direction will do, and it has
		# to be SOME direction or two bodies in the same spot stay there.
		var spin := randf() * TAU
		return Vector3(cos(spin), 0.0, sin(spin)) * weight
	return away / gap * ((reach - gap) / reach) * weight

static func _off_the_edge(me: Vector3, half_world: float) -> Vector3:
	var push := Vector3.ZERO
	var room_x := half_world - absf(me.x)
	if room_x < EDGE_MARGIN:
		push.x = -signf(me.x) * ((EDGE_MARGIN - room_x) / EDGE_MARGIN) * EDGE_WEIGHT
	var room_z := half_world - absf(me.z)
	if room_z < EDGE_MARGIN:
		push.z = -signf(me.z) * ((EDGE_MARGIN - room_z) / EDGE_MARGIN) * EDGE_WEIGHT
	return push

# ---- which one It goes after -------------------------------------------

## How much nearer another It has to be before this one gives up a runner
## and looks elsewhere. Without a margin two Its equidistant from the same
## runner swap their minds every time the picture is rebuilt and neither
## of them ever arrives.
const CLAIM_MARGIN := 3.0

## WHICH RUNNER THIS It SHOULD GO AFTER: the nearest one that no other It
## is clearly closer to.
##
## The other half of the clumping, and the half nobody expects. A room of
## a hundred gets a dozen Its (TagMode.PLAYERS_PER_IT), every one of them
## went for the nearest runner, and "the nearest runner" is very often the
## same runner — so the Its travelled as a pack too, twelve of them
## chasing one child while eighty-seven jogged about unbothered. Handing
## a runner to whoever is closest and making the rest look further afield
## turns one pack into a dozen separate chases, which is the game.
##
## Returns an index into `runners`, or -1 if there are none. Falls back to
## the nearest when every runner is spoken for: a chase somebody else is
## also on beats standing still.
static func quarry(me: Vector3, runners: Array, other_its: Array) -> int:
	var pick := -1
	var pick_gap := INF
	var nearest := -1
	var nearest_gap := INF
	for i in runners.size():
		var gap: float = me.distance_to(runners[i])
		if gap < nearest_gap:
			nearest_gap = gap
			nearest = i
		if _spoken_for(runners[i], gap, other_its):
			continue
		if gap < pick_gap:
			pick_gap = gap
			pick = i
	return pick if pick >= 0 else nearest

static func _spoken_for(runner: Vector3, my_gap: float, other_its: Array) -> bool:
	for it_pos: Vector3 in other_its:
		if it_pos.distance_to(runner) < my_gap - CLAIM_MARGIN:
			return true
	return false
