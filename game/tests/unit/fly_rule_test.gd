extends TestCase
## Who keeps their wings.

func test_not_flying_stays_not_flying() -> void:
	check(not FlyRule.keeps_flying(false, true, false, false), "nothing to cancel")

func test_allowed_and_playing_keeps_flying() -> void:
	check(FlyRule.keeps_flying(true, true, false, false), "flight is on for them")

## THE ONE THIS FILE EXISTS FOR. You are knocked out, you fly to a
## team-mate, they pick you up — and in a game with flying switched off
## you go back to walking like everybody else.
func test_revived_in_a_world_without_flying_comes_back_down() -> void:
	check(not FlyRule.keeps_flying(true, false, false, false),
		"picked up, and the wings go with it")

func test_but_keeps_them_while_still_down() -> void:
	check(FlyRule.keeps_flying(true, false, false, true),
		"the knocked-out fly however the setting reads")

func test_a_raid_grounds_you_even_when_allowed() -> void:
	check(not FlyRule.keeps_flying(true, true, true, false),
		"no flying away from a raid")

func test_and_the_knocked_out_still_fly_in_a_raid() -> void:
	check(FlyRule.keeps_flying(true, true, true, true),
		"being out is being out")

## The per-player setting is the whole point: it must decide on its own,
## both ways round, or it is not a per-player setting at all.
func test_the_setting_decides_in_both_directions() -> void:
	check(FlyRule.keeps_flying(true, true, false, false), "granted, so they fly")
	check(not FlyRule.keeps_flying(true, false, false, false), "denied, so they do not")
