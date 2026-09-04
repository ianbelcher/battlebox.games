extends TestCase
## The storm's timetable: nothing, then in, then a minute's stand, then
## shut.
##
## It used to close to a fifteen-block circle and hold there for ever,
## and a round only ended when one team was left — so two teams dug in
## never finished, the round never ended, and the next person in found
## "18 still standing" with nobody in sight. Now the wall pauses at the
## last-stand arena for a minute and then goes to nothing, and everybody
## still out there burns. These walk the schedule.

const ROUND := 300.0   # five minutes
const START := 200.0   # blocks, from beyond the corners

func _radius(timer: float) -> float:
	return float(StormClock.at(timer, ROUND, START).radius)

func _seconds(timer: float) -> float:
	return float(StormClock.at(timer, ROUND, START).seconds)

func test_the_first_half_has_no_storm() -> void:
	equal(_radius(300.0), -1.0, "at the whistle: none")
	equal(_radius(151.0), -1.0, "just before half time: none")
	near(_seconds(300.0), 150.0, 0.01, "and it counts down to the storm starting")

func test_the_second_half_closes_in_to_the_last_stand() -> void:
	near(_radius(150.0), START, 0.01, "half time: the wall is at the corners")
	near(_radius(75.0), (START + StormClock.HOLD_RADIUS) / 2.0, 0.01,
		"three quarters: half way in")
	near(_radius(0.0), StormClock.HOLD_RADIUS, 0.01,
		"the clock runs out as the wall reaches the arena")
	near(_seconds(75.0), 75.0, 0.01, "counting down to the arena")

func test_the_wall_holds_for_a_minute_and_the_clock_says_so() -> void:
	for over in [0.0, 10.0, 59.0]:
		near(_radius(-over), StormClock.HOLD_RADIUS, 0.01,
			"%.0fs into the stand the wall has not moved" % over)
	near(_seconds(-10.0), StormClock.HOLD_SECONDS - 10.0, 0.01,
		"and it counts down the stand")

func test_then_it_shuts_and_stays_shut() -> void:
	var hold := StormClock.HOLD_SECONDS
	var close := StormClock.CLOSE_SECONDS
	near(_radius(-(hold + close / 2.0)), StormClock.HOLD_RADIUS / 2.0, 0.01,
		"half way through the close")
	equal(_radius(-(hold + close)), 0.0, "shut")
	equal(_radius(-(hold + close + 500.0)), 0.0, "and shut it stays")
	equal(_seconds(-(hold + close + 500.0)), 0.0, "with nothing left to count")

func test_a_short_round_follows_the_same_shape() -> void:
	# Three minutes: the storm starts at ninety seconds, not at some
	# fixed mark that a short round never reaches.
	var short := StormClock.at(100.0, 180.0, START)
	equal(float(short.radius), -1.0, "still the first half")
	var late := StormClock.at(45.0, 180.0, START)
	near(float(late.radius), (START + StormClock.HOLD_RADIUS) / 2.0, 0.01,
		"half way in at half of the second half")
