extends TestCase
## The one ladder that used to be two settings in two cards.

func test_none_is_final() -> void:
	check(ReviveRule.out_for_good(ReviveRule.NONE), "one knockout and out")
	check(not ReviveRule.mates_can_lift(ReviveRule.NONE), "nobody lifts you")
	check(not ReviveRule.flag_brings_you_back(ReviveRule.NONE, true),
		"and the flag does not either — no reviving means all of it")

func test_mates_lift_you() -> void:
	check(ReviveRule.mates_can_lift(ReviveRule.MATES), "a team-mate can")
	check(not ReviveRule.out_for_good(ReviveRule.MATES), "so it is not final")
	check(not ReviveRule.flag_brings_you_back(ReviveRule.MATES, true),
		"but the flag is the rung above")

func test_the_top_rung_has_both() -> void:
	check(ReviveRule.mates_can_lift(ReviveRule.MATES_AND_FLAG), "mates still count")
	check(ReviveRule.flag_brings_you_back(ReviveRule.MATES_AND_FLAG, true),
		"and so does your own flag")

## A mode with no flags cannot offer flying home to one.
func test_no_flags_means_no_flag_route() -> void:
	check(not ReviveRule.flag_brings_you_back(ReviveRule.MATES_AND_FLAG, false),
		"battle royale has no flag to fly to")
	check(ReviveRule.mates_can_lift(ReviveRule.MATES_AND_FLAG),
		"…and it falls back to the rung below rather than to nothing")

func test_the_ladder_only_ever_gets_more_generous() -> void:
	var was_mates := false
	for mode in [ReviveRule.NONE, ReviveRule.MATES, ReviveRule.MATES_AND_FLAG]:
		var mates := ReviveRule.mates_can_lift(mode)
		check(mates or not was_mates, "going up never takes a way back away")
		was_mates = mates

func test_battle_royale_is_offered_two_rungs() -> void:
	equal(ReviveRule.choices(false).size(), 2, "no flag rung without flags")

func test_flag_modes_are_offered_three() -> void:
	equal(ReviveRule.choices(true).size(), 3, "all three where there are flags")

func test_every_rung_has_words() -> void:
	for mode: int in ReviveRule.choices(true):
		check(not ReviveRule.label(mode).is_empty(), "rung %d is named" % mode)
