extends TestCase
## WHAT A NEW GAME CAN BE, checked on the client's side of the fence.
##
## GameSetup is the table three things read: the front page draws it, the
## lobby validates a copy of it in Python, and world.gd applies the result
## at boot. The tests below check this copy; lobby/test_lobby.py checks
## the other one. They are deliberately separate — if the two ever
## disagree the symptom is a setting that was chosen and quietly ignored,
## which nobody reports because it just looks like the button did nothing.

func test_the_default_game_is_one_you_could_actually_play() -> void:
	var settings := GameSetup.defaults()
	# Every default has to be a value that exists in its own table, or the
	# screen opens with nothing highlighted in half its rows.
	equal(GameSetup.clean(settings), settings,
		"the defaults survive their own validator unchanged")

## Two different questions, and conflating them is what this guards.
## defaults() is the FALLBACK a missing field takes — including for a bare
## POST to the lobby, which has always produced a world to build in.
## opening_choice() is what the New game screen opens on, and somebody who
## just pressed New game wants a game.
func test_the_screen_opens_on_a_game_and_the_fallback_stays_neutral() -> void:
	equal(GameSetup.defaults()["mode"], "creative",
		"an unconfigured room is still somewhere to build")
	equal(GameSetup.opening_choice()["mode"], "battle",
		"but pressing New game offers a game")
	equal(GameSetup.clean(GameSetup.opening_choice()),
		GameSetup.opening_choice(), "and what it opens on is itself valid")

func test_a_whole_game_survives_intact() -> void:
	var asked := {"mode": "ctf", "map": "castles", "size": 400, "minutes": 10,
		"players": 10, "target": 5, "teams": 8, "fly": "humans",
		"revive": ReviveRule.MATES, "drop": true}
	equal(GameSetup.clean(asked), asked, "nothing chosen is thrown away")

func test_a_mode_nobody_has_written_falls_back() -> void:
	equal(GameSetup.clean({"mode": "zombies"})["mode"], GameSetup.DEFAULT_MODE,
		"an unknown mode is the default mode, not an empty world")

func test_a_size_off_the_list_is_refused_rather_than_clamped() -> void:
	# 137 is not a small world. It is a number nothing on the screen can
	# produce, so a clamp would silently build the nearest thing to it.
	equal(GameSetup.clean({"size": 137})["size"], GameSetup.DEFAULT_SIZE,
		"a size nothing offers is the default size")
	equal(GameSetup.clean({"size": 800})["size"], 800, "and a real one is kept")

func test_the_revive_ladder_clamps_because_it_is_a_ladder() -> void:
	equal(GameSetup.clean({"revive": 99})["revive"], ReviveRule.MATES_AND_FLAG,
		"above the top rung is the top rung")
	equal(GameSetup.clean({"revive": -3})["revive"], ReviveRule.NONE,
		"below the bottom rung is the bottom rung")

## EVERY CLOCKED MODE OFFERS THE SAME LENGTHS. It used to be 3/5/8 for
## battle royale and 2/5/10 for last flag standing, which on screen is a
## row whose buttons move and grey out as you change your mind about the
## mode — and there was never a reason either mode could give for it.
func test_a_round_length_means_the_same_thing_in_every_mode() -> void:
	for mode: String in ["battle", "holdout"]:
		equal(GameSetup.lengths_for(mode), GameSetup.ROUND_LENGTHS,
			"%s offers the one list" % mode)
		equal(GameSetup.clean({"mode": mode, "minutes": 10})["minutes"], 10,
			"ten minutes is a round of %s" % mode)
	equal(GameSetup.clean({"minutes": 8})["minutes"], GameSetup.DEFAULT_MINUTES,
		"and a length nothing offers is the default")

## Teams are a property of the game, chosen with everything else, and
## applied before a single computer player is spawned — they are spread
## across whatever teams exist at the moment they are made.
## WHO CAN FLY is a condition of the game like any other. It was a world
## setting reachable from inside a running game — and worse, with a
## per-player override on top of it, so the answer could be changed under
## somebody mid-round in two different places.
func test_flying_is_decided_before_the_game_starts() -> void:
	equal(GameSetup.defaults()["fly"], "nobody",
		"a game where everybody can fly from the start is a game nobody "
		+ "walks anywhere in")
	equal(GameSetup.clean({"fly": "humans"})["fly"], "humans", "and it is kept")
	equal(GameSetup.clean({"fly": "wings"})["fly"], "nobody",
		"an answer FlyRule does not have is not an answer")
	for answer: String in GameSetup.FLY_ANSWERS:
		equal(GameSetup.clean({"fly": answer})["fly"], answer,
			"%s is one of FlyRule's own four" % answer)

