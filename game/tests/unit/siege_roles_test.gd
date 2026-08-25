extends TestCase
## Who goes out, who stays, and what they run at.

# ---- the ratio, which is the thing that broke ------------------------

## A SIDE THAT NEVER ATTACKS CANNOT WIN A MODE DECIDED BY TAKING FLAGS,
## and five of them is a round where nothing happens at all. Measured
## before this rule existed: 17 of 26 players inside fourteen blocks of
## their own flag and no flag taken all round.
func test_somebody_always_goes_out() -> void:
	for size in range(2, 30):
		for siege in [true, false]:
			check(SiegeRoles.attackers(size, siege) >= 1,
				"a team of %d sends somebody (siege=%s)" % [size, siege])

func test_somebody_always_stays_home() -> void:
	for size in range(2, 30):
		check(SiegeRoles.keepers(size, true) >= 1,
			"a team of %d in a siege leaves a guard" % size)

func test_a_siege_defends_harder_than_capture_the_flag() -> void:
	for size in range(6, 25):
		check(SiegeRoles.keepers(size, true) > SiegeRoles.keepers(size, false),
			"a team of %d holds back more when the flag is its round" % size)

func test_neither_job_is_squeezed_out_in_a_siege() -> void:
	for size in range(4, 25):
		check(SiegeRoles.keepers(size, true) * 3 >= size,
			"a team of %d keeps a real guard" % size)
		check(SiegeRoles.attackers(size, true) * 3 >= size,
			"a team of %d sends a real raid" % size)

func test_the_push_sends_more_out_and_never_fewer() -> void:
	for size in range(2, 25):
		check(SiegeRoles.attackers(size, true, true)
				>= SiegeRoles.attackers(size, true, false),
			"the last push never sends FEWER at them (%d)" % size)

# ---- jobs and targets -----------------------------------------------

func test_the_first_seats_defend() -> void:
	equal(SiegeRoles.job(0, 2), SiegeRoles.DEFEND, "seat 0 minds the flag")
	equal(SiegeRoles.job(1, 2), SiegeRoles.DEFEND, "so does seat 1")
	equal(SiegeRoles.job(2, 2), SiegeRoles.ATTACK, "seat 2 goes out")

func test_nobody_home_means_everybody_out() -> void:
	for seat in range(0, 5):
		equal(SiegeRoles.job(seat, 0), SiegeRoles.ATTACK, "no guard posted")

func test_a_seat_that_is_not_on_the_team_attacks_nothing() -> void:
	equal(SiegeRoles.job(-1, 2), SiegeRoles.ATTACK, "-1 is not a keeper seat")

## Dealt round-robin, so a side of four with three enemies puts somebody
## on each rather than all of them on the nearest.
func test_raiders_spread_across_the_standing_flags() -> void:
	var hit := {}
	for seat in range(2, 6):
		hit[SiegeRoles.target(seat, 2, [1, 2, 3])] = true
	equal(hit.keys().size(), 3, "all three enemy flags get somebody")

func test_nothing_standing_is_nothing_to_run_at() -> void:
	equal(SiegeRoles.target(3, 2, []), -1, "every flag already taken")

func test_the_same_seat_always_gets_the_same_flag() -> void:
	# Stability matters: a target that moves every tick is a side that
	# changes its mind at once and never arrives anywhere.
	for _again in 3:
		equal(SiegeRoles.target(4, 2, [1, 2, 3]), SiegeRoles.target(4, 2, [1, 2, 3]),
			"the answer does not wander")
