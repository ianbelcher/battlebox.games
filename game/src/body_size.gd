class_name BodySize
## HOW BIG A PLAYER IS, and everything that follows from it.
##
## A player used to be exactly one size, and the three numbers saying so
## were constants in player.gd. They are here now because SEVEN separate
## systems have to agree about what "twice as big" means — the collision
## sweep, the camera, what a shot hits, how far you can reach, the avatar,
## the tags over a head, and the computer players — and seven
## multiplications in seven files is seven chances for one of them to be
## missed. The one that gets missed is always the same one: hit
## detection, and the bug is "I shot the giant and nothing happened".
##
## Nothing here touches a node, an autoload or a world, so
## tests/unit/body_size_test.gd can ask it anything without a game
## running. That is the same reason climb_rule.gd and holdout_rules.gd
## exist and is worth keeping to.
##
## WHO SETS IT: a mode, through `world.bodies.set_size(id, size)`. The
## platform has no opinion about when anybody grows — Giants doubles you
## for a knockout, Tag makes whoever is "it" twice the size, and a mode
## that never calls it has players who are all exactly 1.0 forever, which
## is every game that existed before this file.

## A PERSON IS 1.0. Everything here is a multiple of that, and it is a
## FLOAT on purpose: doubling is Giants' idea, not the platform's, and a
## mode that wants 1.4x or a size that eases smoothly between two values
## must not have to fight the engine for it.
const PERSON := 1.0

## The range `world.bodies.set_size` clamps to. Not a game balance
## number — a sanity bound. Below the minimum the body is thinner than
## the blocks it walks on and falls through the ground; above the maximum
## it is taller than the world is deep (80 blocks) and can never stand up
## in it. A mode's own cap belongs in the mode.
const MIN := 0.25
const MAX := 16.0

# ---- the numbers a body of size 1.0 is made of -------------------------
#
# These moved here from player.gd and are still reached through it
# (Player.HALF_WIDTH and friends alias them) so nothing that read them
# there had to change.

const BASE_HALF_WIDTH := 0.4
const BASE_HEIGHT := 1.8        ## Minecraft's exact player height
## Eye level for first person — near the top of the head, so blocks read
## about waist height like they should.
const BASE_EYE := 1.62          ## Minecraft's exact eye line
## How far above the feet "room above" is tested, and therefore how far a
## top-out has to lift you. See the long note in player.gd: the probe
## decides when a climb has reached the top and the mantle has to clear
## what the probe measured, so these two scale TOGETHER or the arithmetic
## that stops a climb oscillating at the lip stops holding.
const BASE_STEP_UP := 1.05
const BASE_CLIMB_LIFT := 4.2
const BASE_JUMP := 8.6
const BASE_RUN := 5.6
const BASE_SWIM := 3.6

# ---- the body ----------------------------------------------------------

static func clamped(size: float) -> float:
	return clampf(size, MIN, MAX)

static func half_width(size: float) -> float:
	return BASE_HALF_WIDTH * size

static func height(size: float) -> float:
	return BASE_HEIGHT * size

static func eye(size: float) -> float:
	return BASE_EYE * size

# ---- getting about -----------------------------------------------------

## A STEP UP SCALES WITH THE BODY, and this is the load-bearing one.
##
## Auto-hop exists because a four-year-old who digs straight down cannot
## otherwise get out of the hole they have just made, and the only way
## back is an adult (player.gd says so, and CONTRIBUTING.md calls that
## the definition of a wrong change). A player shrunk to half size on an
## unscaled 1.05-block step is exactly that child: every block in the
## world is suddenly a wall.
##
## The other end reads as the whole point of being huge — a giant walks
## over the fort rather than around it.
static func step_up(size: float) -> float:
	return BASE_STEP_UP * size

## Held for CLIMB_TOP_SECONDS, and must carry the body past step_up(size)
## or a climb cannot finish. Scaling both by the same factor keeps the
## margin that tests/unit/climb_rule_test.gd pins, at every size.
static func climb_lift(size: float) -> float:
	return BASE_CLIMB_LIFT * size

## A GIANT JUMPS HIGHER, BUT NOT IN PROPORTION — the square root, not the
## size. Linear would have an 8x giant leaping 107 blocks, out of a world
## that is only 80 deep; unscaled would have it unable to hop a kerb that
## comes up to its ankle. Square root puts an 8x jump at just under three
## times a person's, which looks like weight rather than either kind of
## silliness.
static func jump(size: float) -> float:
	return BASE_JUMP * sqrt(size)

## Running speed is NOT derived from size, and that is deliberate enough
## to be worth a function that says so.
##
## Size and speed are separate knobs because the two games that use them
## want opposite things: a giant keeps a person's pace (at 8x that reads
## as lumbering, which is the point of being a giant), and whoever is
## "it" in Tag is twice the size AND twice the speed. Had speed been
## derived from size, Tag could only exist as an `if mode == "tag"` in
## the platform — the exact thing the modes were split out to stop.
static func run(scale: float) -> float:
	return BASE_RUN * scale

