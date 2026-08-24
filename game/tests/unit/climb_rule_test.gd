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
