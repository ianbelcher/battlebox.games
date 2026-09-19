extends TestCase
## THE TWO THINGS A GAME OF TAG GETS WRONG SILENTLY: whether the one who
## has just been tipped can tip straight back, and why everybody ends up
## standing in the same place.
##
## Both are invisible to every other check here. Nothing errors when the
## It swaps nine times a second between two players stood together, and
## nothing errors when ninety runners converge into one knot — the round
## runs, the console is clean, and the game is not a game.

# ---- no tagging back ---------------------------------------------------

## TEN BLOCKS, which is the rule as asked for. Written down here because
## it is a gameplay promise and not an implementation detail: shortening
## it quietly is exactly how tag-backs come back.
func test_you_have_to_get_ten_blocks_clear() -> void:
	near(TagRules.SAFE_DISTANCE, 10.0, 0.001, "ten blocks to be safe from")
	var it := Vector3(0, 30, 0)
	check(not TagRules.escaped(Vector3(0, 30, 0), it), "stood on them: not clear")
	check(not TagRules.escaped(Vector3(9.5, 30, 0), it), "nine and a half: not yet")
	check(TagRules.escaped(Vector3(10.0, 30, 0), it), "ten exactly: clear")
	check(TagRules.escaped(Vector3(0, 30, -14.0), it), "fourteen behind: clear")

## MEASURED FLAT. Standing ten blocks above the person who is It — on a
## tower, on their head — is not getting away from them, and It is twice
## the size with a proportional reach, so it is not even out of range.
func test_going_upwards_is_not_getting_away() -> void:
	var it := Vector3(0, 30, 0)
	check(not TagRules.escaped(Vector3(0, 62, 0), it),
		"thirty-two blocks straight up is still nought blocks away")
	check(TagRules.escaped(Vector3(11, 62, 0), it),
		"...but eleven along counts, however high it is")

# ---- the runners do not clump ------------------------------------------

## THE ONE THAT WAS REPORTED. Runners all fleeing the same It in a
## straight line converge, because "directly away" is one answer everybody
## arrives at. The crowd shove is what has to beat that, and the test is
## the honest one: take runners that are on top of each other, and check
## the goals they are given are further apart than they are.
func test_two_runners_in_the_same_spot_are_sent_different_ways() -> void:
	var it := [Vector3(0, 30, -30)]
	var a := Vector3(0.6, 30, 0)
	var b := Vector3(-0.6, 30, 0)
	var goal_a := TagRules.flee_goal(a, it, [b], 200.0)
	var goal_b := TagRules.flee_goal(b, it, [a], 200.0)
	check(goal_a != Vector3.INF and goal_b != Vector3.INF, "both have somewhere to be")
	check(goal_a.distance_to(goal_b) > a.distance_to(b),
		"they are sent further apart than they are standing (%.1f apart, goals %.1f)"
			% [a.distance_to(b), goal_a.distance_to(goal_b)])

## AND THEY STILL RUN AWAY. The shove must not be so strong that a runner
## sidesteps into the arms of the person chasing it — being spread out is
## only worth anything while it is also fleeing.
func test_a_crowded_runner_still_goes_away_from_it() -> void:
	var it_pos := Vector3(0, 30, -20)
	var me := Vector3(0, 30, 0)
	var crowd: Array = [Vector3(3, 30, 0), Vector3(-3, 30, 0), Vector3(0, 30, 3)]
	var goal := TagRules.flee_goal(me, [it_pos], crowd, 200.0)
	check(goal != Vector3.INF, "somewhere to run")
	check(goal.distance_to(it_pos) > me.distance_to(it_pos),
		"the goal is further from It than where it is standing")

## OPEN GROUND, NOTHING CHASING: no opinion, and the caller roams. A flee
## goal invented out of nothing would have the whole field drifting in
## whatever direction the arithmetic happened to favour.
func test_nothing_to_run_from_is_no_answer_at_all() -> void:
	equal(TagRules.flee_goal(Vector3(0, 30, 0), [], [], 200.0), Vector3.INF,
		"an empty field asks nothing of anybody")

## AND THE WALL PUSHES BACK. A runner fleeing in a straight line ends up
## in a corner with nowhere to go, which reads as the bot being too stupid
## to turn. Chased INTO the corner, it has to be sent along the edge or
## back out, never further into it.
func test_a_runner_does_not_flee_into_the_corner() -> void:
	var half := 60.0
	var me := Vector3(52, 30, 52)          # near the far corner already
	var it_pos := Vector3(30, 30, 30)      # chasing from inside
	var goal := TagRules.flee_goal(me, [it_pos], [], half)
	check(goal != Vector3.INF, "somewhere to go")
	check(absf(goal.x) <= half and absf(goal.z) <= half,
		"the goal is inside the world (%.1f, %.1f) in a %.0f-block half"
			% [goal.x, goal.z, half])
	check(goal.distance_to(Vector3(half, 30, half)) > me.distance_to(Vector3(half, 30, half)),
		"and not deeper into the corner than it already is")

# ---- the Its do not travel as a pack -----------------------------------

## THE OTHER HALF, and the half nobody expects: a dozen Its all going for
## the nearest runner, who is very often the same runner. Each It should
## come away with a different one.
func test_two_its_go_after_two_different_runners() -> void:
	var runners: Array = [Vector3(0, 30, 0), Vector3(40, 30, 0)]
	var a := Vector3(-8, 30, 0)
	var b := Vector3(48, 30, 0)
	equal(TagRules.quarry(a, runners, [b]), 0, "the near It takes the near runner")
	equal(TagRules.quarry(b, runners, [a]), 1, "and the far one takes the far runner")

## THE ONE THE PACK RULE MUST NOT DO: leave an It standing about because
## every runner is spoken for. A chase somebody else is also on beats no
## chase at all.
func test_an_it_with_no_runner_of_its_own_still_chases() -> void:
	var runners: Array = [Vector3(0, 30, 0)]
	var mine := Vector3(60, 30, 0)
	var closer := Vector3(2, 30, 0)
	equal(TagRules.quarry(mine, runners, [closer]), 0,
		"the only runner there is, even though somebody else is nearer")

func test_no_runners_means_no_quarry() -> void:
	equal(TagRules.quarry(Vector3.ZERO, [], [Vector3(5, 0, 5)]), -1,
		"nobody left to chase")

## A MARGIN, or two Its the same distance off swap their minds every time
## the picture is rebuilt and neither of them ever arrives.
func test_a_dead_heat_does_not_make_either_of_them_give_up() -> void:
	var runners: Array = [Vector3(0, 30, 0)]
	var a := Vector3(-10, 30, 0)
	var b := Vector3(10, 30, 0)
	equal(TagRules.quarry(a, runners, [b]), 0, "level pegging: still going")
	equal(TagRules.quarry(b, runners, [a]), 0, "...and so is the other one")