static func swim(scale: float) -> float:
	return BASE_SWIM * scale

# ---- reach -------------------------------------------------------------

## A giant's arm is a giant's arm: melee reach is simply proportional.
## Being swatted from four blocks away by something four times your size
## is the correct and legible outcome.
static func melee_reach(base: float, size: float) -> float:
	return base * size

## HOW FAR YOU CAN PUT A BLOCK, and it grows by exactly how much TALLER
## you are rather than in proportion.
##
## It has to grow at all: the reach is measured from the feet, so an 8x
## giant whose own eye line is 13 blocks up could not reach the height of
## its own head with a 10-block limit — it would be unable to place a
## block anywhere it was looking. Growing it in PROPORTION instead (80
## blocks at 8x) would let a giant rebuild the far side of a 50-block map
## without walking there. "As far as you could reach before, plus however
## much taller you now are" is the rule that gives a giant its own body
## back and nothing else.
static func edit_reach(base: float, size: float) -> float:
	return base + BASE_HEIGHT * maxf(size - PERSON, 0.0)

# ---- what a shot hits --------------------------------------------------

## HOW GENEROUS THE HIT BOX IS, beyond the body itself. Kept as a flat
## margin rather than a proportion so that it is aim help for a small
## target and vanishes into the noise for a big one, which is the right
## way round: a giant does not need helping.
const AIM_MARGIN := 0.7
const AIM_MARGIN_UP := 0.1
const AIM_MARGIN_DOWN := 0.3

## IS THIS POINT ON THIS BODY? A box, not a ball.
##
## The old test was a 1.1-block sphere around a point 0.8 above the feet,
## which fits a person well enough because a person is nearly as wide as
## the slack in it. It fits a giant terribly: at 8x the same shape is
## either a sphere far too small to cover a 14-block body or, scaled up,
## one that swallows shots passing three blocks wide of it.
##
## At size 1.0 this box has exactly the reach the sphere had along each
## axis — 1.1 out sideways, 0.3 below the feet, 1.9 above them — so no
## game that existed before sizes shoots any differently than it did.
static func hits_body(feet: Vector3, size: float, point: Vector3) -> bool:
	var reach := half_width(size) + AIM_MARGIN
	if absf(point.x - feet.x) > reach or absf(point.z - feet.z) > reach:
		return false
	return point.y >= feet.y - AIM_MARGIN_DOWN \
		and point.y <= feet.y + height(size) + AIM_MARGIN_UP

## HOW FAR A POINT IS FROM THIS BODY, measured to the body itself rather
## than to the spot on the ground it is standing on.
##
## THIS IS THE ONE THAT GETS MISSED, exactly as the note at the top of
## this file says it always is. A blast asks "is anybody within five
## blocks of where this went off" and answers it with the distance to
## each player's POSITION — and a position on the wire is the FEET. On a
## person that is the same question, because a person is under two blocks
## tall. On an eight-times giant it is a different question with a
## different answer: the body is 14.4 blocks tall, so a rocket dead-centre
## in its chest is nine blocks from its feet and a headshot is fourteen,
## and every one of them was thrown away as a miss. "I emptied the medium
## shooter into a giant's head and its hearts did not move" is this line
## and nothing else.
##
## Zero when the point is inside the body. Same box hits_body uses, minus
## the aim help: this is the real body, not the generosity around it.
static func distance_to_body(feet: Vector3, size: float, point: Vector3) -> float:
	var reach := half_width(size)
	var dx := maxf(absf(point.x - feet.x) - reach, 0.0)
	var dz := maxf(absf(point.z - feet.z) - reach, 0.0)
	var dy := maxf(maxf(feet.y - point.y, point.y - (feet.y + height(size))), 0.0)
	return sqrt(dx * dx + dy * dy + dz * dz)

## The server's sanity bound on a hit a client reports: how far from the
## body the claimed impact may be before the server calls it nonsense.
## Grows with the body for the same reason edit_reach does — the position
## on the wire is the FEET, and a shot to a giant's head is legitimately
## a dozen blocks from them.
static func hit_tolerance(base: float, size: float) -> float:
	return base + BASE_HEIGHT * maxf(size - PERSON, 0.0)

# ---- the picture -------------------------------------------------------

## Where a name or a row of hearts floats, given a body. Over the head
## and clear of it, not at the fixed 2.05 blocks that would leave a
## giant's name buried in its own chest.
static func tag_height(size: float) -> float:
	return height(size) + 0.3 * size

## How far back a camera has to sit to keep the whole body in frame.
## Linear: a body twice as tall needs twice the distance to look the
## same size on screen.
static func camera_pull(size: float) -> float:
	return size