func test_a_world_is_said_as_the_square_it_is() -> void:
	equal(GameSetup.size_label(400), "400 × 400",
		"which is the world, written down")

func test_teams_are_part_of_the_game() -> void:
	equal(GameSetup.clean({"teams": 8})["teams"], 8, "eight sides")
	equal(GameSetup.clean({"teams": 10})["teams"], 10, "up to ten")
	equal(GameSetup.clean({"teams": 11})["teams"], GameSetup.DEFAULT_TEAMS,
		"eleven is not on the list")
	equal(GameSetup.clean({"teams": 1})["teams"], GameSetup.SOLO,
		"one is solo: everyone for themselves")
	equal(GameSetup.clean({"teams": 0})["teams"], GameSetup.DEFAULT_TEAMS,
		"and no sides at all is not a thing")
	equal(GameSetup.teams_label(GameSetup.SOLO), "Solo", "said as what it is")

## SOLO IS TEAMS OF ONE. Not "no teams": every seat is its own side, so
## everything that thinks in sides keeps working, and the only limit is
## how many colours there are for people to each have one.
func test_solo_is_a_side_each() -> void:
	equal(GameSetup.seats_for(10, GameSetup.SOLO), 10, "ten players, ten sides")
	equal(GameSetup.seats_for(100, GameSetup.SOLO), GameSetup.SOLO_MAX_PLAYERS,
		"a full house is as many as have a colour")
	equal(GameSetup.players_label(10, GameSetup.SOLO),
		"10 players  ·  everyone for themselves", "and the label says so")
	equal(GameSetup.seats_note(10, GameSetup.SOLO),
		"10 players, everyone for themselves. Computer players fill the seats people are not in.",
		"the line under the row too")
	has(GameSetup.seats_note(100, GameSetup.SOLO), "24 is as many",
		"and says why a hundred became twenty-four")
	check(GameSetup.uses("teams", "battle"), "a battle has sides")
	check(not GameSetup.uses("teams", "creative"),
		"nobody is on a side in creative")

func test_every_mode_offers_lengths_it_can_actually_run() -> void:
	for spec: Dictionary in GameSetup.MODES:
		var mode := str(spec["key"])
		var lengths: Array = GameSetup.lengths_for(mode)
		check(not lengths.is_empty(), "%s offers no round length at all" % mode)
		check(GameSetup.UNLIMITED in lengths,
			"%s cannot be played without a clock" % mode)

## Which questions each mode is asked. Showing a setting a mode does not
## have is offering an answer to a question it never asks — capture the
## flag's target used to show in last flag standing, where there is no
## target and taking a flag knocks a team out instead.
func test_a_mode_is_only_asked_what_it_has() -> void:
	check(not GameSetup.uses("minutes", "creative"),
		"nothing is timed in creative")
	check(not GameSetup.uses("revive", "creative"),
		"nobody is knocked out in creative, so nobody is revived")
	check(not GameSetup.uses("target", "holdout"),
		"last flag standing has no score to reach")
	check(GameSetup.uses("target", "ctf"), "capture the flag does")
	check(GameSetup.uses("minutes", "battle"), "battle royale runs on a clock")
	check(GameSetup.uses("map", "creative"), "every mode is played somewhere")

func test_the_flag_rung_is_offered_only_where_there_are_flags() -> void:
	check(GameSetup.has_flags("ctf") and GameSetup.has_flags("holdout"),
		"both flag modes have flags")
	check(not GameSetup.has_flags("battle") and not GameSetup.has_flags("creative"),
		"and the other two do not")

## The line the front page writes under a game's name. It is the whole
## reason the settings travel back out of the lobby: a list of room names
## answers none of the questions somebody choosing between two is asking.
func test_a_game_says_what_it_is() -> void:
	equal(GameSetup.summary({"mode": "ctf", "map": "castles", "size": 200}),
		"Capture the flag · Castles · 200 across", "mode, world, size")

func test_a_room_that_said_nothing_is_not_described() -> void:
	# An older room reports no settings. Inventing a description for it
	# would put "Just building · Island" under a game that is neither.
	equal(GameSetup.summary({}), "", "nothing said, nothing written")
	equal(GameSetup.summary({"map": "sky"}), "",
		"a map with no mode is not a game")

func test_nobody_is_zero_players() -> void:
	# "0 players" reads as something that failed to load.
	equal(GameSetup.players_label(0), "Just us", "none of them")
	equal(GameSetup.players_label(0, 5), "Just us", "however many sides")
	equal(GameSetup.players_label(20), "20 players", "with no sides to split over")
	equal(GameSetup.players_label(20, 5), "20 players  ·  4 a side",
		"the row says what the two rows add up to")

