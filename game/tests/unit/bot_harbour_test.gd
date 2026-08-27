extends TestCase
## The shape of a defended base, and everybody keeping out of everybody
## else's way.
##
## What this replaces was a circle walked at one lap every eighteen
## seconds. "They just march around the flag" is not a bug with a stack
## trace; it is a set of coordinates, and coordinates can be checked.

# ---- the harbour --------------------------------------------------------

func test_the_first_post_faces_the_threat() -> void:
	# The single most important property here, and the one a lone keeper
	# depends on entirely: whoever holds seat zero stands between the flag
	# and wherever the enemy has been seen.
	for bearing in [0.0, 1.1, -2.4, 3.0]:
		var spot := BotHarbour.post(0, 5, bearing, 7.0)
		near(atan2(spot.z, spot.x), bearing, 0.001,
			"seat zero should stand on the threat bearing")

func test_a_lone_keeper_stands_in_the_way() -> void:
	var spot := BotHarbour.post(0, 1, 0.0, 7.0)
	near(spot.x, 7.0, 0.001, "one defender, on the threatened side")
	near(spot.z, 0.0, 0.001, "and squarely on it")

func test_every_side_is_covered() -> void:
	# All-round defence: with four or more defenders no quarter of the
	# compass is left open, or the answer to a wall of bots is simply to
	# walk round the back.
	for count in range(4, 13):
		var quadrants := {}
		for i in count:
			var spot := BotHarbour.post(i, count, 0.7, 7.0)
			quadrants[int(floor((atan2(spot.z, spot.x) + TAU) / (TAU / 4.0))) % 4] = true
		equal(quadrants.size(), 4,
			"a guard of %d left a quarter of the base open" % count)

func test_no_two_defenders_stand_on_each_other() -> void:
	for count in range(2, 17):
		var spots: Array = []
		for i in count:
			spots.append(BotHarbour.post(i, count, 0.0, 7.0))
		for a in spots.size():
			for b in range(a + 1, spots.size()):
				var apart: float = Vector3(spots[a]).distance_to(spots[b])
				check(apart >= BotHarbour.MIN_GAP - 0.01,
					"guard of %d: posts %d and %d are %.2f apart"
						% [count, a, b, apart])

func test_the_position_has_depth() -> void:
	# Not a picket fence. Alternate posts sit further in, so an attacker
	# who gets past the first one is still in front of somebody.
	var out := BotHarbour.post(0, 4, 0.0, 8.0).length()
	var back := BotHarbour.post(1, 4, 0.0, 8.0).length()
	check(back < out - 1.0, "the harbour should be two ranks, not one ring")

func test_a_big_guard_gets_a_bigger_harbour() -> void:
	check(BotHarbour.radius_for(24, 7.0) > 7.0,
		"twenty-four defenders do not fit on a seven-block ring")
	equal(BotHarbour.radius_for(4, 7.0), 7.0,
		"a small guard stands where it was asked to stand")

func test_sentries_look_outwards() -> void:
	# The facing is what turns eight bots standing about into eight
	# sentries, and it must line up with the post they are holding.
	for i in 6:
		var spot := BotHarbour.post(i, 6, 0.4, 7.0)
		near(BotHarbour.facing(i, 6, 0.4), atan2(spot.z, spot.x), 0.001,
			"a defender looks along its own arc")

# ---- the leash ----------------------------------------------------------

func test_a_defender_does_not_chase_off_the_map() -> void:
	var home := Vector3(0, 30, 0)
	var held := BotHarbour.leashed(home, Vector3(90, 30, 0), 12.0)
	near(Vector3(held.x, 0, held.z).length(), 12.0, 0.001,
		"a keeper that chases is a keeper who has left")

func test_something_close_enough_is_gone_after_properly() -> void:
	var home := Vector3(0, 30, 0)
	var at := Vector3(6, 31, 3)
	equal(BotHarbour.leashed(home, at, 12.0), at,
		"inside the leash there is nothing to hold back")

# ---- keeping apart ------------------------------------------------------

func test_nobody_nearby_means_nothing_changes() -> void:
	var want := Vector3(4, 30, 9)
	equal(BotHarbour.keep_apart(want, [], 4.0), want, "alone is already spread out")
	equal(BotHarbour.keep_apart(want, [Vector3(40, 30, 40)], 4.0), want,
		"a team-mate across the field is not in the way")

func test_two_bots_wanting_one_block_end_up_beside_it() -> void:
	var want := Vector3(0, 30, 0)
	var moved := BotHarbour.keep_apart(want, [Vector3(1, 30, 0)], 5.0)
	check(Vector2(moved.x - 1.0, moved.z).length() > 3.0,
		"a bot should shuffle clear of one standing where it wants to be")

func test_the_shove_is_away_from_them() -> void:
	var moved := BotHarbour.keep_apart(Vector3(0, 30, 0), [Vector3(-2, 30, 0)], 5.0)
	check(moved.x > 0.0, "pushed away from the team-mate, not towards it")

func test_separation_never_runs_away() -> void:
	# Twelve bots in a heap must not launch the thirteenth into the next
	# county: the push is a shuffle, not a second goal.
	var crowd: Array = []
	for i in 12:
		crowd.append(Vector3(cos(float(i)) * 0.5, 30, sin(float(i)) * 0.5))
	var moved := BotHarbour.keep_apart(Vector3(0, 30, 0), crowd, 6.0)
	check(Vector2(moved.x, moved.z).length() <= BotHarbour.SPREAD_LIMIT + 0.01,
		"the shove is capped: %s" % str(moved))

func test_exactly_overlapping_bots_still_separate() -> void:
	# Two positions identical to the last bit is a normalise-by-zero, and
	# the answer has to be stable or the pair swap shoves forever.
	var same := Vector3(5, 30, 5)
	var moved := BotHarbour.keep_apart(same, [same], 4.0)
	check(Vector2(moved.x - same.x, moved.z - same.z).length() > 0.5,
		"standing in the same block should still push apart")
	equal(BotHarbour.keep_apart(same, [same], 4.0), moved,
		"and it must give the same answer twice")

func test_height_is_left_to_the_ground() -> void:
	var moved := BotHarbour.keep_apart(Vector3(0, 44, 0), [Vector3(1, 12, 0)], 5.0)
	near(moved.y, 44.0, 0.001, "separation is a standing-room problem")

# ---- bearings -----------------------------------------------------------

func test_a_bearing_points_at_the_threat() -> void:
	var home := Vector3(10, 30, 10)
	near(BotHarbour.bearing(home, Vector3(20, 30, 10), 9.0), 0.0, 0.001,
		"due +x is bearing zero")
	near(BotHarbour.bearing(home, Vector3(10, 30, 20), 9.0), PI / 2.0, 0.001,
		"due +z is a quarter turn")

func test_a_threat_on_top_of_the_flag_keeps_the_old_bearing() -> void:
	var home := Vector3(10, 30, 10)
	near(BotHarbour.bearing(home, home, 1.25), 1.25, 0.001,
		"no direction to take: hold the one we had")
