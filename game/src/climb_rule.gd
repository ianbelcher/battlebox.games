class_name ClimbRule
## WHAT WALKING INTO SOMETHING DOES: step up it, climb it, or nothing.
##
## Pulled out of Player because the bug this exists to prevent is a HOLE
## IN A TRUTH TABLE, and a truth table can be checked. The geometry — what
## counts as blocked, what counts as room to step up — stays in Player,
## where it needs the world. This is only the decision.
##
## The hole, which shipped twice and was reported twice as "the climb just
## vibrates at the top":
##
##   blocked, pushing, room one block up, NOT on the floor, climbing
##
## The step-up wanted `on_floor` and a climb is never on the floor. The
## climb wanted NO room above and there was room, because room above is
## exactly what reaching the top of a wall MEANS. So at the one moment
## the climb succeeded, neither arm ran, gravity took over, you sank, the
## room closed, and the climb re-engaged. Forever.
##
## Nothing about that is visible from a stack trace, a log, or a
## screenshot. It is one missing case in five booleans.

enum { NOTHING, STEP_UP, CLIMB, TOP_OUT }

## `blocked`   something is in the way horizontally
## `pushing`   the stick is being held towards it
## `room_up`   the space one block up is clear (also: you are at the top)
## `on_floor`  standing on something
## `in_water`  swimming
## `climbing`  was climbing on the previous frame
## `downed`    knocked out
## `flying`    in flight
static func decide(blocked: bool, pushing: bool, room_up: bool,
		on_floor: bool, in_water: bool, climbing: bool,
		downed: bool, flying: bool) -> int:
	if blocked and pushing:
		# ROOM ABOVE: step up into it. `climbing` belongs in this list —
		# see the note above; leaving it out is the whole bug.
		if room_up and (on_floor or in_water or climbing):
			return STEP_UP
		# Taller than a step and you are still pushing into it: climb.
		# Deliberately not gated on `on_floor` — the second block of a
		# climb is not on the floor, and stopping there is the hole a
		# child could not dig their way out of.
		if not room_up and not downed and not flying and not in_water:
			return CLIMB
		return NOTHING
	# Nothing in the way any more, and we were climbing a moment ago: the
	# wall has been cleared. Take the last step onto it rather than
	# letting go one block short.
	if climbing and pushing and not downed and not flying:
		return TOP_OUT
	return NOTHING