## A HUNDRED OVER NINE TEAMS IS NINETY-NINE. The seats are dealt evenly
## across the sides, so "how many players" and "how many teams" together
## say exactly what the game will be — eleven a side — rather than a
## number that one team gets one more of.
func test_seats_are_dealt_evenly_across_the_sides() -> void:
	equal(GameSetup.seats_for(100, 9), 99, "eleven a side, one seat unused")
	equal(GameSetup.seats_for(100, 5), 100, "twenty a side")
	equal(GameSetup.seats_for(10, 3), 9, "three a side")
	equal(GameSetup.seats_for(4, 8), 8,
		"never fewer than one a side, or some teams are nobody")
	equal(GameSetup.seats_for(0, 5), 0, "just us stays just us")
	equal(GameSetup.seats_for(20, 0), 20, "no sides: every seat is a seat")
	equal(GameSetup.players_label(100, 9), "99 players  ·  11 a side",
		"and the label says the dealt number, not the one on the button")
	equal(GameSetup.seats_note(100, 9),
		"99 players over 9 teams: 11 a side. Computer players fill the seats people are not in.",
		"the line under the row does the arithmetic")
	equal(GameSetup.seats_note(0, 9), "Nobody but the people who join.", "just us")
	equal(GameSetup.clean({"players": 20})["players"], 20, "twenty is a choice")
	equal(GameSetup.clean({"players": 7})["players"], GameSetup.DEFAULT_PLAYERS,
		"seven is not")
	equal(GameSetup.clean({"bots": 40})["players"], GameSetup.DEFAULT_PLAYERS,
		"the old bot count is not read: a bot count is not a size")

func test_an_hour_is_how_this_game_spells_unlimited() -> void:
	equal(GameSetup.length_label(GameSetup.UNLIMITED), "No clock",
		"the longest round is described rather than counted")
	equal(GameSetup.length_label(5), "5 min", "and a real one is counted")

## WHAT THE FRONT PAGE ACTUALLY PUTS ON THE WIRE.
##
## The settings leave the client as JSON (see LobbyClient.create_room), so
## every value in the table has to be a type JSON has. A value that does
## not serialise does not fail loudly — Godot writes something else, or
## nothing, and the room quietly boots as the default. This is the check
## that the dictionary survives the round trip it is going to make.
func test_the_settings_survive_being_sent() -> void:
	var wanted := GameSetup.clean({"mode": "holdout", "map": "sky",
		"size": 800, "minutes": 2, "players": 20, "target": 10,
		"revive": ReviveRule.NONE, "drop": true})
	var wire: Variant = JSON.parse_string(JSON.stringify(wanted))
	check(wire is Dictionary, "the settings come back as an object")
	# Through JSON every number is a float, which is exactly the kind of
	# difference that turns 800 into a size nothing matches. clean() is
	# what puts them back, and it runs again on the far side.
	equal(GameSetup.clean(wire as Dictionary), wanted,
		"and mean the same thing at the other end")

## Every table on this screen is drawn as a row of buttons, and a row of
## buttons with a duplicate in it is a row where two of them do the same
## thing and one of them can never be un-highlighted.
func test_no_table_repeats_itself() -> void:
	for spec: Array in [[GameSetup.SIZES, "value"], [GameSetup.MODES, "key"],
			[GameSetup.MAPS, "key"]]:
		var seen: Dictionary = {}
		for row: Dictionary in (spec[0] as Array):
			var key: Variant = row[str(spec[1])]
			check(not seen.has(key), "%s appears twice" % str(key))
			seen[key] = true

## The maps offered here have to be maps the world generator can build.
## A key that is not in WorldGen.THEMES is a button that starts a room
## which then falls back to the default theme, silently.
func test_every_map_offered_is_a_map_that_exists() -> void:
	for spec: Dictionary in GameSetup.MAPS:
		check(str(spec["key"]) in WorldGen.THEMES,
			"%s is not a theme WorldGen can generate" % str(spec["key"]))

## And every mode offered has to be one sv_set_mode accepts, or picking it
## on the front page starts a room that ignores it.
func test_every_mode_offered_is_a_mode_the_server_knows() -> void:
	const SERVER_KNOWS := ["creative", "battle", "ctf", "holdout"]
	for spec: Dictionary in GameSetup.MODES:
		check(str(spec["key"]) in SERVER_KNOWS,
			"%s is not a mode the server will accept" % str(spec["key"]))

## Every mode tile carries a line saying what the mode is. A tile with a
## name and no explanation is four words a child has to already know.
func test_every_mode_explains_itself() -> void:
	for spec: Dictionary in GameSetup.MODES:
		check(not str(spec["note"]).strip_edges().is_empty(),
			"%s has no description on its tile" % str(spec["key"]))
