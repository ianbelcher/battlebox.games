extends TestCase
## How computer players decide to attack together.
##
## Tested because the behaviour it produces is slow and awkward to watch
## for: "do they come in from different sides" is a question about a whole
## round, and a headless run cannot answer it. The DECISIONS are arithmetic
## and can be checked outright.

func test_attackers_are_dealt_into_squads_of_three() -> void:
	equal(BotSquads.squad_of(0), 0, "the first three are one squad")
	equal(BotSquads.squad_of(2), 0, "…all three of them")
	equal(BotSquads.squad_of(3), 1, "the fourth starts the next")
	equal(BotSquads.squad_count(7), 3, "seven attackers make three squads")
	equal(BotSquads.squad_count(1), 1, "and one attacker is still a squad")
	equal(BotSquads.squad_count(0), 1, "never zero squads — nothing would attack")

func test_one_digger_per_squad_and_no_more() -> void:
	var sappers := 0
	for i in 9:
		if BotSquads.is_sapper(i):
			sappers += 1
	equal(sappers, 3, "nine attackers, three squads, three tunnellers")
	# The point of the rule: never a whole team of them, never none.
	check(not BotSquads.is_sapper(0), "the first of a squad goes overground")

func test_squads_come_from_different_sides() -> void:
	# Three squads should be roughly 120 degrees apart, whatever the spin.
	var a := BotSquads.bearing_of(0, 3, 40.0)
	var b := BotSquads.bearing_of(1, 3, 40.0)
	var apart := fposmod(b - a, TAU)
	near(apart, TAU / 3.0, 0.001, "a third of the compass between squads")

func test_the_lanes_turn_through_the_round() -> void:
	var early := BotSquads.bearing_of(0, 3, 0.0)
	var later := BotSquads.bearing_of(0, 3, BotSquads.LANE_SPIN_SECONDS * 0.5)
	var moved := absf(fposmod(later - early, TAU) - PI)
	check(moved < 0.01,
		"half a spin later, the same squad attacks from the opposite side")

## The heart of it: an approach littered with craters must score worse
## than a clear one, or nothing steers away from the trench.
func test_a_lane_full_of_bodies_costs_more_than_a_clear_one() -> void:
	var flag := Vector3(0, 30, 0)
	# Due east of the flag, in a line running out from it.
	var scars: Array = []
	for i in range(5, 25, 4):
		scars.append(flag + Vector3(float(i), 0, 0))
	var east := BotSquads.lane_cost(flag, 0.0, scars)
	var north := BotSquads.lane_cost(flag, PI * 0.5, scars)
	check(east > north, "the crater lane is the expensive one (%.1f vs %.1f)"
		% [east, north])
	equal(north, 0.0, "and a lane with nothing in it costs nothing")

func test_fighting_off_to_one_side_does_not_close_a_lane() -> void:
	# A busy fight well outside the corridor must not make a clear
	# approach look dangerous — otherwise one skirmish shuts every lane.
	var flag := Vector3(0, 30, 0)
	var far_off: Array = []
	for i in 6:
		far_off.append(flag + Vector3(10.0, 0, 60.0 + float(i)))
	equal(BotSquads.lane_cost(flag, 0.0, far_off), 0.0,
		"out of the corridor is out of the reckoning")

func test_the_chosen_bearing_avoids_the_worst_ground() -> void:
	var flag := Vector3(0, 30, 0)
	var scars: Array = []
	for i in range(4, 24, 3):
		scars.append(flag + Vector3(float(i), 0, 0))
	# Squad 0 at time 0 wants due east, which is exactly the crater lane.
	var base := BotSquads.bearing_of(0, 1, 0.0)
	near(base, 0.0, 0.001, "squad 0 would otherwise walk straight up it")
	var picked := BotSquads.attack_bearing(0, 1, 0.0, flag, scars)
	check(not is_equal_approx(picked, base), "so it does not use that one")
	check(BotSquads.lane_cost(flag, picked, scars)
			< BotSquads.lane_cost(flag, base, scars),
		"and what it picks instead is genuinely quieter")

func test_with_nothing_to_avoid_a_squad_keeps_its_own_lane() -> void:
	var flag := Vector3(0, 30, 0)
	equal(BotSquads.attack_bearing(2, 4, 12.0, flag, []),
		BotSquads.bearing_of(2, 4, 12.0),
		"no craters, no reason to deviate")

func test_a_squad_goes_in_once_enough_of_it_has_turned_up() -> void:
	check(not BotSquads.ready_to_push(1, 3, 0.0), "one of three waits")
	check(BotSquads.ready_to_push(2, 3, 0.0), "two is a group — go")
	check(BotSquads.ready_to_push(1, 1, 0.0), "a squad of one waits for nobody")

func test_nobody_waits_forever() -> void:
	# The failure this guards against is a squad that never attacks
	# because its third member was knocked out on the way to the rally.
	check(BotSquads.ready_to_push(1, 3, BotSquads.GATHER_SECONDS),
		"after the timeout, go in short-handed rather than not at all")

func test_the_rally_is_short_of_the_objective_not_on_it() -> void:
	var flag := Vector3(10, 30, -4)
	var rally := BotSquads.point_on_bearing(flag, 0.9, BotSquads.RALLY_RANGE)
	near(Vector2(rally.x - flag.x, rally.z - flag.z).length(),
		BotSquads.RALLY_RANGE, 0.001, "gathering happens at arm's length")
	equal(rally.y, flag.y, "and on the objective's level, not above it")
