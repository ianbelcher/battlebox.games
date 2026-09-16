extends TestCase
## What a size MEANS, at every size.
##
## This is worth testing for the reason climb_rule_test.gd is: the ways
## it goes wrong are ARITHMETIC, not exceptions. A body whose step-up no
## longer clears its own collision box does not raise anything — the
## player simply cannot climb a kerb any more, and finds out about it
## halfway up a hill. A hit box that stops agreeing with the body does
## not raise anything either; shots just quietly stop landing.

# ---- a person is still exactly a person --------------------------------

## THE ONE THAT MATTERS MOST. Five games existed before anybody could be
## any size but 1.0, and not one of them may play differently now. Every
## number below is the number that was hard-coded in player.gd before
## this file existed.
func test_a_person_is_unchanged() -> void:
	near(BodySize.half_width(1.0), 0.4, 0.0001, "half a body wide")
	near(BodySize.height(1.0), 1.8, 0.0001, "Minecraft's player height")
	near(BodySize.eye(1.0), 1.62, 0.0001, "Minecraft's eye line")
	near(BodySize.step_up(1.0), 1.05, 0.0001, "the auto-hop probe")
	near(BodySize.climb_lift(1.0), 4.2, 0.0001, "the mantle")
	near(BodySize.jump(1.0), 8.6, 0.0001, "the jump")
	near(BodySize.run(1.0), 5.6, 0.0001, "the run")
	near(BodySize.melee_reach(3.0, 1.0), 3.0, 0.0001, "the sword's reach")
	near(BodySize.edit_reach(10.0, 1.0), 10.0, 0.0001, "how far you can build")

## The hit box was a 1.1-block sphere around a point 0.8 above the feet.
## A box replaces it, and at size 1.0 it reaches exactly as far along
## every axis as that sphere did — so a shot that landed before lands now.
func test_the_hit_box_matches_the_sphere_it_replaced() -> void:
	var feet := Vector3.ZERO
	check(BodySize.hits_body(feet, 1.0, Vector3(1.0, 0.8, 0)), "just inside sideways")
	check(not BodySize.hits_body(feet, 1.0, Vector3(1.2, 0.8, 0)), "just outside sideways")
	check(BodySize.hits_body(feet, 1.0, Vector3(0, -0.2, 0)), "at the ankles")
	check(not BodySize.hits_body(feet, 1.0, Vector3(0, -0.5, 0)), "under the floor")
	check(BodySize.hits_body(feet, 1.0, Vector3(0, 1.8, 0)), "the top of the head")
	check(not BodySize.hits_body(feet, 1.0, Vector3(0, 2.4, 0)), "over the head")

# ---- the invariant that keeps anybody climbing -------------------------

## THE LOAD-BEARING ONE, and the reason step_up is not simply left at
## 1.05 for everybody.
##
## Auto-hop is what stops a four-year-old being trapped in the hole they
## just dug (player.gd says so at length, and CONTRIBUTING.md calls not
## fixing it the definition of a wrong change). A body may only ever be
## stopped by something it cannot step over — so the step has to be at
## least as tall as one block of the world, RELATIVE to the body, at
## every size anybody can be.
func test_every_body_can_step_over_a_block_of_its_own_world() -> void:
	for size: float in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
		var step := BodySize.step_up(size)
		var body := BodySize.height(size)
		check(step >= body * 0.5,
			"at %.2fx a step (%.2f) is worth taking against a body %.2f tall"
				% [size, step, body])

## A CLIMB MUST BE ABLE TO FINISH. The mantle is held for
## Player.CLIMB_TOP_SECONDS, and if what it lifts you by is less than the
## probe that decided you had reached the top, you bounce at the lip
## forever — which is a real bug this game has had, twice. Scaling both
## by the same factor keeps the margin at every size; this says so.
func test_a_mantle_always_clears_the_lip_it_measured() -> void:
	const HELD := 0.34      # Player.CLIMB_TOP_SECONDS
	for size: float in [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
		var rise := BodySize.climb_lift(size) * HELD
		check(rise > BodySize.step_up(size),
			"at %.2fx a mantle rises %.2f against %.2f needed"
				% [size, rise, BodySize.step_up(size)])

# ---- growing and shrinking are both bounded ----------------------------

func test_a_body_is_clamped_to_something_that_can_exist() -> void:
	near(BodySize.clamped(1000.0), BodySize.MAX, 0.0001, "nothing is taller than the world")
	near(BodySize.clamped(0.0), BodySize.MIN, 0.0001, "nothing falls through the floor")
	near(BodySize.clamped(-4.0), BodySize.MIN, 0.0001, "and nothing is inside out")

## The tallest a body may be still has to fit under the sky, or a giant
## could never stand up in the world it is standing in.
func test_the_biggest_body_fits_in_the_world() -> void:
	check(BodySize.height(BodySize.MAX) < 80.0,
		"the world is 80 blocks deep and the tallest body must fit in it")

# ---- reach -------------------------------------------------------------

## A GIANT MUST BE ABLE TO REACH ITS OWN HEAD. Build reach is measured
## from the FEET, so a body 13 blocks tall with a 10-block limit could
## not place a block anywhere it was looking. This is the whole reason
## edit_reach is not left alone.
func test_you_can_always_build_at_your_own_eye_line() -> void:
	for size: float in [1.0, 2.0, 4.0, 8.0, 16.0]:
		check(BodySize.edit_reach(10.0, size) > BodySize.eye(size),
			"at %.2fx you can reach your own eye line" % size)

## …and not across the whole map. Growing in proportion would give an
## eight-times giant eighty blocks of reach, which on the smallest world
## is further than the world is wide.
func test_but_not_across_the_smallest_world() -> void:
	check(BodySize.edit_reach(10.0, 8.0) < 50.0,
		"an 8x giant cannot rebuild the far side of a 50-block map")

# ---- what the two games depend on --------------------------------------

## SIZE AND SPEED ARE SEPARATE, which is the whole reason both Giants and
## Tag can exist. Nothing in here derives one from the other, and this
## test is what fails if somebody decides it would be tidier if it did.
func test_speed_owes_nothing_to_size() -> void:
	near(BodySize.run(1.0), BodySize.run(1.0), 0.0001, "a giant at a person's pace")
	check(BodySize.run(2.0) > BodySize.run(1.0), "and twice as fast is twice as fast")
	# The give-away: run() does not take a size at all. If it ever does,
	# this stops compiling, which is the intended alarm.
	near(BodySize.run(1.0), 5.6, 0.0001, "the run is the run whatever size you are")

## A giant really is a bigger target — that is what pays for its hearts.
func test_a_bigger_body_is_a_bigger_target() -> void:
	var out := Vector3(2.0, 3.0, 0)
	check(not BodySize.hits_body(Vector3.ZERO, 1.0, out), "a person is missed")
	check(BodySize.hits_body(Vector3.ZERO, 4.0, out), "a giant is not")
