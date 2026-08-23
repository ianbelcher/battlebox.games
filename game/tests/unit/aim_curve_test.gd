extends TestCase
## The shape of the look stick's response.
##
## The brief this has to satisfy, exactly: gentler for small movements,
## and the SAME amount of movement at full stick. Both halves matter — a
## curve that also slows the top just makes the game feel broken instead
## of twitchy, and nobody would be able to turn round.

## What the old single power curve gave, for comparison.
func _old_cubic(t: float) -> float:
	return pow(t, 3.0)

func test_full_stick_is_completely_unchanged() -> void:
	# The whole point. Whipping round to look behind you must cost exactly
	# what it always did.
	equal(InputSlot.look_response(1.0), 1.0, "full stick is full speed")
	equal(_old_cubic(1.0), 1.0, "which is what the old curve gave too")

func test_a_resting_stick_asks_for_nothing() -> void:
	equal(InputSlot.look_response(0.0), 0.0, "no travel, no movement")

func test_every_small_movement_is_gentler_than_it_was() -> void:
	# Sampled across the range a child actually holds the stick at.
	for i in range(1, 20):
		var t := float(i) / 20.0
		var now := InputSlot.look_response(t)
		check(now < _old_cubic(t),
			"at %.2f stick: %.4f should be below the old %.4f"
			% [t, now, _old_cubic(t)])

func test_the_mid_range_is_where_it_had_to_improve() -> void:
	# Half a stick used to ask for an eighth of 223 degrees a second.
	between(InputSlot.look_response(0.5), 0.0, 0.07,
		"half a stick is a fine-aiming speed")
	between(InputSlot.look_response(0.7), 0.0, 0.12,
		"most of the stick stays in the precision zone")

func test_it_only_ever_speeds_up() -> void:
	# A dip anywhere would feel like the stick sticking.
	var previous := -1.0
	for i in range(0, 101):
		var t := float(i) / 100.0
		var value := InputSlot.look_response(t)
		check(value >= previous, "response never falls back (at %.2f)" % t)
		previous = value

func test_there_is_no_step_where_the_two_zones_meet() -> void:
	# A jump at the join would feel like the stick catching.
	var edge := InputSlot.LOOK_PRECISION_EDGE
	near(InputSlot.look_response(edge - 0.001), InputSlot.look_response(edge + 0.001),
		0.01, "the precision zone joins the fast zone smoothly")
	near(InputSlot.look_response(edge), InputSlot.LOOK_PRECISION_SPEED, 0.001,
		"the precision zone tops out where it says it does")

func test_out_of_range_input_is_clamped_not_extrapolated() -> void:
	# A stick pushed to a corner reads past 1.0 on the diagonal.
	equal(InputSlot.look_response(1.4), 1.0, "over-range is still full speed")
	equal(InputSlot.look_response(-0.5), 0.0, "negative travel is nothing")

# ---- fine aim ---------------------------------------------------------

## Holding the right stick in quarters the look. Tested because the number
## is the whole feature: the reported problem was that a deliberate aim at
## range is unmanageable, and the curve cannot help there — at that end of
## the stick you are well into the fast part of it on purpose.
func test_fine_aim_is_a_quarter() -> void:
	equal(InputSlot.PRECISION_SCALE, 0.25,
		"a quarter, as asked for — not a nudge and not a stop")

func test_fine_aim_still_reaches_the_far_end_of_the_stick() -> void:
	# It has to remain USABLE while held, or it is a brake rather than a
	# precision mode: full stick under fine aim should still turn you, at
	# a quarter of the pace.
	var full := InputSlot.look_response(1.0)
	near(full * InputSlot.PRECISION_SCALE, 0.25, 0.0001,
		"full stick held fine is a quarter of full speed, not nothing")

func test_fine_aim_leaves_the_shape_of_the_curve_alone() -> void:
	# A flat scale, so the gentle bottom end stays gentle relative to the
	# top. Scaling the input instead of the output would have moved every
	# point onto a different part of the curve and changed the feel.
	for i in range(1, 10):
		var t := float(i) / 10.0
		var plain := InputSlot.look_response(t)
		near(plain * InputSlot.PRECISION_SCALE / maxf(plain, 0.00001),
			InputSlot.PRECISION_SCALE, 0.0001,
			"the same quarter at %.1f stick" % t)
