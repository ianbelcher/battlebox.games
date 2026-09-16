class_name HeartRow
## THE ROW OF HEARTS OVER A HEAD, and in the corner of your own screen:
## how many of the eight are lit, given what somebody has and what they
## have it out of.
##
## Pure, and in a file of its own, for the reason the rest of the pure
## files in this project exist: it lived on Player, which cannot be loaded
## by a `--script` test run because it names the Game autoload — so the one
## piece of arithmetic in the whole hearts display that is worth checking
## could not be reached by a test at all. It was wrong for a giant for a
## while and nothing said so.
##
## EIGHT CELLS, WHATEVER THE BAR. A mode may hand somebody far more hearts
## than there are cells — Giants gives a giant four times the usual — and
## the answer is the same row draining more slowly rather than a wall of
## tiny hearts, or a full bar until the moment of death. Nothing on screen
## says "x4": a child does not need telling that their hearts are going
## down slower than they used to, they can see it.
const CELLS := 8

## CEILING, NOT ROUNDING: any hearts left at all show at least one, so
## nobody is ever drawn as dead while they are still standing. And zero
## shows zero, so a body that IS down does not keep a heart over it.
static func lit(hp: int, top: int) -> int:
	if top <= 0:
		return 0
	hp = clampi(hp, 0, top)
	if top <= CELLS:
		return hp
	return int(ceilf(float(hp) * float(CELLS) / float(top)))
