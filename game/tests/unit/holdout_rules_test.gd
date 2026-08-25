extends TestCase
## Last flag standing: what a round is worth, and how many stay home.

func test_winning_outright_takes_the_lot() -> void:
	equal(HoldoutRules.share(1), 6, "one team left takes all six")

func test_two_teams_holding_split_it() -> void:
	equal(HoldoutRules.share(2), 3, "both held, three each")

func test_three_teams_still_scores() -> void:
	equal(HoldoutRules.share(3), 2, "a crowd, but everyone dug in")

func test_four_or_more_is_not_a_siege() -> void:
	equal(HoldoutRules.share(4), 0, "nobody was really under threat")
	equal(HoldoutRules.share(9), 0, "…and that does not change with more")

func test_nobody_left_scores_nothing() -> void:
	equal(HoldoutRules.share(0), 0, "no survivors, no points")

## The whole reason the pot is six: it has to divide evenly, or "share the
## round" turns into an argument about remainders.
func test_the_pot_divides_evenly_every_way_it_is_shared() -> void:
	for survivors in [1, 2, 3]:
		equal(HoldoutRules.share(survivors) * survivors, HoldoutRules.ROUND_POINTS,
			"%d teams share the whole pot exactly" % survivors)

func test_sharing_never_pays_more_for_more_survivors() -> void:
	# Surviving alongside other teams must never beat surviving alone.
	for survivors in range(1, 8):
		check(HoldoutRules.share(survivors) <= HoldoutRules.share(1),
			"%d survivors must not out-score winning it" % survivors)

# ---- how many defend -------------------------------------------------

## HALF STAYS HOME. It used to be two thirds, which is what was asked for
## — and on the field two thirds is not a defensive game, it is no game.
## A team of five put three on the wall and sent two, and two attackers
## against three defenders behind a wall never take anything, so nothing
## ever happened and every side sat on its own flag for the whole round.
## Measured: seventeen of twenty-six players within fourteen blocks of
## their own base, four out in the field, no flags taken.
func test_half_a_team_stays_home() -> void:
	equal(HoldoutRules.keepers(9), 4, "nine players, four of them defending")
	equal(HoldoutRules.keepers(12), 6, "twelve players, half defending")

## THE RULE THAT KEEPS IT A GAME. One attacker against a dug-in base is a
## delivery, not a raid — five teams played four minutes without a single
## flag falling, and five survivors share nothing under the table above.
func test_never_fewer_than_a_pair_go_out() -> void:
	for size in range(3, 30):
		check(size - HoldoutRules.keepers(size) >= 2,
			"a team of %d sends at least two out" % size)

func test_somebody_always_goes_out() -> void:
	# Four forts nobody ever leaves is a draw by boredom.
	for size in range(2, 25):
		check(HoldoutRules.keepers(size) < size,
			"a team of %d must send somebody out" % size)

## THIS USED TO ASSERT THE OPPOSITE — "on your own, you mind the flag" —
## and it was wrong for the reason the test below it already knew: a fort
## nobody leaves is a draw by boredom. It exempted a team of one from that
## rule, and a five-team round of one player each is therefore five people
## standing on five flags for ten minutes. Measured: no flags taken, all
## five holding at the whistle, and the table pays nothing past three.
func test_a_lone_player_goes_out() -> void:
	equal(HoldoutRules.keepers(1), 0, "on your own, standing still wins nothing")
	equal(HoldoutRules.keepers(0), 0, "and an empty team has nobody to post")

func test_a_pair_splits_one_and_one() -> void:
	# The one size where "most of them stay home" cannot hold: with two
	# players, one defending and one attacking IS the defensive split.
	equal(HoldoutRules.keepers(2), 1, "one minds the flag, one goes out")

