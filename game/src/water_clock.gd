class_name WaterClock
## THE RISING TIDE'S TIMETABLE, as a function of the round clock — the
## water's answer to StormClock, for King of the Hill: one mountain, no
## circle to close, so the hazard is a level instead of a radius.
##
## First half of the round, dry: nobody is treading water before they have
## even found their footing on the mountain. Over the second half it
## climbs from sea level to just under the summit, forcing the fight
## upward the same way the storm forces a last stand into HOLD_RADIUS.
## Once the round clock runs out it holds at its highest FOREVER — unlike
## the storm it never needs to finish the job itself, because `end_level`
## is chosen short of the true summit (see KingHillMode), so there is
## always one last scrap of dry ground rather than the water swallowing
## the whole mountain and leaving nothing to fight over.
##
## Pure, like StormClock: the round length and the two levels in, the
## level and seconds until the next change out — so
## tests/unit/water_clock_test.gd can walk the whole schedule without
## booting Godot, and the HUD can read the same numbers the server plays
## by.
##
##   seconds  until the water next changes what it is doing

static func at(timer: float, round_seconds: float, start_level: float,
		end_level: float) -> Dictionary:
	var half := maxf(round_seconds * 0.5, 1.0)
	if timer > half:
		return {"level": start_level, "seconds": timer - half}
	if timer > 0.0:
		var frac := 1.0 - timer / half
		return {"level": lerpf(start_level, end_level, frac), "seconds": timer}
	return {"level": end_level, "seconds": 0.0}
