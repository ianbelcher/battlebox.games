extends TestCase
## What the first screen says about how busy a game is.
##
## The number is there to answer one question — is anybody in there? — and
## it used to answer it wrongly: one child and eighteen computer players
## read as "19 playing", which is exactly what a busy game looks like and
## is the reason somebody would pick that room over another.

func test_people_are_what_playing_means() -> void:
	equal(LobbyScreen._crowd(3, 0), "3 playing", "three people, three playing")

func test_a_room_full_of_bots_is_still_empty() -> void:
	equal(LobbyScreen._crowd(0, 18), "waiting for players + 18 computer players",
		"nobody is in there, however many bots are running about")

func test_one_child_among_a_crowd_of_bots() -> void:
	# The reported case, exactly.
	equal(LobbyScreen._crowd(1, 18), "1 playing + 18 computer players",
		"one person, and the bots said separately")

func test_one_of_each_is_not_pluralised() -> void:
	equal(LobbyScreen._crowd(1, 1), "1 playing + 1 computer player",
		"one computer player, singular")

func test_an_empty_game_says_so() -> void:
	equal(LobbyScreen._crowd(0, 0), "waiting for players",
		"and does not mention bots it has not got")

## The lobby only started sending humans and bots separately when this was
## fixed. A room that predates it reports a total alone, and reading that
## as zero people would show a busy game as empty.
func test_a_room_that_only_reports_a_total_is_read_as_people() -> void:
	equal(LobbyScreen._people_in({"players": 4}), [4, 0],
		"an older room's players are treated as people")
	equal(LobbyScreen._people_in({"players": 19, "humans": 1, "bots": 18}), [1, 18],
		"and a current one is read as it was sent")
	equal(LobbyScreen._people_in({}), [0, 0], "nothing at all is nobody")
