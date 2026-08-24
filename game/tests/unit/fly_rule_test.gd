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

## The four group answers, and the round trip between "which button" and
## "what it means". Written apart these two drift, and the symptom is a
## button that does the right thing and then lights up the wrong one.
func test_every_answer_survives_the_round_trip() -> void:
	for answer: String in FlyRule.ANSWERS:
		equal(FlyRule.answer_for(FlyRule.people_fly(answer),
			FlyRule.computers_fly(answer)), answer,
			"%s means what it says and says what it means" % answer)

func test_every_pair_of_settings_has_an_answer() -> void:
	for people in [true, false]:
		for computers in [true, false]:
			var answer := FlyRule.answer_for(people, computers)
			check(answer in FlyRule.ANSWERS,
				"people=%s computers=%s is one of the four" % [people, computers])
			equal(FlyRule.people_fly(answer), people, "people agree")
			equal(FlyRule.computers_fly(answer), computers, "computers agree")

func test_everyone_and_nobody_are_the_ends_of_it() -> void:
	check(FlyRule.people_fly("everyone") and FlyRule.computers_fly("everyone"),
		"everyone means everyone")
	check(not FlyRule.people_fly("nobody") and not FlyRule.computers_fly("nobody"),
		"nobody means nobody")

func test_the_two_that_need_two_switches() -> void:
	check(FlyRule.computers_fly("computers") and not FlyRule.people_fly("computers"),
		"computers only: the bots, and not the table")
	check(FlyRule.people_fly("humans") and not FlyRule.computers_fly("humans"),
		"humans only: the table, and not the bots")

func test_an_unknown_answer_grounds_everybody() -> void:
	# Safer than the alternative: a typo must not hand the whole room wings.
	check(not FlyRule.people_fly("wibble"), "unknown grounds the people")
	check(not FlyRule.computers_fly("wibble"), "unknown grounds the computers")