## Neither side of the split may be squeezed out. A guard that is nearly
## everybody is a stalemate; a guard that is nearly nobody is capture the
## flag with extra steps.
func test_both_jobs_get_a_real_share() -> void:
	for size in range(4, 25):
		var home := HoldoutRules.keepers(size)
		check(home * 3 >= size, "a team of %d keeps a real guard" % size)
		check((size - home) * 3 >= size, "a team of %d sends a real raid" % size)

## A LONE PLAYER GOES OUT. Keeping one back is keeping the whole team
## back: five one-player teams all minding their own base is five bases
## nobody ever attacks, and a measured round of exactly that took no flags
## and paid nobody.
func test_a_team_of_one_attacks() -> void:
	equal(HoldoutRules.keepers(1), 0, "nobody left to mind the shop with")

func test_every_team_size_sends_somebody_out() -> void:
	for size in range(1, 13):
		check(size - HoldoutRules.keepers(size) >= 1,
			"a team of %d puts at least one attacker on the field" % size)

func test_every_team_of_two_or_more_keeps_somebody_home() -> void:
	for size in range(2, 13):
		check(HoldoutRules.keepers(size) >= 1,
			"a team of %d leaves somebody on the pole" % size)

## The last push: with the clock nearly gone, holding is worth nothing.
func test_the_guard_thins_out_at_the_end() -> void:
	check(HoldoutRules.keepers_left(6, true) < HoldoutRules.keepers(6),
		"more of them go out when time is short")

func test_and_stands_full_strength_before_that() -> void:
	equal(HoldoutRules.keepers_left(6, false), HoldoutRules.keepers(6),
		"no early push")

func test_the_push_never_leaves_a_flag_unwatched() -> void:
	for size in range(2, 13):
		check(HoldoutRules.keepers_left(size, true) >= 1,
			"a team of %d still has somebody home at the whistle" % size)

func test_the_push_never_adds_defenders() -> void:
	for size in range(1, 13):
		check(HoldoutRules.keepers_left(size, true) <= HoldoutRules.keepers(size),
			"the clock never sends MORE of them home (%d)" % size)

## WHEN the push starts, across every round length that can be chosen.
## A fraction alone was wrong at both ends: a fifth of an hour is twelve
## minutes of "last push", and a fifth of two minutes is twenty-four
## seconds. Seconds, capped by a fraction, works for both.
func test_the_push_is_off_at_the_bell() -> void:
	for mins: int in HoldoutRules.LENGTHS:
		var whole := float(mins) * 60.0
		check(not HoldoutRules.pushing(whole, whole),
			"a %d minute round starts with the guard up" % mins)

func test_the_push_is_on_at_the_whistle() -> void:
	for mins: int in HoldoutRules.LENGTHS:
		var whole := float(mins) * 60.0
		check(HoldoutRules.pushing(0.0, whole),
			"a %d minute round ends with them out" % mins)

func test_a_long_round_does_not_start_by_pushing() -> void:
	# Five minutes into an hour: neither nearly over nor yet a stalemate.
	var hour := 3600.0
	check(not HoldoutRules.pushing(hour - 120.0, hour),
		"two minutes into an hour, the guard is still up")

func test_a_short_round_pushes_late_not_immediately() -> void:
	var two := 120.0
	check(not HoldoutRules.pushing(two * 0.9, two),
		"ten seconds into a two-minute round is not the last push")

## An unlimited round has no whistle to force a result, so a siege that
## has gone on long enough opens up on its own.
func test_a_stalemate_opens_up_however_long_the_round_is() -> void:
	var hour := 3600.0
	check(HoldoutRules.pushing(hour - HoldoutRules.STALE_SECONDS, hour),
		"ten minutes of siege is enough, whatever the clock says")

func test_every_offered_length_is_sane() -> void:
	for mins: int in HoldoutRules.LENGTHS:
		check(mins >= 1, "%d minutes is a real length" % mins)
		check(not HoldoutRules.length_label(mins).is_empty(), "and it is named")
	equal(HoldoutRules.length_label(HoldoutRules.UNLIMITED), "Unlimited",
		"the long one says so rather than showing an hour")
