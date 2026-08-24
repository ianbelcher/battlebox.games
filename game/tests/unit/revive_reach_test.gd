extends TestCase
## Who is close enough to pick somebody up.
##
## This became a real rule the day being knocked out started lifting you
## ten blocks into the air. A plain radius measured a rescuer standing
## directly underneath as four to ten blocks away, so the pick-up never
## began — reported as "they come to me to be revived and nothing
## happens", and confirmed by a probe: body at y=36.97, rescuer on the
## ground, mates in range: zero.

func _reach(dx: float, dy: float, dz: float) -> bool:
	# Rescuer at the origin, casualty offset from them.
	return ReviveReach.in_reach(Vector3(dx, dy, dz), Vector3.ZERO)

func test_standing_next_to_somebody_on_the_ground() -> void:
	check(_reach(1.5, 0.0, 0.0), "the ordinary case still works")

func test_standing_underneath_somebody_who_is_floating() -> void:
	# THE REPORTED BUG, as a number.
	check(_reach(0.5, 9.9, 0.0),
		"a casualty ten blocks up is still yours to pick up")

func test_the_whole_rise_is_covered_with_room_to_spare() -> void:
	# Arriving while they are still drifting down has to count, or a
	# rescuer has to guess when to be standing there.
	check(ReviveReach.REACH_UP > Player.KNOCKOUT_RISE_BLOCKS,
		"the reach clears the rise (%.1f vs %.1f)"
		% [ReviveReach.REACH_UP, Player.KNOCKOUT_RISE_BLOCKS])

func test_across_the_room_is_still_too_far() -> void:
	check(not _reach(8.0, 0.0, 0.0), "flat distance is still a limit")

func test_it_is_a_column_and_not_a_ball() -> void:
	# The point of the shape: high above counts, far to the side does not,
	# and the two are judged separately.
	check(_reach(0.0, 12.0, 0.0), "directly overhead, high up: yes")
	check(not _reach(5.0, 1.0, 0.0), "just off to the side: no")

func test_falling_past_somebody_is_not_helping_them() -> void:
	check(not _reach(0.0, -9.0, 0.0),
		"a casualty nine blocks BELOW you is not being picked up")

func test_a_step_down_is_allowed() -> void:
	check(_reach(1.0, -2.0, 0.0),
		"standing on a block above them still counts")

func test_the_flat_radius_is_measured_flat() -> void:
	# Diagonally across the ground, just inside and just outside.
	check(_reach(2.0, 4.0, 2.0), "2.83 flat, four up: inside")
	check(not _reach(2.5, 0.0, 2.5), "3.54 flat: outside")
