extends TestCase
## The tide's timetable: dry, then rising, then held at its highest for
## good — the water's answer to storm_test.gd.

const ROUND := 300.0    # five minutes
const START := 24.0     # sea level
const SUMMIT := 74.0    # short of the true peak

func _level(timer: float) -> float:
	return float(WaterClock.at(timer, ROUND, START, SUMMIT).level)

func _seconds(timer: float) -> float:
	return float(WaterClock.at(timer, ROUND, START, SUMMIT).seconds)

func test_the_first_half_is_dry() -> void:
	equal(_level(300.0), START, "at the whistle: sea level")
	equal(_level(151.0), START, "just before half time: still dry")
	near(_seconds(300.0), 150.0, 0.01, "and it counts down to the tide starting")

func test_the_second_half_rises_to_the_summit() -> void:
	near(_level(150.0), START, 0.01, "half time: the tide has not moved yet")
	near(_level(75.0), (START + SUMMIT) / 2.0, 0.01, "three quarters: half way up")
	near(_level(0.0), SUMMIT, 0.01, "the clock runs out as the tide tops out")
	near(_seconds(75.0), 75.0, 0.01, "counting down to the top")

func test_once_up_it_never_comes_back_down() -> void:
	for over in [0.0, 10.0, 500.0]:
		equal(_level(-over), SUMMIT, "%.0fs past the whistle: still at the top" % over)
	equal(_seconds(-10.0), 0.0, "with nothing left to count")

func test_a_short_round_follows_the_same_shape() -> void:
	# Three minutes: the tide starts at ninety seconds, not at some fixed
	# mark a short round never reaches.
	var short := WaterClock.at(100.0, 180.0, START, SUMMIT)
	equal(float(short.level), START, "still the first half")
	var late := WaterClock.at(45.0, 180.0, START, SUMMIT)
	near(float(late.level), (START + SUMMIT) / 2.0, 0.01,
		"half way up at half of the second half")
