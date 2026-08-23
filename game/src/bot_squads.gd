class_name BotSquads
## HOW COMPUTER PLAYERS ATTACK TOGETHER.
##
## They used to run at the flag in a straight line, one at a time, from
## wherever they happened to be. Everything about that is bad to play
## against: they arrive one by one and are dealt with one by one, they all
## follow the same ground, and that ground very quickly becomes a trench
## of craters from the last four who tried it — so the fifth walks into a
## canyon and gets stuck in it.
##
## Three ideas, all of them things a person would do:
##
##   GO IN GROUPS.  Attackers are dealt into squads. A squad gathers at a
##                  rally point short of the objective and goes in
##                  together, so a defender faces three at once instead of
##                  three in a row.
##
##   COME FROM DIFFERENT SIDES.  Each squad is given its own bearing on
##                  the objective, spread around the compass, and the
##                  whole arrangement turns slowly through the round. Two
##                  waves never take the same line twice.
##
##   AVOID WHERE EVERYONE DIED.  Bearings are scored against where people
##                  have actually been knocked out recently, and the worst
##                  ones are not used. That is what stops the whole team
##                  filing into the same crater field.
##
## EVERYTHING HERE IS STATIC AND PURE — no world, no roster, no autoloads.
## That is not tidiness: `--script` runs have no autoloads at all, so the
## only way any of this can be tested is for it to depend on nothing. What
## is left in bot_director.gd is the part that genuinely needs the world.

## How many attackers make a squad. Three is enough to overwhelm one
## defender and few enough that a team of ten still fields three groups
## coming from three directions.
const SQUAD_SIZE := 3

## How far short of the objective a squad gathers before going in.
const RALLY_RANGE := 26.0

## Close enough to the rally to count as having arrived.
const GATHER_RADIUS := 9.0

## Nobody waits longer than this for the rest of the squad. Whatever has
## happened to them, standing about is worse — this is the difference
## between a group that attacks late and a group that never attacks.
const GATHER_SECONDS := 9.0

## A full turn of the whole arrangement, in seconds. Slow: the point is
## that a later wave takes a different line, not that anybody is walking
## in circles.
const LANE_SPIN_SECONDS := 150.0

## How wide a corridor counts as "this lane" when scoring where the
## fighting has been.
const LANE_WIDTH := 16.0

## How close to the objective stops counting as being in a lane at all.
## See lane_cost — without this every lane is charged for the same
## doorstep and none of them can be told apart.
const LANE_DOORSTEP := 5.0

## Which squad the nth attacker on a team belongs to.
static func squad_of(index: int) -> int:
	return index / SQUAD_SIZE

## How many squads a team of this many attackers fields. At least one, so
## a lone attacker is a squad of one rather than no squad at all.
static func squad_count(attackers: int) -> int:
	return maxi(1, int(ceil(float(attackers) / float(SQUAD_SIZE))))

## ONE MEMBER OF EACH SQUAD DIGS. The sapper goes under rather than over —
## see BotDirector for what it does with this — and it is deliberately one
## per squad rather than a dice roll per bot: a whole team of tunnellers
## is not an attack, and none at all is the game as it was.
static func is_sapper(index: int) -> bool:
	return index % SQUAD_SIZE == SQUAD_SIZE - 1

## The direction a squad comes in from, as an angle around the objective.
##
## Squads are spread evenly around the whole compass and the arrangement
## turns with the clock, so the fifth wave of the round is not walking
## into the ruins of the first.
static func bearing_of(squad: int, squads: int, seconds: float) -> float:
	var share := TAU / float(maxi(1, squads))
	var spin := TAU * (seconds / LANE_SPIN_SECONDS)
	return float(squad) * share + spin

## A point on the ground `range_out` blocks from `target`, along `bearing`.
static func point_on_bearing(target: Vector3, bearing: float,
		range_out: float) -> Vector3:
	return target + Vector3(cos(bearing), 0.0, sin(bearing)) * range_out

## HOW BAD A LANE IS, judged by how much of the recent fighting sits in
## it. `scars` are places people have actually been knocked out.
##
## Measured along the corridor rather than at a point: what makes a lane
## unusable is a run of craters between here and the objective, not one
## unlucky spot. Anything outside the corridor's width counts for nothing,
## so a busy fight off to one side does not close a lane that is clear.
##
## The last few blocks are NOT counted, and that is load-bearing rather
## than a detail. Anything lying right beside the objective is inside
## every lane's final approach, so counting it charges the same amount to
## all of them and the whole comparison stops discriminating — which is
## exactly what the test caught. What is being scored is the WALK IN, and
## every squad has to cross the doorstep whichever way it comes.
static func lane_cost(target: Vector3, bearing: float, scars: Array) -> float:
	var along := Vector3(cos(bearing), 0.0, sin(bearing))
	var cost := 0.0
	for scar_v: Variant in scars:
		var scar: Vector3 = scar_v
		var to_scar := Vector3(scar.x - target.x, 0.0, scar.z - target.z)
		var distance_out := to_scar.dot(along)
		# On the doorstep, behind the objective, or further out than a
		# squad ever walks in from: not this lane's problem.
		if distance_out < LANE_DOORSTEP or distance_out > RALLY_RANGE * 1.5:
			continue
		var sideways := (to_scar - along * distance_out).length()
		if sideways > LANE_WIDTH:
			continue
		# Dead centre of the corridor counts for a full point, the edge of
		# it for half: a crater you would walk straight into is worse than
		# one you would pass.
		cost += 1.0 - (sideways / LANE_WIDTH) * 0.5
	return cost

## The bearing this squad should use: its own by default, nudged off it if
## that lane is where everybody has been dying.
##
## It tries a handful of offsets rather than searching properly. A squad
## picking the mathematically quietest approach every time would be its
## own kind of predictable, and this runs for every attacker on a timer.
static func attack_bearing(squad: int, squads: int, seconds: float,
		target: Vector3, scars: Array) -> float:
	var base := bearing_of(squad, squads, seconds)
	if scars.is_empty():
		return base
	var best := base
	var best_cost := lane_cost(target, base, scars)
	for step in [0.6, -0.6, 1.2, -1.2]:
		var candidate := base + float(step)
		var cost := lane_cost(target, candidate, scars)
		if cost < best_cost:
			best_cost = cost
			best = candidate
	return best

## Has this squad gathered? Either enough of it is at the rally, or it has
## waited long enough that going in short-handed beats not going in.
static func ready_to_push(at_rally: int, squad_size: int,
		waited: float) -> bool:
	if waited >= GATHER_SECONDS:
		return true
	# A squad of one has nobody to wait for. Two is a group; three is the
	# whole squad and rarely all present at once, because somebody is
	# always being shot at on the way.
	return at_rally >= mini(2, maxi(1, squad_size))
