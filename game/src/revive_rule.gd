class_name ReviveRule
## HOW YOU GET BACK UP — one setting, because it is one question.
##
## It used to be two, sitting in different cards with an unrelated one
## between them: "Can you be picked up?" (yes/no) and "Getting back up"
## (team-mates too / only flying home). Those are not two questions, they
## are three points on the same ladder, and splitting them let a table
## choose the pair that contradict each other.
##
## The ladder, least generous first:
##
##   NONE            one knockout and you are out
##   MATES           a team-mate standing over you gets you up
##   MATES_AND_FLAG  that, or fly home and touch your own flag
##
## The last rung only exists where there IS a flag, so it is offered in
## capture the flag and last flag standing and nowhere else. Asked for in
## battle royale it means the rung below it.
const NONE := 0
const MATES := 1
const MATES_AND_FLAG := 2

## Can a team-mate stand you up?
static func mates_can_lift(mode: int) -> bool:
	return mode >= MATES

## Does touching your own flag bring you back?
##
## `flags` is whether this mode HAS flags. Without them the top rung is
## unreachable rather than wrong, and answering "yes" would leave a
## knocked-out player waiting for a way back that does not exist.
static func flag_brings_you_back(mode: int, flags: bool) -> bool:
	return flags and mode >= MATES_AND_FLAG

## Is a knockout final?
static func out_for_good(mode: int) -> bool:
	return mode <= NONE

## The rungs worth offering, given whether this mode has flags.
static func choices(flags: bool) -> Array:
	return [NONE, MATES, MATES_AND_FLAG] if flags else [NONE, MATES]

static func label(mode: int) -> String:
	match mode:
		NONE:
			return "No reviving"
		MATES:
			return "Team-mates can revive you"
		_:
			return "Your flag and team-mates"
