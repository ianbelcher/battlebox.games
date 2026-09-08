extends TestCase
## Which game the Play button picks. See quick_play.gd.

func _room(code: String, humans: int, players: int, age := 0, house := false) -> Dictionary:
	return {"code": code, "name": code.capitalize(), "humans": humans,
		"players": players, "age": age, "house": house,
		"settings": {"mode": "battle", "map": "classic", "size": 400}}

func test_nothing_listed_means_nothing_chosen() -> void:
	equal(QuickPlay.choose([], "house"), {}, "an empty list picks nothing")
	equal(QuickPlay.choose([{"name": "no code"}, 7], "house"), {},
		"entries without a code are not games")

func test_the_game_with_people_in_it_wins() -> void:
	var rooms := [_room("house", 0, 100, 0, true), _room("brave-otter", 2, 10),
		_room("calm-fox", 1, 50)]
	equal(str(QuickPlay.choose(rooms, "house").code), "brave-otter",
		"two people beat one person and beat a hundred computer players")

func test_the_always_open_game_breaks_a_tie() -> void:
	var rooms := [_room("brave-otter", 0, 10, 5), _room("house", 0, 4, 900, true)]
	equal(str(QuickPlay.choose(rooms, "house").code), "house",
		"nobody anywhere: the game that never closes")
	var by_code := [_room("brave-otter", 0, 10, 5), _room("house", 0, 4, 900)]
	equal(str(QuickPlay.choose(by_code, "house").code), "house",
		"...recognised by its code when the listing does not flag it")

func test_then_the_fuller_and_then_the_newer_game() -> void:
	var rooms := [_room("old-dog", 0, 10, 600), _room("new-cat", 0, 10, 5),
		_room("big-fish", 0, 30, 300)]
	equal(str(QuickPlay.choose(rooms, "house").code), "big-fish",
		"thirty seats of computer players beat ten")
	var same := [_room("old-dog", 0, 10, 600), _room("new-cat", 0, 10, 5)]
	equal(str(QuickPlay.choose(same, "house").code), "new-cat",
		"and on a dead heat the newer game")

func test_the_line_under_the_button_says_where_you_are_going() -> void:
	equal(QuickPlay.describe(_room("house", 3, 100, 0, true)),
		"House · Battle royale · Island · 400 across · 3 playing",
		"name, what it is, who is there")
	has(QuickPlay.describe(_room("brave-otter", 0, 10)), "waiting for you",
		"an empty game says so without saying zero")
	has(QuickPlay.describe(_room("calm-fox", 1, 10)), "1 playing", "one person")
	equal(QuickPlay.describe({"code": "x", "name": "Bare"}), "Bare · waiting for you",
		"a room that reported no settings gets its name and nothing invented")
