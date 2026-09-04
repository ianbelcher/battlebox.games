class_name StormClock
## THE STORM'S TIMETABLE, as a function of the round clock.
##
## The first half of the round there is no storm at all. Over the second
## half the wall comes in from beyond the corners of the map to a
## last-stand arena (HOLD_RADIUS) — and then it STOPS there for a minute.
## That pause is the fight: everybody left is in one place with nowhere
## else to go. It used to hold forever, which sounds the same and is not:
## two teams dug into the ground in a fifteen-block circle never finish
## each other off, the round never ends, and the next person in finds
## "18 still standing" and not one of them in sight.
##
## So after the pause the wall closes the rest of the way, to nothing.
## Everybody still out there burns, the round ends, and the game goes on.
##
## Pure — the clock, the round length and the starting radius in, the
## radius and the seconds until the next change out — so
## tests/unit/storm_test.gd can walk the whole schedule, and so the HUD
## can read the same numbers the server plays by.
##
##   radius  -1  = no storm yet
##   radius   0  = shut: there is no inside any more
##   seconds     = until the wall next changes what it is doing

## Sixty blocks across is a fight, not a cupboard; a minute of it is
## enough to have one; and then the wall goes to nothing so the round ENDS.
const HOLD_RADIUS := 30.0
const HOLD_SECONDS := 60.0
const CLOSE_SECONDS := 30.0

static func at(timer: float, round_seconds: float, start_radius: float) -> Dictionary:
	var half := maxf(round_seconds * 0.5, 1.0)
	if timer > half:
		return {"radius": -1.0, "seconds": timer - half}
	if timer > 0.0:
		var frac := 1.0 - timer / half
		return {"radius": lerpf(start_radius, HOLD_RADIUS, frac), "seconds": timer}
	var over := -timer
	if over < HOLD_SECONDS:
		return {"radius": HOLD_RADIUS, "seconds": HOLD_SECONDS - over}
	var closing := over - HOLD_SECONDS
	var frac_shut := clampf(closing / CLOSE_SECONDS, 0.0, 1.0)
	return {"radius": lerpf(HOLD_RADIUS, 0.0, frac_shut),
		"seconds": maxf(CLOSE_SECONDS - closing, 0.0)}
