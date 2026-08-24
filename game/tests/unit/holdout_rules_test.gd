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

func test_most_of_a_team_stays_home() -> void:
	equal(HoldoutRules.keepers(8), 6, "eight players, six of them defending")
	equal(HoldoutRules.keepers(4), 3, "four players, three defending")

func test_somebody_always_goes_out() -> void:
	# Four forts nobody ever leaves is a draw by boredom.
	for size in range(2, 25):
		check(HoldoutRules.keepers(size) < size,
			"a team of %d must send somebody out" % size)

func test_a_lone_player_defends() -> void:
	equal(HoldoutRules.keepers(1), 1, "on your own, you mind the flag")
	equal(HoldoutRules.keepers(0), 0, "and an empty team has nobody to post")

func test_a_pair_splits_one_and_one() -> void:
	# The one size where "most of them stay home" cannot hold: with two
	# players, one defending and one attacking IS the defensive split.
	equal(HoldoutRules.keepers(2), 1, "one minds the flag, one goes out")

func test_defending_is_the_majority_once_there_is_a_team() -> void:
	for size in range(3, 25):
		check(HoldoutRules.keepers(size) * 2 > size,
			"a team of %d keeps more than half at home" % size)
