class_name BotHarbour
## WHERE EACH DEFENDER STANDS, and how everybody keeps out of everybody
## else's way.
##
## The keepers used to walk a slow circle round their own flag: one lap
## every eighteen seconds, each started at its own angle. It was written
## to fix something real — a fixed post meant a defender arrived and then
## stood perfectly still for the rest of the round, which reads as a
## broken bot — but the cure is its own complaint. A ring of computer
## players orbiting a pole is not a defence, it is a fairground ride, and
## it is what "they just march around the flag, it's kind of dumb" is
## describing.
##
## What a defence actually looks like is a HARBOUR: everybody faces
## outwards, the arcs between them overlap, the ground behind is covered
## by whoever is opposite, and the side the trouble is coming from has the
## most people on it. Nobody moves much, because moving is how you get
## shot, and nobody is standing where somebody else already is.
##
## Three pieces of arithmetic, and no world behind any of them:
##
##   POST      which spot in the harbour this defender holds. Sectors are
##             dealt around the whole compass so nothing is left open, and
##             the whole arrangement is turned so that seat zero always
##             stands between the flag and wherever the enemy has been
##             seen. One defender is therefore always in the right place
##             by construction, and a lone keeper always is.
##
##   FACING    which way to look while nothing is in sight. Outwards,
##             along your own sector. This is what turns eight bots
##             standing about into eight sentries.
##
##   KEEP APART  the general rule, used by attackers too: a goal is pushed
##             off any team-mate too close to it. This is the "understand
##             where they are standing in relation to other players" part,
##             and it is what stops a squad arriving at a flag and
##             occupying one block between them.
##
## Pure and static so the invariants can be checked directly: every
## sector is covered, seat zero faces the threat, no two posts land on top
## of each other, and separation never runs away.

## How far apart two defenders should be. Close enough that their arcs
## overlap and one can cover the other, far enough that one explosion is
## not two knockouts.
const MIN_GAP := 3.0

## The inner ring's share of the harbour's radius. Alternate posts are
## pulled in, which gives the position DEPTH — somebody at the wall and
## somebody behind them — instead of a picket fence everyone can see over
## at once. It is also what keeps neighbours apart when a big team fields
## a lot of defenders.
const INNER_RING := 0.62

## HOW BIG THE HARBOUR HAS TO BE to hold this many people at MIN_GAP.
##
## Sized for the WORST pair, which is two neighbours that both landed on
## the outer ring: the chord between two posts one sector apart at radius
## r is 2·r·sin(π/count), and that has to be at least MIN_GAP.
##
## Sizing it for alternate posts instead — on the reasoning that the rings
## alternate, so same-ring neighbours are two sectors apart — is wrong at
## every ODD count, because the ring pattern does not survive the wrap:
## with fifteen defenders, seat 0 and seat 14 are both on the outer ring
## AND adjacent, and they stood 2.91 blocks apart. One sector is the
## safe assumption and it costs nothing at the sizes that matter.
##
## Below the requested radius this does nothing: a small guard stands
## where it was asked to stand.
const GAP_MARGIN := 1.02

static func radius_for(count: int, wanted: float) -> float:
	if count <= 1:
		return wanted
	return maxf(wanted, MIN_GAP * GAP_MARGIN / (2.0 * sin(PI / float(count))))

## THE SPOT THIS DEFENDER HOLDS, as an offset from the flag.
##
## `threat_bearing` is where the enemy has been seen from, as an angle
## about the flag. Seat zero stands on it, and the rest are dealt evenly
## round the compass from there — so the front is always manned and the
## back is never empty. That ordering matters more than it looks: seats
## are stable for the round, so as the guard grows or shrinks the people
## already in place keep roughly the position they had.
static func post(index: int, count: int, threat_bearing: float,
		wanted: float) -> Vector3:
	var many := maxi(1, count)
	var out := radius_for(many, wanted)
	var angle := threat_bearing + TAU * float(index) / float(many)
	var ring := out if index % 2 == 0 else out * INNER_RING
	return Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)

## WHICH WAY TO LOOK from that post while there is nothing to shoot at:
## outwards, down the middle of your own arc. Sentries, not statues facing
## a pole.
##
## Wrapped into the same half-open turn `atan2` gives back, so a facing and
## a bearing can be compared without one of them being a whole turn out.
static func facing(index: int, count: int, threat_bearing: float) -> float:
	return wrapf(threat_bearing + TAU * float(index) / float(maxi(1, count)),
		-PI, PI)

## The most a bot will be shoved off the spot it actually wanted. Bigger
## than this and separation stops being "shuffle over" and starts being a
## second, worse, goal of its own.
const SPREAD_LIMIT := 6.0

## PUSH A GOAL OFF ANYBODY ALREADY STANDING NEAR IT.
##
## `mates` are the positions of team-mates worth minding — the caller
## decides which, because it is the one that knows who is nearby. Every
## one closer to the goal than `gap` contributes a shove directly away
## from itself, in proportion to how close it is, and the total is capped.
##
## Two team-mates who want the same block therefore end up beside it
## rather than inside each other, and a squad arriving at a flag spreads
## around the mound. Height is left alone: this is about standing room,
## and the ground decides how high the ground is.
static func keep_apart(want: Vector3, mates: Array, gap: float) -> Vector3:
	if mates.is_empty() or gap <= 0.0:
		return want
	var push := Vector3.ZERO
	for mate_v: Variant in mates:
		var mate: Vector3 = mate_v
		var away := Vector3(want.x - mate.x, 0.0, want.z - mate.z)
		var apart := away.length()
		if apart >= gap:
			continue
		if apart < 0.001:
			# Standing in exactly the same place. Any direction will do,
			# and it has to be a STABLE one or two bots swap shoves
			# forever — so it comes off the numbers themselves.
			away = Vector3(sin(mate.x + mate.z), 0.0, cos(mate.x - mate.z))
			apart = 0.001
		push += away.normalized() * (gap - apart)
	if push.length() > SPREAD_LIMIT:
		push = push.normalized() * SPREAD_LIMIT
	return want + push

## HOW FAR A DEFENDER MAY CHASE.
##
## A keeper that walks at whatever it can see is a keeper who has left,
## and the flag behind it is then unguarded by somebody who is technically
## still a defender. So an engagement is a MOVE WITHIN the position: go
## towards them, but never further from the flag than this.
##
## Returns the point to actually walk to.
static func leashed(home: Vector3, towards: Vector3, leash: float) -> Vector3:
	var out := Vector3(towards.x - home.x, 0.0, towards.z - home.z)
	var far := out.length()
	if far <= leash or far < 0.001:
		return towards
	var held := home + out.normalized() * leash
	held.y = towards.y
	return held

## THE BEARING OF A THREAT about a point, or `fallback` when there is not
## one. Plain arithmetic, here rather than at three call sites, because
## getting the argument order of `atan2` wrong is silent and turns the
## whole harbour to face the wrong way.
static func bearing(home: Vector3, threat: Vector3, fallback: float) -> float:
	var out := Vector3(threat.x - home.x, 0.0, threat.z - home.z)
	if out.length() < 0.001:
		return fallback
	return atan2(out.z, out.x)
