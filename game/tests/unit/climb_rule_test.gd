extends TestCase
## What walking into something does.
##
## This is the truth table behind "the climb vibrates at the top", which
## has been reported twice and survived one fix. It is worth testing
## because the failure is one MISSING case out of five booleans — not an
## error, not a crash, nothing in a log. The player is simply an inch
## below the lip forever.

func _decide(blocked: bool, pushing: bool, room_up: bool, on_floor: bool,
		climbing := false, in_water := false, downed := false,
		flying := false) -> int:
	return ClimbRule.decide(blocked, pushing, room_up, on_floor, in_water,
		climbing, downed, flying)

# ---- the bug ----------------------------------------------------------

## THE ONE THAT MATTERS. Half way up a wall, the space above finally comes
## clear — which is what reaching the top means — and you are not on the
## floor, because you are climbing. Both arms used to refuse this and the
## player sank back into the wall.
func test_reaching_the_top_of_a_climb_steps_up() -> void:
	equal(_decide(true, true, true, false, true), ClimbRule.STEP_UP,
		"room above while climbing is the top: step onto it")

func test_that_case_is_not_nothing() -> void:
	# Stated separately because NOTHING is precisely what it used to
	# return, and what it returned looked like a physics problem.
	not_equal(_decide(true, true, true, false, true), ClimbRule.NOTHING,
		"doing nothing here is the vibration")

# ---- the ordinary cases ----------------------------------------------

func test_a_kerb_from_standing_is_a_step_up() -> void:
	equal(_decide(true, true, true, true), ClimbRule.STEP_UP,
		"on the floor, room above, walking into it")

func test_swimming_into_a_bank_hops_out() -> void:
	equal(_decide(true, true, true, false, false, true), ClimbRule.STEP_UP,
		"in water counts like being on the floor")

func test_a_tall_wall_is_climbed() -> void:
	equal(_decide(true, true, false, true), ClimbRule.CLIMB,
		"no room above: climb it")

func test_the_second_block_of_a_climb_keeps_climbing() -> void:
	# Gating the climb on on_floor is the OTHER way to get stuck: you
	# would rise exactly one block and stop, which is the hole a child
	# digs and cannot get out of.
	equal(_decide(true, true, false, false, true), ClimbRule.CLIMB,
		"still climbing while off the floor")

func test_clearing_the_wall_is_just_walking() -> void:
	# There was a fourth case here that gave you a hop the moment the wall
	# stopped blocking. It is gone: once nothing is in the way you are
	# walking, and adding a jump to that is how touching a wall came to
	# fling you into the air.
	equal(_decide(false, true, false, false, true), ClimbRule.NOTHING,
		"nothing in the way is nothing to do")

# ---- the cases that must do nothing ----------------------------------

func test_walking_into_a_wall_without_pushing_does_nothing() -> void:
	equal(_decide(true, false, false, true), ClimbRule.NOTHING,
		"let go of the stick and you stop climbing")

func test_nothing_in_the_way_does_nothing() -> void:
	equal(_decide(false, true, false, true), ClimbRule.NOTHING,
		"open ground is not a climb")

func test_you_cannot_climb_while_knocked_out() -> void:
	equal(_decide(true, true, false, true, false, false, true),
		ClimbRule.NOTHING, "downed players do not scale walls")

func test_you_cannot_climb_while_flying() -> void:
	equal(_decide(true, true, false, true, false, false, false, true),
		ClimbRule.NOTHING, "flight has its own controls")

func test_you_do_not_climb_in_water() -> void:
	# Swimming into a cliff face should swim, not climb it.
	equal(_decide(true, true, false, false, false, true), ClimbRule.NOTHING,
		"water is for swimming")

## Every combination returns exactly one of the four, and never crashes.
## Cheap, and it is the check that would catch a future arm being added
## with its conditions overlapping an existing one.
func test_the_table_is_total() -> void:
	for bits in 256:
		var out := ClimbRule.decide(
			bits & 1 != 0, bits & 2 != 0, bits & 4 != 0, bits & 8 != 0,
			bits & 16 != 0, bits & 32 != 0, bits & 64 != 0, bits & 128 != 0)
		check(out >= ClimbRule.NOTHING and out <= ClimbRule.CLIMB,
			"case %d returned %d" % [bits, out])

# ---- and the arithmetic behind it -------------------------------------
#
# The truth table above was RIGHT and the climb still vibrated at the top,
# which is worth stating plainly: the second time this was reported, the
# missing case had already been fixed. What was wrong was the size of the
# move the correct answer made.
#
# `room_up` is measured Player.STEP_UP_PROBE above the feet, so by
# construction reaching the top means the lip is that far up — and a
# top-out that lifts you less than that cannot finish, however right the
# decision was. It lifted a third of it.

func test_a_top_out_actually_clears_the_lip() -> void:
	var lift := Player.CLIMB_TOP_LIFT * Player.CLIMB_TOP_SECONDS
	check(lift >= Player.STEP_UP_PROBE,
		"a mantle of %.2f blocks cannot clear a lip %.2f up"
			% [lift, Player.STEP_UP_PROBE])

func test_and_clears_it_with_something_to_spare() -> void:
	# Exactly enough is not enough: the lift ends and gravity takes over,
	# and the body still has to travel forward over the edge before it
	# sinks back below it.
	var lift := Player.CLIMB_TOP_LIFT * Player.CLIMB_TOP_SECONDS
	check(lift >= Player.STEP_UP_PROBE * 1.25,
		"only %.2f blocks of margin over the %.2f lip"
			% [lift - Player.STEP_UP_PROBE, Player.STEP_UP_PROBE])

func test_why_it_is_a_held_lift_and_not_a_hop() -> void:
	# THE SHAPE OF THE BUG, written down. A ballistic shove of 3.8 — what
	# this used to be — rises v²/2g, and against this file's own gravity
	# that is a third of a block. The player rose an inch, fell back,
	# `room_up` went false on the way down, the climb re-engaged, and the
	# two traded places forever. If anybody replaces the held lift with a
	# hop again, it has to be big enough, and this says how big.
	var old_hop := 3.8
	check((old_hop * old_hop) / (2.0 * Player.GRAVITY) < Player.STEP_UP_PROBE,
		"the hop this replaced should NOT have been able to clear the lip")
	var enough := sqrt(2.0 * Player.GRAVITY * Player.STEP_UP_PROBE)
	check(enough > old_hop,
		"a hop would need at least %.2f, not %.2f" % [enough, old_hop])
